# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent leaf values, guarded allocation, effects and machine witnesses."""
from pathlib import Path
import json
import os
import re
import resource
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/support'))
from pipeline import observations, machine_objects
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
FIXTURES = ROOT/'tests/struct-elem-1/fixtures'
STAGES = ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
# Independently enumerated accepted shapes; this is not generated from compiler policy.
VECTORS = ['i8<2>', 'i8<4>', 'i8<8>', 'i8<16>', 'u8<2>', 'u8<4>', 'u8<8>', 'u8<16>', 'i16<2>', 'i16<4>', 'i16<8>', 'u16<2>', 'u16<4>', 'u16<8>', 'int<2>', 'int<4>', 'u32<2>', 'u32<4>', 'f32<2>', 'f32<4>', 'bool<2>', 'bool<4>', 'bool<8>', 'bool<16>']
LEAVES = ['bool', 'i8', 'u8', 'i16', 'u16', 'int', 'u32', 'f32', 'f64', 'void*', *VECTORS]
BITS = {'bool': 1, 'i8': 8, 'u8': 8, 'i16': 16, 'u16': 16, 'int': 32, 'u32': 32, 'f32': 32, 'f64': 64, 'void*': 64}
IMPORTS = '''extern(C) void se_expect(int stride);
extern(C) void se_fail();
extern(C) int se_mark(int value);
extern(C) void* se_pointer();
extern(C) int se_count(int index);
extern(C) f32 se_f32(int index);
extern(C) f64 se_f64(int index);
extern(C) int se_check32(f32 value, int index);
extern(C) int se_check64(f64 value, int index);
'''


def run(argv, cwd=ROOT, status=0):
	result = subprocess.run(list(map(str, argv)), cwd=cwd, capture_output=True, text=True, env=dict(os.environ, CCACHE_DISABLE='1'))
	assert result.returncode == status and not result.stderr, (list(map(str, argv)), result)
	return result.stdout


def layout(leaf):
	base, lanes = leaf.split('<')[0], int(leaf.split('<')[1][:-1]) if '<' in leaf else 1
	bytes_ = (BITS[base] * lanes + 7) // 8
	align = 1 << (bytes_ - 1).bit_length()
	# { u8 before; Leaf value; u8 after; } with ordinary natural alignment.
	return dict(leaf=leaf, size=align, alignment=align, offsets=[0, align, 2*align], stride=3*align)


def scalar_value(base, ordinal):
	if base in ['f32', 'f64']:
		return f'se_{base}(({ordinal}) % 12)'
	if base == 'void*':
		return 'se_pointer()'
	if base == 'bool':
		return f'(({ordinal}) % 2 == 0)'
	return f'(({ordinal}) + 3) as {base}'


def scalar_check(base, value, ordinal=None):
	if base in ['f32', 'f64']:
		return f'se_check{BITS[base]}({value}, {0 if ordinal is None else f"({ordinal}) % 12"}) == 1'
	expected = ('false' if base == 'bool' else 'null' if base == 'void*' else '0') if ordinal is None else scalar_value(base, ordinal)
	return f'{value} == {expected}'


