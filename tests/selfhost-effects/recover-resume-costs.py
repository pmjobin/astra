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
		if not path.is_file() or path.suffix not in ('.time', '.stderr') and path.name != 'time' or path.is_relative_to(leaf):
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
		captured = read(path); inferred_epoch = path.stat().st_mtime-max((row.get('end', 0) for row in captured), default=0)
		for ordinal, row in enumerate(captured):
			if 'start' in row and 'end' in row:
				commands.append(dict(receipt=str(path), receipt_sha256=digest, ordinal=ordinal, name=row.get('name'), argv=row.get('argv'), exit=row.get('exit'), start=row['start'], end=row['end'], inferred_clock_epoch=inferred_epoch))
				# The ordinary LLVM build entry point keeps one receipt per command,
				# rather than commands.json. Include its measured cold-build intervals.
	for path in sorted(paths.RUNTIME.rglob('*.json')):
		if path.is_relative_to(leaf) or any(part.startswith(('handoff-', 'published-verification-')) for part in path.relative_to(paths.RUNTIME).parts): continue
		paired = path.with_suffix('.stdout').is_file() and path.with_suffix('.stderr').is_file()
		acceleration = path.name == 'result.json' and (path.parent/'stdout').is_file() and (path.parent/'stderr').is_file()
		compile_plan = path.name == 'result.json' and path.parent.name.startswith('compile-plan-') and (path.parent/'compile.stdout').is_file() and (path.parent/'compile.stderr').is_file()
		if not paired and not acceleration and not compile_plan: continue
		row = read(path)
		if not isinstance(row, dict): continue
		running = read(path.parent/'running.json') if (acceleration or compile_plan) and (path.parent/'running.json').is_file() else {}
		if compile_plan and 'monotonic_start' in running and 'seconds' in row:
			first = running['monotonic_start']; last = first+row['seconds']
		elif 'monotonic_start' in row and 'monotonic_end' in row:
			first, last = row['monotonic_start'], row['monotonic_end']
		else: continue
		commands.append(dict(receipt=str(path), receipt_sha256=sha(path), ordinal=None, name=path.parent.name if acceleration or compile_plan else path.stem, argv=row.get('argv', running.get('argv')), exit=row.get('exit'), start=first, end=last, inferred_clock_epoch=path.stat().st_mtime-last))
		# A host reboot resets CLOCK_MONOTONIC. Infer separate clock domains from
		# each original receipt's completion mtime and final monotonic endpoint;
		# never merge overlapping numeric timestamps from different boot epochs.
	domains = []
	for row in sorted(commands, key=lambda row: row['inferred_clock_epoch']):
		if not domains or row['inferred_clock_epoch']-domains[-1]['first_inferred_epoch'] > 60:
			domains.append(dict(name='receipt-clock-domain-'+str(len(domains)+1), first_inferred_epoch=row['inferred_clock_epoch'], commands=[]))
		domains[-1]['commands'].append(row); row['clock_domain'] = domains[-1]['name']
	intervals = []
	for domain in domains:
		rows = domain.pop('commands'); domain['command_count'] = len(rows)
		domain['last_inferred_epoch'] = max(row['inferred_clock_epoch'] for row in rows)
		domain['monotonic_interval_union'] = interval_union([(row['start'], row['end']) for row in rows])
		domain['wall_union_seconds'] = sum(last-first for first, last in domain['monotonic_interval_union'])
		intervals.extend(dict(clock_domain=domain['name'], first=first, last=last) for first, last in domain['monotonic_interval_union'])
	builds = []
	for path in sorted(paths.RUNTIME.rglob('*input-identity.json')):
		if path.is_relative_to(leaf) or 'compiler-inputs' in path.parts or 'recipe-inputs' in path.parts:
			continue
		identity = read(path)
		if 'argv' not in identity or str(identity['argv'][0]) != str(C0):
			continue
		compile_plan = path.name == 'input-identity.json' and path.parent.name.startswith('compile-plan-')
		label = 'compile' if compile_plan else path.name.removesuffix('-input-identity.json')
		stdout, stderr = path.parent/(label+'.stdout'), path.parent/(label+'.stderr')
		time_path = path.parent/'compile.time' if compile_plan else stderr
		metrics = next((row for row in measurements if row['path'] == str(time_path)), None)
		target = Path(identity['argv'][-1])
		product = target.with_suffix('.identity.json')
		qualified_product = product.exists() and read(product).get('identity') == identity and target.is_file() and sha(target) == read(product)['sha256']
		actual_receipt = path.parent/'result.json' if compile_plan else path.parent/(label+'.json'); actual = read(actual_receipt) if actual_receipt.exists() else None
		timed_command = re.findall(r'^\s*Command being timed: "(.*)"$', time_path.read_text(errors='replace'), re.M) if time_path.exists() else []
		command = timed_command[0] if timed_command else None
		stage = 'unknown'
		if command and command.startswith(str(C0)+' '):
			if re.search(r'\s-o\s', command) and not re.search(r'\s--dump-[^\s]+', command): stage = 'native'
			for flag, name in [('--dump-semantics', 'semantic'), ('--dump-core', 'Core'), ('--check', 'LLVM-check')]:
				if re.search(r'\s'+re.escape(flag)+r'(?:\s|$)', command): stage = name; break
		observed_product = bool(qualified_product and stage == 'native' and actual and actual.get('exit') == 0 and not actual.get('timed_out'))
		builds.append(dict(input_identity=str(path), input_identity_sha256=sha(path), requested_product_argv=identity['argv'], caller_command_receipt=str(actual_receipt) if actual else None, caller_command=actual, GNU_timed_command_text=command, actual_stage=stage, captured_source_count=len(identity['sources']), metrics=metrics, stdout_sha256=sha(stdout) if stdout.exists() else None, stderr_sha256=sha(stderr) if stderr.exists() else None, matching_product_identity=qualified_product, native_product_observed=observed_product, qualification='Matching sidecars bind product bytes but can also exist after a separate source preflight. Native product credit additionally requires an actual timed native C0 command and a successful caller receipt. The actual GNU-time command, requested argv and caller are separate; transformed semantic/Core/LLVM checks, failed/stopped attempts and unknown commands do not earn native-build credit.'))
	result = dict(status='MEASURED_CONTINUATION_COSTS', GNU_time_measurements=measurements, compiler_attempts=builds, command_intervals=commands, monotonic_clock_domains=domains, completed_command_wall_interval_union=intervals, completed_command_wall_union_seconds=sum(row['wall_union_seconds'] for row in domains), completed_command_durations_sum_seconds=sum(row['end']-row['start'] for row in commands), peak_observed_command_RSS_KiB=max((row['peak_RSS_KiB'] for row in measurements), default=0), limitation='All measured failures, fatal signals, source-only checks and successful commands are retained. GNU time reports actual user/system CPU, elapsed wall and peak RSS for each named process tree. Measurements may contain nested or overlapping process trees; CPU, RSS and wall values are never added and called total session resources. Receipt completion mtimes minus final monotonic endpoints identify separate clock domains within a 60-second tolerance after the host reboot; each domain has its own interval union. This inference is disclosed rather than assigning an uncaptured historical boot UUID. The per-domain wall union differs from the durations sum and excludes unmeasured thinking/idle time. Active attempts have no completed cost/qualification credit. Exact identity reuse is not recompilation or compiler speedup. Earlier R5 costs remain historical in the immutable predecessor report.')
	(leaf/'result.json').write_text(json.dumps(result, indent=2)+'\n')
	print(len(measurements), 'actual GNU time records;', len(builds), 'compiler attempts;', result['completed_command_wall_union_seconds'], 'seconds completed command interval union', flush=True)


if __name__ == '__main__':
	main()
