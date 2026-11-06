#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compare the exact same source/node/span populations past the old member call."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time
from state import ROOT, RUNTIME, BUILD, PRIOR, C0, COHORTS, read, sha, digest, population


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component',type=Path,required=True); a = p.parse_args(); results = {}
	for name in COHORTS:
		old = read(PRIOR/('ledger-v1-'+name)/'ledger.json'); prior = read(PRIOR/'cohorts-v1.json')[name]
		leaf = RUNTIME/('ledger-v1-'+name); build = BUILD/leaf.name
		argv = prior['argv'].copy()
		for flag,value in [('--component',a.component),('--build',build),('--runtime',leaf)]: argv[argv.index(flag)+1] = str(value)
		start = time.monotonic(); r = subprocess.run(['/usr/bin/time','-v','-o',RUNTIME/('cohort-'+name+'.time'),*argv],cwd=ROOT,capture_output=True,timeout=300)
		assert r.returncode == 0,r.stderr.decode(errors='replace')[-2000:]
		(leaf/'collector.stdout').write_bytes(r.stdout); (leaf/'collector.stderr').write_bytes(r.stderr)
		new = read(leaf/'ledger.json'); logical,nodes = population(old); assert (logical,nodes) == population(new)
		assert digest(logical) == prior['population_sha256'] and digest(nodes) == prior['node_identity_sha256']
		facts = []; beyond = []; stop = old['diagnostics'][0]; source_cache = {}
		for identity,left,right in zip(nodes,old['nodes'],new['nodes']):
			if right['type'] and right['deferred'] == 0 and (not left['type'] or left['deferred']):
				path = Path(right['path'])
				if path not in source_cache: source_cache[path] = path.read_bytes() if path.exists() else b''
				fact = dict(identity=identity,before=[left['type'],left['flags'],left['deferred']],after=[right['type'],right['flags'],right['deferred']],source_bytes_hex=source_cache[path][right['start']:right['end']].hex()); facts.append(fact)
				if right['path'] == stop['path'] and right['start'] >= stop['end']: beyond.append(fact)
				# Preserve a precise stop even when an independently unsupported contract limits progress.
		(leaf/'new-facts.json').write_text(json.dumps(facts,indent=2)+'\n')
		results[name] = dict(files=len(new['files']),nodes=len(nodes),population_sha256=digest(logical),node_identity_sha256=digest(nodes),typed_before=sum(bool(row['type']) and row['deferred'] == 0 for row in old['nodes']),typed_after=sum(bool(row['type']) and row['deferred'] == 0 for row in new['nodes']),new_checked_facts=len(facts),new_checked_facts_after_call=len(beyond),beyond_call_samples=beyond[:5],first_stop_before=stop,first_stop_after=new['diagnostics'][0] if new['diagnostics'] else None,argv=argv,start=start,end=time.monotonic(),component_sha256=sha(a.component),old_ledger_sha256=sha(PRIOR/('ledger-v1-'+name)/'ledger.json'),new_ledger_sha256=sha(leaf/'ledger.json'),limitation='Exact original checked type-use facts only; whole original throwing caller/compiler admission, native execution and Stage 1 are not established.')
		(RUNTIME/'cohorts-v1.json').write_text(json.dumps(results,indent=2)+'\n'); print(name,results[name]['typed_before'],'->',results[name]['typed_after'],results[name]['first_stop_after'],flush=True)


if __name__ == '__main__':
	main()
