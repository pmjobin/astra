# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent byte oracle, native memory seam, sequencing and composition."""
from pathlib import Path
import hashlib
import itertools
import json
import os
import platform
import random
import re
import resource
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
STAGES = ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def process(args, **kwargs):
	return subprocess.run(list(map(str, args)), capture_output=True, env=kwargs.pop('env', dict(os.environ, CCACHE_DISABLE='1')), **kwargs)


def run(args, **kwargs):
	p = process(args, **kwargs)
	assert p.returncode == 0 and not p.stderr, (args, p.returncode, p.stdout[-2000:], p.stderr[-4000:])
	return p.stdout.decode()


def sha(data):
	return hashlib.sha256(data.encode() if isinstance(data, str) else data).hexdigest()


def literal(text):
	return '"' + ''.join('\\U%08x' % ord(c) for c in text) + '"'


def oracle(compiler, out):
	rng = random.Random(7301)
	scalars = [0, 1, 9, 10, 13, 0x7f, 0x80, 0x7ff, 0x800, 0xd7ff, 0xe000, 0xfeff, 0xfffe, 0xffff, 0x10000, 0x10ffff]
	texts = ['', 'Astra', 'français', 'e\u0301', 'é', 'Ελληνικά', '中文', '😀', 'a\0b', 'a\0c', '\ufeff']
	texts += [chr(n) for n in scalars]
	for _ in range(256):
		values = []
		for _ in range(rng.randrange(1, 60)):
			n = rng.randrange(0x110000)
			if not 0xd800 <= n <= 0xdfff:
				values.append(chr(n))
		texts.append(''.join(values))
	source = out / 'oracle.astra'
	source.write_text('\n'.join(f'const S{i}={literal(text)}; const N{i}=S{i}.byte_length; const E{i}=S{i}=={literal(text)};' for i, text in enumerate(texts)) + '\nint main(){return 0;}\n')
	dump = run([compiler, '--dump-semantics', source])
	for i, text in enumerate(texts):
		data = text.encode('utf-8')
		assert f'(const "S{i}" (text (bytes {len(data)}) (hex {data.hex()}) : string))' in dump
		assert f'(const "N{i}" (integer {len(data)} : int))' in dump and f'(const "E{i}" (bool true : bool))' in dump
	(out / 'oracle.semantics').write_text(dump)
	# Raw supplementary, noncharacters and BOM content follow the same oracle.
	raw = out / 'raw.astra'
	for i, text in enumerate(texts[:11] + [chr(n) for n in scalars if n not in [0, 10, 13]]):
		text = text.replace('\0', '\\0').replace('"', '\\"')
		raw.write_text(f'const X="{text}"; int main(){{return 0;}}\n')
		run([compiler, '--check', raw])
	locales = run(['locale', '-a']).splitlines()
	selected = ['C'] + [name for name in locales if name.lower().startswith(('fr_', 'tr_', 'de_'))][:3]
	assert len(selected) > 1, 'non-C locale required for qualification'
	raw.write_text('const RAW="français Ελληνικά 中文 😀 e\\u0301 a\\0b"; int main(){return 0;}')
	raw_dump = run([compiler, '--dump-semantics', raw])
	for locale in selected:
		assert run([compiler, '--dump-semantics', source], env=dict(os.environ, LC_ALL=locale)) == dump
		assert run([compiler, '--dump-semantics', raw], env=dict(os.environ, LC_ALL=locale)) == raw_dump
	return dict(sequences=len(texts), independent='Python Unicode UTF-8 encoder', exact_payload_digest=sha(dump), locales=selected)


