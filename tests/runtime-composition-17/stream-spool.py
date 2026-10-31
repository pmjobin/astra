#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Qualify ordinary streaming A against independent TCP/UDP and file oracles."""
from pathlib import Path
import json
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, prefix, output):
	e = Evidence(compiler, output, 'runtime-composition-17-stream-spool')
	prefix = Path(prefix).resolve(); here = Path(__file__).resolve().parent
	app = ROOT / 'examples/runtime-composition-17'; build = app / 'build-stream.py'
	wrappers = ['stream_prepare', 'stream_event', 'stream_finish', 'stream_stop_requested', 'astra_net_read', 'astra_context17_allocate_mode', 'astra_context17_release_origin_checked', 'astra_context17_destroy', 'astra_async_new_allocated', 'astra_async_worker_pool_close']
	observer_flags = ['--c-source', here / 'stream-protocol-oracle.c', '--c-flag=-DASTRA_ASYNC_LINUX_TEST_PROTOCOL'] + ['--link-flag=-Wl,--wrap=' + name for name in wrappers]
	e.data['profiles'] = []; e.save()
	e.files(*[p for p in app.iterdir() if p.is_file()], here / 'stream-peer.py', here / 'stream-protocol-oracle.c', Path(__file__), prefix / 'lib/liburing.a')
	for name in ['composed.c', 'task-core17.c', 'task-api17.c', 'worker17.c', 'linux.c', 'linux.h', 'virtual.h', 'provider.h']:
		e.files(ROOT / 'lib/runtime/async' / name)
	for name in ['context-17.c', 'context-17.h', 'monitors-13.c', 'monitors-13.h']:
		e.files(ROOT / 'lib/runtime/runtime' / name)
	for level in ['0', '1', '2']:
		case = e.output / ('observed-O' + level)
		e.run(['python3', build, '--compiler', e.compiler, '--uring-prefix', prefix, '--output', case, '--optimization', level, *observer_flags])
		product = case / ('stream-spool-O' + level)
		for family in ['4', '6']:
			receipt, data = case / ('peer-' + family + '.json'), case / ('output-' + family + '.bin')
			e.run(['python3', here / 'stream-peer.py', '--product', product, '--output', data, '--receipt', receipt, '--family', family], stdout='PASS: streaming peer, exact ordered transformed file and TCP/UDP progress\n', timeout=90)
			result = json.loads(receipt.read_text()); assert result['status'] == 'PASS'
			metrics = [json.loads(line) for line in result['stdout'].splitlines() if 'cpu_peak' in line]
			assert len(metrics) == 1 and metrics[0]['cpu_peak'] == 2 and metrics[0]['io_completed'] >= 8
			e.data['profiles'].append(dict(level=level, family=family, metrics=metrics[0], seconds=result['seconds'], child_lifetime_maxrss_kib=result['maxrss_kib'])); e.save()
			e.files(receipt, data)
		e.files(product, case / ('stream-spool-O' + level + '.o'), case / ('build-O' + level + '.json'))
	case = e.output / 'ordinary-O2'
	e.run(['python3', build, '--compiler', e.compiler, '--uring-prefix', prefix, '--output', case, '--optimization', '2'])
	product = case / 'stream-spool-O2'; receipt, data = case / 'peer-6.json', case / 'output-6.bin'
	e.run(['python3', here / 'stream-peer.py', '--product', product, '--output', data, '--receipt', receipt, '--family', '6'], stdout='PASS: streaming peer, exact ordered transformed file and TCP/UDP progress\n', timeout=90)
	e.files(product, case / 'stream-spool-O2.o', case / 'build-O2.json', receipt, data)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
