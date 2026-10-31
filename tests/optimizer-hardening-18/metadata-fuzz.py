#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Seeded, resealed malformed native metadata and ELF framing under real limits."""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import random
import resource
import runpy
import signal
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def limits():
	resource.setrlimit(resource.RLIMIT_AS, (512 * 1024**2, 512 * 1024**2))
	resource.setrlimit(resource.RLIMIT_CPU, (6, 6))
	resource.setrlimit(resource.RLIMIT_FSIZE, (16 * 1024**2, 16 * 1024**2))
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	for name in ['compiler', 'build', 'runtime']: parser.add_argument(name, type=Path)
	args = parser.parse_args(); compiler = args.compiler.resolve(strict=True)
	for path in [args.build, args.runtime]:
		assert not path.resolve().is_relative_to(ROOT); path.mkdir(parents=True, exist_ok=True)
	build = Path(tempfile.mkdtemp(prefix='metadata-fuzz-', dir=args.build.resolve()))
	runtime = Path(tempfile.mkdtemp(prefix='metadata-fuzz-', dir=args.runtime.resolve()))
	codec = runpy.run_path(str(ROOT / 'tests/structural-generics-15/units.py'))
	inputs = [Path(__file__).resolve(), ROOT / 'tests/structural-generics-15/units.py', ROOT / 'examples/optimizer-hardening-18/telemetry-leaf.astra']
	receipt = dict(seed=180029, compiler_sha256=sha(compiler), load_before=os.getloadavg(), affinity=sorted(os.sched_getaffinity(0)),
		inputs={str(p.relative_to(ROOT)): sha(p) for p in inputs},
		limits=dict(address_space_bytes=512*1024**2, cpu_seconds=6, wall_seconds=8, file_bytes=16*1024**2), checks=[], status='RUNNING')
	def save(): (runtime / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	def run(command, expected=0):
		command = list(map(str, command)); number = len(receipt['checks']); started = time.monotonic()
		stdout, stderr, timing = [runtime / (str(number) + suffix) for suffix in ['.stdout', '.stderr', '.time']]
		timed_out = False
		with stdout.open('xb') as out, stderr.open('xb') as err:
			process = subprocess.Popen(['/usr/bin/time', '-v', '-o', timing, *command], cwd=build, stdout=out, stderr=err,
				start_new_session=True, preexec_fn=limits, env=dict(os.environ, LC_ALL='C', DEBUGINFOD_URLS='', CCACHE_DISABLE='1'))
			try: process.wait(timeout=8)
			except subprocess.TimeoutExpired:
				timed_out = True
				try: os.killpg(process.pid, signal.SIGKILL)
				except ProcessLookupError: pass
				process.wait(timeout=3)
		row = dict(command=command, exit=process.returncode, expected_exit=expected, timeout=timed_out,
			seconds=time.monotonic()-started, stdout_sha256=sha(stdout), stderr_sha256=sha(stderr), stderr=stderr.read_text()[:16384], resources=timing.read_text())
		receipt['checks'].append(row); save()
		assert not timed_out and process.returncode == expected and not stdout.stat().st_size, row
		if expected:
			assert 'error:' in row['stderr'] and not any(s in row['stderr'] for s in ['CRITICAL', 'assertion failed', 'internal error']), row
		else: assert not stderr.stat().st_size, row
	try:
		producer = build / 'removed-producer.astra'; producer.write_bytes(inputs[-1].read_bytes())
		interface, obj = build / 'leaf.asti', build / 'leaf.o'
		exports = [part for name in ['WindowMetadata', 'metadata_gain', 'metadata_bias', 'combine'] for part in ['--native-export', 'TelemetryLeaf18.' + name]]
		run([compiler, '-O2', '-c', producer, '--module', 'TelemetryLeaf18', *exports, '--emit-interface', interface, '-o', obj])
		producer.unlink(); base = codec['metadata'](interface.read_text()); original = obj.read_bytes()
		assert base['abi']['schema'].endswith('runtime-units/6')
		function = 'function F:TelemetryLeaf18.metadata_gain'
		assert 'p|0|none|readonly' in base[function]['optimizer']
		client = build / 'consumer.astra'
		client.write_text('using TelemetryLeaf18; int main(){var m=new WindowMetadata(0.5,0.25,7);if(metadata_gain(m)!=0.5){return 1;}return 0;}\n')
		exe = build / 'positive'
		run([compiler, '-O2', client, '--import-module', interface, '-o', exe]); run([exe])
		rng = random.Random(receipt['seed'])
		for index in range(256):
			groups = copy.deepcopy(base); payload = original; family = index % 4
			if family == 0:
				groups[function]['lifetimes'] = 'runtime-lifetime-logical/1\\n' * rng.choice([2, 3, 16, 256, 4096]) + groups[function]['lifetimes']
			elif family == 1:
				groups[function]['optimizer'] = rng.choice([
					'astra-optimizer-summary/1\\nmemory|unknown\\np|0|none|readonly\\np|0|none|readonly',
					'astra-optimizer-summary/1\\nmemory|unknown\\np|-2|none|readonly',
					'astra-optimizer-summary/999\\nmemory|none',
					'astra-optimizer-summary/1\\nmemory|unknown\\ninvalid|' + str(rng.getrandbits(64)),
				])
			elif family == 2:
				# Guaranteed invalid ELF framing; do not manufacture executable
				# instruction mutations that might accidentally remain valid code.
				payload = rng.choice([original[:rng.randrange(0, 16)], b'BAD!' + original[4:],
					original[:4] + b'\x00' + original[5:], original[:5] + b'\x00' + original[6:]])
			else:
				groups[function]['lifetimes'] += '\\nunknown-lifetime-equation|' + str(rng.getrandbits(64))
			obj.write_bytes(payload); groups['object']['sha256'] = sha(obj)
			mutant = build / 'mutant.asti'; mutant.write_text(codec['reseal'](groups))
			product = build / ('refused-' + str(index) + '.o')
			run([compiler, '-c', client, '--import-module', mutant, '-o', product], expected=1)
			assert not product.exists(), product
		obj.write_bytes(original)
		run([compiler, '-O2', client, '--import-module', interface, '-o', build / 'restored']); run([build / 'restored'])
		assert sha(compiler) == receipt['compiler_sha256'] and all(sha(ROOT / name) == digest for name, digest in receipt['inputs'].items())
		receipt.update(status='PASS', malformed_imports=256, removed_producer_unavailable=True)
	finally:
		if receipt['status'] != 'PASS': receipt['status'] = 'FAIL'
		save()
	print(runtime / 'checks.json')


if __name__ == '__main__': main()
