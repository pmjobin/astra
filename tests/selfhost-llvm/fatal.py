#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Intentional fatal controls, excluded from ordinary leak/unwinding claims."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import subprocess
import time


def main():
	p = argparse.ArgumentParser()
	for key in ('component','compiler','build','runtime','frozen'):
		p.add_argument('--'+key,type=Path,required=True)
	p.add_argument('--mode',choices=('O0','O2'),required=True)
	a = p.parse_args()
	a.runtime.mkdir(parents=True,exist_ok=False); a.build.mkdir(parents=True,exist_ok=True)
	resource.setrlimit(resource.RLIMIT_CORE,(0,0))
	cases = [x for x in json.loads((a.frozen/'predecessor.json').read_text()) if x['name'] in {'source-order-trap','short-fatal-and','short-fatal-or'}]
	assert len(cases) == 3
	commands = []
	results = []
	for item in cases:
		path = Path(item['paths'][0]); assert hashlib.sha256(path.read_bytes()).hexdigest() == item['sha256']
		obj = a.build/(item['name']+'.o'); native = obj.with_suffix('.native'); c0 = obj.with_suffix('.c0')
		steps = [('emit',[a.component,'--emit-obj',a.mode,obj,path],0),('link',['gcc',obj,'-o',native],0),('compile',[a.compiler,'-'+a.mode,path,'-o',c0],0),('native',[native],-4),('C0',[c0],-4)]
		for stage,argv,expected in steps:
			start = time.monotonic(); r = subprocess.run(list(map(str,argv)),capture_output=True,cwd=a.build,timeout=60,env=dict(os.environ,CCACHE_DISABLE='1'))
			(a.runtime/(item['name']+'-'+stage+'.stdout')).write_bytes(r.stdout); (a.runtime/(item['name']+'-'+stage+'.stderr')).write_bytes(r.stderr)
			commands.append(dict(name=item['name'],stage=stage,argv=list(map(str,argv)),exit=r.returncode,monotonic_start=start,monotonic_end=time.monotonic()))
			(a.runtime/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
			assert r.returncode == expected and not r.stdout and not r.stderr,(item['name'],stage,r.returncode,r.stderr)
		results.append(dict(name=item['name'],source_sha256=item['sha256'],native_sha256=hashlib.sha256(native.read_bytes()).hexdigest(),C0_sha256=hashlib.sha256(c0.read_bytes()).hexdigest(),signal=4,normal_leak_claim=False))
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS',mode=a.mode,cases=results),indent=2)+'\n')
	print(a.mode,'3 fresh SIGILL controls matched independently',flush=True)


if __name__ == '__main__':
	main()
