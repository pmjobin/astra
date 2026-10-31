#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Trace relocated opaque consumers and instrument qualified emitted A operations."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	for name in ['qualification', 'build', 'runtime']: parser.add_argument(name, type=Path)
	args = parser.parse_args(); qualified = json.loads(args.qualification.read_text())
	assert qualified['status'] == 'PASS' and qualified['source_unchanged_during_qualification']
	for path in [args.build, args.runtime]:
		assert not path.resolve().is_relative_to(ROOT); path.mkdir(parents=True, exist_ok=True)
	build = Path(tempfile.mkdtemp(prefix='A-instrument-', dir=args.build.resolve()))
	runtime = Path(tempfile.mkdtemp(prefix='A-instrument-', dir=args.runtime.resolve()))
	oracle = runpy.run_path(str(Path(__file__).with_name('application-a.py')))['oracle']
	receipt = dict(qualification_sha256=sha(args.qualification), source_snapshot=qualified['source_snapshot'],
		inputs={str(Path(__file__).relative_to(ROOT)): sha(Path(__file__))}, commands=[], products={}, traces={}, status='RUNNING',
		coverage='All emitted consumer/library LLVM functions and C providers are instrumented. Exact opaque leaf/middle objects and static liburing are unchanged and outside compiler instrumentation; full native products separately run under unsuppressed Memcheck.')
	def save(): (runtime / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	def run(command, env=None, cwd=ROOT):
		command = list(map(str, command)); started = time.monotonic()
		p = subprocess.run(command, cwd=cwd, text=True, capture_output=True, timeout=90,
			env=dict(os.environ, LC_ALL='C', DEBUGINFOD_URLS='', **(env or {})))
		row = dict(command=command, cwd=str(cwd), environment=env or {}, exit=p.returncode, stdout=p.stdout, stderr=p.stderr, seconds=time.monotonic()-started)
		receipt['commands'].append(row); save(); assert p.returncode == 0 and not p.stderr, row
		return p.stdout
	try:
		for profile in qualified['profiles']:
			for mode in ['off', 'on']:
				name = profile + '-' + mode; case = build / name; case.mkdir()
				product = qualified['products'][profile + '-base-O2-strict-native-' + mode]
				complete = json.loads(Path(product['receipt']).read_text()); assert sha(Path(product['receipt'])) == product['build_receipt_sha256']
				compiler = Path(complete['compiler']['path']); assert sha(compiler) == qualified['compiler_sha256']
				command = next(row['command'] for row in complete['commands'] if row['command'][0] == str(compiler) and '-o' in row['command'] and '-c' not in row['command'])
				# Copy every source/vapi input into a task SDK. Producer implementation
				# copies were already removed by the qualified build recipe.
				sdk = runtime / (name + '-sdk'); sdk.mkdir(); copied = {}
				for argument in command[1:]:
					path = Path(argument)
					if not path.is_file() or path.suffix not in ['.astra', '.vapi', '.asti']: continue
					destination = sdk / (path.relative_to(ROOT) if path.is_relative_to(ROOT) else Path(path.name))
					destination.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(path, destination); copied[argument] = str(destination)
					if path.suffix == '.asti': shutil.copyfile(path.with_suffix('.o'), destination.with_suffix('.o'))
				for unit in ['leaf', 'middle']:
					assert not Path(complete['products'][unit]['producer_input']).exists()
				relocated = [copied.get(argument, argument) for argument in command]
				relocated[-1] = str(case / 'relocated'); trace = runtime / (name + '-opens.log')
				environment = dict(ASTRA_TEST_OPTIMIZATIONS=mode, ASTRA_EXPLAIN_OPTIMIZATIONS='1')
				run(['strace', '-f', '-e', 'trace=openat,openat2', '-o', trace, *relocated], environment, sdk)
				opened = trace.read_text(); assert str(ROOT) not in opened
				for unit in ['leaf', 'middle']: assert complete['products'][unit]['producer_input'] not in opened
				receipt['traces'][name] = dict(path=str(trace), sha256=sha(trace), bytes=trace.stat().st_size, checkout_source_opens=False, removed_producer_opens=False)
				output = case / 'relocated.bin'
				launch = [case / 'relocated'] + ([runtime / (name + '-relocated.pcm')] if profile == 'uring' else [])
				run(launch, dict(ASTRA_TELEMETRY_SAMPLES='3001', ASTRA_TELEMETRY_WINDOW='31', ASTRA_TELEMETRY_SEED='43', ASTRA_TELEMETRY_OUTPUT=str(output)), sdk)
				assert output.read_bytes() == oracle(3001, 31, 43)
				target = dict(line.split('=', 1) for line in run([compiler, '--target-info']).splitlines() if '=' in line)
				raw = Path(product['product']).with_suffix('.ll'); assert sha(raw) == complete['products']['application']['ir_sha256']
				for sanitizer in ['address', 'thread']:
					stem = case / sanitizer
					attribute = 'sanitize_thread' if sanitizer == 'thread' else 'sanitize_address'
					code = re.sub(r'^target (?:datalayout|triple) = .*\n', '', raw.read_text(), flags=re.M)
					code = re.sub(r'^(define .*?)\s*\{\s*$', rf'\1 {attribute} {{', code, flags=re.M)
					code = f'target datalayout = "{target["data-layout"]}"\ntarget triple = "{target["target"]}"\n' + code
					ir = stem.with_suffix('.ll'); modified = stem.with_suffix('.instrumented.ll'); obj = stem.with_suffix('.o'); ir.write_text(code)
					passes = 'default<O1>,tsan-module,function(tsan)' if sanitizer == 'thread' else 'default<O1>,asan'
					run(['opt', '-passes=' + passes, '-S', ir, '-o', modified])
					instrumented = modified.read_text()
					assert ('__tsan_read' in instrumented and '__tsan_write' in instrumented) if sanitizer == 'thread' else '__asan_report' in instrumented
					run(['llc', '-O1', '-filetype=obj', '-relocation-model=pic', modified, '-o', obj])
					flags = ['-fsanitize=' + ('thread' if sanitizer == 'thread' else 'address,undefined'), '-fno-omit-frame-pointer']
					providers = []
					for row in complete['commands']:
						original = row['command']
						if original[0] not in ['cc', 'clang'] or '-c' not in original: continue
						destination = case / (sanitizer + '-' + Path(original[-1]).name)
						compile_command = ['clang', *flags, *['-O1' if a == '-O2' else a for a in original[1:-1]], destination]
						run(compile_command); providers.append(destination)
					objects = [Path(product['product']).parent / (unit + '.o') for unit in ['leaf', 'middle']]
					archives = [Path(argument) for argument in command if argument.endswith('.a')]
					run(['clang', '-O1', '-g', '-pthread', *flags, obj, *providers, *objects, *archives, '-o', stem])
					results = []
					for count, window, seed in [(3001, 31, 43), (48013, 64, 91)]:
						output = case / (sanitizer + str(count) + '.bin')
						env = dict(ASTRA_TELEMETRY_SAMPLES=str(count), ASTRA_TELEMETRY_WINDOW=str(window), ASTRA_TELEMETRY_SEED=str(seed), ASTRA_TELEMETRY_OUTPUT=str(output),
							ASTRA_TELEMETRY_WORKERS='4', ASTRA_TELEMETRY_GRANULARITY='13', ASTRA_TELEMETRY_BARRIER='1', ASTRA_TELEMETRY_IDLE_TICKS='0',
							ASAN_OPTIONS='detect_leaks=1:halt_on_error=1', UBSAN_OPTIONS='halt_on_error=1', TSAN_OPTIONS='halt_on_error=1')
						launch = [stem] + ([runtime / (name + '-' + sanitizer + '.pcm')] if profile == 'uring' else [])
						text = run(launch, env); assert output.read_bytes() == oracle(count, window, seed)
						results.append(dict(samples=count, stdout=text, output_sha256=sha(output)))
					receipt['products'][name + '-' + sanitizer] = dict(path=str(stem), sha256=sha(stem), raw_ir_sha256=sha(raw), instrumented_ir_sha256=sha(modified), executions=results); save()
		assert all(sha(ROOT / name) == digest for name, digest in receipt['source_snapshot'].items())
		assert all(sha(ROOT / name) == digest for name, digest in receipt['inputs'].items())
		receipt.update(status='PASS', source_unchanged_during_qualification=True)
	finally:
		if receipt['status'] != 'PASS': receipt['status'] = 'FAIL'
		save()
	print(runtime / 'checks.json')


if __name__ == '__main__': main()
