#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent C out/inout/status producer with finite borrowed int* transport."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main(compiler_arg, output_arg, policy='CImport'):
	assert policy in ('CImport', 'GObjectImport')
	compiler = Path(compiler_arg).resolve()
	output = Path(output_arg).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='c-pointers-', dir=output))
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
	provider = work / 'provider.c'
	provider.write_text('#include <stdint.h>\nint32_t out14(int32_t mode, int32_t *out) {\n'
		'\tif (!out) return (int32_t)UINT32_C(0x80004003);\n'
		'\tif (mode == 2) { *out += 1; return 0; }\n'
		'\t*out = 0;\n\tif (mode == 1) return (int32_t)UINT32_C(0x80070057);\n'
		'\t*out = mode == 3 ? 7 : 42; return mode == 3 ? 1 : 0;\n}\n')
	run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-c', provider, '-o', work / 'provider.o'])
	source = work / 'out.astra'
	healthy = ('[CImport(name="out14", pointer_abi="i32-noescape")] int call(int mode, borrowed int* out);\n'
		'int main() {\n\tint value = 99;\n'
		'\tif (call(0, &value) != 0 || value != 42) { return 1; }\n'
		'\tif (call(2, &value) != 0 || value != 43) { return 2; }\n'
		'\tif (call(1, &value) != -2147024809 || value != 0) { return 3; }\n'
		'\tif (call(3, &value) != 1 || value != 7) { return 4; }\n'
		'\tif (call(0, null) != -2147467261) { return 5; }\n\treturn 0;\n}\n')
	if policy == 'GObjectImport':
		healthy = healthy.replace('[CImport(', '[GObjectImport(header="provider.h", ')
		(work / 'provider.h').write_text('#include <stdint.h>\nint32_t out14(int32_t, int32_t *);\n')
	source.write_text(healthy)
	for level in ('0', '1', '2'):
		binary = work / ('out-O' + level)
		run([compiler, '-O' + level, source, '--link-object', work / 'provider.o', '-o', binary])
		run([binary])
		if level == '2':
			run(['valgrind', '--vgdb=no', '--default-suppressions=no', '--leak-check=full', '--error-exitcode=99', binary], contains='ERROR SUMMARY: 0 errors')
	bad = work / 'invalid.astra'
	for text, reason in [
		(healthy.replace(', pointer_abi="i32-noescape"', ''), "'borrowed' parameter"),
		(healthy.replace('borrowed int*', 'int*'), 'explicit borrowed int*'),
		(healthy.replace('i32-noescape', 'any-pointer'), 'pointer_abi requires i32-noescape'),
		(healthy.replace('borrowed int*', 'borrowed f64*'), "'borrowed' parameter"),
		(healthy.replace('pointer_abi="i32-noescape"', 'pointer_abi="i32-noescape", text_abi="utf8-i32"'), 'without alternate transports'),
		(healthy.replace('int call(', 'void* call('), 'no pointer-like result'),
		(healthy.replace('borrowed int* out', 'int out'), 'requires borrowed int*'),
	]:
		bad.write_text(text)
		run([compiler, '--check', bad], expected=1, contains=reason)
	for stage in ('semantics', 'core', 'cfg', 'ssa', 'cabi'):
		run([compiler, '--dump-' + stage, source], contains='i32-noescape')
	if policy == 'GObjectImport':
		for stage in ('semantics', 'core', 'cfg', 'ssa', 'cabi', 'nabi'):
			run([compiler, '--dump-' + stage, source], contains='GObjectImport')
		for text, reason in [
			(healthy.replace('header="provider.h", ', ''), 'explicit bridge/SDK header'),
			(healthy.replace('header="provider.h", ', 'header="", '), 'metadata must be nonempty'),
			(healthy.replace('borrowed int* out);', 'borrowed int* out) { return 0; }'), 'foreign declarations have no body'),
			(healthy.replace('GObjectImport', 'GObjectExport'), 'unsupported declaration attribute'),
		]:
			bad.write_text(text)
			run([compiler, '--check', bad], expected=1, contains=reason)
		run([compiler, '--target=x86_64-w64-windows-gnu', '-c', source, '-o', work / 'denied.o'], expected=1, contains='GObjectImport')
	run([compiler, '--check', source])
	receipt['status'] = 'PASS'
	(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	print(f'PASS: {len(rows)} independent C int* out/inout/status and refusal commands; evidence {work}')


if __name__ == '__main__':
	main(*sys.argv[1:])
