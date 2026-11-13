#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Corrupt actual LLVM instructions before structural/physical verification."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

from intrinsic import SOURCE as INTRINSIC
from support import execute, output_path, sha, tool_identity, write

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
BOX = '''class Item { int value; init(int value) { this.value = value; } }
int read(Item item) { return item.value; }
int main() {
	var item = new Item(42);
	var box = shared_acquire(move item);
	var copy = shared_clone(box);
	var observer = shared_downgrade(copy);
	var attempt = weak_upgrade(observer);
	if (attempt != null) return read(shared_borrow(attempt));
	return 1;
}
'''
COMPOUND = 'int main() { int x = 40; int y = 0; x += 2; y += 0; return x+y; }\n'
PARAMETER = 'int adjust(int x) { x += 2; return x; } int main() { return adjust(40); }\n'
CONDITIONAL = 'int main() { int value = true ? 42 : 99; return value; }\n'
RECORD = 'struct Point { int x; int y; } int main() { Point p = {x = 40, y = 0}; p.x += 2; return p.x; }\n'
CASES = {
	'clone-field': ('box', 'astra.e25a.shared.clone', 'retain-field'),
	'upgrade-zero-path': ('box', 'astra.e25a.weak.upgrade', 'upgrade-phi'),
	'weak-release-counter': ('box', 'astra.e25a.weak.release', 'weak-counter'),
	'atomic-order': ('box', 'astra.e25a.shared.increment', 'atomic-order'),
	'acquire-size': ('box', 'astra.e25a.shared.acquire', 'acquire-size'),
	'intrinsic-clone-field': ('intrinsic', 'astra.e25a.intrinsic.clone', 'retain-field'),
	'intrinsic-upgrade-zero-path': ('intrinsic', 'astra.e25a.intrinsic.weak.upgrade', 'upgrade-phi'),
	'intrinsic-weak-release-counter': ('intrinsic', 'astra.e25a.intrinsic.weak.release', 'weak-counter'),
	'native-calling-convention': ('box', '@native', 'calling-convention'),
	'compound-address': ('compound', 'main', 'compound-address'),
	'parameter-initial-alignment': ('parameter', '@parameter', 'parameter-alignment'),
	'record-frame-alignment': ('record', 'main', 'record-alignment'),
	'conditional-branch-value': ('conditional', 'main', 'conditional-phi'),
	'error-descriptor-field': ('box', 'astra.e25a.construct', 'error-field'),
}
GDB = '''set pagination off
set confirm off
set disable-randomization off
set auto-load python-scripts off
set breakpoint pending on
python
import gdb,json,pathlib
configuration=@CONFIGURATION@
leaf=pathlib.Path(configuration['leaf'])
def save(name,value):(leaf/name).write_text(json.dumps(value,indent=2)+'\\n')
def number(expression):return int(gdb.parse_and_eval(expression))
def pointer(name,*arguments):return number('(void*)'+name+'('+','.join('(void*)%d'%p for p in arguments)+')')
def operand(value,index):return number('(void*)LLVMGetOperand((void*)%d,(unsigned)%d)'%(value,index))
def opcode(value):return number('(int)LLVMGetInstructionOpcode((void*)%d)'%value)
def integer(value):return number('(unsigned long long)LLVMConstIntGetZExtValue((void*)%d)'%value)
def replacement(old,value):return number('(void*)LLVMConstInt((void*)%d,(unsigned long long)%d,0)'%(pointer('LLVMTypeOf',old),value))
def set_operand(instruction,index,value):gdb.parse_and_eval('(void)LLVMSetOperand((void*)%d,(unsigned)%d,(void*)%d)'%(instruction,index,value))
def name(value):return gdb.parse_and_eval('(char*)LLVMGetValueName((void*)%d)'%value).string()
def blocks(function):
 result=[];block=pointer('LLVMGetFirstBasicBlock',function)
 while block:
  assert len(result)<8192
  result.append(block);block=pointer('LLVMGetNextBasicBlock',block)
 return result
def instructions(block):
 result=[];value=pointer('LLVMGetFirstInstruction',block)
 while value:
  assert len(result)<8192
  result.append(value);value=pointer('LLVMGetNextInstruction',value)
 return result
def function_for(module,requested):
 if not requested.startswith('@'):return number('(void*)LLVMGetNamedFunction((void*)%d,%s)'%(module,json.dumps(requested)))
 function=pointer('LLVMGetFirstFunction',module);budget=8192
 while function and budget:
  if name(function).startswith('astra.e25a.f.') and number('(unsigned)LLVMGetFunctionCallConv((void*)%d)'%function)==8 and blocks(function):
   if requested=='@native':return function
   if requested=='@parameter':
    entry=instructions(blocks(function)[0])
    if len(entry)>=2 and opcode(entry[0])==26 and opcode(entry[1])==28:return function
  function=pointer('LLVMGetNextFunction',function);budget-=1
 return 0
class StructuralReturn(gdb.FinishBreakpoint):
 def stop(self):
  save('structural-return.json',dict(returned=number('$eax')))
  return False
class Mutate(gdb.Breakpoint):
 def stop(self):
  module=number('$rdi');function=function_for(module,configuration['function'])
  if not function:return False
  self.enabled=False
  action=configuration['action'];body=blocks(function);target=0;before=None;after=None
  if action in ('retain-field','weak-counter'):
   target=instructions(body[1])[0];assert opcode(target)==29
   old=operand(target,2);before=integer(old)
   if action=='retain-field':
    assert before in (0,2);after=before+1
   else:
    assert before in (1,3);after=before-1
   set_operand(target,2,replacement(old,after));assert integer(operand(target,2))==after
  elif action=='upgrade-phi':
   target=instructions(body[5])[0];assert opcode(target)==44
   before=number('(int)LLVMIsNull((void*)%d)'%operand(target,1));assert before==1
   handle=number('(void*)LLVMGetParam((void*)%d,0)'%function)
   set_operand(target,1,handle);after=int(operand(target,1)==handle);assert after==1
  elif action=='atomic-order':
   target=instructions(body[2])[1];assert opcode(target)==56
   before=number('(int)LLVMGetCmpXchgSuccessOrdering((void*)%d)'%target);assert before==6
   gdb.parse_and_eval('(void)LLVMSetCmpXchgSuccessOrdering((void*)%d,4)'%target)
   after=number('(int)LLVMGetCmpXchgSuccessOrdering((void*)%d)'%target);assert after==4
  elif action=='acquire-size':
   target=instructions(body[1])[0];assert opcode(target)==45
   old=operand(target,1);before=integer(old);assert before==24
   set_operand(target,1,replacement(old,16));after=integer(operand(target,1));assert after==16
  elif action=='calling-convention':
   target=function;before=number('(unsigned)LLVMGetFunctionCallConv((void*)%d)'%function);assert before==8
   gdb.parse_and_eval('(void)LLVMSetFunctionCallConv((void*)%d,0)'%function)
   after=number('(unsigned)LLVMGetFunctionCallConv((void*)%d)'%function);assert after==0
  elif action=='compound-address':
   allocas=[value for value in instructions(body[0]) if opcode(value)==26];assert len(allocas)==2
   for block in body:
    for value in instructions(block):
     if opcode(value)==28 and operand(value,1)==allocas[0]:
      computed=operand(value,0)
      if number('(void*)LLVMIsAInstruction((void*)%d)'%computed) and opcode(computed)==8:target=value
   assert target;before=operand(target,1);after=allocas[1];assert before!=after
   set_operand(target,1,after);assert operand(target,1)==after
  elif action=='parameter-alignment':
   entry=instructions(body[0]);target=entry[1];assert opcode(entry[0])==26 and opcode(target)==28
   before=number('(unsigned)LLVMGetAlignment((void*)%d)'%target);assert before==4
   gdb.parse_and_eval('(void)LLVMSetAlignment((void*)%d,16)'%target)
   after=number('(unsigned)LLVMGetAlignment((void*)%d)'%target);assert after==16
  elif action=='record-alignment':
   target=next(value for value in instructions(body[0]) if opcode(value)==26)
   before=number('(unsigned)LLVMGetAlignment((void*)%d)'%target);assert before==8
   gdb.parse_and_eval('(void)LLVMSetAlignment((void*)%d,4)'%target)
   after=number('(unsigned)LLVMGetAlignment((void*)%d)'%target);assert after==4
  elif action=='conditional-phi':
   for block in body:
    for value in instructions(block):
     if opcode(value)==44:target=value
   assert target;old=operand(target,1);before=integer(old);assert before in (42,99)
   set_operand(target,1,replacement(old,7));after=integer(operand(target,1));assert after==7
  elif action=='error-field':
   target=next(value for value in instructions(body[0]) if opcode(value)==29)
   old=operand(target,2);before=integer(old);assert before==0
   set_operand(target,2,replacement(old,1));after=integer(operand(target,2));assert after==1
  else:assert action=='control'
  save('mutation.json',dict(action=action,module=module,function=function,function_name=name(function),target=target,before=before,after=after))
  StructuralReturn(gdb.newest_frame(),internal=True)
  return False
def exited(event):save('inferior-exit.json',dict(exit=getattr(event,'exit_code',None)))
gdb.events.exited.connect(exited)
Mutate('LLVMVerifyModule')
end
run
'''


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for key in ('compiler', 'runtime', 'build'):
		p.add_argument('--'+key, type=Path, required=True)
	p.add_argument('--compiler-sha256', required=True)
	p.add_argument('--case', choices=tuple(CASES), action='append')
	a = p.parse_args()
	assert re.fullmatch('[0-9a-f]{64}', a.compiler_sha256) and sha(a.compiler) == a.compiler_sha256
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	runtime = output_path(a.runtime, WORK/'runtime')
	build = output_path(a.build, WORK/'build')
	runtime.mkdir(parents=True, exist_ok=False)
	build.mkdir(parents=True, exist_ok=False)
	sources = {}
	for key, text in dict(box=BOX, intrinsic=INTRINSIC, compound=COMPOUND, parameter=PARAMETER, conditional=CONDITIONAL, record=RECORD).items():
		path = runtime/(key+'.astra')
		path.write_text('language astra27b;\n'+text)
		sources[key] = path
	inputs = {str(path):sha(path) for path in (Path(__file__), Path(__file__).with_name('support.py'), Path(__file__).with_name('intrinsic.py'), *sources.values())}
	tools = tool_identity([a.compiler, '/usr/bin/time', *[shutil.which(name) for name in ('gdb', 'llvm-config', 'opt')]])
	write(runtime/'identity.json', dict(compiler_sha256=a.compiler_sha256, inputs=inputs, tools=tools, boundary='Fresh process-local LLVM mutations through the exact public C API, before LLVMVerifyModule; no ELF/source modification.'))
	selected = {key:CASES[key] for key in a.case} if a.case else CASES
	plans = [('control-'+kind, kind, 'main', 'control') for kind in sorted({row[0] for row in selected.values()})]
	plans += [(key, *value) for key, value in selected.items()]
	rows = []
	env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1', CCACHE_DISABLE='1')
	env.pop('LD_PRELOAD', None)
	env.pop('VALGRIND_OPTS', None)
	for name, kind, function, action in plans:
		leaf = runtime/name
		leaf.mkdir()
		output = build/(name+'.ll')
		marker = b'ASTRA27B_PHYSICAL_REFUSAL_SENTINEL\n'
		output.write_bytes(marker)
		configuration = dict(leaf=str(leaf), function=function, action=action)
		script = leaf/'mutate.gdb'
		script.write_text(GDB.replace('@CONFIGURATION@', repr(configuration)))
		argv = ['gdb', '--batch', '--nx', '-x', script, '--args', a.compiler, '--emit-llvm', '-o', output, sources[kind]]
		r = execute(argv, leaf/'execution', timeout=120, env=env)
		assert r['status'] == 'EXPECTED_OUTCOME', (name, r)
		observations = {key:json.loads((leaf/(key+'.json')).read_text()) for key in ('mutation', 'structural-return', 'inferior-exit')}
		assert observations['structural-return']['returned'] == 0, (name, observations)
		if action == 'control':
			assert observations['inferior-exit']['exit'] == 0 and output.read_bytes() != marker
			verified = execute(['opt', '-passes=verify', '-disable-output', output], leaf/'independent-LLVM-verify', env=env)
			assert verified['status'] == 'EXPECTED_OUTCOME'
		else:
			assert observations['inferior-exit']['exit'] == 1 and output.read_bytes() == marker, (name, observations)
			assert b'LLVM' in (leaf/'execution/stderr').read_bytes()
		rows.append(dict(name=name, action=action, argv=list(map(str, argv)), script_sha256=sha(script), source_sha256=sha(sources[kind]), output_sha256=sha(output), observations=observations, execution=r))
		write(runtime/'observations.json', rows)
		print(name, 'CONTROL_PASS' if action == 'control' else 'LLVM_VALID_MUTANT_REFUSED', flush=True)
	assert all(sha(path) == h for path, h in {**inputs, **tools}.items())
	write(runtime/'result.json', dict(status='SELECTED_INDEPENDENT_PHYSICAL_MUTATIONS_PASS', compiler_sha256=a.compiler_sha256, selected_cases=list(selected), mutations=len(selected), controls=len(plans)-len(selected), identity_sha256=sha(runtime/'identity.json'), observations_sha256=sha(runtime/'observations.json'), scope='Each returning structural verifier accepts actual mutated IR; an independent physical consumer refuses and preserves the sentinel. No memory, complete language, or delivery credit.'))


if __name__ == '__main__':
	main()
