#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent and SDK C callers for typed scalar reference channels and explicit produced counts."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()


def main(compiler_arg, output_arg):
	compiler, output = Path(compiler_arg).resolve(), Path(output_arg).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='declared-scalar-outs-', dir=output))
	source = Path(__file__).resolve().parent
	receipt = dict(scope='typed scalar references, explicit produced counts and provisional owner cleanup; full M16 remains pending',
		compiler_sha256=sha(compiler), checks=[], sources={})
	for path in [Path(__file__).resolve(), source / 'scalar-outs.astra', source / 'scalar-outs-client.c', ROOT / 'lib/runtime/interop/foreign-14.c']:
		receipt['sources'][str(path.relative_to(ROOT))] = sha(path)
	def run(command, contains='', expected=0):
		assert sha(compiler) == receipt['compiler_sha256'], 'compiler changed during integration'
		result = subprocess.run(list(map(str, command)), cwd=work, capture_output=True, text=True,
			timeout=120, env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'))
		receipt['checks'].append(dict(command=list(map(str, command)), exit=result.returncode, expected_exit=expected,
			stdout=result.stdout, stderr=result.stderr))
		(work / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')
		assert result.returncode == expected and contains in result.stdout + result.stderr, receipt['checks'][-1]
		return result.stdout
	for lifetime in ['unique', 'shared']:
		case = work / lifetime; case.mkdir()
		text = (source / 'scalar-outs.astra').read_text()
		if lifetime == 'shared':
			text = text.replace('class Outputs', '[Shared]\nclass Outputs').replace('class BufferCtor', '[Shared]\nclass BufferCtor').replace('class Child', '[Shared]\nclass Child')
		unit = case / 'service.astra'; unit.write_text(text)
		(case / 'scalar-outs16.h').write_text(run([compiler, '--emit-class-header', unit], contains='declarations-v1'))
		for stage in ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi']:
			run([compiler, '--dump-' + stage, unit], contains='declarations-v1')
		for level in '012':
			obj = case / ('native-O' + level + '.o')
			run([compiler, '-O' + level, '-c', unit, '-o', obj])
			for client_kind in ['independent', 'sdk']:
				binary = case / (client_kind + '-O' + level)
				selection = (['-DEXPECT_SHARED'] if lifetime == 'shared' else []) + (['-DUSE_SDK'] if client_kind == 'sdk' else [])
				run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread',
					*selection, '-I', case, '-Wl,--wrap=calloc', source / 'scalar-outs-client.c', obj,
					ROOT / 'lib/runtime/interop/foreign-14.c', '-o', binary])
				run([binary], contains='PASS typed scalar outputs')
				if level in '02':
					run(['valgrind', '--vgdb=no', '--default-suppressions=no', '--leak-check=full',
						'--show-leak-kinds=definite,indirect,possible', '--errors-for-leak-kinds=definite,indirect,possible',
						'--error-exitcode=99', binary], contains='ERROR SUMMARY: 0 errors')
	for name, old, new, diagnostic in [
		('nullable-place', 'parameter="single",direction="out"', 'parameter="single",direction="out",nullable="true"', 'mandatory typed value place'),
		('unmanaged-place', 'borrowed f64* double_value', 'f64* double_value', 'channel lowering is not implemented for this native type'),
		('input-produced', '[ForeignChannel(parameter="produced",direction="out")]', '[ForeignChannel(parameter="produced",direction="in")]', 'channel/count relationships'),
		('unsigned-produced', 'borrowed int* produced', 'borrowed u32* produced', 'channel/count relationships'),
		('escaped-place', 'class Outputs {', 'class Outputs {[Foreign]void leak(borrowed int* value){int* alias=value;}', 'cannot be stored, returned'),
	]:
		unit = work / (name + '.astra'); unit.write_text((source / 'scalar-outs.astra').read_text().replace(old,new))
		run([compiler,'--dump-llvm',unit],contains=diagnostic,expected=1)
	receipt['status'] = 'SCALAR_REFERENCE_OUTPUT_C_INTEGRATION_PASS'
	(work / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')
	print(json.dumps(dict(status=receipt['status'], commands=len(receipt['checks']), receipt=str(work / 'checks.json'))))


if __name__ == '__main__':
	main(*sys.argv[1:])
