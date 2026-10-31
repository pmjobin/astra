# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""ARGS-1 byte, source, native machine and composition qualification."""
from pathlib import Path
import ctypes
import hashlib
import itertools
import json
import os
import random
import re
import resource
import struct
import subprocess
import sys
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / 'tests/args'
LIB = ROOT / 'lib/astra'
STAGES = ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
COMMANDS = []
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def process(args, **kwargs):
	args = list(map(str, args)); COMMANDS.append(args)
	return subprocess.run(args, capture_output=True, timeout=kwargs.pop('timeout', 90), env=dict(os.environ, CCACHE_DISABLE='1'), **kwargs)


def run(args, **kwargs):
	p = process(args, **kwargs)
	assert p.returncode == 0 and p.stderr == b'', (args, p.returncode, p.stdout[-2000:], p.stderr[-4000:])
	return p.stdout


def sha(data):
	return hashlib.sha256(data).hexdigest()


def cc(host, source, target, extra=()):
	run([host, '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2', *extra, source, '-o', target])


def launch(launcher, executable, arguments, out):
	assert all(b'\0' not in item for item in arguments)
	vector = struct.pack('<I', len(arguments)) + b''.join(struct.pack('<I', len(item)) + item for item in arguments)
	path = out / 'vector.bin'; path.write_bytes(vector)
	p = process([launcher, executable, path])
	assert p.returncode != 125 and b'launcher execve' not in p.stderr, ('exec failure is not application evidence', p)
	return p


def utf8(out):
	library = out / 'validator.so'
	cc('/usr/bin/gcc', HERE / 'provider.c', library, ['-shared', '-fPIC'])
	validate = ctypes.CDLL(str(library)).test_utf8
	validate.argtypes = [ctypes.c_char_p, ctypes.c_size_t]; validate.restype = ctypes.c_int
	size_model = ctypes.CDLL(str(library)).test_size
	size_model.argtypes = [ctypes.c_size_t, ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t), ctypes.c_int]; size_model.restype = ctypes.c_int
	rng = random.Random(7501); counts = dict(scalars=0, bytes=0, sequences=0); digest = hashlib.sha256()
	def compare(data, category):
		try:
			data.decode('utf-8', 'strict'); expected = True
		except UnicodeDecodeError:
			expected = False
		assert bool(validate(data, len(data))) == expected, data.hex()
		digest.update(struct.pack('<I', len(data)) + data + bytes([expected])); counts[category] += 1
	for scalar in range(0x110000):
		if not 0xd800 <= scalar <= 0xdfff:
			compare(chr(scalar).encode('utf-8'), 'scalars')
	for length in range(3):
		for items in itertools.product(range(256), repeat=length):
			compare(bytes(items), 'bytes')
	boundaries = [0, 1, 0x7f, 0x80, 0x9f, 0xa0, 0xbf, 0xc0, 0xc1, 0xc2, 0xdf, 0xe0, 0xed, 0xef, 0xf0, 0xf4, 0xf5, 0xff]
	for length in [3, 4]:
		for items in itertools.product(boundaries, repeat=length):
			compare(bytes(items), 'sequences')
	for _ in range(25000):
		compare(rng.randbytes(rng.randrange(0, 40)), 'sequences')
	for _ in range(2000):
		scalars = [rng.randrange(0x110000) for _ in range(rng.randrange(1, 50))]
		compare(''.join(chr(n) for n in scalars if not 0xd800 <= n <= 0xdfff).encode('utf-8'), 'sequences')
	for _ in range(10000):
		left = rng.getrandbits(64); right = rng.getrandbits(64)
		for multiply in [0, 1]:
			answer = ctypes.c_size_t(); exact = left * 16 if multiply else left + right
			valid = bool(size_model(left, right, ctypes.byref(answer), multiply))
			assert valid == (exact <= 2**63-1) and (not valid or answer.value == exact)
	return dict(counts=counts, size_model_cases=20000, sha256=digest.hexdigest(), oracle='Python strict UTF-8 decoder and unbounded integer arithmetic; scalar encoding enumerated independently; NUL is a scalar here, not argv payload')