def negatives(compiler, out):
	path = out / 'negative.astra'
	invalid_bytes = [b'\x80', b'\xbf', b'\xc0\x80', b'\xc1\xbf', b'\xc2', b'\xe0\x80\x80', b'\xe0\x9f\xbf', b'\xed\xa0\x80', b'\xed\xbf\xbf', b'\xf0\x80\x80\x80', b'\xf0\x8f\xbf\xbf', b'\xf4\x90\x80\x80', b'\xf5\x80\x80\x80', b'\xff', b'\xe2\x82', b'\xf0\x9f\x98', b'\xc2A']
	for data in invalid_bytes + [b'\0']:
		path.write_bytes(b'const X="a' + data + b'b";')
		p = process([compiler, '--parse', path]); assert p.returncode == 1 and (b'unexpected NUL byte' if data == b'\0' else b'invalid UTF-8 encoding') in p.stderr
	bad_literals = ['"\\x41"', '"\\q"', '"\\u12"', '"\\U0000000"', '"\\u12xz"', '"\\U00110000"', '"\\Uffffffff"', '"\\ud800"', '"\\udfff"', '"\\ud83d\\ude00"', '"a\nb"', '"a\rb"', '"a\\\nb"', '"unfinished', '"unfinished\\', '"a" "b"', 'r"a"', "'a'"]
	for value in bad_literals:
		path.write_text('const X=' + value + ';')
		p = process([compiler, '--check', path]); assert p.returncode == 1, (value, p.stderr)
	cases = [
		('string f(string s){return s;}', 'borrowed text cannot escape'),
		('string f(string s){var copy=s;return copy;}', 'borrowed text cannot escape'),
		('string f(string s,bool c){var x="a";if(c){x=s;}return x;}', 'borrowed text cannot escape'),
		('struct string{int x;}', 'builtin'), ('class string{int x;}', 'builtin'),
		('struct S{string text;}', 'string fields'), ('class C{string text;}', 'string fields'),
		('void f(){var x="a";var y=x[0];}', 'index'),
		('void f(){var x="a";var y=slice(x);}', 'array'),
		('void f(){var x="a";var y=x as int;}', 'conversion'),
		('void f(){int[1] a={1};string x=slice(a);}', 'expected initializer'),
		('string f(string p,bool c){var x="a";while(c){{x=p;}continue;}return x;}', 'borrowed text cannot escape'),
		('string f(string p,bool c){var x="a";while(c){var y=x;x=p;if(c){return y;}}return x;}', 'borrowed text cannot escape'),
		('void f(){string[] x="a";}', 'expected initializer'),
		('void f(){string[1] x={"a"};}', 'array'), ('void f(){var x=new string[2];}', 'element'),
		('void f(){owned string x="a";}', 'owned'), ('owned string f(){return "a";}', 'owned'),
		('void f(owned string x){}', 'owned'), ('void f(){var x="a";var y=move x;}', 'owned'),
		('void f(){var s="a";var p=&s;}', 'address'), ('const S="a";void f(){var p=&S;}', 'no storage'),
		('void f(){string* p=null;}', 'pointee'), ('void f(){string s=null;}', 'expected initializer'),
		('bool f(){return "a"==null;}', 'matching'), ('bool f(void* p){return "a"==p;}', 'matching'),
		('void f(){var s="a";s[0]=1;}', 'index'), ('void f(){var s="a";s.byte_length=1;}', 'read-only'),
		('void f(){var s="a" as void*;}', 'conversion'), ('bool f(){return "a"<"b";}', 'operand'),
		('void f(){var s="a"+"b";}', 'operand'), ('void f(){if("a") {}}', 'bool'),
		('void f(){var s="a";var n=s.length;}', 'byte_length'), ('void f(string s){s="b";}', 'assignment to parameter'),
		('T id<T>(T x){return x;} void f(){var s=id("a");}', 'unsupported'),
		('bool eq<T>(T a,T b) where T:Eq{return a==b;} void f(){var x=eq("a","b");}', 'unsupported'),
		('extern(C) string f();', 'C boundaries'), ('extern(C) int f(string x);', 'C boundaries'),
		('export(C) string f(){return "a";}', 'C boundaries'), ('export(C) int f(string x){return 0;}', 'C boundaries'),
		('const A=B; const B=A;', 'cycle'), ('const A=false && ("x"==missing);', 'unknown name'),
		('const A=false && ("x"==1);', 'matching'), ('int f(){return 1;} const A=false && (f()==1);', 'unsupported constant expression'),
		('const X="";void f(){int[X.byte_length] a={1};}', '1..1024'),
		('const X="a";void f(){X="b";}', 'not mutable'),
	]
	for source, message in cases:
		path.write_text(source)
		p = process([compiler, '--check', path]); assert p.returncode == 1 and message.lower().encode() in p.stderr.lower(), (source, message, p.returncode, p.stderr)
		# ERROR-1 supplies the bounded ordinary get-only string property subset.
	path.write_text('class C{property string label{get{return "x";}}}')
	p = process([compiler, '--check', path]); assert p.returncode == 0, p.stderr
	api = out / 'text.vapi'; path.write_text('int main(){return 0;}')
	for source in ['string f();', 'int f(string s);']:
		api.write_text(source); p = process([compiler, '--check', path, '--vapi', api]); assert p.returncode == 1 and b'C ' in p.stderr
	return dict(raw_encoding=len(invalid_bytes)+1, literal_grammar=len(bad_literals), semantic=len(cases), approved_getter=1, vapi=2)


