# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Focused heap/lexical ownership, actual receiver pointers, cleanup and diagnostics."""
import json
import os
from pathlib import Path
import re
import resource
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).resolve().parent
OWNED = 'A I1 A I2 P1 P2 P1 P1 P1 P1 D F1 D F2 A I3 D F3 A I4 A I5 D F4 D F5 '
CHECKED = 'A A F0 F0 A I1 A A D F1 F0 F0 A I2 A A A I1 A A D F1 F0 F0 D F2 F0 F0 A I1 D F1 '
HEADER = 'class Box{int value;init(int value){this.value=value;}}void consume(owned Box value){}'
LABEL = 'class Label{readonly string text;init(string text){this.text=text;}property string view{get{return this.text;}}}'
LOAN_ERROR = 'cannot invalidate a receiver while a stored text loan remains in its lexical extent'
CONSUMER = LABEL+'int consume(owned Label label){return 0;}'
NEGATIVES = {
	'copy': (HEADER, 'var first=new Box(42);Box copy=first;', "persistent alias from owned ClassType binding 'first' is unsupported"),
	'owner-copy': (HEADER, 'var first=new Box(42);owned Box copy=first;', 'owned ClassType local requires fresh object construction'),
	'after-move': (HEADER, 'var first=new Box(42);var second=move first;return first.value;', "use of moved owned value 'first'"),
	'double-move': (HEADER, 'var first=new Box(42);var second=move first;var third=move first;', "use of moved owned value 'first'"),
	'overlap': (HEADER+'void overlap(Box view,owned Box owner){}', 'var first=new Box(42);overlap(first,move first);', "cannot borrow moved owned value 'first'"),
	'rearm': (HEADER+'owned Box make(){var result=new Box(42);return move result;}', 'var first=new Box(42);first=make();', "owned ClassType binding 'first' cannot be rebound"),
	'mixed-input-domain': (HEADER, 'var heap=new Box(42);owned Box lexical=Box.init(42);consume(move heap);consume(move lexical);', 'owned Class parameter joins incompatible heap and lexical storage origins'),
	'borrow-return': (HEADER+'Box leak(Box value){return value;}', '', 'object-reference results are unsupported; result lifetime relationships are not expressible'),
	'field-release': (LABEL, 'var first=new Label("x");var view=first.text;release first;return view.byte_length;', 'cannot invalidate a receiver while a stored text loan remains in its lexical extent'),
	'field-move': (LABEL, 'var first=new Label("x");var view=first.text;var second=move first;return view.byte_length;', 'cannot invalidate a receiver while a stored text loan remains in its lexical extent'),
	'field-escape': (LABEL, 'var view="x";{var first=new Label("x");view=first.text;}return view.byte_length;', 'receiver text loan requires its exact backing owner to outlive the destination local'),
	'field-return': (LABEL+'string leak(Label label){var view=label.text;return view;}', '', 'borrowed text cannot escape through a STATIC_TEXT result'),
	'property-release': (LABEL, 'var first=new Label("x");var view=first.view;release first;return view.byte_length;', 'cannot invalidate a receiver while a stored text loan remains in its lexical extent'),
	'borrowed-parameter-move': (LABEL+'int leak(Label label){var view=label.text;var next=move label;return view.byte_length;}', '', "object ownership transfer requires an owned ClassType binding; 'label' is nontransferable"),
	'field-copy-release': (LABEL, 'var first=new Label("x");var view=first.text;var copy=view;view="static";release first;return copy.byte_length;', LOAN_ERROR),
	'field-join-release': (LABEL, 'var first=new Label("x");var second=new Label("y");var view=first.text;if(second.text=="y"){view=second.text;}release first;return view.byte_length;', LOAN_ERROR),
	'field-loop-release': (LABEL, 'var first=new Label("x");var view="static";int count=0;while(count<2){view=first.text;count=count+1;}release first;return view.byte_length;', LOAN_ERROR),
	'field-inherited-release': (LABEL+'class Child:Label{init(string text):base(text){}}', 'var first=new Child("x");var view=first.text;release first;return view.byte_length;', LOAN_ERROR),
	'field-conversion-move': (CONSUMER, 'var first=new Label("x");var view=first.text;var number=consume(move first) as f64;return view.byte_length;', LOAN_ERROR),
	'field-integer-conversion-move': (CONSUMER, 'var first=new Label("x");var view=first.text;var number=consume(move first) as i8;return view.byte_length;', LOAN_ERROR),
	'field-float-conversion-move': (LABEL+'f64 consume(owned Label label){return 0.0d;}', 'var first=new Label("x");var view=first.text;var number=consume(move first) as f32;return view.byte_length;', LOAN_ERROR),
	'field-store-move': (CONSUMER+'class Value{int number;init(){this.number=0;}}', 'var first=new Label("x");var view=first.text;var value=new Value();value.number=consume(move first);return view.byte_length;', LOAN_ERROR),
	'field-record-store-move': (CONSUMER+'struct Value{int number;}', 'var first=new Label("x");var view=first.text;Value value={number=0};value.number=consume(move first);return view.byte_length;', LOAN_ERROR),
	'field-owner-return': (LABEL+'owned Label pass(owned Label label){var view=label.text;return move label;}', '', LOAN_ERROR),
	'field-owner-result-return': (LABEL+'owned Label transfer(owned Label label){return move label;}owned Label pass(owned Label label){var view=label.text;return transfer(move label);}', '', LOAN_ERROR),
	'constructor-throws': ('class Bad{init() throws Error{}}', '', 'throws requires a concrete native function, class method or bounded Singleton initializer'),
}


