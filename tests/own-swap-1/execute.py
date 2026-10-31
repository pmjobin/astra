# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Descriptor identity, protected payloads, lifecycle, bits and machine controls."""
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
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
spec = importlib.util.spec_from_file_location('elements', ROOT / 'tests/struct-elem-1/execute.py')
elements = importlib.util.module_from_spec(spec)
spec.loader.exec_module(elements)
IMPORTS = '\n'.join(line for line in elements.IMPORTS.splitlines() if 'se_expect' not in line and 'se_count' not in line) + '\nextern(C) void os_live(int n);\n'
HELPERS = 'owned T[] turn<T>(owned T[] a,owned T[] b){swap(a,b);return move a;}owned T[] outer<T>(owned T[] a,owned T[] b){return turn(move a,move b);}\n'


def run(command, cwd, status=0):
	result = subprocess.run(list(map(str, command)), cwd=cwd, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1', TMPDIR=str(cwd)))
	assert result.returncode == status and not result.stderr, (list(map(str, command)), result.returncode, result.stdout.decode(), result.stderr.decode())
	return result.stdout.decode()


def matrix():
	parts = [IMPORTS, HELPERS, 'struct Box<T>{T value;}']
	for number, leaf in enumerate(elements.LEAVES):
		base = leaf.split('<')[0]
		lanes = int(leaf.split('<')[1][:-1]) if '<' in leaf else 1
		value = '{' + ','.join(elements.scalar_value(base, f'pattern+{i}') for i in range(lanes)) + '}' if '<' in leaf else elements.scalar_value(base, 'pattern')
		def check(name):
			return '&&'.join(elements.scalar_check(base, name + (f'[{i}]' if '<' in leaf else ''), f'pattern+{i}') for i in range(lanes))
		parts.append(f'''struct R{number}{{u8 before;{leaf} value;u8 after;}}
class C{number}{{owned {leaf}[] a;owned {leaf}[] b;init(int n){{this.a=new {leaf}[n];this.b=new {leaf}[n+1];}}void rotate(){{swap(this.a,this.b);}}}}
int matrix{number}(int n){{
	var c=C{number}.init(n);var a=new {leaf}[n];var b=new {leaf}[n+1];
	var r=new R{number}[n];var s=new R{number}[n+1];var box=new Box<R{number}>[n];var other=new Box<R{number}>[n+1];
	var pattern=0;while(pattern<12){{
		{leaf} expected={value};a[0]=expected;c.a[0]=expected;r[0].value=expected;box[0].value.value=expected;
		var saved=r[0];swap(a,b);c.rotate();swap(r,s);swap(box,other);
		if(len(b)!=n||len(c.b)!=n||len(s)!=n||len(other)!=n||!({check('b[0]')}&&{check('c.b[0]')}&&{check('s[0].value')}&&{check('other[0].value.value')}&&{check('saved.value')})){{return 1;}}
		swap(a,b);c.rotate();swap(r,s);swap(box,other);swap(a,a);
		pattern=pattern+1;
	}}
	a=outer(move a,move b);if(len(a)!=n+1){{return 2;}}
	return 0;
}}''')
	parts.append('int main(){' + ''.join(f'if(matrix{i}(1)!=0||matrix{i}(17)!=0){{return {i+1};}}os_live(0);' for i in range(34)) + 'return 0;}')
	return '\n'.join(parts) + '\n'


def instrument(ir):
	lines = ir.splitlines()
	output, regions, i = [], [], 0
	while i < len(lines):
		match = re.fullmatch(r'  (%buffer\.exchange\d+)\.left\.base = load ptr, ptr ([%\w.]+), align 8', lines[i])
		if not match:
			output.append(lines[i]); i += 1; continue
		group = lines[i:i+8]
		assert len(group) == 8 and all(' = load ' in line for line in group[:4]) and all(line.startswith('  store ') for line in group[4:])
		addresses = [re.search(r', ptr ([%\w.]+), align', line)[1] for line in group[:4]]
		stem = match[1]
		for n, component in enumerate(['right.base', 'right.count', 'left.base', 'left.count']):
			assert re.fullmatch(r'  store (ptr|i32) ' + re.escape(stem + '.' + component) + r', ptr ' + re.escape(addresses[n]) + r', align (8|4)', group[4+n]), group
		output.append('  call void @os_before(' + ', '.join('ptr ' + address for address in addresses) + ')')
		output.extend(group); output.append('  call void @os_after()')
		regions.append(dict(ordinal=len(regions), addresses=addresses, instructions=group)); i += 8
	assert regions
	return '\n'.join(output) + '\ndeclare void @os_before(ptr, ptr, ptr, ptr)\ndeclare void @os_after()\n', regions


def trace(text, normal=True):
	live, swaps, allocations = {}, 0, []
	for line in text.splitlines():
		if line.startswith('A'):
			i, n, stride = map(int, line[1:].split(':')); assert i not in live and n > 0 and stride > 0; live[i] = (n, stride); allocations.append((n, stride))
		elif line.startswith('F'):
			assert live.pop(int(line[1:]), None) is not None
		elif line.startswith('X'):
			a, n, b, m = map(int, line[1:].split(':'))
			assert (not a and not n or live[a][0] == n) and (not b and not m or live[b][0] == m)
			swaps += 1
	if normal:
		assert not live, live
	return dict(exchanges=swaps, allocations=len(allocations), extents=sorted(set(allocations)), final_live=live)


def qualify(compiler, out):
	out.mkdir(parents=True, exist_ok=False)
	companions = {}
	for cc in ['gcc', 'clang']:
		companions[cc] = out / (cc + '-observer.o')
		run([cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', ROOT / 'tests/own-swap-1/observer.c', '-o', companions[cc]], out)
	(out / 'matrix.astra').write_text(matrix())
	deep = elements.deep(64).replace('var saved=a[1];', 'var b=new D63[3];swap(a,b);swap(b,a);var saved=a[1];')
	(out / 'deep-64.astra').write_text(deep)
	large = 'struct Large{' + ''.join(f'int f{i};' for i in range(256)) + '}int main(){var a=new Large[1];var b=new Large[16387];swap(a,b);swap(a,b);return 0;}\n'
	(out / 'large.astra').write_text(large)
	graph = 'struct Leaf{int x;f64 y;}struct Pair{Leaf a;Leaf b;}struct Graph{Pair a;Pair b;}int main(){var a=new Graph[2];var b=new Graph[3];a[0].a.a.x=17;swap(a,b);if(b[0].a.a.x!=17){return 1;}return 0;}\n'
	(out / 'shared-graph.astra').write_text(graph)
	for name in ['slots', 'snapshot']:
		(out / (name + '.astra')).write_bytes((ROOT / 'tests/own-swap-1/fixtures' / (name + '.astra')).read_bytes())
	lifecycle = IMPORTS + '''class C{owned int[] a;owned int[] b;init(){this.a=new int[2];this.b=new int[3];}deinit(){se_mark(90);swap(this.a,this.b);}}
owned int[] parameter(owned int[] a,owned int[] b){swap(a,b);var local=new int[4];swap(local,a);release b;b=new int[5];swap(a,b);return move a;}
int main(){var c=C.init();{var local=new int[7];swap(local,c.a);se_mark(1);}se_mark(2);var a=new int[11];var b=new int[13];a=parameter(move a,move b);release a;a=new int[17];swap(a,c.b);a=new int[19];se_mark(3);return 0;}
'''
	(out / 'lifecycle.astra').write_text(lifecycle)
	(out / 'later-oom.astra').write_text(IMPORTS + 'int main(){var a=new int[2];var b=new int[3];swap(a,b);se_fail();a=new int[5];return 0;}\n')
	(out / 'field-oom.astra').write_text(IMPORTS + 'void report(int count){se_mark(count);}class C{owned int[] a;owned int[] b;init(){this.a=new int[2];this.b=new int[3];}}int main(){var c=C.init();swap(c.a,c.b);se_fail();c.a=new int[5] else report(len(c.a));return 0;}\n')
	elements.c_layouts(out, [elements.layout(leaf) for leaf in elements.LEAVES])
	records = dict(status='INCOMPLETE', compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(), shapes=elements.LEAVES, runs=[], regions={})
	for name in ['matrix', 'deep-64', 'large', 'shared-graph', 'slots', 'snapshot', 'lifecycle', 'later-oom', 'field-oom']:
		dumps = {}
		for stage in ['instances', 'ssa', 'llvm']:
			command = [compiler, '--dump-' + stage, name + '.astra']
			dumps[stage] = run(command, out); (out / (name + '.' + stage)).write_text(dumps[stage]); assert run(command, out) == dumps[stage]
		ordinal = re.search(r'\(function #(\d+) "main" -> int', dumps['ssa'])[1]
		ir, regions = instrument(dumps['llvm']); records['regions'][name] = regions
		ir += '\ndefine i32 @main(){\n\t%r=call fastcc i32 @astra.fn.' + ordinal + '()\n\tret i32 %r\n}\n'
		status = -signal.SIGILL if name in ['later-oom', 'field-oom'] else 0
		canonical = None
		for mode in ['O0', 'O2', 'O2-fma', 'preserved-O2']:
			stem = name + '-' + mode
			wrapped = re.sub(r'^define internal fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', ir, flags=re.M) if mode == 'preserved-O2' else ir
			inp, optimized, obj = out / (stem + '-input.ll'), out / (stem + '.ll'), out / (stem + '.o'); inp.write_text(wrapped)
			run(['opt', '-passes=verify' if mode == 'O0' else '-passes=default<O2>', '-S', inp, '-o', optimized], out)
			run(['opt', '-passes=verify', '-disable-output', optimized], out)
			run(['llc', '-O0' if mode == 'O0' else '-O2', '-filetype=obj', '-relocation-model=pic', *(['-mattr=+fma'] if mode == 'O2-fma' else []), optimized, '-o', obj], out)
			for cc, observer in companions.items():
				binary = out / (stem + '-' + cc); run([cc, obj, observer, '-Wl,--wrap=calloc,--wrap=free', '-o', binary], out)
				observed = run([binary], out, status); (out / (binary.name + '.stdout')).write_text(observed)
				if canonical is None:
					canonical = observed
				assert observed == canonical, binary.name
				row = trace(observed, status == 0)
				if name == 'later-oom':
					assert observed == 'A1:2:4\nA2:3:4\nX1:2:2:3\nOOM\n'
				if name == 'field-oom':
					assert observed == 'A1:2:4\nA2:3:4\nX1:2:2:3\nOOM\nM3\n'
				if name == 'lifecycle':
					assert observed == ''.join(event + '\n' for event in 'A1:2:4 A2:3:4 A3:7:4 X3:7:1:2 M1 F1 M2 A4:11:4 A5:13:4 X4:11:5:13 A6:4:4 X6:4:5:13 F4 A7:5:4 X6:4:7:5 F5 F6 F7 A8:17:4 X8:17:2:3 A9:19:4 F2 M3 F9 M90 X3:7:8:17 F3 F8'.split())
				records['runs'].append(dict(name=binary.name, status=status, category='normal' if status == 0 else 'fatal-nonunwinding', output_sha256=hashlib.sha256(observed.encode()).hexdigest(), **row))
				(out / 'results.json').write_text(json.dumps(records, indent='\t') + '\n')
			for suffix, command in [('machine', ['objdump', '-dr']), ('symbols', ['readelf', '-h', '-Ws', '-r']), ('size', ['size', '-A'])]:
				(out / (stem + '.' + suffix)).write_text(run([*command, obj], out))
	records['status'] = 'PASS'
	(out / 'results.json').write_text(json.dumps(records, indent='\t') + '\n')
	print(f"{len(records['runs'])} GCC/Clang executions; {sum(len(v) for v in records['regions'].values())} independently checked descriptor regions")


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
