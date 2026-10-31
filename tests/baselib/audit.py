# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact accepted-tree audit, independent compilation and unsuppressed memory evidence."""
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
from qualify import ROOT, BASE, EQUALITY, MATH, FIX, STAGES, MODES, Campaign, process, run, write_json

BASELINE = '63ab1eaf5076eced5e2d12f8bc88dc656e9b7b3c'
GOLDENS = {'.syntax', '.semantics', '.core', '.instances', '.cfg', '.ssa', '.nabi', '.cabi', '.ll', '.stderr', '.flow', '.flow-stderr', '.json'}


def consumers():
	return {
		'pure': ([ROOT / 'examples/base/pure.astra', BASE[0], BASE[1]], []),
		'contracts': ([ROOT / 'examples/base/contracts.astra', *BASE], []),
		'equality': ([ROOT / 'examples/base/diagnostics.astra', EQUALITY], []),
		'math': ([ROOT / 'examples/base/math.astra'], ['--vapi', MATH]),
		'buffer': ([*sorted((ROOT / 'examples/base/buffer').glob('*.astra')), *BASE, EQUALITY], ['--vapi', MATH]),
		'permutation': ([BASE[0], BASE[2], BASE[3], FIX / 'permutation.astra'], []),
		'lifetime': ([FIX / 'lifetime.astra', BASE[2]], ['--vapi', FIX / 'runtime.vapi']),
	}


def golden_audit(out):
	rows = []
	for name in run(['git', 'ls-tree', '-r', '--name-only', BASELINE, 'tests']).splitlines():
		before = subprocess.check_output(['git', 'show', BASELINE + ':' + name], cwd=ROOT)
		assert before == (ROOT / name).read_bytes(), ('accepted test changed', name)
		rows.append(dict(path=name, sha256=hashlib.sha256(before).hexdigest(), golden=Path(name).suffix in GOLDENS))
	write_json(out / 'accepted-tree.json', rows)
	goldens = [row for row in rows if row['golden']]
	write_json(out / 'goldens.json', goldens)
	return dict(accepted_test_files=len(rows), accepted_tree_manifest_sha256=hashlib.sha256((out / 'accepted-tree.json').read_bytes()).hexdigest(), baseline_goldens=len(goldens), golden_manifest_sha256=hashlib.sha256((out / 'goldens.json').read_bytes()).hexdigest(), golden_suffixes={suffix: sum(Path(row['path']).suffix == suffix for row in goldens) for suffix in sorted(GOLDENS)}, new_committed_goldens=0, changed_accepted_files=[])


