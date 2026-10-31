# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Qualify approved historical observations and their exact original controls."""
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
	directory = Path(tempfile.mkdtemp(prefix='observations-', dir=output))
	receipt = dict(compiler_sha256=sha(compiler), recipe_sha256=sha(Path(__file__)),
		corpus_sha256=sha(CORPUS), checks=[], sources={}, products={})

	def run(command, expected=0, diagnostic=None, memory=False, dump=False):
		command = list(map(str, command))
		started = time.perf_counter()
		result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
			timeout=90, env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'))
		passed = result.returncode == expected
		passed &= bool(result.stdout) if dump else not result.stdout
		if diagnostic:
			passed &= diagnostic in result.stderr and 'internal ' not in result.stderr
		elif memory:
			passed &= all(text in result.stderr for text in ['ERROR SUMMARY: 0 errors',
				'in use at exit: 0 bytes in 0 blocks', '(suppressed: 0 from 0)'])
		else:
			passed &= not result.stderr
		receipt['checks'].append(dict(argv=command, exit=result.returncode, expected=expected,
			elapsed_seconds=time.perf_counter() - started, memory=memory,
			stdout_sha256=hashlib.sha256(result.stdout.encode()).hexdigest(),
			stderr=result.stderr, passed=bool(passed)))
		(directory / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')
		assert passed, receipt['checks'][-1]

	for case in json.loads(CORPUS.read_text())['cases']:
		original = directory / (case['name'] + '.astra')
		original.write_text(case['source'])
		assert sha(original) == case['source_sha256']
		receipt['sources'][original.name] = sha(original)
		libraries = [ROOT / path for path in case['libraries']]
		imports = ['--vapi', ROOT / case['vapi']] if case.get('vapi') else []
		if case.get('vapi'): receipt['sources'][case['vapi']] = sha(ROOT / case['vapi'])
		for library in libraries: receipt['sources'][str(library.relative_to(ROOT))] = sha(library)
		if case['phase'] == 'syntax':
			run([compiler, '--dump-syntax', original], dump=True)
		if case['phase'] == 'check':
			run([compiler, '--check', original])
		else:
			for stage in ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']:
				run([compiler, '--dump-' + stage, *imports, original, *libraries],
					expected=1 if case['diagnostic'] else 0,
					diagnostic=case['diagnostic'], dump=not case['diagnostic'])
		variants = []
		if not case['diagnostic']:
			control = directory / (case['name'] + '-control.astra')
			control.write_text(case['source'] if 'int main()' in case['source'] else
				case['source'] + '\nint main(){return 0;}\n')
			variants.append(control)
		exercise = directory / (case['name'] + '-exercise.astra')
		exercise.write_text(case['exercise'])
		variants.append(exercise)
		for source in variants:
			receipt['sources'][source.name] = sha(source)
			for level in ['O0', 'O1', 'O2']:
				executable = directory / (source.stem + '-' + level)
				run([compiler, '-' + level, *imports, source, *libraries, '-o', executable])
				receipt['products'][executable.name] = sha(executable)
				run([executable])
				run(['valgrind', '--default-suppressions=no', '--leak-check=full',
					'--show-leak-kinds=all', '--errors-for-leak-kinds=all',
					'--error-exitcode=99', executable], memory=True)
	assert sha(compiler) == receipt['compiler_sha256']
	assert sha(CORPUS) == receipt['corpus_sha256']
	assert sha(Path(__file__)) == receipt['recipe_sha256']
	receipt['all_passed'] = True
	(directory / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')
	print(directory / 'checks.json')


if __name__ == '__main__':
	main(*sys.argv[1:])
