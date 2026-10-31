#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Direct and correctly resealed importer framing probes with bounded resources."""
from pathlib import Path
import argparse
import hashlib
import json
import resource
import runpy
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('compiler', type=Path)
	parser.add_argument('decoder', type=Path)
	parser.add_argument('output', type=Path)
	parser.add_argument('--observe', action='store_true', help='preserve baseline failures without claiming acceptance')
	args = parser.parse_args()
	out = args.output.resolve()
	assert not out.is_relative_to(ROOT)
	out.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='framing-', dir=out))
	compiler, decoder = args.compiler.resolve(), args.decoder.resolve()
	receipt = {'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
		'decoder_sha256': hashlib.sha256(decoder.read_bytes()).hexdigest(),
		'sources': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [
		Path(__file__).resolve(), ROOT / 'bootstrap/source/runtime-lifetime-contracts.vala',
		ROOT / 'bootstrap/source/runtime-lifetimes.vala', ROOT / 'tests/optimizer-hardening-18/lifetime-decode.vala']},
		'observation_only': args.observe, 'checks': []}
	def limits():
		resource.setrlimit(resource.RLIMIT_AS, (512 * 1024**2, 512 * 1024**2))
		resource.setrlimit(resource.RLIMIT_CPU, (20, 20))
		resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	def run(command, expected, diagnostic=None, observe=False):
		command = list(map(str, command))
		start = time.monotonic()
		p = subprocess.run(['/usr/bin/time', '-v', '-o', str(out / 'time-current.txt'), *command],
			cwd=out, capture_output=True, text=True, timeout=30, preexec_fn=limits)
		row = {'command': command, 'exit': p.returncode, 'expected_exit': expected,
			'stdout': p.stdout, 'stderr': p.stderr, 'seconds': time.monotonic() - start,
			'resources': (out / 'time-current.txt').read_text()}
		row['passed'] = p.returncode == expected and (diagnostic is None or diagnostic in p.stderr)
		receipt['checks'].append(row)
		(out / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
		assert row['passed'] or observe, row
	for n in [0, 1, 2, 256, 8192, 65536]:
		run([decoder, n], 0 if n <= 1 else 1, observe=args.observe)
	leaf = ROOT / 'tests/runtime-composition-17/lifetime-unit-leaf.astra'
	run([compiler, '-O2', '-c', leaf, '--module', 'LifetimeLeaf',
		'--native-export', 'LifetimeLeaf.Leaf', '--native-export', 'LifetimeLeaf.Box',
		'--native-export', 'LifetimeLeaf.create', '--native-export', 'LifetimeLeaf.wrap',
		'--emit-interface', out / 'leaf.asti', '-o', out / 'leaf.o'], 0)
	meta = runpy.run_path(str(ROOT / 'tests/structural-generics-15/units.py'))
	client = out / 'consumer.astra'
	client.write_text('int main() { return 0; }\n')
	for n in [2, 256, 8192]:
		groups = meta['metadata']((out / 'leaf.asti').read_text())
		function = next(v for k, v in groups.items() if k.startswith('function ') and
			v['lifetimes'].startswith('runtime-lifetime-logical/1\\n'))
		function['lifetimes'] = 'runtime-lifetime-logical/1\\n' * (n - 1) + function['lifetimes']
		mutant = out / f'prefixes-{n}.asti'
		mutant.write_text(meta['reseal'](groups))
		product = out / f'refused-{n}.o'
		run([compiler, '-c', client, '--import-module', mutant, '-o', product], 1,
			'invalid versioned lifetime contract', observe=args.observe)
		assert not product.exists()
	print(out / 'checks.json')


if __name__ == '__main__':
	main()
