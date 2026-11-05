#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Read actual inference operands at the unchanged observer's call boundary."""
import json
import argparse
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version',default='v2'); a = p.parse_args(); assert a.version.replace('-','').isalnum()
	leaf = RUNTIME/('inference-operands-'+a.version); leaf.mkdir(exist_ok=False)
	product = BUILD/'diagnosis-v3/diagnose-O0'; identity = read(product.with_suffix('.identity.json'))
	assert sha(product) == identity['sha256']
	assert all(sha(path) == value for group in ('sources','tools') for path,value in identity['identity'][group].items())
	# This O0 product has no DWARF source names. The read-only disassembly binds
	# the diagnostic's select-call function to its direct generic_unify call.
	# SysV arguments at that call are index, origin, enclosing, pattern, actual,
	# argument-array base/count, depth. No inferior function call or write occurs.
	disassembly = subprocess.check_output(['objdump','-d','--start-address=0x4b0990','--stop-address=0x4b0b20',product])
	assert b'4b0a3b:' in disassembly and b'4aee70 <astra.fn.127>' in disassembly and b'403000' in disassembly
	(leaf/'call-boundary.disassembly.txt').write_bytes(disassembly)
	results = {}; initial = read(RUNTIME/'initial.json')
	for name,node,origin,pattern,enclosing in [('original',40833,2097,54,197),('LLVM23-base',42968,2184,55,198),('Class15-current',46736,2309,53,202),('live-initial',47584,2324,53,202)]:
		condition = '*(int*)($rsp+0x304) == '+str(node)
		commands = '\n'.join(['commands','silent','printf "INFERENCE_OPERANDS node=%d origin=%d enclosing=%d pattern=%d actual=%d count=%d depth=%d\\n", *(int*)($rsp+0x304), $esi, $edx, $ecx, $r8d, *(int*)$rsp, *(int*)($rsp+8)','continue','end'])
		script = leaf/(name+'.gdb'); script.write_text('set pagination off\nbreak *0x4b0a3b if '+condition+'\n'+commands+'\nrun\n')
		argv = ['gdb','-q','-batch','-x',str(script),'--args',str(product),*initial['cohorts'][name]['argv'][4:]]
		start = time.monotonic(); r = subprocess.run(['/usr/bin/time','-v','-o',leaf/(name+'.time'),*argv],cwd=ROOT,capture_output=True,timeout=120)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		assert r.returncode == 0
		actual = [line for line in r.stdout.decode().splitlines() if line.startswith('INFERENCE_OPERANDS ')]
		expected = f'INFERENCE_OPERANDS node={node} origin={origin} enclosing={enclosing} pattern={pattern} actual=0 count=0 depth=0'
		assert actual == [expected],actual
		results[name] = dict(argv=argv,exit=r.returncode,start=start,end=time.monotonic(),observation=actual[0],stdout_sha256=sha(leaf/(name+'.stdout')),stderr_sha256=sha(leaf/(name+'.stderr')))
		(leaf/'result.json').write_text(json.dumps(dict(status='ACTUAL_OPERANDS_OBSERVED',product_sha256=sha(product),disassembly_sha256=sha(leaf/'call-boundary.disassembly.txt'),results=results,limitation='Product-specific debugging addresses are observation-only. They are neither an implementation dispatch rule nor a source/fingerprint admission mechanism.'),indent=2)+'\n')
		print(name,actual[0],flush=True)
	assert sha(product) == identity['sha256']


if __name__ == '__main__':
	main()
