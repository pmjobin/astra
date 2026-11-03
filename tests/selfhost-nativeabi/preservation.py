#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Recheck frozen sources, unchanged intake/skill, local hooks and donor bytes."""
import argparse
import hashlib
import json
from pathlib import Path
import stat
import subprocess
import tomllib

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def git(root, *args):
	return subprocess.check_output(['git', '-C', str(root), *args]).decode()


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--initial', type=Path, required=True)
	p.add_argument('--output', type=Path, required=True)
	a = p.parse_args()
	assert not a.output.resolve().is_relative_to(ROOT)
	initial = json.loads(a.initial.read_text())
	scope = json.loads((ROOT/'format/scope.json').read_text())
	protected = {}
	for name, entry in scope.items():
		if 'exclude' not in entry:
			continue
		path = ROOT/name; old = initial['repository']['files'][name]
		assert not path.is_symlink() and path.is_file()
		assert sha(path) == entry['sha256'] == old['sha256']
		assert stat.S_IMODE(path.stat().st_mode) == old['mode']
		protected[name] = dict(sha256=sha(path), mode=old['mode'], reason=entry['exclude'])
	assert set(initial['protected']) <= protected.keys() and len(protected) == 449
	donor = ROOT.parent/'astra-bootstrap'
	assert git(donor, 'rev-parse', 'HEAD').strip() == initial['donor']['head']
	assert git(donor, 'status', '--porcelain=v1') == initial['donor']['status']
	names = {x.decode() for x in subprocess.check_output(['git', '-C', str(donor), 'ls-files', '-z']).split(b'\0') if x}
	assert names == initial['donor']['files'].keys()
	for name, old in initial['donor']['files'].items():
		path = donor/name
		assert sha(path) == old['sha256'] and stat.S_IMODE(path.stat().st_mode) == old['mode']
	assert all(sha(path) == digest for path, digest in initial['skill'].items())
	global_changes = []
	for path, old in initial['local'].items():
		if path == str(Path.home()/'.codex/config.toml'):
			assert stat.S_IMODE(Path(path).stat().st_mode) == old['mode']
			settings = tomllib.loads(Path(path).read_text())
			assert not settings.get('profile')
			assert {key: settings.get(key) for key in initial['effective_codex']} == initial['effective_codex']
			if sha(path) != old['sha256']:
				global_changes.append(dict(path=path, before_sha256=old['sha256'], after_sha256=sha(path),
					critical_settings='unchanged', action='read only; external change retained'))
			continue
		# These are repository-local config/hooks, not changing user-global data.
		assert sha(path) == old['sha256'] and stat.S_IMODE(Path(path).stat().st_mode) == old['mode']
	assert sha(initial['c0']['path']) == initial['c0']['sha256']
	base = initial['repository']['head']
	subprocess.run(['git', '-C', str(ROOT), 'merge-base', '--is-ancestor', base, 'HEAD'], check=True)
	assert git(ROOT, 'diff', '--name-only', '--diff-filter=D', base, '--') == ''
	assert git(ROOT, 'stash', 'list') == initial['operations']['stashes']
	reconciliation = initial['base_reconciliation']
	assert sha(reconciliation['original_submission_path']) == reconciliation['original_submission_sha256']
	(a.output).write_text(json.dumps(dict(status='PASS', head=git(ROOT, 'rev-parse', 'HEAD').strip(),
		tree=git(ROOT, 'rev-parse', 'HEAD^{tree}').strip(), approved_base=base,
		original_protected_files=len(initial['protected']), protected_files=len(protected), protected=protected,
		donor_files=len(names), donor_head=initial['donor']['head'], donor_status_sha256=hashlib.sha256(initial['donor']['status'].encode()).hexdigest(),
		skill_hashes=initial['skill'], repository_config_and_hooks='unchanged', c0=initial['c0'],
		global_configuration_changes=global_changes, effective_codex=initial['effective_codex'],
		private_initial_capture_sha256=sha(a.initial), raw_private_config_included=False), indent=2)+'\n')
	print('PASS:', len(protected), 'protected sources,', len(names), 'donor files, unchanged skill/repository-config/hooks/C0')


if __name__ == '__main__':
	main()
