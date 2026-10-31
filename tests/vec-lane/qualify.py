# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Reproduce lane IR, ABI stability, native machine and Valgrind audits."""
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

BASELINE = '865f526b58277a0efd85403f06ddd8076d14a295'
spec = importlib.util.spec_from_file_location('astra_scalar_qualification', ROOT / 'tests/f32/qualify.py')
scalar = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scalar)


def run(argv):
	result = subprocess.run([str(arg) for arg in argv], cwd=ROOT, capture_output=True, text=True)
	assert result.returncode == 0, (argv, result.returncode, result.stdout, result.stderr)
	return result.stdout


def no_contraction(machine):
	assert not re.search(r'\bv?f(?:n?madd|n?msub)\w*\b', machine)


def audit(build, out):
	rows = []
	for name in FIXTURES:
		source = ROOT / f'tests/vec-lane/fixtures/vec-{name}.astra'
		options = bindings() if name == 'lane-ownership' else []
		stages = {stage: run([build / 'astrac', '--dump-' + stage, source, *options]) for stage in ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']}
		llvm, ssa = stages['llvm'], stages['ssa']
		assert not re.search(r'\b(reassoc|nnan|ninf|nsz|arcp|contract|afn|fast|poison|undef)\b|llvm\.fma|llvm\.fmuladd|unsafe-fp|no-nans|no-infs|no-signed-zeros|denormal-fp-math', llvm), name
		assert not re.search(r'\b(?:alloca|load|store) <', llvm), name
		assert not re.search(r'LanePlace|lane-place|extractelement|insertelement|shufflevector', ssa), name
		assert 'vector-v4' in stages['nabi'], name
		counts = scalar.predecessors(llvm)
		counts['vector_phis'] = len(re.findall(r' = phi <', llvm))
		if name == 'lane-loop':
			assert counts['vector_phis'] >= 3 and 'vector-insert' in ssa and 'vector-shuffle' in ssa
		if name == 'lane-values':
			body = ssa.split('(function #1')[0]
			assert len(re.findall(r' = vector-(?:splat|extract|insert|shuffle|select)\b', body)) == 5
			assert 'conditional-branch' not in body and 'storage' not in body
			assert '%3 : i16 = vector-extract (lane 2) (vector %2)' in body
			assert '%4 : i16<4> = vector-insert (lane 1) (vector %2) (value %3)' in body
			assert '%5 : i16<4> = vector-shuffle (lanes 3 2 1 0) (vector %4)' in body
			physical = llvm.split('define internal fastcc i32')[0]
			assert 'br ' not in physical and 'insertelement <4 x i16> zeroinitializer' in physical
			for op in ['extractelement', 'insertelement', 'shufflevector', 'select <4 x i1>']:
				assert op in physical
		stem = out / name
		for stage, dump in stages.items():
			stem.with_suffix('.ll' if stage == 'llvm' else '.' + stage).write_text(dump)
		run(['llvm-as', stem.with_suffix('.ll'), '-o', stem.with_suffix('.bc')])
		run(['llc', '-O0', '-filetype=obj', '-relocation-model=pic', stem.with_suffix('.bc'), '-o', stem.with_suffix('.o')])
		machine = run(['objdump', '-dr', stem.with_suffix('.o')])
		stem.with_suffix('.machine').write_text(machine)
		no_contraction(machine)
		undefined = run(['nm', '-u', stem.with_suffix('.o')])
		assert all('astra_test_resource_' in line or '_GLOBAL_OFFSET_TABLE_' in line for line in undefined.splitlines()), (name, undefined)
		stem.with_suffix('.symbols').write_text(run(['nm', '-a', stem.with_suffix('.o')]))
		stem.with_suffix('.elf').write_text(run(['readelf', '-aW', stem.with_suffix('.o')]))
		executable = build / 'tests/vec-lane/execution' / name
		linked = run(['ldd', executable])
		stem.with_suffix('.ldd').write_text(linked)
		assert not any(word in linked.lower() for word in ['glib', 'gobject', 'llvm'])
		actual = run(['objdump', '-d', executable])
		stem.with_suffix('.executable-machine').write_text(actual)
		no_contraction(actual)
		if name == 'lane-f32':
			entry = len(re.findall(r'^define ', llvm, re.M)) - 1
			wrapped = llvm + f'\ndefine i32 @main() {{\nentry:\n\t%r = call fastcc i32 @astra.fn.{entry}()\n\tret i32 %r\n}}\n'
			(out / 'fma-execution.ll').write_text(wrapped)
			run(['llc', '-O2', '-mattr=+fma', '-filetype=obj', '-relocation-model=pic', out / 'fma-execution.ll', '-o', out / 'fma-execution.o'])
			run(['cc', out / 'fma-execution.o', '-o', out / 'fma-execution'])
			assert ' fma ' in (' ' + Path('/proc/cpuinfo').read_text().replace('\n', ' ') + ' ')
			run([out / 'fma-execution'])
			fma_machine = run(['objdump', '-dr', out / 'fma-execution.o'])
			(out / 'fma-execution.machine').write_text(fma_machine)
			no_contraction(fma_machine)
		rows.append({'fixture': name, 'module_object_executable_audited': True, **counts})
		# Record machine realization of four parameter-driven operations. No mnemonic
		# is a semantic pass condition; the executable/oracle checks establish values.
	source = out / 'machine.astra'
	source.write_text('f32<4> broadcast(f32 x){return splat(x,4);}\ni16<8> reverse(i16<8> v){return shuffle(v,7,6,5,4,3,2,1,0);}\nint<4> update(int<4> v){return insert(v,1,v[2]);}\nf32<4> choose(bool<4> m,f32<4> a,f32<4> b){return select(m,a,b);}\n')
	llvm = run([build / 'astrac', '--dump-llvm', source])
	(out / 'machine.ll').write_text(llvm)
	run(['llc', '-O0', '-filetype=obj', '-relocation-model=pic', out / 'machine.ll', '-o', out / 'machine.o'])
	machine = run(['objdump', '-dr', out / 'machine.o'])
	(out / 'machine.txt').write_text(machine)
	no_contraction(machine)
	goldens = 0
	for path in run(['git', 'ls-tree', '-r', '--name-only', BASELINE, 'tests']).splitlines():
		if Path(path).suffix in {'.syntax', '.semantics', '.core', '.cfg', '.ssa', '.nabi', '.cabi', '.ll', '.stderr'}:
			before = subprocess.run(['git', 'show', BASELINE + ':' + path], cwd=ROOT, capture_output=True, check=True).stdout
			assert (ROOT / path).read_bytes() == before, path
			goldens += 1
	for path in ['bootstrap/nabi', 'bootstrap/cabi', 'bootstrap/vapi', 'bootstrap/foreign', 'bootstrap/cfg/predecessors.vala', 'bootstrap/ssa/dominance.vala', 'bootstrap/semantic/types.vala', 'bootstrap/semantic/operators.vala', 'bootstrap/semantic/integer-value.vala', 'bootstrap/semantic/int-value.vala', 'bootstrap/semantic/f32-value.vala', 'bootstrap/backend/llvm/llvm-target-machine.vala', 'bootstrap/backend/llvm/llvm-scalar-lowering.vala']:
		assert run(['git', 'diff', BASELINE, '--', path]) == '', path
	for directory in ['semantic', 'core', 'cfg', 'ssa', 'nabi']:
		for path in (ROOT / 'bootstrap' / directory).glob('*.vala'):
			code = re.sub(r'/\*.*?\*/|//[^\n]*', '', path.read_text(), flags=re.S)
			assert not re.search(r'\bLLVM\w*|Astra\.Backend|CApi\.', code), path
			assert 'LanePlace' not in code, path
	commands = json.loads((build / 'compile_commands.json').read_text())
	generated = [row for row in commands if row['file'].endswith('.c') and 'meson-generated' in row['command']]
	assert generated and all('-DVALA_STRICT_C' in row['command'] and '-Werror' in row['command'] for row in generated)
	result = {'baseline': BASELINE, 'workloads': rows, 'baseline_goldens_unchanged': goldens, 'strict_generated_c_commands': len(generated), 'no_lane_places_or_vector_memory': True, 'upstream_llvm_free': True, 'nabi_cabi_vapi_unchanged': True, 'fma_enabled_O2_two_rounding_execution': True, 'llvm': run(['llvm-config', '--version']).strip(), 'host': run(['uname', '-m']).strip(), 'default_cpu': '', 'default_features': ''}
	(out / 'audit-results.json').write_text(json.dumps(result, indent='\t') + '\n')
	print(json.dumps(result), flush=True)


def memory(build, out):
	logs = out / 'valgrind'
	logs.mkdir(exist_ok=True)
	selected = {'vec-lane-semantic-standalone', 'vec-lane-core-standalone', 'vec-lane-cfg-standalone', 'vec-lane-ssa-standalone', 'vec-lane-pipeline', 'vec-lane-llvm', 'vec-nabi-standalone', 'cabi-standalone', 'vapi', 'semantic', 'core', 'cfg'}
	jobs = []
	for test in json.loads((build / 'meson-info/intro-tests.json').read_text()):
		if test['name'] in selected:
			jobs.append((test['name'], test['cmd'], test['workdir'] or str(build), dict(os.environ, **test['env'])))
	for name in FIXTURES + ['oracle', 'order-barriers']:
		jobs.append(('run-' + name, [str(build / 'tests/vec-lane/execution' / name)], str(ROOT), dict(os.environ)))
	jobs.append(('oracle-generator', [str(build / 'tests/vec-lane/astra-vec-lane-oracle')], str(ROOT), dict(os.environ)))
	for name in ['splat', 'extract', 'insert', 'shuffle', 'select', 'lane-f32', 'lane-loop', 'lane-ownership']:
		options = [*bindings(), '--link-object', build / 'tests/cabi/companion.o'] if name == 'lane-ownership' else []
		jobs.append(('compile-' + name, [str(build / 'astrac'), str(ROOT / f'tests/vec-lane/fixtures/vec-{name}.astra'), *map(str, options), '-o', str(logs / name)], str(ROOT), dict(os.environ)))
	for stage in ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']:
		jobs.append(('dump-' + stage, [str(build / 'astrac'), '--dump-' + stage, str(ROOT / 'tests/vec-lane/fixtures/vec-lane-values.astra')], str(ROOT), dict(os.environ)))
	flags = ['--vgdb=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99']
	def measure(job):
		name, argv, cwd, env = job
		command = ['valgrind', *flags, '--log-file=' + str(logs / (name + '.log')), *argv]
		result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True)
		(logs / (name + '.stdout')).write_text(result.stdout)
		(logs / (name + '.stderr')).write_text(result.stderr)
		text = (logs / (name + '.log')).read_text()
		assert 'ERROR SUMMARY:' in text, name
		def number(pattern):
			match = re.search(pattern, text)
			return int(match[1].replace(',', '')) if match else 0
		return {'name': name, 'command': command, 'exit': result.returncode, 'errors': number(r'ERROR SUMMARY: ([\d,]+) errors'), 'definite': number(r'definitely lost: ([\d,]+) bytes'), 'indirect': number(r'indirectly lost: ([\d,]+) bytes'), 'possible': number(r'possibly lost: ([\d,]+) bytes'), 'reachable': number(r'still reachable: ([\d,]+) bytes')}
	rows = []
	with ThreadPoolExecutor(max_workers=4) as pool:
		for future in as_completed([pool.submit(measure, job) for job in jobs]):
			row = future.result()
			rows.append(row)
			(logs / 'results.json').write_text(json.dumps(sorted(rows, key=lambda row: row['name']), indent='\t') + '\n')
			print(json.dumps({key: value for key, value in row.items() if key != 'command'}), flush=True)
	issues = [row['name'] for row in rows if row['exit'] or row['errors'] or row['definite'] or row['indirect'] or row['possible']]
	print(json.dumps({'measured': len(rows), 'requires_investigation': issues}), flush=True)


if __name__ == '__main__':
	parser = argparse.ArgumentParser()
	parser.add_argument('build', type=Path)
	parser.add_argument('--memory', action='store_true')
	args = parser.parse_args()
	build = args.build.resolve()
	out = build / 'qualification-vec-lane'
	out.mkdir(exist_ok=True)
	(memory if args.memory else audit)(build, out)
