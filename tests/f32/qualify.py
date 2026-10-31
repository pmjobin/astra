# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Reproduce F32-1 IR, generated C, linkage, machine, and memory audits."""
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import argparse
import json
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True
from execute import FIXTURES, ROOT, bindings

BASELINE = '409755de8b2a0a4b7cab11ddeedae3c80f5d4f91'


def run(argv):
	result = subprocess.run([str(arg) for arg in argv], cwd=ROOT, capture_output=True, text=True)
	assert result.returncode == 0, (argv, result.returncode, result.stdout, result.stderr)
	return result.stdout


def predecessors(llvm):
	count = 0
	float_count = 0
	integer_split_float_edges = 0
	for function in re.findall(r'(?ms)^define [^\n]+\{\n(.*?)^}', llvm):
		blocks = {}
		for line in function.splitlines():
			label = re.match(r'^([\w.]+):', line)
			if label:
				block = label[1]
				blocks[block] = []
			elif line.strip():
				blocks[block].append(line)
		incoming = {block: set() for block in blocks}
		for block, lines in blocks.items():
			for line in lines:
				if line.strip().startswith('br '):
					for target in re.findall(r'label %([\w.]+)', line):
						incoming[target].add(block)
		for block, lines in blocks.items():
			for line in lines:
				if ' = phi ' in line:
					preds = re.findall(r', %([\w.]+) \]', line)
					assert set(preds) == incoming[block] and len(preds) == len(set(preds)), (block, line, incoming[block])
					count += 1
					if 'phi float ' in line:
						float_count += 1
						integer_split_float_edges += sum(p.endswith(('.continue', '.nonzero')) for p in preds)
	return {'phis': count, 'float_phis': float_count, 'integer_split_float_edges': integer_split_float_edges}


