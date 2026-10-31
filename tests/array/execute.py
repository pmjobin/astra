# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Native array storage, exact ordinal and effect-order qualification."""
from pathlib import Path
import json
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ['basic', 'index', 'bounds', 'order', 'loop', 'f32', 'vector', 'dsp', 'ownership']
INTEGERS = {'i8': (8, True), 'u8': (8, False), 'i16': (16, True), 'u16': (16, False), 'int': (32, True), 'u32': (32, False)}


def run(argv, expected=0, output=''):
	r = subprocess.run(list(map(str, argv)), cwd=ROOT, capture_output=True, text=True)
	assert (r.returncode, r.stdout, r.stderr) == (expected, output, ''), (argv, r)
	return r


def matrices():
	functions = []
	checks = []
	shapes = []
	count = 0
	for element in [*INTEGERS, 'f32']:
		bits, signed = INTEGERS.get(element, (32, None))
		if signed is None:
			values = ['-0.0', '1.401298464324817070923729583289916131280e-45', '3.4028234663852886e38', '-123.25']
		else:
			values = list(map(str, [-(2**(bits-1)), 2**(bits-1)-1, -1, 0] if signed else [2**bits-1, 2**(bits-1), 0, 1]))
		for lanes in [0, 2, 4, 8, 16]:
			if lanes and bits * lanes > 128:
				continue
			type_name = f'{element}<{lanes}>' if lanes else element
			shapes.append(type_name)
			for index_type in INTEGERS:
				name = f'matrix_{element}_{lanes}_{index_type}'
				lines = [f'bool {name}({index_type} i){{']
				for j, value in enumerate(values):
					lines.append(f'\t{type_name} v{j}=' + (f'splat({value},{lanes})' if lanes else value) + ';')
				lines.append(f'\t{type_name}[4] a={{v0,v1,v2,v3}};')
				for j in range(4):
					compare = f'all(a[i]==v{j})' if lanes else f'a[i]==v{j}'
					lines.append(f'\tif(i=={j} && !({compare})){{return false;}}')
				lines.append('\ta[i]=v1;')
				compare = 'all(a[i]==v1)' if lanes else 'a[i]==v1'
				lines += [f'\treturn {compare};', '}']
				functions.extend(lines)
				for j in range(4):
					checks.append(f'\tif(!{name}({j})){{return 1;}}')
					count += 2
					# Bounds above small index domains must not wrap in the comparison, and
					# high-bit unsigned valid ordinals must zero-extend for GEP.
	for length, index_type, index in [(128, 'i8', 127), (256, 'u8', 255), (1024, 'u16', 1023), (1024, 'u32', 1023), (1024, 'int', 1023)]:
		name = f'wide_{length}_{index_type}'
		functions += [f'bool {name}({index_type} i){{', f'\tint[{length}] a={{' + ','.join(map(str, range(length))) + '};', '\ta[i]=1234;', '\treturn a[i]==1234;', '}']
		checks.append(f'\tif(!{name}({index})){{return 2;}}')
	return '\n'.join([*functions, 'int main(){', *checks, '\treturn 0;', '}'])+'\n', count, shapes


def main(compiler, companion, out):
	out.mkdir(parents=True, exist_ok=True)
	results = {'fixtures': FIXTURES, 'traps': []}
	for name in FIXTURES:
		options = [arg for api in ['types', 'api'] for arg in ['--vapi', ROOT/f'tests/resource/fixtures/resource-{api}.vapi']] + ['--link-object', companion] if name == 'ownership' else []
		run([compiler, ROOT/f'tests/array/fixtures/array-{name}.astra', *options, '-o', out/name])
		run([out/name])
	source, count, shapes = matrices()
	(out/'matrix.astra').write_text(source)
	run([compiler, out/'matrix.astra', '-o', out/'matrix'])
	run([out/'matrix'])
	results.update(exact_read_write_checks=count, storage_shapes=shapes, large_length_checks=5)
	for index_type, (bits, signed) in INTEGERS.items():
		invalid = [-1, 4, 2**(bits-1)-1] if signed else [4, 2**bits-1]
		for k, index in enumerate(invalid):
			for operation in ['read', 'write']:
				name = f'trap-{index_type}-{k}-{operation}'
				body = 'int x=a[i];' if operation == 'read' else 'a[i]=42;'
				source = f'void access({index_type} i){{int[4] a={{1,2,3,4}};{body}}} int main(){{access({index});return 0;}}\n'
				(out/(name+'.astra')).write_text(source)
				run([compiler, out/(name+'.astra'), '-o', out/name])
				run([out/name], -signal.SIGILL)
				results['traps'].append(name)
	foreign = 'extern(C) int putchar(int c);extern(C) int fflush(void* p);'
	effects = {
		'trap-effects': (foreign+'int index(int i){putchar(73);fflush(null);return i;} int rhs(){putchar(82);fflush(null);return 42;} void f(int i){int[1] a={0};a[index(i)]=rhs();} int main(){f(-1);return 0;}', 'I', -signal.SIGILL),
		'trap-eager': ('bool f(int i){int[1] a={1};return (i>=0)&(a[i]>0);} int main(){bool x=f(-1);return 0;}', '', -signal.SIGILL),
		'trap-vector': ('void f(u32 i){i16<4> v=splat(1,4);i16<4>[1] a={v};a[i]=v;} int main(){f(4294967295);return 0;}', '', -signal.SIGILL),
		'captured-index': ('int index(int* i){return *i;} int rhs(int* i){*i=1;return 42;} int main(){int i=0;int[2] a={1,2};a[index(&i)]=rhs(&i);if(a[0]!=42 || a[1]!=2 || i!=1){return 1;}return 0;}', '', 0),
	}
	for name, (source, output, status) in effects.items():
		(out/(name+'.astra')).write_text(source+'\n')
		run([compiler, out/(name+'.astra'), '-o', out/name])
		run([out/name], status, output)
		if status:
			results['traps'].append(name)
	(out/'results.json').write_text(json.dumps(results, indent='\t')+'\n')
	print(json.dumps(results), flush=True)


if __name__ == '__main__':
	main(*(Path(arg).resolve() for arg in sys.argv[1:]))
