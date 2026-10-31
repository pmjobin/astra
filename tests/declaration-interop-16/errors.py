#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent and SDK C callers for checked native errors and explicit nonfailure status."""
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
	work = Path(tempfile.mkdtemp(prefix='declared-errors-', dir=output))
	source = Path(__file__).resolve().parent
	receipt = dict(scope='checked native errors and nullable nonfailure statuses; full M16 remains pending',
		compiler_sha256=sha(compiler), checks=[], sources={})
	for path in [Path(__file__).resolve(), source / 'errors.astra', source / 'errors-client.c', ROOT / 'lib/runtime/interop/foreign-14.c']:
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
		text = (source / 'errors.astra').read_text()
		if lifetime == 'shared':
			text = text.replace('class Item', '[Shared]\nclass Item').replace('class Service', '[Shared]\nclass Service')
		unit = case / 'service.astra'; unit.write_text(text)
		header = run([compiler, '--emit-class-header', unit], contains='declarations-v1')
		(case / 'errors16.h').write_text(header)
		record_name = re.search(r'/\* POD Row16:.*?\*/\s*typedef struct (\w+)', header, re.S).group(1)
		forward = case / 'forward.c'; forward.write_text(run([compiler, '--emit-class-source', unit], contains='Mechanical'))
		for stage in ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi']:
			run([compiler, '--dump-' + stage, unit], contains='declarations-v1')
		for level in '012':
			obj = case / ('native-O' + level + '.o')
			run([compiler, '-O' + level, '-c', unit, '-o', obj])
			for client_kind in ['independent', 'sdk']:
				binary = case / (client_kind + '-O' + level)
				selection = (['-DEXPECT_SHARED'] if lifetime == 'shared' else []) + (['-DUSE_SDK', '-DSDK_ROW_TYPE=' + record_name] if client_kind == 'sdk' else [])
				run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread',
					*selection, '-I', case, source / 'errors-client.c', obj, forward,
					ROOT / 'lib/runtime/interop/foreign-14.c', '-o', binary])
				run([binary], contains='PASS named checked errors')
				if level in '02':
					run(['valgrind', '--vgdb=no', '--default-suppressions=no', '--leak-check=full',
						'--show-leak-kinds=definite,indirect,possible', '--errors-for-leak-kinds=definite,indirect,possible',
						'--error-exitcode=99', binary], contains='ERROR SUMMARY: 0 errors')
	for name, old, new, diagnostic in [
		('missing-bound', 'BadInput=-1601,Fault=-1600', 'BadInput=-1601', 'exhaustive final throws-bound mapping'),
		('unreachable-case', 'BadInput=-1601,Fault=-1600', 'BadInput=-1601,PrivateBadInput=-1602,Fault=-1600', 'specific-before-base ordering'),
		('positive-error', 'BadInput=-1601,Fault=-1600', 'BadInput=1,Fault=-1600', 'negative signed 32-bit'),
		('unrelated-error', 'BadInput=-1601,Fault=-1600', 'Service=-1601,Fault=-1600', 'exact native exception types'),
		('duplicate-status', 'BadInput=-1601,Fault=-1600', 'BadInput=-1600,Fault=-1600', 'exhaustive final throws-bound mapping'),
		('nonnullable-status', '[ForeignChannel(parameter="result",nullable="true")]', '[ForeignChannel(parameter="result",nullable="false")]', 'null_status requires a nullable owned object result'),
	]:
		unit = work / (name + '.astra'); unit.write_text((source / 'errors.astra').read_text().replace(old, new))
		run([compiler, '--dump-llvm', unit], contains=diagnostic, expected=1)
	receipt['status'] = 'CHECKED_NATIVE_ERRORS_C_INTEGRATION_PASS'
	(work / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')
	print(json.dumps(dict(status=receipt['status'], commands=len(receipt['checks']), receipt=str(work / 'checks.json'))))


if __name__ == '__main__':
	main(*sys.argv[1:])
