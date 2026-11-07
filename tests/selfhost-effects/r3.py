#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""R3 routing and authenticated intake; historical recipes remain immutable."""
import hashlib
import json
from pathlib import Path
import shutil
import sys
import zipfile
import state

ROOT = state.ROOT
BASE = '633b713cfc14de4d77166ea4220eb5a3bdb6f072'
TREE = '952c6253e71742e1a60eb5e29f1d1c0c5913b57a'
REPORT = 'e7b87031caf01b586df57d84b180685fa12001c2029979b67f1f19a38990c81f'
RUNTIME = ROOT.parent/'codex/work/astra/runtime/effects25-r3'
BUILD = ROOT.parent/'codex/work/astra/build/effects25-r3'
INPUT = RUNTIME.parent/'native-current/input'


def authenticate():
	assert state.git('rev-parse', 'HEAD').strip() == BASE
	assert state.git('rev-parse', 'HEAD^{tree}').strip() == TREE
	assert not state.git('diff', '--name-only') and not state.git('diff', '--cached', '--name-only')
	result = state.preservation()
	proposal = 'd77c02f3144ab5dc3da41eb310b29cd02629b49876042934ea5071a1549ac66e'
	receipt = state.read(INPUT/'reference/approval/abi-approval.json')
	assert receipt == state.read(RUNTIME.parent/'effects25-r1/initial.json')['approval']
	assert receipt['receipt'] == state.read(RUNTIME.parent/'effects25/abi-approval.json')
	assert receipt['proposal_sha256'] == proposal == state.sha(ROOT/'docs/selfhost-effects-25-abi-proposal.md') == state.sha(INPUT/'reference/approval/E25-A-v1-proposal.md')
	lines = Path(receipt['session']).read_bytes().splitlines()
	for kind in ('question', 'answer'):
		row = receipt[kind]; raw = lines[row['line']-1]
		assert hashlib.sha256(raw).hexdigest() == row['sha256']
		assert json.loads(raw)['timestamp'] == row['timestamp']
	question = json.loads(lines[receipt['question']['line']-1])['payload']
	answer = json.loads(lines[receipt['answer']['line']-1])['payload']
	assert question['name'] == 'request_user_input_async' and json.loads(question['arguments']) == receipt['question']['arguments']
	assert answer['role'] == 'user'
	replies = [json.loads(c['text'].split('\n', 1)[1].rsplit('\n', 1)[0]) for c in answer['content'] if c.get('text', '').startswith('<send_user_message_question_reply>')]
	assert receipt['answer']['reply'] in [r for group in replies for r in group]
	assert receipt['answer']['reply']['answer'] == 'APPROVE THE BOUNDED DESIGN E25-A-v1'
	assert receipt['answer']['reply']['questionItemId'] == json.dumps(['request_user_input_async', question['call_id'], 0], separators=(',', ':'))
	for name, row in state.read(INPUT/'REFERENCE-INDEX.json')['files'].items():
		path = INPUT/name
		assert path.stat().st_size == row['bytes'] and state.sha(path) == row['sha256']
	report = ROOT.parent/'codex/reports/astra-report-current.zip'
	assert state.sha(report) == REPORT and report.stat().st_size == 17794440
	with zipfile.ZipFile(report) as z:
		assert z.testzip() is None and len(z.namelist()) == 118
		manifest = json.loads(z.read('MANIFEST.json'))
		assert len(manifest['files']) == 117
		for row in manifest['files']:
			data = z.read(row['path'])
			assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
		previous = json.loads(z.read('RESULT.json'))
		assert (previous['status'], previous['final_commit'], previous['final_tree']) == ('PARTIAL', BASE, TREE)
		for name in ('REPORT.md', 'RESULT.json', 'changes.patch'):
			assert z.read(name) == (INPUT/'reference/r2'/name).read_bytes()
		snapshots = [p for p in z.namelist() if p.startswith('source/')]
		assert len(snapshots) == 91
		for name in snapshots:
			assert (ROOT/name[len('source/'):]).read_bytes() == z.read(name), name
	RUNTIME.mkdir(exist_ok=False); BUILD.mkdir(exist_ok=False)
	shutil.copy2(report, RUNTIME/'predecessor-report.zip')
	result.update(base=BASE, tree=TREE, predecessor_sha256=REPORT, predecessor=previous, approval=receipt, initial_status=state.git('status', '--porcelain=v2', '--untracked-files=all'), refs=state.git('show-ref'), worktrees=state.git('worktree', 'list', '--porcelain'))
	(RUNTIME/'initial.json').write_text(json.dumps(result, indent=2)+'\n')
	print('R3 exact intake/report, original native approval, protected paths/donor, historical proofs and source snapshots authenticated', flush=True)


