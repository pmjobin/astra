#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent and SDK C callers for consuming object C Class imports."""
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
	work = Path(tempfile.mkdtemp(prefix='declared-import-consuming-', dir=output))
	source = Path(__file__).resolve().parent
	receipt = dict(scope='consuming object C Class imports with bounded publication and provisional owner retirement; full M16 remains pending',
		compiler_sha256=sha(compiler), checks=[], sources={})
	for path in [Path(__file__).resolve(), source / 'import-consuming.astra', source / 'import-consuming-provider.c']:
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
		text = (source / 'import-consuming.astra').read_text()
		if lifetime == 'shared':
			text = text.replace('lifetime="unique"', 'lifetime="shared"', 1)
		if child_lifetime == 'shared':
			text = text.replace('name="consume_child16",profile="declarations-v1",lifetime="unique"', 'name="consume_child16",profile="declarations-v1",lifetime="shared"')
		unit = case / 'service.astra'; unit.write_text(text)
		(case / 'imports16.h').write_text(run([compiler, '--emit-class-header', unit], contains='declarations-v1'))
		for stage in ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi']:
			run([compiler, '--dump-' + stage, unit], contains='declarations-v1')
		for level in '012':
			obj = case / ('native-O' + level + '.o')
			run([compiler, '-O' + level, '-c', unit, '-o', obj])
			for client_kind in ['independent', 'sdk']:
				binary = case / (client_kind + '-O' + level)
				selection = (['-DEXPECT_SHARED'] if lifetime == 'shared' else []) + (['-DCHILD_SHARED'] if child_lifetime == 'shared' else []) + (['-DUSE_SDK'] if client_kind == 'sdk' else [])
				run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread',
					*selection, '-I', case, '-Wl,--wrap=calloc', source / 'import-consuming-provider.c', obj, '-o', binary])
				run([binary], contains='PASS typed C Class imports')
				if level in '02':
					run(['valgrind', '--vgdb=no', '--default-suppressions=no', '--leak-check=full',
						'--show-leak-kinds=definite,indirect,possible', '--errors-for-leak-kinds=definite,indirect,possible',
						'--error-exitcode=99', binary], contains='ERROR SUMMARY: 0 errors')
	base = (source / 'import-consuming.astra').read_text()
	negatives = {
		'borrowed-transfer-conflict': base.replace('owned Child input,borrowed u8[] seed', 'borrowed Child input,borrowed u8[] seed'),
		'wrong-root': base.replace('int take(owned Child input', 'int take(owned Provider input'),
		'borrow-to-owned': base.replace('move child,slice(seed)', 'child,slice(seed)'),
		'double-move': base.replace('provider.pair(move first,move second)', 'provider.pair(move first,move first)'),
		'use-after-transfer': base.replace('\n\t\t\tseen();', '\n\t\t\tchild.code();seen();'),
		'owned-byte-input': base.replace('borrowed u8[] seed', 'owned u8[] seed'),
	}
	for name, text in negatives.items():
		unit = work / (name + '.astra'); unit.write_text(text)
		stage = 'cfg' if name == 'use-after-transfer' else 'semantics'
		run([compiler, '--dump-' + stage, unit], contains='error:', expected=1)
	receipt['status'] = 'TYPED_CONSUMING_IMPORT_C_INTEGRATION_PASS'
	(work / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')
	print(json.dumps(dict(status=receipt['status'], commands=len(receipt['checks']), receipt=str(work / 'checks.json'))))


if __name__ == '__main__':
	main(*sys.argv[1:])
