#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""R4 engineering test routing; the installed pm-next owns intake/publication."""
import hashlib
import json
from pathlib import Path
import shutil
import sys
import zipfile
import state

ROOT = state.ROOT
BASE = '776b91c28128c2d5e10b198d0fb510a7f587ac5f'
TREE = 'ce49dee559e27edf6e261804da2f98e94a0f389e'
REPORT = 'f3547341290442b90c59e45e949221c18421f7c5daa3448dfa2cd2c37b722c14'
RUNTIME = ROOT.parent/'codex/work/astra/runtime/effects25-r4'
BUILD = ROOT.parent/'codex/work/astra/build/effects25-r4'
INPUT = RUNTIME.parent/'native-current/input'


def authenticate():
	assert state.git('rev-parse', 'HEAD').strip() == BASE
	assert state.git('rev-parse', 'HEAD^{tree}').strip() == TREE
	assert not state.git('diff', '--name-only') and not state.git('diff', '--cached', '--name-only')
	result = state.preservation()
	receipt = state.read(INPUT/'reference/approval/abi-approval.json')
	assert receipt == state.read(RUNTIME.parent/'effects25-r3/initial.json')['approval']
	proposal = 'd77c02f3144ab5dc3da41eb310b29cd02629b49876042934ea5071a1549ac66e'
	assert receipt['proposal_sha256'] == proposal == state.sha(ROOT/'docs/selfhost-effects-25-abi-proposal.md') == state.sha(INPUT/'reference/approval/E25-A-v1-proposal.md')
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
	assert receipt['answer']['reply']['questionItemId'] == json.dumps(['request_user_input_async', question['call_id'], 0], separators=(',', ':'))
	index = state.read(INPUT/'REFERENCE-INDEX.json')['references']
	rows = ((row['path'], row) for row in index)
	for name, row in rows:
		assert (INPUT/name).stat().st_size == row['bytes'] and state.sha(INPUT/name) == row['sha256']
	report = ROOT.parent/'codex/reports/astra-report-current.zip'
	assert state.sha(report) == REPORT and report.stat().st_size == 22035645
	with zipfile.ZipFile(report) as z:
		assert z.testzip() is None
		manifest = json.loads(z.read('MANIFEST.json')); assert len(manifest['files']) == 84
		for row in manifest['files']:
			data = z.read(row['path']); assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
		previous = json.loads(z.read('RESULT.json'))
		assert (previous['status'], previous['final_commit'], previous['final_tree']) == ('PARTIAL', BASE, TREE)
		for name in ('REPORT.md', 'RESULT.json', 'changes.patch'):
			assert z.read(name) == (INPUT/'reference/report/R3'/name).read_bytes()
		snapshots = [name for name in z.namelist() if name.startswith('source/')]; assert len(snapshots) == 57
		for name in snapshots: assert (ROOT/name[7:]).read_bytes() == z.read(name), name
	RUNTIME.mkdir(); BUILD.mkdir()
	shutil.copy2(report, RUNTIME/'predecessor-report.zip')
	result.update(base=BASE, tree=TREE, predecessor_sha256=REPORT, predecessor=previous, approval=receipt, initial_status=state.git('status', '--porcelain=v2', '--untracked-files=all'), refs=state.git('show-ref'), worktrees=state.git('worktree', 'list', '--porcelain'))
	(RUNTIME/'initial.json').write_text(json.dumps(result, indent=2)+'\n')
	print('R4 exact base, R3 PARTIAL, approval, references and protected state authenticated', flush=True)


def route():
	r3 = state.load_module('r4_inherited_route', ROOT/'tests/selfhost-effects/r3.py')
	r3.RUNTIME = RUNTIME; r3.BUILD = BUILD
	inherited_load = r3.route()
	def load(name, path):
		path = Path(path); original_bytes = path.read_bytes(); source_digest = hashlib.sha256(original_bytes).hexdigest()
		if path.is_relative_to(ROOT):
			snapshot = RUNTIME/'recipe-inputs'/source_digest/path.relative_to(ROOT); snapshot.parent.mkdir(parents=True, exist_ok=True)
			if snapshot.exists(): assert snapshot.read_bytes() == original_bytes
			else: snapshot.write_bytes(original_bytes)
		module = inherited_load(name, path)
		assert path.read_bytes() == original_bytes, ('recipe changed while loading', str(path))
		if Path(path) == ROOT/'tests/selfhost-typecore/build.py':
			original_build = module.build
			def build(compiler, directory, capture, *args, **kwargs):
				kwargs['link_inputs'] = [*kwargs.get('link_inputs', ()), Path(__file__)]
				def snapshot(argv, label, details=None):
					if argv is None and details and 'sources' in details:
						key = hashlib.sha256(json.dumps(details, sort_keys=True).encode()).hexdigest(); leaf = RUNTIME/'compiler-inputs'/key
						leaf.mkdir(parents=True, exist_ok=True)
						for source, expected in details['sources'].items():
							if Path(source).is_relative_to(ROOT):
								assert state.sha(source) == expected; target = leaf/Path(source).relative_to(ROOT); target.parent.mkdir(parents=True, exist_ok=True)
								if target.exists(): assert state.sha(target) == expected
								else: target.write_bytes(Path(source).read_bytes())
						(leaf/'identity.json').write_text(json.dumps(details, indent=2)+'\n')
					return capture(argv, label, details) if argv is None else capture(argv, label)
				return original_build(compiler, directory, snapshot, *args, **kwargs)
			module.build = build
		return module
	state.load_module = load
	original_run = state.bounded_run
	def run(argv, **kwargs):
		# Inherited consolidated recipes spawn their historical routing entry.
		# Redirect only that exact entry to this campaign; never edit old receipts.
		argv = [Path(__file__) if str(arg) == str(ROOT/'tests/selfhost-effects/r3.py') else arg for arg in argv]
		return original_run(argv, **kwargs)
	state.bounded_run = run
	return load


def main():
	if sys.argv[1:] == ['authenticate']:
		authenticate(); return
	load = route(); recipe = sys.argv.pop(1)
	assert recipe.startswith('recover-') and '/' not in recipe and '.' not in recipe
	module = load('r4_recipe_'+recipe, ROOT/('tests/selfhost-effects/'+recipe+'.py'))
	if hasattr(module, 'main'): module.main()
	else:
		runner = load('r4_corpus_runner', ROOT/'tests/selfhost-effects/recover-qualify.py')
		runner.expanded_corpus = module.corpus; sys.argv += ['--expanded']; runner.main()


if __name__ == '__main__':
	main()
