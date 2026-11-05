#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Report actual build intervals/RSS and qualification unions without summing overlaps."""
import argparse
import json
from pathlib import Path
import re
from state import RUNTIME, read, sha


def merged(intervals):
	result = []
	for start, end in sorted(intervals):
		if result and start <= result[-1][1]: result[-1][1] = max(result[-1][1], end)
		else: result.append([start, end])
	return result


def union(intervals):
	return sum(end-start for start, end in merged(intervals))


def main():
	p = argparse.ArgumentParser(); p.add_argument('--output', type=Path, required=True); a = p.parse_args(); assert a.output.resolve().is_relative_to(RUNTIME)
	builds = []
	for path in sorted(RUNTIME.glob('*/build-*/ownflow-O[02].json')):
		row = read(path); stderr = path.with_suffix('.stderr'); text = stderr.read_text(); argv = row['argv']
		peak = re.search(r'Maximum resident set size \(kbytes\): (\d+)', text)
		elapsed = re.search(r'Elapsed \(wall clock\) time \(h:mm:ss or m:ss\): ([\d:.]+)', text)
		builds.append(dict(receipt=str(path), receipt_sha256=sha(path), argv=argv, exit=row['exit'], monotonic_start=row['monotonic_start'], monotonic_end=row['monotonic_end'], seconds=row['monotonic_end']-row['monotonic_start'], peak_RSS_KiB=int(peak.group(1)) if peak else None, GNU_time_elapsed=elapsed.group(1) if elapsed else None, stderr_sha256=sha(stderr), final_candidate=path.parent.parent.name in ('native-v5-O0', 'native-v5-O2')))
		# The source-ledger builder writes its receipts directly in its runtime leaf.
	for leaf in sorted(RUNTIME.glob('ledger-v*-original')):
		for row in read(leaf/'commands.json'):
			if row['name'] != 'ownflow-O0': continue
			stderr = leaf/'ownflow-O0.stderr'; text = stderr.read_text(); peak = re.search(r'Maximum resident set size \(kbytes\): (\d+)', text)
			builds.append(dict(receipt=str(leaf/'commands.json'), receipt_sha256=sha(leaf/'commands.json'), argv=row['argv'], exit=row['exit'], monotonic_start=row['monotonic_start'], monotonic_end=row['monotonic_end'], seconds=row['monotonic_end']-row['monotonic_start'], peak_RSS_KiB=int(peak.group(1)) if peak else None, stderr_sha256=sha(stderr), final_candidate=False, classification='independent source-ledger consumer'))
	final = [row for row in builds if row['final_candidate']]; assert len(final) == 2 and all(row['exit'] == 0 for row in final)
	qualification = []
	for group, mode, gate in [('qualification-final', 'O0', 'new'), *[('qualification-v5', 'O0', gate) for gate in ('mutations', 'negative', 'predecessor-text', 'predecessor-native', 'faults')], *[('qualification-final', 'O2', gate) for gate in ('new', 'mutations', 'negative', 'predecessor-text', 'predecessor-native', 'faults')]]:
		leaf = RUNTIME/group/(gate+'-'+mode); result = read(leaf/'result.json'); assert result['status'] == 'PASS'
		for row in read(leaf/'commands.json'): qualification.append(dict(**row, gate=gate, mode=mode, receipt=str(leaf/'commands.json')))
	build_intervals = [(r['monotonic_start'], r['monotonic_end']) for r in builds]
	final_intervals = [(r['monotonic_start'], r['monotonic_end']) for r in final]
	gate_intervals = [(r['monotonic_start'], r['monotonic_end']) for r in qualification]
	oracles = []
	for leaf in ['frozen', 'frozen-v2', 'supplemental-v1', 'supplemental-growth-v1', 'operation-v1']:
		path = RUNTIME/leaf/'commands.json'
		if path.exists():
			for row in read(path):
				if 'monotonic_start' in row: oracles.append(dict(**row, receipt=str(path)))
	warm = []
	for path in sorted(RUNTIME.glob('warm-v5-*/build-*/ownflow-*-exact-reuse.json')): warm.append(dict(path=str(path), sha256=sha(path), **read(path)))
	assert len(warm) == 2
	result = dict(format='astra-indexpath-measured-costs/1', final_builds=final, all_recorded_build_attempts=builds, all_build_active_union_seconds=union(build_intervals), final_build_active_union_seconds=union(final_intervals), final_build_interval_span_seconds=max(e for s, e in final_intervals)-min(s for s, e in final_intervals), qualification=qualification, qualification_active_union_seconds=union(gate_intervals), qualification_interval_span_seconds=max(e for s, e in gate_intervals)-min(s for s, e in gate_intervals), final_build_qualification_overlap_seconds=union(final_intervals)+union(gate_intervals)-union(final_intervals+gate_intervals), final_build_and_qualification_active_union_seconds=union(final_intervals+gate_intervals), oracle_commands=oracles, oracle_active_union_seconds=union([(r['monotonic_start'], r['monotonic_end']) for r in oracles]), exact_warm_reuse=warm, recipe_sha256=sha(__file__), limitation='RSS is each actual GNU time process peak, not an aggregate parallel peak. Gate command intervals enclose their child native/C0/LLVM/layout/Valgrind work; nested child times must not be added again. Full session elapsed also includes investigation, failed attempts, formatting, packaging and pauses. Historical costs are not substituted for current measurements.')
	a.output.write_text(json.dumps(result, indent=2)+'\n'); print('Final build union', result['final_build_active_union_seconds'], 'qualification union', result['qualification_active_union_seconds'], 'overlap', result['final_build_qualification_overlap_seconds'])


if __name__ == '__main__':
	main()
