# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Accepted-SHA golden audit, independent builds, stage memory, and final counts."""
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
from qualify import CASES, ROOT, STAGES, dump, inputs, run, vapi

BASELINE = '60085d963da3fc5a2840cd007f5e4db752e09c7e'
EXTENSIONS = {'.syntax', '.semantics', '.core', '.instances', '.cfg', '.ssa', '.nabi', '.cabi', '.ll', '.stderr'}


def write(path, data):
	path.write_text(json.dumps(data, indent='\t')+'\n')


def audit(build, independent, baseline, out):
	goldens = []
	names = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', BASELINE, 'tests'], cwd=ROOT).decode().splitlines()
	for name in names:
		if Path(name).suffix not in EXTENSIONS:
			continue
		before = subprocess.check_output(['git', 'show', BASELINE+':'+name], cwd=ROOT)
		assert before == (ROOT/name).read_bytes(), ('accepted baseline golden changed', name)
		goldens.append(dict(path=name, sha256=hashlib.sha256(before).hexdigest()))
	assert len(goldens) == 1005, len(goldens)
	comparisons = []; single = []; partitions = []
	for name in CASES:
		# A one-file test control is built from the exact original declarations.
		# This is test data, never the compiler's multi-source implementation.
		control = out/(name+'-single.astra'); control.write_text('\n'.join((ROOT/p).read_text() for p in inputs(name)))
		for stage in STAGES:
			data = dump(independent/'astrac', name, stage)
			assert data == (build/'tests/sources/qualification'/(name+'.'+stage)).read_text(), (name, stage, 'independent compiler')
			comparisons.append(dict(name=name, stage=stage, sha256=hashlib.sha256(data.encode()).hexdigest()))
			if stage != 'syntax':
				assert data == run([build/'astrac', '--dump-'+stage, control, *vapi(name, stage)]), (name, stage, 'one-file partition equivalence')
				partitions.append(name+':'+stage)
	for source in sorted((ROOT/'tests/param-borrow/fixtures').glob('param-borrow-*.astra')):
		if source.stem in ['param-borrow-invalid', 'param-borrow-overlap']:
			continue
		for stage in STAGES:
			args = ['--dump-'+stage, source] + ([] if stage == 'syntax' else ['--vapi', ROOT/'tests/param-borrow/fixtures/runtime.vapi'])
			before = run([baseline/'astrac', *args]); after = run([build/'astrac', *args])
			assert before == after, (source, stage, 'accepted single-source output changed')
			single.append(dict(name=source.name, stage=stage, sha256=hashlib.sha256(after.encode()).hexdigest()))
			# Reproduce and retain the pre-existing generic/buffer composition defect.
	args = [baseline/'astrac', '--check', out/'ownership-single.astra', *vapi('ownership', 'llvm')]
	old = subprocess.run(list(map(str, args)), cwd=ROOT, capture_output=True, text=True)
	assert old.returncode == 1 and 'buffer borrow requires an exact owner' in old.stderr, old
	(out/'baseline-generic-buffer.stderr').write_text(old.stderr)
	tests = [json.loads(line) for line in (build/'meson-logs/sources-final.json').read_text().splitlines()]
	assert len(tests) == len(json.loads((build/'meson-info/intro-tests.json').read_text()))
	assert all(row['result'] == 'OK' for row in tests), [(row['name'], row['result']) for row in tests if row['result'] != 'OK']
	plans = [int(m[1]) for row in tests if (m := re.search(r'^1\.\.(\d+)$', row.get('stdout', ''), re.M))]
	commands = json.loads((build/'compile_commands.json').read_text())
	generated = [row for row in commands if row['file'].endswith('.c') and 'meson-generated' in row['command']]
	assert generated and all('-DVALA_STRICT_C' in row['command'] and '-Werror' in row['command'] for row in generated)
	native = json.loads((build/'tests/sources/qualification/results.json').read_text())
	negative = json.loads((build/'tests/sources/negative/results.json').read_text())
	for name in native['runs']:
		assert (build/'tests/sources/qualification'/(name+'.machine')).read_bytes() == (independent/'tests/sources/qualification'/(name+'.machine')).read_bytes(), (name, 'independent-build instructions/relocations')
	summary = dict(baseline=BASELINE, meson_tests=len(tests), tap_suites=len(plans), tap_cases=sum(plans), strict_generated_c_commands=len(generated), baseline_goldens=len(goldens), unchanged_baseline_goldens=len(goldens), changed_baseline_goldens=[], new_goldens=sum(p.suffix in EXTENSIONS for p in (ROOT/'tests/sources/goldens').iterdir()), single_source_baseline_comparisons=len(single), independent_build_comparisons=len(comparisons), fresh_process_comparisons=len(native['stages']), one_file_partition_comparisons=len(partitions), cad_permutations=sum(row['name'] == 'cad' for row in native['permutations']), generic_permutations=sum(row['name'] == 'generics' for row in native['permutations']), permutation_stage_comparisons=sum(row['stages'] for row in native['permutations']), exact_executions=len(native['runs']), machine_pairs=len(native['machine_pairs']), diagnostic_checks=len(negative), stage_lifetime_fixtures=len(CASES), firewall_linkage_tests=sum(any(x in row['name'] for x in ['no-llvm', 'links-qualified-llvm', 'linkage-rejects', 'firewall-rejects']) for row in tests), production_dependencies_added=0, preexisting_generic_buffer_defect='reproduced at accepted baseline; exact callee boundary retained by one-line Core clone correction')
	summary['independent_machine_comparisons'] = len(native['runs'])
	write(out/'goldens.json', goldens); write(out/'determinism.json', comparisons); write(out/'single-source.json', single); write(out/'partitions.json', partitions); write(out/'summary.json', summary)
	print(json.dumps(summary), flush=True)


