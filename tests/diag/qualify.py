# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Caller-information declaration, byte, effect and native qualification."""
from pathlib import Path
import hashlib
import itertools
import json
import os
import re
import resource
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / 'tests/diag'
LIB = ROOT / 'lib/astra'
STAGES = ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
MODES = ['O0', 'O2', 'fma', 'preserved']
COMMANDS = []
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def process(args, **kwargs):
	args = list(map(str, args))
	COMMANDS.append(dict(argv=args, cwd=str(kwargs.get('cwd', Path.cwd()))))
	return subprocess.run(args, capture_output=True, timeout=kwargs.pop('timeout', 90), env=kwargs.pop('env', dict(os.environ, CCACHE_DISABLE='1')), **kwargs)


def run(args, **kwargs):
	p = process(args, **kwargs)
	assert p.returncode == 0 and not p.stderr, (args, p.returncode, p.stdout[-2000:], p.stderr[-4000:])
	return p.stdout


def sha(data):
	return hashlib.sha256(data).hexdigest()


def write_json(path, value):
	path.write_text(json.dumps(value, indent='\t') + '\n')


def literal(text):
	return '"' + ''.join('\\U%08x' % ord(c) for c in text) + '"'


def escape(data):
	# Independent byte oracle, with no compiler SourceSpan or provider code.
	special = {0: b'\\0', 9: b'\\t', 10: b'\\n', 13: b'\\r', 34: b'\\"', 92: b'\\\\'}
	return b''.join(special[n] if n in special else ('\\u00%02X' % n).encode() if n < 32 or n == 127 else bytes([n]) for n in data)


def report(file, line, expression, message=b''):
	return b'Astra assertion failed\n  file: "' + escape(file) + b'"\n  line: ' + str(line).encode() + b'\n  expression: "' + escape(expression) + b'"\n  message: "' + escape(message) + b'"\n'


def cc(host, source, target, extra=()):
	run(['/usr/bin/' + host, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *extra, source, '-o', target])


def machine(ir, stem, mode):
	if mode == 'preserved':
		ir = re.sub(rb'(define internal fastcc [^\n]+) \{', rb'\1 noinline {', ir)
	input_ir = stem.with_suffix('.input.ll'); optimized = stem.with_suffix('.ll'); obj = stem.with_suffix('.o')
	input_ir.write_bytes(ir)
	run(['opt', '-passes=verify' if mode == 'O0' else '-passes=default<O2>', '-S', input_ir, '-o', optimized])
	run(['llc', '-filetype=obj', '-relocation-model=pic', '-O0' if mode == 'O0' else '-O2', *(['-mattr=+fma'] if mode == 'fma' else []), optimized, '-o', obj])
	stem.with_suffix('.machine').write_bytes(run(['objdump', '-dr', obj]))
	stem.with_suffix('.symbols').write_bytes(run(['nm', '-u', obj]))
	stem.with_suffix('.size').write_bytes(run(['size', '-A', obj]))
	return obj


