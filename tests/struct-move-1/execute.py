# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Finite local owning-record execution, rejection and cleanup controls."""
import json
import os
from pathlib import Path
import re
import resource
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
VAPI = ROOT / 'tests/own-field/fixtures/resources.vapi'
STAGES = ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']
TRACES = {
	'basic': 'A1 M11 F1 A2 M22 F2 M90 ',
	'mixed': 'A3 A4 M30 F4 A5 F5 A11 M110 F11 A9 A10 F9 M100 F10 F3 ',
	'null': 'N0 M0 ',
	'loop': 'A1 M1 F1 A2 M2 F2 A3 M3 F3 A4 M4 F4 ',
	'generic-plain': 'A6 M60 F6 ',
	'control': 'A7 M42 F7 M900 ',
	'branch': 'A8 M42 F8 A8 M18 F8 ',
	'checked-normal': 'A21 M210 F21 ',
	'checked-caught': 'A22 E220 M221 D220 M222 F22 M223 ',
	'checked-exit': 'A23 E230 F23 M231 D230 M232 ',
	'checked-propagate': 'A24 E240 F24 M241 D240 A25 E250 F25 M251 D250 ',
	'checked-move': 'A26 M260 E261 F26 M262 D261 ',
	'checked-null': 'N0 M270 N0 E270 M271 D270 ',
	'checked-join': 'A28 E280 F28 M281 D280 M291 A29 M290 M291 F29 ',
}
BAG = 'struct Bag{int tag;owned R r;}'
LOCAL = 'Bag bag={tag=42,r=make(1)};'

def body(text):
	return BAG + 'int main(){' + text + 'return 42;}'

	# Existing CFG ownership flow deliberately owns moved-source state diagnostics.
FLOW = {'moved-read', 'moved-store', 'second-move', 'incoming-reuse', 'moved-join',
	'checked-moved-read', 'checked-second-move', 'checked-moved-join', 'checked-moved-catch',
	'async-moved-read', 'async-second-move'}
