#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bind final effect evidence, inherited identities and explicit residual gates."""
import argparse
import json
from pathlib import Path
import subprocess
from state import ROOT, load_module, read, sha, git


def memory(path):
	data = path.read_bytes(); assert b'ERROR SUMMARY: 0 errors' in data and b'in use at exit: 0 bytes in 0 blocks' in data and b'(suppressed: 0 from 0)' in data; return sha(path)


def source_identity(component):
	identity = read(component.with_suffix('.identity.json')); assert sha(component) == identity['sha256']; assert all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items()); return identity


def main():
	p = argparse.ArgumentParser(); p.add_argument('--configuration', type=Path, required=True); p.add_argument('--output', type=Path, required=True); a = p.parse_args(); config = read(a.configuration)
	paths = load_module('recover_audit_paths', ROOT/'tests/selfhost-effects/recover-build.py'); original = load_module('recover_audit_preservation', ROOT/'tests/selfhost-effects/state.py'); r2 = load_module('recover_audit_approval', ROOT/'tests/selfhost-effects/r2-state.py')
	assert not git('status', '--porcelain=v1', '--untracked-files=all').strip(), 'Commit task-owned sources and findings before the final audit'
	head = git('rev-parse', 'HEAD').strip(); tree = git('rev-parse', 'HEAD^{tree}').strip(); assert subprocess.run(['git', 'merge-base', '--is-ancestor', '271d1b80b3922da1466ea303b7deea9e941249d1', head], cwd=ROOT).returncode == 0
	preservation = original.preservation(); approval = r2.approval(); old = paths.RUNTIME/'checkpoint-report.zip'; canonical = ROOT.parent/'codex/reports/astra-report-current.zip'; assert sha(old) == sha(canonical) == '8cc90df9c524cd8a22ca0e9ba166920cff9962cc92a493691de64121aad5dc5a'
	profiles = {}
	for mode in ('O0', 'O2'):
		profile = config['profiles'][mode]; component = Path(profile['component']); identity = source_identity(component); assert identity['identity']['argv'][1] == '-'+mode
		programs = []; names = set(); source_ids = set(); elf_ids = set(); error_paths = 0
		for name in profile['native_results']:
			leaf = paths.RUNTIME/name; result = read(leaf/'result.json'); assert result['target_profile'] == mode and result['component_sha256'] == sha(component)
			assert len(result['programs']) == result['new_Astra_effect_ELFs'] and result['programs']
			for row in result['programs']:
				assert row['Astra_effect_ELF'] and row['expected_exit'] == 42 and row['name'] not in names; names.add(row['name']); source = leaf/(row['name']+'.astra'); product = paths.BUILD/name/(row['name']+'-Astra'); ir = paths.BUILD/name/(row['name']+'-Astra.ll'); optimized = paths.BUILD/name/(row['name']+'-'+mode+'.ll')
				assert sha(source) == row['source_sha256'] and sha(product) == row['Astra_ELF_sha256'] and sha(ir) == row['Astra_raw_LLVM_sha256'] and sha(optimized) == row['Astra_optimized_LLVM_sha256']; assert product.read_bytes().startswith(b'\x7fELF')
				commands = [c for c in result['commands'] if c['name'].startswith(row['name']+'-')]; expected = {row['name']+'-'+suffix:code for suffix, code in [('Astra-emit',0),('Astra-verify',0),('Astra-optimized-verify',0),('Astra-execute',42),('C0-execute',42),('Astra-memory',42),('C0-memory',42)]}
				assert all(any(c['name'] == name and c['exit'] == code for c in commands) for name, code in expected.items()); assert next(c for c in commands if c['name'] == row['name']+'-Astra-emit')['argv'][0] == str(component)
				for command in commands:
					assert sha(leaf/(command['name']+'.stdout')) == command['stdout_sha256'] and sha(leaf/(command['name']+'.stderr')) == command['stderr_sha256']
				witnesses = {label:memory(leaf/(row['name']+'-'+label+'-memory.stderr')) for label in ('Astra','C0')}; source_ids.add(sha(source)); elf_ids.add(sha(product)); error_paths += int(row['observed_error_path']); programs.append(dict(name=row['name'], source_sha256=sha(source), ELF_sha256=sha(product), actual_error_path=row['observed_error_path'], memory=witnesses))
		assert len(programs) == len(source_ids) >= 12 and error_paths >= 8 and len(programs)-error_paths >= 4
		regression = paths.RUNTIME/profile['regression']; inherited = read(regression/('inherited-v1-'+mode)/'result.json'); assert inherited['component_sha256'] == sha(component) and len(inherited['programs']) == 202
		for row in inherited['programs']:
			assert row['IR_equal_to_predecessor'] and all(sha(product['path']) == product['sha256'] for product in row['fresh_products'].values()) and all(sha(source['path']) == source['sha256'] for source in row['sources'])
		continuity = read(regression/('continuity-v1-'+mode)/'result.json'); assert continuity['original_statuses'] == dict(admitted=56,rejected=12,deferred=12)
		cohorts = read(regression/('cohorts-v1-'+mode)/'result.json'); ledgers = read(regression/('ledgers-v1-'+mode+'.json')); assert len(cohorts) == len(ledgers) == 4
		for name, row in ledgers.items(): assert all(row[key] == cohorts[name][key] for key in ('files','nodes','population_sha256','node_identity_sha256')) and cohorts[name]['conditional_facts_preserved']
		first = read(regression/('first-failure-v1-'+mode)/'result.json'); assert first['first_stop'] == ['55','26']
		mutants = []
		for name in profile['adversarial']:
			result = read(paths.RUNTIME/name/'result.json'); assert result['component_sha256'] == sha(component) and result.get('target_profile', result.get('profile')) == mode; mutants.append(dict(path=name, result_sha256=sha(paths.RUNTIME/name/'result.json'), semantic=len(result['semantic']), physical=len(result['LLVM_valid_physical'])))
		assert sum(row['semantic'] for row in mutants) >= 20 and sum(row['physical'] for row in mutants) >= 6
		attempt = read(paths.RUNTIME/profile['original']/'result.json'); assert attempt['component_sha256'] == sha(component) and attempt['source']['exact_original_bytes']
		profiles[mode] = dict(component=str(component), component_sha256=sha(component), native_programs=len(programs), actual_error_programs=error_paths, success_cleanup_programs=len(programs)-error_paths, distinct_ELF_hashes=len(elf_ids), programs=programs, inherited_native_programs=202, inherited_raw_LLVM_identical=202, inherited_distinct_ELFs=len({row['fresh_products']['native']['sha256'] for row in inherited['programs']}), statuses=continuity['original_statuses'], cohorts=ledgers, predicate_26='Independently deferred at graph 55 / symbol 2053; field/root slot 0 versus local slot 6', adversarial=mutants, original_function_attempt=attempt)
		# The caller cannot claim a full milestone merely by providing enough small
		# executable cases. Static receiver and admitted payload/source boundaries
		# must have separate implementation and independent qualification evidence.
	residual = config['remaining_boundary']; assert isinstance(residual, str) and residual
	gates = dict(G0='PASS: approval, submission ancestry and historical PARTIAL preserved', G1='PASS: 202 native identities and four frozen source populations per profile', G2='PASS: genuine checked void/scalar success/error ELF and independent C0/LLVM/Valgrind', G3='PARTIAL: qualified direct carriers and Error layout; '+residual, G4='PARTIAL: independently checked implemented owners and exits; '+residual, G5='PARTIAL: independently checked implemented stage domain; '+residual, G6='PASS: at least twelve distinct Astra source identities, eight error and four success/cleanup per profile', G7='PASS for the returning qualified domain; fatal guards and absent source forms remain separately attributed', G8='PASS for the qualified mutation domain; source-boundaries remain explicit', G9='PASS' if all(p['original_function_attempt']['Astra_actual_execution'] == 42 for p in profiles.values()) else 'PARTIAL: complete immutable cohorts rechecked; original throwing function has no qualified Astra execution', G10='PASS: inherited raw LLVM, statuses, protected paths, donor and historical proofs preserved', G11='PASS: unchanged C0/public ABI/LLVM23/limits/history/workflow; measured costs retain exact build attribution', G12='PENDING: installed publisher amendment and subsequent independent archive verification')
	result = dict(format='astra-effects25-completion-audit/1', status='PARTIAL', final_commit=head, final_tree=tree, previous_report_sha256=sha(canonical), configuration_path=str(a.configuration), configuration_sha256=sha(a.configuration), preservation=preservation, approval=approval, profiles=profiles, gates=gates, remaining_boundary=residual, costs=config['costs'], limitations=config['limitations']); a.output.write_text(json.dumps(result, indent=2)+'\n'); print('PARTIAL; exact current native/source/protection evidence bound to',head,tree,flush=True)


if __name__ == '__main__':
	main()
