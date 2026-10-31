# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Preserve original ownership scope fixtures and exercise finite counterparts."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parents[2]
CORPUS = Path(__file__).with_suffix('.json')


def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()


def main(compiler_path, output_path):
	compiler = Path(compiler_path).resolve(strict=True)
	output = Path(output_path).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	directory = Path(tempfile.mkdtemp(prefix='originals-', dir=output))
	corpus = json.loads(CORPUS.read_text())
	errors = ROOT / 'lib/astra/base/errors.astra'
	receipt = dict(compiler_sha256=sha(compiler), recipe_sha256=sha(Path(__file__)),
		corpus_sha256=sha(CORPUS), errors_sha256=sha(errors), checks=[], sources={})

	def run(command, dump=False, memory=False):
		command = list(map(str, command))
		started = time.perf_counter()
		result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
			timeout=60, env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'))
		passed = result.returncode == (0 if dump or command[0] == str(compiler) else 42)
		passed &= bool(result.stdout) if dump else not result.stdout
		if memory:
			passed &= all(text in result.stderr for text in ['ERROR SUMMARY: 0 errors',
				'in use at exit: 0 bytes in 0 blocks', '(suppressed: 0 from 0)'])
		else:
			passed &= not result.stderr
		receipt['checks'].append(dict(argv=command, exit=result.returncode,
			elapsed_seconds=time.perf_counter() - started, memory=memory,
			stdout_sha256=hashlib.sha256(result.stdout.encode()).hexdigest(),
			stderr=result.stderr, passed=bool(passed)))
		(directory / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')
		assert passed, receipt['checks'][-1]

	for case_index, case in enumerate(corpus['cases']):
		label = Path(case['path']).parent.name + '-' + case['case']
		source = directory / (label + '.astra')
		source.write_text(case['source'])
		assert sha(source) == case['source_sha256']
		receipt['sources'][str(source)] = sha(source)
		for stage in ['--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi']:
			run([compiler, stage, source, errors], dump=True)
		variants = [source]
		if case['exercise_main'] is not None:
			exercise = directory / (label + '-exercise.astra')
			original_main = 'int main(){return 42;}'
			assert case['source'].count(original_main) == 1
			exercise.write_text(case['source'].replace(original_main, case['exercise_main']))
			receipt['sources'][str(exercise)] = sha(exercise)
			variants.append(exercise)
		for variant in variants:
			for level in ['O0', 'O1', 'O2']:
				executable = directory / (variant.stem + '-' + level)
				run([compiler, '-' + level, variant, errors, '-o', executable])
				# Empty original entries share startup; exercised bodies retain all runs.
				if variant != source or case_index == 0:
					run([executable])
					run(['valgrind', '--default-suppressions=no', '--leak-check=full',
						'--show-leak-kinds=all', '--errors-for-leak-kinds=all',
						'--error-exitcode=99', executable], memory=True)
	assert sha(compiler) == receipt['compiler_sha256']
	assert sha(CORPUS) == receipt['corpus_sha256']
	assert sha(Path(__file__)) == receipt['recipe_sha256']
	assert sha(errors) == receipt['errors_sha256']
	receipt['all_passed'] = True
	(directory / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')
	print(directory / 'checks.json')


if __name__ == '__main__':
	main(*sys.argv[1:])
