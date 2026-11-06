#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bind actual GENREF qualification and preserved boundaries to final Git state."""
import argparse
import importlib.util
import json
from pathlib import Path
import platform
import re
import subprocess
import time
import zipfile
from state import ROOT, RUNTIME, BUILD, PRIOR, C0, BASE, TREE, REPORT, COHORTS, read, sha, git, archive


def metrics(path):
	text = path.read_text(); result = {}
	for key, label in [('user_CPU_seconds', 'User time (seconds)'), ('system_CPU_seconds', 'System time (seconds)'), ('peak_RSS_KiB', 'Maximum resident set size (kbytes)')]:
		match = re.search(re.escape(label)+r':\s*([0-9.]+)', text); result[key] = float(match[1]) if match else None
	match = re.search(r'Elapsed \(wall clock\) time \(h:mm:ss or m:ss\):\s*(\S+)', text)
	if match:
		parts = list(map(float, match[1].split(':'))); result['elapsed_seconds'] = sum(value*60**position for position, value in enumerate(reversed(parts)))
	return result


def product(path, mode):
	identity = read(path.with_suffix('.identity.json')); assert sha(path) == identity['sha256']
	assert all(sha(source) == value for group in ('sources', 'tools') for source, value in identity['identity'][group].items())
	assert [arg for arg in identity['identity']['argv'] if arg in ('-O0', '-O2')] == ['-'+mode]
	return dict(path=str(path), bytes=path.stat().st_size, sha256=sha(path), identity_sha256=sha(path.with_suffix('.identity.json')))