def compose(compiler, out):
	sources = [ROOT / 'tests/text/fixtures' / p for p in ['00-constants.astra', '10-default.astra', '20-compare.astra', '30-client.astra']]
	record = {}
	for stage in STAGES:
		expected = run([compiler, '--dump-' + stage, *sources]); (out / ('composition.' + stage)).write_text(expected)
		for order in itertools.permutations(sources):
			assert run([compiler, '--dump-' + stage, *order]) == expected
		record[stage] = sha(expected)
	moved = out / 'source-relocated'; moved.mkdir(exist_ok=True)
	for source in sources: shutil.copy2(source, moved / source.name)
	for stage in STAGES:
		actual = run([compiler, '--dump-' + stage, *[moved / s.name for s in sources]])
		expected = (out / ('composition.' + stage)).read_text()
		assert actual.replace(str(moved), str(sources[0].parent)) == expected
	inventory = re.findall(r'^@astra.text.\d+ = private constant .+$', (out / 'composition.llvm').read_text(), re.M)
	assert len(inventory) == 4
	content = [re.sub(r'\\([0-9A-F]{2})', lambda m: chr(int(m[1], 16)), row.split(' c"', 1)[1][:-1]).encode('latin1') for row in inventory]
	assert content == [b'Astra', 'é'.encode(), b'a\0b', b'a\0c']
	bad = [out / ('bad-%d.astra' % i) for i in range(4)]
	for p, text in zip(bad, ['const A=B.byte_length;', 'const B=A;', 'int f(){return 1;}', 'int main(){return 0;}']): p.write_text(text)
	expected = None
	for order in itertools.permutations(bad):
		p = process([compiler, '--check', *order]); assert p.returncode == 1 and b'cycle' in p.stderr
		assert expected is None or p.stderr == expected; expected = p.stderr
	return dict(stages=record, stage_permutations=216, diagnostic_permutations=24, relocation=9, literal_inventory=inventory, diagnostic=expected.decode().replace(str(out), '<qualification>'))


def ordinal(compiler, source, name='main', extra=()):
	ssa = run([compiler, '--dump-ssa', source, *extra])
	return re.search(r'\(function #(\d+) "' + name + '"', ssa)[1]


def object_file(ir, stem, mode):
	stem.with_suffix('.input.ll').write_text(ir)
	run(['opt', '-passes=verify' if mode == 'O0' else '-passes=default<O2>', '-S', stem.with_suffix('.input.ll'), '-o', stem.with_suffix('.ll')])
	run(['llc', '-O0' if mode == 'O0' else '-O2', '-filetype=obj', '-relocation-model=pic', *(['-mattr=+fma'] if mode == 'fma' else []), stem.with_suffix('.ll'), '-o', stem.with_suffix('.o')])
	return stem.with_suffix('.o')


