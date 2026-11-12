#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Rebind current products and complete regression receipts without narrowing 26."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
from types import SimpleNamespace
import zipfile

from run import BASE, ROOT, WORK, git, sha, write


def r5_delivery(runtime):
	"""Consume the corrected native replay, retaining the earlier provenance gap."""
	prior = WORK/'runtime/compiler26-g12-audit-20261109/final-verdict.json'
	assert sha(prior) == 'd87315df0c6602abd2895897585f2ca0f9fe4a0d1759015e00e30c1f32c5789a'
	leaf = runtime/'g12-frontends-supplement6'
	verdict = leaf/'verdict.json'
	assert sha(verdict) == '47b4ee92bba7f2a75e8b44f4079c3e95e562a55855c0a5aac4d363fa193f5908'
	correction = json.loads(verdict.read_text())
	assert correction['prior_verdict_sha256'] == sha(prior) and correction['prior_verdict_and_raw_receipts_preserved']
	assert correction['canonical_R5_report_sha256'] == '69a1f817f1448ab8eed5cac5db8f6f8e7d262385a9c0b959a8750f573bfeb2a9'
	replay = leaf/'native-replay.json'
	assert sha(replay) == correction['replay_sha256']
	data = json.loads(replay.read_text())
	assert data['status'] == 'PASS' and set(data['profiles']) == {'O0', 'O2'}
	commands = json.loads((leaf/'native-commands.json').read_text())
	assert len({row['name'] for row in commands}) == len(commands)
	for row in commands:
		for stream in ('stdout', 'stderr'): assert sha(leaf/(row['name']+'.'+stream)) == row[stream+'_sha256']
	observed = {row['name']:row for row in commands}
	memory_count = 0
	for mode, profile in data['profiles'].items():
		assert sha(profile['component']) == profile['component_sha256'] and sha(Path(profile['component']).with_suffix('.identity.json')) == profile['component_identity_sha256']
		original = json.loads((WORK/('runtime/effects25-r5-resume/native-frontiers-repair2-'+mode+'/result.json')).read_text())
		original = {row['name']:row for row in original['programs']}
		assert len(profile['programs']) == 4
		for row in profile['programs']:
			name = row['name']; historical = original[name]
			assert row['exit'] == 42 and all(row[key] for key in ('historical_raw_LLVM_equal', 'historical_Astra_ELF_equal', 'historical_C0_ELF_equal'))
			assert row['raw_LLVM_sha256'] == historical['Astra']['raw_LLVM_sha256']
			physical = observed[mode+'-'+name+'-Astra-emit']['argv'][2]
			assert sha(physical) == row['raw_LLVM_sha256']
			for producer in ('C0', 'Astra'):
				label = mode+'-'+name+'-'+producer
				execution, memory = observed[label+'-execute'], observed[label+'-memory']
				assert execution['exit'] == memory['exit'] == 42 and '--default-suppressions=no' in memory['argv']
				assert sha(execution['argv'][0]) == row[producer+'_ELF_sha256'] == historical[producer]['ELF_sha256']
				assert memory['argv'][-1] == execution['argv'][0]
				log = (leaf/(label+'-memory.stderr')).read_bytes()
				assert all(marker in log for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
				memory_count += 1
	assert memory_count == 16 and data['ABI_observer']['exit'] == observed['source-ABI-independent-observer']['exit'] == 42
	return dict(status=correction['status'], receipt=str(verdict), sha256=sha(verdict), prior_receipt=str(prior), prior_sha256=sha(prior), replay=dict(path=str(replay), sha256=sha(replay), native_programs=8, clean_memory_streams=memory_count), limitation=correction['limitation'], chronology='Some milestone26 engineering preceded the corrected frontend supplement. This does not assert that the original pre-edit gate was completely satisfied, relabel the historical report, or qualify milestone26.')


def module_inventory(probe, manifest, scope, output):
	"""Independent object retention check; deliberately grants no final PASS."""
	from accelerate import authenticated_inputs
	from acceleration import output_path
	probe = output_path(probe, WORK/'runtime'); output = output_path(output, WORK/'runtime')
	assert not output.exists()
	inputs = authenticated_inputs(SimpleNamespace(inputs=manifest, scope=scope))
	result = json.loads((probe/'result.json').read_text())
	assert result['status'] == 'JOB_OUTCOMES_MATCHED' and not result['failed_jobs']
	assert len(result['jobs']) == 10
	for name, row in result['jobs'].items():
		assert row['status'] == 'EXPECTED_OUTCOME' and row['exit'] == 0 and not row['timed_out']
		for stream in ('stdout', 'stderr'): assert sha(probe/name/stream) == row[stream+'_sha256']
		assert sha(probe/name/'time') == row['time_sha256']
	stage = json.loads((probe/'native/stages/result.json').read_text())
	assert stage['native_exit'] == stage['debugger_exit'] == 0 and not stage['timed_out']
	observed = (probe/'native/stages/stdout').read_text()
	assert all(marker in observed for marker in ('RECOVER_FLOW 0 0 ', 'RECOVER_SSA_VALID', 'RECOVER_LLVM_WRITTEN'))
	source = json.loads((probe/'source-scope.json').read_text())
	assert source['scope'] == scope and source['input_manifest_sha256'] == sha(manifest) and source['input_count'] == len(inputs)
	command = json.loads((probe/'native/running.json').read_text())['argv']
	component = Path(command[command.index('--host')+1])
	assert sha(component) == source['component_sha256']
	assert command[-len(inputs):] == list(inputs)
	from acceleration import execute
	identity = json.loads(component.with_suffix('.identity.json').read_text())
	toolchain = output.parent/(output.stem+'-toolchain.json')
	verified = execute([sys.executable, '-B', ROOT/'tests/selfhost-compiler-complete/toolchain.py', '--compiler', identity['identity']['argv'][0], '--receipt', toolchain], output.parent/(output.stem+'-tools'), timeout=120)
	assert verified['status'] == 'EXPECTED_OUTCOME'
	def artifact(job, key):
		row = result['jobs'][job]['artifacts'][key]; path = output_path(Path(row['path']), WORK/'build')
		assert sha(path) == row['sha256'] and path.stat().st_size == row['bytes']
		return path, row
	raw, raw_identity = artifact('native', 'raw'); text = raw.read_text()
	used = [line for line in text.splitlines() if line.startswith('@llvm.used =')]
	assert len(used) == 1
	count = int(re.search(r'\[(\d+) x ptr\]', used[0])[1])
	roots = re.findall(r'@(astra\.e25a\.f\.\d+)', used[0])
	assert len(roots) == len(set(roots)) == count
	definitions = re.findall(r'^define .*?@(astra\.e25a\.f\.\d+)\(', text, re.M)
	assert len(definitions) == count and set(definitions) == set(roots)
	raw_verify = execute(['opt', '-passes=verify', '-disable-output', raw], output.parent/(output.stem+'-raw-verify'), timeout=120)
	assert raw_verify['status'] == 'EXPECTED_OUTCOME'
	facts = []
	for mode in ('O0', 'O2'):
		optimized, optimized_identity = artifact(mode+'-optimize', 'optimized')
		obj, identity = artifact(mode+'-object', 'object')
		head = obj.read_bytes()[:64]
		assert head[:6] == b'\x7fELF\x02\x01' and struct.unpack_from('<H', head, 16)[0] == 1 and struct.unpack_from('<H', head, 18)[0] == 62
		symbols = subprocess.check_output(['nm', '--defined-only', '-P', obj], text=True)
		physical = re.findall(r'^(astra\.e25a\.f\.\d+) ([tT]) ', symbols, re.M)
		assert len(physical) == count and {name for name, kind in physical} == set(roots)
		optimized_definitions = re.findall(r'^define .*?@(astra\.e25a\.f\.\d+)\(', optimized.read_text(), re.M)
		assert len(optimized_definitions) == count and set(optimized_definitions) == set(roots)
		verification = execute(['opt', '-passes=verify', '-disable-output', optimized], output.parent/(output.stem+'-'+mode+'-verify'), timeout=120)
		assert verification['status'] == 'EXPECTED_OUTCOME'
		undefined = subprocess.check_output(['nm', '-u', '-P', obj], text=True)
		relocations = subprocess.check_output(['readelf', '-rW', obj], text=True)
		leaf = output.parent/(output.stem+'-'+mode); assert not leaf.exists(); leaf.mkdir()
		for name, data in [('defined-symbols.txt', symbols), ('undefined-symbols.txt', undefined), ('relocations.txt', relocations)]: (leaf/name).write_text(data)
		facts.append(dict(profile=mode, optimized_LLVM=optimized_identity, object=identity, retained_source_functions=count, independent_optimized_verification=verification, inventory={str(p):sha(p) for p in sorted(leaf.iterdir())}, metrics=result['jobs'][mode+'-object']['metrics']))
	write(output, dict(status='FULL_MODULE_SYMBOL_RETENTION_VERIFIED', scope=scope, component_sha256=sha(component), probe_result_sha256=sha(probe/'result.json'), source_manifest_sha256=sha(manifest), input_count=len(inputs), raw_LLVM=raw_identity, independent_raw_verification=raw_verify, toolchain_receipt=dict(path=str(toolchain), sha256=sha(toolchain)), source_functions=count, source_function_names=roots, profiles=facts, tools={str(Path(shutil.which(name)).resolve()):sha(shutil.which(name)) for name in ('nm', 'readelf')}, full_milestone_credit=False, limitation='Actual library root table, raw and optimized function definitions, both ELF symbol sets, undefined symbols and relocation inventories. No final compiler-product, linked ABI, independent graph55, retained-regression or delivery qualification follows from inventory alone.'))
	return count


def complete_source_proofs(runtime, build, output):
	"""Rebind frozen emitters without attributing their results to later hosts."""
	from accelerate import authenticated_inputs
	from run import population
	manifests = dict(original=runtime/'opaque-flow-inputs.json', current=runtime/'current-physicalready3-inputs.json')
	inputs = {scope:authenticated_inputs(SimpleNamespace(inputs=path, scope=scope)) for scope, path in manifests.items()}
	assert len(inputs['original']) == 190 and len(inputs['current']) == 205
	production = {str(ROOT/row['path']):row['sha256'] for row in population()['current_files']}
	assert len(production) == 205
	profiles = {}
	for mode in ('O0', 'O2'):
		host = build/('full-completefinal1-'+mode)/('astra-llvm-'+mode)
		identity = json.loads(host.with_suffix('.identity.json').read_text())
		assert sha(host) == identity['sha256'] and identity['identity']['argv'][1] == '-'+mode
		assert all(sha(path) == digest for path, digest in identity['identity']['tools'].items())
		assert {name:identity['identity']['sources'][name] for name in production} == production
		frozen = []
		for name, digest in identity['identity']['sources'].items():
			if sha(name) == digest: continue
			path = Path(name); assert path.is_relative_to(ROOT)
			relative = str(path.relative_to(ROOT))
			assert relative in ('tests/selfhost-effects/recover-frontier-mutations.astra', 'tests/selfhost-effects/recover-r4-observe.astra')
			raw = git('show', 'bfc3630284fd29927f470a06bb00884c7fbdb49b:'+relative)
			assert __import__('hashlib').sha256(raw).hexdigest() == digest
			frozen.append(dict(path=name, sha256=digest, authenticated_Git_revision='bfc3630284fd29927f470a06bb00884c7fbdb49b', role='Frozen test observer; not the corrected regression host or a changed production translator.'))
		observer = build/('full-observerrepair1-'+mode)/('astra-llvm-'+mode)
		updated = json.loads(observer.with_suffix('.identity.json').read_text())
		assert sha(observer) == updated['sha256']
		assert {name:updated['identity']['sources'][name] for name in production} == production
		rows = {}
		for scope, manifest in manifests.items():
			probe = runtime/('native-probe-complete'+scope+mode)
			where = output.parent/(output.stem+'-'+scope+'-'+mode+'.json')
			count = module_inventory(probe, manifest, scope, where)
			inventory = json.loads(where.read_text()); assert inventory['component_sha256'] == sha(host)
			text = Path(inventory['raw_LLVM']['path']).read_text()
			blocks = {}; function = None; size = 0
			for line in text.splitlines():
				match = re.match(r'^define .*?@(astra\.e25a\.f\.\d+)\(', line)
				if match: function = match[1]; size = 0
				elif function and line.startswith('}'):
					blocks[function] = size; function = None
				elif function and re.match(r'^(?:[-a-zA-Z$._0-9]+|"[^\"]+"):\s*(?:;.*)?$', line): size += 1
			assert len(blocks) == count and min(blocks.values()) > 0
			rows[scope] = dict(inventory=str(where), sha256=sha(where), source_functions=count, raw_LLVM=inventory['raw_LLVM'], maximum_actual_raw_LLVM_blocks=max(blocks.values()), source_functions_over_1024_blocks=sum(n > 1024 for n in blocks.values()), block_count_scope='Actual source-function LLVM blocks; CFG/SSA capacity and corruption controls are separately qualified.')
		profiles[mode] = dict(component=str(host), component_sha256=sha(host), identity_sha256=sha(host.with_suffix('.identity.json')), frozen_observer_sources=frozen, corrected_observer_component=str(observer), corrected_observer_sha256=sha(observer), production_source_hashes=production, proofs=rows)
	for scope in manifests:
		assert profiles['O0']['proofs'][scope]['raw_LLVM']['sha256'] == profiles['O2']['proofs'][scope]['raw_LLVM']['sha256']
	semantics = runtime/'original-C0-final-semantics1'; result = json.loads((semantics/'result.json').read_text())
	assert result['exit'] == 0 and not result['timed_out']
	command = json.loads((semantics/'running.json').read_text())['argv']
	assert command[1] == '--dump-semantics' and command[2:] == list(inputs['original'])
	assert sha(command[0]) == 'e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b'
	for stream in ('stdout', 'stderr', 'time'): assert sha(semantics/stream) == result[stream+'_sha256']
	value = dict(status='ORIGINAL_AND_CURRENT_FULL_SOURCE_PROOFS_INDEPENDENTLY_REBOUND', profiles=profiles, input_manifests={scope:dict(path=str(path), sha256=sha(path)) for scope, path in manifests.items()}, original_C0_semantics=dict(path=str(semantics/'result.json'), sha256=sha(semantics/'result.json')), full_milestone_credit=False, limitation='Actual complete original/current source outputs from each frozen O0/O2 emitter, independently verified through both target object profiles. Corrected regression hosts share byte-exact production inputs; their test-only changes are explicitly distinct. This does not transfer execution credit between compiler products or qualify graph55, resource boundaries, representative usage, costs, preservation or publication/G12 by itself.')
	assert not output.exists(); write(output, value)
	return value


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
	g12 = r5_delivery(a.runtime_root)
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
	result = dict(status='PARTIAL', final_commit=git('rev-parse', 'HEAD').decode().strip(), final_tree=git('rev-parse', 'HEAD^{tree}').decode().strip(), original_packet_sha256='43c89a44a04912f3fdefa4f4c73380095874301eea44cb5684ff0406368e2b11', native_submission_sha256=intake['submission_sha256'], R5_post_delivery_G12=g12, protection=dict(paths=451, donor_files=6622, historical_proof_hashes=1044), profiles=profiles, whole_original_compiler=whole, whole_source_population_sha256=sha(a.whole_source_result.parent/'population.json'), original_context_C0=dict(receipt=str(c0_path), sha256=sha(c0_path), observation=c0, semantic_qualification=False), limitation='PARTIAL for the entire contracted compiler-complete scope. Bounded 411-program regressions and rebuilt C0-produced hosts do not prove original full compiler source-to-native translation. The original full compiler is actually refused with output preserved. Generic slots, independent root0/slot6 proof, full SSA scaling, linked compiler usage and incremental compiler costs remain unqualified. G12 for this new report is pending actual installed publication and a separate after-delivery check.')
	write(a.output, result)
	print('PARTIAL: whole original compiler refused; bounded current regressions independently rebound', flush=True)


if __name__ == '__main__':
	main()
