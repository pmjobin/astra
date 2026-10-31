# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Reproduce INFER-1 baseline stability, independent builds and memory evidence."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True
from execute import CASES, FIXTURES, ROOT, STAGES, run

BASELINE = '130f96f94d10e1ca2f030cf269292a713024010c'
EXTENSIONS = {'.syntax', '.semantics', '.core', '.instances', '.cfg', '.ssa', '.nabi', '.cabi', '.ll', '.stderr'}


def write(path, data):
	path.write_text(json.dumps(data, indent='\t')+'\n')


def git(*args):
	return subprocess.check_output(['git', *args], cwd=ROOT)


def audit(build, independent, out):
	tests = [json.loads(line) for line in (build/'meson-logs/infer-final.json').read_text().splitlines()]
	assert len(tests) == len(json.loads((build/'meson-info/intro-tests.json').read_text()))
	assert all(row['result'] == 'OK' for row in tests), [(row['name'], row['result']) for row in tests if row['result'] != 'OK']
	goldens = []
	for name in git('ls-tree', '-r', '--name-only', BASELINE, 'tests').decode().splitlines():
		if Path(name).suffix in EXTENSIONS:
			before = git('show', BASELINE+':'+name)
			assert (ROOT/name).read_bytes() == before, name
			goldens.append(dict(path=name, sha256=hashlib.sha256(before).hexdigest()))
	assert len(goldens) == 1005
	# The 1,004 inherited goldens plus NUM-CONV's own invalid.stderr.
	assert len([row for row in goldens if not row['path'].startswith('tests/num-conv/')]) == 1004
	unchanged = ['bootstrap/core', 'bootstrap/cfg', 'bootstrap/ssa', 'bootstrap/nabi', 'bootstrap/cabi', 'bootstrap/backend', 'bootstrap/vapi', 'bootstrap/foreign', 'bootstrap/semantic/types.vala', 'bootstrap/semantic/checked-nodes.vala', 'bootstrap/semantic/symbols.vala', 'bootstrap/semantic/binary-float-format.vala', 'bootstrap/semantic/binary-float-value.vala', 'bootstrap/semantic/numeric-conversion.vala']
	for name in unchanged:
		assert not git('diff', BASELINE, '--', name), name
	for path in (ROOT/'bootstrap').rglob('*.vala'):
		assert not re.search(r'\b(?:VarType|AutoType|InferredType)\b', path.read_text()), path
	commands = json.loads((build/'compile_commands.json').read_text())
	generated = [row for row in commands if row['file'].endswith('.c') and 'meson-generated' in row['command']]
	assert generated and all('-DVALA_STRICT_C' in row['command'] and '-Werror' in row['command'] for row in generated)
	execution = build/'tests/infer/execution'
	comparisons = []
	for name in CASES:
		for prefix in ['infer', 'explicit']:
			for stage in STAGES:
				args = ['--dump-'+stage, FIXTURES/(prefix+'-'+name+'.astra')] + ([] if stage == 'syntax' else ['--vapi', FIXTURES/'runtime.vapi'])
				data = run([independent/'astrac', *args]).encode()
				assert data == (execution/(prefix+'-'+name+'.'+stage)).read_bytes(), (name, prefix, stage)
				comparisons.append(dict(name=prefix+'-'+name, stage=stage, sha256=hashlib.sha256(data).hexdigest()))
	by_suite = {}
	for row in tests:
		name = row['name'].split(':')[-1]
		prefix = name.split('-')[0]
		by_suite[prefix] = by_suite.get(prefix, 0)+1
	plans = [int(m[1]) for row in tests if (m := re.search(r'^1\.\.(\d+)$', row.get('stdout', ''), re.M))]
	native = json.loads((execution/'results.json').read_text())
	summary = dict(baseline=BASELINE, meson_tests=len(tests), tap_suites=len(plans), tap_cases=sum(plans), strict_generated_c_commands=len(generated), unchanged_baseline_goldens=len(goldens), inherited_goldens=1004, changed_baseline_goldens=[], unchanged_production_domains=unchanged, stage_pairs=len(native['pairs']), fresh_process_comparisons=len(native['deterministic']), independent_build_comparisons=len(comparisons), machine_pairs=len(native['machine_pairs']), exact_executions=len(native['runs']), negative_checks=len(json.loads((build/'tests/infer/negative/results.json').read_text())), stage_lifetime_fixtures=len(CASES), firewall_linkage_tests=sum(any(x in row['name'] for x in ['no-llvm', 'links-qualified-llvm', 'linkage-rejects', 'firewall-rejects']) for row in tests), suite_counts=by_suite, dependencies_added=0)
	write(out/'goldens.json', goldens); write(out/'determinism.json', comparisons); write(out/'summary.json', summary)
	print(json.dumps(summary), flush=True)


