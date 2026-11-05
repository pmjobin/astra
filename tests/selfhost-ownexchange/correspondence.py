#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bind independently qualified source freezes to the final normal Git commit."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from state import ROOT, RUNTIME, BUILD, BASE, read, sha, git


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', required=True); p.add_argument('--output', type=Path, required=True); a = p.parse_args()
	assert a.output.resolve().is_relative_to(RUNTIME) and git('status', '--porcelain=v1', '--untracked-files=all') == ''
	head = git('rev-parse', 'HEAD').strip(); tree = git('rev-parse', 'HEAD^{tree}').strip(); bindings = {}; products = {}
	for mode in ('O0', 'O2'):
		product = BUILD/('native-'+a.version+'-'+mode)/('astra-llvm-'+mode); sidecar = product.with_suffix('.identity.json'); data = read(sidecar)
		assert sha(product) == data['sha256'] and [f for f in data['identity']['argv'] if f in ('-O0', '-O2')] == ['-'+mode]
		for name, expected in data['identity']['sources'].items():
			path = Path(name); assert sha(path) == expected
			if path.is_relative_to(RUNTIME/('source-'+a.version)): live = ROOT/path.relative_to(RUNTIME/('source-'+a.version))
			elif path.is_relative_to(ROOT): live = path
			else: continue
			relative = str(live.relative_to(ROOT)); raw = subprocess.check_output(['git', 'show', head+':'+relative], cwd=ROOT)
			assert hashlib.sha256(raw).hexdigest() == sha(live) == expected, relative
			bindings[relative] = dict(compiled_path=name, sha256=expected, Git_blob=git('rev-parse', head+':'+relative).strip())
		for name, expected in data['identity']['tools'].items(): assert sha(name) == expected
		products[mode] = dict(path=str(product), sha256=sha(product), identity_path=str(sidecar), identity_sha256=sha(sidecar), argv=data['identity']['argv'], source_dependencies=data['identity']['sources'], tools=data['identity']['tools'])
	changed = git('diff', '--name-only', BASE+'..'+head).splitlines(); assert all(p in bindings for p in changed if p.endswith('.astra'))
	source_costs = []
	for name in changed:
		before = subprocess.run(['git', 'show', BASE+':'+name], cwd=ROOT, capture_output=True)
		after = (ROOT/name).read_bytes()
		source_costs.append(dict(path=name, new=before.returncode != 0, before_bytes=len(before.stdout) if before.returncode == 0 else 0, after_bytes=len(after), before_lines=before.stdout.count(b'\n') if before.returncode == 0 else 0, after_lines=after.count(b'\n'), final_sha256=hashlib.sha256(after).hexdigest(), Git_blob=git('rev-parse', head+':'+name).strip(), generated=name in ('compiler/semantic/generic-copy.astra', 'compiler/semantic/generic-syntax-check.astra')))
	recipes = {}
	for receipt in RUNTIME.glob('final-'+a.version+'-*/result.json'):
		data = read(receipt); expected = data.get('recipe_sha256')
		if expected is None: continue
		live = ROOT/'tests/selfhost-ownexchange/qualify.py'
		candidates = [live, *sorted(RUNTIME.glob('source-*/tests/selfhost-ownexchange/qualify.py'))]
		actual = next((p for p in candidates if p.is_file() and sha(p) == expected), None); assert actual is not None, receipt
		recipes[str(receipt)] = dict(receipt_recorded_sha256=expected, retained_matching_path=str(actual), current_path=str(live), current_sha256=sha(live), classification='Root qualifier file hash observed at receipt completion. The family-selection-only edit occurred during some O0 runs; Python retains loaded code. Both file versions are preserved. Child manifests independently pin actual stage/oracle recipes and compiler products; no child semantic recipe changed.')
	for manifest in RUNTIME.glob('final-'+a.version+'-*/**/manifest.json'):
		for name, expected in read(manifest).get('recipes', {}).items():
			path = Path(name)
			if path.is_relative_to(ROOT):
				assert sha(path) == expected, name
				recipes[str(manifest)+':'+name] = dict(sha256=expected, Git_blob=git('rev-parse', head+':'+str(path.relative_to(ROOT))).strip())
	patch = subprocess.check_output(['git', 'diff', '--binary', BASE+'..'+head], cwd=ROOT)
	result = dict(status='PASS', final_head=head, final_tree=tree, initial_head=BASE, changed_paths=changed, source_costs=source_costs, numstat=git('diff', '--numstat', BASE+'..'+head), compiled_Git_bindings=bindings, exact_products=products, actual_oracle_recipe_bindings=recipes, changed_file_patch_sha256=hashlib.sha256(patch).hexdigest(), recipe_sha256=sha(__file__), limitation='Every changed compiled Astra source is bound to the tested frozen inputs and final Git blobs. Later documentation and packaging recipes do not alter those products.')
	a.output.write_text(json.dumps(result, indent=2)+'\n'); print('Source/product bindings:', len(bindings), head, tree)


if __name__ == '__main__':
	main()
