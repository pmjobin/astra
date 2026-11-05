#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Lossless checkpoint attachments for the unchanged installed publisher."""
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
	assert git('status','--porcelain=v1','--untracked-files=all') == ''
	audit = read(RUNTIME/'checkpoint-audit.json'); head = git('rev-parse','HEAD').strip(); tree = git('rev-parse','HEAD^{tree}').strip()
	assert audit['status'] == 'PARTIAL' and audit['final_commit'] == head and audit['final_tree'] == tree
	output = RUNTIME/'handoff-v1'; output.mkdir(exist_ok=False); files = {}; omissions = []; started = time.monotonic()
	def collect(root,prefix):
		for path in sorted(root.rglob('*')):
			if path.is_dir(): continue
			if root == RUNTIME and path.relative_to(root).parts[0].startswith('handoff-'): continue
			assert path.is_file() and not path.is_symlink(),path
			name = prefix+'/'+str(path.relative_to(root))
			if path.suffix == '.zip':
				omissions.append(dict(path=name,bytes=path.stat().st_size,sha256=sha(path),reason='Exact predecessor report externally preserved, not duplicated in successor.')); continue
			files[name] = path
	collect(RUNTIME,'task-runtime'); collect(BUILD,'task-build')
	for version in ('v1','v2','v3'):
		identity = read(BUILD/('diagnosis-'+version)/'diagnose-O0.identity.json')
		for source,value in identity['identity']['sources'].items():
			path = Path(source)
			if sha(path) != value:
				assert version in ('v1','v2') and path.parent == ROOT/'tests/selfhost-membercall'
				path = RUNTIME/'failed-observer-inputs'/(version+'-'+path.name)
			assert sha(path) == value
			files['compiled-inputs/'+value+'/'+Path(source).name] = path
	for name in COHORTS:
		ledger = PRIOR/('ledger-v1-'+name)/'ledger.json'; files['historical/ledger-before-'+name+'.json'] = ledger
		for row in read(ledger)['files']:
			if 'synthetic_source_hex' not in row:
				path = Path(row['path']); assert sha(path) == row['sha256']; files['historical/source/'+row['sha256']+'/'+path.name] = path
	for mode in ('O0','O2'):
		for row in read(RUNTIME/('inherited-'+mode)/'programs.json'):
			for source in row['sources']:
				path = Path(source['path']); assert sha(path) == source['sha256']; files['program-inputs/'+source['sha256']+'/'+path.name] = path
			for product in row['qualified_products'].values():
				path = Path(product['path']); assert sha(path) == product['sha256']; files['program-products/'+product['sha256']+'/'+path.name] = path
	for name in ('engineering-summary.json','final-audit.json'): files['historical/predecessor-'+name] = PRIOR/name
	files['historical/proof-output-inventory.json'] = RUNTIME.parent/'indexpath18/historical-proof-outputs.json'
	collect(RUNTIME.parent/'native-current/input','submission/input'); files['submission/intake.json'] = RUNTIME.parent/'native-current/pm-next-intake.json'
	decoder = ROOT/'tests/selfhost-textclass/derived-ledgers.py'; encoder = ROOT/'tools/qualification/encoded-evidence.py'; transport_path = ROOT/'tests/selfhost-genclass/transport.py'
	for name,path in [('restore-ledgers.py',decoder),('encoded-evidence.py',encoder),('transport.py',transport_path)]: files['recipes/'+name] = path
	spec = importlib.util.spec_from_file_location('transport',transport_path); transport = importlib.util.module_from_spec(spec); spec.loader.exec_module(transport)
	plan = dict(format='astra-lossless-derived-ledgers/1',final_commit=head,final_tree=tree,files=[]); metadata = output/'derived-ledgers/metadata'; metadata.mkdir(parents=True)
	for name in COHORTS:
		logical = 'historical/ledger-before-'+name+'.json'; path = files[logical]; model = read(path); model['nodes'] = None
		target = metadata/(str(len(plan['files']))+'.json'); target.write_text(json.dumps(model,indent=2)+'\n'); files['derived-ledgers/metadata/'+target.name] = target
		raw_name = 'task-runtime/'+name+'.stdout'; assert raw_name in files
		plan['files'].append(dict(path=logical,bytes=path.stat().st_size,mode=path.stat().st_mode & 0o777,sha256=sha(path),raw=raw_name,raw_sha256=sha(files[raw_name]),metadata='metadata/'+target.name,metadata_sha256=sha(target)))
		del files[logical]
	plan_path = output/'derived-ledgers/restore-plan.json'; plan_path.write_text(json.dumps(plan,indent=2)+'\n'); receipt = output/'ledger-reconstruction.json'
	subprocess.run([sys.executable,'-B',decoder,output,'--plan',plan_path,'--original-runtime',RUNTIME,'--verify-only','--receipt',receipt],check=True)
	files['derived-ledgers/restore-plan.json'] = plan_path; files['derived-ledgers/reconstruction.json'] = receipt
	index = dict(format='astra-membercall22-checkpoint-evidence/1',storage_format='astra-line-chunk/1',final_commit=head,final_tree=tree,files=[],omissions=omissions)
	archive = output/'evidence.tar.xz'
	with tarfile.open(archive,'w:xz',preset=9) as packed:
		writer = transport.ChunkWriter(packed)
		for name,path in sorted(files.items()):
			before = sha(path); index['files'].append(writer.add(name,path,None,path.stat().st_mode & 0o777,before)); assert sha(path) == before
		data = (json.dumps(index,indent=2)+'\n').encode(); entry = tarfile.TarInfo('ARCHIVE-INDEX.json'); entry.size = len(data); entry.mode = 0o644; packed.addfile(entry,io.BytesIO(data))
	verification = transport.verify(archive); assert verification['status'] == 'PASS'; (output/'transport-verification.json').write_text(json.dumps(verification,indent=2)+'\n')
	assert archive.stat().st_size < 24*1024**2
	attachments = output/'attachments'; subprocess.run([sys.executable,'-B',encoder,'pack','--input',archive,'--output',attachments,'--stem','membercall22'],check=True)
	for name,path in [('checkpoint-audit.json',RUNTIME/'checkpoint-audit.json'),('inference-operands.json',RUNTIME/'inference-operands-v2/result.json'),('effect-boundary.json',RUNTIME/'effect-boundary-v2/result.json'),('transport-verification.json',output/'transport-verification.json')]: shutil.copy2(path,attachments/name)
	(attachments/'review-guide.txt').write_text('MEMBERCALL-22 PARTIAL diagnostic checkpoint. Read checkpoint-audit.json and the committed checkpoint note first. No member-call implementation or source advancement is claimed. All 172 inherited identities/profile have fresh LLVM emission/verification and ELF execution with disclosed exact product reuse. New native, memory and mutation gates are unmet.\nDecode membercall22-encoding.json with recipes/encoded-evidence.py; restore the archive with recipes/transport.py, then reconstruct all four exact source ledgers using recipes/restore-ledgers.py. All actual diagnostic/replay sources, products and failed attempts are retained. Predecessor report bytes remain externally preserved by their exact SHA.\n')
	(attachments/'packaging.json').write_text(json.dumps(dict(final_commit=head,final_tree=tree,archive_bytes=archive.stat().st_size,archive_sha256=sha(archive),seconds=time.monotonic()-started),indent=2)+'\n')
	evidence = dict(format='pm-next-evidence/1',files=[dict(path=path.name,bytes=path.stat().st_size,sha256=sha(path)) for path in sorted(attachments.iterdir())])
	assert len(evidence['files']) <= 128 and sum(row['bytes'] for row in evidence['files']) <= 64*1024**2 and all(row['bytes'] <= 2*1024**2 for row in evidence['files'])
	(attachments/'INDEX.json').write_text(json.dumps(evidence,indent=2)+'\n'); print(attachments/'INDEX.json',archive.stat().st_size,sha(archive),flush=True)


if __name__ == '__main__':
	main()
