# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Real Astra builder execution, independent O2, byte oracles and allocation traces."""
from pathlib import Path
import hashlib
import json
import os
import re
import resource
import signal
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
LIBS = [ROOT / p for p in ["lib/astra/text/utf8-byte-builder.astra", "lib/astra/text/utf8-message.astra", "lib/astra/base/errors.astra"]]
TEXT = ROOT / "lib/astra/hosted/text.astra"
BAG = ROOT / "lib/astra/collections/bag.astra"
INVALID = {
	"continuation": [128], "bad-lead": [255], "truncated2": [195], "truncated3": [226,130],
	"truncated4": [240,159,150], "overlong2": [192,175], "overlong3": [224,128,128],
	"overlong4": [240,128,128,128], "surrogate": [237,160,128], "above-max": [244,144,128,128],
	"lead-f5": [245,128,128,128], "bad-second": [226,40,161], "bad-third": [226,130,65],
	"bad-fourth": [240,159,150,127], "invalid-tail": [97,98,255],
}
VALID = ["", "ASCII", "a\0b", "café", "cafe\u0301", "🖤", "\u0080\u07ff\u0800\ud7ff\ue000\U00010000\U0010ffff\ufffe"]


def instrument(ir, ssa):
	builder = re.search(r'\(class #(\d+) "Utf8ByteBuilder"', ssa)[1]
	message = re.search(r'\(class #(\d+) "Utf8Message"', ssa)[1]
	factory = re.search(r'\(function #(\d+) "utf8_message"', ssa)[1]
	def change(name, callback):
		nonlocal ir
		pattern = re.compile(r'(^define [^\n]* @' + re.escape(name) + r'\([^\n]*\n)(.*?)(^\})', re.M | re.S)
		match = pattern.search(ir); assert match, name
		body = callback(match[2]); ir = ir[:match.start(2)] + body + ir[match.end(2):]
	def entry(body, code):
		body, n = re.subn(r'(^[\w.]+:[^\n]*\n)', lambda m: m[0] + code, body, count=1, flags=re.M); assert n == 1
		return body
	def ctor(body):
		body, n = re.subn(r'^  ret void$', '  call void @builder_obs_init(ptr %this)\n  ret void', body, flags=re.M); assert n == 1
		return body
	change('astra.ctor.' + builder, ctor)
	def dtor(body): return entry(body, '  call void @builder_obs_drop(ptr %this)\n')
	change('astra.dtor.' + builder, dtor)
	for method, kind in [(2, 1), (3, 2), (4, 3)]:
		def operation(body, kind=kind):
			args = 'ptr null, i32 %p0' if kind == 1 else 'ptr %p0.base, i32 %p0.length' if kind == 2 else 'ptr null, i32 0'
			body = entry(body, f'  call void @builder_obs_begin(i32 {kind}, ptr %this, {args})\n')
			counter = 0
			def leave(match):
				nonlocal counter
				counter += 1; ty, result = match[1], match[2]; name = '%obs.exit.' + str(counter)
				code = ''
				if ty == 'i1':
					if result in ['true', 'false']: status = '1' if result == 'true' else '0'
					else: code = f'  {name} = zext i1 {result} to i32\n'; status = name
				else:
					code = f'  {name}.ok = icmp eq ptr {result}, null\n  {name} = zext i1 {name}.ok to i32\n'; status = name
				return code + f'  call void @builder_obs_leave(i32 {kind}, ptr %this, i32 {status})\n' + match[0]
			body, n = re.subn(r'^  ret (i1|ptr) ([\w%.]+)$', leave, body, flags=re.M); assert n > 0
			return body
		change(f'astra.class.method.{builder}.{method}', operation)
	def factory_body(body):
		body = entry(body, '  call void @utf8_observe_input(ptr %p0.base, i32 %p0.length)\n')
		body, n = re.subn(r'(^  store ptr ([^,]+), ptr %success.storage[^\n]*\n)', r'\1  call void @utf8_observe_owner(ptr \2)\n  call void @builder_obs_message()\n', body, flags=re.M); assert n == 1
		return body
	change('astra.fn.' + factory, factory_body)
	change('astra.dtor.' + message, lambda body: entry(body, '  call void @utf8_observe_drop(ptr %this)\n'))
	return ir + '''
declare void @builder_obs_init(ptr)
declare void @builder_obs_begin(i32, ptr, ptr, i32)
declare void @builder_obs_leave(i32, ptr, i32)
declare void @builder_obs_drop(ptr)
declare void @builder_obs_message()
declare void @utf8_observe_input(ptr, i32)
declare void @utf8_observe_owner(ptr)
declare void @utf8_observe_drop(ptr)
'''


