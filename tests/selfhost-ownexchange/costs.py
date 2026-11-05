#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Report actual build/test intervals, CPU/RSS, overlap and exact reuse."""
import argparse
import json
from pathlib import Path
import re
from state import RUNTIME, BUILD, read, sha


def union(intervals):
	end = None; total = 0.0
	for first, last in sorted(tuple(row) for row in intervals):
		if end is None or first > end: total += last - first
		else: total += max(0.0, last - end)
		end = last if end is None else max(end, last)
	return total


def metrics(path):
	text = path.read_text(errors='replace') if path.exists() else ''
	result = {}
	for key, pattern, convert in [('user_CPU_seconds', r'User time \(seconds\): ([0-9.]+)', float), ('system_CPU_seconds', r'System time \(seconds\): ([0-9.]+)', float), ('peak_RSS_KiB', r'Maximum resident set size \(kbytes\): (\d+)', int), ('GNU_time_elapsed', r'Elapsed \(wall clock\) time \(h:mm:ss or m:ss\): (.+)', str)]:
		match = re.search(pattern, text); result[key] = convert(match[1]) if match else None
	return result


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', required=True); p.add_argument('--output', type=Path, required=True); a = p.parse_args()
	builds = []
	for path in sorted(RUNTIME.glob('*/build-*/ownflow-*.json')):
		if path.name.endswith(('-input-identity.json', '-exact-reuse.json')): continue
		row = read(path)
		if 'argv' not in row: continue
		builds.append(dict(**row, **metrics(path.with_suffix('.stderr')), receipt=str(path), receipt_sha256=sha(path), classification='final' if path.parent.parent.name in ('native-'+a.version+'-O0', 'native-'+a.version+'-O2') else 'diagnostic or superseded'))
	for path in sorted(RUNTIME.glob('ledger-*-original/commands.json')):
		for row in read(path):
			if row['name'] == 'ownflow-O0': builds.append(dict(**row, **metrics(path.parent/'ownflow-O0.stderr'), receipt=str(path), receipt_sha256=sha(path), classification='source-ledger component'))
	final = [row for row in builds if row['classification'] == 'final']; assert len(final) == 2 and all(row['exit'] == 0 for row in final)
	gates = []; children = []
	for path in sorted(RUNTIME.rglob('commands.json')):
		if path.parent.name.startswith(('source-', 'ledger-')) or '/build-' in str(path): continue
		for row in read(path):
			argv = row.get('argv', []); start = row.get('monotonic_start', row.get('start')); end = row.get('monotonic_end', row.get('end'))
			entry = dict(**row, receipt=str(path), receipt_sha256=sha(path), timing=metrics(path.parent/(row['name']+'.time')) if 'name' in row else {})
			if path.parent.name.startswith('final-'+a.version+'-') and start is not None and end is not None: gates.append(dict(**entry, interval=[start,end]))
			application = bool(argv) and Path(argv[0]).is_relative_to(BUILD) and not Path(argv[0]).name.startswith('astra-llvm-') and not any(str(v).startswith(('--classstorage-', '--class-storage')) for v in argv[1:])
			if argv and ('valgrind' in str(argv[0]) or application or row.get('name','').endswith(('-native-execute','-C0-execute'))):
				entry['classification'] = 'final' if path.relative_to(RUNTIME).parts[0].startswith('final-'+a.version+'-') else 'diagnostic or independent oracle'
				entry['mode'] = path.relative_to(RUNTIME).parts[0][-2:] if path.relative_to(RUNTIME).parts[0].endswith(('O0', 'O2')) else 'mixed oracle profiles'
				children.append(entry)
	build_intervals = [(r['monotonic_start'],r['monotonic_end']) for r in builds]; final_intervals = [(r['monotonic_start'],r['monotonic_end']) for r in final]; gate_intervals = [row['interval'] for row in gates]
	warm = [dict(path=str(path), sha256=sha(path), receipt=read(path)) for path in sorted(RUNTIME.glob('warm-'+a.version+'-*/build-*/ownflow-*-exact-reuse.json'))]
	oracles = []
	for path in sorted(RUNTIME.rglob('*.time')):
		if path.parent.name.startswith(('corpus-', 'family-', 'twins-', 'extras-', 'negative-oracles')):
			oracles.append(dict(path=str(path), sha256=sha(path), **metrics(path)))
	child_path = a.output.with_name('measured-child-processes.json'); child_path.write_text(json.dumps(children, indent=2)+'\n')
	child_totals = {}
	for row in children:
		key = row['classification']+'/'+row['mode']+('/Valgrind' if 'valgrind' in str(row['argv'][0]) else '/application execution')
		group = child_totals.setdefault(key, dict(processes=0, summed_process_wall_seconds=0.0, user_CPU_seconds=0.0, system_CPU_seconds=0.0, peak_individual_RSS_KiB=0))
		group['processes'] += 1; group['summed_process_wall_seconds'] += row.get('seconds', row.get('end', 0)-row.get('start', 0))
		for metric in ('user_CPU_seconds', 'system_CPU_seconds'): group[metric] += row['timing'].get(metric) or 0.0
		group['peak_individual_RSS_KiB'] = max(group['peak_individual_RSS_KiB'], row['timing'].get('peak_RSS_KiB') or 0)
	result = dict(format='astra-ownexchange-costs/1', final_builds=final, all_recorded_build_attempts=builds, incomplete_build=read(RUNTIME/'interrupted-v6-O0.json'), all_build_active_union_seconds=union(build_intervals), final_build_active_union_seconds=union(final_intervals), final_gate_commands=gates, final_gate_active_union_seconds=union(gate_intervals), final_build_gate_overlap_seconds=union(final_intervals)+union(gate_intervals)-union(final_intervals+gate_intervals), combined_final_active_union_seconds=union(final_intervals+gate_intervals), runtime_and_Valgrind_children=dict(path=str(child_path), sha256=sha(child_path), processes=len(children), totals=child_totals, limitation="These are sums of individual process wall times, not exclusive session wall or active unions."), independent_oracle_process_measurements=oracles, C0_contract=metrics(RUNTIME/'C0-contract/qualification.time'), exact_warm_reuse=warm, limitation='CPU/RSS are actual process-tree GNU time measurements when present. The interrupted v6 O0 attempt has no completion measurements and is excluded from numeric totals. Nested gate/child durations are never added as exclusive wall. Initial family-v1 C0 pilot lacks per-child time receipts; its tool wall was 0.642 s and later family-v2 reruns are separately measured. Full session also includes investigation, editing and packaging; historical build costs are not substituted for current work.')
	a.output.write_text(json.dumps(result, indent=2)+'\n'); print('Final build union', result['final_build_active_union_seconds'], 's; gate union', result['final_gate_active_union_seconds'], 's')


if __name__ == '__main__':
	main()
