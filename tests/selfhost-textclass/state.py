#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Freeze and audit TEXTCLASS inputs without changing retained products."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
EXCHANGE = ROOT.parent/'codex'
PRIOR = EXCHANGE/'work/astra/runtime/genclass16'
BASE = 'ce7793ca133502baa73c00cd3fbbf4b8d143fd75'
TREE = '71c517bbc939fc3ab8314250b0c84fc4e018e4d3'


def sha(path):
	with Path(path).open('rb') as stream: return hashlib.file_digest(stream, 'sha256').hexdigest()


def read(path):
	return json.loads(Path(path).read_text())


def git(root, *args):
	return subprocess.check_output(['git', '-C', str(root), *args])


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--runtime', type=Path, required=True)
	a = p.parse_args(); started = time.monotonic()
	assert a.runtime.resolve().is_relative_to(EXCHANGE/'work/astra/runtime/textclass17')
	a.runtime.mkdir(parents=True, exist_ok=False)
	assert git(ROOT, 'rev-parse', 'HEAD').decode().strip() == BASE
	assert git(ROOT, 'rev-parse', 'HEAD^{tree}').decode().strip() == TREE
	sys.path.insert(0, str(Path.home()/'.agents/skills/pm-next/scripts'))
	from common import verify_zip, REPORT_FORMAT
	report = EXCHANGE/'reports/astra-report-current.zip'
	manifest, digest = verify_zip(report, REPORT_FORMAT)
	assert digest == '1c5c33637078926f383df6ebd7701d4bfd1204f07665b8863d7a399b40b5709f'
	assert report.stat().st_size == 25824840
	shutil.copy2(report, a.runtime/'GENCLASS-16-report.zip')
	old = read(PRIOR/'intake/preservation.json'); donor = ROOT.parent/'astra-bootstrap'
	assert len(old['protected']) == 451 and len(old['donor']) == 6622
	for path, expected in old['protected'].items(): assert sha(ROOT/path) == expected, path
	for path, expected in old['donor'].items():
		assert sha(donor/path) == expected['sha256'] and oct((donor/path).stat().st_mode & 0o777) == expected['mode'], path
	assert git(donor, 'rev-parse', 'HEAD').decode().strip() == old['donor_head']
	donor_status = git(donor, 'status', '--porcelain=v2', '--untracked-files=all').decode()
	assert donor_status == old['donor_status']
	prior_state = read(PRIOR/'preservation-v1.json')
	for path, expected in prior_state['hooks_unchanged'].items():
		assert sha(ROOT/path) == expected['sha256'] and oct((ROOT/path).stat().st_mode & 0o777) == expected['mode']
	for path, expected in prior_state['workflow_unchanged'].items():
		if '__pycache__' not in path: assert sha(path) == expected, path
	assert git(ROOT, 'config', '--local', '--show-origin', '--list').decode() == prior_state['local_config']
	toolchain = read(PRIOR/'toolchain.json')
	for group in ('sources', 'generated_c', 'runtime_libraries'):
		for path, expected in toolchain['C0'].get(group, {}).items(): assert sha(path) == expected, path
	assert sha(toolchain['C0']['path']) == toolchain['C0']['sha256']
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	cohorts = {}
	for name in ('original', 'LLVM23-base', 'Class15-current', 'live-committed'):
		leaf = PRIOR/('ledger-final-'+name); data = read(leaf/'ledger.json'); inputs = read(leaf/'inputs.json')
		for path, value in inputs.items(): assert sha(path) == value['sha256'], path
		stop = data['diagnostics'][0]
		assert (stop['start'], stop['end']) == (3180, 3197)
		assert Path(stop['path']).read_bytes()[3180:3197] == b'Bag<Utf8Message> '
		cohorts[name] = dict(inputs=inputs, ledger_path=str(leaf/'ledger.json'), ledger_sha256=sha(leaf/'ledger.json'), parsed=len(data['nodes']), typed=sum(bool(row['type']) and row['deferred'] == 0 for row in data['nodes']), first_stop=stop, node_identity=hashlib.sha256(json.dumps([[row[k] for k in ('node', 'syntax_kind', 'start', 'end', 'source_sha256')] for row in data['nodes']], separators=(',', ':')).encode()).hexdigest())
		if name == 'live-committed':
			for path, value in inputs.items():
				target = a.runtime/'live-source'/value['relative']; target.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(path, target)
			command = read(leaf/'commands.json')[-1]['argv']
			component = Path(command[2]); assert sha(component) == data['component_sha256']
			start = time.monotonic(); result = subprocess.run(command, capture_output=True)
			(a.runtime/'live-before.stdout').write_bytes(result.stdout); (a.runtime/'live-before.stderr').write_bytes(result.stderr)
			assert result.returncode == read(leaf/'commands.json')[-1]['exit'] == 1
			assert result.stdout == (leaf/'whole-compiler.stdout').read_bytes(), 'live source/compiler observations changed'
			cohorts[name]['reproduced_seconds'] = time.monotonic()-start
	shutil.copy2(PRIOR/'intake/preservation.json', a.runtime/'preservation-reference.json')
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', initial_head=BASE, initial_tree=TREE, predecessor=dict(sha256=digest, manifest=manifest), cohorts=cohorts, donor_status=donor_status, donor_head=old['donor_head'], protected_files=451, donor_files=6622, effective_config=git(ROOT, 'config', '--show-origin', '--list').decode(), worktrees=git(ROOT, 'worktree', 'list', '--porcelain').decode(), stash=git(ROOT, 'stash', 'list').decode(), seconds=time.monotonic()-started), indent=2)+'\n')
	print('Exact predecessor, four source cohorts, live first stop, 451 protected and 6622 donor identities verified')


if __name__ == '__main__':
	main()
