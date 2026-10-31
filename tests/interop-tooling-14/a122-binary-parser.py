#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""A122: real runtime binary input, independent C parsing and Resource cleanup."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('compiler', type=Path)
	parser.add_argument('output', type=Path)
	parser.add_argument('--prefix', type=Path)
	args = parser.parse_args()
	compiler, output = args.compiler.resolve(), args.output.resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='a122-', dir=output))
	prefix = args.prefix.resolve() if args.prefix else None
	if prefix:
		assert compiler == prefix / 'bin/astrac'
	sources = prefix / 'share/astra/examples/interop-tooling-14' if prefix else ROOT / 'examples/interop-tooling-14'
	tool = prefix / 'share/astra/tools/headers/import.py' if prefix else ROOT / 'tools/headers/import.py'
	rows, variants = [], []
	receipt = {'application': 'A122', 'compiler_sha256': sha(compiler), 'checks': rows, 'variants': variants}
	def run(command, *, expected=0, contains='', env=None):
		p = subprocess.run(list(map(str, command)), cwd=work, capture_output=True, text=True, timeout=120,
			env=dict(os.environ, CCACHE_DISABLE='1', **(env or {})))
		rows.append({'command': list(map(str, command)), 'environment': env or {}, 'exit': p.returncode,
			'expected_exit': expected, 'stdout': p.stdout, 'stderr': p.stderr})
		(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
		assert p.returncode == expected and contains in p.stdout + p.stderr, rows[-1]
		return p.stdout
	names = ['a122-binary-parser.astra', 'a122-reader.vapi', 'a122-provider.c', 'a122-packets.h']
	for name in names:
		shutil.copyfile(sources / name, work / name)
	receipt['sources'] = {name: sha(work / name) for name in names}
	profile = work / 'headers.json'
	profile.write_text(json.dumps({'format': 'astra-c-header-profile/1', 'target': 'x86_64-linux-gnu-lp64',
		'headers': ['a122-packets.h'], 'constants': [{'macro': 'A122_MAGIC', 'name': 'magic'}, {'macro': 'A122_LIMIT', 'name': 'limit'}]}) + '\n')
	base = [sys.executable, tool, '--profile', profile, '--work', work, '--cc', 'gcc']
	generated = work / 'header-bindings'
	run([*base, '--output', generated])
	run([*base, '--verify', generated])
	receipt['header_contract_sha256'] = sha(generated / 'contract.json')
	header = struct.pack('<HHBB', 0x4132, 4, 1, 0)
	records = [struct.pack('<Bq', 1, -1234567890123), struct.pack('<BQ', 2, 9000000000000000000),
		struct.pack('<Bq', 1, 123), struct.pack('<BQ', 2, 31)]
	valid = header + b''.join(records)
	fixtures = [
		('valid', valid, 0, 4),
		('short-header', header[:3], 11, 0),
		('bad-version', header[:4] + b'\x02\x00' + b''.join(records), 11, 0),
		('bad-magic', b'\x00\x00' + valid[2:], 12, 0),
		('zero-count', header[:2] + b'\x00\x00' + valid[4:], 13, 0),
		('large-count', header[:2] + b'\x11\x00' + valid[4:], 13, 0),
		('unknown-kind', header + b'\x03' + records[0][1:] + b''.join(records[1:]), 14, 0),
		('early-eof', header + b''.join(records[:2]), 14, 2),
		('short-payload', header + b''.join(records[:2]) + records[2][:5], 15, 2),
		('changed-payload', header + b''.join(records[:2]) + struct.pack('<Bq', 1, 124) + records[3], 16, 2),
		('trailing-data', valid + b'\xff', 18, 4),
	]
	for name, data, _, _ in fixtures:
		(work / (name + '.bin')).write_bytes(data)
	receipt['fixtures'] = {name: {'sha256': sha(work / (name + '.bin')), 'status': status, 'callbacks': callbacks}
		for name, _, status, callbacks in fixtures}
	flags = ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic']
	for cc in ('gcc', 'clang'):
		provider = work / (cc + '-provider.o')
		bridge = work / (cc + '-headers.o')
		run([cc, *flags, '-I', work, '-c', work / 'a122-provider.c', '-o', provider])
		run([cc, *flags, '-I', work, '-c', generated / 'bindings.c', '-o', bridge])
		for level in ('0', '1', '2'):
			binary = work / (cc + '-O' + level)
			run([compiler, '-O' + level, '--vapi', work / 'a122-reader.vapi', generated / 'bindings.astra',
				work / 'a122-binary-parser.astra', '--link-object', provider, '--link-object', bridge, '-o', binary])
			for name, _, status, callbacks in fixtures:
				env = {'A122_INPUT': str(work / (name + '.bin')), 'A122_EXPECT': str(status),
					'A122_CALLBACKS': str(callbacks), 'A122_OWNERS': '1', 'A122_ALLOC_FAIL': '0'}
				run([binary], contains='PASS A122:', env=env)
				if level in ('0', '2') and name in ('valid', 'short-payload', 'changed-payload'):
					run(['valgrind', '--vgdb=no', '--default-suppressions=no', '--leak-check=full', '--errors-for-leak-kinds=all',
						'--error-exitcode=99', binary], contains='ERROR SUMMARY: 0 errors', env=env)
			for failure in ('missing-file', 'allocation'):
				run([binary], contains='PASS A122: status=10 opened=0 closed=0 callbacks=0', env={
					'A122_INPUT': str(work / ('valid.bin' if failure == 'allocation' else 'absent.bin')),
					'A122_EXPECT': '10', 'A122_OWNERS': '0', 'A122_CALLBACKS': '0', 'A122_ALLOC_FAIL': str(int(failure == 'allocation'))})
			deps = run(['readelf', '-d', binary])
			assert not any(name in deps for name in ('libgobject', 'libglib', 'libLLVM', 'libstdc++'))
			variants.append({'optimization': level, 'provider': cc, 'binary_sha256': sha(binary), 'fixtures': len(fixtures) + 2})
	receipt['status'] = 'PASS'
	(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	print(f'PASS: A122 real binary parser; {len(rows)} commands, {len(variants)} variants, exact data/cleanup/error oracles; evidence {work}')


if __name__ == '__main__':
	main()
