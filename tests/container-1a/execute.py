# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute concrete growth, source refusals, fatal controls and real allocation observation."""
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
APP = ROOT / 'examples/diagnostic-slots/main.astra'
LIBS = [ROOT / 'lib/astra/text/utf8-message.astra', ROOT / 'lib/astra/base/errors.astra', ROOT / 'lib/astra/hosted/text.astra']
VG = ['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99']


def instrument(ir, diagnostic):
	"""Observe actual generated slot operations after authentic artifact verification."""
	counts = {}
	pattern = re.compile(r'^(define internal fastcc [^\n]+ @astra\.slots\.' + str(diagnostic) + r'\.(\w+)\([^\n]+\) \{\n)(.*?)(^\})', re.M | re.S)
	def operation(match):
		action, body = match[2], match[3]
		if action == 'initialize':
			body, n = re.subn(r'^  ret void$', '  call void @slot_obs_init(ptr %0)\n  ret void', body, flags=re.M)
		elif action == 'append':
			body, n = re.subn(r'^  ret void$', '  call void @slot_obs_append(ptr %0, ptr %1)\n  ret void', body, flags=re.M)
		elif action == 'borrow':
			body, n = re.subn(r'^  ret ptr (%[\w.]+)$', r'  call void @slot_obs_borrow(ptr %0, i32 %1, ptr \1)\n  ret ptr \1', body, flags=re.M)
		elif action == 'reserve':
			body, n = re.subn(r'^(  store i32 %1, ptr %slots\.capacity\.address, align 4)$', r'\1\n  call void @slot_obs_commit(ptr %0, ptr %slots.base, ptr %reserve.replacement.base, i32 %slots.length, i32 %1)', body, flags=re.M)
		elif action == 'drop':
			body, begin = re.subn(r'^(  br label %drop\.reverse\.header)$', r'  call void @slot_obs_drop_begin(ptr %0)\n\1', body, count=1, flags=re.M)
			body, retire = re.subn(r'^(  store i32 %drop\.index, ptr %slots\.length\.address, align 4)$', r'\1\n  call void @slot_obs_retire(ptr %0, i32 %drop.index, ptr %drop.element)', body, flags=re.M)
			body, end = re.subn(r'^  ret void$', '  call void @slot_obs_drop_done(ptr %0)\n  ret void', body, flags=re.M)
			assert (begin, retire, end) == (1, 1, 1)
			n = 1
		else:
			return match[0]
		assert n == 1, (action, n)
		counts[action] = n
		return match[1] + body + match[4]
	result = pattern.sub(operation, ir)
	assert set(counts) == {'initialize', 'reserve', 'append', 'borrow', 'drop'}, counts
	ctor = re.compile(r'^(define internal fastcc void @astra\.ctor\.' + str(diagnostic) + r'\(ptr %this, i32 %p0, ptr %p1\) \{\n)(.*?)(^\})', re.M | re.S)
	def born(match):
		body, n = re.subn(r'^  ret void$', '  call void @slot_obs_born(ptr %this, i32 %p0, ptr %p1)\n  ret void', match[2], flags=re.M)
		assert n == 1
		return match[1] + body + match[3]
	result, n = ctor.subn(born, result); assert n == 1
	dtor = re.compile(r'^(define internal fastcc void @astra\.dtor\.' + str(diagnostic) + r'\(ptr %this\) \{\n[^\n]+:\s*\n)', re.M)
	result, n = dtor.subn(r'\1  call void @slot_obs_dying(ptr %this)\n', result); assert n == 1
	main = re.compile(r'^(define i32 @main\([^\n]*\) \{\n)(.*?)(^\})', re.M | re.S)
	def done(match):
		body, n = re.subn(r'^(  ret i32 .+)$', r'  call void @slot_obs_done()\n\1', match[2], flags=re.M)
		assert n >= 1
		return match[1] + body + match[3]
	result, n = main.subn(done, result); assert n == 1
	result += '''
declare void @slot_obs_init(ptr)
declare void @slot_obs_born(ptr, i32, ptr)
declare void @slot_obs_commit(ptr, ptr, ptr, i32, i32)
declare void @slot_obs_append(ptr, ptr)
declare void @slot_obs_borrow(ptr, i32, ptr)
declare void @slot_obs_drop_begin(ptr)
declare void @slot_obs_retire(ptr, i32, ptr)
declare void @slot_obs_dying(ptr)
declare void @slot_obs_drop_done(ptr)
declare void @slot_obs_done()
'''
	return result


