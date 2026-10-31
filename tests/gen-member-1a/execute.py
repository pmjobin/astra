# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Real two-type bag execution, independent O2, allocator/payload observations."""
from pathlib import Path
import hashlib
import json
import os
import re
import resource
import shutil
import signal
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
APP = ROOT / 'examples/generic-diagnostic-bags/main.astra'
MODEL = APP.with_name('model.astra')
BAG = ROOT / 'lib/astra/collections/bag.astra'
LIBS = [ROOT / name for name in ['lib/astra/text/utf8-message.astra',
	'lib/astra/base/errors.astra', 'lib/astra/hosted/text.astra']]
STAGES = ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'llvm']


def instrument(ir, classes):
	"""Add test-only observers after the real artifact has passed its verifier."""
	for kind, ordinal in classes.items():
		counts = {}
		pattern = re.compile(r'^(define internal fastcc [^\n]+ @astra\.slots\.' + str(ordinal)
			+ r'\.(\w+)\([^\n]+\) \{\n)(.*?)(^\})', re.M | re.S)
		def operation(match):
			action, body = match[2], match[3]
			if action in ['initialize', 'append', 'borrow']:
				if action == 'initialize':
					body, n = re.subn(r'^  ret void$', f'  call void @bag_obs_init(i32 {kind}, ptr %0)\n  ret void', body, flags=re.M)
				elif action == 'append':
					body, n = re.subn(r'^  ret void$', f'  call void @bag_obs_append(i32 {kind}, ptr %0, ptr %1)\n  ret void', body, flags=re.M)
				else:
					body, n = re.subn(r'^  ret ptr (%[\w.]+)$', rf'  call void @bag_obs_borrow(i32 {kind}, ptr %0, i32 %1, ptr \1)\n  ret ptr \1', body, flags=re.M)
			elif action == 'reserve':
				body, n = re.subn(r'^(  store i32 %1, ptr %slots\.capacity\.address, align 4)$', rf'\1\n  call void @bag_obs_commit(i32 {kind}, ptr %0, ptr %slots.base, ptr %reserve.replacement.base, i32 %slots.length, i32 %1)', body, flags=re.M)
			elif action == 'drop':
				body, begin = re.subn(r'^(  br label %drop\.reverse\.header)$', rf'  call void @bag_obs_drop_begin(i32 {kind}, ptr %0)\n\1', body, count=1, flags=re.M)
				body, retire = re.subn(r'^(  store i32 %drop\.index, ptr %slots\.length\.address, align 4)$', rf'\1\n  call void @bag_obs_retire(i32 {kind}, ptr %0, i32 %drop.index, ptr %drop.element)', body, flags=re.M)
				body, end = re.subn(r'^  ret void$', f'  call void @bag_obs_drop_done(i32 {kind}, ptr %0)\n  ret void', body, flags=re.M)
				assert (begin, retire, end) == (1, 1, 1)
				n = 1
			else:
				return match[0]
			assert n == 1, (kind, action, n)
			counts[action] = n
			return match[1] + body + match[4]
		ir = pattern.sub(operation, ir)
		assert set(counts) == {'initialize', 'append', 'borrow', 'reserve', 'drop'}, counts
	main = re.compile(r'^(define i32 @main\([^\n]*\) \{\n)(.*?)(^\})', re.M | re.S)
	def done(match):
		body, n = re.subn(r'^(  ret i32 .+)$', r'  call void @bag_obs_done()\n\1', match[2], flags=re.M)
		assert n > 0
		return match[1] + body + match[3]
	ir, n = main.subn(done, ir); assert n == 1
	return ir + '''
declare void @bag_obs_init(i32, ptr)
declare void @bag_obs_append(i32, ptr, ptr)
declare void @bag_obs_borrow(i32, ptr, i32, ptr)
declare void @bag_obs_commit(i32, ptr, ptr, ptr, i32, i32)
declare void @bag_obs_drop_begin(i32, ptr)
declare void @bag_obs_retire(i32, ptr, i32, ptr)
declare void @bag_obs_drop_done(i32, ptr)
declare void @bag_obs_done()
'''


