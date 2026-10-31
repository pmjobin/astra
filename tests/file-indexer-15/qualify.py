# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compare actual indexer builds with the independent external-format oracle."""
from pathlib import Path
import argparse
import hashlib
import itertools
import json
import os
import re
import subprocess
import tempfile
import time

from build import build, sha, HERE, ROOT
from corpus import generate, DEFAULT_SEED
from oracle import render, analyze, RejectedDocument, escaped_path


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('compiler', type=Path)
	parser.add_argument('build_output', type=Path)
	parser.add_argument('runtime_output', type=Path)
	parser.add_argument('--matrix', action='store_true')
	parser.add_argument('--library-root', type=Path, default=ROOT / 'lib/astra')
	parser.add_argument('--async-profile', choices=['virtual', 'linux'])
	parser.add_argument('--runtime-root', type=Path)
	parser.add_argument('--uring-prefix', type=Path)
	parser.add_argument('--read-fault-adapter', action='store_true')
	parser.add_argument('--seed', type=int, default=DEFAULT_SEED)
	args = parser.parse_args()
	compiler = args.compiler.resolve(strict=True)
	output = args.runtime_output.resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='index-qualification-', dir=output))
	manifest = generate(out / 'corpus', args.seed)
	corpus = json.loads(manifest.read_text())
	paths = [item['path'] for item in corpus['inputs']] + [corpus['missing_input'], 'input-01.astra']
	odd_path = 'space % tab\tλ.astra'
	(manifest.parent / odd_path).write_bytes(b'int path_value=3;\n')
	paths.append(odd_path)
	receipt = dict(format='astra-m15-indexer-oracle/1', compiler_sha256=sha(compiler), async_profile=args.async_profile,
		sources={str(path): sha(path) for path in [Path(__file__), HERE / 'build.py', HERE / 'corpus.py', HERE / 'oracle.py']},
		manifest=str(manifest), manifest_sha256=sha(manifest), builds=[], checks=[],
		scope='Indexer output, cache, checked sink and selected async entry evidence; final registry and other milestone gates remain separate.')

	def save():
		(out / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')

	def run(binary, name, flags, selected, memory=False, cancellation=None, read_fault=False):
		# The public labels are the exact relative arguments used by the CLI.
		previous = Path.cwd()
		try:
			os.chdir(manifest.parent)
			expected = render(selected)
			if cancellation:
				expected = b'' if cancellation == 'cold' else b'astra-index\t1\n'
				if cancellation == 'after-first':
					expected = b''.join(render(selected[:1]).splitlines(keepends=True)[:-1])
			if read_fault:
				rest = render(selected[1:]).splitlines(keepends=True)
				summary = rest[-1].decode().rstrip('\n').split('\t')
				summary[2] = str(int(summary[2]) + 1)
				expected = rest[0] + ('error\t' + escaped_path(selected[0]) + '\tread\n').encode('ascii')
				expected += b''.join(rest[1:-1]) + ('\t'.join(summary) + '\n').encode('ascii')
		finally:
			os.chdir(previous)
		argv = [str(binary), *flags, *selected]
		if memory:
			argv = ['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
				'--errors-for-leak-kinds=all', '--error-exitcode=99', *(['--track-fds=yes'] if read_fault else []), *argv]
		started = time.perf_counter()
		result = subprocess.run(argv, cwd=manifest.parent, capture_output=True, timeout=180,
			env=dict(os.environ, **({'ASTRA_INDEX_READ_FAIL_AFTER': '7'} if read_fault else {})))
		passed = result.returncode == 0 and result.stdout == expected
		if memory:
			passed &= all(value in result.stderr for value in [b'in use at exit: 0 bytes in 0 blocks',
				b'ERROR SUMMARY: 0 errors', b'(suppressed: 0 from 0)'])
		elif '--cache-stats' not in flags:
			passed &= not result.stderr
		if read_fault:
			passed &= result.stderr.count(b'index-read-fault\t7\n') == 1
			if memory:
				passed &= re.search(rb'FILE DESCRIPTORS: 3 open \(3 (?:std|inherited)\) at exit\.', result.stderr) is not None
		cache_evidence = None
		if '--cache-stats' in flags:
			valid = []
			for path in selected:
				try:
					analyze((manifest.parent / path).read_bytes())
				except (OSError, RejectedDocument):
					continue
				valid.append(path)
			unique = len(set(valid))
			accepted = len(valid) if '--refresh' in flags else unique
			evicted = int('--evict-last' in flags and bool(valid))
			expected_cache = [unique - evicted, accepted + evicted, accepted,
				accepted + (unique if '--retry-sink' in flags else 0)]
			match = re.search(rb'^cache\t(\d+)\t(\d+)\t(\d+)\t(\d+)\t(\d+)\r?$', result.stderr, re.M)
			actual = list(map(int, match.groups())) if match else []
			cache_evidence = dict(expected_count_revision_receipts_attempts=expected_cache, actual=actual)
			passed &= bool(actual) and [actual[0], *actual[2:]] == expected_cache and actual[1] >= len(valid)
		receipt['checks'].append(dict(name=name, argv=argv, cwd=str(manifest.parent),
			exit=result.returncode, passed=bool(passed), elapsed_seconds=time.perf_counter() - started,
			output_bytes=len(result.stdout), actual_sha256=hashlib.sha256(result.stdout).hexdigest(),
			expected_sha256=hashlib.sha256(expected).hexdigest(), stderr=result.stderr.decode(errors='replace'),
			cache_evidence=cache_evidence))
		(out / (name + '.actual.tsv')).write_bytes(result.stdout)
		(out / (name + '.expected.tsv')).write_bytes(expected)
		save()
		assert passed, receipt['checks'][-1]

	graphs = [('mono', [0, 0, 0]), ('native', [0, 0, 0])]
	if args.matrix:
		graphs = [('mono', [level, level, level]) for level in [0, 1, 2]]
		graphs += [('native', list(levels)) for levels in [*itertools.product([0, 2], repeat=3), (1, 1, 1)]]
	for mode, levels in graphs:
		built = build(compiler, args.build_output, args.library_root, mode, levels,
			args.async_profile, args.runtime_root, args.uring_prefix, read_fault=args.read_fault_adapter)
		data = json.loads(built.read_text())
		receipt['builds'].append(dict(path=str(built), sha256=sha(built), mode=mode, levels=levels))
		receipt['sources'].update(data['sources'])
		binary = built.parent / 'indexer'
		name = mode + '-' + ''.join(map(str, levels))
		run(binary, name + '-default', [], paths)
		run(binary, name + '-alternate', ['--policy=alternate', '--retry-sink', '--refresh', '--evict-last', '--cache-stats'], paths)
		run(binary, name + '-memory', ['--retry-sink', '--evict-last', '--cache-stats'],
			['input-01.astra', 'input-02.astra', 'input-63.astra', 'embedded-nul.astra',
			'overlong-utf8.astra', 'missing-input.astra', odd_path, 'input-01.astra'], memory=True)
		if args.read_fault_adapter:
			for memory in [False, True]:
				run(binary, name + '-partial-read-fault' + ('-memory' if memory else ''),
					['--retry-sink', '--cache-stats'], ['input-02.astra', 'input-01.astra', 'input-02.astra'],
					memory=memory, read_fault=True)
		if args.async_profile:
			for memory in [False, True]:
				for cancellation in ['cold', 'suspended', 'after-first']:
					run(binary, name + '-cancel-' + cancellation + ('-memory' if memory else ''),
						['--cancel-' + cancellation], ['input-02.astra', 'input-63.astra', 'missing-input.astra'],
						memory=memory, cancellation=cancellation)
			run(binary, name + '-empty', [], [])
	assert sha(compiler) == receipt['compiler_sha256']
	assert all(sha(Path(path)) == digest for path, digest in receipt['sources'].items())
	receipt['all_passed'] = True
	save()
	print(out / 'checks.json')


if __name__ == '__main__':
	main()
