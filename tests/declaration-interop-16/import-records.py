#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent and SDK C callers for POD C Class imports."""
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
	work = Path(tempfile.mkdtemp(prefix='declared-import-records-', dir=output))
	source = Path(__file__).resolve().parent
	receipt = dict(scope='POD C Class imports with bounded publication and provisional owner retirement; full M16 remains pending',
		compiler_sha256=sha(compiler), checks=[], sources={})
	for path in [Path(__file__).resolve(), source / 'import-records.astra', source / 'import-records-provider.c']:
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
		text = (source / 'import-records.astra').read_text()
		if lifetime == 'shared':
			text = text.replace('lifetime="unique"', 'lifetime="shared"')
		unit = case / 'service.astra'; unit.write_text(text)
		header = run([compiler, '--emit-class-header', unit], contains='declarations-v1'); (case / 'imports16.h').write_text(header)
		forwarder = case / 'forwarder.c'; forwarder.write_text(run([compiler, '--emit-class-source', unit], contains='astra_foreign16_import_pod_provider16_adjust'))
		types = {}
		for original, macro in [('MixedSample', 'MIXED'), ('PackedScalars', 'PACKED'), ('Duo<f64>', 'DUO'), ('Single', 'SINGLE')]:
			match = re.search(r'/\* POD ' + re.escape(original) + r':[^\n]*\*/\ntypedef struct (astra_record_[0-9a-f]{64})', header)
			assert match, original
			types['RECORD_' + macro] = match[1]
		definitions = ['-D' + key + '=' + value for key, value in types.items()]
		probe = case / 'header.cc'; probe.write_text('#include "imports16.h"\nstatic_assert(sizeof(' + types['RECORD_MIXED'] + ') == 40);\n')
		for driver in ['c++', 'clang++']:
			run([driver, '-std=c++17', '-Wall', '-Wextra', '-Werror', '-pedantic', '-fsyntax-only', probe])
		for stage in ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi']:
			run([compiler, '--dump-' + stage, unit], contains='declarations-v1')
		for level in '012':
			obj = case / ('native-O' + level + '.o')
			run([compiler, '-O' + level, '-c', unit, '-o', obj])
			for shim_level in ('1' if level == '1' else '02'):
				shim = case / ('forwarder-O' + shim_level + '.o')
				run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-O' + shim_level, '-c', forwarder, '-o', shim])
				for client_kind in ['independent', 'sdk']:
					binary = case / (client_kind + '-O' + level + '-shim-O' + shim_level)
					selection = (['-DEXPECT_SHARED'] if lifetime == 'shared' else []) + (['-DUSE_SDK'] if client_kind == 'sdk' else [])
					run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread',
						*selection, *definitions, '-I', case, source / 'import-records-provider.c', obj, shim, '-o', binary])
					run([binary], contains='PASS typed C Class imports')
					if level in '02':
						run(['valgrind', '--vgdb=no', '--default-suppressions=no', '--leak-check=full',
							'--show-leak-kinds=definite,indirect,possible', '--errors-for-leak-kinds=definite,indirect,possible',
							'--error-exitcode=99', binary], contains='ERROR SUMMARY: 0 errors')

	base = (source / 'import-records.astra').read_text()
	negatives = {
		'private-pod': base.replace('struct MixedSample { int count;', 'struct MixedSample { private int count;'),
		'nested-pod': base.replace('struct Single { f64 value; }', 'struct Single { MixedSample value; }'),
		'borrowed-pod': base.replace('MixedSample adjust(MixedSample input', 'MixedSample adjust(borrowed MixedSample input'),
		'owned-pod-result': base.replace('MixedSample adjust(', 'owned MixedSample adjust('),
		'pointer-field': base.replace('struct Single { f64 value; }', 'struct Single { int* value; }'),
		'wrong-result-direction': base.replace('Single one(Single input)', '[ForeignChannel(parameter="result",direction="in")]Single one(Single input)'),
	}
	for name, text in negatives.items():
		unit = work / (name + '.astra'); unit.write_text(text)
		run([compiler, '--dump-semantics', unit], contains='error:', expected=1)
	receipt['status'] = 'TYPED_POD_IMPORT_C_INTEGRATION_PASS'
	(work / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')
	print(json.dumps(dict(status=receipt['status'], commands=len(receipt['checks']), receipt=str(work / 'checks.json'))))


if __name__ == '__main__':
	main(*sys.argv[1:])
