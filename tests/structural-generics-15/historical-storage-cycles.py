# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compile the unchanged recursive ownership declarations in every source order."""
from pathlib import Path
import hashlib
import itertools
import json
import os
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
CORPUS = Path(__file__).with_suffix('.json')


def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()


def main(compiler_path, output_path):
	compiler = Path(compiler_path).resolve(strict=True)
	output = Path(output_path).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	directory = Path(tempfile.mkdtemp(prefix='cycles-', dir=output))
	corpus = json.loads(CORPUS.read_text())
	errors = ROOT / 'lib/astra/base/errors.astra'
	receipt = dict(compiler_sha256=sha(compiler), corpus_sha256=sha(CORPUS),
		recipe_sha256=sha(Path(__file__)), errors_sha256=sha(errors), checks=[])

	def run(command, expected=0, dump=False, memory=False):
		command = list(map(str, command))
		result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
			timeout=60, env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'))
		passed = result.returncode == expected
		passed &= bool(result.stdout) if dump else not result.stdout
		if memory:
			passed &= all(text in result.stderr for text in ['ERROR SUMMARY: 0 errors',
				'in use at exit: 0 bytes in 0 blocks', '(suppressed: 0 from 0)'])
		else:
			passed &= not result.stderr
		receipt['checks'].append(dict(argv=command, exit=result.returncode, memory=memory,
			stderr=result.stderr, passed=bool(passed)))
		(directory / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')
		assert passed, receipt['checks'][-1]

	for group_index, group in enumerate(corpus['groups']):
		stem = Path(group['path']).parent.name
		paths = []
		for index, source in enumerate(group['sources']):
			path = directory / (stem + '-' + str(index) + '.astra')
			path.write_text(source)
			assert sha(path) == group['source_sha256'][index]
			paths.append(path)
		orders = list(itertools.permutations(paths))
		assert len(orders) == len(group['cases'])
		for order_index, (name, inputs) in enumerate(zip(group['cases'], orders)):
			for stage in ['--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi']:
				run([compiler, stage, *inputs, errors], dump=True)
			for level in ['O0', 'O1', 'O2']:
				executable = directory / (stem + '-' + name + '-' + level)
				run([compiler, '-' + level, *inputs, errors, '-o', executable])
				if group_index == 0 and order_index == 0:
					# The original main returns42; unbounded recursive bodies are never called.
					run([executable], expected=42)
					run(['valgrind', '--default-suppressions=no', '--leak-check=full',
						'--show-leak-kinds=all', '--errors-for-leak-kinds=all',
						'--error-exitcode=99', executable], expected=42, memory=True)
	assert sha(compiler) == receipt['compiler_sha256']
	assert sha(CORPUS) == receipt['corpus_sha256']
	assert sha(Path(__file__)) == receipt['recipe_sha256']
	receipt['all_passed'] = True
	(directory / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')
	print(directory / 'checks.json')


if __name__ == '__main__':
	main(*sys.argv[1:])
