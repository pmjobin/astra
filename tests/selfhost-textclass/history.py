#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Audit retained proof consumers without executing or relabelling old proofs."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
PRIOR = ROOT.parent/'codex/work/astra/runtime/genclass16'
BASE = 'ce7793ca133502baa73c00cd3fbbf4b8d143fd75'


def sha(path):
	with Path(path).open('rb') as stream: return hashlib.file_digest(stream, 'sha256').hexdigest()


def read(path):
	return json.loads(Path(path).read_text())


def main():
	p = argparse.ArgumentParser(); p.add_argument('--output', type=Path, required=True); a = p.parse_args()
	assert not a.output.resolve().is_relative_to(ROOT); a.output.mkdir(parents=True, exist_ok=False)
	started = time.monotonic(); original = read(PRIOR/'proof-reuse-product-reconciled.json')
	assert original['status'] == 'PRESERVED_IDENTITY_BOUND_HISTORICAL' and original['observations'] == 1044
	verified, blobs, products = {}, {}, []
	def verify(path, expected):
		path = Path(path)
		if sha(path) == expected: verified[str(path)] = expected; return
		assert path.is_relative_to(ROOT), ('changed external historical input', str(path))
		relative = str(path.relative_to(ROOT)); mapping = original['original_implementation_blobs'].get(relative, {})
		candidates = list(dict.fromkeys([mapping.get('commit', BASE), BASE, 'd18ad0d5afa8896bb1389813a8601febf913a9c6', '7b8fea49cdd3b3b8bb284d4299a12d31b01ba682']))
		for commit in candidates:
			r = subprocess.run(['git', 'show', commit+':'+relative], cwd=ROOT, capture_output=True)
			if r.returncode == 0 and hashlib.sha256(r.stdout).hexdigest() == expected:
				out = a.output/'original-inputs'/expected/path.name; out.parent.mkdir(parents=True, exist_ok=True)
				if out.exists(): assert out.read_bytes() == r.stdout
				else: out.write_bytes(r.stdout)
				blobs[str(path)] = dict(historical_commit=commit, expected_sha256=expected, current_sha256=sha(path), archived_path=str(out)); return
		raise AssertionError(('no exact historical Git blob', str(path), expected))
	for product in original['products']:
		path = Path(product['path']); sidecar = path.with_suffix('.identity.json')
		assert sha(path) == product['sha256'] and sha(sidecar) == product['identity_sha256']
		data = read(sidecar); assert data['sha256'] == product['sha256']
		for group in ('sources', 'tools'):
			for dependency, expected in data['identity'][group].items(): verify(dependency, expected)
		assert [flag for flag in data['identity']['argv'] if flag in ('-O0', '-O2')] == ['-'+path.name[-2:]]
		products.append(dict(path=str(path), sha256=sha(path), identity_path=str(sidecar), identity_sha256=sha(sidecar), original_flags=data['identity']['argv'], source_dependencies=len(data['identity']['sources']), tool_dependencies=len(data['identity']['tools'])))
	for path, expected in original['verified_inputs'].items(): verify(path, expected)
	result = dict(status='PRESERVED_IDENTITY_BOUND_HISTORICAL', observations=1044, predecessor_receipt=dict(path=str(PRIOR/'proof-reuse-product-reconciled.json'), sha256=sha(PRIOR/'proof-reuse-product-reconciled.json')), products=products, unchanged_inputs=verified, original_Git_blobs=blobs, seconds=time.monotonic()-started, limitation='These are retained proof consumers with their original flags and dependency bytes. No historical proof is executed or claimed as fresh verification of TEXTCLASS source. Current 80-status and native regressions are separate.')
	(a.output/'result.json').write_text(json.dumps(result, indent=2)+'\n')
	print('Audited six original proof products and sidecars;', len(verified), 'unchanged dependencies and', len(blobs), 'exact historical Git inputs; 1044 observations remain historical')


if __name__ == '__main__':
	main()
