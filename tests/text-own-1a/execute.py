# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual public byte factories: native/O2, standard-allocator memory and ABI observer."""
from pathlib import Path
import hashlib
import json
import os
import re
import resource
import signal
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
LIBRARY = ROOT / 'lib/astra/text/utf8-message.astra'
ERRORS = ROOT / 'lib/astra/base/errors.astra'
INVALID = {
	'continuation': [0x80], 'lead': [0xff], 'truncated3': [0xe2, 0x82],
	'overlong2': [0xc0, 0xaf], 'surrogate': [0xed, 0xa0, 0x80],
	'above-max': [0xf4, 0x90, 0x80, 0x80], 'overlong3': [0xe0, 0x80, 0x80],
	'overlong4': [0xf0, 0x80, 0x80, 0x80], 'lead-f5': [0xf5, 0x90, 0x80, 0x80],
	'bad-second2': [0xc2, 0x20], 'bad-second3': [0xe2, 0x28, 0xa1],
	'truncated4': [0xf0, 0x9f, 0x96], 'bad-third4': [0xf0, 0x9f, 0x41, 0xa4],
	'bad-fourth4': [0xf0, 0x9f, 0x96, 0x7f], 'lead-c1': [0xc1, 0xbf],
	'truncated2': [0xc2], 'lead-f8': [0xf8, 0x80, 0x80, 0x80, 0x80],
	'valid-prefix-invalid-tail': [0x61, 0x62, 0xff],
	'truncated-after-prefix': [0x61, 0xe2, 0x82], 'bad-third3': [0xe2, 0x82, 0x41],
}
BOUNDARIES = [0x80, 0x7ff, 0x800, 0xd7ff, 0xe000, 0x10000, 0x10ffff, 0xfffe]


