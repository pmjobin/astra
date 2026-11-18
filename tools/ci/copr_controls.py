#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exercise real source archive guards with modified SRPM inputs before publication."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile

from common import ROOT, external, require, run, sha, write
from copr_source import archive, SEED_PATH


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--commit', required=True)
	p.add_argument('--build', type=Path, required=True)
	p.add_argument('--runtime', type=Path, required=True)
	a = p.parse_args()
	build, runtime = external(a.build), external(a.runtime)
	archives = []
	for n in ('first', 'second'):
		leaf = build/n
		leaf.mkdir()
		path, manifest = archive(a.commit, leaf)
		archives.append(path)
	require(sha(archives[0]) == sha(archives[1]), 'source archive is not deterministic')
	with tarfile.open(archives[0]) as tar:
		tar.extractall(build/'unpacked', filter='data')
	source = build/'unpacked'/('astra-'+a.commit)
	seed = archives[0].parent/Path(SEED_PATH).name
	def check(name, commit=a.commit, expected=0, expected_message=None):
		argv = [sys.executable, '-B', source/'tools/ci/copr_build.py', '--verify-only', '--seed', seed, '--commit', commit, '--tree', manifest['tree']]
		result = subprocess.run(list(map(str, argv)), capture_output=True)
		write(runtime/(name+'.json'), dict(argv=list(map(str, argv)), exit=result.returncode, stdout=result.stdout.decode(), stderr=result.stderr.decode()))
		require((result.returncode == 0) == (expected == 0), name+': incorrect refusal')
		if expected_message:
			require(expected_message.encode() in result.stderr, name+': wrong refusal reason')
	check('valid')
	check('wrong-commit', commit='0'*40, expected=1, expected_message='source commit/tree mismatch')
	old_seed = seed.read_bytes()
	seed.write_bytes(old_seed[:-1]+bytes([old_seed[-1]^1]))
	check('seed-hash', expected=1, expected_message='input identity mismatch')
	seed.write_bytes(old_seed)
	current = source/'compiler/driver/main.astra'
	original = current.read_bytes()
	current.write_bytes(original+b'\n')
	check('stale-source', expected=1, expected_message='input identity mismatch')
	current.write_bytes(original)
	for name, target, data in [('prebuilt-object', 'astrac-O2.o', b'\x7fELF\x02'), ('bundled-llvm', 'libLLVM.so.23.1', b'\x7fELF\x02')]:
		path = source/target
		path.write_bytes(data)
		check(name, expected=1, expected_message='missing or undeclared source input')
		path.unlink()
	for target in ('LICENSE.txt', 'compiler/driver/main.astra'):
		path = source/target
		data = path.read_bytes()
		path.unlink()
		check('missing-'+path.name, expected=1, expected_message='missing or undeclared source input')
		path.write_bytes(data)
		# SRPM frontend refuses arbitrary package/spec selection before producing output.
	result = subprocess.run([sys.executable, '-B', ROOT/'tools/ci/copr_source.py', '--commit', a.commit, '--spec', 'other.spec', '--output', build/'wrong-name'], capture_output=True)
	require(result.returncode != 0 and b'wrong spec/package' in result.stderr, 'foreign package accepted')
	write(runtime/'wrong-package.json', dict(exit=result.returncode, stderr=result.stderr.decode()))
	check('restored-valid')
	write(runtime/'result.json', dict(status='SOURCE_INPUT_NEGATIVE_CONTROLS_PASS', deterministic_archive_sha256=sha(archives[0]), controls=['full commit', 'mutated seed', 'stale source', 'prebuilt object', 'bundled LLVM', 'missing license', 'missing compiler source', 'wrong package'], scope='Archive/input guards only; ELF architecture, LLVM headers/major and installed behavior require separate target tests.'))
	print('SOURCE_INPUT_NEGATIVE_CONTROLS_PASS')


if __name__ == '__main__':
	main()
