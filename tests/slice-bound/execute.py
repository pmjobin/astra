# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Native slice boundaries: exact values, shared callees, aliases and traps."""
from pathlib import Path
import json
import re
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ['sum', 'alias', 'forward', 'merge', 'mixed', 'owned', 'bit', 'dsp', 'dot', 'owned-result']
INTEGERS = {'i8': (8, True), 'u8': (8, False), 'i16': (16, True), 'u16': (16, False), 'int': (32, True), 'u32': (32, False)}


def run(argv, status=0, output=None):
	r = subprocess.run(list(map(str, argv)), cwd=ROOT, capture_output=True, text=True)
	assert r.returncode == status and r.stderr == '' and (output is None or r.stdout == output), (argv, r)
	return r.stdout


def matrix():
	functions = []
	checks = []
	shapes = []
	for element in [*INTEGERS, 'f32']:
		bits, signed = INTEGERS.get(element, (32, None))
		values = ['-0.0', '1.401298464324817e-45', '3.4028234663852886e38', '-123.25'] if signed is None else list(map(str, [-(2**(bits-1)), 2**(bits-1)-1, -1, 0] if signed else [2**bits-1, 2**(bits-1), 0, 1]))
		for lanes in [0, 2, 4, 8, 16]:
			if lanes and bits * lanes > 128:
				continue
			type_name = f'{element}<{lanes}>' if lanes else element
			shapes.append(type_name)
			name = f'case_{element}_{lanes}'
			functions += [f'{type_name} set_{name}(borrowed {type_name}[] s,int i,{type_name} value){{', f'\t{type_name} old=s[i];s[i]=value;return old;', '}', f'bool {name}(){{']
			for i, value in enumerate(values):
				functions.append(f'\t{type_name} v{i}=' + (f'splat({value},{lanes})' if lanes else value) + ';')
			functions += [f'\t{type_name}[4] a={{v0,v1,v2,v3}};', f'\t{type_name}[] s=slice(a);']
			for i in range(4):
				for view, index in [('s', i), (f'slice(a,{i},1)', 0)]:
					replacement = 'v1' if view == 's' else f'v{i}'
					expected = f'v{i}' if view == 's' else 'v1'
					comparison = f'set_{name}({view},{index},{replacement})=={expected}'
					alias = f'a[{i}]=={replacement}'
					if lanes:
						comparison, alias = f'all({comparison})', f'all({alias})'
					functions.append(f'\tif(!({comparison}) || !({alias}) || len(s)!=4){{return false;}}')
			functions += ['\treturn true;', '}']
			checks.append(f'\tif(!{name}()){{return 1;}}')
	return '\n'.join([*functions, 'int main(){', *checks, '\treturn 0;', '}']), shapes


