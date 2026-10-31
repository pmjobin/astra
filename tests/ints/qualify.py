# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Reproduce INTS-1 LLVM/object, golden, strict-build, and memory audits."""
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

BASELINE = '4fe412a59ade5cb7d89cc2e36b0e001a1350b200'


def run(argv):
	result = subprocess.run([str(arg) for arg in argv], cwd=ROOT, capture_output=True, text=True)
	if result.returncode:
		raise RuntimeError(f'{argv}: {result.returncode}\n{result.stdout}\n{result.stderr}')
	return result.stdout


def predecessors(llvm):
	counts = {'phis': 0, 'signed_continuation_edges': 0, 'unsigned_continuation_edges': 0, 'bool_split_edges': 0}
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
						assert target in incoming
						incoming[target].add(block)
		for block, lines in blocks.items():
			for line in lines:
				if ' = phi ' not in line:
					continue
				preds = re.findall(r', %([\w.]+) \]', line)
				assert set(preds) == incoming[block], (block, line, incoming[block])
				counts['phis'] += 1
				counts['signed_continuation_edges'] += sum(pred.endswith('.continue') for pred in preds)
				counts['unsigned_continuation_edges'] += sum(pred.endswith('.nonzero') for pred in preds)
				counts['bool_split_edges'] += sum(pred.endswith(('.continue', '.nonzero')) for pred in preds) if 'phi i1 ' in line else 0
	return counts


