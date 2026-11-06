#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bind the incomplete R2 gates to actual final products, identities and costs."""
import json
from pathlib import Path
from state import ROOT, read, sha, git, load_module, preservation


def main():
	state = load_module('r2_audit_state', ROOT/'tests/selfhost-effects/r2-state.py')
	old = read(state.RUNTIME/'initial.json'); preserved = preservation()
	assert preserved == {k: old[k] for k in preserved}
	assert state.approval() == old['approval']
	assert sha(state.RUNTIME/'predecessor-report.zip') == state.REPORT
	assert not git('status', '--porcelain=v2', '--untracked-files=all')
	assert git('merge-base', state.BASE, 'HEAD').strip() == state.BASE
	assert git('config', '--show-origin', '--list') == old['config']
	assert git('stash', 'list') == old['stash']
	assert git('worktree', 'list', '--porcelain') == old['worktrees'].replace('HEAD '+state.BASE, 'HEAD '+git('rev-parse', 'HEAD').strip(), 1)
	before = dict(reversed(line.split()) for line in old['refs'].splitlines())
	after = dict(reversed(line.split()) for line in git('show-ref').splitlines()); assert before.keys() == after.keys()
	branch = git('symbolic-ref', 'HEAD').strip(); assert before[branch] == state.BASE
	assert all(after[ref] == value for ref, value in before.items() if ref != branch)
	import subprocess
	old_scope = json.loads(subprocess.check_output(['git', 'show', state.BASE+':format/scope.json'], cwd=ROOT))
	assert all(read(ROOT/'format/scope.json').get(path) == row for path, row in old_scope.items())
	assert read(state.RUNTIME/'process-deadline.json')['status'] == 'PASS'
	final = state.RUNTIME/'final'; profiles = {}; products = {}
	time_values = load_module('r2_time_parser', ROOT/'tests/selfhost-effects/r1-audit.py').time_values
	for mode in ('O0', 'O2'):
		component = state.BUILD/('compiler-v1-'+mode)/('astra-llvm-'+mode)
		identity = read(component.with_suffix('.identity.json')); assert sha(component) == identity['sha256']
		assert all(sha(p) == expected for group in ('sources', 'tools') for p, expected in identity['identity'][group].items())
		inherited = read(final/('inherited-v1-'+mode)/'result.json')['programs']
		baseline = read(state.RUNTIME/('inherited-baseline-'+mode)/'result.json')['programs']
		assert len(inherited) == len(baseline) == 202
		assert all(row['IR_equal_to_predecessor'] for row in inherited+baseline)
		for new, previous in zip(inherited, baseline):
			assert new['name'] == previous['name'] and new['sources'] == previous['sources']
			assert new['fresh_products']['raw']['sha256'] == previous['fresh_products']['raw']['sha256']
			assert all(sha(p['path']) == p['sha256'] for p in new['sources'])
			assert all(sha(p['path']) == p['sha256'] for p in new['fresh_products'].values())
		continuity = read(final/('continuity-v1-'+mode)/'result.json'); assert continuity['original_statuses'] == dict(admitted=56, rejected=12, deferred=12) and continuity['model_categories'] == 28
		memory = read(final/('memory-v1-'+mode)/'result.json'); assert len(memory['programs']) == 15
		assert read(final/('negative-v1-'+mode+'-'+mode)/'result.json')['status'] == 'PASS'
		assert read(final/('effect-boundary-v1-'+mode)/'result.json')['status'] == 'EXISTING_EFFECT_BOUNDARY_CONFIRMED'
		cohorts = read(final/('cohorts-v1-'+mode)/'result.json'); ledgers = read(final/('ledgers-v1-'+mode+'.json')); assert len(cohorts) == len(ledgers) == 4
		for name, row in ledgers.items():
			assert all(row[k] == cohorts[name][k] for k in ('files', 'nodes', 'population_sha256', 'node_identity_sha256'))
		assert all(row['conditional_facts_preserved'] and row['native_attempt']['destination_preserved'] for row in cohorts.values())
		assert read(final/('first-failure-v1-'+mode)/'result.json')['first_stop'] == ['55', '26']
		candidates = read(final/('candidates-v1-'+mode)/'result.json'); assert len(candidates['programs']) == 12 and candidates['Astra_new_native_programs'] == 0
		frontier = read(state.RUNTIME/('frontier-final-'+mode+'-v1')/'result.json'); assert len(frontier['programs']) == 4 and frontier['new_Astra_effect_ELFs'] == 0
		assert all(row['Astra_destination_preserved'] and not row['Astra_effect_ELF'] for row in frontier['programs'])
		abi = read(state.RUNTIME/('abi-controls-final-'+mode)/'result.json'); assert len(abi['programs']) == 11
		admitted = [r for r in abi['programs'] if r['declaration_shape_admitted']]; assert len(admitted) == 6
		assert all(r['model_mutations'] == 13 and r['LLVM_valid_signature_alternatives'] == 7 and not r['effect_ELF'] for r in admitted)
		cold_path = next(p for p in (state.RUNTIME/('compiler-build-v1-'+mode)).glob('build-*/ownflow-'+mode+'.json') if read(p)['exit'] == 0)
		cold = read(cold_path); cost = dict(time_values(cold_path.with_suffix('.stderr')), wall_seconds=cold['monotonic_end']-cold['monotonic_start'], monotonic_start=cold['monotonic_start'], monotonic_end=cold['monotonic_end'], receipt=str(cold_path))
		warm = read(state.RUNTIME/('warm-'+mode+'.json')); assert warm['status'] == 'EXACT_REUSE_VERIFIED' and warm['product_sha256'] == sha(component)
		cost['exact_warm_reuse'] = dict(time_values(state.RUNTIME/('warm-'+mode+'.time')), wall_seconds=warm['seconds'])
		profiles[mode] = dict(inherited_native_sources=202, raw_LLVM_identical=202, distinct_ELF_hashes=len({r['fresh_products']['native']['sha256'] for r in inherited}), source_statuses=continuity['original_statuses'], inherited_model_categories=28, inherited_returning_Valgrind_programs=15, new_C0_only_oracles=12, additional_C0_void_scalar_frontier_oracles=4, ABI_signature_sources=6, ABI_signature_deferrals=5, ABI_plan_mutation_categories=13, LLVM_valid_signature_alternatives_per_source=7, new_Astra_effect_ELFs=0, new_Astra_error_path_Valgrind_programs=0, new_cross_stage_effect_mutation_categories=0, new_error_path_LLVM_physical_alternatives=0, original_throwing_function_executed=False, first_native_boundary=frontier['first_boundary'], owner_root_deferral=dict(graph=55, symbol=2053, predicate=26, field_slot=0, local_slot=6), cold_build=cost)
		products[mode] = dict(path=str(component), sha256=sha(component), identity_sha256=sha(component.with_suffix('.identity.json')))
	unchanged = ['compiler/semantic/flow-build.astra', 'compiler/semantic/flow-model.astra', 'compiler/semantic/flow-check.astra', 'compiler/core/model.astra', 'compiler/core/lower.astra', 'compiler/core/verifier.astra', 'compiler/cfg/model.astra', 'compiler/cfg/lower.astra', 'compiler/cfg/verifier.astra', 'compiler/ssa/model.astra', 'compiler/ssa/lower.astra', 'compiler/ssa/verifier.astra', 'compiler/backend/llvm/module.astra', 'docs/selfhost-effects-25.md', 'docs/selfhost-effects-25-r1.md']
	import hashlib
	for path in unchanged:
		data = __import__('subprocess').check_output(['git', 'show', state.BASE+':'+path], cwd=ROOT)
		assert sha(ROOT/path) == hashlib.sha256(data).hexdigest()
	formatting = read(state.RUNTIME/'final-format.json'); assert formatting['changed'] == 0 and formatting['head'] == git('rev-parse', 'HEAD').strip()
	result = dict(format='astra-effects25-r2-audit/1', status='PARTIAL', base_commit=state.BASE, base_tree=state.TREE, final_commit=git('rev-parse', 'HEAD').strip(), final_tree=git('rev-parse', 'HEAD^{tree}').strip(), changed_paths=git('diff', '--name-only', state.BASE, 'HEAD').splitlines(), predecessor_report_sha256=state.REPORT, predecessor_status='PARTIAL', approval=old['approval'], protected_files=len(preserved['protected']), donor_files=len(preserved['donor']), historical_proofs_rehashed=1044, products=products, profiles=profiles, preserved_stage_hashes={p:sha(ROOT/p) for p in unchanged}, gates={
		'G0':'PASS: exact ZIP/Git, R1 report, original native approval/proposal and protections authenticated',
		'G1':'PASS: 202-source native baseline/profile and four immutable cohorts/profile with obligations and separate predicate 26',
		'G2':'NOT_MET: no new Astra recoverable-error ELF; four void/scalar frontier attempts/profile fail upstream',
		'G3':'PARTIAL: scalar/void E25-A-v1 signature planning, real LLVM type construction and physical verifier; source execution, root/error layout authority and other shapes remain unimplemented',
		'G4':'NOT_MET: Flow error owner, reservation failure and checked-call control are unimplemented',
		'G5':'NOT_MET: no Core/CFG/SSA effect operations, dominance/phis or error body lowering; physical signature verifier is not body proof',
		'G6':'NOT_MET: zero of twelve new Astra effect programs/profile',
		'G7':'PARTIAL: fifteen inherited normal-return Valgrind programs/profile pass; C0 errors are separate; zero new Astra error-path checks',
		'G8':'NOT_MET: thirteen ABI plan mutations and seven LLVM-valid signature alternatives/source; zero cross-stage/error-body effect mutation categories',
		'G9':'PARTIAL: exact complete ledgers/cohorts and original native attempts; predicate 26 independently deferred; no original throwing function executes',
		'G10':'PASS: all 202 current inherited source identities/profile emit old raw LLVM and execute; statuses/proofs/protected/donor retained',
		'G11':'PASS: C0/public ABI/LLVM23/limits/history preserved; isolated outputs, bounded process groups, measured cold/warm costs',
		'G12':'PENDING: unchanged installed publisher and independent archive verification'
	}, remaining_boundary='First physical frontier is incomplete Flow: root Class TYPE_POLICY 7, constructors and throws UNSUPPORTED_EFFECT 6, unsupported throw/try syntax. Existing Core returns 3 before any candidate LLVM exists. Next work must implement independently owned Error layout/allocation/destruction and checked-call success/error control in Flow, Core, CFG, SSA and LLVM; declaration signatures alone cannot enable emission.', deferrals=['CheckedIndex.add_signature predicate 26 under unchanged Class ownership rules', 'Record/buffer/heap Class success carriers, static receivers and closed generic effect calls', 'Typed dynamic catches, original rethrow/replacement, reservations and complete cleanup', 'At least 12 new Astra effect ELFs/profile, 8 real error paths, original throwing source execution', '20 cross-stage effect mutation categories and 6 LLVM-valid error-body alternatives/profile', '2 historical 8000000-step SSA examples; wide-u64/f32 Valgrind discrepancy; complete Utf8Message factory; whole-compiler admission and Stage 1'], costs='Cold runs and other intervals may overlap: do not sum wall times or claim a matched-workload speedup. Exact warm reuse is identity reuse, not compilation. Failed routing, semantic checks and probe attempts remain preserved with their own receipts.', task_storage={key:sum(p.stat().st_size for p in directory.rglob('*') if p.is_file()) for key,directory in [('build_bytes',state.BUILD),('runtime_bytes_before_packaging',state.RUNTIME)]})
	(state.RUNTIME/'final-audit.json').write_text(json.dumps(result, indent=2)+'\n'); print('PARTIAL: all gates bound to final identities; zero new Astra effect ELFs')


if __name__ == '__main__':
	main()
