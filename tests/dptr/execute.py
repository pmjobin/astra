# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Native scalar storage, aliasing, special values, and non-unwinding traps."""
from pathlib import Path
import json
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
BASELINE = '92de911f9655fc06ce7057b6f0a07429e85915ea'
FIXTURES = ['basic', 'alias', 'call', 'null', 'f32', 'loop', 'borrow', 'integration', 'ownership', 'widths']
TYPES = {'i8': (8, True), 'u8': (8, False), 'i16': (16, True), 'u16': (16, False), 'int': (32, True), 'u32': (32, False)}


def bindings():
	return [arg for name in ['types', 'api'] for arg in ['--vapi', ROOT / f'tests/resource/fixtures/resource-{name}.vapi']]


def run(argv, expected=0, output=''):
	r = subprocess.run(list(map(str, argv)), cwd=ROOT, capture_output=True, text=True)
	assert r.returncode == expected and r.stdout == output and r.stderr == '', (argv, r)


def matrices():
	functions = []
	checks = []
	count = 0
	for t, (width, signed) in TYPES.items():
		functions += [f'void write_{t}({t}* p,{t} v){{*p=v;}}', f'{t} read_{t}({t}* p){{return *p;}}', f'void alias_{t}({t}* p,{t}* q,{t} v){{*p=v;*q=*p;}}']
		patterns = list(range(256)) if width == 8 else [0, 1, 2**width-1, 2**(width-1), 2**(width-1)-1, (2**width-1)//3, (2**width-1)//3*2, 2**width-2]
		# Keep each verifier graph bounded while exercising every 8-bit pattern.
		for start in range(0, len(patterns), 8):
			lines = [f'bool check_{t}_{start}(){{', f'\t{t} x=0;', f'\t{t}* p=&x;', f'\t{t}* q=p;']
			for bits in patterns[start:start+8]:
				value = bits-2**width if signed and bits >= 2**(width-1) else bits
				lines += [f'\twrite_{t}(p,{value});', f'\tif(x!={value} || *q!={value}){{return false;}}', '\tx=0;', f'\tif(read_{t}(q)!=0){{return false;}}', f'\tx={value};', f'\tif(read_{t}(p)!={value}){{return false;}}', f'\talias_{t}(p,q,{value});', f'\tif(x!={value}){{return false;}}']
				count += 5
			lines += ['\treturn true;', '}']
			functions += lines
			checks.append(f'\tif(!check_{t}_{start}()){{return 1;}}')
	return '\n'.join([*functions, 'int main(){', *checks, '\treturn 0;', '}'])+'\n', count


def main(compiler, companion, out):
	out.mkdir(parents=True, exist_ok=True)
	results = {'fixtures': len(FIXTURES), 'traps': [], 'flagships': {}}
	for name in FIXTURES:
		options = [*bindings(), '--link-object', companion] if name == 'ownership' else []
		run([compiler, ROOT/f'tests/dptr/fixtures/dptr-{name}.astra', *options, '-o', out/name])
		run([out/name])
	flagships = {
		'pointer-to-direct': ('int main(){int x=1;int* p=&x;*p=2;return x;}', 2),
		'direct-to-pointer': ('int main(){int x=1;int* p=&x;x=3;return *p;}', 3),
		'aliases-42': ('int main(){int x=0;int* p=&x;int* q=&x;*p=12;*q=*q+30;return x;}', 42),
		'call-42': ('void increment(int* p){*p=*p+1;} int main(){int x=41;increment(&x);return x;}', 42),
		'double-alias-42': ('void modify(int* a,int* b){*a=12;*b=*b+30;} int main(){int x=0;modify(&x,&x);return x;}', 42),
	}
	for name, (source, expected) in flagships.items():
		path = out/(name+'.astra')
		path.write_text(source+'\n')
		run([compiler, path, '-o', out/name])
		run([out/name], expected)
		results['flagships'][name] = expected
	source, count = matrices()
	(out/'matrices.astra').write_text(source)
	run([compiler, out/'matrices.astra', '-o', out/'matrices'])
	run([out/'matrices'])
	results['exact_memory_checks'] = count
	for t in [*TYPES, 'f32']:
		one = '1.0' if t == 'f32' else '1'
		for operation in ['read', 'write']:
			name = f'trap-{t}-{operation}'
			body = f'{t} value=*p;' if operation == 'read' else f'*p={one};'
			path = out/(name+'.astra')
			path.write_text(f'void access({t}* p){{{body}}} int main(){{access(null);return 0;}}\n')
			run([compiler, path, '-o', out/name])
			run([out/name], -signal.SIGILL)
			results['traps'].append(name)
			# A null store evaluates its RHS, then traps before any store or later effect.
	source = 'extern(C) int putchar(int c);extern(C) int fflush(void* p);\nint effect(){putchar(65);fflush(null);return 1;} int main(){int* p=null;*p=effect();putchar(66);fflush(null);return 0;}\n'
	(out/'trap-effects.astra').write_text(source)
	run([compiler, out/'trap-effects.astra', '-o', out/'trap-effects'])
	run([out/'trap-effects'], -signal.SIGILL, 'A')
	results['traps'].append('trap-effects')
	# & is eager boolean composition even when its left side tests a null pointer.
	source = 'bool effect(int* out){*out=*out+1;return true;} int main(){int x=0;int* p=null;bool a=(p!=null)&effect(&x);if(a || x!=1){return 1;}bool b=(p!=null)&&effect(&x);if(b || x!=1){return 2;}return 0;}\n'
	(out/'eager-bool.astra').write_text(source)
	run([compiler, out/'eager-bool.astra', '-o', out/'eager-bool'])
	run([out/'eager-bool'])
	(out/'results.json').write_text(json.dumps(results, indent='\t')+'\n')
	print(json.dumps(results), flush=True)


if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve(), Path(sys.argv[3]).resolve())