def audit(build, independent, baseline, out):
	summary = golden_audit(out)
	# All production language, ownership, ABI and LLVM implementations are frozen.
	allowed = {'bootstrap/main.vala', 'bootstrap/driver/host-linker.vala', 'bootstrap/driver/native-compilation.vala', 'bootstrap/driver/executable-output.vala', 'bootstrap/driver/meson.build'}
	changed = set(run(['git', 'diff', '--name-only', BASELINE, '--', 'bootstrap']).splitlines())
	assert changed <= allowed, changed
	for path in (ROOT / 'bootstrap').rglob('*.vala'):
		assert not re.search(r'astra_base_|"(?:min|max|clamp|assert|assert_code|sqrt_f32|sqrt_f64)"', path.read_text()), path
	comparisons = []
	for name, (sources, options) in consumers().items():
		for stage in STAGES:
			args = ['--dump-' + stage, *sources, *(options if stage != 'syntax' else [])]
			current = run([build / 'astrac', *args])
			assert current == run([baseline / 'astrac', *args]) == run([independent / 'astrac', *args]), (name, stage)
			comparisons.append(name + ':' + stage)
			# Every generated runtime program must have the same machine instructions and relocations.
	qualification = build / 'tests/baselib/qualification'
	other = independent / 'tests/baselib/qualification'
	records = json.loads((qualification / 'results.json').read_text())
	other_records = json.loads((other / 'results.json').read_text())
	assert records == other_records, 'independent runtime/canonical records differ'
	machine = []
	for row in records['runs']:
		name = row['name'] + '-' + row['mode'] + '.machine'
		assert (qualification / name).read_text().split('Disassembly of section', 1)[1] == (other / name).read_text().split('Disassembly of section', 1)[1], name
		machine.append(name)
	for item in records['dumps']:
		name, stage = item.split(':')
		assert (qualification / (name + '.' + stage)).read_bytes() == (other / (name + '.' + stage)).read_bytes(), item
		# Observe argument order for all three generic selectors and both assertion arguments.
		# Run the very same ordinary sources through the accepted compiler as well.
	effects = []
	for label, compiler in [('accepted', baseline / 'astrac'), ('current', build / 'astrac'), ('independent', independent / 'astrac')]:
		directory = out / ('effects-' + label); directory.mkdir(exist_ok=True)
		probe = Campaign(compiler, directory)
		probe.execute('effects', [FIX / 'effects.astra', *BASE], build / 'lib/astra/failure-trap.o', stdout=''.join('E' + str(n) + '\n' for n in range(1, 10)))
		effects += [dict(compiler=label, **row) for row in probe.records['runs']]
	write_json(out / 'effects.json', effects)
	for name in ['numerical', 'math', 'permutation']:
		text = (qualification / (name + '.llvm')).read_text()
		assert 'declare void @astra_base_fail(i32, i32)' in text
		assert not re.search(r'\b(?:noreturn|readnone|readonly|nounwind)\b', text), name
		# No LLVM may enter either new frontend/driver test executable.
	for path in [build / 'tests/baselib/astra-baselib-pipeline', build / 'tests/baselib/astra-baselib-link-inputs']:
		assert 'LLVM' not in run(['nm', '-u', path]) and 'LLVM' not in run(['ldd', path])
	run(['sh', ROOT / 'tests/llvm/check-linkage.sh', 'ldd', 'nm', 'readelf', 'llvm-config', build / 'tests/baselib/astra-baselib-llvm'])
	tests = [json.loads(line) for line in (build / 'meson-logs/baselib-final.json').read_text().splitlines()]
	assert len(tests) == len(json.loads((build / 'meson-info/intro-tests.json').read_text()))
	assert all(row['result'] == 'OK' for row in tests), [(row['name'], row['result']) for row in tests if row['result'] != 'OK']
	plans = [int(m[1]) for row in tests if (m := re.search(r'^1\.\.(\d+)$', row.get('stdout', ''), re.M))]
	commands = json.loads((build / 'compile_commands.json').read_text())
	generated = [row for row in commands if row['file'].endswith('.c') and 'meson-generated' in row['command']]
	assert all('-DVALA_STRICT_C' in row['command'] and '-Werror' in row['command'] for row in generated)
	for directory in [build, independent, baseline]:
		options = {row['name']: row['value'] for row in json.loads((directory / 'meson-info/intro-buildoptions.json').read_text())}
		assert options['werror'] and '--fatal-warnings' in (directory / 'build.ninja').read_text()
	installation = json.loads((build / 'tests/baselib/integration/results.json').read_text())
	summary.update(baseline=BASELINE, compiler_production_files=sorted(changed), meson_tests=len(tests), tap_suites=len(plans), tap_cases=sum(plans), strict_generated_c_commands=len(generated), baseline_and_independent_stage_comparisons=len(comparisons), independent_generated_dumps=len(records['dumps']), independent_machine_comparisons=len(machine), fresh_process_comparisons=len(records['dumps']), runtime_executions=len(records['runs']), normal_runs=sum(not row['fatal'] for row in records['runs']), fatal_runs=sum(row['fatal'] for row in records['runs']), negative_stage_checks=len(records['negative']), source_permutations=len(records['permutations']), permutation_stage_comparisons=len(records['permutations']) * len(STAGES), relocated_stage_comparisons=16, explicit_inferred_stage_comparisons=8, stage_lifetime_consumers=len(consumers()), firewall_linkage_tests=sum(any(x in row['name'] for x in ['no-llvm', 'links-qualified-llvm', 'linkage-rejects', 'firewall-rejects']) for row in tests), matrix=records['matrix'], driver_failure_controls=installation['driver_failures'], qualified_target={key: installation[key] for key in ['target', 'compiler', 'libc', 'llvm']}, dependencies_added=0)
	summary.update(baseline_compiler_sha256=hashlib.sha256((baseline / 'astrac').read_bytes()).hexdigest(), baseline_version=run([baseline / 'astrac', '--version']).strip(), additional_library_llvm_linkage_audits=1)
	summary['additional_three_compiler_effect_executions'] = len(effects)
	write_json(out / 'comparisons.json', comparisons)
	write_json(out / 'summary.json', summary)
	print(json.dumps({key: value for key, value in summary.items() if key != 'matrix'}), flush=True)


