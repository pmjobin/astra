# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Recursive storage, vector-shape, IEEE, O2, FMA and machine qualification."""
from pathlib import Path
import json
import os
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'tests/struct-agg/fixtures'
CASES = ['basic', 'deep', 'siblings', 'vector', 'f64', 'pointer', 'scalarize', 'addressed', 'method', 'order', 'generic']
FLAGS = r'\b(?:reassoc|nnan|ninf|nsz|arcp|contract|afn|fast)\b|llvm\.(?:fma|fmuladd)|unsafe-fp|no-nans|no-infs|no-signed-zeros'


def run(argv, status=0):
	result = subprocess.run(list(map(str, argv)), cwd=ROOT, capture_output=True, text=True, env=dict(os.environ, CCACHE_DISABLE='1'))
	assert result.returncode == status and result.stderr == '', (argv, result)
	return result.stdout


def matrix():
	lines = []
	initializers = []
	checks = []
	shapes = []
	for element, width in [('i8',8),('u8',8),('i16',16),('u16',16),('int',32),('u32',32),('f32',32),('bool',1)]:
		for lanes in [2,4,8,16]:
			if element == 'f32' and lanes > 4 or element not in ['bool','f32'] and width * lanes > 128:
				continue
			shape = f'{element}<{lanes}>'
			name = f'v{len(shapes)}'
			zero, one = ('false','true') if element == 'bool' else ('0.0','1.0') if element == 'f32' else ('0','1')
			shapes.append(shape)
			lines.append(f'\t{shape} {name};')
			initializers.append(f'{name}=splat({zero},{lanes})')
			checks += [f'\ts.inner.{name}=insert(s.inner.{name},{lanes-1},{one});', f'\tif(s.inner.{name}[{lanes-1}]!={one} || s.inner.{name}[0]!={zero}){{return 1;}}']
	decl = 'struct Leaf {\n' + '\n'.join(lines) + '\n}\nstruct Outer{Leaf inner;}\n'
	body = '\tOuter s={inner={' + ','.join(initializers) + '}};\n' + '\n'.join(checks) + '\n'
	# Exercise the same fields through both promotion and addressable storage.
	return decl + 'int promoted(){\n' + body + '\treturn 0;\n}\nvoid touch(Outer* p){p->inner.v0=insert(p->inner.v0,0,7);}\nint main(){\n' + body + '\ttouch(&s);if(s.inner.v0[0]!=7){return 2;}return promoted();\n}\n', shapes


def deep(depth):
	declarations = ['struct Leaf { int value; }']
	for i in range(depth):
		declarations.append(f'struct S{i}{{' + ('Leaf' if i == 0 else f'S{i-1}') + ' child;}')
	initializer = '{value=1}'
	for _ in range(depth):
		initializer = '{child=' + initializer + '}'
	field = 'o.' + 'child.' * depth + 'value'
	return '\n'.join(declarations) + f'\nint main(){{S{depth-1} o={initializer};{field}=42;if({field}!=42){{return 1;}}return 0;}}\n'


