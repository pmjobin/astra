#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Consolidated existing native/ABI/owner/physical suites for current host profiles."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
OLD = ROOT/'tests/selfhost-ownership-syntax-27b'
MODERN = ROOT/'tests/selfhost-expressive-language-27c'
sys.path.insert(0, str(OLD))
from support import execute, output_path, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for name in ('products', 'link', 'toolchain', 'build', 'runtime'):
		p.add_argument('--'+name, type=Path, required=True)
	a = p.parse_args()
	products = json.loads(a.products.read_text())['products']
	assert set(products) == {'O0', 'O2'}
	assert all(row['status'] == 'BUILT_NOT_QUALIFIED' and sha(row['path']) == row['sha256'] for row in products.values())
	build = output_path(a.build, WORK/'build')
	runtime = output_path(a.runtime, WORK/'runtime')
	build.mkdir(parents=True, exist_ok=False)
	runtime.mkdir(parents=True, exist_ok=False)
	(runtime/'executed-recipe.py.txt').write_bytes(Path(__file__).read_bytes())
	toolchain = json.loads(a.toolchain.read_text())
	assert all(sha(path) == h for path,h in toolchain['tools'].items())
	env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1', CCACHE_DISABLE='1')
	env.update({key:value for key,value in toolchain['environment'].items() if value is not None})
	env.pop('LD_PRELOAD', None)
	env.pop('VALGRIND_OPTS', None)
	assert subprocess.check_output(['llvm-config', '--version'], env=env).strip() == b'23.1.4'
	c0 = WORK/'build/selfhost27b/c0-recovery-safealloc2/astrac'
	assert sha(c0) == '19d744c828551b2184f06552740db1beb5b6eeb326b8e98ba56d2dfa5bca31b6'
	oracle = WORK/'runtime/selfhost27c-dev20/inputs.json'
	plans = []
	for mode, product in products.items():
		identity = ['--compiler', product['path'], '--compiler-sha256', product['sha256']]
		linked = [*identity, '--c0', str(c0), '--c0-sha256', sha(c0), '--link', str(a.link)]
		for feature in ('named', 'match', 'range', 'format', 'collection'):
			plans.append((mode+'-'+feature, MODERN/'named.py', [*linked, '--oracle-library-inputs', str(oracle), '--feature', feature]))
		features = ('initial', 'records', 'conditional', 'compound', 'weak', 'borrowed', 'errors', 'workload')
		plans.append((mode+'-ownership', OLD/'native.py', [*linked, '--oracle-library-inputs', str(oracle), *[part for feature in features for part in ('--feature', feature)]]))
		plans.append((mode+'-intrinsic', OLD/'intrinsic.py', linked))
		plans.append((mode+'-C-client', ROOT/'tests/selfhost-convergence-27d/c-client.py', [*identity, '--link', str(a.link)]))
		plans.append((mode+'-physical-owner', OLD/'physical.py', identity))
		for feature in ('range', 'enum'):
			plans.append((mode+'-physical-'+feature, MODERN/'physical.py', [*identity, '--feature', feature]))
		if mode == 'O2':
			plans.append((mode+'-source-owner', MODERN/'component.py', [*linked, '--producer-kind', 'astra', '--layer', 'semantic', '--mode', 'O0', '--mode', 'O2', '--semantic-oracle-inputs', str(oracle)]))
	write(runtime/'plans.json', [dict(label=label, recipe=str(recipe), recipe_sha256=sha(recipe), options=options) for label,recipe,options in plans])
	def job(plan):
		label, recipe, options = plan
		argv = ['python3', '-B', recipe, *options, '--build', build/label, '--runtime', runtime/label]
		result = execute(argv, runtime/(label+'-controller'), timeout=14400, env=env)
		receipt = runtime/label/'result.json'
		print(label, result['status'], round(result['seconds'], 3), flush=True)
		return dict(label=label, argv=list(map(str, argv)), result=result, receipt_sha256=sha(receipt) if receipt.is_file() else None)
	with ThreadPoolExecutor(max_workers=4) as pool:
		results = list(pool.map(job, plans))
	assert all(sha(row['path']) == row['sha256'] for row in products.values())
	passed = all(row['result']['status'] == 'EXPECTED_OUTCOME' and row['receipt_sha256'] for row in results)
	write(runtime/'result.json', dict(status='CURRENT_CONSOLIDATED_NATIVE_ABI_OWNER_PHYSICAL_PASS' if passed else 'CURRENT_CONSOLIDATED_NATIVE_ABI_OWNER_PHYSICAL_FAILURE', products=products, suites=results, plans_sha256=sha(runtime/'plans.json'), LLVM='23.1.4', historical_scope='Rebuilt C0 is an authenticated comparison seed only; its memory NOT_PASS and the 1044 lost historical records remain separate. This run is current engineering evidence, not restoration or a release qualification.'))
	assert passed


if __name__ == '__main__':
	main()