def matrix():
	parts, layouts = [IMPORTS], []
	for number, leaf in enumerate(LEAVES):
		info = layout(leaf); layouts.append(info)
		base, lanes = leaf.split('<')[0], int(leaf.split('<')[1][:-1]) if '<' in leaf else 1
		decl = '{' + ', '.join(scalar_value(base, f'pattern + {lane}') for lane in range(lanes)) + '}' if '<' in leaf else scalar_value(base, 'pattern')
		zero = 'splat(false, '+str(lanes)+')' if base == 'bool' and '<' in leaf else 'splat(0.0f, '+str(lanes)+')' if base == 'f32' and '<' in leaf else 'splat(0, '+str(lanes)+')' if '<' in leaf else 'false' if base == 'bool' else 'null' if base == 'void*' else '0.0f' if base == 'f32' else '0.0d' if base == 'f64' else '0'
		def checks(value, initial=False):
			return ' && '.join(scalar_check(base, value + (f'[{lane}]' if '<' in leaf else ''), None if initial else f'pattern + {lane}') for lane in range(lanes))
		parts.append(f'''struct L{number} {{ u8 before; {leaf} value; u8 after; }}
L{number} pick{number}(L{number}[] a, int i) {{ return a[i]; }}
void alias{number}(L{number}[] a, L{number}[] b, int i) {{ a[i] = b[i]; }}
int leaf{number}(int n) {{
	se_expect({info['stride']});
	var a = new L{number}[n];
	if (len(a) != n) {{ return 1; }}
	int k = 0;
	while (k < n) {{ if (!(a[k].before == 0 && a[k].after == 0 && {checks('a[k].value', True)})) {{ return 2; }} k = k + 1; }}
	if (n == 0) {{ return 0; }}
	int pattern = 0;
	while (pattern < 12) {{
		{leaf} expected = {decl};
		a[n - 1].before = 91; a[n - 1].value = expected; a[n - 1].after = 117;
		var saved = a[n - 1];
		a[n - 1].value = {zero};
		if (!(saved.before == 91 && saved.after == 117 && {checks('saved.value')})) {{ return 3; }}
		a[n - 1] = saved; alias{number}(a, a, n - 1); a[n - 1] = a[n - 1];
		var returned = pick{number}(a, n - 1);
		L{number}[2] fixed = {{returned, {{after=117, value=expected, before=91}}}};
		var fixed_saved = fixed[1]; fixed[0] = fixed[1];
		if (!({checks('a[n - 1].value')} && {checks('returned.value')} && {checks('fixed_saved.value')} && {checks('fixed[0].value')})) {{ return 4; }}
		k = 0; while (k < n - 1) {{ if (!(a[k].before == 0 && a[k].after == 0 && {checks('a[k].value', True)})) {{ return 5; }} k = k + 1; }}
		pattern = pattern + 1;
	}}
	a = new L{number}[0];
	return 0;
}}
''')
	parts.append('int main(){int j=0;while(j<4){int n=se_count(j);\n' + '\n'.join(f'\tif(leaf{i}(n)!=0){{return {i+1};}}' for i in range(len(LEAVES))) + '\nj=j+1;}return 0;}\n')
	trace, owner = [], 0
	for n in [1, 2, 17]:
		for info in layouts:
			owner += 1; trace += [f"A{owner}:{n}:{info['stride']}", f'F{owner}']
	return '\n'.join(parts), layouts, '\n'.join(trace)+'\n'


def deep(depth):
	parts = ['struct Leaf { int x; f64 y; }']
	for i in range(depth):
		parts.append(f'struct D{i}{{'+('Leaf' if i == 0 else f'D{i-1}')+' child;}')
	path, init = 'child.'*depth, '{x=42,y=3.5d}'
	for _ in range(depth):
		init = '{child='+init+'}'
	parts.append(f'int main(){{D{depth-1}[1] fixed={{{init}}};var a=new D{depth-1}[2];a[1]=fixed[0];var saved=a[1];a[1].{path}x=7;release a;if(saved.{path}x!=42||saved.{path}y!=3.5d){{return 1;}}return 0;}}')
	return '\n'.join(parts)+'\n'


def c_layouts(out, layouts):
	ctypes = {'bool': '_Bool', 'i8': 'int8_t', 'u8': 'uint8_t', 'i16': 'int16_t', 'u16': 'uint16_t', 'int': 'int32_t', 'u32': 'uint32_t', 'f32': 'float', 'f64': 'double', 'void*': 'void *'}
	declarations, prints, expected, masks = [], [], [], []
	for i, info in enumerate(layouts):
		leaf = info['leaf']; base = leaf.split('<')[0]
		if base == 'bool' and '<' in leaf:
			masks.append(dict(**info, rationale='Packed LLVM i1 lanes; C _Bool vectors/arrays do not match this storage. Guarded compiled leaf reads and writes qualify the independently specified byte extent.'))
			continue
		attribute = f" __attribute__((vector_size({info['size']})))" if '<' in leaf else ''
		declarations += [f'typedef {ctypes[base]} T{i}{attribute};', f'struct R{i} {{ uint8_t before; T{i} value; uint8_t after; }};']
		prints.append(f'\tprintf("{i} %zu %zu %zu %zu %zu\\n", sizeof(struct R{i}), _Alignof(struct R{i}), offsetof(struct R{i}, before), offsetof(struct R{i}, value), offsetof(struct R{i}, after));')
		expected.append(' '.join(map(str, [i, info['stride'], info['alignment'], *info['offsets']]))+'\n')
	path = out/'layout.c'; path.write_text('#include <stdint.h>\n#include <stddef.h>\n#include <stdio.h>\n'+'\n'.join(declarations)+'\nint main(void){\n'+'\n'.join(prints)+'\n\treturn 0;\n}\n')
	for cc in ['gcc', 'clang']:
		binary = out/('layout-'+cc); run([cc, '-std=c11', '-Wall', '-Wextra', '-Werror', path, '-o', binary]); output = run([binary]); (out/(binary.name+'.stdout')).write_text(output); assert output == ''.join(expected), (cc, output, expected)
	(out/'packed-mask-layouts.json').write_text(json.dumps(masks, indent='\t')+'\n')


