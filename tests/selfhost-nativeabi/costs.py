#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Collect actual task measurements, retaining retries and overlap boundaries."""
import argparse
import hashlib
import json
from pathlib import Path
import re


def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--runtime', type=Path, required=True)
	p.add_argument('--output', type=Path, required=True)
	a = p.parse_args()
	root = a.runtime.resolve()
	assert a.output.resolve().is_relative_to(root)
	commands, timed, scalar = {}, {}, []
	for path in sorted(root.rglob('*')):
		if not path.is_file() or path == a.output or path.name == 'initial.json' or any(x in path.relative_to(root).parts for x in ('before', 'handoff', 'report-evidence')):
			continue
		if path.suffix == '.json':
			try:
				value = json.loads(path.read_text())
			except (ValueError, UnicodeError):
				continue
			rows = value if isinstance(value, list) else [value]
			for row in rows:
				if not isinstance(row, dict):
					continue
				if 'argv' in row and 'monotonic_start' in row and 'monotonic_end' in row:
					key = (tuple(row['argv']), row['monotonic_start'], row['monotonic_end'])
					commands[key] = dict(receipt=str(path.relative_to(root)), argv=row['argv'],
						exit=row.get('exit'), start=row['monotonic_start'], end=row['monotonic_end'],
						seconds=row['monotonic_end']-row['monotonic_start'])
				elif 'seconds' in row and 'argv' in row:
					scalar.append(dict(receipt=str(path.relative_to(root)), argv=row['argv'],
						exit=row.get('exit'), seconds=row['seconds'], overlap_unknown=True))
		if path.suffix in ('.time', '.stderr'):
			text = path.read_text(errors='replace')
			if 'Maximum resident set size (kbytes):' not in text:
				continue
				# Separate .time logs take precedence over mirrored stderr reports.
			if path.suffix == '.stderr' and path.with_suffix('.time').exists():
				continue
			def number(pattern):
				match = re.search(pattern, text)
				return float(match[1]) if match else None
			timed[str(path.relative_to(root))] = dict(sha256=sha(path),
				user_seconds=number(r'User time \(seconds\): ([0-9.]+)'),
				system_seconds=number(r'System time \(seconds\): ([0-9.]+)'),
				max_rss_kib=number(r'Maximum resident set size \(kbytes\): (\d+)'),
				wall_text=re.search(r'Elapsed \(wall clock\) time \(h:mm:ss or m:ss\): (\S+)', text)[1])
	intervals = sorted((x['start'], x['end']) for x in commands.values())
	union = []
	for start, end in intervals:
		if union and start <= union[-1][1]:
			union[-1][1] = max(end, union[-1][1])
		else:
			union.append([start, end])
	result = dict(format='astra-nativeabi-costs/1', commands=list(commands.values()),
		unplaced_measurements=scalar, GNU_time_logs=timed,
		measured_command_sum_seconds=sum(x['seconds'] for x in commands.values()),
		measured_active_wall_union_seconds=sum(end-start for start, end in union),
		user_seconds=sum(x['user_seconds'] or 0 for x in timed.values()),
		system_seconds=sum(x['system_seconds'] or 0 for x in timed.values()),
		largest_process_rss_kib=max((x['max_rss_kib'] or 0 for x in timed.values()), default=0),
		limits=['Monotonic command intervals measure active commands, not total human/session elapsed time.',
		'Unplaced seconds lack monotonic boundaries and are excluded from overlap union.',
		'RSS is largest individual measured process, not simultaneous campaign peak.',
		'Task receipts include failed attempts and development trials; historical predecessor logs are not fresh costs.',
		'API token usage and dollar charges are not exposed to this session.'])
	a.output.write_text(json.dumps(result, indent=2)+'\n')
	print(len(commands), 'measured command intervals;', len(timed), 'CPU/RSS receipts')


if __name__ == '__main__':
	main()
