#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Lossless current evidence through the installed unchanged pm-next publisher."""
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
from state import ROOT, RUNTIME, BUILD, PRIOR, BASE, COHORTS, read, sha, git


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version',default='v1'); a = p.parse_args(); assert a.version.replace('-','').isalnum()
	assert git('status','--porcelain=v1','--untracked-files=all') == ''
	audit = read(RUNTIME/'final-audit.json'); head = git('rev-parse','HEAD').strip(); tree = git('rev-parse','HEAD^{tree}').strip()
	assert audit['status'] == 'PASS' and audit['final_commit'] == head and audit['final_tree'] == tree
	output = RUNTIME/('handoff-'+a.version); output.mkdir(exist_ok=False); files = {}; omissions = []; started = time.monotonic()
	def collect(root,prefix):
		for path in sorted(root.rglob('*')):
			if path.is_dir(): continue
			if root == RUNTIME and path.relative_to(root).parts[0].startswith('handoff-'): continue
			if root == RUNTIME and path.relative_to(root).parts[0] == 'transport-sort-preflight': continue
			assert path.is_file() and not path.is_symlink(),path
			name = prefix+'/'+str(path.relative_to(root))
			if path.suffix == '.zip':
				omissions.append(dict(path=name,bytes=path.stat().st_size,sha256=sha(path),reason='Exact predecessor report remains externally preserved; compressed report is not duplicated in successor.')); continue
			files[name] = path
	collect(RUNTIME,'task-runtime'); collect(BUILD,'task-build')
	# Retain every repository input version used by successful or failed builds.
	# System libraries/headers remain pinned tool dependencies, not source copies.
	snapshots = {sha(p):p for p in RUNTIME.rglob('*.astra') if p.is_file()}
	commits = [BASE,*git('rev-list',BASE+'..'+head).splitlines()]; recovered = output/'recovered-inputs'; recovered.mkdir()
	identities = [*BUILD.rglob('*.identity.json'),*RUNTIME.rglob('ownflow-*-input-identity.json')]
	for identity_path in identities:
		model = read(identity_path); identity = model.get('identity',model)
		for source,expected in identity.get('sources',{}).items():
			path = Path(source)
			if not path.is_relative_to(ROOT): continue
			if sha(path) != expected:
				if expected in snapshots: path = snapshots[expected]
				else:
					for commit in commits:
						r = subprocess.run(['git','show',commit+':'+str(path.relative_to(ROOT))],cwd=ROOT,capture_output=True)
						if r.returncode == 0:
							import hashlib
							if hashlib.sha256(r.stdout).hexdigest() == expected:
								path = recovered/expected; path.write_bytes(r.stdout); snapshots[expected] = path; break
				assert sha(path) == expected,(source,expected)
			files['compiled-inputs/'+expected+'/'+Path(source).name] = path
	for name in COHORTS:
		ledger = PRIOR/('ledger-v1-'+name)/'ledger.json'; files['historical/ledger-before-'+name+'.json'] = ledger
		for row in read(ledger)['files']:
			if 'synthetic_source_hex' not in row:
				path = Path(row['path']); assert sha(path) == row['sha256']; files['historical/source/'+row['sha256']+'/'+path.name] = path
	for mode in ('O0','O2'):
		for row in read(RUNTIME/('inherited-v2-'+mode)/'programs.json'):
			for source in row['sources']:
				path = Path(source['path']); assert sha(path) == source['sha256']; files['program-inputs/'+source['sha256']+'/'+path.name] = path
			for product in row['prior_products'].values():
				path = Path(product['path']); assert sha(path) == product['sha256']; files['historical/program-products/'+product['sha256']+'/'+path.name] = path
	for name in ('engineering-summary.json','final-audit.json'): files['historical/slotswap21-'+name] = PRIOR/name
	for name in ('checkpoint-audit.json','inference-operands-v2/result.json','facts-v2/result.json'):
		files['historical/membercall22/'+name] = RUNTIME.parent/'membercall22'/name
	files['historical/proof-output-inventory.json'] = RUNTIME.parent/'indexpath18/historical-proof-outputs.json'
	collect(RUNTIME.parent/'native-current/input','submission/input'); files['submission/intake.json'] = RUNTIME.parent/'native-current/pm-next-intake.json'
	decoder = ROOT/'tests/selfhost-textclass/derived-ledgers.py'; encoder = ROOT/'tools/qualification/encoded-evidence.py'; transport_path = ROOT/'tests/selfhost-callplace/transport.py'
	for name,path in [('restore-ledgers.py',decoder),('encoded-evidence.py',encoder),('transport.py',transport_path)]: files['recipes/'+name] = path
	observations_path = ROOT/'tests/selfhost-callplace/observations.py'; files['recipes/restore-observations.py'] = observations_path
	observation_spec = importlib.util.spec_from_file_location('observations',observations_path); observations = importlib.util.module_from_spec(observation_spec); observation_spec.loader.exec_module(observations)
	observation_directory = output/'derived-observations'; observation_directory.mkdir()
	observation_plan = dict(format='astra-lossless-native-observations/1',final_commit=head,final_tree=tree,files=[])
	for logical,path in list(files.items()):
		if path.name == 'whole-compiler.stdout' or logical in {'task-runtime/'+name+'.stdout' for name in COHORTS}:
			observation_plan['files'].append(observations.encode(path,observation_directory,logical,len(observation_plan['files'])))
	observation_plan_path = observation_directory/'restore-plan.json'; observation_plan_path.write_text(json.dumps(observation_plan,indent=2)+'\n')
	observation_receipt = output/'observation-reconstruction.json'
	subprocess.run([sys.executable,'-B',observations_path,output,'--plan',observation_plan_path,'--verify-only','--receipt',observation_receipt],check=True)
	spec = importlib.util.spec_from_file_location('transport',transport_path); transport = importlib.util.module_from_spec(spec); spec.loader.exec_module(transport)
	plan = dict(format='astra-lossless-derived-ledgers/1',final_commit=head,final_tree=tree,files=[]); metadata = output/'derived-ledgers/metadata'; metadata.mkdir(parents=True)
	for logical,path in list(files.items()):
		if path.name != 'ledger.json': continue
		model = read(path)
		if model.get('format') != 'astra-whole-source-ledger/1': continue
		if logical.startswith('historical/ledger-before-'):
			name = logical.removeprefix('historical/ledger-before-').removesuffix('.json'); raw_name = 'task-runtime/'+name+'.stdout'
		else: raw_name = str(Path(logical).with_name('whole-compiler.stdout'))
		assert raw_name in files
		model['nodes'] = None; target = metadata/(str(len(plan['files']))+'.json'); target.write_text(json.dumps(model,indent=2)+'\n'); files['derived-ledgers/metadata/'+target.name] = target
		plan['files'].append(dict(path=logical,bytes=path.stat().st_size,mode=path.stat().st_mode & 0o777,sha256=sha(path),raw=raw_name,raw_sha256=sha(files[raw_name]),metadata='metadata/'+target.name,metadata_sha256=sha(target))); del files[logical]
	plan_path = output/'derived-ledgers/restore-plan.json'; plan_path.write_text(json.dumps(plan,indent=2)+'\n'); receipt = output/'ledger-reconstruction.json'
	subprocess.run([sys.executable,'-B',decoder,output,'--plan',plan_path,'--original-runtime',RUNTIME,'--verify-only','--receipt',receipt],check=True)
	files['derived-ledgers/restore-plan.json'] = plan_path; files['derived-ledgers/reconstruction.json'] = receipt
	for row in observation_plan['files']: del files[row['path']]
	for path in observation_directory.iterdir(): files['derived-observations/'+path.name] = path
	files['derived-observations/reconstruction.json'] = observation_receipt
	index = dict(format='astra-callplace23-evidence/1',storage_format='astra-line-chunk/1',final_commit=head,final_tree=tree,files=[],omissions=omissions)
	archive = output/'evidence.tar.xz'
	with tarfile.open(archive,'w:xz',preset=9) as packed:
		writer = transport.ChunkWriter(packed)
		for name,path in sorted(files.items()):
			before = sha(path); index['files'].append(writer.add(name,path,None,path.stat().st_mode & 0o777,before)); assert sha(path) == before
		data = (json.dumps(index,indent=2)+'\n').encode(); entry = tarfile.TarInfo('ARCHIVE-INDEX.json'); entry.size = len(data); entry.mode = 0o644; packed.addfile(entry,io.BytesIO(data))
	verification = transport.verify(archive); assert verification['status'] == 'PASS'; (output/'transport-verification.json').write_text(json.dumps(verification,indent=2)+'\n')
	assert archive.stat().st_size < 24*1024**2,'Preserve the report cap; improve lossless transport rather than dropping evidence'
	attachments = output/'attachments'; subprocess.run([sys.executable,'-B',encoder,'pack','--input',archive,'--output',attachments,'--stem','callplace23'],check=True)
	for name in ('final-audit.json','cohorts-v2.json','archive-integrity.json'): shutil.copy2(RUNTIME/name,attachments/name)
	shutil.copy2(output/'transport-verification.json',attachments/'transport-verification.json')
	(attachments/'review-guide.txt').write_text('CALLPLACE-23: read final-audit.json and the committed qualification note first. MEMBERCALL-22 remains PARTIAL. Original admit_record_value and class_storage_slot_flow callers remain DEFERRED because their recoverable throws Error contract is outside this milestone.\nDecode callplace23-encoding.json with recipes/encoded-evidence.py, restore the lossless archive with recipes/transport.py, reconstruct exact native stdout with recipes/restore-observations.py, then reconstruct exact before/after source ledgers with recipes/restore-ledgers.py. These byte reconstructions are not fresh executions.\nAll 172 inherited plus 15 new source programs/profile have fresh native emissions and ELF execution. New C0/ABI/memory, 28 model-consumer mutations and seven independent LLVM-valid physical alternatives/profile have separate ledgers. Failed drafts and cancelled builds retain their actual costs and input identities. Tool dependencies remain hash-pinned; no donor source is collected.\n')
	(attachments/'packaging.json').write_text(json.dumps(dict(final_commit=head,final_tree=tree,archive_bytes=archive.stat().st_size,archive_sha256=sha(archive),seconds=time.monotonic()-started),indent=2)+'\n')
	evidence = dict(format='pm-next-evidence/1',files=[dict(path=path.name,bytes=path.stat().st_size,sha256=sha(path)) for path in sorted(attachments.iterdir())]); assert len(evidence['files']) <= 128 and sum(row['bytes'] for row in evidence['files']) <= 64*1024**2 and all(row['bytes'] <= 2*1024**2 for row in evidence['files'])
	(attachments/'INDEX.json').write_text(json.dumps(evidence,indent=2)+'\n'); print(attachments/'INDEX.json',archive.stat().st_size,sha(archive),flush=True)


if __name__ == '__main__':
	main()
