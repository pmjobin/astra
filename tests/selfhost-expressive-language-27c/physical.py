#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""27-C cases for the existing process-local LLVM mutation driver."""
import importlib.util
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
PRIOR = ROOT/'tests/selfhost-ownership-syntax-27b'
sys.path.insert(0, str(PRIOR))
from support import sha, write


def module(name, path):
	spec = importlib.util.spec_from_file_location(name, path)
	result = importlib.util.module_from_spec(spec)
	spec.loader.exec_module(result)
	return result


def main():
	prior = module('ownership_physical', PRIOR/'physical.py')
	cases = module('expressive_cases', Path(__file__).with_name('named.py'))
	selected = {row[0]:row[1] for row in cases.MATCH_CASES}
	prior.COMPOUND = 'int combine(int first, int last) { return first*2+last; } int main() { return combine(last: 2, first: 20); }\n'
	prior.CONDITIONAL = selected['match-three-way']
	prior.RECORD = selected['match-nested-payload']
	prior.PARAMETER = selected['match-payload-alignment']
	prior.CASES = {
		'named-ABI-slots': ('compound', 'main', 'named-slots'),
		'match-arm-result': ('conditional', '@native', 'match-phi'),
		'nested-variant-test': ('record', '@native', 'nested-tag'),
		'enum-payload-value': ('record', 'main', 'enum-payload'),
		'enum-constructor-tag': ('record', 'main', 'enum-tag'),
		'enum-carrier-alignment': ('parameter', 'main', 'enum-alignment'),
	}
	mutations = '''  elif action=='named-slots':
   candidates=[]
   for block in body:
    for value in instructions(block):
     if opcode(value)!=45:continue
     callee=pointer('LLVMGetCalledValue',value)
     if name(callee).startswith('astra.e25a.f.') and number('(unsigned)LLVMGetNumArgOperands((void*)%d)'%value)==2:
      if pointer('LLVMIsAConstantInt',operand(value,0)) and pointer('LLVMIsAConstantInt',operand(value,1)):
       if [integer(operand(value,n)) for n in (0,1)]==[20,2]:candidates.append(value)
   assert len(candidates)==1,candidates
   target=candidates[0];left=operand(target,0);right=operand(target,1);before=[integer(left),integer(right)]
   set_operand(target,0,right);set_operand(target,1,left);after=[integer(operand(target,n)) for n in (0,1)];assert after==[2,20]
  elif action=='match-phi':
   candidates=[value for block in body for value in instructions(block) if opcode(value)==44 and number('(unsigned)LLVMCountIncoming((void*)%d)'%value)==3]
   assert len(candidates)==1,candidates
   target=candidates[0];old=operand(target,2);before=integer(old);assert before in (20,22,42)
   set_operand(target,2,replacement(old,7));after=integer(operand(target,2));assert after==7
  elif action=='nested-tag':
   candidates=[]
   for block in body:
    for value in instructions(block):
     if opcode(value)==42 and number('(int)LLVMGetICmpPredicate((void*)%d)'%value)==32 and pointer('LLVMIsAConstantInt',operand(value,1)) and integer(operand(value,1))==1:candidates.append(value)
   assert candidates
   target=candidates[0];old=operand(target,1);before=integer(old);set_operand(target,1,replacement(old,0));after=integer(operand(target,1));assert after==0
  elif action in ('enum-payload','enum-tag'):
   candidates=[]
   for block in body:
    for value in instructions(block):
     if opcode(value)!=28 or not pointer('LLVMIsAConstantInt',operand(value,0)):continue
     address=operand(value,1)
     if not pointer('LLVMIsAInstruction',address) or opcode(address)!=29:continue
     kind=pointer('LLVMGetGEPSourceElementType',address)
     if number('(int)LLVMGetTypeKind((void*)%d)'%kind)!=10:continue
     fields=number('(unsigned)LLVMCountStructElementTypes((void*)%d)'%kind)
     literal=integer(operand(value,0))
     if action=='enum-payload' and literal==40 and fields==1:candidates.append(value)
     if action=='enum-tag' and literal==1 and fields==2 and integer(operand(address,2))==0:candidates.append(value)
   assert candidates
   if action=='enum-payload':assert len(candidates)==1,candidates
   target=candidates[0];old=operand(target,0);before=integer(old);set_operand(target,0,replacement(old,before+1));after=integer(operand(target,0));assert after==before+1
  elif action=='enum-alignment':
   candidates=[value for value in instructions(body[0]) if opcode(value)==26 and number('(unsigned)LLVMGetAlignment((void*)%d)'%value)==8]
   candidates=[value for value in candidates if number('(int)LLVMGetTypeKind((void*)%d)'%pointer('LLVMGetAllocatedType',value))==10]
   assert candidates
   target=candidates[0];before=number('(unsigned)LLVMGetAlignment((void*)%d)'%target)
   gdb.parse_and_eval('(void)LLVMSetAlignment((void*)%d,4)'%target);after=number('(unsigned)LLVMGetAlignment((void*)%d)'%target);assert before==8 and after==4
'''
	needle = "  else:assert action=='control'\n"
	assert prior.GDB.count(needle) == 1
	prior.GDB = prior.GDB.replace(needle, mutations+needle)
	identity = {str(path):sha(path) for path in (Path(__file__), Path(__file__).with_name('named.py'), PRIOR/'physical.py', PRIOR/'support.py')}
	prior.main()
	assert all(sha(path) == h for path,h in identity.items())
	arguments = sys.argv[1:]
	runtime = Path(arguments[arguments.index('--runtime')+1])
	result = json.loads((runtime/'result.json').read_text())
	result['extension_inputs'] = identity
	result['scope'] = 'Selected 27-C actual named ABI operands, match phi values, nested tag tests and enum stores/layout. The unchanged 27-B driver observes structural LLVM acceptance and independent physical refusal with preserved sentinels. No complete milestone, source, owner or memory credit.'
	write(runtime/'result.json', result)


if __name__ == '__main__': main()
