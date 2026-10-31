# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Source-bound native/O2/memory and explicit negative owning-child witnesses."""
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
TRACES = {
	'children': ('I1 I2 P1 P1 P2 P1 P2 I3 I4 P3 P4 E90 D0 D0 P3 P4 P3 P4 E100 E90 D0 D0 I5 I6 P5 P6 E90 D0 D0 I7 I8 P7 P8 E90 D0 D0 ', 15),
	'replacement': ('I1 P1 I2 D0 P2 I3 D0 P3 I4 D0 P4 D0 I5 P5 E90 I9 D0 D0 I10 D0 ', 5),
	'checked': ('I1 I2 D0 E20 I3 D0 P1 I4 D0 P4 E90 D0 I5 I2 D0 E20 I6 P5 P6 D0 E90 D0 ', 4),
	'async-boundary': ('I1 P1 P1 E90 D0 I2 P2 E90 D0 ', 3),
	'lifecycle': ('I1 I2 I3 P1 P2 P3 E100 D0 D0 E90 D0 ', 3),
	'async-replacement': ('I1 I2 D0 P2 E90 D0 ', 1),
}
DEATHS = {'children': '2,1,4,3,6,5,8,7,', 'replacement': '1,2,3,4,5,9,10,', 'checked': '2,3,1,4,2,6,5,', 'async-boundary': '1,2,', 'lifecycle': '3,2,1,', 'async-replacement': '1,2,'}
CHILD = 'class Child{int value;init(){this.value=42;}}'
FACTORY = 'owned Child make(){var child=new Child();return move child;}'
HOLDER = 'class Holder{owned Child child;init(owned Child child){this.child=move child;}void replace(owned Child incoming){this.child=move incoming;}}'
HEADER = CHILD + FACTORY + HOLDER
BORROW = 'owned child field use requires a temporary borrowed argument or null comparison'
TRANSFER = 'owned child field transfer requires an explicit move or direct owned result of the exact heap ClassType'
OVERLAP = 'temporary owned-field borrow overlaps'
TEXT_CHILD = 'class Label{readonly string text;init(string text){this.text=text;}}'
TEXT_HOLDER = 'class TextHolder{owned Label child;init(owned Label c){this.child=move c;}}'
LOAN_ERROR = 'cannot invalidate a receiver while a stored text loan remains in its lexical extent'
NEGATIVES = {
	'missing': (CHILD+'class Holder{owned Child child;init(){}}', 'not definitely initialized'),
	'no-init': (CHILD+'class Holder{owned Child child;}', 'requires an explicit constructor'),
	'uninitialized-read': (CHILD+FACTORY+'int read(Child c){return c.value;}class Holder{owned Child child;init(){read(this.child);this.child=make();}}', 'read before definite initialization'),
	'branch-hole': (CHILD+FACTORY+'class Holder{owned Child child;init(bool b){if(b){this.child=make();}}}', 'not definitely initialized'),
	'twice': (CHILD+FACTORY+'class Holder{owned Child child;init(){this.child=make();this.child=make();}}', 'initialized twice'),
	'loop-init': (CHILD+FACTORY+'class Holder{owned Child child;init(){while(true){this.child=make();break;}}}', 'initialization inside a loop'),
	'lexical-move': (CHILD+'class Holder{owned Child child;init(){owned Child local=Child.init();this.child=move local;}}', TRANSFER),
	'lexical-factory': (CHILD+'owned Child make(){return Child.init();}class Holder{owned Child child;init(){this.child=make();}}', 'owned Class result joins incompatible heap and caller-backed storage origins'),
	'raw-null': (CHILD+'class Holder{owned Child child;init(){this.child=null;}}', TRANSFER),
	'wrong-class': (HEADER+'class Other{init(){}}void f(Holder h){var child=new Other();h.child=move child;}', TRANSFER),
	'owner-copy': (HEADER+'void f(Holder h){var child=new Child();h.child=child;}', 'persistent alias from owned ClassType'),
	'duplicate-owner': (HEADER+'void f(Holder a,Holder b){var child=new Child();a.child=move child;b.child=move child;}', 'moved'),
	'source-reuse': (HEADER+'void f(Holder h){var child=new Child();h.child=move child;int n=child.value;}', 'moved'),
	'parent-reuse': (HEADER+'void f(){var child=new Child();var h=new Holder(move child);var other=move h;h.child=make();}', 'moved'),
	'double-release': (HEADER+'void f(){var child=new Child();var h=new Holder(move child);release h;release h;}', 'has already been released'),
	'parent-copy': (HEADER+'void f(){var child=new Child();var h=new Holder(move child);Holder alias=h;}', 'persistent alias from owned ClassType'),
	'field-copy': (HEADER+'void f(Holder h){Child view=h.child;}', BORROW),
	'retained-destruction': (HEADER+'void f(){var c=new Child();var h=new Holder(move c);var view=h.child;release h;}', BORROW),
	'retained-replacement': (HEADER+'void f(Holder h){var view=h.child;h.child=make();}', BORROW),
	'child-text-view': (TEXT_CHILD+TEXT_HOLDER+'void f(TextHolder h){var view=h.child.text;}', 'nested field base requires an exact StructType Place'),
	'incoming-text-loan': (TEXT_CHILD+'class H{owned Label child;init(){var c=new Label("x");var view=c.text;this.child=move c;}}', LOAN_ERROR),
	'producer-text-loan': (TEXT_CHILD+'owned Label pass(owned Label c){return move c;}class H{owned Label child;init(){var c=new Label("x");var view=c.text;this.child=pass(move c);}}', LOAN_ERROR),
	'field-extraction': (HEADER+'void f(Holder h){var extracted=move h.child;}', 'moving ownership out of an owned field'),
	'field-release': (HEADER+'void f(Holder h){release h.child;}', 'explicit release of an owned field'),
	'field-to-field': (HEADER+'void f(Holder a,Holder b){a.child=move b.child;}', 'moving ownership out of an owned field'),
	'borrow-return': (HEADER+'Child leak(Holder h){return h.child;}', 'object-reference results are unsupported'),
	'borrow-move': (HEADER+'void consume(owned Holder h){}void use(Child c,owned Holder h){}void f(){var c=new Child();var h=new Holder(move c);use(h.child,move h);}', OVERLAP),
	'borrow-replace': (HEADER+'int change(Holder h){h.child=make();return 0;}void use(Child c,int n){}void f(Holder h){use(h.child,change(h));}', OVERLAP),
	'borrow-container': (HEADER+'void use(Child c,Holder h){}void f(Holder h){use(h.child,h);}', OVERLAP),
	'replacement-consumes-parent': (HEADER+'owned Child steal(owned Holder h){return make();}void f(){var c=new Child();var h=new Holder(move c);h.child=steal(move h);}', OVERLAP),
	'borrow-ancestor': (HEADER+'class Grand{owned Holder h;init(owned Holder h){this.h=move h;}}void use(Child c,Grand g){}void f(Holder h,Grand g){use(h.child,g);}', OVERLAP),
	'borrow-base': (HEADER+'class Derived:Holder{init(owned Child c):base(move c){}}void use(Child c,Holder h){}void f(Derived h){use(h.child,h);}', OVERLAP),
	'borrow-derived': (HEADER+'class Derived:Holder{init(owned Child c):base(move c){}}void use(Child c,Derived h){}void f(Holder h,Derived d){use(h.child,d);}', OVERLAP),
	'self-cycle': ('class C{owned C child;init(){}}', 'cyclic owned child composition'),
	'mutual-cycle': ('class A{owned B child;init(){}}class B{owned A child;init(){}}', 'cyclic owned child composition'),
	'polymorphic-child': ('class Base{init(){}}class Derived:Base{init():base(){}}class H{owned Base child;init(){}}', 'nonpolymorphic'),
	'plain-child': (CHILD+'class H{Child child;}', 'object-reference fields are unsupported'),
	# Surge 10 accepted owning records. Keep the ownership refusal on an
	# actual borrowed input, rather than prohibiting that accepted family.
	'owned-struct-borrow': (CHILD+'struct H{owned Child child;}void bad(borrowed Child value){H h={child=value};}', 'record Class replacement requires an exact heap owner move or owned factory result'),
	'generic-field': ('struct H<T>{owned T child;}', 'owned struct fields are unsupported'),
	'constructor-throws': (CHILD+'class H{owned Child child;init() throws Error{}}', 'throws requires a concrete native function, class method or bounded Singleton initializer'),
}