def main():
	p = argparse.ArgumentParser(); p.add_argument('--O0', type=Path, required=True); p.add_argument('--O2', type=Path, required=True); a = p.parse_args()
	assert git('status', '--porcelain=v1', '--untracked-files=all') == ''
	head = git('rev-parse', 'HEAD').strip(); tree = git('rev-parse', 'HEAD^{tree}').strip(); initial = read(RUNTIME/'initial.json')
	assert initial['base'] == BASE and initial['tree'] == TREE
	assert subprocess.run(['git', 'merge-base', '--is-ancestor', BASE, head], cwd=ROOT).returncode == 0
	changed = git('diff', '--name-only', BASE+'..'+head).splitlines()
	assert all(name.startswith('tests/selfhost-genref/') or name in ('compiler/semantic/generic.astra', 'compiler/semantic/generic-check.astra', 'format/scope.json', 'docs/selfhost-genref-24.md') for name in changed)
	assert sorted(name for name in changed if name.startswith('compiler/')) == ['compiler/semantic/generic-check.astra', 'compiler/semantic/generic.astra']
	spec = importlib.util.spec_from_file_location('preservation', ROOT/'tests/selfhost-genresource/state.py'); previous = importlib.util.module_from_spec(spec); spec.loader.exec_module(previous)
	assert all(value == initial[key] for key, value in previous.preservation().items())
	for name in initial['protected']:
		mode = git('ls-tree', BASE, '--', name).split()[0]; assert (ROOT/name).stat().st_mode & 0o777 == (0o755 if mode == '100755' else 0o644)
	proofs = read(RUNTIME.parent/'indexpath18/historical-proof-outputs.json'); assert len(proofs['outputs']) == proofs['count'] == 1044 and all(sha(path) == row['sha256'] for path, row in proofs['outputs'].items())
	for path, value in initial['workflow'].items(): assert sha(path) == value
	for path, value in initial['hooks'].items(): assert sha(path) == value['sha256'] and oct(Path(path).stat().st_mode & 0o777) == value['mode']
	assert git('config', '--show-origin', '--list') == initial['config'] and git('stash', 'list') == initial['stash'] and git('ls-files', '--others', '--ignored', '--exclude-standard') == initial['ignored']
	refs = dict((line.split()[1], line.split()[0]) for line in git('show-ref').splitlines()); oldrefs = dict((line.split()[1], line.split()[0]) for line in initial['refs'].splitlines())
	assert refs.keys() == oldrefs.keys() and all(refs[key] == value for key, value in oldrefs.items() if key != 'refs/heads/main')
	assert git('worktree', 'list', '--porcelain').replace('HEAD '+head, 'HEAD '+BASE) == initial['worktrees']
	assert sha(RUNTIME/'predecessor-report.zip') == REPORT and (RUNTIME/'predecessor-report.zip').stat().st_size == 21408478
	archives = [archive(ROOT.parent/'codex/submissions/ASTRA-SELFHOST-GENREF-24-SUBMISSION.zip'), archive(RUNTIME/'predecessor-report.zip'), archive(PRIOR/'predecessor-report.zip')]
	with zipfile.ZipFile(RUNTIME/'predecessor-report.zip') as z:
		assert read(RUNTIME.parent/'native-current/input/PROVENANCE.json')['predecessor']['report_sha256'] == REPORT
		result = json.loads(z.read('RESULT.json')); assert (result['status'], result['final_commit'], result['final_tree']) == ('PASS', BASE, TREE)
		for row in read(RUNTIME.parent/'native-current/input/REFERENCE-INDEX.json')['entries']: assert (RUNTIME.parent/'native-current/input'/row['path']).read_bytes() == z.read(row['origin_report_member'])
	with zipfile.ZipFile(PRIOR/'predecessor-report.zip') as z: assert json.loads(z.read('RESULT.json'))['status'] == 'PARTIAL'
	assert (ROOT/'docs/selfhost-membercall-22-checkpoint.md').read_bytes() == subprocess.check_output(['git', 'show', BASE+':docs/selfhost-membercall-22-checkpoint.md'], cwd=ROOT)
	old_scope = json.loads(subprocess.check_output(['git', 'show', BASE+':format/scope.json'], cwd=ROOT)); scope = read(ROOT/'format/scope.json'); assert all(scope.get(name) == value for name, value in old_scope.items())
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4' and sha(C0) == 'e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b' and platform.machine() == 'x86_64'
	# Generic limits, exact type/key matching, call/borrow checks and all other
	# compiler stages retain their original independent implementations.
	old = subprocess.check_output(['git', 'show', BASE+':compiler/semantic/generic.astra'], cwd=ROOT); new = (ROOT/'compiler/semantic/generic.astra').read_bytes()
	assert old.split(b'GenericInstance generic_copy_bindings(', 1)[0] == new.split(b'GenericInstance generic_copy_bindings(', 1)[0]
	assert old.split(b'SymbolId generic_instantiate(', 1)[1] == new.split(b'SymbolId generic_instantiate(', 1)[1]
	old = subprocess.check_output(['git', 'show', BASE+':compiler/semantic/generic-check.astra'], cwd=ROOT); new = (ROOT/'compiler/semantic/generic-check.astra').read_bytes()
	assert old.split(b'bool generic_token_equal(', 1)[0] == new.split(b'bool generic_token_equal(', 1)[0]
	assert old.split(b'// Independent storage-bound checks', 1)[1] == new.split(b'// Independent storage-bound checks', 1)[1]
	assert b'CoreWalk' not in (ROOT/'compiler/semantic/generic.astra').read_bytes()+new
	assert read(RUNTIME/'recovered-build-inputs/result.json')['status'] == 'PASS'
	formatting = read(RUNTIME/'final-format.json'); assert formatting['changed'] == 0 and all(row['state'] == 'compliant' for row in formatting['rows'])
	profiles = {}; products = {}; cohort_results = {}; next_results = {}; sizes = {}
	for mode in ('O0', 'O2'):
		component = getattr(a, mode); products[mode] = product(component, mode)
		inherited = read(RUNTIME/('inherited-v3-'+mode)/'result.json'); qualified = read(RUNTIME/('qualified-v3-'+mode)/'result.json')
		assert inherited['status'] == qualified['status'] == 'PASS' and inherited['component_sha256'] == qualified['component_sha256'] == sha(component)
		assert len(inherited['programs']) == 187 and len(qualified['programs']) == 15
		rows = inherited['programs']+qualified['programs']; assert len({tuple(s['sha256'] for s in row['sources']) for row in rows}) == 202
		for row in rows:
			assert all(sha(source['path']) == source['sha256'] for source in row['sources'])
			for value in row.get('fresh_products', row.get('products')).values(): assert sha(value['path']) == value['sha256']
			elf = row.get('fresh_products', row.get('products'))['native']; header = Path(elf['path']).read_bytes()[:64]; assert header[:5] == b'\x7fELF\x02' and int.from_bytes(header[18:20], 'little') == 62
		assert all(row['IR_equal_to_predecessor'] for row in inherited['programs'])
		assert all(row['baseline_complete'] and set(row['memory']) == {'native', 'C0'} for row in qualified['programs'])
		models = read(RUNTIME/('models-v4-'+mode)/'result.json'); physical = read(RUNTIME/('physical-v3-'+mode)/'result.json'); independent = read(RUNTIME/('oracle-mutants-v3-'+mode)/'result.json')
		assert all(value['status'] == 'PASS' for value in (models, physical, independent)) and len(models['mutations']) == 37 and len(physical['mutations']) == 7 and len(independent['mutations']) == 27
		assert all(row['stage'] == 7 and row['valid_twin_restored'] for row in models['mutations']) and all(row['LLVM_valid'] and row['independently_rejected'] for row in physical['mutations'])
		assert [row['retained_v1_predicate'] for row in models['mutations'][26:29]] == [0, 0, 0]
		mutator = BUILD/('mutator-v4-'+mode)/('genref-mutator-'+mode); assert sha(mutator) == models['component_sha256']; product(mutator, mode)
		assert read(RUNTIME/('lifetime-v3-'+mode)/'result.json')['status'] == 'PASS'
		assert len(read(RUNTIME/('lifetime-v3-'+mode)/'result.json')['allocating_programs']) == 13
		controls = read(RUNTIME/('controls-v3-'+mode)/'result.json'); resources = read(RUNTIME/('resources-v3-'+mode)/'result.json')
		assert controls['status'] == resources['status'] == 'PASS' and controls['component_sha256'] == resources['component_sha256'] == sha(component)
		assert controls['original_statuses'] == {'admitted':56, 'rejected':12, 'deferred':12} and controls['continuity']['inherited_downstream_models']['categories'] == 28
		assert resources['results']['reuse']['retained_instances'] == 1 and resources['results']['distinct-257']['retained_instances'] == 256
		assert read(RUNTIME/('effect-boundary-v3-'+mode)/'result.json')['status'] == 'EXISTING_EFFECT_BOUNDARY_CONFIRMED' and len(read(RUNTIME/('negative-v3-'+mode)/'result.json')['cases']) == 10
		cohorts = read(RUNTIME/('cohorts-v3-'+mode+'.json')); next_stop = read(RUNTIME/('next-blocker-v3b-'+mode)/'result.json')
		assert set(cohorts) == set(next_stop['cohorts']) == set(COHORTS)
		for name in COHORTS:
			row = cohorts[name]; before = read(RUNTIME/'baseline.json')[name]; after = next_stop['cohorts'][name]
			assert row['component_sha256'] == sha(component) and row['independent_consumer']['codes'] == ['CHECKED_CONSUMER 1 25']
			assert row['population_sha256'] == before['population_sha256'] and row['node_identity_sha256'] == before['node_identity_sha256'] and row['nodes'] == before['nodes'] and row['files'] == before['files']
			assert (row['original_call']['type'], row['original_call']['flags'], row['original_call']['deferred']) == (1, 0, 19)
			oracle = after['reference_oracle']; assert oracle['status'] == 'PASS' and oracle['verified_references'] == (2394 if name in ('original', 'LLVM23-base') else 2367)
			assert oracle['input_sha256'] == sha(RUNTIME/('data-full-v3-'+mode)/(name+'.stdout')) and oracle['oracle_sha256'] == sha(ROOT/'tests/selfhost-genref/oracle.py')
			assert after['predicate_reason'] == 13 and (after['argument']['type'], after['argument']['flags'], after['argument']['obligation']) == (0, 4, 19)
		cohort_results[mode] = cohorts; next_results[mode] = next_stop['cohorts']
		warm = RUNTIME/('warm-v3-'+mode); assert list(warm.rglob('ownflow-'+mode+'-exact-reuse.json')) and not list(warm.rglob('ownflow-'+mode+'.json'))
		sizes[mode] = dict(native_ELF_bytes=sum(Path(row.get('fresh_products', row.get('products'))['native']['path']).stat().st_size for row in rows), native_ELF_unique_sha256=len({row.get('fresh_products', row.get('products'))['native']['sha256'] for row in rows}), new_C0_ELF_bytes=sum(Path(row['products']['C0']['path']).stat().st_size for row in qualified['programs']), warm_reuse=metrics(RUNTIME/('warm-v3-'+mode+'.time')))
		profiles[mode] = dict(inherited_native_sources=187, new_native_sources=15, total_native_sources=202, inherited_raw_LLVM_identical=187, new_Astra_reference_model_mutations=37, separate_Python_oracle_mutations=27, LLVM_valid_physical_alternatives=7, new_native_and_C0_memory_pairs=15, material_native_allocation_programs=13, inherited_source_statuses=controls['original_statuses'], inherited_downstream_model_controls=28, strict_source_negatives=10)
	costs = []
	for path in sorted(RUNTIME.rglob('ownflow-*.json')):
		if path.name.endswith(('input-identity.json', 'exact-reuse.json')): continue
		row = read(path)
		if 'exit' not in row: continue
		start = row.get('start', row.get('monotonic_start')); end = row.get('end', row.get('monotonic_end')); stderr = path.with_suffix('.stderr')
		costs.append(dict(path=str(path), exit=row['exit'], monotonic_start=start, monotonic_end=end, wall_seconds=end-start, **metrics(stderr)))
	result = dict(format='astra-genref24-qualification/1', status='PASS', scope='Reference correspondence only; not whole-compiler native admission or Stage 1', base_commit=BASE, base_tree=TREE, final_commit=head, final_tree=tree, changed_paths=changed, source_blobs={name:dict(Git_blob=git('rev-parse', head+':'+name).strip(), sha256=sha(ROOT/name)) for name in changed}, products=products, profiles=profiles, cohorts=cohort_results, next_actual_blocker=next_results, archives=archives, protected_files=451, donor_files=6622, historical_proof_outputs=1044, historical_proof_attribution='Original byte identities preserved, not fresh historical qualification', historical_MEMBERCALL22_status='PARTIAL', cold_and_failed_build_attempts=costs, sizes=sizes, cost_attribution='Builds overlap. Parent and child timing/RSS observations overlap and are not summed as an exclusive benchmark. Warm checks validate exact identities and reuse products; they are not cold recompilations.', gates={**{f'G{i}':'PASS' for i in range(11)}, 'G11':'Installed publisher validates final state and creates the canonical report; this audit precedes publication'}, remaining_deferrals=['All four complete frozen modules refuse at generic call verification 25: append(move graph), argument TypeId 0, owned flag 4, obligation 19. No inferred nominal local type replaces the actual recorded zero.', 'The four original calls 40833/42968/46736/47584 retain int TypeId 1, flags 0 and ownership/borrow obligation 19.', 'Complete original admit_record_value and class_storage_slot_flow bytes/ASTs and throws Error signatures remain unchanged; native complete-caller execution is DEFERRED. C0 parse/AST identity is not complete-caller native execution.', 'Recoverable error transport, cleanup and exception/error ABI require separate explicit approval; fatal traps do not establish them.', 'Historical three-specialization SSA work-limit cases, wide-u64/f32 Valgrind discrepancy, complete Utf8Message factory/exception coverage, full compiler native admission, self-compilation and Stage 1 remain unqualified. Their source/limit boundaries and historical attribution are preserved.', 'Refused shadowing drafts, the oversized single-function resource probe, failed observer borrow/check selector attempts, short cancelled v2 builds and intermediate v1 qualifications remain in the evidence with their actual revisions and outcomes.'], recipe_sha256=sha(__file__), audit_monotonic=time.monotonic())
	(RUNTIME/'final-audit.json').write_text(json.dumps(result, indent=2)+'\n'); print(head, tree, 'GENREF scoped PASS: 202/profile; 37 reference, 27 independent-oracle and 7 physical alternatives/profile')


if __name__ == '__main__':
	main()
