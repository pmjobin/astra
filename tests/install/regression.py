#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""One current local qualification plan, using the existing independent suites."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tools/ci'))
from common import clean_environment, external, require, run, sha, verify, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for name in ('products', 'identity', 'link', 'toolchain', 'build', 'runtime'):
		p.add_argument('--'+name, type=Path, required=True)
	a = p.parse_args()
	products = json.loads(a.products.read_text())['products']
	require(set(products) == {'O0', 'O2'}, 'both current compiler profiles required')
	for product in products.values():
		for image in (product, product['native'], product['doc']):
			require(sha(image['path']) == image['sha256'], 'compiler identity mismatch')
	build, runtime = external(a.build), external(a.runtime)
	tools = json.loads(a.toolchain.read_text())
	require(all(sha(path) == digest for path, digest in tools['tools'].items()), 'toolchain identity mismatch')
	env = clean_environment()
	env.update({key:value for key, value in tools['environment'].items() if value is not None})
	require(subprocess.check_output(['llvm-config', '--version'], env=env).strip() == b'23.1.4', 'wrong LLVM')
	lock = json.loads((ROOT/'tools/ci/llvm-linux.json').read_text())
	for name in ('llvm-config', 'opt', 'llc'):
		path = Path(shutil.which(name, path=env['PATH']))
		verify(path, lock['files']['bin/'+name])
		tools['tools'][str(path)] = sha(path)
		# Older suites explicitly record LIBRARY_PATH even when they link no LLVM.
		# Derive a new receipt; leave the generation's original receipt unchanged.
	tools['environment']['LIBRARY_PATH'] = tools['environment']['LD_LIBRARY_PATH']
	tools['generation_receipt_sha256'] = sha(a.toolchain)
	toolchain = runtime/'qualification-toolchain.json'
	write(toolchain, tools)
	plans = []
	def plan(label, recipe, options, timeout):
		plans.append(dict(label=label, recipe=recipe, recipe_sha256=sha(ROOT/recipe), argv=[sys.executable, '-B', str(ROOT/recipe), *map(str, options)], timeout=timeout))
	shared = ['--products', a.products, '--toolchain', toolchain]
	plan('native', 'tests/api-docs/qualify.py', [*shared, '--link', a.link, '--build', build/'native', '--runtime', runtime/'native'], 14400)
	plan('books', 'tests/books/run.py', [*shared, '--keep-going', '--link', a.link, '--build', build/'books', '--runtime', runtime/'books'], 7200)
	plan('limits', 'tests/books/limits.py', [*shared, '--keep-going', '--build', build/'limits', '--runtime', runtime/'limits'], 7200)
	plan('grammar', 'tests/books/grammar.py', [*shared, '--link', a.link, '--build', build/'grammar', '--runtime', runtime/'grammar', '--preflight'], 1800)
	plan('docs-native', 'tests/api-docs/native.py', [*shared, '--build', build/'docs-native', '--runtime', runtime/'docs-native'], 3600)
	for mode, product in products.items():
		label = mode+'-docs'
		plan(label, 'tests/api-docs/run.py', ['--compiler', product['path'], '--compiler-sha256', product['sha256'], '--toolchain', toolchain, '--build-identity', a.identity, '--runtime', runtime/label], 1800)
		label = mode+'-api'
		plan(label, 'tools/docs/preview.py', [*shared, '--identity', a.identity, '--mode', mode, '--build', build/label, '--runtime', runtime/label], 1800)
	write(runtime/'plans.json', plans)
	(runtime/'executed-recipe.py.txt').write_bytes(Path(__file__).read_bytes())
	expected = {'native':'CURRENT_CONSOLIDATED_NATIVE_ABI_OWNER_PHYSICAL_PASS', 'books':'BOOK_CURRENT_NATIVE_O0_O2_STRICT_MEMORY_PASS', 'limits':'CURRENT_GENERIC_LAZY_CAPTURE_COMPREHENSION_AND_PARSER_BOUNDARIES_PASS', 'grammar':'GRAMMAR_DUMP_PREFLIGHT_PASS', 'docs-native':'CURRENT_COMPLETE_COMPILER_DOCS_ISOLATION_AND_COMMENT_EQUIVALENCE_PASS', 'O0-docs':'FOCUSED_NATIVE_DOCS_ACCEPTANCE_PASS', 'O2-docs':'FOCUSED_NATIVE_DOCS_ACCEPTANCE_PASS', 'O0-api':'CURRENT_COMPILER_REAL_API_PREVIEWS_PASS', 'O2-api':'CURRENT_COMPILER_REAL_API_PREVIEWS_PASS'}
	def execute(row):
		try:
			run(row['argv'], runtime/(row['label']+'-controller'), env, timeout=row['timeout'], cwd=ROOT)
			receipt = runtime/row['label']/'result.json'
			require(receipt.is_file(), 'suite has no acceptance receipt')
			require(json.loads(receipt.read_text())['status'] == expected[row['label']], 'suite did not establish its native acceptance contract')
			result = dict(label=row['label'], completed=True, receipt_sha256=sha(receipt), status=json.loads(receipt.read_text())['status'])
		except (ValueError, OSError, subprocess.TimeoutExpired) as error:
			result = dict(label=row['label'], completed=False, error=str(error))
		print(json.dumps(result), flush=True)
		return result
	with ThreadPoolExecutor(max_workers=3) as pool:
		results = list(pool.map(execute, plans))
	passed = all(row['completed'] for row in results)
	write(runtime/'result.json', dict(status='CURRENT_LOCAL_CONSOLIDATED_REGRESSION_PASS' if passed else 'CURRENT_LOCAL_CONSOLIDATED_REGRESSION_FAILED', suites=results, plans_sha256=sha(runtime/'plans.json'), products_sha256=sha(a.products), products=products, toolchain_sha256=sha(toolchain), scope='Current Linux native ABI/ownership/source-owner/physical mutation suites; all 63 Book cases; exact generic/lazy/profile boundary controls; parser dump preflight; API isolation/schema/render/memory. Grammar typed-source regeneration is not claimed. No Windows, hosted CI or historical C0 memory credit.'))
	require(passed, 'current qualification has failed suites; inspect retained receipts')


if __name__ == '__main__':
	main()
