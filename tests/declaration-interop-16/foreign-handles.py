#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent and SDK C callers for native Class exports of foreign handles."""
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
	work = Path(tempfile.mkdtemp(prefix='declared-foreign-handles-', dir=output))
	source = Path(__file__).resolve().parent
	receipt = dict(scope='native Class exports of foreign handles with bounded publication and provisional owner retirement; full M16 remains pending',
		compiler_sha256=sha(compiler), checks=[], sources={})
	for path in [Path(__file__).resolve(), source / 'foreign-handles.astra', source / 'foreign-handles-client.c', ROOT / 'lib/runtime/interop/foreign-14.c']:
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
	for lifetime, child_lifetime in [('unique','unique'),('shared','unique'),('unique','shared'),('shared','shared')]:
		case = work / (lifetime + '-' + child_lifetime); case.mkdir()
		text = (source / 'foreign-handles.astra').read_text()
		if lifetime == 'shared':
			text = text.replace('class Container', '[Shared]\nclass Container')
		if child_lifetime == 'shared':
			text = text.replace('lifetime="unique"', 'lifetime="shared"')
		unit = case / 'service.astra'; unit.write_text(text)
		(case / 'foreign16.h').write_text(run([compiler, '--emit-class-header', unit], contains='declarations-v1'))
		for stage in ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi']:
			run([compiler, '--dump-' + stage, unit], contains='declarations-v1')
		for level in '012':
			obj = case / ('native-O' + level + '.o')
			run([compiler, '-O' + level, '-c', unit, '-o', obj])
			for client_kind in ['independent', 'sdk']:
				binary = case / (client_kind + '-O' + level)
				selection = (['-DEXPECT_SHARED'] if lifetime == 'shared' else []) + (['-DITEM_SHARED'] if child_lifetime == 'shared' else []) + (['-DUSE_SDK'] if client_kind == 'sdk' else [])
				run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread',
					*selection, '-I', case, '-Wl,--wrap=calloc', source / 'foreign-handles-client.c', obj, ROOT / 'lib/runtime/interop/foreign-14.c', '-o', binary])
				run([binary], contains='PASS native Class exports')
				if level in '02':
					run(['valgrind', '--vgdb=no', '--default-suppressions=no', '--leak-check=full',
						'--show-leak-kinds=definite,indirect,possible', '--errors-for-leak-kinds=definite,indirect,possible',
						'--error-exitcode=99', binary], contains='ERROR SUMMARY: 0 errors')
	base = (source / 'foreign-handles.astra').read_text()
	negatives = {
		'unowned-result': base.replace('owned Item relay(', 'Item relay('),
		'borrowed-consumption': base.replace('int burn(owned Item input', 'int burn(borrowed Item input'),
		'raw-pointer-object': base.replace('observe(borrowed Item input', 'observe(borrowed int* input'),
		'null-status-mandatory-result': base.replace('parameter="result",nullable="true"', 'parameter="result",nullable="false"'),
		'missing-import-policy': base.replace('profile="declarations-v1",lifetime="unique"', 'profile="bounded",lifetime="unique"'),
	}
	for name, text in negatives.items():
		unit = work / (name + '.astra'); unit.write_text(text)
		stage = 'semantics'
		run([compiler, '--dump-' + stage, unit], contains='error:', expected=1)
	receipt['status'] = 'TYPED_FOREIGN_RESOURCE_EXPORT_C_INTEGRATION_PASS'
	(work / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')
	print(json.dumps(dict(status=receipt['status'], commands=len(receipt['checks']), receipt=str(work / 'checks.json'))))


if __name__ == '__main__':
	main(*sys.argv[1:])
