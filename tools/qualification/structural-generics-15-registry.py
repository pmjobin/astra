#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Capture one ordinary Meson run without hiding consent-held registrations.

All protocol, expected-exit, timeout, dependency and serial-barrier behavior stays
with Meson. A held registration always prevents overall registry qualification.
This script supplies no approval mechanism and never changes build profiles.
"""
from pathlib import Path
import argparse
import collections
import hashlib
import json
import os
import re
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()


def git(*arguments):
	return subprocess.check_output(['git', *arguments], cwd=ROOT)


def source_snapshot():
	assert subprocess.run(['git', 'diff', '--quiet', 'HEAD'], cwd=ROOT).returncode == 0, 'commit tracked task inputs before qualification'
	return dict(commit=git('rev-parse', 'HEAD').decode().strip(),
		tracked_files={os.fsdecode(name): sha(ROOT / os.fsdecode(name))
		for name in git('ls-files', '-z').split(b'\0') if name and (ROOT / os.fsdecode(name)).is_file()})


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--build', type=Path, required=True)
	parser.add_argument('--output', type=Path, required=True)
	parser.add_argument('--jobs', type=int, default=4)
	parser.add_argument('--hold', action='append', default=[])
	parser.add_argument('--hold-reason')
	args = parser.parse_args()
	assert 1 <= args.jobs <= 8
	assert not args.hold or args.hold_reason, 'record the authority reason for every held set'
	build, output = args.build.resolve(strict=True), args.output.resolve()
	assert not build.is_relative_to(ROOT) and not output.is_relative_to(ROOT)
	configuration = json.loads((build / 'meson-info/meson-info.json').read_text())['directories']
	assert Path(configuration['source']).resolve() == ROOT and Path(configuration['build']).resolve() == build
	registry_path = build / 'meson-info/intro-tests.json'
	registry = json.loads(registry_path.read_text())
	names = [row['name'] for row in registry]
	assert len(names) == len(set(names)) and not any(any(c in name for c in '*?[]') for name in names)
	held = set(args.hold)
	assert held <= set(names)
	selected = set(names) - held
	assert selected
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='structural-registry-', dir=output))
	compiler = build / 'astrac'
	receipt = dict(format='astra-m15-current-registry/1', build=str(build),
		registry=registry, registry_sha256=sha(registry_path),
		build_options=json.loads((build / 'meson-info/intro-buildoptions.json').read_text()),
		source_freeze=source_snapshot(), compiler_sha256=sha(compiler), recipe_sha256=sha(Path(__file__)),
		held=[dict(name=name, status='NOT_RUN_AUTHORITY_REQUIRED', reason=args.hold_reason) for name in sorted(held)],
		selected_registrations=sorted(selected), stage='RUNNING', started_unix=time.time())

	def save():
		(out / 'receipt.json').write_text(json.dumps(receipt, indent='\t') + '\n')

	command = ['meson', 'test', '-C', str(build), '--no-rebuild', '--num-processes', str(args.jobs),
		'--print-errorlogs', '--logbase', str(out / 'registry')]
	if held:
		command += sorted(selected)
	receipt['command'] = command
	save()
	print(str(out / 'receipt.json'), flush=True)
	with (out / 'console.log').open('w') as stream:
		result = subprocess.run(command, cwd=ROOT,
			env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'),
			stdout=stream, stderr=subprocess.STDOUT)
	receipt['exit'] = result.returncode
	receipt['elapsed_seconds'] = time.time() - receipt['started_unix']
	receipt['source_unchanged'] = source_snapshot() == receipt['source_freeze']
	receipt['compiler_unchanged'] = sha(compiler) == receipt['compiler_sha256']
	receipt['registry_unchanged'] = sha(registry_path) == receipt['registry_sha256']
	log = out / 'registry.json'
	# Never copy inherited environment values into compact engineering evidence.
	receipt['results'] = [{key: value for key, value in json.loads(line).items() if key != 'env'}
		for line in log.read_text().splitlines()] if log.exists() else []
	observed = [row['name'].removeprefix('astra:') for row in receipt['results']]
	receipt['missing_selected'] = sorted(selected - set(observed))
	receipt['unexpected'] = sorted(set(observed) - selected)
	receipt['duplicates'] = [name for name, count in collections.Counter(observed).items() if count != 1]
	receipt['nonpassing'] = [row for row in receipt['results'] if row['result'] != 'OK']
	receipt['tap_skips'] = [dict(registration=row['name'], line=line) for row in receipt['results']
		for line in row.get('stdout', '').splitlines() if re.match(r'^\s*(?:not )?ok\s+\d+.*#\s*SKIP\b', line, re.I)]
	selected_pass = result.returncode == 0 and all(receipt[key] for key in
		['source_unchanged', 'compiler_unchanged', 'registry_unchanged']) and not any(receipt[key] for key in
		['missing_selected', 'unexpected', 'duplicates', 'nonpassing', 'tap_skips'])
	receipt['selected_pass'] = selected_pass
	receipt['full_registry_pass'] = selected_pass and not held
	receipt['stage'] = 'REGISTRY_PASS' if receipt['full_registry_pass'] else 'REGISTRY_NOT_QUALIFIED'
	save()
	print(json.dumps(dict(stage=receipt['stage'], registered=len(names), selected=len(selected),
		observed=len(observed), held=len(held), nonpassing=len(receipt['nonpassing']))))
	return 0 if receipt['full_registry_pass'] else 1


if __name__ == '__main__':
	raise SystemExit(main())
