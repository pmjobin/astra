#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Package lossless, identity-checked evidence for the unchanged native publisher."""
import argparse
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import time
import zipfile
from state import ROOT, RUNTIME, BUILD, PRIOR, BASE, read, sha, git


def main():
	p = argparse.ArgumentParser(); p.add_argument('--output', type=Path, required=True); a = p.parse_args()
	assert a.output.resolve().is_relative_to(RUNTIME) and git('status', '--porcelain=v1', '--untracked-files=all') == ''
	engineering = read(RUNTIME/'engineering-summary.json'); assert engineering['status'] == 'ENGINEERING_GATES_COMPLETE_PUBLICATION_PENDING'
	correspondence = read(RUNTIME/'source-product-correspondence.json'); preservation = read(RUNTIME/'preservation-final.json')
	head = git('rev-parse', 'HEAD').strip(); tree = git('rev-parse', 'HEAD^{tree}').strip()
	assert correspondence['status'] == preservation['status'] == 'PASS' and correspondence['final_head'] == preservation['head'] == head and correspondence['final_tree'] == preservation['tree'] == tree
	assert preservation['clean_required'] and preservation['tracked_and_untracked_status'] == ''
	a.output.mkdir(exist_ok=False); files = {}; blobs = {}; omitted = []
	def collect(root, prefix):
		for path in sorted(root.rglob('*')):
			if path.is_dir(): continue
			assert path.is_file() and not path.is_symlink(), path
			if path.is_relative_to(a.output): continue
			rel = path.relative_to(root)
			if prefix == 'task-runtime' and rel.parts[0].startswith('handoff'): continue
			name = prefix+'/'+str(rel)
			if path.suffix == '.zip':
				omitted.append(dict(path=name, bytes=path.stat().st_size, sha256=sha(path), reason='Original report remains immutable at its verified external path; do not duplicate an already compressed predecessor ZIP inside the bounded current report.')); continue
			files[name] = path
	collect(RUNTIME, 'task-runtime'); collect(BUILD, 'task-build')
	# Original proof outputs retain their old command and product identities.
	proof = PRIOR.parent/'classstorage15/resume-llvm23-v1/final-proof-replay-v2'; collect(proof, 'historical/proofs')
	products = read(PRIOR/'history-audit/result.json')
	for row in products['products']:
		for key in ('path', 'identity_path'):
			path = Path(row[key]); files['historical/proof-products/'+path.parent.name+'/'+path.name] = path
	for path, expected in read(proof/'inputs.json').items():
		path = Path(path); name = 'historical/proof-inputs/'+expected+'/'+path.name
		if sha(path) == expected: files[name] = path; continue
		assert path.is_relative_to(ROOT)
		mapping = products['original_Git_blobs'].get(str(path))
		candidates = [mapping['historical_commit']] if mapping else [BASE, 'ce7793ca133502baa73c00cd3fbbf4b8d143fd75']
		for commit in candidates:
			r = subprocess.run(['git', 'show', commit+':'+str(path.relative_to(ROOT))], cwd=ROOT, capture_output=True)
			if r.returncode == 0 and hashlib.sha256(r.stdout).hexdigest() == expected: blobs[name] = r.stdout; break
		else: raise AssertionError(('historical input unavailable', path, expected))
		# Exact frozen compiler populations and exact application inputs are portable
		# evidence; donor source is never collected or packaged.
	for cohort in read(RUNTIME/'initial/result.json')['cohorts'].values():
		for value in read(cohort['ledger'])['files']:
			if 'synthetic_source_hex' in value: continue
			path = Path(value['path']); assert sha(path) == value['sha256']; files['historical/cohorts/'+value['sha256']+'/'+path.name] = path
	for mode in ('O0', 'O2'):
		for row in engineering['profiles'][mode]['programs']:
			for source in row['sources']:
				assert sha(source['path']) == source['sha256']; files['program-inputs/'+source['sha256']+'/'+Path(source['path']).name] = Path(source['path'])
	for path in sorted((ROOT/'tools/qualification').glob('*.py')): files['recipes/tools/qualification/'+path.name] = path
	for directory in sorted((ROOT/'tests').glob('selfhost-*')):
		for path in sorted(directory.glob('*.py')): files['recipes/tests/'+directory.name+'/'+path.name] = path
	for name in ('AGENTS.md', 'CODING_STYLE.md', 'codex-project.json', 'format/scope.json', 'format/toolchain.json'):
		files['final-policy/'+name] = ROOT/name
	stage = RUNTIME.parent/'native-current'
	files['historical/history-audit.json'] = PRIOR/'history-audit/result.json'; files['historical/proof-output-inventory.json'] = PRIOR/'historical-proof-outputs.json'
	collect(stage/'input', 'submission/input'); files['submission/intake-before-publication.json'] = stage/'pm-next-intake.json'
	archive = Path(read(stage/'pm-next-intake.json')['submission_path'])
	with zipfile.ZipFile(archive) as z: blobs['submission/MANIFEST.json'] = z.read('MANIFEST.json')
	# JSON node rows are derived deterministically from the preserved raw native
	# observations. Reconstruct and hash every original byte before packaging.
	plan = dict(format='astra-lossless-derived-ledgers/1', final_commit=head, final_tree=tree, files=[])
	metadata_root = a.output/'derived-ledgers/metadata'; metadata_root.mkdir(parents=True)
	for name in ('original', 'LLVM23-base', 'Class15-current', 'live-initial'):
		files['historical/ledger-before-'+name+'.json'] = PRIOR/('ledger-v5-'+name)/'ledger.json'
	for logical, path in list(files.items()):
		if path.name != 'ledger.json': continue
		data = read(path)
		if data.get('format') != 'astra-whole-source-ledger/1': continue
		if logical.startswith('historical/ledger-before-'):
			name = logical.removeprefix('historical/ledger-before-').removesuffix('.json'); raw_name = 'task-runtime/initial/'+name+'.stdout'
		else: raw_name = str(Path(logical).with_name('whole-compiler.stdout'))
		assert raw_name in files
		metadata = dict(data); metadata['nodes'] = None; name = hashlib.sha256(logical.encode()).hexdigest()[:20]+'.json'; target = metadata_root/name
		target.write_text(json.dumps(metadata, indent=2)+'\n'); files['derived-ledgers/metadata/'+name] = target
		plan['files'].append(dict(path=logical, bytes=path.stat().st_size, mode=path.stat().st_mode & 0o777, sha256=sha(path), raw=raw_name, raw_sha256=sha(files[raw_name]), metadata='metadata/'+name, metadata_sha256=sha(target)))
		del files[logical]
	plan_path = a.output/'derived-ledgers/restore-plan.json'; plan_path.write_text(json.dumps(plan, indent=2)+'\n')
	decoder = ROOT/'tests/selfhost-textclass/derived-ledgers.py'; reconstruction = a.output/'ledger-reconstruction-verification.json'
	subprocess.run([sys.executable, '-B', decoder, a.output, '--plan', plan_path, '--original-runtime', RUNTIME, '--verify-only', '--receipt', reconstruction], check=True)
	files['derived-ledgers/restore-plan.json'] = plan_path; files['derived-ledgers/reconstruction-verification.json'] = reconstruction; files['recipes/restore-ledgers.py'] = decoder
	transport_path = ROOT/'tests/selfhost-genclass/transport.py'; files['recipes/transport.py'] = transport_path
	spec = importlib.util.spec_from_file_location('transport', transport_path); transport = importlib.util.module_from_spec(spec); spec.loader.exec_module(transport)
	model = dict(format='astra-ownexchange-handoff/1', storage_format='astra-line-chunk/1', status='SCOPED_ENGINEERING_PASS_PUBLICATION_PENDING', final_commit=head, final_tree=tree, initial_commit=BASE, profiles={mode: {k: v for k, v in data.items() if k != 'programs'} for mode, data in engineering['profiles'].items()}, limits=engineering['limits'], omissions=omitted, files=[])
	packed = a.output/'ownexchange19-evidence.tar.xz'; started = time.monotonic()
	with tarfile.open(packed, 'w:xz', preset=6) as tar:
		writer = transport.ChunkWriter(tar)
		for name in sorted(set(files)|set(blobs)):
			path, raw = files.get(name), blobs.get(name); digest = sha(path) if path else hashlib.sha256(raw).hexdigest(); mode = path.stat().st_mode & 0o777 if path else 0o644
			model['files'].append(writer.add(name, path, raw, mode, digest))
		index = (json.dumps(model, indent=2)+'\n').encode(); entry = tarfile.TarInfo('ARCHIVE-INDEX.json'); entry.size = len(index); entry.mode = 0o644; tar.addfile(entry, io.BytesIO(index))
	verified = transport.verify(packed); assert verified['final_commit'] == head and verified['final_tree'] == tree
	(a.output/'transport-verification.json').write_text(json.dumps(verified, indent=2)+'\n')
	(a.output/'handoff-summary.json').write_text(json.dumps(dict(format=model['format'], final_commit=head, final_tree=tree, profiles={mode: {k: v for k, v in data.items() if k != 'programs'} for mode, data in engineering['profiles'].items()}, limits=model['limits'], logical_files=len(model['files']), archive_bytes=packed.stat().st_size, archive_sha256=sha(packed), archive_index_sha256=hashlib.sha256(index).hexdigest(), omissions=omitted, packaging_seconds=time.monotonic()-started), indent=2)+'\n')
	subprocess.run([sys.executable, '-B', ROOT/'tools/qualification/encoded-evidence.py', 'pack', '--input', packed, '--output', a.output, '--stem', 'ownexchange19'], check=True)
	# A small review index sits outside the lossless transport for quick review.
	for name in ('engineering-summary.json', 'source-product-correspondence.json', 'preservation-final.json', 'measured-costs.json', 'source-witness-O0.json', 'source-witness-O2.json', 'review-guide.txt'):
		shutil.copy2(RUNTIME/name, a.output/name)
	for source, name in [(transport_path, 'transport.py.txt'), (decoder, 'restore-ledgers.py.txt'), (ROOT/'tools/qualification/encoded-evidence.py', 'encoded-evidence.py.txt')]: shutil.copy2(source, a.output/name)
	selected = [path for path in sorted(a.output.iterdir()) if path.suffix in ('.json', '.txt') and path.name != 'INDEX.json']
	assert all(path.stat().st_size <= 2*1024**2 for path in selected)
	evidence = dict(format='pm-next-evidence/1', files=[dict(path=path.name, bytes=path.stat().st_size, sha256=sha(path)) for path in selected])
	(a.output/'INDEX.json').write_text(json.dumps(evidence, indent=2)+'\n')
	print('Lossless evidence verified:', len(model['files']), 'files;', packed.stat().st_size, 'compressed bytes;', len(evidence['files']), 'publisher attachments')


if __name__ == '__main__':
	main()