def runtime(compiler, out):
	records = {}
	for name in ['basics', 'control']:
		source = ROOT / f'tests/text/fixtures/{name}.astra'
		n = ordinal(compiler, source)
		ir = run([compiler, '--dump-llvm', source]) + f'\ndefine i32 @main() {{\n\t%r = call fastcc i32 @astra.fn.{n}()\n\tret i32 %r\n}}\n'
		links = []
		if name == 'control':
			companion = out / 'effects.o'; run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-O0', '-c', ROOT / 'tests/text/effects.c', '-o', companion]); links = [companion]
		for mode in ['O0', 'O2', 'fma']:
			stem = out / (name + '-' + mode); obj = object_file(ir, stem, mode)
			run(['cc', obj, *links, '-o', stem]); run([stem])
			records[stem.name] = dict(ir=sha(stem.with_suffix('.ll').read_bytes()), undefined=run(['nm', '-u', obj]), size=run(['size', '-A', obj]).splitlines()[1:])
	source = ROOT / 'tests/text/fixtures/native.astra'
	ir = run([compiler, '--dump-llvm', source]) + '''
define i32 @text_equal(ptr %a, i32 %an, ptr %b, i32 %bn) {
	%r = call fastcc i1 @astra.fn.0(ptr %a, i32 %an, ptr %b, i32 %bn)
	%z = zext i1 %r to i32
	ret i32 %z
}
define i32 @text_length(ptr %a, i32 %an) {
	%r = call fastcc i32 @astra.fn.1(ptr %a, i32 %an)
	ret i32 %r
}
'''
	for mode in ['O0', 'O2', 'fma']:
		stem = out / ('native-' + mode); obj = object_file(ir, stem, mode)
		assert run(['nm', '-u', obj]) == ''
		for host in ['gcc', 'clang']:
			harness = out / ('harness-' + host + '.o'); run([host, '-std=c11', '-Wall', '-Wextra', '-Werror', '-O0', '-c', ROOT / 'tests/text/native-harness.c', '-o', harness])
			exe = out / ('native-' + mode + '-' + host); run([host, obj, harness, '-o', exe]); run([exe])
		records[stem.name] = dict(undefined=run(['nm', '-u', obj]), symbols=run(['nm', '-a', obj]).splitlines(), size=run(['size', '-A', obj]).splitlines()[1:])
	return records


def mixed(compiler, out):
	source = ROOT / 'tests/text/fixtures/mixed.astra'
	extra = [ROOT / 'lib/astra/base/contracts.astra', '--vapi', ROOT / 'tests/baselib/fixtures/runtime.vapi']
	n = ordinal(compiler, source, extra=extra)
	ir = run([compiler, '--dump-llvm', source, *extra]) + f'\ndefine i32 @main() {{\n\t%r = call fastcc i32 @astra.fn.{n}()\n\tret i32 %r\n}}\n'
	nabi = run([compiler, '--dump-nabi', source, *extra]); (out / 'mixed.nabi').write_text(nabi)
	assert 'text-v9' in nabi and 'borrowed-noescape' in nabi and 'static-text' in nabi
	companion = out / 'ownership.o'; run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-O0', '-c', ROOT / 'tests/text/ownership.c', '-o', companion])
	expected = 'E7\nE90\nE90\nE90\nE1\nE2\nE3\nE8\nE-90\nE-7\nE-90\nE-90\n'
	rows = {}
	for mode in ['O0', 'O2', 'fma']:
		stem = out / ('mixed-' + mode); obj = object_file(ir, stem, mode)
		run(['cc', obj, companion, compiler.parent / 'lib/astra/failure-trap.o', '-Wl,--wrap=calloc,--wrap=free', '-o', stem])
		trace = run([stem]); assert trace == expected, (mode, trace)
		rows[mode] = dict(trace=trace, undefined=run(['nm', '-u', obj]), size=run(['size', '-A', obj]).splitlines()[1:])
	return rows


def traps(compiler, out):
	companion = out / 'trap-effects.c'; companion.write_text('#include <stdio.h>\nint text_mark(int n){printf("E%d\\n",n);fflush(stdout);return n;}\nint text_zero(void){return 0;}\n')
	obj = out / 'trap-effects.o'; run(['cc', '-Wall', '-Wextra', '-Werror', '-O0', '-c', companion, '-o', obj])
	rows = []
	for trap_side in ['left', 'right']:
		source = out / ('trap-' + trap_side + '.astra')
		left = 'int n=1/text_zero();' if trap_side == 'left' else ''
		right = 'int n=1/text_zero();' if trap_side == 'right' else ''
		source.write_text('extern(C) int text_mark(int n); extern(C) int text_zero();' + f'string first(){{text_mark(11);{left}return "a";}} string second(){{text_mark(12);{right}return "long";}} int main(){{if(first()==second()){{return 1;}}return 0;}}')
		n = ordinal(compiler, source); ir = run([compiler, '--dump-llvm', source]) + f'\ndefine i32 @main() {{\n\t%r = call fastcc i32 @astra.fn.{n}()\n\tret i32 %r\n}}\n'
		for mode in ['O0', 'O2', 'fma']:
			stem = out / ('trap-' + trap_side + '-' + mode); compiled = object_file(ir, stem, mode)
			run(['cc', compiled, obj, '-o', stem]); result = process([stem])
			assert result.returncode < 0 and result.stdout == (b'E11\n' if trap_side == 'left' else b'E11\nE12\n') and not result.stderr
			rows.append(dict(side=trap_side, mode=mode, status=result.returncode, trace=result.stdout.decode()))
	return rows


