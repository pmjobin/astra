# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Read-only actual source/artifact/host checks for the second frozen challenge."""
from pathlib import Path
import hashlib
import json
import shutil
import stat
import subprocess


def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def check(path, root):
	path, root = Path(path).resolve(), Path(root).resolve(); data = json.loads(path.read_text())
	assert data['format'] == 'astra-optimizer-hardening-18-freeze/1' and data['freeze'] == 2
	assert data['B_selected'] is False and data['B_requirements'] is None and data['B_seed'] is None
	for name, row in data['source_files'].items():
		p = root / name
		assert sha(p) == row['sha256'] and p.stat().st_size == row['bytes'] and stat.S_IMODE(p.stat().st_mode) == row['mode'], name
	for name, row in data['production_artifacts'].items():
		p = Path(row['path'])
		assert sha(p) == row['sha256'] and p.stat().st_size == row['bytes'] and stat.S_IMODE(p.stat().st_mode) == row['mode'], name
	for name, row in data['host_dependencies'].items(): assert sha(name) == row['sha256'], name
	for name, row in data['host_tools'].items(): assert str(Path(shutil.which(name)).resolve()) == row['path'], name
	changed = subprocess.check_output(['git', 'diff', '--name-only', data['source_commit']], cwd=root, text=True).splitlines()
	allowed = ['docs/optimizer-hardening-18-freeze-2.json', 'docs/optimizer-hardening-18-challenge-2.md', 'tests/optimizer-hardening-18/meson.build']
	for name in changed:
		assert name in allowed or name.startswith(('examples/optimizer-hardening-18/B2/', 'tests/optimizer-hardening-18/b2/')), name
	return dict(freeze=2, freeze_sha256=sha(path), source_commit=data['source_commit'], checked_source_files=len(data['source_files']),
		checked_production_artifacts=len(data['production_artifacts']), checked_host_dependencies=len(data['host_dependencies']), unchanged=True)
