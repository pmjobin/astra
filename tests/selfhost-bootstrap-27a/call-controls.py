#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Reject corrupted recovered-call facts in fresh actual seed processes.

The seed is the unchanged C0's native product. Its unchanged class layouts are
checked against actual table lengths, source IDs, spans and node identities
before a primitive table cell is changed. These are negative process-local
controls, never verification overrides or persistent source/product edits.
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
	assert names.count('recover_types_verify') == 1
	symbol = 'astra.fn.'+str(names.index('recover_types_verify'))
	symbols = {v[2]:int(v[0], 16) for line in subprocess.check_output(['nm', '-an', a.producer], text=True).splitlines() if len(v := line.split()) == 3}
	address = symbols[symbol]
	producer_hash = sha(a.producer)
	manifest = json.loads((a.inputs/'inputs.json').read_text())['inputs']
	fixture = ROOT/'tests/selfhost-bootstrap-27a/caught-message-call.astra'
	inputs = {str(fixture):sha(fixture), **{p:h for p, h in manifest.items() if '/lib/astra/' in p}}
	ordered = sorted(inputs)
	env = environment(dict(LD_PRELOAD=None, VALGRIND_OPTS=None, CCACHE_DISABLE='1'))
	rows = []
	for control in ('none', 'call-result', 'message-member', 'message-borrow', 'message-type', 'pending-origin'):
		output = build/(control+'.ll'); marker = b'27A_CALL_FACT_FAILURE_SENTINEL\n'; output.write_bytes(marker)
		run_leaf = leaf/control; run_leaf.mkdir()
		script = '''set pagination off
set confirm off
set disable-randomization off
set auto-load python-scripts off
python
import gdb,json,pathlib,struct
leaf=pathlib.Path(LEAF)
ordered=ORDERED
control=CONTROL
read=lambda p,n:bytes(gdb.selected_inferior().read_memory(p,n))
ptr=lambda p:struct.unpack('<Q',read(p,8))[0]
i32=lambda p:struct.unpack('<i',read(p,4))[0]
class Corrupt(gdb.Breakpoint):
 def stop(self):
  data=int(gdb.parse_and_eval('$rdi')); checked=int(gdb.parse_and_eval('$rsi'))
  types=ptr(data+8); count=i32(data+16)
  uses=ptr(checked+0x118)
  assert count==i32(checked+0x120) and 0<count<100000
  members=ptr(data+24); borrows=ptr(data+40)
  calls=[]; messages=[]
  for n in range(1,count):
   row=struct.unpack('<7i',read(uses+n*28,28))
   if row[6]==15 and row[4]==0 and i32(types+n*4)>0:
    assert row[0]==n and row[5]==0
    source,first,last=row[1:4]
    assert 1<=source<=len(ordered) and 0<=first<=last<=len(pathlib.Path(ordered[source-1]).read_bytes())
    assert ordered[source-1].endswith('/caught-message-call.astra')
    calls.append(n)
   if i32(members+n*4)>0 and i32(borrows+n*4)>0:
    assert row[6]==12 and row[4]==0 and i32(types+n*4)==15
    messages.append(n)
  assert len(calls)==2 and len(messages)==2,(calls,messages)
  changed=None
  if control=='call-result': changed=(types+calls[0]*4,1)
  if control=='message-member': changed=(members+messages[0]*4,0)
  if control=='message-borrow': changed=(borrows+messages[0]*4,0)
  if control=='message-type': changed=(types+messages[0]*4,1)
  if control=='pending-origin': changed=(uses+calls[0]*28+24,17)
  observation=dict(control=control,calls=calls,messages=messages,table_length=count,write=None)
  if changed:
   p,value=changed; before=i32(p); assert before!=value
   gdb.selected_inferior().write_memory(p,struct.pack('<i',value))
   observation['write']=dict(address=p,before=before,after=i32(p))
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
		for key, value in [('LEAF', str(run_leaf)), ('ORDERED', ordered), ('CONTROL', control), ('ADDRESS', address)]: script = script.replace(key, repr(value))
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
		print('CALL_FACT_CONTROL', control, status, flush=True)
	assert all(sha(p) == h for p, h in inputs.items())
	write(leaf/'result.json', dict(status='INDEPENDENT_RECOVERED_CALL_CONTROLS_PASS', producer=dict(path=str(a.producer), sha256=producer_hash), core_map_sha256=sha(a.core_map), controls=rows, limitation='Five fresh negative seed processes and one unchanged positive process; primitive process-local fact corruption, returning refusals and output preservation. These are new controls, not a reclassification of historical mutation cohorts or qualification of a different product layout.'))


if __name__ == '__main__':
	main()
