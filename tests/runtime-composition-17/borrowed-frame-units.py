#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Use allocator-borrowing frame helpers from a genuine opaque native SDK."""
from pathlib import Path
import hashlib
import re
import shutil
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output, profile='concurrent'):
	assert profile in ['concurrent', 'scoped']
	e = Evidence(compiler, output, 'runtime-composition-17-' + ('scoped-frame-units' if profile == 'scoped' else 'borrowed-frame-units'))
	here = Path(__file__).resolve().parent
	text = (here / 'borrowed-frame-contexts.astra').read_text()
	if profile == 'scoped':
		text = text.replace('ConcurrentAllocator', 'ScopedAllocator').replace('concurrent_allocator_query', 'scoped_allocator_query')
		text = text.replace('var first = concurrent_allocator(1, 8197, 1, 64);', 'owned u8[] first_backing=new u8[8197];owned u8[] second_backing=new u8[12289];var first=scoped_allocator<ScopedAllocator>(first_backing,1,1);')
		text = text.replace('var second = concurrent_allocator(2, 12289, 1, 64);', 'var second=scoped_allocator<ScopedAllocator>(second_backing,2,1);')

	producer, consumer = text.split('export(C) int run_borrowed_frame_contexts()', 1)
	producer = 'namespace BorrowedFrames;\n' + producer + (ROOT / 'lib/astra/base/errors.astra').read_text() + (ROOT / 'lib/astra/async/virtual.astra').read_text()
	consumer = 'extern(C) int borrowed_frames_finish();\nexport(C) int run_borrowed_frame_contexts()' + consumer
	names = ['borrowed_frame_drop', 'borrowed_frame_run', 'borrowed_frame_refuse', 'borrowed_frame_cancel']
	for name in names:
		consumer = re.sub(r'\b' + name + r'\b', 'BorrowedFrames.' + name, consumer)
	vapi = ROOT / 'lib/bindings/memory/contexts.vapi'
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/async/virtual.c', ROOT / 'lib/runtime/platform/text-posix.c', here / 'borrowed-frame-contexts-oracle.c']
	objects = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', *(['-DM17_BORROWED_AFFINE'] if profile == 'scoped' else []), '-c', provider, '-o', obj])
		objects.append(obj)
		e.files(obj)
	expected = 'borrowed frame contexts: 2 instances, 6 actual frames, joined error, suspended cancel, cold drops and 1 refusal\n'
	wrappers = ['-Wl,--wrap=astra_async_new_allocated', '-Wl,--wrap=astra_async_try_new_allocated', '-Wl,--wrap=astra_async_host_cancel']
	exports = [part for name in names for part in ['--native-export', 'BorrowedFrames.' + name]]
	for levels in ['00', '02', '20', '22', '11']:
		case = e.output / ('units-' + levels)
		case.mkdir(exist_ok=True)
		source = case / 'implementation.astra'
		source.write_text(producer)
		e.run([e.compiler, '-O' + levels[0], '-c', source, '--vapi', vapi, '--module', 'BorrowedFrames', *exports, '--emit-interface', case / 'producer.asti', '-o', case / 'producer.o'])
		sdk = case / 'sdk'
		sdk.mkdir(exist_ok=True)
		for path in [case / 'producer.asti', case / 'producer.o', vapi, *objects]:
			shutil.copyfile(path, sdk / path.name)
		shutil.copyfile(e.compiler, sdk / 'astrac')
		(sdk / 'astrac').chmod(0o755)
		(sdk / 'consumer.astra').write_text(consumer)
		assert [p.name for p in sdk.glob('*.astra')] == ['consumer.astra']
		command = [sdk / 'astrac', '-O' + levels[1], '-c', sdk / 'consumer.astra', '--vapi', sdk / vapi.name, '--import-module', sdk / 'producer.asti', '-o', sdk / 'consumer.o']
		e.run(command, cwd=sdk)
		e.run(['cc', '-pthread', sdk / 'consumer.o', sdk / 'producer.o', *[sdk / p.name for p in objects], *wrappers, '-o', sdk / 'consumer'], cwd=sdk)
		e.run([sdk / 'consumer'], stdout=expected, cwd=sdk, timeout=15)
		if levels == '22':
			e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', sdk / 'consumer'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=45, cwd=sdk)
			original = hashlib.sha256((sdk / 'consumer.o').read_bytes()).hexdigest()
			trace = sdk / 'opens.log'
			e.run(['strace', '-f', '-e', 'trace=openat,openat2', '-o', trace, *command], cwd=sdk)
			assert hashlib.sha256((sdk / 'consumer.o').read_bytes()).hexdigest() == original
			assert str(source) not in trace.read_text() and str(sdk / 'producer.asti') in trace.read_text()
		e.files(source, *[p for p in sdk.iterdir() if p.is_file()])
	e.files(*providers, vapi, here / 'borrowed-frame-contexts.astra', ROOT / 'lib/astra/base/errors.astra', ROOT / 'lib/astra/async/virtual.astra', Path(__file__), ROOT / 'tests/systems-dsp-9/support.py')
	for name in ['task-core17.c', 'task-api17.c', 'virtual.h', 'provider.h']:
		e.files(ROOT / 'lib/runtime/async' / name)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
