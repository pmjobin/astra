# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact-baseline audit, independent build comparison and unsuppressed memory evidence."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import sys

sys.dont_write_bytecode = True
from qualify import ROOT, STAGES, process, run, sha
BASELINE = '58c6fcaca8b8fb275890dfdf1d38e935b1d388e0'
STASH = 'd280dd61953b9e959a1c55aae70900e0c169c606'
GOLDENS = {'.syntax', '.semantics', '.core', '.instances', '.cfg', '.ssa', '.nabi', '.cabi', '.ll', '.llvm', '.stderr', '.flow', '.flow-stderr', '.json'}


def save(path, value):
	path.write_text(json.dumps(value, indent='\t') + '\n')


def inventory(out):
	names = run(['git', 'ls-tree', '-r', '--name-only', BASELINE, 'tests'], cwd=ROOT).splitlines()
	rows = []
	for name in names:
		original = subprocess.check_output(['git', 'show', BASELINE + ':' + name], cwd=ROOT)
		rows.append(dict(path=name, sha256=sha(original), golden=Path(name).suffix in GOLDENS, changed=original != (ROOT / name).read_bytes()))
	assert not any(r['changed'] for r in rows), [r['path'] for r in rows if r['changed']]
	save(out / 'accepted-tests.json', rows)
	assert STASH in run(['git', 'stash', 'list', '--format=%H'], cwd=ROOT).splitlines()
	trees = {suffix: run(['git', 'rev-parse', STASH + suffix], cwd=ROOT).strip() for suffix in ['^{tree}', '^2^{tree}', '^3^{tree}']}
	assert list(trees.values()) == ['63c1b1d68ffa27486e9db149c9a1eea0e72e002b', '51ebb0a2fde7d44c938820349aaebbe13783c66c', '6a6d34eefab3b3e335a407e825aa2b4070477a02']
	return dict(baseline=BASELINE, tests=len(rows), goldens=sum(r['golden'] for r in rows), unchanged=len(rows), supersessions=[], manifest_sha256=sha((out / 'accepted-tests.json').read_bytes()), stash=STASH, trees=trees)


def suite(build):
	rows = [json.loads(line) for line in (build / 'meson-logs/testlog.json').read_text().splitlines()]
	registered = json.loads((build / 'meson-info/intro-tests.json').read_text())
	assert len(rows) == len(registered), ('incomplete full suite', build, len(rows), len(registered))
	assert all(r['result'] in ['OK', 'EXPECTEDFAIL'] for r in rows), [(r['name'], r['result']) for r in rows if r['result'] not in ['OK', 'EXPECTEDFAIL']]
	plans = [int(m[1]) for row in rows for m in re.finditer(r'^1\.\.(\d+)$', row.get('stdout', ''), re.M)]
	commands = json.loads((build / 'compile_commands.json').read_text())
	generated = [r for r in commands if 'meson-generated' in r['command']]
	assert generated and all('-DVALA_STRICT_C' in r['command'] and '-Werror' in r['command'] for r in generated)
	options = {r['name']: r['value'] for r in json.loads((build / 'meson-info/intro-buildoptions.json').read_text())}
	assert options['werror'] and '--fatal-warnings' in (build / 'build.ninja').read_text()
	return dict(tests=len(rows), tap_suites=len(plans), tap_cases=sum(plans), failed=0, skipped=0, strict_generated_c_commands=len(generated), firewall_tests=sum(any(x in r['name'] for x in ['no-llvm', 'links-qualified-llvm', 'linkage-rejects', 'firewall-rejects']) for r in rows))


