# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Native bounded views: exact elements, extents, aliases, traps and effects."""
from pathlib import Path
import json
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ['basic', 'subrange', 'empty', 'len', 'alias', 'branch', 'loop', 'bounds', 'order', 'f32', 'vector', 'dsp', 'ownership']
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
				lines += [f'\t{type_name}[4] a={{v0,v1,v2,v3}};', f'\t{type_name}[] s=slice(a);', f'\t{type_name}[] copy=s;', '\tif(len(s)!=4){return false;}']
				for j in range(4):
					compare = f'all(s[i]==v{j})' if lanes else f's[i]==v{j}'
					lines.append(f'\tif(i=={j} && !({compare})){{return false;}}')
				lines.append('\ts[i]=v1;')
				compare = 'all(copy[i]==v1) && all(a[i]==v1)' if lanes else 'copy[i]==v1 && a[i]==v1'
				lines += [f'\treturn {compare};', '}']
				functions.extend(lines)
				for j in range(4):
					checks.append(f'\tif(!{name}({j})){{return 1;}}')
					count += 3
	for length, index_type, index in [(128, 'i8', 127), (256, 'u8', 255), (1024, 'u16', 1023), (1024, 'u32', 1023), (1024, 'int', 1023)]:
		name = f'wide_{length}_{index_type}'
		functions += [f'bool {name}({index_type} i){{', f'\tint[{length}] a={{' + ','.join(map(str, range(length))) + '};', '\tint[] s=slice(a);', '\tif(s[i]!=i as int){return false;}', '\ts[i]=1234;', f'\treturn s[i]==1234 && a[i]==1234 && len(s)=={length};', '}']
		checks.append(f'\tif(!{name}({index})){{return 2;}}')
	return '\n'.join([*functions, 'int main(){', *checks, '\treturn 0;', '}'])+'\n', count, shapes


def range_matrix():
	functions = []
	checks = []
	cases = 0
	for start in INTEGERS:
		for count in INTEGERS:
			name = f'range_{start}_{count}'
			functions += [f'bool {name}({start} start,{count} count){{', '\tint[4] a={0,1,2,3};', '\tint[] s=slice(a,start,count);', '\tif(len(s)!=count as int){return false;}', '\tint i=0;', '\twhile(i<len(s)){if(s[i]!=start as int+i){return false;}i=i+1;}', '\treturn true;', '}']
			for first in range(5):
				for length in range(5-first):
					checks.append(f'\tif(!{name}({first},{length})){{return 1;}}')
					cases += 1
	return '\n'.join([*functions, 'int main(){', *checks, '\treturn 0;', '}'])+'\n', cases