def main(compiler, output):
	compiler, output = Path(compiler).resolve(), Path(output).resolve()
	assert not output.is_relative_to(ROOT), "generated tests must stay outside the source tree"
	output.mkdir(parents=True, exist_ok=True)
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	rows = []

	def run(command, expected=0, stdout=None, diagnostic=None, memory=False):
		p = subprocess.run(list(map(str, command)), cwd=ROOT, capture_output=True,
			text=True, timeout=90, env=dict(os.environ, CCACHE_DISABLE='1'))
		valid = p.returncode == expected and (stdout is None or p.stdout == stdout)
		if memory:
			valid &= ('ERROR SUMMARY: 0 errors' in p.stderr and 'in use at exit: 0 bytes in 0 blocks' in p.stderr
				and '(suppressed: 0 from 0)' in p.stderr)
		elif diagnostic:
			valid &= diagnostic in p.stderr and not p.stdout
		else:
			valid &= not p.stderr
		rows.append(dict(command=list(map(str, command)), expected_exit=expected, actual_exit=p.returncode, stdout=p.stdout,
			stderr=p.stderr, status='PASS' if valid else 'FAIL'))
		(output/'checks.json').write_text(json.dumps(rows, indent=2)+'\n')
		assert valid, rows[-1]
		return p.stdout

	observer = output/'observer.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', HERE/'observer.c', '-o', observer], stdout='')
	for name, (trace, probes) in TRACES.items():
		inputs = [HERE/(name+'.astra')]
		if name == 'checked' or name.startswith('async-'):
			inputs += [ROOT/'lib/astra/base/errors.astra']
		links = [observer]
		if name.startswith('async-'):
			inputs += [ROOT/'lib/astra/async/virtual.astra']
			links += [compiler.parent/'lib/astra/async-virtual.o']
		link_args = [arg for obj in links for arg in ['--link-object', obj]]
		for stage in ['semantics', 'core', 'cfg', 'nabi']:
			run([compiler, '--dump-'+stage, *inputs])
		native = output/name
		run([compiler, *inputs, *link_args, '-o', native], stdout='')
		run([native], 42, trace+'probes=0 deaths=\n')
		ir = run([compiler, '--dump-llvm', *inputs])
		ssa = run([compiler, '--dump-ssa', *inputs])
		ordinal = re.search(r'\(function #(\d+) "main" -> int', ssa)[1]
		child_ordinal = re.search(r'\(class #(\d+) "Child"', ssa)[1]
		ir += '\ndefine i32 @main(){\n %r=call fastcc i32 @astra.fn.'+ordinal+'()\n ret i32 %r\n}\n'
		# Resolve the exact Child identity after deterministic source-set ordering.
		for pattern, bridge in [
			(r'(define internal fastcc void @astra.ctor.0\(ptr %this, i32 %p0\) \{\n\w+:\n)', 'call void @field_born(ptr %this, i32 %p0)'),
			(r'(define internal fastcc i32 @astra.class.method.0.0\(ptr %this, i32 %p0\) \{\n\w+:\n)', 'call void @field_probe(ptr %this, i32 %p0)'),
			(r'(define internal fastcc void @astra.dtor.0\(ptr %this\) \{\n\w+:\n)', 'call void @field_dying(ptr %this)'),
		]:
			pattern = pattern.replace('ctor.0', 'ctor.'+child_ordinal).replace('method.0.0', 'method.'+child_ordinal+'.0').replace('dtor.0', 'dtor.'+child_ordinal)
			ir, matches = re.subn(pattern, lambda m: m[1]+'  '+bridge+'\n', ir)
			assert matches == 1, (name, pattern, matches)
		ir += '\ndeclare void @field_born(ptr, i32)\ndeclare void @field_probe(ptr, i32)\ndeclare void @field_dying(ptr)\n'
		llvm, optimized, obj = output/(name+'.ll'), output/(name+'-O2.ll'), output/(name+'-O2.o')
		llvm.write_text(ir)
		run(['opt', '-passes=default<O2>', '-S', llvm, '-o', optimized], stdout='')
		run(['opt', '-passes=verify', '-disable-output', optimized], stdout='')
		run(['llc', '-O2', '-filetype=obj', '-relocation-model=pic', optimized, '-o', obj], stdout='')
		binary = output/(name+'-O2')
		run(['cc', obj, *links, '-o', binary], stdout='')
		run([binary], 42, trace+f'probes={probes} deaths={DEATHS[name]}\n')
		if shutil.which('valgrind'):
			run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full',
				'--show-leak-kinds=all', '--errors-for-leak-kinds=all', binary], 42,
				trace+f'probes={probes} deaths={DEATHS[name]}\n', memory=True)
		else:
			print('Valgrind unavailable: memory run NOT TESTED')
	for stage in ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']:
		run([compiler, '--dump-'+stage, HERE/'declarations.astra'])
	declaration = output/'declarations'
	run([compiler, HERE/'declarations.astra', '-o', declaration], stdout='')
	run([declaration], 42, '')
	# The former declaration-only owned-struct negative is now positively
	# exercised, including nested ownership transport and explicit extraction.
	owned_record = output/'owned-record-current.astra'
	owned_record.write_text(CHILD+'struct H{owned Child child;}int main(){var original=new Child();H h={child=move original};var next=move h;var child=move next.child;if(child.value!=42){return 81;}release child;return 42;}\n')
	for stage in ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']:
		run([compiler, '--dump-'+stage, owned_record])
	for level in [0, 1, 2]:
		binary = output/f'owned-record-current-O{level}'
		run([compiler, f'-O{level}', owned_record, '-o', binary], stdout='')
		run([binary], 42, '')
	if shutil.which('valgrind'):
		run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full',
			'--show-leak-kinds=all', '--errors-for-leak-kinds=all', binary], 42, '', memory=True)
	for name, (source, message) in NEGATIVES.items():
		path = output/(name+'.astra')
		path.write_text(source+'int main(){return 42;}\n')
		# Class move/release state is proved by the established CFG ownership
		# flow, after semantic/Core construction. Other source rules reject early.
		stages = ['cfg', 'ssa', 'llvm'] if name in {'duplicate-owner', 'source-reuse', 'parent-reuse', 'double-release'} else ['semantics', 'core', 'cfg', 'ssa', 'llvm']
		for stage in stages:
			run([compiler, '--dump-'+stage, path, *([ROOT/'lib/astra/base/errors.astra'] if name == 'constructor-throws' else [])], 1, diagnostic=message)
	print(f'{len(rows)} command checks passed ({len(NEGATIVES)} negative source forms)')


if __name__ == '__main__':
	main(*sys.argv[1:])
