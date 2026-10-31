# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Reproduce vector IR, native objects, instruction selection, and memory audits."""
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import argparse
import importlib.util
import json
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True
from execute import FIXTURES, ROOT, bindings

BASELINE = 'b2a3a58bbe1a0d5e2f2e880ee2860748bc6f01bf'
spec = importlib.util.spec_from_file_location('astra_scalar_qualification', ROOT / 'tests/f32/qualify.py')
scalar_qualification = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scalar_qualification)


def run(argv):
	result = subprocess.run([str(arg) for arg in argv], cwd=ROOT, capture_output=True, text=True)
	assert result.returncode == 0, (argv, result.returncode, result.stdout, result.stderr)
	return result.stdout


def no_contraction(machine):
	assert not re.search(r'\bv?f(?:n?madd|n?msub)\w*\b', machine)


def audit(build, out):
	rows = []
	for name in FIXTURES:
		source = ROOT / f'tests/vec/fixtures/vec-{name}.astra'
		options = bindings() if name == 'ownership' else []
		llvm = run([build / 'astrac', '--dump-llvm', source, *options])
		assert not re.search(r'\b(reassoc|nnan|ninf|nsz|arcp|contract|afn|fast|poison|undef)\b|llvm\.fma|llvm\.fmuladd|unsafe-fp|no-nans|no-infs|no-signed-zeros|denormal-fp-math', llvm), name
		assert not re.search(r' = (?:add|sub|mul) (?:nuw|nsw)', llvm), name
		assert not re.search(r'\b(?:alloca|load|store) <', llvm), name
		ssa = run([build / 'astrac', '--dump-ssa', source, *options])
		assert 'vector-init' in ssa and 'vector-all' in ssa
		assert not re.search(r'LanePlace|lane-place|extractelement|insertelement|shuffle|splat', ssa)
		counts = scalar_qualification.predecessors(llvm)
		counts['vector_phis'] = len(re.findall(r' = phi <', llvm))
		counts['integer_split_vector_edges'] = sum(len(re.findall(r', %[\w.]+\.(?:continue|nonzero) \]', line)) for line in llvm.splitlines() if ' = phi <' in line)
		if name == 'physical':
			assert counts['integer_split_vector_edges'] >= 2
		if name in ['branch', 'loop']:
			assert counts['vector_phis'] >= 2
		if name == 'basic':
			assert len(re.findall(r'= binary \+', ssa.split('(function #1')[0])) == 1
			assert 'insertelement <4 x i32> zeroinitializer' in llvm
		if name == 'f32':
			for op in ['fadd', 'fsub', 'fmul', 'fdiv', 'fneg']:
				assert op + ' <4 x float>' in llvm
			for predicate in ['oeq', 'une', 'olt', 'ole', 'ogt', 'oge']:
				assert 'fcmp ' + predicate + ' <4 x float>' in llvm
		if name == 'integers':
			assert 'icmp sgt <4 x i8>' in llvm and 'icmp ugt <4 x i8>' in llvm
		stem = out / name
		stem.with_suffix('.ssa').write_text(ssa)
		stem.with_suffix('.ll').write_text(llvm)
		run(['llvm-as', stem.with_suffix('.ll'), '-o', stem.with_suffix('.bc')])
		run(['llc', '-O0', '-filetype=obj', '-relocation-model=pic', stem.with_suffix('.bc'), '-o', stem.with_suffix('.o')])
		machine = run(['objdump', '-dr', stem.with_suffix('.o')])
		stem.with_suffix('.machine').write_text(machine)
		no_contraction(machine)
		selected = []
		if name == 'f32':
			selected.append({'shape': 'f32<4> add', 'instruction': 'addps' if 'addps' in machine else 'legalized; see machine artifact'})
		if name == 'basic':
			selected.append({'shape': 'int<4> add', 'instruction': 'paddd' if 'paddd' in machine else 'legalized; see machine artifact'})
		if name == 'integers':
			selected += [{'shape': 'i16<8> add', 'instruction': 'paddw' if 'paddw' in machine else 'legalized; see machine artifact'}, {'shape': 'u8<16> add', 'instruction': 'paddb' if 'paddb' in machine else 'legalized; see machine artifact'}]
		undefined = run(['nm', '-u', stem.with_suffix('.o')])
		assert all('astra_test_resource_' in line or '_GLOBAL_OFFSET_TABLE_' in line for line in undefined.splitlines()), (name, undefined)
		stem.with_suffix('.symbols').write_text(run(['nm', '-a', stem.with_suffix('.o')]))
		stem.with_suffix('.elf').write_text(run(['readelf', '-aW', stem.with_suffix('.o')]))
		executable = build / 'tests/vec/execution' / name
		linked = run(['ldd', executable])
		stem.with_suffix('.ldd').write_text(linked)
		assert not any(word in linked.lower() for word in ['glib', 'gobject', 'llvm'])
		actual = run(['objdump', '-d', executable])
		stem.with_suffix('.executable-machine').write_text(actual)
		no_contraction(actual)
		if name == 'f32':
			fma_object = out / 'f32-fma-enabled.o'
			run(['llc', '-O2', '-mattr=+fma', '-filetype=obj', '-relocation-model=pic', stem.with_suffix('.bc'), '-o', fma_object])
			fma_machine = run(['objdump', '-dr', fma_object])
			(out / 'f32-fma-enabled.machine').write_text(fma_machine)
			assert re.search(r'\b(?:v?mulps|v?mulss)\b', fma_machine) and re.search(r'\b(?:v?addps|v?addss)\b', fma_machine)
			no_contraction(fma_machine)
			# Execute the FMA-enabled object as well. This wrapper calls the
			# Astra int main using the same fastcc as the compiler's launcher.
			entry = len(re.findall(r'^define ', llvm, re.M)) - 1
			wrapped = llvm + f'\ndefine i32 @main() {{\nentry:\n\t%r = call fastcc i32 @astra.fn.{entry}()\n\tret i32 %r\n}}\n'
			(out / 'fma-execution.ll').write_text(wrapped)
			run(['llc', '-O2', '-mattr=+fma', '-filetype=obj', '-relocation-model=pic', out / 'fma-execution.ll', '-o', out / 'fma-execution.o'])
			run(['cc', out / 'fma-execution.o', '-o', out / 'fma-execution'])
			assert ' fma ' in (' ' + Path('/proc/cpuinfo').read_text().replace('\n', ' ') + ' '), 'FMA execution audit requires a qualified FMA-capable host'
			run([out / 'fma-execution'])
			no_contraction(run(['objdump', '-d', out / 'fma-execution']))
		rows.append({'fixture': name, 'module_object_executable_audited': True, 'instructions': selected, **counts})
	goldens = 0
	for path in run(['git', 'ls-tree', '-r', '--name-only', BASELINE, 'tests']).splitlines():
		if Path(path).suffix in {'.syntax', '.semantics', '.core', '.cfg', '.ssa', '.nabi', '.cabi', '.ll', '.stderr'}:
			before = subprocess.run(['git', 'show', BASELINE + ':' + path], cwd=ROOT, capture_output=True, check=True).stdout
			assert (ROOT / path).read_bytes() == before, path
			goldens += 1
	for path in ['bootstrap/cabi', 'bootstrap/vapi', 'bootstrap/foreign', 'bootstrap/cfg/predecessors.vala', 'bootstrap/ssa/dominance.vala', 'bootstrap/semantic/integer-value.vala', 'bootstrap/semantic/int-value.vala', 'bootstrap/semantic/f32-value.vala']:
		assert run(['git', 'diff', BASELINE, '--', path]) == '', path
	for directory in ['semantic', 'core', 'cfg', 'ssa', 'nabi']:
		for path in (ROOT / 'bootstrap' / directory).glob('*.vala'):
			code = re.sub(r'/\*.*?\*/|//[^\n]*', '', path.read_text(), flags=re.S)
			assert not re.search(r'\bLLVM\w*|Astra\.Backend|CApi\.', code), path
			assert 'VectorLanePlace' not in code and 'LanePlace' not in code, path
	commands = json.loads((build / 'compile_commands.json').read_text())
	generated = [row for row in commands if row['file'].endswith('.c') and 'meson-generated' in row['command']]
	assert generated and all('-DVALA_STRICT_C' in row['command'] and '-Werror' in row['command'] for row in generated)
	result = {'baseline': BASELINE, 'workloads': rows, 'baseline_goldens_unchanged': goldens, 'strict_generated_c_commands': len(generated), 'upstream_llvm_free': True, 'no_lane_places_or_vector_memory': True, 'fma_enabled_O2_no_contraction_executed': True, 'default_cpu': '', 'default_features': '', 'llvm': run(['llvm-config', '--version']).strip(), 'host': run(['uname', '-m']).strip()}
	(out / 'audit-results.json').write_text(json.dumps(result, indent='\t') + '\n')
	print(json.dumps(result), flush=True)


