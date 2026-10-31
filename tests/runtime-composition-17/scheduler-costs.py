#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Snapshot qualified worker products; measure plain and observed execution."""
from pathlib import Path
import json
import shutil
import statistics
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence, identity


def main(build, output):
	build = Path(build).resolve()
	e = Evidence(build / 'astrac', output, 'runtime-composition-17-scheduler-costs')
	here = Path(__file__).resolve().parent
	observer = e.output / 'scheduler-cost-oracle.so'
	e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-fPIC', '-shared', '-pthread', here / 'scheduler-cost-oracle.c', '-ldl', '-o', observer])
	e.data['scope'] = 'Process-wide explicit pthread calls, including independent observers. Acquisition and broadcast-to-wait-return samples include instrumentation and mutex reacquisition. Samples match condition addresses and broadcasts inside actual wait intervals; they do not prove causal wakeups. Paired samples measure overhead; no speedup or race-freedom inference.'
	e.data['measurements'] = []
	registry = {test['name']: test for test in json.loads((build / 'meson-info/intro-tests.json').read_text())}
	for name, directory, receipt, binary in [
		('context-workers', 'runtime-composition-17-context-workers', 'runtime-composition-17-context-workers', 'workers-O2'),
		('worker-stress', 'concurrency-runtime-13-task-stress', 'concurrency-task-stress', 'pool-8-17.O2'),
	]:
		base = Path(registry[directory]['cmd'][-1]).resolve()
		assert base.is_relative_to(build)
		qualified_path = base / (receipt + '.json')
		qualified = json.loads(qualified_path.read_text())
		assert qualified['status'] == 'PASS' and qualified['compiler'] == e.data['compiler']
		original = base / binary
		assert identity(original) in qualified['files']
		controls = [row for row in qualified['commands'] if row['command'] == [str(original)] and row['expected_stdout'] is not None]
		assert controls
		expected = controls[-1]['expected_stdout']
		snapshot = e.output / name
		snapshot.mkdir(exist_ok=False)
		product = snapshot / 'product'
		shutil.copy2(original, product)
		shutil.copy2(qualified_path, snapshot / 'qualification.json')
		# Snapshot all source identities used by the qualification, so subsequent
		# scheduler edits cannot silently change the baseline's source closure.
		for row in qualified['files']:
			path = Path(row['path'])
			if path.is_relative_to(ROOT):
				assert identity(path) == row, row
				destination = snapshot / 'source' / path.relative_to(ROOT)
				destination.parent.mkdir(parents=True, exist_ok=True)
				shutil.copy2(path, destination)
				e.files(destination)
		for relative in ['lib/runtime/async/task-core17.c', 'lib/runtime/async/worker17.c', 'lib/runtime/async/task-api17.c', 'lib/runtime/async/virtual.h', 'lib/runtime/async/provider.h']:
			path = ROOT / relative
			destination = snapshot / 'source' / relative
			destination.parent.mkdir(parents=True, exist_ok=True)
			shutil.copy2(path, destination)
			e.files(path, destination)
		samples = []
		for repetition in range(5):
			for mode in ['plain', 'observed']:
				timing = snapshot / f'{repetition}-{mode}.time'
				log = snapshot / f'{repetition}-{mode}.json'
				launch = [product]
				if mode == 'observed':
					launch = ['env', 'LD_PRELOAD=' + str(observer), 'ASTRA_SCHEDULER_OBSERVER_LOG=' + str(log), product]
				e.run(['/usr/bin/time', '-f', '%e %U %S %M %w %c', '-o', timing, *launch], stdout=expected, timeout=45, env={'LC_ALL': 'C'})
				wall, user, system, rss, voluntary, involuntary = timing.read_text().split()
				row = dict(repetition=repetition, mode=mode, elapsed_with_launch_seconds=e.data['commands'][-1]['seconds'], time_wall_seconds=float(wall), user_seconds=float(user), system_seconds=float(system), rss_kib=int(rss), voluntary_switches=int(voluntary), involuntary_switches=int(involuntary))
				if mode == 'observed':
					row['pthread'] = json.loads(log.read_text())
					assert row['pthread']['locks'] > 0 and row['pthread']['broadcasts'] > 0
					assert row['pthread']['wake_slots_full'] == 0
					assert row['pthread']['wake_samples'] > 0
					e.files(log)
				samples.append(row)
				e.files(timing)
		trace = snapshot / 'syscalls.txt'
		e.run(['strace', '-f', '-c', '-o', trace, product], stdout=expected, timeout=45)
		e.data['measurements'].append(dict(name=name, original=identity(original), snapshot=identity(product), samples=samples,
			median_plain_seconds=statistics.median(row['elapsed_with_launch_seconds'] for row in samples if row['mode'] == 'plain'),
			median_observed_seconds=statistics.median(row['elapsed_with_launch_seconds'] for row in samples if row['mode'] == 'observed'), syscall_summary=trace.read_text()))
		e.files(product, snapshot / 'qualification.json', trace)
		e.save()
	e.files(Path(__file__), here / 'scheduler-cost-oracle.c', observer)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
