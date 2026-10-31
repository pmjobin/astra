#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual selected-context initialization failure and owning aggregate unwind."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-context-constructors')
	here = Path(__file__).resolve().parent
	sources = [here / 'context-constructors.astra']
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/platform/text-posix.c', here / 'context-provider.c', here / 'context-constructor-oracle.c']
	vapis = [ROOT / 'lib/bindings/memory/contexts.vapi', here / 'context-custom.vapi']
	e.files(*sources, *providers, *vapis, Path(__file__))
	imports = [argument for path in vapis for argument in ['--vapi', path]]
	links = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
		links += ['--link-object', obj]
		e.files(obj)
	expected = 'context constructors: twelve success/failure paths, exact input and initialized-prefix retirement\n'
	for level in ['O0', 'O1', 'O2']:
		product = e.output / ('constructors-' + level)
		e.run([e.compiler, '-' + level, *sources, *imports, *links, '--link-library', 'pthread', '-o', product])
		e.run([product], stdout=expected, timeout=15)
		e.files(product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'constructors-O2'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=45)
	for sanitizer in ['address', 'thread']:
		instrument(e, 'constructors', sources, providers, expected, sanitizer, vapis=vapis)
	root = '''[ExceptionRoot] class Failure {
	readonly string text; init(string text) { this.text = text; }
	virtual property string message { get { return this.text; } }
}
'''
	context = '[Allocator(kind="context",context="owned-concurrent")]'
	for name, source, diagnostic in [
		('missing-field', sources[0].read_text().replace('this.first = move first;', ''), 'not definitely initialized'),
		('legacy-static', root + '''class Item { init() throws Failure { throw new Failure("no context contract"); } }
int main() { return 0; }
''', 'throws requires'),
		('unhandled', root + context + '''class Item { init() throws Failure { throw new Failure("checked"); } }
int main() { var context = concurrent_allocator(1, 8197, 7, 64); var item = new (context) Item(); return 0; }
''', 'throws'),
		('consumed-input', root + '''class Leaf { int value; init(int value) { this.value = value; } }
''' + context + '''class Item { private owned Leaf leaf;
init(owned Leaf leaf) throws Failure { this.leaf = move leaf; throw new Failure("consumed"); } }
int main() { var context = concurrent_allocator(1, 8197, 7, 64); var leaf = new Leaf(17);
try { var item = new (context) Item(move leaf); } catch(Failure error) {}
return leaf.value; }
''', 'moved')]:
		negative = e.output / ('constructor-' + name + '.astra')
		negative.write_text(source)
		e.run([e.compiler, '-c', negative, *imports, '-o', negative.with_suffix('.o')],
			expected=1, contains=diagnostic)
		e.files(negative)
	e.files(*sources, *providers, *vapis, ROOT / 'lib/runtime/runtime/context-17.h', here / 'context-provider.h', Path(__file__))
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