def trap_cases(out):
	prelude = IMPORTS + '''struct S { int x; f64 weight; }
S make() { se_mark(99); S s={x=7,weight=3.0d}; return s; }
class C { owned S[] records; init() { this.records=new S[2]; } void replace() { se_fail(); this.records=new S[3]; } }
void replace(owned S[] a) { se_fail(); a=new S[3]; }
'''
	fixtures = {
		'destination-bounds': ('var a=new S[2]; a[se_mark(2)]=make();', 'A1:2:16 M2'),
		'source-bounds': ('var a=new S[2]; a[se_mark(0)]=a[se_mark(2)];', 'A1:2:16 M0 M2'),
		'empty-bounds': ('var a=new S[0]; a[se_mark(0)]=make();', 'M0'),
		'negative-count': ('var a=new S[se_mark(-1)];', 'M-1'),
		'oom': ('se_fail(); var a=new S[se_mark(1)];', 'M1 OOM'),
		'local-oom': ('var a=new S[2]; se_fail(); a=new S[3];', 'A1:2:16 OOM'),
		'parameter-oom': ('var a=new S[2]; replace(move a);', 'A1:2:16 OOM'),
		'field-oom': ('owned C c=C.init(); c.replace();', 'A1:2:16 OOM'),
		'fixed-trap': ('S[3] a={make(),{x=se_mark(4)/se_mark(0),weight=2.0d},make()};', 'M99 M4 M0'),
	}
	results = []
	for name, (body, trace) in fixtures.items():
		path = out/(name+'.astra'); path.write_text(prelude+'int main(){'+body+'return 0;}\n'); results.append((name, path, -signal.SIGILL, ''.join(event+'\n' for event in trace.split())))
	return results


def identity_harness(ir, ssa):
	ids = {name: ordinal for ordinal, name in re.findall(r'\(function #(\d+) "([^"]+)"', ssa)}
	generic = next(ordinal for name, ordinal in ids.items() if name.startswith('astra.gen.'))
	return ir+f'''
define i32 @main() {{
	%storage = alloca %astra.class.0, align 8
	%unused = alloca %astra.class.0, align 8
	store {{ ptr, i32 }} zeroinitializer, ptr %unused
	%fresh = call fastcc ptr @astra.fn.{ids['make']}(ptr %storage, i32 2)
	%before = load {{ ptr, i32 }}, ptr %fresh
	%before.base = extractvalue {{ ptr, i32 }} %before, 0
	%before.length = extractvalue {{ ptr, i32 }} %before, 1
	%once = call fastcc ptr @astra.fn.{ids['relay']}(ptr %unused, ptr %fresh)
	%twice = call fastcc ptr @astra.fn.{generic}(ptr %unused, ptr %once)
	%after = load {{ ptr, i32 }}, ptr %twice
	%after.base = extractvalue {{ ptr, i32 }} %after, 0
	%after.length = extractvalue {{ ptr, i32 }} %after, 1
	%unused.base = load ptr, ptr %unused
	%tag = load i32, ptr %after.base
	%weight.address = getelementptr i8, ptr %after.base, i64 8
	%weight.bits = load i64, ptr %weight.address
	%a = icmp eq ptr %fresh, %storage
	%b = icmp eq ptr %once, %fresh
	%c = icmp eq ptr %twice, %fresh
	%d = icmp eq ptr %before.base, %after.base
	%e = icmp eq i32 %before.length, 2
	%f = icmp eq i32 %after.length, 2
	%g = icmp eq ptr %unused.base, null
	%h = icmp eq i32 %tag, 7
	%i = icmp eq i64 %weight.bits, 4602678819172646912
	%ab = and i1 %a, %b
	%cd = and i1 %c, %d
	%ef = and i1 %e, %f
	%gh = and i1 %g, %h
	%abcd = and i1 %ab, %cd
	%efgh = and i1 %ef, %gh
	%all = and i1 %abcd, %efgh
	%ok = and i1 %all, %i
	call fastcc void @astra.dtor.0(ptr %twice)
	%result = select i1 %ok, i32 0, i32 1
	ret i32 %result
}}
'''


