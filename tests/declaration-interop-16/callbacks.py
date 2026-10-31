#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exercise declaration-derived typed callbacks with exact user data through independent C ABIs."""
from pathlib import Path
import hashlib
import json
import os
import re
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
	work = Path(tempfile.mkdtemp(prefix='declared-callbacks-', dir=output))
	source = Path(__file__).resolve().parent
	receipt = dict(scope='typed synchronous C callbacks; remaining M16 personalities/gates not qualified',
		compiler_sha256=sha(compiler), recipe_sha256=sha(Path(__file__)), checks=[], sources={})
	for path in [source / 'callbacks.astra', source / 'callbacks-client.c', ROOT / 'lib/runtime/interop/foreign-14.c']:
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
		text = (source / 'callbacks.astra').read_text()
		if lifetime == 'shared':
			text = text.replace('class Processor', '[Shared]\nclass Processor')
		unit = case / 'service.astra'; unit.write_text(text)
		header = run([compiler, '--emit-class-header', unit], contains='declarations-v1')
		(case / 'callbacks16.h').write_text(header)
		match=re.search(r'/\* POD Reading:[^\n]*\*/\ntypedef struct (astra_record_[0-9a-f]{64})',header);assert match
		forwarder=case/'forwarder.c';forwarder.write_text(run([compiler,'--emit-class-source',unit]))
		shim=case/'forwarder.o';run(['cc',*flags,'-O2','-c',forwarder,'-o',shim])
		assert ('callbacks16_acquire(' in header) == (lifetime == 'shared')
		assert 'callback_' in header and 'argument1_data' in header
		cpp=case/'header.cc';cpp.write_text('#include \"callbacks16.h\"\n')
		for driver in ['c++','clang++']:
			run([driver,'-std=c++17','-Wall','-Wextra','-Werror','-pedantic','-fsyntax-only',cpp])
		for stage in ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi']:
			run([compiler, '--dump-' + stage, unit], contains='declarations-v1')
		for level in '012':
			obj = case / ('native-O' + level + '.o')
			run([compiler, '-O' + level, '-c', unit, '-o', obj])
			for client_kind in ['independent', 'sdk']:
				binary = case / (client_kind + '-O' + level)
				selection = (['-DEXPECT_SHARED'] if lifetime == 'shared' else []) + (['-DUSE_SDK'] if client_kind == 'sdk' else [])
				run(['cc', *flags, *selection, '-DRECORD_READING='+match[1], '-I', case, source / 'callbacks-client.c', obj, shim,
					ROOT / 'lib/runtime/interop/foreign-14.c', '-o', binary])
				run([binary], contains='PASS typed C callbacks with exact userdata and native algorithms')
				dependencies = run(['readelf', '-d', binary])
				assert not any(name in dependencies for name in ['libglib', 'libgobject', 'libLLVM'])
				if level in '02':
					run(['valgrind', '--vgdb=no', '--default-suppressions=no', '--leak-check=full',
						'--show-leak-kinds=definite,indirect,possible', '--errors-for-leak-kinds=definite,indirect,possible',
						'--error-exitcode=99', binary], contains='ERROR SUMMARY: 0 errors')
	receipt['status'] = 'CALLBACK_C_EXPORT_INTEGRATION_PASS'
	save()
	print(json.dumps(dict(status=receipt['status'], commands=len(receipt['checks']), receipt=str(work / 'checks.json'))))


if __name__ == '__main__':
	main(*sys.argv[1:])
