# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Reproducible NUM-CONV-1 golden, lifetime, determinism, machine and memory evidence."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import signal
import subprocess
import sys

sys.dont_write_bytecode = True
from execute import ROOT, FIXTURES, INTEGERS, F32, F64, Fraction, int_values, limits, run

BASELINE = '04530f13800bdbba792b4214f182d276557fb4d8'
STAGES = ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
EXTENSIONS = {'.syntax', '.semantics', '.core', '.instances', '.cfg', '.ssa', '.nabi', '.cabi', '.ll', '.stderr'}
LEGACY = {'semantic', 'core', 'cfg'}


def write(path, value):
	path.write_text(json.dumps(value, indent='\t')+'\n')


def git(*args):
	return subprocess.check_output(['git', *args], cwd=ROOT)


def integer_evidence(out):
	matrices = {}
	for name, width, signed in INTEGERS:
		rows = [dict(integer=value, f32=f'0x{F32.round(Fraction(value)):08x}', f64=f'0x{F64.round(Fraction(value)):016x}') for value in int_values(width, signed)]
		assert all(F64.value(int(row['f64'], 16)) == row['integer'] for row in rows)
		entry = dict(cases=len(rows), exact_f64=True, sha256=hashlib.sha256(json.dumps(rows, sort_keys=True, separators=(',', ':')).encode()).hexdigest())
		low, high = limits(width, signed)
		if width == 8:
			entry['all_results'] = rows
		elif width == 16:
			assert all(F32.value(int(row['f32'], 16)) == row['integer'] for row in rows)
			entry.update(exhaustive_range=[low, high], exact_f32=True)
		else:
			points = {low, low+1, -1, 0, 1, high-1, high} | {sign*((1 << 24)+delta) for sign in [-1, 1] for delta in range(-5, 6)}
			entry['selected_results'] = [row for row in rows if row['integer'] in points]
		matrices[name] = entry
	write(out/'integer-matrices.json', matrices)
	return hashlib.sha256((out/'integer-matrices.json').read_bytes()).hexdigest()


def machine(execution, out):
	parts = ['ASTRA-NUM-CONV-1 machine audit\nLLVM 22; x86-64 Linux. Machine instructions realize, not define, semantics.\n']
	# The matrix orders signed/unsigned 32-bit source/destination pairs last.
	for mode in ['O0', 'O2', 'fma']:
		llvm = (execution/('matrix-'+mode+'.ll')).read_text()
		assembly = (execution/('matrix-'+mode+'.machine')).read_text()
		for number in range(16, 24):
			symbol = 'astra.fn.'+str(number)
			ir = re.search(r'^define [^\n]*@'+re.escape(symbol)+r'\(.*?^}', llvm, re.M|re.S)
			code = re.search(r'^[0-9a-f]+ <'+re.escape(symbol)+r'>:\n.*?(?=\n[0-9a-f]+ <|\Z)', assembly, re.M|re.S)
			assert ir and code, (symbol, mode)
			parts += ['\n'+mode+' '+symbol+'\n', ir[0]+'\n', code[0]+'\n']
	text = '\n'.join(line.rstrip() for line in ''.join(parts).splitlines()).rstrip()+'\n'
	(out/'machine.txt').write_text(text)
	return dict(functions=8, modes=3, sha256=hashlib.sha256(text.encode()).hexdigest())


