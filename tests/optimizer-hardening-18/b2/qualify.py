#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""B2 image execution, opaque linkage, metamorphic and memory controls."""
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
from reference import controls, generate as generate_image, reconcile, HEADER, INPUT_MAGIC, SEED

ROOT = Path(__file__).resolve().parents[3]
APP = ROOT / 'examples/optimizer-hardening-18/B2'
sys.path.insert(0, str(APP))
from freeze import check as freeze_check


def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()


SIZES = {0: (0, 0), 35: (7, 5), 527: (31, 17), 8255: (127, 65), 33153: (257, 129)}


def sample_input(count, seed=SEED): return generate_image(*SIZES[count], seed=seed)


generate = sample_input


def observations(stdout, data, reference, profile, workers):
	match = re.search(r'^image2 width=(\d+) height=(\d+) threshold=(\d+) components=(\d+) foreground=(\d+) classification_allocations=(\d+) merge_allocations=(\d+) classification_ns=(\d+) merge_ns=(\d+) peak_jobs=(\d+) storage_bytes=(\d+)$', stdout, re.M)
	assert match, stdout
	row = dict(zip(['width', 'height', 'threshold', 'components', 'foreground', 'classification_allocations', 'merge_allocations', 'classification_ns', 'merge_ns', 'peak_jobs', 'storage_bytes'], map(int, match.groups())))
	assert all(row[key] == reference[key] for key in ['width', 'height', 'threshold', 'foreground'])
	assert row['components'] == len(reference['components']) and 1 <= row['peak_jobs'] <= workers
	contexts = [dict(zip(['identity', 'instance', 'live', 'reserved', 'allocations', 'releases', 'peak_payload'], map(int, match)))
		for match in re.findall(r'^image2 context=(\d+) instance=(\d+) live=(\d+) reserved=(\d+) allocations=(\d+) releases=(\d+) peak_payload=(\d+)$', stdout, re.M)]
	assert [r['identity'] for r in contexts] == ([1] if profile == 'sequential' else [1, 2]), contexts
	assert len(set(r['instance'] for r in contexts)) == len(contexts)
	assert all(r['live'] == r['reserved'] == 0 and r['allocations'] == r['releases'] for r in contexts)
	expected = [(y, y % 2) for y in range(reference['height'])]
	actual = [tuple(map(int, match)) for match in re.findall(r'^image2 policy=(\d+) mode=(\d+)$', stdout, re.M)]
	assert actual == expected, (actual, expected)
	row.update(contexts=contexts, allocations=row['classification_allocations'] + row['merge_allocations'], kernel_ns=row['classification_ns'] + row['merge_ns'])
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
	build = Path(tempfile.mkdtemp(prefix='B2-qualification-', dir=args.build.resolve()))
	runtime = Path(tempfile.mkdtemp(prefix='B2-qualification-', dir=args.runtime.resolve()))
	inputs = [*APP.glob('*'), *Path(__file__).parent.glob('*.py')]
	inputs = [p for p in inputs if p.is_file()]
	receipt = dict(status='RUNNING', compiler=dict(path=str(compiler), sha256=sha(compiler)),
		seed=SEED, scope='B2 correctness and measured mechanisms; PASS here does not by itself satisfy the frozen optimization challenge',
		original_challenge=bool(args.freeze), profiles=args.profiles, source_snapshot={str(p): sha(p) for p in inputs},
		commands=[], products={}, comparisons=[], reference_controls=controls())
	def save(): (runtime / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	def frozen(): return freeze_check(args.freeze, ROOT) if args.freeze else None
	def run(command, *, workers=1, exit=0, diagnostics=False, timeout=90):
		command = list(map(str, command)); started = time.monotonic()
		q = subprocess.run(command, capture_output=True, text=True, cwd=runtime, timeout=timeout,
			env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1', DEBUGINFOD_URLS='', ASTRA_IMAGE_WORKERS=str(workers)))
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
				command = [sys.executable, '-B', APP / 'build-image.py', '--compiler', compiler, '--library-root', args.library_root,
					'--build', build, '--runtime', runtime, '--profile', profile, '--variant', variant, '--optimization', level,
					'--facts', facts, '--linkage', linkage, '--producer-optimization', producer]
				if args.freeze: command += ['--freeze', args.freeze]
				if profile == 'uring': command += ['--uring-prefix', args.uring_prefix]
				lines = run(command)['stdout'].splitlines(); path = Path(lines[-2]); complete = json.loads(path.read_text())
				assert complete['status'] == 'BUILT_NOT_QUALIFIED'
				product = {key: complete[key] for key in ['product', 'profile', 'facts', 'linkage', 'optimization', 'variant', 'claims', 'sections', 'products']}
				product.update(receipt=str(path), receipt_sha256=sha(path), executions=[])
				receipt['products'][name] = product; pair[facts] = product; save()
				for count, seed in [(0, SEED), (35, SEED + 17), (527, SEED + 31), (8255, SEED + 71), (33153, SEED)]:
					execute(product, name + '-' + str(count), count, seed, workers=2 if profile != 'sequential' else 1)
				execute(product, name + '-memory', 527, SEED + 31, workers=4 if profile != 'sequential' else 1, memory=True)
				if variant == 'base' and level == '2' and producer == '2':
					if profile != 'sequential':
						for workers in [1, 4]:
							for count in [527, 33153]: execute(product, name + f'-w{workers}-n{count}', count, workers=workers)
					malformed = [('truncated', b'x', 3), ('overbound', bytes(16 + 257 * 129 * 3 + 1), 65),
						('magic', HEADER.pack(0, 0, 0, 0), 3), ('zero-width', HEADER.pack(INPUT_MAGIC, 0, 1, 0), 3),
						('wide', HEADER.pack(INPUT_MAGIC, 258, 1, 0), 3), ('tall', HEADER.pack(INPUT_MAGIC, 1, 130, 0), 3),
						('threshold', HEADER.pack(INPUT_MAGIC, 0, 0, 256), 3), ('missing-rgb', HEADER.pack(INPUT_MAGIC, 1, 1, 0), 3),
						('trailing', HEADER.pack(INPUT_MAGIC, 0, 0, 0) + b'x', 3)]
					for label, data, status in malformed:
						source, target = runtime / (name + label + '.input'), runtime / (name + label + '.output'); source.write_bytes(data)
						run([product['product'], source, target], workers=4 if profile != 'sequential' else 1, exit=status)
						assert not target.exists()
					for label in ['same-path', 'same-inode']:
						source = runtime / (name + label + '.input'); original = generate(35); source.write_bytes(original)
						target = source if label == 'same-path' else source.with_suffix('.alias')
						if target != source: os.link(source, target)
						run([product['product'], source, target], exit=65); assert source.read_bytes() == original
				assert len(product['claims']['shared']) <= 1 and len(product['claims']['storage']) <= 2, (name, product['claims'])
				if linkage == 'local': assert len(product['claims']['storage']) == 2 and len(product['claims']['shared']) == 1, name
				if linkage == 'native' and producer == '2' and variant == 'base': assert len(product['claims']['shared']) == 1, name
				product['freeze_after_execution'] = frozen(); save()
			if linkage == 'native':
				for unit in ['leaf', 'middle']:
					for suffix in ['.asti', '.o']:
						paths = [Path(pair[mode]['product']).parent / 'sdk' / (unit + suffix) for mode in ['off', 'on']]
						assert sha(paths[0]) == sha(paths[1]), (name, unit, suffix)
			for off, on in zip(pair['off']['executions'], pair['on']['executions']):
				assert off['output_sha256'] == on['output_sha256']
				if not off['memory']:
					assert off['allocations'] - on['allocations'] == len(pair['on']['claims']['storage']) * off['height'], (name, off, on)
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
