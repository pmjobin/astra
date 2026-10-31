# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Measure already qualified products; preserve independent output oracles."""
from pathlib import Path
import json
import re
import statistics
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence, identity


def main(build, output):
	build = Path(build).resolve()
	e = Evidence(build / 'astrac', output, 'concurrency-costs')
	base = build / 'tests/concurrency-runtime-13'
	e.data['measurements'] = []
	observer_source = Path(__file__).with_name('runtime-cost-oracle.c')
	observer = e.output / 'runtime-cost-oracle.so'
	e.run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-fPIC', '-shared', '-pthread', observer_source, '-ldl', '-o', observer])
	e.data['provider_layouts'] = {}
	for name, relative, fields in [
		('threads', 'runtime/threads-13.c', {'worker_bytes': 'sizeof(struct worker)', 'slot_table_bytes': 'sizeof(slots)'}),
		('monitor', 'runtime/monitors-13.c', {'monitor_bytes': 'sizeof(struct monitor)'}),
		('actor', 'runtime/actors-13.c', {'actor_bytes': 'sizeof(struct actor)', 'message_slot_bytes': 'sizeof(struct message)'}),
		('pool', 'async/threaded.c', {'pool_bytes': 'sizeof(struct threaded_pool)', 'executor_bytes': 'sizeof(AstraAsyncExecutor)', 'registration_bytes': 'sizeof(AstraAsyncRegistration)', 'task_protocol_bytes': 'sizeof(AstraAsyncTask)'}),
	]:
		provider = ROOT / 'lib/astra' / relative
		source = e.output / (name + '-layout.c'); product = source.with_suffix('')
		format_text = '{' + ','.join('"' + field + '":%zu' for field in fields) + '}\n'
		source.write_text('#include ' + json.dumps(str(provider)) + '\n#include <stdio.h>\nint main(void){printf(' + json.dumps(format_text) + ',' + ','.join(fields.values()) + ');return 0;}\n')
		e.run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', source, '-o', product])
		e.data['provider_layouts'][name] = json.loads(e.run([product]).stdout)
		e.files(provider, source, product)
	shapes = [
		('weak', 'weak-stress', 'concurrency-weak-stress', 'weak-8-17.O2', 32000, 'upgrade attempts'),
		('monitor', 'monitor-stress', 'concurrency-monitor-stress', 'monitor-8-17.O2', 16000, 'attempted credits'),
		('pool', 'task-stress', 'concurrency-task-stress', 'pool-8-17.O2', 35, 'Work captures, including cancellation'),
		('actor', 'actor-stress', 'concurrency-actor-stress', 'actor-8-17.O2', 1024, 'delivered messages; rejected attempts also retire'),
		('tcp', 'network-listener', 'concurrency-network-listener', 'listener-8-17.O2', 65536, 'frame payload bytes, both directions'),
		('service', 'applications', 'concurrency-applications', 'A120/O2', None, 'integrated service'),
	]
	for name, directory, receipt_name, product_name, operations, unit in shapes:
		directory = base / directory
		receipt = directory / (receipt_name + '.json')
		qualified = json.loads(receipt.read_text())
		assert qualified['status'] == 'PASS' and qualified['compiler'] == e.data['compiler']
		product = directory / product_name
		assert identity(product) in qualified['files'], product
		controls = [row for row in qualified['commands'] if row['command'] == [str(product)] and row['expected_stdout'] is not None]
		assert controls, product
		expected = controls[-1]['expected_stdout']
		runs = []
		for repetition in range(3):
			timing = e.output / f'{name}-{repetition}.time'
			result = e.run(['/usr/bin/time', '-f', '%e %U %S %M %w %c', '-o', timing, product], stdout=expected, timeout=60, env={'LC_ALL': 'C'})
			wall, user, system, rss, voluntary, involuntary = timing.read_text().split()
			seconds = e.data['commands'][-1]['seconds']
			runs.append(dict(elapsed_with_launch_seconds=seconds, time_wall_seconds=float(wall), user_seconds=float(user), system_seconds=float(system), max_rss_kib=int(rss), voluntary_switches=int(voluntary), involuntary_switches=int(involuntary), operations_per_elapsed_second=operations / seconds if operations else None))
			e.files(timing)
		massif = e.output / (name + '.massif')
		e.run(['valgrind', '--tool=massif', '--massif-out-file=' + str(massif), product], stdout=expected, timeout=90)
		heap = [int(value) for value in re.findall(r'^mem_heap_B=(\d+)$', massif.read_text(), re.M)]
		assert heap
		sections = e.run(['size', product]).stdout
		dynamic = e.run(['readelf', '-d', product]).stdout
		observed = e.output / (name + '-runtime.json')
		e.run([product], stdout=expected, timeout=60, env={'LD_PRELOAD': str(observer), 'ASTRA_COST_OBSERVER_LOG': str(observed)})
		counts = json.loads(observed.read_text())
		assert counts['threads_created'] > 1 and counts['successful_explicit_mutex_locks'] > 0
		trace = e.output / (name + '-syscalls.txt')
		e.run(['strace', '-f', '-c', '-o', trace, product], stdout=expected, timeout=60)
		e.data['measurements'].append(dict(name=name, product=identity(product), operations=operations, unit=unit,
			runs=runs, median_elapsed_seconds=statistics.median(row['elapsed_with_launch_seconds'] for row in runs),
			massif_max_sampled_heap_bytes=max(heap), sections=sections,
			needed=re.findall(r'\(NEEDED\).*?\[(.*?)\]', dynamic), runtime_counts=counts, syscall_summary=trace.read_text()))
		e.files(product, receipt, massif, observed, trace)
		# A plain unique Class proves that unused policies introduce no service.
	source = e.output / 'unique.astra'
	source.write_text('class Value{int n;init(int n){this.n=n;}}int main(){var value=new Value(7);return value.n-7;}\n')
	for level in ['O0', 'O2']:
		product = e.output / ('unique-' + level)
		e.run([e.compiler, '-' + level, source, '-o', product])
		e.run([product], stdout='')
		ir = e.run([e.compiler, '-' + level, '--dump-llvm', source]).stdout
		assert not any(token in ir for token in ['cmpxchg', 'atomicrmw', 'astra_monitor_', 'astra_async_', 'astra_thread_', 'astra_actor_', 'astra_singleton_'])
		symbols = e.run(['nm', product]).stdout
		assert not any(token in symbols for token in ['pthread_', 'astra_monitor_', 'astra_async_', 'astra_actor_', 'astra_singleton_', 'io_uring_', 'g_object_'])
		dynamic = e.run(['readelf', '-d', product]).stdout
		needed = re.findall(r'\(NEEDED\).*?\[(.*?)\]', dynamic)
		assert needed == ['libc.so.6'], needed
		e.data.setdefault('unique', []).append(dict(level=level, product=identity(product), needed=needed, sections=e.run(['size', product]).stdout))
		e.files(product)
	guest = build / 'tests/freestanding-allocation-12/guest/a97-O2.elf'
	e.run(['nm', '-u', guest], stdout='')
	headers = e.run(['readelf', '-l', '-d', guest]).stdout
	assert 'INTERP' not in headers and 'NEEDED' not in headers
	e.data['guest'] = dict(product=identity(guest), sections=e.run(['size', guest]).stdout)
	for command in [['uname', '-a'], ['getconf', '_NPROCESSORS_ONLN'], ['ldd', '--version'], ['clang', '--version'], ['opt', '--version'], ['cc', '--version'], ['valgrind', '--version'], ['pkg-config', '--modversion', 'gobject-2.0']]:
		e.run(command)
	e.files(source, guest, Path(__file__), observer_source, observer)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