def main(compiler_path, emitter_path, output_path):
	compiler, emitter, output = [Path(p).resolve() for p in [compiler_path, emitter_path, output_path]]
	assert not output.is_relative_to(ROOT), 'generated artifacts must stay outside source'
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='run-', dir=output))
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	rows = []

	def run(command, expected=0, stdout='', diagnostic=None, memory=False, save=None, extra_env=None):
		command = list(map(str, command))
		p = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=90,
			env=dict(os.environ, CCACHE_DISABLE='1', **(extra_env or {})))
		valid = p.returncode == expected and (stdout is None or save is not None or p.stdout == stdout.encode())
		if diagnostic:
			valid &= diagnostic.encode() in p.stderr and b'internal error' not in p.stderr.lower()
		elif memory:
			valid &= all(s in p.stderr for s in [b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
		else:
			valid &= not p.stderr
		if save is not None:
			save.write_bytes(p.stdout)
		rows.append(dict(command=command, expected=expected, actual=p.returncode,
			stdout=p.stdout.decode(), stderr=p.stderr.decode(), memory=memory, passed=bool(valid), extra_env=extra_env))
		(out / 'checks.json').write_text(json.dumps(rows, indent=2) + '\n')
		assert valid, rows[-1]
		return p.stdout.decode()

	providers = []
	for name in ['args', 'text']:
		obj = out / (name + '.o'); providers.append(obj)
		run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', ROOT / f'lib/astra/platform/{name}-posix.c', '-o', obj])
	observer = out / 'observer.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', HERE / 'observer.c', '-o', observer])

	def compile_pair(label, source, libraries):
		inputs = [source, *libraries]
		for stage in ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']:
			run([compiler, '--dump-' + stage, *inputs], save=out / (label + '.' + stage))
		binary, ir, optimized, obj, o2 = [out / (label + suffix) for suffix in ['', '.ll', '-O2.ll', '-O2.o', '-O2']]
		run([compiler, *inputs, *[x for p in providers for x in ['--link-object', p]], '-o', binary])
		run([emitter, '--emit', ir, *inputs])
		run(['opt', '-passes=verify', '-disable-output', ir])
		run(['opt', '-passes=default<O2>', '-S', ir, '-o', optimized])
		run(['opt', '-passes=verify', '-disable-output', optimized])
		run(['llc', '-O2', '-filetype=obj', '-relocation-model=pic', optimized, '-o', obj])
		run(['cc', obj, *providers, '-o', o2])
		return binary, o2, ir

	traces = [
		(['empty'], 'empty\ndrop diagnostics\n'),
		(['one'], '1: café\ndrop diagnostics\ndrop 1\n'),
		(['two'], '1: café\n2: cafe\u0301\ndrop diagnostics\ndrop 2\ndrop 1\n'),
		([], '1: café\n2: cafe\u0301\n3: 🖤\ndrop diagnostics\ndrop 3\ndrop 2\ndrop 1\n'),
		(['early'], 'drop diagnostics\ndrop 3\ndrop 2\ndrop 1\n'),
	]
	binary, o2, app_ir = compile_pair('application', APP, LIBS)
	for executable in [binary, o2]:
		for arguments, expected in traces:
			run([executable, *arguments], stdout=expected)
			run([*VG, executable, *arguments], stdout=expected, memory=True)
	for label, source, libraries in [('smoke', HERE / 'smoke.astra', []), ('numeric-spelling', HERE / 'numeric-spelling.astra', []), ('messages', HERE / 'messages.astra', LIBS)]:
		for executable in compile_pair(label, source, libraries)[:2]:
			run([executable]); run([*VG, executable], memory=True)

			# Checked failure after a completed 2->3 reserve retires both live elements
			# before the caller's catch. No third diagnostic is published.
	prefix = APP.read_text().split('int main(string[] args) {')[0]
	checked = out / 'checked.astra'
	checked.write_text(prefix + '''void checked_scope() throws InvalidUtf8 {
	var bag = new Diagnostics();
	if (!bag.reserve(2)) { return; }
	u8[5] first_bytes = {99, 97, 102, 195, 169};
	u8[6] second_bytes = {99, 97, 102, 101, 204, 129};
	var first = make_diagnostic(1, slice(first_bytes));
	var second = make_diagnostic(2, slice(second_bytes));
	bag.append(move first); bag.append(move second);
	if (!bag.reserve(3) || bag.count() != 2 || !bag.distinct()) { return; }
	u8[1] malformed = {255};
	var unpublished = make_diagnostic(3, slice(malformed));
}
int main(string[] args) {
	try { checked_scope(); }
	catch (InvalidUtf8 error) { if (error.message == "invalid UTF-8" && println("caught")) { return 0; } }
	return 81;
}
''')
	checked_pair = compile_pair('checked', checked, LIBS)
	for executable in checked_pair[:2]:
		trace = 'drop diagnostics\ndrop 2\ndrop 1\ncaught\n'
		run([executable], stdout=trace); run([*VG, executable], stdout=trace, memory=True)

		# Observe the actual emitted backing stores and nested snapshot owners,
		# with a separate untouched standard-allocator execution above.
	observations = {}
	for label, ir, scenarios in [('application', app_ir, traces), ('checked', checked_pair[2], [([], 'drop diagnostics\ndrop 2\ndrop 1\ncaught\n')])]:
		ssa = (out / (label + '.ssa')).read_text()
		diagnostic = int(re.search(r'\(class #(\d+) "Diagnostic"', ssa)[1])
		observed = out / (label + '-observed.ll'); observed.write_text(instrument(ir.read_text(), diagnostic))
		programs = []
		for mode in ['O0', 'O2']:
			optimized, obj, executable = [out / (label + '-observed-' + mode + suffix) for suffix in ['.ll', '.o', '']]
			run(['opt', '-passes=verify' if mode == 'O0' else '-passes=default<O2>', '-S', observed, '-o', optimized])
			run(['opt', '-passes=verify', '-disable-output', optimized])
			run(['llc', '-' + mode, '-filetype=obj', '-relocation-model=pic', optimized, '-o', obj])
			run(['cc', obj, *providers, observer, '-Wl,--wrap=calloc,--wrap=malloc,--wrap=free', '-o', executable])
			programs.append(executable)
		for arguments, _ in scenarios:
			outputs = [run([program, *arguments], stdout=None) for program in programs]
			assert outputs[0] == outputs[1] and 'OK allocations=' in outputs[0], outputs
			if label == 'application' and (not arguments or arguments == ['early']):
				assert re.search(r'^G1 2->3 len=2 old=\d+ new=\d+$', outputs[0], re.M)
				assert re.search(r'^OK allocations=\d+ elements=3 growth=1 borrows=\d+$', outputs[0], re.M)
			key = label + ':' + ','.join(arguments)
			(out / (label + '-' + ('-'.join(arguments) or 'three') + '.trace')).write_text(outputs[0])
			observations[key] = outputs[0].splitlines()[-1]
		if label == 'application':
			outputs = [run([program], expected=-signal.SIGILL, stdout=None, extra_env={'SLOTS_FAIL_GROW': '1'}) for program in programs]
			assert outputs[0] == outputs[1] and 'OOM growth\n' in outputs[0] and '2->3' not in outputs[0] and not re.search(r'^[RDEZ]', outputs[0], re.M)
			(out / 'fatal-growth.trace').write_text(outputs[0])

	identity = dict(output=str(out), compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),
		emitter_sha256=hashlib.sha256(emitter.read_bytes()).hexdigest(), commands=len(rows),
		memory_runs=sum(r['memory'] for r in rows), observations=observations,
		all_passed=all(r['passed'] for r in rows), source_sha256={str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [APP, *LIBS, HERE / 'smoke.astra', HERE / 'numeric-spelling.astra', HERE / 'messages.astra', HERE / 'observer.c', Path(__file__).resolve()]})
	(out / 'identity.json').write_text(json.dumps(identity, indent=2) + '\n')
	(output / 'current.json').write_text(json.dumps(identity, indent=2) + '\n')
	print(f"{identity['commands']} commands; {identity['memory_runs']} clean standard-allocator memory runs; native/O2 and observed pointer/cleanup parity")
	print(f'Evidence: {out}')


if __name__ == '__main__':
	main(*sys.argv[1:])
