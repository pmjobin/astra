#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build the real production driver from a frozen, committed current source graph."""
import argparse
import ast
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
from support import execute, output_path, tool_identity, write


def sha(path):
	with Path(path).open('rb') as stream:
		return hashlib.file_digest(stream, 'sha256').hexdigest()


def git(*args):
	return subprocess.check_output(['git', '-C', str(ROOT), *args])


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--compiler-sha256', required=True)
	p.add_argument('--producer-kind', choices=('c0', 'astra'), required=True)
	p.add_argument('--semantic-oracle', type=Path)
	p.add_argument('--semantic-oracle-sha256')
	p.add_argument('--build', type=Path, required=True)
	p.add_argument('--runtime', type=Path, required=True)
	p.add_argument('--retain-ir', action='store_true', help='Retain C0 O2 optimized IR for exact downstream reuse and diagnostics')
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	a = p.parse_args()
	assert not a.retain_ir or a.producer_kind == 'c0' and a.mode == 'O2'
	assert re.fullmatch('[0-9a-f]{64}', a.compiler_sha256) and sha(a.compiler) == a.compiler_sha256
	oracle = a.compiler
	oracle_sha = a.compiler_sha256
	if a.producer_kind == 'astra':
		assert a.semantic_oracle and a.semantic_oracle_sha256
		oracle = a.semantic_oracle
		oracle_sha = a.semantic_oracle_sha256
		assert re.fullmatch('[0-9a-f]{64}', oracle_sha) and sha(oracle) == oracle_sha
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	build = output_path(a.build, WORK/'build')
	runtime = output_path(a.runtime, WORK/'runtime')
	build.mkdir(parents=True, exist_ok=False)
	runtime.mkdir(parents=True, exist_ok=False)
	revision = git('rev-parse', 'HEAD').decode().strip()
	tree = git('rev-parse', 'HEAD^{tree}').decode().strip()
	compiler = [n for n in git('ls-tree', '-r', '--name-only', revision, 'compiler').decode().splitlines() if n.endswith('.astra')]
	assert 'compiler/driver/main.astra' in compiler and len(compiler) >= 196
	model = ast.parse((ROOT/'tests/selfhost-typecore/build.py').read_text())
	constants = {t.id:ast.literal_eval(n.value) for n in model.body if isinstance(n, ast.Assign) for t in n.targets if isinstance(t, ast.Name) and t.id in ('LIBRARIES', 'PROVIDERS')}
	libraries = ['lib/astra/'+name+'.astra' for name in constants['LIBRARIES']]
	provider_names = [(name, 'lib/runtime/platform/'+name+'.c', []) for name in constants['PROVIDERS']]
	provider_names += [('llvm-capi', 'compiler/backend/llvm/capi.c', subprocess.check_output(['llvm-config', '--cflags'], text=True).split()), ('arguments', 'compiler/driver/arguments.c', [])]
	names = sorted(set([*compiler, *libraries, *git('ls-tree', '-r', '--name-only', revision, 'lib/runtime/platform').decode().splitlines(), 'compiler/backend/llvm/capi.c', 'compiler/driver/arguments.c']))
	snapshot = runtime/'source-inputs'
	rows = []
	for name in names:
		data = git('show', revision+':'+name)
		assert data == (ROOT/name).read_bytes(), 'commit task-owned source before building: '+name
		path = snapshot/name
		path.parent.mkdir(parents=True, exist_ok=True)
		path.write_bytes(data)
		path.chmod(0o444)
		rows.append(dict(original_path=str(ROOT/name), input_path=str(path), sha256=sha(path), bytes=len(data), git_blob=git('rev-parse', revision+':'+name).decode().strip()))
	inputs = {str(snapshot/name):sha(snapshot/name) for name in [*compiler, *libraries]}
	write(runtime/'snapshot.json', dict(revision=revision, tree=tree, sources=rows))
	write(runtime/'inputs.json', dict(format='astra-current-inputs/1', revision=revision, inputs=inputs))
	env = dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1')
	env.pop('VALGRIND_OPTS', None)
	env.pop('LD_PRELOAD', None)
	tool_paths = [a.compiler, oracle, '/usr/bin/time', *[shutil.which(name) for name in ('gcc', 'cc', 'as', 'ld', 'llvm-config', 'opt', 'llc')]]
	for name in ('cc1', 'collect2'):
		tool_paths.append(subprocess.check_output(['gcc', '-print-prog-name='+name], text=True).strip())
	for name in ('crt1.o', 'crti.o', 'crtn.o', 'crtbegin.o', 'crtend.o', 'libgcc.a', 'libgcc_s.so'):
		tool_paths.append(subprocess.check_output(['gcc', '-print-file-name='+name], text=True).strip())
	tools = tool_identity(tool_paths)
	commands = []
	def run(name, argv, timeout=300):
		argv = list(map(str, argv))
		result = execute(argv, runtime/name, timeout=timeout, env=env)
		commands.append(dict(name=name, argv=argv, result=result))
		write(runtime/'commands.json', commands)
		print(name, result['status'], round(result['seconds'], 3), flush=True)
		assert result['status'] == 'EXPECTED_OUTCOME', (name, result)
	run('semantic-preflight', [oracle, '--dump-semantics', *inputs], 600)
	objects = {}
	for name, source, flags in provider_names:
		path = snapshot/source
		dependencies = subprocess.check_output(['gcc', '-std=c11', *flags, '-M', path], text=True).replace('\\\n', ' ').split(':', 1)[1].split()
		target = build/(name+'.o')
		identity = dict(argv=['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *flags, '-c', str(path), '-o', str(target)], dependencies={n:sha(n) for n in dependencies}, tools=tools)
		run('provider-'+name, identity['argv'])
		assert all(sha(p) == h for p, h in identity['dependencies'].items())
		write(target.with_suffix('.identity.json'), dict(identity=identity, sha256=sha(target)))
		objects[str(target)] = sha(target)
	library = subprocess.check_output(['llvm-config', '--link-shared', '--libs', 'core', 'analysis', 'native'], text=True).strip()
	assert library.startswith('-l') and ' ' not in library
	target = build/('astrac-'+a.mode)
	if a.retain_ir:
		argv = [a.compiler, '--dump-llvm', '-O2', *inputs]
	elif a.producer_kind == 'c0':
		links = [arg for path in objects for arg in ('--link-object', path)]
		argv = [a.compiler, '-'+a.mode, *inputs, *links, '--link-library', library[2:], '-o', target]
	else:
		obj = build/('astrac-'+a.mode+'.o')
		argv = [a.compiler, '-c', '-'+a.mode, '-o', obj, *inputs]
	write(runtime/'build-identity.json', dict(argv=list(map(str, argv)), sources=inputs, tools=tools, objects=objects, library=library, recipe_sha256=sha(__file__), support_sha256=sha(Path(__file__).with_name('support.py')), environment={k:env.get(k) for k in ('PATH', 'CC', 'CFLAGS', 'CXXFLAGS', 'LDFLAGS', 'LIBRARY_PATH', 'CPATH', 'C_INCLUDE_PATH', 'LD_LIBRARY_PATH', 'LC_ALL', 'LANG')}))
	run('compiler-build', argv, 7200)
	retained_ir = None
	if a.retain_ir:
		ir = build/'astrac-C0-O2.ll'
		ir.write_bytes((runtime/'compiler-build/stdout').read_bytes())
		assert re.search(rb'^define [^\n]*@main\(', ir.read_bytes(), re.M), 'C0 dump did not retain the executable entry'
		run('compiler-ir-verify', ['opt', '-passes=verify', '-disable-output', ir])
		obj = build/('astrac-'+a.mode+'.o')
		run('compiler-ir-object', ['llc', '-O=2', '-relocation-model=pic', '-filetype=obj', ir, '-o', obj])
		retained_ir = dict(path=str(ir), sha256=sha(ir), optimization='C0 O2 optimized executable dump; not raw O0 IR')
	if a.producer_kind == 'astra' or a.retain_ir:
		run('compiler-link', ['cc', '-no-pie', obj, *objects, library, '-o', target])
	assert sha(a.compiler) == a.compiler_sha256 and sha(oracle) == oracle_sha and all(sha(p) == h for p, h in inputs.items())
	assert all(sha(p) == h for p, h in tools.items())
	assert all(sha(p) == h for p, h in objects.items())
	write(runtime/'link.json', dict(objects=objects, libraries=[library]))
	write(runtime/'result.json', dict(status='PRODUCTION_DRIVER_BUILT_NOT_QUALIFIED', revision=revision, tree=tree, compiler_sources=len(compiler), libraries=len(libraries), producer=dict(path=str(a.compiler), sha256=a.compiler_sha256, kind=a.producer_kind), product=dict(path=str(target), sha256=sha(target)), mode=a.mode, retained_ir=retained_ir, commands_sha256=sha(runtime/'commands.json'), identity_sha256=sha(runtime/'build-identity.json'), scope='Build receipt only; run feature, negative, memory, ABI and physical correspondence gates separately. No Stage3 or release credit.'))
	print('PRODUCTION_DRIVER_BUILT_NOT_QUALIFIED', target, sha(target), flush=True)


if __name__ == '__main__':
	main()
