#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Streaming A handles live cancellation, framing and file-open failures."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, prefix, output):
	e = Evidence(compiler, output, 'runtime-composition-17-stream-failures')
	here = Path(__file__).resolve().parent; app = ROOT / 'examples/runtime-composition-17'
	wrappers = ['stream_prepare', 'stream_event', 'stream_finish', 'stream_stop_requested', 'astra_net_read', 'astra_context17_allocate_mode', 'astra_context17_release_origin_checked', 'astra_context17_destroy', 'astra_async_new_allocated', 'astra_async_worker_pool_close']
	flags = ['--c-source', here / 'stream-protocol-oracle.c', '--c-flag=-DASTRA_ASYNC_LINUX_TEST_PROTOCOL'] + ['--link-flag=-Wl,--wrap=' + name for name in wrappers]
	case = e.output / 'observed-O2'
	e.run(['python3', app / 'build-stream.py', '--compiler', e.compiler, '--uring-prefix', prefix, '--output', case, '--optimization', '2', *flags])
	product = case / 'stream-spool-O2'
	for family in ['4', '6']:
		for mode in ['truncate', 'oversize', 'file-error', 'cancel']:
			receipt = case / (family + '-' + mode + '.json'); data = case / (family + '-' + mode + '.output')
			e.run(['python3', here / 'stream-failure-peer.py', '--product', product, '--output', data, '--receipt', receipt, '--family', family, '--mode', mode], stdout='PASS: stream ' + mode + ', observed outcome and complete resource conservation\n', timeout=90)
			e.files(receipt)
	e.files(*[p for p in app.iterdir() if p.is_file()], here / 'stream-protocol-oracle.c', here / 'stream-failure-peer.py', here / 'stream-peer.py', Path(__file__), product, case / 'stream-spool-O2.o', case / 'build-O2.json')
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
