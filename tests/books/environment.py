#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Select the authenticated development environment for the opening lessons."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
PINS = {
	'products': '69a1f88e1a9d72000317cc73da79436f8277286cab335e6bc19e9437e0df407b',
	'toolchain': 'ad4d53dee8592908049d1dfadf8f8108bfe4d9b8e4d3641fc235b305ef2f1f9e',
}
KEYS = {'PATH', 'CC', 'CFLAGS', 'CXXFLAGS', 'LDFLAGS', 'LIBRARY_PATH', 'CPATH', 'C_INCLUDE_PATH', 'LD_LIBRARY_PATH', 'LC_ALL', 'LANG'}
LINK_PIN = '9ba7ba15c3f7fba9f1b1c27f457118e4d0b427a29aca60ca5ce1f2ce8105d95c'
PROVIDERS = {'args-posix.o': 'ARGS', 'files-posix.o': 'FILES', 'text-posix.o': 'TEXT', 'text-ops-posix.o': 'TEXT_OPS', 'diagnostics-trap.o': 'DIAGNOSTICS'}


def sha(path):
	with Path(path).open('rb') as stream:
		return hashlib.file_digest(stream, 'sha256').hexdigest()


def require(condition, message):
	if not condition:
		raise ValueError(message)


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--products', type=Path, required=True)
	p.add_argument('--toolchain', type=Path, required=True)
	p.add_argument('--host', choices=('O0', 'O2'), default='O0')
	p.add_argument('--link', type=Path, help='Also authenticate and expose the selected hosted provider objects')
	p.add_argument('--output', type=Path, required=True)
	a = p.parse_args()
	for key, expected in PINS.items():
		require(sha(getattr(a, key)) == expected, key+' manifest differs from the qualified development edition')
	products = json.loads(a.products.read_text())['products']
	tools = json.loads(a.toolchain.read_text())
	product = products[a.host]
	for image in (product, product['native'], product['doc']):
		require(sha(image['path']) == image['sha256'], 'compiler product changed: '+image['path'])
	for path, expected in tools['tools'].items():
		require(sha(path) == expected, 'tool or dependency changed: '+path)
	require(set(tools['environment']) <= KEYS, 'unrecognized environment setting')
	env = dict(os.environ)
	lines = ['# Generated from authenticated development manifests; source in this shell.']
	for key, value in tools['environment'].items():
		if value is None:
			env.pop(key, None)
			lines.append('unset '+key)
		else:
			env[key] = value
			lines.append('export '+key+'='+shlex.quote(value))
	require(subprocess.check_output(['llvm-config', '--version'], env=env).strip() == b'23.1.4', 'LLVM must be exactly 23.1.4')
	require(shutil.which('cc', path=env['PATH']) is not None, 'a host C linker command (cc) is required')
	lines.append('export ASTRA_HOST='+shlex.quote(product['path']))
	if a.link:
		require(sha(a.link) == LINK_PIN, 'link manifest differs from the qualified development edition')
		objects = json.loads(a.link.read_text())['objects']
		selected = set()
		for path, expected in objects.items():
			require(sha(path) == expected, 'provider changed: '+path)
			name = Path(path).name
			if name in PROVIDERS:
				selected.add(name)
				lines.append('export ASTRA_PROVIDER_'+PROVIDERS[name]+'='+shlex.quote(path))
		require(selected == set(PROVIDERS), 'hosted provider set is incomplete')
	out = a.output
	require(out.is_absolute() and out.resolve().is_relative_to(WORK/'build'), 'output must be an absolute path below '+str(WORK/'build'))
	require(not any(p.is_symlink() for p in (out, *out.parents)), 'output must not traverse a symbolic link')
	out.parent.mkdir(parents=True, exist_ok=True)
	with out.open('x') as stream:
		stream.write('\n'.join(lines)+'\n')
	print('Environment ready:', out)
	print('Compiler host:', a.host, '; LLVM: 23.1.4; this does not install a compiler.')


if __name__ == '__main__':
	try:
		main()
	except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
		print('Book environment unavailable:', error, file=sys.stderr)
		print('Use the qualified external products described in docs/guide/tooling.md; no substitute was selected.', file=sys.stderr)
		sys.exit(1)