def compare(build, candidate, independent, baseline, out):
	compilers = [build / 'astrac', candidate / 'astrac', independent / 'astrac']
	rows = []
	programs = [([ROOT / 'tests/text/fixtures/basics.astra'], []), ([ROOT / 'tests/text/fixtures' / n for n in ['00-constants.astra', '10-default.astra', '20-compare.astra', '30-client.astra']], []), ([ROOT / 'tests/text/fixtures/control.astra'], []), ([ROOT / 'tests/text/fixtures/mixed.astra', ROOT / 'lib/astra/base/contracts.astra'], ['--vapi', ROOT / 'tests/baselib/fixtures/runtime.vapi'])]
	for sources, options in programs:
		for stage in STAGES:
			args = ['--dump-' + stage, *sources, *(options if stage != 'syntax' else [])]
			expected = run([compilers[0], *args])
			for compiler in compilers[1:]:
				assert run([compiler, *args]) == expected
				rows.append(dict(program=sources[0].name, stage=stage, compiler=compiler.parent.name, sha256=sha(expected)))
	legacy = [(['tests/core/fixtures/arithmetic.astra'], []), (['tests/array/fixtures/array-basic.astra'], []), (['tests/f64/fixtures/f64-literal.astra'], []), (['examples/base/constants.astra', 'lib/astra/base/contracts.astra', 'lib/astra/base/clamp.astra', 'lib/astra/base/classify.astra', 'lib/astra/base/order.astra'], ['--vapi', ROOT / 'lib/bindings/hosted/math.vapi']), (['tests/baselib/fixtures/lifetime.astra', 'lib/astra/base/contracts.astra'], ['--vapi', ROOT / 'tests/baselib/fixtures/runtime.vapi'])]
	for names, options in legacy:
		for stage in STAGES:
			args = ['--dump-' + stage, *[ROOT / n for n in names], *(options if stage != 'syntax' else [])]
			expected = run([baseline / 'astrac', *args])
			for compiler in compilers:
				assert run([compiler, *args]) == expected
				rows.append(dict(program=names[0], stage=stage, compiler=compiler.parent.name, baseline_equal=True, sha256=sha(expected)))
				# The new builtin intentionally supersedes previously legal replacement types.
	source = out / 'formerly-user-string.astra'; source.write_text('struct string {int value;} int main(){string x={value=1};return x.value-1;}')
	assert run([baseline / 'astrac', '--check', source]) == ''
	p = process([compilers[0], '--check', source]); assert p.returncode == 1 and b'builtin' in p.stderr
	# Freeze the ordinary value namespace and standalone null behavior.
	source.write_text('int string(int n){return n;} int main(){var p=null;return string(0);}')
	for compiler in [baseline / 'astrac', *compilers]: assert run([compiler, '--check', source]) == ''
	# Every fresh full suite runs the complete CONST integer/floating/conversion oracle.
	const_oracles = [json.loads((directory / 'const-1/oracle/oracle.json').read_text()) for directory in [baseline, candidate, independent]]
	assert const_oracles[0] == const_oracles[1] == const_oracles[2]
	return dict(comparisons=len(rows), rows=rows, independent_const_oracles=const_oracles[0], builtin_replacement_superseded=True, value_namespace_preserved=True)


