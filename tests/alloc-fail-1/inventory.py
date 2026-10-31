# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""All admitted elements, independent leaf/layout oracles, both allocation producers."""
from pathlib import Path
import hashlib
import importlib.util
import json
import os
import re
import resource
import signal
import subprocess
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('elements', ROOT / 'tests/struct-elem-1/execute.py')
elements = importlib.util.module_from_spec(spec)
spec.loader.exec_module(elements)


def source():
	parts = [elements.IMPORTS, '''extern(C) int inv_case();extern(C) int inv_mode();
void inventory_report(int code,int n){se_mark(10000+code);se_mark(n);}
void inventory_check(bool value){if(!value){se_mark(999);}}
owned T[] inventory_make<T>(int n,int code){return new T[n] else inventory_report(se_mark(code),se_mark(n));}
struct Box<T>{T value;}
''']
	shapes = []
	for index, leaf in enumerate(elements.LEAVES):
		base = leaf.split('<')[0]
		lanes = int(leaf.split('<')[1][:-1]) if '<' in leaf else 1
		info = elements.layout(leaf)
		parts.append(f'struct R{index}{{u8 before;{leaf} value;u8 after;}}')
		for name, stride, path, extra in [(leaf, info['size'], '', ''), (f'R{index}', info['stride'], '.value', 'a[i].before==0&&a[i].after==0&&'), (f'Box<R{index}>', info['stride'], '.value.value', 'a[i].value.before==0&&a[i].value.after==0&&')]:
			shapes.append(dict(name=name, element=leaf, stride=stride, base=base, lanes=lanes, path=path, extra=extra))
	parts.append('struct Leaf{int x;f64 y;}')
	for i in range(64):
		parts.append(f'struct D{i}{{' + ('Leaf' if i == 0 else f'D{i-1}') + ' child;}')
	shapes.append(dict(name='D63', stride=16, leaves=[('.' + 'child.' * 64 + 'x', 'int'), ('.' + 'child.' * 64 + 'y', 'f64')]))
	parts.append('struct Large{' + ''.join(f'int f{i};' for i in range(256)) + '}')
	shapes.append(dict(name='Large', stride=1024, leaves=[(f'.f{i}', 'int') for i in range(256)]))
	parts.append('struct Pair{Leaf a;Leaf b;}struct Shared{Pair a;Pair b;}')
	shapes.append(dict(name='Shared', stride=64, leaves=[(f'.{a}.{b}.{c}', t) for a in 'ab' for b in 'ab' for c, t in [('x', 'int'), ('y', 'f64')]]))
	for index, shape in enumerate(shapes):
		name, stride = shape['name'], shape['stride']
		parts.append(f'owned {name}[] concrete{index}(int n,int code){{return new {name}[n] else inventory_report(se_mark(code),se_mark(n));}}')
		leaves = shape.get('leaves')
		# Vectors embedded in records still select each packed/numeric lane.
		if 'lanes' in shape:
			leaves = [(shape['path'] + (f'[{i}]' if shape['lanes'] > 1 else ''), shape['base']) for i in range(shape['lanes'])]
		zero = ('inventory_check(' + shape['extra'][:-2] + ');' if shape.get('extra') else '') + ''.join('inventory_check(' + elements.scalar_check(t, 'a[i]' + p) + ');' for p, t in leaves)
		writes = ''.join(f'a[n-1]{p}={elements.scalar_value(t, "pattern")};' for p, t in leaves)
		reset = ''.join(f'a[n-1]{p}={"false" if t == "bool" else "null" if t == "void*" else "0.0f" if t == "f32" else "0.0d" if t == "f64" else "0"};' for p, t in leaves)
		if shape.get('lanes', 1) > 1:
			values = ','.join(elements.scalar_value(shape['base'], 'pattern') for _ in range(shape['lanes']))
			zeros = ','.join('false' if shape['base'] == 'bool' else '0.0f' if shape['base'] == 'f32' else '0' for _ in range(shape['lanes']))
			writes = f'{shape["element"]} pattern_value={{{values}}};{shape["element"]} zero_value={{{zeros}}};a[n-1]{shape["path"]}=pattern_value;'
			reset = f'a[n-1]{shape["path"]}=zero_value;'
		checks = ''.join('inventory_check(' + elements.scalar_check(t, 'saved' + p, 'pattern') + ');' for p, t in leaves)
		for generic in [False, True]:
			ordinal = 2 * index + int(generic)
			producer = f'inventory_make<{name}>' if generic else f'concrete{index}'
			parts.append(f'''int case{ordinal}(int mode){{
	int n=0;if(mode==1){{n=17;}}if(mode==2){{n=2;se_fail();}}if(mode==3){{n=se_mark(-1);}}
	se_expect({stride});var a={producer}(n,{ordinal});if(len(a)!=n){{return 1;}}
	int i=0;while(i<n){{{zero}i=i+1;}}
	if(n>0){{int pattern=0;while(pattern<12){{{writes}var saved=a[n-1];{reset}{checks}a[0]=saved;var independent=a[0];{reset}{checks.replace('saved', 'independent').replace('return 3', 'return 4')}pattern=pattern+1;}}}}
	return 0;
}}''')
	parts.append('int main(){int selected=inv_case();int mode=inv_mode();' + ''.join(f'if(selected=={i}){{return case{i}(mode);}}' for i in range(2 * len(shapes))) + 'return 99;}')
	return '\n'.join(parts) + '\n', shapes


