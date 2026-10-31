# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""GEN-1 complete regression, independent-build determinism and memory qualification."""
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
from execute import CASES, FIXTURES, ROOT

BASELINE = '07aeb36b4af337add8fd886992af8f6cb218047b'
SUITES = {'gen-parser', 'gen-semantic', 'gen-core-standalone', 'gen-monomorphizer-standalone', 'gen-cfg-standalone', 'gen-ssa-standalone', 'gen-nabi-standalone', 'gen-pipeline', 'gen-llvm'}
LEGACY = {'semantic', 'core', 'cfg'}


def audit(build, out, independent):
	tests = [json.loads(line) for line in (build/'meson-logs/testlog.json').read_text().splitlines()]
	assert len(tests) == len(json.loads((build/'meson-info/intro-tests.json').read_text()))
	assert all(test['result'] == 'OK' for test in tests)
	goldens = []
	for name in subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', BASELINE, 'tests'], cwd=ROOT, text=True).splitlines():
		if Path(name).suffix in {'.syntax', '.semantics', '.core', '.cfg', '.ssa', '.nabi', '.cabi', '.ll', '.stderr'}:
			content = (ROOT/name).read_bytes()
			assert content == subprocess.check_output(['git', 'show', BASELINE+':'+name], cwd=ROOT), name
			goldens.append(dict(path=name, sha256=hashlib.sha256(content).hexdigest()))
	for path in ['bootstrap/ssa', 'bootstrap/nabi', 'bootstrap/cabi', 'bootstrap/vapi', 'bootstrap/foreign', 'bootstrap/backend/llvm', 'bootstrap/cfg/ownership-flow.vala', 'bootstrap/semantic/binary-float-format.vala', 'bootstrap/semantic/binary-float-value.vala', 'bootstrap/semantic/f32-value.vala', 'bootstrap/semantic/floating-conversion.vala', 'bootstrap/semantic/pointer-parameter-contract.vala']:
		assert subprocess.check_output(['git', 'diff', BASELINE, '--', path], cwd=ROOT) == b'', path
	commands = json.loads((build/'compile_commands.json').read_text())
	generated = [row for row in commands if row['file'].endswith('.c') and 'meson-generated' in row['command']]
	assert generated and all('-DVALA_STRICT_C' in row['command'] and '-Werror' in row['command'] for row in generated)
	for stage in ['syntax', 'semantic', 'core', 'cfg', 'ssa', 'nabi']:
		for path in (ROOT/'bootstrap'/stage).glob('*.vala'):
			code = re.sub(r'/\*.*?\*/|//[^\n]*', '', path.read_text(), flags=re.S)
			assert not re.search(r'\bLLVM\w*|Astra\.Backend|CApi\.', code), path
			if stage in ['cfg', 'ssa', 'nabi']:
				assert not re.search(r'\b(?:TypeParameterType|CoreGenericCall|CoreGenericFunction|GenericFunctionSymbol)\b', code), path
	cloner = (ROOT/'bootstrap/core/generic-monomorphizer.vala').read_text()
	assert not re.search(r'\b(?:Parser|Syntax|SemanticAnalyzer|Checked\w*|FunctionSymbol|MethodSymbol|PropertySymbol|FieldSymbol)\b', cloner)
	assert 'CoreVerifier.verify_concrete (program)' in (ROOT/'bootstrap/cfg/cfg-builder.vala').read_text()
	execution = json.loads((build/'tests/gen/execution/results.json').read_text())
	assert len(execution['runs']) == 4*(len(CASES)+1)+10
	assert len(execution['value_shapes']) == 34 and sum(map(len, execution['floating_patterns'].values())) == 21
	assert len(execution['deterministic']) == 64
	# Equal physical signatures must not erase signedness or semantic instance identity.
	dedup = execution['inventories']['dedup']
	ssa = (build/'tests/gen/execution/dedup.ssa').read_text()
	llvm = (build/'tests/gen/execution/dedup.llvm').read_text()
	def physical_signature(argument):
		row = next(row for row in dedup if row['name'] == 'identity' and row['arguments'] == [argument])
		name = f"astra.gen.{row['definition']}.{row['ordinal']}"
		ordinal = re.search(r'\(function #(\d+) "'+re.escape(name)+'"', ssa)[1]
		signature = re.search(r'^define internal fastcc .* @astra\.fn\.'+ordinal+r'\([^\n]+', llvm, re.M)[0]
		return ordinal, re.sub(r'@astra\.fn\.\d+', '@INSTANCE', signature)
	for first, second in [('i8', 'u8'), ('i16', 'u16'), ('int', 'u32'), ('i16<8>', 'u16<8>')]:
		a, b = physical_signature(first), physical_signature(second)
		assert a[0] != b[0] and a[1] == b[1], (first, second, a, b)
	integer = next(row for row in dedup if row['name'] == 'identity' and row['arguments'] == ['int'])
	assert integer['requests'] == 7 and len(integer['callers']) == 6
	assert independent is not None and (independent/'astrac').is_file(), 'provide a second independently configured strict compiler build'
	deterministic = []
	for name in [*CASES, 'matrix']:
		source = build/'tests/gen/execution/matrix.astra' if name == 'matrix' else FIXTURES/f'gen-{name}.astra'
		options = ['--vapi', str(ROOT/'tests/obj-life/fixtures/lifecycle.vapi')] if name == 'owned' else []
		for stage in ['semantics', 'core', 'instances', 'llvm']:
			argv = [str(independent/'astrac'), '--dump-'+stage, str(source), *options]
			actual = subprocess.check_output(argv, cwd=ROOT)
			expected = (build/'tests/gen/execution'/(name+'.'+stage)).read_bytes()
			assert actual == expected, (name, stage)
			deterministic.append(dict(fixture=name, stage=stage, sha256=hashlib.sha256(actual).hexdigest()))
	plans = [int(plan) for test in tests for plan in re.findall(r'^1\.\.(\d+)\s*$', test['stdout'], re.M)]
	gen_plans = [int(plan) for test in tests if test['name'].split(':')[-1] in SUITES for plan in re.findall(r'^1\.\.(\d+)\s*$', test['stdout'], re.M)]
	counts = {prefix: sum(test['name'].split(':')[-1].startswith(prefix+'-') for test in tests) for prefix in ['gen', 'prop', 'f32', 'f64', 'cabi', 'vapi']}
	inventories = []
	for name, rows in execution['inventories'].items():
		core = (build/'tests/gen/execution'/(name+'.core')).read_text()
		definitions = re.findall(r'\(generic-definition #[0-9]+ "([^"]+)"', core)
		assert definitions and all(row['name'] in definitions for row in rows), name
		requests = sum(row['requests'] for row in rows)
		inventories.append(dict(fixture=name, definitions=definitions, requests=requests, dedup_hits=requests-len(rows), concrete_instances=len(rows), instances=rows))
	summary = dict(baseline=BASELINE, meson_tests=len(tests), tap_cases=sum(plans), tap_suites=len(plans), test_counts=counts, generic_tap_cases=sum(gen_plans), generic_standalone_suites=len(gen_plans), unchanged_goldens=len(goldens), unchanged_prop_goldens=sum('/prop/' in row['path'] for row in goldens), unchanged_f64_goldens=sum('/f64/' in row['path'] for row in goldens), new_goldens=len([path for path in FIXTURES.iterdir() if path.suffix in {'.syntax', '.semantics', '.core', '.instances', '.cfg', '.ssa', '.nabi', '.ll', '.stderr'}]), strict_generated_c_commands=len(generated), native_runs=len(execution['runs']), value_shapes=len(execution['value_shapes']), exact_floating_patterns=sum(map(len, execution['floating_patterns'].values())), machine_audits=len(execution['machine']), independent_build_comparisons=len(deterministic), fresh_process_comparisons=len(execution['deterministic']), dependencies_added=0)
	summary['firewall_linkage_tests'] = sum(any(marker in test['name'] for marker in ['no-llvm', 'links-qualified-llvm', 'linkage-rejects', 'firewall-rejects']) for test in tests)
	for filename, data in [('summary', summary), ('unchanged-goldens', goldens), ('independent-determinism', deterministic), ('instance-inventory', inventories)]:
		(out/(filename+'.json')).write_text(json.dumps(data, indent='\t')+'\n')
	print(json.dumps(summary), flush=True)