def main(compiler, companion, out):
	out.mkdir(parents=True, exist_ok=True)
	results = {'fixtures': FIXTURES, 'valid_cases': [], 'traps': [], 'effects': {}}
	for name in FIXTURES:
		options = [arg for api in ['types', 'api'] for arg in ['--vapi', ROOT/f'tests/resource/fixtures/resource-{api}.vapi']] + ['--link-object', companion] if name == 'ownership' else []
		run([compiler, ROOT/f'tests/slice/fixtures/slice-{name}.astra', *options, '-o', out/name])
		run([out/name])

	def execute(name, source, status=0, output=''):
		assert name not in FIXTURES, 'Generated cases must preserve the named fixture executables'
		(out/(name+'.astra')).write_text(source+'\n')
		run([compiler, out/(name+'.astra'), '-o', out/name])
		run([out/name], status, output)
		if status:
			results['traps'].append(name)

	source, count, shapes = matrices()
	execute('matrix', source)
	results.update(exact_read_write_alias_checks=count, storage_shapes=shapes, large_length_checks=5)
	source, cases = range_matrix()
	execute('ranges', source)
	results['valid_range_checks'] = cases
	for index_type, (bits, signed) in INTEGERS.items():
		invalid = [-1, 4, 2**(bits-1)-1] if signed else [4, 2**bits-1]
		for k, index in enumerate(invalid):
			for operation in ['read', 'write']:
				body = 'int x=s[i];' if operation == 'read' else 's[i]=42;'
				execute(f'trap-{index_type}-{k}-{operation}', f'void access({index_type} i){{int[4] a={{1,2,3,4}};int[] s=slice(a);{body}}} int main(){{access({index});return 0;}}', -signal.SIGILL)
		for end in [0, 4]:
			execute(f'trap-empty-{index_type}-{end}', f'void access({index_type} i){{int[4] a={{1,2,3,4}};int[] s=slice(a,{end},0);s[i]=42;}}int main(){{access(0);return 0;}}', -signal.SIGILL)
		for which in ['start', 'count']:
			invalid_range = [-1, 5, 2**(bits-1)-1] if signed else [5, 2**bits-1]
			for k, number in enumerate(invalid_range):
				range_args = 'n,0' if which == 'start' else '1,n'
				execute(f'trap-range-{which}-{index_type}-{k}', f'void access({index_type} n){{int[4] a={{1,2,3,4}};int[] s=slice(a,{range_args});}}int main(){{access({number});return 0;}}', -signal.SIGILL)
				# A constant index still uses the selected runtime extent.
	execute('trap-constant-runtime-length', 'void f(bool b){int[1] a={1};int[4] c={1,2,3,4};int[] s=slice(c);if(b){s=slice(a);}s[2]=1;}int main(){f(true);return 0;}', -signal.SIGILL)
	execute('trap-remaining', 'void f(int start,int count){int[4] a={1,2,3,4};int[] s=slice(a,start,count);}int main(){f(3,2);return 0;}', -signal.SIGILL)
	foreign = 'extern(C) int putchar(int c);extern(C) int fflush(void* p);'
	recorder = foreign+'int record(int digit,int value){putchar(digit);fflush(null);return value;}'
	for start, count, index, output, status, name in [(1,2,0,'SCIR',0,'valid'),(-1,2,0,'SC',-signal.SIGILL,'start'),(1,4,0,'SC',-signal.SIGILL,'count'),(1,2,2,'SCI',-signal.SIGILL,'index'),(4,0,0,'SCI',-signal.SIGILL,'empty')]:
		source = recorder+f'int main(){{int[4] a={{1,2,3,4}};slice(a,record(83,{start}),record(67,{count}))[record(73,{index})]=record(82,42);return 0;}}'
		execute('effect-'+name, source, status, output)
		results['effects'][name] = output
	for name, source, status in [
		('full-alias', 'int flagship(){int[4] storage={1,2,3,4};int[] a=slice(storage);int[] b=slice(storage);a[1]=42;return b[1];}int main(){if(flagship()!=42){return 1;}return 0;}', 0),
		('full-branch', 'int choose(bool condition){int[4] a={1,2,3,4};int[8] b={5,6,7,8,9,10,11,12};int[] s=slice(a);if(condition){s=slice(b);}return len(s);}int main(){if(choose(false)!=4 || choose(true)!=8){return 1;}return 0;}', 0),
		('eager', 'bool f(int i){int[1] a={1};int[] s=slice(a);return (i>=0)&(s[i]>0);}int main(){bool x=f(-1);return 0;}', -signal.SIGILL),
		('trap-vector', 'void f(u32 i){i16<8> v=splat(1,8);i16<8>[1] a={v};i16<8>[] s=slice(a);s[i]=v;}int main(){f(4294967295);return 0;}', -signal.SIGILL),
		('captured-view', 'int index(int* start,int* count){*start=2;*count=0;return 0;}int main(){int[4] a={10,20,30,40};int start=1;int count=2;int x=slice(a,start,count)[index(&start,&count)];if(x!=20 || start!=2 || count!=0){return 1;}return 0;}', 0),
		('captured-index', 'int rhs(int* i){*i=1;return 42;}int main(){int i=0;int[2] a={1,2};int[] s=slice(a);s[i]=rhs(&i);if(a[0]!=42 || a[1]!=2 || i!=1){return 1;}return 0;}', 0),
		('rhs-join', 'int rhs(bool b){if(b){return 42;}return 0;}int f(int i){int[2] a={1,2};int[] s=slice(a);s[i]=rhs(i>=0 && i<len(s) && s[i]>0);return s[i];}int main(){if(f(1)!=42){return 1;}return 0;}', 0),
		('vector-subrange', 'bool f(int start,int count){f32<4> a=splat(1.0,4);f32<4> b=splat(2.0,4);f32<4> c=splat(3.0,4);f32<4>[4] storage={a,b,c,a};f32<4>[] s=slice(storage,start,count);if(len(s)!=2 || !all(s[0]==b) || !all(s[1]==c)){return false;}s[0]=c;return all(storage[1]==c);}int main(){if(!f(1,2)){return 1;}return 0;}', 0),
	]:
		execute(name, source, status)
		if status == 0:
			results['valid_cases'].append(name)
	(out/'results.json').write_text(json.dumps(results, indent='\t')+'\n')
	print(json.dumps(results), flush=True)


if __name__ == '__main__':
	main(*(Path(arg).resolve() for arg in sys.argv[1:]))
