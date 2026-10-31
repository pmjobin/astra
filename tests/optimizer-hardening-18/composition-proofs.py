#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute independent-reference storage and checked-region lifetime controls."""
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


def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	for name in ['compiler', 'build', 'runtime']: parser.add_argument(name, type=Path)
	args = parser.parse_args(); compiler = args.compiler.resolve(strict=True)
	for path in [args.build, args.runtime]:
		assert not path.resolve().is_relative_to(ROOT); path.mkdir(parents=True, exist_ok=True)
	build = Path(tempfile.mkdtemp(prefix='composition-proofs-', dir=args.build.resolve()))
	runtime = Path(tempfile.mkdtemp(prefix='composition-proofs-', dir=args.runtime.resolve()))
	files = [Path(__file__), HERE / 'reference-storage.astra', HERE / 'checked-shared.astra', HERE / 'composition-observer.c']
	files += [ROOT / name for name in ['bootstrap/ssa/ssa-stack-objects.vala', 'bootstrap/ssa/ssa-stack-object-verifier.vala', 'bootstrap/ssa/ssa-shared-balance.vala']]
	receipt = dict(status='RUNNING', compiler_sha256=sha(compiler), inputs={str(p): sha(p) for p in files}, commands=[], products={},
		trace_scope='Lackey instruction traces count lock cmpxchg in linked executable only; shared-library instructions are excluded. 64 MiB file and 20 CPU-second child caps.')
	def save(): (runtime / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	def run(command, mode='on', expected=None, limits=None):
		command = list(map(str, command)); started = time.monotonic()
		q = subprocess.run(command, cwd=build, capture_output=True, text=True, timeout=60, preexec_fn=limits,
			env=dict(os.environ, CCACHE_DISABLE='1', ASTRA_TEST_OPTIMIZATIONS=mode, ASTRA_EXPLAIN_OPTIMIZATIONS='1', DEBUGINFOD_URLS='', LC_ALL='C'))
		row = dict(command=command, facts=mode, exit=q.returncode, stdout=q.stdout, stderr=q.stderr, seconds=time.monotonic() - started)
		receipt['commands'].append(row); save()
		assert q.returncode == 0 and not q.stderr and (expected is None or q.stdout == expected), row
		return q.stdout
	def limits():
		resource.setrlimit(resource.RLIMIT_FSIZE, (64 * 1024 ** 2, 64 * 1024 ** 2))
		resource.setrlimit(resource.RLIMIT_CPU, (20, 20)); resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	try:
		provider = build / 'observer.o'
		run(['clang', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-c', HERE / 'composition-observer.c', '-o', provider])
		for case in ['reference-storage', 'checked-shared']:
			text = (HERE / (case + '.astra')).read_text()
			for variant in ['original', 'renamed']:
				source = build / (case + '-' + variant + '.astra')
				source.write_text(text if variant == 'original' else text.replace('CompositionValue18', 'IndependentCell18').replace('CompositionSink18', 'RetainedJournal18').replace('CompositionPayload18', 'CheckedPacket18'))
				ssa = run([compiler, '--dump-ssa', source]); (source.with_suffix('.ssa')).write_text(ssa)
				assert ssa.count('(stack-object') == (2 if case == 'reference-storage' else 0)
				assert ssa.count('(shared-elision') == (1 if case == 'checked-shared' else 0)
				for level in '012':
					pair = {}
					for mode in ['off', 'on']:
						name = f'{case}-{variant}-O{level}-{mode}'; product = build / name
						obj = product.with_suffix('.o')
						run([compiler, '-O' + level, source, '--entry-object', '-o', obj], mode)
						run(['cc', '-O2', '-g', '-no-pie', obj, provider, '-Wl,--wrap=calloc', '-Wl,--wrap=malloc', '-o', product], mode)
						expected = ('retire=15\nretire=5\nallocations=' + ('1' if mode == 'on' else '3') + '\nretire=25\n') if case == 'reference-storage' else 'retire=0\nretire=3\nretire=4\nobserve=5\nretire=5\nretire=-2\n'
						run([product], mode, expected)
						run(['valgrind', '--quiet', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--errors-for-leak-kinds=all', product], mode, expected)
						ir = run([compiler, '-O' + level, '--dump-llvm', source], mode); product.with_suffix('.ll').write_text(ir)
						assembly = run(['objdump', '-dr', product]); product.with_suffix('.asm').write_text(assembly)
						row = dict(path=str(product), sha256=sha(product), bytes=product.stat().st_size, ir_sha256=hashlib.sha256(ir.encode()).hexdigest(),
							disassembly_sha256=hashlib.sha256(assembly.encode()).hexdigest(), sections=run(['size', '-A', product])
						)
						if level == '2' and case == 'checked-shared':
							assert 'EXEC (Executable file)' in run(['readelf', '-h', product])
							addresses = {int(m[1], 16) for m in re.finditer(r'^\s*([0-9a-f]+):[^\n]*\block\s+cmpxchg', assembly, re.M)}
							trace = runtime / (name + '.trace')
							run(['valgrind', '--tool=lackey', '--basic-counts=no', '--trace-mem=yes', '--log-file=' + str(trace), product], mode, expected, limits)
							counts = {address: 0 for address in addresses}
							with trace.open() as stream:
								for line in stream:
									match = re.match(r'I\s+([0-9a-fA-F]+),', line)
									if match and int(match[1], 16) in counts: counts[int(match[1], 16)] += 1
							row.update(static_cmpxchg=len(addresses), executed_cmpxchg=sum(counts.values()), sites={hex(k): v for k, v in counts.items()}, trace_sha256=sha(trace), trace_bytes=trace.stat().st_size)
						pair[mode] = row; receipt['products'][name] = row; save()
					if level == '2' and case == 'checked-shared':
						assert pair['on']['executed_cmpxchg'] < pair['off']['executed_cmpxchg'], pair
		assert sha(compiler) == receipt['compiler_sha256'] and all(sha(path) == digest for path, digest in receipt['inputs'].items())
		receipt.update(status='PASS', inputs_unchanged=True)
	finally:
		if receipt['status'] != 'PASS': receipt['status'] = 'FAIL'
		save()
	print(runtime / 'checks.json')


if __name__ == '__main__': main()
