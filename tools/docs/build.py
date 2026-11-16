#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build the production documentation frontend or complete compiler out of source."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
sys.path.insert(0, str(ROOT/'tests/selfhost-ownership-syntax-27b'))
from support import execute, output_path, sha, tool_identity, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for name in ('compiler', 'link', 'build', 'runtime'):
		p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--compiler-sha256', required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), action='append', required=True)
	p.add_argument('--full', action='store_true')
	p.add_argument('--probe', action='store_true')
	a = p.parse_args()
	assert a.compiler.is_absolute() and sha(a.compiler) == a.compiler_sha256
	assert len(a.mode) == len(set(a.mode))
	build = output_path(a.build, WORK/'build')
	runtime = output_path(a.runtime, WORK/'runtime')
	build.mkdir(parents=True, exist_ok=False)
	runtime.mkdir(parents=True, exist_ok=False)
	(runtime/'executed-recipe.py.txt').write_bytes(Path(__file__).read_bytes())
	link = json.loads(a.link.read_text())
	toolchain_path = a.link.parent/'build-identity.json'
	toolchain = json.loads(toolchain_path.read_text())
	assert all(sha(path) == h for path,h in toolchain['tools'].items())
	env = dict(os.environ)
	env.update({key:value for key,value in toolchain['environment'].items() if value is not None})
	env.update(CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1')
	env.pop('LD_PRELOAD', None)
	env.pop('VALGRIND_OPTS', None)
	assert subprocess.check_output(['llvm-config', '--version'], env=env).strip() == b'23.1.4'
	baseline = json.loads((WORK/'runtime/selfhost27d/fixed-source.json').read_text())
	libraries = [ROOT/row['path'] for row in baseline['source_rows'] if row['path'].startswith('lib/')]
	assert not (a.full and a.probe)
	folders = ('source', 'syntax', 'semantic') if a.probe else ('source', 'syntax', 'semantic', 'docs')
	inputs = sorted((ROOT/'compiler').rglob('*.astra')) if a.full else [path for folder in folders for path in sorted((ROOT/'compiler'/folder).glob('*.astra'))]
	if not a.full:
		inputs += [ROOT/'compiler/driver/front-end.astra', ROOT/('tests/api-docs/probe.astra' if a.probe else 'tests/api-docs/driver.astra')]
	inputs += libraries
	providers = {n:h for n,h in link['objects'].items() if a.full or Path(n).name != 'llvm-capi.o'}
	assert all(sha(n) == h for n,h in providers.items())
	tools = {}
	for executable in (a.compiler, Path('/usr/bin/cc'), Path('/usr/bin/time')):
		executable = executable.resolve()
		tools[str(executable)] = sha(executable)
		linked = subprocess.run(['ldd', executable], capture_output=True, text=True, env=env)
		assert 'not found' not in linked.stdout
		for word in linked.stdout.split():
			if word.startswith('/') and Path(word).is_file():
				dependency = Path(word).resolve()
				tools[str(dependency)] = sha(dependency)
	assert {h for n,h in tools.items() if 'libLLVM' in n} == {'3149b73c3118dee2d2829a210b422ca89a4aa0064b57e77936ede12bdcfe750d'}
	for source in [*inputs, ROOT/'compiler/docs/host.c']:
		witness = runtime/'source-witness'/source.relative_to(ROOT)
		witness.parent.mkdir(parents=True, exist_ok=True)
		witness.write_bytes(source.read_bytes())
		witness.chmod(0o444)
	identity = dict(producer=dict(path=str(a.compiler), sha256=a.compiler_sha256), full=a.full, source_revision=subprocess.check_output(['git', '-C', ROOT, 'rev-parse', 'HEAD'], text=True).strip(), sources={str(n):sha(n) for n in inputs}, providers=providers, tools=tools, recipe_sha256=sha(__file__), host_source_sha256=sha(ROOT/'compiler/docs/host.c'), exact_toolchain_receipt=str(toolchain_path), toolchain_receipt_sha256=sha(toolchain_path), environment={key:env.get(key) for key in ('PATH', 'LD_LIBRARY_PATH', 'LIBRARY_PATH', 'LC_ALL')})
	write(runtime/'identity.json', identity)
	host = build/'docs-host.o'
	argv = ['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', ROOT/'compiler/docs/host.c', '-o', host]
	r = execute(argv, runtime/'host', env=env)
	assert r['status'] == 'EXPECTED_OUTCOME', r
	def profile(mode):
		obj = build/('astrac-'+mode+'.o')
		exe = build/('astrac-'+mode)
		argv = [a.compiler, '-c', '-'+mode, '-o', obj, *inputs]
		write(runtime/(mode+'-plan.json'), dict(argv=list(map(str, argv)), output_preexisting=obj.exists()))
		compiled = execute(argv, runtime/(mode+'-compile'), timeout=10800, env=env)
		print(mode, compiled['status'], compiled['seconds'], flush=True)
		if compiled['status'] != 'EXPECTED_OUTCOME':
			return mode, dict(status='COMPILE_FAILED', compile=compiled)
		argv = ['cc', '-no-pie', obj, *providers, host]
		if a.full: argv += ['-lLLVM-23']
		argv += ['-o', exe]
		linked = execute(argv, runtime/(mode+'-link'), env=env)
		assert linked['status'] == 'EXPECTED_OUTCOME', linked
		if not a.full:
			dependencies = subprocess.check_output(['ldd', exe], text=True)
			assert 'LLVM' not in dependencies
		assert all(sha(path) == h for path,h in identity['sources'].items())
		return mode, dict(status='BUILT_NOT_QUALIFIED', path=str(exe), sha256=sha(exe), object=str(obj), object_sha256=sha(obj), compile=compiled, link=linked)
	with ThreadPoolExecutor(max_workers=len(a.mode)) as pool:
		products = dict(pool.map(profile, a.mode))
	write(runtime/'result.json', dict(status='BUILT_NOT_QUALIFIED' if all(v['status'] == 'BUILT_NOT_QUALIFIED' for v in products.values()) else 'COMPILE_FAILED', products=products, identity_sha256=sha(runtime/'identity.json')))


if __name__ == '__main__':
	main()
