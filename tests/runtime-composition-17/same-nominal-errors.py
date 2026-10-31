#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Host observation preserves actual scoped error payload and empty outcomes."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, output, profile='local'):
	e = Evidence(compiler, output, 'runtime-composition-17-same-nominal-errors-' + profile)
	here = Path(__file__).resolve().parent
	original = here / 'same-nominal-errors.astra'
	text = original.read_text()
	if profile in ['await', 'await-catch', 'await-suspended']:
		observe = 'await move child;'
		if profile != 'await':
			suspend = 'await delay_ticks(1); ' if profile == 'await-suspended' else ''
			observe = 'try { await move child; } catch (HostErrorFault error) { ' + suspend + 'int expected = mode + 1; if (mode == 3) { expected = -1; } int value = error.read(); if (value != expected) { return; } throw; }'
		parent = 'async void await_error_parent(owned HostErrorLeaf input, int mode) throws HostErrorFault { var child = host_error_fail(move input, mode); ' + observe + ' }\n'
		text = text.replace('int host_error_forward(', parent + 'int host_error_forward(')
		text = text.replace('var task = host_error_fail(move input, mode);', 'var task = await_error_parent(move input, mode);')
	elif profile == 'forwarded':
		start = text.index('\t\tvar executor = HostErrorTasks.open(8);')
		end = text.index('\n\t} catch(HostErrorFault unexpected)', start)
		text = text[:start] + '\t\ttry { int result = host_error_forward(move input, mode); if (result != 0) { return result; } } catch(HostErrorFault error) { host_error_outcome(mode, error.read()); }' + text[end:]
	elif profile == 'borrowed':
		text = text.replace('int host_error_case(int mode) {\n\towned u8[] backing = new u8[16381];\n\tvar objects = scoped_allocator<ScopedAllocator>(backing, 1, 8);\n', 'int host_error_case(borrowed ScopedAllocator objects, int mode) {\n')
		text = text.replace('export(C) int host_error_probe() {\n', 'export(C) int host_error_probe() {\n\towned u8[] backing = new u8[16381];\n\tvar objects = scoped_allocator<ScopedAllocator>(backing, 1, 8);\n')
		text = text.replace('host_error_case(mode)', 'host_error_case(objects, mode)')
	else:
		assert profile == 'local'
	source = e.output / (profile + '.astra')
	source.write_text(text)
	sources = [source]
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/async/virtual.c', ROOT / 'lib/runtime/platform/text-posix.c', here / 'host-scoped-errors-oracle.c']
	vapi = ROOT / 'lib/bindings/memory/contexts.vapi'
	link_flags = ['-Wl,--wrap=astra_async_run', '-Wl,--wrap=astra_async_delay']
	expected = 'host scoped errors: original and suspended payloads, empty errors, cancellation and success retire exactly once\n'
	for level in ['O0', 'O1', 'O2']:
		obj = e.output / ('choices-' + level + '.o')
		product = obj.with_suffix('')
		e.run([e.compiler, '-' + level, '-c', *sources, '--vapi', vapi, '-o', obj])
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', *link_flags, obj, *providers, '-o', product])
		e.run([product], stdout=expected)
		e.files(obj, product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', product], stdout=expected, contains='ERROR SUMMARY: 0 errors')
	instrument(e, 'choices', sources, providers, expected, 'address', link_flags=link_flags, vapis=[vapi], entry_symbol='host_error_probe')
	text = sources[0].read_text()
	for name, changed, diagnostic in [
		('moved-error', text.replace('host_error_outcome(mode, error.read());', 'var duplicate = move error; host_error_outcome(mode, error.read());'), 'moved'),
		('retired-backing', text.replace('for (int mode = 0;', 'release backing; for (int mode = 0;') if profile == 'borrowed' else text.replace('host_error_begin(mode);', 'release backing; host_error_begin(mode);'), 'exclusively borrowed'),
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
