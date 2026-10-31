#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exercise declaration-derived native scalar members through independent C ABIs."""
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
	work = Path(tempfile.mkdtemp(prefix='declared-scalars-', dir=output))
	source = Path(__file__).resolve().parent
	receipt = dict(scope='first C scalar bridge integration; remaining M16 channels/gates not qualified',
		compiler_sha256=sha(compiler), recipe_sha256=sha(Path(__file__)), checks=[], sources={})
	for path in [source / 'scalars.astra', source / 'scalars-client.c', ROOT / 'lib/runtime/interop/foreign-14.c']:
		receipt['sources'][str(path.relative_to(ROOT))] = sha(path)
	def save():
		(work / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')
	def run(command, expected=0, contains=''):
		assert sha(compiler) == receipt['compiler_sha256'], 'compiler changed during integration'
		result = subprocess.run(list(map(str, command)), cwd=work, capture_output=True, text=True,
			timeout=120, env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'))
		receipt['checks'].append(dict(command=list(map(str, command)), exit=result.returncode,
			expected_exit=expected, stdout=result.stdout, stderr=result.stderr))
		save()
		assert result.returncode == expected and contains in result.stdout + result.stderr, receipt['checks'][-1]
		return result.stdout
	flags = ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread']
	for lifetime in ['unique', 'shared']:
		case = work / lifetime; case.mkdir()
		text = (source / 'scalars.astra').read_text()
		if lifetime == 'shared':
			text = text.replace('class ScalarService', '[Shared]\nclass ScalarService')
		unit = case / 'service.astra'; unit.write_text(text)
		header = run([compiler, '--emit-class-header', unit], contains='declarations-v1')
		(case / 'scalar16.h').write_text(header)
		assert ('scalar16_acquire(' in header) == (lifetime == 'shared')
		assert 'factor;' not in header and 'flag_value;' not in header
		for stage in ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi']:
			run([compiler, '--dump-' + stage, unit], contains='declarations-v1')
		for level in '012':
			obj = case / ('native-O' + level + '.o')
			run([compiler, '-O' + level, '-c', unit, '-o', obj])
			for client_kind in ['independent', 'sdk']:
				binary = case / (client_kind + '-O' + level)
				selection = (['-DEXPECT_SHARED'] if lifetime == 'shared' else []) + (['-DUSE_SDK'] if client_kind == 'sdk' else [])
				run(['cc', *flags, *selection, '-I', case, '-Wl,--wrap=calloc', source / 'scalars-client.c', obj,
					ROOT / 'lib/runtime/interop/foreign-14.c', '-o', binary])
				run([binary], contains='PASS declaration-derived scalar native members')
				dependencies = run(['readelf', '-d', binary])
				assert not any(name in dependencies for name in ['libglib', 'libgobject', 'libLLVM'])
				if level in '02':
					run(['valgrind', '--vgdb=no', '--default-suppressions=no', '--leak-check=full',
						'--show-leak-kinds=definite,indirect,possible', '--errors-for-leak-kinds=definite,indirect,possible',
						'--error-exitcode=99', binary], contains='ERROR SUMMARY: 0 errors')
	receipt['status'] = 'SCALAR_C_INTEGRATION_PASS'
	save()
	print(json.dumps(dict(status=receipt['status'], commands=len(receipt['checks']), receipt=str(work / 'checks.json'))))


if __name__ == '__main__':
	main(*sys.argv[1:])