def source_contracts(compiler, out):
	accepted = [
		'int f(string[] p){var x=p;return len(x);}',
		'int f(borrowed string[] p){var x=p;var y=x;x=p;return len(y);}',
		'int f(string[] p,string[] q){var x=p;{var y=q;x=y;}var text=x[0];return text.byte_length;}',
		'int g(string p){return p.byte_length;} int f(string[] p){var t=p[0];return g(t);}',
		'int f(string[] p,bool b){var x=p;while(b){var saved=x;x=p;if(b){x=saved;break;}}return len(x);}',
		'string f(string[] p){var s="static";var saved=s;s=p[0];return saved;}',
		'string f(string[] p){var s=p[0];return "literal";}',
		'int f<T>(T n,string[] p){var q=p;var t=q[0];return t.byte_length;} int main(string[] a){return f<int>(1,a);}',
		'struct S{int n; int f(string[] p){return len(p)+this.n;}} int main(string[] a){S s={n=0};return s.f(a);}',
		'class C{int n; init(string[] p){this.n=len(p);} int f(borrowed string[] p){return this.n+len(p);}} int main(string[] a){C c=C.init(a);return c.f(a);}',
		'[CCode(text_abi="utf8-i32")] extern(C) int observe(borrowed string p); int f(string[] a){var p=a[0];return observe(p);}',
		'int main(string[] a){if(false){return main(a);}return len(a);}',
		'void f<T>(T[] a){}',
	]
	rejected = [
		('void f(string[] a){a[0]="x";}', b'descriptor elements are read-only'),
		('void f(string[] a){var p=&a;}', b'address'),
		('void f(string[] a){var p=&a[0];}', b'address'),
		('struct S{string[] items;}', b'fields'),
		('class C{owned string[] items;init(){this.items=new string[1];}}', b'fields'),
		('struct S{string text;}', b'field'),
		('void f(owned string[] a){}', b'owned string'),
		('void f(string[] a){owned string[] b=a;}', b'owned string'),
		('void f(){var x=new string[2];}', b'element'),
		('void f(){string[2] x={"a","b"};}', b'array'),
		('string[] f(string[] a){return a;}', b'slice results'),
		('owned string[] f(){return new string[2];}', b'slice results'),
		('string f(string[] a){return a[0];}', b'borrowed text cannot escape'),
		('string f(string[] a){var p=a[0];var q=p;return q;}', b'borrowed text cannot escape'),
		('string f(string[] a,bool b){var p="x";if(b){p=a[0];}return p;}', b'borrowed text cannot escape'),
		('string f(string[] a,bool b){var p="x";while(b){p=a[0];break;}return p;}', b'borrowed text cannot escape'),
		('[CCode(text_abi="utf8-i32")] extern(C) int observe(borrowed string p); string f(string[] a){var p=a[0];observe(p);return p;}', b'borrowed text cannot escape'),
		('void f(string[] a){var p=a as void*;}', b'conversion'),
		('void f(void* p){string[] a=p;}', b'expected initializer'),
		('void f(){string[] a=null;}', b'no null state'),
		('void f(string[] a){var b=slice(a);}', b'array'),
		('void f(string[] a){const N=len(a);}', b'constant'),
		('T f<T>(T p){return p;} void g(string[] a){var b=f<string[]>(a);}', b'GEN1_PLAIN_COPY'),
		('void f<T>(T[] a){}void g(string[] a){f(a);}', b'GEN1_PLAIN_COPY'),
		('void f(string[][] a){}', b'nested slices'),
		('extern(C) int f(string[] a);', b'unsupported'),
		('export(C) int f(string[] a){return len(a);}', b'C boundaries'),
		('extern(C) string f();', b'string'),
		('extern(C) int f(string a);', b'C boundaries'),
	]
	path = out / 'contracts.astra'; evidence = []
	for index, text in enumerate(accepted):
		path.write_text(text)
		for stage in STAGES:
			run([compiler, '--dump-' + stage, path])
		evidence.append(dict(kind='accept', source=text))
	for text, diagnostic in rejected:
		path.write_text(text); p = process([compiler, '--check', path])
		assert p.returncode == 1 and diagnostic in p.stderr and b'error:' in p.stderr, (text, p.returncode, p.stderr)
		evidence.append(dict(kind='reject', source=text, diagnostic=p.stderr.decode()))
		# Existing implicit and explicit borrowing have identical checked contracts.
	for stage in STAGES[1:]:
		path.write_text('int f(string[] a){var b=a;return len(b);}')
		plain = run([compiler, '--dump-' + stage, path])
		path.write_text('int f(borrowed string[] a){var b=a;return len(b);}')
		assert plain == run([compiler, '--dump-' + stage, path]), stage
	return evidence


