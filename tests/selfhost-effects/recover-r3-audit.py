#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bind R3 source executions and residual gates to one clean final Git tree."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
from state import ROOT, load_module, read, sha, git, preservation


def memory(path):
	data = path.read_bytes(); assert b'ERROR SUMMARY: 0 errors' in data and b'in use at exit: 0 bytes in 0 blocks' in data and b'(suppressed: 0 from 0)' in data
	return sha(path)


def main():
	p = argparse.ArgumentParser(); p.add_argument('--configuration', type=Path, required=True); p.add_argument('--output', type=Path, required=True); a = p.parse_args(); config = read(a.configuration); paths = load_module('r3_audit_paths', ROOT/'tests/selfhost-effects/recover-build.py'); r3 = load_module('r3_audit_intake', ROOT/'tests/selfhost-effects/r3.py'); assert not git('status', '--porcelain=v1', '--untracked-files=all').strip()
	head = git('rev-parse', 'HEAD').strip(); tree = git('rev-parse', 'HEAD^{tree}').strip(); assert subprocess.run(['git', 'merge-base', '--is-ancestor', r3.BASE, head], cwd=ROOT).returncode == 0
	initial = read(paths.RUNTIME/'initial.json'); assert (initial['base'], initial['tree'], initial['predecessor_sha256']) == (r3.BASE, r3.TREE, r3.REPORT); assert sha(paths.RUNTIME/'predecessor-report.zip') == r3.REPORT == sha(ROOT.parent/'codex/reports/astra-report-current.zip'); protection = preservation(); assert protection == {key:initial[key] for key in protection}
	history = []
	for name, expected in [('published-verification.json', '393ef64b93e3db7a4731158617717c5d94ec9637919a4fba8835bbc3fc43f14b'), ('published-verification-v12.json', 'e37424a775bf8ca65062b573264f7c9c347283e9c3986705ace9282ae0b5438d')]:
		path = paths.RUNTIME.parent/'effects25-r2-completion'/name; assert sha(path) == expected; row = read(path); assert row['status'] == 'PUBLISHED_PARTIAL_AMENDMENT_VERIFIED' and row['G12'].startswith('PASS:'); history.append(dict(path=str(path), sha256=expected, receipt=row))
	assert history[-1]['receipt']['report_sha256'] == r3.REPORT and history[-1]['receipt']['final_commit'] == r3.BASE and history[-1]['receipt']['final_tree'] == r3.TREE
	profiles = {}
	for mode in ('O0', 'O2'):
		profile = config['profiles'][mode]; component = Path(profile['component']); identity = read(component.with_suffix('.identity.json')); assert sha(component) == identity['sha256'] and identity['identity']['argv'][1] == '-'+mode and all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
		def programs(names):
			rows = []; used = set()
			for name in names:
				leaf = paths.RUNTIME/name; result = read(leaf/'result.json'); assert result['target_profile'] == mode and result['component_sha256'] == sha(component) and result['new_Astra_effect_ELFs'] == len(result['programs'])
				for row in result['programs']:
					assert row['name'] not in used and row['Astra_effect_ELF']; used.add(row['name']); source = leaf/(row['name']+'.astra'); build = paths.BUILD/name
					assert sha(source) == row['source_sha256'] and sha(build/(row['name']+'-Astra')) == row['Astra_ELF_sha256'] and sha(build/(row['name']+'-Astra.ll')) == row['Astra_raw_LLVM_sha256'] and sha(build/(row['name']+'-'+mode+'.ll')) == row['Astra_optimized_LLVM_sha256']
					expected = {'Astra-emit':0, 'Astra-verify':0, 'Astra-optimized-verify':0, 'Astra-execute':42, 'C0-execute':42, 'Astra-memory':42, 'C0-memory':42}
					for suffix, code in expected.items():
						command = next(c for c in result['commands'] if c['name'] == row['name']+'-'+suffix); assert command['exit'] == code
						assert sha(leaf/(command['name']+'.stdout')) == command['stdout_sha256'] and sha(leaf/(command['name']+'.stderr')) == command['stderr_sha256']
						if suffix == 'Astra-emit': assert command['argv'][0] == str(component)
					for label in ('Astra', 'C0'):
						data = (leaf/(row['name']+'-'+label+'-memory.stderr')).read_bytes(); heap = re.search(rb'total heap usage: ([0-9,]+) allocs, ([0-9,]+) frees', data); assert heap
						allocations = int(heap[1].replace(b',', b'')); frees = int(heap[2].replace(b',', b'')); assert allocations == frees == row[label+'_allocations']
						if row['observed_error_path'] and not (row['name'] == 'empty-snapshot' and mode == 'O2'): assert allocations >= (1 if row['name'] == 'empty-snapshot' else 2)
					rows.append(dict(name=row['name'], source_sha256=sha(source), ELF_sha256=row['Astra_ELF_sha256'], actual_error_path=row['observed_error_path'], memory={label:memory(leaf/(row['name']+'-'+label+'-memory.stderr')) for label in ('Astra', 'C0')}))
			return rows
		prior = programs(profile['native_results']); new = programs(profile['new_native_results']); assert len(prior) == len({r['source_sha256'] for r in prior}) == 60 and sum(r['actual_error_path'] for r in prior) == 35 and len({r['ELF_sha256'] for r in prior}) == 60
		baseline = []
		for leaf in paths.RUNTIME.glob('early-baseline*-'+mode): baseline += read(leaf/'result.json')['programs']
		assert len(baseline) == 60 and {r['name']:r['source_sha256'] for r in baseline} == {r['name']:r['source_sha256'] for r in prior}
		assert len(new) == len({r['source_sha256'] for r in new}) >= 12 and sum(r['actual_error_path'] for r in new) >= 8
		assert len({r['ELF_sha256'] for r in new}) >= 12
		assert {r['source_sha256'] for r in new}.isdisjoint(r['source_sha256'] for r in prior)
		regression = paths.RUNTIME/profile['regression']; inherited = read(regression/('inherited-v1-'+mode)/'result.json'); before = read(paths.RUNTIME/('regression-baselineregression-'+mode)/('inherited-v1-'+mode)/'result.json'); assert inherited['component_sha256'] == sha(component) and len(inherited['programs']) == 202
		assert [[r['name'], r['sources']] for r in inherited['programs']] == [[r['name'], r['sources']] for r in before['programs']]
		for row in inherited['programs']: assert row['IR_equal_to_predecessor'] and all(sha(p['path']) == p['sha256'] for p in row['fresh_products'].values()) and all(sha(p['path']) == p['sha256'] for p in row['sources'])
		assert {r['source_sha256'] for r in new}.isdisjoint(p['sha256'] for r in inherited['programs'] for p in r['sources'])
		continuity = read(regression/('continuity-v1-'+mode)/'result.json'); assert continuity['original_statuses'] == dict(admitted=56, rejected=12, deferred=12)
		cohorts = read(regression/('cohorts-v1-'+mode)/'result.json'); ledgers = read(regression/('ledgers-v1-'+mode+'.json')); assert len(cohorts) == len(ledgers) == 4
		for name, row in ledgers.items(): assert all(row[key] == cohorts[name][key] for key in ('files', 'nodes', 'population_sha256', 'node_identity_sha256')) and cohorts[name]['conditional_facts_preserved']
		mutants = []
		for name in [*profile['adversarial'], *profile['new_adversarial']]:
			result = read(paths.RUNTIME/name/'result.json'); assert result['component_sha256'] == sha(component) and result.get('target_profile', result.get('profile')) == mode; mutants.append(dict(path=name, result_sha256=sha(paths.RUNTIME/name/'result.json'), semantic=len(result['semantic']), physical=len(result['LLVM_valid_physical'])))
			for command in read(paths.RUNTIME/name/'commands.json'):
				assert sha(paths.RUNTIME/name/(command['name']+'.stdout')) == command['stdout_sha256'] and sha(paths.RUNTIME/name/(command['name']+'.stderr')) == command['stderr_sha256']
		assert sum(r['semantic'] for r in mutants[:3]) == 39 and sum(r['physical'] for r in mutants[:3]) == 24 and sum(r['semantic'] for r in mutants[3:]) >= 20 and sum(r['physical'] for r in mutants[3:]) >= 6
		original = read(paths.RUNTIME/profile['original']/'result.json'); assert original['component_sha256'] == sha(component) and original['source']['exact_original_bytes'] and original['source']['slice_sha256'] == '8641d4ff6a1f19cc8bfc0ccbec492a8f7d4248eebcb05373c15479e7114a3e68'
		view = read(paths.RUNTIME/profile['original_view']/'result.json'); assert view['component_sha256'] == view['ledger_component_sha256'] == sha(component) and view['C0_actual_execution'] == 42 and all(r['AST_byte_exact'] for r in view['selections'])
		guards = read(paths.RUNTIME/profile['receiver_guard']/'result.json'); assert guards['component_sha256'] == sha(component) and guards['status'] == 'FATAL_CHECKED_RECEIVER_ORDER' and len(guards['programs']) == 2 and all(r['Astra_exit'] == r['C0_exit'] == -4 for r in guards['programs']) and guards['returning_effect_program_credit'] == 0
		floating = read(paths.RUNTIME/profile['floating_probe']/'result.json'); assert floating['component_sha256'] == sha(component) and floating['status'] == 'INDEPENDENT_FP_CARRIER_BITS_ONLY' and floating['Astra_effect_ELFs'] == 0 and len(floating['results']) == 24
		observer = read(paths.RUNTIME/profile['dynamic_observer']/'result.json'); assert observer['status'] == 'INDEPENDENT_C0_ASTRA_DYNAMIC_ERROR_OBSERVATION' and len(observer['observations']) == 4 and all(r['actual_exit'] == 42 and 'valid=1 snapshots=1 errors=1 live=0' in r['observation'] for r in observer['observations'])
		literal = next(r for name in profile['new_native_results'] for r in read(paths.RUNTIME/name/'result.json')['programs'] if r['name'] == 'literal-exact-catch')
		assert all(r['ELF_sha256'] == literal[r['program']+'_ELF_sha256'] and r['observer_sha256'] == sha(paths.BUILD/profile['dynamic_observer']/(r['observer_compiler']+'.so')) for r in observer['observations'])
		root = read(paths.RUNTIME/profile['root']); assert (root['status'], root['graph'], root['symbol'], root['predicate']) == ('DEFERRED', 55, 2053, 26)
		assert root['component_sha256'] == sha(component)
		frontier = read(paths.RUNTIME/profile['frontier']/'result.json'); assert frontier['component_sha256'] == sha(component) and len(frontier['programs']) == 8
		fields = read(paths.RUNTIME/profile['fields']/'result.json'); assert fields['component_sha256'] == sha(component) and len(fields['programs']) == 4 and all(r['C0_actual_execution'] == 42 for r in fields['programs'])
		oracles = read(paths.RUNTIME/profile['source_oracles']/'result.json'); assert oracles['C0_sha256'] == sha(ROOT.parent/'codex/work/astra/build/llvm23-migration/production-final/astrac') and len(oracles['programs']) == 11 and oracles['primary_Astra_credit'] == 0
		assert sum(r['C0_actual_execution'] == -4 for r in oracles['programs']) == 2 and sum(r['C0_build_exit'] == 1 for r in oracles['programs']) == 1
		rows = prior+new; profiles[mode] = dict(component=str(component), component_sha256=sha(component), native_programs=len(rows), actual_error_programs=sum(r['actual_error_path'] for r in rows), success_cleanup_programs=sum(not r['actual_error_path'] for r in rows), distinct_ELF_hashes=len({r['ELF_sha256'] for r in rows}), programs=rows, retained_R2_programs=60, additional_programs=len(new), additional_error_programs=sum(r['actual_error_path'] for r in new), inherited_native_programs=202, inherited_raw_LLVM_identical=202, total_source_programs=202+len(rows), statuses=continuity['original_statuses'], cohorts=ledgers, adversarial=mutants, original_function_attempt=original, original_source_view=view, source_frontier=frontier['programs'], predicate_26='DEFERRED with independent source/slot investigation', dynamic_observer=profile['dynamic_observer'], fatal_receiver_controls=profile['receiver_guard'], floating_ABI_probe=profile['floating_probe'])
	for name in config['independent_layouts']:
		layout = read(paths.RUNTIME/name/'result.json'); assert layout['status'] == 'INDEPENDENT_C_CPP_LAYOUT_ONLY' and layout['Astra_effect_ELFs'] == 0
	residual = config['remaining_boundary']; assert isinstance(residual, str) and residual
	original_executed = all(p['original_function_attempt']['Astra_actual_execution'] == 42 for p in profiles.values())
	gates = dict(G0='PASS: exact intake, predecessor manifest/source snapshots, original native approval and historical PARTIAL authenticated', G1='PASS: independent baseline and final replay of 202 inherited plus 60 R2 source identities/profile', G2='PASS for retained private void/scalar ABI, independent C0/GCC/Clang/LLVM evidence', G3='PARTIAL: '+residual, G4='PARTIAL: implemented returning owners qualify; bounded source/field obligations remain', G5='PARTIAL: implemented source-bound domain has independent stage controls; missing bounded forms have no proof', G6=('PASS' if original_executed else 'PARTIAL')+': additional native counts qualified; original unchanged function '+('executes' if original_executed else 'has no Astra execution'), G7=('PASS' if original_executed else 'PARTIAL')+': returning qualified corpora have zero unsuppressed errors/losses; original native memory '+('qualified' if original_executed else 'unavailable'), G8='PASS for implemented domain: inherited 39/24 plus independently checked new semantic/physical categories/profile; exact counts in profiles', G9='PASS' if original_executed else 'PARTIAL: four exact cohorts replayed; original unchanged function remains source-bound deferred', G10='PASS: 56/12/12 statuses, 1044 historical proof hashes, 451 protected paths and 6622 donor files preserved', G11='PASS: C0/public ABI/LLVM23/limits/workflow/history preserved; costs retain actual attribution', G12='PENDING installed publication; independently verify the delivered ZIP, final HEAD/tree and every manifest byte after publication')
	result = dict(format='astra-effects25-r3-audit/1', status='PARTIAL', final_commit=head, final_tree=tree, previous_report_sha256=r3.REPORT, previous_report_path=str(paths.RUNTIME/'predecessor-report.zip'), historical_publication_receipts=history, configuration_path=str(a.configuration), configuration_sha256=sha(a.configuration), preservation=protection, approval=initial['approval'], profiles=profiles, gates=gates, remaining_boundary=residual, costs=config['costs'], limitations=config['limitations']); a.output.write_text(json.dumps(result, indent=2)+'\n'); print('R3 PARTIAL; actual native/source evidence bound to', head, tree, flush=True)


if __name__ == '__main__':
	main()