def main(compiler_path, emitter_path, output_path):
	compiler, emitter, output = map(lambda p: Path(p).resolve(), [compiler_path, emitter_path, output_path])
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='run-', dir=output))
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	rows = []
	def run(command, expected=0, stdout='', memory=False, save=None, extra_env=None):
		command = list(map(str, command))
		p = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=90,
			env=dict(os.environ, CCACHE_DISABLE='1', **(extra_env or {})))
		valid = p.returncode == expected and (stdout is None or save is not None or p.stdout == stdout)
		if memory:
			valid &= all(x in p.stderr for x in ['ERROR SUMMARY: 0 errors', 'in use at exit: 0 bytes in 0 blocks', '(suppressed: 0 from 0)'])
		else:
			valid &= not p.stderr
		if save is not None: save.write_text(p.stdout)
		rows.append(dict(command=command, expected=expected, actual=p.returncode, stdout=p.stdout,
			stderr=p.stderr, memory=memory, extra_env=extra_env, passed=bool(valid)))
		(out / 'checks.json').write_text(json.dumps(rows, indent=2) + '\n')
		assert valid, rows[-1]
		return p.stdout
	providers = []
	for name in ['args', 'text']:
		obj = out / (name + '.o'); providers.append(obj)
		run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', ROOT / f'lib/astra/platform/{name}-posix.c', '-o', obj])
	observer = out / 'observer.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', HERE / 'observer.c', '-o', observer])
	vg = ['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99']
	memory_available = shutil.which('valgrind') is not None
	def compile_pair(label, inputs):
		for stage in STAGES:
			run([compiler, '--dump-' + stage, *inputs], save=out / (label + '.' + stage))
		native, ir, optimized, obj, o2 = [out / (label + suffix) for suffix in ['', '.ll', '-O2.ll', '-O2.o', '-O2']]
		run([compiler, *inputs, *[x for p in providers for x in ['--link-object', p]], '-o', native])
		run([emitter, '--emit', ir, *inputs])
		run(['opt', '-passes=verify', '-disable-output', ir])
		run(['opt', '-passes=default<O2>', '-S', ir, '-o', optimized])
		run(['opt', '-passes=verify', '-disable-output', optimized])
		run(['llc', '-O2', '-filetype=obj', '-relocation-model=pic', optimized, '-o', obj])
		run(['cc', obj, *providers, '-o', o2])
		return native, o2, ir
	def exercise(pair, cases):
		for executable in pair[:2]:
			for arguments, trace in cases:
				run([executable, *arguments], stdout=trace)
				if memory_available: run([*vg, executable, *arguments], stdout=trace, memory=True)
	cases = [(['empty'], 'empty\n'), (['one'], 'checked\ndrop 1\n'),
		(['two'], 'checked\ndrop 2\ndrop 1\n'), ([], 'checked\ndrop 3\ndrop 2\ndrop 1\n'),
		(['early'], 'early\ndrop 3\ndrop 2\ndrop 1\n'), (['error'], 'drop 2\ndrop 1\ncaught\n')]
	inputs = [APP, MODEL, BAG, *LIBS]
	pair = compile_pair('application', inputs); exercise(pair, cases)
	# Reverse source argument order and check same-key requests do not duplicate.
	other = compile_pair('reverse-inputs', list(reversed(inputs))); exercise(other, [cases[3]])
	# Reverse real application/request order, not only argv (SourceSet sorts argv).
	original = APP.read_text(); first = original.index('bool inspect_diagnostic(')
	second = original.index('bool inspect_message('); third = original.index('bool diagnostic_identity(')
	reordered = original[:first] + original[second:third] + original[first:second] + original[third:]
	reordered = reordered.replace('var diagnostics = new Bag<Diagnostic>();\n\tvar messages = new Bag<Utf8Message>();',
		'var messages = new Bag<Utf8Message>();\n\tvar diagnostics = new Bag<Diagnostic>();')
	reverse_source = out / 'reverse-order.astra'; reverse_source.write_text(reordered)
	reverse_order = compile_pair('reverse-order', [reverse_source, MODEL, BAG, *LIBS]); exercise(reverse_order, [cases[3]])
	def bag_order(label):
		text = (out / (label + '.ssa')).read_text()
		return int(re.search(r'\(class #(\d+) "Bag<Diagnostic>"', text)[1]) < int(re.search(r'\(class #(\d+) "Bag<Utf8Message>"', text)[1])
	assert bag_order('application') != bag_order('reverse-order')
	for label in ['application', 'reverse-inputs']:
		ssa = (out / (label + '.ssa')).read_text()
		for name in ['Bag<Diagnostic>', 'Bag<Utf8Message>']:
			assert len(re.findall(r'\(class #\d+ "' + re.escape(name) + '"', ssa)) == 1
	for element, trace in [('Diagnostic', 'drop 3\ndrop 2\ndrop 1\n'), ('Utf8Message', '')]:
		source = out / (element + '-alone.astra')
		inspect = 'diagnostic_is(value, 1, "a\\0b")' if element == 'Diagnostic' else 'message_is(value, "a\\0b")'
		# Every owner comes from an existing exact heap factory; one Bag source.
		maker = lambda n: f'make_diagnostic({n}, slice(bytes))' if element == 'Diagnostic' else f'utf8_message(slice(bytes))'
		source.write_text(f'''bool inspect(Bag<{element}> bag){{return read(bag.entries[0]);}}
bool read({element} value){{return {inspect};}}
int main(){{try{{u8[3] bytes={{97,0,98}};var bag=new Bag<{element}>();if(!bag.reserve(2)){{return 81;}}
var first={maker(1)};var second={maker(2)};bag.append(move first);bag.append(move second);
if(!bag.reserve(3)||!inspect(bag)){{return 82;}}var third={maker(3)};bag.append(move third);
if(bag.count()!=3||bag.capacity()!=3){{return 83;}}}}catch(InvalidUtf8 error){{return 84;}}return 0;}}
''')
		alone = compile_pair(element + '-alone', [source, MODEL, BAG, *LIBS]); exercise(alone, [([], trace)])
		text = (out / (element + '-alone.ssa')).read_text()
		assert len(re.findall(r'\(class #\d+ "Bag<', text)) == 1
	empty_messages = out / 'empty-messages.astra'
	empty_messages.write_text('''bool empty_at(Bag<Utf8Message> bag,int index){return message_is(bag.entries[index],"");}
int main(){try{var bytes=new u8[0];var first=utf8_message(bytes);var second=utf8_message(bytes);release bytes;
var bag=new Bag<Utf8Message>();if(!bag.reserve(2)){return 81;}bag.append(move first);bag.append(move second);
if(!bag.reserve(3)||!empty_at(bag,0)||!empty_at(bag,1)){return 82;}}
catch(InvalidUtf8 error){return 83;}return 0;}
''')
	empty_pair = compile_pair('empty-messages', [empty_messages, MODEL, BAG, *LIBS]); exercise(empty_pair, [([], '')])
	# Same argument/layout with two independent source definition identities.
	crate = out / 'crate.astra'; crate.write_text(BAG.read_text().replace('class Bag<T>', 'class Crate<T>'))
	nominal = out / 'nominal.astra'
	nominal.write_text('''bool read_bag(Bag<Utf8Message> bag){return message_is(bag.entries[0],"a");}
bool read_crate(Crate<Utf8Message> bag){return message_is(bag.entries[0],"a");}
int main(){try{u8[1] bytes={97};var a=new Bag<Utf8Message>();var b=new Crate<Utf8Message>();
if(!a.reserve(2)||!b.reserve(2)){return 81;}var x=utf8_message(slice(bytes));var y=utf8_message(slice(bytes));
a.append(move x);b.append(move y);if(!read_bag(a)||!read_crate(b)){return 82;}}
catch(InvalidUtf8 error){return 83;}return 0;}
''')
	definitions = compile_pair('two-definitions', [nominal, MODEL, BAG, crate, *LIBS]); exercise(definitions, [([], '')])
	smoke = compile_pair('smoke', [HERE / 'smoke.astra', BAG]); exercise(smoke, [([], '')])
	moved = compile_pair('move', [HERE / 'move.astra', BAG]); exercise(moved, [([], '')])
	# No slot layout/helper/runtime cost for an unused generic definition.
	unused = out / 'unused.astra'; unused.write_text('int main(){return 0;}\n')
	plain = compile_pair('unused', [unused, BAG]); exercise(plain, [([], '')])
	assert 'astra.slots.' not in (out / 'unused.llvm').read_text()
	# Source-valid dynamic preconditions trap in expected fatal children only.
	fatal_prefix = 'class Item{int value;init(int value){this.value=value;}}bool read(Item item){return item.value==1;}'
	fatal_cases = {
		'empty-index': 'var bag=new Bag<Item>();if(read(bag.entries[0])){return 81;}',
		'negative-index': 'var bag=new Bag<Item>();if(!bag.reserve(1)){return 81;}var item=new Item(1);bag.append(move item);if(read(bag.entries[-1])){return 82;}',
		'index-at-length': 'var bag=new Bag<Item>();if(!bag.reserve(1)){return 81;}var item=new Item(1);bag.append(move item);if(read(bag.entries[1])){return 82;}',
		'full-append': 'var bag=new Bag<Item>();if(!bag.reserve(1)){return 81;}var first=new Item(1);var second=new Item(2);bag.append(move first);bag.append(move second);',
		'zero-capacity': 'var bag=new Bag<Item>();var item=new Item(1);bag.append(move item);',
		'null-owner': 'var bag=new Bag<Item>();if(!bag.reserve(1)){return 81;}var item=maybe(false);bag.append(move item);',
	}
	for label, body in fatal_cases.items():
		source = out / ('fatal-' + label + '.astra')
		extra = 'owned Item maybe(bool present){if(present){var item=new Item(1);return move item;}return null;}' if label == 'null-owner' else ''
		source.write_text(fatal_prefix + extra + 'int main(){' + body + 'return 0;}\n')
		for program in compile_pair('fatal-' + label, [source, BAG])[:2]:
			run([program], expected=-signal.SIGILL)
	ssa = (out / 'application.ssa').read_text()
	classes = {kind: int(re.search(r'\(class #(\d+) "' + element + '"', ssa)[1])
		for kind, element in [(1, 'Diagnostic'), (2, 'Utf8Message')]}
	observed = out / 'observed.ll'; observed.write_text(instrument(pair[2].read_text(), classes))
	programs = []
	for mode in ['O0', 'O2']:
		ir, obj, binary = [out / ('observed-' + mode + suffix) for suffix in ['.ll', '.o', '']]
		run(['opt', '-passes=verify' if mode == 'O0' else '-passes=default<O2>', '-S', observed, '-o', ir])
		run(['opt', '-passes=verify', '-disable-output', ir])
		run(['llc', '-' + mode, '-filetype=obj', '-relocation-model=pic', ir, '-o', obj])
		run(['cc', obj, *providers, observer, '-Wl,--wrap=calloc,--wrap=malloc,--wrap=free', '-o', binary])
		programs.append(binary)
	for arguments, _ in cases:
		outputs = [run([program, *arguments], stdout=None) for program in programs]
		assert outputs[0] == outputs[1] and 'OK bags=2 ' in outputs[0]
		if arguments in [[], ['early'], ['error']]:
			assert len(re.findall(r'^G\d kind=[12] 2->3 len=2 ', outputs[0], re.M)) == 2
		(out / ('observed-' + ('-'.join(arguments) or 'three') + '.trace')).write_text(outputs[0])
	for program in programs:
		trace = run([program], expected=-signal.SIGILL, stdout=None, extra_env={'GEN_BAG_FAIL_GROW': '1'})
		assert 'OOM growth\n' in trace and '2->3' not in trace and not re.search(r'^[RDZ]', trace, re.M)
	identity = dict(output=str(out), commands=len(rows), all_passed=all(r['passed'] for r in rows),
		memory_available=memory_available, memory_runs=sum(r['memory'] for r in rows),
		compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),
		emitter_sha256=hashlib.sha256(emitter.read_bytes()).hexdigest(),
		sources={str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [APP, MODEL, BAG, *LIBS, HERE / 'observer.c', Path(__file__).resolve()]})
	(out / 'identity.json').write_text(json.dumps(identity, indent=2) + '\n')
	(output / 'current.json').write_text(json.dumps(identity, indent=2) + '\n')
	print(json.dumps(identity, indent=2))


if __name__ == '__main__':
	main(*sys.argv[1:])
