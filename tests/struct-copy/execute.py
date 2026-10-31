# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Whole-storage copy execution, snapshot ordering, exact bits and machine evidence."""
from pathlib import Path
import json
import os
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'tests/struct-copy/fixtures'
CASES = ['basic', 'assign', 'nested', 'deep', 'vector', 'f64', 'pointer', 'alias', 'generic', 'scalarize', 'mixed', 'method', 'void-pointer', 'null-source', 'null-destination']
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
			shapes.append(shape); fields.append(f'\t{shape} {name};'); initializers.append(f'{name}=splat({zero},{lanes})')
			checks += [f'\tb.leaf.{name}=insert(b.leaf.{name},{lanes-1},{one});',f'\tif(a.leaf.{name}[{lanes-1}]!={zero} || b.leaf.{name}[{lanes-1}]!={one} || c.leaf.{name}[0]!={zero}){{return 1;}}']
	decl = 'struct S{\n'+'\n'.join(fields)+'\n}\nstruct O{S leaf;}\n'
	body = '\tO a={leaf={'+','.join(initializers)+'}};\n\tO b=a;O c=b;b=a;\n'
	return decl+'void copy(O* d,O* s){*d=*s;}\nint promoted(){\n'+body+'\n'.join(checks)+'\n\treturn 0;\n}\nint main(){\n'+body+'\tcopy(&b,&a);c=b;\n'+'\n'.join(checks)+'\n\treturn promoted();\n}\n', shapes


def deep(depth):
	decls = ['struct Leaf{int x;}']
	for i in range(depth):
		decls.append(f'struct S{i}{{'+('Leaf' if i==0 else f'S{i-1}')+' child;}')
	initializer='{x=42}'
	for _ in range(depth):
		initializer='{child='+initializer+'}'
	path='child.'*depth+'x'
	return '\n'.join(decls)+f'\nint main(){{S{depth-1} a={initializer};S{depth-1} b=a;b=a;b.{path}=7;if(a.{path}!=42 || b.{path}!=7){{return 1;}}return 0;}}\n'


