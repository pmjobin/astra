# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Native generic aggregate qualification; physical results are evidence only."""
from pathlib import Path
import json
import os
import re
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'tests/gen-struct/fixtures'
CASES = ['basic', 'box-matrix', 'multi', 'phantom', 'dedup', 'generic-fn', 'cap', 'nested', 'pointer', 'f64', 'vector', 'members', 'scalarize', 'layout']
STAGES = ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
FLAGS = r'\b(?:reassoc|nnan|ninf|nsz|arcp|contract|afn|fast)\b|llvm\.(?:fma|fmuladd)|unsafe-fp|no-nans|no-infs|no-signed-zeros'


def run(argv, status=0):
	result = subprocess.run(list(map(str, argv)), cwd=ROOT, capture_output=True, text=True, env=dict(os.environ, CCACHE_DISABLE='1'))
	assert result.returncode == status and result.stderr == '', (argv, result)
	return result.stdout


def deep(depth):
	lines = ['struct Leaf<T>{T value;}']
	for i in range(depth):
		lines.append(f'struct S{i}<T>{{' + ('Leaf' if i == 0 else f'S{i-1}') + '<T> child;}')
	initializer = '{value=1.25}'
	for _ in range(depth):
		initializer = '{child=' + initializer + '}'
	projection = 'b.' + 'child.' * depth + 'value'
	lines += [f'int main(){{S{depth-1}<f64> b={initializer};{projection}=3.5;if({projection}!=3.5){{return 1;}}return 0;}}']
	return '\n'.join(lines) + '\n'


