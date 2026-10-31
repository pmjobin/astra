#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independently compiled target-C POD values forwarding into native Astra bodies."""
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
	work = Path(tempfile.mkdtemp(prefix='declared-records-', dir=output))
	source = Path(__file__).resolve().parent
	receipt = dict(scope='scalar POD C value bridges; full M16 remains pending', compiler_sha256=sha(compiler), checks=[], products={}, sources={})
	for path in [Path(__file__).resolve(), source / 'records.astra', source / 'records-client.c', ROOT / 'lib/runtime/interop/foreign-14.c']:
		receipt['sources'][str(path.relative_to(ROOT))] = sha(path)
	def save():
		(work / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')
	def run(command, contains=''):
		assert sha(compiler) == receipt['compiler_sha256'], 'compiler changed during integration'
		result = subprocess.run(list(map(str, command)), cwd=work, capture_output=True, text=True,
			timeout=120, env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'))
		receipt['checks'].append(dict(command=list(map(str, command)), exit=result.returncode, stdout=result.stdout, stderr=result.stderr))
		save()
		assert result.returncode == 0 and contains in result.stdout + result.stderr, receipt['checks'][-1]
		return result.stdout
	flags = ['-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread']
	for lifetime in ['unique', 'shared']:
		case = work / lifetime; case.mkdir()
		text = (source / 'records.astra').read_text()
		if lifetime == 'shared':
			text = text.replace('class RecordService', '[Shared]\nclass RecordService')
		unit = case / 'service.astra'; unit.write_text(text)
		header = run([compiler, '--emit-class-header', unit], contains='declarations-v1'); (case / 'record16.h').write_text(header)
		forwarder = case / 'record-source.c'; forwarder.write_text(run([compiler, '--emit-class-source', unit], contains='Mechanical target-C record forwarding'))
		types = {}
		for original, macro in [('MixedSample', 'MIXED'), ('PackedScalars', 'PACKED'), ('Duo<f64>', 'DUO'), ('Single', 'SINGLE')]:
			match = re.search(r'/\* POD ' + re.escape(original) + r':[^\n]*\*/\ntypedef struct (astra_record_[0-9a-f]{64})', header)
			assert match, original
			types['RECORD_' + macro] = match[1]
		definitions = ['-D' + key + '=' + value for key, value in types.items()]
		probe = case / 'header-oracle.cc'; probe.write_text('#include "record16.h"\nstatic_assert(sizeof(' + types['RECORD_MIXED'] + ') == 40);\n')
		for driver in ['c++', 'clang++']:
			run([driver, '-std=c++17', '-Wall', '-Wextra', '-Werror', '-pedantic', '-fsyntax-only', probe])
		for stage in ['semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi']:
			run([compiler, '--dump-' + stage, unit], contains='declarations-v1')
		for level in '012':
			obj = case / ('native-O' + level + '.o'); run([compiler, '-O' + level, '-c', unit, '-o', obj])
			native_symbols = run(['nm', '--defined-only', obj]); assert 'astra_foreign16_record16_adjust' in native_symbols
			assert not re.search(r'\bT record16_adjust$', native_symbols, re.M)
			for shim_level in ('1' if level == '1' else '02'):
				shim = case / ('forwarder-O' + shim_level + '.o')
				run(['cc', *flags, '-O' + shim_level, '-c', forwarder, '-o', shim])
				shim_symbols = run(['nm', '--defined-only', shim]); assert re.search(r'\bT record16_adjust$', shim_symbols, re.M)
				assert not re.search(r'\bT astra\.', shim_symbols)
				for client_kind in ['independent', 'sdk']:
					binary = case / (client_kind + '-native-O' + level + '-forwarder-O' + shim_level)
					selection = (['-DEXPECT_SHARED'] if lifetime == 'shared' else []) + (['-DUSE_SDK', *definitions] if client_kind == 'sdk' else [])
					driver = 'clang' if client_kind == 'independent' else 'cc'
					run([driver, *flags, '-O2', *selection, '-I', case, source / 'records-client.c', obj, shim, ROOT / 'lib/runtime/interop/foreign-14.c', '-o', binary])
					run([binary], contains='PASS declaration-derived mixed POD values')
					receipt['products'][str(binary.relative_to(work))] = sha(binary)
					if level in '02' and shim_level == '2':
						run(['valgrind', '--vgdb=no', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=definite,indirect,possible',
							'--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', binary], contains='ERROR SUMMARY: 0 errors')
	receipt['status'] = 'SCALAR_POD_C_INTEGRATION_PASS'; save()
	print(json.dumps(dict(status=receipt['status'], commands=len(receipt['checks']), receipt=str(work / 'checks.json'))))


if __name__ == '__main__':
	main(*sys.argv[1:])
