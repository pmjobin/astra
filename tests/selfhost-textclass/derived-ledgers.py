#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Restore byte-exact source ledgers from native observations and metadata."""
from pathlib import Path
import argparse,hashlib,json,os,time

def sha(path):
	with path.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()

def main():
	p=argparse.ArgumentParser(description='Reconstruct the exact derived ledgers from preserved original native NODE observations and metadata.')
	p.add_argument('root',type=Path);p.add_argument('--plan',type=Path);p.add_argument('--original-runtime',type=Path);p.add_argument('--verify-only',action='store_true');p.add_argument('--receipt',type=Path)
	a=p.parse_args();root=a.root.resolve();plan=(a.plan or root/'derived-ledgers/restore-plan.json').resolve();m=json.loads(plan.read_text());assert m['format']=='astra-lossless-derived-ledgers/1';results=[];start=time.monotonic()
	for row in m['files']:
		raw=(a.original_runtime/row['raw'].removeprefix('task-runtime/')) if a.original_runtime else root/row['raw']
		metadata=plan.parent/row['metadata'];assert sha(raw)==row['raw_sha256'] and sha(metadata)==row['metadata_sha256']
		model=json.loads(metadata.read_text());assert model['nodes'] is None
		identities={r['path']:r['sha256'] for r in model['files']};decls=model['declarations'];reasons=model['reason_authority']['reasons'];failed=any(s.startswith('CHECKED_ERROR ') for s in model['raw_flow']);nodes=[]
		with raw.open() as source:
			for line in source:
				if not line.startswith('NODE '):continue
				v=line.split();path=bytes.fromhex(v[7]).decode()
				node=dict(node=int(v[1]),syntax_kind=int(v[2]),function_symbol=int(v[3]),type=int(v[4]),flags=int(v[5]),deferred=int(v[6]),path=path,start=int(v[8]),end=int(v[9]),source_sha256=identities[path])
				node['function']=decls.get(str(node['function_symbol']))
				node['deferred_reason']=reasons.get(str(node['deferred']),'specific syntax family '+str(node['syntax_kind']) if node['deferred']>=100 else None)
				node['disposition']='TYPE_DEFERRED_'+str(node['deferred']) if node['deferred'] else 'TYPE_RECORDED_WITHOUT_WHOLE_PROGRAM_ADMISSION' if node['type'] else 'NO_CHECKED_USE_RECORDED'
				node['program_checked_error']=failed;nodes.append(node)
		model['nodes']=nodes;data=(json.dumps(model,indent=2)+'\n').encode();observed=hashlib.sha256(data).hexdigest();assert len(data)==row['bytes'] and observed==row['sha256'],row['path']
		if not a.verify_only:
			output=root/row['path'];assert output.resolve().is_relative_to(root) and not output.is_symlink();output.parent.mkdir(parents=True,exist_ok=True)
			if output.exists():assert sha(output)==observed
			else:output.write_bytes(data);os.chmod(output,row['mode'])
		results.append(dict(path=row['path'],bytes=len(data),sha256=observed,nodes=len(nodes)));print(row['path'],observed,flush=True)
		del nodes,model,data
	result=dict(status='PASS',format=m['format'],files=results,final_commit=m['final_commit'],final_tree=m['final_tree'],plan_sha256=sha(plan),decoder_sha256=sha(Path(__file__)),seconds=time.monotonic()-start,classification='Exact byte reconstruction, not compiler re-execution or a new safety proof.')
	if a.receipt:a.receipt.write_text(json.dumps(result,indent=2)+'\n')
	print(json.dumps(result))

if __name__=='__main__':main()
