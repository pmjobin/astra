# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Whole-vector value roundtrips through generic typed memory on x86-64 Linux."""
from pathlib import Path
import json
import random
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
BASELINE = '77acb61b2107afb20946f0fb5dc152540836ad44'
FIXTURES = ['basic', 'alias', 'call', 'null', 'f32', 'loop', 'borrow', 'lanes', 'dsp', 'dot', 'ownership', 'widths']
TYPES = {'i8': (8, True), 'u8': (8, False), 'i16': (16, True), 'u16': (16, False), 'int': (32, True), 'u32': (32, False), 'f32': (32, None)}
SHAPES = [(t, n) for t, (bits, _) in TYPES.items() for n in [2, 4, 8, 16] if bits*n <= 128]


def bindings():
	return [arg for name in ['types', 'api'] for arg in ['--vapi', ROOT / f'tests/resource/fixtures/resource-{name}.vapi']]


def run(argv, expected=0, output=''):
	r = subprocess.run(list(map(str, argv)), cwd=ROOT, capture_output=True, text=True)
	assert r.returncode == expected and r.stdout == output and r.stderr == '', (argv, r)


def matrices():
	rng = random.Random(4401)
	functions = []
	checks = []
	count = 0
	for t, n in SHAPES:
		type_name = f'{t}<{n}>'
		name = f'{t}_{n}'
		zero = '0.0' if t == 'f32' else '0'
		functions += [f'void write_{name}({type_name}* p,{type_name} v){{*p=v;}}', f'{type_name} read_{name}({type_name}* p){{return *p;}}', f'void alias_{name}({type_name}* p,{type_name}* q,{type_name} v){{*p=v;*q=*p;}}']
		bits, signed = TYPES[t]
		for k in range(16):
			if t == 'f32':
				patterns = ['0.0','-0.0','1.5','-123.25','1.401298464324817e-45','3.4028234663852886e38','-1.1754943508222875e-38','16777216.0']
				values = [patterns[(k+j) % len(patterns)] for j in range(n)]
			else:
				patterns = [0,1,2**bits-1,2**(bits-1),2**(bits-1)-1,(2**bits-1)//3,(2**bits-1)//3*2,2**bits-2]
				lane_bits = [patterns[(k+j) % len(patterns)] if k < 8 else rng.randrange(2**bits) for j in range(n)]
				values = [str(v-2**bits if signed and v >= 2**(bits-1) else v) for v in lane_bits]
			lines = [f'bool check_{name}_{k}(){{', f'\t{type_name} value={{'+','.join(values)+'};', f'\t{type_name} x=value;', f'\t{type_name}* p=&x;', f'\t{type_name}* q=p;', f'\t{type_name} loaded=*p;', '\tif(!all(loaded==value)){return false;}', f'\tx=splat({zero},{n});', '\t*p=value;', '\tloaded=*p;', '\tif(!all(loaded==value) || !all(x==value)){return false;}', f'\tx=splat({zero},{n});', f'\twrite_{name}(p,value);', '\tif(!all(x==value) || !all(*q==value)){return false;}', f'\tx=splat({zero},{n});', '\tx=value;', f'\tif(!all(read_{name}(q)==value)){{return false;}}', f'\talias_{name}(p,q,value);', '\tif(!all(x==value)){return false;}', '\treturn true;', '}']
			count += 7
			functions += lines
			checks.append(f'\tif(!check_{name}_{k}()){{return 1;}}')
	return '\n'.join([*functions,'int main(){',*checks,'\treturn 0;','}'])+'\n', count


def main(compiler, companion, out):
	out.mkdir(parents=True, exist_ok=True)
	results = {'fixtures': len(FIXTURES), 'shapes': [f'{t}<{n}>' for t,n in SHAPES], 'traps': []}
	for name in FIXTURES:
		options = [*bindings(),'--link-object',companion] if name == 'ownership' else []
		run([compiler,ROOT/f'tests/vec-mem/fixtures/vecmem-{name}.astra',*options,'-o',out/name])
		run([out/name])
	source, count = matrices()
	(out/'matrices.astra').write_text(source)
	run([compiler,out/'matrices.astra','-o',out/'matrices'])
	run([out/'matrices'])
	results['exact_vector_value_checks'] = count
	for t, n in SHAPES:
		one = '1.0' if t == 'f32' else '1'
		for operation in ['read','write']:
			name = f'trap-{t}-{n}-{operation}'
			body = f'{t}<{n}> value=*p;' if operation == 'read' else f'*p=splat({one},{n});'
			path = out/(name+'.astra')
			path.write_text(f'void access({t}<{n}>* p){{{body}}} int main(){{access(null);return 0;}}\n')
			run([compiler,path,'-o',out/name])
			run([out/name], -signal.SIGILL)
			results['traps'].append(name)
	source = 'extern(C) int putchar(int c);extern(C) int fflush(void* p);\ni16<8> effect(){putchar(65);fflush(null);return splat(1,8);} int main(){i16<8>* p=null;*p=effect();putchar(66);fflush(null);return 0;}\n'
	(out/'trap-effects.astra').write_text(source)
	run([compiler,out/'trap-effects.astra','-o',out/'trap-effects'])
	run([out/'trap-effects'], -signal.SIGILL, 'A')
	results['traps'].append('trap-effects')
	(out/'results.json').write_text(json.dumps(results,indent='\t')+'\n')
	print(json.dumps(results),flush=True)


if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(),Path(sys.argv[2]).resolve(),Path(sys.argv[3]).resolve())
