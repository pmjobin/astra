#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Prepare hashed runtime evidence for the installed publisher; never publish."""
import argparse
import base64
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[2]


def sha(data):
	return hashlib.sha256(data).hexdigest()


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--runtime',type=Path,required=True)
	p.add_argument('--build',type=Path,required=True)
	p.add_argument('--profile-prefix',default='qualified-v5-')
	p.add_argument('--receipt-prefix',default='v5-')
	a = p.parse_args()
	assert not a.runtime.resolve().is_relative_to(ROOT) and not a.build.resolve().is_relative_to(ROOT)
	summary = dict(format='astra-llvm12-qualification/1',status='PASS',profiles={})
	payload = {}
	def put(name,data):
		assert name not in payload
		payload[name] = data
	def regular(path,name):
		assert path.is_file() and not path.is_symlink(),path
		put(name,path.read_bytes())
	for mode in ('O0','O2'):
		runs = json.loads((a.runtime/(a.receipt_prefix+'final-'+mode)/'result.json').read_text())
		negative = json.loads((a.runtime/(a.receipt_prefix+'negative-'+mode)/'result.json').read_text())
		continuity = json.loads((a.runtime/(a.receipt_prefix+'continuity-'+mode)/'result.json').read_text())
		literals = json.loads((a.runtime/(a.receipt_prefix+'literals-'+mode)/'result.json').read_text())
		assert literals['status'] == 'PASS' and literals['counted_in_frozen_24'] is False
		fatal = json.loads((a.runtime/(a.receipt_prefix+'fatal-'+mode)/'result.json').read_text())
		assert runs['status'] == negative['status'] == continuity['status'] == fatal['status'] == 'PASS'
		assert runs['executions'] == len(runs['cases']) == 24 and negative['categories'] >= 20 and len(negative['mapping']) == 80 and len(fatal['cases']) == 3
		assert len({x['source_sha256'] for x in runs['cases']}) == 24
		assert continuity['outcomes'] == {'0':56,'4':12,'3':12}
		assert {key:len(value) for key,value in continuity['mutations'][mode]['categories'].items()} == dict(core=22,cfg=26,ssa=30)
		component = a.build/(a.profile_prefix+mode)/('astra-llvm-'+mode)
		identity = json.loads(component.with_suffix('.identity.json').read_text())
		assert sha(component.read_bytes()) == identity['sha256'] == runs['cases'][0]['component_sha256']
		assert all(sha(Path(path).read_bytes()) == digest for path,digest in identity['identity']['sources'].items())
		assert all(sha(Path(path).read_bytes()) == digest for path,digest in identity['identity']['tools'].items())
		for case in runs['cases']:
			assert sha(Path(case['source_path']).read_bytes()) == case['source_sha256']
			for label,product in case['products'].items():
				path = Path(product['path']); assert sha(path.read_bytes()) == product['sha256']
				regular(path,'products/'+mode+'/'+case['name']+'/'+label+path.suffix)
			for path,digest in case['runtime'].items():
				assert sha(Path(path).read_bytes()) == digest
			regular(Path(case['source_path']),'inputs/selected/'+case['name']+'.astra') if mode == 'O0' else None
		regular(component,'components/'+mode+'/'+component.name)
		regular(component.with_suffix('.identity.json'),'components/'+mode+'/identity.json')
		summary['profiles'][mode] = dict(executions=24,backend_mutation_categories=negative['categories'],predecessor_sources=80,predecessor_mutations=dict(core=22,cfg=26,ssa=30),fatal_controls=3,additional_literal_regressions=1,component_sha256=identity['sha256'],llvm_mapping=negative['outcomes'],coverage_sha256=sha((a.runtime/(a.receipt_prefix+'final-'+mode)/'results.json').read_bytes()),memory=negative['memory'])
	proof = json.loads((a.runtime/'proof-continuity/result.json').read_text()); assert proof['status'] == 'PASS' and proof['observations'] == 1044
	preservation = json.loads((a.runtime/'preservation-final.json').read_text()); assert preservation['status'] == 'PASS' and preservation['protected_files'] == 446 and preservation['donor_files'] == 6622
	for item in json.loads((a.runtime/'frozen/predecessor.json').read_text()):
		for index,path in enumerate(item['paths']):
			regular(Path(path),'inputs/predecessor/'+item['name']+'/'+str(index)+'.astra')
			# Lossless task receipts, including failed development attempts. The initial
			# capture contains raw local configuration text, so publish only its digest.
	for path in sorted(a.runtime.rglob('*')):
		if not path.is_file():
			continue
		rel = path.relative_to(a.runtime)
		if rel.parts[0] in {'handoff','report-evidence'} or path.name == 'initial.json':
			continue
		if path.suffix in {'.json','.stdout','.stderr','.time','.log','.astra'}:
			regular(path,'runtime/'+rel.as_posix())
	failed_artifacts = {
		'implicit-GEP-flags.raw.ll':a.build/'applications-O0/ordered-owned-arguments-O0.raw.ll',
		'owner-loop-elided.raw.ll':a.build/'v4-applications-O2/owner-loop-exits-O2.raw.ll',
		'owner-loop-elided.optimized.ll':a.build/'v4-applications-O2/owner-loop-exits-O2.ll',
		'literal-before-fix.o':a.build/'literal-preflight/old-emitter.o',
		'literal-before-fix.native':a.build/'literal-preflight/old-emitter',
		'literal-independent-C0.native':a.build/'literal-preflight/C0-reference',
	}
	for name,path in failed_artifacts.items():
		regular(path,'failures/'+name)
	for mode in ('O0','O2'):
		literal = json.loads((a.runtime/(a.receipt_prefix+'literals-'+mode)/'result.json').read_text())
		for name,digest in literal['artifacts'].items():
			path = Path(name); assert sha(path.read_bytes()) == digest
			regular(path,'additional-literals/'+mode+'/'+path.name)
	summary.update(proof_observations=1044,preservation=preservation,compiled_source_commit=subprocess.check_output(['git','log','-1','--format=%H','--','compiler/backend/llvm/capi.astra','compiler/backend/llvm/module.astra','compiler/backend/llvm/check.astra','compiler/backend/llvm/capi.c'],cwd=ROOT,text=True).strip(),head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),tree=subprocess.check_output(['git','rev-parse','HEAD^{tree}'],cwd=ROOT,text=True).strip(),initial_private_capture_sha256=sha((a.runtime/'initial.json').read_bytes()),limitations=['24 distinct executed programs per profile; other positives have IR verification only.','No Stage 1, full compiler, general foreign ABI or additional target qualification.','No pre-known IR/object/executable byte hashes: independent semantic/structural expectations plus actual artifact hashes.','Historical and concurrent external global Codex config byte changes are recorded; critical model/reasoning/sandbox/approval settings and project/skill pins match.'])
	out = a.runtime/'report-evidence'; out.mkdir(exist_ok=True)
	attachments = [out/'qualification.json',out/'raw-index.json']
	(out/'qualification.json').write_text(json.dumps(summary,indent=2)+'\n')
	index = {name:dict(bytes=len(data),sha256=sha(data)) for name,data in payload.items()}
	# Keep the complete raw-member inventory within the installed publisher's
	# per-attachment bound, without dropping receipts or shortening identities.
	parts = []
	items = list(index.items())
	for i,start in enumerate(range(0,len(items),1000)):
		part = out/('raw-index-'+str(i).zfill(3)+'.json')
		part.write_text(json.dumps(dict(items[start:start+1000]),indent=2)+'\n')
		attachments.append(part)
		parts.append(dict(path=part.name,bytes=part.stat().st_size,sha256=sha(part.read_bytes()),members=len(items[start:start+1000])))
	(out/'raw-index.json').write_text(json.dumps(dict(format='astra-evidence-raw-index/1',members=len(index),parts=parts),indent=2)+'\n')
	archive = a.runtime/'handoff'; archive.mkdir(exist_ok=True)
	path = archive/'raw-evidence.tar.xz'
	with tarfile.open(path,'w:xz',preset=3) as tar:
		for name,data in sorted(payload.items()):
			info = tarfile.TarInfo(name); info.size = len(data); info.mode = 0o644; tar.addfile(info,io.BytesIO(data))
	data = path.read_bytes(); summary['raw_archive'] = dict(path=str(path),bytes=len(data),sha256=sha(data),members=len(payload))
	(out/'qualification.json').write_text(json.dumps(summary,indent=2)+'\n')
	for i,start in enumerate(range(0,len(data),900000)):
		chunk = data[start:start+900000]
		part = out/('raw-part-'+str(i).zfill(3)+'.json')
		part.write_text(json.dumps(dict(format='astra-evidence-base64-chunk/1',archive_sha256=sha(data),offset=start,bytes=len(chunk),sha256=sha(chunk),base64=base64.b64encode(chunk).decode()),separators=(',',':'))+'\n')
		attachments.append(part)
	files = [dict(path=p.name,bytes=p.stat().st_size,sha256=sha(p.read_bytes())) for p in sorted(attachments)]
	assert all(x['bytes'] <= 2*1024*1024 for x in files)
	(out/'evidence-index.json').write_text(json.dumps(dict(format='pm-next-evidence/1',files=files),indent=2)+'\n')
	print('prepared',len(files),'hashed evidence attachments;',len(data),'compressed raw bytes; installed publisher still required')


if __name__ == '__main__':
	main()
