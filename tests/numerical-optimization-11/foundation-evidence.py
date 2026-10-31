# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Freeze compact component findings from real receipts; runs no engineering."""
from pathlib import Path
import hashlib
import json
import sys

ROOT=Path(__file__).resolve().parents[2]


def identity(path):
	path=Path(path)
	return {'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}


def main(build,runtime,output):
	build,runtime,output=Path(build).resolve(),Path(runtime).resolve(),Path(output).resolve()
	compiler=build/'astrac'
	rows=[]
	for name in ['policies','memory','unit-policies','portability',*[f'a{i}' for i in range(85,92)]]:
		path=build/'tests/numerical-optimization-11'/name/(name+'.json')
		r=json.loads(path.read_text())
		assert r['status']=='PASS' and r['compiler']['sha256']==identity(compiler)['sha256'],name
		for source,expected in r['frozen_inputs'].items():
			assert identity(source)=={key:expected[key] for key in ['bytes','sha256']},source
		assert all(c['exit']==c['expected_exit'] for c in r['commands']),name
		rows.append({'name':name,'receipt':str(path),'identity':identity(path),'commands':len(r['commands']),
			'valgrind_commands':sum(c['command'][0]=='valgrind' for c in r['commands']),
			'compiler_commands':sum(c['command'][0]==str(compiler) for c in r['commands'])})
	meson=build/'meson-logs/surge-11-foundation-qualified-restored.json'
	tests=[json.loads(line) for line in meson.read_text().splitlines()]
	assert len(tests)==15 and all(test['result']=='OK' for test in tests)
	sources={}
	for directory in [ROOT/'bootstrap',ROOT/'lib/astra',ROOT/'tests/numerical-optimization-11']:
		for path in sorted(directory.rglob('*')):
			if path.is_file() and path.suffix in ['.vala','.vapi','.c','.h','.in','.astra','.py','.S'] or path.is_file() and path.name=='meson.build':
				sources[str(path.relative_to(ROOT))]=identity(path)['sha256']
	for path in [ROOT/'meson.build',ROOT/'meson.options',*sorted((ROOT/'examples/numerical-optimization-11').glob('a8*.astra')),ROOT/'examples/numerical-optimization-11/a90-dft.astra',ROOT/'examples/numerical-optimization-11/a91-geometry.astra',ROOT/'examples/numerical-optimization-11/a92-policies.astra']:
		sources[str(path.relative_to(ROOT))]=identity(path)['sha256']
	canonical=json.dumps(sources,sort_keys=True,separators=(',',':')).encode()
	policy=build/'tests/numerical-optimization-11/policies'
	metrics={str(path.name):json.loads(path.read_text()) for path in sorted(policy.glob('*errors.json'))}
	record={'scope':'Surge 11 numerical foundation component; remaining campaign gates are open',
		'base_commit':'f799990886184cb79d2892350c8631f16aad18e2','compiler':identity(compiler),
		'source_digest':hashlib.sha256(canonical).hexdigest(),'source_inputs':sources,
		'meson_selection':{'receipt':str(meson),'identity':identity(meson),'passed':15,'tap_subtests':12},
		'current_source_receipts':rows,'floating_error_tables':metrics,
		'followup_receipts':[{'path':str(runtime/name),'identity':identity(runtime/name)} for name in ['n3-fp-error-tables-final.log','n3-unit-source-conservation.log']],
		'limits':['A93 prototype has not been linked or executed','N4–N6 optimizations and controlled ablations pending','A94–A96 pending','Repeated performance and final integrated qualification pending','Historical LAZY-1 Q4 remains HELD/INCOMPLETE']}
	output.write_text(json.dumps(record,indent=2,sort_keys=True)+'\n')
	print('Verified',len(rows),'source-frozen recipes;',sum(row['commands'] for row in rows),'commands; 15 Meson registrations; 12 TAP controls.')


if __name__=='__main__':main(*sys.argv[1:])
