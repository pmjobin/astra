#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bind measured R5 evidence to Git; unfinished original gates stay PARTIAL."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile
from state import ROOT, load_module, read, sha, git, preservation

BASE = 'c271e0822d0fc12a878a5adc1388aa1a8e147067'
REPORT = 'c188a95de8b070ad5fd396afb2ad6d4132649278f05ba0e5dc49a1f3d9e8e00c'


def memory(path):
	data = path.read_bytes(); assert b'ERROR SUMMARY: 0 errors' in data and b'in use at exit: 0 bytes in 0 blocks' in data and b'(suppressed: 0 from 0)' in data
	return sha(path)


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', required=True); p.add_argument('--build-version', required=True); p.add_argument('--output', type=Path, required=True); a = p.parse_args(); assert a.version.isalnum() and a.build_version.isalnum()
	paths = load_module('r5_audit_paths', ROOT/'tests/selfhost-effects/recover-build.py'); initial = read(paths.RUNTIME/'initial.json'); assert initial['base'] == BASE and initial['predecessor_sha256'] == REPORT
	assert not git('status', '--porcelain=v1', '--untracked-files=all').strip(); head = git('rev-parse', 'HEAD').strip(); tree = git('rev-parse', 'HEAD^{tree}').strip(); assert subprocess.run(['git', 'merge-base', '--is-ancestor', BASE, head], cwd=ROOT).returncode == 0
	protection = preservation(); assert protection == initial['protection'] and git('config', '--show-origin', '--list') == initial['config']
	assert sha(paths.RUNTIME/'predecessor-report.zip') == REPORT == sha(ROOT.parent/'codex/reports/astra-report-current.zip')
	with zipfile.ZipFile(paths.RUNTIME/'predecessor-report.zip') as z: old = json.loads(z.read('evidence/final-audit.json'))
	anchors = [('compiler/semantic/flow-query.astra', 1870, 2001, '8641d4ff6a1f19cc8bfc0ccbec492a8f7d4248eebcb05373c15479e7114a3e68'), ('compiler/source/source.astra', 6349, 7688, '379db79194d55c7f116b08c8dba7157bdfdebbee5dc5c2b95f1478de483c8305'), ('lib/astra/text/utf8-message.astra', 383, 445, '7f3d16f810dd512103d3f836b3acd2cb55ecfaea3ec4186e9f67bcbb738a6767')]
	for name, first, last, expected in anchors: assert hashlib.sha256((ROOT/name).read_bytes()[first:last]).hexdigest() == expected
	for name in ('compiler/backend/llvm/recover-helpers-check.astra', 'compiler/backend/llvm/recover-float.astra', 'compiler/backend/llvm/capi.c', 'compiler/backend/llvm/capi.astra'):
		assert (ROOT/name).read_bytes() == subprocess.check_output(['git', 'show', BASE+':'+name], cwd=ROOT)
	module = 'compiler/backend/llvm/recover-module.astra'; original = subprocess.check_output(['git', 'show', BASE+':'+module], cwd=ROOT); assert original.split(b'\n\tvoid emit(', 1)[0] == (ROOT/module).read_bytes().split(b'\n\tvoid emit(', 1)[0], 'Allocation helpers and noinline policy must remain exact'
	profiles = {}
	for mode in ('O0', 'O2'):
		component = paths.BUILD/('full-'+a.build_version+'-'+mode)/('astra-llvm-'+mode); identity = read(component.with_suffix('.identity.json')); assert sha(component) == identity['sha256'] and identity['identity']['argv'][1] == '-'+mode and all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
		consolidated = paths.RUNTIME/('consolidated-'+a.version+'-'+mode); complete = read(consolidated/'result.json'); assert complete['status'] == 'R5_CONSOLIDATED_RECIPES_COMPLETED' and not complete['failed_jobs'] and complete['component_sha256'] == sha(component)
		for row in read(consolidated/'commands.json'):
			assert row['exit'] == 0 and sha(consolidated/(row['name']+'.stdout')) == row['stdout_sha256'] and sha(consolidated/(row['name']+'.stderr')) == row['stderr_sha256']
		def programs(suffix):
			leaf = paths.RUNTIME/('early-'+a.version+suffix+'-'+mode); result = read(leaf/'result.json'); assert result['component_sha256'] == sha(component) and result['target_profile'] == mode and result['component_build_profile'] == '-'+mode
			commands = {row['name']: row for row in result['commands']}; rows = []
			for row in result['programs']:
				name = row['name']; build = paths.BUILD/leaf.name; assert row['Astra_effect_ELF'] and sha(leaf/(name+'.astra')) == row['source_sha256'] and sha(build/(name+'-Astra.ll')) == row['Astra_raw_LLVM_sha256'] and sha(build/(name+'-Astra')) == row['Astra_ELF_sha256'] and sha(build/(name+'-C0')) == row['C0_ELF_sha256']
				for label, code in [('Astra-emit', 0), ('Astra-verify', 0), ('Astra-optimized-verify', 0), ('Astra-execute', 42), ('C0-execute', 42), ('Astra-memory', 42), ('C0-memory', 42)]: assert commands[name+'-'+label]['exit'] == code
				for stream in ('stdout', 'stderr'): assert (leaf/(name+'-Astra-execute.'+stream)).read_bytes() == (leaf/(name+'-C0-execute.'+stream)).read_bytes()
				rows.append(dict(name=name, source_sha256=row['source_sha256'], raw_LLVM_sha256=row['Astra_raw_LLVM_sha256'], ELF_sha256=row['Astra_ELF_sha256'], actual_error_path=row['observed_error_path'], returning_memory={label: memory(leaf/(name+'-'+label+'-memory.stderr')) for label in ('Astra', 'C0')}))
			return rows
		retained = [row for suffix in ('scalar', 'record', 'owned', 'errors', 'loops', 'literal', 'domain', 'fields') for row in programs(suffix)]; prefix = programs('prefix')
		assert len(retained) == 138 and sum(r['actual_error_path'] for r in retained) == 74 and {r['source_sha256'] for r in retained} == {r['source_sha256'] for r in old['profiles'][mode]['programs']}
		assert len(prefix) == 13 and sum(r['actual_error_path'] for r in prefix) == 8 and len({r['source_sha256'] for r in retained+prefix}) == 151
		inherited = read(paths.RUNTIME/('inherited-'+a.version+'-'+mode)/'result.json'); assert inherited['component_sha256'] == sha(component) and len(inherited['programs']) == 202 and all(set(r['returning_memory']) == {'Astra', 'C0'} for r in inherited['programs'])
		mutants = []
		for stem in ('adversarial', 'owner-adversarial', 'loop-adversarial', 'r3-adversarial', 'r3-domain-adversarial', 'r4-adversarial'):
			leaf = paths.RUNTIME/(stem+'-'+a.version+'-'+mode); result = read(leaf/'result.json'); assert result['component_sha256'] == sha(component); commands = read(leaf/'commands.json'); physical = result['LLVM_valid_physical']; artifacts = {sha(p): p for p in (paths.BUILD/leaf.name).glob('*.ll')}
			for row in physical:
				path = artifacts[row['LLVM_sha256']]; assert any(c['exit'] == 0 and c['argv'][0] == 'opt' and '-passes=verify' in c['argv'] and str(path) in c['argv'] for c in commands)
			mutants.append(dict(recipe=stem, semantic=len(result['semantic']), LLVM_valid_physical=len(physical), result_sha256=sha(leaf/'result.json')))
		assert sum(r['semantic'] for r in mutants) == 101 and sum(r['LLVM_valid_physical'] for r in mutants) == 52
		cohorts = read(paths.RUNTIME/('cohorts-'+a.version+'-'+mode)/'result.json'); assert cohorts['component_sha256'] == sha(component) and len(cohorts['cohorts']) == 4 and sorted(r['files'] for r in cohorts['cohorts'].values()) == [79, 85, 92, 92] and all(r['conditional_17_19_preserved'] for r in cohorts['cohorts'].values())
		root = cohorts['cohorts']['original']['independent_root']; assert (root['status'], root['graph'], root['symbol'], root['predicate'], root['source_root'], root['grown_slot']) == ('DEFERRED', 55, 2053, 26, 0, 6)
		full = read(paths.RUNTIME/('original-'+a.version+'-'+mode)/'result.json'); reduced = read(paths.RUNTIME/('r4-original-view-'+a.version+'-'+mode)/'result.json'); assert not full['Astra_emitted'] and not reduced['Astra_emitted'] and full['Astra_actual_execution'] is None and reduced['Astra_actual_execution'] is None and full['C0_actual_execution'] == reduced['C0_actual_execution'] == 42
		assert full['first_source_boundary']['node'] == 1004 and full['first_source_boundary']['source_fragment_sha256'] == anchors[1][3] and reduced['first_source_boundary']['node'] == 282 and reduced['first_source_boundary']['fragment_sha256'] == anchors[2][3]
		negative = read(paths.RUNTIME/('prefix-negative-'+a.version+'-'+mode)/'result.json'); assert negative['component_sha256'] == sha(component) and len(negative['programs']) == 12 and all(r['Astra_Typecore_rejected'] and r['C0_rejected'] and r['destination_preserved'] for r in negative['programs'])
		literals = read(paths.RUNTIME/('prefix-literals-'+a.version+'-'+mode)/'result.json'); assert literals['component_sha256'] == sha(component) and len(literals['programs']) == 3 and all(not r['Astra_emitted'] and r['C0_exit'] == 42 for r in literals['programs'])
		oracles = read(paths.RUNTIME/('original-oracles-first-'+mode)/'result.json'); assert len(oracles['programs']) == 16 and sum(r['actual_InvalidUtf8'] for r in oracles['programs']) == 8 and oracles['Astra_native_credit'] == 0
		drift = read(paths.RUNTIME/('drift-'+a.version+'-'+mode)/'result.json'); assert len(drift['retained_138']) == 138 and len(drift['inherited_202']) == 202 and drift['effects_R4_R3_raw_identical'] == 0
		profiles[mode] = dict(component=str(component), component_sha256=sha(component), component_identity_sha256=sha(component.with_suffix('.identity.json')), retained_native=340, retained_error_paths=74, new_native=13, new_error_paths=8, total_native=353, programs=retained+prefix, inherited=inherited['programs'], mutations=mutants, full_original=full, minimal_original=reduced, cohorts=cohorts['cohorts'], drift_summary={k: v for k, v in drift.items() if k not in ('retained_138', 'inherited_202')}, historical_statuses=dict(admitted=56, rejected=12, deferred=12))
	proof = read(paths.RUNTIME/'prefix-proof-canonical/result.json'); assert proof['source_sha256'] == sha(ROOT/'compiler/backend/llvm/recover-integral.astra')
	cost_path = paths.RUNTIME/'costs-final.json'; costs = read(cost_path)
	cost_index = dict(path=str(cost_path), bytes=cost_path.stat().st_size, sha256=sha(cost_path), status=costs['status'], build_check_attempts=len(costs['builds']), exact_reuse_observations=len(costs['exact_product_reuse']), GNU_time_records=len(costs['all_GNU_time_measurements']), measurement_accounting=costs['measurement_accounting'], evidence='Complete measured costs and every referenced receipt are retained in the lossless evidence archive; this compact audit binds their index by exact hash and size.')
	gates = dict(G0='PASS: exact intake, R4 report/source/Git, C0 and original E25-A-v1 approval authenticated', G1='PASS for retained source/mutation domain: fresh 340 native identities and 101 semantic/52 LLVM-valid physical categories per profile; strict raw drift disclosed separately', G2='PARTIAL: original SourceSpan shared owner/field/retain/release admission remains unproved', G3='PARTIAL: unary !, +, signed - and integral ~ on recorded typed operands qualified; signed literal operand provenance remains unproved; UTF8/count conversion, indexed buffers, fixed arrays/slices and integer division/modulo/casts in effects lowering remain unqualified', G4='PARTIAL: complete original builder/SourceBuffer/formatter have independent C0 oracles only', G5='PARTIAL: remaining bounded owned result/field/rvalue receiver and derived Error computed-base forms unproved', G6='PARTIAL: ZERO original flow_number Astra executions at O0 and O2, in both full source and reduced view', G7='PARTIAL: implemented-domain returning memory, fatal allocation and physical controls pass; original shared/UTF8 target has no Astra memory qualification', G8='PARTIAL: 12 new source negatives and nine focused physical categories; 12 new semantic stage mutation categories and new integrated full-module physical mutations are not established', G9='PASS for preserved cohorts: exact four source/node populations and 17/19 facts; independent 55/2053/26 remains DEFERRED root0 vs slot6; 56/12/12 historical statuses preserved', G10='PASS: protected paths, donor, 1044 proof hashes, hooks/settings, workflow and Git history preserved', G11='PASS for platform/provenance: matched actual O0/O2 LLVM23 builds and executions; unchanged C0/public ABI/E25-A-v1 and 256/8M ceilings; measured costs recorded', G12='PENDING: installed publication and independent after-delivery ZIP/source/Git/transport verification')
	result = dict(format='astra-effects25-r5-audit/1', status='PARTIAL', final_commit=head, final_tree=tree, previous_report_sha256=REPORT, protection_counts=dict(protected=len(protection['protected']), donor=len(protection['donor']), historical_proofs=protection['historical_proofs']), approval=initial['approval']['receipt'], profiles=profiles, gates=gates, focused_physical_proof=proof, costs=cost_index, changed_paths=git('diff', '--name-only', BASE, head).splitlines(), remaining_boundary='Full original: RecoverFlow declaration admission SourceSpan node1004 compiler/source/source.astra [6349,7688), SHA256 '+anchors[1][3]+'. Minimal byte/AST-preserving view: Utf8MessageFactory node282 lib/astra/text/utf8-message.astra [383,445), SHA256 '+anchors[2][3]+'. Genuine unchanged original flow_number has zero Astra executions. Shared owner lifetime, checked UTF8/count conversion, indexed buffers, fixed arrays/slices, casts/div/mod, signed literal operand Typecore facts, original builder/formatter and remaining C0-valid bounded owning result/receiver/derived Error forms remain unfinished.', limitation='Milestone 25 completion attempt only. No narrowed PASS, R4 retroactive PASS, Stage1, milestone26, release or push. Selected source witnesses are relocated read-only inputs; no live original source was replaced.')
	a.output.write_text(json.dumps(result, indent=2)+'\n'); print('R5 audit PARTIAL: matched 353 native programs/profile; original flow_number remains unexecuted', flush=True)


if __name__ == '__main__':
	main()
