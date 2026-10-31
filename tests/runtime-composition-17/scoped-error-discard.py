#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual scoped error payload disposal after cold creation, publication and cancellation."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, output, profile='single'):
	e = Evidence(compiler, output, 'runtime-composition-17-scoped-error-discard-' + profile)
	here = Path(__file__).resolve().parent
	original = here / 'scoped-error-discard.astra'
	text = original.read_text()
	link_flags = []
	suspended = profile.startswith('suspended-')
	layout_profile = profile.removeprefix('suspended-')
	if layout_profile == 'pair':
		text = text.replace('private owned ScopedErrorLeaf child;', 'private owned ScopedErrorLeaf child; private owned ScopedErrorLeaf second;')
		text = text.replace('init(owned ScopedErrorLeaf child) { this.child = move child; }', 'init(owned ScopedErrorLeaf child, owned ScopedErrorLeaf second) { this.child = move child; this.second = move second; }')
		text = text.replace('base(null)', 'base(null, null)')
		text = text.replace('scoped_error_fail(owned ScopedErrorLeaf input)', 'scoped_error_fail(owned ScopedErrorLeaf input, owned ScopedErrorLeaf other)')
		text = text.replace('new ScopedFault(move input)', 'new ScopedFault(move input, move other)')
		text = text.replace('scoped_error_dispose(owned ScopedErrorLeaf input, int mode)', 'scoped_error_dispose(owned ScopedErrorLeaf input, owned ScopedErrorLeaf other, int mode)')
		text = text.replace('scoped_error_fail(move input)', 'scoped_error_fail(move input, move other)')
		text = text.replace('scoped_error_case(borrowed ScopedAllocator context, int mode)', 'scoped_error_case(borrowed ScopedAllocator context, borrowed ScopedAllocator second, int mode)')
		text = text.replace('var input = new(context) ScopedErrorLeaf(mode + 1);', 'var input = new(context) ScopedErrorLeaf(mode * 2 + 1); var other = new(second) ScopedErrorLeaf(mode * 2 + 2);')
		text = text.replace('scoped_error_dispose(move input, mode)', 'scoped_error_dispose(move input, move other, mode)')
		text = text.replace('scoped_allocator_query(context, 1) != 0', 'scoped_allocator_query(context, 1) != 0 || scoped_allocator_query(second, 1) != 0')
		text = text.replace('scoped_error_checked(mode + 1,', 'scoped_error_checked(mode * 2 + 1,')
		text = text.replace('var context = scoped_allocator<ScopedAllocator>(backing, 1, 4);', 'var context = scoped_allocator<ScopedAllocator>(backing, 1, 4); owned u8[] second_backing = new u8[16381]; var second = scoped_allocator<ScopedAllocator>(second_backing, 2, 4);')
		text = text.replace('scoped_error_case(context, mode)', 'scoped_error_case(context, second, mode)')
		link_flags = ['-DSCOPED_ERROR_WIDTH=2']
	else:
		assert layout_profile == 'single'
	if suspended:
		text = text.replace('extern(C) int scoped_error_is_published();', 'extern(C) int scoped_error_is_published(); extern(C) void scoped_error_delay_arm(int mode);')
		start = text.index('async void scoped_error_fail(')
		end = text.index(')', start)
		text = text[:end] + ', int mode' + text[end:]
		text = text.replace('var child = scoped_error_fail(move input' + (', move other' if layout_profile == 'pair' else '') + ');', 'var child = scoped_error_fail(move input' + (', move other' if layout_profile == 'pair' else '') + ', mode);')
		text = text.replace('int identity = input.read();', 'scoped_error_delay_arm(mode); await delay_ticks(1); int identity = input.read();')
		text = text.replace('mode < 3;', 'mode < 4;')
		link_flags += ['-DSCOPED_ERROR_SUSPENDED=1', '-Wl,--wrap=astra_async_delay']
	source = e.output / (profile + '.astra')
	source.write_text(text)
	sources = [source]
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/async/virtual.c', ROOT / 'lib/runtime/platform/text-posix.c', here / 'scoped-error-discard-oracle.c']
	vapi = ROOT / 'lib/bindings/memory/contexts.vapi'
	expected = 'scoped error discard: cold, published and cancelled owners retire exactly once\n'
	for level in ['O0', 'O1', 'O2']:
		obj = e.output / ('discard-' + level + '.o')
		product = obj.with_suffix('')
		e.run([e.compiler, '-' + level, '-c', *sources, '--vapi', vapi, '-o', obj])
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', *link_flags, obj, *providers, '-o', product])
		e.run([product], stdout=expected)
		e.files(obj, product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', product], stdout=expected, contains='ERROR SUMMARY: 0 errors')
	instrument(e, 'discard', sources, providers, expected, 'address', link_flags=link_flags, vapis=[vapi], entry_symbol='scoped_error_probe')
	text = sources[0].read_text()
	for name, changed, diagnostic in [
		('retired-backing', text.replace('for (int mode = 0;', 'release backing; for (int mode = 0;'), 'exclusively borrowed'),
		('unjoined-start', text.replace('await cancel_and_join(move child);', ''), 'unjoined'),
		('moved-root', text.replace('var status = executor.run(move pending);', 'var status = executor.run(move pending); var duplicate = executor.run(move pending);'), 'moved'),
	]:
		assert changed != text
		negative = e.output / (name + '.astra')
		negative.write_text(changed)
		e.run([e.compiler, '--check', negative, '--vapi', vapi], expected=1, contains=diagnostic)
		e.files(negative)
	e.files(original, Path(__file__), vapi, *sources, *providers, ROOT / 'tests/systems-dsp-9/support.py', ROOT / 'tests/concurrency-runtime-13/sanitizers.py', ROOT / 'lib/runtime/runtime/context-17.h')
	for name in ['virtual.h', 'provider.h', 'task-core17.c', 'task-api17.c']:
		e.files(ROOT / 'lib/runtime/async' / name)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
