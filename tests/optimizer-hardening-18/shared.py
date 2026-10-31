#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Executed Shared balance proofs and instruction-traced native retain costs."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import resource
import subprocess
import tempfile
import time

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
EXPECTED='retire=0\nretire=3\nretire=4\nobserve=5\nretire=5\nretire=6\n'


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
	parser=argparse.ArgumentParser(description=__doc__)
	parser.add_argument('compiler',type=Path);parser.add_argument('build',type=Path);parser.add_argument('runtime',type=Path)
	args=parser.parse_args();compiler=args.compiler.resolve(strict=True)
	for p in [args.build,args.runtime]:
		assert not p.resolve().is_relative_to(ROOT);p.mkdir(parents=True,exist_ok=True)
	build=Path(tempfile.mkdtemp(prefix='shared-',dir=args.build.resolve()))
	runtime=Path(tempfile.mkdtemp(prefix='shared-',dir=args.runtime.resolve()))
	inputs=[HERE/'shared.astra',HERE/'shared-observer.c',Path(__file__).resolve(),ROOT/'bootstrap/ssa/ssa-shared-balance.vala',ROOT/'bootstrap/ssa/ssa-shared-elision.vala']
	receipt={'compiler_sha256':sha(compiler),'inputs':{str(p.relative_to(ROOT)):sha(p) for p in inputs},'checks':[],'products':{},
		'trace_scope':'Lackey instruction traces of linked executable lock cmpxchg sites; excludes shared libraries; task-owned trace files capped at 64 MiB'}
	production=[ROOT/name for name in subprocess.check_output(['git','ls-files','-z','--','bootstrap','lib','tools','meson.build','meson.options'],cwd=ROOT).decode().split('\0') if name]
	production.append(ROOT/'bootstrap/ssa/ssa-shared-balance.vala')
	receipt['production_snapshot']={str(p.relative_to(ROOT)):sha(p) for p in production}
	def save(): (runtime/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n')
	def run(command,mode='on',expected_stdout=None,limits=None):
		command=list(map(str,command));started=time.monotonic()
		p=subprocess.run(command,cwd=build,capture_output=True,text=True,timeout=45,
			env=dict(os.environ,CCACHE_DISABLE='1',ASTRA_TEST_OPTIMIZATIONS=mode,ASTRA_EXPLAIN_OPTIMIZATIONS='1',DEBUGINFOD_URLS='',LC_ALL='C'),preexec_fn=limits)
		row=dict(command=command,mode=mode,exit=p.returncode,stdout=p.stdout,stderr=p.stderr,seconds=time.monotonic()-started)
		row['passed']=p.returncode==0 and not p.stderr and (expected_stdout is None or p.stdout==expected_stdout)
		receipt['checks'].append(row);save();assert row['passed'],row
		return p.stdout
	provider=build/'observer.o';run(['clang','-std=c11','-O2','-Wall','-Wextra','-Werror','-c',HERE/'shared-observer.c','-o',provider])
	def trace_limits():
		resource.setrlimit(resource.RLIMIT_FSIZE,(64*1024**2,64*1024**2));resource.setrlimit(resource.RLIMIT_CPU,(20,20));resource.setrlimit(resource.RLIMIT_CORE,(0,0))
	text=(HERE/'shared.astra').read_text()
	for variant,body in [('original',text),('renamed',text.replace('Payload18','Measurement18').replace('spaced18','transform18').replace('pure18','affine18'))]:
		source=build/(variant+'.astra');source.write_text(body)
		ssa=run([compiler,'--dump-ssa',source]);(build/(variant+'.ssa')).write_text(ssa)
		assert ssa.count('(shared-elision')==1,ssa
		for level in '012':
			for mode in ['off','on']:
				exe=build/f'{variant}-O{level}-{mode}'
				run([compiler,'-O'+level,source,'--link-object',provider,'-o',exe],mode)
				run([exe],mode,EXPECTED)
				run(['valgrind','--quiet','--default-suppressions=no','--error-exitcode=99','--leak-check=full','--errors-for-leak-kinds=all',exe],mode,EXPECTED)
				assembly=run(['objdump','-dr',exe]);(build/(exe.name+'.asm')).write_text(assembly)
				ir=run([compiler,'-O'+level,'--dump-llvm',source],mode);(build/(exe.name+'.ll')).write_text(ir)
				row={'sha256':sha(exe),'bytes':exe.stat().st_size,'ir_sha256':hashlib.sha256(ir.encode()).hexdigest(),
					'assembly_sha256':hashlib.sha256(assembly.encode()).hexdigest(),'static_cmpxchg':len(re.findall(r'\block\s+cmpxchg',assembly))}
				if level=='2':
					assert 'EXEC (Executable file)' in run(['readelf','-h',exe])
					addresses={int(m[1],16) for m in re.finditer(r'^\s*([0-9a-f]+):[^\n]*\block\s+cmpxchg',assembly,re.M)}
					trace=runtime/(exe.name+'.trace')
					run(['valgrind','--tool=lackey','--basic-counts=no','--trace-mem=yes','--log-file='+str(trace),exe],mode,EXPECTED,trace_limits)
					counts={address:0 for address in addresses}
					with trace.open() as stream:
						for line in stream:
							match=re.match(r'I\s+([0-9a-fA-F]+),',line)
							if match and int(match[1],16) in counts: counts[int(match[1],16)]+=1
					row['executed_cmpxchg']=sum(counts.values());row['cmpxchg_sites']={hex(k):v for k,v in counts.items()}
					row['trace_sha256']=sha(trace);row['trace_bytes']=trace.stat().st_size
					receipt['products'][exe.name]=row;save()
					assert row['executed_cmpxchg']==(18 if mode=='on' else 22),row
				receipt['products'][exe.name]=row;save()
	assert sha(compiler)==receipt['compiler_sha256'] and all(sha(ROOT/name)==value for name,value in receipt['inputs'].items())
	assert all(sha(ROOT/name)==value for name,value in receipt['production_snapshot'].items())
	receipt['production_unchanged_during_ablation']=True;save()
	print(runtime/'checks.json')


if __name__=='__main__': main()
