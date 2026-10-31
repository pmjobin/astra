# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""GEN-1 native/O0/O2, exact floating transport, deterministic identity and machine evidence."""
from pathlib import Path
import json
import os
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT/'tests/gen/fixtures'
CASES = {name: (42, '') for name in ['identity', 'multi', 'choose', 'loop', 'chain', 'recursive', 'mutual', 'cross', 'dedup', 'f64', 'vector', 'property', 'concrete']}
CASES.update({'owned': (42, 'VRVS'), 'object-owned': (42, 'AB')})
FLAGS = r'\b(?:reassoc|nnan|ninf|nsz|arcp|contract|afn|fast)\b|llvm\.(?:fma|fmuladd)|unsafe-fp|no-nans|no-infs|no-signed-zeros'


def run(argv, status=0, output=None):
	p = subprocess.run(list(map(str, argv)), cwd=ROOT, capture_output=True, text=True, env=dict(os.environ, CCACHE_DISABLE='1'))
	assert p.returncode == status and not p.stderr and (output is None or p.stdout == output), (argv, p)
	return p.stdout


def value_matrix():
	lines = ['T identity<T>(T value){return value;}', 'int main(){']
	shapes = []
	for element, bits in [('bool',1), ('i8',8), ('u8',8), ('i16',16), ('u16',16), ('int',32), ('u32',32), ('f32',32), ('f64',64)]:
		for lanes in [0,2,4,8,16]:
			if lanes and (element == 'f64' or bits*lanes > 128):
				continue
			name = f'{element}<{lanes}>' if lanes else element
			index = len(shapes); shapes.append(name)
			values = ['false','true'] if element == 'bool' else ['-0.0','4.9406564584124654e-324'] if element == 'f64' else ['-0.0','1.401298464324817e-45'] if element == 'f32' else ['0',str(2**bits-1)] if element.startswith('u') else [str(-2**(bits-1)),str(2**(bits-1)-1)]
			for sample in range(2):
				initializer = '{'+','.join(values[(i+sample)%2] for i in range(lanes))+'}' if lanes else values[sample]
				variable = f'x{index}_{sample}'
				lines += [f'\t{name} {variable}={initializer};', f'\t{name} y{index}_{sample}=identity<{name}>({variable});']
				comparison = f'{variable}==y{index}_{sample}'
				lines.append('\tif (!('+(f'all({comparison})' if lanes else comparison)+')) { return 1; }')
	lines += ['\tvoid* p=null; void* q=identity<void*>(p); if(q!=p){return 1;}', '\treturn 42;', '}']
	return '\n'.join(lines)+'\n', shapes+['void*']


def inventory(text):
	rows = []
	for match in re.finditer(r'\(generic-instance #(\d+) \(origin #(\d+) "([^"]+)"\) \(type-arguments (.*?)\) \(requests (\d+)\) \(callers(.*?)\)\)', text):
		ordinal, definition, name, arguments, requests, callers = match.groups()
		rows.append(dict(ordinal=int(ordinal), definition=int(definition), name=name, arguments=arguments.split(), requests=int(requests), callers=re.findall(r'"([^"]+)"', callers)))
	assert len({(row['definition'], tuple(row['arguments'])) for row in rows}) == len(rows)
	return rows