def declarations(compiler, out):
	out.mkdir()
	check = 'void check(bool value,[CallerFilePath] string file,[CallerLineNumber] int line,[CallerArgumentExpression("value")] string expression){} '
	accepted = [
		check + 'void f(string file,int line,string expression){check(true);check(true,file);check(true,file,line);check(true,file,line,expression);}',
		'void f([CallerFilePath] string file){} void g(){f();f("explicit");}',
		'void f([CallerLineNumber] i32 line,[CallerFilePath] borrowed string file){} void g(){f();f(-9);f(-9,"");}',
		'void f(bool x,[CallerArgumentExpression("x")] string text){} void g(){f(false);}',
		'void f(bool x,[CallerArgumentExpression("\\u0078")] borrowed string text){} void g(){f(false);}',
		'int CallerFilePath(int CallerLineNumber){return CallerLineNumber;} int CallerArgumentExpression(){return CallerFilePath(7);}',
		'int assert_that(bool value){if(value){return 0;}return 1;} int main(){return assert_that(true);}',
		'int check_value(int value){return value;} int main(){return check_value(0);}',
		'struct S{int x; int check(int value,[CallerLineNumber] int line){return value+line;}} int main(){S s={x=0};return s.check(1);}',
		'class C{int x; init(int value,[CallerLineNumber] int line){this.x=value+line;} int check([CallerFilePath] string file){return file.byte_length;}} int main(){C c=C.init(1);return c.check();}',
		check + 'class C{int x;init(){this.x=0;}deinit(){check(true);}property int value{get{check(true);return this.x;}set(int x){check(true);this.x=x;}}}',
		'T id<T>(T x,[CallerFilePath] string f,[CallerLineNumber] int n,[CallerArgumentExpression("x")] string e){return x;} T outer<T>(T x){return id(x);} int f(){return outer(1)+id<int>(2);}',
		'owned T take<T>(owned T x,[CallerArgumentExpression("x")] string e) where T:Ownable{return move x;} owned T outer<T>(owned T x) where T:Ownable{return take(move x);}',
		'string f([CallerFilePath] string file){var saved="static";var x=file;return saved;}',
	]
	annotations = ['[CallerFilePath] string f', '[CallerLineNumber] int n', '[CallerArgumentExpression("x")] borrowed string e']
	for order in itertools.permutations(annotations):
		accepted.append('void f(bool x,' + ','.join(order) + '){} void g(){f(true);}')
	for type, value in [('bool', 'true'), ('i8', '1 as i8'), ('u8', '1 as u8'), ('i16', '1 as i16'), ('u16', '1 as u16'), ('int', '1'), ('u32', '1 as u32'), ('f32', '1.0f'), ('f64', '1.0d'), ('void*', 'null')]:
		accepted.append(f'T id<T>(T x,[CallerArgumentExpression("x")] string e){{return x;}} {type} f(){{return id({value});}}')
	rejected = [
		('void f([Unknown] int x){}', 'parse', b'unknown native parameter annotation'),
		('void f([CallerMemberName] string x){}', 'parse', b'unknown native parameter annotation'),
		('void f([CallerFilePath()] string x){}', 'parse', b'no payload'),
		('void f([CallerLineNumber(1)] int x){}', 'parse', b'no payload'),
		('void f([CallerArgumentExpression] string x){}', 'parse', b'one string literal'),
		('void f([CallerArgumentExpression()] string x){}', 'parse', b'one string literal'),
		('void f([CallerArgumentExpression(1)] string x){}', 'parse', b'one string literal'),
		('void f(int x,[CallerArgumentExpression(x)] string e){}', 'parse', b'one string literal'),
		('void f(int x,[CallerArgumentExpression("x","x")] string e){}', 'parse', b'exactly one string literal'),
		('void f([CallerLineNumber][CallerLineNumber] int x){}', 'parse', b'exactly one caller-information'),
		('void f([CallerFilePath][CallerLineNumber] int x){}', 'parse', b'exactly one caller-information'),
		('void f([CallerFilePath] string x=""){}', 'parse', b'default initializers'),
		('void f([CallerLineNumber] int x=1){}', 'parse', b'default initializers'),
		('void f([CallerFilePath] string x,bool later){}', 'semantic', b'required parameter cannot follow'),
		('void f(int value,[CallerArgumentExpression("missing")] string e){}', 'semantic', b'earlier required'),
		('void f(int value,[CallerArgumentExpression("e")] string e){}', 'semantic', b'earlier required'),
		('void f(int value,[CallerFilePath] string file,[CallerArgumentExpression("file")] string e){}', 'semantic', b'earlier required'),
		('void f(int value,[CallerArgumentExpression("value.field")] string e){}', 'semantic', b'earlier required'),
		('void f(int value,[CallerArgumentExpression("value\\0junk")] string e){}', 'semantic', b'earlier required'),
		('struct S{int n;void f([CallerArgumentExpression("this")] string e){}}', 'semantic', b'earlier required'),
		('extern(C) int f([CallerLineNumber] int line);', 'semantic', b'foreign or exported'),
		('export(C) int f([CallerLineNumber] int line){return line;}', 'semantic', b'foreign or exported'),
		('[CCode(text_abi="utf8-i32")] extern(C) void f([CallerFilePath] borrowed string file);', 'semantic', b'foreign or exported'),
		('string f([CallerFilePath] string file){return file;}', 'semantic', b'borrowed text cannot escape'),
		('string f(int value,[CallerArgumentExpression("value")] string e){var x=e;return x;}', 'semantic', b'borrowed text cannot escape'),
		(check + 'void g(){check();}', 'semantic', b'expects 1 through 4 arguments, provided 0'),
		(check + 'void g(){check(true,"",1,"",0);}', 'semantic', b'expects 1 through 4 arguments, provided 5'),
		(check + 'void g(){check(true,1);}', 'semantic', b'argument 2'),
		('void old(int x){} void g(){old();}', 'semantic', b"function 'old' expects 1 arguments, provided 0"),
		('void f<T>([CallerLineNumber] int line){} void g(){f();}', 'semantic', b'cannot infer'),
		('T f<T>(T x,[CallerLineNumber] int n){return x;} void g(){f();}', 'semantic', b'expects 1 through 2 arguments'),
		('T f<T>(T x,[CallerLineNumber] int n){return x;} void g(){f(1,2,3);}', 'semantic', b'expects 1 through 2 arguments'),
		('T f<T>(T x,[CallerFilePath] string path){return x;} void g(){f("text");}', 'semantic', b'GEN1_PLAIN_COPY'),
		('void f<T>(owned T x,[CallerFilePath] string f) where T:Ownable{} void outer<T>(owned T x) where T:Ownable{f(x);}', 'semantic', b'explicit'),
		('owned T make<T>(owned T x) where T:Ownable{return move x;} void take<T>(owned T x,[CallerLineNumber] int n) where T:Ownable{} void outer<T>(owned T x) where T:Ownable{take(make(move x));}', 'semantic', b'explicit'),
		('void f(int x,[CallerLineNumber] int n){} void f(int x,[CallerFilePath] string f){}', 'semantic', b'duplicate function'),
	]
	for type in ['bool', 'i8', 'u8', 'i16', 'u16', 'u32', 'f32', 'f64', 'string']:
		rejected.append((f'void f([CallerLineNumber] {type} line){{}}', 'semantic', b'exact int/i32'))
	for annotation in ['CallerFilePath', 'CallerArgumentExpression("x")']:
		for type in ['bool', 'int', 'u32', 'f32', 'f64', 'void*']:
			rejected.append((f'void f(int x,[{annotation}] {type} value){{}}', 'semantic', b'exact borrowed string'))
	for text, message in [('[CallerLineNumber] int f(){return 1;}', b'CCode'), ('struct S{[CallerLineNumber] int field;}', b'field'), ('class C{[CallerLineNumber] property int p{get{return 1;}}}', b'field'), ('void f(){[CallerLineNumber] int x=1;}', b'statement'), ('class C{property int p{get{return 1;}set([CallerLineNumber] int v){}}}', b'parameter type')]:
		rejected.append((text, 'parse', message))
	rows = []
	for i, source in enumerate(accepted):
		path = out / f'accepted-{i:03}.astra'; path.write_text(source)
		for stage in STAGES:
			data = run([compiler, '--dump-' + stage, path]); path.with_suffix('.' + stage).write_bytes(data)
		rows.append(dict(kind='accepted', path=path.name))
	for i, (source, stage, message) in enumerate(rejected):
		path = out / f'rejected-{i:03}.astra'; path.write_text(source)
		parsed = process([compiler, '--parse', path])
		assert (parsed.returncode == 0) == (stage != 'parse'), (path, stage, parsed.stderr)
		p = parsed if stage == 'parse' else process([compiler, '--check', path])
		assert p.returncode == 1 and message in p.stderr, (source, stage, message, p.returncode, p.stderr)
		path.with_suffix('.stderr').write_bytes(p.stderr); rows.append(dict(kind='rejected', path=path.name, stage=stage, diagnostic=p.stderr.decode()))
	api = out / 'invalid.vapi'; api.write_text('int f([CallerLineNumber] int line);')
	p = process([compiler, '--check', out / 'accepted-000.astra', '--vapi', api]); assert p.returncode == 1 and b'parameter' in p.stderr
	rows.append(dict(kind='vapi-rejected', diagnostic=p.stderr.decode()))
	write_json(out / 'results.json', rows)
	return rows


