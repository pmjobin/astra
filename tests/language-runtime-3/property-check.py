# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Public native ownership-property qualification with independent C traces."""
import hashlib
import json
import os
from pathlib import Path
import resource
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
CHILD = 'class Child{int value;init(){this.value=42;}}'
HOLDER = ('class Holder{private owned Child child;init(owned Child child){this.child=move child;}'
	'property borrowed Child view{get{return this.child;}set(owned Child incoming){this.child=move incoming;}}}')
CREATE = 'var child=new Child();var holder=new Holder(move child);'
NEGATIVES = {
	'stored-borrow': (CHILD+HOLDER, CREATE+'var view=holder.view;', 'borrowed property result requires'),
	'owner-copy': (CHILD+HOLDER, CREATE+'owned Child view=holder.view;', 'owned ClassType local requires'),
	'private-field': (CHILD+HOLDER+'int inspect(Child c){return c.value;}', CREATE+'return inspect(holder.child);', 'private field'),
	'borrow-consume': (CHILD+HOLDER+'int overlap(Child view,owned Holder owner){return view.value;}', CREATE+'return overlap(holder.view,move holder);', 'temporary owned-field borrow overlaps'),
	'borrow-mutate': (CHILD+HOLDER+'int mutate(Holder h){var child=new Child();h.view=move child;return 0;}int inspect(Child child,int other){return child.value;}', CREATE+'return inspect(holder.view,mutate(holder));', 'temporary owned-field borrow overlaps'),
	'generic-borrow': (CHILD+HOLDER+'int inspect<T>(borrowed T value)where T:Ownable{return 0;}', CREATE+'return inspect<Child>(holder.view);', 'generic borrowed argument requires'),
	'direct-producer': (CHILD+HOLDER+'owned Child make(){var child=new Child();return move child;}', CREATE+'holder.view=make();', 'requires explicit'),
	'lexical-replacement': (CHILD+HOLDER, CREATE+'owned Child child2=Child.init();holder.view=move child2;', 'heap and lexical storage origins'),
	'wrong-property-kind': ('class Bad{int value;property borrowed int view{get{return this.value;}}}', '', 'borrowed property requires'),
	'wrong-getter': (CHILD+'class Bad{property borrowed Child view{get{return Child.init();}}}', '', 'borrowed property getter requires'),
	'plain-class-property': (CHILD+'class Bad{property Child view{get{return null;}}}', '', 'unsupported property value type'),
	'borrowed-setter-input': (CHILD+'class Bad{owned Child child;init(owned Child child){this.child=move child;}property borrowed Child view{get{return this.child;}set(Child incoming){this.child=move incoming;}}}', '', 'requires an explicit owned setter parameter'),
	'borrowed-result': (CHILD+HOLDER+'Child leak(Holder holder){return holder.view;}', '', 'object-reference results are unsupported'),
}
TRACES = {
	'class': '1:10\n4:1\n1:30\n2:30\n4:2\n1:40\n2:10\n2:40\n1:50\n3:2\n2:50\n',
	'resource': '1:10\n4:1\n1:30\n2:30\n4:2\n1:40\n2:10\n2:40\n1:50\n3:0\n2:50\n',
}


def main(compiler, output):
	compiler, output = Path(compiler).resolve(), Path(output).resolve()
	assert not output.is_relative_to(ROOT), 'generated outputs must remain outside source'
	output.mkdir(parents=True, exist_ok=True)
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	rows, products = [], {}

	def run(command, stdout=None, diagnostic=None, memory=False):
		command = list(map(str, command))
		result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120,
			env=dict(os.environ, CCACHE_DISABLE='1'))
		valid = result.returncode != 0 if diagnostic else result.returncode == 0
		valid &= stdout is None or result.stdout == stdout
		if diagnostic:
			valid &= diagnostic in result.stderr and 'internal error' not in result.stderr.lower()
		elif memory:
			valid &= ('ERROR SUMMARY: 0 errors' in result.stderr
				and 'in use at exit: 0 bytes in 0 blocks' in result.stderr
				and '(suppressed: 0 from 0)' in result.stderr)
		else:
			valid &= not result.stderr
		rows.append(dict(command=command, exit=result.returncode, stdout=result.stdout,
			stderr=result.stderr, status='PASS' if valid else 'FAIL'))
		(output/'checks.json').write_text(json.dumps(rows, indent=2)+'\n')
		assert valid, rows[-1]
		return result.stdout

	observer = output/'property-observer.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', HERE/'property-observer.c', '-o', observer], stdout='')
	for name, trace in TRACES.items():
		sources = [HERE/('property-'+name+'.astra'), ROOT/'lib/astra/base/errors.astra']
		foreign = ['--vapi', HERE/'property-resource.vapi'] if name == 'resource' else []
		for stage in ('syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm'):
			text = run([compiler, '--dump-'+stage, *sources, *(foreign if stage != 'syntax' else [])])
			(output/(name+'.'+stage)).write_text(text)
		for mode in ('O0', 'O1', 'O2'):
			binary = output/(name+'-'+mode)
			run([compiler, '-'+mode, *sources, *foreign, '--link-object', observer, '-o', binary], stdout='')
			run([binary], stdout=trace)
			products[binary.name] = hashlib.sha256(binary.read_bytes()).hexdigest()
		if shutil.which('valgrind'):
			run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full',
				'--show-leak-kinds=all', '--errors-for-leak-kinds=all', output/(name+'-O2')], stdout=trace, memory=True)
	for name, (declarations, body, diagnostic) in NEGATIVES.items():
		source = output/('negative-'+name+'.astra')
		source.write_text(declarations+'int main(){'+body+'return 0;}\n')
		run([compiler, '--check', source], diagnostic=diagnostic)
	(output/'products.json').write_text(json.dumps(products, indent=2)+'\n')
	print(f'PASS borrowed owner properties: {len(rows)} checks; {len(products)} public products; memory={bool(shutil.which("valgrind"))}')


if __name__ == '__main__':
	main(*sys.argv[1:])