def audit(build, out):
	rows = []
	for name in FIXTURES + ['physical']:
		source = ROOT / f'tests/ints/fixtures/ints-{name}.astra'
		stem = out / name
		options = bindings() if name == 'ownership' else []
		llvm = run([build / 'astrac', '--dump-llvm', source, *options])
		assert not re.search(r'\b(sext|zext|trunc|poison)\b', llvm), name
		# LLVMBuildStructGEP2 already prints inbounds nuw in the accepted
		# addressable-storage path. Check arithmetic flags, not GEP bounds.
		assert not re.search(r'\b(add|sub|mul)\s+(?:nsw|nuw)\b', llvm), name
		for line in llvm.splitlines():
			if re.search(r'\b(nsw|nuw)\b', line):
				assert 'getelementptr inbounds nuw' in line, (name, line)
		assert not re.search(r'call\b[^\n]*%[\w.]+\(', llvm), name
		declarations = re.findall(r'(?m)^(i8|u8|i16|u16|i32|u32|int|bool|void) (\w+)\(([^)]*)\)\s*\{', source.read_text())
		definitions = re.findall(r'(?m)^define internal fastcc (void|i8|i16|i32|i1|ptr) @astra.fn.\d+\(([^)]*)\)', llvm)
		assert len(declarations) == len(definitions), (name, len(declarations), len(definitions))
		physical = {'i8': 'i8', 'u8': 'i8', 'i16': 'i16', 'u16': 'i16', 'i32': 'i32', 'int': 'i32', 'u32': 'i32', 'bool': 'i1', 'void': 'void', 'void*': 'ptr', 'Packet*': 'ptr', 'Resource': 'ptr'}
		for (result, _, parameters), (lowered_result, lowered_parameters) in zip(declarations, definitions):
			expected = [physical[p.strip().split()[-2]] for p in parameters.split(',') if p.strip()]
			actual = [p.strip().split()[0] for p in lowered_parameters.split(',') if p.strip()]
			assert lowered_result == physical[result] and actual == expected, (name, expected, actual)
		phis = predecessors(llvm)
		if name in ['branch', 'loop']:
			assert phis['signed_continuation_edges'] > 0 and phis['unsigned_continuation_edges'] > 0, phis
		if name == 'branch':
			assert phis['bool_split_edges'] > 0, phis
		if name == 'physical':
			for width in ['i8', 'i16', 'i32']:
				for op in ['add', 'sub', 'mul', 'sdiv', 'srem', 'udiv', 'urem']:
					assert f'{op} {width} ' in llvm
				for pred in ['slt', 'sle', 'sgt', 'sge', 'ult', 'ule', 'ugt', 'uge', 'eq', 'ne']:
					assert f'icmp {pred} {width} ' in llvm
			for (result, source_name, _), body in zip(declarations, re.findall(r'(?ms)^define [^\n]+\{\n(.*?)^}', llvm)):
				if source_name.startswith(('div_', 'rem_')):
					assert 'call void @llvm.trap()' in body
					assert ('.special' in body) == result.startswith('i')
					assert (' = sdiv ' in body or ' = srem ' in body) == result.startswith('i')
		stem.with_suffix('.ll').write_text(llvm)
		run(['llvm-as', stem.with_suffix('.ll'), '-o', stem.with_suffix('.bc')])
		run(['llc', '-O0', '-filetype=obj', '-relocation-model=pic', stem.with_suffix('.bc'), '-o', stem.with_suffix('.o')])
		for tool, flags in [('nm', ['-a']), ('readelf', ['-aW']), ('objdump', ['-dr'])]:
			stem.with_suffix('.' + tool).write_text(run([tool, *flags, stem.with_suffix('.o')]))
		for line in run(['nm', '-u', stem.with_suffix('.o')]).splitlines():
			assert 'astra_test_resource_' in line or '_GLOBAL_OFFSET_TABLE_' in line, (name, line)
		if name in FIXTURES:
			executable = build / 'tests/ints/execution' / name
			assert executable.exists(), 'Run Meson execution tests before the audit'
			linked = run(['ldd', executable])
			stem.with_suffix('.ldd').write_text(linked)
			assert not any(word in linked.lower() for word in ['glib', 'gobject', 'llvm'])
		rows.append({'fixture': name, 'llvm_verified': True, 'exact_signature': True, 'object_audited': True, **phis})
	goldens = 0
	for path in run(['git', 'ls-tree', '-r', '--name-only', BASELINE, 'tests']).splitlines():
		if Path(path).suffix not in {'.syntax', '.semantics', '.core', '.cfg', '.ssa', '.nabi', '.cabi', '.ll', '.stderr'}:
			continue
		before = subprocess.run(['git', 'show', BASELINE + ':' + path], cwd=ROOT, capture_output=True, check=True).stdout
		assert (ROOT / path).read_bytes() == before, path
		goldens += 1
	for path in ['bootstrap/cabi', 'bootstrap/vapi', 'bootstrap/foreign', 'bootstrap/cfg/ownership-flow.vala', 'bootstrap/cfg/predecessors.vala', 'bootstrap/ssa/dominance.vala']:
		assert run(['git', 'diff', BASELINE, '--', path]) == '', path
	commands = json.loads((build / 'compile_commands.json').read_text())
	generated = [row for row in commands if row['file'].endswith('.c') and 'meson-generated' in row['command']]
	assert generated and all('-DVALA_STRICT_C' in row['command'] and '-Werror' in row['command'] for row in generated)
	result = {'baseline': BASELINE, 'workloads': rows, 'baseline_goldens_unchanged': goldens, 'strict_generated_c_commands': len(generated)}
	(out / 'audit-results.json').write_text(json.dumps(result, indent='\t') + '\n')
	print(json.dumps(result), flush=True)


