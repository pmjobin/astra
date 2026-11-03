#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Recheck protected/donor/tool/local identities against the real task intake."""
import argparse
import hashlib
import json
from pathlib import Path
import stat
import subprocess

ROOT = Path(__file__).resolve().parents[2]
DONOR = ROOT.parent/'astra-bootstrap'


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def git(root, *args):
	return subprocess.check_output(['git', '--no-optional-locks', '-C', str(root), *args]).decode()


def identity(path):
	return dict(sha256=sha(path), mode=stat.S_IMODE(path.stat().st_mode), bytes=path.stat().st_size)


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--initial', type=Path, required=True)
	p.add_argument('--output', type=Path, required=True)
	a = p.parse_args(); initial = json.loads(a.initial.read_text())
	assert not a.output.resolve().is_relative_to(ROOT)
	assert git(ROOT, 'status', '--porcelain=v1', '--untracked-files=all') == ''
	start = initial['repository']
	assert start['head'] == '5cd200f8210482835f1ff80182a59fb1532801ba' and start['tree'] == 'acddbd3da33c771b956082e27d68a1bc98a53cfe'
	subprocess.run(['git', '-C', str(ROOT), 'merge-base', '--is-ancestor', start['head'], 'HEAD'], check=True)
	files = {name: identity(ROOT/name) for name in git(ROOT, 'ls-files', '-z').split('\0') if name}
	protected = {name: identity(ROOT/name) for name in initial['protected']}
	assert len(protected) == 451 and protected == initial['protected']
	donor_files = {name: identity(DONOR/name) for name in git(DONOR, 'ls-files', '-z').split('\0') if name}
	assert len(donor_files) == 6622 and donor_files == initial['donor']['files']
	assert git(DONOR, 'rev-parse', 'HEAD').strip() == initial['donor']['head']
	assert git(DONOR, 'status', '--porcelain=v1') == initial['donor']['status']
	assert all(sha(path) == digest for path, digest in initial['skill'].items())
	for name, expected in initial['local'].items():
		actual = identity(Path(name)); assert all(actual[key] == value for key, value in expected.items()), name
	changed = git(ROOT, 'diff', '--name-only', '-z', start['head'], 'HEAD').split('\0'); changed = [name for name in changed if name]
	assert not (set(changed) & set(protected))
	assert all(files[name] == expected for name, expected in start['files'].items() if name not in changed)
	rows = [dict(path=name, before=start['files'].get(name), after=files.get(name)) for name in changed]
	result = dict(status='PASS', initial_sha256=sha(a.initial), head=git(ROOT, 'rev-parse', 'HEAD').strip(), tree=git(ROOT, 'rev-parse', 'HEAD^{tree}').strip(), tracked_files=len(files), protected_files=len(protected), donor_files=len(donor_files), donor_head=initial['donor']['head'], source_changes=rows, protected=protected, skill=initial['skill'], local=initial['local'], current_files=files, refs=git(ROOT, 'show-ref'), worktrees=git(ROOT, 'worktree', 'list', '--porcelain'), limitations='Tracked byte/mode inventories are exhaustive. No reset, stash, clean, ignored-work deletion or donor mutation was performed. No claim is made to inventory unknown historical ignored files retroactively.')
	a.output.write_text(json.dumps(result, indent=2)+'\n')
	print('PASS: 451 protected and 6622 donor byte/mode identities; installed skill/local configuration unchanged')


if __name__ == '__main__':
	main()
