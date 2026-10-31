# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Unsuppressed memory checks on normal compilers, models and generated programs."""
from pathlib import Path
import json
import os
import re
import subprocess
import sys
sys.dont_write_bytecode = True


def main(build, evidence, out):
	out.mkdir(parents=True, exist_ok=True)
	jobs = [(name,[build / 'tests/enum-1' / ('astra-enum-'+name)],0) for name in ('core','cfg','ssa','native','llvm')]
	jobs += [('compiler-success',[build / 'astrac','--dump-llvm',evidence / 'execution/runtime.astra'],0), ('compiler-nested',[build / 'astrac','--dump-llvm',evidence / 'execution/depth-64.astra'],0)]
	jobs += [('compiler-reject-'+name,[build / 'astrac','--check',evidence / 'source' / (name+'.astra')],1) for name in ('indirect-cycle','generic-record-enum-field','nonexhaustive','mixed-pattern')]
	jobs += [('runtime-'+name,[evidence / 'execution' / name],0) for name in ('runtime','depth-64','runtime-O0','runtime-O2','runtime-O2-fma','runtime-preserved-O2','transport-O0','transport-O2','transport-O2-fma')]
	rows = []
	for name, command, expected in jobs:
		log = out / (name+'.log'); argv = ['valgrind','--vgdb=no','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible','--error-exitcode=99','--log-file='+str(log),*map(str,command)]
		p = subprocess.run(argv,capture_output=True,env=dict(os.environ,CCACHE_DISABLE='1')); (out / (name+'.stdout')).write_bytes(p.stdout); (out / (name+'.stderr')).write_bytes(p.stderr)
		text = log.read_text()
		def count(pattern):
			match = re.search(pattern,text); return int(match[1].replace(',','')) if match else 0
		row = dict(name=name,argv=argv,status=p.returncode,errors=count(r'ERROR SUMMARY: ([\d,]+) errors'),definite=count(r'definitely lost: ([\d,]+) bytes'),indirect=count(r'indirectly lost: ([\d,]+) bytes'),possible=count(r'possibly lost: ([\d,]+) bytes'),reachable=count(r'still reachable: ([\d,]+) bytes'),suppressed=count(r'suppressed: ([\d,]+) bytes'))
		rows.append(row); (out / 'results.json').write_text(json.dumps(rows,indent='\t')+'\n')
		assert 'ERROR SUMMARY:' in text and p.returncode == expected and row['errors'] == row['definite'] == row['indirect'] == row['possible'] == row['suppressed'] == 0,row
	print(str(len(rows))+' clean unsuppressed memory runs')


if __name__ == '__main__':
	main(*(Path(arg).resolve() for arg in sys.argv[1:]))
