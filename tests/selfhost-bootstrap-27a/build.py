#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Freeze the complete Git compiler graph and use the existing measured builder.

Run inside the authenticated LLVM23.1.4 capsule. All output roots are explicit.
The reference host is a development preflight, never a self-build witness.
"""
import argparse
import ast
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tests/selfhost-compiler-complete'))
from run import C0_SHA256, WORK, git, sha
from acceleration import execute, output_path, run_jobs, tool_identity, write


def prepare(a):
	assert sha(a.compiler) == C0_SHA256
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	assert not git('diff', '--name-only').strip() and not git('diff', '--cached', '--name-only').strip()
	revision = git('rev-parse', 'HEAD').decode().strip()
	leaf = output_path(a.runtime/a.version, WORK/'runtime')
	build = output_path(a.build/a.version, WORK/'build')
	leaf.mkdir(); build.mkdir()
	model = ast.parse((ROOT/'tests/selfhost-typecore/build.py').read_text())
	constants = {t.id:ast.literal_eval(n.value) for n in model.body if isinstance(n, ast.Assign) for t in n.targets if isinstance(t, ast.Name) and t.id in ('LIBRARIES', 'PROVIDERS')}
	compiler = [p for p in git('ls-tree', '-r', '--name-only', revision, 'compiler').decode().splitlines() if p.endswith('.astra')]
	libraries = ['lib/astra/'+n+'.astra' for n in constants['LIBRARIES']]
	names = sorted(set(compiler+libraries+git('ls-tree', '-r', '--name-only', revision, 'lib/runtime/platform').decode().splitlines()+['compiler/backend/llvm/capi.c', 'compiler/driver/arguments.c']))
	rows = []; snapshot = leaf/'source-inputs'
	for name in names:
		data = git('show', revision+':'+name)
		assert data == (ROOT/name).read_bytes()
		path = snapshot/name; path.parent.mkdir(parents=True, exist_ok=True)
		path.write_bytes(data); path.chmod(0o444)
		rows.append(dict(original_path=str(ROOT/name), input_path=str(path), sha256=sha(path), bytes=len(data)))
	write(leaf/'snapshot.json', dict(revision=revision, tree=git('rev-parse', 'HEAD^{tree}').decode().strip(), sources=rows))
	inputs = {str(snapshot/n):sha(snapshot/n) for n in [*compiler, *libraries]}
	write(leaf/'inputs.json', dict(format='astra-current-inputs/1', revision=revision, inputs=inputs))
	write(leaf/'scope.json', dict(stage='native', compiler_sources={str(snapshot/n):inputs[str(snapshot/n)] for n in compiler}, compiler_modules=len(compiler), library_modules=len(libraries), production_driver='compiler/driver/main.astra', test_driver_inputs=[]))
	tools = tool_identity([a.compiler, *[shutil.which(n) for n in ('gcc', 'cc', 'ld', 'as', 'opt', 'llc', 'llvm-config')]])
	for n in ('cc1', 'collect2'):
		path = Path(subprocess.check_output(['gcc', '-print-prog-name='+n], text=True).strip()).resolve()
		tools[str(path)] = sha(path)
	for n in ('crt1.o', 'crti.o', 'crtn.o', 'crtbegin.o', 'crtend.o', 'libgcc.a', 'libgcc_s.so'):
		path = Path(subprocess.check_output(['gcc', '-print-file-name='+n], text=True).strip()).resolve()
		tools[str(path)] = sha(path)
	jobs = []
	providers = [(n, 'lib/runtime/platform/'+n+'.c', []) for n in constants['PROVIDERS']]
	providers += [('llvm-capi', 'compiler/backend/llvm/capi.c', subprocess.check_output(['llvm-config', '--cflags'], text=True).split()), ('arguments', 'compiler/driver/arguments.c', [])]
	for name, source, flags in providers:
		path = snapshot/source
		deps = subprocess.check_output(['gcc', '-std=c11', *flags, '-M', path], text=True).replace('\\\n', ' ').split(':', 1)[1].split()
		jobs.append(dict(id=name, argv=['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *flags, '-c', str(path), '-o', '{work}/'+name+'.o'], tools=tools, inputs={n:sha(n) for n in deps}, artifacts={'object':'{work}/'+name+'.o'}, cache='artifact', timeout_seconds=120, estimated_RSS_bytes=512*1024**2))
	result = run_jobs(dict(format='astra-native-jobs/1', jobs=jobs), leaf/'providers', build/'providers', a.runtime/'artifact-cache', jobs=3, max_jobs=3, reuse=True)
	assert not result['failed_jobs'], result['failed_jobs']
	objects = [result['jobs'][name]['artifacts']['object']['path'] for name, _, _ in providers]
	library = subprocess.check_output(['llvm-config', '--link-shared', '--libs', 'core', 'analysis', 'native'], text=True).strip()
	assert library.startswith('-l') and ' ' not in library
	links = [arg for path in objects for arg in ('--link-object', path)]+['--link-library', library[2:]]
	argv = [str(a.compiler), '-O2', *inputs, *links, '-o', str(build/'astrac-stage1')]
	sources = {**inputs, **{str(p):sha(p) for p in (Path(__file__), ROOT/'tests/selfhost-typecore/build.py')}, **{p:sha(p) for p in objects}}
	for job in jobs: sources.update(job['inputs'])
	identity = dict(argv=argv, sources=sources, tools=tools, environment={k:os.environ.get(k) for k in ('CC', 'CFLAGS', 'CXXFLAGS', 'LDFLAGS', 'PATH', 'LIBRARY_PATH', 'CPATH', 'C_INCLUDE_PATH', 'LD_LIBRARY_PATH', 'LC_ALL', 'LANG')}, CCACHE_DISABLE='1')
	write(leaf/'ownflow-O2-input-identity.json', identity)
	write(leaf/'link.json', dict(objects={p:sha(p) for p in objects}, libraries=[library], environment=identity['environment']))
	check = execute([a.compiler, '--dump-semantics', *inputs], leaf/'C0-semantics', timeout=600)
	assert check['status'] == 'EXPECTED_OUTCOME'
	print('FROZEN_COMPLETE_DRIVER_GRAPH', len(compiler), len(libraries), leaf, flush=True)
	if a.reference_host:
		preflight = execute([a.reference_host, '--native', build/'preflight.ll', *inputs], leaf/'preflight', timeout=1200)
		assert preflight['status'] == 'EXPECTED_OUTCOME'
		assert execute(['opt', '-passes=verify', '-disable-output', build/'preflight.ll'], leaf/'preflight-verify', timeout=300)['status'] == 'EXPECTED_OUTCOME'
	print('READY_FOR_EXISTING_ACCELERATE_COMPILE', leaf/'ownflow-O2-input-identity.json', flush=True)


def rebuild(a):
	leaf = output_path(a.runtime/a.version, WORK/'runtime'); build = output_path(a.build/a.version, WORK/'build')
	manifest = json.loads((a.inputs/'inputs.json').read_text()); inputs = manifest['inputs']
	assert all(sha(p) == h and Path(p).stat().st_mode & 0o222 == 0 for p, h in inputs.items())
	link = json.loads((a.inputs/'link.json').read_text())
	assert all(sha(p) == h for p, h in link['objects'].items())
	leaf.mkdir(); build.mkdir()
	commands = []
	def run(name, argv, expected=0, timeout=1200):
		argv = list(map(str, argv))
		before = {str(p):sha(p) for p in [a.producer, *inputs]}
		result = execute(argv, leaf/name, expected=expected, timeout=timeout)
		commands.append(dict(name=name, argv=argv, result=result, input_hashes=before))
		write(leaf/'commands.json', commands)
		assert result['status'] == 'EXPECTED_OUTCOME', (name, result)
		assert before == {p:sha(p) for p in before}
		print(name, result['exit'], result['seconds'], flush=True)
	raw = build/'compiler.ll'
	run('producer-version', [a.producer, '--version'])
	run('source-to-LLVM', [a.producer, '--emit-llvm', '-o', raw, *inputs], timeout=7200)
	run('raw-verify', ['opt', '-passes=verify', '-disable-output', raw])
	products = {}
	for mode in ('O0', 'O2'):
		ir = build/('compiler-'+mode+'.ll'); obj = build/('compiler-'+mode+'.o'); exe = build/('astrac-'+a.product+'-'+mode)
		run(mode+'-optimize', ['opt', '-passes=default<'+mode+'>', '-S', raw, '-o', ir])
		run(mode+'-verify', ['opt', '-passes=verify', '-disable-output', ir])
		run(mode+'-object', ['llc', '-filetype=obj', '-'+mode, ir, '-o', obj])
		run(mode+'-link', ['cc', '-no-pie', obj, *link['objects'], *link['libraries'], '-o', exe])
		run(mode+'-ELF', ['readelf', '-h', exe])
		run(mode+'-version', [exe, '--version'])
		for name, argv in [('symbols', ['nm', '-an', exe]), ('relocations', ['readelf', '-rW', obj]), ('machine-code', ['objdump', '-d', exe])]:
			run(mode+'-'+name, argv)
		products[mode] = {str(p):dict(sha256=sha(p), bytes=p.stat().st_size) for p in (raw, ir, obj, exe)}
	write(leaf/'result.json', dict(status='NATIVE_COMPILER_REBUILT_REQUIRES_BEHAVIORAL_QUALIFICATION', producer=str(a.producer), producer_sha256=sha(a.producer), frozen_manifest_sha256=sha(a.inputs/'inputs.json'), source_revision=manifest['revision'], products=products, limitation='This build receipt alone does not qualify self-hosting, equivalence or memory behavior. Final convergence is reserved for 27-D.'))


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('phase', choices=('prepare', 'rebuild'))
	p.add_argument('--build', type=Path, required=True); p.add_argument('--runtime', type=Path, required=True)
	p.add_argument('--version', required=True); p.add_argument('--compiler', type=Path)
	p.add_argument('--reference-host', type=Path); p.add_argument('--producer', type=Path)
	p.add_argument('--inputs', type=Path); p.add_argument('--product', default='stage2')
	a = p.parse_args(); assert a.version.isalnum() and a.product.isalnum()
	assert a.build.is_dir() and a.runtime.is_dir()
	if a.phase == 'prepare': prepare(a)
	else: rebuild(a)


if __name__ == '__main__':
	main()
