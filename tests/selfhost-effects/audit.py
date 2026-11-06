#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bind the honest PARTIAL checkpoint and its preserved boundaries to Git."""
import json
from pathlib import Path
import re
import subprocess
from state import ROOT, RUNTIME, BUILD, PRIOR, INPUT, BASE, TREE, REPORT, C0, COHORTS, read, sha, git, preservation


def metrics(path):
	text = path.read_text(); result = {}
	for key, label in [('user_seconds', 'User time (seconds)'), ('system_seconds', 'System time (seconds)'), ('peak_RSS_KiB', 'Maximum resident set size (kbytes)')]:
		match = re.search(re.escape(label)+r':\s*([0-9.]+)', text); result[key] = float(match[1]) if match else None
	match = re.search(r'Elapsed \(wall clock\) time \(h:mm:ss or m:ss\):\s*(\S+)', text)
	if match:
		parts = list(map(float, match[1].split(':'))); result['wall_seconds'] = sum(value*60**i for i, value in enumerate(reversed(parts)))
	return result


def main():
	assert not git('status', '--porcelain=v1', '--untracked-files=all')
	head = git('rev-parse', 'HEAD').strip(); tree = git('rev-parse', 'HEAD^{tree}').strip(); initial = read(RUNTIME/'initial.json')
	assert initial['base'] == BASE and initial['tree'] == TREE
	assert subprocess.run(['git', 'merge-base', '--is-ancestor', BASE, head], cwd=ROOT).returncode == 0
	changed = git('diff', '--name-only', BASE+'..'+head).splitlines()
	assert all(p.startswith('tests/selfhost-effects/') or p in ('compiler/semantic/TYPECORE.md', 'compiler/semantic/expressions.astra', 'compiler/semantic/statements.astra', 'format/scope.json', 'docs/selfhost-effects-25.md', 'docs/selfhost-effects-25-abi-proposal.md') for p in changed)
	assert sorted(p for p in changed if p.startswith('compiler/') and p.endswith('.astra')) == ['compiler/semantic/expressions.astra', 'compiler/semantic/statements.astra']
	state = preservation(); assert all(state[k] == initial[k] for k in ('protected', 'donor', 'donor_head', 'donor_status', 'workflow', 'hooks', 'historical_proofs', 'exclusions'))
	for path in initial['protected']:
		mode = git('ls-tree', BASE, '--', path).split()[0]; assert (ROOT/path).stat().st_mode & 0o777 == (0o755 if mode == '100755' else 0o644)
	assert git('config', '--show-origin', '--list') == initial['config'] and git('stash', 'list') == initial['stash'] and git('ls-files', '--others', '--ignored', '--exclude-standard') == initial['ignored']
	refs = dict((line.split()[1], line.split()[0]) for line in git('show-ref').splitlines()); oldrefs = dict((line.split()[1], line.split()[0]) for line in initial['refs'].splitlines())
	assert refs.keys() == oldrefs.keys() and all(refs[key] == value for key, value in oldrefs.items() if key != 'refs/heads/main')
	assert git('worktree', 'list', '--porcelain').replace('HEAD '+head, 'HEAD '+BASE) == initial['worktrees']
	assert sha(RUNTIME/'predecessor-report.zip') == sha(ROOT.parent/'codex/reports/astra-report-current.zip') == REPORT
	for row in initial['archives']: assert sha(row['path']) == row['sha256']
	proposal = ROOT/'docs/selfhost-effects-25-abi-proposal.md'; approval = read(RUNTIME/'abi-approval.json')
	assert sha(proposal) == sha(RUNTIME/'approved-proposal.md') == approval['proposal_sha256'] == 'd77c02f3144ab5dc3da41eb310b29cd02629b49876042934ea5071a1549ac66e'
	assert approval['decision'] == 'APPROVE THE BOUNDED DESIGN E25-A-v1'
	assert read(RUNTIME/'source-oracle-v2/result.json')['status'] == 'EXACT_METHOD_C0_SYNTAX_ONLY'
	assert read(RUNTIME/'c0-design-v2/result.json')['status'] == 'C0_DESIGN_EVIDENCE_ONLY'
	assert read(RUNTIME/'layout-v1/result.json')['status'] == 'C0_LAYOUT_DESIGN_EVIDENCE'
	assert read(RUNTIME/'process-deadline.json')['status'] == 'PASS'
	products = {}; profiles = {}
	for mode in ('O0', 'O2'):
		component = BUILD/('compiler-v1-'+mode)/('astra-llvm-'+mode); identity = read(component.with_suffix('.identity.json'))
		assert sha(component) == identity['sha256'] and all(sha(path) == value for group in ('sources', 'tools') for path, value in identity['identity'][group].items())
		assert '-'+mode in identity['identity']['argv']; products[mode] = dict(path=str(component), sha256=sha(component), bytes=component.stat().st_size, identity_sha256=sha(component.with_suffix('.identity.json')))
		rows = read(RUNTIME/('inherited-v1-'+mode)/'result.json')['programs']; assert len(rows) == 202 and len({tuple(s['sha256'] for s in row['sources']) for row in rows}) == 202
		for row in rows:
			assert row['IR_equal_to_predecessor'] and all(sha(s['path']) == s['sha256'] for s in row['sources'])
			assert all(sha(p['path']) == p['sha256'] for p in row['fresh_products'].values())
			elf = Path(row['fresh_products']['native']['path']).read_bytes(); assert elf[:5] == b'\x7fELF\x02' and int.from_bytes(elf[18:20], 'little') == 62
		cohorts = read(RUNTIME/('cohorts-v1-'+mode+'.json')); traces = read(RUNTIME/('trace-full-v1-'+mode)/'result.json')
		for name, expected in zip(COHORTS, (197, 198, 202, 202)):
			row = traces[name]; cohort = cohorts[name]; assert row['component_sha256'] == cohort['component_sha256'] == sha(component)
			assert row['consumer'][0][0] == '0' and list(map(int, row['local'][5:7])) == [expected, 4]
			assert list(map(int, row['local_use'][1:4])) == list(map(int, row['initializer'][1:4])) == [expected, 4, 17]
			assert list(map(int, row['move'][1:4])) == [expected, 4, 19] and int(row['signature'][4]) == 68
			assert row['Flow_status'][0][0] == '1' and int(row['Flow_verifier_stops'][0][1]) == 26
			producer = next(r for r in row['source_signatures'] if r[0] == row['producer'][1]); assert int(producer[1]) == expected and int(producer[2]) == row['error_type'][1] and producer[4] == '1'
			assert cohort['independent_consumer']['exit'] == 1 and cohort['independent_consumer']['codes'] == []
			old = read(INPUT/('reference/report/GENREF24-COHORTS-'+mode+'.json'))[name]
			assert all(cohort[k] == old[k] for k in ('files', 'nodes', 'population_sha256', 'node_identity_sha256'))
		continuity = read(RUNTIME/('continuity-v1-'+mode)/'result.json'); assert continuity['status'] == 'INHERITED_CONTROLS_PASSED' and continuity['model_categories'] == 28 and continuity['new_effect_model_categories'] == 0
		assert continuity['original_statuses'] == dict(admitted=56, rejected=12, deferred=12)
		controls = read(RUNTIME/('controls-final-v1-'+mode)/'result.json'); assert len(controls['programs']) == 8 and controls['component_sha256'] == sha(component)
		memory = read(RUNTIME/('memory-v1-'+mode)/'result.json'); assert len(memory['programs']) == 15 and memory['new_Astra_recoverable_error_paths'] == 0
		candidates = read(RUNTIME/('candidates-final-v3-'+mode)/'result.json'); assert len(candidates['programs']) == 12 and candidates['Astra_new_native_programs'] == 0
		assert all(not row['profiles'][mode]['Astra_native_qualified'] and row['profiles'][mode]['destination_preserved'] for row in candidates['programs'])
		attempts = RUNTIME/('compiler-build-v1-'+mode); cold = list(attempts.rglob('ownflow-'+mode+'.stderr')); warm = list(attempts.rglob('ownflow-'+mode+'-exact-reuse.json')); assert len(cold) == 1 and warm
		profiles[mode] = dict(inherited_native_sources=202, raw_LLVM_identical=202, distinct_native_ELF_sha256=len({row['fresh_products']['native']['sha256'] for row in rows}), source_statuses=continuity['original_statuses'], inherited_model_controls=28, new_effect_model_controls=0, new_C0_source_oracles=12, new_Astra_effect_programs=0, fresh_normal_return_memory_programs=15, new_Astra_error_return_memory_programs=0, cold_build=metrics(cold[0]), exact_warm_reuse=[dict(path=str(p), sha256=sha(p)) for p in warm])
	formatting = read(RUNTIME/'final-format.json'); assert formatting['changed'] == 0
	result = dict(format='astra-effects25-checkpoint/1', status='PARTIAL', base_commit=BASE, base_tree=TREE, final_commit=head, final_tree=tree, changed_paths=changed, source_blobs={p:dict(Git_blob=git('rev-parse', head+':'+p).strip(), sha256=sha(ROOT/p)) for p in changed}, abi_approval=approval, products=products, profiles=profiles, protected_files=451, donor_files=6622, historical_proofs_rehashed=1044, historical_MEMBERCALL22_status='PARTIAL', gates=dict(G0='PASS', G1='PASS', G2='STATIC_TYPE_SEPARATION_PASSED; ownership/effect proof remains pending', G3='E25-A-v1 EXPLICITLY APPROVED', G4='NOT_IMPLEMENTED', G5='NOT_IMPLEMENTED', G6='202 inherited native sources/profile freshly executed; historical records retained', G7='NOT_MET: 12 C0 oracles/profile; zero new qualified Astra effect programs', G8='NOT_MET: inherited model and C0 layout checks do not qualify a new effect implementation', G9='PARTIAL: known nominal argument; complete Flow still fails', G10='PRESERVED', G11='Installed publisher pending'), remaining_deferrals=['Approved recoverable-effect ABI and full Typecore/Flow/Core/CFG/SSA/LLVM implementation, owner/error cleanup and native error execution', 'Whole-source owner-capture authority and other independent Flow refusals; no complete flow_index/flow_graph native execution', 'At least 12 new Astra programs including 8 error paths, new semantic/LLVM physical mutations and actual error-return memory checks', 'Two inherited 8000000-step SSA stress deferrals; wide-u64/f32 Valgrind disagreement; complete Utf8Message factory coverage; full compiler native admission and Stage 1'], cost_notes='Cold/warm/candidate/failed command observations overlap and are not summed as an exclusive benchmark. The source timeout/orphan overrun is explicit. No matched-workload speedup is claimed.')
	(RUNTIME/'final-audit.json').write_text(json.dumps(result, indent=2)+'\n'); print('PARTIAL checkpoint bound to', head, tree, flush=True)


if __name__ == '__main__':
	main()