def memory(build, out):
	logs = out/'valgrind'; logs.mkdir(exist_ok=True)
	jobs = []
	for stage in ['parser', 'semantic', 'pipeline']:
		jobs.append(('test-'+stage, [build/f'tests/infer/astra-infer-{stage}', '--tap'], None))
	for name in ['scalars', 'literals', 'resource', 'buffer', 'object', 'structs', 'generic-struct', 'generic-result', 'generic-owner', 'cad']:
		for stage in ['syntax', 'semantics', 'core', 'ssa', 'nabi', 'llvm']:
			args = [build/'astrac', '--dump-'+stage, FIXTURES/('infer-'+name+'.astra')] + ([] if stage == 'syntax' else ['--vapi', FIXTURES/'runtime.vapi'])
			jobs.append(('dump-'+name+'-'+stage, args, None))
		for mode in ['O0', 'O2']:
			jobs.append(('run-'+name+'-'+mode, [build/'tests/infer/execution'/('infer-'+name+'-'+mode)], ''.join(event+'\n' for event in CASES[name].split())))
	for mode in ['O0', 'O2']:
		jobs.append(('identity-'+mode, [build/'tests/infer/execution'/('object-storage-identity-'+mode)], 'M9\n'))

	def measure(job):
		name, argv, expected = job
		path = logs/(name+'.log')
		p = subprocess.run(list(map(str, ['valgrind', '--vgdb=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', '--log-file='+str(path), *argv])), cwd=ROOT, capture_output=True, text=True, env=dict(os.environ, CCACHE_DISABLE='1'))
		(logs/(name+'.stdout')).write_text(p.stdout); (logs/(name+'.stderr')).write_text(p.stderr)
		text = path.read_text()
		assert 'ERROR SUMMARY:' in text, name
		def number(pattern):
			match = re.search(pattern, text)
			return int(match[1].replace(',', '')) if match else 0
		row = dict(name=name, exit=p.returncode, errors=number(r'ERROR SUMMARY: ([\d,]+) errors'), definite=number(r'definitely lost: ([\d,]+) bytes'), indirect=number(r'indirectly lost: ([\d,]+) bytes'), possible=number(r'possibly lost: ([\d,]+) bytes'), output_matches=expected is None or expected == p.stdout)
		return row

	with ThreadPoolExecutor(max_workers=4) as pool:
		rows = list(pool.map(measure, jobs))
	write(logs/'results.json', rows)
	assert all(row['exit'] == row['errors'] == row['definite'] == row['indirect'] == row['possible'] == 0 and row['output_matches'] for row in rows), [row for row in rows if row['exit'] or row['errors'] or not row['output_matches']]
	summary = dict(runs=len(rows), new_astra_errors=0, definite=0, indirect=0, possible=0)
	write(logs/'summary.json', summary)
	print(json.dumps(summary), flush=True)


if __name__ == '__main__':
	parser = argparse.ArgumentParser()
	parser.add_argument('build', type=Path)
	parser.add_argument('--independent-build', type=Path)
	parser.add_argument('--memory', action='store_true')
	args = parser.parse_args()
	build = args.build.resolve(); out = build/'qualification-infer'; out.mkdir(exist_ok=True)
	if args.memory:
		memory(build, out)
	else:
		assert args.independent_build is not None
		audit(build, args.independent_build.resolve(), out)
