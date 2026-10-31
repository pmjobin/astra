# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Native struct boundary execution, exact leaf transport and machine evidence."""
from pathlib import Path
import json
import os
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'tests/struct-abi/fixtures'
CASES = ['basic','identity','result','order','nested','vector','f32','f64','branch','forward','generic','single','cad','method','mixed','pointer','deep','many','null-source','null-destination']
STAGES = ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
FLAGS = r'\b(?:reassoc|nnan|ninf|nsz|arcp|contract|afn|fast)\b|llvm\.(?:fma|fmuladd)|unsafe-fp|no-nans|no-infs|no-signed-zeros'


def run(argv, trap=False):
	r = subprocess.run(list(map(str, argv)), cwd=ROOT, capture_output=True, text=True, env=dict(os.environ, CCACHE_DISABLE='1'))
	assert (r.returncode < 0 if trap else r.returncode == 0) and r.stderr == '', (argv, r)
	return r.stdout


def matrix():
	fields, initializers, checks, shapes = [], [], [], []
	for element, width in [('i8',8),('u8',8),('i16',16),('u16',16),('int',32),('u32',32),('f32',32),('bool',1)]:
		for lanes in [2,4,8,16]:
			if element == 'f32' and lanes > 4 or element not in ['bool','f32'] and width * lanes > 128:
				continue
			shape, name = f'{element}<{lanes}>', f'v{len(shapes)}'
			zero, one = ('false','true') if element == 'bool' else ('0.0','1.0') if element == 'f32' else ('0','1')
			shapes.append(shape); fields.append(f'\t{shape} {name};'); initializers.append(f'{name}=splat({one},{lanes})')
			checks.append(f'\tok=ok & all(b.leaf.{name}==a.leaf.{name}) & all(c.leaf.{name}==a.leaf.{name});')
			checks += [f'\tb.leaf.{name}=insert(b.leaf.{name},{lanes-1},{zero});',f'\tok=ok & (a.leaf.{name}[{lanes-1}]=={one}) & (b.leaf.{name}[{lanes-1}]=={zero});']
	decl='struct S{\n'+'\n'.join(fields)+'\n}\nstruct O{S leaf;}\n'
	body='\tO a={leaf={'+','.join(initializers)+'}};\n\tO b=forward(a);O c=identity(b);b=identity(a);\n'
	return decl+'O identity(O value){return value;}\nO forward(O value){return identity(value);}\nint main(){\n\tbool ok=true;\n'+body+'\n'.join(checks)+'\n\tif(!ok){return 1;}\n\treturn 0;\n}\n', shapes


def deep(depth):
	decls=['struct Leaf{int x;f64 y;}']
	for i in range(depth):
		decls.append(f'struct S{i}{{'+('Leaf' if i==0 else f'S{i-1}')+' child;}')
	initializer='{x=42,y=3.5}'
	for _ in range(depth):
		initializer='{child='+initializer+'}'
	path='child.'*depth
	return '\n'.join(decls)+f'\nS{depth-1} identity(S{depth-1} value){{return value;}}\nint main(){{S{depth-1} a={initializer};S{depth-1} b=identity(a);if(b.{path}x!=42 || b.{path}y!=3.5){{return 1;}}return 0;}}\n'


