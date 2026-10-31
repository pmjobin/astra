#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independently compiled C client for compiler-owned opaque Class adapters."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main(compiler_arg, output_arg):
	compiler = Path(compiler_arg).resolve()
	output = Path(output_arg).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='c-class-', dir=output))
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
	source = ROOT / 'tests/interop-tooling-14/c-class/counter.astra'
	client = ROOT / 'tests/interop-tooling-14/c-class/client.c'
	header = run([compiler, '--emit-class-header', source])
	(work / 'counter.h').write_text(header)
	flags = ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread']
	run(['cc', *flags, '-I', work, '-c', client, '-o', work / 'client.o'])
	run(['cc', *flags, '-I', work, '-c', client.with_name('fault.c'), '-o', work / 'fault.o'])
	run(['cc', *flags, '-c', ROOT / 'lib/runtime/interop/foreign-14.c', '-o', work / 'foreign.o'])
	for level in ('0', '1', '2'):
		obj = work / ('counter-O' + level + '.o')
		binary = work / ('client-O' + level)
		run([compiler, '-O' + level, '-c', source, '-o', obj])
		run(['cc', '-pthread', work / 'client.o', obj, work / 'foreign.o', '-o', binary])
		run([binary], contains='PASS opaque C Class')
		fault = work / ('fault-O' + level)
		run(['cc', '-pthread', '-Wl,--wrap=calloc', work / 'fault.o', obj, work / 'foreign.o', '-o', fault])
		run([fault], contains='exact partial cleanup')
		dependencies = run(['readelf', '-d', binary])
		assert not any(name in dependencies for name in ['libglib', 'libgobject', 'libLLVM'])
		if level in ('0', '2'):
			run(['valgrind', '--vgdb=no', '--default-suppressions=no', '--leak-check=full',
				'--show-leak-kinds=definite,indirect,possible', '--errors-for-leak-kinds=definite,indirect,possible',
				'--error-exitcode=99', binary], contains='ERROR SUMMARY: 0 errors')
			run(['valgrind', '--vgdb=no', '--default-suppressions=no', '--leak-check=full',
				'--show-leak-kinds=definite,indirect,possible', '--errors-for-leak-kinds=definite,indirect,possible',
				'--error-exitcode=99', fault], contains='ERROR SUMMARY: 0 errors')
	bad = work / 'invalid.astra'
	healthy = source.read_text()
	for changed, reason in [
		(healthy.replace('[Shared]', ''), 'plain Shared'),
		(healthy.replace('name="counter14"', 'name="astra_private"'), 'unique explicit portable name'),
		(healthy.replace('property="value"', 'property="missing"'), 'read/write int property'),
		(healthy.replace('set(int value) { this.data = value; }', ''), 'read/write int property'),
		(healthy.replace('init(int value)', 'init(int value, int extra)'), 'init(int)'),
		(healthy.replace('private int data;', 'private int data; private f64 extra;'), 'copied int payload'),
	]:
		bad.write_text(changed)
		run([compiler, '--check', bad], expected=1, contains=reason)
	run([compiler, '--check', source])
	# Commuting policies and Monitor composition use the same native authority.
	for label, text in [('commuted', healthy.replace('[CExport(name="counter14", property="value")]\n[Shared]', '[Shared]\n[CExport(name="counter14", property="value")]')),
		('monitor', healthy.replace('[Shared]', '[Shared,Monitor]'))]:
		changed = work / (label + '.astra')
		changed.write_text(text)
		assert run([compiler, '--emit-class-header', changed]) == header
		obj = work / (label + '.o')
		run([compiler, '-O2', '-c', changed, '-o', obj])
		binary = work / label
		provider = [ROOT / 'lib/runtime/runtime/monitors-13.c'] if label == 'monitor' else []
		run(['cc', *flags, work / 'client.o', obj, work / 'foreign.o', *provider, '-o', binary])
		run([binary], contains='PASS opaque C Class')
	for stage in ('semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi'):
		run([compiler, '--dump-' + stage, source], contains='foreign-class' if stage != 'cabi' else 'opaque-class')
	formatted = run([compiler, '--format', source])
	assert formatted == healthy
	assert source.read_text() == healthy
	receipt['status'] = 'PASS'
	(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	print(f'PASS: {len(rows)} opaque Class C ABI, lifetime, affinity and refusal commands; evidence {work}')


if __name__ == '__main__':
	main(*sys.argv[1:])