def failure_cases():
	# Each name-token line and expected expression is recorded independently.
	text = 'français e\u0301 😀 %s%n "quoted" \\path\n\r\t\0after' + ''.join(chr(n) for n in range(32) if n not in [0, 9, 10, 13]) + '\x7f'
	return [
		('that', 'int main(){\n\tassert_that(false);\n\treturn 0;\n}\n', 2, b'false', b'', None),
		('message-empty', 'int main(){\n\tassert_message(1 == 2, "");\n\treturn 0;\n}\n', 2, b'1 == 2', b'', None),
		('message-bytes', 'int main(){\n\tassert_message(false,' + literal(text) + ');\n\treturn 0;\n}\n', 2, b'false', text.encode(), None),
		('long', 'int main(){\n\tassert_message(false,' + literal('long %s%n é😀\0after ' * 4096) + ');\n\treturn 0;\n}\n', 2, b'false', ('long %s%n é😀\0after ' * 4096).encode(), None),
		('crlf', 'int main(){\r\n\t/* é😀 */ assert_that( /* outside */ ((1 as f64)\r\n\t/* inside */ == 2.0d) /* outside */ );\r\n\treturn 0;\r\n}', 2, b'((1 as f64)\r\n\t/* inside */ == 2.0d)', b'', None),
		('literal-spelling', 'const NAME="a\\0b";\nint main(){\n\tassert_that(NAME == "a\\0c");\n\treturn 0;\n}', 3, b'NAME == "a\\0c"', b'', None),
		('override-min', 'int main(){assert_message(false,"m","synthetic\\0tail",-2147483648,"provided\\nexpression");return 0;}', -2147483648, b'provided\nexpression', b'm', b'synthetic\0tail'),
		('override-max', 'int main(){assert_that(false,"/explicit/label",2147483647,"%s%n");return 0;}', 2147483647, b'%s%n', b'', b'/explicit/label'),
		('partial-file', 'int main(){\nassert_that(false,"manual");return 0;}', 2, b'false', b'', b'manual'),
		('partial-line', 'int main(){assert_that(false,"manual",-8);return 0;}', -8, b'false', b'', b'manual'),
		('forward', 'void wrapper(bool ready,[CallerFilePath] string f,[CallerLineNumber] int n,[CallerArgumentExpression("ready")] string e){assert_that(ready,f,n,e);}\nint main(){\nwrapper((2 == 3));return 0;}', 3, b'(2 == 3)', b'', None),
		('inner', 'void wrapper(bool ready){\nassert_that(ready);\n}\nint main(){wrapper(2 == 3);return 0;}', 2, b'ready', b'', None),
		('generic-definition', 'void wrapper<T>(T ready){\nassert_that(false);\n}\nint main(){wrapper<int>(1);return 0;}', 2, b'false', b'', None),
		('generic-forward', 'void wrapper<T>(T ready,[CallerFilePath] string f,[CallerLineNumber] int n,[CallerArgumentExpression("ready")] string e){assert_that(false,f,n,e);}\nint main(){\nwrapper<int>((7 as int));return 0;}', 3, b'(7 as int)', b'', None),
		('member', 'struct S{int n;void demand(bool x,[CallerFilePath] string f,[CallerLineNumber] int n,[CallerArgumentExpression("x")] string e){assert_that(x,f,n,e);}}\nint main(){S s={n=1};s\n.demand(2 == 3);return 0;}', 3, b'2 == 3', b'', None),
		('constructor', 'class C{int n;init(bool x,[CallerFilePath] string f,[CallerLineNumber] int n,[CallerArgumentExpression("x")] string e){this.n=0;assert_that(x,f,n,e);}}\nint main(){C c=C\n.init(2 == 3);return 0;}', 3, b'2 == 3', b'', None),
	]