def main(compiler, out):
	out.mkdir(parents=True, exist_ok=True)
	records=dict(runs=[],shapes=[],deterministic=[],machine=[],bit_patterns={},carrier_audits=[])
	source,records['shapes']=matrix(); assert len(records['shapes'])==24
	(out/'matrix.astra').write_text(source); (out/'deep-64.astra').write_text(deep(64))

	def execute(name, ir, optimized=False, fma=False, trap=False):
		input_path=out/(name+'-input.ll'); input_path.write_text(ir)
		path,obj,binary=out/(name+'.ll'),out/(name+'.o'),out/name
		run(['opt','-passes=default<O2>' if optimized else '-passes=verify','-S',input_path,'-o',path]); run(['opt','-passes=verify','-disable-output',path])
		assert not re.search(FLAGS,path.read_text()),name
		run(['llc','-O2' if optimized else '-O0','-filetype=obj','-relocation-model=pic',*(['-mattr=+fma'] if fma else []),path,'-o',obj]); run(['cc',obj,'-o',binary]); run([binary],trap)
		machine=run(['objdump','-dr',obj]); (out/(name+'.machine')).write_text(machine); (out/(name+'.symbols')).write_text(run(['readelf','-Ws',obj]))
		assert not re.search(r'\bv?f(?:n?madd|n?msub)\w*\b',machine),name
		records['runs'].append(name); records['machine'].append(name)

	for name in [*CASES,'matrix','deep-64']:
		source=out/(name+'.astra') if name in ['matrix','deep-64'] else FIXTURES/('struct-abi-'+name+'.astra')
		trap=name.startswith('null-')
		binary=out/(name+'-native'); run([compiler,source,'-o',binary]); run([binary],trap); records['runs'].append(name+'-native')
		stages={stage:run([compiler,'--dump-'+stage,source]) for stage in STAGES}
		for stage,text in stages.items():
			(out/(name+'.'+stage)).write_text(text); assert text==run([compiler,'--dump-'+stage,source]),(name,stage); records['deterministic'].append(name+':'+stage)
		ir=stages['llvm']; assert not re.search(FLAGS,ir) and not re.search(r'@(?:llvm\.mem(?:cpy|move)|malloc|calloc|realloc)|typeinfo|descriptor|\bsret\b|\bbyval\b',ir)
		assert '(native-abi aggregate-v7' in stages['nabi']
		if name not in ['method','mixed','result','order','pointer','null-source','null-destination']:
			assert 'alloca' not in ir and 'getelementptr' not in ir,name
		if name in ['identity','nested','single','f64','vector','generic','forward','branch','matrix','deep-64','many']:
			first=re.search(r'define internal fastcc [^\n]+\n.*?\n}',ir,re.S)[0]
			assert 'ptr ' not in first and 'alloca' not in first and not re.search(r'\b(?:load|store|extractelement|insertelement)\b',first),first
			records['carrier_audits'].append(dict(name=name,signature=first.splitlines()[0],insertvalue=first.count('insertvalue'),extractvalue=first.count('extractvalue')))
		if name in ['f32','f64']:
			assert not re.search(r'\bf(?:add|sub|mul|div|ptrunc|pext)\b',ir)
		main_id=re.search(r'\(function #(\d+) "main" -> int',stages['ssa'])[1]
		wrapped=ir+'\ndefine i32 @main(){\n\t%r=call fastcc i32 @astra.fn.'+main_id+'()\n\tret i32 %r\n}\n'
		execute(name+'-O0',wrapped,trap=trap); execute(name+'-O2',wrapped,True,trap=trap)
		preserved=re.sub(r'^define internal fastcc ([^\n]+) \{$',r'define fastcc \1 noinline {',wrapped,flags=re.M)
		execute(name+'-callable-O2-fma',preserved,True,True,trap)
		assert not re.search(r'libglib|libgobject|libLLVM',run(['ldd',binary]))

	for typename,lltype,width,patterns in [('f64','double',64,[0,0x8000000000000000,1,0xfffffffffffff,0x10000000000000,0x3ff0000000000001,0x7ff0000000000000,0xfff0000000000000,0x7ff8000000001234]),('f32','float',32,[0,0x80000000,1,0x7fffff,0x800000,0x3f800001,0x7f800000,0xff800000,0x7fc01234])]:
		source=out/(typename+'-bits.astra')
		source.write_text(f'struct One{{{typename} value;}}struct Triple{{One inner;{typename} second;{typename} third;}}\nOne single(One value){{return value;}}\nTriple multiple(Triple value){{return value;}}\nTriple forward(Triple value){{return multiple(value);}}\nTriple addressed(Triple value){{Triple local=value;Triple* p=&local;return *p;}}\n')
		ir=run([compiler,'--dump-llvm',source]); assert not re.search(r'\bf(?:add|sub|mul|div|ptrunc|pext)\b',ir)
		ir=re.sub(r'^define internal fastcc ([^\n]+) \{$',r'define fastcc \1 noinline {',ir,flags=re.M)
		lines=[ir,'define i32 @main(){']; ordinal=0
		for function in [0,1,2,3]:
			for index,bits in enumerate(patterns):
				i=ordinal; ordinal+=1; leaf_bits=[bits,patterns[(index+1)%len(patterns)],patterns[(index+2)%len(patterns)]]
				carrier=lltype if function==0 else '{ '+', '.join([lltype]*3)+' }'
				arguments=leaf_bits[:1] if function==0 else leaf_bits
				args=', '.join(f'{lltype} bitcast(i{width} {value} to {lltype})' for value in arguments)
				lines.append(f'\t%r{i}=call fastcc {carrier} @astra.fn.{function}({args})')
				for leaf,value in enumerate(arguments):
					name=f'{i}_{leaf}'
					if function!=0:
						lines.append(f'\t%leaf{name}=extractvalue {carrier} %r{i},{leaf}')
					operand=f'%r{i}' if function==0 else f'%leaf{name}'
					lines += [f'\t%b{name}=bitcast {lltype} {operand} to i{width}',f'\t%ok{name}=icmp eq i{width} %b{name},{value}',f'\tbr i1 %ok{name},label %next{name},label %bad',f'next{name}:']
		lines += ['\tret i32 0','bad:','\tret i32 1','}']; records['bit_patterns'][typename]=[hex(x) for x in patterns]
		for optimized in [False,True]:
			execute(typename+'-bits-'+('O2-fma' if optimized else 'O0'),'\n'.join(lines)+'\n',optimized,True)

	source=out/'pointer-bits.astra'; source.write_text('struct P{void* value;int tag;}P identity(P value){return value;}P forward(P value){return identity(value);}\n')
	ir=run([compiler,'--dump-llvm',source]); ir=re.sub(r'^define internal fastcc ([^\n]+) \{$',r'define fastcc \1 noinline {',ir,flags=re.M)
	wrapped=ir+'''\n@token=global i8 7
define i32 @main(){
	%r=call fastcc {ptr,i32} @astra.fn.1(ptr @token,i32 42)
	%p=extractvalue {ptr,i32} %r,0
	%tag=extractvalue {ptr,i32} %r,1
	%a=icmp eq ptr %p,@token
	%b=icmp eq i32 %tag,42
	%ok=and i1 %a,%b
	%result=select i1 %ok,i32 0,i32 1
	ret i32 %result
}
'''
	for optimized in [False,True]:
		execute('pointer-bits-'+('O2-fma' if optimized else 'O0'),wrapped,optimized,True)
	records['exact_float_comparisons']=360
	(out/'results.json').write_text(json.dumps(records,indent='\t')+'\n')
	print(f"{len(records['runs'])} executions; {len(records['shapes'])} vector shapes; {len(records['deterministic'])} deterministic comparisons; exact F32/F64/PTR native transport")


if __name__=='__main__':
	main(Path(sys.argv[1]).resolve(),Path(sys.argv[2]).resolve())
