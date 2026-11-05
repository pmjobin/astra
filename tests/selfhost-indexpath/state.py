#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Freeze INDEXPATH provenance and reproduce the unchanged source frontier."""
import hashlib
import json
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT.parent/'codex/work/astra/runtime/indexpath18'
PRIOR = ROOT.parent/'codex/work/astra/runtime/textclass17'
BASE = '9286190fdc3650f127b8f523cbcfe052d41cb730'
TREE = '00628c897e62c1baa9198da1cb6374b6171e10c0'


def sha(path):
	with Path(path).open('rb') as stream: return hashlib.file_digest(stream, 'sha256').hexdigest()


def read(path):
	return json.loads(Path(path).read_text())


def git(*args):
	return subprocess.check_output(['git', '-C', str(ROOT), *args]).decode()


def main():
	assert git('rev-parse', 'HEAD').strip() == BASE and git('rev-parse', 'HEAD^{tree}').strip() == TREE
	assert git('diff', '--name-only') == '' and git('diff', '--cached', '--name-only') == ''
	leaf = RUNTIME/'initial'; leaf.mkdir(exist_ok=False)
	old = read(PRIOR/'intake-v3/preservation-reference.json')
	for path, expected in old['protected'].items(): assert sha(ROOT/path) == expected, path
	donor = ROOT.parent/'astra-bootstrap'
	for path, expected in old['donor'].items():
		assert sha(donor/path) == expected['sha256'] and oct((donor/path).stat().st_mode & 0o777) == expected['mode'], path
	assert len(old['protected']) == 451 and len(old['donor']) == 6622
	assert subprocess.check_output(['git', '--no-optional-locks', '-C', donor, 'rev-parse', 'HEAD']).decode().strip() == old['donor_head']
	assert subprocess.check_output(['git', '--no-optional-locks', '-C', donor, 'status', '--porcelain=v2', '--untracked-files=all']).decode() == old['donor_status']
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	cohorts = {}
	for name, expected in [('original', (79, 174297, 8003)), ('LLVM23-base', (85, 188293, 8297)), ('Class15-current', (92, 206465, 8760)), ('live-initial', (92, 208328, 8810))]:
		prior = PRIOR/('ledger-v9-'+name); data = read(prior/'ledger.json'); inputs = read(prior/'inputs.json')
		for path, value in inputs.items(): assert sha(path) == value['sha256'], path
		counts = (len(data['files']), len(data['nodes']), sum(bool(row['type']) and row['deferred'] == 0 for row in data['nodes']))
		assert counts == expected, (name, counts)
		cmd = read(prior/'commands.json')[-1]['argv']; start = time.monotonic()
		with (leaf/(name+'.stdout')).open('xb') as out, (leaf/(name+'.stderr')).open('xb') as err:
			r = subprocess.run(cmd, stdout=out, stderr=err, timeout=120)
		assert r.returncode == 1 and sha(leaf/(name+'.stdout')) == sha(prior/'whole-compiler.stdout')
		stop = data['diagnostics'][0]; assert (stop['start'], stop['end']) == (650, 664)
		cohorts[name] = dict(counts=counts, inputs=inputs, ledger=str(prior/'ledger.json'), ledger_sha256=sha(prior/'ledger.json'), stdout_sha256=sha(leaf/(name+'.stdout')), argv=cmd, exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic(), stop=stop, component_sha256=sha(cmd[2]))
	workflow = Path.home()/'.agents/skills/pm-next'
	result = dict(base=BASE, tree=TREE, cohorts=cohorts, protected=old['protected'], donor=old['donor'], donor_head=old['donor_head'], donor_status=old['donor_status'], config=git('config', '--show-origin', '--list'), worktrees=git('worktree', 'list', '--porcelain'), stash=git('stash', 'list'), hooks={str(p):dict(sha256=sha(p), mode=oct(p.stat().st_mode & 0o777)) for p in (ROOT/'.git/hooks').iterdir()}, workflow={str(p):sha(p) for p in [workflow/'SKILL.md', *sorted((workflow/'scripts').glob('*.py'))]}, tracked_status=git('status', '--porcelain=v2'), initial_ignored=git('ls-files', '--others', '--ignored', '--exclude-standard'), toolchain=read(ROOT.parent/'codex/work/astra/runtime/genclass16/toolchain.json'))
	(leaf/'result.json').write_text(json.dumps(result, indent=2)+'\n')
	print('Four exact cohorts reproduced; 451 protected and 6622 donor identities verified')


if __name__ == '__main__':
	main()
