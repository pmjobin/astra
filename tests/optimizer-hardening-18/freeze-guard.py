#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Positive and drift counterexamples for the proposed explicit replay profiles."""
from pathlib import Path
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / 'tests/runtime-composition-17/frozen-4/freeze_guard.py'
spec = importlib.util.spec_from_file_location('braid_freeze_guard', HELPER)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def main(output):
	output = Path(output).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='freeze-guard-', dir=output))
	root = work / 'source'
	root.mkdir()
	subprocess.run(['git', 'init', '-q', root], check=True)
	(root / 'bootstrap').mkdir()
	source, compiler, dependency, extra = [root / name for name in ['bootstrap/unit', 'compiler', 'dependency', 'braid']]
	for path in (source, compiler, dependency, extra):
		path.write_text(path.name + '\n')
	subprocess.run(['git', 'add', '--', 'bootstrap/unit'], cwd=root, check=True)
	freeze = root / 'freeze.json'
	sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
	data = {'freeze': 4, 'compiler': {'sha256': sha(compiler)},
		'source_files': {'bootstrap/unit': {'sha256': sha(source)}},
		'host_dependencies': {str(dependency): {'sha256': sha(dependency)}}}
	freeze.write_text(json.dumps(data))
	checks = []
	for profile in ('frozen', 'regression'):
		guard = module.FreezeGuard(root, compiler, freeze, profile, [extra, dependency, HELPER])
		guard.check()
		checks.append(profile + ': unchanged inputs accepted')
		for path in (source, compiler, dependency, extra, *([freeze] if profile == 'frozen' else [])):
			original = path.read_bytes()
			path.write_bytes(original + b'changed\n')
			try:
				try:
					guard.check()
					assert False, 'changed input accepted: ' + str(path)
				except AssertionError as error:
					assert 'qualification input changed' in str(error), error
					checks.append(profile + ': changed ' + path.name + ' refused')
			finally:
				path.write_bytes(original)
			guard.check()
	compiler.write_bytes(b'current compiler\n')
	current = module.FreezeGuard(root, compiler, freeze, 'regression', [extra])
	assert current.record()['regression_only'] and 'no historical' in current.record()['scope']
	checks.append('current compiler accepted only as current regression')
	tool_dir = work / 'changed-tools'
	tool_dir.mkdir()
	tool = tool_dir / 'gcc'
	tool.write_text('#!/bin/sh\nexit 1\n')
	tool.chmod(0o755)
	original_path = os.environ['PATH']
	try:
		os.environ['PATH'] = str(tool_dir) + os.pathsep + original_path
		try:
			current.check()
		except AssertionError as error:
			assert 'qualification tool resolution changed' in str(error), error
			checks.append('current regression refuses changed tool resolution')
		else:
			raise AssertionError('changed tool resolution accepted')
	finally:
		os.environ['PATH'] = original_path
	current.check()
	for profile in ('frozen', 'unknown'):
		try:
			module.FreezeGuard(root, compiler, freeze, profile, [extra])
			assert False, 'invalid profile or historical mismatch accepted'
		except AssertionError as error:
			assert ('historical frozen compiler' if profile == 'frozen' else 'invalid qualification profile') in str(error), error
			checks.append(profile + ': invalid historical identity/profile refused')
	freeze.unlink()
	module.FreezeGuard(root, compiler, freeze, 'regression', [extra, dependency]).check()
	checks.append('current regression accepts absent historical evidence')
	try:
		module.FreezeGuard(root, compiler, freeze, 'frozen', [extra])
	except AssertionError as error:
		assert 'historical evidence unavailable' in str(error), error
		checks.append('historical replay refuses absent evidence')
	else:
		raise AssertionError('missing historical evidence accepted')
	receipt = {'status': 'PASS', 'checks': checks, 'helper_sha256': sha(HELPER),
		'recipe_sha256': sha(Path(__file__)), 'scope': 'Profile identity controls; no application execution'}
	(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	print('PASS:', len(checks), 'profile controls;', work)


if __name__ == '__main__':
	main(*sys.argv[1:])