def machine(out, companion):
	"""Keep real callable bodies during O2 qualification; production linkage stays internal."""
	summary = {'fixtures': [], 'paired_call_arguments': 0, 'aggregate_phis': 0}
	runs = []
	for name in [*FIXTURES, 'empty-parameter']:
		llvm = (out/(name+'.ll')).read_text()
		functions = re.findall(r'^define [^\n]*@(astra\.fn\.\d+)\(([^\n]*?)\) \{\n(.*?)^}', llvm, re.M | re.S)
		assert functions, name
		for symbol, parameters, body in functions:
			assert not re.search(r'\b(nonnull|noalias|readonly)\b', parameters), (name, symbol)
			assert 'alloca { ptr, i32 }' not in body
			if '.base' in parameters:
				assert 'alloca' not in body, (name, symbol)
			components = {result: (source, int(index)) for result, source, index in re.findall(r'(%[\w.]+) = extractvalue \{ ptr, i32 } (%[\w.]+), ([01])', body)}
			slice_bases = {result for result, (_, index) in components.items() if index == 0} | set(re.findall(r'%p\d+\.base', parameters))
			# The mixed fixture's independent int* out still requires its own null check.
			assert not slice_bases.intersection(re.findall(r'icmp (?:eq|ne) ptr (%[\w.]+), null', body)), (name, symbol)
			for line in body.splitlines():
				if 'call fastcc' not in line:
					continue
				for base, length in re.findall(r'ptr (%arg[\w.]+), i32 (%arg[\w.]+)', line):
					assert components[base][0] == components[length][0] and components[base][1] == 0 and components[length][1] == 1, (name, line)
					summary['paired_call_arguments'] += 1
			parts = re.split(r'^([\w.]+):[^\n]*\n', body, flags=re.M)
			blocks = dict(zip(parts[1::2], parts[2::2]))
			predecessors = {block: set() for block in blocks}
			for block, instructions in blocks.items():
				for target in re.findall(r'label %([\w.]+)', instructions):
					predecessors[target].add(block)
			for block, instructions in blocks.items():
				for incoming in re.findall(r'phi \{ ptr, i32 } ([^\n]+)', instructions):
					assert set(re.findall(r', %([\w.]+) ]', incoming)) == predecessors[block], (name, block, incoming)
					summary['aggregate_phis'] += 1
					# Retain the compiler-produced linkage in an unoptimized object audit.
		stem = name+'-machine'
		run(['llc', '-O0', '-filetype=obj', '-relocation-model=pic', out/(name+'.ll'), '-o', out/(stem+'-O0.o')], output='')
		symbols = run(['nm', '--defined-only', out/(stem+'-O0.o')])
		assert all(re.search(r' t '+re.escape(symbol)+r'$', symbols, re.M) for symbol, _, _ in functions), name
		(out/(stem+'-O0.symbols')).write_text(symbols)
		(out/(stem+'-O0.disassembly')).write_text(run(['objdump', '-dr', out/(stem+'-O0.o')]))
		(out/(stem+'-O0.elf')).write_text(run(['readelf', '-h', '-Ws', out/(stem+'-O0.o')]))
		# Only this audit copy uses external linkage and noinline. O2 therefore
		# cannot replace the entire overlap test with its constant answer.
		preserved = re.sub(r'^define internal fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', llvm, flags=re.M)
		(out/(stem+'.ll')).write_text(preserved)
		run(['opt', '-passes=default<O2>', '-S', out/(stem+'.ll'), '-o', out/(stem+'-O2.ll')], output='')
		run(['opt', '-passes=verify', '-disable-output', out/(stem+'-O2.ll')], output='')
		optimized = (out/(stem+'-O2.ll')).read_text()
		assert all(re.search(r'^define [^\n]*@'+re.escape(symbol)+r'\(', optimized, re.M) for symbol, _, _ in functions), name
		if name == 'alias':
			alias = re.search(r'^define [^\n]*@astra\.fn\.1\([^\n]*\).*?\n(.*?)^}', optimized, re.M | re.S)[1]
			assert 'store i32 40' in alias and len(re.findall(r'load i32', alias)) >= 2 and len(re.findall(r'store i32', alias)) >= 2
			assert alias.rfind('load i32') > alias.rfind('store i32') and 'noalias' not in alias
		if name == 'merge':
			assert summary['aggregate_phis'] >= 2
			assert 'phi ptr' in optimized or 'select i1' in optimized
		if name == 'empty-parameter':
			# O2 may merge the two identical, side-effect-free empty-view calls.
			assert re.search(r'@astra\.fn\.0\(ptr null, i32 0\)', optimized)
		run(['llc', '-O2', '-filetype=obj', '-relocation-model=pic', out/(stem+'-O2.ll'), '-o', out/(stem+'-O2.o')], output='')
		run(['cc', out/(stem+'-O2.o'), *([companion] if name.startswith('owned') else []), '-o', out/(stem+'-O2')], output='')
		status = 46 if name == 'sum' else 0
		run([out/(stem+'-O2')], status, '')
		runs.append(dict(name=stem+'-O2', status=status, output='', optimized=True))
		disassembly = run(['objdump', '-dr', out/(stem+'-O2.o')])
		assert all('<'+symbol+'>:' in disassembly for symbol, _, _ in functions), name
		if name in {'alias', 'merge'}:
			assert re.search(r'R_\w+\s+astra\.fn\.1', disassembly), name
		(out/(stem+'-O2.disassembly')).write_text(disassembly)
		(out/(stem+'-O2.elf')).write_text(run(['readelf', '-h', '-Ws', out/(stem+'-O2.o')]))
		undefined = run(['nm', '-u', out/(stem+'-O2.o')])
		assert not re.search(r'slice|LLVM|g_object|g_type_', undefined), (name, undefined)
		(out/(stem+'-O2.undefined')).write_text(undefined)
		for executable in [name, name+'-O2', stem+'-O2']:
			linkage = run(['ldd', out/executable])
			assert not re.search(r'libglib|libgobject|libLLVM', linkage), (name, linkage)
			(out/(executable+'.linkage')).write_text(linkage)
		summary['fixtures'].append(dict(name=name, functions=len(functions), production_linkage='internal', optimized_status=status))
	(out/'machine-results.json').write_text(json.dumps(summary, indent='\t')+'\n')
	return runs


