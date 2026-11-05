#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Lossless evidence transport through the unchanged installed publisher."""
import argparse
import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import time
from state import ROOT, RUNTIME, BUILD, PRIOR, COHORTS, read, sha, git


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version',default='v1'); a = p.parse_args(); assert a.version.replace('-','').isalnum()
	assert git('status','--porcelain=v1','--untracked-files=all') == ''
	audit = read(RUNTIME/'final-audit.json'); summary = read(RUNTIME/'engineering-summary.json'); head = git('rev-parse','HEAD').strip(); tree = git('rev-parse','HEAD^{tree}').strip()
	assert audit['status'] == 'PASS' and audit['final_commit'] == head and audit['final_tree'] == tree
	output = RUNTIME/('handoff-'+a.version); output.mkdir(exist_ok=False); files = {}; omissions = []; started = time.monotonic()
	def collect(root,prefix):
		for path in sorted(root.rglob('*')):
			if path.is_dir(): continue
			if root == RUNTIME and path.relative_to(root).parts[0].startswith('handoff-'): continue
			assert path.is_file() and not path.is_symlink(),path
			name = prefix+'/'+str(path.relative_to(root))
			if path.suffix == '.zip':
				omissions.append(dict(path=name,bytes=path.stat().st_size,sha256=sha(path),reason='Exact predecessor report preserved externally; not duplicated inside the bounded successor.')); continue
			files[name] = path
	collect(RUNTIME,'task-runtime'); collect(BUILD,'task-build')
	for name in COHORTS:
		ledger = PRIOR/('ledger-final-v2-'+name)/'ledger.json'; files['historical/ledger-before-'+name+'.json'] = ledger
		for row in read(ledger)['files']:
			if 'synthetic_source_hex' not in row:
				path = Path(row['path']); assert sha(path) == row['sha256']; files['historical/source/'+row['sha256']+'/'+path.name] = path
	for mode,data in summary['profiles'].items():
		for row in data['programs']:
			for source in row['sources']:
				path = Path(source['path']); assert sha(path) == source['sha256']; files['program-inputs/'+source['sha256']+'/'+path.name] = path
			for product in row.get('products',row.get('qualified_products')).values():
				path = Path(product['path']); assert sha(path) == product['sha256']; files['program-products/'+product['sha256']+'/'+path.name] = path
	for name in ('engineering-summary.json','final-audit.json','final-publication-verification.json'):
		files['historical/predecessor-'+name] = PRIOR/name
	files['historical/proof-output-inventory.json'] = RUNTIME.parent/'indexpath18/historical-proof-outputs.json'
	collect(RUNTIME.parent/'native-current/input','submission/input'); files['submission/intake.json'] = RUNTIME.parent/'native-current/pm-next-intake.json'
	decoder = ROOT/'tests/selfhost-textclass/derived-ledgers.py'; files['recipes/restore-ledgers.py'] = decoder
	encoder = ROOT/'tools/qualification/encoded-evidence.py'; files['recipes/encoded-evidence.py'] = encoder
	transport_path = ROOT/'tests/selfhost-genclass/transport.py'; files['recipes/transport.py'] = transport_path
	spec = importlib.util.spec_from_file_location('transport',transport_path); transport = importlib.util.module_from_spec(spec); spec.loader.exec_module(transport)
	plan = dict(format='astra-lossless-derived-ledgers/1',final_commit=head,final_tree=tree,files=[])
	metadata = output/'derived-ledgers/metadata'; metadata.mkdir(parents=True)
	for logical,path in list(files.items()):
		if not (path.name == 'ledger.json' and read(path).get('format') == 'astra-whole-source-ledger/1'): continue
		model = read(path)
		if logical.startswith('historical/ledger-before-'):
			name = logical.removeprefix('historical/ledger-before-').removesuffix('.json'); raw_name = 'task-runtime/'+name+'.stdout'
		else: raw_name = str(Path(logical).with_name('whole-compiler.stdout'))
		assert raw_name in files
		model['nodes'] = None; target = metadata/(str(len(plan['files']))+'.json'); target.write_text(json.dumps(model,indent=2)+'\n')
		files['derived-ledgers/metadata/'+target.name] = target
		plan['files'].append(dict(path=logical,bytes=path.stat().st_size,mode=path.stat().st_mode & 0o777,sha256=sha(path),raw=raw_name,raw_sha256=sha(files[raw_name]),metadata='metadata/'+target.name,metadata_sha256=sha(target)))
		del files[logical]
	plan_path = output/'derived-ledgers/restore-plan.json'; plan_path.write_text(json.dumps(plan,indent=2)+'\n')
	# The external original-runtime mode resolves both before and after raw paths
	# here, and verifies byte-exact reconstruction without changing old ledgers.
	receipt = output/'ledger-reconstruction.json'
	subprocess.run([sys.executable,'-B',decoder,output,'--plan',plan_path,'--original-runtime',RUNTIME,'--verify-only','--receipt',receipt],check=True)
	files['derived-ledgers/restore-plan.json'] = plan_path; files['derived-ledgers/reconstruction.json'] = receipt
	index = dict(format='astra-slotswap21-raw-evidence/1',storage_format='astra-line-chunk/1',final_commit=head,final_tree=tree,files=[],omissions=omissions)
	archive = output/'evidence.tar.xz'
	with tarfile.open(archive,'w:xz',preset=9) as packed:
		writer = transport.ChunkWriter(packed)
		for name,path in sorted(files.items()):
			before = sha(path); index['files'].append(writer.add(name,path,None,path.stat().st_mode & 0o777,before)); assert sha(path) == before
		data = (json.dumps(index,indent=2)+'\n').encode(); info = tarfile.TarInfo('ARCHIVE-INDEX.json'); info.size = len(data); info.mode = 0o644; packed.addfile(info,io.BytesIO(data))
	verification = transport.verify(archive); (output/'transport-verification.json').write_text(json.dumps(verification,indent=2)+'\n'); assert verification['status'] == 'PASS'
	assert archive.stat().st_size < 24*1024**2,'Keep the unchanged report cap; revise lossless transport, never drop evidence'
	attachments = output/'attachments'; subprocess.run([sys.executable,'-B',encoder,'pack','--input',archive,'--output',attachments,'--stem','slotswap21'],check=True)
	for name in ('final-audit.json','cohorts-v1.json','witness-O0.json','witness-O2.json'): shutil.copy2(RUNTIME/name,attachments/name)
	shutil.copy2(output/'transport-verification.json',attachments/'transport-verification.json')
	(attachments/'review-guide.txt').write_text('SLOTSWAP-21: read final-audit.json and cohorts-v1.json first.\nDecode slotswap21-encoding.json using the committed tools/qualification/encoded-evidence.py; restore the decoded archive with recipes/transport.py, then restore all eight exact source ledgers with recipes/restore-ledgers.py. Every derived ledger is byte/hash verified.\n159 inherited identities are freshly checked through LLVM and executed, with exact qualified product reuse disclosed separately. Thirteen new programs/profile include the byte-preserving add_signature method view; full Class/compiler admission remains deferred.\nRecord authority mutations, parse-valid source controls and six external LLVM-valid physical candidates have separately attributed rejection boundaries. Historical proof outputs retain historical attribution.\nThe exact predecessor ZIP is preserved externally by SHA-256. No C0/donor/history/workflow/LLVM/ABI/resource limit changes; no Stage 1 or release claim.\n')
	(attachments/'packaging.json').write_text(json.dumps(dict(final_commit=head,final_tree=tree,archive_bytes=archive.stat().st_size,archive_sha256=sha(archive),seconds=time.monotonic()-started),indent=2)+'\n')
	evidence = dict(format='pm-next-evidence/1',files=[dict(path=path.name,bytes=path.stat().st_size,sha256=sha(path)) for path in sorted(attachments.iterdir())])
	assert len(evidence['files']) <= 128 and sum(row['bytes'] for row in evidence['files']) <= 64*1024**2 and all(row['bytes'] <= 2*1024**2 for row in evidence['files'])
	(attachments/'INDEX.json').write_text(json.dumps(evidence,indent=2)+'\n'); print(attachments/'INDEX.json',archive.stat().st_size,sha(archive),flush=True)


if __name__ == '__main__':
	main()
