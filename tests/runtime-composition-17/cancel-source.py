#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Force public-source cancellation during native worker execution and publication."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, prefix, output, profile='direct'):
	assert profile in ['direct', 'nested', 'bytes']
	e = Evidence(compiler, output, 'runtime-composition-17-source-cancellation' + ('-' + profile if profile != 'direct' else ''))
	e.data['backing_profile'] = profile
	e.save()
	prefix = Path(prefix).resolve()
	here = Path(__file__).resolve().parent
	vapis = [ROOT / 'lib/bindings/memory/contexts.vapi', here / 'context-custom.vapi', ROOT / 'lib/bindings/async/composition.vapi']
	imports = [argument for path in vapis for argument in ['--vapi', path]]
	base_providers = [ROOT / 'lib/runtime/async/composed.c', ROOT / 'lib/runtime/runtime/context-17.c',
		ROOT / 'lib/runtime/platform/text-posix.c', here / 'context-provider.c', here / 'cancel-oracle.c']
	flags = ['-Wl,--wrap=' + name for name in ['astra_async_new', 'astra_async_new_allocated', 'astra_async_worker_pool_close', 'astra_async_bridge_wait', 'pthread_create', 'pthread_join']]
	expected = 'source cancellation: cold, worker start failure, full/closed admission, queued, executing, published success/error; exact context/frame/capture retirement and FD/thread baselines\n'
	worker = here / 'cancel-worker.astra'
	if profile == 'bytes':
		worker = e.output / 'byte-worker.astra'
		worker.write_text((here / 'cancel-worker.astra').read_text().replace('owned int[]', 'owned ContextBytes<ConcurrentAllocator>').replace('this.input[i % len(this.input)]', '(this.input[i % len(this.input)] as int)'))
		flags += ['-DM17_CONTEXT_BYTE_INPUT', '-Wl,--wrap=astra_context17_allocate_mode', '-Wl,--wrap=astra_context17_release_origin_checked']
	e.files(*vapis, *base_providers, here / 'cancel-source.astra', here / 'cancel-worker.astra', here / 'cancel-entry.c', Path(__file__))
	for name, provider, wait in [('virtual', 'virtual-composed', 'delay_ticks(1)'), ('linux', 'linux-io-uring-composed', 'delay_ms(1)')]:
		common, source = e.output / (name + '-common.astra'), e.output / (name + '-main.astra')
		common.write_text('class BridgeError : Error { init(string message) : base(message) {} }\n'
			'enum CancellationStatus { Completed, Cancelled }\n'
			'async runtime CancellationService throws BridgeError returns CancellationStatus provider "' + provider + '";\n')
		text = (here / 'cancel-source.astra').read_text().replace('WAIT_ONE', wait)
		if profile == 'bytes':
			text = text.replace('owned int[] input = new int[37];', 'owned ContextBytes<ConcurrentAllocator> input = new(context)u8[37];')
			text = text.replace('input[i] = (i * 23 + 41) % 251;', 'input[i] = ((i * 23 + 41) % 251) as u8;')
		if profile == 'nested':
			needle = 'var context = custom_allocator(65543, 17);'
			assert text.count(needle) == 2
			text = text.replace(needle, '''var parent = custom_allocator(131101, 17);
	if (parent == null) { throw new Error("parent context admission"); }
	var middle = nested_allocator(parent, 1, 65543, 11, 128);
	if (middle == null) { throw new Error("middle context admission"); }
	var context = nested_allocator(middle, 2, 32779, 5, 256);
	close_cancellation_anchor(move parent);
	close_cancellation_anchor(move middle);''')
		source.write_text(text)
		sources = [common, worker, source, ROOT / 'lib/astra/base/errors.astra']
		providers = base_providers + ([ROOT / 'lib/runtime/async/linux.c'] if name == 'linux' else [])
		links = flags + (['-isystem', prefix / 'include', prefix / 'lib/liburing.a'] if name == 'linux' else [])
		e.files(*sources, *providers)
		for level in ['O0', 'O1', 'O2']:
			obj, product = [e.output / (name + '-' + level + suffix) for suffix in ['.o', '']]
			e.run([e.compiler, '-' + level, '-c', *sources, *imports, '-o', obj])
			e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', obj, *providers, here / 'cancel-entry.c', *links, '-o', product])
			e.run([product], stdout=expected, timeout=30)
			e.files(obj, product)
		e.run([e.output / (name + '-O2')], stdout=expected, timeout=60, env={'M17_CANCEL_ROUNDS': '24'})
		e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / (name + '-O2')], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=90)
		for sanitizer in ['address', 'thread']:
			instrument(e, name + '-cancel', sources, providers, expected, sanitizer, links, vapis=vapis)
	for path in ['task-core17.c', 'task-api17.c', 'worker17.c', 'virtual.h', 'provider.h', 'linux.h']:
		e.files(ROOT / 'lib/runtime/async' / path)
	e.files(prefix / 'lib/liburing.a')
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