def main(compiler, emitter, output):
	compiler, emitter, output = [Path(p).resolve() for p in [compiler, emitter, output]]
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='run-', dir=output))
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	rows = []

	def run(command, expected=0, stdout=None, diagnostic=None, memory=False, env=None):
		command = list(map(str, command))
		p = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=60, env=dict(os.environ, CCACHE_DISABLE='1', **(env or {})))
		valid = p.returncode == expected and (stdout is None or p.stdout == stdout)
		if memory:
			valid &= all(t in p.stderr for t in [b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
		elif diagnostic:
			valid &= diagnostic.encode() in p.stderr and b'internal error' not in p.stderr.lower()
		else:
			valid &= not p.stderr
		rows.append(dict(command=command, expected=expected, observed=p.returncode, stdout=p.stdout.decode('utf-8'), stderr=p.stderr.decode('utf-8'), memory=memory, passed=bool(valid)))
		(out / 'checks.json').write_text(json.dumps(rows, indent=2, ensure_ascii=False) + '\n')
		assert valid, rows[-1]
		return p.stdout

	providers = []
	for name in ['args', 'text']:
		obj = out / (name + '.o')
		run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', ROOT / f'lib/astra/platform/{name}-posix.c', '-o', obj])
		providers.append(obj)
	observer = out / 'observer.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-fno-builtin', '-c', HERE / 'observer.c', '-o', observer])
	vg = ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all']
	identities = {}

	def instrument(ir, ssa):
		factory = re.search(r'\(function #(\d+) "utf8_message"', ssa).group(1)
		pattern = rf'(define internal fastcc ptr @astra.fn.{factory}\([^\n]*\n)(.*?)(^\}})'
		match = re.search(pattern, ir, re.M | re.S)
		assert match
		body = match.group(2)
		message_class = re.search(r'call fastcc void @astra.ctor.(\d+)\(', body).group(1)
		body, n = re.subn(r'(^[A-Za-z0-9_.]+:.*\n)', r'\1  call void @utf8_observe_input(ptr %p0.base, i32 %p0.length)\n', body, count=1, flags=re.M)
		assert n == 1
		body, n = re.subn(r'(^  store ptr ([^,]+), ptr %success.storage[^\n]*\n)', r'\1  call void @utf8_observe_owner(ptr \2)\n', body, flags=re.M)
		assert n == 1
		ir = ir[:match.start(2)] + body + ir[match.end(2):]
		pattern = rf'(define internal fastcc void @astra.dtor.{message_class}\(ptr %this\)[^\n]*\n)(.*?)(^\}})'
		match = re.search(pattern, ir, re.M | re.S)
		assert match
		body, n = re.subn(r'(^[A-Za-z0-9_.]+:.*\n)', r'\1  call void @utf8_observe_drop(ptr %this)\n', match.group(2), count=1, flags=re.M)
		assert n == 1
		ir = ir[:match.start(2)] + body + ir[match.end(2):]
		return ir + '\ndeclare void @utf8_observe_input(ptr, i32)\ndeclare void @utf8_observe_owner(ptr)\ndeclare void @utf8_observe_drop(ptr)\n'

	def qualify(name, sources, cases, observed=None):
		inputs = [*sources, LIBRARY, ERRORS]
		binary = out / name
		run([compiler, *inputs, *[a for obj in providers for a in ['--link-object', obj]], '-o', binary])
		ssa = run([compiler, '--dump-ssa', *inputs]).decode()
		(out / (name + '.ssa')).write_text(ssa)
		ir, optimized, obj, o2 = [out / (name + suffix) for suffix in ['.ll', '-O2.ll', '-O2.o', '-O2']]
		run([emitter, '--emit', ir, *inputs])
		run(['opt', '-passes=verify', '-disable-output', ir])
		run(['opt', '-passes=default<O2>', '-S', ir, '-o', optimized])
		run(['opt', '-passes=verify', '-disable-output', optimized])
		run(['llc', '-O2', '-filetype=obj', '-relocation-model=pic', optimized, '-o', obj])
		run(['cc', obj, *providers, '-o', o2])
		for program in [binary, o2]:
			for arguments, expected, stdout in cases:
				run([program, *arguments], expected=expected, stdout=stdout)
				run([*vg, program, *arguments], expected=expected, stdout=stdout, memory=True)
		identities[name] = {str(p.name): hashlib.sha256(p.read_bytes()).hexdigest() for p in [binary, o2, ir]}
		if observed:
			observed_ir = out / (name + '-observed.ll')
			observed_ir.write_text(instrument(ir.read_text(), ssa))
			for suffix, passes in [('native', 'verify'), ('O2', 'default<O2>')]:
				opt_ir = out / (name + '-observed-' + suffix + '.ll')
				observed_obj = opt_ir.with_suffix('.o')
				program = opt_ir.with_suffix('')
				run(['opt', '-passes=' + passes, '-S', observed_ir, '-o', opt_ir])
				run(['llc', '-O2' if suffix == 'O2' else '-O0', '-filetype=obj', '-relocation-model=pic', opt_ir, '-o', observed_obj])
				run(['cc', observed_obj, observer, *providers, '-o', program])
				for (arguments, expected, stdout), (order, owners, payloads, allocations) in zip(cases, observed):
					actual = run([program, *arguments], expected=expected)
					assert [int(i) for i in re.findall(rb'owner-drop (\d+)\n', actual)] == order, actual
					assert re.sub(rb'owner-drop \d+\n', b'', actual).split(b'observer:')[0] == stdout
					assert re.search(fr'observer: owners={owners} drops={owners} objects={owners} payloads={payloads} allocations={allocations}\n$'.encode(), actual), actual
		return binary

	qualify('positive', [HERE / 'positive.astra', ROOT / 'lib/astra/hosted/text.astra'], [([], 0, 'café\ndrop slot\ndrop slot\n'.encode()), (['early'], 0, 'café\ndrop slot\n'.encode())], observed=[([1, 3, 4, 10, 7, 9, 8, 6, 5, 2], 10, 8, 25), ([1, 3, 4, 7, 9, 8, 6, 5, 2], 9, 7, 19)])
	qualify('smoke', [HERE / 'smoke.astra'], [([], 42, b'')], observed=[([1], 1, 1, 5)])
	qualify('example', [ROOT / 'examples/utf8-message/main.astra'], [([], 0, b'')])
	for name, values in INVALID.items():
		source = out / (name + '.astra')
		writes = ' '.join(f'bytes[{i}] = {v};' for i, v in enumerate(values))
		unchanged = ' && '.join(f'bytes[{i}] == {v}' for i, v in enumerate(values))
		source.write_text(f'int main() {{ var survivor = new Utf8Message("survivor"); owned u8[] bytes = new u8[{len(values)}]; {writes} if (!rejects(bytes, survivor) || !({unchanged})) {{ return 97; }} return 0; }}\n')
		qualify(name, [HERE / 'malformed.astra', source], [([], 0, b'')], observed=[([], 0, 0, 5)] if name == 'surrogate' else None)
	boundary = out / 'boundaries.astra'
	lines = ['int main() { try {']
	for i, scalar in enumerate(BOUNDARIES):
		values = chr(scalar).encode('utf-8')
		lines.append(f'owned u8[] b{i} = new u8[{len(values)}];')
		lines += [f'b{i}[{j}] = {v};' for j, v in enumerate(values)]
		lines.append(f'var m{i} = utf8_message(b{i}); if (m{i}.text != "\\U{scalar:08x}" || m{i}.text.byte_length != {len(values)}) {{ return 96; }}')
	lines.append('} catch(Error error) { return 97; } return 0; }')
	boundary.write_text('\n'.join(lines) + '\n')
	qualify('boundaries', [boundary], [([], 0, b'')])
	# A private observer can fail only a selected real calloc. Signals prove
	# fatal behavior, never checked recovery or complete fatal-path retirement.
	for version in ['native', 'O2']:
		for allocation in [1, 2, 3, 4, 5]:
			run([out / ('smoke-observed-' + version)], expected=-signal.SIGILL, stdout=b'' if allocation <= 3 else b'owner-drop 1\n', env={'UTF8_FAIL_ALLOC': str(allocation)})
			# Existing implicit-conversion expectation stays unchanged, including no exe.
	probe = ROOT / 'tests/app-diag-collection-0/probes/bytes-as-text.astra'
	run([compiler, '--parse', probe], stdout=b'')
	for mode in ['--check', 'native']:
		exe = out / 'implicit-invalid'
		run([compiler, *([] if mode == 'native' else [mode]), probe, *(['-o', exe] if mode == 'native' else [])], expected=1, stdout=b'', diagnostic="expected initializer of type 'string', found 'u8[]'")
		assert not exe.exists()
	start = 'int main() { owned u8[] raw = new u8[1]; raw[0] = 97; try { var message = utf8_message(raw); '
	end = ' } catch(Error error) { return 99; } return 0; }'
	probes = {
		'loan-release': (start + 'var view = message.text; release message; return view.byte_length;' + end, 'cannot invalidate a receiver while a stored text loan remains in its lexical extent'),
		'loan-move': ('void consume(owned Utf8Message message) {} ' + start + 'var view = message.text; consume(move message); return view.byte_length;' + end, 'cannot invalidate a receiver while a stored text loan remains in its lexical extent'),
		'loan-replace': (start + 'var view = message.text; message = utf8_message(raw); return view.byte_length;' + end, "owned ClassType binding 'message' cannot be rebound"),
		'loan-return': ('string escape(Utf8Message message) { return message.text; } int main() { return 0; }', 'borrowed text cannot escape through a STATIC_TEXT result'),
		'loan-outer': ('int main() { owned u8[] raw = new u8[1]; var view = ""; try { { var message = utf8_message(raw); view = message.text; } return view.byte_length; } catch(Error error) { return 99; } }', 'receiver text loan requires its exact backing owner to outlive the destination local'),
		'class-elements': ('int main() { owned Utf8Message[] messages = new Utf8Message[1]; return 0; }', "unsupported slice element type 'Utf8Message'"),
	}
	for name, (text, diagnostic) in probes.items():
		source = out / (name + '.astra'); source.write_text(text + '\n')
		run([compiler, '--parse', source], stdout=b'')
		for mode in ['--check', 'native']:
			exe = out / (name + '-invalid')
			run([compiler, *([] if mode == 'native' else [mode]), source, LIBRARY, ERRORS, *(['-o', exe] if mode == 'native' else [])], expected=1, stdout=b'', diagnostic=diagnostic)
			assert not exe.exists()
			# Mutate separate generated source copies; the canonical library stays byte-identical.
	library_bytes = LIBRARY.read_bytes()
	for name, old, replacement, diagnostic in [
		('factory-signature', 'u8[] bytes', 'u16[] bytes', 'requires exactly owned Utf8Message'),
		('factory-body', 'throws InvalidUtf8;', 'throws InvalidUtf8 {}', "requires a bodyless ';' definition"),
		('false-snapshot', 'this.snapshot = input;', 'this.snapshot = "forged";', 'requires the canonical unique snapshot Class'),
		('false-view', 'return this.snapshot;', 'return "forged";', 'requires the canonical unique snapshot Class'),
		('false-diagnostic', 'base("invalid UTF-8")', 'base("forged")', 'requires the canonical unique snapshot Class'),
	]:
		mutated = out / (name + '.astra'); assert old in library_bytes.decode()
		mutated.write_text(library_bytes.decode().replace(old, replacement))
		exe = out / (name + '-invalid')
		run([compiler, HERE / 'smoke.astra', mutated, ERRORS, '-o', exe], expected=1, stdout=b'', diagnostic=diagnostic)
		assert not exe.exists() and LIBRARY.read_bytes() == library_bytes
		# Pay-for-use control: an ordinary source program selects no message library
		# and gains neither a UTF-8 helper nor allocator dependencies.
	unused_source = out / 'unused.astra'; unused_source.write_text('int main() { return 42; }\n')
	unused, unused_ir, unused_opt, unused_obj, unused_o2 = [out / name for name in ['unused', 'unused.ll', 'unused-O2.ll', 'unused-O2.o', 'unused-O2']]
	run([compiler, unused_source, '-o', unused])
	run([emitter, '--emit', unused_ir, unused_source])
	assert all(token not in unused_ir.read_text() for token in ['astra.text.validate.utf8', '@calloc', '@free'])
	run(['opt', '-passes=default<O2>', '-S', unused_ir, '-o', unused_opt])
	run(['llc', '-O2', '-filetype=obj', '-relocation-model=pic', unused_opt, '-o', unused_obj])
	run(['cc', unused_obj, '-o', unused_o2])
	for program in [unused, unused_o2]:
		run([program], expected=42, stdout=b'')
		run([*vg, program], expected=42, stdout=b'', memory=True)
	identities['unused'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [unused, unused_o2, unused_ir]}
	identity = dict(compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(), emitter_sha256=hashlib.sha256(emitter.read_bytes()).hexdigest(), output=str(out), commands=len(rows), memory_runs=sum(r['memory'] for r in rows), malformed_cases=len(INVALID), scalar_boundaries=BOUNDARIES, binaries=identities, all_passed=all(r['passed'] for r in rows))
	(out / 'identity.json').write_text(json.dumps(identity, indent=2) + '\n')
	(output / 'current.json').write_text(json.dumps(identity, indent=2) + '\n')
	print(f'{len(identities)} source programs, native/O2; {len(INVALID)} malformed byte cases; {identity["memory_runs"]} unsuppressed memory runs; {len(rows)} commands')
	print(f'Evidence: {out}')


if __name__ == '__main__':
	main(*sys.argv[1:])