NEGATIVES = {
	'async-moved-read': ('struct Bag{int tag;owned R r;}async int work(){Bag bag={tag=42,r=make(1)};var moved=move bag;return bag.tag;}int main(){return 42;}', 'moved'),
	'async-second-move': ('struct Bag{int tag;owned R r;}async int work(){Bag bag={tag=42,r=make(1)};var moved=move bag;var again=move bag;return 42;}int main(){return 42;}', 'moved'),
	'missing': (body('Bag bag={tag=42};'), 'missing'),
	'duplicate': (body('Bag bag={tag=42,r=make(1),r=make(2)};'), 'duplicate'),
	'raw-null': (body('Bag bag={tag=42,r=null};'), 'exact explicit owner move or direct owned producer'),
	'wrong-resource': (body('Bag bag={tag=42,r=make_other(1)};'), 'exact explicit owner move or direct owned producer'),
	'copied-resource': (body('owned R source=make(1);Bag bag={tag=42,r=source};'), 'copied'),
	'implicit-copy': (body(LOCAL+'var copy=bag;'), 'copyable'),
	'typed-copy': (body(LOCAL+'Bag copy=bag;'), 'owning record copy is forbidden'),
	'moved-read': (body(LOCAL+'var moved=move bag;int tag=bag.tag;'), 'moved'),
	'moved-store': (body(LOCAL+'var moved=move bag;bag.tag=7;'), 'moved'),
	'moved-join': (body(LOCAL+'if(live()==1){var moved=move bag;}int tag=bag.tag;'), 'may have been moved'),
	'second-move': (body(LOCAL+'var moved=move bag;var again=move bag;'), 'moved'),
	'incoming-reuse': (body('owned R input=make(1);Bag bag={tag=42,r=move input};id(input);'), 'moved'),
	'explicit-release': (body(LOCAL+'release bag;'), 'explicit owning record release is deferred'),
	'second-release': (body(LOCAL+'release bag;release bag;'), 'explicit owning record release is deferred'),
	'resource-read': (body(LOCAL+'id(bag.r);'), 'Resource field access and extraction are deferred'),
	'retained-borrow': (body(LOCAL+'var loan=&bag;'), 'address exposure is deferred'),
	'pointer-signature': (BAG+'void use(Bag* bag){}int main(){return 42;}', 'pointer and address exposure are deferred'),
	'generic-owner': ('struct Bag<T>{owned R r;T value;}int main(){return 42;}', 'owned struct fields are unsupported'),
	'method': ('struct Bag{owned R r;int read(){return 42;}}int main(){return 42;}', 'methods and properties are deferred'),
	'property': ('struct Bag{owned R r;property int value{get{return 42;}}}int main(){return 42;}', 'methods and properties are deferred'),
	'return': (BAG+'Bag make_bag(){'+LOCAL+'return bag;}int main(){return 42;}', 'explicit move'),
	'call-move': (BAG+'void consume(int n){}int main(){'+LOCAL+'consume(move bag);return 42;}', 'move requires a fresh owned local'),
	'array': (BAG+'int main(){Bag[1] data={{tag=42,r=make(1)}};return 42;}', 'copyable'),
	'buffer': (BAG+'int main(){owned Bag[] data=new Bag[1];return 42;}', 'copyable'),
	'generic-argument': (BAG+'struct Plain<T>{T value;}int main(){Plain<Bag> data={value={tag=42,r=make(1)}};return 42;}', 'GEN1_PLAIN_COPY'),
	'enum-payload-copy': (BAG+'enum Value{Item(Bag bag)}int main(){'+LOCAL+'var value=Value.Item(bag);return 42;}', 'move'),
	'generic-context': (BAG+'int work<T>(T value){'+LOCAL+'return 42;}int main(){return 42;}', 'concrete nongeneric local context'),
	'checked-moved-read': (BAG+'int work() throws Error{'+LOCAL+'var moved=move bag;return bag.tag;}int main(){return 42;}', 'moved'),
	'checked-second-move': (BAG+'int work() throws Error{'+LOCAL+'var moved=move bag;var again=move bag;return 42;}int main(){return 42;}', 'moved'),
	'checked-moved-join': (BAG+'int work() throws Error{'+LOCAL+'try{if(live()==1){var moved=move bag;}}catch(Error error){}return bag.tag;}int main(){return 42;}', 'may have been moved'),
	'checked-moved-catch': (BAG+'int main(){'+LOCAL+'var moved=move bag;try{throw new Error("failure");}catch(Error error){return bag.tag;}return 42;}', 'moved'),
	'checked-out-of-scope': (BAG+'int main(){try{'+LOCAL+'throw new Error("failure");}catch(Error error){return bag.tag;}return 42;}', 'unknown'),
	'checked-unhandled-effect': (BAG+'int checked() throws Error{throw new Error("failure");}int main(){'+LOCAL+'checked();return 42;}', 'unhandled checked exception'),
}

# Historical refusals promoted by the authorized ownership campaigns remain positive controls.
PROMOTED = {
	'async-local': (BAG+'async int work(){'+LOCAL+'return 42;}int main(){return 42;}', ''),
	'async-local-executed': ('struct Bag { int tag; owned R r; }\nasync int work() throws Error {\n\tBag bag = {tag = 42, r = make(1)};\n\tawait delay_ticks(1);\n\tmark(bag.tag); return bag.tag;\n}\nasync void collect() throws Error {\n\tint value = await work();\n\tif (value != 42 || live() != 0) { throw new Error("async record cleanup"); }\n}\nint main() {\n\ttry { var executor = VirtualExecutor.open(8); var status = executor.run(collect());\n\t\tmatch (status) { case RunStatus.Completed(): {} else: { return 1; } }\n\t} catch (Error error) { return 2; }\n\treturn 42;\n}', 'A1 M42 F1 '),
	'enum-payload': (BAG+'enum Value{Item(Bag bag)}int main(){'+LOCAL+'var value=Value.Item(move bag);match(move value){case Value.Item(payload):{mark(payload.tag);}}return 42;}', 'A1 M42 F1 '),
	'parameter': (BAG+'void consume(Bag bag){}int main(){'+LOCAL+'consume(move bag);return 42;}', 'A1 F1 '),
	'return-move': (BAG+'Bag make_bag(){'+LOCAL+'return move bag;}int main(){var result=make_bag();return result.tag;}', 'A1 F1 '),
	'resource-write': (body(LOCAL+'bag.r=make(2);'), 'A1 A2 F1 F2 '),
	'extract-resource': (body(LOCAL+'owned R extracted=move bag.r;'), 'A1 F1 '),
	'owning-slice': ('struct Bag{owned int[] data;}int main(){return 42;}', ''),
	'owning-class': ('class C{}struct Bag{owned C child;}int main(){return 42;}', ''),
	'checked-nested-owner': (BAG+'struct Nested{Bag bag;}int checked() throws Error{return 42;}int main(){try{Nested nested={bag={tag=checked(),r=make(1)}};}catch(Error error){}return 42;}', 'A1 F1 '),
	'nested-owner': (BAG+'struct Nested{Bag bag;}int main(){return 42;}', ''),
	'nested-companion': ('struct Plain{int tag;}struct Bag{Plain plain;owned R r;}int main(){return 42;}', ''),
	'vector-companion': ('struct Bag{f32<4> lanes;owned R r;}int main(){return 42;}', ''),
	'resource-first': (body('Bag bag={r=make(1),tag=42};'), 'A1 F1 '),
	'two-resources': ('struct Bag{owned R a;owned R b;}int main(){return 42;}', ''),
	'checked-resource-initializer': (BAG+'owned R checked() throws Error{owned R result=make(1);return move result;}int main(){try{Bag bag={tag=42,r=checked()};}catch(Error error){}return 42;}', 'A1 F1 '),
	'checked-scalar-initializer': (BAG+'int checked() throws Error{return 42;}int main(){try{Bag bag={tag=(checked() as int),r=make(1)};}catch(Error error){}return 42;}', 'A1 F1 '),
	'checked-nested-resource-argument': (BAG+'int checked() throws Error{return 1;}int main(){try{Bag bag={tag=42,r=make(checked())};}catch(Error error){}return 42;}', 'A1 F1 '),
	'checked-throws-initializer': (BAG+'int checked() throws Error{return 42;}int work() throws Error{Bag bag={tag=checked(),r=make(1)};return bag.tag;}int main(){return 42;}', ''),
}

