#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""New LLVM-valid member-call alternatives, checked by source assertions, ABI and memory."""
import argparse
import json
import os
from pathlib import Path
import re
import resource
import subprocess
import time
import xml.etree.ElementTree as ET
from state import ROOT, RUNTIME, BUILD, read, sha


def main():
	resource.setrlimit(resource.RLIMIT_CORE,(0,0))
	p = argparse.ArgumentParser(); p.add_argument('--qualification',type=Path,required=True); p.add_argument('--mode',choices=('O0','O2'),required=True); a = p.parse_args()
	leaf = RUNTIME/('physical-'+a.mode); build = BUILD/leaf.name; leaf.mkdir(exist_ok=False); build.mkdir(exist_ok=False)
	row = next(row for row in read(a.qualification/'results.json') if row['name'] == 'independent-nested-order'); assert row['baseline_complete']
	assert all(sha(s['path']) == s['sha256'] for s in row['sources']) and all(sha(x['path']) == x['sha256'] for x in row['products'].values())
	measured = (a.qualification/'independent-nested-order-ABI-probe.stdout').read_text(); assert 'LAYOUT Sample 4 4 1\n' in measured
	raw = Path(row['products']['raw']['path']); text = raw.read_text()
	inner = re.search(r'^  (?P<result>%[\w.]+) = call \{ i32 \} (?P<fn>@[\w.]+)\(ptr (?P<receiver>%[\w.]+), i32 7\)\n',text,re.M); assert inner
	outer = re.search(r'^  (?P<result>%[\w.]+) = call i32 (?P<fn>@[\w.]+)\(ptr (?P<receiver>%[\w.]+), \{ i32 \} (?P<argument>%[\w.]+)\)\n',text,re.M); assert outer
	def replace(match,replacement): return text[:match.start()]+replacement+text[match.end():]
	variants = {
		'wrong-Class-receiver': replace(inner,inner[0].replace('ptr '+inner['receiver'],'ptr null',1)),
		'stale-inner-input': replace(inner,inner[0].replace('i32 7','i32 8')),
		'duplicated-inner-effect': replace(inner,inner[0]+inner[0].replace(inner['result']+' =','%callplace.duplicate =',1)),
		'omitted-outer-effect': replace(outer,'  '+outer['result']+' = add i32 0, 7\n'),
		'lost-owner-cleanup': re.sub(r'^  call void @free\(ptr [^\n]+\)(?: #[0-9]+)?\n','',text,flags=re.M),
	}
	assert variants['lost-owner-cleanup'] != text
	function = re.search(r'^define (?:internal )?\{ i32 \} '+re.escape(inner['fn'])+r'\(ptr (?P<receiver>%[\w.]+), i32 [^\n]+\n.*?^}\n',text,re.M|re.S); assert function
	old_function = function[0]; receiver = function['receiver']; body_start = old_function.index('\n')+1
	header = old_function[:body_start].replace('ptr '+receiver,'i64 '+receiver,1)
	body = re.sub(re.escape(receiver)+r'(?![\w.])','%callplace.receiver.ptr',old_function[body_start:])
	label = re.search(r'^[\w.]+:[^\n]*\n',body,re.M); assert label
	body = body[:label.end()]+'  %callplace.receiver.ptr = inttoptr i64 '+receiver+' to ptr\n'+body[label.end():]
	abi = text[:function.start()]+header+body+text[function.end():]
	call = inner[0]; converted = '  %callplace.receiver.bits = ptrtoint ptr '+inner['receiver']+' to i64\n'+call.replace('ptr '+inner['receiver'],'i64 %callplace.receiver.bits',1)
	abi = abi.replace(call,converted,1); variants['wrong-borrowed-receiver-signature'] = abi
	ret = re.search(r'^  ret \{ i32 \} [^\n]+\n',old_function,re.M); assert ret
	variants['wrong-record-result-binding'] = text[:function.start()]+old_function[:ret.start()]+'  ret { i32 } zeroinitializer\n'+old_function[ret.end():]+text[function.end():]
	commands = []; results = []; env = dict(os.environ,CCACHE_DISABLE='1'); env.pop('VALGRIND_OPTS',None); env.pop('LD_PRELOAD',None)
	def run(argv,name):
		start = time.monotonic(); r = subprocess.run(['/usr/bin/time','-v','-o',leaf/(name+'.time'),*map(str,argv)],cwd=build,capture_output=True,env=env,timeout=180)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name,argv=list(map(str,argv)),exit=r.returncode,start=start,end=time.monotonic())); (leaf/'commands.json').write_text(json.dumps(commands,indent=2)+'\n'); return r
	assert run([row['products']['native']['path']],'valid-twin').returncode == 63
	for name,candidate in variants.items():
		assert candidate != text; path = build/(name+'.ll'); path.write_text(candidate)
		assert run(['opt','-passes=verify','-disable-output',path],name+'-LLVM-verify').returncode == 0
		obj = path.with_suffix('.o'); elf = path.with_suffix('')
		assert run(['llc','-'+a.mode,'-relocation-model=pic','-filetype=obj',path,'-o',obj],name+'-lower').returncode == 0
		assert run(['gcc',obj,'-o',elf],name+'-link').returncode == 0
		xml = leaf/(name+'.xml'); r = run(['valgrind','--command-line-only=yes','--default-suppressions=no','--error-exitcode=97','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=all','--track-origins=yes','--xml=yes','--xml-file='+str(xml),elf],name+'-execute'); errors = len(ET.parse(xml).getroot().findall('error'))
		# The private ABI requires a pointer-valued borrowed Class receiver.
		# i64 transport is LLVM-valid and may preserve LP64 bits at runtime; it
		# still violates that independently stated source/ABI contract.
		abi_rejected = name == 'wrong-borrowed-receiver-signature' and re.search(r'^define (?:internal )?\{ i32 \} '+re.escape(inner['fn'])+r'\(ptr ',candidate,re.M) is None
		assert r.returncode != 63 or errors > 0 or abi_rejected,name
		assert sha(raw) == row['products']['raw']['sha256'] and run([row['products']['native']['path']],name+'-restored-twin').returncode == 63
		results.append(dict(category=name,LLVM_valid=True,runtime_exit=r.returncode,Valgrind_errors=errors,independent_ABI_rejected=abi_rejected,independently_rejected=True,IR_sha256=sha(path),object_sha256=sha(obj),ELF_sha256=sha(elf))); print(a.mode,name,'LLVM_VALID INDEPENDENTLY_REJECTED',flush=True)
	assert len(results) == 7
	(leaf/'result.json').write_text(json.dumps(dict(status='PASS',mode=a.mode,mutations=results,commands=commands,recipe_sha256=sha(__file__),boundary='External LLVM verifier, independently stated private pointer receiver ABI, explicit C0-matched source assertions and unsuppressed Valgrind. Post-emission alternatives are not claimed to be inputs to Astra retained-module audit.'),indent=2)+'\n')


if __name__ == '__main__':
	main()
