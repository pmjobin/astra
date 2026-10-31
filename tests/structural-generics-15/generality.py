# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Apply a bounded, seeded structural matrix to a cell and an accumulator.

Every family changes both abstractions. Expectations come from the Python model
and declared reverse field/local retirement order, independently of emitted IR.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import random
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
FAMILIES = ['baseline', 'rename', 'copied-fields', 'owned-field', 'parameters',
	'nesting', 'helpers', 'declarations', 'diamond', 'inputs-and-types']


def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()


def generate(family, seed):
	rng = random.Random(seed)
	renamed = family == 'rename'
	leaf = 'DifferentFoundation' if renamed else 'MatrixFoundation'
	middle = 'DifferentOperations' if renamed else 'MatrixOperations'
	side = 'DifferentBranch' if renamed else 'MatrixBranch'
	cell = 'Chamber' if renamed else 'Cell'
	accumulator = 'Journal' if renamed else 'Accumulator'
	value, tag = ('content', 'label') if renamed else ('payload', 'tag')
	read, write = ('observe', 'replace') if renamed else ('read', 'write')
	parameter = 'Element' if renamed else 'T'
	parameters = f'Flag, Spare, {parameter}' if family == 'parameters' else f'{parameter}, Flag'
	payload = 'Parcel<int>' if family == 'nesting' else 'i64' if family == 'inputs-and-types' else 'int'
	arguments = f'bool, i64, {payload}' if family == 'parameters' else f'{payload}, bool'
	inputs = [rng.randrange(3, 70) for _ in range(3 if family != 'inputs-and-types' else 7)]
	primary = 61
	secondary = 161

	def declaration(name, accumulating):
		fields = [f'private {parameter} {value};', f'private Flag {tag};',
			'private int changes;', 'private owned R guard;']
		initializers = [f'this.{value} = initial;', f'this.{tag} = flag;',
			'this.changes = 0;', 'this.guard = move guard;']
		if family == 'copied-fields':
			# One before, one between, and one after the existing fields.
			fields = ['private int before;', fields[0], 'private bool between;', *fields[1:], 'private i64 after;']
			initializers += ['this.before = 7;', 'this.between = true;', 'this.after = 9000000001;']
		if family == 'owned-field':
			# The declaration order differs from initialization order deliberately.
			fields.insert(0, 'private owned Other extra;')
			initializers += ['this.extra = move extra;']
		formal = f'{parameter} initial, Flag flag, owned R guard'
		if family == 'parameters':
			fields.insert(1, 'private Spare auxiliary;')
			initializers += ['this.auxiliary = spare;']
			formal += ', Spare spare'
		if family == 'owned-field':
			formal += ', owned Other extra'
		body = f'this.{value} = replacement;'
		if accumulating:
			body += '\n\t\tthis.changes = this.changes + 1;'
		if family == 'helpers':
			body = f'if (this.changes >= 0) {{ this.store(replacement); }}'
		methods = [f'{parameter} {read}() {{ return this.{value}; }}',
			f'void {write}({parameter} replacement) {{\n\t\t{body}\n\t}}',
			'int count() { return this.changes; }',
			f'property Flag flag {{ get {{ return this.{tag}; }} }}']
		if family == 'parameters':
			methods += ['Spare extra_value() { return this.auxiliary; }']
		if family == 'helpers':
			methods += [f'void store({parameter} replacement) {{ this.{value} = replacement;' +
				(' this.changes = this.changes + 1;' if accumulating else '') + ' }']
		if family == 'declarations':
			methods.reverse()
			fields.reverse()
		return f'class {name}<{parameters}> {{\n' + '\n'.join('\t' + f for f in fields) + \
			f'\n\tinit({formal}) {{\n' + '\n'.join('\t\t' + f for f in initializers) + \
			'\n\t}\n' + '\n'.join('\t' + method for method in methods) + '\n}\n'

	declarations = [declaration(cell, False), declaration(accumulator, True)]
	if family == 'declarations':
		declarations.reverse()
	prelude = 'struct Parcel<X> { X value; bool valid; }\n' if family == 'nesting' else ''
	if family == 'declarations':
		prelude += 'internal int private_marker(int value) { return value + 17; }\n'
	factories = []
	for ordinal, name in enumerate([cell, accumulator]):
		initial = 'Parcel<int> initial = {value = input, valid = true};' if family == 'nesting' else \
			'i64 initial = input as i64;' if family == 'inputs-and-types' else 'int initial = input;'
		if family == 'declarations':
			initial = 'int initial = private_marker(input) - 17;'
		extra = f'\n\tvar extra = make_other({secondary + ordinal});' if family == 'owned-field' else ''
		if family == 'parameters':
			extra += '\n\ti64 spare = 9000000003;'
		factories += [f'owned {name}<{arguments}> create_{ordinal}(int input, int resource) {{\n\t{initial}\n' +
			f'\tvar guard = make(resource);{extra}\n' +
			f'\tvar result = new {name}<{arguments}>(initial, true, move guard' +
			(', move extra' if family == 'owned-field' else ', spare' if family == 'parameters' else '') +
			');\n\treturn move result;\n}\n']
	producer = f'namespace {leaf};\n' + prelude + '\n'.join(declarations + factories)
	imports = []
	if family == 'declarations':
		imports += ['internal int private_marker(int value) { return value + 29; }']
	replacement = f'{leaf}.Parcel<int> replacement = {{value = input + 5, valid = true}};' if family == 'nesting' else \
		'i64 replacement = (input + 5) as i64;' if family == 'inputs-and-types' else 'int replacement = input + 5;'
	first = f'first.{read}().value' if family == 'nesting' else f'first.{read}()'
	second = f'second.{read}().value' if family == 'nesting' else f'second.{read}()'
	if family == 'inputs-and-types':
		first, second = f'({first} as int)', f'({second} as int)'
	branch = f' + {side}.offset()' if family == 'diamond' else ''
	additional_check = '\n\ti64 expected = 9000000003;\n\tif (first.extra_value() != expected || second.extra_value() != expected) { return -2; }' if family == 'parameters' else \
		'\n\tif (private_marker(input) != input + 29) { return -3; }' if family == 'declarations' else ''
	operation = f'namespace {middle};\n' + '\n'.join(imports) + f'''
int evaluate(int input) {{
	var first = {leaf}.create_0(input, {primary});
	var second = {leaf}.create_1(input + 2, {primary + 1});
	{replacement}
	first.{write}(replacement);
	second.{write}(replacement);
	second.{write}(replacement);
	if (!first.flag || !second.flag || first.count() != 0 || second.count() != 2) {{ return -1; }}{additional_check}
	return {first} + {second} + second.count(){branch};
}}
'''
	branch_source = f'namespace {side};\nint offset() {{ return 3; }}\n'
	# The side imports the same leaf identity and calls its factory: a real diamond.
	if family == 'diamond':
		branch_source = f'''namespace {side};
int offset() {{
	var probe = {leaf}.create_0(3, {primary + 2});
	return probe.count() + 3;
}}
'''
	main = 'int main() {\n'
	for index, number in enumerate(inputs):
		expected = 2 * (number + 5) + 2 + (3 if family == 'diamond' else 0)
		main += f'\tif ({middle}.evaluate({number}) != {expected}) {{ return {index + 1}; }}\n'
	main += '\treturn live();\n}\n'
	# Two owning locals retire in reverse order; fields do the same. External R and
	# Other observers report construction and destruction independently.
	trace = f'+{primary}\n+{primary + 1}\n'
	if family == 'owned-field':
		trace = f'+{primary}\n+{secondary}\n+{primary + 1}\n+{secondary + 1}\n'
	if family == 'diamond':
		trace += f'+{primary + 2}\n-{primary + 2}\n'
	for ordinal in [1, 0]:
		if family == 'owned-field':
			trace += f'-{primary + ordinal}\n-{secondary + ordinal}\n'
		else:
			trace += f'-{primary + ordinal}\n'
	return dict(leaf=leaf, middle=middle, side=side, producer=producer, operation=operation,
		branch=branch_source, consumer=main, inputs=inputs, stdout=(trace * len(inputs)).encode(),
		factories=[f'{leaf}.{name}<' + arguments.replace(' ', '').replace('Parcel', leaf + '.Parcel') + '>'
		for name in [cell, accumulator]] +
		([f'{leaf}.Parcel<int>'] if family == 'nesting' else []) +
		[f'{leaf}.create_0', f'{leaf}.create_1'], entry=f'{middle}.evaluate')


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('compiler', type=Path)
	parser.add_argument('output', type=Path)
	parser.add_argument('--seed', type=int, default=151065)
	parser.add_argument('--family', choices=FAMILIES, action='append')
	args = parser.parse_args()
	compiler = args.compiler.resolve(strict=True)
	output = args.output.resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='generality-', dir=output))
	observer = ROOT / 'tests/own-field/companion.c'
	vapi = ROOT / 'tests/own-field/fixtures/resources.vapi'
	receipt = dict(format='astra-m15-generality/1', seed=args.seed, compiler_sha256=sha(compiler),
		sources={str(p.resolve().relative_to(ROOT)): sha(p) for p in [Path(__file__), observer, vapi]},
		families={}, checks=[], products={})

	def save():
		(out / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')

	def run(argv, stdout=b'', memory=False):
		argv = list(map(str, argv))
		started = time.perf_counter()
		result = subprocess.run(argv, cwd=out, capture_output=True, timeout=90,
			env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1', DEBUGINFOD_URLS=''))
		passed = result.returncode == 0 and result.stdout == stdout
		passed &= all(word in result.stderr for word in [b'ERROR SUMMARY: 0 errors',
			b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)']) if memory else not result.stderr
		receipt['checks'].append(dict(argv=argv, exit=result.returncode, passed=bool(passed),
			elapsed_seconds=time.perf_counter() - started, stdout=result.stdout.decode(errors='replace'),
			stderr=result.stderr.decode(errors='replace'), memory=memory))
		save()
		assert passed, receipt['checks'][-1]

	adapter = out / 'observer.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2', '-c', observer, '-o', adapter])
	for family in args.family or FAMILIES:
		model = generate(family, args.seed)
		folder = out / family
		folder.mkdir()
		paths = {}
		for part in ['producer', 'operation', 'consumer', 'branch']:
			path = folder / (part + '.astra')
			path.write_text('// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception\n' + model[part])
			paths[part] = path
		receipt['families'][family] = dict(abstractions=['cell', 'accumulator'], inputs=model['inputs'],
			sources={part: sha(path) for part, path in paths.items()}, expected_stdout=model['stdout'].decode())
		base = [compiler, '--vapi', vapi]
		links = ['--link-object', adapter]
		for level in [0, 1, 2]:
			native = folder / ('mono-O' + str(level))
			sources = [paths['producer'], paths['operation'], paths['consumer']]
			if family == 'diamond':
				sources.insert(1, paths['branch'])
			run([*base, '-O' + str(level), *sources, *links, '-o', native])
			run([native], stdout=model['stdout'])
			run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
				'--errors-for-leak-kinds=all', '--error-exitcode=99', native], stdout=model['stdout'], memory=True)
			receipt['products'][str(native.relative_to(out))] = dict(sha256=sha(native), bytes=native.stat().st_size)
			# Each producer is removed from its original path before downstream compile.
		leaf = folder / 'leaf.asti'
		middle = folder / 'middle.asti'
		exports = [word for name in model['factories'] for word in ['--native-export', name]]
		run([*base, '-O1', '-c', '--module', model['leaf'], '--emit-interface', leaf, *exports,
			paths['producer'], '-o', leaf.with_suffix('.o')])
		paths['producer'].rename(folder / 'hidden-producer.astra')
		imports = ['--import-module', leaf]
		if family == 'diamond':
			side = folder / 'side.asti'
			run([*base, '-O1', '-c', '--module', model['side'], '--emit-interface', side,
				'--native-export', model['side'] + '.offset', *imports, paths['branch'], '-o', side.with_suffix('.o')])
			paths['branch'].rename(folder / 'hidden-branch.astra')
			imports += ['--import-module', side]
		run([*base, '-O1', '-c', '--module', model['middle'], '--emit-interface', middle,
			'--native-export', model['entry'], *imports, paths['operation'], '-o', middle.with_suffix('.o')])
		paths['operation'].rename(folder / 'hidden-operation.astra')
		native = folder / 'native-O1'
		run([*base, '-O1', '--import-module', middle, paths['consumer'], *links, '-o', native])
		run([native], stdout=model['stdout'])
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', native], stdout=model['stdout'], memory=True)
		for path in [*folder.glob('*.asti'), *folder.glob('*.o'), native]:
			receipt['products'][str(path.relative_to(out))] = dict(sha256=sha(path), bytes=path.stat().st_size)
		print('passed:', family, flush=True)
	assert sha(compiler) == receipt['compiler_sha256']
	assert all(sha(ROOT / path) == digest for path, digest in receipt['sources'].items())
	receipt['all_passed'] = True
	save()
	print(out / 'checks.json', flush=True)


if __name__ == '__main__':
	main()