def native(compiler, out):
	source = HERE / 'fixtures/native.astra'
	ssa = run([compiler, '--dump-ssa', source]); ir = run([compiler, '--dump-llvm', source])
	def ordinal(name):
		return re.search(rb'\(function #(\d+) "' + name.encode() + b'"', ssa)[1].decode()
	ir += f'''\ndefine i32 @args_consume(ptr %a, i32 %an, ptr %b, i32 %bn, i32 %i) {{
\t%r = call fastcc i32 @astra.fn.{ordinal('consume')}(ptr %a, i32 %an, ptr %b, i32 %bn, i32 %i)
\tret i32 %r
}}
define i32 @args_count(ptr %a, i32 %n) {{
\t%r = call fastcc i32 @astra.fn.{ordinal('count')}(ptr %a, i32 %n)
\tret i32 %r
}}
define i32 @args_short(ptr %a, i32 %n, i32 %i, i32 %skip) {{
	%b = icmp ne i32 %skip, 0
	%r = call fastcc i1 @astra.fn.{ordinal('short_read')}(ptr %a, i32 %n, i32 %i, i1 %b)
	%result = zext i1 %r to i32
	ret i32 %result
}}
define i32 @args_element(ptr %a, i32 %n, i32 %i) {{
\t%r = call fastcc i32 @astra.fn.{ordinal('element')}(ptr %a, i32 %n, i32 %i)
\tret i32 %r
}}
'''.encode()
	assert b'getelementptr { ptr, i32 }' in ir and b'load { ptr, i32 }' in ir
	results = []
	for mode in ['O0', 'O2', 'fma', 'preserved']:
		stem = out / ('native-' + mode)
		input_ir = ir if mode != 'preserved' else re.sub(rb'(define internal fastcc [^\n]+) \{', rb'\1 noinline {', ir)
		stem.with_suffix('.input.ll').write_bytes(input_ir)
		run(['opt', '-passes=verify' if mode == 'O0' else '-passes=default<O2>', '-S', stem.with_suffix('.input.ll'), '-o', stem.with_suffix('.ll')])
		run(['llc', '-O0' if mode == 'O0' else '-O2', '-filetype=obj', '-relocation-model=pic', *(['-mattr=+fma'] if mode == 'fma' else []), stem.with_suffix('.ll'), '-o', stem.with_suffix('.o')])
		for host in ['gcc', 'clang']:
			provider = out / ('args-' + host + '.o'); cc('/usr/bin/' + host, LIB / 'platform/args-posix.c', provider, ['-c'])
			exe = out / ('native-' + mode + '-' + host)
			cc('/usr/bin/' + host, HERE / 'native.c', exe, [stem.with_suffix('.o'), provider])
			run([exe])
			traps = []
			for index in [-1, 0, 3]:
				p = process([exe, index]); assert p.returncode < 0 and p.stdout == b'' and p.stderr == b'', (mode, host, index, p)
				traps.append(dict(index=index, signal=-p.returncode))
			results.append(dict(mode=mode, host=host, executable=str(exe), traps=traps, llvm_sha256=sha(stem.with_suffix('.ll').read_bytes())))
	return results


