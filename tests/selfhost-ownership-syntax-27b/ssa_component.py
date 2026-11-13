#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build current real SSA independently and admit an exact full compiler graph."""
import argparse
import ast
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

from support import execute, output_path, sha, tool_identity, write

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for key in ('compiler', 'c0', 'link', 'inputs', 'build', 'runtime'): p.add_argument('--'+key, type=Path, required=True)
	for key in ('compiler', 'c0'): p.add_argument('--'+key+'-sha256', required=True)
	a = p.parse_args()
	for key in ('compiler', 'c0'): assert re.fullmatch('[0-9a-f]{64}', getattr(a, key+'_sha256')) and sha(getattr(a, key)) == getattr(a, key+'_sha256')
	runtime = output_path(a.runtime, WORK/'runtime'); build = output_path(a.build, WORK/'build')
	runtime.mkdir(parents=True, exist_ok=False); build.mkdir(parents=True, exist_ok=False)
	graph = json.loads(a.inputs.read_text())['inputs']; assert len(graph) == 206 and all(sha(path) == h for path, h in graph.items())
	constants = ast.parse((ROOT/'tests/selfhost-typecore/build.py').read_text())
	libraries = next(ast.literal_eval(n.value) for n in constants.body if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'LIBRARIES' for t in n.targets))
	sources = [*[path for folder in ('source', 'syntax', 'semantic', 'core', 'cfg', 'ssa') for path in sorted((ROOT/'compiler'/folder).glob('*.astra'))], ROOT/'tests/selfhost-ownership-syntax-27b/ssa-query.astra', *[ROOT/('lib/astra/'+name+'.astra') for name in libraries]]
	inputs = {str(path):sha(path) for path in sources}; snapshot = runtime/'source-inputs'; snapshot.mkdir()
	actual = []
	for path in sources:
		name = path.relative_to(ROOT); destination = snapshot/name; destination.parent.mkdir(parents=True, exist_ok=True)
		destination.write_bytes(path.read_bytes()); destination.chmod(0o444); actual.append(destination)
	providers = {path:h for path, h in json.loads(a.link.read_text())['objects'].items() if Path(path).name != 'llvm-capi.o'}
	assert len(providers) == 6 and all(sha(path) == h for path, h in providers.items())
	tools = tool_identity([a.compiler, a.c0, '/usr/bin/time', *[shutil.which(n) for n in ('cc', 'as', 'ld', 'opt', 'llc')]])
	write(runtime/'identity.json', dict(compiler_sha256=a.compiler_sha256, c0_sha256=a.c0_sha256, inputs=inputs, full_graph=graph, full_graph_manifest_sha256=sha(a.inputs), tools=tools, providers=providers, actual_snapshot={str(path):sha(path) for path in actual}, scope='Actual current production source through SSA; LLVM backend and production CLI are not part of this focused component. No compiler, Stage2 or native-feature acceptance credit.'))
	commands = []; env = dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'); env.pop('LD_PRELOAD', None); env.pop('VALGRIND_OPTS', None)
	def run(name, argv, timeout=600):
		argv = list(map(str, argv)); r = execute(argv, runtime/name, timeout=timeout, env=env)
		commands.append(dict(name=name, argv=argv, result=r)); write(runtime/'commands.json', commands)
		print(name, r['status'], round(r['seconds'], 3), flush=True)
		assert r['status'] == 'EXPECTED_OUTCOME', (name, r)
	run('C0-Core-preflight', [a.c0, '--dump-core', *actual])
	obj = build/'ssa-query.o'; product = build/'ssa-query'
	run('current-SSA-component', [a.compiler, '-c', '-O2', '-o', obj, *actual], 3600)
	run('component-link', ['cc', '-no-pie', obj, *providers, '-o', product])
	write(runtime/'component-built.json', dict(status='CURRENT_SSA_COMPONENT_BUILT_NOT_QUALIFIED', product=dict(path=str(product), sha256=sha(product))))
	run('full-current-source-SSA', [product, *graph], 3600)
	assert (runtime/'full-current-source-SSA/stdout').read_bytes().startswith(b'CURRENT_PRODUCTION_SSA_VERIFIED_8M ')
	assert all(sha(path) == h for path, h in {**inputs, **graph, **providers, **tools}.items())
	write(runtime/'result.json', dict(status='FOCUSED_CURRENT_FULL_SOURCE_SSA_PASS_8M', product=dict(path=str(product), sha256=sha(product)), object_sha256=sha(obj), identity_sha256=sha(runtime/'identity.json'), commands_sha256=sha(runtime/'commands.json'), scope='Actual patched production SSA admits the exact 206-source compiler graph under its unchanged 8M work limit. This is not an LLVM/production compiler build, Stage2, memory or complete 27-B acceptance.'))


if __name__ == '__main__': main()
