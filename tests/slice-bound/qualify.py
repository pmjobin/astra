# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Audit the strict build, preserved goldens and slice-boundary lifetimes."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import argparse
import json
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True
from execute import ROOT

BASELINE = 'fe9ac2ba55850ce29243ae84e651505c7ba1e50f'


def audit(build, out):
	tests = [json.loads(line) for line in (build/'meson-logs/testlog.json').read_text().splitlines()]
	assert len(tests) == len(json.loads((build/'meson-info/intro-tests.json').read_text()))
	assert all(test['result'] == 'OK' for test in tests)
	goldens = 0
	for name in subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', BASELINE, 'tests'], cwd=ROOT, text=True).splitlines():
		if Path(name).suffix in {'.syntax', '.semantics', '.core', '.cfg', '.ssa', '.nabi', '.cabi', '.ll', '.stderr'}:
			assert (ROOT/name).read_bytes() == subprocess.check_output(['git', 'show', BASELINE+':'+name], cwd=ROOT), name
			goldens += 1
	for path in ['bootstrap/cabi', 'bootstrap/vapi', 'bootstrap/foreign', 'bootstrap/semantic/types.vala', 'bootstrap/semantic/lexical-region.vala', 'bootstrap/semantic/data-pointer-provenance.vala', 'bootstrap/semantic/pointer-parameter-contract.vala', 'bootstrap/cfg/ownership-flow.vala', 'bootstrap/ssa/ssa-builder.vala', 'bootstrap/ssa/ssa-memory.vala', 'bootstrap/backend/llvm/llvm-scalar-lowering.vala']:
		assert subprocess.check_output(['git', 'diff', BASELINE, '--', path], cwd=ROOT) == b'', path
	commands = json.loads((build/'compile_commands.json').read_text())
	generated = [row for row in commands if row['file'].endswith('.c') and 'meson-generated' in row['command']]
	assert generated and all('-DVALA_STRICT_C' in row['command'] and '-Werror' in row['command'] for row in generated)
	for stage in ['syntax', 'semantic', 'core', 'cfg', 'ssa', 'nabi']:
		for path in (ROOT/'bootstrap'/stage).glob('*.vala'):
			code = re.sub(r'/\*.*?\*/|//[^\n]*', '', path.read_text(), flags=re.S)
			assert not re.search(r'\bLLVM\w*|Astra\.Backend|CApi\.', code), path
	results = json.loads((build/'tests/slice-bound/execution/results.json').read_text())
	machine = json.loads((build/'tests/slice-bound/execution/machine-results.json').read_text())
	assert len(machine['fixtures']) == 11 and machine['paired_call_arguments'] > 0 and machine['aggregate_phis'] >= 2
	plans = [int(plan) for test in tests for plan in re.findall(r'^1\.\.(\d+)\s*$', test['stdout'], re.M)]
	summary = dict(baseline=BASELINE, meson_tests=len(tests), boundary_tests=sum('slice-bound-' in t['name'] for t in tests), tap_suites=len(plans), tap_cases=sum(plans), baseline_goldens_unchanged=goldens, strict_c_commands=len(generated), native_executions=len(results['runs']), expected_traps=sum(r['status'] < 0 for r in results['runs']), optimized_executions=sum(r['optimized'] for r in results['runs']), shapes=len(results['shapes']), exact_boundary_calls=results['exact_boundary_calls'], machine_fixtures=len(machine['fixtures']), machine_functions=sum(row['functions'] for row in machine['fixtures']), paired_call_arguments=machine['paired_call_arguments'], aggregate_phis=machine['aggregate_phis'], executable_linkage_audits=3*len(machine['fixtures']))
	(out/'audit-results.json').write_text(json.dumps(summary, indent='\t')+'\n')
	print(json.dumps(summary))


def memory(build, out):
	logs = out/'valgrind'
	logs.mkdir(exist_ok=True)
	jobs = []
	for test in json.loads((build/'meson-info/intro-tests.json').read_text()):
		if test['name'] in {'slice-bound-semantic', 'slice-bound-pipeline', 'slice-bound-llvm', 'slice-bound-core-standalone', 'slice-bound-cfg-standalone', 'slice-bound-ssa-standalone', 'slice-bound-nabi-standalone'}:
			jobs.append((test['name'], test['cmd'], test['workdir'] or str(build), dict(os.environ, **test['env']), 0, None))
	for row in json.loads((build/'tests/slice-bound/execution/results.json').read_text())['runs']:
		jobs.append(('run-'+row['name'], [str(build/'tests/slice-bound/execution'/row['name'])], str(ROOT), os.environ, row['status'], row['output']))
	for stage in ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']:
		jobs.append(('dump-'+stage, [str(build/'astrac'), '--dump-'+stage, str(ROOT/'tests/slice-bound/fixtures/slice-bound-mixed.astra')], str(ROOT), os.environ, 0, None))
	assert len({job[0] for job in jobs}) == len(jobs)

	def measure(job):
		name, argv, cwd, env, status, output = job
		command = ['valgrind', '--vgdb=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', '--log-file='+str(logs/(name+'.log')), *argv]
		r = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True)
		(logs/(name+'.stdout')).write_text(r.stdout)
		(logs/(name+'.stderr')).write_text(r.stderr)
		text = (logs/(name+'.log')).read_text()
		assert 'ERROR SUMMARY:' in text, name
		def number(pattern):
			match = re.search(pattern, text)
			return int(match[1].replace(',', '')) if match else 0
		return dict(name=name, command=command, exit=r.returncode, expected=status, output_matches=output is None or output == r.stdout, errors=number(r'ERROR SUMMARY: ([\d,]+) errors'), definite=number(r'definitely lost: ([\d,]+) bytes'), indirect=number(r'indirectly lost: ([\d,]+) bytes'), possible=number(r'possibly lost: ([\d,]+) bytes'))

	with ThreadPoolExecutor(max_workers=4) as pool:
		rows = list(pool.map(measure, jobs))
	(logs/'results.json').write_text(json.dumps(rows, indent='\t')+'\n')
	for row in rows:
		assert row['exit'] == row['expected'] and row['output_matches'] and row['errors'] == row['definite'] == row['indirect'] == row['possible'] == 0, row
	print(json.dumps(dict(valgrind_runs=len(rows), errors=0, lost_bytes=0)))


if __name__ == '__main__':
	parser = argparse.ArgumentParser()
	parser.add_argument('build', type=Path)
	parser.add_argument('--memory', action='store_true')
	args = parser.parse_args()
	build = args.build.resolve()
	out = build/'qualification-slice-bound'
	out.mkdir(exist_ok=True)
	(memory if args.memory else audit)(build, out)
