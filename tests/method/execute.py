# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""METHOD-1 native execution and optimized alias/machine qualification."""
from pathlib import Path
import json
import re
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ['basic', 'mutate', 'alias', 'call', 'recursive', 'vector', 'slice', 'owned', 'order']


def run(argv, status=0, output=None):
	r = subprocess.run(list(map(str, argv)), cwd=ROOT, capture_output=True, text=True)
	assert r.returncode == status and not r.stderr and (output is None or r.stdout == output), (argv, r)
	return r.stdout


def matrix():
	methods = []
	checks = []
	shapes = []
	for element, bits in [('i8', 8), ('u8', 8), ('i16', 16), ('u16', 16), ('int', 32), ('u32', 32), ('f32', 32)]:
		for lanes in [0, 2, 4, 8, 16]:
			if lanes and bits * lanes > 128:
				continue
			type_name = f'{element}<{lanes}>' if lanes else element
			name = f'id_{element}_{lanes}'
			shapes.append(type_name)
			methods.append(f'\t{type_name} {name}({type_name} v) {{ this.calls = this.calls + 1; return v; }}')
			values = ['-0.0', '1.401298464324817e-45', '3.4028234663852886e38', '-123.25'] if element == 'f32' else [str(2**bits - 1), str(2**(bits-1)), '0', '1'] if element.startswith('u') else [str(-2**(bits-1)), str(2**(bits-1)-1), '-1', '0']
			for i, value in enumerate(values):
				value = f'splat({value},{lanes})' if lanes else value
				checks.append(f'\t{type_name} v_{name}_{i} = {value};')
				expression = f's.{name}(v_{name}_{i}) == v_{name}_{i}'
				checks.append('\tif (!(' + (f'all({expression})' if lanes else expression) + ')) { return 1; }')
	return '\n'.join(['struct Samples {', '\tint calls;', *methods, '}', 'int main() {', '\tSamples s = { calls = 0 };', *checks, f'\tif (s.calls != {len(shapes)*4}) {{ return 2; }}', '\treturn 42;', '}']), shapes


