# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Unsuppressed normal paths with one reusable log and reduced observations."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
import sys
sys.dont_write_bytecode=True

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
from output_paths import current_output

def main(build, output):
	output.mkdir(parents=True,exist_ok=True)
	evidence=build/'tests/enum-own-1'
	jobs=[(stage,[build/'tests/enum-own-1'/('astra-enum-own-'+stage)],0) for stage in ['core','cfg','ssa','native','llvm']]
	jobs += [('compiler-'+name,[build/'astrac','--dump-llvm',evidence/'source'/(name+'.astra')],0) for name in ['copied-outcomes','generic-owning-forward','nested-replacement-and-ignore','nested-generic-premise']]
	jobs += [('reject-'+name,[build/'astrac','--check',evidence/'source'/(name+'.astra')],1) for name in ['phantom-identity','inspection-record-mutate','double-buffer-capture','unstated-element-premise']]
	jobs += [('source-'+name,[evidence/'source'/name],0) for name in ['owning-cleanup','owning-consuming-result','nested-replacement-and-ignore','empty-is-owning','generic-owning-forward','early-loop-cleanup']]
	jobs += [('execution-'+name,[current_output(evidence / 'execution')/name],0) for name in ['matrix-O0-gcc','matrix-preserved-O2-clang','lifecycle-O0-gcc','lifecycle-preserved-O2-clang']]
	options={row['name']:row['value'] for row in json.loads(subprocess.check_output(['meson','introspect',str(build),'--buildoptions']))}
	bindir=Path(options['bindir']); bindir=bindir.relative_to(options['prefix']) if bindir.is_absolute() else bindir
	client=current_output(evidence/'client'); relocated=client/'relocated'/bindir/'astrac'
	assert relocated.read_bytes()==(build/'astrac').read_bytes()
	jobs += [('relocated-compiler',[relocated,'--dump-llvm',*[client/name for name in ['types.astra','produce.astra','consume.astra','main.astra','outcomes.astra']]],0),('relocated-consumer',[client/'consumer'],0)]
	rows=[]; log=output/'current.log'
	for name,command,expected in jobs:
		argv=['valgrind','--vgdb=no','--default-suppressions=no','--leak-check=full','--show-leak-kinds=definite,indirect,possible','--errors-for-leak-kinds=definite,indirect,possible','--error-exitcode=99','--log-file='+str(log),*map(str,command)]
		result=subprocess.run(argv,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,env={**os.environ,'CCACHE_DISABLE':'1'})
		text=log.read_text(); assert 'ERROR SUMMARY:' in text and len(text)<65536
		def count(pattern):
			match=re.search(pattern,text); return int(match[1].replace(',','')) if match else 0
		row={'name':name,'status':result.returncode,'errors':count(r'ERROR SUMMARY: ([\d,]+) errors'),'definite':count(r'definitely lost: ([\d,]+) bytes'),'indirect':count(r'indirectly lost: ([\d,]+) bytes'),'possible':count(r'possibly lost: ([\d,]+) bytes'),'suppressed':count(r'suppressed: ([\d,]+) bytes'),'reachable':count(r'still reachable: ([\d,]+) bytes'),'log_sha256':hashlib.sha256(text.encode()).hexdigest()}
		rows.append(row); (output/'checks.json').write_text(json.dumps(rows,indent=2)+'\n')
		assert result.returncode==expected and row['errors']==row['definite']==row['indirect']==row['possible']==row['suppressed']==0,row
	print(str(len(rows))+' unsuppressed clean normal memory runs')

if __name__=='__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	main(*(Path(arg).resolve() for arg in sys.argv[1:]))
