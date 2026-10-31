# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent outbound C and hosted output qualification through the real CLI."""
from pathlib import Path
import hashlib
import itertools
import json
import os
import re
import resource
import shutil
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / 'tests/text-io'
LIB = ROOT / 'lib/astra'
STAGES = ['semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
COMMANDS = []


def process(args, **kwargs):
	args = list(map(str, args)); COMMANDS.append(args)
	return subprocess.run(args, capture_output=True, timeout=kwargs.pop('timeout', 90), env=kwargs.pop('env', dict(os.environ, CCACHE_DISABLE='1')), **kwargs)


def run(args, **kwargs):
	p = process(args, **kwargs)
	assert p.returncode == 0 and p.stderr == b'', (args, p.returncode, p.stdout[-2000:], p.stderr[-3000:])
	return p.stdout


def sha(data):
	return hashlib.sha256(data).hexdigest()


def literal(text):
	return '"' + text.replace('\\', '\\\\').replace('"', '\\"').replace('\0', '\\0').replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t') + '"'


def ordinal(compiler, sources, name, extra=()):
	return re.search(rb'\(function #(\d+) "' + name.encode() + b'"', run([compiler, '--dump-ssa', *sources, *extra]))[1].decode()


def object_file(ir, stem, mode):
	stem.with_suffix('.input.ll').write_bytes(ir)
	run(['opt', '-passes=verify' if mode in ['O0', 'preserved'] else '-passes=default<O2>', '-S', stem.with_suffix('.input.ll'), '-o', stem.with_suffix('.ll')])
	run(['llc', '-O0' if mode == 'O0' else '-O2', '-filetype=obj', '-relocation-model=pic', *(['-mattr=+fma'] if mode == 'fma' else []), stem.with_suffix('.ll'), '-o', stem.with_suffix('.o')])
	return stem.with_suffix('.o')


def cc(host, source, target, extra=()):
	run([host, '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2', *extra, '-c', source, '-o', target])


def native(compiler, out):
	source = HERE / 'fixtures/native.astra'
	text = source.read_text(); pattern = r'(\[CCode[^\n]*\]\n)extern\(C\) ([^\n]*;)'
	declarations = re.findall(pattern, text); assert len(declarations) == 6
	vapi = out / 'native.vapi'; vapi.write_text('\n'.join(metadata + declaration for metadata, declaration in declarations))
	vapi_source = out / 'native-vapi.astra'; vapi_source.write_text(re.sub(pattern, '', text))
	equivalence = {}
	for stage in STAGES:
		original = run([compiler, '--dump-' + stage, source]); normalized = run([compiler, '--dump-' + stage, vapi_source, '--vapi', vapi]); assert original == normalized, stage; equivalence[stage] = sha(original)
	(out / 'native-vapi-equivalence.json').write_text(json.dumps(equivalence, indent='\t') + '\n')
	ir = run([compiler, '--dump-llvm', source]); entry = ordinal(compiler, [source], 'entry')
	ir += f'\ndefine i32 @text_io_entry(ptr %a, i32 %an, ptr %b, i32 %bn, ptr %token) {{\n\t%r = call fastcc i32 @astra.fn.{entry}(ptr %a, i32 %an, ptr %b, i32 %bn, ptr %token)\n\tret i32 %r\n}}\n'.encode()
	assert b'declare i32 @unfamiliar_reader(i32, ptr, i32, float, ptr, i32, double, ptr)' in ir
	assert not re.search(rb'\b(strlen|strcmp|malloc|memcpy|memmove)\b', ir)
	for line in ir.splitlines():
		if b'declare ' in line or b'call i32 @unfamiliar_reader' in line:
			assert not re.search(rb'\b(readonly|readnone|noalias|nonnull|dereferenceable|speculatable)\b', line)
	records = []
	for host in ['gcc', 'clang']:
		cc(host, HERE / 'observer.c', out / (host + '-observer.o'))
		cc(host, HERE / 'native-harness.c', out / (host + '-harness.o'))
	for mode in ['O0', 'O2', 'fma', 'preserved']:
		stem = out / ('native-' + mode); obj = object_file(ir, stem, mode)
		for host in ['gcc', 'clang']:
			exe = out / ('native-' + mode + '-' + host)
			run([host, obj, out / (host + '-observer.o'), out / (host + '-harness.o'), '-o', exe]); assert run([exe]) == b''
		records.append(dict(mode=mode, object_sha256=sha(obj.read_bytes()), undefined=run(['nm', '-u', obj]).decode(), sizes=run(['size', '-A', obj]).decode(), disassembly=run(['objdump', '-dr', obj]).decode()))
	return records


def model(stream, count, newline, null, events):
	payload = b'a\0b%n'; emitted = b''; counts = []; position = 0
	if stream not in [1, 2] or newline not in [0, 1] or count < 0 or (count and null):
		return dict(status=1, calls=0, counts=[], hex='')
	for requested in [payload[:count], b'\n' if newline else b'']:
		while requested:
			counts.append(len(requested)); event = events[position] if position < len(events) else 99; position += 1
			if event == -1:
				continue
			if event <= 0:
				return dict(status=1, calls=position, counts=counts, hex=emitted.hex())
			prefix = requested[:event]; emitted += prefix; requested = requested[len(prefix):]
	return dict(status=0, calls=position, counts=counts, hex=emitted.hex())


def provider_progress(out):
	scenarios = [(1, 5, 1, 0, events) for length in range(4) for events in itertools.product([-4, -3, -2, -1, 0, 1, 2, 5], repeat=length)]
	scenarios += [(stream, count, newline, null, ()) for stream, count, newline, null in itertools.product([0, 1, 2, 3], [-1, 0, 5], [-1, 0, 1, 2], [0, 1])]
	digests = {}
	for host in ['gcc', 'clang']:
		provider = out / ('intercept-' + host + '.o'); harness = out / ('intercept-harness-' + host + '.o'); exe = out / ('intercept-' + host)
		cc(host, LIB / 'platform/text-posix.c', provider, ['-Dwrite=intercepted_write']); cc(host, HERE / 'provider-intercept.c', harness)
		run([host, provider, harness, '-o', exe]); rows = []
		for stream, count, newline, null, events in scenarios:
			actual = json.loads(run([exe, stream, count, newline, null, *events])); expected = model(stream, count, newline, null, events)
			assert actual == expected, (host, stream, count, newline, null, events, expected, actual)
			rows.append(actual)
		digests[host] = sha(json.dumps(rows, sort_keys=True).encode())
	assert digests['gcc'] == digests['clang']
	return dict(scenarios_per_compiler=len(scenarios), digests=digests)


def output(compiler, out, provider):
	texts = ['ASCII', 'français e\u0301 😀', '', 'a\0b\0c', '%s%n', 'z' * 200000]
	lines = ['int main(){']; expected = [b'', b'']
	for repetition in range(3):
		for text in texts:
			for name, stream, newline in [('print', 0, False), ('println', 0, True), ('print_stderr', 1, False), ('println_stderr', 1, True)]:
				lines.append(f'\tif (!{name}({literal(text)})) {{ return 1; }}')
				expected[stream] += text.encode() + (b'\n' if newline else b'')
	lines.append('\treturn 0;\n}')
	source = out / 'output.astra'; source.write_text('\n'.join(lines)); exe = out / 'output'
	run([compiler, source, LIB / 'hosted/text.astra', '--link-object', provider, '-o', exe])
	p = process([exe]); assert p.returncode == 0 and [p.stdout, p.stderr] == expected
	(out / 'stdout.bin').write_bytes(p.stdout); (out / 'stderr.bin').write_bytes(p.stderr)
	with (out / 'redirected-stdout.bin').open('wb') as stdout, (out / 'redirected-stderr.bin').open('wb') as stderr:
		p = subprocess.run([exe], stdout=stdout, stderr=stderr, timeout=60); assert p.returncode == 0
	assert (out / 'redirected-stdout.bin').read_bytes() == expected[0] and (out / 'redirected-stderr.bin').read_bytes() == expected[1]
	# Normal failure is handled by returning; the class field is cleaned normally.
	failure = out / 'failure.astra'
	failure.write_text('class Buffer { owned int[] data; init(){this.data=new int[4];} deinit(){if(!println_stderr("cleanup")){return;}} } int main(){var b=Buffer.init();if(!println("payload")){return 0;}return 7;}')
	bad = out / 'failure'; run([compiler, failure, LIB / 'hosted/text.astra', '--link-object', provider, '-o', bad])
	p = process([bad], preexec_fn=lambda: os.close(1)); assert p.returncode == 0 and p.stderr == b'cleanup\n'
	failures = {'closed_stdout': p.returncode}
	if Path('/dev/full').exists():
		with open('/dev/full', 'wb') as full:
			p = subprocess.run([bad], stdout=full, stderr=subprocess.PIPE, timeout=30)
		assert p.returncode == 0 and p.stderr == b'cleanup\n'; failures['dev_full'] = p.returncode
	for ignore in [False, True]:
		read, write = os.pipe(); os.close(read)
		try:
			def child_policy():
				signal.signal(signal.SIGPIPE, signal.SIG_IGN if ignore else signal.SIG_DFL)
			p = subprocess.run([bad], stdout=write, stderr=subprocess.PIPE, preexec_fn=child_policy, timeout=30)
		finally:
			os.close(write)
		assert p.returncode == (0 if ignore else -signal.SIGPIPE) and p.stderr == (b'cleanup\n' if ignore else b'')
		failures['pipe_ignore' if ignore else 'pipe_default'] = p.returncode
	for name, descriptor in [('print', 1), ('println', 1), ('print_stderr', 2), ('println_stderr', 2)]:
		closed = out / (name + '-closed.astra'); closed.write_text(f'int main(){{if(!{name}("payload")){{return 0;}}return 7;}}'); exe = out / (name + '-closed')
		run([compiler, closed, LIB / 'hosted/text.astra', '--link-object', provider, '-o', exe]); result = process([exe], preexec_fn=lambda: os.close(descriptor)); assert result.returncode == 0
		failures[name + '_closed'] = result.returncode
		if Path('/dev/full').exists():
			with open('/dev/full', 'wb') as full:
				result = subprocess.run([exe], stdout=full if descriptor == 1 else subprocess.PIPE, stderr=full if descriptor == 2 else subprocess.PIPE, timeout=30)
			assert result.returncode == 0; failures[name + '_full'] = result.returncode
	for name in ['print', 'print_stderr']:
		empty = out / (name + '-empty.astra'); empty.write_text(f'int main(){{if(!{name}("")){{return 1;}}return 0;}}'); exe = out / (name + '-empty')
		run([compiler, empty, LIB / 'hosted/text.astra', '--link-object', provider, '-o', exe]); assert process([exe], preexec_fn=lambda: (os.close(1), os.close(2))).returncode == 0
	return dict(stdout_bytes=len(expected[0]), stderr_bytes=len(expected[1]), stdout_sha256=sha(expected[0]), stderr_sha256=sha(expected[1]), failures=failures)


def negatives(compiler, out):
	prefix = '[CCode(text_abi="utf8-i32")] '
	declarations = ['extern(C) int f(borrowed string x);', prefix+'extern(C) int f(string x);', prefix+'extern(C) int f(owned string x);', prefix+'extern(C) string f(borrowed string x);', prefix+'int f(string x){return 0;}', prefix+'export(C) int f(string x){return 0;}', prefix+'extern(C) int f(int x);', '[CCode(text_abi="unknown")] extern(C) int f(borrowed string x);', prefix+'extern(C) int f(borrowed string x, u8 y);', prefix+'extern(C) int f(borrowed string x, f32<2> y);', prefix+'extern(C) int f(borrowed string x, int* y);', prefix+'extern(C) int f(borrowed string x, bool y);', prefix+'extern(C) bool f(borrowed string x);', prefix+'extern(C) int f(borrowed string x); int main(){return f("a",3);}', prefix+'extern(C) int f(borrowed string x); int main(){return f();}', prefix+'extern(C) int f(borrowed string x); string g(string x){f(x);return x;}', 'void f(){string* x=null;}', 'void f(void* p){var x=p as string;}', 'class X {string value;}', 'void f(){string[] x=null;}', 'T identity<T>(T x){return x;} void f(){var x=identity("a");}', 'void f(){var x="a";x[0]=1;}', 'string f(){return "x";} void g(){var x=f().other;}']
	path = out / 'negative.astra'; rows = []
	for text in declarations:
		path.write_text(text); p = process([compiler, '--dump-llvm', path]); assert p.returncode == 1 and p.stderr and not p.stdout, (text, p)
		for spelling, diagnostic in [('string*', b'typed pointer pointee'), ('p as string', b'unsupported integer conversion source'), ('string[]', b'no null state')]:
			if spelling in text:
				assert diagnostic in p.stderr, (text, p.stderr)
		rows.append(dict(source=text, diagnostic=p.stderr.decode().replace(str(out), '<qualification>')))
	path.write_text('int main(){return 0;}'); api = out / 'negative.vapi'
	for declaration in ['int f(string x);', 'int f(borrowed string x);', prefix+'int f(string x);', prefix+'string f(borrowed string x);', prefix+'int f(int x);', '[CCode(text_abi="other")] int f(borrowed string x);', prefix+'int f(owned string x);']:
		api.write_text(declaration); p = process([compiler, '--dump-llvm', path, '--vapi', api]); assert p.returncode == 1 and not p.stdout
		rows.append(dict(vapi=declaration, diagnostic=p.stderr.decode().replace(str(out), '<qualification>')))
	for declaration in ['int b(void* x, int n);', 'int b(borrowed string x);', 'int b(borrowed string x, int n);']:
		api.write_text('[CCode(cname="shared",text_abi="utf8-i32")] int a(borrowed string x);\n[CCode(cname="shared"'+(',text_abi="utf8-i32"' if 'string' in declaration else '')+')] '+declaration)
		p = process([compiler, '--dump-llvm', path, '--vapi', api]); assert p.returncode == 1 and b'declared more than once' in p.stderr
		rows.append(dict(duplicate=declaration, diagnostic=p.stderr.decode().replace(str(out), '<qualification>')))
	return rows


def sequencing(compiler, out):
	cc('gcc', HERE / 'effects.c', out / 'effects.o')
	declarations = 'extern(C) int record(int n); extern(C) int zero(); [CCode(text_abi="utf8-i32")] extern(C) int ordered(int a, borrowed string x, int b, borrowed string y, int c);'
	records = []
	for trapped in ['none', 'first', 'second']:
		first_trap = 'int bad=1/zero();' if trapped == 'first' else ''
		second_trap = 'int bad=1/zero();' if trapped == 'second' else ''
		source = out / ('order-' + trapped + '.astra')
		source.write_text(declarations + f'string first(){{record(2);{first_trap}return "left";}} string second(){{record(4);{second_trap}return "right";}}' + 'f64 number(){record(3);return 3.0d;} int predicate(bool x){if(x){return 1;}return 0;} string eqleft(){record(5);return "a\\0b";} string eqright(){record(6);return "a\\0b";} int main(){if(false && ordered(1,"left",3,"right",1)==0){return 1;} if(!(true || ordered(1,"left",3,"right",1)==0)){return 2;} var join="left"; if(number()>0.0d){join="left";} else {join="other";} if(join!="left"){return 3;} int result=ordered(record(1),first(),number() as int,second(),predicate(eqleft()==eqright()));record(9);return result;}')
		ir = run([compiler, '--dump-llvm', source]); n = ordinal(compiler, [source], 'main'); ir += f'\ndefine i32 @main() {{\n\t%r = call fastcc i32 @astra.fn.{n}()\n\tret i32 %r\n}}\n'.encode()
		expected = bytes([3, 1, 2] if trapped == 'first' else [3, 1, 2, 3, 4] if trapped == 'second' else [3, 1, 2, 3, 4, 5, 6, 8, 9])
		for mode in ['O0', 'O2', 'fma', 'preserved']:
			stem = out / ('order-' + trapped + '-' + mode); obj = object_file(ir, stem, mode); run(['gcc', obj, out / 'effects.o', '-o', stem]); result = process([stem])
			assert result.returncode == 0 if trapped == 'none' else result.returncode < 0
			assert result.stdout == b'' and result.stderr == expected, (trapped, mode, result.stderr, expected)
			records.append(dict(case=trapped, mode=mode, status=result.returncode, trace=result.stderr.hex()))
	return records


def composition(compiler, out, provider):
	sources = [ROOT / 'examples/text-output' / name for name in ['labels.astra', 'model.astra', 'main.astra']] + [LIB / 'hosted/text.astra']
	extra = [LIB / 'base/contracts.astra']; failure = compiler.parent / 'lib/astra/failure-trap.o'
	expected = [b'Astra \xc3\xa9\0\xf0\x9f\x98\x80\n%s%n\0after', b'status\0okreleased\n']
	records = {}; comparisons = 0
	for stage in ['syntax', *STAGES]:
		canonical = run([compiler, '--dump-' + stage, *sources, *extra]); (out / ('composition.' + stage)).write_bytes(canonical)
		for permutation in itertools.permutations(sources):
			assert run([compiler, '--dump-' + stage, *permutation, *extra]) == canonical; comparisons += 1
		records[stage] = sha(canonical)
	for index, permutation in enumerate(itertools.permutations(sources)):
		exe = out / ('composition-' + str(index)); run([compiler, *permutation, *extra, '--link-object', provider, '--link-object', failure, '-o', exe]); result = process([exe]); assert result.returncode == 0 and [result.stdout, result.stderr] == expected
		# Source/VAPI imports share the same physical plan and full canonical pipeline.
	declaration = '[CCode(cname="unfamiliar_reader",text_abi="utf8-i32")] '
	native_decl = 'extern(C) int inspect(int tag, borrowed string a, f32 scale, borrowed string b, f64 wide, void* token);'
	api_decl = 'int inspect(int tag, borrowed string a, float scale, borrowed string b, double wide, void* token);'
	mapping = out / 'mapping'; mapping.mkdir(exist_ok=True)
	files = [mapping / ('0'+str(i)+'.astra') for i in range(4)]
	contents = [declaration+native_decl, 'const X="a\\0b";', 'int helper(string x){return inspect(1,x,1.5,x,2.5d,null);}', 'int main(){return helper(X);}']
	for file, text in zip(files, contents): file.write_text(text)
	canonical = {stage: run([compiler, '--dump-'+stage, *files]) for stage in STAGES}
	api = mapping / 'reader.vapi'; api.write_text(declaration+api_decl)
	files[0].write_text('')
	for permutation in itertools.permutations(files):
		for stage in STAGES:
			assert run([compiler, '--dump-'+stage, *permutation, '--vapi', api]) == canonical[stage]; comparisons += 1
	files[0].write_text(contents[0])
	for permutation in itertools.permutations(files):
		for stage in STAGES:
			assert run([compiler, '--dump-'+stage, *permutation]) == canonical[stage]; comparisons += 1
	inventory = re.findall(rb'^@astra.text.\d+ = private constant .+$', (out / 'composition.llvm').read_bytes(), re.M)
	assert len(inventory) == len(set(inventory))
	return dict(stages=records, canonical_comparisons=comparisons, executable_permutations=24, literal_inventory=[line.decode() for line in inventory], stdout_hex=expected[0].hex(), stderr_hex=expected[1].hex())


def linker_controls(compiler, out, provider):
	source = ROOT / 'examples/text-output/hello.astra'; target = out / 'protected-output'; target.write_bytes(b'original')
	rows = []
	for extra, needle in [([], b'astra_host_text_write'), (['--link-object', provider, '--link-object', provider], b'multiple definition')]:
		p = process([compiler, source, LIB / 'hosted/text.astra', *extra, '-o', target]); assert p.returncode == 1 and needle in p.stderr and target.read_bytes() == b'original'
		rows.append(p.stderr.decode().replace(str(out), '<qualification>'))
	unrelated = out / 'ordinary-name.astra'; unrelated.write_text('bool println(int n){return n==7;} int main(){if(!println(7)){return 1;}return 0;}'); run([compiler, unrelated, '-o', out/'ordinary-name']); assert run([out/'ordinary-name']) == b''
	p = process([compiler, unrelated, LIB/'hosted/text.astra', '--check']); assert p.returncode == 1 and b'duplicate function' in p.stderr
	return rows


def main():
	compiler = Path(sys.argv[1]).resolve(); out = Path(sys.argv[2]).resolve(); out.mkdir(parents=True, exist_ok=True)
	provider = compiler.parent / 'lib/astra/text-posix.o'
	results = dict(native=native(compiler, out), progress=provider_progress(out), output=output(compiler, out, provider), negatives=negatives(compiler, out), sequencing=sequencing(compiler, out), composition=composition(compiler, out, provider), linker=linker_controls(compiler, out, provider))
	(out / 'qualification.json').write_text(json.dumps(results, indent='\t')+'\n')
	(out / 'commands.json').write_text(json.dumps(COMMANDS, indent='\t')+'\n')
	print('TEXT-IO qualification PASS')


if __name__ == '__main__':
	main()
