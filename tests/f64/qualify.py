# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Reproducible F64 regression/firewall/strict-build and Valgrind evidence."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import argparse
import json
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True
from execute import FIXTURES, ROOT, FLAGS, FUSED

BASELINE = '3cf216df0588e62c83da0ff5f1111fad68456387'
SUITES = {'f64-values', 'f64-semantic-standalone', 'f64-core-standalone', 'f64-cfg-standalone', 'f64-ssa-standalone', 'f64-nabi-standalone', 'f64-pipeline', 'f64-llvm'}
LEGACY = {'semantic', 'core', 'cfg'}


def audit(build, out):
	tests = [json.loads(line) for line in (build/'meson-logs/testlog.json').read_text().splitlines()]
	assert len(tests) == len(json.loads((build/'meson-info/intro-tests.json').read_text()))
	assert all(test['result'] == 'OK' for test in tests), [(t['name'], t['result']) for t in tests if t['result'] != 'OK']
	goldens = []
	for name in subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', BASELINE, 'tests'], cwd=ROOT, text=True).splitlines():
		if Path(name).suffix in {'.syntax', '.semantics', '.core', '.cfg', '.ssa', '.nabi', '.cabi', '.ll', '.stderr'}:
			assert (ROOT/name).read_bytes() == subprocess.check_output(['git', 'show', BASELINE+':'+name], cwd=ROOT), name
			goldens.append(name)
	for name in ['bootstrap/cabi', 'bootstrap/vapi', 'bootstrap/foreign', 'bootstrap/semantic/integer-conversion.vala', 'bootstrap/semantic/vector-dot.vala', 'bootstrap/semantic/vector-dsp.vala', 'bootstrap/semantic/pointer-parameter-contract.vala', 'bootstrap/semantic/semantic-lifecycle.vala', 'bootstrap/semantic/semantic-object-results.vala']:
		assert not subprocess.check_output(['git', 'diff', BASELINE, '--', name], cwd=ROOT), name
	for stage in ['syntax', 'semantic', 'core', 'cfg', 'ssa', 'nabi']:
		for path in (ROOT/'bootstrap'/stage).glob('*.vala'):
			code = re.sub(r'/\*.*?\*/|//[^\n]*', '', path.read_text(), flags=re.S)
			assert not re.search(r'\bLLVM\w*|Astra\.Backend|CApi\.', code), path
	for name in ['binary-float-format', 'binary-float-value', 'f32-value']:
		path = ROOT/f'bootstrap/semantic/{name}.vala'
		code = re.sub(r'/\*.*?\*/|//[^\n]*', '', path.read_text(), flags=re.S)
		assert not re.search(r'\b(?:float|double|strtod|strtof|scanf|atof|g_ascii_strtod|LLVM\w*)\b', code), path
		matches = list(build.glob(f'**/meson-generated*{name}*.c.o'))
		assert matches, name
		# Same enumerator ordering and values for every existing ABI profile/channel.
	model = (ROOT/'bootstrap/nabi/native-model.vala').read_text()
	before = subprocess.check_output(['git', 'show', BASELINE+':src/nabi/native-model.vala'], cwd=ROOT, text=True)
	for enum, addition in [('NativeAbiVersion', 'FP64_V6'), ('NativeScalarType', 'F64')]:
		pattern = r'public enum '+enum+r' \{(.*?);'
		old = re.findall(r'\b[A-Z][A-Z0-9_]+\b', re.search(pattern, before, re.S)[1])
		new = re.findall(r'\b[A-Z][A-Z0-9_]+\b', re.search(pattern, model, re.S)[1])
		assert new == old + [addition], (enum, old, new)
	commands = json.loads((build/'compile_commands.json').read_text())
	generated = [row for row in commands if row['file'].endswith('.c') and 'meson-generated' in row['command']]
	assert generated and all('-DVALA_STRICT_C' in row['command'] and '-Werror' in row['command'] for row in generated)
	for path in [build/'tests/f64/astra-f64-convert.p/binary-float-value.c', build/'tests/f32/astra-f32-convert.p/f32-value.c']:
		code = re.sub(r'/\*.*?\*/|//[^\n]*', '', path.read_text(), flags=re.S)
		# Vala #line filenames contain "binary-float-value", not C float use.
		code = re.sub(r'^\s*#line[^\n]*', '', code, flags=re.M)
		assert not re.search(r'\b(?:float|double|strtod|strtof|scanf|atof|g_ascii_strtod|LLVM\w*)\b', code), path
	plans = [int(plan) for test in tests for plan in re.findall(r'^1\.\.(\d+)\s*$', test['stdout'], re.M)]
	new_plans = [int(plan) for test in tests if test['name'].split(':')[-1] in SUITES or test['name'].endswith('f64-values-ubsan') for plan in re.findall(r'^1\.\.(\d+)\s*$', test['stdout'], re.M)]
	execution = json.loads((build/'tests/f64/execution/results.json').read_text())
	oracle = json.loads((build/'tests/f64/oracle-results.json').read_text())
	f32 = json.loads((build/'tests/f32/oracle-results.json').read_text())
	f32_runtime = json.loads((build/'tests/f32/execution/results.json').read_text())
	# Repeat F32's physical audit without its historical INTS-1 source freeze.
	f32_audits = out/'f32'
	f32_audits.mkdir(exist_ok=True)
	for row in f32_runtime:
		if 'fixture' not in row:
			continue
		name = row['fixture']
		bindings = [arg for part in ['types', 'api'] for arg in ['--vapi', ROOT/f'tests/resource/fixtures/resource-{part}.vapi']] if name == 'ownership' else []
		llvm = subprocess.check_output([build/'astrac', '--dump-llvm', ROOT/f'tests/f32/fixtures/f32-{name}.astra', *bindings], text=True)
		assert not re.search(FLAGS, llvm) and not re.search(r'\b(?:double|fpext|fptrunc|sitofp|uitofp|fptosi|fptoui)\b', llvm), name
		(f32_audits/(name+'.ll')).write_text(llvm)
		machine = subprocess.check_output(['objdump', '-d', build/'tests/f32/execution'/name], text=True)
		assert not re.search(FUSED, machine), name
		(f32_audits/(name+'.machine')).write_text(machine)
		if name == 'rounding':
			subprocess.run(['llc', '-O2', '-mattr=+fma', '-filetype=obj', '-relocation-model=pic', f32_audits/(name+'.ll'), '-o', f32_audits/'rounding-fma.o'], check=True)
			fma = subprocess.check_output(['objdump', '-dr', f32_audits/'rounding-fma.o'], text=True)
			assert 'mulss' in fma and 'addss' in fma and not re.search(FUSED, fma)
			(f32_audits/'rounding-fma.machine').write_text(fma)
	objects = out/'objects'
	objects.mkdir(exist_ok=True)
	for name in [*FIXTURES, 'matrix']:
		stem = build/'tests/f64/execution'/(name+'-O0')
		subprocess.run(['llvm-as', stem.with_suffix('.ll'), '-o', objects/(name+'.bc')], check=True)
		undefined = subprocess.check_output(['nm', '-u', stem.with_suffix('.o')], text=True)
		expected = {'life_create', 'life_destroy', 'life_id', 'life_live', 'life_record'} if name == 'ownership' else set()
		assert {line.split()[-1] for line in undefined.splitlines()} == expected, (name, undefined)
		header = subprocess.check_output(['readelf', '-h', stem.with_suffix('.o')], text=True)
		assert 'ELF64' in header and 'X86-64' in header, name
		(objects/(name+'.undefined')).write_text(undefined)
		(objects/(name+'.header')).write_text(header)
		machine = stem.with_suffix('.machine').read_text()
		assert not re.search(r'\b(?:fld|fst)\w*\b', machine), name
		if name in ['pointer', 'array', 'slice']:
			assert 'movsd' in machine, name
		if name == 'compare':
			assert 'ucomisd' in machine, name
		if name == 'call':
			assert re.search(r'\bcall\b', machine), name
	summary = dict(baseline=BASELINE, meson_tests=len(tests), f64_meson_tests=sum('f64-' in t['name'] for t in tests), f32_meson_tests=sum(t['name'].split(':')[-1].startswith('f32-') for t in tests), tap_suites=len(plans), tap_cases=sum(plans), f64_tap_suites=len(new_plans), f64_tap_cases=sum(new_plans), unchanged_baseline_goldens=len(goldens), unchanged_f32_goldens=sum(name.startswith('tests/f32/') for name in goldens), strict_generated_c_commands=len(generated), firewall_linkage_tests=sum('no-llvm' in t['name'] or 'links-qualified-llvm' in t['name'] or 'linkage-rejects' in t['name'] or 'firewall-rejects' in t['name'] for t in tests), runtime_executions=len(execution['runs']), machine_fixtures=len(execution['machine']), matrix=execution['matrix'], oracle=oracle, f32_oracle=f32, f32_runtime=f32_runtime, dependencies_added=0)
	summary['object_audits'] = len(FIXTURES) + 1
	summary['f32_physical_audits'] = sum('fixture' in row for row in f32_runtime)
	(out/'summary.json').write_text(json.dumps(summary, indent='\t')+'\n')
	(out/'unchanged-goldens.json').write_text(json.dumps(goldens, indent='\t')+'\n')
	print(json.dumps(summary), flush=True)


