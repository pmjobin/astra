#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Check protected bytes, read-only donor, workflow, hooks and Git routing."""
import argparse
import json
from pathlib import Path
import subprocess
from state import ROOT, RUNTIME, BASE, read, sha, git


def main():
	p = argparse.ArgumentParser(); p.add_argument('--output', type=Path, required=True); p.add_argument('--require-clean', action='store_true'); a = p.parse_args()
	assert a.output.resolve().is_relative_to(RUNTIME)
	initial = read(RUNTIME/'initial/result.json'); assert initial['base'] == BASE
	subprocess.run(['git', 'merge-base', '--is-ancestor', BASE, 'HEAD'], cwd=ROOT, check=True)
	for path, expected in initial['protected'].items(): assert sha(ROOT/path) == expected, path
	donor = ROOT.parent/'astra-bootstrap'
	for path, expected in initial['donor'].items():
		assert sha(donor/path) == expected['sha256'] and oct((donor/path).stat().st_mode & 0o777) == expected['mode'], path
	assert len(initial['protected']) == 451 and len(initial['donor']) == 6622
	def donor_git(*args):
		return subprocess.check_output(['git', '--no-optional-locks', '-C', str(donor), *args]).decode()
	assert donor_git('rev-parse', 'HEAD').strip() == initial['donor_head']
	assert donor_git('status', '--porcelain=v2', '--untracked-files=all') == initial['donor_status']
	assert git('config', '--show-origin', '--list') == initial['config'] and git('stash', 'list') == initial['stash']
	for path, expected in initial['hooks'].items(): assert sha(path) == expected['sha256'] and oct(Path(path).stat().st_mode & 0o777) == expected['mode']
	for path, expected in initial['workflow'].items(): assert sha(path) == expected, path
	for name in ('AGENTS.md', 'CODING_STYLE.md', 'codex-project.json'):
		assert (ROOT/name).read_bytes() == subprocess.check_output(['git', 'show', BASE+':'+name], cwd=ROOT)
	old_scope = json.loads(subprocess.check_output(['git', 'show', BASE+':format/scope.json'], cwd=ROOT)); scope = read(ROOT/'format/scope.json')
	assert all(scope.get(name) == value for name, value in old_scope.items()), 'pre-existing formatter classifications changed'
	def worktrees(text):
		return [[line if not line.startswith('HEAD ') else 'HEAD <authorized task commit>' for line in record.splitlines()] for record in text.strip().split('\n\n')]
	assert worktrees(git('worktree', 'list', '--porcelain')) == worktrees(initial['worktrees'])
	assert sha(RUNTIME/'predecessor-report.zip') == 'b201bdf8421aadf537f08092c8111cd47f76b494d2dfc829b400d7199d0669c8'
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	toolchain = initial['toolchain']['C0']; assert sha(toolchain['path']) == toolchain['sha256']
	for group in ('sources', 'generated_c', 'runtime_libraries'):
		for path, expected in toolchain.get(group, {}).items(): assert sha(path) == expected, path
	status = git('status', '--porcelain=v1', '--untracked-files=all')
	if a.require_clean: assert status == '', status
	result = dict(status='PASS', base=BASE, head=git('rev-parse', 'HEAD').strip(), tree=git('rev-parse', 'HEAD^{tree}').strip(), protected_files=451, donor_files=6622, donor_head=initial['donor_head'], donor_status=initial['donor_status'], workflow=initial['workflow'], hooks=initial['hooks'], effective_config=initial['config'], worktrees=git('worktree', 'list', '--porcelain'), stash=initial['stash'], previous_formatter_classifications='byte-equivalent JSON entries retained', predecessor_report_sha256=sha(RUNTIME/'predecessor-report.zip'), tracked_and_untracked_status=status, clean_required=a.require_clean, recipe_sha256=sha(__file__), limitation='Only this authorized checkout HEAD may advance. Donor commands use --no-optional-locks; no donor source, build, ref, worktree or configuration mutation is performed.')
	a.output.write_text(json.dumps(result, indent=2)+'\n'); print('451 protected files, 6622 donor identities, installed workflow, hooks, configuration and routing preserved')


if __name__ == '__main__':
	main()
