#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Materialize the compatibility port from a verified prepare.py extraction."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def digest(path):
	with path.open('rb') as stream:
		return hashlib.file_digest(stream, 'sha256').hexdigest()


def materialize(reference, manifest, output):
	if output.exists() or not output.is_relative_to(ROOT / 'build/app-cad-1'):
		raise ValueError('output must be a fresh directory under build/app-cad-1/')
	expected = json.loads(manifest.read_text())
	if 'members' in expected:
		expected = expected['members']
	pin = json.loads((HERE / 'pins.json').read_text())['cad']
	# Compare the complete manifest with the committed inventory obtained from
	# the pinned Git tree, rather than trusting a caller-supplied set of hashes.
	authority = json.loads((HERE / 'cad-members.json').read_text())
	if expected != authority:
		raise ValueError(f'manifest is not the qualified CAD {pin["revision"]}')
	actual = {str(p.relative_to(reference)) for p in reference.rglob('*') if p.is_file() or p.is_symlink()}
	if actual != set(expected):
		raise ValueError('reference file set differs from the pinned manifest')
	for name, row in expected.items():
		path = reference / name
		if path.is_symlink() or digest(path) != row['sha256'] or stat.S_IMODE(path.stat().st_mode) != int(row['mode'][-3:], 8):
			raise ValueError(f'reference blob/mode differs: {path}')
	shutil.copytree(reference, output)
	patch = HERE / 'compat/port.patch'
	command = ['git', 'apply', '--directory=' + str(output.relative_to(ROOT)), str(patch)]
	p = subprocess.run(command, cwd=ROOT, env=dict(os.environ, GIT_OPTIONAL_LOCKS='0'), capture_output=True, text=True)
	if p.returncode:
		raise RuntimeError(f'{command!r}: {p.stderr}')
	for source, destination in [('compat/arguments.c', 'native/arguments.c'), ('compat/entry.astra', 'src/entry.astra')]:
		shutil.copyfile(HERE / source, output / destination)
	rows = {}
	for path in sorted(output.rglob('*')):
		if not path.is_file():
			continue
		name = str(path.relative_to(output))
		row = {'sha256': digest(path), 'mode': format(stat.S_IMODE(path.stat().st_mode), '06o'), 'bytes': path.stat().st_size}
		row['origin'] = name if name in expected else {'native/arguments.c': 'compat/arguments.c', 'src/entry.astra': 'compat/entry.astra'}[name]
		row['origin_revision'] = pin['revision'] if name in expected else None
		row['changed'] = name not in expected or row['sha256'] != expected[name]['sha256']
		rows[name] = row
	return {'route': 'P', 'qualification': 'NOT_RUN', 'origin': pin, 'patch_sha256': digest(patch), 'members': rows, 'application_changes': [name for name, row in rows.items() if row['changed']]}


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--reference', required=True, type=Path)
	parser.add_argument('--manifest', required=True, type=Path)
	parser.add_argument('--output', required=True, type=Path)
	args = parser.parse_args()
	record = materialize(args.reference.resolve(), args.manifest.resolve(), args.output.resolve())
	(args.output.parent / (args.output.name + '-manifest.json')).write_text(json.dumps(record, indent='\t') + '\n')
	print(json.dumps({'route': 'P', 'qualification': 'NOT_RUN', 'changed': record['application_changes']}, indent='\t'))
	return 0


if __name__ == '__main__':
	sys.exit(main())
