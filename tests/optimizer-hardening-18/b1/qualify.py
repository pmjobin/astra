#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""B1 journal execution, opaque linkage, metamorphic and memory controls."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
sys.dont_write_bytecode = True
from reference import controls, generate, reconcile, RECORD, SEED

ROOT = Path(__file__).resolve().parents[3]
APP = ROOT / 'examples/optimizer-hardening-18/B'
sys.path.insert(0, str(APP))
from freeze import check as freeze_check


def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def observations(stdout, data, reference, profile, workers):
	match = re.search(r'^journal18 transactions=(\d+) allocations=(\d+) kernel_ns=(\d+) peak_jobs=(\d+)$', stdout, re.M)
	assert match, stdout
	row = dict(zip(['transactions', 'allocations', 'kernel_ns', 'peak_jobs'], map(int, match.groups())))
	assert row['transactions'] == reference['transactions'] and 1 <= row['peak_jobs'] <= workers
	contexts = [dict(zip(['identity', 'instance', 'live', 'reserved', 'allocations', 'releases', 'peak_payload'], map(int, match)))
		for match in re.findall(r'^journal18 context=(\d+) instance=(\d+) live=(\d+) reserved=(\d+) allocations=(\d+) releases=(\d+) peak_payload=(\d+)$', stdout, re.M)]
	assert [r['identity'] for r in contexts] == ([1] if profile == 'sequential' else [1, 2]), contexts
	assert len(set(r['instance'] for r in contexts)) == len(contexts)
	assert all(r['live'] == r['reserved'] == 0 and r['allocations'] == r['releases'] for r in contexts)
	lanes = {}
	for offset in range(0, len(data), RECORD.size):
		tx, lane = RECORD.unpack_from(data, offset)[:2]; lanes[tx] = lane
	expected = [(tx, (tx & 1) + 2 * (lanes[tx] & 1)) for tx in range(reference['transactions'])]
	actual = [tuple(map(int, match)) for match in re.findall(r'^journal18 policy=(\d+) value=(\d+)$', stdout, re.M)]
	assert actual == expected, (actual, expected)
	row['contexts'] = contexts
	return row


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	for name in ['compiler', 'build', 'runtime']: parser.add_argument(name, type=Path)
	parser.add_argument('--profiles', nargs='+', choices=['sequential', 'threaded', 'uring'], default=['sequential'])
	parser.add_argument('--uring-prefix', type=Path)
	parser.add_argument('--library-root', type=Path, default=ROOT / 'lib/astra')
	parser.add_argument('--freeze', type=Path, help='Original challenge only; current regressions do not claim a historical freeze')
	args = parser.parse_args()
	compiler = args.compiler.resolve(strict=True)
	for path in [args.build, args.runtime]:
		assert not path.resolve().is_relative_to(ROOT); path.mkdir(parents=True, exist_ok=True)
	build = Path(tempfile.mkdtemp(prefix='B1-qualification-', dir=args.build.resolve()))
	runtime = Path(tempfile.mkdtemp(prefix='B1-qualification-', dir=args.runtime.resolve()))
	inputs = [*APP.glob('*'), *Path(__file__).parent.glob('*.py')]
	inputs = [p for p in inputs if p.is_file()]
	receipt = dict(status='RUNNING', compiler=dict(path=str(compiler), sha256=sha(compiler)),
		seed=SEED, scope='B1 correctness and measured mechanisms; PASS here does not by itself satisfy the frozen optimization challenge',
		original_challenge=bool(args.freeze), profiles=args.profiles, source_snapshot={str(p): sha(p) for p in inputs},
		commands=[], products={}, comparisons=[], reference_controls=controls())
	def save(): (runtime / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	def frozen(): return freeze_check(args.freeze, ROOT) if args.freeze else None
	def run(command, *, workers=1, exit=0, diagnostics=False, timeout=90):
		command = list(map(str, command)); started = time.monotonic()
		q = subprocess.run(command, capture_output=True, text=True, cwd=runtime, timeout=timeout,
			env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1', DEBUGINFOD_URLS='', ASTRA_JOURNAL_WORKERS=str(workers)))
		row = dict(command=command, workers=workers, exit=q.returncode, stdout=q.stdout, stderr=q.stderr,
			seconds=time.monotonic() - started)
		receipt['commands'].append(row); save()
		assert q.returncode == exit and (diagnostics or not q.stderr), row
		return row
	def execute(product, name, count, seed=SEED, workers=1, memory=False):
		data = generate(count, seed); expected, reference = reconcile(data)
		source, target = runtime / (name + '.input'), runtime / (name + '.output'); source.write_bytes(data)
		launch = [product['product'], source, target]
		if memory:
			launch = ['valgrind', '--quiet', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--errors-for-leak-kinds=all', *launch]
		row = run(launch, workers=workers)
		assert target.read_bytes() == expected, name
		result = dict(records=count, seed=seed, workers=workers, memory=memory, output_sha256=sha(target),
			expected_sha256=hashlib.sha256(expected).hexdigest(), seconds=row['seconds'],
			**observations(row['stdout'], data, reference, product['profile'], workers))
		product['executions'].append(result); save(); return result
	configurations = [(profile, 'base', level, 'native', '2') for profile in args.profiles for level in '012']
	configurations += [('sequential', variant, level, 'native', '2') for variant in ['renamed', 'fields', 'helpers'] for level in '012']
	configurations += [('sequential', 'base', level, 'local', '2') for level in '012']
	configurations += [('sequential', 'base', '2', 'native', producer) for producer in '01']
	try:
		receipt['freeze_before'] = frozen()
		for profile, variant, level, linkage, producer in configurations:
			pair = {}
			for facts in ['off', 'on']:
				name = '-'.join([profile, variant, 'O' + level, linkage, 'P' + producer, facts])
				command = [sys.executable, '-B', APP / 'build-journal.py', '--compiler', compiler, '--library-root', args.library_root,
					'--build', build, '--runtime', runtime, '--profile', profile, '--variant', variant, '--optimization', level,
					'--facts', facts, '--linkage', linkage, '--producer-optimization', producer]
				if args.freeze: command += ['--freeze', args.freeze]
				if profile == 'uring': command += ['--uring-prefix', args.uring_prefix]
				lines = run(command)['stdout'].splitlines(); path = Path(lines[-2]); complete = json.loads(path.read_text())
				assert complete['status'] == 'BUILT_NOT_QUALIFIED'
				product = {key: complete[key] for key in ['product', 'profile', 'facts', 'linkage', 'optimization', 'variant', 'claims', 'sections', 'products']}
				product.update(receipt=str(path), receipt_sha256=sha(path), executions=[])
				receipt['products'][name] = product; pair[facts] = product; save()
				for count, seed in [(0, SEED), (7, SEED + 17), (513, SEED + 31), (4093, SEED + 71), (8193, SEED)]:
					execute(product, name + '-' + str(count), count, seed, workers=2 if profile != 'sequential' else 1)
				execute(product, name + '-memory', 513, SEED + 31, workers=4 if profile != 'sequential' else 1, memory=True)
				if variant == 'base' and level == '2' and producer == '2':
					if profile != 'sequential':
						for workers in [1, 4]:
							for count in [513, 8193]: execute(product, name + f'-w{workers}-n{count}', count, workers=workers)
					malformed = [('truncated', b'x', 65), ('overbound', bytes(8194 * 16), 65),
						('first-id', RECORD.pack(1, 0, 0, 0, 0, 1), 3), ('bad-shard', RECORD.pack(0, 4, 0, 0, 0, 1), 3),
						('mixed-shard', RECORD.pack(0, 0, 0, 0, 0, 1) + RECORD.pack(0, 1, 3, 0, 1, 0), 3),
						('gap-id', RECORD.pack(0, 0, 0, 0, 0, 1) + RECORD.pack(2, 0, 3, 0, 1, 0), 3)]
					for label, data, status in malformed:
						source, target = runtime / (name + label + '.input'), runtime / (name + label + '.output'); source.write_bytes(data)
						run([product['product'], source, target], workers=4 if profile != 'sequential' else 1, exit=status)
						assert not target.exists()
					for label in ['same-path', 'same-inode']:
						source = runtime / (name + label + '.input'); original = generate(7); source.write_bytes(original)
						target = source if label == 'same-path' else source.with_suffix('.alias')
						if target != source: os.link(source, target)
						run([product['product'], source, target], exit=65); assert source.read_bytes() == original
				product['freeze_after_execution'] = frozen(); save()
			if linkage == 'native':
				for unit in ['leaf', 'middle']:
					for suffix in ['.asti', '.o']:
						paths = [Path(pair[mode]['product']).parent / 'sdk' / (unit + suffix) for mode in ['off', 'on']]
						assert sha(paths[0]) == sha(paths[1]), (name, unit, suffix)
			for off, on in zip(pair['off']['executions'], pair['on']['executions']):
				assert off['output_sha256'] == on['output_sha256']
				receipt['comparisons'].append(dict(configuration=[profile, variant, level, linkage, producer], off=off, on=on))
			save()
		assert sha(compiler) == receipt['compiler']['sha256']
		assert all(sha(path) == digest for path, digest in receipt['source_snapshot'].items())
		receipt.update(status='PASS', source_unchanged=True, freeze_after=frozen())
	finally:
		if receipt['status'] != 'PASS': receipt['status'] = 'FAIL'
		save()
	print(runtime / 'checks.json')


if __name__ == '__main__': main()
