#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Repeat costs of exact qualified A products, including observed/idle controls."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import runpy
import statistics
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def trace_limits():
	resource.setrlimit(resource.RLIMIT_FSIZE, (64 * 1024**2, 64 * 1024**2))
	resource.setrlimit(resource.RLIMIT_CPU, (20, 20))
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	for name in ['qualification', 'build', 'runtime']: parser.add_argument(name, type=Path)
	args = parser.parse_args(); qualified = json.loads(args.qualification.read_text())
	assert qualified['status'] == 'PASS' and qualified['source_unchanged_during_qualification']
	for path in [args.build, args.runtime]:
		assert not path.resolve().is_relative_to(ROOT); path.mkdir(parents=True, exist_ok=True)
	build = Path(tempfile.mkdtemp(prefix='A-costs-', dir=args.build.resolve()))
	runtime = Path(tempfile.mkdtemp(prefix='A-costs-', dir=args.runtime.resolve()))
	oracle = runpy.run_path(str(Path(__file__).with_name('application-a.py')))['oracle']
	observer_source = ROOT / 'tests/runtime-composition-17/scheduler-cost-oracle.c'
	receipt = dict(qualification_sha256=sha(args.qualification), source_snapshot=qualified['source_snapshot'],
		inputs={str(p.relative_to(ROOT)): sha(p) for p in [Path(__file__).resolve(), observer_source]},
		scope='Serial alternating on/off process runs. Kernel intervals include observers; process costs include input/oracle/report/I/O/launch. Pthread matching includes observer/mutex reacquisition and does not establish causal wake latency.',
		affinity=sorted(os.sched_getaffinity(0)), load_before=Path('/proc/loadavg').read_text().strip(), commands=[], samples=[], traces={}, status='RUNNING')
	def save(): (runtime / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	def run(command, env=None, limits=None):
		command = list(map(str, command)); started = time.monotonic()
		p = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=45, preexec_fn=limits,
			env=dict(os.environ, LC_ALL='C', DEBUGINFOD_URLS='', **(env or {})))
		row = dict(command=command, environment=env or {}, exit=p.returncode, stdout=p.stdout, stderr=p.stderr, seconds=time.monotonic()-started)
		receipt['commands'].append(row); save(); assert p.returncode == 0 and not p.stderr, row
		return p.stdout
	observer = build / 'scheduler-observer.so'
	try:
		run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-fPIC', '-shared', '-pthread', observer_source, '-ldl', '-o', observer])
		products = {}
		for profile in qualified['profiles']:
			for mode in ['off', 'on']:
				product = qualified['products']['-'.join([profile, 'base', 'O2', 'strict', 'native', mode])]
				exe = Path(product['product']); assert sha(exe) == product['details']['products']['application']['sha256']
				products[profile, mode] = exe
		for profile in qualified['profiles']:
			for workers in ([1] if profile == 'sequential' else [1, 2, 4]):
				for granularity in ([1, 13] if profile == 'threaded' else [1]):
					for idle in ([0] if profile == 'sequential' else [0, 100]):
						for repetition in range(5):
							for mode in (['off', 'on'] if repetition % 2 == 0 else ['on', 'off']):
								for observed in ([False] if profile == 'sequential' else [False, True]):
									name = f'{profile}-w{workers}-g{granularity}-idle{idle}-r{repetition}-{mode}-{observed}'
									exe = products[profile, mode]; output = build / (name + '.bin'); timing = runtime / (name + '.time'); log = runtime / (name + '.json')
									env = dict(ASTRA_TELEMETRY_SAMPLES='48013', ASTRA_TELEMETRY_WINDOW='31', ASTRA_TELEMETRY_SEED='43', ASTRA_TELEMETRY_WORKERS=str(workers),
										ASTRA_TELEMETRY_GRANULARITY=str(granularity), ASTRA_TELEMETRY_BARRIER='0', ASTRA_TELEMETRY_IDLE_TICKS=str(idle), ASTRA_TELEMETRY_OUTPUT=str(output),
										ASTRA_SCHEDULER_OBSERVER_LOG=str(log))
									launch = [exe] + ([runtime / (name + '.pcm')] if profile == 'uring' else [])
									# Preload the measured child only; GNU time must not overwrite
									# the child's observer receipt from its own exit handler.
									if observed: launch = ['env', 'LD_PRELOAD=' + str(observer), *launch]
									text = run(['/usr/bin/time', '-f', '%e %U %S %M %w %c', '-o', timing, *launch], env)
									assert output.read_bytes() == oracle(48013, 31, 43)
									wall, user, system, rss, voluntary, involuntary = timing.read_text().split()
									row = dict(profile=profile, workers=workers, granularity=granularity, idle_ticks=idle, repetition=repetition, facts=mode, observed=observed,
										process_seconds=receipt['commands'][-1]['seconds'], time_wall_seconds=float(wall), user_seconds=float(user), system_seconds=float(system),
										rss_kib=int(rss), voluntary_switches=int(voluntary), involuntary_switches=int(involuntary),
										kernel_ns=int(re.search(r'kernel_ns=(\d+)', text)[1]), allocations=int(re.search(r'allocations=(\d+) retired=', text)[1]), output_sha256=sha(output))
									if observed:
										row['pthread'] = json.loads(log.read_text()); assert row['pthread']['locks'] and not row['pthread']['wake_slots_full'], row
									receipt['samples'].append(row); save()
									# Bounded instruction observations use the exact qualified executable,
									# shorter runtime data and only its linked lock-cmpxchg instruction sites.
		for mode in ['off', 'on']:
			exe = products['sequential', mode]
			assert 'EXEC (Executable file)' in run(['readelf', '-h', exe])
			assembly = run(['objdump', '-dr', exe])
			addresses = {int(m[1], 16) for m in re.finditer(r'^\s*([0-9a-f]+):[^\n]*\block\s+cmpxchg', assembly, re.M)}
			trace = runtime / (mode + '.trace')
			env = dict(ASTRA_TELEMETRY_SAMPLES='7', ASTRA_TELEMETRY_WINDOW='16', ASTRA_TELEMETRY_SEED='17', ASTRA_TELEMETRY_OUTPUT=str(build / (mode + '-trace.bin')))
			run(['valgrind', '--tool=lackey', '--basic-counts=no', '--trace-mem=yes', '--log-file=' + str(trace), exe], env, trace_limits)
			counts = {address: 0 for address in addresses}
			with trace.open() as stream:
				for line in stream:
					match = re.match(r'I\s+([0-9a-fA-F]+),', line)
					if match and int(match[1], 16) in counts: counts[int(match[1], 16)] += 1
			receipt['traces'][mode] = dict(static_sites=len(addresses), executed_cmpxchg=sum(counts.values()), sites={hex(k): v for k, v in counts.items()}, sha256=sha(trace), bytes=trace.stat().st_size); save()
		assert receipt['traces']['off']['executed_cmpxchg'] - receipt['traces']['on']['executed_cmpxchg'] == 4, receipt['traces']
		if 'threaded' in qualified['profiles']:
			receipt['context_metadata_dwarf'] = run(['gdb', '--nx', '--batch', '-ex', 'set disable-randomization off', '-ex', 'p sizeof(struct AstraContext17)',
				'-ex', 'p sizeof(ContextBlock)', '-ex', 'p sizeof(ContextHeader)', products['threaded', 'on']])
		groups = sorted({(r['profile'], r['workers'], r['granularity'], r['idle_ticks'], r['facts'], r['observed']) for r in receipt['samples']})
		receipt['medians'] = []
		for group in groups:
			rows = [r for r in receipt['samples'] if (r['profile'], r['workers'], r['granularity'], r['idle_ticks'], r['facts'], r['observed']) == group]
			receipt['medians'].append(dict(configuration=group, process_seconds=statistics.median(r['process_seconds'] for r in rows), kernel_ns=statistics.median(r['kernel_ns'] for r in rows), rss_kib=statistics.median(r['rss_kib'] for r in rows)))
		assert all(sha(ROOT / name) == digest for name, digest in receipt['source_snapshot'].items())
		assert all(sha(ROOT / name) == digest for name, digest in receipt['inputs'].items())
		receipt.update(status='PASS', source_unchanged_during_measurement=True)
	finally:
		if receipt['status'] != 'PASS': receipt['status'] = 'FAIL'
		save()
	print(runtime / 'checks.json')


if __name__ == '__main__': main()
