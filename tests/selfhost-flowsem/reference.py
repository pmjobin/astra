#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independently compile frozen C0 positives; execute meaningful runtime cases."""
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
	p.add_argument('--compiler',type=Path,required=True)
	p.add_argument('--baseline',type=Path,required=True)
	p.add_argument('--build',type=Path,required=True)
	p.add_argument('--runtime',type=Path,required=True)
	a=p.parse_args()
	a.build.mkdir(parents=True,exist_ok=True)
	a.runtime.mkdir(parents=True,exist_ok=False)
	entries=json.loads((a.baseline/'frozen.json').read_text())
	rows=[]
	assert hashlib.sha256(a.compiler.read_bytes()).hexdigest()==json.loads((a.baseline/'compiler.json').read_text())['sha256']
	def run(argv,name,expected=0):
		start=time.monotonic()
		r=subprocess.run(list(map(str,argv)),cwd=a.build,capture_output=True,env=dict(os.environ,CCACHE_DISABLE='1'))
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout)
		(a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		rows.append(dict(argv=list(map(str,argv)),exit=r.returncode,seconds=time.monotonic()-start))
		assert r.returncode==expected,(name,r.stderr.decode()[-4000:])
		return r
	try:
		for item in entries:
			if item.get('error') or item.get('deferred'):
				continue
			for path,digest in item['sha256'].items():
				assert hashlib.sha256(Path(path).read_bytes()).hexdigest()==digest
			for mode in ('O0','O2'):
				paths=list(item['paths'])
				if not item.get('execute') and item['name']!='owner-null':
					harness=a.runtime/(item['name']+'-main.astra')
					harness.write_text('int main(){return 0;}\n')
					paths.append(str(harness))
				exe=a.build/(item['name']+'-'+mode)
				run(['/usr/bin/time','-v',a.compiler,'-'+mode,*paths,'-o',exe],item['name']+'-compile-'+mode)
				if item.get('execute') or item['name']=='owner-null':
					run([exe],item['name']+'-execute-'+mode)
					r=run(['valgrind','--default-suppressions=no','--error-exitcode=97','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible',exe],item['name']+'-memory-'+mode)
					assert b'ERROR SUMMARY: 0 errors' in r.stderr and not re.search(rb'(?:definitely|indirectly|possibly) lost: [1-9]',r.stderr)
				print(item['name'],mode,'compiled'+(' / executed / memory' if item.get('execute') or item['name']=='owner-null' else ''),flush=True)
	finally:
		(a.runtime/'commands.json').write_text(json.dumps(rows,indent=2)+'\n')


if __name__=='__main__':
	main()
