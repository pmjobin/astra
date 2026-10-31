# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Read-only B1 production/host stability checks; never grants challenge credit."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def check(path, root):
	path, root = Path(path).resolve(), Path(root).resolve()
	data = json.loads(path.read_text())
	assert data['format'] == 'astra-optimizer-hardening-18-freeze/1' and data['freeze'] == 1
	assert data['B_selected'] is False, 'original pre-selection record changed'
	for name, row in data['source_files'].items():
		assert sha(root / name) == row['sha256'], 'frozen production source changed: ' + name
	for name, row in data['production_artifacts'].items():
		assert sha(row['path']) == row['sha256'], 'frozen production artifact changed: ' + name
	for name, row in data['host_dependencies'].items():
		assert sha(name) == row['sha256'], 'frozen host dependency changed: ' + name
	for name, row in data['host_tools'].items():
		assert str(Path(shutil.which(name)).resolve()) == row['path'], 'frozen tool route changed: ' + name
	changed = subprocess.check_output(['git', 'diff', '--name-only', data['source_commit']], cwd=root, text=True).splitlines()
	allowed = ['docs/optimizer-hardening-18-freeze-1.json', 'docs/optimizer-hardening-18-challenge-1.md',
		'tests/optimizer-hardening-18/meson.build']
	for name in changed:
		assert name in allowed or name.startswith(('examples/optimizer-hardening-18/B/',
			'tests/optimizer-hardening-18/b1/')), 'non-B file changed during challenge: ' + name
	return {'freeze': 1, 'freeze_sha256': sha(path), 'source_commit': data['source_commit'],
		'checked_source_files': len(data['source_files']), 'checked_production_artifacts': len(data['production_artifacts']),
		'checked_host_dependencies': len(data['host_dependencies']), 'unchanged': True}
