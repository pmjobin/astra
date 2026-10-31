# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""OBJ-1 execution, identity, alias, trap-order, O2 and machine qualification."""
from pathlib import Path
import importlib.util
import json
import re
import signal
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ['basic', 'alias', 'identity', 'null', 'method', 'branch', 'branch-null', 'loop', 'lifetime', 'empty', 'nominal', 'construction-order', 'nested-construction', 'integration', 'slice', 'owned', 'order', 'fields']


def run(argv, status=0, output=None):
	result = subprocess.run(list(map(str, argv)), cwd=ROOT, capture_output=True, text=True)
	assert result.returncode == status and not result.stderr and (output is None or result.stdout == output), (argv, result)
	return result.stdout


def main(compiler, companion, out):
	out.mkdir(parents=True, exist_ok=True)
	bindings = [arg for name in ['types', 'api'] for arg in ['--vapi', ROOT/f'tests/resource/fixtures/resource-{name}.vapi']]
	records = {'runs': [], 'machine': [], 'shapes': []}

	def execute(name, source, status=42, output='', owned=False, machine=False):
		path = out/(name+'.astra')
		path.write_text(source+'\n')
		options = bindings if owned else []
		link = [companion] if owned else []
		run([compiler, path, *options, *(['--link-object', companion] if owned else []), '-o', out/name], output='')
		run([out/name], status, output)
		records['runs'].append(dict(name=name, status=status, output=output))
		ssa = run([compiler, '--dump-ssa', path, *options])
		llvm = run([compiler, '--dump-llvm', path, *options])
		(out/(name+'.ssa')).write_text(ssa)
		for pattern in [r'\bnoalias\b', r'vtable|vptr|typeinfo|object\.descriptor|refcount|gc\.header', r'llvm\.memcpy|llvm\.memmove']:
			assert not re.search(pattern, llvm), (name, pattern)
		assert not re.search(r'call (?:fastcc )?[^@\n]*@(malloc|calloc|realloc|free)\(', llvm), name
		assert llvm.count('alloca %astra.class.') == ssa.count('(object-storage #'), name
		methods = re.findall(r'^define internal fastcc ([^\n]+) @(astra\.class\.method\.\d+\.\d+)\(([^\n]*)\) \{\n(.*?)^}', llvm, re.M | re.S)
		for result, symbol, parameters, body in methods:
			assert parameters.startswith('ptr %this'), (name, symbol)
			assert not re.search(r'icmp (?:eq|ne) ptr %this, null', body), (name, symbol)
			assert not re.search(r'call (?:fastcc )?[^\n]* %\w+\(', body), (name, symbol)
		if name in {'identity', 'empty'}:
			assert re.search(r'icmp (?:eq|ne) ptr %object0, %object1', llvm), name
		if name == 'empty':
			assert '%astra.class.0 = type { i8 }' in llvm and '%astra.class.1 = type { i8 }' in llvm
		if name == 'fields':
			assert '%astra.class.0 = type { i8, i8, i16, i16, i32, i32, float, i1, ptr }' in llvm
		if name == 'basic':
			assert llvm.count('alloca %astra.class.') == 1
		main_id = re.search(r'\(function #(\d+) "main" -> int', ssa)[1]
		llvm += '\ndefine i32 @main() {\n\t%result = call fastcc i32 @astra.fn.'+main_id+'()\n\tret i32 %result\n}\n'
		(out/(name+'.ll')).write_text(llvm)
		for mode in ['O2', *(['callable-O2'] if machine and methods else [])]:
			stem = name+'-'+mode
			input_ir = llvm
			if mode == 'callable-O2':
				input_ir = re.sub(r'^define internal fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', llvm, flags=re.M)
			(out/(stem+'-input.ll')).write_text(input_ir)
			run(['opt', '-passes=default<O2>', '-S', out/(stem+'-input.ll'), '-o', out/(stem+'.ll')], output='')
			run(['opt', '-passes=verify', '-disable-output', out/(stem+'.ll')], output='')
			run(['llc', '-O2', '-filetype=obj', '-relocation-model=pic', out/(stem+'.ll'), '-o', out/(stem+'.o')], output='')
			run(['cc', out/(stem+'.o'), *link, '-o', out/stem], output='')
			run([out/stem], status, output)
			records['runs'].append(dict(name=stem, status=status, output=output))
			if machine:
				(out/(stem+'.disassembly')).write_text(run(['objdump', '-dr', out/(stem+'.o')]))
		if machine:
			run(['llc', '-O0', '-filetype=obj', '-relocation-model=pic', out/(name+'.ll'), '-o', out/(name+'-O0.o')], output='')
			(out/(name+'-O0.disassembly')).write_text(run(['objdump', '-dr', out/(name+'-O0.o')]))
			(out/(name+'-O0.symbols')).write_text(run(['readelf', '-h', '-Ws', out/(name+'-O0.o')]))
			linkage = run(['ldd', out/name])
			assert not re.search(r'libglib|libgobject|libLLVM', linkage), name
			(out/(name+'.linkage')).write_text(linkage)
			records['machine'].append(dict(name=name, methods=len(methods), objects=ssa.count('(object-storage #'), receiver='first PTR', dispatch='direct fastcc'))

	for name in FIXTURES:
		execute(name, (ROOT/f'tests/object/fixtures/object-{name}.astra').read_text(), output='LGSF' if name == 'construction-order' else '', owned=name == 'owned', machine=name in {'basic', 'alias', 'identity', 'empty', 'method', 'nested-construction', 'integration', 'slice', 'owned'})
	spec = importlib.util.spec_from_file_location('method_matrix', ROOT/'tests/method/execute.py')
	matrix = importlib.util.module_from_spec(spec)
	spec.loader.exec_module(matrix)
	source, records['shapes'] = matrix.matrix()
	execute('matrix', source.replace('struct Samples', 'class Samples'))
	recorder = 'extern(C) int putchar(int c);extern(C) int fflush(void* p);int record(int c,int n){putchar(c);fflush(null);return n;}'
	counter = 'class C{int x;void consume(int a,int b){this.x=a+b;record(70,0);}int get(){return this.x;}}'
	for name, body in [
		('null-read', 'return c.x;'),
		('null-write', 'c.x=record(87,42);return 0;'),
		('null-method', 'c.consume(record(65,20),record(66,22));return 0;'),
	]:
		execute(name, recorder+counter+'int main(){C c=null;'+body+'}', -signal.SIGILL)
	execute('valid-method-order', recorder+counter+'int main(){C c={x=0};c.consume(record(65,20),record(66,22));return c.get();}', output='ABF')
	execute('valid-write-order', recorder+counter+'int main(){C c={x=0};c.x=record(87,42);return c.x;}', output='W')
	execute('null-branch-trap', counter+'int choose(bool b){C a={x=42};C ref=a;if(b){ref=null;}return ref.get();}int record(int a,int b){return b;}int main(){return choose(true);}', -signal.SIGILL)
	execute('null-loop-trap', counter+'int record(int a,int b){return b;}int main(){C a={x=42};C ref=a;int i=0;while(i<2){ref=null;i=i+1;}return ref.x;}', -signal.SIGILL)
	execute('construction-trap', recorder+'class C{int a;int b;}int zero(){return 0;}int main(){C c={a=record(65,1)/zero(),b=record(66,2)};return c.a;}', -signal.SIGILL, 'A')
	owned_class = 'class C{int x;void consume(owned Resource r,int n,borrowed int[] a){record(70,0);this.x=resource_id(r)+n+a[0];}}'
	for name, receiver, start, output in [('owned-null', 'null', 0, ''), ('owned-valid', '{x=0}', 0, 'SLF'), ('owned-slice-trap', '{x=0}', -1, 'S')]:
		status = 42 if name == 'owned-valid' else -signal.SIGILL
		body = 'resource_reset();owned Resource r=create_resource(4);C c='+receiver+';int[2] a={36,0};'
		if status < 0:
			body += 'astra_test_resource_forbid_cleanup();'
		body += f'c.consume(move r,record(83,2),slice(a,record(76,{start}),1));'
		if name == 'owned-valid':
			body += 'if(resource_destroy_count()!=1||resource_live_count()!=0){return 1;}return c.x;'
		else:
			body += 'return 0;'
			# The bounds trap occurs after both source-written scalar effects.
		execute(name, recorder+'extern(C) void astra_test_resource_forbid_cleanup();'+owned_class+'int main(){'+body+'}', status, 'SL' if name == 'owned-slice-trap' else output, owned=True)
	execute('alias-captured-before-arguments', 'class C{int x;int update(int n){this.x=n;return n;}int add(int a,int b){this.x=this.x+a+b;return this.x;}}int main(){C a={x=1};C b=a;return a.add(b.update(20),b.update(11));}')
	(out/'results.json').write_text(json.dumps(records, indent='\t')+'\n')
	print(f"{len(records['runs'])} executions; {len(records['shapes'])} scalar/vector shapes; {len(records['machine'])} machine audits")


if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve(), Path(sys.argv[3]).resolve())
