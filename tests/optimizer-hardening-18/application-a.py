#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Source-bound application A variants, native/local linkage and runtime profiles."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import statistics
import struct
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / 'examples/optimizer-hardening-18'


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def oracle(samples, window, seed):
	def sample(index):
		value = (index ^ (seed * 0x9e3779b9)) & 0xffffffff
		value = ((value ^ (value >> 16)) * 0x7feb352d) & 0xffffffff
		value = ((value ^ (value >> 15)) * 0x846ca68b) & 0xffffffff
		value ^= value >> 16
		return ((value & 65535) - 32768) / 32768.0
	output = [0.0] * samples
	for sequence, start in enumerate(range(0, samples, window)):
		if sequence % 97 == 96: continue
		count = min(window, samples - start)
		gain = (0.5 + (sequence % 7) * 0.03125) + 0.25
		affine = [sample(start + index) * gain + 0.0625 for index in range(count)]
		z1 = z2 = 0.0
		for index in range(count):
			filtered = 0.0
			for tap, weight in enumerate([0.125, 0.25, 0.25, 0.25, 0.125]):
				filtered = filtered + weight * (affine[index - tap] if tap <= index else 0.0)
			value = 0.5 * filtered + z1
			z1 = (0.25 * filtered - (-0.25) * value) + z2
			z2 = 0.125 * filtered - 0.125 * value
			output[start + index] = value * (0.25 if sequence % 2 else 0.5)
	return struct.pack('<' + 'd' * samples, *output)


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	for name in ['compiler', 'build', 'runtime']: parser.add_argument(name, type=Path)
	parser.add_argument('--profiles', nargs='+', choices=['sequential', 'threaded', 'uring'], default=['sequential'])
	parser.add_argument('--uring-prefix', type=Path)
	args = parser.parse_args()
	compiler = args.compiler.resolve(strict=True)
	for path in [args.build, args.runtime]:
		assert not path.resolve().is_relative_to(ROOT); path.mkdir(parents=True, exist_ok=True)
	build = Path(tempfile.mkdtemp(prefix='application-A-', dir=args.build.resolve()))
	runtime = Path(tempfile.mkdtemp(prefix='application-A-', dir=args.runtime.resolve()))
	production = [ROOT / name for name in subprocess.check_output(['git', 'ls-files', '-z', '--', 'bootstrap', 'lib', 'tools', 'meson.build', 'meson.options'], cwd=ROOT).decode().split('\0') if name]
	production += [path for path in APP.rglob('*') if path.is_file()]
	inputs = [Path(__file__).resolve(), *production]
	receipt = dict(compiler_sha256=sha(compiler), source_snapshot={str(p.relative_to(ROOT)): sha(p) for p in inputs},
		profiles=args.profiles, commands=[], products={}, comparisons=[], status='RUNNING')
	def save(): (runtime / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	def run(command, env=None, stderr=False, timeout=120):
		command = list(map(str, command)); started = time.monotonic()
		p = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=timeout,
			env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1', DEBUGINFOD_URLS='', **(env or {})))
		row = dict(command=command, environment=env or {}, exit=p.returncode, stdout=p.stdout, stderr=p.stderr, seconds=time.monotonic()-started)
		receipt['commands'].append(row); save(); assert p.returncode == 0 and (stderr or not p.stderr), row
		return p.stdout
	cache = {}
	def execute(product, name, count=48013, window=31, seed=17, workers=2, granularity=1, barrier=0, memory=False):
		output = build / (name + '.bin')
		env = dict(ASTRA_TELEMETRY_SAMPLES=str(count), ASTRA_TELEMETRY_WINDOW=str(window), ASTRA_TELEMETRY_SEED=str(seed),
			ASTRA_TELEMETRY_WORKERS=str(workers), ASTRA_TELEMETRY_GRANULARITY=str(granularity), ASTRA_TELEMETRY_BARRIER=str(barrier),
			ASTRA_TELEMETRY_IDLE_TICKS='0', ASTRA_TELEMETRY_OUTPUT=str(output))
		launch = [product['product']]
		if product['profile'] == 'uring': launch += [runtime / (name + '.pcm')]
		if memory: launch = ['valgrind', '--quiet', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--errors-for-leak-kinds=all', *launch]
		stdout = run(launch, env)
		match = re.search(r'telemetry18 samples=(\d+) windows=(\d+) emitted=(\d+) failed=(\d+) allocations=(\d+) retired=(\d+) kernel_ns=(\d+) max_error=(\S+)', stdout)
		assert match, stdout
		keys = ['samples', 'windows', 'emitted', 'failed', 'allocations', 'retired', 'kernel_ns']
		row = dict(zip(keys, map(int, match.groups()[:-1]))); row['maximum_error'] = float.fromhex(match[8])
		frames = (count + window - 1) // window + 1
		assert row['samples'] == count and row['windows'] == frames and row['retired'] == frames * (4 if product['variant'] in ['state', 'escape'] else 3), row
		key = (count, window, seed)
		if key not in cache: cache[key] = oracle(count, window, seed)
		expected = cache[key]
		actual = output.read_bytes(); assert len(actual) == len(expected)
		if product['policy'] == 'strict': assert actual == expected, (name, sha(output))
		else:
			for index, (a, b) in enumerate(zip(struct.unpack('<' + 'd' * count, actual), struct.unpack('<' + 'd' * count, expected))):
				length = min(window, count - (index // window) * window)
				assert abs(a - b) <= 2**-36 * (1 + length), (name, index, a, b)
		row.update(output_sha256=sha(output), name=name, memory=memory, workers=workers, granularity=granularity)
		if memory: row['allocation_counter_is_native_measurement'] = False
		product.setdefault('executions', []).append(row); save(); return row
	configurations = []
	for profile in args.profiles:
		variants = ['base', 'renamed', 'state', 'fields', 'helpers', 'third', 'branch', 'escape'] if profile == 'sequential' else ['base']
		for variant in variants:
			for level in '012': configurations.append((profile, variant, level, 'strict', 'native'))
		for level in '012': configurations.append((profile, 'base', level, 'contract', 'native'))
		if profile == 'sequential':
			for level in '012': configurations.append((profile, 'base', level, 'strict', 'local'))
	try:
		for profile, variant, level, policy, layout in configurations:
			pair = {}
			for mode in ['off', 'on']:
				name = '-'.join([profile, variant, 'O' + level, policy, layout, mode])
				command = ['python3', APP / 'build-telemetry.py', '--compiler', compiler, '--build', build, '--runtime', runtime,
					'--profile', profile, '--variant', variant, '--optimization', level, '--facts', mode, '--policy', policy, '--layout', layout]
				if profile == 'uring':
					assert args.uring_prefix is not None; command += ['--uring-prefix', args.uring_prefix.resolve(strict=True)]
				product = json.loads(run(command)); complete = json.loads(Path(product['receipt']).read_text())
				product['build_receipt_sha256'] = sha(Path(product['receipt']))
				details = {key: complete[key] for key in ['configuration', 'compiler', 'inputs', 'rendered_inputs', 'products', 'stack_claims', 'exact_claims', 'shared_claims', 'status']}
				product.update(profile=profile, variant=variant, policy=policy, mode=mode, level=level, layout=layout, details=details)
				receipt['products'][name] = product; save()
				indices = sorted(int(re.search(r'storage=#(\d+)', line)[1]) for line in details['stack_claims'])
				assert indices == ([0, 1, 2, 3, 5] if variant == 'state' else [0, 1, 2, 3]), (name, indices)
				assert len(details['exact_claims']) >= 1 and len(details['shared_claims']) == 1, name
				ir = Path(product['product']).with_suffix('.ll').read_text()
				assert not re.search(r'\b(?:fadd|fsub|fmul|fdiv|fcmp)\s+(?:fast|reassoc|nnan|ninf|nsz|arcp|afn)\b', ir), name
				if policy == 'contract': assert re.search(r'\b(?:fadd|fmul)\s+contract\b', ir), name
				pair[mode] = product
				for count, window, seed in [(7, 16, 17), (3001, 31, 43), (48013, 64, 91)]:
					execute(product, name + f'-n{count}', count, window, seed)
				execute(product, name + '-memory', 3001, 31, 17, memory=True)
			if layout == 'native':
				for unit in ['leaf', 'middle']:
					for kind in ['interface_sha256', 'object_sha256']:
						assert pair['off']['details']['products'][unit][kind] == pair['on']['details']['products'][unit][kind], (profile, variant, unit, kind)
			for off, on in zip(pair['off']['executions'], pair['on']['executions']):
				assert off['output_sha256'] == on['output_sha256'] or policy == 'contract', (off, on)
				if not off['memory']:
					assert off['allocations'] - on['allocations'] == off['windows'] * (5 if variant == 'state' else 4), (off, on)
				receipt['comparisons'].append(dict(configuration=[profile, variant, level, policy, layout], off=off, on=on)); save()
		assert sha(compiler) == receipt['compiler_sha256']
		assert all(sha(ROOT / name) == digest for name, digest in receipt['source_snapshot'].items())
		receipt['source_unchanged_during_qualification'] = True; receipt['status'] = 'PASS'
	finally:
		if receipt['status'] != 'PASS': receipt['status'] = 'FAIL'
		save()
	print(runtime / 'checks.json')


if __name__ == '__main__': main()