def audit(build, out, independent):
	assert independent and (independent/'astrac').exists()
	tests = [json.loads(line) for line in (build/'meson-logs/num-conv-final.json').read_text().splitlines()]
	assert len(tests) == len(json.loads((build/'meson-info/intro-tests.json').read_text()))
	assert all(row['result'] == 'OK' for row in tests), [(row['name'], row['result']) for row in tests if row['result'] != 'OK']
	goldens = []
	for name in git('ls-tree', '-r', '--name-only', BASELINE, 'tests').decode().splitlines():
		if Path(name).suffix in EXTENSIONS:
			before = git('show', BASELINE+':'+name)
			assert (ROOT/name).read_bytes() == before, name
			goldens.append(dict(path=name, sha256=hashlib.sha256(before).hexdigest()))
	assert len(goldens) == 1004, len(goldens)
	for name in ['bootstrap/nabi', 'bootstrap/cabi', 'bootstrap/vapi', 'bootstrap/foreign', 'bootstrap/semantic/types.vala', 'bootstrap/semantic/binary-float-value.vala', 'bootstrap/semantic/binary-float-format.vala', 'bootstrap/semantic/f32-value.vala', 'bootstrap/semantic/floating-conversion.vala', 'bootstrap/semantic/integer-conversion.vala', 'bootstrap/semantic/generic-capabilities.vala']:
		assert not git('diff', BASELINE, '--', name), name
	for stage in ['syntax', 'semantic', 'core', 'cfg', 'ssa', 'nabi']:
		for path in (ROOT/'bootstrap'/stage).glob('*.vala'):
			code = re.sub(r'/\*.*?\*/|//[^\n]*', '', path.read_text(), flags=re.S)
			assert not re.search(r'\bLLVM\w*|Astra\.Backend|CApi\.', code), path
	for name in ['binary-float-format', 'binary-float-value', 'f32-value', 'numeric-conversion']:
		path = ROOT/f'bootstrap/semantic/{name}.vala'
		code = re.sub(r'/\*.*?\*/|//[^\n]*', '', path.read_text(), flags=re.S)
		assert not re.search(r'\b(?:float|double|strtod|strtof|scanf|atof|g_ascii_strtod|LLVM\w*)\b', code), path
	commands = json.loads((build/'compile_commands.json').read_text())
	generated = [row for row in commands if row['file'].endswith('.c') and 'meson-generated' in row['command']]
	assert generated and all('-DVALA_STRICT_C' in row['command'] and '-Werror' in row['command'] for row in generated)
	comparisons = []
	dumps = out/'dumps'; dumps.mkdir(exist_ok=True)
	for name in FIXTURES:
		for stage in STAGES:
			args = ['--dump-'+stage, ROOT/f'tests/num-conv/fixtures/num-conv-{name}.astra']
			text = run([build/'astrac', *args])
			assert text == run([build/'astrac', *args]) == run([independent/'astrac', *args]), (name, stage)
			(dumps/(name+'.'+stage)).write_text(text)
			comparisons.append(dict(name=name, stage=stage, sha256=hashlib.sha256(text.encode()).hexdigest()))
			# Conversion/guard and marker order are explicitly visible before LLVM.
	for stage in ['cfg', 'ssa']:
		text = (dumps/('order.'+stage)).read_text().split('"main" -> int')[1]
		position = 0
		for pattern in ['mark_int', 'numeric-convert', 'mark_float', 'numeric-guard', 'numeric-convert', 'mark_int', 'consume']:
			found = text.find(pattern, position)
			assert found >= position, (stage, pattern, text)
			position = found + len(pattern)
		assert text.count('"mark_int"') == 2 and text.count('"mark_float"') == 1
	execution = build/'tests/num-conv/execution'
	native = json.loads((execution/'results.json').read_text())
	plans = [int(match[1]) for row in tests if (match := re.search(r'^1\.\.(\d+)$', row.get('stdout', ''), re.M))]
	counts = {}
	for row in tests:
		name = row['name'].split(':')[-1]
		prefix = name.split('-')[0]
		counts[prefix] = counts.get(prefix, 0)+1
	summary = dict(baseline=BASELINE, meson_tests=len(tests), tap_suites=len(plans), tap_cases=sum(plans), strict_generated_c_commands=len(generated), unchanged_baseline_goldens=len(goldens), changed_baseline_goldens=[], frozen_nabi_goldens=sum(Path(row['path']).suffix == '.nabi' for row in goldens), fresh_process_comparisons=len(comparisons), independent_build_comparisons=len(comparisons), stage_lifetime_fixtures=len(FIXTURES), firewall_linkage_tests=sum(any(x in row['name'] for x in ['no-llvm', 'links-qualified-llvm', 'linkage-rejects', 'firewall-rejects']) for row in tests), source_runs=len(native['runs']), matrix=native['matrix_runs'], conversion_inventory=native['inventory'], freestanding=native['freestanding'], suffix_oracle=json.loads((build/'tests/num-conv/literal-results.json').read_text()), f32_oracle=json.loads((build/'tests/f32/oracle-results.json').read_text()), f64_oracle=json.loads((build/'tests/f64/oracle-results.json').read_text()), machine=machine(execution, out), suite_counts=counts, dependencies_added=0)
	summary['integer_matrices_sha256'] = integer_evidence(out)
	write(out/'summary.json', summary)
	write(out/'goldens.json', goldens)
	write(out/'determinism.json', comparisons)
	print(json.dumps(summary), flush=True)


def losses(text):
	text = re.sub(r'^==\d+== ?', '', text, flags=re.M)
	records = re.findall(r'[\d,]+ bytes in [\d,]+ blocks are (?:definitely|indirectly|possibly) lost in loss record[^\n]*\n.*?(?=\n\n|\Z)', text, flags=re.S)
	return [re.sub(r'0x[0-9A-Fa-f]+', 'ADDRESS', re.sub(r'loss record [\d,]+ of [\d,]+', 'loss record', record)) for record in records]