def route():
	original = state.load_module
	def load(name, path):
		module = original(name, path)
		if Path(path).name == 'recover-build.py':
			module.RUNTIME = RUNTIME
			module.BUILD = BUILD
		if Path(path) in (ROOT/'tests/selfhost-typecore/build.py', ROOT/'tests/selfhost-genref/build.py'):
			entry = 'build' if Path(path).name == 'build.py' and Path(path).parent.name == 'selfhost-typecore' else 'original'
			build = getattr(module, entry)
			def pinned_build(*args, **kwargs):
				kwargs['link_inputs'] = list(dict.fromkeys([*kwargs.get('link_inputs', ()), Path(__file__)]))
				kwargs['extra_sources'] = list(dict.fromkeys([*kwargs.get('extra_sources', ()), ROOT/'tests/selfhost-effects/recover-r3-mutations.astra', ROOT/'tests/selfhost-effects/recover-r3-domain-mutations.astra']))
				return build(*args, **kwargs)
			setattr(module, entry, pinned_build)
		return module
	state.load_module = load
	return load


def main():
	if sys.argv[1:] == ['authenticate']:
		authenticate()
		return
	load = route(); recipe = sys.argv.pop(1)
	def run(name):
		module = load('r3_recipe_'+name, ROOT/('tests/selfhost-effects/'+name+'.py'))
		if hasattr(module, 'main'):
			module.main()
		else:
			runner = load('r3_corpus_runner', ROOT/'tests/selfhost-effects/recover-qualify.py')
			runner.expanded_corpus = module.corpus
			sys.argv += ['--expanded']
			runner.main()
	if recipe == 'baseline':
		mode = sys.argv[1]; assert mode in ('O0', 'O2')
		component = BUILD.parent/('effects25-r2-completion/full-v11-'+mode)/('astra-llvm-'+mode)
		jobs = [('recover-regression', []), ('recover-qualify', ['--expanded']), ('recover-record-qualify', []), ('recover-owned-qualify', []), ('recover-error-owned-qualify', []), ('recover-loop-qualify', []), ('recover-adversarial', []), ('recover-owner-adversarial', []), ('recover-loop-adversarial', []), ('recover-original', ['--provider-build', str(component.parent)])]
		for name, extra in jobs:
			sys.argv = [name, '--mode', mode, '--version', 'baseline'+name.replace('recover-', '').replace('-', ''), '--component', str(component), *extra]
			if name == 'recover-regression' and (RUNTIME/('regression-baselineregression-'+mode)/'result.json').exists():
				continue
			if name == 'recover-qualify' and (RUNTIME/('early-baselinequalify-'+mode)/'result.json').exists():
				result = state.read(RUNTIME/('early-baselinequalify-'+mode)/'result.json')
				assert result['new_Astra_effect_ELFs'] == 15
				continue
			print(mode, name, flush=True)
			run(name)
		return
	assert recipe.startswith('recover-') and '/' not in recipe and '.' not in recipe
	run(recipe)


if __name__ == '__main__':
	main()
