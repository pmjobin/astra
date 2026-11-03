#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Measured command intervals and build costs; no inferred currency/token costs."""
import argparse
import json
from pathlib import Path
import re


def union(intervals):
	end = 0.0; total = 0.0
	for start,finish in sorted(intervals):
		if finish > end:
			total += finish-max(start,end); end = finish
	return total


def timed(text):
	result = {}
	for key,pattern in [('user_seconds',r'User time \(seconds\): ([\d.]+)'),('system_seconds',r'System time \(seconds\): ([\d.]+)'),('peak_rss_kib',r'Maximum resident set size \(kbytes\): (\d+)')]:
		match = re.search(pattern,text)
		if match:
			result[key] = float(match[1]) if key != 'peak_rss_kib' else int(match[1])
	wall = re.search(r'Elapsed \(wall clock\) time \(h:mm:ss or m:ss\): ([\d:.]+)',text)
	if wall:
		parts = list(map(float,wall[1].split(':')))
		result['wall_seconds'] = sum(value*60**i for i,value in enumerate(reversed(parts)))
	return result


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--runtime',type=Path,required=True)
	a = p.parse_args()
	rows = []
	for path in sorted(a.runtime.glob('build-*/build-*/ownflow-*.json')):
		if path.name.endswith('-input-identity.json'):
			continue
		d = json.loads(path.read_text())
		if 'monotonic_start' not in d:
			continue
		row = dict(receipt=str(path),exit=d['exit'],seconds=d['monotonic_end']-d['monotonic_start'],start=d['monotonic_start'],end=d['monotonic_end'],**timed(path.with_suffix('.stderr').read_text()))
		row['kind'] = 'check' if '--dump-cfg' in d['argv'] or '--check' in d['argv'] else 'native-build'
		row['accepted_identity'] = (path.parent/'products.json').is_file()
		row['classification'] = 'CHECK_COMPLETE' if row['kind'] == 'check' and d['exit'] == 0 else 'ACCEPTED_BUILD' if row['accepted_identity'] and d['exit'] == 0 else 'FAILED_OR_UNQUALIFIED'
		row['process_exit_is_not_qualification'] = True
		rows.append(row)
	command_groups = []
	for path in sorted(a.runtime.glob('*/commands.json')):
		data = json.loads(path.read_text())
		intervals = [(d['monotonic_start'],d['monotonic_end']) for d in data if 'monotonic_start' in d and 'monotonic_end' in d]
		command_groups.append(dict(path=str(path),commands=len(data),sum_seconds=sum(b-a for a,b in intervals),union_seconds=union(intervals)))
	reuse = []
	for path in sorted(a.runtime.glob('warm-*/build-*/*-exact-reuse.json')):
		reuse.append(dict(path=str(path),**json.loads(path.read_text())))
	warm_measurements = {path.stem:timed(path.read_text()) for path in sorted(a.runtime.glob('warm-*.time'))}
	result = dict(warm_measurements=warm_measurements,build_attempts=rows,build_command_sum_seconds=sum(x['seconds'] for x in rows),build_overlap_union_seconds=union((x['start'],x['end']) for x in rows),command_groups=command_groups,warm_exact_reuse=reuse,limitations=['Peak RSS is per command; it is not a sum of concurrent peaks.','Intervals cover measured commands, not model reasoning or approval wait.','API token usage and currency cost were not exposed by this session.','SSA-11 timing numbers remain historical and are not a claimed LLVM speedup.'])
	(a.runtime/'costs.json').write_text(json.dumps(result,indent=2)+'\n')
	print(len(rows),'measured build/check attempts;',len(reuse),'exact warm reuse receipts')


if __name__ == '__main__':
	main()
