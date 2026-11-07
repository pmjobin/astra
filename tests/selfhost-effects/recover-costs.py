#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Summarize measured builds/reuse without adding overlapping wall intervals."""
import argparse
import json
from pathlib import Path
import re
from state import ROOT, load_module, read, sha


def time_values(path):
	data = path.read_text(); result = {}
	for key,label in [('user_seconds','User time (seconds)'),('system_seconds','System time (seconds)'),('maximum_RSS_KiB','Maximum resident set size (kbytes)')]:
		match = re.search(re.escape(label)+r':\s*([0-9.]+)',data)
		if match: result[key] = float(match[1]) if key != 'maximum_RSS_KiB' else int(match[1])
	match = re.search(r'Elapsed \(wall clock\) time \(h:mm:ss or m:ss\):\s*([0-9:.]+)',data)
	if match:
		seconds = 0.0
		for part in match[1].split(':'): seconds = seconds*60+float(part)
		result['wall_seconds'] = seconds
	return result


def main():
	p = argparse.ArgumentParser(); p.add_argument('--output',type=Path,required=True); a = p.parse_args(); paths = load_module('recover_cost_paths',ROOT/'tests/selfhost-effects/recover-build.py'); builds = []; reuse = []
	for directory in sorted(paths.RUNTIME.iterdir()):
		if not directory.is_dir(): continue
		if directory.name.startswith('build-'):
			for receipt in sorted(directory.glob('*/commands.json')):
				for row in read(receipt):
					if not row['name'].startswith('typecore-'): continue
					stderr = receipt.parent/(row['name']+'.stderr'); values = time_values(stderr); flags = row['argv']; kind = 'Core check' if '--dump-core' in flags else 'LLVM lowering/verification check' if '--check' in flags else 'Native compiler build'
					builds.append(dict(kind=kind,receipt=str(receipt),receipt_sha256=sha(receipt),stderr_sha256=sha(stderr),exit=row['exit'],monotonic_start=row['start'],monotonic_end=row['end'],**values))
		if directory.name.startswith('full-build-'):
			for receipt in sorted(directory.glob('build-*/ownflow-*.json')):
				if '-input-identity' in receipt.name or '-exact-reuse' in receipt.name: continue
				row = read(receipt)
				if 'argv' not in row: continue
				stderr = receipt.with_suffix('.stderr'); flags = row['argv']; values = time_values(stderr); kind = 'Combined Core check' if '--dump-core' in flags else 'Combined LLVM lowering/verification check' if '--check' in flags else 'Combined native compiler build'; builds.append(dict(kind=kind,receipt=str(receipt),receipt_sha256=sha(receipt),stderr_sha256=sha(stderr),exit=row['exit'],monotonic_start=row['monotonic_start'],monotonic_end=row['monotonic_end'],**values))
		if directory.name.startswith('warm-') and (directory/'result.json').is_file():
			row = read(directory/'result.json')
			if row['status'] == 'EXACT_IDENTITY_REUSE': reuse.append(dict(result=str(directory/'result.json'),result_sha256=sha(directory/'result.json'),measurement=time_values(directory/'time'),**row))
	intervals = sorted((row['monotonic_start'],row['monotonic_end']) for row in builds); union = 0.0; first = None; last = None
	for start,end in intervals:
		if first is None: first,last = start,end
		elif start > last: union += last-first; first,last = start,end
		else: last = max(last,end)
	if first is not None: union += last-first
	result = dict(status='MEASURED_COSTS',builds=builds,exact_product_reuse=reuse,measured_compile_interval_union_seconds=union,measured_compile_interval_sum_seconds=sum(end-start for start,end in intervals),interpretation='Compile intervals overlap. Their sum is not campaign elapsed time, nor a speedup. Core checks, full LLVM checks, native cold builds and identity reuse are distinct. Historical failed checks and explicitly stopped owned process groups retain their own receipts; no resource ceiling was raised. GNU time RSS is per command, not aggregate simultaneous memory.')
	a.output.write_text(json.dumps(result,indent=2)+'\n'); print(len(builds),'measured build/check attempts;',len(reuse),'exact reuse observations',flush=True)


if __name__ == '__main__':
	main()
