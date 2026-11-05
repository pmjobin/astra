#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Recheck preserved bytes and configuration after TEXTCLASS engineering."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
BASE = 'ce7793ca133502baa73c00cd3fbbf4b8d143fd75'
PRIOR = ROOT.parent/'codex/work/astra/runtime/genclass16'


def sha(path):
	with Path(path).open('rb') as stream: return hashlib.file_digest(stream, 'sha256').hexdigest()


def read(path):
	return json.loads(Path(path).read_text())


def git(root, *args):
	return subprocess.check_output(['git', '-C', str(root), *args])


def main():
	p = argparse.ArgumentParser()
	for name in ('intake', 'output'): p.add_argument('--'+name, type=Path, required=True)
	a = p.parse_args(); assert not a.output.resolve().is_relative_to(ROOT)
	initial = read(a.intake/'result.json'); old = read(a.intake/'preservation-reference.json')
	assert initial['initial_head'] == BASE
	assert git(ROOT, 'merge-base', '--is-ancestor', BASE, 'HEAD') == b''
	donor = ROOT.parent/'astra-bootstrap'
	for path, expected in old['protected'].items(): assert sha(ROOT/path) == expected, path
	for path, expected in old['donor'].items():
		assert sha(donor/path) == expected['sha256'] and oct((donor/path).stat().st_mode & 0o777) == expected['mode'], path
	assert len(old['protected']) == 451 and len(old['donor']) == 6622
	assert git(donor, 'rev-parse', 'HEAD').decode().strip() == old['donor_head']
	assert git(donor, 'status', '--porcelain=v2', '--untracked-files=all').decode() == old['donor_status']
	prior = read(PRIOR/'preservation-v1.json')
	for path, expected in prior['hooks_unchanged'].items():
		assert sha(ROOT/path) == expected['sha256'] and oct((ROOT/path).stat().st_mode & 0o777) == expected['mode']
	workflow = {path:expected for path, expected in prior['workflow_unchanged'].items() if '__pycache__' not in path}
	for path, expected in workflow.items(): assert sha(path) == expected, path
	assert git(ROOT, 'config', '--local', '--show-origin', '--list').decode() == prior['local_config']
	assert git(ROOT, 'config', '--show-origin', '--list').decode() == initial['effective_config']
	worktrees = git(ROOT, 'worktree', 'list', '--porcelain').decode()
	def worktree_structure(raw, expected_head):
		records = []
		for record in raw.strip().split('\n\n'):
			lines = record.splitlines()
			if lines[0] == 'worktree '+str(ROOT):
				assert 'HEAD '+expected_head in lines
				lines = ['HEAD <authorized task revision>' if line.startswith('HEAD ') else line for line in lines]
			records.append(lines)
		return records
	assert worktree_structure(worktrees, git(ROOT, 'rev-parse', 'HEAD').decode().strip()) == worktree_structure(initial['worktrees'], BASE)
	assert git(ROOT, 'stash', 'list').decode() == initial['stash']
	unchanged = ('AGENTS.md', 'CODING_STYLE.md', 'codex-project.json')
	for path in unchanged:
		assert (ROOT/path).read_bytes() == git(ROOT, 'show', BASE+':'+path), path
	scope = read(ROOT/'format/scope.json'); old_scope = json.loads(git(ROOT, 'show', BASE+':format/scope.json'))
	# New authored lanes may be added; every pre-existing classification remains.
	def retained(left, right):
		if isinstance(left, dict): return all(key in right and retained(value, right[key]) for key, value in left.items())
		if isinstance(left, list): return all(value in right for value in left)
		return left == right
	assert retained(old_scope, scope), 'pre-existing formatter classification changed'
	toolchain = read(PRIOR/'toolchain.json')
	for group in ('sources', 'generated_c', 'runtime_libraries'):
		for path, expected in toolchain['C0'].get(group, {}).items(): assert sha(path) == expected, path
	assert sha(toolchain['C0']['path']) == toolchain['C0']['sha256']
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	assert sha(a.intake/'GENCLASS-16-report.zip') == '1c5c33637078926f383df6ebd7701d4bfd1204f07665b8863d7a399b40b5709f'
	result = dict(status='PASS', base=BASE, final_head=git(ROOT, 'rev-parse', 'HEAD').decode().strip(), final_tree=git(ROOT, 'rev-parse', 'HEAD^{tree}').decode().strip(), protected_files=451, donor_files=6622, donor_head=old['donor_head'], donor_status=old['donor_status'], workflow_unchanged=workflow, hooks_unchanged=prior['hooks_unchanged'], effective_config=initial['effective_config'], worktrees_initial=initial['worktrees'], worktrees_final=worktrees, worktree_structure='Exact paths, branches and other fields; only this authorized task checkout HEAD advances.', formatter_existing_classifications_preserved=True, C0_sources=len(toolchain['C0']['sources']), C0_runtime_libraries=len(toolchain['C0']['runtime_libraries']), original_report_sha256=sha(a.intake/'GENCLASS-16-report.zip'), tracked_status=git(ROOT, 'status', '--porcelain=v1', '--untracked-files=all').decode(), recipe_sha256=sha(__file__))
	with a.output.open('x') as out: out.write(json.dumps(result, indent=2)+'\n')
	print('451 protected files, 6622 read-only donor files, workflow/hooks/config, formatter lanes and pinned C0 preserved')


if __name__ == '__main__':
	main()
