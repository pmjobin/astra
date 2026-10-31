# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""GEN-CAP-1 native matrices, IEEE/bit edges, O2 and machine qualification."""
from pathlib import Path
import json
import os
import re
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT/'tests/gen-cap/fixtures'
CASES = {name: (42, '') for name in ['eq', 'ordered', 'numeric', 'bitwise', 'shift', 'multi', 'forward', 'recursive', 'property']}
CASES.update({'owned': (42, 'VRVS'), 'object-owned': (42, 'AB')})
FLAGS = r'\b(?:reassoc|nnan|ninf|nsz|arcp|contract|afn|fast)\b|llvm\.(?:fma|fmuladd)|unsafe-fp|no-nans|no-infs|no-signed-zeros'
OPERATORS = [('eq','Eq','=='), ('ne','Eq','!='), ('lt','Ordered','<'), ('le','Ordered','<='), ('gt','Ordered','>'), ('ge','Ordered','>='), ('add','Numeric','+'), ('sub','Numeric','-'), ('mul','Numeric','*'), ('div','Numeric','/'), ('band','Bitwise','&'), ('bor','Bitwise','|'), ('bxor','Bitwise','^'), ('bnot','Bitwise','~'), ('shl','Shift','<<'), ('shr','Shift','>>')]


def run(argv, status=0, output=None, stderr=''):
	p = subprocess.run(list(map(str, argv)), cwd=ROOT, capture_output=True, text=True, env=dict(os.environ, CCACHE_DISABLE='1'))
	assert p.returncode == status and (stderr is None or p.stderr == stderr) and (output is None or p.stdout == output), (argv, p)
	return p.stdout


def definitions():
	lines = []
	for name, capability, op in OPERATORS:
		result = 'bool' if capability in ['Eq','Ordered'] else 'T'
		parameters = 'T a' if name == 'bnot' else 'T a,int b' if capability == 'Shift' else 'T a,T b'
		expression = '~a' if name == 'bnot' else 'a'+op+'b'
		lines.append(f'{result} {name}<T>({parameters}) where T : {capability} {{return {expression};}}')
	return '\n'.join(lines)+'\n'


def value_matrix():
	constraints = ['Eq, Ordered','Numeric, Bitwise','Ordered, Bitwise','Numeric, Shift']
	lines = [definitions()]+[f'int intersection{i}<T>() where T : {constraint} {{return 1;}}' for i,constraint in enumerate(constraints)]+['int main(){']
	checks = []
	for element, width in [('i8',8),('u8',8),('i16',16),('u16',16),('int',32),('i32',32),('u32',32),('f32',32),('f64',64),('bool',1),('void*',0)]:
		floating = element.startswith('f')
		integer = width > 1 and not floating
		lo = 'false' if element == 'bool' else 'null' if element == 'void*' else '2.0' if floating else '2'
		hi = 'true' if element == 'bool' else 'null' if element == 'void*' else '4.0' if floating else '4'
		for name, capability, op in OPERATORS:
			if capability != 'Eq' and not (integer or floating and capability in ['Numeric','Ordered']):
				continue
			if name in ['eq','ne','lt','le','gt','ge']:
				samples = [(lo,lo),(lo,hi),(hi,lo),(hi,hi)]
				for a,b in samples:
					expected = {'eq':a==b,'ne':a!=b,'lt':a<b,'le':a<=b,'gt':a>b,'ge':a>=b}[name]
					checks.append((element,name,f'{name}<{element}>({a},{b})',str(expected).lower()))
			elif capability == 'Numeric':
				expected = {'add':'6','sub':'2','mul':'8','div':'2'}[name]+('.0' if floating else '')
				checks.append((element,name,f'{name}<{element}>({hi},{lo})',expected))
			else:
				high = str(1 << (width-1)) if element.startswith('u') else str(-(1 << (width-1)))
				maximum = str((1 << width)-1) if element.startswith('u') else '-1'
				if name == 'bnot':
					checks.append((element,name,f'bnot<{element}>(0)',maximum))
				elif capability == 'Bitwise':
					checks.append((element,name,f'{name}<{element}>({high},1)', '0' if name=='band' else str(int(high)+1)))
				else:
					for count in [0,width-1]:
						value = '1' if name == 'shl' else high
						expected = ('1' if count == 0 else high) if name=='shl' else high if count==0 else '1' if element.startswith('u') else '-1'
						checks.append((element,name,f'{name}<{element}>({value},{count})',expected))
		if integer:
			maximum = (1 << width)-1 if element.startswith('u') else (1 << (width-1))-1
			minimum = 0 if element.startswith('u') else -(1 << (width-1))
			checks += [(element,'wrap',f'add<{element}>({maximum},1)',str(minimum)), (element,'wrap',f'sub<{element}>({minimum},1)',str(maximum))]
			if not element.startswith('u'):
				checks += [(element,'div-edge',f'div<{element}>({minimum},-1)',str(minimum)),(element,'signed-order',f'lt<{element}>({minimum},0)','true')]
	for i in range(len(constraints)):
		for element in ['i8','u8','i16','u16','int','u32']+(['f32','f64'] if i==0 else []):
			checks.append((element,'intersection',f'intersection{i}<{element}>()','1'))
	for i, (element,op,expression,expected) in enumerate(checks):
		lines.append(f'\tif({expression}!={expected}){{return {i%200+1};}}')
	lines += ['\treturn 42;','}']
	return '\n'.join(lines)+'\n', checks


