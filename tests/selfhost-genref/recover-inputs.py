#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Recover exact earlier build inputs without changing the checkout or Git.

Prefer retained snapshots and Git blobs. Early task-only inputs can also be
recovered from this session's actual authored patch records. Only bytes matching
a recorded build-input SHA-256 are accepted. The private session log is never
copied into evidence; only the matching task source and a patch-hash receipt are.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from state import ROOT, RUNTIME, BASE, read, sha


def digest(raw):
	return hashlib.sha256(raw).hexdigest()


def edits(patch):
	rows = patch.splitlines(keepends=True); i = 0
	while i < len(rows):
		line = rows[i]; match = re.match(r'\*\*\* (Add|Update|Delete) File: (.+)\n?$', line)
		if not match: i += 1; continue
		operation, name = match.groups(); i += 1; body = []
		while i < len(rows) and not rows[i].startswith(('*** Add File:', '*** Update File:', '*** Delete File:', '*** End Patch')): body.append(rows[i]); i += 1
		yield operation, name, body


def update(source, rows):
	cursor = 0; chunks = []; current = []
	for row in rows:
		if row.startswith('@@'):
			if current: chunks.append(current); current = []
		elif not row.startswith('*** End of File'): current.append(row)
	if current: chunks.append(current)
	for chunk in chunks:
		old = ''.join(row[1:] if row[:1] in (' ', '-') else row for row in chunk if row[:1] != '+')
		new = ''.join(row[1:] if row[:1] in (' ', '+') else row for row in chunk if row[:1] != '-')
		position = source.find(old, cursor); assert position >= 0, old[:160]
		source = source[:position]+new+source[position+len(old):]; cursor = position+len(new)
	return source


def main():
	p = argparse.ArgumentParser(); p.add_argument('--session', type=Path); a = p.parse_args()
	output = RUNTIME/'recovered-build-inputs'; output.mkdir(exist_ok=True)
	expected = {}
	for path in RUNTIME.rglob('ownflow-*-input-identity.json'):
		for source, value in read(path).get('sources', {}).items():
			if Path(source).is_relative_to(ROOT): expected.setdefault(value, set()).add(str(Path(source).relative_to(ROOT)))
	found = {}; receipts = []
	def accept(raw, origin):
		value = digest(raw)
		if value in expected and value not in found:
			target = output/value
			if target.exists(): assert target.read_bytes() == raw
			else: target.write_bytes(raw)
			found[value] = str(target); receipts.append(dict(sha256=value, sources=sorted(expected[value]), origin=origin))
	for source in sorted({name for names in expected.values() for name in names}):
		accept((ROOT/source).read_bytes(), dict(kind='current-file', path=source))
		for revision in (BASE, 'HEAD'):
			r = subprocess.run(['git', 'show', revision+':'+source], cwd=ROOT, capture_output=True)
			if r.returncode == 0: accept(r.stdout, dict(kind='Git-blob', revision=revision, path=source))
	for path in RUNTIME.rglob('*'):
		if path.is_file() and path.suffix in ('.astra', '.py') and not path.is_relative_to(output): accept(path.read_bytes(), dict(kind='retained-snapshot', path=str(path)))
	if len(found) < len(expected):
		if not a.session:
			thread = os.environ.get('CODEX_THREAD_ID'); assert thread
			matches = list((Path.home()/'.codex/sessions').rglob('*'+thread+'*.jsonl')); assert len(matches) == 1; a.session = matches[0]
		buffers = {}
		for raw_line in a.session.open():
			record = json.loads(raw_line); payload = record.get('payload', {})
			if not isinstance(payload, dict): continue
			code = payload.get('input', '')
			if not isinstance(code, str): continue
			for match in re.finditer(r'tools\.apply_patch\(\s*(?=")', code):
				try: patch, _ = json.JSONDecoder().raw_decode(code[match.end():])
				except json.JSONDecodeError: continue
				if not isinstance(patch, str) or not patch.startswith('*** Begin Patch'): continue
				for operation, name, rows in edits(patch):
					path = Path(name); path = path if path.is_absolute() else ROOT/path
					if not path.is_relative_to(ROOT): continue
					name = str(path.relative_to(ROOT))
					if not any(name in names for names in expected.values()): continue
					if name not in buffers:
						r = subprocess.run(['git', 'show', BASE+':'+name], cwd=ROOT, capture_output=True); buffers[name] = r.stdout.decode() if r.returncode == 0 else ''
					if operation == 'Add': buffers[name] = ''.join(row[1:] for row in rows if row.startswith('+'))
					elif operation == 'Delete': buffers[name] = ''
					else:
						try: buffers[name] = update(buffers[name], rows)
						except AssertionError: continue
					accept(buffers[name].encode(), dict(kind='actual-authored-patch', call_id=payload.get('call_id'), patch_sha256=digest(patch.encode()), path=name))
	missing = {value:sorted(names) for value, names in expected.items() if value not in found}
	result = dict(status='PASS' if not missing else 'INCOMPLETE', expected=len(expected), recovered=len(found), inputs=receipts, missing=missing, source_changes='None: checkout, index, Git and original evidence were only read')
	(output/'result.json').write_text(json.dumps(result, indent=2)+'\n'); print('Recovered', len(found), '/', len(expected), 'recorded input hashes; missing:', json.dumps(missing))
	raise SystemExit(0 if not missing else 1)


if __name__ == '__main__':
	main()