def failures(build, out):
	out.mkdir(); compiler = build / 'astrac'; emitter = build / 'tests/diag/astra-diag-llvm'
	providers = {}
	for host in ['gcc', 'clang']:
		for kind in ['hosted', 'trap']:
			obj = out / f'{kind}-{host}.o'; cc(host, LIB / f'platform/diagnostics-{kind}.c', obj, ['-c', '-fno-stack-protector', '-ffreestanding']); providers[host, kind] = obj
			(out / f'{kind}-{host}.symbols').write_bytes(run(['nm', '-u', obj])); (out / f'{kind}-{host}.machine').write_bytes(run(['objdump', '-dr', obj]))
			if kind == 'trap':
				assert not run(['nm', '-u', obj]) and b'ud2' in run(['objdump', '-d', obj])
	rows = []
	for name, source, line, expression, message, override in failure_cases():
		path = out / (name + '.astra'); path.write_bytes(source.encode())
		emitted = out / (name + '.entry.ll'); run([emitter, '--emit', emitted, path.name, LIB / 'base/diagnostics.astra'], cwd=out); ir = emitted.read_bytes()
		assert b'declare void @astra_diag_assert_fail_v0(ptr, i32, i32, ptr, i32, ptr, i32)' in ir
		assert not re.search(rb'\b(noreturn|readnone|readonly|noalias|nonnull)\b', ir)
		expected = report(override if override is not None else path.name.encode(), line, expression, message); (out / (name + '.expected')).write_bytes(expected)
		for mode in MODES:
			obj = machine(ir, out / (name + '-' + mode), mode)
			for host in ['gcc', 'clang']:
				exe = out / f'{name}-{mode}-{host}'; run(['/usr/bin/' + host, obj, providers[host, 'hosted'], '-o', exe]); p = process([exe])
				assert p.returncode < 0 and not p.stdout and p.stderr == expected, (name, mode, host, p.returncode, p.stderr[:300], expected[:300])
				exe.with_suffix('.stderr').write_bytes(p.stderr); rows.append(dict(name=name, mode=mode, host=host, status=p.returncode, stderr_bytes=len(p.stderr), stderr_sha256=sha(p.stderr), object_sha256=sha(obj.read_bytes()), executable=str(exe)))
				if name in ['that', 'long']:
					for sink in ['closed', 'full']:
						if sink == 'full' and not Path('/dev/full').exists():
							continue
						if sink == 'closed':
							failed = subprocess.run([exe], stdout=subprocess.PIPE, stderr=subprocess.PIPE, preexec_fn=lambda: os.close(2), timeout=20)
						else:
							with open('/dev/full', 'wb') as full:
								failed = subprocess.run([exe], stdout=subprocess.PIPE, stderr=full, timeout=20)
						assert failed.returncode < 0 and not failed.stdout
						rows.append(dict(name=name, mode=mode, host=host, sink=sink, status=failed.returncode))
				if name == 'that':
					trap = out / f'trap-{mode}-{host}'; run(['/usr/bin/' + host, obj, providers[host, 'trap'], '-o', trap]); p = process([trap]); assert p.returncode < 0 and not p.stdout and not p.stderr
					rows.append(dict(name='trap', mode=mode, host=host, status=p.returncode, executable=str(trap)))
	write_json(out / 'results.json', rows)
	return rows


