#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Source-bound R1 gate accounting; an absent native effect is always PARTIAL."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
from state import ROOT, read, sha, git, preservation, load_module

BASE_PATH = ROOT.parent/'codex/work/astra'
RUNTIME = BASE_PATH/'runtime/effects25-r1'
BUILD = BASE_PATH/'build/effects25-r1'
state = load_module('r1_audit_state', ROOT/'tests/selfhost-effects/r1-state.py')


def time_values(path):
	text = path.read_text()
	def number(label):
		return float(re.search(re.escape(label)+r': ([0-9.]+)', text).group(1))
	return dict(user_seconds=number('User time (seconds)'), system_seconds=number('System time (seconds)'), peak_RSS_KiB=int(number('Maximum resident set size (kbytes)')))


def main():
	assert not git('status', '--porcelain=v2', '--untracked-files=all'), 'Commit only reviewed task-owned paths first'
	assert subprocess.run(['git', 'merge-base', '--is-ancestor', state.BASE, 'HEAD'], cwd=ROOT).returncode == 0
	protected = preservation(); initial = read(RUNTIME/'initial.json')
	assert sha(RUNTIME/'predecessor-report.zip') == state.REPORT
	assert initial['approval'] == state.approval()
	assert read(RUNTIME/'submission-history.json') == state.submission_history()
	assert read(RUNTIME/'predecessor-source-audit.json')['status'] == 'PASS'
	assert read(RUNTIME/'process-deadline.json')['status'] == 'PASS'
	assert len(read(RUNTIME/'baseline.json')) == 8
	assert git('config', '--show-origin', '--list') == initial['config']
	assert git('stash', 'list') == initial['stash']
	assert git('worktree', 'list', '--porcelain') == initial['worktrees'].replace('HEAD '+state.BASE, 'HEAD '+git('rev-parse', 'HEAD').strip())
	old_refs = dict(reversed(line.split()) for line in initial['refs'].splitlines())
	new_refs = dict(reversed(line.split()) for line in git('show-ref').splitlines())
	assert old_refs.keys() == new_refs.keys()
	for ref, value in old_refs.items():
		if ref != 'refs/heads/main': assert new_refs[ref] == value
	old_scope = json.loads(subprocess.check_output(['git', 'show', state.BASE+':format/scope.json'], cwd=ROOT))
	scope = read(ROOT/'format/scope.json'); assert all(scope.get(path) == row for path, row in old_scope.items())
	for path, expected in initial['workflow'].items(): assert sha(path) == expected
	unchanged = ['compiler/semantic/flow-check.astra', 'compiler/semantic/flow-owner-exchange.astra', 'compiler/semantic/generic.astra', 'compiler/core/verifier.astra', 'compiler/cfg/verifier.astra', 'compiler/ssa/verifier.astra', 'compiler/ssa/model.astra', 'compiler/backend/llvm/module.astra', 'docs/selfhost-effects-25.md', 'docs/selfhost-effects-25-abi-proposal.md', 'codex-project.json', 'AGENTS.md']
	for path in unchanged:
		original = subprocess.check_output(['git', 'show', state.BASE+':'+path], cwd=ROOT)
		assert hashlib.sha256(original).hexdigest() == sha(ROOT/path)
	profiles = {}; products = {}
	for mode in ('O0', 'O2'):
		component = BUILD/('compiler-v1-'+mode)/('astra-llvm-'+mode)
		identity = read(component.with_suffix('.identity.json')); assert sha(component) == identity['sha256']
		assert all(sha(path) == h for group in ('sources', 'tools') for path, h in identity['identity'][group].items())
		inherited = read(RUNTIME/('inherited-v1-'+mode)/'result.json'); assert inherited['status'] == 'PASS' and len(inherited['programs']) == 202
		assert all(row['IR_equal_to_predecessor'] for row in inherited['programs'])
		for row in inherited['programs']:
			assert all(sha(p['path']) == p['sha256'] for p in row['sources'])
			assert all(sha(p['path']) == p['sha256'] for p in row['fresh_products'].values())
		continuity = read(RUNTIME/('continuity-v1-'+mode)/'result.json')
		assert continuity['original_statuses'] == dict(admitted=56, rejected=12, deferred=12) and continuity['model_categories'] == 28
		memory = read(RUNTIME/('memory-v1-'+mode)/'result.json'); assert len(memory['programs']) == 15
		negative = read(RUNTIME/('negative-inherited-v1-'+mode+'-'+mode)/'result.json'); assert negative['status'] == 'PASS' and len(negative['cases']) == 10
		assert read(RUNTIME/('effect-boundary-inherited-v1-'+mode)/'result.json')['status'] == 'EXISTING_EFFECT_BOUNDARY_CONFIRMED'
		controls = read(RUNTIME/('typecore-controls-final-v2-'+mode)/'result.json'); assert len(controls['cases']) == 21 and controls['model_mutations'] == 12
		cohorts = read(RUNTIME/('cohorts-v1-'+mode)/'result.json'); assert len(cohorts) == 4
		assert all(row['conditional_facts_preserved'] and row['native_attempt']['destination_preserved'] for row in cohorts.values())
		assert read(RUNTIME/('first-failure-v1-'+mode)/'result.json')['first_stop'] == ['55', '26']
		captures = []
		with (RUNTIME/('cohorts-v1-'+mode)/'original.stdout').open() as stream:
			for line in stream:
				if not line.startswith('E 55 '): continue
				values = line.split()
				if values[3] != '24': continue
				path = Path(bytes.fromhex(values[9]).decode()); begin, end = map(int, values[10:12])
				captures.append(dict(slot=int(values[4]), source=str(path), source_sha256=sha(path), start=begin, end=end, text=path.read_bytes()[begin:end].decode()))
		assert {(row['text'], row['slot']) for row in captures} == {('this.signatures', 0), ('grown', 6)}
		oracles = read(RUNTIME/('candidates-v1-'+mode)/'result.json'); assert len(oracles['programs']) == 12 and oracles['Astra_new_native_programs'] == 0
		assert all(not row['profiles'][mode]['Astra_native_qualified'] for row in oracles['programs'])
		cold_receipt = next(p for p in sorted((RUNTIME/('compiler-build-v1-'+mode)).glob('build-*/ownflow-'+mode+'.json'), reverse=True) if read(p)['exit'] == 0)
		cold = read(cold_receipt)
		cost = dict(time_values(cold_receipt.with_suffix('.stderr')), wall_seconds=cold['monotonic_end']-cold['monotonic_start'], monotonic_start=cold['monotonic_start'], monotonic_end=cold['monotonic_end'], receipt=str(cold_receipt))
		warm = read(RUNTIME/('warm-'+mode+'.json')); assert warm['status'] == 'EXACT_REUSE_VERIFIED' and warm['product_sha256'] == sha(component)
		cost['exact_warm_reuse'] = dict(time_values(RUNTIME/('warm-'+mode+'.time')), wall_seconds=warm['seconds'], receipt=str(RUNTIME/('warm-'+mode+'.json')))
		profiles[mode] = dict(inherited_native_sources=202, raw_LLVM_identical=202, distinct_native_ELF_sha256=len({row['fresh_products']['native']['sha256'] for row in inherited['programs']}), source_statuses=continuity['original_statuses'], inherited_model_categories=28, Typecore_source_controls=21, new_Typecore_model_mutations=12, new_effect_Flow_Core_CFG_SSA_mutation_categories=0, new_effect_LLVM_valid_physical_alternatives=0, new_C0_oracles=12, new_Astra_effect_programs=0, new_Astra_error_return_memory_programs=0, inherited_normal_return_memory_programs=15, cold_build=cost)
		products[mode] = dict(path=str(component), sha256=sha(component), identity_sha256=sha(component.with_suffix('.identity.json')))
		profiles[mode]['original_owner_capture'] = dict(graph=55, symbol=2053, predicate=26, status='DEFERRED', sides=captures)
	storage = dict(build_bytes=sum(p.stat().st_size for p in BUILD.rglob('*') if p.is_file()), runtime_bytes_before_packaging=sum(p.stat().st_size for p in RUNTIME.rglob('*') if p.is_file()))
	result = dict(format='astra-effects25-r1-audit/1', status='PARTIAL', effect_domain='PARTIAL: source effect checking; approved transport unimplemented', base_commit=state.BASE, base_tree=state.TREE, final_commit=git('rev-parse', 'HEAD').strip(), final_tree=git('rev-parse', 'HEAD^{tree}').strip(), changed_paths=git('diff', '--name-only', state.BASE, 'HEAD').splitlines(), products=products, profiles=profiles, protected_files=len(protected['protected']), donor_files=len(protected['donor']), historical_proofs_rehashed=1044, approval=initial['approval'], unchanged_boundaries={path:sha(ROOT/path) for path in unchanged}, gates={
		'G0':'PASS: exact intake/history/protected work and original native E25-A-v1 approval authenticated',
		'G1':'PASS: eight predecessor consumers, two 202-source native baselines and final conditional source chains',
		'G2':'NOT_MET: no Astra private checked-call transport; fresh C0/GCC/Clang layout design evidence only',
		'G3':'PARTIAL: nominal bounds, argument types, typed catch order/open coverage and lexical rethrow source checking; dynamic owner/identity and complete effect admission remain unqualified',
		'G4':'NOT_MET: no Flow error owner/success/error cleanup implementation',
		'G5':'NOT_MET: no Core/CFG/SSA/LLVM effect transport or independent error-path verification',
		'G6':'NOT_MET: zero new qualified Astra effect executables/profile; twelve C0 oracles/profile are separate',
		'G7':'PARTIAL: fifteen inherited normal-return Valgrind programs/profile; zero new Astra recoverable-error memory pairs',
		'G8':'NOT_MET: twelve Typecore model mutations/profile, no cross-stage effect mutants or candidate LLVM-valid physical alternatives',
		'G9':'PARTIAL: four original cohorts rechecked/profile, original complete native emission attempted/refused, owner capture predicate 26 remains independently deferred; no original throwing function ran',
		'G10':'PASS: 202 current inherited native sources/profile, 80 statuses, 1044 historical hashes and protected verifier/layout boundaries preserved',
		'G11':'PASS: unchanged source ceilings, isolated artifacts, actual per-command cost/overlap attribution and bounded process-group runner',
		'G12':'PENDING installed publication and independent ZIP verification'
	}, remaining_deferrals=['E25-A-v1 private ABI, Error layout/descriptors/getters/dynamic destruction, Flow error control and ownership, Core/CFG/SSA/LLVM effect transport, exactly-once cleanup', '12+ new Astra emitters/profile with 8+ real error paths and 4+ success/cleanup cases', '20+ independent cross-stage effect mutation categories and 6+ LLVM-valid physical alternatives/profile', 'New Astra normal/error memory and original throwing-function execution', 'CheckedIndex.add_signature original graph 55/symbol 2053/predicate 26, field/root slot 0 versus grown slot 6', '2 historical SSA 8000000-step cases; wide-u64/f32 Valgrind discrepancy; complete Utf8Message factory', 'Whole compiler native admission, self-compilation and Stage 1'], costs='Cold profiles overlap. Failed/exploratory attempts retain separate receipts. No sum of overlapping wall intervals or matched-workload speedup is claimed. The source-check exploration lacking a process-group runner was terminated with its exact process receipt; subsequent task commands use bounded_run.')
	result['task_storage'] = storage
	formatting = read(RUNTIME/'final-format.json'); assert formatting['changed'] == 0 and formatting['head'] == result['final_commit']
	(RUNTIME/'final-audit.json').write_text(json.dumps(result, indent=2)+'\n')
	print('PARTIAL: exact final identities and gates recorded; zero Astra effect native programs', flush=True)


if __name__ == '__main__':
	main()
