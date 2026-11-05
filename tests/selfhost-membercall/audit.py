#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Audit the exact diagnostic checkpoint without promoting unmet gates."""
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, PRIOR, BASE, TREE, COHORTS, read, sha, git


def metrics(path):
	text = path.read_text(); result = {}
	for key,label in [('user_CPU_seconds','User time (seconds)'),('system_CPU_seconds','System time (seconds)'),('peak_RSS_KiB','Maximum resident set size (kbytes)')]:
		match = re.search(re.escape(label)+r':\s*([0-9.]+)',text); result[key] = float(match[1]) if match else None
	return result


def active_union(intervals):
	end = None; total = 0.0
	for left,right in sorted(intervals):
		if end is None or right > end: total += right-max(left,end if end is not None else left)
		end = max(right,end if end is not None else right)
	return total


def main():
	assert git('status','--porcelain=v1','--untracked-files=all') == ''
	head = git('rev-parse','HEAD').strip(); tree = git('rev-parse','HEAD^{tree}').strip(); initial = read(RUNTIME/'initial.json')
	assert initial['base'] == BASE and initial['tree'] == TREE
	assert subprocess.run(['git','merge-base','--is-ancestor',BASE,head],cwd=ROOT).returncode == 0
	changed = git('diff','--name-only',BASE+'..'+head).splitlines()
	assert all(path.startswith('tests/selfhost-membercall/') or path in ('format/scope.json','docs/selfhost-membercall-22-checkpoint.md') for path in changed)
	spec = importlib.util.spec_from_file_location('preservation',ROOT/'tests/selfhost-genresource/state.py'); previous = importlib.util.module_from_spec(spec); spec.loader.exec_module(previous)
	assert all(value == initial[key] for key,value in previous.preservation().items())
	for path in initial['protected']:
		mode = git('ls-tree',BASE,'--',path).split()[0]; assert mode in ('100644','100755')
		assert (ROOT/path).stat().st_mode & 0o777 == (0o755 if mode == '100755' else 0o644)
	assert sha(RUNTIME/'predecessor-report.zip') == initial['predecessor_sha256']
	assert git('config','--show-origin','--list') == initial['config'] and git('stash','list') == initial['stash']
	refs = {row.split()[1]:row.split()[0] for row in git('show-ref').splitlines()}; oldrefs = {row.split()[1]:row.split()[0] for row in initial['refs'].splitlines()}
	assert refs.keys() == oldrefs.keys() and all(refs[name] == value for name,value in oldrefs.items() if name != 'refs/heads/main')
	assert git('worktree','list','--porcelain').replace('HEAD '+head,'HEAD '+BASE) == initial['worktrees']
	for path,value in initial['hooks'].items(): assert sha(path) == value['sha256'] and oct(Path(path).stat().st_mode & 0o777) == value['mode']
	for path,value in initial['workflow'].items(): assert sha(path) == value
	proofs = read(RUNTIME.parent/'indexpath18/historical-proof-outputs.json'); assert len(proofs['outputs']) == proofs['count'] == 1044
	assert all(sha(path) == row['sha256'] for path,row in proofs['outputs'].items())
	for path in ('AGENTS.md','CODING_STYLE.md','codex-project.json'):
		assert (ROOT/path).read_bytes() == subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT)
	old_scope = json.loads(subprocess.check_output(['git','show',BASE+':format/scope.json'],cwd=ROOT)); scope = read(ROOT/'format/scope.json')
	assert all(scope.get(path) == value for path,value in old_scope.items())
	products = dict(initial['products']); observer = BUILD/'diagnosis-v3/diagnose-O0'; products['observer'] = dict(path=str(observer),sha256=sha(observer))
	for product in products.values():
		path = Path(product['path']); identity = read(path.with_suffix('.identity.json'))
		assert sha(path) == identity['sha256'] == product['sha256']
		assert all(sha(path) == value for group in ('sources','tools') for path,value in identity['identity'][group].items())
	profiles = {}; costs = []; intervals = []
	for mode in ('O0','O2'):
		replay = read(RUNTIME/('inherited-'+mode)/'result.json'); assert replay['status'] == 'INHERITED_REPLAY_PASS'
		rows = replay['programs']; assert len(rows) == len({tuple(source['sha256'] for source in row['sources']) for row in rows}) == 172
		elfs = []
		for row in rows:
			assert all(sha(s['path']) == s['sha256'] for s in row['sources'])
			assert sha(row['fresh_raw']['path']) == row['fresh_raw']['sha256']
			assert all(sha(p['path']) == p['sha256'] for p in row['qualified_products'].values())
			product = row['qualified_products']; elfs.append(product.get('native',product.get('executable'))['sha256'])
		assert len(set(elfs)) == (172 if mode == 'O0' else 152)
		profiles[mode] = dict(inherited_source_programs=172,fresh_LLVM_emissions=172,fresh_LLVM_verifications=172,fresh_ELF_executions=172,distinct_ELF_bytes=len(set(elfs)),new_native_programs=0,new_mutation_categories=0,new_physical_alternatives=0,new_material_memory_qualifications=0)
	continuity = read(RUNTIME/'continuity/result.json'); assert continuity['status'] == 'INHERITED_CONTROLS_PASS'
	for mode in ('O0','O2'): assert continuity['results'][mode]['source-status'] == {'0':56,'4':12,'3':12}
	assert read(RUNTIME/'reference-v4/result.json')['status'] == 'C0_BOUNDED_CHECKS_PASS'
	assert read(RUNTIME/'effect-boundary-v2/result.json')['status'] == 'EXISTING_EFFECT_BOUNDARY_CONFIRMED'
	assert read(RUNTIME/'diagnostic-controls-v2/result.json')['status'] == 'DISTINGUISHING_CONTROLS_PASS'
	trace = read(RUNTIME/'inference-operands-v2/result.json'); assert trace['status'] == 'ACTUAL_OPERANDS_OBSERVED' and set(trace['results']) == set(COHORTS)
	facts = read(RUNTIME/'facts-v2/result.json'); assert set(facts['cohorts']) == set(COHORTS)
	for name in COHORTS:
		assert facts['cohorts'][name]['first_stop'] == initial['cohorts'][name]['first_stop']
		assert (RUNTIME/'diagnosis-v3'/(name+'.stdout')).is_file()
	for version in ('v1','v2','v3'):
		leaf = RUNTIME/('diagnosis-'+version); row = read(leaf/'typecore-O0.json'); assert row['exit'] == 0
		costs.append(dict(kind='cold_read_only_observer_build',version=version,wall_seconds=row['end']-row['start'],**metrics(leaf/'typecore-O0.stderr'))); intervals.append((row['start'],row['end']))
	command_costs = {}
	for name in ('inherited-O0','inherited-O2','continuity','facts-v2','reference-v4','effect-boundary-v2','diagnostic-controls-v2'):
		leaf = RUNTIME/name; commands = read(leaf/'commands.json'); ranges = [(row['start'],row['end']) for row in commands]
		command_costs[name] = dict(wall_sum_seconds=sum(right-left for left,right in ranges),active_wall_union_seconds=active_union(ranges),commands=len(commands),measurements=[dict(name=row['name'],**metrics(leaf/(row['name']+'.time'))) for row in commands])
	result = dict(format='astra-membercall22-checkpoint/1',status='PARTIAL',final_commit=head,final_tree=tree,base_commit=BASE,base_tree=TREE,changed_paths=changed,compiler_sources_unchanged=True,protected_files=451,donor_files=6622,historical_proof_outputs=1044,historical_attribution='Byte identities preserved; no new historical-proof qualification claimed',products=products,profiles=profiles,continuity=continuity['results'],cohorts=initial['cohorts'],actual_inference_operands=trace['results'],cold_observer_builds=costs,observer_build_active_union_seconds=active_union(intervals),observer_build_overlap_seconds=sum(right-left for left,right in intervals)-active_union(intervals),command_costs=command_costs,measured_interval_seconds=time.monotonic()-min(row['start'] for row in initial['cohorts'].values()),cost_limitations='Measured interval starts at the first frozen compiler replay, excluding earlier intake/inventory work. No new native O0/O2 cold builds; exact inherited products reused. Failed whole-C0 check CPU/RSS total unavailable after its timer child outlived timeout. Nested continuity child costs are included once at the parent level. Other failed attempts remain in their own logs.',gates={'G0':'VERIFIED','G1':'FOUR_FIRST_STOPS_AND_ACTUAL_OPERANDS_REPRODUCED; whole frozen C0 check timed out; bounded C0 views separately verified','G2':'UNAVAILABLE_OPERANDS_AND_ZERO_PARAMETER_ROUTE_DISTINGUISHED; repair not implemented','G3':'NOT_IMPLEMENTED','G4':'COMPLETE_ORIGINAL_CALLERS_BLOCKED_BY_UNQUALIFIED_THROWS_EFFECT_CONTRACT','G5':'172_INHERITED_REPLAYED_PER_PROFILE; 0_NEW','G6':'NO_NEW_QUALIFICATION; inherited ABI/memory historical','G7':'NO_NEW_MUTATION_CAMPAIGN','G8':'NO_SOURCE_ADVANCEMENT; original stops unchanged','G9':'CONTINUITY_AND_PRESERVATION_VERIFIED; new cold build campaign incomplete','G10':'CHECKPOINT_COMMITTED; installed publication pending'},next_work='Resolve complete-original-caller versus bounded nonthrowing-driver witness scope without dropping declared effects, then implement and independently qualify member target/receiver/argument contracts under the original limits.',recipe_sha256=sha(__file__))
	(RUNTIME/'checkpoint-audit.json').write_text(json.dumps(result,indent=2)+'\n'); print(head,tree,'PARTIAL: unchanged compiler; 172 inherited identities/profile; all preservation checks verified')


if __name__ == '__main__':
	main()
