#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Preserve GENRESOURCE intake and rerun the exact four predecessor queries."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time
import zipfile

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT.parent/'codex/work/astra/runtime/genresource20'
BUILD = ROOT.parent/'codex/work/astra/build/genresource20'
PRIOR = ROOT.parent/'codex/work/astra/runtime/ownexchange19'
C0 = ROOT.parent/'codex/work/astra/build/llvm23-migration/production-final/astrac'
BASE = '63278cb36c51a4d874c6a3a74b6d6f3e9e12883c'
TREE = 'c954c51beaef1e0a13b9413393f6e21a7c82e929'
REPORT = '24f1b14a49903afdcf2bc75aff9de043e28763bb8a98470a853384481886e45d'
COHORTS = ('original', 'LLVM23-base', 'Class15-current', 'live-initial')


def sha(path):
	with Path(path).open('rb') as stream: return hashlib.file_digest(stream, 'sha256').hexdigest()


def read(path):
	return json.loads(Path(path).read_text())


def git(*args):
	return subprocess.check_output(['git', '--no-optional-locks', '-C', ROOT, *args]).decode()


def preservation():
	old = read(PRIOR/'initial/result.json')
	for path, expected in old['protected'].items(): assert sha(ROOT/path) == expected, path
	donor = ROOT.parent/'astra-bootstrap'
	for path, expected in old['donor'].items():
		assert sha(donor/path) == expected['sha256'] and oct((donor/path).stat().st_mode & 0o777) == expected['mode'], path
	assert len(old['protected']) == 451 and len(old['donor']) == 6622
	assert subprocess.check_output(['git', '--no-optional-locks', '-C', donor, 'rev-parse', 'HEAD']).decode().strip() == old['donor_head']
	assert subprocess.check_output(['git', '--no-optional-locks', '-C', donor, 'status', '--porcelain=v2', '--untracked-files=all']).decode() == old['donor_status']
	return dict(protected=old['protected'], donor=old['donor'], donor_head=old['donor_head'], donor_status=old['donor_status'])


def main():
	assert git('rev-parse', 'HEAD').strip() == BASE and git('rev-parse', 'HEAD^{tree}').strip() == TREE
	assert git('diff', '--name-only') == '' and git('diff', '--cached', '--name-only') == ''
	leaf = RUNTIME/'initial'; leaf.mkdir(parents=True, exist_ok=False)
	result = preservation()
	report = ROOT.parent/'codex/reports/astra-report-current.zip'
	assert report.stat().st_size == 22070184 and sha(report) == REPORT
	shutil.copy2(report, RUNTIME/'predecessor-report.zip'); assert sha(RUNTIME/'predecessor-report.zip') == REPORT
	with zipfile.ZipFile(report) as archive:
		manifest = json.loads(archive.read('MANIFEST.json'))
		assert archive.testzip() is None
		for row in manifest['files']:
			data = archive.read(row['path']); assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
		for name in ('engineering-summary.json', 'handoff-summary.json'):
			assert archive.read('evidence/'+name) == (PRIOR/name).read_bytes() if (PRIOR/name).exists() else True
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	assert sha(C0) == 'e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b'
	cohorts = {}
	for name in COHORTS:
		previous = PRIOR/('ledger-v7-'+name); ledger = read(previous/'ledger.json')
		for row in ledger['files']:
			if 'synthetic_source_hex' in row: assert hashlib.sha256(bytes.fromhex(row['synthetic_source_hex'])).hexdigest() == row['sha256']
			else: assert sha(row['path']) == row['sha256']
		argv = read(previous/'commands.json')[-1]['argv']; component = Path(argv[2])
		identity = read(component.with_suffix('.identity.json')); assert sha(component) == identity['sha256'] == ledger['component_sha256']
		assert all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
		start = time.monotonic()
		with (leaf/(name+'.stdout')).open('xb') as out, (leaf/(name+'.stderr')).open('xb') as err:
			r = subprocess.run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv[2:]], cwd=ROOT, stdout=out, stderr=err, timeout=120)
		assert r.returncode == 1 and sha(leaf/(name+'.stdout')) == sha(previous/'whole-compiler.stdout')
		assert ledger['diagnostics'][0]['message'] == 'generic instance resource limit'
		cohorts[name] = dict(argv=argv[2:], exit=r.returncode, start=start, end=time.monotonic(), component_sha256=sha(component), files=ledger['files'], ledger_sha256=sha(previous/'ledger.json'), nodes=len(ledger['nodes']), typed=sum(bool(row['type']) and row['deferred'] == 0 for row in ledger['nodes']), stop=ledger['diagnostics'][0], stdout_sha256=sha(leaf/(name+'.stdout')))
		print(name, cohorts[name]['nodes'], cohorts[name]['typed'], ledger['diagnostics'][0], flush=True)
	workflow = Path.home()/'.agents/skills/pm-next'
	result.update(base=BASE, tree=TREE, cohorts=cohorts, predecessor_sha256=REPORT, config=git('config', '--show-origin', '--list'), refs=git('show-ref'), worktrees=git('worktree', 'list', '--porcelain'), stash=git('stash', 'list'), initial_status=git('status', '--porcelain=v2', '--untracked-files=all'), ignored=git('ls-files', '--others', '--ignored', '--exclude-standard'), hooks={str(p): dict(sha256=sha(p), mode=oct(p.stat().st_mode & 0o777)) for p in (ROOT/'.git/hooks').iterdir()}, workflow={str(p): sha(p) for p in [workflow/'SKILL.md', *sorted((workflow/'scripts').glob('*.py'))]})
	(leaf/'result.json').write_text(json.dumps(result, indent=2)+'\n')
	print('Four exact first stops reproduced; 451 protected and 6622 donor files unchanged')


if __name__ == '__main__':
	main()
