#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Rehash inherited identities without claiming a fresh native qualification."""
import json
from pathlib import Path
from state import ROOT, RUNTIME, PRIOR, sha, read


def main():
	profiles = {}
	for mode in ('O0', 'O2'):
		rows = read(PRIOR/('inherited-v3-'+mode)/'result.json')['programs'] + read(PRIOR/('qualified-v3-'+mode)/'result.json')['programs']
		assert len(rows) == 202 and len({tuple(s['sha256'] for s in row['sources']) for row in rows}) == 202
		for row in rows:
			assert all(sha(s['path']) == s['sha256'] for s in row['sources'])
			for product in row.get('fresh_products', row.get('products')).values(): assert sha(product['path']) == product['sha256']
		controls = read(PRIOR/('controls-v3-'+mode)/'result.json')
		assert controls['original_statuses'] == dict(admitted=56, rejected=12, deferred=12)
		profiles[mode] = dict(retained_sources=202, original_statuses=controls['original_statuses'], source_identities=[row['sources'] for row in rows], fresh_native_reexecution=False, attribution='GENREF-24 native qualification; EFFECTS-25 rehash only')
	result = dict(status='INHERITED_IDENTITIES_REHASHED_ONLY', profiles=profiles, historical_proof_outputs=1044)
	(RUNTIME/'retained.json').write_text(json.dumps(result, indent=2)+'\n')
	print('202 source/product identities per profile retained; original 80 source statuses remain historical', flush=True)


if __name__ == '__main__':
	main()
