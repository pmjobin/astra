#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact local receivers across helper/branch composition; dynamic inputs stay dynamic."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	for name in ['compiler', 'build', 'runtime']: parser.add_argument(name, type=Path)
	args = parser.parse_args()
	compiler = args.compiler.resolve(strict=True)
	for path in [args.build, args.runtime]:
		assert not path.resolve().is_relative_to(ROOT)
		path.mkdir(parents=True, exist_ok=True)
	build = Path(tempfile.mkdtemp(prefix='dispatch-', dir=args.build.resolve()))
	runtime = Path(tempfile.mkdtemp(prefix='dispatch-', dir=args.runtime.resolve()))
	inputs = [HERE / name for name in ['dispatch.astra', 'dispatch-oracle.c', 'storage-observer.c', 'dispatch.py']]
	production = [ROOT / name for name in subprocess.check_output(['git', 'ls-files', '-z', '--', 'bootstrap', 'lib', 'tools', 'meson.build', 'meson.options'], cwd=ROOT).decode().split('\0') if name]
	receipt = dict(compiler_sha256=sha(compiler), inputs={str(p.relative_to(ROOT)): sha(p) for p in inputs},
		production_snapshot={str(p.relative_to(ROOT)): sha(p) for p in production}, checks=[], products={})
	def save(): (runtime / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	def run(command, mode='on', env=None, expected=None, memory=False):
		command = list(map(str, command)); started = time.monotonic()
		settings = dict(CCACHE_DISABLE='1', ASTRA_TEST_OPTIMIZATIONS=mode, ASTRA_EXPLAIN_OPTIMIZATIONS='1', DEBUGINFOD_URLS='')
		settings.update(env or {})
		p = subprocess.run(command, cwd=build, text=True, capture_output=True, timeout=60, env=dict(os.environ, **settings))
		row = dict(command=command, environment=settings, exit=p.returncode, stdout=p.stdout, stderr=p.stderr, seconds=time.monotonic()-started)
		receipt['checks'].append(row); save(); assert p.returncode == 0 and not p.stderr, row
		if expected is not None:
			if memory:
				assert p.stdout.splitlines()[:-1] == expected.splitlines()[:-1], row
				assert re.fullmatch(r'allocations=\d+ retired=42\n', p.stdout.splitlines(keepends=True)[-1]), row
			else: assert p.stdout == expected, row
		return p.stdout
	providers = []
	for name in ['storage-observer', 'dispatch-oracle']:
		provider = build / (name + '.o'); providers += ['--link-object', provider]
		run(['clang', '-std=c11', '-O2', '-fno-builtin', '-Wall', '-Wextra', '-Werror', '-c', HERE / (name + '.c'), '-o', provider], expected='')
	original = (HERE / 'dispatch.astra').read_text()
	renamed = original.replace('Offset18', 'TelemetryOffset18').replace('Scale18', 'PacketScale18').replace('Stage18', 'FrameStage18')
	third = original + '\nclass ExtraStage18 : Stage18 { int delta; init(int value) : base(){this.delta=value;} override int invoke(int value){return value-this.delta;} }\n'
	expected = ''.join(''.join(f'retire={n}\n' for n in [7, 3, 9, 5, 219, 217, 102, 11]) for _ in range(5)) + 'retire=103\nretire=13\nallocations=42 retired=42\n'
	for variant, text in [('original', original), ('renamed', renamed), ('third-type', third)]:
		source = build / (variant + '.astra'); source.write_text(text)
		ssa = run([compiler, '--dump-ssa', source]); (build / (variant + '.ssa')).write_text(ssa)
		assert ssa.count('(exact-call') == 8, ssa
		for name in ['dispatch18_mixed', 'dispatch18_dynamic']:
			ordinal = re.search(r'\(function #(\d+) "' + name + '"', ssa).group(1)
			assert '(exact-call function=#' + ordinal + ' ' not in ssa, ssa
		for level in '012':
			counts = {}
			for mode in ['off', 'on']:
				exe = build / f'{variant}-O{level}-{mode}'
				run([compiler, '-O' + level, source, *providers, '-o', exe], mode, expected='')
				for seed in [-100, 0, 100]: run([exe], mode, dict(DISPATCH18_SEED=str(seed)), expected=expected)
				run(['valgrind', '--quiet', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--errors-for-leak-kinds=all', exe], mode, dict(DISPATCH18_SEED='7'), expected=expected, memory=True)
				ir = build / (exe.name + '.ll'); ir.write_text(run([compiler, '-O' + level, '--dump-llvm', source], mode))
				assembly = build / (exe.name + '.asm'); assembly.write_text(run(['objdump', '-dr', exe]))
				counts[mode] = dict(indirect_llvm_calls=len(re.findall(r'call fastcc i32 %', ir.read_text())),
					indirect_machine_calls=len(re.findall(r'\bcall\s+\*', assembly.read_text())))
				receipt['products'][exe.name] = dict(sha256=sha(exe), bytes=exe.stat().st_size, ir_sha256=sha(ir),
					assembly_sha256=sha(assembly), mechanisms=counts[mode], sections=run(['size', '-A', exe])); save()
			if level == '0':
				assert counts['on']['indirect_llvm_calls'] < counts['off']['indirect_llvm_calls'], counts
				assert counts['on']['indirect_machine_calls'] < counts['off']['indirect_machine_calls'], counts
	assert sha(compiler) == receipt['compiler_sha256']
	assert all(sha(ROOT / name) == digest for name, digest in receipt['production_snapshot'].items())
	receipt.update(status='PASS', production_unchanged_during_ablation=True); save()
	print(runtime / 'checks.json')


if __name__ == '__main__': main()