def memory(build, out):
	logs = out / 'valgrind'; logs.mkdir(exist_ok=True)
	jobs = []
	for name, (sources, options) in consumers().items():
		for stage in STAGES[1:]:
			jobs.append(('compiler-' + name + '-' + stage, [build / 'astrac', '--dump-' + stage, *sources, *options], False, None))
	for name in ['pipeline', 'llvm']:
		jobs.append(('test-' + name, [build / ('tests/baselib/astra-baselib-' + name), '--tap'], False, None))
	for name in ['math', 'buffer']:
		sources, options = consumers()[name]
		jobs.append(('compile-' + name, [build / 'astrac', *sources, *options, '--link-object', build / 'lib/astra/failure-hosted.o', '--link-library=m', '-o', logs / ('compiled-' + name)], False, ''))
	records = json.loads((build / 'tests/baselib/qualification/results.json').read_text())
	for row in records['runs']:
		if not row['fatal']:
			jobs.append(('run-' + row['name'] + '-' + row['mode'], [build / 'tests/baselib/qualification' / (row['name'] + '-' + row['mode'])], False, row['stdout']))
	for name in ['pure', 'contracts', 'diagnostics', 'math', 'buffer']:
		jobs.append(('installed-' + name, [build / 'tests/baselib/integration/installed' / name], False, ''))
		# Deliberately fatal witnesses are recorded separately; their live ownership is intentional.
	for name in ['lifetime-fatal', 'assert-hosted', 'assert-trap', 'equality-f64']:
		jobs.append(('fatal-' + name, [build / 'tests/baselib/qualification' / (name + '-O0')], True, None))
	def measure(job):
		name, argv, fatal, expected = job; path = logs / (name + '.log')
		p = process(['valgrind', '--vgdb=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', '--log-file=' + str(path), *argv])
		(logs / (name + '.stdout')).write_text(p.stdout); (logs / (name + '.stderr')).write_text(p.stderr)
		text = path.read_text(); assert 'ERROR SUMMARY:' in text, name
		def number(pattern):
			m = re.search(pattern, text); return int(m[1].replace(',', '')) if m else 0
		row = dict(name=name, status=p.returncode, fatal=fatal, errors=number(r'ERROR SUMMARY: ([\d,]+) errors'), definite=number(r'definitely lost: ([\d,]+) bytes'), indirect=number(r'indirectly lost: ([\d,]+) bytes'), possible=number(r'possibly lost: ([\d,]+) bytes'), reachable=number(r'still reachable: ([\d,]+) bytes'), suppressed=number(r'suppressed: ([\d,]+) bytes'), output_matches=expected is None or p.stdout == expected)
		row.update(allocations=number(r'total heap usage: ([\d,]+) allocs'), frees=number(r'total heap usage: [\d,]+ allocs, ([\d,]+) frees'), bytes_allocated=number(r'total heap usage: [\d,]+ allocs, [\d,]+ frees, ([\d,]+) bytes allocated'), in_use_at_exit=number(r'in use at exit: ([\d,]+) bytes'))
		assert p.returncode < 0 if fatal else p.returncode == 0, row
		assert row['errors'] == row['suppressed'] == 0 and row['output_matches'], row
		if not fatal:
			assert row['definite'] == row['indirect'] == row['possible'] == 0, row
		return row
	with ThreadPoolExecutor(max_workers=4) as pool:
		rows = list(pool.map(measure, jobs))
	write_json(logs / 'results.json', rows)
	summary = dict(runs=len(rows), normal_runs=sum(not row['fatal'] for row in rows), fatal_runs=sum(row['fatal'] for row in rows), errors=0, normal_definite=0, normal_indirect=0, normal_possible=0, suppressions=0, fatal_measurements=[row for row in rows if row['fatal']])
	write_json(logs / 'summary.json', summary); print(json.dumps(summary), flush=True)


if __name__ == '__main__':
	parser = argparse.ArgumentParser(); parser.add_argument('build', type=Path); parser.add_argument('--independent-build', type=Path); parser.add_argument('--baseline-build', type=Path); parser.add_argument('--memory', action='store_true'); args = parser.parse_args()
	build = args.build.resolve(); out = build / 'tests/baselib/audit'; out.mkdir(parents=True, exist_ok=True)
	if args.memory:
		memory(build, out)
	else:
		assert args.independent_build and args.baseline_build
		audit(build, args.independent_build.resolve(), args.baseline_build.resolve(), out)
