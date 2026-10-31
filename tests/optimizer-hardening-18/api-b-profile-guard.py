#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Standalone identity-drift controls for the approved current API-B profile."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('compiler', type=Path); parser.add_argument('output', type=Path)
	args = parser.parse_args(); compiler = args.compiler.resolve(strict=True)
	assert not args.output.resolve().is_relative_to(ROOT); args.output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='api-b-profile-guard-', dir=args.output.resolve()))
	source = ROOT / 'tests/declaration-interop-16/api-b.py'
	spec = importlib.util.spec_from_file_location('api_b_profile', source)
	module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
	receipt = dict(status='RUNNING', compiler_sha256=sha(compiler), sources={str(p): sha(p) for p in [source, Path(__file__)]}, checks=[])
	def record(name): receipt['checks'].append(dict(name=name, passed=True))
	try:
		paths = [work / name for name in ['compiler', 'source', 'dependency']]
		for path in paths: path.write_bytes(('initial-' + path.name).encode())
		sys.path.insert(0, str(ROOT / 'tests/support'))
		from input_guard import InputGuard
		guard = InputGuard(ROOT, compiler, None, 'regression', paths)
		guard.check(); record('unchanged-current-identities')
		for path in paths:
			original = path.read_bytes(); path.write_bytes(original + b'-changed')
			try: guard.check()
			except AssertionError: record(path.name + '-drift-refused')
			else: raise AssertionError('changed ' + path.name + ' accepted')
			path.write_bytes(original); guard.check(); record(path.name + '-restored-positive')
		try: module.main('unused', 'unused', 'invalid')
		except AssertionError: record('invalid-profile-refused')
		else: raise AssertionError('invalid qualification profile accepted')
		command = [sys.executable, '-B', source, compiler, work / 'historical', 'frozen']
		q = subprocess.run(list(map(str, command)), capture_output=True, text=True, timeout=15,
			env=dict(os.environ, PYTHONDONTWRITEBYTECODE='1'))
		receipt['historical_refusal'] = dict(command=list(map(str, command)), exit=q.returncode, stdout=q.stdout, stderr=q.stderr)
		assert q.returncode == 1 and 'historical evidence unavailable' in q.stderr
		record('explicit-historical-replay-refuses-missing-evidence')
		assert sha(compiler) == receipt['compiler_sha256'] and all(sha(Path(path)) == digest for path, digest in receipt['sources'].items())
		receipt['status'] = 'PASS'
	finally:
		if receipt['status'] != 'PASS': receipt['status'] = 'FAIL'
		(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	print(work / 'checks.json')


if __name__ == '__main__': main()
