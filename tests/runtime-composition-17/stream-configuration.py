#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Runtime configuration, bounded queue observations and independent stream oracles."""
from pathlib import Path
import json
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, prefix, output):
	e = Evidence(compiler, output, 'runtime-composition-17-stream-configuration')
	prefix = Path(prefix).resolve(); here = Path(__file__).resolve().parent
	app = ROOT / 'examples/runtime-composition-17'
	wrappers = ['stream_prepare', 'stream_event', 'stream_finish', 'stream_stop_requested', 'astra_net_read', 'astra_context17_allocate_mode', 'astra_context17_release_origin_checked', 'astra_context17_destroy', 'astra_async_new_allocated', 'astra_async_worker_pool_close']
	flags = ['--c-source', here / 'stream-protocol-oracle.c', '--c-flag=-DASTRA_ASYNC_LINUX_TEST_PROTOCOL'] + ['--link-flag=-Wl,--wrap=' + name for name in wrappers]
	e.data['profiles'] = []
	for level, capacity, workers, storage, frames, limit, alignment in [
		('0', 1, 2, 131071, 524309, 1021, 64),
		('1', 3, 3, 524309, 786433, 3001, 128),
		('2', 5, 4, 1048573, 1048583, 4093, 256),
	]:
		case = e.output / ('configured-O' + level)
		e.run(['python3', app / 'build-stream.py', '--compiler', e.compiler, '--uring-prefix', prefix, '--output', case, '--optimization', level, *flags])
		product = case / ('stream-spool-O' + level)
		environment = dict(ASTRA_STREAM_CAPACITY=str(capacity), ASTRA_STREAM_WORKERS=str(workers), ASTRA_STREAM_CONTEXT_BYTES=str(storage), ASTRA_STREAM_FRAME_BYTES=str(frames), ASTRA_STREAM_CHUNK_LIMIT=str(limit), ASTRA_STREAM_ALIGNMENT=str(alignment))
		for family in ['4', '6']:
			receipt = case / ('peer-' + family + '.json'); data = case / ('output-' + family + '.bin')
			e.run(['python3', here / 'stream-peer.py', '--product', product, '--output', data, '--receipt', receipt, '--family', family, '--frame-limit', str(limit)], env=environment, stdout='PASS: streaming peer, exact ordered transformed file and TCP/UDP progress\n', timeout=90)
			result = json.loads(receipt.read_text()); assert result['status'] == 'PASS'
			metrics = [json.loads(line) for line in result['stdout'].splitlines() if 'cpu_peak' in line]
			assert len(metrics) == 1; metrics = metrics[0]
			assert metrics['cpu_peak'] == 2 and 2 <= metrics['worker_count'] <= workers
			assert metrics['queue_limit'] == capacity
			assert 1 <= metrics['queue_peak'] <= capacity and metrics['io_completed'] >= 8
			assert len({row['instance'] for row in metrics['context_peaks']}) == 5
			e.data['profiles'].append(dict(level=level, family=family, environment=environment, metrics=metrics, seconds=result['seconds'], child_lifetime_maxrss_kib=result['maxrss_kib']))
			e.files(receipt, data); e.save()
		e.files(product, case / ('stream-spool-O' + level + '.o'), case / ('build-O' + level + '.json'))
	case = e.output / 'invalid-configuration'
	e.run(['python3', app / 'build-stream.py', '--compiler', e.compiler, '--uring-prefix', prefix, '--output', case, '--optimization', '2'])
	product = case / 'stream-spool-O2'
	for name, value in [('ASTRA_STREAM_WORKERS', '1'), ('ASTRA_STREAM_CAPACITY', 'nine'), ('ASTRA_STREAM_ALIGNMENT', '96')]:
		e.run([product, '127.0.0.1', '4', case / 'unused.bin'], env={name: value}, expected=64, contains='"result":64')
		assert not (case / 'unused.bin').exists()
	e.files(product, case / 'stream-spool-O2.o', case / 'build-O2.json', *[p for p in app.iterdir() if p.is_file()], here / 'stream-peer.py', here / 'stream-protocol-oracle.c', Path(__file__), prefix / 'lib/liburing.a', ROOT / 'tests/systems-dsp-9/support.py')
	for directory in ['lib/astra/async', 'lib/runtime/async', 'lib/runtime/runtime', 'lib/astra/memory', 'lib/bindings/memory', 'lib/astra/platform', 'lib/runtime/platform']:
		e.files(*[p for p in (ROOT / directory).iterdir() if p.is_file()])
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
