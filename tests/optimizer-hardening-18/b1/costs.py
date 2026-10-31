#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Serial raw B1 timings, whole-process RSS and instruction-traced lifetime costs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import statistics
import subprocess
import sys
import tempfile
import time
sys.dont_write_bytecode = True
from reference import generate, reconcile, SEED
from qualify import observations, ROOT, APP
sys.path.insert(0, str(APP))
from freeze import check as freeze_check


def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	for name in ['qualification', 'build', 'runtime']: parser.add_argument(name, type=Path)
	parser.add_argument('--freeze', type=Path)
	args = parser.parse_args(); qualified = json.loads(args.qualification.read_text())
	assert qualified['status'] == 'PASS' and qualified['source_unchanged']
	for path in [args.build, args.runtime]:
		assert not path.resolve().is_relative_to(ROOT); path.mkdir(parents=True, exist_ok=True)
	build = Path(tempfile.mkdtemp(prefix='B1-costs-', dir=args.build.resolve()))
	runtime = Path(tempfile.mkdtemp(prefix='B1-costs-', dir=args.runtime.resolve()))
	receipt = dict(status='RUNNING', qualification_sha256=sha(args.qualification), source_snapshot=qualified['source_snapshot'],
		inputs={str(Path(__file__)): sha(Path(__file__))}, schedule='Five serial alternating off/on repetitions per size/profile/worker count; process wall includes launch and file I/O. kernel_ns sums thread-local job intervals, including map and allocator work. No idle-host assumption or universal scaling claim.',
		load_average_before=os.getloadavg(), commands=[], samples=[], summaries=[], products={},
		memory_scope='GNU time reports whole-process maximum RSS in KiB separately from fixed backing capacities and observed live/reserved payload. A zero report means below this short-lived measurement resolution, not zero resident memory.',
		contexts=dict(input_and_jobs=dict(capacity_bytes=2097152, slots=64), frames=dict(capacity_bytes=262144, slots=32),
		metadata_rule='Each distinct context reserves its fixed payload backing plus a 280-byte instance and 72 bytes per slot, excluding allocator headers/alignment; sequential uses only input/job context.'),
		trace_scope='Exact qualified consumer/native objects and C providers relinked with -no-pie solely for stable instruction addresses. Lackey counts linked executable lock cmpxchg sites; external shared libraries are excluded. 32 MiB file/20 CPU-second child caps.')
	def save(): (runtime / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	def run(command, *, workers=1, limits=None, diagnostics=False):
		command = list(map(str, command)); started = time.monotonic()
		q = subprocess.run(command, capture_output=True, text=True, cwd=runtime, timeout=60, preexec_fn=limits,
			env=dict(os.environ, CCACHE_DISABLE='1', DEBUGINFOD_URLS='', LC_ALL='C', ASTRA_JOURNAL_WORKERS=str(workers)))
		row = dict(command=command, workers=workers, exit=q.returncode, stdout=q.stdout, stderr=q.stderr, seconds=time.monotonic() - started)
		receipt['commands'].append(row); save(); assert q.returncode == 0 and (diagnostics or not q.stderr), row
		return row
	def frozen(): return freeze_check(args.freeze, ROOT) if args.freeze else None
	def trace_limits():
		resource.setrlimit(resource.RLIMIT_FSIZE, (32 * 1024 ** 2, 32 * 1024 ** 2))
		resource.setrlimit(resource.RLIMIT_CPU, (20, 20)); resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	try:
		receipt['freeze_before'] = frozen()
		for profile in qualified['profiles']:
			for workers in ([1] if profile == 'sequential' else [1, 2, 4]):
				for count in [513, 8193]:
					data = generate(count, SEED + 31); expected, reference = reconcile(data)
					source = runtime / (str(count) + '.input'); source.write_bytes(data)
					for repetition in range(5):
						for facts in (['off', 'on'] if repetition % 2 == 0 else ['on', 'off']):
							product = qualified['products'][profile + '-base-O2-native-P2-' + facts]
							name = f'{profile}-w{workers}-n{count}-r{repetition}-{facts}'; target = runtime / (name + '.output')
							row = run([product['product'], source, target], workers=workers)
							assert target.read_bytes() == expected
							receipt['samples'].append(dict(profile=profile, workers=workers, records=count, repetition=repetition, facts=facts,
								wall_seconds=row['seconds'], output_sha256=sha(target), **observations(row['stdout'], data, reference, profile, workers))); save()
					for facts in ['off', 'on']:
						product = qualified['products'][profile + '-base-O2-native-P2-' + facts]
						name = f'{profile}-w{workers}-n{count}-{facts}'; target, rss = runtime / (name + '-rss.output'), runtime / (name + '-rss.txt')
						row = run(['/usr/bin/time', '-f', '%M', '-o', rss, product['product'], source, target], workers=workers)
						assert target.read_bytes() == expected; observed = observations(row['stdout'], data, reference, profile, workers)
						samples = [r for r in receipt['samples'] if (r['profile'], r['workers'], r['records'], r['facts']) == (profile, workers, count, facts)]
						receipt['summaries'].append(dict(profile=profile, workers=workers, records=count, facts=facts,
							median_wall_seconds=statistics.median(r['wall_seconds'] for r in samples),
							median_kernel_ns=statistics.median(r['kernel_ns'] for r in samples), maximum_rss_kib=int(rss.read_text()), observations=observed)); save()
		for facts in ['off', 'on']:
			product = qualified['products']['sequential-base-O2-native-P2-' + facts]
			path = Path(product['receipt']); assert sha(path) == product['receipt_sha256']; complete = json.loads(path.read_text())
			trace_product = build / (facts + '-address-control'); link = complete['link_command'][:]; link[-1] = str(trace_product)
			link.insert(1, '-no-pie'); run(link)
			assert 'EXEC (Executable file)' in run(['readelf', '-h', trace_product])['stdout']
			assembly = run(['objdump', '-dr', trace_product])['stdout']; asm = runtime / (facts + '.asm'); asm.write_text(assembly)
			addresses = {int(m[1], 16) for m in re.finditer(r'^\s*([0-9a-f]+):[^\n]*\block\s+cmpxchg', assembly, re.M)}
			data = generate(7); expected, reference = reconcile(data); source, target = runtime / 'trace.input', runtime / (facts + '-trace.output'); source.write_bytes(data)
			trace = runtime / (facts + '.trace')
			row = run(['valgrind', '--tool=lackey', '--basic-counts=no', '--trace-mem=yes', '--log-file=' + str(trace), trace_product, source, target], limits=trace_limits)
			assert target.read_bytes() == expected; observations(row['stdout'], data, reference, 'sequential', 1)
			counts = {address: 0 for address in addresses}
			with trace.open() as stream:
				for line in stream:
					match = re.match(r'I\s+([0-9a-fA-F]+),', line)
					if match and int(match[1], 16) in counts: counts[int(match[1], 16)] += 1
			receipt['products'][facts] = dict(path=str(trace_product), sha256=sha(trace_product), qualified_product=product['product'],
				sections=run(['size', '-A', product['product']])['stdout'], disassembly_sha256=sha(asm),
				static_cmpxchg=len(addresses), executed_cmpxchg=sum(counts.values()), cmpxchg_sites={hex(k): v for k, v in counts.items()},
				trace_sha256=sha(trace), trace_bytes=trace.stat().st_size); save()
		assert all(sha(path) == digest for path, digest in receipt['source_snapshot'].items())
		assert all(sha(path) == digest for path, digest in receipt['inputs'].items())
		receipt.update(status='PASS', source_unchanged=True, freeze_after=frozen(), load_average_after=os.getloadavg())
	finally:
		if receipt['status'] != 'PASS': receipt['status'] = 'FAIL'
		save()
	print(runtime / 'checks.json')


if __name__ == '__main__': main()
