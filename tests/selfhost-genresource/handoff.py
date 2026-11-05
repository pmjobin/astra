#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Losslessly package current evidence for the unchanged pm-next publisher."""
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
import zipfile
from state import ROOT, RUNTIME, BUILD, PRIOR, COHORTS, read, sha, git


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version',default='v2'); a = p.parse_args(); assert a.version.replace('-','').isalnum()
	assert git('status','--porcelain=v1','--untracked-files=all') == ''
	audit = read(RUNTIME/'final-audit.json'); engineering = read(RUNTIME/'engineering-summary.json')
	head = git('rev-parse','HEAD').strip(); tree = git('rev-parse','HEAD^{tree}').strip()
	assert audit['status'] == 'PASS' and audit['final_commit'] == head and audit['final_tree'] == tree
	assert engineering['status'] == 'ENGINEERING_GATES_COMPLETE_PUBLICATION_PENDING'
	output = RUNTIME/('handoff-'+a.version); output.mkdir(exist_ok=False); files = {}; omitted = []; start = time.monotonic()
	def collect(root,prefix):
		for path in sorted(root.rglob('*')):
			if path.is_dir() or path.is_relative_to(output): continue
			if root == RUNTIME and path.relative_to(root).parts[0].startswith('handoff'): continue
			assert path.is_file() and not path.is_symlink(),path
			name = prefix+'/'+str(path.relative_to(root))
			if path.suffix == '.zip':
				omitted.append(dict(path=name,bytes=path.stat().st_size,sha256=sha(path),reason='Byte-exact predecessor preserved externally; original compressed report is not duplicated inside the bounded current report.')); continue
			files[name] = path
	collect(RUNTIME,'task-runtime'); collect(BUILD,'task-build')
	# Preserve original source populations by content, never collect donor source.
	for cohort in read(RUNTIME/'initial/result.json')['cohorts'].values():
		for row in cohort['files']:
			if 'synthetic_source_hex' in row: continue
			path = Path(row['path']); assert sha(path) == row['sha256']; files['historical/cohorts/'+row['sha256']+'/'+path.name] = path
	for mode,data in engineering['profiles'].items():
		for row in data['programs']:
			for source in row['sources']:
				path = Path(source['path']); assert sha(path) == source['sha256']; files['program-inputs/'+source['sha256']+'/'+path.name] = path
		component = ROOT.parent/'codex/work/astra/build/ownexchange19'/('native-v7-'+mode)/('astra-llvm-'+mode)
		files['historical/baseline-products/'+component.name] = component; files['historical/baseline-products/'+component.with_suffix('.identity.json').name] = component.with_suffix('.identity.json')
	proofs = RUNTIME.parent/'indexpath18/historical-proof-outputs.json'; files['historical/proof-output-inventory.json'] = proofs
	for name in COHORTS: files['historical/ledger-before-'+name+'.json'] = PRIOR/('ledger-v7-'+name)/'ledger.json'
	stage = RUNTIME.parent/'native-current'; collect(stage/'input','submission/input'); files['submission/intake.json'] = stage/'pm-next-intake.json'
	intake = read(stage/'pm-next-intake.json'); submission = Path(intake['submission_path']); assert sha(submission) == intake['submission_sha256']
	with zipfile.ZipFile(submission) as source: manifest = source.read('MANIFEST.json')
	manifest_path = output/'submission-manifest.json'; manifest_path.write_bytes(manifest); files['submission/MANIFEST.json'] = manifest_path
	decoder = ROOT/'tests/selfhost-textclass/derived-ledgers.py'; files['recipes/restore-ledgers.py'] = decoder
	encoder = ROOT/'tools/qualification/encoded-evidence.py'; files['recipes/encoded-evidence.py'] = encoder
	transport_path = ROOT/'tests/selfhost-genclass/transport.py'; files['recipes/transport.py'] = transport_path
	spec = importlib.util.spec_from_file_location('lossless_transport',transport_path); transport = importlib.util.module_from_spec(spec); spec.loader.exec_module(transport)
	plan = dict(format='astra-lossless-derived-ledgers/1',final_commit=head,final_tree=tree,files=[])
	metadata_root = output/'derived-ledgers/metadata'; metadata_root.mkdir(parents=True)
	for logical,path in list(files.items()):
		if path.name != 'ledger.json': continue
		model = read(path)
		if model.get('format') != 'astra-whole-source-ledger/1': continue
		if logical.startswith('historical/ledger-before-'):
			name = logical.removeprefix('historical/ledger-before-').removesuffix('.json'); raw_name = 'task-runtime/initial/'+name+'.stdout'
		else: raw_name = str(Path(logical).with_name('whole-compiler.stdout'))
		assert raw_name in files
		model['nodes'] = None; target = metadata_root/(str(len(plan['files']))+'.json'); target.write_text(json.dumps(model,indent=2)+'\n')
		files['derived-ledgers/metadata/'+target.name] = target
		plan['files'].append(dict(path=logical,bytes=path.stat().st_size,mode=path.stat().st_mode & 0o777,sha256=sha(path),raw=raw_name,raw_sha256=sha(files[raw_name]),metadata='metadata/'+target.name,metadata_sha256=sha(target)))
		del files[logical]; del model
	plan_path = output/'derived-ledgers/restore-plan.json'; plan_path.write_text(json.dumps(plan,indent=2)+'\n')
	receipt = output/'ledger-reconstruction.json'
	subprocess.run([sys.executable,'-B',decoder,output,'--plan',plan_path,'--original-runtime',RUNTIME,'--verify-only','--receipt',receipt],check=True)
	files['derived-ledgers/restore-plan.json'] = plan_path; files['derived-ledgers/reconstruction.json'] = receipt
	index = dict(format='astra-genresource20-raw-evidence/1',storage_format='astra-line-chunk/1',final_commit=head,final_tree=tree,files=[],omissions=omitted)
	archive = output/'evidence.tar.xz'
	with tarfile.open(archive,'w:xz',preset=6) as packed:
		writer = transport.ChunkWriter(packed)
		for name,path in sorted(files.items()):
			before = sha(path); index['files'].append(writer.add(name,path,None,path.stat().st_mode & 0o777,before))
			assert sha(path) == before
		data = (json.dumps(index,indent=2)+'\n').encode(); info = tarfile.TarInfo('ARCHIVE-INDEX.json'); info.size = len(data); info.mode = 0o644; packed.addfile(info,io.BytesIO(data))
	verification = transport.verify(archive); (output/'transport-verification.json').write_text(json.dumps(verification,indent=2)+'\n'); assert verification['status'] == 'PASS'
	assert archive.stat().st_size < 24*1024**2,'Evidence must fit the unchanged 25 MiB report limit; revise only lossless transport if needed'
	attachments = output/'attachments'
	subprocess.run([sys.executable,'-B',encoder,'pack','--input',archive,'--output',attachments,'--stem','genresource20'],check=True)
	light = dict(engineering); light['profiles'] = {mode:{key:value for key,value in data.items() if key != 'programs'} for mode,data in engineering['profiles'].items()}; light.update(final_commit=head,final_tree=tree,evidence_archive_sha256=sha(archive),evidence_archive_bytes=archive.stat().st_size,packaging_seconds=time.monotonic()-start)
	(attachments/'engineering-summary.json').write_text(json.dumps(light,indent=2)+'\n')
	for name in ('final-audit.json','cohorts-final-v2.json','warm-timed.json'):
		shutil.copy2(RUNTIME/name,attachments/name)
	shutil.copy2(output/'transport-verification.json',attachments/'transport-verification.json')
	(attachments/'review-guide.txt').write_text('GENRESOURCE-20: read engineering-summary.json and final-audit.json first.\nVerify/unpack genresource20-encoding.json with the committed tools/qualification/encoded-evidence.py. The decoded file is a lossless line/chunk tar.xz archive: restore it with recipes/transport.py first. Restore the eight exact derived ledgers with recipes/restore-ledgers.py; reconstruction is byte-verified and is not a fresh safety proof.\n145 inherited + 12 required new + 2 additional source identities/profile = 159, with actual optimized ELF collisions disclosed separately.\nFour exact frozen populations have new checked prefix facts but remain whole-source deferred at the documented signatures-array swap.\nFourteen retained-model mutations and six external LLVM-valid source/ABI/runtime controls/profile are separate from the 37 rerun OWNEXCHANGE controls and their 11 retained-module physical audits.\nThe nonproductive signature cycle is bounded-deferred with no failed declaration published. The genuine 257th distinct request remains deferred at 256; SSA and other named deferrals remain unchanged.\nThe preserved predecessor ZIP is external, identified by its original SHA-256; all 1044 historical proof outputs retain historical attribution. No donor checkout source is collected.\n')
	evidence = dict(format='pm-next-evidence/1',files=[dict(path=path.name,bytes=path.stat().st_size,sha256=sha(path)) for path in sorted(attachments.iterdir())])
	assert len(evidence['files']) <= 128 and sum(row['bytes'] for row in evidence['files']) <= 64*1024**2 and all(row['bytes'] <= 2*1024**2 for row in evidence['files'])
	(attachments/'INDEX.json').write_text(json.dumps(evidence,indent=2)+'\n')
	print('Publisher evidence manifest:',attachments/'INDEX.json','archive',archive.stat().st_size,'bytes',sha(archive),flush=True)


if __name__ == '__main__':
	main()
