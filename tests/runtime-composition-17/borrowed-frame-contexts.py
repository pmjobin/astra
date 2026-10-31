#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exercise actual frame leases selected through borrowed allocator parameters."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-borrowed-frame-contexts')
	here = Path(__file__).resolve().parent
	sources = [here / 'borrowed-frame-contexts.astra', ROOT / 'lib/astra/async/virtual.astra', ROOT / 'lib/astra/base/errors.astra']
	vapi = ROOT / 'lib/bindings/memory/contexts.vapi'
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/async/virtual.c', ROOT / 'lib/runtime/platform/text-posix.c']
	links = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
		links += [obj]
		e.files(obj)
	expected = 'borrowed frame contexts: 2 instances, 6 actual frames, joined error, suspended cancel, cold drops and 1 refusal\n'
	wrappers = ['-Wl,--wrap=astra_async_new_allocated', '-Wl,--wrap=astra_async_try_new_allocated', '-Wl,--wrap=astra_async_host_cancel']
	oracle = here / 'borrowed-frame-contexts-oracle.c'
	for profile in ['concurrent', 'affine', 'scoped']:
		variant = e.output / (profile + '.astra')
		text = sources[0].read_text()
		if profile == 'affine':
			text = text.replace('ConcurrentAllocator', 'AffineAllocator').replace('concurrent_allocator', 'affine_allocator')
		if profile == 'scoped':
			text = text.replace('ConcurrentAllocator', 'ScopedAllocator').replace('concurrent_allocator_query', 'scoped_allocator_query')
			text = text.replace('var first = concurrent_allocator(1, 8197, 1, 64);', 'owned u8[] first_backing=new u8[8197];owned u8[] second_backing=new u8[12289];var first=scoped_allocator<ScopedAllocator>(first_backing,1,1);')
			text = text.replace('var second = concurrent_allocator(2, 12289, 1, 64);', 'var second=scoped_allocator<ScopedAllocator>(second_backing,2,1);')

		variant.write_text(text)
		e.files(variant)
		oracle_object = e.output / ('oracle-' + profile + '.o')
		flags = ['-DM17_BORROWED_AFFINE'] if profile != 'concurrent' else []
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', *flags, '-c', oracle, '-o', oracle_object])
		e.files(oracle_object)
		for level in ['O0', 'O1', 'O2']:
			product = e.output / ('borrowed-frames-' + profile + '-' + level)
			obj = product.with_suffix('.o')
			e.run([e.compiler, '-' + level, '-c', variant, *sources[1:], '--vapi', vapi, '-o', obj])
			e.run(['cc', '-pthread', obj, *links, oracle_object, *wrappers, '-o', product])
			e.run([product], stdout=expected, timeout=15)
			e.files(obj, product)
		e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / ('borrowed-frames-' + profile + '-O2')], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=45)
	empty_error = here / 'scoped-frame-empty-error.astra'
	empty_expected = 'scoped empty error: refused admission and checked success retain exact backing ownership\n'
	for level in ['O0', 'O1', 'O2']:
		product = e.output / ('empty-error-' + level)
		obj = product.with_suffix('.o')
		e.run([e.compiler, '-' + level, '-c', empty_error, '--vapi', vapi, '-o', obj])
		e.run(['cc', '-pthread', obj, *links, e.output / 'oracle-scoped.o', *wrappers, '-o', product])
		e.run([product], stdout=empty_expected, timeout=15)
		e.files(obj, product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'empty-error-O2'], stdout=empty_expected, contains='ERROR SUMMARY: 0 errors', timeout=45)
	e.files(empty_error)
	for name, setup, argument, diagnostic in [
		('moved', 'var frames=concurrent_allocator(1,8197,7,64);var stolen=move frames;', 'frames', 'cannot borrow moved owned value'),
		('wrong-mode', 'var frames=affine_allocator(1,8197,7,64);', 'frames', "expects type 'ConcurrentAllocator'"),
	]:
		negative = e.output / (name + '.astra')
		declarations = sources[0].read_text().split('export(C) int run_borrowed_frame_contexts()')[0]
		negative.write_text(declarations + 'int main(){' + setup + 'return borrowed_frame_drop(' + argument + ',false);}')
		e.run([e.compiler, '-c', negative, *sources[1:], '--vapi', vapi, '-o', e.output / (name + '.o')], expected=1, contains=diagnostic)
		e.files(negative)
	for name, body, diagnostic in [
		('scoped-backing-release', 'async void child(){}int main(){owned u8[] backing=new u8[8197];var frames=scoped_allocator<ScopedAllocator>(backing,1,1);var task=task_in(frames,child());release backing;return 0;}', 'exclusively borrowed'),
		('scoped-worker', 'async void child(){}int main(){owned u8[] backing=new u8[8197];var frames=scoped_allocator<ScopedAllocator>(backing,1,1);var task=task_in(frames,child());return 0;}', 'selected worker frames require concurrent backing'),
	]:
		negative = e.output / (name + '.astra')
		negative.write_text(body)
		runtime = ROOT / ('lib/astra/async/threaded.astra' if name == 'scoped-worker' else 'lib/astra/async/virtual.astra')
		e.run([e.compiler, '-c', negative, runtime, sources[2], '--vapi', vapi, '-o', e.output / (name + '.o')], expected=1, contains=diagnostic)
		e.files(negative)
	e.files(*sources, vapi, *providers, oracle, Path(__file__), ROOT / 'tests/systems-dsp-9/support.py')
	for name in ['task-core17.c', 'task-api17.c', 'virtual.h', 'provider.h']:
		e.files(ROOT / 'lib/runtime/async' / name)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