def main(compiler, out):
	out.mkdir(parents=True, exist_ok=True)
	companion = out/'companion.o'; run(['cc','-c',ROOT/'tests/obj-life/companion.c','-o',companion])
	records = dict(runs=[],machine=[],inventories={},floating_patterns={},deterministic=[])
	matrix, records['value_shapes'] = value_matrix(); (out/'matrix.astra').write_text(matrix)

	def compile_ir(stem, ir, status=42, output='', optimize=False, fma=False, isolate_calls=False):
		extra_objects = []
		if isolate_calls:
			ir, main = ir.rsplit('\ndefine i32 @main() {',1)
			declarations = '\n'.join('declare fastcc '+signature for signature in re.findall(r'^define fastcc ([^\n]+) noinline \{$',ir,re.M))
			caller_input = out/(stem+'-caller-input.ll'); caller_input.write_text(declarations+'\ndefine i32 @main() {'+main)
			caller_ir = out/(stem+'-caller.ll'); caller_object = out/(stem+'-caller.o')
			run(['opt','-passes=default<O2>' if optimize else '-passes=verify','-S',caller_input,'-o',caller_ir])
			assert re.search(r'call fastcc .* @astra\.fn\.1\(',caller_ir.read_text()) and not re.search(FLAGS,caller_ir.read_text())
			run(['llc','-O2' if optimize else '-O0','-filetype=obj','-relocation-model=pic',caller_ir,'-o',caller_object])
			extra_objects.append(caller_object)
		input_path = out/(stem+'-input.ll'); input_path.write_text(ir)
		path = out/(stem+'.ll'); obj = out/(stem+'.o')
		run(['opt','-passes=default<O2>' if optimize else '-passes=verify','-S',input_path,'-o',path])
		run(['opt','-passes=verify','-disable-output',path])
		assert not re.search(FLAGS,path.read_text()), stem
		run(['llc','-O2' if optimize else '-O0','-filetype=obj','-relocation-model=pic',*(['-mattr=+fma'] if fma else []),path,'-o',obj])
		run(['cc',obj,*extra_objects,companion,'-o',out/stem]); run([out/stem],status,output)
		machine = run(['objdump','-dr',obj,*extra_objects]); (out/(stem+'.machine')).write_text(machine)
		if isolate_calls: assert re.search(r'R_X86_64_PLT32\s+astra\.fn\.1',machine), stem
		assert not re.search(r'\bv?f(?:n?madd|n?msub)\w*\b',machine), stem
		(out/(stem+'.symbols')).write_text(run(['readelf','-h','-Ws',obj]))
		records['runs'].append(dict(name=stem,status=status,output=output))

	for name,(status,output) in dict(CASES,matrix=(42,'')).items():
		source = out/'matrix.astra' if name=='matrix' else FIXTURES/f'gen-{name}.astra'
		options = ['--vapi',ROOT/'tests/obj-life/fixtures/lifecycle.vapi'] if name=='owned' else []
		run([compiler,source,*options,'--link-object',companion,'-o',out/name],output=''); run([out/name],status,output)
		records['runs'].append(dict(name=name,status=status,output=output))
		stages = {stage:run([compiler,'--dump-'+stage,source,*([] if stage=='syntax' else options)]) for stage in ['syntax','semantics','core','instances','cfg','ssa','nabi','llvm']}
		for stage,text in stages.items():
			(out/(name+'.'+stage)).write_text(text)
			if stage in ['semantics','core','instances','llvm']:
				assert text == run([compiler,'--dump-'+stage,source,*options]), (name,stage)
				records['deterministic'].append(name+':'+stage)
		rows = inventory(stages['instances']); records['inventories'][name] = rows
		ir = stages['llvm']; assert not re.search(FLAGS,ir)
		assert not re.search(r'type.descriptor|dictionary|witness|boxing|generic.dispatch|typeid|malloc',ir)
		assert not re.search(r'(?:generic-call|type-parameter|GEN1_PLAIN_COPY)', '\n'.join(stages[stage] for stage in ['cfg','ssa','nabi','llvm']))
		if name=='dedup':
			assert len(rows)==10 and sum(row['name']=='identity' for row in rows)==8 and sum(row['name']=='tag' for row in rows)==2
			assert sum(row['arguments']==['int'] for row in rows)==1
			assert all(row['name']!='unused' for row in rows)
			assert len(re.findall(r'^define internal fastcc i8 @astra\.fn\.\d+\(i8 %p0\)',ir,re.M))==2
		if name=='matrix': assert len(rows)==len(records['value_shapes'])
		if name=='cross': assert len(rows)==2 and rows[1]['requests']>=2
		main_id = re.search(r'\(function #(\d+) "main" -> int',stages['ssa'])[1]
		wrapped = ir+'\ndefine i32 @main() {\n\t%r = call fastcc i32 @astra.fn.'+main_id+'()\n\tret i32 %r\n}\n'
		compile_ir(name+'-O0',wrapped,status,output)
		compile_ir(name+'-O2',wrapped,status,output,True)
		preserved = re.sub(r'^define internal fastcc ([^\n]+) \{$',r'define fastcc \1 noinline {',wrapped,flags=re.M)
		compile_ir(name+'-callable-O2',preserved,status,output,True,name=='f64')
		linkage = run(['ldd',out/name]); assert not re.search(r'libglib|libgobject|libLLVM',linkage)
		(out/(name+'.linkage')).write_text(linkage)
		records['machine'].append(dict(name=name,instances=len(rows),target='x86-64',linkage='internal fastcc',evidence=name+'-callable-O2.machine'))

	for typename,llvmtype,width,bits in [
		('f32','float',32,[0,1<<31,1,0x007fffff,0x00800000,0x3f800001,0x7f800000,0xff800000,0x7fc12345,0xffc56789]),
		('f64','double',64,[0,1<<63,1,(1<<63)|1,0x0010000000000000,0x3ff0000000000001,0x7fefffffffffffff,0x7ff0000000000000,0xfff0000000000000,0x7ff8123456789abc,0xfff8abcdef123456])]:
		source=out/(typename+'-transport.astra'); source.write_text('T identity<T>(T x){return x;}'+typename+' root('+typename+' x){return identity<'+typename+'>(x);}')
		ir=run([compiler,'--dump-llvm',source]); ir=re.sub(r'^define internal fastcc ([^\n]+) \{$',r'define fastcc \1 noinline {',ir,flags=re.M)
		lines=[ir,'define i32 @main() {']
		for i,pattern in enumerate(bits):
			lines += [f'\t%r{i} = call fastcc {llvmtype} @astra.fn.1({llvmtype} bitcast (i{width} {pattern} to {llvmtype}))',f'\t%b{i} = bitcast {llvmtype} %r{i} to i{width}',f'\t%c{i} = icmp eq i{width} %b{i}, {pattern}',f'\tbr i1 %c{i}, label %next{i}, label %bad',f'next{i}:']
		lines += ['\tret i32 42','bad:','\tret i32 1','}']; transport='\n'.join(lines)+'\n'
		compile_ir(typename+'-transport-O0',transport,isolate_calls=True)
		compile_ir(typename+'-transport-O2-fma',transport,optimize=True,fma=True,isolate_calls=True)
		records['floating_patterns'][typename]=[f'{value:0{width//4}x}' for value in bits]
		# Non-null opaque pointer and whole-vector bits cross real native calls.
	for name,typename,llvmtype,width,pattern in [
		('pointer','void*','ptr',0,0),
		('vector-f32','f32<4>','<4 x float>',128,0x000000017fc123457f80000080000000),
		('vector-i16','i16<8>','<8 x i16>',128,0x8000ffff000012347fffabcd00010002)]:
		source=out/(name+'-transport.astra'); source.write_text('T identity<T>(T x){return x;}'+typename+' root('+typename+' x){return identity<'+typename+'>(x);}')
		ir=run([compiler,'--dump-llvm',source]); ir=re.sub(r'^define internal fastcc ([^\n]+) \{$',r'define fastcc \1 noinline {',ir,flags=re.M)
		if name=='pointer':
			body='\t%p = alloca i32\n\t%r = call fastcc ptr @astra.fn.1(ptr %p)\n\t%ok = icmp eq ptr %r, %p\n'
		else:
			body=f'\t%r = call fastcc {llvmtype} @astra.fn.1({llvmtype} bitcast (i{width} {pattern} to {llvmtype}))\n\t%bits = bitcast {llvmtype} %r to i{width}\n\t%ok = icmp eq i{width} %bits, {pattern}\n'
		ir+='\ndefine i32 @main() {\n'+body+'\t%status = select i1 %ok, i32 42, i32 1\n\tret i32 %status\n}\n'
		compile_ir(name+'-transport-O0',ir,isolate_calls=True)
		compile_ir(name+'-transport-O2',ir,optimize=True,isolate_calls=True)
	f64_machine=(out/'f64-callable-O2.machine').read_text()
	assert 'mulsd' in f64_machine and 'addsd' in f64_machine
	(out/'results.json').write_text(json.dumps(records,indent='\t')+'\n')
	print(f"{len(records['runs'])} executions; {len(records['value_shapes'])} value shapes; {sum(map(len, records['floating_patterns'].values()))} exact floating patterns; {len(records['deterministic'])} deterministic comparisons")


if __name__=='__main__':
	main(Path(sys.argv[1]).resolve(),Path(sys.argv[2]).resolve())