def main(compiler, companion, out):
	out.mkdir(parents=True, exist_ok=True)
	bindings = [arg for name in ['types', 'api'] for arg in ['--vapi', ROOT/f'tests/resource/fixtures/resource-{name}.vapi']]
	results = {'runs': [], 'shapes': []}

	def execute(name, source, status=0, output='', owned=False, optimize=False):
		path = out/(name+'.astra')
		path.write_text(source+'\n')
		options = [*bindings, '--link-object', companion] if owned else []
		run([compiler, path, *options, '-o', out/name], output='')
		run([out/name], status, output)
		results['runs'].append(dict(name=name, status=status, output=output, optimized=False))
		if optimize:
			declarations = bindings if owned else []
			llvm = run([compiler, '--dump-llvm', path, *declarations])
			ssa = run([compiler, '--dump-ssa', path, *declarations])
			main_id = re.search(r'\(function #(\d+) "main" -> int', ssa)[1]
			llvm += '\ndefine i32 @main() {\n\t%result = call fastcc i32 @astra.fn.'+main_id+'()\n\tret i32 %result\n}\n'
			(out/(name+'.ll')).write_text(llvm)
			run(['opt', '-passes=default<O2>', '-S', out/(name+'.ll'), '-o', out/(name+'-O2.ll')], output='')
			run(['opt', '-passes=verify', '-disable-output', out/(name+'-O2.ll')], output='')
			run(['llc', '-O2', '-filetype=obj', '-relocation-model=pic', out/(name+'-O2.ll'), '-o', out/(name+'-O2.o')], output='')
			run(['cc', out/(name+'-O2.o'), *([companion] if owned else []), '-o', out/(name+'-O2')], output='')
			run([out/(name+'-O2')], status, output)
			results['runs'].append(dict(name=name+'-O2', status=status, output=output, optimized=True))

	for fixture in FIXTURES:
		execute(fixture, (ROOT/f'tests/slice-bound/fixtures/slice-bound-{fixture}.astra').read_text(), status=46 if fixture == 'sum' else 0, owned=fixture.startswith('owned'), optimize=True)
	execute('empty-parameter', 'int observe(borrowed int[] s){if(len(s)==0){return 17;}return s[0];}int main(){int[4] a={1,2,3,4};if(observe(slice(a,0,0))!=17 || observe(slice(a,4,0))!=17 || observe(slice(a))!=1){return 1;}return 0;}', optimize=True)
	source, shapes = matrix()
	execute('matrix', source, optimize=True)
	results['shapes'] = shapes
	results['exact_boundary_calls'] = len(shapes) * 8
	execute('f32-special', 'void copy(borrowed f32[] dst,borrowed f32[] src){int i=0;while(i<len(src)){dst[i]=src[i];i=i+1;}}int main(){f32 nan=0.0/0.0;f32[4] a={-0.0,nan,1.401298464324817e-45,3.4028234663852886e38};f32[4] b={1.0,1.0,1.0,1.0};copy(slice(b),slice(a));if(1.0/b[0]>=0.0 || b[1]==b[1] || b[2]!=a[2] || b[3]!=a[3]){return 1;}return 0;}', optimize=True)
	for type_name, (bits, signed) in INTEGERS.items():
		for i in ([-1, 4, 2**(bits-1)-1] if signed else [4, 2**bits-1]):
			for operation in ['read', 'write']:
				body = 'int x=s[i];' if operation == 'read' else 's[i]=42;'
				execute(f'trap-{type_name}-{i}-{operation}', f'void access(borrowed int[] s,{type_name} i){{{body}}}int main(){{int[4] a={{1,2,3,4}};access(slice(a),{i});return 0;}}', -signal.SIGILL)
		for start in [0, 4]:
			execute(f'empty-{type_name}-{start}', f'void access(borrowed int[] s,{type_name} i){{s[i]=42;}}int main(){{int[4] a={{1,2,3,4}};access(slice(a,{start},0),0);return 0;}}', -signal.SIGILL, optimize=type_name == 'u32')
			# A constant callee index must use the length of this call's view.
	execute('constant-index', 'int read(borrowed int[] s){return s[2];}int main(){int[4] a={1,2,3,4};int x=read(slice(a));return read(slice(a,0,1));}', -signal.SIGILL, optimize=True)
	execute('vector-bounds', 'void access(borrowed i16<8>[] s,u32 i){s[i]=splat(1,8);}int main(){i16<8> v=splat(0,8);i16<8>[1] a={v};access(slice(a),4294967295);return 0;}', -signal.SIGILL)
	recorder = 'extern(C) int putchar(int c);extern(C) int fflush(void* p);int record(int c,int value){putchar(c);fflush(null);return value;}'
	for start, count, status, output, name in [(0,2,0,'SCLF','valid'),(-1,2,-signal.SIGILL,'SC','start'),(1,4,-signal.SIGILL,'SC','count')]:
		source = recorder+f'void consume(borrowed int[] s,int later){{record(70,0);}}int main(){{int[4] a={{1,2,3,4}};consume(slice(a,record(83,{start}),record(67,{count})),record(76,0));return 0;}}'
		execute('order-'+name, source, status, output, optimize=True)
	for first, second, output in [(0,0,'ABCDLF'),(-1,0,'AB'),(0,-1,'ABCD')]:
		source = recorder+f'void consume(borrowed int[] a,borrowed int[] b,int later){{record(70,0);}}int main(){{int[4] a={{1,2,3,4}};consume(slice(a,record(65,{first}),record(66,2)),slice(a,record(67,{second}),record(68,2)),record(76,0));return 0;}}'
		execute(f'order-multiple-{first}-{second}', source, 0 if first == second == 0 else -signal.SIGILL, output)
	for before in [True, False]:
		parameters = 'owned Resource r,borrowed int[] s,int later' if before else 'borrowed int[] s,owned Resource r,int later'
		arguments = 'move r,slice(a,record(83,-1),record(67,2)),record(76,0)' if before else 'slice(a,record(83,-1),record(67,2)),move r,record(76,0)'
		source = recorder+f'extern(C) void astra_test_resource_forbid_cleanup();void consume({parameters}){{record(70,0);}}int main(){{resource_reset();owned Resource r=create_resource(4);astra_test_resource_forbid_cleanup();int[4] a={{1,2,3,4}};consume({arguments});return 0;}}'
		execute('order-owned-'+str(before).lower(), source, -signal.SIGILL, 'SC', owned=True, optimize=True)
	execute('callee-store-order', recorder+'void write(borrowed int[] s,int i){s[record(73,i)]=record(82,42);}int main(){int[1] a={1};write(slice(a),1);return 0;}', -signal.SIGILL, 'I', optimize=True)
	execute('capture-range', 'int change(int* start,int* count){*start=3;*count=0;return 0;}int access(borrowed int[] s,int later){return len(s)*10+s[0];}int main(){int[4] a={1,2,3,4};int start=1;int count=2;if(access(slice(a,start,count),change(&start,&count))!=22 || start!=3 || count!=0){return 1;}return 0;}', optimize=True)
	results['runs'].extend(machine(out, companion))
	(out/'results.json').write_text(json.dumps(results, indent='\t')+'\n')
	print(json.dumps(results), flush=True)


if __name__ == '__main__':
	main(*(Path(arg).resolve() for arg in sys.argv[1:]))
