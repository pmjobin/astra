#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Focused production-source frontend consumer; native host gates are separate."""
import argparse
import ast
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
sys.path.insert(0, str(ROOT/'tests/selfhost-ownership-syntax-27b'))
from support import execute, output_path, sha, tool_identity, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for name in ('compiler', 'c0', 'link', 'build', 'runtime'):
		p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--compiler-sha256', required=True)
	p.add_argument('--c0-sha256', required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), action='append', required=True)
	p.add_argument('--layer', choices=('syntax', 'binding', 'semantic', 'ssa', 'types'), default='syntax')
	p.add_argument('--producer-kind', choices=('astra', 'c0'), default='astra')
	p.add_argument('--consumer', type=Path)
	a = p.parse_args()
	if a.consumer is None: a.consumer = Path(__file__).with_name(a.layer+'.astra')
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	assert sha(a.compiler) == a.compiler_sha256 and sha(a.c0) == a.c0_sha256
	assert a.producer_kind != 'c0' or a.compiler_sha256 == a.c0_sha256
	build = output_path(a.build, WORK/'build'); build.mkdir(parents=True, exist_ok=False)
	runtime = output_path(a.runtime, WORK/'runtime'); runtime.mkdir(parents=True, exist_ok=False)
	model = ast.parse((ROOT/'tests/selfhost-typecore/build.py').read_text())
	constants = {t.id:ast.literal_eval(n.value) for n in model.body if isinstance(n, ast.Assign) for t in n.targets if isinstance(t, ast.Name) and t.id == 'LIBRARIES'}
	folders = ['source', 'syntax']
	if a.layer in ('semantic', 'ssa'): folders.append('semantic')
	if a.layer == 'ssa': folders.extend(('core', 'cfg', 'ssa'))
	inputs = [*[path for folder in folders for path in sorted((ROOT/'compiler'/folder).glob('*.astra'))], a.consumer, *[ROOT/('lib/astra/'+n+'.astra') for n in constants['LIBRARIES']]]
	if a.layer == 'binding': inputs.extend(ROOT/('compiler/semantic/'+n+'.astra') for n in ('model', 'types', 'names', 'index'))
	if a.layer == 'types':
		inputs = [*sorted((ROOT/'compiler/source').glob('*.astra')), *[ROOT/('compiler/syntax/'+n+'.astra') for n in ('model', 'token', 'arena-support')], *[ROOT/('compiler/semantic/'+n+'.astra') for n in ('model', 'types')], a.consumer, *[ROOT/('lib/astra/'+n+'.astra') for n in constants['LIBRARIES']]]
	providers = {n:h for n,h in json.loads(a.link.read_text())['objects'].items() if Path(n).name not in ('llvm-capi.o', 'arguments.o')}
	assert len(providers) == 5 and all(sha(n) == h for n,h in providers.items())
	actual = []; snapshot = runtime/'source-inputs'
	for path in inputs:
		destination = snapshot/path.relative_to(ROOT); destination.parent.mkdir(parents=True, exist_ok=True)
		destination.write_bytes(path.read_bytes()); destination.chmod(0o444); actual.append(destination)
	recipes = [Path(__file__), ROOT/'tests/selfhost-typecore/build.py', ROOT/'tests/selfhost-ownership-syntax-27b/support.py']
	identity = dict(layer=a.layer, producer_kind=a.producer_kind, revision=subprocess.check_output(['git', '-C', ROOT, 'rev-parse', 'HEAD'], text=True).strip(), sources={str(n):sha(n) for n in [*inputs, *recipes]}, actual_sources={str(n):sha(n) for n in actual}, providers=providers, tools=tool_identity([a.compiler, a.c0, *[shutil.which(n) for n in ('opt', 'llc', 'cc', 'valgrind', 'llvm-config')]]), environment={n:os.environ.get(n) for n in ('PATH', 'LD_LIBRARY_PATH', 'LIBRARY_PATH', 'LC_ALL', 'LANG')})
	write(runtime/'identity.json', identity)
	env = dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1')
	env.pop('LD_PRELOAD', None); env.pop('VALGRIND_OPTS', None)
	commands = []
	def run(name, argv, expected=0, timeout=900):
		r = execute(argv, runtime/name, expected=expected, timeout=timeout, env=env)
		commands.append(dict(name=name, argv=list(map(str, argv)), result=r)); write(runtime/'commands.json', commands)
		print(name, r['status'], round(r['seconds'], 3), flush=True)
		assert r['status'] == 'EXPECTED_OUTCOME', (name, r)
	run('semantic-preflight', [a.c0, '--dump-semantics', *actual])
	products = {}
	for mode in a.mode:
		obj = build/('component-'+mode+'.o'); target = build/('component-'+mode)
		if a.producer_kind == 'c0':
			links = [arg for path in providers for arg in ('--link-object', path)]
			run(mode+'-compile-link', [a.compiler, '-'+mode, *actual, *links, '-o', target], timeout=3600)
		else:
			run(mode+'-compile', [a.compiler, '-c', '-'+mode, '-o', obj, *actual], timeout=1800)
			run(mode+'-link', ['cc', '-no-pie', obj, *providers, '-o', target])
		run(mode+'-native', [target], 42)
		run(mode+'-memory', ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', target], 42)
		log = (runtime/(mode+'-memory')/'stderr').read_bytes()
		assert all(m in log for m in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
		products[mode] = dict(path=str(target), sha256=sha(target))
	assert all(sha(n) == h for n,h in {**identity['actual_sources'], **providers, **identity['tools']}.items())
	write(runtime/'result.json', dict(status='FOCUSED_EXPRESSIVE_'+a.layer.upper()+'_COMPONENT_PASS', compiler_sha256=a.compiler_sha256, products=products, identity_sha256=sha(runtime/'identity.json'), commands_sha256=sha(runtime/'commands.json'), limitation='Selected '+a.layer+' source consumers only; no complete host, ABI, native new-feature or milestone qualification.'))


if __name__ == '__main__': main()
