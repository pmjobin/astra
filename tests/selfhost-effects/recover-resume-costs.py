#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Keep every actual measurement; overlapping/nested durations are not elapsed time."""
import argparse
import json
from pathlib import Path
import re
from state import ROOT, C0, load_module, read, sha


def elapsed(value):
	parts = value.split(':')
	assert 1 <= len(parts) <= 3
	result = 0.0
	for part in parts:
		result = result * 60 + float(part)
	return result


def interval_union(intervals):
	merged = []
	for first, last in sorted(intervals):
		assert 0 <= first <= last
		if merged and first <= merged[-1][1]:
			merged[-1][1] = max(last, merged[-1][1])
		else:
			merged.append([first, last])
	return merged


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--version', required=True)
	a = p.parse_args()
	assert a.version.isalnum()
	paths = load_module('resume_cost_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	leaf = paths.RUNTIME/('costs-'+a.version)
	leaf.mkdir()
	measurements = []
	patterns = dict(user=r'User time \(seconds\): ([0-9.]+)', system=r'System time \(seconds\): ([0-9.]+)', wall=r'Elapsed \(wall clock\) time \(h:mm:ss or m:ss\): ([0-9:.]+)', RSS=r'Maximum resident set size \(kbytes\): ([0-9]+)', exit=r'Exit status: ([0-9]+)')
	for path in sorted(paths.RUNTIME.rglob('*')):
		if not path.is_file() or path.suffix not in ('.time', '.stderr') or path.is_relative_to(leaf):
			continue
		if any(part.startswith(('handoff-', 'published-verification-')) for part in path.relative_to(paths.RUNTIME).parts):
			continue
		text = path.read_text(errors='replace')
		rows = {key: re.findall(pattern, text) for key, pattern in patterns.items()}
		if not rows['wall']:
			continue
		assert all(len(values) == 1 for values in rows.values()), str(path)
		measurements.append(dict(path=str(path), bytes=path.stat().st_size, sha256=sha(path), user_CPU_seconds=float(rows['user'][0]), system_CPU_seconds=float(rows['system'][0]), wall_seconds=elapsed(rows['wall'][0]), peak_RSS_KiB=int(rows['RSS'][0]), GNU_time_exit=int(rows['exit'][0]), signal=[int(value) for value in re.findall(r'Command terminated by signal ([0-9]+)', text)]))
	commands = []
	for path in sorted(paths.RUNTIME.rglob('commands.json')):
		if path.is_relative_to(leaf) or any(part.startswith(('handoff-', 'published-verification-')) for part in path.relative_to(paths.RUNTIME).parts):
			continue
		digest = sha(path)
		for ordinal, row in enumerate(read(path)):
			if 'start' in row and 'end' in row:
				commands.append(dict(receipt=str(path), receipt_sha256=digest, ordinal=ordinal, name=row.get('name'), argv=row.get('argv'), exit=row.get('exit'), start=row['start'], end=row['end']))
				# The ordinary LLVM build entry point keeps one receipt per command,
				# rather than commands.json. Include its measured cold-build intervals.
	for path in sorted(paths.RUNTIME.rglob('*.json')):
		if path.is_relative_to(leaf) or any(part.startswith(('handoff-', 'published-verification-')) for part in path.relative_to(paths.RUNTIME).parts): continue
		if not path.with_suffix('.stdout').is_file() or not path.with_suffix('.stderr').is_file(): continue
		row = read(path)
		if not isinstance(row, dict) or 'monotonic_start' not in row or 'monotonic_end' not in row: continue
		commands.append(dict(receipt=str(path), receipt_sha256=sha(path), ordinal=None, name=path.stem, argv=row.get('argv'), exit=row.get('exit'), start=row['monotonic_start'], end=row['monotonic_end']))
	intervals = interval_union([(row['start'], row['end']) for row in commands])
	builds = []
	for path in sorted(paths.RUNTIME.rglob('*input-identity.json')):
		if path.is_relative_to(leaf) or 'compiler-inputs' in path.parts or 'recipe-inputs' in path.parts:
			continue
		identity = read(path)
		if 'argv' not in identity or str(identity['argv'][0]) != str(C0):
			continue
		label = path.name.removesuffix('-input-identity.json')
		stdout, stderr = path.parent/(label+'.stdout'), path.parent/(label+'.stderr')
		metrics = next((row for row in measurements if row['path'] == str(stderr)), None)
		target = Path(identity['argv'][-1])
		product = target.with_suffix('.identity.json')
		qualified_product = product.exists() and read(product).get('identity') == identity and target.is_file() and sha(target) == read(product)['sha256']
		actual_receipt = path.parent/(label+'.json'); actual = read(actual_receipt) if actual_receipt.exists() else None
		timed_command = re.findall(r'^\s*Command being timed: "(.*)"$', stderr.read_text(errors='replace'), re.M) if stderr.exists() else []
		builds.append(dict(input_identity=str(path), input_identity_sha256=sha(path), requested_product_argv=identity['argv'], caller_command_receipt=str(actual_receipt) if actual else None, caller_command=actual, GNU_timed_command_text=timed_command[0] if timed_command else None, captured_source_count=len(identity['sources']), metrics=metrics, stdout_sha256=sha(stdout) if stdout.exists() else None, stderr_sha256=sha(stderr) if stderr.exists() else None, matching_product_identity=qualified_product, qualification='A matching sidecar proves the product identity check completed. Caller/requested argv and the GNU-time actual child command text are separate: a task recipe can transform --check to --dump-core after the caller receipt. Missing/mismatched sidecars and failed/stopped checks earn no product credit. Source-only checks are distinct from native builds.'))
	result = dict(status='MEASURED_CONTINUATION_COSTS', GNU_time_measurements=measurements, compiler_attempts=builds, command_intervals=commands, completed_command_wall_interval_union=intervals, completed_command_wall_union_seconds=sum(last-first for first, last in intervals), completed_command_durations_sum_seconds=sum(row['end']-row['start'] for row in commands), peak_observed_command_RSS_KiB=max((row['peak_RSS_KiB'] for row in measurements), default=0), limitation='All measured failures, fatal signals, source-only checks and successful commands are retained. GNU time reports actual user/system CPU, elapsed wall and peak RSS for each named process tree. Measurements may contain nested or overlapping process trees; CPU, RSS and wall values are never added and called total session resources. The merged monotonic command interval union differs from the durations sum and excludes unmeasured thinking/idle time. Active attempts have no completed cost/qualification credit. Exact identity reuse is not recompilation or compiler speedup. Earlier R5 costs remain historical in the immutable predecessor report.')
	(leaf/'result.json').write_text(json.dumps(result, indent=2)+'\n')
	print(len(measurements), 'actual GNU time records;', len(builds), 'compiler attempts;', result['completed_command_wall_union_seconds'], 'seconds completed command interval union', flush=True)


if __name__ == '__main__':
	main()
