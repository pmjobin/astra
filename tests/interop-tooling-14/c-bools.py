#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute explicit C99 bool calls against independent strict C11 toolchains."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]

SOURCE = '''[CImport(name="bool14_not",bool_abi="c99")]
bool incoming_not(bool value);
[CImport(name="bool14_gate",bool_abi="c99")]
bool incoming_gate(int value, bool enabled, f64 threshold);
[CImport(name="bool14_number",bool_abi="c99")]
int incoming_number(bool value);
[CImport(name="bool14_present",bool_abi="c99")]
bool incoming_present(bool enabled, void* value);
[CExport(name="astra14_flip",bool_abi="c99")]
bool flip(bool value) { return incoming_not(value); }
[CExport(name="astra14_gate",bool_abi="c99")]
bool gate(int value, bool enabled, f64 threshold) { return incoming_gate(value, enabled, threshold); }
[CExport(name="astra14_number",bool_abi="c99")]
int number(bool value) { return incoming_number(value); }
[CExport(name="astra14_present",bool_abi="c99")]
bool present(bool enabled, void* value) { return incoming_present(enabled, value); }
'''

HEADER = '''#ifndef BOOL14_H
#define BOOL14_H
#include <stdint.h>
_Static_assert(sizeof(_Bool) == 1 && _Alignof(_Bool) == 1, "selected C bool storage oracle");
_Static_assert(sizeof(void *) == 8, "selected pointer model");
_Bool bool14_not(_Bool);
_Bool bool14_gate(int32_t, _Bool, double);
int32_t bool14_number(_Bool);
_Bool bool14_present(_Bool, void *);
_Bool astra14_flip(_Bool);
_Bool astra14_gate(int32_t, _Bool, double);
int32_t astra14_number(_Bool);
_Bool astra14_present(_Bool, void *);
#endif
'''

PROVIDER = '''#include "bool14.h"
_Bool bool14_not(_Bool value) { return !value; }
_Bool bool14_gate(int32_t value, _Bool enabled, double threshold) { return enabled && value >= 0 && value < threshold; }
int32_t bool14_number(_Bool value) { return value ? 57 : -11; }
_Bool bool14_present(_Bool enabled, void *value) { return enabled && value != 0; }
'''

CLIENT = '''#include "bool14.h"
#include <stdio.h>
int main(void) {
	int marker = 42;
	for (int enabled = 0; enabled < 2; ++enabled) {
		if (astra14_flip((_Bool)enabled) != !enabled) return 1;
		if (astra14_number((_Bool)enabled) != (enabled ? 57 : -11)) return 2;
		if (astra14_present((_Bool)enabled, &marker) != (_Bool)enabled || astra14_present((_Bool)enabled, 0)) return 3;
		for (int value = -3; value < 5; ++value) {
			if (astra14_gate(value, (_Bool)enabled, 2.5) != (_Bool)(enabled && value >= 0 && value < 2.5)) return 4;
		}
	}
	puts("PASS: C99 _Bool in both directions, mixed integer/FP/pointer channels, canonical true/false");
	return 0;
}
'''


def main(compiler_arg, output_arg):
	compiler, output = Path(compiler_arg).resolve(), Path(output_arg).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='c-bools-', dir=output))
	rows = []
	receipt = {'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(), 'checks': rows}
	def run(command, expected=0, contains=''):
		p = subprocess.run(list(map(str, command)), capture_output=True, text=True, timeout=120,
			cwd=work, env=dict(os.environ, CCACHE_DISABLE='1'))
		rows.append({'command': list(map(str, command)), 'exit': p.returncode, 'expected_exit': expected, 'stdout': p.stdout, 'stderr': p.stderr})
		(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
		assert p.returncode == expected and contains in p.stdout + p.stderr, rows[-1]
		return p.stdout
	for name, data in [('boundary.astra', SOURCE), ('bool14.h', HEADER), ('provider.c', PROVIDER), ('client.c', CLIENT)]:
		(work / name).write_text(data)
	source = work / 'boundary.astra'
	for cc in ('gcc', 'clang'):
		for name in ('provider', 'client'):
			run([cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-c', work / (name + '.c'), '-o', work / (cc + '-' + name + '.o')])
	for level in ('0', '1', '2'):
		obj = work / ('astra-O' + level + '.o')
		run([compiler, '-O' + level, '-c', source, '-o', obj])
		for cc in ('gcc', 'clang'):
			binary = work / (cc + '-O' + level)
			run([cc, obj, work / (cc + '-provider.o'), work / (cc + '-client.o'), '-o', binary])
			run([binary], contains='PASS: C99 _Bool')
			if level in ('0', '2'):
				run(['valgrind', '--vgdb=no', '--default-suppressions=no', '--leak-check=full', '--error-exitcode=99', binary], contains='ERROR SUMMARY: 0 errors')
	for stage in ('semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi'):
		run([compiler, '--dump-' + stage, source], contains='C99-bool')
	run([compiler, '--explain-semantics', source], contains='C99 _Bool copied i1/zeroext')
	run([compiler, '--tooling-index', source], contains='C99 _Bool copied i1/zeroext')
	llvm = run([compiler, '--dump-llvm', source], contains='zeroext i1')
	assert 'declare zeroext i1 @bool14_not(i1 zeroext)' in llvm
	assert 'call zeroext i1 @bool14_not(i1 zeroext' in llvm
	bad = work / 'invalid.astra'
	for text, reason in [
		(SOURCE.replace(',bool_abi="c99"', '', 1), 'foreign bool is unsupported'),
		(SOURCE.replace('"c99"', '"gboolean"', 1), 'bool_abi requires'),
		('[CImport(bool_abi="c99")] int unused(int value);', 'requires copied bool channels'),
		('[CExport(bool_abi="c99")] int unused(int value) { return value; }', 'requires copied bool channels'),
		('[CImport(bool_abi="c99")] bool pointer(borrowed bool* value);', "'borrowed' parameter"),
		('[CImport(bool_abi="c99",text_abi="utf8-i32")] bool alternate(borrowed string value);', 'without alternate transports'),
		('extern(C) bool legacy(bool value);', 'foreign bool is unsupported'),
		('export(C) bool legacy(bool value) { return value; }', 'foreign bool is unsupported'),
		('[CCode(bool_abi="c99")] extern(C) bool legacy(bool value);', 'unknown CCode metadata key'),
		('[GObjectImport(header="g.h",bool_abi="c99")] bool wrong(bool value);', 'unsupported GObjectImport argument'),
	]:
		bad.write_text(text)
		run([compiler, '--check', bad], expected=1, contains=reason)
	for flags in [('--target=x86_64-w64-windows-gnu',), ('--target=x86_64-none-elf', '--runtime=none')]:
		run([compiler, *flags, '-c', source, '-o', work / 'denied.o'], expected=1, contains='C99 bool')
	native = work / 'native.astra'
	native.write_text('bool predicate(int value) { return value > 0; }\nint main() { if (!predicate(42) || predicate(-1)) { return 1; } return 0; }\n')
	run([compiler, '-O2', native, '-o', work / 'native'])
	run([work / 'native'])
	deps = run(['readelf', '-d', work / 'native'])
	assert not any(name in deps for name in ('libgobject', 'libglib', 'libLLVM'))
	assert 'C99-bool' not in run([compiler, '--dump-nabi', native])
	run([compiler, '--check', source])
	receipt['status'] = 'PASS'
	(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	print(f'PASS: {len(rows)} independent GCC/Clang C99 bool, physical attribute, optionality and refusal commands; evidence {work}')


if __name__ == '__main__':
	main(*sys.argv[1:])