def snapshot_output(compiler, out):
	sources = [HERE / 'fixtures/snapshot-output.astra', LIB / 'hosted/text.astra']
	ssa = run([compiler, '--dump-ssa', *sources]); ir = run([compiler, '--dump-llvm', *sources])
	ordinal = re.search(rb'\(function #(\d+) "print_snapshot"', ssa)[1].decode()
	ir += f'\ndefine i32 @args_print(ptr %items, i32 %count) {{\n\t%r = call fastcc i32 @astra.fn.{ordinal}(ptr %items, i32 %count)\n\tret i32 %r\n}}\n'.encode()
	expected = ('invocation\n\né e\u0301😀\n'.encode()) * 16; rows = []
	for mode in ['O0', 'O2', 'fma', 'preserved']:
		stem = out / ('snapshot-output-' + mode)
		stem.with_suffix('.input.ll').write_bytes(ir if mode != 'preserved' else re.sub(rb'(define internal fastcc [^\n]+) \{', rb'\1 noinline {', ir))
		run(['opt', '-passes=verify' if mode == 'O0' else '-passes=default<O2>', '-S', stem.with_suffix('.input.ll'), '-o', stem.with_suffix('.ll')])
		run(['llc', '-O0' if mode == 'O0' else '-O2', '-filetype=obj', '-relocation-model=pic', *(['-mattr=+fma'] if mode == 'fma' else []), stem.with_suffix('.ll'), '-o', stem.with_suffix('.o')])
		for host in ['gcc', 'clang']:
			output = out / ('snapshot-text-' + host + '.o'); cc('/usr/bin/' + host, LIB / 'platform/text-posix.c', output, ['-c'])
			exe = out / ('snapshot-output-' + mode + '-' + host)
			cc('/usr/bin/' + host, HERE / 'snapshot-output.c', exe, [stem.with_suffix('.o'), out / ('args-' + host + '.o'), output])
			actual = run([exe]); assert actual == expected; exe.with_suffix('.stdout').write_bytes(actual)
			rows.append(dict(mode=mode, host=host, cycles=16, bytes=len(actual), stdout_sha256=sha(actual), llvm_sha256=sha(stem.with_suffix('.ll').read_bytes())))
	return rows


def cli(compiler, out):
	launcher = out / 'launcher'; cc('/usr/bin/gcc', HERE / 'launcher.c', launcher)
	provider = out / 'args-gcc.o'; output = out / 'text.o'
	cc('/usr/bin/gcc', LIB / 'platform/args-posix.c', provider, ['-c']); cc('/usr/bin/gcc', LIB / 'platform/text-posix.c', output, ['-c'])
	source = out / 'entry.astra'; source.write_text('int main(string[] args){if(!println("entered")){return 1;}var i=0;while(i<len(args)){if(!println(args[i])){return 1;}i=i+1;}return 0;}')
	exe = out / 'entry'; run([compiler, source, LIB / 'hosted/text.astra', '--link-object', provider, '--link-object', output, '-o', exe])
	valid = [[b'custom invocation'], [b'', b'', b'a', b''], [b'custom', b'a b', b'"quoted"', b'\\path\\', b'-x', b'--', b'%s%n'], ['é'.encode(), 'e\u0301'.encode(), '😀\ufeff\ufffe\U0010ffff'.encode()], [b'many'] + [('%04d' % i).encode() for i in range(4097)]]
	results = []
	for arguments in valid:
		p = launch(launcher, exe, arguments, out); expected = b'entered\n' + b''.join(a + b'\n' for a in arguments)
		assert p.returncode == 0 and p.stdout == expected and p.stderr == b''
		results.append(dict(count=len(arguments), stdout_bytes=len(p.stdout), stdout_sha256=sha(p.stdout), status=0))
	invalid = [b'\x80', b'\xc0\xaf', b'\xc1\xbf', b'\xc2', b'\xe0\x80\x80', b'\xed\xa0\x80', b'\xf0\x80\x80\x80', b'\xf4\x90\x80\x80', b'\xf5\x80\x80\x80', b'\xff', b'x\xe2\x82', b'\xe2A\xac']
	for bad in invalid:
		for arguments in [[bad, b'good'], [b'zero', bad, b'late'], [b'zero', b'early', bad]]:
			p = launch(launcher, exe, arguments, out); assert p.returncode == 2 and p.stdout == b'' and p.stderr == b''
			# Unused arguments still validate; old main neither validates nor allocates.
	for name, text, expected, needs in [('unused', 'int main(string[] a){return 19;}', 2, True), ('old', 'int main(){return 19;}', 19, False)]:
		path = out / (name + '.astra'); path.write_text(text); target = out / name
		run([compiler, path, *(['--link-object', provider] if needs else []), '-o', target])
		p = launch(launcher, target, [b'\xff', b'\xff'], out); assert p.returncode == expected and not p.stdout and not p.stderr
		if not needs:
			assert b'astra_host_args' not in run(['nm', target])
	failure = out / 'failure.c'; failure.write_text('#include <stddef.h>\nvoid *args_fail_malloc(size_t n){(void)n;return NULL;}\n')
	failure_object = out / 'failure.o'; cc('/usr/bin/gcc', failure, failure_object, ['-c'])
	failure_provider = out / 'args-fail.o'; cc('/usr/bin/gcc', LIB / 'platform/args-posix.c', failure_provider, ['-c', '-Dmalloc=args_fail_malloc'])
	failure_exe = out / 'failure'; run([compiler, source, LIB / 'hosted/text.astra', '--link-object', failure_provider, '--link-object', failure_object, '--link-object', output, '-o', failure_exe])
	p = launch(launcher, failure_exe, [b'zero', b'valid'], out); assert p.returncode == 3 and not p.stdout and not p.stderr
	# Failed links must preserve the requested output bytes.
	for objects in [[], [provider, provider]]:
		target = out / 'preserved-output'; target.write_bytes(b'prior-output')
		p = process([compiler, out / 'unused.astra', *sum((['--link-object', str(o)] for o in objects), []), '-o', target])
		assert p.returncode == 1 and b'host linker' in p.stderr and target.read_bytes() == b'prior-output'
	recursive = out / 'recursive.astra'; recursive.write_text('extern(C) int once(); int main(string[] a){if(once()!=0){return main(a);}return len(a);}')
	once = out / 'once.c'; once.write_text('static int seen; int once(void){return seen++==0;}\n'); once_object = out / 'once.o'; cc('/usr/bin/gcc', once, once_object, ['-c'])
	run([compiler, recursive, '--link-object', provider, '--link-object', once_object, '-o', out / 'recursive'])
	p = launch(launcher, out / 'recursive', [b'name', b'one', b'two'], out); assert p.returncode == 3 and not p.stdout and not p.stderr
	return dict(valid=results, invalid_launches=len(invalid)*3+1, allocation_failure_status=3, old_main_status=19, zero_count='private C harness; no kernel argc=0 claim', launcher=str(launcher), entry=str(exe), failure_entry=str(failure_exe))


