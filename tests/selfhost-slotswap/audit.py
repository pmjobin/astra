#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Reconcile actual current gates, immutable history and compiled Git bindings."""
import importlib.util
import json
from pathlib import Path
import re
import subprocess
from state import ROOT, RUNTIME, BUILD, PRIOR, BASE, COHORTS, read, sha, git


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
	head = git('rev-parse','HEAD').strip(); tree = git('rev-parse','HEAD^{tree}').strip()
	assert subprocess.run(['git','merge-base','--is-ancestor',BASE,head],cwd=ROOT).returncode == 0
	initial = read(RUNTIME/'initial.json')
	spec = importlib.util.spec_from_file_location('preservation',ROOT/'tests/selfhost-genresource/state.py'); module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
	assert all(value == initial[key] for key,value in module.preservation().items())
	assert sha(RUNTIME/'predecessor-report.zip') == initial['predecessor_sha256']
	assert git('config','--show-origin','--list') == initial['config'] and git('stash','list') == initial['stash']
	refs = {row.split()[1]:row.split()[0] for row in git('show-ref').splitlines()}; oldrefs = {row.split()[1]:row.split()[0] for row in initial['refs'].splitlines()}
	assert refs.keys() == oldrefs.keys() and all(refs[name] == value for name,value in oldrefs.items() if name != 'refs/heads/main')
	assert git('worktree','list','--porcelain').replace('HEAD '+head,'HEAD '+BASE) == initial['worktrees']
	for path,value in initial['hooks'].items(): assert sha(path) == value['sha256'] and oct(Path(path).stat().st_mode & 0o777) == value['mode']
	for path,value in initial['workflow'].items(): assert sha(path) == value
	proofs = read(RUNTIME.parent/'indexpath18/historical-proof-outputs.json'); assert len(proofs['outputs']) == proofs['count'] == 1044
	assert all(sha(path) == row['sha256'] for path,row in proofs['outputs'].items())
	for path in ('AGENTS.md','codex-project.json','CODING_STYLE.md'):
		assert (ROOT/path).read_bytes() == subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT)
	old_scope = json.loads(subprocess.check_output(['git','show',BASE+':format/scope.json'],cwd=ROOT)); scope = read(ROOT/'format/scope.json')
	assert all(scope.get(path) == value for path,value in old_scope.items())
	profiles = {}; products = {}; bindings = {}; costs = []
	for mode in ('O0','O2'):
		component = BUILD/('native-v1-'+mode)/('astra-llvm-'+mode); identity = read(component.with_suffix('.identity.json')); assert sha(component) == identity['sha256']
		for path,value in identity['identity']['sources'].items():
			assert sha(path) == value; path = Path(path)
			if path.is_relative_to(ROOT):
				relative = str(path.relative_to(ROOT)); blob = subprocess.check_output(['git','show',head+':'+relative],cwd=ROOT)
				import hashlib
				assert hashlib.sha256(blob).hexdigest() == value; bindings[relative] = dict(sha256=value,Git_blob=git('rev-parse',head+':'+relative).strip())
		assert all(sha(path) == value for path,value in identity['identity']['tools'].items())
		products[mode] = dict(path=str(component),sha256=sha(component),identity_sha256=sha(component.with_suffix('.identity.json')))
		new = read(RUNTIME/('qualified-v1-'+mode)/'result.json'); inherited = read(RUNTIME/('inherited-v2-'+mode)/'result.json')
		assert new['status'] == inherited['status'] == 'PASS' and new['component_sha256'] == inherited['component_sha256'] == sha(component)
		cost_leaves = [RUNTIME/('qualified-v1-'+mode),RUNTIME/('inherited-v2-'+mode)]
		for gate in ('own-mutations','own-faults','own-lifetime','models','resource','inherited-native'):
			name = gate+'-v3' if gate == 'own-lifetime' else gate
			receipt = read(RUNTIME/('replay-'+name+'-'+mode)/'result.json'); assert receipt['status'] == 'PASS' and receipt['component_sha256'] == sha(component)
			cost_leaves.append(RUNTIME/('replay-'+name+'-'+mode))
		assert read(RUNTIME/('witness-'+mode+'.json'))['status'] == 'PASS'
		assert read(RUNTIME/('controls-v1-'+mode)/'result.json')['status'] == 'PASS'
		assert read(RUNTIME/('negative-observation-v1-'+mode)/'result.json')['status'] == 'PASS'
		assert read(RUNTIME/('replay-inherited-native-layout-'+mode)/'result.json')['status'] == 'PASS'
		physical = read(RUNTIME/('physical-v1-'+mode)/'result.json'); negatives = read(RUNTIME/('negative-v2-'+mode)/'result.json'); lifetime = read(RUNTIME/('lifetime-v1-'+mode)/'result.json')
		assert physical['status'] == negatives['status'] == lifetime['status'] == 'PASS'
		assert len(physical['mutations']) == 6 and all(row['LLVM_valid'] and row['independently_rejected'] for row in physical['mutations'])
		assert len(negatives['mutations']) == 10
		rows = inherited['programs']+new['programs']; assert len(rows) == len({tuple(s['sha256'] for s in row['sources']) for row in rows}) == 172
		assert [row['sources'] for row in inherited['programs']] == [row['sources'] for row in read(PRIOR/'engineering-summary.json')['profiles'][mode]['programs']]
		def elf(row):
			p = row.get('products',row.get('qualified_products')); return p.get('native',p.get('executable'))['sha256']
		continuity = read(RUNTIME/('replay-inherited-native-'+mode)/('continuity-'+mode)/'observations/result.json')['outcomes']
		assert continuity == inherited['original_source_statuses'] == {'0':56,'4':12,'3':12}
		allocation_cases = [row['name'] for row in new['programs'] if 'calloc(' in (RUNTIME/('qualified-v1-'+mode)/'observations'/(row['name']+'-memory-native.stderr')).read_text()]
		assert len(allocation_cases) >= 4
		profiles[mode] = dict(source_programs=172,inherited=159,new=13,distinct_ELF_bytes=len({elf(row) for row in rows}),inherited_distinct_ELF_bytes=len({elf(row) for row in inherited['programs']}),programs=rows,new_authority_mutants=14,new_source_controls=10,new_external_LLVM_valid_alternatives=6,conservative_category_note='Nested field qualifier bit variants share an authority; physical and source controls retain their actual independent boundaries.',Valgrind_material_cases=allocation_cases,source_statuses=continuity)
		intervals = []; command_CPU = 0.0; peak = 0
		for cost_leaf in cost_leaves:
			for command in read(cost_leaf/'commands.json'):
				intervals.append((command['start'],command['end'])); measured = metrics(cost_leaf/(command['name']+'.time'))
				command_CPU += (measured['user_CPU_seconds'] or 0)+(measured['system_CPU_seconds'] or 0); peak = max(peak,measured['peak_RSS_KiB'] or 0)
		profiles[mode]['required_gate_cost'] = dict(command_wall_sum_seconds=sum(right-left for left,right in intervals),active_wall_union_seconds=active_union(intervals),command_CPU_seconds=command_CPU,maximum_command_peak_RSS_KiB=peak,scope='Top-level native/inherited/required replay commands; nested children are included once through their parent. Supplemental observer/control/pilot/build and failed earlier replay-attempt costs remain in their separate actual logs.')
		for receipt in (RUNTIME/('native-v1-'+mode)).glob('build-*/ownflow-'+mode+'.json'):
			data = read(receipt); assert data['exit'] == 0; costs.append(dict(mode=mode,**data,**metrics(receipt.with_suffix('.stderr'))))
		assert list((RUNTIME/('warm-'+mode)).glob('build-*/ownflow-'+mode+'-exact-reuse.json'))
	cohorts = read(RUNTIME/'cohorts-v1.json'); assert set(cohorts) == set(COHORTS) and all(row['new_checked_facts_after_swap'] > 0 for row in cohorts.values())
	diagnostic = BUILD/'diagnosis-v2/diagnose-O0'; diagnostic_identity = read(diagnostic.with_suffix('.identity.json'))
	assert sha(diagnostic) == diagnostic_identity['sha256']
	name = 'tests/selfhost-slotswap/diagnose.astra'; value = diagnostic_identity['identity']['sources'][str(ROOT/name)]
	assert sha(ROOT/name) == value
	bindings[name] = dict(sha256=value,Git_blob=git('rev-parse',head+':'+name).strip(),classification='Unchanged observer compiled against the verified pre-repair checker; used only for causal baseline observations')
	changed = git('diff','--name-only',BASE+'..'+head).splitlines(); assert all(name in bindings for name in changed if name.endswith('.astra'))
	build_intervals = [(row['monotonic_start'],row['monotonic_end']) for row in costs]
	result = dict(format='astra-slotswap21-summary/1',status='ENGINEERING_GATES_COMPLETE_PUBLICATION_PENDING',final_commit=head,final_tree=tree,base_commit=BASE,protected_files=451,donor_files=6622,historical_proof_outputs=1044,historical_attribution='Preserved original proof bytes, not freshly re-proven',predecessor_sha256=initial['predecessor_sha256'],products=products,compiled_Git_bindings=bindings,profiles=profiles,cohorts=cohorts,cold_builds=costs,cold_build_active_union_seconds=active_union(build_intervals),cold_build_overlap_seconds=sum(right-left for left,right in build_intervals)-active_union(build_intervals),cost_limitations='Actual completed durations and fixed limits; previous cold builds and changing checked prefixes are not equal-work comparative baselines.',workflow=initial['workflow'],changed_paths=changed,deferrals=['Whole CheckedIndex/Class and whole compiler admission; exact method view is qualified separately.','Fixed 256-instance exhaustion and independent original SSA 8000000-step workloads.','Utf8Message factories/exceptions/text_split; wide-u64/f32 Valgrind discrepancy.','Owning-element and effectful/indexed owner targets outside the existing qualified domain; Stage 1 and release.'],recipe_sha256=sha(__file__))
	(RUNTIME/'engineering-summary.json').write_text(json.dumps(result,indent=2)+'\n')
	light = {key:value for key,value in result.items() if key != 'profiles'}; light['profiles'] = {mode:{key:value for key,value in data.items() if key != 'programs'} for mode,data in profiles.items()}; light['status'] = 'PASS'
	(RUNTIME/'final-audit.json').write_text(json.dumps(light,indent=2)+'\n'); print(head,tree,'172 identities/profile; all source, memory, mutation and preservation gates verified')


if __name__ == '__main__':
	main()