def main(compiler, output):
	compiler = Path(compiler).resolve()
	output = Path(output).resolve()
	assert not output.is_relative_to(ROOT), 'generated tests must stay outside the source tree'
	output.mkdir(parents=True, exist_ok=True)
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	rows = []
	def run(command, expected=0, stdout=None, diagnostic=None, memory=False, contains=None):
		command = list(map(str, command))
		p = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=90,
			env=dict(os.environ, CCACHE_DISABLE='1'))
		valid = p.returncode == expected and (stdout is None or p.stdout == stdout)
		if contains is not None:
			valid = valid and contains in p.stdout
		if memory:
			valid = valid and 'ERROR SUMMARY: 0 errors' in p.stderr and 'in use at exit: 0 bytes in 0 blocks' in p.stderr and '(suppressed: 0 from 0)' in p.stderr
		elif diagnostic:
			valid = valid and diagnostic in p.stderr
		else:
			valid = valid and not p.stderr
		rows.append(dict(command=command, expected_exit=expected, actual_exit=p.returncode,
			stdout=p.stdout, stderr=p.stderr, status='PASS' if valid else 'FAIL'))
		(output/'checks.json').write_text(json.dumps(rows, indent='\t')+'\n')
		assert valid, rows[-1]
		return p.stdout
	objects = {}
	for name, defines in [('observer', []), ('memory', ['-DALLOC_MEMORY_ONLY']), ('lexical', [])]:
		obj = output/(name+'.o')
		run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', *defines, '-c', FIXTURES/('lexical.c' if name == 'lexical' else 'observer.c'), '-o', obj], stdout='')
		objects[name] = obj
	for name, trace in [('owned', OWNED), ('checked', CHECKED), ('lexical', '42\n41\n'), ('mixed', '77\n42\n41\n'), ('loans', ''), ('nested', ''), ('empty', '')]:
		inputs = [FIXTURES/(name+'.astra')]
		if name == 'checked': inputs += [ROOT/'lib/astra/base/errors.astra']
		run([compiler, '--dump-semantics', *inputs], contains='native-object-destroy-and-deallocate' if name in ('owned', 'checked', 'empty') else None)
		observer = 'lexical' if name in ('lexical', 'mixed') else 'observer'
		links = ['--link-object', objects[observer]] if name not in ('loans', 'nested', 'empty') else []
		executable = output/name
		run([compiler, *inputs, *links, '-o', executable], stdout='')
		run([executable], 42, trace+'pointers=0\n' if name in ('owned', 'checked') else trace)
		ir = run([compiler, '--dump-llvm', *inputs])
		ssa = run([compiler, '--dump-ssa', *inputs])
		ordinal = re.search(r'\(function #(\d+) "main" -> int', ssa)[1]
		ir += '\ndefine i32 @main(){\n %r=call fastcc i32 @astra.fn.'+ordinal+'()\n ret i32 %r\n}\n'
		if name == 'owned':
			# Observe the actual receiver at the generated probe entry, before O2.
			# This is a test-only C bridge; it never changes owner/storage operations.
			pattern = r'(define internal fastcc i32 @astra.class.method.0.0\(ptr %this, i32 %p0\) \{\n\w+:\n)'
			ir, count = re.subn(pattern, r'\1  call void @alloc_pointer(ptr %this, i32 %p0)\n', ir)
			assert count == 1
			ir += '\ndeclare void @alloc_pointer(ptr, i32)\n'
		if name == 'lexical':
			assert '@calloc' not in ir and '@free' not in ir and '%result.storage' in ir
		if name == 'mixed':
			assert '@calloc' in ir and '@free' in ir and '%result.storage' in ir
		llvm = output/(name+'.ll'); llvm.write_text(ir)
		optimized = output/(name+'-O2.ll')
		run(['opt', '-passes=default<O2>', '-S', llvm, '-o', optimized], stdout='')
		run(['opt', '-passes=verify', '-disable-output', optimized], stdout='')
		obj = output/(name+'-O2.o')
		run(['llc', '-O2', '-filetype=obj', '-relocation-model=pic', optimized, '-o', obj], stdout='')
		for mode in ('native', 'memory'):
			binary = output/(name+'-O2-'+mode)
			companions = [] if name in ('loans', 'nested', 'empty') else [objects['lexical' if name in ('lexical', 'mixed') else 'memory' if mode == 'memory' else 'observer']]
			run(['cc', obj, *companions, '-o', binary], stdout='')
			observed_trace = trace
			if mode == 'memory' and name in ('owned', 'checked'):
				observed_trace = re.sub(r'A |F\d+ ', '', trace)
			expected = observed_trace+('pointers=6\n' if name == 'owned' else 'pointers=0\n' if name == 'checked' else '')
			if mode == 'native': run([binary], 42, expected)
			else: run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', binary], 42, expected, memory=True)
	fatal = output/'fatal.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', FIXTURES/'fatal.c', '-o', fatal], stdout='')
	run([compiler, FIXTURES/'fatal.astra', '--link-object', fatal, '-o', output/'fatal'], stdout='')
	run([output/'fatal'], -signal.SIGILL, 'A')
	buffer = output/'buffer-release.astra'
	buffer.write_text('int main(){owned f64[] values=new f64[1];release values;return 42;}\n')
	run([compiler, '--dump-semantics', buffer], contains='native-buffer-deallocate')
	resource_fixtures = ROOT/'tests/resource/fixtures'
	run([compiler, '--dump-semantics', resource_fixtures/'resource-release.astra',
		'--vapi', resource_fixtures/'resource-types.vapi', '--vapi', resource_fixtures/'resource-api.vapi'],
		contains='(cleanup "astra_test_resource_destroy")')
	for name, body in [
		('other-owner-release', 'var first=new Label("x");var second=new Label("y");var view=first.text;release second;if(view!="x"){return 81;}'),
		('snapshot-release', 'var first=new Label("x");var snapshot=new Label(first.text);var view=snapshot.text;release first;if(view!="x"){return 81;}'),
	]:
		path = output/(name+'.astra'); path.write_text(LABEL+'int main(){'+body+'return 42;}\n')
		run([compiler, '--dump-core', path])
		run([compiler, path, '-o', output/name], stdout='')
		run([output/name], 42, '')
	for name, (header, body, message) in NEGATIVES.items():
		path = output/(name+'.astra'); path.write_text(header+'int main(){'+body+'return 42;}\n')
		for stage in ('semantics', 'core', 'ssa', 'llvm') if name.startswith('field-') or message == LOAN_ERROR else ('llvm',):
			run([compiler, '--dump-'+stage, path, ROOT/'lib/astra/base/errors.astra'], 1, '', message)
	print(f'PASS: seven native fixtures, seven independent O2 fixtures, seven unsuppressed Valgrind runs, fatal object OOM, {len(NEGATIVES)} negative forms.')


if __name__ == '__main__':
	main(sys.argv[1], sys.argv[2])
