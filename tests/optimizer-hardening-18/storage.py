#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Executed storage ablation with independent ordered destructor observations."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
	parser=argparse.ArgumentParser(description=__doc__)
	parser.add_argument('compiler',type=Path)
	parser.add_argument('build',type=Path)
	parser.add_argument('runtime',type=Path)
	parser.add_argument('--checked',action='store_true',help='exercise success and checked-error cleanup paths')
	args=parser.parse_args()
	compiler=args.compiler.resolve(strict=True)
	source=HERE/('checked-storage.astra' if args.checked else 'storage.astra')
	for p in [args.build,args.runtime]:
		assert not p.resolve().is_relative_to(ROOT)
		p.mkdir(parents=True,exist_ok=True)
	build=Path(tempfile.mkdtemp(prefix='storage-',dir=args.build.resolve()))
	runtime=Path(tempfile.mkdtemp(prefix='storage-',dir=args.runtime.resolve()))
	receipt={'compiler_sha256':sha(compiler),'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
		'inputs':{str(p.relative_to(ROOT)):sha(p) for p in [source,HERE/'storage-observer.c',Path(__file__).resolve(),ROOT/'bootstrap/ssa/ssa-stack-objects.vala',ROOT/'bootstrap/ssa/ssa-stack-object-verifier.vala']},'checks':[],'products':{}}
	production = [ROOT / name for name in subprocess.check_output(
		['git','ls-files','-z','--','bootstrap','lib','tools','meson.build','meson.options'],cwd=ROOT).decode().split('\0') if name]
	production.append(ROOT/'bootstrap/ssa/ssa-stack-object-verifier.vala')
	production.append(ROOT/'bootstrap/ssa/ssa-shared-balance.vala')
	receipt['production_snapshot'] = {str(p.relative_to(ROOT)): sha(p) for p in production}
	def save(): (runtime/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n')
	def run(command,mode='on',expected_stdout=None):
		command=list(map(str,command));start=time.monotonic()
		p=subprocess.run(command,cwd=build,capture_output=True,text=True,timeout=90,
			env=dict(os.environ,CCACHE_DISABLE='1',ASTRA_TEST_OPTIMIZATIONS=mode,ASTRA_EXPLAIN_OPTIMIZATIONS='1',DEBUGINFOD_URLS=''))
		row=dict(command=command,mode=mode,exit=p.returncode,stdout=p.stdout,stderr=p.stderr,seconds=time.monotonic()-start)
		row['passed']=p.returncode==0 and not p.stderr and (expected_stdout is None or p.stdout==expected_stdout)
		receipt['checks'].append(row);save();assert row['passed'],row
		return p.stdout
	provider=build/'observer.o'
	run(['clang','-std=c11','-O2','-fno-builtin','-Wall','-Wextra','-Werror','-c',HERE/'storage-observer.c','-o',provider])
	renamed=source.read_text().replace('Local18','TelemetryState18').replace('independent18','combine18').replace('mixed18','return_with_local18').replace('Cleanup18','TelemetryCleanup18').replace('Failure18','TelemetryFailure18').replace('unwind18','checked_transform18')
	for variant,text in [('original',source.read_text()),('renamed',renamed)]:
		selected=build/(variant+'.astra');selected.write_text(text)
		ssa=run([compiler,'--dump-ssa',selected]);(build/(variant+'.ssa')).write_text(ssa)
		assert ssa.count('(stack-object')==(2 if args.checked else 4),ssa
		for level in '012':
			for mode in ['off','on']:
				exe=build/f'{variant}-O{level}-{mode}'
				run([compiler,'-O'+level,selected,'--link-object',provider,'-o',exe],mode)
				if args.checked:
					expected='retire=11\nretire=1\nretire=9\nretire=-1\ncaught\n'+f'allocations={1 if mode=="on" else 5} retired=4\n'
				else:
					expected=''.join(f'retire={n}\n' for n in [10,0,13,3,39,9,7,27])+f'allocations={2 if mode=="on" else 8} retired=8\n'
				run([exe],mode,expected)
				memory=run(['valgrind','--quiet','--default-suppressions=no','--error-exitcode=99','--leak-check=full','--errors-for-leak-kinds=all',exe],mode)
				# Valgrind redirects allocation functions, including this observer's
				# calloc. Its counter is not a native allocation measurement.
				assert memory.splitlines()[:-1]==expected.splitlines()[:-1]
				assert re.fullmatch(r'allocations=\d+ retired='+('4' if args.checked else '8')+r'\n',memory.splitlines(keepends=True)[-1])
				ir=build/(exe.name+'.ll');ir.write_text(run([compiler,'-O'+level,'--dump-llvm',selected],mode))
				assembly=build/(exe.name+'.asm');assembly.write_text(run(['objdump','-dr',exe]))
				sections=run(['size','-A',exe])
				receipt['products'][exe.name]={'sha256':sha(exe),'bytes':exe.stat().st_size,'sections':sections,'ir_sha256':sha(ir),'disassembly_sha256':sha(assembly)};save()
	assert sha(compiler)==receipt['compiler_sha256']
	assert all(sha(ROOT/name)==value for name,value in receipt['production_snapshot'].items())
	receipt['production_unchanged_during_ablation']=True;save()
	print(runtime/'checks.json')


if __name__=='__main__': main()
