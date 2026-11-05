#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bind compiled snapshot inputs to final Git bytes and explicit ledger reuse."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
	with Path(path).open('rb') as stream: return hashlib.file_digest(stream, 'sha256').hexdigest()


def read(path):
	return json.loads(Path(path).read_text())


def main():
	p = argparse.ArgumentParser()
	for name in ('snapshot', 'O0', 'O2', 'ledger-snapshot', 'ledger-component', 'live-ledger', 'output'): p.add_argument('--'+name, type=Path, required=True)
	a = p.parse_args()
	assert subprocess.check_output(['git', 'status', '--porcelain=v1', '--untracked-files=all']) == b''
	head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
	tree = subprocess.check_output(['git', 'rev-parse', 'HEAD^{tree}'], text=True).strip()
	def product(component, snapshot, expected_mode):
		sidecar = component.with_suffix('.identity.json'); data = read(sidecar)
		assert sha(component) == data['sha256']
		assert [flag for flag in data['identity']['argv'] if flag in ('-O0', '-O2')] == ['-'+expected_mode]
		routing = []
		for group in ('sources', 'tools'):
			for path, expected in data['identity'][group].items():
				path = Path(path); assert sha(path) == expected, str(path)
				if path.is_relative_to(snapshot):
					relative = str(path.relative_to(snapshot)); live = ROOT/relative
					assert sha(live) == expected, ('changed final source', relative)
					blob = subprocess.check_output(['git', 'show', head+':'+relative]); assert hashlib.sha256(blob).hexdigest() == expected
					routing.append(dict(compiled_path=str(path), final_Git_path=relative, sha256=expected))
				elif path.is_relative_to(ROOT):
					relative = str(path.relative_to(ROOT)); blob = subprocess.check_output(['git', 'show', head+':'+relative]); assert hashlib.sha256(blob).hexdigest() == expected
					routing.append(dict(compiled_path=str(path), final_Git_path=relative, sha256=expected))
		assert routing
		return dict(path=str(component), sha256=sha(component), sidecar_sha256=sha(sidecar), mode=expected_mode, compiled_snapshot=str(snapshot), exact_final_Git_inputs=routing)
	profiles = {mode:product(getattr(a, mode), a.snapshot, mode) for mode in ('O0', 'O2')}
	assert [(row['final_Git_path'], row['sha256']) for row in profiles['O0']['exact_final_Git_inputs']] == [(row['final_Git_path'], row['sha256']) for row in profiles['O2']['exact_final_Git_inputs']]
	ledger = product(a.ledger_component, a.ledger_snapshot, 'O0')
	live = read(a.live_ledger); assert live['component_sha256'] == ledger['sha256']
	for row in live['files']:
		if 'synthetic_source_hex' in row:
			assert hashlib.sha256(bytes.fromhex(row['synthetic_source_hex'])).hexdigest() == row['sha256']; continue
		path = Path(row['path']); assert path.is_relative_to(ROOT) and sha(path) == row['sha256']
		assert hashlib.sha256(subprocess.check_output(['git', 'show', head+':'+str(path.relative_to(ROOT))])).hexdigest() == row['sha256']
	result = dict(status='PASS', final_head=head, final_tree=tree, profiles=profiles, source_ledger_consumer=ledger, exact_final_live_ledger_sha256=sha(a.live_ledger), explicit_reuse='The ledger consumer compiles only source/syntax/semantic and hosted-library inputs. Those exact input bytes match final Git. Later Core/CFG release lowering and its tests do not enter the ledger consumer; no rebuilt or whole-source proof is inferred from that exact semantic-product reuse.', limitation='Final live and each frozen historical source cohort retain distinct path/node/span/hash populations. All source-to-native and safety claims require their separate native witnesses and gate receipts.')
	with a.output.open('x') as out: out.write(json.dumps(result, indent=2)+'\n')
	print('Final O0/O2 compiler inputs and reused semantic observer inputs match exact committed bytes')


if __name__ == '__main__':
	main()
