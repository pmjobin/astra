#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Public COM contract/codegen controls; native execution is qualified separately."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main(compiler_arg, output_arg):
	compiler = Path(compiler_arg).resolve()
	output = Path(output_arg).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='com-policies-', dir=output))
	rows = []
	receipt = {'scope': 'public COM compiler policies/codegen only; Windows execution receipts are separate',
		'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(), 'checks': rows}
	def run(command, expected=0, contains=''):
		p = subprocess.run(list(map(str, command)), capture_output=True, text=True, timeout=90,
			cwd=work, env=dict(os.environ, CCACHE_DISABLE='1'))
		rows.append({'command': list(map(str, command)), 'exit': p.returncode,
			'expected_exit': expected, 'stdout': p.stdout, 'stderr': p.stderr})
		(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
		assert p.returncode == expected and contains in p.stdout + p.stderr, rows[-1]
		return p.stdout
	target = ['--target=x86_64-w64-windows-gnu']
	for label, path in [('import', 'com-import/client.astra'), ('export', 'com-export/counter.astra')]:
		unit = ROOT / 'tests/interop-tooling-14' / path
		original = unit.read_bytes()
		for stage in ('syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi'):
			run([compiler, *target, '--dump-' + stage, unit], contains='COMImport' if label == 'import' else 'COMExport')
		run([compiler, '--explain-semantics', unit], contains='COMImport' if label == 'import' else 'CExport opaque')
		run([compiler, '--tooling-index', unit])
		run([compiler, *target, '--emit-com-header', unit], contains='sizeof(void *) == 8')
		generated = run([compiler, *target, '--emit-com-source', unit], contains='CoGetApartmentType')
		assert 'reinterpret_cast' not in generated and 'RegisterClass' not in generated
		assert run([compiler, *target, '--emit-com-source', unit]) == generated
		for level in ('0', '1', '2'):
			obj = work / (label + '-O' + level + '.o')
			run([compiler, *target, '-O' + level, '-c', unit, '-o', obj])
			run(['objdump', '-f', obj], contains='pe-x86-64')
		run([compiler, '--check', unit], expected=1, contains='requires --target=')
		run([compiler, *target, '--emit-com-source', unit, '-o', unit], expected=2)
		assert unit.read_bytes() == original
		run([compiler, *target, '--check', unit])
	bad = work / 'invalid.astra'
	unit = ROOT / 'tests/interop-tooling-14/com-import/client.astra'
	healthy = unit.read_text()
	for text in [healthy.replace('view="value"', 'view="dispatch"'), healthy.replace('threading="constructing"', 'threading="agile"'),
		healthy.replace('owned ImportedValue moved = move copy;', 'owned ImportedValue moved = copy;'),
		healthy.replace('is14_scale(scale,', 'is14_scale(moved,'),
		healthy.replace('interface ImportedValue;', 'interface ImportedValue { int read(); }'),
		healthy + '\n[CImport] int forged(borrowed ImportedValue value);\n']:
		bad.write_text(text)
		run([compiler, *target, '--check', bad], expected=1)
	run([compiler, *target, '--check', unit])
	receipt['status'] = 'PASS'
	(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	print(f'PASS: {len(rows)} COM public policy, COFF and refusal commands; native execution qualified separately; evidence {work}')


if __name__ == '__main__':
	main(*sys.argv[1:])
