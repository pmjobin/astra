#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Numeric views/owners beside independent Class placement, with exact oracles."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def no_core(): resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	for name in ['compiler', 'build', 'runtime']: parser.add_argument(name, type=Path)
	args = parser.parse_args()
	compiler = args.compiler.resolve(strict=True)
	for path in [args.build, args.runtime]:
		assert not path.resolve().is_relative_to(ROOT)
		path.mkdir(parents=True, exist_ok=True)
	build = Path(tempfile.mkdtemp(prefix='views-', dir=args.build.resolve()))
	runtime = Path(tempfile.mkdtemp(prefix='views-', dir=args.runtime.resolve()))
	inputs = [HERE / name for name in ['view-storage.astra', 'view-storage-oracle.c', 'storage-observer.c', 'view-storage.py']]
	production = [ROOT / name for name in subprocess.check_output(['git', 'ls-files', '-z', '--', 'bootstrap', 'lib', 'tools', 'meson.build', 'meson.options'], cwd=ROOT).decode().split('\0') if name]
	receipt = dict(compiler_sha256=sha(compiler), inputs={str(p.relative_to(ROOT)): sha(p) for p in inputs},
		production_snapshot={str(p.relative_to(ROOT)): sha(p) for p in production}, checks=[], products={})
	def save(): (runtime / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	def run(command, mode='on', env=None, expected=0, stdout=None, memory=False):
		command = list(map(str, command)); started = time.monotonic()
		settings = dict(CCACHE_DISABLE='1', ASTRA_TEST_OPTIMIZATIONS=mode, ASTRA_EXPLAIN_OPTIMIZATIONS='1', DEBUGINFOD_URLS='', VIEW18_SHORT='0')
		settings.update(env or {})
		p = subprocess.run(command, cwd=build, text=True, capture_output=True, timeout=60,
			env=dict(os.environ, **settings), preexec_fn=no_core)
		row = dict(command=command, environment=settings, exit=p.returncode, stdout=p.stdout, stderr=p.stderr, seconds=time.monotonic()-started)
		receipt['checks'].append(row); save()
		assert p.returncode == expected and not p.stderr, row
		if stdout is not None:
			if memory:
				assert p.stdout.splitlines()[:-1] == stdout.splitlines()[:-1], row
				assert re.fullmatch(r'allocations=\d+ retired=5\n', p.stdout.splitlines(keepends=True)[-1]), row
			else: assert p.stdout == stdout, row
		return p.stdout
	observer = build / 'observer.o'
	run(['clang', '-std=c11', '-O2', '-fno-builtin', '-Wall', '-Wextra', '-Werror', '-c', HERE / 'storage-observer.c', '-o', observer], stdout='')
	for precision in ['f64', 'f32']:
		oracle = build / (precision + '-oracle.o')
		run(['clang', '-std=c11', '-O2', '-ffp-contract=off', '-fno-fast-math', '-Wall', '-Wextra', '-Werror',
			*(['-DVIEW18_FLOAT32'] if precision == 'f32' else []), '-c', HERE / 'view-storage-oracle.c', '-o', oracle], stdout='')
		original = (HERE / 'view-storage.astra').read_text().replace('f64', precision)
		for variant, text in [('original', original), ('renamed', original.replace('ViewState18', 'PacketGain18').replace('ViewLoop18', 'FrameCursor18').replace('view18_process', 'transform18').replace('view18_weights', 'gain_pair18').replace('view18_buffer', 'scratch_transform18'))]:
			source = build / (precision + '-' + variant + '.astra'); source.write_text(text)
			ssa = run([compiler, '--dump-ssa', source]); (build / (source.stem + '.ssa')).write_text(ssa)
			assert ssa.count('(stack-object') == 4 and 'vector-memory' in ssa and 'buffer-deallocate' in ssa, ssa
			for level in '012':
				for mode in ['off', 'on']:
					exe = build / f'{source.stem}-O{level}-{mode}'
					run([compiler, '-O' + level, source, '--link-object', observer, '--link-object', oracle, '-o', exe], mode, stdout='')
					for count in [0, 1, 3, 6, 7]:
						for overlap in [0, 1]:
							for seed in [0, 3, 8, 12]:
								expected = ''.join(f'retire={n}\n' for n in [3, 2, 1, 5, 4]) + f'allocations={(1 if mode == "on" else 5) + (count != 0)} retired=5\n'
								run([exe], mode, dict(VIEW18_COUNT=str(count), VIEW18_OVERLAP=str(overlap), VIEW18_SEED=str(seed)), stdout=expected)
					env = dict(VIEW18_COUNT='7', VIEW18_OVERLAP='1', VIEW18_SEED='5')
					expected = ''.join(f'retire={n}\n' for n in [3, 2, 1, 5, 4]) + f'allocations={2 if mode == "on" else 6} retired=5\n'
					run(['valgrind', '--quiet', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--errors-for-leak-kinds=all', exe], mode, env, stdout=expected, memory=True)
					# The same short vector/scalar tail traps before cleanup in both
					# ablations. A trap does not run normal-exit atexit observers.
					run([exe], mode, dict(env, VIEW18_SHORT='1'), expected=-4, stdout='')
					ir = build / (exe.name + '.ll'); ir.write_text(run([compiler, '-O' + level, '--dump-llvm', source], mode))
					assembly = build / (exe.name + '.asm'); assembly.write_text(run(['objdump', '-dr', exe]))
					receipt['products'][exe.name] = dict(sha256=sha(exe), bytes=exe.stat().st_size,
						ir_sha256=sha(ir), assembly_sha256=sha(assembly), sections=run(['size', '-A', exe])); save()
	assert sha(compiler) == receipt['compiler_sha256']
	assert all(sha(ROOT / name) == digest for name, digest in receipt['production_snapshot'].items())
	receipt.update(status='PASS', production_unchanged_during_ablation=True); save()
	print(runtime / 'checks.json')


if __name__ == '__main__': main()
