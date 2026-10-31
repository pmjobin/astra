#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual foreign completion wake, affine home destruction and joined observation."""
from pathlib import Path
import resource
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, prefix, output):
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	e = Evidence(compiler, output, 'runtime-composition-17-affine-home-retirement')
	prefix = Path(prefix).resolve()
	here = Path(__file__).resolve().parent
	sources = [here / name for name in ['affine-home-common.astra', 'affine-home-worker.astra', 'affine-home-retirement.astra']]
	sources += [ROOT / 'lib/astra/base/errors.astra']
	vapis = [ROOT / 'lib/bindings/memory/contexts.vapi', ROOT / 'lib/bindings/async/composition.vapi']
	imports = [arg for path in vapis for arg in ['--vapi', path]]
	providers = [ROOT / name for name in ['lib/runtime/async/composed.c', 'lib/runtime/async/linux.c', 'lib/runtime/runtime/context-17.c', 'lib/runtime/platform/text-posix.c']]
	providers += [here / 'affine-home-oracle.c']
	wrapped = ['astra_context17_open_affine', 'eventfd', 'write', 'close', 'astra_async_new_allocated', 'astra_async_new', 'astra_async_bridge_wait', 'astra_async_release_wait', 'astra_async_worker_pool_close', 'astra_async_run']
	flags = ['-isystem', prefix / 'include', prefix / 'lib/liburing.a', *['-Wl,--wrap=' + name for name in wrapped]]
	expected = 'affine home retirement: real worker notification, home owner/frame release and observed joined shutdown\n'
	for level in ['O0', 'O1', 'O2']:
		obj, product = e.output / (level + '.o'), e.output / level
		e.run([e.compiler, '-' + level, '-c', *sources, *imports, '-o', obj])
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', obj, *providers, *flags, '-o', product])
		e.run([product], stdout=expected, timeout=15)
		e.files(obj, product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'O2'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=45)
	for sanitizer in ['address', 'thread']:
		instrument(e, 'affine-home', sources, providers, expected, sanitizer, [*flags, '-DM17_EMITTED_ENTRY'], vapis=vapis)
	for name, text in [
		('direct', 'async void unsafe(owned HomeOwner owner){}'),
		('record', 'struct Unsafe{owned HomeOwner owner;}async void unsafe(Unsafe value){}'),
		('frame', 'void unsafe(){var frames=affine_allocator(1,4099,3,64);var pending=task_in(frames,compute(1,false));}'),
	]:
		negative = e.output / (name + '-refused.astra')
		negative.write_text(sources[1].read_text() + '\n' + text)
		diagnostic = 'selected worker frames require concurrent backing' if name == 'frame' else 'threaded task parameter is not Send'
		e.run([e.compiler, '-c', sources[0], negative, *sources[2:], *imports, '-o', e.output / 'negative.o'], expected=1, contains=diagnostic)
		e.files(negative)
	e.files(*sources, *vapis, *providers, Path(__file__), prefix / 'lib/liburing.a')
	for name in ['virtual.h', 'provider.h', 'task-core17.c', 'task-api17.c', 'worker17.c']:
		e.files(ROOT / 'lib/runtime/async' / name)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
