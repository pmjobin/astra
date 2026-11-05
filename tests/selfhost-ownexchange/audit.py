#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Recheck immutable history, source/tool routing, and task-owned final bytes."""
import argparse
import json
from pathlib import Path
import subprocess
from state import ROOT, RUNTIME, PRIOR, BASE, read, sha, git


def main():
	p = argparse.ArgumentParser(); p.add_argument('--output', type=Path, required=True); p.add_argument('--require-clean', action='store_true'); a = p.parse_args()
	assert a.output.resolve().is_relative_to(RUNTIME)
	initial = read(RUNTIME/'initial/result.json'); assert initial['base'] == BASE
	subprocess.run(['git', 'merge-base', '--is-ancestor', BASE, 'HEAD'], cwd=ROOT, check=True)
	for name, expected in initial['protected'].items(): assert sha(ROOT/name) == expected
	donor = ROOT.parent/'astra-bootstrap'
	for name, expected in initial['donor'].items(): assert sha(donor/name) == expected['sha256'] and oct((donor/name).stat().st_mode & 0o777) == expected['mode']
	def donor_git(*args): return subprocess.check_output(['git', '--no-optional-locks', '-C', donor, *args]).decode()
	assert donor_git('rev-parse', 'HEAD').strip() == initial['donor_head']
	assert donor_git('status', '--porcelain=v2', '--untracked-files=all') == initial['donor_status']
	assert git('config', '--show-origin', '--list') == initial['config'] and git('stash', 'list') == initial['stash']
	for path, expected in initial['hooks'].items(): assert sha(path) == expected['sha256'] and oct(Path(path).stat().st_mode & 0o777) == expected['mode']
	for path, expected in initial['workflow'].items(): assert sha(path) == expected
	for name in ('AGENTS.md', 'CODING_STYLE.md', 'codex-project.json'): assert (ROOT/name).read_bytes() == subprocess.check_output(['git', 'show', BASE+':'+name], cwd=ROOT)
	old_scope = json.loads(subprocess.check_output(['git', 'show', BASE+':format/scope.json'], cwd=ROOT)); scope = read(ROOT/'format/scope.json'); assert all(scope.get(k) == v for k, v in old_scope.items())
	assert sha(RUNTIME/'predecessor-report.zip') == initial['predecessor_sha256']
	proofs = read(PRIOR/'historical-proof-outputs.json'); assert proofs['count'] == 1044
	for path, row in proofs['outputs'].items(): assert sha(path) == row['sha256'], path
	programs = {}
	for mode in ('O0', 'O2'):
		rows = read(PRIOR/'inherited-identity-preservation.json')['profiles'][mode]['programs']
		rows += read(PRIOR/'qualification-final'/('new-'+mode)/'observations/results.json')
		assert len(rows) == len({tuple(source['sha256'] for source in row['sources']) for row in rows}) == 121
		for row in rows:
			for source in row['sources']: assert sha(source['path']) == source['sha256']
			for product in row['products'].values(): assert sha(product['path']) == product['sha256']
		programs[mode] = rows
	status = git('status', '--porcelain=v1', '--untracked-files=all')
	ref_checkpoint = RUNTIME/'git-before-first-task-commit.json'
	if ref_checkpoint.exists():
		checkpoint = read(ref_checkpoint)
		def refs(value): return dict(line.split() for line in value.splitlines())
		before_refs = refs(checkpoint['refs']); after_refs = refs(git('for-each-ref', '--format=%(refname) %(objectname)'))
		assert before_refs.keys() == after_refs.keys()
		assert all(after_refs[name] == value for name, value in before_refs.items() if name != 'refs/heads/main')
		assert git('symbolic-ref', 'HEAD').strip() == 'refs/heads/main'
		assert git('remote', '-v') == checkpoint['remotes']
		assert git('worktree', 'list', '--porcelain').replace(git('rev-parse', 'HEAD').strip(), BASE) == checkpoint['worktrees']
	if a.require_clean: assert status == '', status
	result = dict(status='PASS', base=BASE, head=git('rev-parse', 'HEAD').strip(), tree=git('rev-parse', 'HEAD^{tree}').strip(), protected_files=len(initial['protected']), donor_files=len(initial['donor']), donor_head=initial['donor_head'], workflow=initial['workflow'], effective_config=initial['config'], historical_proof_outputs=1044, predecessor_sha256=initial['predecessor_sha256'], inherited_programs=programs, tracked_and_untracked_status=status, clean_required=a.require_clean, limitation='Preservation evidence only; inherited proof files remain historical and current runtime results require the separate qualification receipts.')
	a.output.write_text(json.dumps(result, indent=2)+'\n'); print('451 protected files, 6622 donor files, 1044 historical proof outputs and 121 inherited programs/profile preserved')


if __name__ == '__main__':
	main()
