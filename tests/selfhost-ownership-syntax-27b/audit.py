#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independently bind compiler generations, execution receipts and preservation."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess

from support import output_path, sha, write

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
BASE = 'e750030baa139481d89946b2b2182dbe72628d31'
PROPOSAL = 'd77c02f3144ab5dc3da41eb310b29cd02629b49876042934ea5071a1549ac66e'


def load(path): return json.loads(Path(path).read_text())


def git(*args): return subprocess.check_output(['git', '-C', str(ROOT), *args])


def observe(directory, pid):
	identity = load(directory/'build-identity.json'); inputs = load(directory/'inputs.json')['inputs']
	process = Path('/proc')/str(pid)
	actual = [v.decode() for v in (process/'cmdline').read_bytes().split(b'\0') if v]
	assert actual == identity['argv'], 'running argv differs from frozen compiler plan'
	assert sha(process/'exe') == identity['tools'][str(Path(actual[0]).resolve())]
	assert len(inputs) == 206 and actual[1:4] == ['-c', '-O2', '-o'] and actual[5:] == list(inputs)
	assert all(sha(path) == h for path, h in inputs.items())
	imports = subprocess.check_output(['nm', '-D', '--undefined-only', actual[0]], text=True)
	for line in imports.splitlines():
		name = line.split()[-1].split('@', 1)[0]
		assert name not in ('system', 'popen', 'fork', 'vfork', 'execve', 'execvp', 'posix_spawn', 'posix_spawnp'), name
	environment = dict(entry.split(b'=', 1) for entry in (process/'environ').read_bytes().split(b'\0') if b'=' in entry)
	selected = {key:environment.get(key.encode(), b'').decode() for key in ('CCACHE_DISABLE', 'LD_PRELOAD', 'VALGRIND_OPTS', 'TMPDIR')}
	assert selected['CCACHE_DISABLE'] == '1' and not selected['LD_PRELOAD'] and not selected['VALGRIND_OPTS']
	write(directory/'independent-producer-process.json', dict(status='ACTUAL_STAGE1_PRODUCER_PROCESS_AUTHENTICATED', UTC=datetime.datetime.now(datetime.timezone.utc).isoformat(), pid=pid, actual_argv=actual, executable_sha256=sha(process/'exe'), sources=inputs, environment=selected, dynamic_imports_sha256=hashlib.sha256(imports.encode()).hexdigest(), imported_process_launch_functions=[], scope='Independent live /proc observation of the actual compiler process and complete frozen source closure. No Stage3 or convergence credit.'))


def receipt(directory, status):
	v = load(directory/'result.json'); assert v['status'] == status, (directory, v['status'])
	for row in load(directory/'commands.json') if (directory/'commands.json').exists() else []:
		result = row.get('result', row.get('observation'))
		if result is None: continue
		assert result['status'] == 'EXPECTED_OUTCOME' and not result['timed_out']
		for stream in ('stdout', 'stderr', 'time'):
			path = directory/row['name']/('time.txt' if stream == 'time' else stream)
			assert sha(path) == result[stream+'_sha256'], path
	return v


