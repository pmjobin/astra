#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bind final qualified facts and preservation to the exact Git/source identities."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, PRIOR, C0, BASE, TREE, COHORTS, read, sha, git


def metrics(path):
	text = path.read_text(); result = {}
	for key,label in [('user_CPU_seconds','User time (seconds)'),('system_CPU_seconds','System time (seconds)'),('peak_RSS_KiB','Maximum resident set size (kbytes)')]:
		match = re.search(re.escape(label)+r':\s*([0-9.]+)',text); result[key] = float(match[1]) if match else None
	return result


def main():
	p = argparse.ArgumentParser(); p.add_argument('--O0',type=Path,required=True); p.add_argument('--O2',type=Path,required=True); p.add_argument('--qualification',default='v3'); a = p.parse_args()
	assert git('status','--porcelain=v1','--untracked-files=all') == ''
	head = git('rev-parse','HEAD').strip(); tree = git('rev-parse','HEAD^{tree}').strip(); initial = read(RUNTIME/'initial.json')
	assert initial['base'] == BASE and initial['tree'] == TREE
	assert subprocess.run(['git','merge-base','--is-ancestor',BASE,head],cwd=ROOT).returncode == 0
	changed = git('diff','--name-only',BASE+'..'+head).splitlines()
	assert all(path.startswith('tests/selfhost-callplace/') or path in ('compiler/ssa/dominance.astra','compiler/semantic/index.astra','compiler/semantic/generic.astra','compiler/semantic/generic-methods.astra','compiler/semantic/generic-check.astra','format/scope.json','docs/selfhost-callplace-23.md') for path in changed)
	spec = importlib.util.spec_from_file_location('preservation',ROOT/'tests/selfhost-genresource/state.py'); previous = importlib.util.module_from_spec(spec); spec.loader.exec_module(previous)
	assert all(value == initial[key] for key,value in previous.preservation().items())
	for path in initial['protected']:
		mode = git('ls-tree',BASE,'--',path).split()[0]; assert (ROOT/path).stat().st_mode & 0o777 == (0o755 if mode == '100755' else 0o644)
	assert sha(RUNTIME/'predecessor-report.zip') == initial['predecessor_sha256'] == '33098abb7273845a70279ea71e33ff5285044433a410f130f6fa243a3d56cfc5'
	assert git('config','--show-origin','--list') == initial['config'] and git('stash','list') == initial['stash']
	refs = {row.split()[1]:row.split()[0] for row in git('show-ref').splitlines()}; oldrefs = {row.split()[1]:row.split()[0] for row in initial['refs'].splitlines()}
	assert refs.keys() == oldrefs.keys() and all(refs[name] == value for name,value in oldrefs.items() if name != 'refs/heads/main')
	assert git('worktree','list','--porcelain').replace('HEAD '+head,'HEAD '+BASE) == initial['worktrees']
	assert git('ls-files','--others','--ignored','--exclude-standard') == initial['ignored']
	for path,value in initial['hooks'].items(): assert sha(path) == value['sha256'] and oct(Path(path).stat().st_mode & 0o777) == value['mode']
	for path,value in initial['workflow'].items(): assert sha(path) == value
	proofs = read(RUNTIME.parent/'indexpath18/historical-proof-outputs.json'); assert len(proofs['outputs']) == proofs['count'] == 1044
	assert all(sha(path) == row['sha256'] for path,row in proofs['outputs'].items())
	for path in ('AGENTS.md','CODING_STYLE.md','codex-project.json','docs/selfhost-membercall-22-checkpoint.md'):
		assert (ROOT/path).read_bytes() == subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT)
	old_ssa = subprocess.check_output(['git','show',BASE+':compiler/ssa/dominance.astra'],cwd=ROOT)
	new_ssa = (ROOT/'compiler/ssa/dominance.astra').read_bytes()
	boundary = b'// Independent, bounded entry worklist'
	assert old_ssa.split(boundary,1)[1] == new_ssa.split(boundary,1)[1]
	for path in ('compiler/ssa/model.astra','compiler/ssa/verifier.astra','compiler/semantic/model.astra'):
		assert (ROOT/path).read_bytes() == subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT)
	old_scope = json.loads(subprocess.check_output(['git','show',BASE+':format/scope.json'],cwd=ROOT)); scope = read(ROOT/'format/scope.json'); assert all(scope.get(path) == value for path,value in old_scope.items())
	assert sha(C0) == 'e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b' and subprocess.check_output(['llvm-config','--version']).strip() == b'23.1.4'
	profiles = {}; products = {}
	for mode in ('O0','O2'):
		component = getattr(a,mode); identity = read(component.with_suffix('.identity.json')); assert sha(component) == identity['sha256']
		assert all(sha(path) == value for group in ('sources','tools') for path,value in identity['identity'][group].items())
		assert ['-'+mode] == [word for word in identity['identity']['argv'] if word in ('-O0','-O2')]
		products[mode] = dict(path=str(component),sha256=sha(component),identity_sha256=sha(component.with_suffix('.identity.json')))
		inherited = read(RUNTIME/('inherited-v2-'+mode)/'result.json'); assert inherited['status'] == 'PASS' and len(inherited['programs']) == 172
		qualified = read(RUNTIME/('qualified-'+a.qualification+'-'+mode)/'result.json'); assert qualified['status'] == 'PASS' and len(qualified['programs']) == 15
		assert inherited['component_sha256'] == qualified['component_sha256'] == sha(component)
		rows = inherited['programs']+qualified['programs']; assert len({tuple(s['sha256'] for s in row['sources']) for row in rows}) == 187
		for row in rows:
			assert all(sha(s['path']) == s['sha256'] for s in row['sources'])
			assert all(sha(p['path']) == p['sha256'] for p in row.get('fresh_products',row.get('products')).values())
		models = read(RUNTIME/('models-v2-'+mode)/'result.json'); physical = read(RUNTIME/('physical-v2-'+mode)/'result.json'); negative = read(RUNTIME/('negative-v2-'+mode)/'result.json'); failure = read(RUNTIME/('failure-v2-'+mode)/'result.json')
		assert all(result['status'] == 'PASS' for result in (models,physical,negative,failure))
		assert models['component_sha256'] == negative['component_sha256'] == failure['component_sha256'] == sha(component)
		assert len(models['mutations']) == 28 and len(physical['mutations']) == 7 and all(row['LLVM_valid'] and row['independently_rejected'] for row in physical['mutations'])
		assert read(RUNTIME/('lifetime-'+mode)/'result.json')['status'] == 'PASS'
		assert len(negative['cases']) == 10 and all(row['baseline_complete'] and set(row['memory']) == {'native','C0'} for row in qualified['programs'])
		profiles[mode] = dict(inherited_source_programs=172,new_native_source_programs=15,total=187,model_mutations=28,LLVM_valid_physical_alternatives=7,source_negatives=10,new_normal_return_native_memory_qualifications=15,new_C0_memory_qualifications=15,previous_IR_identical=sum(row['IR_equal_to_predecessor'] for row in inherited['programs']),failure_order=failure['results'])
	continuity = read(RUNTIME/'continuity/result.json'); assert continuity['status'] == 'INHERITED_CONTROLS_PASS'
	for mode in ('O0','O2'): assert continuity['results'][mode]['source-status'] == {'0':56,'4':12,'3':12}
	cohorts = read(RUNTIME/'cohorts-v2.json'); assert set(cohorts) == set(COHORTS)
	for name,row in cohorts.items():
		assert row['new_checked_facts'] > 0
		assert row['component_sha256'] == sha(a.O0) and row['independent_consumer']['codes'] == ['CHECKED_CONSUMER 1 7'] and row['independent_consumer']['exit'] == 2
		assert row['population_sha256'] == initial['cohorts'][name]['population_sha256'] and row['node_identity_sha256'] == initial['cohorts'][name]['node_identity_sha256']
		new = read(RUNTIME/('ledger-v2-'+name)/'ledger.json'); old_node = read(RUNTIME.parent/'membercall22/facts-v2/result.json')['cohorts'][name]['call_node']['node']; fact = next(r for r in new['nodes'] if r['node'] == old_node)
		assert fact['type'] != 0 and fact['deferred'] in (0,19),(name,fact)
		row['old_call_lexical_type_available'] = fact
		row['old_call_contract_obligation'] = 'BORROW/OWNERSHIP_PROOF_PENDING' if fact['deferred'] == 19 else 'NONE'
		row['whole_Flow_status'] = new['raw_flow'][:2]
	witness = read(RUNTIME/'source-witness-v3/result.json'); assert witness['status'] == 'PASS'
	assert read(RUNTIME/'inference-operands-baseline/result.json')['status'] == 'ACTUAL_OPERANDS_OBSERVED'
	for version,component in (('v3',a.O0),('v3O2',a.O2)):
		effect = read(RUNTIME/('effect-boundary-'+version)/'result.json'); assert effect['status'] == 'EXISTING_EFFECT_BOUNDARY_CONFIRMED' and effect['component_sha256'] == sha(component)
	costs = []
	for path in sorted(RUNTIME.rglob('ownflow-*.json')):
		if path.name.endswith(('input-identity.json','exact-reuse.json')) or 'checkpoint' in path.parts: continue
		row = read(path)
		if not isinstance(row,dict) or 'exit' not in row: continue
		left = row.get('monotonic_start',row.get('start')); right = row.get('monotonic_end',row.get('end')); stderr = path.with_suffix('.stderr')
		costs.append(dict(path=str(path),exit=row['exit'],wall_seconds=right-left if left is not None and right is not None else None,**(metrics(stderr) if stderr.exists() else {})))
	result = dict(format='astra-callplace23-qualification/1',status='PASS',base_commit=BASE,base_tree=TREE,final_commit=head,final_tree=tree,changed_paths=changed,products=products,profiles=profiles,cohorts=cohorts,original_throwing_callers=witness['cohorts'],original_caller_native_status='DEFERRED: throws Error; separately authorized recoverable effect/ABI work remains required',historical_MEMBERCALL22_status='PARTIAL',protected_files=451,donor_files=6622,historical_proof_outputs=1044,historical_proof_attribution='Byte identities preserved; no fresh requalification claimed',continuity=continuity['results'],cold_build_attempts=costs,gates={f'G{i}':'PASS' for i in range(11)},limitations=['Scoped nonthrowing member-call capability; no complete compiler, original throwing caller execution or Stage 1 qualification.','Empty generic Class owned-child constructor and direct effectful record-result indexed-store forms remain outside the existing bounded storage profile; failed draft inputs and exact deferrals are retained.','Cold build attempts include failed and intentionally cancelled products; these are costs, not qualified executions. Parent and child measurements overlap and are not summed as an exclusive benchmark.'],recipe_sha256=sha(__file__),audit_monotonic=time.monotonic())
	(RUNTIME/'final-audit.json').write_text(json.dumps(result,indent=2)+'\n'); print(head,tree,'PASS: 187 source identities/profile, 28 model and 7 LLVM-valid physical alternatives/profile; original throwing callers DEFERRED')


if __name__ == '__main__':
	main()