def main(compiler, companion, out):
	out.mkdir(parents=True, exist_ok=True)
	bindings = [arg for name in ['types', 'api'] for arg in ['--vapi', ROOT/f'tests/resource/fixtures/resource-{name}.vapi']]
	records = {'runs': [], 'machine': [], 'shapes': []}

	def execute(name, source, status=42, output='', owned=False, preserve=False):
		path = out/(name+'.astra')
		path.write_text(source+'\n')
		options = bindings if owned else []
		link = [companion] if owned else []
		run([compiler, path, *options, *(['--link-object', companion] if owned else []), '-o', out/name], output='')
		run([out/name], status, output)
		records['runs'].append(dict(name=name, status=status, output=output))
		llvm = run([compiler, '--dump-llvm', path, *options])
		ssa = run([compiler, '--dump-ssa', path, *options])
		(out/(name+'.ssa')).write_text(ssa)
		main_id = re.search(r'\(function #(\d+) "main" -> int', ssa)[1]
		llvm += '\ndefine i32 @main() {\n\t%result = call fastcc i32 @astra.fn.'+main_id+'()\n\tret i32 %result\n}\n'
		(out/(name+'.ll')).write_text(llvm)
		assert not re.search(r'(?<![\w.])(noalias|readonly|nonnull)(?![\w.])', llvm), name
		assert not re.search(r'vtable|vptr|typeinfo|method\.descriptor|llvm\.memcpy|llvm\.memmove', llvm), name
		methods = re.findall(r'^define internal fastcc ([^\n]+) @(astra\.method\.\d+\.\d+)\(([^\n]+)\) \{\n(.*?)^}', llvm, re.M | re.S)
		assert methods, name
		for result, symbol, parameters, body in methods:
			assert parameters.startswith('ptr %this') and not re.search(r'icmp (?:eq|ne) ptr %this, null', body), (name, symbol)
			# All fixture methods use only incoming receiver storage. Other method
			# locals remain eligible for ordinary addressable storage when needed.
			assert 'alloca' not in body, (name, symbol)
			assert not re.search(r'call (?:fastcc )?[^\n]* %\w+\(', body), (name, symbol)
		for mode in ['O2', *(['callable-O2'] if preserve else [])]:
			stem = name+'-'+mode
			input_ir = llvm
			if mode == 'callable-O2':
				# Test artifact only: preserve callable bodies with unknown inputs.
				input_ir = re.sub(r'^define internal fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', llvm, flags=re.M)
			(out/(stem+'-input.ll')).write_text(input_ir)
			run(['opt', '-passes=default<O2>', '-S', out/(stem+'-input.ll'), '-o', out/(stem+'.ll')], output='')
			run(['opt', '-passes=verify', '-disable-output', out/(stem+'.ll')], output='')
			run(['llc', '-O2', '-filetype=obj', '-relocation-model=pic', out/(stem+'.ll'), '-o', out/(stem+'.o')], output='')
			run(['cc', out/(stem+'.o'), *link, '-o', out/stem], output='')
			run([out/stem], status, output)
			records['runs'].append(dict(name=stem, status=status, output=output))
			if preserve:
				(out/(stem+'.disassembly')).write_text(run(['objdump', '-dr', out/(stem+'.o')]))
				(out/(stem+'.symbols')).write_text(run(['readelf', '-h', '-Ws', out/(stem+'.o')]))
			if mode == 'callable-O2':
				optimized = (out/(stem+'.ll')).read_text()
				assert all(re.search(r'^define [^\n]*@'+re.escape(symbol)+r'\(', optimized, re.M) for _, symbol, _, _ in methods)
				if name == 'alias':
					body = re.search(r'^define [^\n]*@astra\.method\.0\.0\([^\n]*\).*?\n(.*?)^}', optimized, re.M | re.S)[1]
					assert body.count('store i32') >= 3 and body.count('load i32') >= 2 and body.rfind('load i32') > body.rfind('store i32')
					disassembly = (out/(stem+'.disassembly')).read_text()
					assert re.search(r'R_\w+\s+astra\.method\.0\.0', disassembly)
					# Negative control demonstrates that this workload detects an
					# unsound receiver-uniqueness assumption at O2.
					unsound = input_ir.replace('@astra.method.0.0(ptr %this,', '@astra.method.0.0(ptr noalias %this,')
					(out/'alias-unsound.ll').write_text(unsound)
					run(['opt', '-passes=default<O2>', '-S', out/'alias-unsound.ll', '-o', out/'alias-unsound-O2.ll'], output='')
					run(['llc', '-O2', '-filetype=obj', '-relocation-model=pic', out/'alias-unsound-O2.ll', '-o', out/'alias-unsound.o'], output='')
					run(['cc', out/'alias-unsound.o', '-o', out/'alias-unsound'], output='')
					wrong = subprocess.run([str(out/'alias-unsound')], capture_output=True, text=True)
					assert wrong.returncode != 42 and not wrong.stdout and not wrong.stderr, wrong
					records['noalias_negative_control'] = wrong.returncode
		if preserve:
			run(['llc', '-O0', '-filetype=obj', '-relocation-model=pic', out/(name+'.ll'), '-o', out/(name+'-O0.o')], output='')
			symbols = run(['nm', '--defined-only', out/(name+'-O0.o')])
			assert all(re.search(r' t '+re.escape(symbol)+r'$', symbols, re.M) for _, symbol, _, _ in methods)
			(out/(name+'-O0.symbols')).write_text(symbols)
			(out/(name+'-O0.disassembly')).write_text(run(['objdump', '-dr', out/(name+'-O0.o')]))
			linkage = run(['ldd', out/name])
			assert not re.search(r'libglib|libgobject|libLLVM', linkage)
			(out/(name+'.linkage')).write_text(linkage)
			records['machine'].append(dict(name=name, methods=len(methods), linkage='internal fastcc', receiver='first PTR'))

	for name in FIXTURES:
		execute(name, (ROOT/f'tests/method/fixtures/method-{name}.astra').read_text(), owned=name == 'owned', preserve=True)
	source, records['shapes'] = matrix()
	execute('matrix', source)
	execute('f32-special', 'struct S{int x;f32 id(f32 v){return v;}f32 add(f32 a,f32 b){return a+b;}f32<4> vec(f32<4> v){return v;}}int main(){S s={x=0};f32 z=s.id(-0.0);f32 nan=s.id(0.0/0.0);f32 small=s.id(1.401298464324817e-45);f32 large=s.id(3.4028234663852886e38);if(1.0/z>=0.0 || nan==nan || small!=1.401298464324817e-45 || large!=3.4028234663852886e38 || s.add(16777216.0,1.0)!=16777216.0){return 1;}f32<4> v=s.vec(splat(-0.0,4));if(1.0/v[0]>=0.0){return 2;}return 42;}')
	recorder = 'extern(C) int putchar(int c);extern(C) int fflush(void* p);int record(int c,int value){putchar(c);fflush(null);return value;}'
	for start, count, status, output, name in [(0, 2, 42, 'SCLF', 'valid'), (-1, 2, -signal.SIGILL, 'SC', 'start'), (1, 4, -signal.SIGILL, 'SC', 'count')]:
		execute('slice-order-'+name, recorder+f'struct S{{int x;void consume(borrowed int[] s,int later){{this.x=s[0]+later;record(70,0);}}}}int main(){{S s={{x=0}};int[4] a={{1,2,3,4}};s.consume(slice(a,record(83,{start}),record(67,{count})),record(76,0));return 42;}}', status, output)
	for before in [True, False]:
		parameters = 'owned Resource r,borrowed int[] s,int n' if before else 'borrowed int[] s,owned Resource r,int n'
		arguments = 'move r,slice(a,record(83,-1),record(67,2)),record(76,0)' if before else 'slice(a,record(83,-1),record(67,2)),move r,record(76,0)'
		execute('owned-trap-'+str(before).lower(), recorder+f'extern(C) void astra_test_resource_forbid_cleanup();struct S{{int x;void consume({parameters}){{record(70,0);}}}}int main(){{resource_reset();owned Resource r=create_resource(4);astra_test_resource_forbid_cleanup();S s={{x=0}};int[4] a={{1,2,3,4}};s.consume({arguments});return 42;}}', -signal.SIGILL, 'SC', owned=True)
	execute('argument-trap', recorder+'struct S{int x;int f(int a,int b){record(70,0);return a+b;}}int zero(){return 0;}int main(){S s={x=0};return s.f(record(65,1)/zero(),record(66,2));}', -signal.SIGILL, 'A')
	execute('pointer-null', 'struct S{int x;int read(S* p){return this.x+p->x;}}int main(){S s={x=1};return s.read(null);}', -signal.SIGILL)
	execute('slice-mutate', 'struct S{int x;int f(borrowed int[] a,borrowed int[] b){a[0]=40;b[0]=b[0]+2;this.x=a[0];return this.x;}}int main(){S s={x=0};int[2] a={1,2};if(s.f(slice(a,0,1),slice(a,0,2))!=42 || a[0]!=42){return 1;}return s.x;}', preserve=True)
	(out/'results.json').write_text(json.dumps(records, indent='\t')+'\n')
	print(f"{len(records['runs'])} executions; {len(records['shapes'])} scalar/vector shapes; {len(records['machine'])} machine audits")


if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve(), Path(sys.argv[3]).resolve())
