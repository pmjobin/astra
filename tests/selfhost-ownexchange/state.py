#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Record immutable OWNEXCHANGE intake and reproduce the original checked stop."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT.parent/'codex/work/astra/runtime/ownexchange19'
BUILD = ROOT.parent/'codex/work/astra/build/ownexchange19'
PRIOR = ROOT.parent/'codex/work/astra/runtime/indexpath18'
BASE = '9e05ae99120336f1b3de96d5a375d6dd94a802ea'
TREE = '12e6cb369a93a8042490e5459857da4c89488b18'
C0 = ROOT.parent/'codex/work/astra/build/llvm23-migration/production-final/astrac'


def sha(path):
	with Path(path).open('rb') as stream: return hashlib.file_digest(stream, 'sha256').hexdigest()


def read(path):
	return json.loads(Path(path).read_text())


def git(*args):
	return subprocess.check_output(['git', '--no-optional-locks', '-C', ROOT, *args]).decode()


def main():
	assert git('rev-parse', 'HEAD').strip() == BASE and git('rev-parse', 'HEAD^{tree}').strip() == TREE
	assert git('diff', '--name-only') == '' and git('diff', '--cached', '--name-only') == ''
	leaf = RUNTIME/'initial'; leaf.mkdir(parents=True, exist_ok=False)
	old = read(PRIOR/'initial/result.json')
	for path, expected in old['protected'].items(): assert sha(ROOT/path) == expected, path
	donor = ROOT.parent/'astra-bootstrap'
	for path, expected in old['donor'].items():
		assert sha(donor/path) == expected['sha256'] and oct((donor/path).stat().st_mode & 0o777) == expected['mode'], path
	assert len(old['protected']) == 451 and len(old['donor']) == 6622
	assert subprocess.check_output(['git', '--no-optional-locks', '-C', donor, 'rev-parse', 'HEAD']).decode().strip() == old['donor_head']
	assert subprocess.check_output(['git', '--no-optional-locks', '-C', donor, 'status', '--porcelain=v2', '--untracked-files=all']).decode() == old['donor_status']
	report = ROOT.parent/'codex/reports/astra-report-current.zip'
	assert sha(report) == '03bb1d84dd9eb0561d2b929eaf2c1baa0cdb83e65d47af62c2f820f545fb0218' and report.stat().st_size == 18748705
	shutil.copy2(report, RUNTIME/'predecessor-report.zip')
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	assert sha(C0) == 'e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b'
	source = ROOT/'compiler/semantic/flow-model.astra'
	assert sha(source) == '4f901a3f358e7a5ccb7683938559ee8592f97c734d93a6a82b198586709c6f52'
	assert source.read_bytes()[3589:3614] == b'swap(this.events, grown);'
	cohorts = {}
	for name in ('original', 'LLVM23-base', 'Class15-current', 'live-initial'):
		prior = PRIOR/('ledger-v5-'+name); data = read(prior/'ledger.json')
		cmd = read(prior/'commands.json')[-1]['argv']; start = time.monotonic()
		with (leaf/(name+'.stdout')).open('xb') as out, (leaf/(name+'.stderr')).open('xb') as err:
			r = subprocess.run(cmd, stdout=out, stderr=err, timeout=120)
		assert r.returncode == 1 and sha(leaf/(name+'.stdout')) == sha(prior/'whole-compiler.stdout')
		stop = data['diagnostics'][0]; assert (stop['start'], stop['end']) == (3589, 3614)
		assert stop['message'] == 'DEFERRED: generic body syntax lacks a concrete specialization contract'
		cohorts[name] = dict(counts=[len(data['files']), len(data['nodes']), sum(bool(row['type']) and row['deferred'] == 0 for row in data['nodes'])], ledger=str(prior/'ledger.json'), ledger_sha256=sha(prior/'ledger.json'), argv=cmd, exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic(), stop=stop, stdout_sha256=sha(leaf/(name+'.stdout')), component_sha256=sha(cmd[2]))
	workflow = Path.home()/'.agents/skills/pm-next'
	result = dict(base=BASE, tree=TREE, cohorts=cohorts, protected=old['protected'], donor=old['donor'], donor_head=old['donor_head'], donor_status=old['donor_status'], config=git('config', '--show-origin', '--list'), worktrees=git('worktree', 'list', '--porcelain'), stash=git('stash', 'list'), hooks={str(p): dict(sha256=sha(p), mode=oct(p.stat().st_mode & 0o777)) for p in (ROOT/'.git/hooks').iterdir()}, workflow={str(p): sha(p) for p in [workflow/'SKILL.md', *sorted((workflow/'scripts').glob('*.py'))]}, initial_status=git('status', '--porcelain=v2'), initial_ignored=git('ls-files', '--others', '--ignored', '--exclude-standard'), source=dict(path=str(source), sha256=sha(source), blob=git('hash-object', str(source)).strip(), span=[3589, 3614]), predecessor_sha256=sha(report))
	(leaf/'result.json').write_text(json.dumps(result, indent=2)+'\n')
	print('Four frozen cohorts reproduced byte-exactly; predecessor, 451 protected files and 6622 donor files verified')


if __name__ == '__main__':
	main()
