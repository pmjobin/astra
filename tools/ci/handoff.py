#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Verify a local generation and make a portable, content-bound packaging input."""
import argparse
import json
from pathlib import Path
import subprocess

from common import ROOT, require, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--system-llvm', action='store_true', help='Permit the audited C provider rebuild; compiler object sources stay exact')
	p.add_argument('--products', type=Path, required=True)
	p.add_argument('--identity', type=Path, required=True)
	p.add_argument('--output', type=Path, required=True)
	a = p.parse_args()
	products = json.loads(a.products.read_text())
	identity = json.loads(a.identity.read_text())
	require(products['identity_sha256'] == sha(a.identity), 'generation identity receipt mismatch')
	sources = {}
	provider_rebuilds = {}
	for name, item in identity['sources'].items():
		path = Path(item['path'] if isinstance(item, dict) else name)
		digest = item['sha256'] if isinstance(item, dict) else item
		require(path.is_relative_to(ROOT), 'generation source outside repository')
		name = str(path.relative_to(ROOT))
		if sha(path) != digest:
			require(a.system_llvm and name == 'compiler/backend/llvm/capi.c', 'generation source changed: '+name)
			original = subprocess.check_output(['git', 'show', identity.get('source_commit', identity.get('source_revision'))+':'+name], cwd=ROOT)
			import hashlib
			require(hashlib.sha256(original).hexdigest() == digest, 'original provider mismatch')
			require(original.split(b'\n', 1)[0] == path.read_bytes().split(b'\n', 1)[0], 'provider license changed')
			provider_rebuilds[name] = dict(original_sha256=digest, rebuilt_source_sha256=sha(path), change='22/23 header guard and branch-opcode adapter; native C provider recompiled against target headers; current ABI/physical qualification required')
		sources[name] = sha(path)
	rows = {}
	for mode, row in products['products'].items():
		require(sha(row['object']) == row['object_sha256'], 'generation object mismatch')
		require(sha(row['path']) == row['sha256'], 'generation executable mismatch')
		rows[mode] = dict(object_sha256=row['object_sha256'], compiler_sha256=row['sha256'])
	paths = ['docs', 'tools/ci', 'tools/docs', 'tools/release', 'tests/install', 'tests/books', 'lib', 'LICENSE.txt']
	require(not subprocess.check_output(['git', 'diff', 'HEAD', '--', *paths], cwd=ROOT), 'commit package inputs before handoff')
	tracked = subprocess.check_output(['git', 'ls-files', '--', *paths], cwd=ROOT, text=True).splitlines()
	package_sources = {name:sha(ROOT/name) for name in tracked}
	package_commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
	package_tree = subprocess.check_output(['git', 'rev-parse', 'HEAD^{tree}'], cwd=ROOT, text=True).strip()
	write(a.output, dict(format='astra-native-handoff/1', status='AUTHENTICATED_GENERATION_INPUT', provider_rebuilds=provider_rebuilds, source_commit=identity.get('source_commit', identity.get('source_revision')), sources=sources, products=rows, package_commit=package_commit, package_tree=package_tree, package_sources=package_sources, producer=identity.get('seed', identity.get('producer')), generation_receipt_sha256=sha(a.products), identity_sha256=sha(a.identity), qualification='Current installed and regression tests required; build alone gives no PASS'))


if __name__ == '__main__':
	main()
