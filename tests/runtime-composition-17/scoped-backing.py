#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Qualify the exclusive scoped controller; derived-owner lifetimes are separate."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-scoped-backing')
	here = Path(__file__).resolve().parent
	source = here / 'scoped-backing.astra'
	vapis = [ROOT / 'lib/bindings/memory/contexts.vapi', here / 'scoped-backing.vapi']
	imports = [arg for path in vapis for arg in ['--vapi', path]]
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', here / 'scoped-backing-oracle.c']
	wrappers = ['-Wl,--wrap=' + name for name in ['astra_context17_open_scoped', 'astra_context17_destroy', 'astra_context17_release_origin_checked', 'free']]
	expected = 'scoped backing: exact caller buffers, exclusive lexical loans, original storage and ordered retirement\n'
	e.files(source, *vapis, *providers, ROOT / 'lib/runtime/runtime/context-17.h', Path(__file__), ROOT / 'tests/concurrency-runtime-13/sanitizers.py')
	ssa = e.run([e.compiler, '--dump-ssa', source, *imports]).stdout
	assert 'scoped-allocator backing=' in ssa and 'scoped-backing/1:' in ssa
	for level in ['0', '1', '2']:
		obj, product = [e.output / ('scoped-O' + level + suffix) for suffix in ['.o', '']]
		e.run([e.compiler, '-O' + level, '-c', source, *imports, '-o', obj])
		e.run(['cc', '-O2', '-g', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', obj, *providers, *wrappers, '-o', product])
		e.run([product], stdout=expected); e.files(obj, product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'scoped-O2'], stdout=expected, contains='ERROR SUMMARY: 0 errors')
	for sanitizer in ['address', 'thread']:
		instrument(e, 'scoped', [source], providers, expected, sanitizer, link_flags=wrappers, vapis=vapis, entry_symbol='scoped_backing_run')
	text = source.read_text()
	point = '\t\t\tif (region == null || pool == null)'
	negatives = {
		'read-backing': ('int count = len(first);', 'exclusively borrowed'),
		'write-backing': ('first[0] = 9;', 'exclusively borrowed'),
		'move-backing': ('owned u8[] moved = move first;', 'exclusively borrowed'),
		'release-backing': ('release first;', 'exclusively borrowed'),
		'replace-backing': ('first = new u8[21];', 'exclusively borrowed'),
		'competing-context': ('var duplicate = scoped_allocator<ScopedAllocator>(first, 1, 3);', 'exclusively borrowed'),
		'move-context': ('var moved = move region;', 'cannot escape or transfer its backing loan'),
		'release-context': ('release region;', 'scoped context'),
		'rearm-context': ('region = null;', 'scoped context'),
		'alias-context': ('ScopedAllocator alias = region;', 'direct lexical scoped_allocator binding'),
		'null-controller': ('owned ScopedAllocator forged = null;', 'direct lexical scoped_allocator binding'),
	}
	for name, (statement, diagnostic) in negatives.items():
		negative = e.output / (name + '.astra'); negative.write_text(text.replace(point, '\t\t\t' + statement + '\n' + point))
		e.run([e.compiler, '-c', negative, *imports, '-o', e.output / 'negative.o'], expected=1, contains=diagnostic); e.files(negative)
	for name, declaration, diagnostic in [
		('owned-parameter', 'void consume(owned ScopedAllocator context) {}', 'synchronous nonescaping borrow'),
		('owned-result', 'owned ScopedAllocator escape() { return null; }', 'through a result'),
		('field-context', 'class Escape { owned ScopedAllocator context; init(owned ScopedAllocator input) { this.context = move input; } }', 'cannot be stored in a field'),
		('borrowed-backing', 'void borrow(borrowed u8[] backing) { var context = scoped_allocator<ScopedAllocator>(backing, 1, 3); }', 'named complete owned u8 buffer'),
		('kind-consumes-backing', 'int consume_backing(owned u8[] backing) { return 1; }', 'reserved throughout context argument evaluation'),
	]:
		negative = e.output / (name + '.astra')
		contents = declaration + '\n' + text
		if name == 'kind-consumes-backing':
			contents = contents.replace('(first, 1, 7)', '(first, consume_backing(move first), 7)')
		negative.write_text(contents)
		e.run([e.compiler, '-c', negative, *imports, '-o', e.output / 'negative.o'], expected=1, contains=diagnostic); e.files(negative)
	negative = e.output / 'refusal-keeps-loan.astra'
	negative.write_text(text.replace('if (refused != null)', 'int count = len(empty); if (refused != null)'))
	e.run([e.compiler, '-c', negative, *imports, '-o', e.output / 'negative.o'], expected=1, contains='exclusively borrowed'); e.files(negative)
	bad_vapi = e.output / 'forged-factory.vapi'
	bad_vapi.write_text('[CCode(cname="forged_scoped_factory")] owned ScopedAllocator forged();\n')
	e.run([e.compiler, '-c', source, *imports, '--vapi', bad_vapi, '-o', e.output / 'negative.o'], expected=1, contains='lexical scoped_allocator intrinsic'); e.files(bad_vapi)
	loops = e.output / 'lexical-loops.astra'
	loops.write_text('''int early(int mode) {
	owned u8[] backing = new u8[4097];
	var context = scoped_allocator<ScopedAllocator>(backing, 1, 3);
	if (context == null) { return 1; }
	if (mode == 0) { return 0; }
	return 0;
}
int main() {
	owned u8[] backing = new u8[4097]; int index = 0;
	while (index < 7) {
		{ var context = scoped_allocator<ScopedAllocator>(backing, 1 + index % 2, 3); if (context == null || scoped_allocator_query(context, 7) != 1) { return 1; } }
		backing[0] = index as u8; index = index + 1;
	}
	if (backing[0] != 6 || early(0) != 0 || early(1) != 0) { return 2; }
	return 0;
}
''')
	runtime_object = e.output / 'context-17.o'
	e.run(['cc', '-O2', '-g', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', providers[0], '-o', runtime_object])
	for level in ['0', '2']:
		product = e.output / ('loops-O' + level)
		e.run([e.compiler, '-O' + level, loops, '--vapi', vapis[0], '--link-object', runtime_object, '--link-library', 'pthread', '-o', product])
		e.run([product], stdout=''); e.files(product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'loops-O2'], stdout='', contains='ERROR SUMMARY: 0 errors')
	e.files(loops, runtime_object); e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