def composition(compiler, out):
	sources = [ROOT / 'examples/args/main.astra', ROOT / 'examples/args/views.astra', ROOT / 'examples/args/labels.astra', LIB / 'hosted/text.astra']
	canonical = {stage: run([compiler, '--dump-' + stage, *sources]) for stage in STAGES}
	arguments = [b'invocation', b'', 'é e\u0301😀'.encode(), b'--']
	expected = b''.join(b'arg: ' + argument + b'\n' for argument in arguments)
	for order in itertools.permutations(sources):
		for stage in STAGES:
			assert run([compiler, '--dump-' + stage, *order]) == canonical[stage], (stage, order)
		exe = out / 'composition'; run([compiler, *order, '--link-object', out / 'args-gcc.o', '--link-object', out / 'text.o', '-o', exe])
		p = launch(out / 'launcher', exe, arguments, out); assert p.returncode == 0 and p.stdout == expected and not p.stderr
	return dict(permutations=24, stages={stage: sha(data) for stage, data in canonical.items()}, output_sha256=sha(expected))


def qualify(compiler, out):
	compiler = compiler.resolve(); out = out.resolve(); out.mkdir(parents=True, exist_ok=True)
	result = dict(compiler=str(compiler), compiler_sha256=sha(compiler.read_bytes()))
	result['layout'] = {}
	for host in ['gcc', 'clang']:
		exe = out / ('provider-' + host); cc('/usr/bin/' + host, HERE / 'provider.c', exe); run([exe])
		probe = out / ('layout-' + host); cc('/usr/bin/' + host, HERE / 'layout.c', probe)
		layout = json.loads(run([probe])); assert layout == dict(pointer_bytes=8, char_bits=8, int_bytes=4, int_max=2147483647, data_offset=0, length_offset=8, stride=16, alignment=8)
		result['layout'][host] = layout
	result['utf8'] = utf8(out)
	result['source_contracts'] = source_contracts(compiler, out)
	result['native'] = native(compiler, out)
	result['snapshot_output'] = snapshot_output(compiler, out)
	result['cli'] = cli(compiler, out)
	result['composition'] = composition(compiler, out)
	result['commands'] = COMMANDS
	(out / 'qualification.json').write_text(json.dumps(result, indent='\t') + '\n')
	print('ARGS-1 qualification PASS')


if __name__ == '__main__':
	qualify(Path(sys.argv[1]), Path(sys.argv[2]))
