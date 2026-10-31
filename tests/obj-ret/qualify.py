# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Reproducible OBJ-RET-1 regression, firewall, machine and Valgrind qualification."""
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

BASELINE = '02e76fda0b570438b96e65decda8283712c0256f'
SUITES = {'obj-ret-parser', 'obj-ret-semantic', 'obj-ret-ownership-standalone', 'obj-ret-core-standalone', 'obj-ret-cfg-standalone', 'obj-ret-ssa-standalone', 'obj-ret-nabi-standalone', 'obj-ret-pipeline', 'obj-ret-llvm'}
LEGACY = {'semantic', 'core', 'cfg'}


def audit(build, out):
	tests = [json.loads(line) for line in (build/'meson-logs/testlog.json').read_text().splitlines()]
	assert len(tests) == len(json.loads((build/'meson-info/intro-tests.json').read_text()))
	assert all(test['result'] == 'OK' for test in tests), [row['name'] for row in tests if row['result'] != 'OK']
	goldens = 0
	for name in subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', BASELINE, 'tests'], cwd=ROOT, text=True).splitlines():
		if Path(name).suffix in {'.syntax', '.semantics', '.core', '.cfg', '.ssa', '.nabi', '.cabi', '.ll', '.stderr'}:
			assert (ROOT/name).read_bytes() == subprocess.check_output(['git', 'show', BASELINE+':'+name], cwd=ROOT), name
			goldens += 1
	for name in ['bootstrap/semantic/types.vala', 'bootstrap/semantic/pointer-parameter-contract.vala', 'bootstrap/semantic/lexical-region.vala', 'bootstrap/semantic/semantic-lifecycle.vala', 'bootstrap/cabi', 'bootstrap/vapi', 'bootstrap/foreign']:
		assert not subprocess.check_output(['git', 'diff', BASELINE, '--', name], cwd=ROOT), name
	for stage in ['syntax', 'semantic', 'core', 'cfg', 'ssa', 'nabi']:
		for path in (ROOT/'bootstrap'/stage).glob('*.vala'):
			code = re.sub(r'/\*.*?\*/|//[^\n]*', '', path.read_text(), flags=re.S)
			assert not re.search(r'\bLLVM\w*|Astra\.Backend|CApi\.', code), path
	model = (ROOT/'bootstrap/nabi/native-model.vala').read_text()
	before = subprocess.check_output(['git', 'show', BASELINE+':src/nabi/native-model.vala'], cwd=ROOT, text=True)
	for enum in ['NativeAbiVersion', 'NativeScalarType']:
		pattern = r'public enum '+enum+r' \{.*?\n\t\}'
		assert re.search(pattern, model, re.S)[0] == re.search(pattern, before, re.S)[0], enum
	commands = json.loads((build/'compile_commands.json').read_text())
	generated = [row for row in commands if row['file'].endswith('.c') and 'meson-generated' in row['command']]
	assert generated and all('-DVALA_STRICT_C' in row['command'] and '-Werror' in row['command'] for row in generated)
	results = json.loads((build/'tests/obj-ret/execution/results.json').read_text())
	plans = [int(plan) for test in tests for plan in re.findall(r'^1\.\.(\d+)\s*$', test['stdout'], re.M)]
	new_plans = [int(plan) for test in tests if test['name'].split(':')[-1] in SUITES for plan in re.findall(r'^1\.\.(\d+)\s*$', test['stdout'], re.M)]
	summary = dict(baseline=BASELINE, meson_tests=len(tests), new_meson_tests=sum('obj-ret-' in test['name'] for test in tests), tap_suites=len(plans), tap_cases=sum(plans), new_tap_suites=len(new_plans), new_tap_cases=sum(new_plans), unchanged_goldens=goldens, strict_generated_c_commands=len(generated), runtime_executions=len(results['runs']), machine_fixtures=len(results['machine']), firewall_linkage_tests=sum('no-llvm' in test['name'] or 'links-qualified-llvm' in test['name'] or 'linkage-rejects' in test['name'] or 'firewall-rejects' in test['name'] for test in tests), dependencies_added=0)
	(out/'summary.json').write_text(json.dumps(summary, indent='\t')+'\n')
	print(json.dumps(summary))


def losses(text):
	text = re.sub(r'^==\d+== ?', '', text, flags=re.M)
	records = re.findall(r'[\d,]+ bytes in [\d,]+ blocks are (?:definitely|indirectly|possibly) lost in loss record[^\n]*\n.*?(?=\n\n|\Z)', text, flags=re.S)
	return [re.sub(r'0x[0-9A-Fa-f]+', 'ADDRESS', re.sub(r'loss record [\d,]+ of [\d,]+', 'loss record', record)) for record in records]


def memory(build, out, baseline):
	assert baseline is not None, 'provide an independent strict build of baseline 02e76fda'
	logs = out/'valgrind'
	logs.mkdir(exist_ok=True)
	jobs = []
	for root, prefix, names in [(build, '', SUITES | LEGACY | {'obj-own-pipeline'}), (baseline, 'baseline-', LEGACY)]:
		for test in json.loads((root/'meson-info/intro-tests.json').read_text()):
			if test['name'] in names:
				jobs.append((prefix+test['name'], test['cmd'], test['workdir'] or str(root), dict(os.environ, **test['env']), 0, None))
	for row in json.loads((build/'tests/obj-ret/execution/results.json').read_text())['runs']:
		jobs.append(('run-'+row['name'], [str(build/'tests/obj-ret/execution'/row['name'])], str(ROOT), os.environ, row['status'], row['output']))
	for fixture, case in json.loads((FIXTURES/'runtime-cases.json').read_text()).items():
		for stage in ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']:
			bindings = ['--vapi', str(ROOT/'tests/obj-life/fixtures/lifecycle.vapi')] if case['resource'] and stage != 'syntax' else []
			jobs.append(('dump-'+fixture+'-'+stage, [str(build/'astrac'), '--dump-'+stage, str(FIXTURES/f'obj-ret-{fixture}.astra'), *bindings], str(ROOT), os.environ, 0, None))
	jobs.append(('invalid-local-escape', [str(build/'astrac'), '--dump-semantics', str(FIXTURES/'obj-ret-invalid.astra')], str(ROOT), os.environ, 1, ''))

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
			if name.startswith('run-') and row['expected'] == 42:
				assert row['reachable'] == 0, row
	summary = dict(current_runs=len(rows)-len(LEGACY), baseline_runs=len(LEGACY), clean_current_runs=len(rows)-2*len(LEGACY), matching_legacy_startup_losses=len(LEGACY), new_astra_errors=0, new_astra_lost_bytes=0)
	(logs/'summary.json').write_text(json.dumps(summary, indent='\t')+'\n')
	print(json.dumps(summary))


if __name__ == '__main__':
	parser = argparse.ArgumentParser()
	parser.add_argument('build', type=Path)
	parser.add_argument('--memory', action='store_true')
	parser.add_argument('--baseline', type=Path)
	args = parser.parse_args()
	build = args.build.resolve()
	out = build/'qualification-obj-ret'
	out.mkdir(exist_ok=True)
	if args.memory:
		memory(build, out, args.baseline.resolve() if args.baseline else None)
	else:
		audit(build, out)
