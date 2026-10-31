# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""OBJ-OWN-1 strict build, regression, physical/semantic firewall and memory qualification."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import argparse
import json
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True
from execute import FIXTURES, ROOT

BASELINE = '1eff1debad1c0187bb277bfba5d0ee1c1c645f51'
SUITES = {'obj-own-parser', 'obj-own-semantic', 'obj-own-core-standalone', 'obj-own-cfg-standalone', 'obj-own-ssa-standalone', 'obj-own-nabi-standalone', 'obj-own-pipeline', 'obj-own-cleanup-standalone', 'obj-own-llvm'}
OBJECT_SUITES = {'object-parser', 'object-semantic', 'object-borrow', 'object-pipeline', 'object-llvm', 'object-core-standalone', 'object-cfg-standalone', 'object-ssa-standalone', 'object-nabi-standalone'}
LEGACY = {'semantic', 'core', 'cfg'}


def audit(build, out):
	tests = [json.loads(line) for line in (build/'meson-logs/testlog.json').read_text().splitlines()]
	assert len(tests) == len(json.loads((build/'meson-info/intro-tests.json').read_text()))
	assert all(test['result'] == 'OK' for test in tests)
	goldens = 0
	for name in subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', BASELINE, 'tests'], cwd=ROOT, text=True).splitlines():
		if Path(name).suffix in {'.syntax', '.semantics', '.core', '.cfg', '.ssa', '.nabi', '.cabi', '.ll', '.stderr'}:
			assert (ROOT/name).read_bytes() == subprocess.check_output(['git', 'show', BASELINE+':'+name], cwd=ROOT), name
			goldens += 1
	for path in ['bootstrap/vapi', 'bootstrap/foreign', 'bootstrap/semantic/types.vala', 'bootstrap/semantic/pointer-parameter-contract.vala', 'bootstrap/semantic/lexical-region.vala', 'bootstrap/semantic/semantic-objects.vala', 'bootstrap/semantic/semantic-lifecycle.vala', 'bootstrap/nabi/native-model.vala', 'bootstrap/nabi/native-builder.vala', 'bootstrap/cabi/cabi-model.vala', 'bootstrap/cabi/cabi-type-mapper.vala', 'bootstrap/cabi/cabi-verifier.vala']:
		assert subprocess.check_output(['git', 'diff', BASELINE, '--', path], cwd=ROOT) == b'', path
	commands = json.loads((build/'compile_commands.json').read_text())
	generated = [row for row in commands if row['file'].endswith('.c') and 'meson-generated' in row['command']]
	assert generated and all('-DVALA_STRICT_C' in row['command'] and '-Werror' in row['command'] for row in generated)
	for stage in ['syntax', 'semantic', 'core', 'cfg', 'ssa', 'nabi']:
		for path in (ROOT/'bootstrap'/stage).glob('*.vala'):
			code = re.sub(r'/\*.*?\*/|//[^\n]*', '', path.read_text(), flags=re.S)
			assert not re.search(r'\bLLVM\w*|Astra\.Backend|CApi\.', code), path
	model = (ROOT/'bootstrap/nabi/native-model.vala').read_text()
	baseline_model = subprocess.check_output(['git', 'show', BASELINE+':src/nabi/native-model.vala'], cwd=ROOT, text=True)
	for name in ['NativeAbiVersion', 'NativeScalarType']:
		pattern = r'public enum '+name+r' \{.*?\n\t\}'
		assert re.search(pattern, model, re.S)[0] == re.search(pattern, baseline_model, re.S)[0], name
	results = json.loads((build/'tests/obj-own/execution/results.json').read_text())
	cases = json.loads((FIXTURES/'runtime-cases.json').read_text())
	assert len(results['machine']) == 12 and len(results['runs']) == 2*len(cases)+12
	assert results['noalias_negative_control']['status'] != 42
	old = json.loads((build/'tests/object/execution/results.json').read_text())
	life = json.loads((build/'tests/obj-life/execution/results.json').read_text())
	assert len(old['runs']) == 71 and len(old['machine']) == 9
	assert len(life['runs']) == 58 and len(life['machine']) == 12
	source = '\n'.join(path.read_text() for path in (ROOT/'bootstrap').rglob('*.vala'))
	for forbidden in ['NativeOwnedObject', 'NativeObjectOwnerType', 'OwnedObjectStorage', 'ObjectMoveAnalyzer', 'ObjectPendingTransferEngine']:
		assert forbidden not in source, forbidden
	plans = [int(plan) for test in tests for plan in re.findall(r'^1\.\.(\d+)\s*$', test['stdout'], re.M)]
	bound_plans = [int(plan) for test in tests if test['name'].split(':')[-1] in SUITES for plan in re.findall(r'^1\.\.(\d+)\s*$', test['stdout'], re.M)]
	summary = dict(baseline=BASELINE, meson_tests=len(tests), object_ownership_tests=sum('obj-own-' in test['name'] for test in tests), tap_suites=len(plans), tap_cases=sum(plans), ownership_tap_suites=len(bound_plans), ownership_tap_cases=sum(bound_plans), baseline_goldens_unchanged=goldens, strict_c_commands=len(generated), ownership_fixtures=len(cases), native_executions=len(results['runs']), expected_traps=sum(row['status'] < 0 for row in results['runs']), optimized_executions=sum('O2' in row['name'] for row in results['runs']), machine_fixtures=len(results['machine']), legacy_object_executions=len(old['runs']), legacy_lifecycle_executions=len(life['runs']), noalias_negative_control=results['noalias_negative_control'], firewall_linkage_tests=sum(test['name'].endswith('-no-llvm') or test['name'].endswith('-links-qualified-llvm') or 'firewall-rejects' in test['name'] or 'linkage-rejects' in test['name'] for test in tests))
	(out/'audit-results.json').write_text(json.dumps(summary, indent='\t')+'\n')
	print(json.dumps(summary))


