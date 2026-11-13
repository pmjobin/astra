#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exercise caught-message borrow obligations in fresh native seed processes.

Corruption occurs at the independent payload consumer, after earlier structural
checks. It must refuse without publishing. No executable or source is patched.
The checked layouts are specific to this unchanged-C0-produced seed.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tests/selfhost-compiler-complete'))
from run import WORK, sha
from acceleration import environment, execute, output_path, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for n in ('producer', 'core-map', 'inputs', 'build', 'runtime'): p.add_argument('--'+n, type=Path, required=True)
	p.add_argument('--version', required=True); a = p.parse_args(); assert a.version.isalnum()
	leaf = output_path(a.runtime/a.version, WORK/'runtime'); build = output_path(a.build/a.version, WORK/'build')
	leaf.mkdir(); build.mkdir()
	names = re.findall(r'^\t\(function "([^"]+)"', a.core_map.read_text(), re.M)
	assert names.count('recover_payload_calls_verified') == 1
	symbol = 'astra.fn.'+str(names.index('recover_payload_calls_verified'))
	symbols = {v[2]:int(v[0], 16) for line in subprocess.check_output(['nm', '-an', a.producer], text=True).splitlines() if len(v := line.split()) == 3}
	address = symbols[symbol]; producer_hash = sha(a.producer)
	manifest = json.loads((a.inputs/'inputs.json').read_text())['inputs']
	fixture = ROOT/'tests/selfhost-bootstrap-27a/caught-message-call.astra'
	inputs = {str(fixture):sha(fixture), **{p:h for p, h in manifest.items() if p.endswith(('/lib/astra/base/errors.astra', '/lib/astra/hosted/text.astra'))}}
	env = environment(dict(LD_PRELOAD=None, VALGRIND_OPTS=None, CCACHE_DISABLE='1'))
	rows = []
	for control in ('none', 'missing-owner', 'owner-function', 'message-type', 'coargument-move'):
		output = build/(control+'.ll'); marker = b'27A_BORROW_FAILURE_SENTINEL\n'; output.write_bytes(marker)
		run_leaf = leaf/control; run_leaf.mkdir()
		script = '''set pagination off
set confirm off
set disable-randomization off
set auto-load python-scripts off
python
import gdb,json,pathlib,struct
leaf=pathlib.Path(LEAF)
control=CONTROL
read=lambda p,n:bytes(gdb.selected_inferior().read_memory(p,n))
ptr=lambda p:struct.unpack('<Q',read(p,8))[0]
i32=lambda p:struct.unpack('<i',read(p,4))[0]
class Corrupt(gdb.Breakpoint):
 def stop(self):
  flow=int(gdb.parse_and_eval('$rdi')); data=ptr(flow+32)
  nodes=ptr(data+24); edges=ptr(data+40); owners=ptr(data+72)
  count=i32(data+108); owner_count=i32(data+80)
  assert 0<count<=i32(data+32)<100000 and 0<owner_count<100000
  node=lambda n:struct.unpack('<13i',read(nodes+(n-1)*52,52))
  calls=[]
  for n in range(1,count+1):
   row=node(n)
   if row[0]!=4 or row[10]!=2: continue
   argument=i32(edges+row[9]*4)
   assert 1<=argument<=count
   message=node(argument)
   if message[0]==6:
    assert message[3]==15 and message[1]==row[1] and 0<message[5]<owner_count
    owner=i32(owners+message[5]*4)
    assert 1<=owner<=count
    catch=node(owner)
    assert catch[0]==25 and catch[5]==message[5] and catch[1]==row[1]
    other=i32(edges+(row[9]+1)*4)
    assert 1<=other<=count and node(other)[0]==1
    calls.append((n,argument,owner,other,message[5],row[1]))
  assert len(calls)==1,calls
  call,message,owner,other,root,function=calls[0]
  changes=[]
  if control=='missing-owner': changes=[(owners+root*4,0)]
  if control=='owner-function': changes=[(nodes+(owner-1)*52+4,0)]
  if control=='message-type': changes=[(nodes+(message-1)*52+12,1)]
  if control=='coargument-move': changes=[(nodes+(other-1)*52,10),(nodes+(other-1)*52+20,root)]
  observation=dict(control=control,node_count=count,call=call,message=message,owner=owner,coargument=other,root=root,function=function,writes=[])
  for p,value in changes:
   before=i32(p); assert before!=value
   gdb.selected_inferior().write_memory(p,struct.pack('<i',value))
   observation['writes'].append(dict(address=p,before=before,after=i32(p)))
  (leaf/'injection.json').write_text(json.dumps(observation,indent=2)+'\\n')
  self.enabled=False
  return False
Corrupt('*'+hex(ADDRESS),internal=True)
def ended(event):
 (leaf/'inferior-exit.json').write_text(json.dumps(dict(exit=getattr(event,'exit_code',None)))+'\\n')
gdb.events.exited.connect(ended)
end
run
'''
		for key, value in [('LEAF', str(run_leaf)), ('CONTROL', control), ('ADDRESS', address)]: script = script.replace(key, repr(value))
		command_file = run_leaf/'commands.gdb'; command_file.write_text(script)
		argv = ['gdb', '-q', '--nx', '--batch', '-x', str(command_file), '--args', str(a.producer), '--emit-llvm', '-o', str(output), *inputs]
		result = execute(argv, run_leaf/'execution', timeout=120, env=env)
		assert result['status'] == 'EXPECTED_OUTCOME'
		injection = json.loads((run_leaf/'injection.json').read_text())
		status = json.loads((run_leaf/'inferior-exit.json').read_text())['exit']
		assert status == (0 if control == 'none' else 1), (control, status)
		if control == 'none':
			assert output.read_bytes() != marker
			assert execute(['opt', '-passes=verify', '-disable-output', output], run_leaf/'verify', timeout=120)['status'] == 'EXPECTED_OUTCOME'
		else:
			assert output.read_bytes() == marker and not list(build.glob(output.name+'.??????'))
		rows.append(dict(control=control, injection=injection, native_exit=status, command=argv, result=result, output_sha256=sha(output)))
		assert sha(a.producer) == producer_hash
		print('BORROW_CONTROL', control, status, flush=True)
	assert all(sha(p) == h for p, h in inputs.items())
	write(leaf/'result.json', dict(status='INDEPENDENT_CAUGHT_MESSAGE_BORROW_CONTROLS_PASS', producer=dict(path=str(a.producer), sha256=producer_hash), core_map_sha256=sha(a.core_map), controls=rows, limitation='Four fresh process-local negative controls and an unchanged positive control at the independent payload consumer. No persistent patch or historical mutation reclassification; only this C0 seed layout is qualified.'))


if __name__ == '__main__':
	main()