def qualify(compiler, out):
	out.mkdir(parents=True, exist_ok=False)
	(out / 'tmp').mkdir()
	os.environ['TMPDIR'] = str(out / 'tmp')
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	env = dict(os.environ, TMPDIR=str(out / 'tmp'), CCACHE_DISABLE='1')
	commands = []
	def run(argv, label, status=0, expected=None, selection=None, mode=None):
		p = subprocess.run(list(map(str, argv)), cwd=out, env=env | ({} if selection is None else {'INVENTORY_CASE': str(selection), 'INVENTORY_MODE': str(mode)}), capture_output=True)
		commands.append(dict(label=label, status=p.returncode, argv=list(map(str, argv)), case=selection, mode=mode, stdout=p.stdout.decode(), stderr=p.stderr.decode()))
		assert p.returncode == status and not p.stderr and (expected is None or p.stdout == expected), commands[-1]
		return p.stdout
	try:
		program, shapes = source()
		(out / 'inventory.astra').write_text(program)
		elements.c_layouts(out, [elements.layout(leaf) for leaf in elements.LEAVES])
		(out / 'selection.c').write_text('#include <stdlib.h>\n#include <stdint.h>\nint32_t inv_case(void){return (int32_t)strtol(getenv("INVENTORY_CASE"),0,10);}\nint32_t inv_mode(void){return (int32_t)strtol(getenv("INVENTORY_MODE"),0,10);}\n')
		observers = {}
		for cc in ['gcc', 'clang']:
			observers[cc] = [cc + '-observer.o', cc + '-selection.o']
			for inp, obj in [(ROOT / 'tests/struct-elem-1/companion.c', observers[cc][0]), ('selection.c', observers[cc][1])]:
				run([cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', inp, '-o', obj], obj)
		dumps = {}
		for stage in elements.STAGES:
			dumps[stage] = run([compiler, '--dump-' + stage, 'inventory.astra'], stage).decode()
			(out / ('inventory.' + stage)).write_text(dumps[stage])
		ordinal = re.search(r'\(function #(\d+) "main" -> int', dumps['ssa'])[1]
		wrapped = dumps['llvm'] + '\ndefine i32 @main(){\n\t%r=call fastcc i32 @astra.fn.' + ordinal + '()\n\tret i32 %r\n}\n'
		executions = 0
		for optimization in ['O0', 'O2', 'O2-fma', 'preserved-O2']:
			ir = re.sub(r'^define internal fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', wrapped, flags=re.M) if optimization == 'preserved-O2' else wrapped
			(out / (optimization + '-input.ll')).write_text(ir)
			run(['opt', '-passes=verify' if optimization == 'O0' else '-passes=default<O2>', '-S', optimization + '-input.ll', '-o', optimization + '.ll'], optimization + '-opt')
			run(['opt', '-passes=verify', '-disable-output', optimization + '.ll'], optimization + '-verify')
			run(['llc', '-O0' if optimization == 'O0' else '-O2', '-filetype=obj', '-relocation-model=pic', *(['-mattr=+fma'] if optimization == 'O2-fma' else []), optimization + '.ll', '-o', optimization + '.o'], optimization + '-llc')
			for cc, objects in observers.items():
				binary = out / (optimization + '-' + cc)
				run([cc, optimization + '.o', *objects, '-Wl,--wrap=calloc,--wrap=free', '-o', binary], binary.name + '-link')
				for index, shape in enumerate(shapes):
					for generic in [False, True]:
						case = 2 * index + int(generic)
						for mode in range(4):
							expected = ['', f'A1:17:{shape["stride"]}\nF1\n', f'OOM\nM{case}\nM2\nM{10000+case}\nM2\n', 'M-1\n'][mode].encode()
							run([binary], binary.name, -signal.SIGILL if mode >= 2 else 0, expected, case, mode)
							executions += 1
			for suffix, args in [('machine', ['objdump', '-dr']), ('symbols', ['nm', '-u']), ('size', ['size', '-A'])]:
				(out / (optimization + '.' + suffix)).write_bytes(run([*args, optimization + '.o'], optimization + '-' + suffix))
		(out / 'result.json').write_text(json.dumps(dict(compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(), shapes=shapes, executions=executions, scalar_types=10, vector_mask_shapes=24, padding_compared=False), indent='\t') + '\n')
	finally:
		# Large canonical stages have their own files; do not duplicate them here.
		for row in commands:
			if row['label'] in elements.STAGES:
				row['stdout_sha256'] = hashlib.sha256(row.pop('stdout').encode()).hexdigest()
		(out / 'commands.json').write_text(json.dumps(commands, indent='\t') + '\n')
	print(f'{executions} concrete/generic element executions; independent value, zero and stride checks')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