def main(compiler, output):
	compiler, output = Path(compiler).resolve(), Path(output).resolve()
	assert not output.is_relative_to(ROOT), 'generated tests must stay outside source'
	output.mkdir(parents=True, exist_ok=True)
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	rows = []

	def run(command, expected=0, stdout=None, diagnostic=None, memory=False, leaked=False):
		result = subprocess.run(list(map(str, command)), cwd=ROOT, capture_output=True,
			text=True, timeout=90, env=dict(os.environ, CCACHE_DISABLE='1'))
		valid = result.returncode == expected and (stdout is None or result.stdout == stdout)
		if memory:
			valid &= ('ERROR SUMMARY: 0 errors' in result.stderr
				and 'in use at exit: 0 bytes in 0 blocks' in result.stderr
				and '(suppressed: 0 from 0)' in result.stderr)
		elif leaked:
			valid &= ('in use at exit: 4 bytes in 1 blocks' in result.stderr
				and 'ERROR SUMMARY: 1 errors' in result.stderr
				and '(suppressed: 0 from 0)' in result.stderr)
		elif diagnostic:
			valid &= diagnostic in result.stderr and not result.stdout
			valid &= 'internal ' not in result.stderr and 'assertion' not in result.stderr
		else:
			valid &= not result.stderr
		rows.append(dict(command=list(map(str, command)), expected_exit=expected,
			actual_exit=result.returncode, stdout=result.stdout,
			stderr=result.stderr, status='PASS' if valid else 'FAIL'))
		(output/'checks.json').write_text(json.dumps(rows, indent=2)+'\n')
		assert valid, rows[-1]
		return result.stdout

	observer = output/'observer.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', HERE/'observer.c', '-o', observer], stdout='')
	async_objects = []
	for name in ['async/virtual', 'platform/text-posix']:
		obj = output/(Path(name).name+'-async.o'); async_objects += ['--link-object', obj]
		run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', ROOT/('lib/astra/'+name+'.c'), '-o', obj], stdout='')
	originals = {}
	for name, trace in TRACES.items():
		inputs = [HERE/(name+'.astra'), '--vapi', VAPI]
		if name.startswith('checked-'):
			inputs += [HERE/'checked-support.astra']
		for stage in STAGES:
			dump = run([compiler, '--dump-'+stage, *inputs])
			(output/(name+'.'+stage)).write_text(dump)
		native = output/name
		run([compiler, *inputs, '--link-object', observer, '-o', native], stdout='')
		run([native], 42, trace)
		ssa, ir = (output/(name+'.ssa')).read_text(), (output/(name+'.llvm')).read_text()
		ordinal = re.search(r'\(function #(\d+) "main" -> int', ssa)[1]
		ir += '\ndefine i32 @main(){\n %r=call fastcc i32 @astra.fn.'+ordinal+'()\n ret i32 %r\n}\n'
		llvm, optimized, obj = output/(name+'.ll'), output/(name+'-O2.ll'), output/(name+'-O2.o')
		llvm.write_text(ir)
		run(['opt', '-passes=verify', '-disable-output', llvm], stdout='')
		run(['opt', '-passes=default<O2>', '-S', llvm, '-o', optimized], stdout='')
		run(['opt', '-passes=verify', '-disable-output', optimized], stdout='')
		run(['llc', '-O2', '-filetype=obj', '-relocation-model=pic', optimized, '-o', obj], stdout='')
		binary = output/(name+'-O2')
		run(['cc', obj, observer, '-o', binary], stdout='')
		run([binary], 42, trace)
		originals[name] = (ir, binary)
		if shutil.which('valgrind'):
			run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full',
				'--show-leak-kinds=all', '--errors-for-leak-kinds=all', binary], 42, trace, memory=True)
		else:
			print('Valgrind unavailable: memory evidence NOT TESTED')

	for name, (source, trace) in PROMOTED.items():
		path = output/(name+'.astra'); path.write_text(source+'\n')
		inputs = [path, '--vapi', VAPI]
		if name.startswith(('checked-', 'async-')):
			inputs += [ROOT/'lib/astra/base/errors.astra']
		linked = []
		if name.startswith('async-'):
			inputs += [ROOT/'lib/astra/async/virtual.astra']
			linked = [*async_objects, '--link-library', 'pthread']
		for stage in STAGES:
			dump = run([compiler, '--dump-'+stage, *inputs])
			(output/(name+'.'+stage)).write_text(dump)
		for level in ['O0', 'O1', 'O2']:
			binary = output/(name+'-'+level)
			run([compiler, '-'+level, *inputs, '--link-object', observer, *linked, '-o', binary], stdout='')
			run([binary], 42, trace)
			if name in ['enum-payload', 'async-local-executed']:
				run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', binary], 42, trace, memory=True)

				# Mutate only generated IR in the external build, keep both source and
				# the independently optimized positive untouched. The observer catches
				# omitted and repeated actual release, independently of stage markers.
	original, positive = originals['control']
	pattern = r'^\s*call void @of_release\(ptr [^)]+\)\n'
	assert len(re.findall(pattern, original, re.M)) == 1
	for name, replacement, expected, trace in [('omitted', '', 81, 'A7 M42 '),
		('doubled', lambda match: match[0]*2, -6, None)]:
		llvm, obj, binary = (output/('control-'+name+suffix) for suffix in ['.ll', '.o', ''])
		llvm.write_text(re.sub(pattern, replacement, original, flags=re.M))
		run(['opt', '-passes=verify', '-disable-output', llvm], stdout='')
		run(['llc', '-filetype=obj', '-relocation-model=pic', llvm, '-o', obj], stdout='')
		run(['cc', obj, observer, '-o', binary], stdout='')
		run([binary], expected, trace)
		if name == 'omitted' and shutil.which('valgrind'):
			run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full',
				'--show-leak-kinds=all', '--errors-for-leak-kinds=all', binary], 99, trace, leaked=True)
	run([positive], 42, TRACES['control'])

	# Exceptional cleanup has its own actual-release controls. The omitted
	# release is detected in the catch, before exception destruction, and the
	# original binary remains intact throughout both isolated child mutations.
	original, positive = originals['checked-exit']
	# This witness has one normal return and one exceptional cleanup. Select
	# the failure predecessor from the emitted SSA, rather than rewriting both.
	ssa = (output/'checked-exit.ssa').read_text()
	call = re.search(r'\(call #\d+ "checked"[\s\S]*?\(conditional-branch[\s\S]*?\(false #([0-9]+)', ssa)
	assert call, 'checked call must expose its actual failure edge'
	failure = call[1]
	edge = re.search(r'^b'+failure+r':[^\n]*\n[\s\S]*?(?=^[-\w.]+:)', original, re.M)
	assert edge, 'failure block must exist in generated LLVM'
	cleanup = re.search(r'br i1 [^\n]+label %([\w.]+\.call)', edge[0])
	assert cleanup, 'failure edge must guard its Resource cleanup'
	exceptional = re.escape(cleanup[1])+r':[^\n]*\n(?P<release>\s*call void @of_release\(ptr [^)]+\)\n)'
	assert len(re.findall(exceptional, original, re.M)) == 1
	for name, expected, trace in [('omitted', 81, 'A23 E230 D230 '), ('doubled', -6, None)]:
		llvm, obj, binary = (output/('checked-exit-'+name+suffix) for suffix in ['.ll', '.o', ''])
		def mutate(match):
			release = match['release']
			return match[0][:-len(release)] + (release*2 if name == 'doubled' else '')
		llvm.write_text(re.sub(exceptional, mutate, original, flags=re.M))
		run(['opt', '-passes=verify', '-disable-output', llvm], stdout='')
		run(['llc', '-filetype=obj', '-relocation-model=pic', llvm, '-o', obj], stdout='')
		run(['cc', obj, observer, '-o', binary], stdout='')
		run([binary], expected, trace)
		if name == 'omitted' and shutil.which('valgrind'):
			run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full',
				'--show-leak-kinds=all', '--errors-for-leak-kinds=all', binary], 99, trace, leaked=True)
	run([positive], 42, TRACES['checked-exit'])

	sanitizer_cases = 0
	if shutil.which('clang'):
		# LLVM dumps have no target triple. Use the installed compiler's host
		# triple for correct ASan shadow mapping, instrument once with opt,
		# then use llc; feeding instrumented IR to a sanitizer compiler again
		# gives redundant instrumentation rather than independent evidence.
		triple = run(['clang', '-dumpmachine']).strip()
		sanitized_observer = output/'observer-asan.o'
		run(['clang', '-std=c11', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined',
			'-c', HERE/'observer.c', '-o', sanitized_observer], stdout='')
		for name, expected, trace in [*( (name, 42, trace) for name, trace in TRACES.items()
			if name.startswith('checked-') ),
			('checked-exit-omitted', 81, 'A23 E230 D230 '),
			('checked-exit-doubled', -6, None)]:
			llvm = output/(name+'-asan.ll')
			ir = (output/(name+'.ll')).read_text()
			ir, count = re.subn(r'^(define [^\n]+) \{$', r'\1 sanitize_address {', ir, flags=re.M)
			assert count > 0
			llvm.write_text(ir)
			instrumented, obj, binary = (output/(name+'-asan'+suffix) for suffix in ['-instrumented.ll', '.o', ''])
			run(['opt', '-mtriple='+triple, '-passes=asan', '-S', llvm, '-o', instrumented], stdout='')
			assert '__asan_report_' in instrumented.read_text(), 'sanitizer must instrument generated accesses'
			run(['llc', '-filetype=obj', '-relocation-model=pic', instrumented, '-o', obj], stdout='')
			run(['clang', '-fsanitize=address,undefined', obj, sanitized_observer, '-o', binary], stdout='')
			run(['env', 'ASAN_OPTIONS=detect_leaks=1:halt_on_error=1', 'UBSAN_OPTIONS=halt_on_error=1',
				binary], expected, trace)
			sanitizer_cases += 1
		run(['env', 'ASAN_OPTIONS=detect_leaks=1:halt_on_error=1', 'UBSAN_OPTIONS=halt_on_error=1',
			output/'checked-exit-asan'], 42, TRACES['checked-exit'])
	else:
		print('Clang sanitizer unavailable: sanitizer evidence NOT TESTED')

	for name, (source, message) in NEGATIVES.items():
		path = output/(name+'.astra'); path.write_text(source+'\n')
		inputs = [path, '--vapi', VAPI]
		if name.startswith(('checked-', 'async-')):
			inputs += [ROOT/'lib/astra/base/errors.astra']
		if name.startswith('async-'):
			inputs += [ROOT/'lib/astra/async/virtual.astra']
		stages = ['cfg', 'ssa', 'nabi', 'llvm'] if name in FLOW else STAGES
		for stage in stages:
			run([compiler, '--dump-'+stage, *inputs], 1, diagnostic=message)
		rejected = output/(name+'-rejected')
		run([compiler, *inputs, '-o', rejected], 1, diagnostic=message)
		assert not rejected.exists(), 'invalid source must not produce an executable'
	print(f'{len(rows)} command checks passed: {len(TRACES)} native/O2 cases, {len(PROMOTED)} promoted O0/O1/O2 cases, four rejected cleanup controls, '
		f'{len(NEGATIVES)} negative source forms, {sanitizer_cases} sanitizer cases; Valgrind '+(f'{len(TRACES)}/{len(TRACES)}' if shutil.which('valgrind') else 'NOT TESTED'))

if __name__ == '__main__':
	main(*sys.argv[1:])
