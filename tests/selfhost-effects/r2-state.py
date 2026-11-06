#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Authenticate R2 against live Git, native consent and immutable R1 evidence."""
import hashlib
import json
from pathlib import Path
import shutil
import zipfile
from state import ROOT, RUNTIME as ORIGINAL, preservation, read, sha, git, load_module

BASE = '48eb69926ad5735864696d15963d7396ce181683'
TREE = 'e6fb45f0599a81400eaffe5be6d536b57e5922eb'
REPORT = '0b35b4382dc06074600731bcae4516171825ef9b4cab0dfbab653afab90a5395'
RUNTIME = ORIGINAL.parent/'effects25-r2'
BUILD = ROOT.parent/'codex/work/astra/build/effects25-r2'
INPUT = ORIGINAL.parent/'native-current/input'


def approval():
	receipt = read(INPUT/'reference/r1/evidence/abi-approval.json')
	proposal = receipt['proposal_sha256']
	assert proposal == 'd77c02f3144ab5dc3da41eb310b29cd02629b49876042934ea5071a1549ac66e'
	assert sha(ROOT/'docs/selfhost-effects-25-abi-proposal.md') == proposal
	assert sha(INPUT/'reference/approved/E25-A-v1-proposal.md') == proposal
	assert receipt == read(ORIGINAL.parent/'effects25-r1/initial.json')['approval']
	assert receipt['receipt'] == read(ORIGINAL/'abi-approval.json')
	lines = Path(receipt['session']).read_bytes().splitlines()
	for kind in ('question', 'answer'):
		row = receipt[kind]; raw = lines[row['line']-1]
		assert hashlib.sha256(raw).hexdigest() == row['sha256']
		assert json.loads(raw)['timestamp'] == row['timestamp']
	question = json.loads(lines[receipt['question']['line']-1])['payload']
	answer = json.loads(lines[receipt['answer']['line']-1])['payload']
	assert question['name'] == 'request_user_input_async'
	assert json.loads(question['arguments']) == receipt['question']['arguments']
	assert answer['role'] == 'user'
	texts = [c.get('text', '') for c in answer['content']]
	replies = [json.loads(t.split('\n', 1)[1].rsplit('\n', 1)[0]) for t in texts if t.startswith('<send_user_message_question_reply>')]
	assert receipt['answer']['reply'] in [r for group in replies for r in group]
	assert receipt['answer']['reply']['answer'] == 'APPROVE THE BOUNDED DESIGN E25-A-v1'
	assert receipt['answer']['reply']['questionItemId'] == json.dumps(['request_user_input_async', question['call_id'], 0], separators=(',', ':'))
	return receipt


def main():
	assert git('rev-parse', 'HEAD').strip() == BASE
	assert git('rev-parse', 'HEAD^{tree}').strip() == TREE
	assert not git('diff', '--name-only') and not git('diff', '--cached', '--name-only')
	result = preservation(); result['approval'] = approval()
	r1 = load_module('r2_r1_archive', ROOT/'tests/selfhost-effects/r1-state.py')
	report = ROOT.parent/'codex/reports/astra-report-current.zip'
	assert report.stat().st_size == 13362799
	manifest = r1.archive(report, REPORT); assert len(manifest['files']) == 51
	with zipfile.ZipFile(report) as z:
		previous = json.loads(z.read('RESULT.json'))
		assert (previous['status'], previous['final_commit'], previous['final_tree']) == ('PARTIAL', BASE, TREE)
		assert previous['submission_sha256'] == 'ed84f5a7b5c09162df2df1af5a5cc4f7d5d322361639566ac8c1fc7f00ff31f7'
		for row in read(INPUT/'REFERENCE-INDEX.json')['references']:
			path = INPUT/row['path']; assert path.stat().st_size == row['bytes'] and sha(path) == row['sha256']
			if row['path'].startswith('reference/r1/'):
				member = row['path'][len('reference/r1/'):]
				assert path.read_bytes() == z.read(member), member
	RUNTIME.mkdir(exist_ok=False); BUILD.mkdir(exist_ok=False)
	shutil.copy2(report, RUNTIME/'predecessor-report.zip')
	assert sha(RUNTIME/'predecessor-report.zip') == REPORT
	result.update(base=BASE, tree=TREE, predecessor_sha256=REPORT, predecessor=previous, config=git('config', '--show-origin', '--list'), refs=git('show-ref'), worktrees=git('worktree', 'list', '--porcelain'), stash=git('stash', 'list'), initial_status=git('status', '--porcelain=v2', '--untracked-files=all'))
	(RUNTIME/'initial.json').write_text(json.dumps(result, indent=2)+'\n')
	print('R2 exact intake, original native approval, immutable R1 PARTIAL, 451 protected paths, 6622 donor files, 1044 proof hashes verified', flush=True)


if __name__ == '__main__':
	main()
