# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Qualify the current single-file async indexer entry and task retirement."""
from pathlib import Path
import argparse
import hashlib
import itertools
import json
import os
import subprocess
import tempfile
import time

from build import build, sha, HERE, ROOT
from corpus import generate, DEFAULT_SEED
from oracle import render


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('compiler', type=Path)
	parser.add_argument('build_output', type=Path)
	parser.add_argument('runtime_output', type=Path)
	parser.add_argument('--profile', choices=['virtual', 'linux'], default='virtual')
	parser.add_argument('--uring-prefix', type=Path)
	parser.add_argument('--runtime-root', type=Path)
	parser.add_argument('--matrix', action='store_true')
	parser.add_argument('--mode', choices=['native', 'mono'], default='native')
	args = parser.parse_args()
	compiler = args.compiler.resolve(strict=True)
	output = args.runtime_output.resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='async-indexer-', dir=output))
	manifest = generate(out / 'corpus', DEFAULT_SEED)
	receipt = dict(format='astra-m15-async-indexer/1', compiler_sha256=sha(compiler),
		profile=args.profile, sources={str(path): sha(path) for path in [Path(__file__), HERE / 'build.py', HERE / 'corpus.py', HERE / 'oracle.py']},
		manifest=str(manifest), manifest_sha256=sha(manifest), builds=[], checks=[],
		scope='Observed producer suspension and single-file async entry; full multi-file CLI, packaging and final milestone gates remain.')

	def save():
		(out / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')

	def run(binary, graph, name, path, flags, expected_exit, expected, diagnostic=None, memory=False):
		argv = [str(binary), path, *flags]
		if memory:
			argv = ['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
				'--errors-for-leak-kinds=all', '--error-exitcode=99', *argv]
		started = time.perf_counter()
		result = subprocess.run(argv, cwd=manifest.parent, capture_output=True, timeout=180)
		passed = result.returncode == expected_exit and result.stdout == expected
		if memory:
			passed &= all(value in result.stderr for value in [b'in use at exit: 0 bytes in 0 blocks',
				b'ERROR SUMMARY: 0 errors', b'(suppressed: 0 from 0)'])
		elif diagnostic is None:
			passed &= not result.stderr
		if diagnostic:
			passed &= diagnostic in result.stderr
		receipt['checks'].append(dict(graph=graph, name=name, argv=argv, cwd=str(manifest.parent),
			exit=result.returncode, passed=bool(passed), elapsed_seconds=time.perf_counter() - started,
			actual_sha256=hashlib.sha256(result.stdout).hexdigest(), expected_sha256=hashlib.sha256(expected).hexdigest(),
			stderr=result.stderr.decode(errors='replace')))
		save()
		assert passed, receipt['checks'][-1]

	graphs = [[0, 0, 0]]
	if args.matrix:
		graphs = [list(levels) for levels in [*itertools.product([0, 2], repeat=3), (1, 1, 1)]]
	for levels in graphs:
		built = build(compiler, args.build_output, ROOT / 'lib/astra', args.mode, levels,
			args.profile, args.runtime_root, args.uring_prefix, async_entry="single")
		data = json.loads(built.read_text())
		receipt['builds'].append(dict(path=str(built), sha256=sha(built)))
		receipt['sources'].update(data['sources'])
		binary = built.parent / 'indexer'
		graph = ''.join(map(str, levels))
		previous = Path.cwd()
		try:
			os.chdir(manifest.parent)
			small = render(['input-02.astra'])
			large = render(['input-63.astra'])
		finally:
			os.chdir(previous)
		for memory in [False, True]:
			for name, path, flags, code, expected, diagnostic in [
				('complete', 'input-02.astra', [], 0, small, None),
				('retry-late-policy', 'input-02.astra', ['--policy=alternate', '--retry-sink'], 0, small, None),
				('cold-cancel', 'input-02.astra', ['--cancel-cold'], 0, b'', None),
				('suspended-cancel', 'input-02.astra', ['--cancel-suspended'], 0, b'astra-index\t1\n', None),
				('checked-read-error', 'missing.astra', [], 4, b'astra-index\t1\n', b'file I/O'),
				('large', 'input-63.astra', ['--policy=alternate', '--retry-sink'], 0, large, None)]:
				run(binary, graph, name, path, flags, code, expected, diagnostic, memory)
	assert sha(compiler) == receipt['compiler_sha256']
	assert all(sha(Path(path)) == digest for path, digest in receipt['sources'].items())
	receipt['all_passed'] = True
	save()
	print(out / 'checks.json')


if __name__ == '__main__':
	main()
