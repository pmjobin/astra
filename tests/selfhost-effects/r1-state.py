#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Pinned R1 intake, original native approval and predecessor cohort replay."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import stat
import time
import zipfile
from state import ROOT, RUNTIME as PREVIOUS, bounded_run, preservation, read, sha, git, population, digest

RUNTIME = PREVIOUS.parent/'effects25-r1'
INPUT = RUNTIME.parent/'native-current/input'
BASE = '5f2ae0e2d681ca2eb34b2687760ec4a055370638'
TREE = '5674e853eed983752d9b4a604b633dceb13491e7'
REPORT = 'a3a364209b11e0d7c9e9ce337513764e9075d534b7ab5921dad25dcd9a50dcb3'
PROPOSAL = 'd77c02f3144ab5dc3da41eb310b29cd02629b49876042934ea5071a1549ac66e'
SESSION = Path.home()/'.codex/sessions/2026/11/06/rollout-2026-11-06T06-31-06-01a1b0a0-6f9f-7990-8644-f1e8f6aed93a.jsonl'


def archive(path, expected):
	assert sha(path) == expected
	with zipfile.ZipFile(path) as z:
		assert z.testzip() is None
		manifest = json.loads(z.read('MANIFEST.json'))
		assert len(z.namelist()) == len(set(z.namelist())) == len(manifest['files']) + 1
		assert set(z.namelist()) == {'MANIFEST.json', *(r['path'] for r in manifest['files'])}
		for entry in z.infolist():
			assert not Path(entry.filename).is_absolute() and '..' not in Path(entry.filename).parts and not entry.is_dir()
			assert stat.S_IFMT(entry.external_attr >> 16) in (0, stat.S_IFREG)
		for row in manifest['files']:
			data = z.read(row['path'])
			assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
		return manifest


def submission_history():
	path = ROOT.parent/'codex/submissions/ASTRA-SELFHOST-EFFECTS-25-SUBMISSION.zip'
	expected = '7be68ba88a6891dacb4a6a3e0bc4c6226722d43739358d1144fbc419e3f939ca'
	manifest = archive(path, expected)
	assert (manifest['format'], manifest['project_id'], manifest['milestone_id'], manifest['base_commit']) == ('pm-codex-submission/1', 'astra', 'ASTRA-SELFHOST-EFFECTS-25', 'a19425f2cd0932fb0c93629abcd1ed63b98aa5bf')
	with zipfile.ZipFile(path) as z:
		for row in read(INPUT/'REFERENCE-INDEX.json')['sources']:
			if row['origin']['archive'] == path.name: assert (INPUT/row['path']).read_bytes() == z.read(row['origin']['member'])
	return dict(path=str(path), sha256=expected, manifest=manifest, reference_members_verified=True)


def approval():
	assert sha(ROOT/'docs/selfhost-effects-25-abi-proposal.md') == PROPOSAL
	assert sha(INPUT/'reference/effects25/docs/selfhost-effects-25-abi-proposal.md') == PROPOSAL
	receipt = read(INPUT/'reference/effects25/evidence/abi-approval.json')
	assert receipt == read(PREVIOUS/'abi-approval.json')
	assert receipt['proposal_sha256'] == PROPOSAL and receipt['decision'] == 'APPROVE THE BOUNDED DESIGN E25-A-v1'
	question = None; answer = None
	for line_number, raw in enumerate(SESSION.read_bytes().splitlines(), 1):
		row = json.loads(raw); payload = row.get('payload', {})
		if row['type'] != 'response_item': continue
		if payload.get('name') == 'request_user_input_async':
			args = json.loads(payload['arguments'])
			if any('E25-A-v1' in q['title'] for q in args['questions']):
				question = dict(line=line_number, sha256=hashlib.sha256(raw).hexdigest(), timestamp=row['timestamp'], call_id=payload['call_id'], arguments=args)
		if payload.get('role') == 'user' and question:
			for content in payload.get('content', []):
				text = content.get('text', '')
				if not text.startswith('<send_user_message_question_reply>'): continue
				answers = json.loads(text.split('\n', 1)[1].rsplit('\n', 1)[0])
				for reply in answers:
					if reply.get('answer') == receipt['decision'] and reply['questionItemId'] == json.dumps(['request_user_input_async', question['call_id'], 0], separators=(',', ':')):
						answer = dict(line=line_number, sha256=hashlib.sha256(raw).hexdigest(), timestamp=row['timestamp'], reply=reply)
		if answer: break
	assert question and answer
	return dict(session=str(SESSION), question=question, answer=answer, receipt=receipt, proposal_sha256=PROPOSAL)