def memory(build, out, baseline):
	assert baseline and 'ASTRA-BUFFER-1' in run([baseline/'astrac', '--version'])
	logs = out/'valgrind'; logs.mkdir(exist_ok=True)
	jobs = []
	for root, prefix, names in [(build, '', LEGACY|{'num-conv-'+s for s in ['semantic', 'core', 'cfg', 'ssa', 'pipeline', 'llvm']}), (baseline, 'baseline-', LEGACY)]:
		for test in json.loads((root/'meson-info/intro-tests.json').read_text()):
			if test['name'] in names:
				jobs.append((prefix+test['name'], test['cmd'], test['workdir'] or str(root), dict(os.environ, **test['env']), 0, None, None))
	for name in ['int-f32', 'int-f64', 'f32-int', 'f64-int', 'literals', 'order', 'trap', 'cad']:
		for stage in ['syntax', 'semantics', 'ssa', 'llvm']:
			jobs.append(('dump-'+name+'-'+stage, [str(build/'astrac'), '--dump-'+stage, str(ROOT/f'tests/num-conv/fixtures/num-conv-{name}.astra')], str(ROOT), os.environ, 0, None, None))
		for mode in ['O0', 'O2']:
			jobs.append(('run-'+name+'-'+mode, [str(build/'tests/num-conv/execution'/(name+'-'+mode))], str(ROOT), os.environ, -signal.SIGILL if name == 'trap' else 0, '12' if name == 'trap' else '1234' if name == 'order' else '', None))
	jobs.append(('suffix-driver', [str(build/'tests/num-conv/astra-num-conv-semantic'), '--literals'], str(ROOT), os.environ, 0, 'f64 0x3ff0000000000001\nf32 0x3f800000\nf64 0x8000000000000000\nf32 0x80000000\n', '1.0000000000000002d\n1.0000000000000002f\n-0.0D\n-0.0F\n'))

	def measure(job):
		name, argv, cwd, env, status, expected, inputs = job
		command = ['valgrind', '--vgdb=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', '--log-file='+str(logs/(name+'.log')), *argv]
		p = subprocess.run(command, cwd=cwd, env=env, input=inputs, capture_output=True, text=True)
		(logs/(name+'.stdout')).write_text(p.stdout)
		(logs/(name+'.stderr')).write_text(p.stderr)
		text = (logs/(name+'.log')).read_text()
		assert 'ERROR SUMMARY:' in text, name
		def number(pattern):
			match = re.search(pattern, text)
			return int(match[1].replace(',', '')) if match else 0
		return dict(name=name, exit=p.returncode, expected=status, output_matches=expected is None or expected == p.stdout, errors=number(r'ERROR SUMMARY: ([\d,]+) errors'), definite=number(r'definitely lost: ([\d,]+) bytes'), indirect=number(r'indirectly lost: ([\d,]+) bytes'), possible=number(r'possibly lost: ([\d,]+) bytes'), suppressed=number(r'suppressed: ([\d,]+) from'), lost_records=losses(text))

	with ThreadPoolExecutor(max_workers=4) as pool:
		rows = list(pool.map(measure, jobs))
	write(logs/'results.json', rows)
	by_name = {row['name']: row for row in rows}
	for row in rows:
		name = row['name']
		if name.removeprefix('baseline-') in LEGACY:
			assert row['exit'] == 99 and row['errors'] == 1 and row['definite'] == 16384 and row['indirect'] == row['possible'] == row['suppressed'] == 0, row
			assert len(row['lost_records']) == 1 and 'g_malloc' in row['lost_records'][0] and 'call_init' in row['lost_records'][0], row
			assert row['lost_records'] == by_name['baseline-'+name.removeprefix('baseline-')]['lost_records'], row
		else:
			assert row['exit'] == row['expected'] and row['output_matches'] and row['errors'] == row['definite'] == row['indirect'] == row['possible'] == row['suppressed'] == 0, row
	summary = dict(current_runs=len(rows)-len(LEGACY), baseline_runs=len(LEGACY), matching_legacy_startup_losses=len(LEGACY), new_astra_errors=0, new_astra_lost_bytes=0)
	write(logs/'summary.json', summary)
	print(json.dumps(summary), flush=True)


if __name__ == '__main__':
	parser = argparse.ArgumentParser()
	parser.add_argument('build', type=Path)
	parser.add_argument('--independent-build', type=Path)
	parser.add_argument('--baseline-build', type=Path)
	parser.add_argument('--memory', action='store_true')
	args = parser.parse_args()
	build = args.build.resolve()
	out = build/'qualification-num-conv'
	out.mkdir(exist_ok=True)
	if args.memory:
		memory(build, out, args.baseline_build.resolve() if args.baseline_build else None)
	else:
		audit(build, out, args.independent_build.resolve() if args.independent_build else None)
