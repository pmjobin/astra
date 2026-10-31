#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute distinct Surge 14 applications with independent foreign consumers."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
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
	work = Path(tempfile.mkdtemp(prefix='applications-', dir=output))
	prefix = args.prefix.resolve() if args.prefix else None
	if prefix:
		assert compiler == prefix / 'bin/astrac'
	sources = prefix / 'share/astra/examples/interop-tooling-14' if prefix else ROOT / 'examples/interop-tooling-14'
	support = prefix / 'share/astra/interop' if prefix else ROOT / 'lib/runtime/interop'
	rows = []
	receipt = {'compiler_sha256': sha(compiler), 'checks': rows, 'applications': {}}
	def run(command, contains=''):
		p = subprocess.run(list(map(str, command)), cwd=work, capture_output=True, text=True, timeout=120,
			env=dict(os.environ, CCACHE_DISABLE='1'))
		rows.append({'command': list(map(str, command)), 'exit': p.returncode, 'stdout': p.stdout, 'stderr': p.stderr})
		(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
		assert p.returncode == 0 and contains in p.stdout + p.stderr, rows[-1]
		return p.stdout
	for name in ('a121-quota-service.astra', 'a121-client.c'):
		shutil.copyfile(sources / name, work / name)
	source = work / 'a121-quota-service.astra'
	header = run([compiler, '--emit-class-header', source])
	(work / 'a121.h').write_text(header)
	flags = ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread']
	run(['gcc', *flags, '-c', support / 'foreign-14.c', '-o', work / 'foreign.o'])
	for cc in ('gcc', 'clang'):
		run([cc, *flags, '-c', work / 'a121-client.c', '-o', work / (cc + '-client.o')])
	levels = []
	for level in ('0', '1', '2'):
		obj = work / ('a121-O' + level + '.o')
		run([compiler, '-O' + level, '-c', source, '-o', obj])
		for cc in ('gcc', 'clang'):
			binary = work / ('a121-' + cc + '-O' + level)
			run([cc, '-pthread', obj, work / (cc + '-client.o'), work / 'foreign.o', '-o', binary])
			run([binary], contains='PASS A121:')
			if level in ('0', '2'):
				run(['valgrind', '--vgdb=no', '--default-suppressions=no', '--leak-check=full', '--error-exitcode=99', binary], contains='ERROR SUMMARY: 0 errors')
			dependencies = run(['readelf', '-d', binary])
			assert not any(name in dependencies for name in ('libgobject', 'libglib', 'libLLVM'))
			levels.append({'optimization': level, 'client': cc, 'binary_sha256': sha(binary)})
	receipt['applications']['A121'] = {'status': 'PASS', 'source_sha256': sha(source),
		'client_sha256': sha(work / 'a121-client.c'), 'generated_header_sha256': sha(work / 'a121.h'), 'variants': levels}
	receipt['status'] = 'PASS'
	(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	print(f'PASS: A121 distinct quota service; {len(rows)} compiler/C-client/lifetime/memory commands; evidence {work}')


if __name__ == '__main__':
	main()
