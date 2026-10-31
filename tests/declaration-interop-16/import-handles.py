#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent and SDK C callers for typed object C Class imports."""
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
	work = Path(tempfile.mkdtemp(prefix='declared-import-handles-', dir=output))
	source = Path(__file__).resolve().parent
	receipt = dict(scope='typed object C Class imports with bounded publication and provisional owner retirement; full M16 remains pending',
		compiler_sha256=sha(compiler), checks=[], sources={})
	for path in [Path(__file__).resolve(), source / 'import-handles.astra', source / 'import-handles-provider.c']:
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
		text = (source / 'import-handles.astra').read_text()
		if lifetime == 'shared':
			text = text.replace('lifetime="unique"', 'lifetime="shared"', 1)
		unit = case / 'service.astra'; unit.write_text(text)
		(case / 'imports16.h').write_text(run([compiler, '--emit-class-header', unit], contains='declarations-v1'))
		for stage in ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi']:
			run([compiler, '--dump-' + stage, unit], contains='declarations-v1')
		for level in '012':
			obj = case / ('native-O' + level + '.o')
			run([compiler, '-O' + level, '-c', unit, '-o', obj])
			for client_kind in ['independent', 'sdk']:
				binary = case / (client_kind + '-O' + level)
				selection = (['-DEXPECT_SHARED'] if lifetime == 'shared' else []) + (['-DUSE_SDK'] if client_kind == 'sdk' else [])
				run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread',
					*selection, '-I', case, source / 'import-handles-provider.c', obj, '-o', binary])
				run([binary], contains='PASS typed C Class imports')
				if level in '02':
					run(['valgrind', '--vgdb=no', '--default-suppressions=no', '--leak-check=full',
						'--show-leak-kinds=definite,indirect,possible', '--errors-for-leak-kinds=definite,indirect,possible',
						'--error-exitcode=99', binary], contains='ERROR SUMMARY: 0 errors')
	base = (source / 'import-handles.astra').read_text()
	negatives = {
		'wrong-nominal-input': base.replace('combine(borrowed Child input', 'combine(borrowed Provider input'),
		'unowned-object-result': base.replace('owned Child make(', 'Child make('),
		'borrow-transfer-conflict': base.replace('parameter="input",nullable="true"', 'parameter="input",nullable="true",transfer="full"'),
		'nullable-constructor': base.replace('init(int value) throws Fault;', '[ForeignChannel(parameter="result",nullable="true")]init(int value) throws Fault;', 1),
		'negative-null-status': base.replace('null_status="1"', 'null_status="-1"'),
		'null-status-mandatory-result': base.replace('parameter="result",nullable="true"', 'parameter="result",nullable="false"'),
		'borrow-escape': base + '\nowned Child escape(borrowed Child input){return move input;}\n',
	}
	for name, text in negatives.items():
		unit = work / (name + '.astra'); unit.write_text(text)
		run([compiler, '--dump-semantics', unit], contains='error:', expected=1)
	receipt['status'] = 'TYPED_HANDLE_IMPORT_C_INTEGRATION_PASS'
	(work / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')
	print(json.dumps(dict(status=receipt['status'], commands=len(receipt['checks']), receipt=str(work / 'checks.json'))))


if __name__ == '__main__':
	main(*sys.argv[1:])