def intake():
	assert git('rev-parse', 'HEAD').strip() == BASE and git('rev-parse', 'HEAD^{tree}').strip() == TREE
	assert not git('diff', '--name-only') and not git('diff', '--cached', '--name-only')
	result = preservation()
	result['approval'] = approval()
	result['original_submission'] = submission_history()
	report = ROOT.parent/'codex/reports/astra-report-current.zip'
	assert report.stat().st_size == 13629382
	manifest = archive(report, REPORT); assert len(manifest['files']) == 51
	with zipfile.ZipFile(report) as z:
		previous = json.loads(z.read('RESULT.json'))
		assert (previous['status'], previous['final_commit'], previous['final_tree']) == ('PARTIAL', BASE, TREE)
		assert previous['submission_sha256'] == '7be68ba88a6891dacb4a6a3e0bc4c6226722d43739358d1144fbc419e3f939ca'
		for row in read(INPUT/'REFERENCE-INDEX.json')['sources']:
			if row['origin']['archive'] == 'astra-report-current(20261106-181829).zip': assert (INPUT/row['path']).read_bytes() == z.read(row['origin']['member'])
	RUNTIME.mkdir(exist_ok=True)
	target = RUNTIME/'predecessor-report.zip'
	if target.exists(): assert sha(target) == REPORT
	else: shutil.copy2(report, target)
	result.update(base=BASE, tree=TREE, predecessor_sha256=REPORT, predecessor_payloads=len(manifest['files']), config=git('config', '--show-origin', '--list'), refs=git('show-ref'), worktrees=git('worktree', 'list', '--porcelain'), stash=git('stash', 'list'), status=git('status', '--porcelain=v2', '--untracked-files=all'))
	(RUNTIME/'initial.json').write_text(json.dumps(result, indent=2)+'\n')
	print('R1 exact intake, original native approval, 451 protected paths, 6622 donor files and 1044 historical hashes verified', flush=True)


def replay():
	results = {}
	for mode in ('O0', 'O2'):
		for name, old in read(PREVIOUS/('cohorts-v1-'+mode+'.json')).items():
			ledger = read(PREVIOUS/('ledger-v1-'+mode+'-'+name)/'ledger.json')
			logical, nodes = population(ledger)
			assert (digest(logical), digest(nodes)) == (old['population_sha256'], old['node_identity_sha256'])
			for row in ledger['files']:
				data = bytes.fromhex(row['synthetic_source_hex']) if 'synthetic_source_hex' in row else Path(row['path']).read_bytes()
				assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
			argv = old['independent_consumer']['argv'][2:]
			identity = read(Path(argv[0]).with_suffix('.identity.json'))
			assert sha(argv[0]) == identity['sha256']
			assert all(sha(p) == h for group in ('sources', 'tools') for p, h in identity['identity'][group].items())
			leaf = RUNTIME/('baseline-'+mode+'-'+name); leaf.mkdir(exist_ok=False)
			start = time.monotonic()
			with (leaf/'stdout').open('xb') as out, (leaf/'stderr').open('xb') as err:
				r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/'time', *argv], cwd=ROOT, stdout=out, stderr=err, timeout=240)
			status = next(line for line in (leaf/'stdout').read_text().splitlines() if line.startswith('STATUS '))
			assert r.returncode == old['independent_consumer']['exit'] and status == old['independent_consumer']['status']
			assert 'CHECKED_CONSUMER' not in (leaf/'stderr').read_text()
			results[mode+'/'+name] = dict(argv=argv, exit=r.returncode, status=status, files=len(ledger['files']), nodes=len(nodes), population_sha256=digest(logical), node_identity_sha256=digest(nodes), seconds=time.monotonic()-start, component_sha256=sha(argv[0]), stdout_sha256=sha(leaf/'stdout'), stderr_sha256=sha(leaf/'stderr'))
			(RUNTIME/'baseline.json').write_text(json.dumps(results, indent=2)+'\n')
			print(mode, name, status, 'original conditional type, incomplete Flow', flush=True)


if __name__ == '__main__':
	p = argparse.ArgumentParser(); p.add_argument('--replay', action='store_true'); a = p.parse_args()
	if a.replay: replay()
	else: intake()
