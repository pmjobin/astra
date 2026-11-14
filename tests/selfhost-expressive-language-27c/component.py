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
	p.add_argument('--consumer', type=Path, default=Path(__file__).with_name('syntax.astra'))
	a = p.parse_args()
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	assert sha(a.compiler) == a.compiler_sha256 and sha(a.c0) == a.c0_sha256
	build = output_path(a.build, WORK/'build'); build.mkdir(parents=True, exist_ok=False)
	runtime = output_path(a.runtime, WORK/'runtime'); runtime.mkdir(parents=True, exist_ok=False)
	model = ast.parse((ROOT/'tests/selfhost-typecore/build.py').read_text())
	constants = {t.id:ast.literal_eval(n.value) for n in model.body if isinstance(n, ast.Assign) for t in n.targets if isinstance(t, ast.Name) and t.id == 'LIBRARIES'}
	inputs = [*sorted((ROOT/'compiler/source').glob('*.astra')), *sorted((ROOT/'compiler/syntax').glob('*.astra')), a.consumer, *[ROOT/('lib/astra/'+n+'.astra') for n in constants['LIBRARIES']]]
	providers = {n:h for n,h in json.loads(a.link.read_text())['objects'].items() if Path(n).name not in ('llvm-capi.o', 'arguments.o')}
	assert len(providers) == 5 and all(sha(n) == h for n,h in providers.items())
	identity = dict(sources={str(n):sha(n) for n in [*inputs, Path(__file__)]}, providers=providers, tools=tool_identity([a.compiler, a.c0, *[shutil.which(n) for n in ('opt', 'llc', 'cc', 'valgrind', 'llvm-config')]]), environment={n:os.environ.get(n) for n in ('PATH', 'LD_LIBRARY_PATH', 'LIBRARY_PATH', 'LC_ALL', 'LANG')})
	write(runtime/'identity.json', identity)
	env = dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1')
	env.pop('LD_PRELOAD', None); env.pop('VALGRIND_OPTS', None)
	commands = []
	def run(name, argv, expected=0, timeout=900):
		r = execute(argv, runtime/name, expected=expected, timeout=timeout, env=env)
		commands.append(dict(name=name, argv=list(map(str, argv)), result=r)); write(runtime/'commands.json', commands)
		print(name, r['status'], round(r['seconds'], 3), flush=True)
		assert r['status'] == 'EXPECTED_OUTCOME', (name, r)
	run('semantic-preflight', [a.c0, '--dump-semantics', *inputs])
	products = {}
	for mode in a.mode:
		obj = build/('component-'+mode+'.o'); target = build/('component-'+mode)
		run(mode+'-compile', [a.compiler, '-c', '-'+mode, '-o', obj, *inputs], timeout=1800)
		run(mode+'-link', ['cc', '-no-pie', obj, *providers, '-o', target])
		run(mode+'-native', [target], 42)
		run(mode+'-memory', ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', target], 42)
		log = (runtime/(mode+'-memory')/'stderr').read_bytes()
		assert all(m in log for m in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
		products[mode] = dict(path=str(target), sha256=sha(target))
	assert all(sha(n) == h for n,h in identity['sources'].items())
	write(runtime/'result.json', dict(status='FOCUSED_EXPRESSIVE_SYNTAX_COMPONENT_PASS', compiler_sha256=a.compiler_sha256, products=products, identity_sha256=sha(runtime/'identity.json'), commands_sha256=sha(runtime/'commands.json'), limitation='Focused typed syntax only; no complete semantic, host, ABI or milestone qualification.'))


if __name__ == '__main__': main()