def losses(text):
	text = re.sub(r'^==\d+== ?', '', text, flags=re.M)
	records = re.findall(r'[\d,]+ bytes in [\d,]+ blocks are (?:definitely|indirectly|possibly) lost in loss record[^\n]*\n.*?(?=\n\n|\Z)', text, flags=re.S)
	return [re.sub(r'0x[0-9A-Fa-f]+', 'ADDRESS', re.sub(r'loss record [\d,]+ of [\d,]+', 'loss record', record)) for record in records]


def memory(build, out, baseline):
	assert baseline is not None, 'provide an independent strict build of baseline 3cf216df'
	logs = out/'valgrind'
	logs.mkdir(exist_ok=True)
	jobs = []
	for root, prefix, names in [(build, '', SUITES | LEGACY | {'f32-values', 'f32-pipeline', 'f32-llvm'}), (baseline, 'baseline-', LEGACY)]:
		for test in json.loads((root/'meson-info/intro-tests.json').read_text()):
			if test['name'] in names:
				jobs.append((prefix+test['name'], test['cmd'], test['workdir'] or str(root), dict(os.environ, **test['env']), 0, None, None))
	execution = build/'tests/f64/execution'
	for row in json.loads((execution/'results.json').read_text())['runs']:
		if row['name'] in FIXTURES or row['name'] in ['matrix-O0', 'matrix-fma', 'round-fma']:
			jobs.append(('run-'+row['name'], [str(execution/row['name'])], str(ROOT), os.environ, row['status'], row['output'], None))
	for fixture in ['literal', 'convert', 'loop', 'pointer', 'array', 'slice', 'object', 'ownership']:
		for stage in ['semantics', 'ssa', 'llvm']:
			bindings = ['--vapi', str(ROOT/'tests/obj-life/fixtures/lifecycle.vapi')] if fixture == 'ownership' else []
			jobs.append(('dump-'+fixture+'-'+stage, [str(build/'astrac'), '--dump-'+stage, str(ROOT/f'tests/f64/fixtures/f64-{fixture}.astra'), *bindings], str(ROOT), os.environ, 0, None, None))
	inputs = 'decimal 9007199254740993.0\ndecimal 4.9406564584124654e-324\ndecimal 1.00000000000000011102230246251565404236316680908203125' + '0' * 10000 + '1\nwiden 80000000\nwiden 00000001\nnarrow 3ff0000010000000\nnarrow 7fefffffffffffff\nnarrow 8000000000000001\nnarrow 7ff0000000000001\n'
	jobs.append(('literal-conversion-driver', [str(build/'tests/f64/astra-f64-convert')], str(ROOT), os.environ, 0, '0x4340000000000000\n0x0000000000000001\n0x3ff0000000000001\n0x8000000000000000\n0x36a0000000000000\n0x3f800000\n0x7f800000\n0x80000000\n0x7fc00000\n', inputs))

	def measure(job):
		name, argv, cwd, env, status, output, inputs = job
		command = ['valgrind', '--vgdb=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', '--log-file='+str(logs/(name+'.log')), *argv]
		p = subprocess.run(command, cwd=cwd, env=env, input=inputs, capture_output=True, text=True)
		(logs/(name+'.stdout')).write_text(p.stdout)
		(logs/(name+'.stderr')).write_text(p.stderr)
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
			if name.startswith('run-') and row['expected'] == 0:
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
	build = args.build.resolve()
	out = build/'qualification-f64'
	out.mkdir(exist_ok=True)
	if args.memory:
		memory(build, out, args.baseline.resolve() if args.baseline else None)
	else:
		audit(build, out)
