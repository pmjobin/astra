#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""R5 exact intake and external recipe routing; pm-next owns publication."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import zipfile
import state

ROOT = state.ROOT
BASE = 'c271e0822d0fc12a878a5adc1388aa1a8e147067'
TREE = 'cb487de4a6f3a8faa73675feb0b9a090047d3fef'
REPORT = 'c188a95de8b070ad5fd396afb2ad6d4132649278f05ba0e5dc49a1f3d9e8e00c'
RUNTIME = ROOT.parent/'codex/work/astra/runtime/effects25-r5'
BUILD = ROOT.parent/'codex/work/astra/build/effects25-r5'
INPUT = RUNTIME.parent/'native-current/input'


def authenticate():
	assert state.git('rev-parse', 'HEAD').strip() == BASE
	assert state.git('rev-parse', 'HEAD^{tree}').strip() == TREE
	assert not state.git('diff', '--cached', '--name-only')
	protection = state.preservation()
	previous_initial = state.read(RUNTIME.parent/'effects25-r4/initial.json')
	assert protection == {key: previous_initial[key] for key in protection}
	receipt = state.read(INPUT/'reference/approval/abi-approval.json')
	assert receipt == previous_initial['approval']
	assert receipt['proposal_sha256'] == state.sha(ROOT/'docs/selfhost-effects-25-abi-proposal.md') == state.sha(INPUT/'reference/approval/E25-A-v1-proposal.md')
	lines = Path(receipt['session']).read_bytes().splitlines()
	for kind in ('question', 'answer'):
		row = receipt[kind]; raw = lines[row['line']-1]
		assert hashlib.sha256(raw).hexdigest() == row['sha256'] and json.loads(raw)['timestamp'] == row['timestamp']
	question = json.loads(lines[receipt['question']['line']-1])['payload']
	answer = json.loads(lines[receipt['answer']['line']-1])['payload']
	assert question['name'] == 'request_user_input_async' and json.loads(question['arguments']) == receipt['question']['arguments'] and answer['role'] == 'user'
	replies = [json.loads(c['text'].split('\n', 1)[1].rsplit('\n', 1)[0]) for c in answer['content'] if c.get('text', '').startswith('<send_user_message_question_reply>')]
	assert receipt['answer']['reply'] in [r for group in replies for r in group]
	assert receipt['answer']['reply']['answer'] == 'APPROVE THE BOUNDED DESIGN E25-A-v1'
	report = ROOT.parent/'codex/reports/astra-report-current.zip'
	assert report.stat().st_size == 22249687 and state.sha(report) == REPORT
	with zipfile.ZipFile(report) as archive:
		assert len(archive.namelist()) == len(set(archive.namelist())) == 102
		manifest = json.loads(archive.read('MANIFEST.json'))['files']; assert len(manifest) == 101
		assert set(archive.namelist()) == {row['path'] for row in manifest} | {'MANIFEST.json'}
		for row in manifest:
			data = archive.read(row['path']); assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
		previous = json.loads(archive.read('RESULT.json'))
		assert (previous['status'], previous['final_commit'], previous['final_tree']) == ('PARTIAL', BASE, TREE)
		for row in state.read(INPUT/'REFERENCE-INDEX.json')['references']:
			data = (INPUT/row['path']).read_bytes(); assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
			if row['source'].startswith('astra-report-current(20261107-224251).zip!'): assert data == archive.read(row['source'].split('!', 1)[1])
		for name in archive.namelist():
			if name.startswith('source/'): assert (ROOT/name[7:]).read_bytes() == archive.read(name), name
	RUNTIME.mkdir(); BUILD.mkdir()
	shutil.copy2(report, RUNTIME/'predecessor-report.zip')
	result = dict(base=BASE, tree=TREE, protection=protection, approval=receipt, predecessor_sha256=REPORT, predecessor=previous, status=state.git('status', '--porcelain=v2', '--untracked-files=all'), config=state.git('config', '--show-origin', '--list'), refs=state.git('show-ref'), worktrees=state.git('worktree', 'list', '--porcelain'), ignored=state.git('ls-files', '--others', '--ignored', '--exclude-standard'), timestamped_predecessor_name='Offline reference label; exact bytes authenticated at canonical astra-report-current.zip')
	(RUNTIME/'initial.json').write_text(json.dumps(result, indent=2)+'\n')
	print('R5 exact R4 report, live source, approval and protected state authenticated', flush=True)


def route():
	r4 = state.load_module('r5_inherited_route', ROOT/'tests/selfhost-effects/r4.py')
	r4.RUNTIME = RUNTIME; r4.BUILD = BUILD
	inherited_load = r4.route()
	def load(name, path):
		module = inherited_load(name, path)
		if Path(path) == ROOT/'tests/selfhost-effects/full-build.py':
			module.PRIOR = RUNTIME/'r4-history/runtime/full-inputs-final16'
		if Path(path) == ROOT/'tests/selfhost-typecore/build.py':
			original_build = module.build
			def build(*args, **kwargs):
				kwargs['link_inputs'] = list(dict.fromkeys([*kwargs.get('link_inputs', ()), Path(__file__)]))
				return original_build(*args, **kwargs)
			module.build = build
		return module
	state.load_module = load
	original_run = state.bounded_run
	def run(argv, **kwargs):
		argv = [Path(__file__) if str(arg) in (str(ROOT/'tests/selfhost-effects/r3.py'), str(ROOT/'tests/selfhost-effects/r4.py')) else arg for arg in argv]
		return original_run(argv, **kwargs)
	state.bounded_run = run
	return load


def main():
	assert Path(os.environ['PM_CODEX_BUILD_DIR']).resolve() == BUILD.parent
	assert Path(os.environ['PM_CODEX_RUNTIME_DIR']).resolve() == RUNTIME.parent
	if sys.argv[1:] == ['authenticate']:
		authenticate(); return
	load = route(); recipe = sys.argv.pop(1)
	assert recipe.startswith('recover-') and '/' not in recipe and '.' not in recipe
	module = load('r5_recipe_'+recipe, ROOT/('tests/selfhost-effects/'+recipe+'.py'))
	if hasattr(module, 'main'): module.main()
	else:
		runner = load('r5_corpus_runner', ROOT/'tests/selfhost-effects/recover-qualify.py')
		runner.expanded_corpus = module.corpus; sys.argv += ['--expanded']; runner.main()


if __name__ == '__main__':
	main()
