#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual header evaluation, independent C bridges, tamper/stale controls."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / 'tools/headers/import.py'


def main(compiler_arg, output_arg):
	compiler = Path(compiler_arg).resolve()
	output = Path(output_arg).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='c-headers-', dir=output))
	rows = []
	receipt = {'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(), 'checks': rows}
	def run(command, expected=0, contains=''):
		p = subprocess.run(list(map(str, command)), capture_output=True, text=True, timeout=120,
			cwd=work, env=dict(os.environ, CCACHE_DISABLE='1'))
		rows.append({'command': list(map(str, command)), 'exit': p.returncode,
			'expected_exit': expected, 'stdout': p.stdout, 'stderr': p.stderr})
		(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
		assert p.returncode == expected and contains in p.stdout + p.stderr, rows[-1]
		return p.stdout
	profile = work / 'profile.json'
	contract = dict(format='astra-c-header-profile/1', target='x86_64-linux-gnu-lp64', headers=['packet.h'],
		constants=[dict(macro=name, name=label) for name, label in [('PACKET_MAGIC', 'magic'), ('PACKET_LIMIT', 'limit'), ('PACKET_MINIMUM', 'minimum'), ('PACKET_ENUM', 'kind')]])
	profile.write_text(json.dumps(contract) + '\n')
	header = '#include "nested.h"\n#define PACKET_MAGIC 0x5142\n#define PACKET_LIMIT (NESTED_BASE * 7 + 1)\n#define PACKET_MINIMUM (-2147483647 - 1)\nenum { PACKET_ENUM = (5 << 4) | 3 };\n'
	(work / 'packet.h').write_text(header)
	(work / 'nested.h').write_text('#define NESTED_BASE 6\n')
	base = [sys.executable, TOOL, '--profile', profile, '--work', work]
	first = work / 'first'
	second = work / 'second'
	run([*base, '--cc', 'gcc', '--output', first])
	run([*base, '--cc', 'gcc', '--output', second])
	for name in ('bindings.astra', 'bindings.c', 'bindings.h', 'contract.json'):
		assert (first / name).read_bytes() == (second / name).read_bytes(), name
	run([*base, '--cc', 'gcc', '--verify', first])
	main = work / 'main.astra'
	main.write_text('int main() {\n\tif (Header_magic != 20802 || Header_limit != 43 || Header_minimum != -2147483648 || Header_kind != 83) { return 1; }\n\tif (header_magic() != Header_magic || header_limit() != Header_limit || header_minimum() != Header_minimum || header_kind() != Header_kind) { return 2; }\n\treturn 0;\n}\n')
	for cc in ('gcc', 'clang'):
		generated = first if cc == 'gcc' else work / 'clang'
		if cc == 'clang':
			run([*base, '--cc', cc, '--output', generated])
			run([*base, '--cc', cc, '--verify', generated])
		run([cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-I', work, '-c', generated / 'bindings.c', '-o', generated / 'bindings.o'])
		for level in ('0', '1', '2'):
			binary = work / (cc + '-O' + level)
			run([compiler, '-O' + level, generated / 'bindings.astra', main, '--link-object', generated / 'bindings.o', '-o', binary])
			run([binary])
			if level == '2':
				run(['valgrind', '--vgdb=no', '--default-suppressions=no', '--leak-check=full', '--error-exitcode=99', binary], contains='ERROR SUMMARY: 0 errors')
	for name in ('bindings.astra', 'bindings.c', 'bindings.h', 'contract.json'):
		path = first / name
		healthy = path.read_bytes()
		path.write_bytes(healthy + b' altered\n')
		run([*base, '--cc', 'gcc', '--verify', first], expected=1, contains='stale or altered header product')
		path.write_bytes(healthy)
		run([*base, '--cc', 'gcc', '--verify', first])
	(work / 'nested.h').write_text('#define NESTED_BASE 7\n')
	run([*base, '--cc', 'gcc', '--verify', first], expected=1, contains='stale or altered header product')
	run(['gcc', '-std=c11', '-I', work, '-c', first / 'bindings.c', '-o', work / 'denied.o'], expected=1, contains='stale header constant')
	changed = work / 'changed'
	run([*base, '--cc', 'gcc', '--output', changed])
	stale = subprocess.run([str(compiler), str(changed / 'bindings.astra'), str(main), '--link-object', str(first / 'bindings.o'), '-o', str(work / 'stale')], capture_output=True, text=True, timeout=120)
	rows.append({'command': stale.args, 'exit': stale.returncode, 'stdout': stale.stdout, 'stderr': stale.stderr})
	assert stale.returncode != 0 and 'astra_header_' in stale.stderr
	(work / 'nested.h').write_text('#define NESTED_BASE 6\n')
	run([*base, '--cc', 'gcc', '--verify', first])
	for index, mutation in enumerate([
		header.replace('0x5142', '0x5142u'),
		header.replace('0x5142', '((int)sizeof(__TIME__))'),
		header.replace('0x5142', 'missing_symbol'),
		header.replace('0x5142', '3.5'),
		header.replace('0x5142', '(header_side_effect())') + 'int header_side_effect(void);\n',
	]):
		(work / 'packet.h').write_text(mutation)
		run([*base, '--output', work / ('bad-' + str(index))], expected=1, contains='C compiler rejected selected header contract')
		assert not (work / ('bad-' + str(index))).exists()
	(work / 'packet.h').write_text(header)
	for index, mutation in enumerate([
		dict(contract, target='i686-windows'),
		dict(contract, headers=['../private.h']),
		dict(contract, constants=[dict(macro='f();', name='bad')]),
		dict(contract, constants=contract['constants'] + [contract['constants'][0]]),
	]):
		profile.write_text(json.dumps(mutation) + '\n')
		run([*base, '--output', work / ('invalid-' + str(index))], expected=1, contains='astra-c-header:')
		assert not (work / ('invalid-' + str(index))).exists()
	profile.write_text(json.dumps(contract) + '\n')
	run([*base, '--cc', 'gcc', '--verify', first])
	receipt['status'] = 'PASS'
	(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	print(f'PASS: {len(rows)} evaluated headers, reproducibility, GCC/Clang O0/O1/O2 and stale/tamper/refusal commands; evidence {work}')


if __name__ == '__main__':
	main(*sys.argv[1:])