def execute(compiler, out, collector=None):
	collector = collector or compiler.parent / 'tests/support/astra-stage-collector'
	out.mkdir(parents=True, exist_ok=False)
	companions = {}
	for cc in ['gcc', 'clang']:
		companions[cc] = out/(cc+'-companion.o')
		run([cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', ROOT/'tests/struct-elem-1/companion.c', '-o', companions[cc]])
	records = dict(runs=[], stages=[], layouts=[], machines=[])
	source, records['layouts'], trace = matrix()
	c_layouts(out, records['layouts'])
	(out/'matrix.astra').write_text(source)
	(out/'deep-64.astra').write_text(deep(64))
	cases = [('matrix', out/'matrix.astra', 0, trace), ('deep-64', out/'deep-64.astra', 0, 'A1:2:16\nF1\n')]
	cases.append(('effects', FIXTURES/'effects.astra', 0, ''.join(f'M{n}\n' for n in [11, 10, 21, 20, 31, 32, 0, 40, 41, 40, 0, 2, 50, 0, 60, 0, 6, 70, 1, 80, 1, 91, 90])))
	events = {'caller': '', 'borrowed': '', 'method': 'A1:2:4 F1', 'call-entry': '', 'compose': 'A1:2:24 F1', 'generic-boundaries': 'A1:2:16 A2:2:16 A3:2:16 F3 F2 F1', 'owned': 'A1:2:16 A2:1:16 F1 F2 A3:3:16 A4:3:16 F3 F4 A5:1:16 F5 A6:2:16 A7:2:16 A8:2:8 A9:1:16 F7 A10:1:16 F9 F8 F10 F6', 'lifetime': 'A1:2:8 A2:3:8 F1 A3:2:8 A4:3:8 F3 F4 A5:2:8 F5 F2', 'mixed-leaves': 'A1:17:128 F1', 'mixed': 'R+1 A1:2:16 R+3 A2:4:8 M7 A3:3:16 F1 M7 F2 R-3 F3 R-1'}
	for name, trace in events.items():
		cases.append((name, FIXTURES/(name+'.astra'), 0, ''.join(event+'\n' for event in trace.split())))
	cases.append(('boundary', FIXTURES/'boundary.astra', 0, 'R+1\nA1:2:16\nF1\nR-1\n'))
	cases.append(('identity', FIXTURES/'identity.astra', 0, 'A1:2:16\nF1\n'))
	maximum = out/'fixed-1024.astra'
	maximum.write_text('const int side=32; const int extent=side*side; struct S{int x;} int main(){S[extent] a={'+','.join('{x='+str(i)+'}' for i in range(1024))+'};S[1] b={a[1023]};if(b[0].x!=1023){return 1;}return 0;}\n')
	cases.append(('fixed-1024', maximum, 0, ''))
	cases += trap_cases(out)
	for name, path, status, expected in cases:
		dumps = observations(compiler, collector, [path, *(['--vapi', FIXTURES / 'runtime.vapi'] if name in ['mixed', 'boundary'] else [])], out, name, run, ROOT, public=name in ['basic', 'transport', 'identity', 'mixed', 'boundary', 'effects'])
		for stage in STAGES:
			records['stages'].append(name + ':' + stage)
		ordinal = re.search(r'\(function #(\d+) "main" -> int', dumps['ssa'])[1]
		wrapped = dumps['llvm'] + '\ndefine i32 @main(){\n\t%r=call fastcc i32 @astra.fn.'+ordinal+'()\n\tret i32 %r\n}\n'
		if name == 'identity':
			wrapped = identity_harness(dumps['llvm'], dumps['ssa'])
		for mode, stem, obj in machine_objects(wrapped, out, name, run):
			for cc, companion in companions.items():
				binary = out/(stem+'-'+cc)
				run([cc, obj, companion, '-Wl,--wrap=calloc,--wrap=free', '-o', binary])
				observed = run([binary], status=status)
				(out/(binary.name+'.stdout')).write_text(observed)
				if expected is not None:
					assert observed == expected, (binary.name, observed, expected)
				records['runs'].append(dict(name=binary.name, status=status, output=observed))
			(out/(stem+'.machine')).write_text(run(['objdump', '-dr', obj]))
			(out/(stem+'.symbols')).write_text(run(['readelf', '-h', '-Ws', '-r', obj]))
			(out/(stem+'.size')).write_text(run(['size', '-A', obj]))
			records['machines'].append(stem)
	(out/'results.json').write_text(json.dumps(records, indent='\t')+'\n')
	print(f"{len(records['runs'])} executions, {len(records['stages'])} repeated stage comparisons, {len(records['layouts'])} independent leaf layouts")


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	execute(Path(sys.argv[1]).resolve(), fresh_output(sys.argv[2]), Path(sys.argv[3]).resolve(strict=True) if len(sys.argv) == 4 else None)