def audit(build, out):
	rows = []
	for name in FIXTURES:
		source = ROOT / f'tests/f32/fixtures/f32-{name}.astra'
		options = bindings() if name == 'ownership' else []
		llvm = run([build / 'astrac', '--dump-llvm', source, *options])
		assert not re.search(r'\b(reassoc|nnan|ninf|nsz|arcp|contract|afn|fast|double|fpext|fptrunc|sitofp|uitofp|fptosi|fptoui|poison)\b', llvm), name
		assert not re.search(r'no-nans|no-infs|no-signed-zeros|unsafe-fp|nofpclass|llvm\.fma|llvm\.fmuladd|denormal-fp-math', llvm), name
		if name in ['basic', 'special', 'compare', 'rounding']:
			assert 'llvm.trap' not in llvm and '.nonzero' not in llvm, name
		if name == 'basic':
			for op in ['fadd', 'fsub', 'fmul', 'fdiv', 'fneg']:
				assert op + ' float ' in llvm
		if name == 'compare':
			for predicate in ['oeq', 'une', 'olt', 'ole', 'ogt', 'oge']:
				assert 'fcmp ' + predicate + ' float ' in llvm
		if name == 'addressable':
			assert 'type { float, float }' in llvm and 'load float,' in llvm and 'store float ' in llvm
		counts = predecessors(llvm)
		if name in ['branch', 'loop', 'struct', 'physical']:
			assert counts['float_phis'] > 0, name
		if name == 'physical':
			assert counts['integer_split_float_edges'] >= 2, counts
		stem = out / name
		stem.with_suffix('.ll').write_text(llvm)
		run(['llvm-as', stem.with_suffix('.ll'), '-o', stem.with_suffix('.bc')])
		run(['llc', '-O0', '-filetype=obj', '-relocation-model=pic', stem.with_suffix('.bc'), '-o', stem.with_suffix('.o')])
		machine = run(['objdump', '-dr', stem.with_suffix('.o')])
		stem.with_suffix('.machine').write_text(machine)
		assert not re.search(r'\b(?:v?fmadd\w*|v?fmsub\w*|v?fnmadd\w*|v?fnmsub\w*|fld\w*|fst\w*)\b', machine), name
		if name == 'basic':
			for op in ['addss', 'subss', 'mulss', 'divss']:
				assert op in machine
		undefined = run(['nm', '-u', stem.with_suffix('.o')])
		assert all('astra_test_resource_' in line or '_GLOBAL_OFFSET_TABLE_' in line for line in undefined.splitlines()), (name, undefined)
		stem.with_suffix('.symbols').write_text(run(['nm', '-a', stem.with_suffix('.o')]))
		stem.with_suffix('.elf').write_text(run(['readelf', '-aW', stem.with_suffix('.o')]))
		executable = build / 'tests/f32/execution' / name
		linked = run(['ldd', executable])
		stem.with_suffix('.ldd').write_text(linked)
		assert not any(word in linked.lower() for word in ['glib', 'gobject', 'llvm'])
		# Also inspect the object actually emitted and linked by astrac.
		actual_machine = run(['objdump', '-d', executable])
		assert not re.search(r'\b(?:v?fmadd\w*|v?fmsub\w*|v?fnmadd\w*|v?fnmsub\w*)\b', actual_machine)
		stem.with_suffix('.executable-machine').write_text(actual_machine)
		if name == 'rounding':
			fma_object = out / 'rounding-fma-enabled.o'
			run(['llc', '-O2', '-mattr=+fma', '-filetype=obj', '-relocation-model=pic', stem.with_suffix('.bc'), '-o', fma_object])
			fma_machine = run(['objdump', '-dr', fma_object])
			(out / 'rounding-fma-enabled.machine').write_text(fma_machine)
			assert 'mulss' in fma_machine and 'addss' in fma_machine
			assert not re.search(r'\bv?f(?:n?madd|n?msub)\w*\b', fma_machine)
		rows.append({'fixture': name, 'module_object_executable_audited': True, **counts})
	goldens = 0
	for path in run(['git', 'ls-tree', '-r', '--name-only', BASELINE, 'tests']).splitlines():
		if Path(path).suffix in {'.syntax', '.semantics', '.core', '.cfg', '.ssa', '.nabi', '.cabi', '.ll', '.stderr'}:
			before = subprocess.run(['git', 'show', BASELINE + ':' + path], cwd=ROOT, capture_output=True, check=True).stdout
			assert (ROOT / path).read_bytes() == before, path
			goldens += 1
	for path in ['bootstrap/cabi', 'bootstrap/vapi', 'bootstrap/foreign', 'bootstrap/cfg/ownership-flow.vala', 'bootstrap/cfg/predecessors.vala', 'bootstrap/ssa/dominance.vala', 'bootstrap/semantic/integer-value.vala', 'bootstrap/semantic/int-value.vala']:
		assert run(['git', 'diff', BASELINE, '--', path]) == '', path
	commands = json.loads((build / 'compile_commands.json').read_text())
	generated = [row for row in commands if row['file'].endswith('.c') and 'meson-generated' in row['command']]
	assert generated and all('-DVALA_STRICT_C' in row['command'] and '-Werror' in row['command'] for row in generated)
	generated_converter = build / 'astrac.p/bootstrap/semantic/f32-value.c'
	c = re.sub(r'/\*.*?\*/|//[^\n]*', '', generated_converter.read_text(), flags=re.S)
	assert not re.search(r'\b(float|double|strtof|strtod|atof|g_ascii_strtod|LLVM\w*)\b', c)
	assert 'guint32' in c and 'gint64' in c and '113' in c
	for path in [ROOT / 'bootstrap/semantic/f32-value.vala', ROOT / 'bootstrap/semantic/analyzer.vala', ROOT / 'bootstrap/syntax/lexer.vala']:
		assert not re.search(r'\b(strtof|strtod|atof|g_ascii_strtod|double\.parse|float\.parse|LLVM\w*)\b', re.sub(r'/\*.*?\*/|//[^\n]*', '', path.read_text(), flags=re.S))
	result = {'baseline': BASELINE, 'workloads': rows, 'baseline_goldens_unchanged': goldens, 'strict_generated_c_commands': len(generated), 'generated_converter_host_float_free': True, 'fma_enabled_O2_no_contraction': True, 'default_cpu': '', 'default_features': '', 'llvm': run(['llvm-config', '--version']).strip(), 'host': run(['uname', '-m']).strip()}
	(out / 'audit-results.json').write_text(json.dumps(result, indent='\t') + '\n')
	print(json.dumps(result), flush=True)


def memory(build, out):
	logs = out / 'valgrind'
	logs.mkdir(exist_ok=True)
	selected = {'f32-values', 'f32-semantic-standalone', 'f32-core-standalone', 'f32-cfg-standalone', 'f32-ssa-standalone', 'f32-nabi-standalone', 'f32-pipeline', 'f32-llvm', 'cabi-standalone', 'vapi', 'owned-boundaries', 'resources', 'semantic', 'core', 'cfg'}
	jobs = []
	for test in json.loads((build / 'meson-info/intro-tests.json').read_text()):
		if test['name'] in selected:
			jobs.append((test['name'], test['cmd'], test['workdir'] or str(build), dict(os.environ, **test['env']), 0))
	for name in FIXTURES + ['matrix']:
		jobs.append(('run-' + name, [str(build / 'tests/f32/execution' / name)], str(ROOT), dict(os.environ), 0))
	for name in ['literals', 'special', 'struct', 'addressable', 'ownership', 'physical']:
		options = [*bindings(), '--link-object', build / 'tests/cabi/companion.o'] if name == 'ownership' else []
		jobs.append(('compile-' + name, [str(build / 'astrac'), str(ROOT / f'tests/f32/fixtures/f32-{name}.astra'), *map(str, options), '-o', str(logs / name)], str(ROOT), dict(os.environ), 0))
	for mode in ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']:
		jobs.append(('dump-' + mode, [str(build / 'astrac'), '--dump-' + mode, str(ROOT / 'tests/f32/fixtures/f32-literals.astra')], str(ROOT), dict(os.environ), 0))
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
	out = build / 'qualification'
	out.mkdir(exist_ok=True)
	(memory if args.memory else audit)(build, out)
