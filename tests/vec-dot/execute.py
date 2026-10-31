# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Native dot/MAC comparisons with independent exact test authorities."""
from pathlib import Path
import json
import subprocess
import sys

sys.dont_write_bytecode = True
from oracle import TYPES, ROOT, f32_cases, f32_dot, integer_cases, integer_dot, integer_value, is_nan, literal, SIGN

FIXTURES = ['int-basic', 'int-wrap', 'int-signedness', 'int-mac', 'f32-basic', 'f32-order', 'f32-mac', 'f32-special', 'loop', 'native', 'order', 'ownership', 'values']


def bindings():
	return [arg for name in ['types', 'api'] for arg in ['--vapi', ROOT / f'tests/resource/fixtures/resource-{name}.vapi']]


def run(argv):
	result = subprocess.run([str(arg) for arg in argv], cwd=ROOT, capture_output=True, text=True)
	assert result.returncode == 0 and result.stdout == result.stderr == '', (argv, result)


def program(functions, checks):
	lines = list(functions)
	for i, body in enumerate(checks):
		lines.extend([f'bool check{i}(){{', *['\t' + line for line in body], '\treturn true;', '}'])
	for start in range(0, len(checks), 16):
		lines.append(f'bool group{start}(){{')
		for i in range(start, min(start + 16, len(checks))):
			lines.append(f'\tif(!check{i}()){{return false;}}')
		lines.extend(['\treturn true;', '}'])
	lines += ['int main(){']
	for start in range(0, len(checks), 16):
		lines.append(f'\tif(!group{start}()){{return 1;}}')
	lines += ['\treturn 0;', '}']
	return '\n'.join(lines) + '\n'


def integer_matrix():
	functions = {}
	checks = []
	for source, dest, a, b, c in integer_cases():
		n = len(a)
		v = f'{source}<{n}>'
		name = f'{source}_{n}_{dest}'
		functions[name] = f'{dest} d_{name}({v} a,{v} b){{return dot_wrap(a,b,{dest});}}\n{dest} m_{name}({dest} c,{v} a,{v} b){{return mac_wrap(c,a,b);}}'
		av, bv = ['{' + ','.join(str(integer_value(x, source)) for x in vector) + '}' for vector in [a, b]]
		dot = integer_value(integer_dot(a, b, source, dest), dest)
		mac = integer_value(integer_dot(a, b, source, dest, c), dest)
		perm = ','.join(str(i) for i in reversed(range(n)))
		checks.append([f'{v} a={av};', f'{v} b={bv};', f'if(d_{name}(a,b)!={dot}){{return false;}}', f'if(m_{name}({integer_value(c, dest)},a,b)!={mac}){{return false;}}', f'if(m_{name}(0,a,b)!={dot}){{return false;}}', f'if(d_{name}(shuffle(a,{perm}),shuffle(b,{perm}))!={dot}){{return false;}}'])
	return program(functions.values(), checks), {'rows': len(checks), 'checks': len(checks) * 4, 'signatures': len(functions) * 2}


def f32_check(expression, expected, name):
	lines = [f'f32 {name}={expression};']
	if is_nan(expected):
		lines.append(f'if({name}=={name}){{return false;}}')
	else:
		lines.append(f'if({name}!={literal(expected)}){{return false;}}')
		if expected & 0x7fffffff == 0:
			lines.append(f'if(1.0/{name}!={"-" if expected & SIGN else ""}1e100){{return false;}}')
	return lines


