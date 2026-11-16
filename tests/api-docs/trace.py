#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Read-only source-refusal trace for the exact immutable 27-D Stage3 producer."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

PIN = '560e7c9eaeb6cdb974efdd43ed4ac41191cdda4acdb4afd77052325addf1f1c6'
ROOT = Path(__file__).resolve().parents[2]

SCRIPT = '''set pagination off
set confirm off
set debuginfod enabled off
python
import gdb
u64=lambda p: int.from_bytes(gdb.selected_inferior().read_memory(p,8).tobytes(),'little')
u32=lambda p: int.from_bytes(gdb.selected_inferior().read_memory(p,4).tobytes(),'little')
class Returned(gdb.FinishBreakpoint):
 def __init__(self,node,span):
  super().__init__(gdb.newest_frame(),internal=True);self.node=node;self.span=span
 def stop(self):
  if (int(gdb.parse_and_eval('$eax'))&1)==0:
   print('INDEPENDENT_CHILD_REFUSAL',self.node,'SOURCE_SPAN',self.span);return True
  return False
class Enter(gdb.Breakpoint):
 def stop(self):
  checked=int(gdb.parse_and_eval('$rsi'));arena=u64(u64(u64(checked)));headers=u64(arena+240);node=int(gdb.parse_and_eval('$r8d'));capacity=u32(arena+248)
  assert node<capacity
  span=[u32(headers+node*36+20),u32(headers+node*36+24),u32(headers+node*36+28)]
  if span[0] in ALLOWED:Returned(node,span)
  return False
Enter('*0x51a7c0',internal=True)
end
run
bt 4
quit
'''

PAYLOAD_SCRIPT = '''set pagination off
set confirm off
set debuginfod enabled off
break *0x52df37 if (($ebx & 1) == 0)
break *0x52cd27
run
info registers rax rbx rcx rdx rsi rdi r12 r13 r14 r15 rsp
x/96wx $rsp
python
import gdb
u64=lambda p: int.from_bytes(gdb.selected_inferior().read_memory(p,8).tobytes(),'little')
u32=lambda p: int.from_bytes(gdb.selected_inferior().read_memory(p,4).tobytes(),'little')
stack=int(gdb.parse_and_eval('$rsp'));pc=int(gdb.parse_and_eval('$pc'))
flow=u64(stack+0x20) if pc!=0x52cd27 else int(gdb.parse_and_eval('$r15'))
checked=u64(flow);arena=u64(u64(u64(checked)));headers=u64(arena+240);data=u64(flow+32);nodes=u64(data+24);capacity=u32(arena+248)
if pc!=0x52cd27:
 print('WORK_REMAINING',u32(u64(stack+0x60)))
 n=u64(stack+0xb8)
 if n<u32(data+108):
  node=nodes+56*n;source=u32(node+8)
  print('FLOW_ROW',n,[u32(node+i*4) for i in range(14)])
  if source<capacity:print('INDEPENDENT_CHILD_REFUSAL',source,'SOURCE_SPAN',[u32(headers+source*36+j) for j in [20,24,28]])
 other=int(gdb.parse_and_eval('$ebp'))
 if 0<other<=u32(data+108):
  node=nodes+56*(other-1);source=u32(node+8)
  print('OTHER_ARGUMENT_ROW',other,[u32(node+i*4) for i in range(14)])
  if source<capacity:print('OTHER_ARGUMENT_SPAN',[u32(headers+source*36+j) for j in [20,24,28]])
end
bt 4
quit
'''


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--plan', type=Path, required=True)
	p.add_argument('--toolchain', type=Path, required=True)
	p.add_argument('--runtime', type=Path, required=True)
	p.add_argument('--payload', action='store_true', help='Trace aggregate payload-call refusal rather than source child checks')
	a = p.parse_args()
	sha = lambda path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
	argv = json.loads(a.plan.read_text())['argv']
	assert sha(argv[0]) == PIN and argv[1] == '-c' and argv[3] == '-o'
	inputs = argv[5:]
	assert all(Path(n).is_relative_to(ROOT) for n in inputs)
	identity = {n:sha(n) for n in inputs}
	ordered = sorted(inputs)
	allowed = [i+1 for i,n in enumerate(ordered) if Path(n).is_relative_to(ROOT/'compiler/docs')]
	toolchain = json.loads(a.toolchain.read_text())
	assert all(sha(n) == h for n,h in toolchain['tools'].items())
	# The host debugger keeps its own Python ABI. Only the inferior receives
	# the authenticated compiler capsule's environment.
	prefix = ''.join('set environment '+key+' '+value+'\n' for key,value in toolchain['environment'].items() if value is not None)
	script = prefix+(PAYLOAD_SCRIPT if a.payload else SCRIPT.replace('span[0] in ALLOWED', 'span[0] in '+repr(allowed)))
	a.runtime.mkdir(parents=True, exist_ok=False)
	(a.runtime/'executed-recipe.py.txt').write_bytes(Path(__file__).read_bytes())
	path = a.runtime/'read-only.gdb'
	path.write_text(script)
	command = ['/usr/bin/time', '-v', '-o', str(a.runtime/'time.txt'), '--', 'gdb', '--batch', '--nx', '-x', str(path), '--args', argv[0], '--check', *inputs]
	with (a.runtime/'stdout').open('wb') as out,(a.runtime/'stderr').open('wb') as err:
		r = subprocess.run(command, stdout=out, stderr=err, cwd=ROOT, timeout=600)
	output = (a.runtime/'stdout').read_text()
	match = re.search(r'INDEPENDENT_CHILD_REFUSAL (\d+) SOURCE_SPAN \[(\d+), (\d+), (\d+)\]', output)
	result = dict(status='DIAGNOSTIC_ONLY_NO_ACCEPTANCE_CREDIT', debugger_exit=r.returncode, command=command, producer_sha256=PIN, sources=identity, recipe_sha256=sha(__file__))
	if match:
		node,source,first,last = map(int, match.groups())
		result['refusal'] = dict(node=node, path=ordered[source-1], start=first, end=last, exact_source=Path(ordered[source-1]).read_bytes()[first:last].decode())
	assert all(sha(n) == h for n,h in identity.items())
	(a.runtime/'result.json').write_text(json.dumps(result, indent=2)+'\n')
	print(json.dumps(result.get('refusal', dict(debugger_exit=r.returncode, raw_stdout=output[-2000:]))))


if __name__ == '__main__':
	main()
