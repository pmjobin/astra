# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compare opaque reconciliation implementations with the frozen integer model."""
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
from inputs import scenarios
from oracle import render, MAXIMUM, InvalidInput


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('compiler', type=Path)
	parser.add_argument('build_output', type=Path)
	parser.add_argument('runtime_output', type=Path)
	parser.add_argument('--library-root', type=Path, default=ROOT / 'lib/astra')
	parser.add_argument('--matrix', action='store_true')
	args = parser.parse_args()
	compiler = args.compiler.resolve(strict=True)
	output = args.runtime_output.resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='reconciliation-', dir=output))
	receipt = dict(format='astra-m15-reconciliation-oracle/1', compiler_sha256=sha(compiler),
		sources={str(p): sha(p) for p in [Path(__file__), HERE / 'build.py', HERE / 'oracle.py', HERE / 'inputs.py', HERE / 'FORMAT.md']},
		builds=[], checks=[], scope='Frozen challenge execution and ownership evidence; final milestone gates require separate qualification.')

	def save():
		(out / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')

	def run(binary, graph, name, arguments, memory=False):
		try:
			expected, code = render(arguments), 0
		except InvalidInput:
			expected, code = b'', 2
		argv = [str(binary), *arguments]
		if memory:
			argv = ['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
				'--errors-for-leak-kinds=all', '--error-exitcode=99', *argv]
		started = time.perf_counter()
		result = subprocess.run(argv, cwd=out, capture_output=True, timeout=90,
			env=dict(os.environ, PYTHONDONTWRITEBYTECODE='1'))
		passed = result.returncode == code and result.stdout == expected
		if memory:
			passed &= all(value in result.stderr for value in [b'in use at exit: 0 bytes in 0 blocks',
				b'ERROR SUMMARY: 0 errors', b'(suppressed: 0 from 0)'])
		else:
			passed &= not result.stderr
		receipt['checks'].append(dict(name=name, graph=graph, argv=argv, expected_exit=code,
			exit=result.returncode, passed=bool(passed), elapsed_seconds=time.perf_counter() - started,
			actual_sha256=hashlib.sha256(result.stdout).hexdigest(), expected_sha256=hashlib.sha256(expected).hexdigest(),
			stderr=result.stderr.decode(errors='replace')))
		(out / (graph + '-' + name + ('-memory' if memory else '') + '.expected.tsv')).write_bytes(expected)
		(out / (graph + '-' + name + ('-memory' if memory else '') + '.actual.tsv')).write_bytes(result.stdout)
		save()
		assert passed, receipt['checks'][-1]

	invalid = [[], ['-1'], ['0', '1'], ['1', '1', '2', '3', '4', '1', '2', '0', '0', '2'],
		['2', '1', '2', '3', '4', '1', '2', '5', '6'],
		['2', '1', '2', '3', '4', '5', '6', '-1', '6'],
		['2', '1', '2', '3', '4', '5', '6', str(MAXIMUM), str(MAXIMUM)],
		['1', '1', '2', '3', 'not-decimal'], ['1', '1', '2', str(MAXIMUM + 1), '0']]
	graphs = [('native', [0, 0])]
	if args.matrix:
		graphs = [('mono', [level, level]) for level in [0, 1, 2]]
		graphs += [('native', list(levels)) for levels in [*itertools.product([0, 2], repeat=2), (1, 1)]]
	for variant in [False, True]:
		for mode, levels in graphs:
			built = build(compiler, args.build_output, args.library_root, mode, levels, variant)
			data = json.loads(built.read_text())
			receipt['sources'].update(data['sources'])
			receipt['builds'].append(dict(path=str(built), sha256=sha(built), mode=mode, levels=levels, variant=variant))
			binary = built.parent / 'reconcile'
			graph = ('renamed-' if variant else 'original-') + mode + '-' + ''.join(map(str, levels))
			for name, arguments in scenarios():
				for memory in [False, True]:
					run(binary, graph, name, arguments, memory)
			for index, arguments in enumerate(invalid):
				for memory in [False, True]:
					run(binary, graph, 'invalid-' + str(index), arguments, memory)
	assert sha(compiler) == receipt['compiler_sha256']
	assert all(sha(Path(path)) == digest for path, digest in receipt['sources'].items())
	receipt['all_passed'] = True
	save()
	print(out / 'checks.json')


if __name__ == '__main__':
	main()
