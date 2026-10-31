# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""PROP-1 regression, semantic/ABI firewall and independent memory qualification."""
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

BASELINE = 'ffb889b48c6e2ebf91146b71a2a300a4bd0e1d55'
SUITES = {'prop-parser', 'prop-semantic', 'prop-core-standalone', 'prop-cfg-standalone', 'prop-ssa-standalone', 'prop-nabi-standalone', 'prop-pipeline', 'prop-llvm'}
LEGACY = {'semantic', 'core', 'cfg'}


def audit(build, out):
	tests = [json.loads(line) for line in (build/'meson-logs/testlog.json').read_text().splitlines()]
	assert len(tests) == len(json.loads((build/'meson-info/intro-tests.json').read_text()))
	assert all(test['result'] == 'OK' for test in tests)
	goldens = []
	for name in subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', BASELINE, 'tests'], cwd=ROOT, text=True).splitlines():
		if Path(name).suffix in {'.syntax', '.semantics', '.core', '.cfg', '.ssa', '.nabi', '.cabi', '.ll', '.stderr'}:
			content = (ROOT/name).read_bytes()
			assert content == subprocess.check_output(['git', 'show', BASELINE+':'+name], cwd=ROOT), name
			goldens.append(dict(path=name, sha256=hashlib.sha256(content).hexdigest()))
	for path in ['bootstrap/cabi', 'bootstrap/vapi', 'bootstrap/foreign', 'bootstrap/semantic/binary-float-format.vala', 'bootstrap/semantic/binary-float-value.vala', 'bootstrap/semantic/f32-value.vala', 'bootstrap/semantic/floating-conversion.vala', 'bootstrap/semantic/pointer-parameter-contract.vala', 'bootstrap/cfg/ownership-flow.vala', 'bootstrap/backend/llvm/llvm-function-lowering.vala', 'bootstrap/backend/llvm/llvm-scalar-lowering.vala', 'bootstrap/nabi/native-type-mapper.vala']:
		assert subprocess.check_output(['git', 'diff', BASELINE, '--', path], cwd=ROOT) == b'', path
	commands = json.loads((build/'compile_commands.json').read_text())
	generated = [row for row in commands if row['file'].endswith('.c') and 'meson-generated' in row['command']]
	assert generated and all('-DVALA_STRICT_C' in row['command'] and '-Werror' in row['command'] for row in generated)
	for stage in ['syntax', 'semantic', 'core', 'cfg', 'ssa', 'nabi']:
		for path in (ROOT/'bootstrap'/stage).glob('*.vala'):
			code = re.sub(r'/\*.*?\*/|//[^\n]*', '', path.read_text(), flags=re.S)
			assert not re.search(r'\bLLVM\w*|Astra\.Backend|CApi\.', code), path
			assert not re.search(r'PropertyPlace|PropertyFieldPlace|PropertyStoragePlace|AccessorPlace|PropertyStorage|LanePlace|NativeProperty\b', code), path
	model = (ROOT/'bootstrap/nabi/native-model.vala').read_text()
	old_model = subprocess.check_output(['git', 'show', BASELINE+':src/nabi/native-model.vala'], cwd=ROOT, text=True)
	for name in ['NativeAbiVersion', 'NativeScalarType']:
		pattern = r'public enum '+name+r' \{.*?\n\t\}'
		assert re.search(pattern, model, re.S)[0] == re.search(pattern, old_model, re.S)[0], name
	for stage, accessor, method in [('semantic', 'PropertyAccessorSymbol', 'MethodSymbol'), ('core', 'CorePropertyAccessor', 'CoreMethod'), ('cfg', 'CfgPropertyAccessor', 'CfgMethod'), ('ssa', 'SsaPropertyAccessor', 'SsaMethod')]:
		code = '\n'.join(path.read_text() for path in (ROOT/'bootstrap'/stage).glob('*.vala'))
		assert len(re.findall(r'class '+accessor+r'\s*:', code)) == 1
		assert not re.search(r'class '+accessor+r'\s*:\s*'+method, code)
		assert not re.search(r'(?:Struct|Class)PropertyResolver', code)
		# Field symbols are still created only for explicit source field declarations.
	analyzer = (ROOT/'bootstrap/semantic/analyzer.vala').read_text()
	assert analyzer.count('new StructFieldSymbol (') == 1
	assert analyzer.count('new CheckedReceiverAddressExpression (') == 1
	assert analyzer.count('new CheckedObjectReceiverExpression (') == 1
	assert 'var body = check_block (syntax.body, symbol, null, locals);' in analyzer
	assert 'value' not in re.findall(r'values.insert \("([^"]+)"', analyzer)
	execution = json.loads((build/'tests/prop/execution/results.json').read_text())
	assert len(execution['runs']) == 4 * (len(CASES)+1) + 2
	assert len(execution['transport_bits']) == 11 and len(execution['value_shapes']) >= 30
	plans = [int(plan) for test in tests for plan in re.findall(r'^1\.\.(\d+)\s*$', test['stdout'], re.M)]
	prop_plans = [int(plan) for test in tests if test['name'].split(':')[-1] in SUITES for plan in re.findall(r'^1\.\.(\d+)\s*$', test['stdout'], re.M)]
	summary = dict(baseline=BASELINE, meson_tests=len(tests), tap_cases=sum(plans), tap_suites=len(plans), property_tests=sum(test['name'].split(':')[-1].startswith('prop-') for test in tests), property_tap_cases=sum(prop_plans), property_standalone_suites=len(prop_plans), f64_tests=sum(test['name'].split(':')[-1].startswith('f64-') for test in tests), f32_tests=sum(test['name'].split(':')[-1].startswith('f32-') for test in tests), unchanged_goldens=len(goldens), unchanged_f64_goldens=sum('/f64/' in item['path'] for item in goldens), strict_generated_c_commands=len(generated), native_runs=len(execution['runs']), value_shapes=len(execution['value_shapes']), machine_audits=len(execution['machine']), f64_transport_patterns=len(execution['transport_bits']), dependencies_added=0)
	summary['firewall_linkage_tests'] = sum(any(marker in test['name'] for marker in ['no-llvm', 'links-qualified-llvm', 'linkage-rejects', 'firewall-rejects']) for test in tests)
	(out/'summary.json').write_text(json.dumps(summary, indent='\t')+'\n')
	(out/'unchanged-goldens.json').write_text(json.dumps(goldens, indent='\t')+'\n')
	print(json.dumps(summary), flush=True)


