# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Source composition, typed expansion, runtime differential and installed consumer."""
from pathlib import Path
import hashlib
import itertools
import json
import os
import random
import re
import resource
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True
from oracle import BINARY32, BINARY64, TYPES, OPS, integer, integer_result, patterns
ROOT = Path(__file__).resolve().parents[2]
STAGES = ['core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def process(args, **kwargs):
	return subprocess.run(list(map(str, args)), capture_output=True, text=True, env=dict(os.environ, CCACHE_DISABLE='1'), **kwargs)


def run(args, **kwargs):
	p = process(args, **kwargs)
	assert p.returncode == 0 and not p.stderr, (args, p.returncode, p.stdout, p.stderr)
	return p.stdout


def literal(fmt, bits):
	if fmt.is_nan(bits):
		return '(0.0' + ('f' if fmt.width == 32 else 'd') + '/0.0' + ('f' if fmt.width == 32 else 'd') + ')'
	return fmt.literal(bits) + ('f' if fmt.width == 32 else 'd')


def compile_ir(ir, stem, mode, links=()):
	stem.with_suffix('.input.ll').write_text(ir)
	run(['opt', '-passes=verify' if mode == 'O0' else '-passes=default<O2>', '-S', stem.with_suffix('.input.ll'), '-o', stem.with_suffix('.ll')])
	run(['llc', '-O0' if mode == 'O0' else '-O2', '-filetype=obj', '-relocation-model=pic', *(['-mattr=+fma'] if mode == 'fma' else []), stem.with_suffix('.ll'), '-o', stem.with_suffix('.o')])
	machine = run(['objdump', '-dr', stem.with_suffix('.o')]); stem.with_suffix('.machine').write_text(machine)
	assert not re.search(r'\bv(?:fmadd|fmsub|fnmadd|fnmsub)', machine)
	run(['cc', stem.with_suffix('.o'), *links, '-o', stem])
	assert run([stem]) == ''
	return hashlib.sha256(machine.split('Disassembly of section', 1)[-1].encode()).hexdigest()


def composition(compiler, out):
	sources = [ROOT / 'tests/const/fixtures' / name for name in ['00-dimensions.astra', '10-values.astra', '20-client.astra']] + [ROOT / 'lib/astra/base/order.astra']
	records = {}
	for stage in ['syntax', 'semantics', *STAGES]:
		expected = run([compiler, '--dump-' + stage, *sources]); (out / ('composition.' + stage)).write_text(expected)
		for order in itertools.permutations(sources):
			assert run([compiler, '--dump-' + stage, *order]) == expected
		records[stage] = hashlib.sha256(expected.encode()).hexdigest()
	moved = out / 'relocated'
	for source in sources:
		target = moved / source.relative_to(ROOT); target.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(source, target)
	for stage in ['semantics', *STAGES]:
		assert run([compiler, '--dump-' + stage, *[moved / p.relative_to(ROOT) for p in sources]]) == (out / ('composition.' + stage)).read_text()
		# Error choice and exact per-file declaration/use provenance are stable.
	bad = out / 'bad'; bad.mkdir(exist_ok=True)
	texts = ['const A=false && B;', 'const B=A;', 'int f(){return 1;}', 'int main(){return 0;}']
	negative = []
	for mode in ['cycle', 'duplicate', 'unknown', 'unused']:
		case = texts[:]
		if mode == 'duplicate': case[:2] = ['const A=1;', 'const A=2;']
		if mode == 'unknown': case[:2] = ['const A=MISSING;', 'const B=2;']
		if mode == 'unused': case[:2] = ['const A=1/0;', 'const B=2;']
		paths = [bad / f'{i}.astra' for i in range(4)]
		for p, t in zip(paths, case): p.write_text(t)
		expected = None
		for order in itertools.permutations(paths):
			p = process([compiler, '--check', *order]); assert p.returncode == 1 and not p.stdout
			assert expected is None or expected == p.stderr; expected = p.stderr
		assert '0.astra:1:' in expected
		if mode in ['cycle', 'duplicate']: assert '1.astra:1:' in expected
		negative.append(dict(kind=mode, diagnostic=expected.replace(str(out), '<qualification>')))
		# VAPI remains independent; exact C symbol strings may still say const.
	api = out / 'foreign.vapi'; api.write_text('[CCode (cname = "const")]\nint foreign_name();\n')
	use = out / 'foreign.astra'; use.write_text('int main(){return foreign_name();}')
	assert '@const' in run([compiler, '--dump-llvm', use, '--vapi', api])
	api.write_text('int const();\n'); use.write_text('int main(){return 0;}'); run([compiler, '--check', use, '--vapi', api])
	api.write_text('int VALUE();\n'); use.write_text('const VALUE=1;')
	p = process([compiler, '--check', use, '--vapi', api]); assert p.returncode == 1 and 'duplicate constant or callable' in p.stderr
	return dict(stages=records, permutations=24, permutation_stage_checks=24 * 9, relocated_stage_checks=8, negative_permutation_checks=96, diagnostics=negative)


def expansion(compiler, out):
	# Final TYPE-CORRECT exact values: each int use remains int; f32/f64
	# spellings fix their already-rounded precision. No raw initializer expansion.
	name = out / 'named.astra'; expanded = out / 'expanded.astra'
	name.write_text('''const N=2*2; const int WRAP=(2147483647+1)/2;
const f64 X=(1.0d+1.1102230246251565e-16d)-1.0d;
T id<T>(T value){const IGNORE=1;return value;}
int main(){const L=N;int[L] a={1,2,3,4};var x=id(L);if(x!=4 || a[3]!=4 || WRAP!=-1073741824 || X!=0.0d){return 1;}return 0;}
''')
	expanded.write_text('''T id<T>(T value){return value;}
int main(){int[4] a={1,2,3,4};var x=id(4);if(x!=4 || a[3]!=4 || -1073741824!=-1073741824 || 0.0d!=0.0d){return 1;}return 0;}
''')
	for stage in STAGES:
		first = run([compiler, '--dump-' + stage, name]); second = run([compiler, '--dump-' + stage, expanded]); assert first == second, stage
		(out / ('expansion.' + stage)).write_text(first)
	for source in [name, expanded]:
		run([compiler, source, '-o', source.with_suffix('')]); assert run([source.with_suffix('')]) == ''
		# A pure constant program requires no runtime library even at O0.
	pure = out / 'pure.astra'; pure.write_text('const COUNT=40+2; const SCALE=1.0d/255.0d; export(C) int answer(){return COUNT;} export(C) f64 scale(){return SCALE;}')
	ir = run([compiler, '--dump-llvm', pure]); (out / 'pure.ll').write_text(ir)
	assert not re.search(r'\b(alloca|load|store|global|llvm.global_ctors|malloc|calloc|free)\b', ir)
	run(['llc', '-O0', '-filetype=obj', out / 'pure.ll', '-o', out / 'pure.o'])
	assert run(['nm', '-u', out / 'pure.o']) == ''
	symbols = run(['nm', out / 'pure.o']); assert not re.search(r'\b(COUNT|SCALE)\b', symbols)
	(out / 'pure-symbols.txt').write_text(symbols)
	# Named operands do not turn ordinary runtime traps into source errors.
	for label, body in [('divide','const Z=0;return 1/Z;'), ('convert','const INF=1.0d/0.0d;return INF as int;')]:
		path = out / ('runtime-trap-' + label + '.astra'); path.write_text('int main(){'+body+'}')
		run([compiler, path, '-o', path.with_suffix('')]); p = process([path.with_suffix('')]); assert p.returncode < 0
	return dict(executable_stage_comparisons=len(STAGES), pure_undefined_symbols=0, pure_constant_object_symbols=0)


def runtime(compiler, out):
	rng = random.Random(7218); declarations = []; header = ['#include <stdint.h>', '#include <string.h>']; rows_by_width = {}
	for fmt in [BINARY32, BINARY64]:
		w = fmt.width; suffix = 'f' if w == 32 else 'd'; p = [b for b in patterns(fmt) if not fmt.is_nan(b)]
		pairs = [(a, op, b) for a, b in itertools.product(p[:12], p[:12]) for op in ['+', '-', '*', '/']]
		pairs += [(rng.choice(p), rng.choice(['+', '-', '*', '/']), rng.choice(p)) for _ in range(1024 - len(pairs))]
		assert len(pairs) == 1024
		rows = []
		for i, (a, op, b) in enumerate(pairs):
			bits = fmt.arithmetic(op, a, b); rows.append([a, b, bits, ['+', '-', '*', '/'].index(op), int(fmt.is_nan(bits))])
			declarations.append(f'const C{w}_{i}=({literal(fmt, a)}) {op} ({literal(fmt, b)});')
		declarations.append(f'export(C) f{w} named{w}(int i) {{f{w}[1024] values={{' + ','.join(f'C{w}_{i}' for i in range(1024)) + '};return values[i];}')
		for op, label in zip(['+', '-', '*', '/'], ['add', 'sub', 'mul', 'div']): declarations.append(f'export(C) f{w} {label}{w}(f{w} a,f{w} b){{return a{op}b;}}')
		declarations.append(f'export(C) f{w} separate{w}(f{w} a,f{w} b,f{w} c){{return a*b+c;}}')
		# One-ulp cancellation distinguishes multiply+add rounding from FMA.
		a = (fmt.bias << fmt.fraction) + 1; b = (fmt.bias << fmt.fraction) - 2; c = (fmt.bias << fmt.fraction) | fmt.sign
		bits = fmt.arithmetic('+', fmt.arithmetic('*', a, b), c)
		assert bits != fmt.round(fmt.value(a) * fmt.value(b) + fmt.value(c)), 'witness must distinguish fused arithmetic'
		declarations.append(f'const SEP{w}=({literal(fmt,a)})*({literal(fmt,b)})+({literal(fmt,c)}); export(C) f{w} separated{w}(){{return SEP{w};}}')
		ctype = 'float' if w == 32 else 'double'
		header += [f'extern {ctype} named{w}(int32_t);', *[f'extern {ctype} {label}{w}({ctype},{ctype});' for label in ['add', 'sub', 'mul', 'div']], f'extern {ctype} separate{w}({ctype},{ctype},{ctype});', f'extern {ctype} separated{w}(void);']
		header.append(f'static const uint{w}_t rows{w}[1024][5]={{' + ',\n'.join('{' + ','.join(f'UINT{w}_C(0x{x:x})' for x in row) + '}' for row in rows) + '};')
		header.append(f'''static int check{w}(void) {{
	for(int i=0;i<1024;i++){{
		{ctype} a,b,v,n;uint{w}_t vb,nb;memcpy(&a,&rows{w}[i][0],sizeof a);memcpy(&b,&rows{w}[i][1],sizeof b);
		switch(rows{w}[i][3]){{case 0:v=add{w}(a,b);break;case 1:v=sub{w}(a,b);break;case 2:v=mul{w}(a,b);break;default:v=div{w}(a,b);}}
		n=named{w}(i);memcpy(&vb,&v,sizeof v);memcpy(&nb,&n,sizeof n);
		if(rows{w}[i][4]){{if((vb&UINT{w}_C(0x{fmt.sign-1:x}))<=UINT{w}_C(0x{fmt.infinity:x}) || (nb&UINT{w}_C(0x{fmt.sign-1:x}))<=UINT{w}_C(0x{fmt.infinity:x}))return 1;}}
		else if(vb!=rows{w}[i][2] || nb!=rows{w}[i][2])return 2;
	}}
	uint{w}_t ab=UINT{w}_C(0x{a:x}),bb=UINT{w}_C(0x{b:x}),cb=UINT{w}_C(0x{c:x}),vbits,nbits;
	{ctype} a,b,c,v,n;memcpy(&a,&ab,sizeof a);memcpy(&b,&bb,sizeof b);memcpy(&c,&cb,sizeof c);
	v=separate{w}(a,b,c);n=separated{w}();memcpy(&vbits,&v,sizeof v);memcpy(&nbits,&n,sizeof n);
	return vbits!=UINT{w}_C(0x{bits:x}) || nbits!=UINT{w}_C(0x{bits:x});
}}''')
		large = (fmt.bias + fmt.fraction + 2) << fmt.fraction; opposite = large | fmt.sign; one = fmt.bias << fmt.fraction
		ordered = fmt.arithmetic('+', fmt.arithmetic('+', large, opposite), one)
		reassociated = fmt.arithmetic('+', large, fmt.arithmetic('+', opposite, one))
		assert ordered != reassociated
		declarations.append(f'const SUM{w}=(({literal(fmt,large)})+({literal(fmt,opposite)}))+({literal(fmt,one)});export(C) f{w} ordered{w}(){{return SUM{w};}}export(C) f{w} sum{w}(f{w} a,f{w} b,f{w} c){{return (a+b)+c;}}')
		header.append(f'extern {ctype} ordered{w}(void);extern {ctype} sum{w}({ctype},{ctype},{ctype});')
		header.append(f'static int order{w}(void){{uint{w}_t ab=UINT{w}_C(0x{large:x}),bb=UINT{w}_C(0x{opposite:x}),cb=UINT{w}_C(0x{one:x}),vb,nb;{ctype} a,b,c,v,n;memcpy(&a,&ab,sizeof a);memcpy(&b,&bb,sizeof b);memcpy(&c,&cb,sizeof c);v=sum{w}(a,b,c);n=ordered{w}();memcpy(&vb,&v,sizeof v);memcpy(&nb,&n,sizeof n);return vb!=UINT{w}_C(0x{ordered:x}) || nb!=UINT{w}_C(0x{ordered:x});}}')
		rows_by_width[str(w)] = dict(cases=len(rows), fusion_witness=[hex(a),hex(b),hex(c),hex(bits)], reassociation_witness=[hex(large),hex(opposite),hex(one),hex(ordered),hex(reassociated)], rational_result_sha256=hashlib.sha256(json.dumps(rows).encode()).hexdigest())
	declarations.append('int constant_bool_value(bool b){if(b){return 1;}return 0;}')
	integer_checks = []
	for name, (width, signed) in TYPES.items():
		mask = (1 << width) - 1; edges = [0,1,2,mask//2,mask//2+1,mask-1,mask]
		cases = [(a,op,b) for a,b in itertools.product(edges, repeat=2) for op in OPS if not (op in ['/', '%'] and b == 0)]
		declarations.append(f'export(C) int run_{name}(int op,int a,int b){{var x=a as {name};var y=b as {name};')
		for index, op in enumerate(OPS):
			value = f'x{op}y'
			declarations.append(f'if(op=={index}){{' + (f'if({value}){{return 1;}}return 0;' if op in ['==','!=','<','<=','>','>='] else f'return ({value}) as int;') + '}')
		declarations.append('return 0;}')
		rows = []
		for i,(a,op,b) in enumerate(cases):
			expected = integer_result(name,op,a,b)
			number = int(expected == 'true') if expected in ['true','false'] else int(expected)
			result = integer('int',number & 0xffffffff)
			av,bv = integer('int',a),integer('int',b)
			declarations.append(f'const K_{name}_{i}=({av} as {name}) {op} ({bv} as {name});')
			rows.append([av,bv,OPS.index(op),result])
		declarations.append(f'export(C) int named_{name}(int i){{int[{len(cases)}] values={{' + ','.join(f'(K_{name}_{i} as int)' if op not in ['==','!=','<','<=','>','>='] else f'constant_bool_value(K_{name}_{i})' for i,(_,op,_) in enumerate(cases)) + '};return values[i];}')
		header += [f'extern int32_t run_{name}(int32_t,int32_t,int32_t);extern int32_t named_{name}(int32_t);', f'static const int32_t integers_{name}[][4]={{' + ','.join('{' + ','.join(str(x) for x in row) + '}' for row in rows) + '};', f'static int check_{name}(void){{for(int i=0;i<{len(rows)};i++){{const int32_t *r=integers_{name}[i];if(run_{name}(r[2],r[0],r[1])!=r[3] || named_{name}(i)!=r[3])return 1;}}return 0;}}']
		integer_checks.append('check_' + name + '()')
	header += ['int main(void){return check32() || check64() || order32() || order64() || ' + ' || '.join(integer_checks) + ';}']
	source = out / 'runtime.astra'; source.write_text('\n'.join(declarations) + '\n')
	companion = out / 'runtime.c'; companion.write_text('\n'.join(header) + '\n')
	ir = run([compiler, '--dump-llvm', source]); (out / 'runtime.ll').write_text(ir)
	machines = {mode: compile_ir(ir, out / ('runtime-' + mode), mode, [companion]) for mode in ['O0', 'O2', 'fma']}
	return dict(rows=rows_by_width, modes=machines, floating_comparisons=3 * (2048 * 2 + 8), integer_comparisons=3 * len(TYPES) * len(cases) * 2, arithmetic_nan='classification only; finite and zero results bit exact')


def ownership(compiler, out):
	# Reuse the qualified BASELIB observer/provider without altering its semantics.
	sys.path.insert(0, str(ROOT / 'tests/baselib'))
	import importlib.util
	spec = importlib.util.spec_from_file_location('baselib_campaign', ROOT / 'tests/baselib/qualify.py')
	module = importlib.util.module_from_spec(spec)
	# Its sibling oracle has the same module name as this campaign's oracle.
	previous = sys.modules.pop('oracle')
	try:
		spec.loader.exec_module(module)
	finally:
		sys.modules['oracle'] = previous
	target = out / 'ownership'; target.mkdir(exist_ok=True)
	campaign = module.Campaign(compiler, target)
	source = target / 'lifetime.astra'
	text = (ROOT / 'tests/baselib/fixtures/lifetime.astra').read_text()
	text = 'const DIMENSION=2;const RESOURCE_ID=7;const ZERO=0.0d;\n' + text.replace('new f64[2]', 'new f64[DIMENSION]').replace('acquire(7)', 'acquire(RESOURCE_ID)').replace('== 0.0d', '== ZERO')
	source.write_text(text)
	campaign.execute('lifetime', [source, module.BASE[2]], campaign.hosted, module.FIX / 'runtime.vapi', stdout='E7\nE90\nE1\nE2\nE8\nE-90\nE-7\n')
	fatal = target / 'fatal.astra'; fatal.write_text(text.replace('assert(test_mark(1) == 1)', 'assert(test_mark(1) == 0)'))
	campaign.execute('fatal', [fatal, module.BASE[2]], campaign.hosted, module.FIX / 'runtime.vapi', stdout='E7\nE90\nE1\n', stderr='astra base: assertion failure kind=1 code=0\n', fatal=True)
	for i, bad in enumerate(['const Resource X=null;', 'const X=acquire(7);', 'const X=new f64[DIMENSION];']):
		negative = target / f'invalid-{i}.astra'; negative.write_text('const DIMENSION=2;'+bad)
		p = process([compiler, '--check', negative, '--vapi', module.FIX / 'runtime.vapi']); assert p.returncode == 1 and 'unsupported constant' in p.stderr
	return campaign.records['runs']


def installed_consumer(compiler, out):
	build = compiler.parent
	prefix = out / 'install'; run(['meson', 'install', '-C', build, '--no-rebuild', '--destdir', prefix])
	options = {r['name']: r['value'] for r in json.loads((build / 'meson-info/intro-buildoptions.json').read_text())}
	install = prefix / options['prefix'].lstrip('/')
	relocated = out / 'installed-relocated'; shutil.copytree(install, relocated, dirs_exist_ok=True)
	client = out / 'consumer.astra'; shutil.copy2(ROOT / 'examples/base/constants.astra', client)
	for label, directory in [('installed', install), ('relocated', relocated)]:
		lib = directory / options['datadir'] / 'astra'; support = directory / options['libdir'] / 'astra/x86_64-linux'
		# This consumer requires the legacy BASELIB failure interface.
		trap = support / 'failure-trap.o'; assert trap.is_file()
		args = [directory / 'bin/astrac', client, *[lib / 'base' / (n + '.astra') for n in ['order','classify','contracts','clamp']], '--vapi', lib / 'hosted/math.vapi', '--link-object', trap, '--link-library=m', '-o', out / ('consumer-' + label)]
		run(args, cwd=out); assert run([out / ('consumer-' + label)], cwd=out) == ''
	return dict(installed=1, relocated=1, provider=trap.name, link_library='m')


def main(compiler, out):
	out.mkdir(parents=True, exist_ok=True)
	result = dict(composition=composition(compiler,out), expansion=expansion(compiler,out), runtime=runtime(compiler,out), consumer=installed_consumer(compiler,out), ownership=ownership(compiler,out))
	(out / 'qualification.json').write_text(json.dumps(result, indent='\t') + '\n'); print(json.dumps(result, indent='\t'))


if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