def memory(build, baseline, out):
	qualification = build / 'text-1/qualification'; logs = out / 'valgrind'; logs.mkdir(exist_ok=True)
	jobs = []
	for name in ['decoder', 'semantic', 'pipeline', 'llvm', 'core', 'cfg', 'ssa', 'nabi']:
		jobs.append(('test-' + name, [build / 'tests/text' / ('astra-text-' + name), '--tap'], 0, 'normal'))
	for stage in STAGES:
		jobs.append(('compiler-' + stage, [build / 'astrac', '--dump-' + stage, ROOT / 'tests/text/fixtures/basics.astra'], 0, 'normal'))
	for mode in ['O0', 'O2', 'fma']:
		for prefix in ['basics-', 'control-', 'mixed-', 'native-']:
			jobs.append((prefix + mode, [qualification / (prefix + mode + ('-gcc' if prefix == 'native-' else ''))], 0, 'normal'))
	for name in ['installed', 'relocated']:
		jobs.append(('consumer-' + name, [qualification / ('consumer-' + name)], 0, 'normal'))
	for name, source in [('escape', 'string f(string p){var x=p;return x;}'), ('decode', 'const X="\\ud800";'), ('cycle', 'const A=B;const B=A;'), ('readonly', 'void f(){var x="a";x.byte_length=2;}')]:
		path = logs / (name + '.astra'); path.write_text(source)
		jobs.append(('negative-' + name, [build / 'astrac', '--check', path], 1, 'normal'))
	control = logs / 'ordinary-name-control.astra'; control.write_text('int f(){' + ''.join('int C%d=0;' % n for n in range(5001)) + 'return 0;}')
	jobs += [('baseline-name-control', [baseline / 'astrac', '--dump-semantics', control], 99, 'inherited-glib'), ('candidate-name-control', [build / 'astrac', '--dump-semantics', control], 99, 'inherited-glib')]
	fatal_source = logs / 'fatal.astra'; fatal_source.write_text((ROOT / 'examples/base/text.astra').read_text().replace('assert_code(samples.size() == CAPACITY, 731);', 'assert_code(false, 731);'))
	fatal = logs / 'fatal'; run([build / 'astrac', fatal_source, *[ROOT / 'lib/astra/base' / (n + '.astra') for n in ['contracts', 'order', 'classify', 'clamp']], '--link-object', build / 'lib/astra/failure-trap.o', '-o', fatal])
	jobs.append(('fatal-baselib-text-consumer', [fatal], None, 'intentional-fatal'))
	def measure(job):
		name, args, status, category = job; path = logs / (name + '.log')
		p = process(['valgrind', '--vgdb=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', '--log-file=' + str(path), *args], cwd=ROOT)
		(logs / (name + '.stdout')).write_bytes(p.stdout); (logs / (name + '.stderr')).write_bytes(p.stderr)
		text = path.read_text()
		def number(pattern):
			match = re.search(pattern, text); return int(match[1].replace(',', '')) if match else 0
		row = dict(name=name, category=category, status=p.returncode, errors=number(r'ERROR SUMMARY: ([\d,]+) errors'), definite=number(r'definitely lost: ([\d,]+) bytes'), indirect=number(r'indirectly lost: ([\d,]+) bytes'), possible=number(r'possibly lost: ([\d,]+) bytes'), reachable=number(r'still reachable: ([\d,]+) bytes'), suppressed=number(r'suppressed: ([\d,]+) bytes'), allocations=number(r'total heap usage: ([\d,]+) allocs'))
		assert 'ERROR SUMMARY:' in text and row['suppressed'] == 0, row
		if category == 'inherited-glib':
			assert p.returncode == 99 and row['errors'] == 2 and row['definite'] == 49152 and row['indirect'] == row['possible'] == 0, row
			assert 'g_quark_from_string' in text and 'call_init' in text
		else:
			assert row['errors'] == 0 and row['definite'] == row['indirect'] == row['possible'] == 0, row
			assert p.returncode < 0 if category == 'intentional-fatal' else p.returncode == status, row
		return row
	with ThreadPoolExecutor(max_workers=4) as pool: rows = list(pool.map(measure, jobs))
	save(out / 'valgrind.json', rows)
	return dict(runs=len(rows), normal=sum(r['category'] == 'normal' for r in rows), fatal=sum(r['category'] == 'intentional-fatal' for r in rows), inherited=[r for r in rows if r['category'] == 'inherited-glib'], suppressions=0, new_errors=0, new_losses=0)


def main():
	parser = argparse.ArgumentParser(); parser.add_argument('build', type=Path); parser.add_argument('--baseline', required=True, type=Path); parser.add_argument('--candidate', type=Path); parser.add_argument('--independent', type=Path); parser.add_argument('--memory', action='store_true'); args = parser.parse_args()
	build = args.build.resolve(); out = ROOT / 'build/text-1/evidence'; baseline = args.baseline.resolve()
	if args.memory:
		save(out / 'memory-summary.json', memory(build, baseline, out)); print('memory PASS'); return
	candidate = args.candidate.resolve(); independent = args.independent.resolve()
	result = dict(inventory=inventory(out), comparisons=compare(build, candidate, independent, baseline, out), suites={name: suite(path) for name, path in [('baseline', baseline), ('candidate', candidate), ('independent', independent)]}, compilers={name: dict(sha256=sha((path / 'astrac').read_bytes()), version=run([path / 'astrac', '--version']).strip()) for name, path in [('development', build), ('baseline', baseline), ('candidate', candidate), ('independent', independent)]})
	save(out / 'audit.json', result); print('inventory, independent stages, legacy controls, oracles and strict suites PASS')


if __name__ == '__main__':
	main()
