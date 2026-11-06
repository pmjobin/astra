#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independently reopen the installed publisher's report and reconstruct evidence."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import zipfile
from state import ROOT, sha, read, git, load_module, bounded_run

RUNTIME = ROOT.parent/'codex/work/astra/runtime/effects25-r1'


def main():
	assert not git('status', '--porcelain=v2', '--untracked-files=all')
	path = ROOT.parent/'codex/reports/astra-report-current.zip'
	leaf = RUNTIME/'published-verification'; leaf.mkdir(exist_ok=False)
	with zipfile.ZipFile(path) as z:
		assert z.testzip() is None and len(z.namelist()) == len(set(z.namelist()))
		manifest = json.loads(z.read('MANIFEST.json'))
		assert manifest['format'] == 'pm-codex-report/1'
		assert set(z.namelist()) == {'MANIFEST.json', *(row['path'] for row in manifest['files'])}
		for row in manifest['files']:
			data = z.read(row['path']); assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
		result = json.loads(z.read('RESULT.json'))
		assert result['status'] == 'PARTIAL' and result['milestone_id'] == 'ASTRA-SELFHOST-EFFECTS-25-R1'
		assert result['submission_sha256'] == 'ed84f5a7b5c09162df2df1af5a5cc4f7d5d322361639566ac8c1fc7f00ff31f7'
		assert (result['final_commit'], result['final_tree']) == (git('rev-parse', 'HEAD').strip(), git('rev-parse', 'HEAD^{tree}').strip())
		assert not result['final_dirty_tracked_paths'] and not result['untracked_inventory_changed']
		assert b'**Result:** PARTIAL' in z.read('REPORT.md')
		for name in z.namelist():
			if name.startswith('source/'):
				assert z.read(name) == subprocess.check_output(['git', 'show', result['final_commit']+':'+name.removeprefix('source/')], cwd=ROOT)
		audit = json.loads(z.read('evidence/final-audit.json'))
		assert audit == read(RUNTIME/'final-audit.json') and audit['final_commit'] == result['final_commit'] and audit['final_tree'] == result['final_tree']
		assert all(row['new_Astra_effect_programs'] == 0 for row in audit['profiles'].values())
		for name in z.namelist():
			if name.startswith('evidence/') and name != 'evidence/INDEX.json':
				part = Path(name.removeprefix('evidence/')); assert len(part.parts) == 1
				(leaf/part).write_bytes(z.read(name))
	packaging = read(leaf/'packaging.json')
	decoder = load_module('r1_independent_transport_decoder', ROOT/'tools/qualification/encoded-evidence.py')
	model, raw = decoder.decode(leaf/'effects25-r1-encoding.json')
	assert hashlib.sha256(raw).hexdigest() == packaging['archive_sha256'] and len(raw) == packaging['archive_bytes']
	archive = leaf/'effects25-r1-evidence.tar.xz'; archive.write_bytes(raw)
	argv = [sys.executable, '-B', ROOT/'tests/selfhost-effects/restore.py', archive, '--output', leaf/'decoded', '--verify-only']
	r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/'restore.time', *argv], cwd=ROOT, capture_output=True, timeout=900)
	(leaf/'restore.stdout').write_bytes(r.stdout); (leaf/'restore.stderr').write_bytes(r.stderr)
	assert r.returncode == 0, r.stderr[-2500:]
	restored = json.loads(r.stdout); assert restored['status'] == 'BYTE_EXACT' and restored['logical_files'] == packaging['logical_files']
	intake = read(RUNTIME.parent/'native-current/pm-next-intake.json')
	assert intake['published'] and intake['final_commit'] == result['final_commit'] and intake['report_sha256'] == sha(path)
	receipt = dict(status='PUBLISHED_PARTIAL_VERIFIED', report=str(path), report_bytes=path.stat().st_size, report_sha256=sha(path), final_commit=result['final_commit'], final_tree=result['final_tree'], payloads=len(manifest['files']), logical_evidence_files=restored['logical_files'], evidence_archive_sha256=packaging['archive_sha256'], predecessor_sha256=sha(RUNTIME/'predecessor-report.zip'), classification='Report/Git/transport verification; missing compiler effect gates remain PARTIAL')
	(RUNTIME/'published-verification.json').write_text(json.dumps(receipt, indent=2)+'\n')
	print(json.dumps(receipt, indent=2), flush=True)


if __name__ == '__main__':
	main()