def memory(build, out):
	assert (out / 'audit-results.json').exists(), 'Run the object audit first'
	logs = out / 'valgrind'
	logs.mkdir(exist_ok=True)
	selected = {'ints-reference', 'ints-semantic-standalone', 'ints-core-standalone', 'ints-cfg-standalone', 'ints-ssa-standalone', 'ints-nabi-standalone', 'ints-pipeline', 'ints-llvm', 'scalar-reference', 'scalar-pipeline', 'semantic', 'core', 'cfg', 'ssa', 'core-standalone', 'cfg-standalone', 'ssa-standalone', 'nabi', 'nabi-standalone', 'cabi', 'cabi-standalone', 'vapi', 'vapi-frontend', 'owned-boundaries', 'owned-boundaries-llvm', 'ownbound-semantic-standalone', 'ownbound-core-standalone', 'ownbound-cfg-standalone', 'ownbound-ssa-standalone', 'ownbound-abi-standalone', 'resources', 'ownership', 'moves', 'owner-borrows', 'releases', 'rearms', 'native-execution'}
	jobs = []
	for test in json.loads((build / 'meson-info/intro-tests.json').read_text()):
		if test['name'] in selected:
			args = test['cmd'] + (['-p', '/exec/ownbound'] if test['name'] == 'native-execution' else [])
			jobs.append((test['name'], args, test['workdir'] or str(build), dict(os.environ, **test['env']), 0))
	for name in FIXTURES:
		jobs.append(('run-' + name, [str(build / 'tests/ints/execution' / name)], str(ROOT), dict(os.environ), 0))
		source = ROOT / f'tests/ints/fixtures/ints-{name}.astra'
		options = [*bindings(), '--link-object', build / 'tests/cabi/companion.o'] if name == 'ownership' else []
		jobs.append(('compile-' + name, [str(build / 'astrac'), str(source), *map(str, options), '-o', str(logs / name)], str(ROOT), dict(os.environ), 0))
	for t in ['i8', 'u8', 'i16', 'u16', 'i32', 'u32']:
		jobs.append(('run-matrix-' + t, [str(build / 'tests/ints/execution' / ('matrix-' + t))], str(ROOT), dict(os.environ), 0))
	for mode in ['--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']:
		jobs.append((mode[2:], [str(build / 'astrac'), mode, str(ROOT / 'tests/ints/fixtures/ints-literals.astra')], str(ROOT), dict(os.environ), 0))
	jobs.append(('reject-range', [str(build / 'astrac'), '--check', str(ROOT / 'tests/ints/fixtures/ints-invalid.astra')], str(ROOT), dict(os.environ), 1))
	flags = ['--vgdb=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99']

	def measure(job):
		name, args, cwd, env, expected = job
		command = ['valgrind', *flags, '--log-file=' + str(logs / (name + '.log')), *args]
		result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True)
		(logs / (name + '.stdout')).write_text(result.stdout)
		(logs / (name + '.stderr')).write_text(result.stderr)
		log = (logs / (name + '.log')).read_text()
		assert 'ERROR SUMMARY:' in log, name

		def number(pattern):
			match = re.search(pattern, log)
			return int(match[1].replace(',', '')) if match else 0

		return {'name': name, 'command': command, 'exit': result.returncode, 'expected': expected, 'errors': number(r'ERROR SUMMARY: ([\d,]+) errors'), 'definite': number(r'definitely lost: ([\d,]+) bytes'), 'indirect': number(r'indirectly lost: ([\d,]+) bytes'), 'possible': number(r'possibly lost: ([\d,]+) bytes'), 'reachable': number(r'still reachable: ([\d,]+) bytes')}

	results = []
	with ThreadPoolExecutor(max_workers=4) as pool:
		for future in as_completed([pool.submit(measure, job) for job in jobs]):
			row = future.result()
			results.append(row)
			print(json.dumps({key: value for key, value in row.items() if key != 'command'}), flush=True)
			(logs / 'results.json').write_text(json.dumps(sorted(results, key=lambda row: row['name']), indent='\t') + '\n')
	issues = [row['name'] for row in results if row['exit'] != row['expected'] or row['errors'] or row['definite'] or row['indirect'] or row['possible']]
	print(json.dumps({'measured': len(results), 'requires_investigation': issues}), flush=True)


if __name__ == '__main__':
	parser = argparse.ArgumentParser()
	parser.add_argument('build', type=Path)
	parser.add_argument('--memory', action='store_true')
	args = parser.parse_args()
	build = args.build.resolve()
	out = build / 'qualification'
	out.mkdir(exist_ok=True)
	(memory if args.memory else audit)(build, out)
