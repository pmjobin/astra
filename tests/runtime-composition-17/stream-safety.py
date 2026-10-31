#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Instrument emitted streaming algorithms, all project C providers and oracles."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, prefix, output):
	e = Evidence(compiler, output, 'runtime-composition-17-stream-safety')
	prefix = Path(prefix).resolve(); here = Path(__file__).resolve().parent; app = ROOT / 'examples/runtime-composition-17'
	sources = [app / ('stream-' + name + '.astra') for name in ['common', 'pipeline', 'factories', 'worker', 'stages', 'spool']] + [ROOT / 'lib/astra/base/errors.astra', ROOT / 'lib/astra/hosted/network.astra', ROOT / 'lib/astra/async/payload.astra']
	vapis = [ROOT / 'lib/bindings/memory/contexts.vapi', ROOT / 'lib/bindings/async/composition.vapi', ROOT / 'lib/bindings/async/payload.vapi', app / 'stream-host.vapi']
	providers = [app / 'stream-host.c', ROOT / 'lib/runtime/async/composed.c', ROOT / 'lib/runtime/async/linux.c', ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/runtime/monitors-13.c', ROOT / 'lib/runtime/platform/network-posix.c', ROOT / 'lib/runtime/platform/text-posix.c', ROOT / 'lib/runtime/platform/args-posix.c', here / 'stream-protocol-oracle.c']
	names = ['stream_prepare', 'stream_event', 'stream_finish', 'stream_stop_requested', 'astra_net_read', 'astra_context17_allocate_mode', 'astra_context17_release_origin_checked', 'astra_context17_destroy', 'astra_async_new_allocated', 'astra_async_worker_pool_close']
	wrappers = ['-Wl,--wrap=' + name for name in names]
	flags = ['-DASTRA_ASYNC_LINUX_TEST_PROTOCOL', '-isystem', prefix / 'include', prefix / 'lib/liburing.a', *wrappers]
	case = e.output / 'ordinary-O2'
	build_flags = ['--c-source', here / 'stream-protocol-oracle.c', '--c-flag=-DASTRA_ASYNC_LINUX_TEST_PROTOCOL', *['--link-flag=-Wl,--wrap=' + name for name in names]]
	e.run(['python3', app / 'build-stream.py', '--compiler', e.compiler, '--uring-prefix', prefix, '--output', case, '--optimization', '2', *build_flags])
	expected = 'PASS: streaming peer, exact ordered transformed file and TCP/UDP progress\n'
	receipt, data = case / 'valgrind.json', case / 'valgrind.bin'
	e.run(['python3', here / 'stream-peer.py', '--product', case / 'stream-spool-O2', '--output', data, '--receipt', receipt, '--family', '4', '--valgrind'], stdout=expected, timeout=120, env={'M17_STREAM_SERIALIZED_TOOL': '1'})
	e.files(receipt, data, case / 'stream-spool-O2', case / 'stream-spool-O2.o', case / 'build-O2.json')
	for sanitizer in ['address', 'thread']:
		def execute(product, environment):
			receipt, data = e.output / (sanitizer + '.json'), e.output / (sanitizer + '.bin')
			e.run(['python3', here / 'stream-peer.py', '--product', product, '--output', data, '--receipt', receipt, '--family', '6'], stdout=expected, timeout=120, env=environment)
			e.files(receipt, data)
			for mode in ['truncate', 'oversize', 'file-error', 'cancel']:
				receipt, data = e.output / (sanitizer + '-' + mode + '.json'), e.output / (sanitizer + '-' + mode + '.output')
				e.run(['python3', here / 'stream-failure-peer.py', '--product', product, '--output', data, '--receipt', receipt, '--family', '6', '--mode', mode], stdout='PASS: stream ' + mode + ', observed outcome and complete resource conservation\n', timeout=120, env=environment)
				e.files(receipt)
		instrument(e, 'stream', sources, providers, '', sanitizer, link_flags=flags, vapis=vapis, execute=execute)
	e.files(Path(__file__), here / 'stream-peer.py', here / 'stream-failure-peer.py', ROOT / 'tests/concurrency-runtime-13/sanitizers.py', prefix / 'lib/liburing.a')
	for name in ['task-core17.c', 'task-api17.c', 'worker17.c', 'virtual.h', 'provider.h', 'linux.h']: e.files(ROOT / 'lib/runtime/async' / name)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
