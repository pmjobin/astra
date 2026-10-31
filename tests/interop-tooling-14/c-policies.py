#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Typed C policies use checked C ABI paths and independent C producers/clients."""
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
	work = Path(tempfile.mkdtemp(prefix='c-policies-', dir=output))
	rows = []
	receipt = {'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(), 'checks': rows}
	def run(command, expected=0, contains=''):
		p = subprocess.run(list(map(str, command)), capture_output=True, text=True, timeout=90,
			cwd=work, env=dict(os.environ, CCACHE_DISABLE='1'))
		rows.append({'command': list(map(str, command)), 'exit': p.returncode,
			'expected_exit': expected, 'stdout': p.stdout, 'stderr': p.stderr})
		(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
		assert p.returncode == expected and contains in p.stdout + p.stderr, rows[-1]
		return p.stdout
	header = work / 'contract.h'
	header.write_text('''#include <stdint.h>
#include <stddef.h>
typedef struct { int64_t count; double total; int64_t tag; } Record14;
_Static_assert(sizeof(Record14) == 24, "selected LP64 record extent");
_Static_assert(_Alignof(Record14) == 8, "selected LP64 record alignment");
_Static_assert(offsetof(Record14, total) == 8 && offsetof(Record14, tag) == 16, "record offsets");
int32_t c_input14(int32_t value);
Record14 c_record14(Record14 value);
int32_t astra_output14(int32_t value);
Record14 astra_record14(Record14 value);
''')
	provider = work / 'provider.c'
	provider.write_text('''#include "contract.h"
int32_t c_input14(int32_t value) { return value + 2; }
Record14 c_record14(Record14 value) {
	value.count += 1; value.total += 2.5; value.tag += 3; return value;
}
''')
	client = work / 'client.c'
	client.write_text('''#include "contract.h"
int main(void) {
	if (astra_output14(39) != 42) { return 1; }
	Record14 input = {40, 1.25, 7};
	Record14 result = astra_record14(input);
	if (result.count != 42 || result.total != 3.75 || result.tag != 10) { return 2; }
	if (input.count != 40 || input.total != 1.25 || input.tag != 7) { return 3; }
	return 0;
}
''')
	cflags = ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror']
	run(['cc', *cflags, '-c', provider, '-o', work / 'provider.o'])
	run(['cc', *cflags, '-c', client, '-o', work / 'client.o'])
	source = work / 'boundary.astra'
	source.write_text('''struct Record14 { i64 count; f64 total; i64 tag; }
[CImport(name="c_input14", header="contract.h")]
int input(int value);
[CImport(name="c_record14", header="contract.h", record_abi="value-lp64")]
Record14 incoming(Record14 value);
[CExport(name="astra_output14")]
int output(int value) { return input(value) + 1; }
[CExport(name="astra_record14", record_abi="value-lp64")]
Record14 outgoing(Record14 value) {
	Record14 result = incoming(value);
	result.count = result.count + 1;
	return result;
}
''')
	legacy = work / 'legacy.astra'
	legacy.write_text(source.read_text().replace('[CImport(name="c_input14", header="contract.h")]',
		'[CCode(cname="c_input14", cheader_filename="contract.h")] extern(C)')
		.replace('[CImport(name="c_record14", header="contract.h", record_abi="value-lp64")]',
		'[CCode(cname="c_record14", cheader_filename="contract.h", record_abi="value-lp64")] extern(C)')
		.replace('[CExport(name="astra_output14")]', 'export(C)').replace('int output(', 'int astra_output14(')
		.replace('[CExport(name="astra_record14", record_abi="value-lp64")]', '[CCode(record_abi="value-lp64")] export(C)')
		.replace('Record14 outgoing(', 'Record14 astra_record14('))
	# The new declarations normalize to the same existing checked/IR identities.
	# Different native names on the exported source functions are intentional;
	# compare import signatures and C ABI symbols, then execute actual clients.
	for mode in ['--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']:
		dump = run([compiler, mode, source])
		assert dump
		if mode == '--dump-syntax':
			assert '(policy CImport)' in dump and '(policy CExport)' in dump
		if mode == '--dump-cabi':
			assert all(name in dump for name in ['c_input14', 'c_record14', 'astra_output14', 'astra_record14'])
	for level in ('0', '1', '2'):
		obj = work / ('astra-O' + level + '.o')
		run([compiler, '-O' + level, '-c', source, '-o', obj])
		binary = work / ('client-O' + level)
		run(['cc', work / 'client.o', work / 'provider.o', obj, '-o', binary])
		run([binary])
		assert not any(name in run(['readelf', '-d', binary]) for name in ['libglib', 'libgobject', 'libLLVM'])
		symbols = run(['nm', '-g', '--defined-only', obj])
		assert ' astra_output14' in symbols and ' astra_record14' in symbols
		# Existing legacy spellings continue to execute the same foreign contract.
		run([compiler, '-O' + level, '-c', legacy, '-o', work / 'legacy.o'])
		run(['cc', work / 'client.o', work / 'provider.o', work / 'legacy.o', '-o', work / 'legacy-client'])
		run([work / 'legacy-client'])
	bare = work / 'bare.astra'
	bare.write_text('[CImport] int abs(int value);\n[CExport()] int visible(int value) { return abs(value); }\nint main() { return visible(-42) - 42; }\n')
	run([compiler, bare, '-o', work / 'bare'])
	run([work / 'bare'])
	run([compiler, '--explain-semantics', source], contains='CImport')
	formatted = run([compiler, '--format', source])
	(work / 'formatted.astra').write_text(formatted)
	run([compiler, '--check', work / 'formatted.astra'])
	assert run([compiler, '--format', work / 'formatted.astra']) == formatted
	bad = work / 'invalid.astra'
	for text, reason in [
		('[CImport] int f() { return 0; }', 'foreign declarations have no body'),
		('[CExport] int f();', 'requires a definition'),
		('[CImport] extern(C) int f();', 'cannot combine'),
		('[CImport][CExport] int f();', 'cannot combine'),
		('[CImport(name="a", name="b")] int f();', 'duplicate'),
		('[CExport(header="x.h")] int f() { return 0; }', 'unsupported CExport argument'),
		('[CImport(name="bad-name")] int f();', 'portable C identifier'),
		('[CExport(name="astra.private")] int f() { return 0; }', 'portable C identifier'),
		('[CExport(record_abi="natural-lp64")] int f() { return 0; }', 'requires value-lp64'),
		('[CImport(agile="yes")] int f();', 'unsupported CImport argument'),
		('[CImport] async int f();', 'async foreign'),
		('[CExport] T f<T>(T value) { return value; }', 'generic extern(C)'),
		('[CImport] bool f(bool value);', 'foreign bool'),
		('[CExport(name="same")] int a() { return 0; }\n[CExport(name="same")] int b() { return 0; }', 'declared more than once'),
		('class X { [CExport] int f() { return 0; } }', 'expected'),
	]:
		bad.write_text(text)
		run([compiler, '--check', bad], expected=1, contains=reason)
	run([compiler, '--check', source])
	receipt['status'] = 'PASS'
	(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	print(f'PASS: {len(rows)} typed C policy, independent C client and refusal commands; evidence {work}')


if __name__ == '__main__':
	main(*sys.argv[1:])