def memory(build, out):
	logs = out / 'valgrind'
	logs.mkdir(exist_ok=True)
	selected = {'vec-semantic-standalone', 'vec-core-standalone', 'vec-cfg-standalone', 'vec-ssa-standalone', 'vec-nabi-standalone', 'vec-pipeline', 'vec-llvm', 'cabi-standalone', 'vapi', 'owned-boundaries', 'resources', 'semantic', 'core', 'cfg', 'f32-semantic-standalone', 'f32-pipeline'}
	jobs = []
	for test in json.loads((build / 'meson-info/intro-tests.json').read_text()):
		if test['name'] in selected:
			jobs.append((test['name'], test['cmd'], test['workdir'] or str(build), dict(os.environ, **test['env']), 0))
	for name in FIXTURES + ['integer-oracle', 'f32-oracle', 'mask-matrix']:
		jobs.append(('run-' + name, [str(build / 'tests/vec/execution' / name)], str(ROOT), dict(os.environ), 0))
	for name in ['basic', 'f32', 'loop', 'order', 'ownership']:
		options = [*bindings(), '--link-object', build / 'tests/cabi/companion.o'] if name == 'ownership' else []
		jobs.append(('compile-' + name, [str(build / 'astrac'), str(ROOT / f'tests/vec/fixtures/vec-{name}.astra'), *map(str, options), '-o', str(logs / name)], str(ROOT), dict(os.environ), 0))
	for mode in ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']:
		jobs.append(('dump-' + mode, [str(build / 'astrac'), '--dump-' + mode, str(ROOT / 'tests/vec/fixtures/vec-basic.astra')], str(ROOT), dict(os.environ), 0))
	flags = ['--vgdb=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99']
	def measure(job):
		name, argv, cwd, env, expected = job
		command = ['valgrind', *flags, '--log-file=' + str(logs / (name + '.log')), *argv]
		result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True)
		(logs / (name + '.stdout')).write_text(result.stdout)
		(logs / (name + '.stderr')).write_text(result.stderr)
		text = (logs / (name + '.log')).read_text()
		assert 'ERROR SUMMARY:' in text, name
		def number(pattern):
			m = re.search(pattern, text)
			return int(m[1].replace(',', '')) if m else 0
		return {'name': name, 'command': command, 'exit': result.returncode, 'expected': expected, 'errors': number(r'ERROR SUMMARY: ([\d,]+) errors'), 'definite': number(r'definitely lost: ([\d,]+) bytes'), 'indirect': number(r'indirectly lost: ([\d,]+) bytes'), 'possible': number(r'possibly lost: ([\d,]+) bytes'), 'reachable': number(r'still reachable: ([\d,]+) bytes')}
	rows = []
	with ThreadPoolExecutor(max_workers=4) as pool:
		for future in as_completed([pool.submit(measure, job) for job in jobs]):
			row = future.result()
			rows.append(row)
			(logs / 'results.json').write_text(json.dumps(sorted(rows, key=lambda row: row['name']), indent='\t') + '\n')
			print(json.dumps({k: v for k, v in row.items() if k != 'command'}), flush=True)
	issues = [row['name'] for row in rows if row['exit'] != row['expected'] or row['errors'] or row['definite'] or row['indirect'] or row['possible']]
	print(json.dumps({'measured': len(rows), 'requires_investigation': issues}), flush=True)


if __name__ == '__main__':
	parser = argparse.ArgumentParser()
	parser.add_argument('build', type=Path)
	parser.add_argument('--memory', action='store_true')
	args = parser.parse_args()
	build = args.build.resolve()
	out = build / 'qualification-vec'
	out.mkdir(exist_ok=True)
	(memory if args.memory else audit)(build, out)