def losses(text):
	text = re.sub(r'^==\d+== ?', '', text, flags=re.M)
	records = re.findall(r'[\d,]+ bytes in [\d,]+ blocks are (?:definitely|indirectly|possibly) lost in loss record[^\n]*\n.*?(?=\n\n|\Z)', text, flags=re.S)
	return [re.sub(r'0x[0-9A-Fa-f]+', 'ADDRESS', re.sub(r'loss record [\d,]+ of [\d,]+', 'loss record', record)) for record in records]


def memory(build, out, baseline):
	assert baseline is not None, 'provide an independent strict build of accepted PROP-1'
	logs = out/'valgrind'; logs.mkdir(exist_ok=True)
	jobs = []
	for root, prefix, names in [(build, '', SUITES | LEGACY | {'f64-semantic-standalone', 'f64-pipeline', 'f64-llvm', 'prop-pipeline', 'prop-llvm'}), (baseline, 'baseline-', LEGACY)]:
		for test in json.loads((root/'meson-info/intro-tests.json').read_text()):
			if test['name'] in names:
				jobs.append((prefix+test['name'], test['cmd'], test['workdir'] or str(root), dict(os.environ, **test['env']), 0, None))
	execution = build/'tests/gen/execution'
	for row in json.loads((execution/'results.json').read_text())['runs']:
		jobs.append(('run-'+row['name'], [str(execution/row['name'])], str(ROOT), os.environ, row['status'], row['output']))
	for fixture in CASES:
		for stage in ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'llvm']:
			bindings = ['--vapi', str(ROOT/'tests/obj-life/fixtures/lifecycle.vapi')] if fixture == 'owned' and stage != 'syntax' else []
			jobs.append(('dump-'+fixture+'-'+stage, [str(build/'astrac'), '--dump-'+stage, str(FIXTURES/f'gen-{fixture}.astra'), *bindings], str(ROOT), os.environ, 0, None))
	jobs.append(('invalid-unused-definition', [str(build/'astrac'), '--check', str(FIXTURES/'gen-invalid.astra')], str(ROOT), os.environ, 1, ''))
	assert len({job[0] for job in jobs}) == len(jobs)

	def measure(job):
		name, argv, cwd, env, status, output = job
		command = ['valgrind', '--vgdb=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', '--log-file='+str(logs/(name+'.log')), *argv]
		p = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True)
		(logs/(name+'.stdout')).write_text(p.stdout); (logs/(name+'.stderr')).write_text(p.stderr)
		text = (logs/(name+'.log')).read_text()
		assert 'ERROR SUMMARY:' in text, name
		def number(pattern):
			match = re.search(pattern, text)
			return int(match[1].replace(',', '')) if match else 0
		return dict(name=name, command=command, exit=p.returncode, expected=status, output_matches=output is None or output == p.stdout, errors=number(r'ERROR SUMMARY: ([\d,]+) errors'), definite=number(r'definitely lost: ([\d,]+) bytes'), indirect=number(r'indirectly lost: ([\d,]+) bytes'), possible=number(r'possibly lost: ([\d,]+) bytes'), suppressed=number(r'suppressed: ([\d,]+) from'), reachable=number(r'still reachable: ([\d,]+) bytes'), lost_records=losses(text))

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
	print(json.dumps(summary), flush=True)


if __name__ == '__main__':
	parser = argparse.ArgumentParser()
	parser.add_argument('build', type=Path)
	parser.add_argument('--memory', action='store_true')
	parser.add_argument('--baseline', type=Path)
	parser.add_argument('--independent-build', type=Path)
	args = parser.parse_args()
	build = args.build.resolve(); out = build/'qualification-gen'; out.mkdir(exist_ok=True)
	if args.memory:
		memory(build, out, args.baseline.resolve() if args.baseline else None)
	else:
		audit(build, out, args.independent_build.resolve() if args.independent_build else None)
