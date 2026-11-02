#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact-identity, external native checked-type build; no host installation."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
LIBRARIES = ['base/errors', 'base/diagnostics', 'text/utf8-message', 'text/utf8-byte-builder', 'text/scalar-format', 'hosted/text-ops', 'collections/bag', 'collections/vector', 'hosted/files', 'hosted/text']
PROVIDERS = ['args-posix', 'files-posix', 'text-posix', 'text-ops-posix', 'diagnostics-trap']


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def build(compiler, directory, capture, modes=('O0', 'O2')):
	directory.mkdir(parents=True, exist_ok=True)
	paths = {compiler}
	for tool in ('gcc', 'ld', 'as', 'pkg-config', 'llvm-config'):
		paths.add(Path(shutil.which(tool)).resolve())
	for exe in list(paths):
		out = subprocess.run(['ldd', exe], capture_output=True, text=True).stdout
		for word in out.split():
			if word.startswith('/') and Path(word).is_file(): paths.add(Path(word).resolve())
	gcc = shutil.which('gcc')
	for name in ('crt1.o', 'crti.o', 'crtn.o', 'crtbegin.o', 'crtend.o', 'libgcc.a', 'libgcc_s.so'):
		path = Path(subprocess.check_output([gcc, '-print-file-name=' + name], text=True).strip())
		if path.is_file(): paths.add(path.resolve())
	tools = {str(p): sha(p) for p in sorted(paths)}
	products = {}
	def product(argv, target, sources, name):
		identity = dict(argv=list(map(str, argv)), sources={str(p): sha(p) for p in sources}, tools=tools)
		cache = target.with_suffix('.identity.json')
		previous = json.loads(cache.read_text()) if cache.exists() else None
		if target.exists() and previous and previous['identity'] == identity and previous['sha256'] == sha(target):
			capture(None, name + '-exact-reuse', details=dict(identity=sha(cache), product=sha(target)))
		else:
			capture(None, name + '-input-identity', details=identity)
			capture(['/usr/bin/time', '-v', *argv], name)
			assert identity['sources'] == {str(p): sha(p) for p in sources}
			cache.write_text(json.dumps(dict(identity=identity, sha256=sha(target)), indent=2) + '\n')
		products[target.name] = dict(path=str(target), sha256=sha(target), identity=sha(cache))
	objects = []
	for name in PROVIDERS:
		source = ROOT / f'lib/runtime/platform/{name}.c'
		deps = subprocess.check_output([gcc, '-std=c11', '-M', source], text=True).replace('\\\n', ' ').split(':', 1)[1].split()
		target = directory / (name + '.o')
		product([gcc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', source, '-o', target], target, [Path(p) for p in deps], name)
		objects += ['--link-object', target]
	sources = [*sorted((ROOT / 'compiler/source').glob('*.astra')), *sorted((ROOT / 'compiler/syntax').glob('*.astra')), *sorted((ROOT / 'compiler/semantic').glob('*.astra')), ROOT / 'tests/selfhost-typecore/query.astra', ROOT / 'tests/selfhost-parser/controls.astra', ROOT / 'tests/selfhost-parser/cursors.astra', *[ROOT / f'lib/astra/{p}.astra' for p in LIBRARIES]]
	for mode in modes:
		target = directory / ('astra-types-' + mode)
		product([compiler, '-' + mode, *sources, *objects, '-o', target], target, [*sources, *objects[1::2]], 'typecore-' + mode)
	return products


if __name__ == '__main__':
	import argparse
	p = argparse.ArgumentParser()
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--build', type=Path, required=True)
	p.add_argument('--runtime', type=Path, required=True)
	p.add_argument('--mode', action='append')
	a = p.parse_args()
	a.runtime.mkdir(parents=True, exist_ok=True)
	attempt = a.runtime / ('build-' + str(time.time_ns()))
	attempt.mkdir()
	def capture(argv, name, details=None):
		if argv is None:
			(attempt / (name + '.json')).write_text(json.dumps(details))
			return b''
		start = time.monotonic()
		r = subprocess.run(list(map(str, argv)), cwd=a.build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'))
		(attempt / (name + '.stdout')).write_bytes(r.stdout)
		(attempt / (name + '.stderr')).write_bytes(r.stderr)
		(attempt / (name + '.json')).write_text(json.dumps(dict(argv=list(map(str, argv)), exit=r.returncode, seconds=time.monotonic()-start)))
		print(name, r.returncode, flush=True)
		assert r.returncode == 0, r.stderr.decode(errors='replace').split('Command exited')[0][-3000:]
		return r.stdout
	products = build(a.compiler.resolve(), a.build.resolve(), capture, a.mode or ('O0', 'O2'))
	(attempt / 'products.json').write_text(json.dumps(products, indent=2))
