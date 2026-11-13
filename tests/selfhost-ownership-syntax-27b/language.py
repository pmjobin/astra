#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Focused real native source-policy proof; outputs and exact reuse are external."""
import argparse
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


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--compiler-sha256', required=True)
	p.add_argument('--producer-kind', choices=('c0', 'astra'), required=True)
	p.add_argument('--build', type=Path, required=True)
	p.add_argument('--runtime', type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), action='append', required=True)
	a = p.parse_args()
	assert re.fullmatch('[0-9a-f]{64}', a.compiler_sha256)
	assert sha(a.compiler) == a.compiler_sha256
	build = output_path(a.build, WORK/'build')
	runtime = output_path(a.runtime, WORK/'runtime')
	build.mkdir(parents=True, exist_ok=True)
	runtime.mkdir(parents=True, exist_ok=True)
	assert not (runtime/'result.json').exists(), 'use a fresh receipt directory'
	base = json.loads((ROOT/'compiler/syntax/model.json').read_text())
	assert base['format'] == 'astra-syntax-model/1'
	import runpy
	constants = runpy.run_path(str(ROOT/'tests/selfhost-typecore/build.py'))
	inputs = [*sorted((ROOT/'compiler/source').glob('*.astra')),
		*sorted((ROOT/'compiler/syntax').glob('*.astra')), Path(__file__).with_suffix('.astra'),
		*[ROOT/('lib/astra/'+name+'.astra') for name in constants['LIBRARIES']]]
	sources = {str(path):sha(path) for path in inputs}
	tools = tool_identity([a.compiler, *[shutil.which(name) for name in ('gcc', 'cc', 'as', 'ld', 'llvm-config', 'opt', 'llc')]])
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	env = dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1')
	env.pop('LD_PRELOAD', None)
	env.pop('VALGRIND_OPTS', None)
	commands = []
	def run(name, argv, expected=0, timeout=900):
		argv = list(map(str, argv))
		r = execute(argv, runtime/name, expected=expected, timeout=timeout, env=env)
		commands.append(dict(name=name, argv=argv, observation=r))
		write(runtime/'commands.json', commands)
		assert r['status'] == 'EXPECTED_OUTCOME', (name, r)
		return r
	def cached(name, argv, target, dependencies):
		argv = list(map(str, argv))
		identity = dict(argv=argv, inputs={str(path):sha(path) for path in [*dependencies, Path(__file__).with_name('support.py')]}, tools=tools,
			environment={key:env.get(key) for key in ('PATH', 'CC', 'CFLAGS', 'LDFLAGS', 'LD_LIBRARY_PATH', 'LC_ALL', 'LANG')})
		sidecar = target.with_suffix(target.suffix+'.identity.json')
		if target.exists() or sidecar.exists():
			assert target.is_file() and sidecar.is_file(), 'incomplete product; use a fresh build directory'
			previous = json.loads(sidecar.read_text())
			assert previous['identity'] == identity and previous['sha256'] == sha(target), 'identity differs; use a fresh build directory'
			commands.append(dict(name=name, exact_product_reuse=True, product_sha256=sha(target), identity_sha256=sha(sidecar)))
			write(runtime/'commands.json', commands)
			return
		run(name, argv)
		assert all(sha(path) == digest for path, digest in identity['inputs'].items())
		write(sidecar, dict(identity=identity, sha256=sha(target)))
	if a.producer_kind == 'c0':
		run('semantic-preflight', [a.compiler, '--dump-semantics', *inputs], timeout=300)
	objects = []
	for name in constants['PROVIDERS']:
		source = ROOT/('lib/runtime/platform/'+name+'.c')
		deps = subprocess.check_output(['gcc', '-std=c11', '-M', source], text=True).replace('\\\n', ' ').split(':', 1)[1].split()
		target = build/(name+'.o')
		cached('provider-'+name, ['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', source, '-o', target], target, deps)
		objects.append(target)
	products = {}
	for mode in a.mode:
		target = build/('language-'+mode)
		if a.producer_kind == 'c0':
			links = [arg for path in objects for arg in ('--link-object', path)]
			cached(mode+'-build', [a.compiler, '-'+mode, *inputs, *links, '-o', target], target, [*inputs, *objects, Path(__file__)])
		else:
			obj = build/('language-'+mode+'.o')
			cached(mode+'-object', [a.compiler, '-c', '-'+mode, '-o', obj, *inputs], obj, [*inputs, Path(__file__)])
			cached(mode+'-link', ['cc', '-no-pie', obj, *objects, '-o', target], target, [obj, *objects])
		run(mode+'-native', [target], 42)
		run(mode+'-memory', ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', target], 42, 300)
		log = (runtime/(mode+'-memory')/'stderr').read_bytes()
		assert all(marker in log for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
		products[mode] = dict(path=str(target), sha256=sha(target))
	assert all(sha(path) == digest for path, digest in sources.items())
	assert sha(a.compiler) == a.compiler_sha256
	write(runtime/'result.json', dict(status='FOCUSED_NATIVE_LANGUAGE_POLICY_COMPONENT_PASS', producer_kind=a.producer_kind,
		compiler=dict(path=str(a.compiler), sha256=a.compiler_sha256), sources=sources, products=products,
		commands_sha256=sha(runtime/'commands.json'), scope='Source/syntax and source-profile authentication only; ownership defaults, remaining syntax and full compiler acceptance are separate gates.'))
	print('FOCUSED_NATIVE_LANGUAGE_POLICY_COMPONENT_PASS', flush=True)


if __name__ == '__main__':
	main()
