# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Native bit/shift qualification; independent arbitrary-integer expectations."""
from pathlib import Path
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
BASELINE = '10159b5b4d57cbc8f3bb555a0cdc4cfe2f7477d1'
FIXTURES = ['basic', 'signed', 'bool', 'mask', 'shift', 'vector', 'loop', 'integration', 'ownership', 'values']
TYPES = {'i8': (8, True), 'u8': (8, False), 'i16': (16, True), 'u16': (16, False), 'i32': (32, True), 'u32': (32, False)}


def bindings():
	return [arg for name in ['types', 'api'] for arg in ['--vapi', ROOT / f'tests/resource/fixtures/resource-{name}.vapi']]


def run(argv, expected=0):
	r = subprocess.run(list(map(str, argv)), cwd=ROOT, capture_output=True, text=True)
	assert r.returncode == expected and r.stdout == r.stderr == '', (argv, r)


def mathematical(bits, name):
	w, signed = TYPES[name]
	bits %= 2**w
	return bits - 2**w if signed and bits >= 2**(w - 1) else bits


def patterns(w):
	return [0, 1, 2**w - 1, 2**(w - 1), 2**(w - 1) - 1, (2**w - 1)//3, (2**w - 1)//3*2, 2**w - 2]


def program(functions, checks):
	lines = list(functions)
	for i, body in enumerate(checks):
		lines += [f'bool check{i}(){{', *['\t' + line for line in body], '\treturn true;', '}']
	for start in range(0, len(checks), 16):
		lines += [f'bool group{start}(){{', *[f'\tif(!check{i}()){{return false;}}' for i in range(start, min(start + 16, len(checks)))], '\treturn true;', '}']
	lines += ['int main(){', *[f'\tif(!group{start}()){{return 1;}}' for start in range(0, len(checks), 16)], '\treturn 0;', '}']
	return '\n'.join(lines) + '\n'


def exhaustive():
	functions = ['int band(int x,int y){int a=x;int b=y;int r=0;int p=1;int i=0;while(i<8){if(a%2==1 && b%2==1){r=r+p;}a=a/2;b=b/2;p=p*2;i=i+1;}return r;}']
	checks = []
	for t in ['i8', 'u8']:
		functions += [f'{t} and_{t}({t} a,{t} b){{return a&b;}}', f'{t} or_{t}({t} a,{t} b){{return a|b;}}', f'{t} xor_{t}({t} a,{t} b){{return a^b;}}', f'{t} not_{t}({t} a){{return ~a;}}', f'{t} left_{t}({t} a,int c){{return a<<c;}}', f'{t} right_{t}({t} a,int c){{return a>>c;}}']
		checks.append(['int x=0;', 'while(x<256){', '\tint y=0;', '\twhile(y<256){', '\t\tint both=band(x,y);', f'\t\t{t} a=x as {t};', f'\t\t{t} b=y as {t};', f'\t\tif(and_{t}(a,b)!=(both as {t}) || or_{t}(a,b)!=((x+y-both) as {t}) || xor_{t}(a,b)!=((x+y-2*both) as {t})){{return false;}}', '\t\ty=y+1;', '\t}', f'\t{t} a=x as {t};', f'\tif(not_{t}(a)!=((255-x) as {t})){{return false;}}', '\tint c=0;', '\tint p=1;', '\twhile(c<8){', '\t\tint v=x;', *(['\t\tif(v>=128){v=v-256;}'] if t=='i8' else []), '\t\tint expected=v/p;', '\t\tif(v<0 && v%p!=0){expected=expected-1;}', f'\t\tif(left_{t}(a,c)!=((x*p) as {t}) || right_{t}(a,c)!=(expected as {t})){{return false;}}', '\t\tc=c+1;', '\t\tp=p*2;', '\t}', '\tx=x+1;', '}'])
	return program(functions, checks), {'binary_results': 393216, 'complements': 512, 'shift_results': 8192}


def matrices():
	functions = {}
	checks = []
	counts = {'scalar_binary': 0, 'scalar_shift': 0, 'vector_results': 0, 'vector_lanes': 0}
	for t, (w, signed) in TYPES.items():
		for op, symbol in [('and','&'),('or','|'),('xor','^')]:
			functions[t+op] = f'{t} {op}_{t}({t} a,{t} b){{return a{symbol}b;}}'
		for a in patterns(w):
			for b in patterns(w):
				checks.append([f'if(and_{t}({mathematical(a,t)},{mathematical(b,t)})!={mathematical(a&b,t)} || or_{t}({mathematical(a,t)},{mathematical(b,t)})!={mathematical(a|b,t)} || xor_{t}({mathematical(a,t)},{mathematical(b,t)})!={mathematical(a^b,t)}){{return false;}}'])
				counts['scalar_binary'] += 3
		for ct in TYPES:
			name = t+'_'+ct
			functions[name] = f'{t} left_{name}({t} a,{ct} c){{return a<<c;}}\n{t} right_{name}({t} a,{ct} c){{return a>>c;}}'
			for a in patterns(w):
				for c in [0, 1, w//2, w-1]:
					v = mathematical(a,t)
					checks.append([f'if(left_{name}({v},{c})!={mathematical(a*2**c,t)} || right_{name}({v},{c})!={v//2**c}){{return false;}}'])
					counts['scalar_shift'] += 2
					# Every supported shape, all integer categories, scalar counts of every
					# exact type; one function boundary and one whole-vector result per op.
		for n in [2,4,8,16]:
			if n*w>128:
				continue
			vtype = f'{t}<{n}>'
			for ct in TYPES:
				name = t+str(n)+'_'+ct
				functions['v'+name] = f'{vtype} vl_{name}({vtype} a,{ct} c){{return a<<c;}}\n{vtype} vr_{name}({vtype} a,{ct} c){{return a>>c;}}'
				for c in [0,1,w-1]:
					a = [patterns(w)[i%8] for i in range(n)]
					b = [patterns(w)[(i+3)%8] for i in range(n)]
					vec = lambda x: '{'+','.join(str(mathematical(y,t)) for y in x)+'}'
					body = [f'{vtype} a={vec(a)};', f'{vtype} b={vec(b)};', f'{vtype} l={vec([x*2**c for x in a])};', f'{vtype} r={vec([mathematical(x,t)//2**c for x in a])};', f'{vtype} both={vec([x&y for x,y in zip(a,b)])};', f'{vtype} either={vec([x|y for x,y in zip(a,b)])};', f'{vtype} different={vec([x^y for x,y in zip(a,b)])};', f'{vtype} complement={vec([2**w-1-x for x in a])};', f'if(!all(vl_{name}(a,{c})==l) || !all(vr_{name}(a,{c})==r)){{return false;}}', 'if(!all((a&b)==both) || !all((a|b)==either) || !all((a^b)==different) || !all(~a==complement)){return false;}']
					checks.append(body)
					counts['vector_results'] += 6
					counts['vector_lanes'] += n*6
	return program(functions.values(), checks), counts


def main(compiler, companion, out):
	out.mkdir(parents=True, exist_ok=True)
	results = {'fixtures': len(FIXTURES)}
	for name in FIXTURES:
		source = ROOT / f'tests/bit/fixtures/bit-{name}.astra'
		options = [*bindings(), '--link-object', companion] if name=='ownership' else []
		run([compiler, source, *options, '-o', out/name])
		run([out/name])
	for name, (source, counts) in {'exhaustive': exhaustive(), 'matrices': matrices()}.items():
		path = out/(name+'.astra')
		path.write_text(source)
		run([compiler, path, '-o', out/name])
		run([out/name])
		results[name] = counts
	traps = []
	for t, (w, signed) in TYPES.items():
		for vector in [False,True]:
			vt = f'{t}<{128//w}>' if vector else t
			for ct, c in [('int',-1),('int',w),('u32',4294967295)]:
				for symbol, tag in [('<<','left'),('>>','right')]:
					name = f'trap-{t}-{vector}-{ct}-{c}-{tag}'
					source = out/(name+'.astra')
					source.write_text(f'{vt} shifted({vt} a,{ct} c){{return a{symbol}c;}}\nint main(){{{vt} a='+ (f'splat(1,{128//w})' if vector else '1')+f';{vt} r=shifted(a,{c});return 0;}}\n')
					run([compiler, source, '-o', out/name])
					r = subprocess.run([out/name], capture_output=True)
					assert r.returncode < 0 and r.stdout == r.stderr == b'', (name,r)
					traps.append(name)
					# Prove both operands ran, in order, before the invalid operation traps:
					# foreign putchar/fflush expose effects even under non-unwinding trap.
	for vector in [False,True]:
		t = 'i8<16>' if vector else 'i8'
		name = 'trap-effects-vector' if vector else 'trap-effects-scalar'
		source = out/(name+'.astra')
		source.write_text('extern(C) int putchar(int c);extern(C) int fflush(void* p);\n'+f'{t} value(){{putchar(65);fflush(null);return '+('splat(-3,16)' if vector else '-3')+';}\nint count(){putchar(66);fflush(null);return -1;}\n'+f'int main(){{{t} r=value()<<count();putchar(67);return 0;}}\n')
		run([compiler, source, '-o', out/name])
		r = subprocess.run([out/name], capture_output=True)
		assert r.returncode < 0 and r.stdout == b'AB' and r.stderr == b'', r
		traps.append(name)
	results['dynamic_traps'] = traps
	(out/'results.json').write_text(json.dumps(results,indent='\t')+'\n')
	print(json.dumps(results),flush=True)


if __name__=='__main__':
	main(Path(sys.argv[1]).resolve(),Path(sys.argv[2]).resolve(),Path(sys.argv[3]).resolve())
