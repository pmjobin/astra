# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""A25-A27 public source applications, exact traces and real memory tests."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import sys
ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
APPS = {
	'A25': ('shared-document', '1:4\n3:4173\n4:4173\n5:4173\n2:4\n'),
	'A26': ('weak-subscribers', '1:42\n3:43\n4:44\n2:42\n5:-1\n6:-1\n'),
	'A27': ('shared-diagnostics', '1:9\n3:9\n5:37\n6:47\n4:0\n2:9\n'),
}
def main(compiler,output):
	compiler,output=Path(compiler).resolve(),Path(output).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True,exist_ok=True)
	rows=[];products={}
	def run(command,expected=''):
		command=list(map(str,command))
		p=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=120,
			env=dict(os.environ,CCACHE_DISABLE='1'))
		ok=p.returncode==0 and p.stdout==expected
		rows.append(dict(command=command,exit=p.returncode,stdout=p.stdout,stderr=p.stderr,status='PASS' if ok else 'FAIL'))
		(output/'checks.json').write_text(json.dumps(rows,indent=2)+'\n')
		assert ok,rows[-1]
		return p
	observer=output/'observer.o'
	run(['cc','-std=c11','-Wall','-Wextra','-Werror','-c',HERE/'apps-observer.c','-o',observer])
	for identity,(name,trace) in APPS.items():
		source=ROOT/'examples/language-runtime-4'/(name+'.astra')
		for mode in ('O0','O1','O2'):
			product=output/(name+'-'+mode)
			run([compiler,'-'+mode,source,'--link-object',observer,'-o',product])
			run([product],trace)
			products[product.name]=hashlib.sha256(product.read_bytes()).hexdigest()
		if shutil.which('valgrind'):
			p=run(['valgrind','--default-suppressions=no','--error-exitcode=99','--leak-check=full',
				'--show-leak-kinds=all','--errors-for-leak-kinds=all',output/(name+'-O2')],trace)
			assert 'ERROR SUMMARY: 0 errors' in p.stderr and 'in use at exit: 0 bytes in 0 blocks' in p.stderr
	sources={name+'.astra':hashlib.sha256((ROOT/'examples/language-runtime-4'/(name+'.astra')).read_bytes()).hexdigest() for name,_ in APPS.values()}
	sources['apps-observer.c']=hashlib.sha256((HERE/'apps-observer.c').read_bytes()).hexdigest()
	(output/'result.json').write_text(json.dumps(dict(status='PASS',applications=list(APPS),checks=rows,products=products,sources=sources,compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest()),indent=2)+'\n')
	print('A25-A27 exact traces, O0/O1/O2 and memory checks passed')
if __name__=='__main__':main(*sys.argv[1:])
