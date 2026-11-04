#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Verify focused gates and assemble lossless evidence for the installed publisher."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import time

from transport import ChunkWriter

ROOT = Path(__file__).resolve().parents[2]
BASE = 'd18ad0d5afa8896bb1389813a8601febf913a9c6'
GATES = ('new', 'inherited', 'Class', 'mutations', 'negative', 'focused', 'continuity', 'layout', 'retirement', 'failure')


def sha(path):
	with Path(path).open('rb') as stream: return hashlib.file_digest(stream, 'sha256').hexdigest()


def read(path):
	return json.loads(Path(path).read_text())


def main():
	p = argparse.ArgumentParser()
	for name in ('runtime', 'build', 'qualification', 'historical', 'output'):
		p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--development-supplement', type=Path, help='Preserved comprehensive archive; current acceptance evidence remains embedded')
	a = p.parse_args()
	assert a.output.resolve().is_relative_to(a.runtime.resolve())
	assert subprocess.check_output(['git', 'status', '--porcelain=v1', '--untracked-files=all']) == b''
	profiles = {}
	for mode in ('O0', 'O2'):
		gates = {name:read(a.qualification/(name+'-'+mode)/'result.json') for name in GATES}
		assert all(row['status'] == 'PASS' and row['mode'] == mode for row in gates.values())
		assert len({row['component_sha256'] for row in gates.values()}) == 1
		old = read(a.qualification/('inherited-'+mode)/'observations/result.json')['profiles'][mode]
		classes = read(a.qualification/('Class-'+mode)/'observations/results.json')
		new = read(a.qualification/('new-'+mode)/'observations/results.json')
		assert len(old) == 52 and len(classes) == 23 and len(new) >= 12
		assert all(row['baseline_complete'] for row in classes+new)
		identities = [tuple(source['sha256'] for source in row['sources']) for row in old+classes+new]
		assert len(set(identities)) == len(identities)
		for row in old+classes+new:
			assert all(sha(source['path']) == source['sha256'] for source in row['sources'])
			assert all(sha(product['path']) == product['sha256'] for product in row['products'].values())
		mutations = read(a.qualification/('mutations-'+mode)/'observations/result.json')
		assert mutations['distinct_categories'] >= 20 and sum(row.get('LLVM_verifier_accepts_mutant', False) for row in mutations['observations']) == 6
		profiles[mode] = dict(inherited=52, frozen_Class=19, late_observers=4, new=len(new), distinct=len(identities), source_identities=identities, component_sha256=gates['new']['component_sha256'])
	assert profiles['O0']['source_identities'] == profiles['O2']['source_identities']
	assert read(a.runtime/'proof-reuse-product-reconciled.json')['status'] == 'PRESERVED_IDENTITY_BOUND_HISTORICAL'
	assert read(a.runtime/'preservation-v1.json')['status'] == 'PASS'
	a.output.mkdir(parents=True, exist_ok=False)
	model = dict(format='astra-genclass-handoff/1', final_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(), final_tree=subprocess.check_output(['git', 'rev-parse', 'HEAD^{tree}'], text=True).strip(), profiles=profiles, omissions=[], files=[])
	if a.development_supplement:
		model['optional_development_supplement'] = dict(path=str(a.development_supplement), bytes=a.development_supplement.stat().st_size, sha256=sha(a.development_supplement), purpose='Additional superseded development products and observations; all current acceptance gates, required source cohorts and reused proof observations are embedded in this archive.')
	files, blobs = {}, {}
	current_runtime = {'intake', 'predecessor-report-identity', 'frozen-v1', 'frozen-supplemental-v1', 'source-v10', 'source-v12', 'ledger-before', 'ledger-final-original', 'ledger-final-LLVM23-base', 'ledger-final-Class15-current', 'ledger-final-live-committed', 'qualification-final', 'native-v9-O0', 'native-v9-O2', 'warm-v9-O0', 'warm-v9-O2'}
	current_build = {'native-v9-O0', 'native-v9-O2', 'ledger-v10', 'qualification-final', 'frozen-v1', 'frozen-supplemental-v1'}
	def collect(root, prefix):
		for path in sorted(root.rglob('*')):
			if path.is_dir(): continue
			assert path.is_file() and not path.is_symlink(), str(path)
			if path.is_relative_to(a.output): continue
			relative = path.relative_to(root); name = prefix+'/'+str(relative)
			if prefix == 'task-runtime' and len(relative.parts) > 1 and relative.parts[0].startswith('handoff'): continue
			if prefix == 'task-runtime' and relative.parts[0] == 'transport-pilot' and relative != Path('transport-pilot/result.json'): continue
			development = prefix == 'task-runtime' and len(relative.parts) > 1 and relative.parts[0] not in current_runtime
			keep_failure = path.suffix in {'.stderr', '.time', '.json', '.astra'} or path.suffix == '.stdout' and path.stat().st_size <= 65536
			old_build = prefix == 'task-build' and relative.parts[0] not in current_build and not path.name.endswith('.identity.json')
			if a.development_supplement and (development and not keep_failure or old_build):
				model['omissions'].append(dict(path=name, bytes=path.stat().st_size, sha256=sha(path), reason='Superseded development artifact remains in its original leaf; the named optional supplement preserves earlier development data. Current acceptance data are embedded.'))
				continue
			redundant_ledger = prefix == 'task-runtime' and path.name == 'ledger.json' and (relative.parts[0].startswith('ledger-after-') or relative.parts[0] == 'ledger-final-live')
			old_product = prefix == 'task-build' and path.name.startswith(('astra-llvm-', 'astra-class-storage-')) and path.suffix == '' and not relative.parts[0].startswith('native-v9-')
			if redundant_ledger or old_product:
				model['omissions'].append(dict(path=name, bytes=path.stat().st_size, sha256=sha(path), reason='Superseded development artifact remains intact in its original leaf. Final equivalent observer data or compiler products, source snapshots, failure receipts and original identity sidecars are embedded.'))
				continue
			if path.suffix == '.zip':
				model['omissions'].append(dict(path=name, bytes=path.stat().st_size, sha256=sha(path), reason='Exact predecessor ZIP preserved separately; its manifest and required historical proof subset are embedded.'))
			else: files[name] = path
	collect(a.runtime, 'task-runtime'); collect(a.build, 'task-build')
	proof = a.historical/'final-proof-replay-v2'; collect(proof, 'historical/proof')
	# Reused consumers retain their original source identity. Changed then-live
	# paths are recovered from Git, never relabelled as the current source.
	inputs = read(proof/'inputs.json')
	for product in read(a.runtime/'proof-reuse-product-reconciled.json')['products']:
		path = Path(product['path']); sidecar = path.with_suffix('.identity.json')
		if a.development_supplement:
			model['omissions'].append(dict(path=str(path), bytes=path.stat().st_size, sha256=sha(path), reason='Audited historical proof tool; full source/flag/dependency sidecars and raw observations are embedded. Original executable also remains in the optional supplement and its original build leaf.'))
		else: files['historical/proof-products/'+path.parent.name+'/'+path.name] = path
		files['historical/proof-products/'+path.parent.name+'/'+sidecar.name] = sidecar
		inputs.update(read(sidecar)['identity']['sources'])
	for path, expected in sorted(inputs.items()):
		path = Path(path); name = 'historical/inputs/'+expected+'/'+path.name
		if sha(path) == expected: files[name] = path
		else:
			assert path.is_relative_to(ROOT), str(path)
			raw = subprocess.check_output(['git', 'show', BASE+':'+str(path.relative_to(ROOT))]); assert hashlib.sha256(raw).hexdigest() == expected
			blobs[name] = raw
		model['files'].append(dict(original_path=str(path), archive_path=name, sha256=expected, role='original reused proof input'))
		# Preserve the exact frozen compiler populations and executable source inputs.
	for relative in ('ledger-final-original/inputs.json', 'ledger-final-LLVM23-base/inputs.json', 'ledger-final-Class15-current/inputs.json'):
		for path, row in read(a.runtime/relative).items():
			assert sha(path) == row['sha256']; files['historical/cohorts/'+row['sha256']+'/'+Path(path).name] = Path(path)
	for mode in ('O0', 'O2'):
		for family in ('inherited', 'Class'):
			path = a.qualification/(family+'-'+mode)/'observations'
			rows = read(path/('result.json' if family == 'inherited' else 'results.json'))
			if family == 'inherited': rows = rows['profiles'][mode]
			for row in rows:
				for source in row['sources']: files['historical/programs/'+source['sha256']+'/'+Path(source['path']).name] = Path(source['path'])
	archive = a.output/'genclass16-evidence.tar.xz'; started = time.monotonic(); model['storage_format'] = 'astra-line-chunk/1'
	with tarfile.open(archive, 'w:xz', preset=9) as tar:
		writer = ChunkWriter(tar)
		for name in sorted(set(files)|set(blobs)):
			path = files.get(name); raw = blobs.get(name); digest = sha(path) if path else hashlib.sha256(raw).hexdigest(); mode = path.stat().st_mode & 0o777 if path else 0o644
			model['files'].append(writer.add(name, path, raw, mode, digest))
		index = (json.dumps(model, indent=2)+'\n').encode(); entry = tarfile.TarInfo('ARCHIVE-INDEX.json'); entry.size = len(index); entry.mode = 0o644; tar.addfile(entry, io.BytesIO(index))
	model.update(archive_bytes=archive.stat().st_size, archive_sha256=sha(archive), packaging_seconds=time.monotonic()-started)
	(a.output/'handoff.json').write_text(json.dumps(model, indent=2)+'\n')
	summary = {key:value for key, value in model.items() if key != 'files'}; summary.update(archive_index_sha256=hashlib.sha256(index).hexdigest(), indexed_records=len(model['files']))
	(a.output/'handoff-summary.json').write_text(json.dumps(summary, indent=2)+'\n')
	subprocess.run([sys.executable, '-B', ROOT/'tools/qualification/encoded-evidence.py', 'pack', '--input', archive, '--output', a.output, '--stem', 'genclass16'], check=True)
	print('Verified', profiles['O0']['distinct'], 'distinct native identities per profile; lossless evidence', model['archive_bytes'], 'bytes')


if __name__ == '__main__':
	main()