def losses(text):
	text = re.sub(r'^==\d+== ?', '', text, flags=re.M)
	records = re.findall(r'[\d,]+ bytes in [\d,]+ blocks are (?:definitely|indirectly|possibly) lost in loss record[^\n]*\n.*?(?=\n\n|\Z)', text, flags=re.S)
	return [re.sub(r'0x[0-9A-Fa-f]+', 'ADDRESS', re.sub(r'loss record [\d,]+ of [\d,]+', 'loss record', record)) for record in records]


def memory(build, out, baseline):
	assert baseline is not None, 'provide an independent strict build of accepted F64-1'
	logs = out/'valgrind'; logs.mkdir(exist_ok=True)
	jobs = []
	for root, prefix, names in [(build, '', SUITES | LEGACY | {'f64-semantic-standalone', 'f64-pipeline', 'f64-llvm'}), (baseline, 'baseline-', LEGACY)]:
		for test in json.loads((root/'meson-info/intro-tests.json').read_text()):
			if test['name'] in names:
				jobs.append((prefix+test['name'], test['cmd'], test['workdir'] or str(root), dict(os.environ, **test['env']), 0, None))
	execution = build/'tests/prop/execution'
	for row in json.loads((execution/'results.json').read_text())['runs']:
		if row['name'] in CASES or row['name'] in ['matrix', 'transport-O0', 'transport-O2-fma', 'alias-callable-O2', 'effect-callable-O2', 'f64-callable-O2']:
			jobs.append(('run-'+row['name'], [str(execution/row['name'])], str(ROOT), os.environ, row['status'], row['output']))
	for fixture in CASES:
		for stage in ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']:
			bindings = ['--vapi', str(ROOT/'tests/obj-life/fixtures/lifecycle.vapi')] if fixture == 'life' and stage != 'syntax' else []
			jobs.append(('dump-'+fixture+'-'+stage, [str(build/'astrac'), '--dump-'+stage, str(FIXTURES/f'prop-{fixture}.astra'), *bindings], str(ROOT), os.environ, 0, None))
	jobs.append(('invalid-property', [str(build/'astrac'), '--check', str(FIXTURES/'prop-invalid.astra')], str(ROOT), os.environ, 1, ''))
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
	args = parser.parse_args()
	build = args.build.resolve(); out = build/'qualification-prop'; out.mkdir(exist_ok=True)
	if args.memory:
		memory(build, out, args.baseline.resolve() if args.baseline else None)
	else:
		audit(build, out)
