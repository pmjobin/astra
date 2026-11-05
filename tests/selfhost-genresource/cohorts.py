#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compare exact original node populations and newly recorded checked uses."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time
from state import ROOT, RUNTIME, BUILD, PRIOR, C0, COHORTS, read, sha


def digest(value):
	return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).hexdigest()


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component',type=Path,required=True); p.add_argument('--name',required=True); a = p.parse_args()
	assert a.name.replace('-','').isalnum(); results = {}
	for name in COHORTS:
		initial = read(RUNTIME/'initial/result.json')['cohorts'][name]
		old = read(PRIOR/('ledger-v7-'+name)/'ledger.json'); physical = next(row for row in old['files'] if 'synthetic_source_hex' not in row)
		root = Path(physical['path'])
		for _ in Path(physical['relative']).parts: root = root.parent
		leaf = RUNTIME/('ledger-'+a.name+'-'+name); build = BUILD/('ledger-'+a.name+'-'+name)
		argv = [sys.executable,'-B',ROOT/'tests/selfhost-generics/ledger.py','--compiler',C0,'--component',a.component,'--phase','after','--class-storage','--target-root',root,'--build',build,'--runtime',leaf]
		start = time.monotonic(); r = subprocess.run(list(map(str,argv)),cwd=ROOT,capture_output=True,timeout=300)
		assert r.returncode == 0,r.stderr.decode(errors='replace')[-2000:]
		(leaf/'collector.stdout').write_bytes(r.stdout); (leaf/'collector.stderr').write_bytes(r.stderr)
		new = read(leaf/'ledger.json')
		def population(data):
			files = {row['path']:row for row in data['files']}
			logical = {row['relative']:(row['bytes'],row['sha256']) for row in data['files']}
			nodes = [[row['node'],row['syntax_kind'],files[row['path']]['relative'],row['start'],row['end'],row['source_sha256']] for row in data['nodes']]
			return logical,nodes
		before,before_nodes = population(old); after,after_nodes = population(new); assert before == after and before_nodes == after_nodes
		assert len(new['nodes']) == initial['nodes'] and len(new['files']) == len(initial['files'])
		facts = []; source_cache = {}
		for identity,left,right in zip(before_nodes,old['nodes'],new['nodes']):
			if right['type'] and right['deferred'] == 0 and (not left['type'] or left['deferred'] != 0):
				path = Path(right['path'])
				if path not in source_cache: source_cache[path] = path.read_bytes() if path.exists() else b''
				source = source_cache[path]
				facts.append(dict(identity=identity,before=[left['type'],left['flags'],left['deferred']],after=[right['type'],right['flags'],right['deferred']],source_bytes_hex=source[right['start']:right['end']].hex()))
		(leaf/'new-checked-prefix-uses.json').write_text(json.dumps(facts,indent=2)+'\n')
		results[name] = dict(argv=list(map(str,argv)),start=start,end=time.monotonic(),population_sha256=digest(before),node_identity_sha256=digest(before_nodes),files=len(new['files']),nodes=len(new['nodes']),typed_before=sum(bool(row['type']) and row['deferred'] == 0 for row in old['nodes']),typed_after=sum(bool(row['type']) and row['deferred'] == 0 for row in new['nodes']),first_stop_before=old['diagnostics'][0],first_stop_after=new['diagnostics'][0] if new['diagnostics'] else None,new_checked_prefix_uses=len(facts),samples=facts[:3],old_ledger_sha256=sha(PRIOR/('ledger-v7-'+name)/'ledger.json'),new_ledger_sha256=sha(leaf/'ledger.json'),component_sha256=sha(a.component),limitation='New original-node checked-use observations under an eventual whole-population deferral. This does not qualify whole-source Flow, native execution or Stage 1.')
		(RUNTIME/('cohorts-'+a.name+'.json')).write_text(json.dumps(results,indent=2)+'\n')
		print(name,results[name]['typed_before'],'->',results[name]['typed_after'],'new exact uses',len(facts),results[name]['first_stop_after'],flush=True)


if __name__ == '__main__':
	main()