def main(compiler, out):
	out.mkdir(parents=True, exist_ok=True)
	records = dict(runs=[], shapes=[], deterministic=[], audits=[])
	matrix_source, records['shapes'] = matrix()
	(out/'matrix.astra').write_text(matrix_source)
	(out/'deep-64.astra').write_text(deep(64))

	def execute(name, ir, optimize=False, fma=False):
		input_path = out/(name+'-input.ll')
		input_path.write_text(ir)
		path, obj, binary = out/(name+'.ll'), out/(name+'.o'), out/name
		run(['opt','-passes=default<O2>' if optimize else '-passes=verify','-S',input_path,'-o',path])
		run(['opt','-passes=verify','-disable-output',path])
		assert not re.search(FLAGS, path.read_text()), name
		run(['llc','-O2' if optimize else '-O0','-filetype=obj','-relocation-model=pic',*(['-mattr=+fma'] if fma else []),path,'-o',obj])
		run(['cc',obj,'-o',binary]); run([binary])
		machine = run(['objdump','-dr',obj]); (out/(name+'.machine')).write_text(machine)
		assert not re.search(r'\bv?f(?:n?madd|n?msub)\w*\b',machine), name
		(out/(name+'.symbols')).write_text(run(['readelf','-Ws',obj]))
		records['runs'].append(name)

	for name in [*CASES,'matrix','deep-64']:
		source = out/(name+'.astra') if name in ['matrix','deep-64'] else FIXTURES/('struct-agg-'+name+'.astra')
		binary = out/(name+'-native'); run([compiler,source,'-o',binary]); run([binary]); records['runs'].append(name+'-native')
		stages = {stage: run([compiler,'--dump-'+stage,source]) for stage in ['syntax','semantics','core','cfg','ssa','nabi','llvm']}
		for stage, text in stages.items():
			(out/(name+'.'+stage)).write_text(text)
			assert text == run([compiler,'--dump-'+stage,source]), (name, stage)
			records['deterministic'].append(name+':'+stage)
		ir = stages['llvm']
		assert not re.search(FLAGS,ir) and not re.search(r'@(?:llvm\.memcpy|malloc|calloc|realloc)|typeinfo|descriptor',ir)
		if name in ['basic','deep','siblings','scalarize','deep-64']:
			assert 'alloca' not in ir and 'getelementptr' not in ir
		if name == 'addressed':
			assert len(re.findall(r' = alloca ',ir)) == 1
		if name == 'vector':
			assert 'load <8 x i16>' in ir and 'store <8 x i16>' in ir and '<4 x float>' in ir
		main_id = re.search(r'\(function #(\d+) "main" -> int',stages['ssa'])[1]
		wrapped = ir + '\ndefine i32 @main(){\n\t%r=call fastcc i32 @astra.fn.' + main_id + '()\n\tret i32 %r\n}\n'
		execute(name+'-O0',wrapped)
		execute(name+'-O2',wrapped,True)
		preserved = re.sub(r'^define internal fastcc ([^\n]+) \{$',r'define fastcc \1 noinline {',wrapped,flags=re.M)
		execute(name+'-callable-O2-fma',preserved,True,True)
		linkage = run(['ldd',binary]); assert not re.search(r'libglib|libgobject|libLLVM',linkage)
		records['audits'].append(name)
		# Bit patterns cross nested promoted and addressed storage without conversions.
	for typename,lltype,width,patterns in [('f64','double',64,[0,0x8000000000000000,1,0xfffffffffffff,0x10000000000000,0x3ff0000000000001]),('f32','float',32,[0,0x80000000,1,0x7fffff,0x800000,0x3f800001])]:
		source = out/(typename+'-bits.astra')
		source.write_text(f'struct I{{{typename} value;}}struct O{{I a;I b;}}\n{typename} promoted({typename} x){{O o={{a={{value=x}},b={{value=0.0}}}};return o.a.value;}}\nvoid change(O* p,{typename} x){{p->a.value=x;}}\n{typename} addressed({typename} x){{O o={{a={{value=0.0}},b={{value=x}}}};change(&o,x);return o.a.value;}}\n{typename} separate({typename} a,{typename} b,{typename} c){{O o={{a={{value=a}},b={{value=b}}}};return o.a.value*o.b.value+c;}}\n')
		ir = run([compiler,'--dump-llvm',source]); ssa = run([compiler,'--dump-ssa',source])
		ids = {name: ordinal for ordinal,name in re.findall(r'\(function #(\d+) "([^\"]+)"',ssa)}
		ir = re.sub(r'^define internal fastcc ([^\n]+) \{$',r'define fastcc \1 noinline {',ir,flags=re.M)
		lines = [ir,'define i32 @main(){']
		ordinal = 0
		for name in ['promoted','addressed']:
			for bits in patterns:
				i = ordinal; ordinal += 1
				lines += [f'\t%r{i}=call fastcc {lltype} @astra.fn.{ids[name]}({lltype} bitcast(i{width} {bits} to {lltype}))', f'\t%b{i}=bitcast {lltype} %r{i} to i{width}', f'\t%ok{i}=icmp eq i{width} %b{i},{bits}', f'\tbr i1 %ok{i},label %next{i},label %bad',f'next{i}:']
				# A*b+c distinguishes separate rounding from FMA contraction.
		a,b,c = (0x3ff0000000000001,0x3feffffffffffffe,0xbff0000000000000) if width == 64 else (0x3f800001,0x3f7ffffe,0xbf800000)
		arguments = ','.join(f'{lltype} bitcast(i{width} {bits} to {lltype})' for bits in [a,b,c])
		lines += [f'\t%round=call fastcc {lltype} @astra.fn.{ids["separate"]}({arguments})',f'\t%bits=bitcast {lltype} %round to i{width}',f'\t%ok=icmp eq i{width} %bits,0','\tbr i1 %ok,label %good,label %bad','good:','\tret i32 0','bad:','\tret i32 1','}']
		for optimize in [False,True]:
			execute(typename+'-bits-'+('O2-fma' if optimize else 'O0'),'\n'.join(lines)+'\n',optimize,True)
	(out/'results.json').write_text(json.dumps(records,indent='\t')+'\n')
	print(f"{len(records['runs'])} executions; {len(records['shapes'])} vector shapes; {len(records['deterministic'])} deterministic stage comparisons")


if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(),Path(sys.argv[2]).resolve())
