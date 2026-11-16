#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Link paired native/semantic images from one authenticated native Astra object."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
sys.path.insert(0, str(ROOT/'tests/selfhost-ownership-syntax-27b'))
from support import execute, output_path, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for name in ('products', 'identity', 'build', 'runtime'):
		p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), action='append', required=True)
	a = p.parse_args()
	identity = json.loads(a.identity.read_text())
	assert identity['full'] and len(a.mode) == len(set(a.mode))
	assert all(sha(path) == value for path,value in {**identity['sources'], **identity['tools'], **identity['providers']}.items())
	assert sha(ROOT/'compiler/docs/host.c') == identity['host_source_sha256']
	toolchain_path = Path(identity['exact_toolchain_receipt'])
	assert sha(toolchain_path) == identity['toolchain_receipt_sha256']
	toolchain = json.loads(toolchain_path.read_text())
	env = dict(os.environ)
	env.update({key:value for key,value in toolchain['environment'].items() if value is not None})
	env.pop('LD_PRELOAD', None)
	env.pop('VALGRIND_OPTS', None)
	assert subprocess.check_output(['llvm-config', '--version'], env=env).strip() == b'23.1.4'
	build = output_path(a.build, WORK/'build')
	runtime = output_path(a.runtime, WORK/'runtime')
	build.mkdir(parents=True, exist_ok=False)
	runtime.mkdir(parents=True, exist_ok=False)
	(runtime/'executed-recipe.py.txt').write_bytes(Path(__file__).read_bytes())
	auxiliary = [ROOT/'compiler/driver/doc-launch.c', ROOT/'compiler/driver/doc-guard.c']
	sources = {str(path):sha(path) for path in auxiliary}
	for path in auxiliary:
		(runtime/path.name).write_bytes(path.read_bytes())
	material = json.loads((a.identity.parent/'docs-build-identity.json').read_text())['material']
	material.update(image_link_recipe_sha256=sha(__file__), image_sources={str(path.relative_to(ROOT)):sha(path) for path in auxiliary})
	fingerprint = hashlib.sha256(json.dumps(material, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
	write(runtime/'docs-build-identity.json', dict(fingerprint=fingerprint, material=material, scope='Actual source/toolchain and paired-image link fingerprint; O0/O2 share this metadata'))
	commands = []
	def run(label, argv):
		result = execute(argv, runtime/label, env=env)
		commands.append(dict(label=label, argv=list(map(str, argv)), result=result))
		write(runtime/'commands.json', commands)
		assert result['status'] == 'EXPECTED_OUTCOME', label
	host = build/'docs-host.o'
	guard = build/'doc-guard.o'
	run('host', ['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-DASTRA_DOC_BUILD_SHA256="'+fingerprint+'"', '-c', ROOT/'compiler/docs/host.c', '-o', host])
	run('guard', ['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', auxiliary[1], '-o', guard])
	products = {}
	raw = json.loads(a.products.read_text())['products']
	for mode in a.mode:
		product = raw[mode]
		assert product['status'] == 'BUILT_NOT_QUALIFIED' and sha(product['path']) == product['sha256'] and sha(product['object']) == product['object_sha256']
		exe = build/('astrac-'+mode)
		native = exe.with_name(exe.name+'.native')
		doc = exe.with_name(exe.name+'.doc')
		common = ['cc', '-no-pie', product['object'], *identity['providers'], host]
		run(mode+'-native', [*common, '-lLLVM-23', '-o', native])
		undefined = subprocess.check_output(['nm', '-u', native], text=True, env=env)
		names = sorted(set(re.findall(r'\b(LLVM[A-Za-z0-9_]+)(?:@[^\s]+)?\s*$', undefined, re.M)))
		assert 1 < len(names) < 1024 and 'LLVMShutdown' in names and 'LLVMContextCreate' in names
		# These are link-time fatal aliases, never forwarding or generated ABI code.
		# The identical compiled semantic implementation is retained in both images.
		run(mode+'-doc', [*common, guard, *['-Wl,--defsym='+name+'=astrac_doc_backend_unavailable' for name in names], '-o', doc])
		run(mode+'-launcher', ['cc', '-std=c11', '-'+mode, '-Wall', '-Wextra', '-Werror', auxiliary[0], '-o', exe])
		for path in (exe, doc):
			assert 'LLVM' not in subprocess.check_output(['ldd', path], text=True, env=env)
		assert not re.search(r'\bLLVM[A-Za-z0-9_]+', subprocess.check_output(['nm', '-u', doc], text=True, env=env))
		products[mode] = dict(status='BUILT_NOT_QUALIFIED', path=str(exe), sha256=sha(exe), object=product['object'], object_sha256=product['object_sha256'], native=dict(path=str(native), sha256=sha(native)), doc=dict(path=str(doc), sha256=sha(doc)), forbidden_LLVM_imports=names)
	assert all(sha(path) == value for path,value in {**identity['sources'], **sources}.items())
	write(runtime/'result.json', dict(status='BUILT_NOT_QUALIFIED', products=products, raw_products_sha256=sha(a.products), source_identity_sha256=sha(a.identity), auxiliary_sources=sources, commands_sha256=sha(runtime/'commands.json'), build_identity_sha256=sha(runtime/'docs-build-identity.json'), scope='GNU/Linux x86-64 paired images; native behavior and semantic-only memory/isolation require independent qualification'))
	print(json.dumps(dict(status='BUILT_NOT_QUALIFIED', products=products)))


if __name__ == '__main__':
	main()
