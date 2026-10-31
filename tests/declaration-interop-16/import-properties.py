#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent and SDK C callers for typed C Class property imports."""
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
	work = Path(tempfile.mkdtemp(prefix='declared-import-properties-', dir=output))
	source = Path(__file__).resolve().parent
	receipt = dict(scope='typed C Class property imports with bounded publication and provisional owner retirement; full M16 remains pending',
		compiler_sha256=sha(compiler), checks=[], sources={})
	for path in [Path(__file__).resolve(), source / 'import-properties.astra', source / 'import-properties-provider.c']:
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
		text = (source / 'import-properties.astra').read_text()
		if lifetime == 'shared':
			text = text.replace('name="property_provider16",profile="declarations-v1",lifetime="unique"', 'name="property_provider16",profile="declarations-v1",lifetime="shared"')
		unit = case / 'service.astra'; unit.write_text(text)
		header = run([compiler, '--emit-class-header', unit], contains='declarations-v1'); (case / 'imports16.h').write_text(header)
		forwarder = case / 'forwarder.c'; forwarder.write_text(run([compiler, '--emit-class-source', unit], contains='astra_foreign16_import_property_provider16_set_reading'))
		types = {}
		for original, macro in [('Reading', 'READING'), ('Pair<f64>', 'PAIR')]:
			match = re.search(r'/\* POD ' + re.escape(original) + r':[^\n]*\*/\ntypedef struct (astra_record_[0-9a-f]{64})', header)
			assert match, original
			types['RECORD_' + macro] = match[1]
		definitions = ['-D' + key + '=' + value for key, value in types.items()]
		probe = case / 'header.cc'; probe.write_text('#include "imports16.h"\nstatic_assert(sizeof(' + types['RECORD_READING'] + ') == 24);\n')
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
						*selection, *definitions, '-I', case, source / 'import-properties-provider.c', obj, shim, '-o', binary])
					run([binary], contains='PASS typed C Class imported properties')
					if level in '02':
						run(['valgrind', '--vgdb=no', '--default-suppressions=no', '--leak-check=full',
							'--show-leak-kinds=definite,indirect,possible', '--errors-for-leak-kinds=definite,indirect,possible',
							'--error-exitcode=99', binary], contains='ERROR SUMMARY: 0 errors')

	base = (source / 'import-properties.astra').read_text()
	negatives = {
		'getter-body': base.replace('get; set(i32 input);', 'get { return 1; } set(i32 input);'),
		'setter-body': base.replace('get; set(i32 input);', 'get; set(i32 input) {}'),
		'setter-type': base.replace('set(i32 input);', 'set(f64 input);'),
		'nominal-setter-type': base.replace('set(Reading input);', 'set(Pair<f64> input);'),
		'setter-only': base.replace('get; set(i32 input);', 'set(i32 input);'),
		'read-only-assignment': base.replace('get; set(i32 input);', 'get;'),
		'getter-unhandled-error': base.replace('int doubled(borrowed Provider provider) throws Fault', 'int doubled(borrowed Provider provider)'),
		'setter-unhandled-error': base + '\nvoid unchecked(borrowed Provider provider){provider.total=4;}\n',
		'owned-scalar-property': base.replace('property i32 total', 'property owned i32 total'),
		'borrowed-owned-result': base.replace('property owned u8[] bytes', 'property u8[] bytes'),
		'setter-missing-move': base.replace('provider.child=move child', 'provider.child=child'),
		'setter-use-after-move': base.replace('provider.child=move child;', 'provider.child=move child;var wrong=child.code;'),
		'unknown-property-channel': base.replace('parameter="result",encoding="utf8-counted"', 'parameter="absent",encoding="utf8-counted"'),
		'property-name-collision': base.replace('property f64 precise', 'property f64 single'),
		'foreign-name-collision': base.replace('name="amount"', 'name="unsigned32"'),
	}

	for name, text in negatives.items():
		unit = work / (name + '.astra'); unit.write_text(text)
		stage = 'cfg' if name == 'setter-use-after-move' else 'semantics'
		if stage == 'cfg':
			run([compiler, '--dump-semantics', unit], contains='declarations-v1')
		run([compiler, '--dump-' + stage, unit], contains='error:', expected=1)
	receipt['status'] = 'TYPED_PROPERTY_IMPORT_C_INTEGRATION_PASS'
	(work / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')
	print(json.dumps(dict(status=receipt['status'], commands=len(receipt['checks']), receipt=str(work / 'checks.json'))))


if __name__ == '__main__':
	main(*sys.argv[1:])
