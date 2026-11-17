#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Continue untouched Book cases after a strict failure, without waiving failures."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tools/ci'))
from common import clean_environment, external, require, run, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for name in ('products', 'toolchain', 'link', 'original', 'build', 'runtime'):
		p.add_argument('--'+name, type=Path, required=True)
	a = p.parse_args()
	build, runtime = external(a.build), external(a.runtime)
	manifest = json.loads((ROOT/'tests/books/examples.json').read_text())
	original = json.loads((a.original/'commands.json').read_text())
	started = {row['id'] for row in manifest['cases'] if any(command['label'].startswith(row['id']+'-O') for command in original)}
	require(started, 'no original attempted cases')
	cases = [row['id'] for row in manifest['cases'] if row['id'] not in started]
	toolchain = json.loads(a.toolchain.read_text())
	env = clean_environment()
	env.update({key:value for key, value in toolchain['environment'].items() if value is not None})
	write(runtime/'plan.json', dict(original_commands_sha256=sha(a.original/'commands.json'), previously_started=sorted(started), remaining=cases, recipe_sha256=sha(ROOT/'tests/books/run.py')))
	def execute(case):
		argv = [sys.executable, '-B', ROOT/'tests/books/run.py', '--products', a.products, '--toolchain', a.toolchain, '--link', a.link, '--case', case, '--build', build/case, '--runtime', runtime/case]
		try:
			run(argv, runtime/(case+'-controller'), env, cwd=ROOT, timeout=1800)
			receipt = runtime/case/'result.json'
			require(json.loads(receipt.read_text())['status'] == 'BOOK_CURRENT_NATIVE_O0_O2_STRICT_MEMORY_PASS', 'case has no strict acceptance')
			result = dict(case=case, passed=True, receipt_sha256=sha(receipt))
		except ValueError as error:
			result = dict(case=case, passed=False, error=str(error))
		print(json.dumps(result), flush=True)
		return result
	with ThreadPoolExecutor(max_workers=3) as pool:
		results = list(pool.map(execute, cases))
	write(runtime/'result.json', dict(status='DIAGNOSTIC_CASE_COVERAGE_NOT_FULL_QUALIFICATION', cases=results, previously_started=sorted(started), total_manifest_cases=len(manifest['cases']), original=str(a.original), scope='Existing strict suite and expectations unchanged. Each case stops on its first failed check. Previously failed profiles remain failed; no full Book PASS is inferred.'))


if __name__ == '__main__':
	main()
