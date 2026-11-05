#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bind tested compiler inputs and late oracle recipes to exact Git blobs."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from state import ROOT, RUNTIME, BASE, read, sha, git


def main():
	p = argparse.ArgumentParser(); p.add_argument('--output', type=Path, required=True); a = p.parse_args(); assert a.output.resolve().is_relative_to(RUNTIME)
	assert git('status', '--porcelain=v1', '--untracked-files=all') == '', 'commit task-owned findings first'
	head = git('rev-parse', 'HEAD').strip(); tree = git('rev-parse', 'HEAD^{tree}').strip(); bindings = {}; products = {}
	def blob(path, expected, original_path):
		relative = str(path.relative_to(ROOT)); raw = subprocess.check_output(['git', 'show', head+':'+relative], cwd=ROOT)
		assert hashlib.sha256(raw).hexdigest() == expected and sha(path) == expected, relative
		bindings[relative] = dict(compiled_path=original_path, sha256=expected, Git_blob=git('rev-parse', head+':'+relative).strip())
	for mode in ('O0', 'O2'):
		product = ROOT.parent/('codex/work/astra/build/indexpath18/native-v5-'+mode)/('astra-llvm-'+mode); sidecar = product.with_suffix('.identity.json'); data = read(sidecar)
		assert sha(product) == data['sha256'] and [flag for flag in data['identity']['argv'] if flag in ('-O0', '-O2')] == ['-'+mode]
		for path, expected in data['identity']['sources'].items():
			path = Path(path); assert sha(path) == expected
			if path.is_relative_to(RUNTIME/'source-v5'): blob(ROOT/path.relative_to(RUNTIME/'source-v5'), expected, str(path))
			elif path.is_relative_to(ROOT): blob(path, expected, str(path))
		for path, expected in data['identity']['tools'].items(): assert sha(path) == expected
		products[mode] = dict(path=str(product), sha256=sha(product), identity_path=str(sidecar), identity_sha256=sha(sidecar), argv=data['identity']['argv'], source_dependencies=data['identity']['sources'], tools=data['identity']['tools'])
	changed = git('diff', '--name-only', BASE+'..'+head).splitlines()
	assert all(path in bindings for path in changed if path.endswith('.astra')), 'changed compiled Astra source not bound to tested products'
	# Early Class-only runs used the unchanged predecessor collector. Its
	# record-only fallback was then added and exercised by the final new O0/O2
	# corpus. Preserve both recipe versions under their actual Git identities.
	recipes = {}
	for manifest in RUNTIME.glob('qualification-*/**/manifest.json'):
		data = read(manifest)
		for path, expected in data.get('recipes', {}).items():
			path = Path(path)
			if not path.is_relative_to(ROOT): continue
			relative = str(path.relative_to(ROOT)); current = sha(path)
			if current == expected: commit = head
			else:
				raw = subprocess.check_output(['git', 'show', BASE+':'+relative], cwd=ROOT); assert hashlib.sha256(raw).hexdigest() == expected, (relative, expected); commit = BASE
			recipes[str(manifest)+':'+relative] = dict(path=relative, observed_sha256=expected, source_commit=commit, current_sha256=current)
	patch = subprocess.check_output(['git', 'diff', '--binary', BASE+'..'+head, '--', *changed], cwd=ROOT)
	result = dict(status='PASS', final_head=head, final_tree=tree, initial_head=BASE, changed_paths=changed, compiled_Git_bindings=bindings, exact_products=products, actual_oracle_recipe_bindings=recipes, changed_file_patch_sha256=hashlib.sha256(patch).hexdigest(), recipe_sha256=sha(__file__), limitation='Source routing is explicit from the retained source-v5 build inputs to these exact final Git blobs. Historical collector runs retain their original recipe revision; they are not relabelled as executing a later script. Documentation/evidence recipes do not alter compiled products.')
	a.output.write_text(json.dumps(result, indent=2)+'\n'); print(len(bindings), 'tested source/recipe Git bindings;', head, tree)


if __name__ == '__main__':
	main()