def equivalence(compiler, out):
	out.mkdir()
	declaration = 'int check(int value,[CallerFilePath] string file,[CallerLineNumber] int line,[CallerArgumentExpression("value")] string expression){if(file=="pair.astra" && line==2 && expression=="(1)"){return value;}return 99;}\n'
	path = out / 'pair.astra'; pairs = []
	for generic in [False, True]:
		prefix = declaration + ('T id<T>(T value,[CallerLineNumber] int line){return value;}\n' if generic else '')
		for stage in STAGES[2:]:
			call = 'check((1))'; explicit = 'check((1),"pair.astra",' + str(3 if generic else 2) + ',"(1)")'
			path.write_text(prefix + 'int main(){return ' + ('id(' + call + ')' if generic else call) + ';}')
			(out / (('generic' if generic else 'plain') + '.automatic.astra')).write_bytes(path.read_bytes())
			auto = run([compiler, '--dump-' + stage, path.name], cwd=out)
			path.write_text(prefix + 'int main(){return ' + ('id<int>(' + explicit + ',3)' if generic else explicit) + ';}')
			(out / (('generic' if generic else 'plain') + '.explicit.astra')).write_bytes(path.read_bytes())
			full = run([compiler, '--dump-' + stage, path.name], cwd=out)
			assert auto == full, (generic, stage)
			(out / (('generic' if generic else 'plain') + '.' + stage)).write_bytes(auto); pairs.append(dict(generic=generic, stage=stage, sha256=sha(auto)))
			# Independent explicit/inferred sites have one specialization for the same T.
	path.write_text('T id<T>(T x,[CallerFilePath] string f,[CallerLineNumber] int n,[CallerArgumentExpression("x")] string e){return x;} int a(){return id(1);} int b(){return id<int>(2);} f64 c(){return id(1.0d);}')
	instances = run([compiler, '--dump-instances', path.name], cwd=out); (out / 'dedup.instances').write_bytes(instances)
	assert instances.count(b'(generic-instance #') == 2 and b'(type-arguments int) (requests 2)' in instances and b'(type-arguments f64) (requests 1)' in instances, instances
	return pairs


def qualify(build, out):
	build = build.resolve(); out = out.resolve(); out.mkdir(parents=True, exist_ok=False)
	try:
		result = dict(declarations=declarations(build / 'astrac', out / 'declarations'), equivalence=equivalence(build / 'astrac', out / 'equivalence'), failures=failures(build, out / 'failures'))
		write_json(out / 'results.json', result)
	finally:
		write_json(out / 'commands.json', COMMANDS)
	print('DIAG-1 source and real failure qualification PASS')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(Path(sys.argv[1]), Path(sys.argv[2]))