def inventory(text):
	return [dict(ordinal=int(m[0]), definition=int(m[1]), name=m[2], arguments=m[3].split(), requests=int(m[4])) for m in re.findall(r'\(generic-instance #(\d+) \(origin #(\d+) "([^"]+)"\) \(type-arguments (.*?)\) \(requests (\d+)\)',text)]


def main(compiler, out):
	out.mkdir(parents=True,exist_ok=True)
	companion = out/'companion.o'; run(['cc','-c',ROOT/'tests/obj-life/companion.c','-o',companion])
	records = dict(runs=[], machine=[], inventories={}, deterministic=[], floating_patterns={}, matrix_checks=[])
	matrix, records['matrix_checks'] = value_matrix(); (out/'matrix.astra').write_text(matrix)

	def execute(stem, ir, status=42, output='', optimize=False, fma=False):
		input_path=out/(stem+'-input.ll'); input_path.write_text(ir)
		path=out/(stem+'.ll'); obj=out/(stem+'.o')
		run(['opt','-passes=default<O2>' if optimize else '-passes=verify','-S',input_path,'-o',path])
		run(['opt','-passes=verify','-disable-output',path])
		# Optimizers can infer integer flags for concrete arithmetic. The source IR
		# audit forbids them; the floating contract remains strict at every stage.
		assert not re.search(FLAGS,path.read_text()), stem
		run(['llc','-O2' if optimize else '-O0','-filetype=obj','-relocation-model=pic',*(['-mattr=+fma'] if fma else []),path,'-o',obj])
		run(['cc',obj,companion,'-o',out/stem]); run([out/stem],status,output)
		machine=run(['objdump','-dr',obj]); (out/(stem+'.machine')).write_text(machine)
		assert not re.search(r'\bv?f(?:n?madd|n?msub)\w*\b',machine), stem
		(out/(stem+'.symbols')).write_text(run(['readelf','-h','-Ws',obj]))
		records['runs'].append(dict(name=stem,status=status,output=output))

	for name,(status,output) in dict(CASES,matrix=(42,'')).items():
		source = out/'matrix.astra' if name=='matrix' else FIXTURES/f'gen-cap-{name}.astra'
		options = ['--vapi',ROOT/'tests/obj-life/fixtures/lifecycle.vapi'] if name=='owned' else []
		run([compiler,source,*options,'--link-object',companion,'-o',out/name],output=''); run([out/name],status,output)
		records['runs'].append(dict(name=name,status=status,output=output))
		stages={stage:run([compiler,'--dump-'+stage,source,*options]) for stage in ['semantics','core','instances','cfg','ssa','nabi','llvm']}
		for stage,text in stages.items():
			(out/(name+'.'+stage)).write_text(text)
			if stage in ['semantics','core','instances','llvm']:
				assert text==run([compiler,'--dump-'+stage,source,*options]),(name,stage)
				records['deterministic'].append(name+':'+stage)
		rows=inventory(stages['instances']); records['inventories'][name]=rows
		assert len({(row['definition'],tuple(row['arguments'])) for row in rows})==len(rows)
		ir=stages['llvm']; assert not re.search(FLAGS,ir)
		assert not re.search(r'\b(?:add|sub|mul|sdiv|udiv|shl)\s+(?:nsw|nuw)\b',ir), name
		assert not re.search(r'capability|dictionary|witness|boxing|generic.dispatch|type.descriptor',ir)
		assert all(not re.search(r'generic-op|type-parameter|GEN1_PLAIN_COPY',stages[stage]) for stage in ['cfg','ssa','nabi','llvm'])
		main_id=re.search(r'\(function #(\d+) "main" -> int',stages['ssa'])[1]
		wrapped=ir+'\ndefine i32 @main() {\n\t%r = call fastcc i32 @astra.fn.'+main_id+'()\n\tret i32 %r\n}\n'
		execute(name+'-O0',wrapped,status,output)
		execute(name+'-O2',wrapped,status,output,True)
		preserved=re.sub(r'^define internal fastcc ([^\n]+) \{$',r'define fastcc \1 noinline {',wrapped,flags=re.M)
		execute(name+'-callable-O2',preserved,status,output,True,True)
		linkage=run(['ldd',out/name]); assert not re.search(r'libglib|libgobject|libLLVM',linkage)
		records['machine'].append(dict(name=name,evidence=name+'-callable-O2.machine',target='x86-64',instances=len(rows)))
		# Concrete invalid counts and integer divide zero use ordinary trap operations.
	for typename,width in [('i8',8),('u8',8),('i16',16),('u16',16),('int',32),('u32',32)]:
		for op in ['div','shl','shr']:
			for invalid in ([0] if op=='div' else [width,-1]):
				name=f'trap-{typename}-{op}-{invalid}'
				source=out/(name+'.astra'); source.write_text(definitions()+f'int main(){{{typename} x={op}<{typename}>(1,{invalid});return x as int;}}')
				ir=run([compiler,'--dump-llvm',source]); main_id=re.search(r'\(function #(\d+) "main"',run([compiler,'--dump-ssa',source]))[1]
				ir+='\ndefine i32 @main(){\n\t%r=call fastcc i32 @astra.fn.'+main_id+'()\n\tret i32 %r\n}\n'
				for optimize in [False,True]: execute(name+('-O2' if optimize else '-O0'),ir,-signal.SIGILL,'',optimize)
	floating_audit(compiler,out,records,execute)
	assert 'sdiv i32' in (out/'numeric.llvm').read_text() and 'fdiv double' in (out/'numeric.llvm').read_text()
	assert 'ashr i32' in (out/'shift.llvm').read_text() and 'lshr i32' in (out/'shift.llvm').read_text()
	assert 'icmp slt i32' in (out/'ordered.llvm').read_text() and 'icmp ult i32' in (out/'ordered.llvm').read_text()
	(out/'results.json').write_text(json.dumps(records,indent='\t')+'\n')
	print(f"{len(records['runs'])} executions; {len(records['matrix_checks'])} scalar operator/edge checks; {len(records['deterministic'])} deterministic comparisons")


