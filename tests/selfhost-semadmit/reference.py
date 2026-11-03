#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent execution of frozen C0 sources; no candidate algorithm."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time


def main():
	p=argparse.ArgumentParser()
	for name in ('compiler','build','runtime','baseline'):
		p.add_argument('--'+name,type=Path,required=True)
	a=p.parse_args()
	a.runtime.mkdir(parents=True,exist_ok=False)
	a.build.mkdir(parents=True,exist_ok=True)
	rows=[]
	for item in json.loads((a.baseline/'frozen.json').read_text()):
		if not item['execute']: continue
		path=Path(item['paths'][0])
		assert hashlib.sha256(path.read_bytes()).hexdigest()==item['sha256']
		paths=[path]
		if 'int main(' not in path.read_text():
			harness=a.runtime/(item['name']+'-harness.astra')
			harness.write_text('int main(){return 0;}\n')
			paths.append(harness)
		for mode in ('O0','O2'):
			exe=a.build/(item['name']+'-'+mode)
			for stage,argv in [('compile',[a.compiler,'-'+mode,*paths,'-o',exe]),('execute',[exe]),('memory',['valgrind','--default-suppressions=no','--error-exitcode=97','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible',exe])]:
				start=time.monotonic()
				r=subprocess.run(list(map(str,argv)),capture_output=True,cwd=a.build,env=dict(os.environ,CCACHE_DISABLE='1'))
				name=item['name']+'-'+mode+'-'+stage
				(a.runtime/(name+'.stdout')).write_bytes(r.stdout)
				(a.runtime/(name+'.stderr')).write_bytes(r.stderr)
				rows.append(dict(name=name,argv=list(map(str,argv)),exit=r.returncode,seconds=time.monotonic()-start))
				(a.runtime/'commands.json').write_text(json.dumps(rows,indent=2)+'\n')
				assert r.returncode==0,(name,r.stderr.decode()[:3000])
				if stage=='memory': assert b'ERROR SUMMARY: 0 errors' in r.stderr and not re.search(rb'(?:definitely|indirectly|possibly) lost: [1-9]',r.stderr)
			print(item['name'],mode,'compile / execute / memory',flush=True)
	destructor(a.compiler,a.build,a.runtime/'destructor')


def destructor(compiler,build,runtime):
	runtime.mkdir()
	root=Path(__file__).resolve().parents[2]
	source=root/'tests/selfhost-semadmit/destructor.astra'
	provider=root/'tests/selfhost-semadmit/destructor.c'
	obj=build/'destructor.o'
	commands=[('provider',['cc','-std=c11','-O2','-Wall','-Wextra','-Werror','-c',provider,'-o',obj]),('check',[compiler,'--check',source])]
	for mode in ('O0','O2'):
		exe=build/('destructor-'+mode)
		commands.extend([('compile-'+mode,[compiler,'-'+mode,source,'--link-object',obj,'-o',exe]),('execute-'+mode,[exe]),('memory-'+mode,['valgrind','--default-suppressions=no','--error-exitcode=97','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible',exe])])
	rows=[]
	for name,argv in commands:
		start=time.monotonic()
		r=subprocess.run(list(map(str,argv)),capture_output=True,cwd=build,env=dict(os.environ,CCACHE_DISABLE='1'))
		(runtime/(name+'.stdout')).write_bytes(r.stdout)
		(runtime/(name+'.stderr')).write_bytes(r.stderr)
		rows.append(dict(name=name,argv=list(map(str,argv)),exit=r.returncode,seconds=time.monotonic()-start))
		(runtime/'commands.json').write_text(json.dumps(rows,indent=2)+'\n')
		assert r.returncode==0,(name,r.stderr.decode())


if __name__=='__main__':
	main()