def memory(build, out):
	logs = out/'valgrind'; logs.mkdir(exist_ok=True)
	jobs = []
	for stage in ['parser', 'semantic', 'core', 'cfg', 'ssa', 'nabi', 'cabi', 'pipeline', 'llvm', 'llvm-standalone']:
		jobs.append(('test-'+stage, [build/'tests/sources'/('astra-sources-'+stage), '--tap'], None))
	for name, events in CASES.items():
		for stage in STAGES:
			jobs.append(('dump-'+name+'-'+stage, [build/'astrac', '--dump-'+stage, *inputs(name), *vapi(name, stage)], None))
		for mode in ['O0', 'O2', 'fma']:
			jobs.append(('run-'+name+'-'+mode, [build/'tests/sources/qualification'/(name+'-'+mode)], ''.join(event+'\n' for event in events.split())))
	for mode in ['O0', 'O2', 'fma']:
		jobs.append(('identity-'+mode, [build/'tests/sources/qualification'/('object-storage-identity-'+mode)], 'M8\n'))

	def measure(job):
		name, argv, expected = job; path = logs/(name+'.log')
		p = subprocess.run(list(map(str, ['valgrind', '--vgdb=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', '--log-file='+str(path), *argv])), cwd=ROOT, capture_output=True, text=True, env=dict(os.environ, CCACHE_DISABLE='1'))
		(logs/(name+'.stdout')).write_text(p.stdout); (logs/(name+'.stderr')).write_text(p.stderr)
		text = path.read_text(); assert 'ERROR SUMMARY:' in text, name
		def number(pattern):
			match = re.search(pattern, text)
			return int(match[1].replace(',', '')) if match else 0
		return dict(name=name, exit=p.returncode, errors=number(r'ERROR SUMMARY: ([\d,]+) errors'), definite=number(r'definitely lost: ([\d,]+) bytes'), indirect=number(r'indirectly lost: ([\d,]+) bytes'), possible=number(r'possibly lost: ([\d,]+) bytes'), output_matches=expected is None or expected == p.stdout)

	with ThreadPoolExecutor(max_workers=4) as pool:
		rows = list(pool.map(measure, jobs))
	write(logs/'results.json', rows)
	assert all(row['exit'] == row['errors'] == row['definite'] == row['indirect'] == row['possible'] == 0 and row['output_matches'] for row in rows), [row for row in rows if row['exit'] or row['errors'] or not row['output_matches']]
	summary = dict(runs=len(rows), errors=0, definite=0, indirect=0, possible=0, suppressions=0)
	write(logs/'summary.json', summary); print(json.dumps(summary), flush=True)


if __name__ == '__main__':
	parser = argparse.ArgumentParser(); parser.add_argument('build', type=Path); parser.add_argument('--independent-build', type=Path); parser.add_argument('--baseline-build', type=Path, default=ROOT/'build-param-borrow-1'); parser.add_argument('--memory', action='store_true'); args = parser.parse_args()
	build = args.build.resolve(); out = build/'qualification-sources'; out.mkdir(exist_ok=True)
	if args.memory:
		memory(build, out)
	else:
		assert args.independent_build
		audit(build, args.independent_build.resolve(), args.baseline_build.resolve(), out)
