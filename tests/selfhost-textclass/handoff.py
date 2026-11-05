#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Require all scoped gates before packaging lossless publisher evidence."""
import argparse
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import time

ROOT = Path(__file__).resolve().parents[2]
BASE = 'ce7793ca133502baa73c00cd3fbbf4b8d143fd75'
OLD_GATES = ('new', 'inherited', 'Class', 'mutations', 'negative', 'focused', 'continuity', 'layout', 'retirement', 'failure')
NEW_GATES = ('new', 'mutations', 'negative', 'bounds', 'retirement', 'allocation', 'reserve', 'layout', 'adapter')


def sha(path):
	with Path(path).open('rb') as stream: return hashlib.file_digest(stream, 'sha256').hexdigest()


def read(path):
	return json.loads(Path(path).read_text())


def main():
	p = argparse.ArgumentParser()
	for name in ('runtime', 'build', 'qualification', 'predecessor-qualification', 'output'): p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--source-version', required=True, help='Exact final immutable implementation snapshot, e.g. source-v9')
	p.add_argument('--ledger-version', required=True, help='Exact final ledger leaf prefix, e.g. ledger-v9')
	p.add_argument('--live-ledger', type=Path, required=True, help='Separate exact final live-population ledger')
	p.add_argument('--correspondence', type=Path, required=True, help='Exact final committed source/product correspondence receipt')
	a = p.parse_args(); assert a.output.resolve().is_relative_to(a.runtime.resolve())
	assert subprocess.check_output(['git', 'status', '--porcelain=v1', '--untracked-files=all']) == b''
	assert subprocess.run(['git', 'merge-base', '--is-ancestor', BASE, 'HEAD']).returncode == 0
	assert read(a.runtime/'preservation-final.json')['status'] == 'PASS'
	assert read(a.runtime/'preservation-final.json')['tracked_status'] == ''
	historical = read(a.runtime/'historical-preservation.json'); assert historical['status'] == 'PRESERVED_HISTORICAL_NOT_FRESH_EXECUTION' and historical['original_proof_observations'] == 1044
	proof_products = read(a.runtime/'history-audit-final/result.json'); assert proof_products['status'] == 'PRESERVED_IDENTITY_BOUND_HISTORICAL' and proof_products['observations'] == 1044
	profiles = {}; receipts = {}
	for mode in ('O0', 'O2'):
		gates = {}
		for root, names, family in ((a.qualification, NEW_GATES, 'textclass'), (a.predecessor_qualification, OLD_GATES, 'predecessor')):
			for name in names:
				path = root/(name+'-'+mode)/'result.json'; data = read(path)
				assert data['status'] == 'PASS' and data['mode'] == mode
				gates[family+'/'+name] = data; receipts[str(path)] = sha(path)
		assert len({gate['component_sha256'] for gate in gates.values()}) == 1
		old = read(a.predecessor_qualification/('inherited-'+mode)/'observations/result.json')['profiles'][mode]
		classes = read(a.predecessor_qualification/('Class-'+mode)/'observations/results.json')
		genclass = read(a.predecessor_qualification/('new-'+mode)/'observations/results.json')
		new = read(a.qualification/('new-'+mode)/'observations/results.json')
		assert (len(old), len(classes), len(genclass)) == (52, 23, 15) and len(new) >= 16
		assert all(row['baseline_complete'] for row in classes+genclass+new)
		text_bags = []
		for row in new:
			projection = a.qualification/('new-'+mode)/'observations'/(row['name']+'-ssa.stdout')
			if any(line.startswith('FUNCTION ') and bytes.fromhex(line.split()[-3]).decode() == str(ROOT/'lib/astra/collections/bag.astra') for line in projection.read_text().splitlines()): text_bags.append(row['name'])
		assert len(text_bags) >= 5
		identities = [tuple(source['sha256'] for source in row['sources']) for row in old+classes+genclass+new]
		assert len(identities) == len(set(identities))
		for row in old+classes+genclass+new:
			assert all(sha(source['path']) == source['sha256'] for source in row['sources'])
			assert all(sha(product['path']) == product['sha256'] for product in row['products'].values())
		mutations = read(gates['textclass/mutations']['receipts'][0]['path'])
		assert mutations['distinct_categories'] == 24 and sum(row.get('LLVM_verifier_accepts_mutant', False) for row in mutations['observations']) == 8
		witness = read(a.runtime/('source-witness-'+mode+'.json')); assert witness['status'] == 'PASS' and witness['component_sha256'] == gates['textclass/new']['component_sha256']
		statuses = read(a.predecessor_qualification/('continuity-'+mode)/'observations/result.json')['outcomes']; assert sum(statuses.values()) == 80
		profiles[mode] = dict(inherited=52, Class=19, late_Class_observers=4, GenClass=15, new_textclass=len(new), substantive_text_owner_Bag_programs=text_bags, distinct_native_programs=len(identities), source_identities=identities, component_sha256=gates['textclass/new']['component_sha256'], new_mutants=24, LLVM_valid_new_physical_mutants=8, original_statuses=statuses)
	assert profiles['O0']['source_identities'] == profiles['O2']['source_identities']
	for name in ('original', 'LLVM23-base', 'Class15-current', 'live-initial'):
		data = read(a.runtime/('comparison-final-'+name+'.json')); assert data['status'] == 'EXACT_COHORT_CHECKED_STOP_ADVANCED'
		assert data['after']['typed'] > data['before']['typed']
	assert a.live_ledger.resolve().is_relative_to(a.runtime.resolve()) and read(a.live_ledger)['diagnostics'], 'final live source must retain honest disposition'
	correspondence = read(a.correspondence)
	assert correspondence['status'] == 'PASS' and correspondence['final_head'] == subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip() and correspondence['final_tree'] == subprocess.check_output(['git', 'rev-parse', 'HEAD^{tree}'], text=True).strip()
	a.output.mkdir(parents=True, exist_ok=False)
	model = dict(format='astra-textclass-handoff/1', storage_format='astra-line-chunk/1', status='PASS', final_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(), final_tree=subprocess.check_output(['git', 'rev-parse', 'HEAD^{tree}'], text=True).strip(), profiles=profiles, gate_receipts=receipts, historical_proof_outputs=1044, evidence_classification='Current native/model/physical gates are fresh. Historical proof outputs are hash-preserved under original source/tool/flag/dependency identities.', omissions=[], files=[])
	files, blobs = {}, {}
	final_ledgers = {a.ledger_version+'-'+name for name in ('original', 'LLVM23-base', 'Class15-current', 'live-initial')} | {a.live_ledger.parent.name}
	def collect(root, prefix, task=False):
		for path in sorted(root.rglob('*')):
			if path.is_dir(): continue
			assert path.is_file() and not path.is_symlink(), str(path)
			if path.is_relative_to(a.output): continue
			relative = path.relative_to(root); name = prefix+'/'+str(relative)
			if task and relative.parts[0].startswith('handoff'): continue
			redundant_ledger = task and relative.parts[0].startswith('ledger-') and relative.parts[0] not in final_ledgers and path.name in ('ledger.json', 'whole-compiler.stdout')
			old_binary = prefix == 'task-build' and path.name.startswith(('astra-llvm-', 'astra-ledger-')) and path.suffix == '' and ('native-'+a.source_version.removeprefix('source-')+'-' not in relative.parts[0] and relative.parts[0] != a.ledger_version)
			if path.suffix == '.zip' or redundant_ledger or old_binary:
				model['omissions'].append(dict(path=name, bytes=path.stat().st_size, sha256=sha(path), reason='Exact predecessor report remains preserved in intake; its full manifest and required historical proof inputs/outputs are embedded. Superseded ledger/product bytes remain in their original leaves; final observations/products and every failure receipt/source snapshot are embedded.'))
			else: files[name] = path
	collect(a.runtime, 'task-runtime', True); collect(a.build, 'task-build')
	proof = ROOT.parent/'codex/work/astra/runtime/classstorage15/resume-llvm23-v1/final-proof-replay-v2'; collect(proof, 'historical/proof')
	for product in proof_products['products']:
		path = Path(product['path']); sidecar = Path(product['identity_path'])
		assert sha(path) == product['sha256'] and sha(sidecar) == product['identity_sha256']
		files['historical/proof-products/'+path.parent.name+'/'+path.name] = path
		files['historical/proof-products/'+path.parent.name+'/'+sidecar.name] = sidecar
		for source, expected in read(sidecar)['identity']['sources'].items():
			source = Path(source)
			if str(source) in proof_products['original_Git_blobs']: continue
			if source.suffix in ('.astra', '.c', '.h', '.py', '.json'):
				assert sha(source) == expected; files['historical/proof-sources/'+expected+'/'+source.name] = source
	for path, expected in read(proof/'inputs.json').items():
		path = Path(path); name = 'historical/proof-inputs/'+expected+'/'+path.name
		if sha(path) == expected: files[name] = path
		else:
			mapping = historical['historical_live_path_reconciliation'][str(path)]
			raw = subprocess.check_output(['git', 'show', mapping['historical_commit']+':'+str(path.relative_to(ROOT))]); assert hashlib.sha256(raw).hexdigest() == expected; blobs[name] = raw
			# Preserve exact frozen populations and external application inputs.
	for cohort in read(a.runtime/'intake-v3/result.json')['cohorts'].values():
		for path, row in cohort['inputs'].items():
			path = Path(path); name = 'historical/cohorts/'+row['sha256']+'/'+path.name
			if sha(path) == row['sha256']: files[name] = path
			else:
				raw = subprocess.check_output(['git', 'show', BASE+':'+str(path.relative_to(ROOT))]); assert hashlib.sha256(raw).hexdigest() == row['sha256']; blobs[name] = raw
	for mode in ('O0', 'O2'):
		for family, key in (('inherited', 'result.json'), ('Class', 'results.json'), ('new', 'results.json')):
			rows = read(a.predecessor_qualification/(family+'-'+mode)/'observations'/key)
			if family == 'inherited': rows = rows['profiles'][mode]
			for row in rows:
				for source in row['sources']: files['historical/programs/'+source['sha256']+'/'+Path(source['path']).name] = Path(source['path'])
	for path in sorted((ROOT/'tools/qualification').glob('*.py')): files['recipes/tools/qualification/'+path.name] = path
	files['recipes/transport.py'] = ROOT/'tests/selfhost-genclass/transport.py'
	files['recipes/encoded-evidence.py'] = ROOT/'tools/qualification/encoded-evidence.py'
	files['recipes/tests/ecosystem-abi-8/layout-lifetime-guard.c'] = ROOT/'tests/ecosystem-abi-8/layout-lifetime-guard.c'
	spec = importlib.util.spec_from_file_location('transport', files['recipes/transport.py']); transport = importlib.util.module_from_spec(spec); spec.loader.exec_module(transport)
	archive = a.output/'textclass17-evidence.tar.xz'; started = time.monotonic()
	with tarfile.open(archive, 'w:xz', preset=6) as tar:
		writer = transport.ChunkWriter(tar)
		for name in sorted(set(files)|set(blobs)):
			path, raw = files.get(name), blobs.get(name); digest = sha(path) if path else hashlib.sha256(raw).hexdigest(); mode = path.stat().st_mode & 0o777 if path else 0o644
			model['files'].append(writer.add(name, path, raw, mode, digest))
		index = (json.dumps(model, indent=2)+'\n').encode(); entry = tarfile.TarInfo('ARCHIVE-INDEX.json'); entry.size = len(index); entry.mode = 0o644; tar.addfile(entry, io.BytesIO(index))
	model.update(archive_bytes=archive.stat().st_size, archive_sha256=sha(archive), packaging_seconds=time.monotonic()-started)
	(a.output/'handoff.json').write_text(json.dumps(model, indent=2)+'\n')
	summary = {key:value for key,value in model.items() if key != 'files'}; summary.update(archive_index_sha256=hashlib.sha256(index).hexdigest(), indexed_files=len(model['files']))
	(a.output/'handoff-summary.json').write_text(json.dumps(summary, indent=2)+'\n')
	verified = transport.verify(archive); assert verified['final_commit'] == model['final_commit'] and verified['final_tree'] == model['final_tree']
	(a.output/'transport-verification.json').write_text(json.dumps(verified, indent=2)+'\n')
	subprocess.run([sys.executable, '-B', ROOT/'tools/qualification/encoded-evidence.py', 'pack', '--input', archive, '--output', a.output, '--stem', 'textclass17'], check=True)
	print('All gates verified:', profiles['O0']['distinct_native_programs'], 'distinct native programs per profile; lossless evidence bytes', archive.stat().st_size)


if __name__ == '__main__':
	main()