def main(compiler, out):
	out.mkdir(parents=True, exist_ok=True)
	records = dict(runs=[], shapes=[], deterministic=[], machine=[], bit_patterns={}, snapshot_audits=[])
	source, records['shapes'] = matrix(); assert len(records['shapes']) == 24
	(out/'matrix.astra').write_text(source); (out/'deep-64.astra').write_text(deep(64))
	companion=out/'companion.o'; run(['cc','-c',ROOT/'tests/struct-copy/companion.c','-o',companion])

	def execute(name, ir, optimized=False, fma=False, trap=False, objects=()):
		input_path=out/(name+'-input.ll'); input_path.write_text(ir)
		path,obj,binary=out/(name+'.ll'),out/(name+'.o'),out/name
		run(['opt','-passes=default<O2>' if optimized else '-passes=verify','-S',input_path,'-o',path]); run(['opt','-passes=verify','-disable-output',path])
		assert not re.search(FLAGS,path.read_text()), name
		run(['llc','-O2' if optimized else '-O0','-filetype=obj','-relocation-model=pic',*(['-mattr=+fma'] if fma else []),path,'-o',obj]); run(['cc',obj,*objects,'-o',binary]); run([binary],trap)
		machine=run(['objdump','-dr',obj]); (out/(name+'.machine')).write_text(machine); (out/(name+'.symbols')).write_text(run(['readelf','-Ws',obj]))
		assert not re.search(r'\bv?f(?:n?madd|n?msub)\w*\b',machine),name
		records['runs'].append(name); records['machine'].append(name)

	for name in [*CASES,'matrix','deep-64']:
		source=out/(name+'.astra') if name in ['matrix','deep-64'] else FIXTURES/('struct-copy-'+name+'.astra')
		trap=name.startswith('null-'); objects=[companion] if name=='void-pointer' else []
		binary=out/(name+'-native'); run([compiler,source,*(['--link-object',companion] if objects else []),'-o',binary]); run([binary],trap); records['runs'].append(name+'-native')
		stages={stage:run([compiler,'--dump-'+stage,source]) for stage in STAGES}
		for stage,text in stages.items():
			(out/(name+'.'+stage)).write_text(text); assert text==run([compiler,'--dump-'+stage,source]),(name,stage); records['deterministic'].append(name+':'+stage)
		ir=stages['llvm']; assert not re.search(FLAGS,ir) and not re.search(r'@(?:llvm\.mem(?:cpy|move)|malloc|calloc|realloc)|typeinfo|descriptor|noalias',ir)
		if name in ['basic','assign','nested','deep','scalarize','deep-64']:
			assert 'alloca' not in ir and 'getelementptr' not in ir
		if name=='mixed':
			assert len(re.findall(r' = alloca ',ir))==1
		if name in ['pointer','vector','f64','matrix']:
			copy_fn=re.search(r'define internal fastcc void @astra.fn.0\([^\n]+\).*?\n}',ir,re.S)[0]
			loads=[m.start() for m in re.finditer(r' = load ',copy_fn)]; stores=[m.start() for m in re.finditer(r'\bstore ',copy_fn)]
			assert loads and stores and max(loads)<min(stores),(name,copy_fn)
			assert copy_fn.index('icmp eq ptr %p0, null')<copy_fn.index('icmp eq ptr %p1, null')<min(loads)
			if name in ['vector','matrix']:
				assert 'extractelement' not in copy_fn and 'insertelement' not in copy_fn
			records['snapshot_audits'].append(dict(name=name,loads=len(loads),stores=len(stores)))
		if name=='f64':
			assert not re.search(r'\bf(?:add|sub|mul|div|ptrunc|pext)\b',ir)
		main_id=re.search(r'\(function #(\d+) "main" -> int',stages['ssa'])[1]
		wrapped=ir+'\ndefine i32 @main(){\n\t%r=call fastcc i32 @astra.fn.'+main_id+'()\n\tret i32 %r\n}\n'
		execute(name+'-O0',wrapped,trap=trap,objects=objects); execute(name+'-O2',wrapped,True,trap=trap,objects=objects)
		preserved=re.sub(r'^define internal fastcc ([^\n]+) \{$',r'define fastcc \1 noinline {',wrapped,flags=re.M)
		execute(name+'-callable-O2-fma',preserved,True,True,trap,objects)
		assert not re.search(r'libglib|libgobject|libLLVM',run(['ldd',binary]))

	for typename,lltype,width,patterns in [('f64','double',64,[0,0x8000000000000000,1,0xfffffffffffff,0x10000000000000,0x3ff0000000000001,0x7ff0000000000000,0xfff0000000000000,0x7ff8000000001234]),('f32','float',32,[0,0x80000000,1,0x7fffff,0x800000,0x3f800001,0x7f800000,0xff800000,0x7fc01234])]:
		source=out/(typename+'-bits.astra'); source.write_text(f'struct I{{{typename} value;}}struct O{{I inner;}}\n{typename} promoted({typename} x){{O a={{inner={{value=x}}}};O b=a;b=a;return b.inner.value;}}\n{typename} addressed({typename} x){{O a={{inner={{value=x}}}};O b={{inner={{value=0.0}}}};O* ap=&a;O* bp=&b;*bp=*ap;O c=*bp;return c.inner.value;}}\n')
		ir=run([compiler,'--dump-llvm',source]); assert not re.search(r'\bf(?:add|sub|mul|div|ptrunc|pext)\b',ir)
		ir=re.sub(r'^define internal fastcc ([^\n]+) \{$',r'define fastcc \1 noinline {',ir,flags=re.M)
		lines=[ir,'define i32 @main(){']; ordinal=0
		for function in [0,1]:
			for bits in patterns:
				i=ordinal; ordinal+=1
				lines += [f'\t%r{i}=call fastcc {lltype} @astra.fn.{function}({lltype} bitcast(i{width} {bits} to {lltype}))',f'\t%b{i}=bitcast {lltype} %r{i} to i{width}',f'\t%ok{i}=icmp eq i{width} %b{i},{bits}',f'\tbr i1 %ok{i},label %next{i},label %bad',f'next{i}:']
		lines += ['\tret i32 0','bad:','\tret i32 1','}']; records['bit_patterns'][typename]=[hex(x) for x in patterns]
		for optimized in [False,True]:
			execute(typename+'-bits-'+('O2-fma' if optimized else 'O0'),'\n'.join(lines)+'\n',optimized,True)
	(out/'results.json').write_text(json.dumps(records,indent='\t')+'\n')
	print(f"{len(records['runs'])} executions; {len(records['shapes'])} vector shapes; {len(records['deterministic'])} deterministic comparisons; exact F32/F64 transport")


if __name__=='__main__':
	main(Path(sys.argv[1]).resolve(),Path(sys.argv[2]).resolve())