def freestanding(compiler, out):
	assert platform.machine() == 'x86_64' and sys.platform == 'linux'
	source = out / 'pure.astra'
	source.write_text('string choose_static(int n){var x="a\\0b";if(n==2){x="é";}return x;} int entry(int n){var x=choose_static(n);if(x=="é" && x.byte_length==2){return 0;}return 1;}')
	n = ordinal(compiler, source, 'entry'); ir = run([compiler, '--dump-llvm', source]) + f'\ndefine i32 @text_entry(i32 %n) {{\n\t%r = call fastcc i32 @astra.fn.{n}(i32 %n)\n\tret i32 %r\n}}\n'
	startup = out / 'start.S'; startup.write_text('.text\n.globl _start\n_start:\n\tmov $2, %edi\n\tcall text_entry\n\tmov %eax, %edi\n\tmov $60, %eax\n\tsyscall\n.section .note.GNU-stack,"",@progbits\n')
	run(['cc', '-c', startup, '-o', out / 'start.o'])
	rows = {}
	for mode in ['O0', 'O2', 'fma']:
		stem = out / ('pure-' + mode); obj = object_file(ir, stem, mode)
		assert run(['nm', '-u', obj]) == ''
		run(['ld', '-e', '_start', out / 'start.o', obj, '-o', stem]); run([stem])
		assert run(['nm', '-u', stem]) == ''
		rows[mode] = dict(size=run(['size', '-A', obj]).splitlines()[1:], sections=run(['readelf', '-SW', obj]), symbols=run(['nm', '-a', obj]))
	return dict(target='Linux x86_64', explicit_startup=True, builds=rows)


def consumer(compiler, out):
	build = compiler.parent; prefix = out / 'install'
	run(['meson', 'install', '-C', build, '--no-rebuild', '--destdir', prefix])
	options = {o['name']: o['value'] for o in json.loads(run(['meson', 'introspect', build, '--buildoptions']))}
	installed = prefix / options['prefix'].lstrip('/')
	relocated = out / 'installed-relocated'; shutil.copytree(installed, relocated, dirs_exist_ok=True)
	for label, directory in [('installed', installed), ('relocated', relocated)]:
		lib = directory / options['datadir'] / 'astra'; provider = directory / options['libdir'] / 'astra/x86_64-linux/failure-trap.o'
		exe = out / ('consumer-' + label)
		run([directory / 'bin/astrac', ROOT / 'examples/base/text.astra', *[lib / 'base' / (n + '.astra') for n in ['contracts', 'order', 'classify', 'clamp']], '--link-object', provider, '-o', exe], cwd=out); run([exe], cwd=out)
	return dict(installed=1, relocated=1, provider='explicit failure-trap.o', buffer_owner=True)


def main():
	compiler = Path(sys.argv[1]).resolve(); out = Path(sys.argv[2]).resolve(); out.mkdir(parents=True, exist_ok=True)
	result = dict(oracle=oracle(compiler, out), negatives=negatives(compiler, out), composition=compose(compiler, out), runtime=runtime(compiler, out), mixed=mixed(compiler, out), traps=traps(compiler, out), freestanding=freestanding(compiler, out), consumer=consumer(compiler, out))
	(out / 'qualification.json').write_text(json.dumps(result, indent='\t') + '\n')
	print(json.dumps({key: 'PASS' for key in result}))


if __name__ == '__main__':
	main()