def floating_audit(compiler,out,records,execute):
	for name,lltype,width,one,negzero,inf,quiet,normal,ulp,below,half in [
		('f32','float',32,0x3f800000,0x80000000,0x7f800000,0x7fc12345,0x00800000,0x3f800001,0x3f7ffffe,0x33800000),
		('f64','double',64,0x3ff0000000000000,0x8000000000000000,0x7ff0000000000000,0x7ff8123456789abc,0x0010000000000000,0x3ff0000000000001,0x3feffffffffffffe,0x3ca0000000000000)]:
		source=out/(name+'-specials.astra')
		code=definitions()+'T compose<T>(T a,T b,T c) where T : Numeric {return a*b+c;}\n'
		ops=OPERATORS[:10]+[('compose','Numeric','')]
		for op,cap,_ in ops:
			result='bool' if cap in ['Eq','Ordered'] else name
			params=f'{name} a,{name} b'+(f',{name} c' if op=='compose' else '')
			args='a,b,c' if op=='compose' else 'a,b'
			code+=f'{result} root_{op}({params}){{return {op}<{name}>({args});}}\n'
		source.write_text(code)
		ir=run([compiler,'--dump-llvm',source]); assert not re.search(FLAGS,ir)
		ssa=run([compiler,'--dump-ssa',source]); ids=dict(re.findall(r'\(function #(\d+) "root_([^"]+)"',ssa)); ids={op:ordinal for ordinal,op in ids.items()}
		ir=re.sub(r'^define internal fastcc ([^\n]+) \{$',r'define fastcc \1 noinline {',ir,flags=re.M)
		cases=[('eq',[quiet,quiet],False),('ne',[quiet,quiet],True),('eq',[0,negzero],True),('eq',[inf,inf],True)]
		for op in ['lt','le','gt','ge']: cases += [(op,[quiet,one],False),(op,[one,quiet],False)]
		cases += [('lt',[inf|negzero,0],True),('gt',[inf,one],True),('le',[0,negzero],True),('ge',[negzero,0],True)]
		cases += [('add',[negzero,negzero],negzero),('add',[one,half],one),('sub',[normal,1],normal-1),('mul',[1,one],1),('mul',[negzero,one],negzero),('div',[one,0],inf),('div',[one|negzero,0],inf|negzero),('div',[0,0],'nan'),('compose',[ulp,below,one|negzero],0)]
		lines=[ir,'define i32 @main() {']
		for i,(op,args,expected) in enumerate(cases):
			comparison=op in ['eq','ne','lt','le','gt','ge']
			arguments=', '.join(f'{lltype} bitcast (i{width} {bits} to {lltype})' for bits in args)
			lines.append(f'\t%r{i}=call fastcc {"i1" if comparison else lltype} @astra.fn.{ids[op]}({arguments})')
			if comparison: lines.append(f'\t%ok{i}=icmp eq i1 %r{i}, {str(expected).lower()}')
			elif expected=='nan': lines.append(f'\t%ok{i}=fcmp uno {lltype} %r{i}, %r{i}')
			else: lines += [f'\t%bits{i}=bitcast {lltype} %r{i} to i{width}', f'\t%ok{i}=icmp eq i{width} %bits{i}, {expected}']
			lines += [f'\tbr i1 %ok{i}, label %next{i}, label %bad',f'next{i}:']
		lines += ['\tret i32 42','bad:','\tret i32 1','}']
		for optimize in [False,True]: execute(name+'-specials-'+('O2-fma' if optimize else 'O0'),'\n'.join(lines)+'\n',optimize=optimize,fma=True)
		records['floating_patterns'][name]=cases
		machine=(out/(name+'-specials-O2-fma.machine')).read_text()
		assert ('mulss' if name=='f32' else 'mulsd') in machine and ('addss' if name=='f32' else 'addsd') in machine
		records['machine'].append(dict(name=name+'-specials',evidence=name+'-specials-O2-fma.machine',target='x86-64 +fma'))
	source=out/'pointer.astra'; source.write_text('bool same<T>(T a,T b) where T : Eq {return a==b;}bool root(void* a,void* b){return same<void*>(a,b);}')
	ir=run([compiler,'--dump-llvm',source]); ir=re.sub(r'^define internal fastcc ([^\n]+) \{$',r'define fastcc \1 noinline {',ir,flags=re.M)
	lines=[ir,'define i32 @main(){','\t%a=alloca i32','\t%b=alloca i32']
	for i,(a,b,expected) in enumerate([('null','null',True),('%a','%a',True),('%a','%b',False),('%a','null',False),('null','%a',False)]):
		lines += [f'\t%r{i}=call fastcc i1 @astra.fn.0(ptr {a}, ptr {b})',f'\t%ok{i}=icmp eq i1 %r{i}, {str(expected).lower()}',f'\tbr i1 %ok{i}, label %next{i}, label %bad',f'next{i}:']
	lines += ['\tret i32 42','bad:','\tret i32 1','}']
	for optimize in [False,True]: execute('pointer-'+('O2' if optimize else 'O0'),'\n'.join(lines)+'\n',optimize=optimize)


if __name__=='__main__':
	main(Path(sys.argv[1]).resolve(),Path(sys.argv[2]).resolve())
