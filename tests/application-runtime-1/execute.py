# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compile independent applications; compare real bytes, O2, memory and I/O faults."""
from pathlib import Path
import hashlib
import importlib.util
import json
import os
import random
import re
import resource
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
APPS = ROOT / 'examples/application-runtime'
LIBS = [ROOT / ('lib/astra/' + p + '.astra') for p in [
	'text/scalar-format', 'hosted/text-ops', 'hosted/files', 'text/utf8-byte-builder',
	'text/utf8-message', 'collections/bag', 'base/errors', 'hosted/text']]
VG = ['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
	'--errors-for-leak-kinds=all', '--error-exitcode=99']


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main(compiler, emitter, output):
	compiler, emitter, output = map(lambda p: Path(p).resolve(), [compiler, emitter, output])
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='run-', dir=output))
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	checks, applications = [], {}
	started = time.monotonic()

	def run(command, code=0, stdout=b'', stderr=b'', memory=False, save=None, env=None, accept=None):
		command = list(map(str, command)); before = time.monotonic()
		result = subprocess.run(command, cwd=ROOT, input=b'', capture_output=True, timeout=90,
			env=dict(os.environ, CCACHE_DISABLE='1', **(env or {})))
		valid = result.returncode == code and (stdout is None or save is not None or result.stdout == stdout)
		if memory:
			valid &= all(x in result.stderr for x in [b'ERROR SUMMARY: 0 errors',
				b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
			application_stderr = re.sub(rb'^==\d+==[^\n]*\n', b'', result.stderr, flags=re.M)
			valid &= application_stderr == stderr
		else:
			valid &= stderr is None or result.stderr == stderr
		if accept is not None:
			valid &= accept(result)
		if save is not None:
			Path(save).write_bytes(result.stdout)
		checks.append(dict(command=command, stdin_hex='', expected_exit=code, exit=result.returncode,
			expected_stdout_hex=None if stdout is None else stdout.hex(), stdout_hex=result.stdout.hex(),
			expected_stderr_hex=None if stderr is None else stderr.hex(),
			stderr_hex=result.stderr.hex(), seconds=time.monotonic()-before, memory=memory,
			environment=env, passed=bool(valid)))
		(out / 'checks.json').write_text(json.dumps(checks, indent=2) + '\n')
		assert valid, checks[-1]
		return result.stdout

	providers = []
	for name in ['args', 'text', 'text-ops', 'files']:
		obj = out / (name + '.o'); providers.append(obj)
		run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c',
			ROOT / f'lib/astra/platform/{name}-posix.c', '-o', obj])
	platform = out / 'platform-contracts'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', HERE / 'platform-contracts.c',
		out / 'files.o', out / 'text-ops.o', '-o', platform])
	run([platform])

	def compile_pair(name, source, pure=False):
		inputs = [source, *[p for p in LIBS if '/hosted/' not in str(p) and p.name != 'bag.astra']] if pure else [source, APPS / 'support.astra', *LIBS]
		linked = [] if pure else providers
		native, ir, optir, obj, optimized = [out / (name + suffix) for suffix in ['', '.ll', '-O2.ll', '-O2.o', '-O2']]
		run([compiler, *inputs, *[v for p in linked for v in ['--link-object', p]], '-o', native])
		run([emitter, '--emit', ir, *inputs])
		run(['opt', '-passes=verify', '-disable-output', ir])
		run(['opt', '-passes=default<O2>', '-S', ir, '-o', optir])
		run(['opt', '-passes=verify', '-disable-output', optir])
		run(['llc', '-O2', '-filetype=obj', '-relocation-model=pic', optir, '-o', obj])
		run(['cc', obj, *linked, '-o', optimized])
		applications[name] = dict(sources={str(p.relative_to(ROOT)): sha(p) for p in inputs},
			products={str(p): sha(p) for p in [native, ir, optir, obj, optimized]}, cases=[])
		return native, optimized, ir

	def exercise(name, pair, args=(), expected=b'', code=0, stderr=b'', memory=True, env=None):
		for program in pair[:2]:
			run([program, *args], code, expected, stderr, env=env)
			if memory:
				run([*VG, program, *args], code, expected, stderr, memory=True, env=env)
		applications[name]['cases'].append(dict(args=list(map(str, args)), expected_hex=expected.hex(), exit=code))

	a1 = compile_pair('format-matrix', APPS / 'format-matrix.astra')
	decimal = ','.join(map(str, [-2147483648, -1, 0, 1, 2147483647]))
	expected = ('café:' + decimal + ';0,4294967295;false,true;a\0🖤é\n').encode()
	exercise('format-matrix', a1, expected=expected)
	pure = compile_pair('pure-format', HERE / 'pure-format.astra', pure=True)
	exercise('pure-format', pure)
	a2 = compile_pair('text-ops', APPS / 'text-ops.astra')
	exercise('text-ops', a2, expected='a\ncafé\n\né\n🖤\n\0\n\nparse-error\nrange-error\n'.encode())
	a3 = compile_pair('copy-bytes', APPS / 'copy-bytes.astra')
	a4 = compile_pair('io-errors', APPS / 'io-errors.astra')
	exercise('io-errors', a4, [out / 'absent'], b'missing-file\ninvalid-path\n')

	binary_cases = [b'', bytes([0, 255, 128, 195, 40]), b'\n', b'a\r\nb\0\xff',
		random.Random(20261016).randbytes(8193), b'a' * 255 + b'\n' + b'b' * 256 + b'\n']
	file_checks = []

	def file_case(name, pair, number, data, expected, code=0, stderr=b'', memory=False):
		source = out / f'{name}-{number}.input'; source.write_bytes(data)
		for route, program in enumerate(pair[:2]):
			target = out / f'{name}-{number}-{route}.output'
			assert not target.exists()
			run([program, source, target], code, b'', stderr)
			actual = target.read_bytes() if target.exists() else None
			assert actual == expected, (name, number, route, actual, expected)
			if memory:
				run([*VG, program, source, target], code, b'', stderr, memory=True)
				assert (target.read_bytes() if target.exists() else None) == expected
			file_checks.append(dict(app=name, number=number, route=route, input=str(source), input_sha256=sha(source),
				output=str(target), expected_hex=None if expected is None else expected.hex(),
				output_sha256=None if actual is None else sha(target), exit=code))
		applications[name]['cases'].append(dict(input_sha256=sha(source), number=number, exit=code))
		(out / 'file-checks.json').write_text(json.dumps(file_checks, indent=2) + '\n')

	for i, data in enumerate(binary_cases):
		file_case('copy-bytes', a3, i, data, data, memory=i in [0, 1, 4])
		# Real read failure (directory) and real write failures, beyond synthetic faults.
	for program in a3[:2]:
		run([program, out, out / 'never-created'], 2, b'', b'file I/O\n')
		assert not (out / 'never-created').exists()
		run([*VG, program, out, out / 'never-created'], 2, b'', b'file I/O\n', memory=True)
		run([program, out / 'copy-bytes-1.input', out], 2, b'', b'file I/O\n')
		run([*VG, program, out / 'copy-bytes-1.input', '/dev/full'], 2, b'', b'file I/O\n', memory=True)
	permission = 'SKIP: effective uid can bypass mode bits'
	if os.geteuid() != 0:
		denied = out / 'denied.input'; denied.write_bytes(b'secret'); denied.chmod(0)
		try:
			for program in a3[:2]:
				run([*VG, program, denied, out / 'denied.output'], 2, b'', b'file I/O\n', memory=True)
				assert not (out / 'denied.output').exists()
			permission = 'PASS: real task-owned mode-000 input rejects with EACCES'
		finally:
			denied.chmod(0o600)

	b1 = compile_pair('diagnostic-transform', APPS / 'diagnostic-transform.astra')
	records = ['info|0|café', 'warning|-2|', 'error|2147483647|a\0🖤']
	data = ('\r\n'.join(records) + '\r\n').encode()
	expected = '1:info[0] café\n2:warning[-2] \n3:error[2147483647] a\0🖤\n'.encode()
	file_case('diagnostic-transform', b1, 0, data, expected, memory=True)
	file_case('diagnostic-transform', b1, 1, b'info|001|different\n', b'1:info[1] different\n', memory=True)
	file_case('diagnostic-transform', b1, 2, b'', b'')
	for i, bad in enumerate([b'wat|1|bad\n', b'info|2147483648|bad\n', data + b'error|x|bad\n', b'info|0|\xff\n']):
		file_case('diagnostic-transform', b1, i+3, bad, None, 3, b'invalid diagnostic input\n', memory=True)
	many = ''.join(f'info|{i}|record {i} café\n' for i in range(240))
	many_expected = ''.join(f'{i+1}:info[{i}] record {i} café\n' for i in range(240))
	file_case('diagnostic-transform', b1, 7, many.encode(), many_expected.encode(), memory=True)

	b2 = compile_pair('kv-config', APPS / 'kv-config.astra')
	file_case('kv-config', b2, 0, b'# config\r\n x = -001 \r\nx=0\ny=2147483647\n\n', b'x=-1\nx=0\ny=2147483647\n', memory=True)
	file_case('kv-config', b2, 1, b'\tother\t= -2147483648', b'other=-2147483648\n', memory=True)
	file_case('kv-config', b2, 2, b'', b'')
	for i, bad in enumerate([b'x=2147483648', b'=1', b'x=+1', b'x=1\0', b'x y=1', b'no-equals']):
		file_case('kv-config', b2, i+3, bad, None, 3, b'invalid config input\n', memory=i<2)

	b3 = compile_pair('line-stat', APPS / 'line-stat.astra')
	for i, data in enumerate(binary_cases):
		expected = f'byte_count={len(data)}\nLF_count={data.count(bytes([10]))}\nends_in_LF={str(data.endswith(bytes([10]))).lower()}\n'.encode()
		file_case('line-stat', b3, i, data, expected, memory=i in [0, 4])
	b4 = compile_pair('owner-log', APPS / 'owner-log.astra')
	exercise('owner-log', b4, expected=b'1\n12\n123\n')
	exercise('owner-log', b4, ['early'], b'1\n')
	exercise('owner-log', b4, ['error'], b'caught\n')
	edges = compile_pair('edge-cases', HERE / 'edge-cases.astra')
	exercise('edge-cases', edges)
	api = compile_pair('file-api', HERE / 'file-api.astra')
	exercise('file-api', api, [out / 'borrowed.output'])
	assert (out / 'borrowed.output').read_bytes() == bytes([0,255,128])
	status = compile_pair('io-status', HERE / 'io-status.astra')

	# Syscall faults hit the same Astra byte-copy sources and independently O2 object.
	fault = out / 'io-faults.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', HERE / 'io-faults.c', '-o', fault])
	source = out / 'fault.input'; source.write_bytes(b'ab\0\xffz')
	wrappers = '-Wl,--wrap=open,--wrap=read,--wrap=write,--wrap=fsync,--wrap=close'
	native_obj = out / 'copy-bytes-O0.o'
	run(['llc', '-O0', '-filetype=obj', '-relocation-model=pic', a3[2], '-o', native_obj])
	for route, obj in enumerate([native_obj, out / 'copy-bytes-O2.o']):
		program = out / f'copy-fault-{route}'
		run(['cc', obj, *providers, fault, wrappers, '-o', program])
		for kind in ['eintr', 'read', 'write', 'zero', 'flush', 'close', 'output-close']:
			target = out / f'fault-{route}-{kind}.output'
			code, err = (0, b'') if kind == 'eintr' else (2, b'file I/O\n')
			run([program, source, target], code, b'', err, env={'ASTRA_IO_FAULT': kind})
			run([*VG, program, source, target], code, b'', err, memory=True, env={'ASTRA_IO_FAULT': kind})
			if kind == 'eintr':
				assert target.read_bytes() == source.read_bytes()
			else:
				expected = {'read': None, 'write': b'a', 'zero': b'', 'flush': source.read_bytes(),
					'close': None, 'output-close': source.read_bytes()}[kind]
				assert (target.read_bytes() if target.exists() else None) == expected
	status_native = out / 'io-status-O0.o'
	run(['llc', '-O0', '-filetype=obj', '-relocation-model=pic', status[2], '-o', status_native])
	for route, obj in enumerate([status_native, out / 'io-status-O2.o']):
		program = out / f'status-fault-{route}'
		run(['cc', obj, *providers, fault, wrappers, '-o', program])
		statuses = {'read': b'2:-5\n', 'write': b'3:-5\n', 'zero': b'3:-5\n',
			'flush': b'4:-5\n', 'close': b'5:-4\n', 'output-close': b'5:-5\n'}
		for kind, expected in statuses.items():
			run([program, source, out / f'status-{route}-{kind}.output'], 2, expected, env={'ASTRA_IO_FAULT': kind})

			# Instrument only independently verified real LLVM. No corrupted IR executes.
	sys.dont_write_bytecode = True
	def load_instrument(name, path):
		spec = importlib.util.spec_from_file_location(name, path)
		module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
		return module.instrument
	builder_instrument = load_instrument('builder_instrument', HERE.parent / 'text-own-1b/execute.py')
	bag_instrument = load_instrument('bag_instrument', HERE.parent / 'gen-member-1a/execute.py')
	ssa = run([compiler, '--dump-ssa', APPS / 'owner-log.astra', APPS / 'support.astra', *LIBS],
		save=out / 'owner-log.ssa').decode()
	# Slot helper symbols are keyed by exact element Class, not container Class.
	ordinal = int(re.search(r'\(class #(\d+) "Utf8Message"', ssa)[1])
	observed = out / 'owner-observed.ll'
	observed.write_text(bag_instrument(builder_instrument(b4[2].read_text(), ssa), {1: ordinal}))
	observer = out / 'owner-observer.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-fno-builtin', '-c', HERE / 'owner-observer.c', '-o', observer])
	traces = []
	for route, passes, level in [('native', 'verify', '-O0'), ('O2', 'default<O2>', '-O2')]:
		ir = out / f'observed-{route}.ll'; obj = ir.with_suffix('.o'); program = ir.with_suffix('')
		run(['opt', '-passes=' + passes, '-S', observed, '-o', ir])
		run(['opt', '-passes=verify', '-disable-output', ir])
		run(['llc', level, '-filetype=obj', '-relocation-model=pic', ir, '-o', obj])
		run(['cc', obj, observer, *providers, '-o', program])
		route_traces = []
		for args in [[], ['early'], ['error']]:
			trace = run([program, *args], stdout=None)
			assert b'bag-growth 2->3 len=2\n' in trace
			assert re.findall(rb'^owner-drop (\d+)$', trace, re.M) == [b'3', b'2', b'1']
			assert re.findall(rb'^bag-retire (\d+)$', trace, re.M) == [b'2', b'1', b'0']
			assert b'bag-observer: growth=1 reverse=3 drops=1\n' in trace
			assert b'observer: owners=3 drops=3 objects=3 payloads=3' in trace
			route_traces.append(trace)
			(out / f'observed-{route}-{args[0] if args else "normal"}.txt').write_bytes(trace)
		traces.append(route_traces)
	assert traces[0] == traces[1]

	# Source-negative controls use meaningful lifetime/ABI boundaries, never run.
	negatives = {
		'escaped-text': ('int main(){var text="";{var b=new Utf8ByteBuilder();try{var m=b.snapshot();text=m.text;}catch(Error e){}}return text.byte_length;}', 'outlive'),
		'private-binary': ('int main(){var a=new u8[1];var b=new FileBytes(move a);return len(b.storage);}', 'private'),
		'double-owner': ('int main(){var a=new u8[1];var b=new FileBytes(move a);var c=new FileBytes(move a);return 0;}', 'use of moved owned value'),
		'foreign-slice': ('extern(C) int unsafe(u8[] bytes);int main(){return 0;}', 'slice parameters'),
		'foreign-text': ('extern(C) int unsafe(string bytes);int main(){return 0;}', 'string parameters'),
		'borrowed-substring': ('string unsafe(Utf8Message m){return m.text;}int main(){return 0;}', 'return'),
		'bag-loan-growth': ('void use(Utf8Message m,bool changed){}int main(){var bag=new Bag<Utf8Message>();var m=new Utf8Message("x");bag.append(move m);use(bag.entries[0],bag.reserve(3));return 0;}', 'overlaps'),
	}
	for name, (text, diagnostic) in negatives.items():
		source = out / (name + '.astra'); source.write_text(text)
		binary = out / (name + '-invalid')
		stages = ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm', 'native']
		if name == 'double-owner':
			# Construction retains move events; the CFG ownership analysis
			# rejects the second transfer before executable lowering.
			for stage in stages[:2]:
				run([compiler, source, *LIBS, '--dump-' + stage], 0, None, b'')
			stages = stages[2:]
		for stage in stages:
			args = ['-o', binary] if stage == 'native' else ['--dump-' + stage]
			run([compiler, source, *LIBS, *args], 1, b'', None,
				accept=lambda p, d=diagnostic: d.encode() in p.stderr and b'internal' not in p.stderr.lower())
			assert not binary.exists()

	identity = dict(output=str(out), applications=applications, checks=len(checks),
		memory_runs=sum(c['memory'] for c in checks), file_comparisons=len(file_checks),
		all_passed=all(c['passed'] for c in checks), seconds=time.monotonic()-started,
		compiler_sha256=sha(compiler), emitter_sha256=sha(emitter), oracle_sha256=sha(__file__),
		permission_case=permission, providers={str(p): sha(p) for p in providers},
		sources={str(p.relative_to(ROOT)): sha(p) for p in [*LIBS, *APPS.glob('*.astra'), *HERE.glob('*.*'),
		ROOT / 'lib/runtime/platform/files-posix.h',
		HERE.parent / 'text-own-1b/execute.py', HERE.parent / 'text-own-1b/observer.c',
		HERE.parent / 'text-own-1a/observer.c', HERE.parent / 'gen-member-1a/execute.py',
		*[ROOT / f'lib/astra/platform/{n}-posix.c' for n in ['args','text','text-ops','files']]] if p.is_file()})
	(out / 'identity.json').write_text(json.dumps(identity, indent=2) + '\n')
	(output / 'current.json').write_text(json.dumps(identity, indent=2) + '\n')
	print(json.dumps({k:v for k,v in identity.items() if k not in ['sources','applications']}, indent=2))


if __name__ == '__main__':
	main(*sys.argv[1:])