def preservation(initial):
	old = load(initial)
	assert len(old['protected']) == 451 and len(old['donor']) == 6622 and len(old['hooks']) == 14
	assert all(sha(ROOT/name) == h for name, h in old['protected'].items())
	donor = ROOT.parent/'astra-bootstrap'
	for name, row in old['donor'].items():
		path = donor/name; assert sha(path) == row['sha256'] and oct(path.stat().st_mode & 0o777) == row['mode']
	assert subprocess.check_output(['git', '-C', str(donor), 'rev-parse', 'HEAD']).decode().strip() == old['donor_HEAD']
	assert subprocess.check_output(['git', '-C', str(donor), 'status', '--porcelain=v2', '--untracked-files=all']).decode() == old['donor_status']
	for name, row in old['hooks'].items():
		assert sha(name) == row['sha256'] and oct(Path(name).stat().st_mode & 0o777) == row['mode']
	assert hashlib.sha256(git('config', '--show-origin', '--list')).hexdigest() == old['git_settings_sha256']
	assert sha(ROOT/'tests/selfhost-compiler-complete/run.py') == old['untracked_run_sha256']
	assert sha(ROOT/'docs/selfhost-effects-25-abi-proposal.md') == old['approved_proposal_sha256'] == PROPOSAL
	base_scope = json.loads(git('show', BASE+':format/scope.json'))
	scope = load(ROOT/'format/scope.json')
	assert all(scope[name] == row for name, row in base_scope.items())
	for name, row in scope.items():
		if 'exclude' in row: assert sha(ROOT/name) == row['sha256']
	assert sha('/home/pmjobin/.agents/skills/pm-next/scripts/common.py') == '3a755214c16490696097452ae39fc3393a1de6b0f0eb2efeb89ad0a8e20c91f5'
	stages = load(WORK/'runtime/selfhost27a/audit3/result.json')['stages']
	for stage in [stages['stage1'], *stages['stage2'].values()]: assert sha(stage['path']) == stage['sha256']
	assert sha(WORK/'runtime/selfhost27b-intake/predecessor-27a-report.zip') == 'de5cd9ed28c3960c272bf9456cbdbb2127d3fd17ee3cb0e867e320fbe6ae2a7d'
	assert load(WORK/'runtime/selfhost27a/audit3/result.json')['gates']['G7']['status'] == 'PENDING'
	workflow = {str(path):sha(path) for path in Path('/home/pmjobin/.agents/skills/pm-next').rglob('*') if path.is_file() and path.suffix in ('.py', '.md')}
	assert len(workflow) == 6
	return dict(status='LIVE_SOURCE_DONOR_USER_WORK_AND_FIRST_SELFBUILD_PRESERVED', paths=451, donor_files=6622, hooks=14, settings_unchanged=True, scope_entries_preserved=len(base_scope), proposal_sha256=PROPOSAL, workflow_current_hashes=workflow, initial_manifest_sha256=sha(initial), historical_raw_proofs='NOT_RESTORED_AFTER_PRIOR_USER_AUTHORIZED_PURGE; counts and prior qualification remain historical, with no new preservation or execution claim for absent raw files.')


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--observe-build', type=Path); p.add_argument('--pid', type=int)
	for key in ('stage1', 'stage2', 'native', 'intrinsic', 'physical', 'semantic', 'legacy-stage1', 'legacy-stage2', 'runtime'): p.add_argument('--'+key, type=Path)
	a = p.parse_args()
	if a.observe_build:
		assert a.pid and not a.runtime; observe(output_path(a.observe_build, WORK/'runtime'), a.pid); return
	assert all(getattr(a, key) for key in ('stage1', 'stage2', 'native', 'intrinsic', 'physical', 'semantic', 'legacy_stage1', 'legacy_stage2', 'runtime'))
	runtime = output_path(a.runtime, WORK/'runtime'); runtime.mkdir(parents=True, exist_ok=False)
	assert not git('diff', '--name-only').strip() and not git('diff', '--cached', '--name-only').strip()
	head = git('rev-parse', 'HEAD').decode().strip(); tree = git('rev-parse', 'HEAD^{tree}').decode().strip()
	assert subprocess.run(['git', '-C', ROOT, 'merge-base', '--is-ancestor', BASE, head]).returncode == 0
	first = receipt(a.stage1, 'PRODUCTION_DRIVER_BUILT_NOT_QUALIFIED'); second = receipt(a.stage2, 'PRODUCTION_DRIVER_BUILT_NOT_QUALIFIED')
	assert first['producer']['kind'] == 'c0' and second['producer']['kind'] == 'astra'
	assert sha(first['product']['path']) == first['product']['sha256'] == second['producer']['sha256']
	assert first['product']['path'] == second['producer']['path'] and sha(second['product']['path']) == second['product']['sha256']
	assert first['compiler_sources'] == second['compiler_sources'] == 196 and first['libraries'] == second['libraries'] == 10
	for row in load(a.stage2/'snapshot.json')['sources']:
		name = str(Path(row['original_path']).relative_to(ROOT))
		assert sha(row['input_path']) == row['sha256'] == sha(row['original_path'])
		assert (ROOT/name).read_bytes() == git('show', second['revision']+':'+name) == git('show', head+':'+name)
	witness = load(a.stage2/'independent-producer-process.json'); assert witness['executable_sha256'] == first['product']['sha256']
	native = receipt(a.native, 'SELECTED_CURRENT_COMPILER_NATIVE_GATES_PASS')
	assert set(native['features']) == {'initial', 'records', 'conditional', 'compound', 'weak', 'borrowed', 'workload', 'errors'} and len(native['selected_cases']) == 16
	assert not native['oracle_only'] and native['compiler']['sha256'] == second['product']['sha256']
	for path, h in {**native['source_inputs'], **native['products'], **native['tools'], **native['providers']}.items(): assert sha(path) == h
	intrinsic = receipt(a.intrinsic, 'SELECTED_INTRINSIC_ABI_NATIVE_GATES_PASS'); assert intrinsic['compiler_sha256'] == second['product']['sha256'] and not intrinsic['oracle_only']
	physical = receipt(a.physical, 'SELECTED_INDEPENDENT_PHYSICAL_MUTATIONS_PASS'); assert physical['compiler_sha256'] == second['product']['sha256'] and physical['mutations'] == 13 and physical['controls'] == 5
	semantic = receipt(a.semantic, 'SELECTED_SOURCE_OWNERSHIP_FACT_MUTATIONS_PASS'); assert semantic['compiler_sha256'] == first['product']['sha256'] and semantic['mutations'] == 14 and semantic['controls'] == 4
	for directory, product in ((a.legacy_stage1, first['product']), (a.legacy_stage2, second['product'])):
		legacy = receipt(directory, 'SELECTED_LEGACY_REGRESSIONS_PASS'); assert legacy['compiler_sha256'] == product['sha256'] and legacy['programs'] == 7 and legacy['strict_returning_memory_streams'] == 21
		assert sha(directory/'identity.json') == legacy['identity_sha256'] and sha(directory/'programs.json') == legacy['programs_sha256']
		for row in load(directory/'programs.json'):
			assert row['raw_LLVM_identical']
			for path, h in {**row['sources'], **row['products']}.items(): assert sha(path) == h
	for directory, result in ((a.intrinsic, intrinsic), (a.physical, physical), (a.semantic, semantic)):
		assert sha(directory/'identity.json') == result['identity_sha256']
		identity = load(directory/'identity.json')
		for path, h in {**identity['inputs'], **identity['tools']}.items(): assert sha(path) == h
		if directory == a.intrinsic:
			for path, h in {**result['products'], **load(directory/'source-inputs.json')}.items(): assert sha(path) == h
			continue
		assert sha(directory/'observations.json') == result['observations_sha256']
		rows = load(directory/'observations.json'); assert len(rows) == result['mutations']+result['controls']
		for row in rows:
			observation = row['observations']; control = row['action'].endswith('control')
			assert observation['inferior-exit']['exit'] == int(not control)
			if directory == a.physical: assert observation['structural-return']['returned'] == 0
			else: assert observation['consumer-return']['returned'] == int(control)
	memory = []
	for directory in (a.native, a.intrinsic, a.legacy_stage1, a.legacy_stage2):
		for row in load(directory/'commands.json'):
			if row['name'].endswith('memory'):
				path = directory/row['name']/'stderr'; log = path.read_bytes()
				assert all(v in log for v in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
				memory.append(dict(path=str(path), sha256=sha(path)))
	assert len(memory) == 95
	prior = load(WORK/'runtime/selfhost27b-g7v2/result.json'); assert prior['new_G7_actual_Astra_compiler_native_memory_ABI_negatives'] == 'PASS' and prior['HEAD'] == BASE
	protected = preservation(WORK/'runtime/selfhost27b-intake/pre-edit-preservation.json'); write(runtime/'preservation.json', protected)
	receipts = {str(directory/'result.json'):sha(directory/'result.json') for directory in (a.stage1, a.stage2, a.native, a.intrinsic, a.physical, a.semantic, a.legacy_stage1, a.legacy_stage2)}
	write(runtime/'result.json', dict(status='BOUNDED_27B_IMPLEMENTATION_QUALIFIED_HISTORICAL_PRESERVATION_PARTIAL', UTC=datetime.datetime.now(datetime.timezone.utc).isoformat(), HEAD=head, tree=tree, stages=dict(stage1=first, stage2=second), gates=dict(G0='PASS_WITH_USER_AUTHORIZED_C0_REBUILD_AND_LOSSLESS_INTAKE_PACKAGING', G1='PASS_BOUNDED_IMPLEMENTED_CONTRACT', G2='PASS_ALL_SEVEN_SYNTAX_GROUPS', G3='PASS_ACTUAL_C0_STAGE1_TO_ASTRA_STAGE2_WITH_EXPLICIT_SOURCE_REVISIONS', G4='PARTIAL_ABSENT_PREVIOUSLY_PURGED_RAW_HISTORICAL_PROOFS; LIVE_PROTECTION_PASS; PUBLICATION_PENDING', G5='PENDING_SEPARATE_AFTER_PUBLICATION_CHECK'), receipts=receipts, strict_returning_memory_streams=memory, C0_rebuilt_identity=prior['C0_rebuild'], historical_411_101_52='Preserved prior report qualifications only; no invented current complete-cohort replay.', full_milestone27_credit=False, Stage3_credit=False, release_credit=False, reserved='27-C complete idiomatic migration, named args, match expressions, typed interpolation, ranges (20..=80).step_by(5).collect_array() with 13 values, safe slicing, lazy pipelines and comprehensions; 27-D fixed improved-source full Stage1/2/3 convergence; 28 first release.', limitation='Implementation and focused independent gates are qualified only if every asserted receipt exists. Previously user-authorized cleanup removed the original C0 and external historical raw proof population. Replacement C0 is separately qualified and identified; its GLib/LLVM process has no strict all-kinds memory PASS. No raw-history preservation claim or narrowed overall PASS. G5 remains pending until installed publication.'))
	print('BOUNDED_27B_IMPLEMENTATION_QUALIFIED_HISTORICAL_PRESERVATION_PARTIAL', flush=True)


if __name__ == '__main__': main()