def main(compiler, emitter, output):
	compiler, emitter, output = [Path(p).resolve() for p in [compiler, emitter, output]]
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True); out = Path(tempfile.mkdtemp(prefix="run-", dir=output))
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0)); rows = []; identities = {}
	source_paths = [*LIBS, TEXT, BAG, *HERE.glob('*.astra'), HERE / 'observer.c', HERE / 'limit-observer.c', HERE / 'execute.py', HERE.parent / 'text-own-1a/observer.c', ROOT / 'examples/utf8-byte-builder/main.astra', *[ROOT / f'lib/astra/platform/{name}-posix.c' for name in ['args', 'text']]]
	source_hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in source_paths}
	def run(args, expected=0, stdout=b"", memory=False, save=None, extra_env=None):
		args = list(map(str, args)); p = subprocess.run(args, cwd=ROOT, capture_output=True, timeout=90, env=dict(os.environ, CCACHE_DISABLE="1", **(extra_env or {})))
		valid = p.returncode == expected and (stdout is None or save is not None or p.stdout == stdout)
		if memory:
			valid &= all(t in p.stderr for t in [b"ERROR SUMMARY: 0 errors", b"in use at exit: 0 bytes in 0 blocks", b"(suppressed: 0 from 0)"])
		else: valid &= not p.stderr
		if save: save.write_bytes(p.stdout)
		rows.append(dict(command=args, expected=expected, actual=p.returncode, stdout=p.stdout.decode(), stderr=p.stderr.decode(), memory=memory, extra_env=extra_env, passed=bool(valid)))
		(out / "checks.json").write_text(json.dumps(rows, indent=2, ensure_ascii=False) + "\n")
		assert valid, rows[-1]
		return p.stdout
	providers = []
	for name in ['args', 'text']:
		obj = out / (name + '.o'); providers.append(obj)
		run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', ROOT / f'lib/astra/platform/{name}-posix.c', '-o', obj])
	observer = out / 'observer.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-fno-builtin', '-c', HERE / 'observer.c', '-o', observer])
	vg = ['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99']
	memory_available = shutil.which('valgrind') is not None
	def qualify(label, sources, cases, observed=False, stages=False):
		inputs = [*sources, *LIBS]
		if stages:
			for stage in ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']:
				run([compiler, '--dump-' + stage, *inputs], save=out / (label + '.' + stage))
		native, ir, optimized, obj, o2 = [out / (label + suffix) for suffix in ['', '.ll', '-O2.ll', '-O2.o', '-O2']]
		run([compiler, *inputs, *[a for obj in providers for a in ['--link-object', obj]], '-o', native])
		run([emitter, '--emit', ir, *inputs]); run(['opt', '-passes=verify', '-disable-output', ir])
		run(['opt', '-passes=default<O2>', '-S', ir, '-o', optimized]); run(['opt', '-passes=verify', '-disable-output', optimized])
		run(['llc', '-O2', '-filetype=obj', '-relocation-model=pic', optimized, '-o', obj]); run(['cc', obj, *providers, '-o', o2])
		for program in [native, o2]:
			for args, expected in cases:
				run([program, *args], stdout=expected)
				if memory_available: run([*vg, program, *args], stdout=expected, memory=True)
		identities[label] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [native, o2, ir]}
		if observed:
			ssa = run([compiler, '--dump-ssa', *inputs], save=out / (label + '.ssa')).decode()
			traced = out / (label + '-observed.ll'); traced.write_text(instrument(ir.read_text(), ssa))
			traces = []
			for suffix, passes, level in [('native', 'verify', '-O0'), ('O2', 'default<O2>', '-O2')]:
				opt_ir = out / (label + '-observed-' + suffix + '.ll'); obs_obj = opt_ir.with_suffix('.o'); program = opt_ir.with_suffix('')
				run(['opt', '-passes=' + passes, '-S', traced, '-o', opt_ir]); run(['opt', '-passes=verify', '-disable-output', opt_ir])
				run(['llc', level, '-filetype=obj', '-relocation-model=pic', opt_ir, '-o', obs_obj]); run(['cc', obs_obj, observer, *providers, '-o', program])
				actual = []
				for args, expected in cases:
					trace = run([program, *args], stdout=None)
					if label in ['smoke', 'application']: assert b'2->3 used=2' in trace
					error = args == ['error']
					owners, payloads, allocations, builders, growths = {
						'smoke': (2, 2, 12, 1, 2), 'positive': (5, 3, 22, 2, 4),
						'application': (2, 2, 18, 1, 3) if error else (3, 3, 17, 1, 2),
					}[label]
					assert [int(x) for x in re.findall(rb'^owner-drop (\d+)$', trace, re.M)] == list(range(owners, 0, -1))
					assert f'observer: owners={owners} drops={owners} objects={owners} payloads={payloads} allocations={allocations}\n'.encode() in trace
					assert trace.endswith(f'builder-observer: builders={builders} drops={builders} growths={growths}\n'.encode())
					application_output = re.sub(rb'^(builder-[^\n]*|owner-drop \d+|observer:[^\n]*)\n', b'', trace, flags=re.M)
					assert application_output == expected, (label, application_output, expected)
					(out / (label + '-trace-' + suffix + '-' + ('-'.join(args) or 'normal') + '.txt')).write_bytes(trace)
					actual.append(trace)
				traces.append(actual)
			assert traces[0] == traces[1], label
		return ir
	qualify('smoke', [HERE / 'smoke.astra'], [([], b'')], observed=True, stages=True)
	qualify('positive', [HERE / 'positive.astra', TEXT], [([], '🖤a\0bcafe\u0301\n'.encode())], observed=True, stages=True)
	qualify('privacy', [HERE / 'privacy.astra', HERE / 'privacy-model.astra'], [([], b'')], stages=True)
	application = [ROOT / 'examples/utf8-byte-builder/main.astra', BAG, TEXT]
	qualify('application', application, [([], b'assembled\n'), (['early'], b'early\n'), (['error'], b'caught\n')], observed=True, stages=True)
	for number, text in enumerate(VALID):
		values = text.encode(); split = len(values) // 2; literal = json.dumps(text, ensure_ascii=False)
		lines = ['int main(){try{var b=new Utf8ByteBuilder();']
		for tag, part in [('a', values[:split]), ('z', values[split:])]:
			lines += [f'var {tag}=new u8[{len(part)}];'] + [f'{tag}[{i}]={v};' for i, v in enumerate(part)]
			lines += [f'if(!b.append_bytes({tag})){{return 81;}}release {tag};']
		lines += [f'var m=b.snapshot();release b;if(m.text!={literal}||m.text.byte_length!={len(values)}){{return 82;}}if(!println(m.text)){{return 83;}}', '}catch(InvalidUtf8 error){return 84;}return 0;}']
		path = out / f'valid-{number}.astra'; path.write_text('\n'.join(lines))
		qualify(f'valid-{number}', [path, TEXT], [([], values + b'\n')])
	for label, values in INVALID.items():
		path = out / (label + '.astra')
		writes = ''.join(f'bytes[{i}]={v};' for i, v in enumerate(values))
		path.write_text('''bool reject(Utf8ByteBuilder b){try{var m=b.snapshot();return false;}catch(InvalidUtf8 error){return error.message=="invalid UTF-8";}}
int main(){var b=new Utf8ByteBuilder();var bytes=new u8[''' + str(len(values)) + '];' + writes + f'if(!b.append_bytes(bytes)||!reject(b)||b.byte_count()!={len(values)}||!reject(b)){{return 81;}}release bytes;return 0;}}')
		qualify(label, [path], [([], b'')])
		# Authorized null receiver access remains a runtime trap, including a
		# folded field address at both zero and nonzero layout offsets.
	for index in [0, 1]:
		source = out / f'null-private-{index}.astra'
		source.write_text(f'class Secret{{private int first;private int second;init(){{this.first=1;this.second=2;}}int read_null(){{Secret other=null;return other.{"first" if index == 0 else "second"};}}}}int main(){{var value=new Secret();return value.read_null();}}\n')
		ir = out / f'null-private-{index}.ll'; optimized = ir.with_name(ir.stem + '-O2.ll'); obj = optimized.with_suffix('.o'); native = ir.with_suffix(''); o2 = optimized.with_suffix('')
		run([compiler, source, '-o', native]); run([emitter, '--emit', ir, source]); run(['opt', '-passes=verify', '-disable-output', ir])
		run(['opt', '-passes=default<O2>', '-S', ir, '-o', optimized]); run(['opt', '-passes=verify', '-disable-output', optimized])
		run(['llc', '-O2', '-filetype=obj', '-relocation-model=pic', optimized, '-o', obj]); run(['cc', obj, '-o', o2])
		for program in [native, o2]: run([program], expected=-signal.SIGILL)
		# Only observer calls are added to already verified LLVM. A separate C test
		# observer seeds an impossible near-limit count and restores it on return;
		# no corrupted verifier artifact or forged pointer is ever executed. This
		# tests the actual library guard, not the availability of a huge allocation.
	limit_source = out / 'limit.astra'
	limit_source.write_text('''int main(string[] args){var b=new Utf8ByteBuilder();int count=1;
if(len(args)>1&&args[1]=="empty"){count=0;}var bytes=new u8[count];
bool accepted=b.append_bytes(bytes);if(accepted!=(count==0)||b.byte_count()!=0||b.capacity()!=0){return 81;}return 0;}\n''')
	limit_ir = out / 'limit.ll'; limit_ssa = out / 'limit.ssa'
	run([emitter, '--emit', limit_ir, limit_source, *LIBS]); run([compiler, '--dump-ssa', limit_source, *LIBS], save=limit_ssa)
	builder_id = re.search(r'\(class #(\d+) "Utf8ByteBuilder"', limit_ssa.read_text())[1]
	ir = limit_ir.read_text(); pattern = re.compile(r'(^define [^\n]* @astra.class.method.' + builder_id + r'.3\([^\n]*\n)(.*?)(^\})', re.M | re.S)
	match = pattern.search(ir); assert match
	body, n = re.subn(r'(^[\w.]+:[^\n]*\n)', r'\1  call void @builder_limit_enter(ptr %this)\n', match[2], count=1, flags=re.M); assert n == 1
	counter = 0
	def limit_exit(match):
		nonlocal counter
		counter += 1; value = match[1]
		if value in ['true', 'false']: code = ''; accepted = '1' if value == 'true' else '0'
		else: accepted = '%limit.accepted.' + str(counter); code = f'  {accepted} = zext i1 {value} to i32\n'
		return code + f'  call void @builder_limit_leave(ptr %this, i32 {accepted})\n' + match[0]
	body, n = re.subn(r'^  ret i1 ([\w%.]+)$', limit_exit, body, flags=re.M); assert n > 0
	limit_ir.write_text(ir[:match.start(2)] + body + ir[match.end(2):] + '\ndeclare void @builder_limit_enter(ptr)\ndeclare void @builder_limit_leave(ptr, i32)\n')
	limit_observer = out / 'limit-observer.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-fno-builtin', '-c', HERE / 'limit-observer.c', '-o', limit_observer])
	for suffix, passes, level in [('native', 'verify', '-O0'), ('O2', 'default<O2>', '-O2')]:
		optimized = out / ('limit-' + suffix + '.ll'); obj = optimized.with_suffix('.o'); program = optimized.with_suffix('')
		run(['opt', '-passes=' + passes, '-S', limit_ir, '-o', optimized]); run(['opt', '-passes=verify', '-disable-output', optimized])
		run(['llc', level, '-filetype=obj', '-relocation-model=pic', optimized, '-o', obj]); run(['cc', obj, limit_observer, *providers, '-o', program])
		run([program], stdout=b'limit-overflow rejected without allocation or mutation\n')
		run([program, 'empty'], stdout=b'limit-empty accepted without allocation or mutation\n')
		run([program], expected=-signal.SIGILL, stdout=b'limit-growth rejected allocation=2147483647\n', extra_env={'BUILDER_LIMIT_MODE': 'growth'})
		# Merely selecting unused opt-in sources must not add emitted dependencies.
	unused = out / 'unused.astra'; unused.write_text('int main(){return 0;}\n')
	base_ir = out / 'unused-base.ll'; run([emitter, '--emit', base_ir, unused])
	selected_ir = qualify('unused-selected', [unused], [([], b'')])
	def required(ir): return sorted(re.findall(r'^declare [^@]*@([^ (]+)', ir.read_text(), re.M))
	base_opt = out / 'unused-base-O2.ll'
	run(['opt', '-passes=default<O2>', '-S', base_ir, '-o', base_opt])
	assert '@calloc' not in base_ir.read_text() and '@free' not in base_ir.read_text()
	assert required(base_opt) == required(out / 'unused-selected-O2.ll')
	dependencies = run(['readelf', '-d', out / 'unused-selected'], stdout=None).decode()
	assert all(name not in dependencies for name in ['glib', 'gobject', 'uring'])
	assert source_hashes == {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in source_hashes}, 'qualification source changed during execution'
	(out / 'identities.json').write_text(json.dumps(dict(compiler=hashlib.sha256(compiler.read_bytes()).hexdigest(), emitter=hashlib.sha256(emitter.read_bytes()).hexdigest(), sources=source_hashes, programs=identities), indent=2) + '\n')
	print(json.dumps(dict(output=str(out), commands=len(rows), all_passed=True, memory_available=memory_available, memory_runs=sum(r['memory'] for r in rows)), indent=2))


if __name__ == '__main__':
	main(*sys.argv[1:])