def f32_matrix():
	functions = [f'f32 d{n}(f32<{n}> a,f32<{n}> b){{return dot(a,b);}}\nf32 m{n}(f32 c,f32<{n}> a,f32<{n}> b){{return mac(c,a,b);}}' for n in [2, 4]]
	checks = []
	for a, b, c in f32_cases():
		n = len(a)
		body = [f'f32<{n}> a={{' + ','.join(map(literal, a)) + '};', f'f32<{n}> b={{' + ','.join(map(literal, b)) + '};']
		body += f32_check(f'd{n}(a,b)', f32_dot(a, b), 'd')
		body += f32_check(f'm{n}({literal(c)},a,b)', f32_dot(a, b, c), 'm')
		checks.append(body)
		# Loop recurrence uses the same exact scalar authority at every round.
	for n in [2, 4]:
		functions.append(f'f32 loop{n}(int count,f32 initial,f32<{n}> a,f32<{n}> b){{int i=0;f32 c=initial;while(i<count){{c=mac(c,a,b);i=i+1;}}return c;}}')
		for count in [0, 1, 2, 7, 31]:
			a = [0x3f800001, 0xbf800000] + ([0x4b800000, 0xcb800000] if n == 4 else [])
			b = [0x3f7ffffe, 0x3f800000] + ([0x3f800000, 0x3f800000] if n == 4 else [])
			c = 1
			for _ in range(count):
				c = f32_dot(a, b, c)
			checks.append([f'f32<{n}> a={{' + ','.join(map(literal, a)) + '};', f'f32<{n}> b={{' + ','.join(map(literal, b)) + '};', *f32_check(f'loop{n}({count},{literal(1)},a,b)', c, 'r')])
	return program(functions, checks), {'rows': len(checks), 'exact_comparisons': sum(sum('if(' in line for line in body) for body in checks), 'shapes': [2, 4], 'loop_rows': 10}


def exhaustive_products():
	functions = []
	checks = []
	for source in ['i8', 'u8']:
		for dest in TYPES:
			name = source + '_' + dest
			functions += [f'{dest} d_{name}({source}<2> a,{source}<2> b){{return dot_wrap(a,b,{dest});}}']
			# The accepted scalar int authority holds every 8-bit mathematical
			# product exactly; this loop never overflows or uses host dot.
			checks.append(['int x=0;', 'while(x<256){', '\tint y=0;', '\twhile(y<256){', '\t\tint a=x;', '\t\tint b=y;', *(['\t\tif(a>=128){a=a-256;}', '\t\tif(b>=128){b=b-256;}'] if source == 'i8' else []), f'\t\t{source}<2> va={{a as {source},0}};', f'\t\t{source}<2> vb={{b as {source},0}};', f'\t\tif(d_{name}(va,vb)!=((a*b) as {dest})){{return false;}}', '\t\ty=y+1;', '\t}', '\tx=x+1;', '}'])
	return program(functions, checks)


def main(compiler, companion, out):
	out.mkdir(parents=True, exist_ok=True)
	for name in FIXTURES:
		source = ROOT / f'tests/vec-dot/fixtures/dot-{name}.astra'
		options = [*bindings(), '--link-object', companion] if name == 'ownership' else []
		run([compiler, source, *options, '-o', out / name])
		run([out / name])
	results = {'fixtures': len(FIXTURES)}
	for name, (text, counts) in {'integer-matrix': integer_matrix(), 'f32-matrix': f32_matrix(), 'exhaustive-products': (exhaustive_products(), {'contributions': 2 * 6 * 65536})}.items():
		source = out / (name + '.astra')
		source.write_text(text)
		run([compiler, source, '-o', out / name])
		run([out / name])
		results[name] = counts
		# Integer operand division traps precede a later aborting effect. F32
		# expressions also accept exact int-producing calls before float vectors.
	traps = {'dot-wrap': 'dot_wrap(splat(1/z,4),splat(effect(),4),int)', 'mac-wrap-acc': 'mac_wrap(1/z,splat(effect(),4),splat(1,4))', 'mac-wrap-a': 'mac_wrap(0,splat(1/z,4),splat(effect(),4))', 'dot-f32': 'dot(floats(1/z),floats(effect()))', 'mac-f32-acc': 'mac(number(1/z),floats(effect()),floats(1))', 'mac-f32-a': 'mac(0.0,floats(1/z),floats(effect()))'}
	for name, expression in traps.items():
		source = out / ('trap-' + name + '.astra')
		result_type = 'f32' if 'f32' in name else 'int'
		source.write_text('extern(C) void abort(); int effect(){abort();return 1;} f32<4> floats(int x){return splat(1.0,4);} f32 number(int x){return 1.0;} int main(){int z=0;' + result_type + ' r=' + expression + ';return 0;}\n')
		run([compiler, source, '-o', out / ('trap-' + name)])
		result = subprocess.run([str(out / ('trap-' + name))], capture_output=True)
		assert result.returncode == -4 and result.stdout == result.stderr == b'', (name, result)
	results['trap_order'] = list(traps)
	(out / 'results.json').write_text(json.dumps(results, indent='\t') + '\n')
	print(json.dumps(results), flush=True)


if __name__ == '__main__':
	main(*(Path(arg).resolve() for arg in sys.argv[1:]))
