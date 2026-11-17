#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Verify a local generation and make a portable, content-bound packaging input."""
import argparse
import json
from pathlib import Path

from common import ROOT, require, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--products', type=Path, required=True)
	p.add_argument('--identity', type=Path, required=True)
	p.add_argument('--output', type=Path, required=True)
	a = p.parse_args()
	products = json.loads(a.products.read_text())
	identity = json.loads(a.identity.read_text())
	require(products['identity_sha256'] == sha(a.identity), 'generation identity receipt mismatch')
	sources = {}
	for name, item in identity['sources'].items():
		path = Path(item['path'] if isinstance(item, dict) else name)
		digest = item['sha256'] if isinstance(item, dict) else item
		require(path.is_relative_to(ROOT) and sha(path) == digest, 'generation source changed: '+str(path))
		sources[str(path.relative_to(ROOT))] = digest
	rows = {}
	for mode, row in products['products'].items():
		require(sha(row['object']) == row['object_sha256'], 'generation object mismatch')
		require(sha(row['path']) == row['sha256'], 'generation executable mismatch')
		rows[mode] = dict(object_sha256=row['object_sha256'], compiler_sha256=row['sha256'])
	write(a.output, dict(format='astra-native-handoff/1', status='AUTHENTICATED_GENERATION_INPUT', source_commit=identity.get('source_commit', identity.get('source_revision')), sources=sources, products=rows, producer=identity.get('seed', identity.get('producer')), generation_receipt_sha256=sha(a.products), identity_sha256=sha(a.identity), qualification='Current installed and regression tests required; build alone gives no PASS'))


if __name__ == '__main__':
	main()