def losses(text):
	text = re.sub(r'^==\d+== ?', '', text, flags=re.M)
	records = re.findall(r'[\d,]+ bytes in [\d,]+ blocks are (?:definitely|indirectly|possibly) lost in loss record[^\n]*\n.*?(?=\n\n|\Z)', text, flags=re.S)
	return [re.sub(r'0x[0-9A-Fa-f]+', 'ADDRESS', re.sub(r'loss record [\d,]+ of [\d,]+', 'loss record', record)) for record in records]


def memory(build, out, baseline):
	assert baseline is not None, 'provide an independent strict build of the accepted baseline'
	logs = out/'valgrind'; logs.mkdir(exist_ok=True)
	jobs = []
	for root, prefix, names in [(build, '', SUITES | OBJECT_SUITES | LEGACY), (baseline, 'baseline-', LEGACY)]:
		for test in json.loads((root/'meson-info/intro-tests.json').read_text()):
			if test['name'] in names:
				jobs.append((prefix+test['name'], test['cmd'], test['workdir'] or str(root), dict(os.environ, **test['env']), 0, None))
	for row in json.loads((build/'tests/obj-own/execution/results.json').read_text())['runs']:
		jobs.append(('run-'+row['name'], [str(build/'tests/obj-own/execution'/row['name'])], str(ROOT), os.environ, row['status'], row['output']))
	for fixture, case in json.loads((FIXTURES/'runtime-cases.json').read_text()).items():
		for stage in ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']:
			bindings = ['--vapi', str(ROOT/'tests/obj-life/fixtures/lifecycle.vapi')] if case['resource'] and stage != 'syntax' else []
			jobs.append(('dump-'+fixture+'-'+stage, [str(build/'astrac'), '--dump-'+stage, str(FIXTURES/f'obj-own-{fixture}.astra'), *bindings], str(ROOT), os.environ, 0, None))
	jobs.append(('invalid-boundary', [str(build/'astrac'), '--dump-semantics', str(FIXTURES/'obj-own-invalid.astra')], str(ROOT), os.environ, 1, ''))
	assert len({job[0] for job in jobs}) == len(jobs)

	def measure(job):
		name, argv, cwd, env, status, output = job
		command = ['valgrind', '--vgdb=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', '--log-file='+str(logs/(name+'.log')), *argv]
		result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True)
		(logs/(name+'.stdout')).write_text(result.stdout)
		(logs/(name+'.stderr')).write_text(result.stderr)
		text = (logs/(name+'.log')).read_text()
		assert 'ERROR SUMMARY:' in text, name
		def number(pattern):
			match = re.search(pattern, text)
			return int(match[1].replace(',', '')) if match else 0
		return dict(name=name, command=command, exit=result.returncode, expected=status, output_matches=output is None or output == result.stdout, errors=number(r'ERROR SUMMARY: ([\d,]+) errors'), definite=number(r'definitely lost: ([\d,]+) bytes'), indirect=number(r'indirectly lost: ([\d,]+) bytes'), possible=number(r'possibly lost: ([\d,]+) bytes'), suppressed=number(r'suppressed: ([\d,]+) from'), reachable=number(r'still reachable: ([\d,]+) bytes'), lost_records=losses(text))

	with ThreadPoolExecutor(max_workers=4) as pool:
		rows = list(pool.map(measure, jobs))
	(logs/'results.json').write_text(json.dumps(rows, indent='\t')+'\n')
	by_name = {row['name']: row for row in rows}
	for row in rows:
		name = row['name']
		if name.removeprefix('baseline-') in LEGACY:
			assert row['exit'] == 99 and row['errors'] == 1 and row['definite'] == 16384 and row['indirect'] == row['possible'] == row['suppressed'] == 0, row
			assert len(row['lost_records']) == 1 and 'g_malloc' in row['lost_records'][0] and 'call_init' in row['lost_records'][0], row
			assert row['lost_records'] == by_name['baseline-'+name.removeprefix('baseline-')]['lost_records'], row
		else:
			assert row['exit'] == row['expected'] and row['output_matches'] and row['errors'] == row['definite'] == row['indirect'] == row['possible'] == row['suppressed'] == 0, row
	summary = dict(current_runs=len(rows)-len(LEGACY), baseline_runs=len(LEGACY), clean_current_runs=len(rows)-2*len(LEGACY), matching_legacy_startup_losses=len(LEGACY), new_astra_errors=0, new_astra_lost_bytes=0)
	(logs/'summary.json').write_text(json.dumps(summary, indent='\t')+'\n')
	print(json.dumps(summary))


if __name__ == '__main__':
	parser = argparse.ArgumentParser()
	parser.add_argument('build', type=Path)
	parser.add_argument('--memory', action='store_true')
	parser.add_argument('--baseline', type=Path)
	args = parser.parse_args()
	build = args.build.resolve(); out = build/'qualification-obj-own'; out.mkdir(exist_ok=True)
	if args.memory:
		memory(build, out, args.baseline.resolve() if args.baseline else None)
	else:
		audit(build, out)