def main(compiler, out):
	out.mkdir(parents=True, exist_ok=True)
	records = dict(runs=[], deterministic=[], cycles=[], audits=[], definitions={}, inventory={}, function_inventory={}, dependencies={})
	(out/'deep-64.astra').write_text(deep(64))
	(out/'unused.astra').write_text('struct Box<T>{T value;}struct Bundle<T>{Box<T> inner;}int main(){return 0;}\n')
	(out/'null.astra').write_text('struct Pair<T,U>{T first;U second;}int read(Pair<int,f64>* p){return p->first;}int main(){Pair<int,f64>* p=null;return read(p);}\n')

	def execute(name, ir, optimize=False, fma=False, status=0):
		input_path = out/(name+'-input.ll'); input_path.write_text(ir)
		path, obj, binary = out/(name+'.ll'), out/(name+'.o'), out/name
		run(['opt', '-passes=default<O2>' if optimize else '-passes=verify', '-S', input_path, '-o', path])
		run(['opt', '-passes=verify', '-disable-output', path])
		assert not re.search(FLAGS, path.read_text()), name
		run(['llc', '-O2' if optimize else '-O0', '-filetype=obj', '-relocation-model=pic', *(['-mattr=+fma'] if fma else []), path, '-o', obj])
		run(['cc', obj, '-o', binary]); run([binary], status)
		machine = run(['objdump', '-dr', obj]); (out/(name+'.machine')).write_text(machine)
		assert not re.search(r'\bv?f(?:n?madd|n?msub)\w*\b', machine), name
		(out/(name+'.symbols')).write_text(run(['readelf', '-Ws', obj]))
		records['runs'].append(name)

	for name in [*CASES, 'deep-64', 'unused', 'null']:
		source = out/(name+'.astra') if name in ['deep-64', 'unused', 'null'] else FIXTURES/('gen-struct-'+name+'.astra')
		status = -signal.SIGILL if name == 'null' else 0
		binary = out/(name+'-native'); run([compiler, source, '-o', binary]); run([binary], status); records['runs'].append(name+'-native')
		stages = {stage: run([compiler, '--dump-'+stage, source]) for stage in STAGES}
		for stage, text in stages.items():
			(out/(name+'.'+stage)).write_text(text)
			assert text == run([compiler, '--dump-'+stage, source]), (name, stage)
			records['deterministic'].append(name+':'+stage)
		ir = stages['llvm']
		assert not re.search(FLAGS, ir) and not re.search(r'@(?:llvm\.(?:memcpy|memmove)|malloc|calloc|realloc)|typeinfo|descriptor|dictionary|witness', ir)
		assert 'generic-field-place' not in stages['instances']
		for stage in ['cfg', 'ssa', 'nabi', 'cabi', 'llvm']:
			assert not re.search(r'generic-(?:field|struct-instance|call)|\b(?:Box|Pair|Bundle|Tagged)<', stages[stage]), (name, stage)
		instances = re.findall(r'\(generic-struct-instance #(\d+) \(origin #(\d+) "([^"]+)"\) \(application (.*?)\) \(concrete-struct #(\d+)\) \(state COMPLETE\) \(requests (\d+)\)(.*?)\n\t\t\)', stages['instances'], re.S)
		records['inventory'][name] = [dict(ordinal=int(i), definition=int(d), name=n, application=a, core_struct=int(c), requests=int(r), requesters=re.findall(r'\(requester "([^"]+)"\)', sites)) for i,d,n,a,c,r,sites in instances]
		records['definitions'][name] = [dict(ordinal=int(i), name=n, parameters=re.findall(r'\(type-parameter #\d+ "([^"]+)"', body), fields=[dict(ordinal=int(f), name=label, type=t) for f,label,t in re.findall(r'\(generic-field #(\d+) "([^"]+)" : ([^\n]+)\)', body)]) for i,n,body in re.findall(r'\(generic-struct #(\d+) "([^"]+)"(.*?)\n\t\)', stages['core'], re.S)]
		records['function_inventory'][name] = [dict(ordinal=int(i), definition=int(d), name=n, arguments=a.split(), requests=int(r), callers=re.findall(r'"([^"]+)"', sites)) for i,d,n,a,r,sites in re.findall(r'\(generic-instance #(\d+) \(origin #(\d+) "([^"]+)"\) \(type-arguments ([^)]*)\) \(requests (\d+)\) \(callers ([^)]*)\)\)', stages['instances'])]
		records['dependencies'][name] = [dict(requester_struct=int(match[1]), requested_struct=row['ordinal']) for row in records['inventory'][name] for requester in row['requesters'] if (match := re.match(r'struct#(\d+):', requester))]
		if name == 'box-matrix':
			assert len(instances) == 34 and sum('<' in row['application'][4:-1] for row in records['inventory'][name]) == 24
		if name == 'unused':
			assert not instances and '(struct ' not in stages['instances'] and ' = type ' not in ir
		if name in ['basic', 'nested', 'generic-fn', 'cap', 'multi', 'phantom', 'dedup', 'scalarize', 'deep-64']:
			assert 'alloca' not in ir and 'getelementptr' not in ir
		if name == 'pointer':
			function = re.search(r'^define [^\n]* @astra.fn.2\(.*?^}', ir, re.M|re.S)[0]
			assert len(re.findall(r' = alloca ', function)) == 1
		if name == 'vector':
			assert 'load <8 x i16>' in ir and 'store <8 x i16>' in ir
		main_id = re.search(r'\(function #(\d+) "main" -> int', stages['ssa'])[1]
		wrapped = ir + '\ndefine i32 @main(){\n\t%r=call fastcc i32 @astra.fn.' + main_id + '()\n\tret i32 %r\n}\n'
		execute(name+'-O0', wrapped, status=status)
		execute(name+'-O2', wrapped, True, status=status)
		preserved = re.sub(r'^define internal fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', wrapped, flags=re.M)
		execute(name+'-callable-O2-fma', preserved, True, True, status)
		assert not re.search(r'libglib|libgobject|libLLVM', run(['ldd', binary]))
		records['audits'].append(name)

	for typename, lltype, width, patterns in [('f64', 'double', 64, [0, 0x8000000000000000, 1, 0xfffffffffffff, 0x10000000000000, 0x3ff0000000000001, 0x7ff0000000000000, 0x7ff8000000000042]), ('f32', 'float', 32, [0, 0x80000000, 1, 0x7fffff, 0x800000, 0x3f800001, 0x7f800000, 0x7fc00042])]:
		source = out/(typename+'-bits.astra')
		source.write_text(f'struct Box<T>{{T value;}}\n{typename} promoted({typename} x){{Box<{typename}> b={{value=x}};return b.value;}}\nvoid change(Box<{typename}>* b,{typename} x){{b->value=x;}}\n{typename} addressed({typename} x){{Box<{typename}> b={{value=0.0}};change(&b,x);return b.value;}}\n{typename} separate({typename} a,{typename} b,{typename} c){{Box<{typename}> x={{value=a}};Box<{typename}> y={{value=b}};return x.value*y.value+c;}}\n')
		ir = run([compiler, '--dump-llvm', source]); ssa = run([compiler, '--dump-ssa', source])
		ids = {name: ordinal for ordinal,name in re.findall(r'\(function #(\d+) "([^"]+)"', ssa)}
		ir = re.sub(r'^define internal fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', ir, flags=re.M)
		lines = [ir, 'define i32 @main(){']; ordinal = 0
		for name in ['promoted', 'addressed']:
			for bits in patterns:
				i = ordinal; ordinal += 1
				lines += [f'\t%r{i}=call fastcc {lltype} @astra.fn.{ids[name]}({lltype} bitcast(i{width} {bits} to {lltype}))', f'\t%b{i}=bitcast {lltype} %r{i} to i{width}', f'\t%ok{i}=icmp eq i{width} %b{i},{bits}', f'\tbr i1 %ok{i},label %next{i},label %bad', f'next{i}:']
		a,b,c = (0x3ff0000000000001, 0x3feffffffffffffe, 0xbff0000000000000) if width == 64 else (0x3f800001, 0x3f7ffffe, 0xbf800000)
		arguments = ','.join(f'{lltype} bitcast(i{width} {bits} to {lltype})' for bits in [a,b,c])
		lines += [f'\t%round=call fastcc {lltype} @astra.fn.{ids["separate"]}({arguments})', f'\t%bits=bitcast {lltype} %round to i{width}', f'\t%ok=icmp eq i{width} %bits,0', '\tbr i1 %ok,label %good,label %bad', 'good:', '\tret i32 0', 'bad:', '\tret i32 1', '}']
		for optimize in [False, True]:
			execute(typename+'-bits-'+('O2-fma' if optimize else 'O0'), '\n'.join(lines)+'\n', optimize, True)

			# Opaque pointer values include a nonnull static address, without allocation.
	source = out/'opaque.astra'
	source.write_text('struct Box<T>{T value;}T relay<T>(T v){Box<T> b={value=v};return b.value;}void write(Box<void*>* b,void* v){b->value=v;}void* addressed(void* v){Box<void*> b={value=null};write(&b,v);return b.value;}void* promoted(void* v){return relay<void*>(v);}\n')
	ir = run([compiler, '--dump-llvm', source]); ssa = run([compiler, '--dump-ssa', source])
	ids = {name: ordinal for ordinal,name in re.findall(r'\(function #(\d+) "([^"]+)"', ssa)}
	ir = re.sub(r'^define internal fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', ir, flags=re.M)
	lines = [ir, '@object = private global i8 0', 'define i32 @main(){']; ordinal = 0
	for name in ['promoted', 'addressed']:
		for value in ['null', '@object']:
			i = ordinal; ordinal += 1
			lines += [f'\t%r{i}=call fastcc ptr @astra.fn.{ids[name]}(ptr {value})', f'\t%ok{i}=icmp eq ptr %r{i},{value}', f'\tbr i1 %ok{i},label %next{i},label %bad', f'next{i}:']
	lines += ['\tret i32 0', 'bad:', '\tret i32 1', '}']
	for optimize in [False, True]:
		execute('opaque-'+('O2' if optimize else 'O0'), '\n'.join(lines)+'\n', optimize)

		# Ordered projections preserve IEEE unordered behavior and signed-zero choice.
	ir = (out/'cap.llvm').read_text(); ssa = (out/'cap.ssa').read_text()
	ordinal = re.search(r'\(function #(\d+) "astra.gen.0.2"', ssa)[1]
	ir = re.sub(r'^define internal fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', ir, flags=re.M)
	lines = [ir, 'define i32 @main(){']
	for i,(a,b,expected) in enumerate([(0,0x8000000000000000,0x8000000000000000), (0x8000000000000000,0,0), (0x7ff8000000000042,0x3ff0000000000000,0x3ff0000000000000), (0x3ff0000000000000,0x7ff8000000000042,0x7ff8000000000042), (1,2,1)]):
		lines += [f'\t%r{i}=call fastcc double @astra.fn.{ordinal}(double bitcast(i64 {a} to double),double bitcast(i64 {b} to double))', f'\t%b{i}=bitcast double %r{i} to i64', f'\t%ok{i}=icmp eq i64 %b{i},{expected}', f'\tbr i1 %ok{i},label %next{i},label %bad', f'next{i}:']
	lines += ['\tret i32 0', 'bad:', '\tret i32 1', '}']
	for optimize in [False, True]:
		execute('cap-ieee-'+('O2-fma' if optimize else 'O0'), '\n'.join(lines)+'\n', optimize, True)

	for name, definitions, demand, expected in [('direct', 'struct Node<T>{Node<T> next;}', 'Node<int>', 'Node<int> → Node<int>'), ('mutual', 'struct A<T>{B<T> b;}struct B<T>{A<T> a;}', 'A<int>', 'A<int> → B<int> → A<int>'), ('permuted', 'struct Flip<A,B>{Flip<B,A> next;}', 'Flip<int,f64>', 'Flip<int,f64> → Flip<f64,int> → Flip<int,f64>'), ('collapse', 'struct Freeze<T>{Freeze<int> next;}', 'Freeze<f64>', 'Freeze<f64> → Freeze<int> → Freeze<int>')]:
		source = out/('cycle-'+name+'.astra'); source.write_text(definitions+'void demand('+demand+'* p){}\n')
		for stage in ['syntax', 'semantics', 'core']:
			run([compiler, '--dump-'+stage, source])
		for stage in ['instances', 'cfg', 'ssa', 'nabi', 'llvm']:
			result = subprocess.run([compiler, '--dump-'+stage, source], capture_output=True, text=True)
			assert result.returncode == 1 and result.stdout == '' and 'recursive generic struct layout: '+expected in result.stderr, result
			(out/('cycle-'+name+'-'+stage+'.stderr')).write_text(result.stderr)
			records['cycles'].append(name+':'+stage)
	(out/'results.json').write_text(json.dumps(records, indent='\t')+'\n')
	print(f"{len(records['runs'])} executions; 34 Box types; 24 vector/mask shapes; {len(records['deterministic'])} deterministic comparisons; {len(records['cycles'])} cycle firewalls")


if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
