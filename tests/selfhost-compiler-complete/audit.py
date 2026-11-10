#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Rebind current products and complete regression receipts without narrowing 26."""
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace
import zipfile

from run import BASE, ROOT, WORK, git, sha, write


def source_identities(paths, component, mode, version, consumer):
	leaf = paths.RUNTIME/('identity-'+version+'-'+mode)
	build = paths.BUILD/leaf.name
	result = json.loads((leaf/'result.json').read_text())
	assert result['status'] == 'EXACT_R5_SOURCE_IDENTITIES_RETAINED' and result['component_sha256'] == sha(component)
	assert result['source_byte_identical_primary'] == 70 and result['original_source_identities_retained'] == 71
	original, primary = (result[key] for key in ('old_receipt', 'primary_receipt'))
	assert all(sha(row['path']) == row['sha256'] for row in (original, primary))
	old = {row['name']:row for row in json.loads(Path(original['path']).read_text())['programs']}
	new = {row['name']:row for row in json.loads(Path(primary['path']).read_text())['programs']}
	assert set(old) == set(new) == {row['name'] for row in result['comparisons']} and len(old) == 71
	for row in result['comparisons']:
		before, after = old[row['name']], new[row['name']]
		assert row['original_inputs'] == before['inputs'] and row['current_inputs'] == after['inputs']
		assert all(sha(source['path']) == source['sha256'] for item in (before, after) for source in item['inputs'])
		assert row['source_bytes_equal'] == ([v['sha256'] for v in before['inputs']] == [v['sha256'] for v in after['inputs']])
		for key, producer, field in (('raw_LLVM', 'Astra', 'raw_LLVM_sha256'), ('Astra_ELF', 'Astra', 'ELF_sha256'), ('C0_ELF', 'C0', 'ELF_sha256')):
			assert row['R5_'+key+'_sha256'] == before[producer][field] and row['current_'+key+'_sha256'] == after[producer][field]
			assert row[key+'_equal'] == (row['R5_'+key+'_sha256'] == row['current_'+key+'_sha256'])
	assert [row['name'] for row in result['comparisons'] if not row['source_bytes_equal']] == ['caller-all']
	before, after = (Path(table['caller-all']['inputs'][0]['path']) for table in (old, new))
	assert before.read_bytes().replace(str(before).encode(), str(after).encode()) == after.read_bytes()
	caller = result['exact_original_caller']
	assert caller['inputs'] == old['caller-all']['inputs']
	observed = consumer.commands(leaf)
	for name in ('C0-build', 'Astra-emit', 'verify', 'optimize', 'optimized-verify', 'object', 'link'):
		assert observed[name]['exit'] == 0 and not observed[name]['timed_out']
	inputs = [row['path'] for row in caller['inputs']]
	assert observed['Astra-emit']['argv'] == [str(component), '--native', str(build/'caller-all.ll'), *inputs]
	assert observed['C0-build']['argv'][:2+len(inputs)] == [str(consumer.C0), '-'+mode, *inputs]
	assert observed['original-source-stages']['argv'] == [str(component), '--shared-stages', *inputs]
	assert observed['original-source-stages']['exit'] == 42 and not observed['original-source-stages']['timed_out']
	stages = (leaf/'original-source-stages.stdout').read_bytes()
	assert b'SHARED_SSA_VALID' in stages and b'FLOW_LEAF ' not in stages
	for producer in ('C0', 'Astra'):
		assert observed[producer+'-execute']['exit'] == observed[producer+'-memory']['exit'] == 42
		assert '--default-suppressions=no' in observed[producer+'-memory']['argv']
		consumer.memory(leaf/(producer+'-memory.stderr'))
		assert sha(build/('caller-all-'+producer)) == caller[producer+'_ELF_sha256']
	for stream in ('stdout', 'stderr'):
		assert (leaf/('Astra-execute.'+stream)).read_bytes() == (leaf/('C0-execute.'+stream)).read_bytes()
	for filename, key in (('caller-all.ll', 'raw_LLVM'), ('caller-all-optimized.ll', 'optimized_LLVM'), ('caller-all.o', 'object')):
		assert sha(build/filename) == caller[key+'_sha256']
	assert all(sha(row['path']) == row['sha256'] for row in caller['provider_objects'])
	pool = {}
	for label, producer, field in (('raw_LLVM', 'Astra', 'raw_LLVM_sha256'), ('Astra_ELF', 'Astra', 'ELF_sha256'), ('C0_ELF', 'C0', 'ELF_sha256')):
		pool[label] = sum(row[label+'_equal'] for row in result['comparisons'] if row['name'] != 'caller-all') + int(caller[field if label == 'raw_LLVM' else label+'_sha256'] == old['caller-all'][producer][field])
	return dict(receipt=str(leaf/'result.json'), sha256=sha(leaf/'result.json'), original_source_identities=71, primary_source_identical=70, exact_original_caller=caller, current_primary_raw_identical=sum(row['raw_LLVM_equal'] for row in result['comparisons']), current_primary_Astra_ELF_identical=sum(row['Astra_ELF_equal'] for row in result['comparisons']), current_primary_C0_ELF_identical=sum(row['C0_ELF_equal'] for row in result['comparisons']), exact_original_source_pool_product_identities=pool, limitation=result['limitation'])


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--build-root', type=Path, required=True)
	p.add_argument('--runtime-root', type=Path, required=True)
	p.add_argument('--build-version', required=True)
	p.add_argument('--version', required=True)
	p.add_argument('--fixture-version', default='fix26')
	p.add_argument('--whole-source-result', type=Path, required=True)
	p.add_argument('--output', type=Path, required=True)
	a = p.parse_args()
	assert a.version.isalnum() and a.build_version.isalnum() and a.fixture_version.isalnum()
	assert not a.output.exists() and a.output.resolve().is_relative_to(a.runtime_root.resolve())
	assert not git('status', '--porcelain=v1', '--untracked-files=all').strip()
	assert git('merge-base', '--is-ancestor', BASE, 'HEAD') == b''
	intake = json.loads((WORK/'runtime/native-current/pm-next-intake.json').read_text())
	assert intake['milestone_id'] == 'ASTRA-SELFHOST-COMPILER-COMPLETE-26' and intake['base_commit'] == BASE
	assert intake['submission_sha256'] == 'c2471bf201cf558a4c079d7b185ffb17454322366743e1719289232639f8558b'
	assert sha(intake['submission_path']) == intake['submission_sha256']
	with zipfile.ZipFile(intake['submission_path']) as z:
		original = z.read('reference/original-submission.zip')
		import hashlib
		assert hashlib.sha256(original).hexdigest() == '43c89a44a04912f3fdefa4f4c73380095874301eea44cb5684ff0406368e2b11'
	parent = WORK/'runtime/report-history/16408c8bd00c3e81633e2ab7cefa6d557bbdad0dbdd9239add328c160fe7f887.zip'
	assert sha(parent) == parent.stem
	with zipfile.ZipFile(parent) as z:
		previous = json.loads(z.read('evidence/final-audit.json'))
		assert json.loads(z.read('RESULT.json'))['status'] == 'PARTIAL'
	sys.path.insert(0, str(ROOT/'tests/selfhost-effects'))
	path = ROOT/'tests/selfhost-effects/recover-resume-audit.py'
	spec = importlib.util.spec_from_file_location('compiler26_independent_receipt_consumer', path)
	consumer = importlib.util.module_from_spec(spec)
	spec.loader.exec_module(consumer)
	paths = SimpleNamespace(RUNTIME=a.runtime_root, BUILD=a.build_root)
	profiles = {}
	for mode in ('O0', 'O2'):
		component = a.build_root/('full-'+a.build_version+'-'+mode)/('astra-llvm-'+mode)
		compiler = consumer.compiler(component, mode)
		native = consumer.native(paths, component, mode, a.version)
		retained = consumer.retained(paths, component, mode, a.version, previous['profiles'][mode])
		support = consumer.support(paths, component, mode, a.version, native, retained, a.version)
		if not support['complete']:
			from receipt_support import current_support
			support = current_support(paths, component, mode, a.version, native, retained, consumer, a.fixture_version)
		identities = source_identities(paths, component, mode, a.version, consumer)
		assert native['complete'] and retained['complete'] and support['complete']
		assert len(native['programs']) == 71 and retained['retained_native'] == 340
		assert sum(row['semantic'] for row in retained['mutations']) == 101
		assert sum(row['LLVM_valid_physical'] for row in retained['mutations']) == 52
		profiles[mode] = dict(compiler=compiler, bounded_native=native, retained=retained, support=support, literal_R5_source_identities=identities)
		print(mode, 'current 340+71 and independent source/IR/ELF/ABI/memory/mutation receipts rebound', flush=True)
	assert profiles['O0']['compiler']['project_input_hashes'] == profiles['O2']['compiler']['project_input_hashes']
	assert profiles['O0']['compiler']['tools'] == profiles['O2']['compiler']['tools']
	whole = json.loads(a.whole_source_result.read_text())
	population = json.loads((a.whole_source_result.parent/'population.json').read_text())
	assert population['compiler_files'] == 180 and population['library_files'] == 10
	assert population['baseline_commit'] == BASE and len(population['files']) == 190
	for row in population['files']:
		assert sha(row['input_path']) == row['baseline_sha256']
		assert Path(row['input_path']).stat().st_mode & 0o222 == 0
		assert git('rev-parse', BASE+':'+row['path']).decode().strip() == row['baseline_blob']
		assert sha(ROOT/row['path']) == row['sha256']
	assert set(whole['profiles']) == {'O0', 'O2'}
	for mode, row in whole['profiles'].items():
		assert row['component_sha256'] == profiles[mode]['compiler']['component_sha256']
		assert row['native']['exit'] != 0 and row['refusal_destination_preserved']
		assert not any(row[key] for key in ('full_source_emitted', 'LLVM_verified', 'object_generated', 'linkage_verified', 'runtime_verified'))
		assert row['first_frontier'] is not None
	c0_path = a.runtime_root/'whole-context-C0/result.json'
	c0 = json.loads(c0_path.read_text())
	assert c0['timed_out'] and c0['exit'] == -9 and c0['seconds'] >= 2400
	g12 = WORK/'runtime/compiler26-g12-audit-20261109/final-verdict.json'
	assert sha(g12) == 'd87315df0c6602abd2895897585f2ca0f9fe4a0d1759015e00e30c1f32c5789a'
	assert json.loads(g12.read_text())['R5_G12']['status'] == 'PASS'
	assert sha(ROOT/'docs/selfhost-effects-25-abi-proposal.md') == 'd77c02f3144ab5dc3da41eb310b29cd02629b49876042934ea5071a1549ac66e'
	# Scope and protection are checked independently of the compiler being tested.
	old = json.loads((WORK/'runtime/effects25-r5-resume/initial.json').read_text())
	protection = old['protection']
	for name, expected in protection['protected'].items():
		assert sha(ROOT/name) == expected
	for name, row in protection['donor'].items():
		path = ROOT.parent/'astra-bootstrap'/name
		assert sha(path) == row['sha256'] and oct(path.stat().st_mode & 0o777) == row['mode']
	donor = ROOT.parent/'astra-bootstrap'
	assert subprocess.check_output(['git', '-C', str(donor), 'rev-parse', 'HEAD']).decode().strip() == protection['donor_head']
	assert subprocess.check_output(['git', '-C', str(donor), 'status', '--porcelain=v2', '--untracked-files=all']).decode() == protection['donor_status']
	for name, expected in protection['workflow'].items():
		assert sha(name) == expected
	for name, row in protection['hooks'].items():
		assert sha(name) == row['sha256'] and oct(Path(name).stat().st_mode & 0o777) == row['mode']
	assert git('config', '--show-origin', '--list').decode() == old['config']
	proofs = json.loads((WORK/'runtime/indexpath18/historical-proof-outputs.json').read_text())
	assert proofs['count'] == len(proofs['outputs']) == 1044
	assert all(sha(name) == row['sha256'] for name, row in proofs['outputs'].items())
	result = dict(status='PARTIAL', final_commit=git('rev-parse', 'HEAD').decode().strip(), final_tree=git('rev-parse', 'HEAD^{tree}').decode().strip(), original_packet_sha256='43c89a44a04912f3fdefa4f4c73380095874301eea44cb5684ff0406368e2b11', native_submission_sha256=intake['submission_sha256'], R5_post_delivery_G12=dict(status='PASS', receipt=str(g12), sha256=sha(g12)), protection=dict(paths=451, donor_files=6622, historical_proof_hashes=1044), profiles=profiles, whole_original_compiler=whole, whole_source_population_sha256=sha(a.whole_source_result.parent/'population.json'), original_context_C0=dict(receipt=str(c0_path), sha256=sha(c0_path), observation=c0, semantic_qualification=False), limitation='PARTIAL for the entire contracted compiler-complete scope. Bounded 411-program regressions and rebuilt C0-produced hosts do not prove original full compiler source-to-native translation. The original full compiler is actually refused with output preserved. Generic slots, independent root0/slot6 proof, full SSA scaling, linked compiler usage and incremental compiler costs remain unqualified. G12 for this new report is pending actual installed publication and a separate after-delivery check.')
	write(a.output, result)
	print('PARTIAL: whole original compiler refused; bounded current regressions independently rebound', flush=True)


if __name__ == '__main__':
	main()
