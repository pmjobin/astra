#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Backend-only actual IR faults, upstream status preservation and resource safety."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess
import time
from oracle import memory

MUTATIONS = ['wrong-phi-value','extra-wrong-phi-edge','wrong-predicate','wrong-extension','wrong-constant-operand','unproved-nsw','unproved-nuw','unproved-inbounds','reversed-branch','wrong-return-value','swapped-call-arguments','wrong-return-ABI','false-noalias','omitted-cleanup','duplicate-cleanup','wrong-cleanup-pointer','wrong-load-place','wrong-target','wrong-layout','forged-verification-success']


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	p = argparse.ArgumentParser()
	for key in ('component','runtime','frozen'):
		p.add_argument('--'+key,type=Path,required=True)
	p.add_argument('--mode',choices=('O0','O2'),required=True)
	a = p.parse_args()
	a.runtime.mkdir(parents=True,exist_ok=False)
	commands = []
	def run(argv,name,expected=0,timeout=60):
		start = time.monotonic()
		r = subprocess.run(list(map(str,argv)),capture_output=True,timeout=timeout)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(argv=list(map(str,argv)),exit=r.returncode,monotonic_start=start,monotonic_end=time.monotonic(),stdout_sha256=hashlib.sha256(r.stdout).hexdigest(),stderr_sha256=hashlib.sha256(r.stderr).hexdigest()))
		(a.runtime/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
		assert r.returncode == expected,(name,r.returncode,r.stderr[-1500:])
		return r
	items = json.loads((a.frozen/'selection.json').read_text())
	selection = {'ssa-diamond','ssa-counter','numeric-conversions','numeric-wrapping','ssa-field-memory','ssa-argument-order'}
	mutations = []
	killed = set()
	for item in items:
		if item['name'] not in selection:
			continue
		source = Path(item['source_path']); assert sha(source) == item['source_sha256']
		artifact = a.runtime/(item['name']+'.forbidden.o')
		r = run([a.component,'--mutate-llvm',a.mode,artifact,source],item['name']+'-mutations')
		assert not artifact.exists() and not list(a.runtime.glob('*.o.*'))
		for line in r.stdout.splitlines():
			x = line.split(); assert len(x) == 5 and x[0] == b'LLVM_MUTATION',x[:2]
			index = int(x[1]); before,mutant,restored = map(bytes.fromhex,[v.decode() for v in x[2:]])
			assert before == restored and before != mutant
			killed.add(index)
			mutations.append(dict(case=item['name'],category=MUTATIONS[index],index=index,before_sha256=hashlib.sha256(before).hexdigest(),mutant_sha256=hashlib.sha256(mutant).hexdigest(),restored_sha256=hashlib.sha256(restored).hexdigest(),upstream='independently verified SSA before every attempt and after byte-exact SSA backing restoration',restoration='new LLVM owner, identical IR'))
		for command in ('--llvm-limits','--llvm-lifecycle'):
			run([a.component,command,a.mode,artifact,source],item['name']+command)
			assert not artifact.exists()
	assert killed == set(range(20)),sorted(set(range(20))-killed)
	item = items[0]
	sentinel = a.runtime/'existing-destination.sentinel'
	sentinel.write_bytes(b'pre-existing private output identity\n')
	run([a.component,'--llvm-limits',a.mode,sentinel,item['source_path']],'preserve-existing-destination')
	assert sentinel.read_bytes() == b'pre-existing private output identity\n'
	r = run([a.component,'--emit-obj',a.mode,a.runtime/'missing-parent/output.o',item['source_path']],'output-failure',2)
	assert b'LLVM_OUTPUT_FAILURE' in r.stderr and not (a.runtime/'missing-parent').exists()
	mapping = []
	for item in json.loads((a.frozen/'predecessor.json').read_text()):
		artifact = a.runtime/(item['name']+'.forbidden.o')
		upstream = run([a.component,'--ssa',*item['paths']],item['name']+'-upstream',item['core_status'])
		if item['core_status']:
			r = run([a.component,'--emit-obj',a.mode,artifact,*item['paths']],item['name']+'-backend',2)
			assert not r.stdout and b'LLVM_INVALID_UPSTREAM' in r.stderr and not artifact.exists()
			status = 'SSA_DEFERRED' if item['core_status'] == 3 else 'SSA_INVALID'
		else:
			# Positives are enumerated even if outside the frozen execution pool.
			r = subprocess.run(list(map(str,[a.component,'--llvm-raw',a.mode,artifact,*item['paths']])),capture_output=True,timeout=60)
			(a.runtime/(item['name']+'-matrix.stdout')).write_bytes(r.stdout); (a.runtime/(item['name']+'-matrix.stderr')).write_bytes(r.stderr)
			if r.returncode == 0:
				assert artifact.exists(); artifact.unlink(); status = 'LLVM_IR_VERIFIED'
			else:
				assert r.returncode == 2 and b'LLVM_DEFERRED' in r.stderr and not artifact.exists(),(item['name'],r.returncode,r.stderr)
				status = 'LLVM_DEFERRED'
		used_types = []
		if item['core_status'] == 0:
			rows = {}
			for line in upstream.stdout.decode().splitlines():
				x = line.split()
				if x and x[0] in {'SSA_VALUE','PLACE','FUNCTION'}:
					rows.setdefault(x[0],[]).append(x[1:])
			active = {int(x[7]) for x in rows.get('SSA_VALUE',[])} | {int(x[6]) for x in rows.get('PLACE',[])} | {int(x[3]) for x in rows.get('FUNCTION',[])}
			used_types = sorted(active)
		mapping.append(dict(active_type_ids=used_types,name=item['name'],source_sha256=item['sha256'],ssa_status=item['core_status'],llvm_status=status,diagnostic=r.stderr.decode()))
		# Real unsuppressed LLVM lifecycle/error-path runs, separate from fatal apps.
	memory_rows = []
	for name,command in [('ssa-diamond','--llvm-lifecycle'),('ssa-argument-order','--llvm-limits'),('ssa-borrow-end','--emit-obj'),('numeric-conversions','--mutate-llvm')]:
		item = next(x for x in items if x['name'] == name)
		artifact = a.runtime/(name+'.memory-forbidden.o')
		r = run(['valgrind','--default-suppressions=no','--error-exitcode=97','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible',a.component,command,a.mode,artifact,item['source_path']],name+'-lifecycle-memory',timeout=180)
		memory_rows.append(dict(name=name,command=command,result=memory(r.stderr),product_sha256=sha(artifact) if artifact.exists() else None))
		if command == '--emit-obj':
			assert artifact.is_file()
		else:
			assert not artifact.exists()
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS',mode=a.mode,component_sha256=sha(a.component),categories=20,mutations=mutations,mapping=mapping,outcomes=dict(Counter(x['llvm_status'] for x in mapping)),memory=memory_rows),indent=2)+'\n')
	print(a.mode,'20 backend categories rejected; 80 upstream statuses retained',flush=True)


if __name__ == '__main__':
	main()
