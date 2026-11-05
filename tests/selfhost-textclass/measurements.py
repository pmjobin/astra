#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Report measured build/test intervals and every retained development attempt."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re


def sha(path):
	with Path(path).open('rb') as stream: return hashlib.file_digest(stream, 'sha256').hexdigest()


def read(path):
	return json.loads(Path(path).read_text())


def union(intervals):
	end, total = 0, 0
	for first, last in sorted(intervals):
		assert last >= first
		total += max(0, last-max(end, first)); end = max(end, last)
	return total


def main():
	p = argparse.ArgumentParser()
	for name in ('runtime', 'qualification', 'predecessor-qualification', 'output'): p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--version', required=True, help='Final native build version, e.g. v9'); a = p.parse_args()
	builds = {}; build_intervals = []
	for mode in ('O0', 'O2'):
		paths = sorted((a.runtime/('native-'+a.version+'-'+mode)).glob('build-*/ownflow-'+mode+'.json')); assert paths
		path = paths[-1]; row = read(path); assert row['exit'] == 0
		first, last = row['monotonic_start'], row['monotonic_end']; build_intervals.append((first, last))
		stderr = path.with_suffix('.stderr'); raw = stderr.read_text()
		rss = re.search(r'Maximum resident set size \(kbytes\): (\d+)', raw); assert rss
		builds[mode] = dict(command_receipt=str(path), command_receipt_sha256=sha(path), elapsed_seconds=last-first, monotonic_start=first, monotonic_end=last, peak_RSS_KiB=int(rss[1]), raw_time_sha256=sha(stderr))
	tests, intervals = [], []
	for family, root in (('textclass', a.qualification), ('predecessor', a.predecessor_qualification)):
		for path in sorted(root.glob('*/commands.json')):
			for row in read(path):
				assert row['exit'] == 0 or row['name'].startswith('bounded-three-specializations-')
				first, last = row['monotonic_start'], row['monotonic_end']; intervals.append((first, last))
				tests.append(dict(family=family, gate=path.parent.name, name=row['name'], exit=row['exit'], seconds=last-first, monotonic_start=first, monotonic_end=last, command_receipt=str(path), command_receipt_sha256=sha(path)))
	reused = []
	for path in sorted(a.qualification.glob('*/current-reuse.json')):
		data = read(path); observations = Path(data['observations']); commands = read(observations/'commands.json')
		reused.append(dict(classification=data['classification'], receipt_path=str(observations/'result.json'), receipt_sha256=sha(observations/'result.json'), sequential_child_elapsed_seconds=sum(row['seconds'] for row in commands), limitation='These fresh candidate mutation commands ran sequentially before the final gate wrapper. Their original receipt has elapsed durations but no absolute monotonic endpoints. They are reported separately and are not added to the overlapping qualification interval union.'))
	attempts = []
	for path in sorted(a.runtime.glob('*/build-*/*.json')):
		row = read(path)
		if not isinstance(row, dict) or 'argv' not in row or 'exit' not in row: continue
		if not path.stem.startswith('ownflow-'): continue
		stderr = path.with_suffix('.stderr'); stdout = path.with_suffix('.stdout')
		attempts.append(dict(receipt=str(path), receipt_sha256=sha(path), exit=row['exit'], argv=row['argv'], seconds=row.get('seconds', row.get('monotonic_end', 0)-row.get('monotonic_start', 0)), stderr_sha256=sha(stderr), stdout_sha256=sha(stdout), final_qualified=path.parent.parent.name in ('native-'+a.version+'-O0', 'native-'+a.version+'-O2')))
	pilots = []
	for path in sorted(a.runtime.glob('pilot*/results.json')):
		pilots.append(dict(path=str(path), sha256=sha(path), observations=read(path)))
	intake = read(a.runtime.parent/'native-current/pm-next-intake.json'); now = datetime.now(timezone.utc)
	result = dict(format='astra-textclass-measured-costs/1', measured_utc=now.isoformat(), intake_utc=intake['created_utc'], elapsed_since_intake_seconds=(now-datetime.fromisoformat(intake['created_utc'])).total_seconds(), final_cold_builds=builds, final_build_active_union_seconds=union(build_intervals), final_build_span_seconds=max(x[1] for x in build_intervals)-min(x[0] for x in build_intervals), final_build_overlap_seconds=sum(x[1]-x[0] for x in build_intervals)-union(build_intervals), qualification_active_union_seconds=union(intervals), qualification_span_seconds=max(x[1] for x in intervals)-min(x[0] for x in intervals), qualification_command_intervals=tests, current_candidate_reused_mutation_costs=reused, retained_development_build_attempts=attempts, retained_native_pilot_attempts=pilots, predecessor_cold_build_observations=dict(O0_seconds=1019.03, O2_seconds=1621.34, O0_peak_RSS_KiB=1732432, O2_peak_RSS_KiB=1740880, provenance='Exact predecessor HISTORY-AND-OPERATIONS.md; overlapping command measurements, not a toolchain speedup baseline'), interpretation='Compiler component cold builds are separate from qualification wall intervals. Qualification includes small application/oracle compilations, native execution, Valgrind, mutation and semantic queries. Parent command intervals are unioned, never added across overlaps. Raw child command timings remain attached. Preliminary semantic-v1 used changing workspace sources and is not final qualification; superseded builds/pilots and all failures remain development observations. Packaging costs are measured separately in the handoff receipt.')
	with a.output.open('x') as out: out.write(json.dumps(result, indent=2)+'\n')
	print('Measured', len(attempts), 'retained build attempts and', len(tests), 'qualification command intervals; overlaps reported explicitly')


if __name__ == '__main__':
	main()
