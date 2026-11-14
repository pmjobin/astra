#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""27-C cases for the existing process-local LLVM mutation driver."""
import argparse
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
	selection = argparse.ArgumentParser(add_help=False)
	selection.add_argument('--feature', choices=('existing', 'format', 'lazy', 'collection', 'range', 'enum'), default='existing')
	options, remaining = selection.parse_known_args()
	sys.argv = [sys.argv[0], *remaining]
	prior = module('ownership_physical', PRIOR/'physical.py')
	cases = module('expressive_cases', Path(__file__).with_name('named.py'))
	selected = {row[0]:row[1] for row in cases.MATCH_CASES}
	prior.COMPOUND = 'int combine(int first, int last) { return first*2+last; } int main() { return combine(last: 2, first: 20); }\n'
	prior.CONDITIONAL = selected['match-three-way']
	prior.RECORD = selected['match-nested-payload']
	prior.PARAMETER = selected['match-payload-alignment']
	prior.BOX = '''enum Packet { Empty, Data(owned int[] data, owned int[] extra, int count) }
int main() {
	var packet = Packet.Data(new int[13],new int[7],13);
	return match (move packet) { case Packet.Empty() => 1; case Packet.Data(data,_,count) => len(data)+count+16; };
}
'''
	prior.INTRINSIC = '''[ExceptionRoot] class Error {
	readonly string text;
	init(string message) { this.text = message; }
	virtual property string message { get { return this.text; } }
}
int marker(bool fail) throws Error { if (fail) { throw new Error("operand failure"); } return 29; }
int eat(owned int[] values, int marker) { return len(values)+marker; }
int main() { try { return eat(values: new int[13], marker: marker(true)); } catch (Error error) { return 42; } }
'''
	prior.CASES = {
		'named-ABI-slots': ('compound', 'main', 'named-slots'),
		'match-arm-result': ('conditional', '@native', 'match-phi'),
		'nested-variant-test': ('record', '@native', 'nested-tag'),
		'enum-payload-value': ('record', 'main', 'enum-payload'),
		'enum-constructor-tag': ('record', 'main', 'enum-tag'),
		'enum-carrier-alignment': ('parameter', 'main', 'enum-alignment'),
		'fresh-temporary-retirement': ('intrinsic', 'main', 'temporary-drop'),
		'owning-payload-clear': ('box', 'main', 'enum-clear'),
		'owning-residual-retirement': ('box', 'main', 'enum-residual'),
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
  elif action=='temporary-drop':
   candidates=[value for block in body for value in instructions(block) if opcode(value)==45 and name(pointer('LLVMGetCalledValue',value))=='free']
   assert len(candidates)==1,candidates
   target=candidates[0];old=operand(target,0);assert pointer('LLVMIsAInstruction',old) and opcode(old)==53
   before=dict(argument=old,argument_opcode=opcode(old))
   changed=pointer('LLVMConstNull',pointer('LLVMTypeOf',old));set_operand(target,0,changed);after=dict(is_null=number('(int)LLVMIsNull((void*)%d)'%operand(target,0)));assert after['is_null']==1
  elif action=='enum-clear':
   candidates=[]
   for block in body:
    sequence=instructions(block)
    for at,value in enumerate(sequence):
     if opcode(value)!=28 or not number('(int)LLVMIsNull((void*)%d)'%operand(value,0)):continue
     address=operand(value,1)
     if not pointer('LLVMIsAInstruction',address) or opcode(address)!=29:continue
     kind=pointer('LLVMTypeOf',operand(value,0))
     if number('(int)LLVMGetTypeKind((void*)%d)'%kind)!=10 or number('(unsigned)LLVMCountStructElementTypes((void*)%d)'%kind)!=2:continue
     first=number('(void*)LLVMStructGetTypeAtIndex((void*)%d,0)'%kind)
     if number('(int)LLVMGetTypeKind((void*)%d)'%first)==12 and at>0 and opcode(sequence[at-1])==27:candidates.append((value,sequence[at-1]))
   assert len(candidates)==1,candidates
   target,loaded=candidates[0];before=dict(is_null=True);set_operand(target,0,loaded);after=dict(is_original_payload=operand(target,0)==loaded);assert after['is_original_payload']
  elif action=='enum-residual':
   candidates=[]
   for block in body:
    for value in instructions(block):
     if opcode(value)!=45 or not name(pointer('LLVMGetCalledValue',value)).startswith('astra.enum.drop.'):continue
     argument=operand(value,0)
     if pointer('LLVMIsAInstruction',argument) and opcode(argument)==26:candidates.append(value)
   # Each of the two source arms retires the same captured sum. Corrupt one
   # actual arm operation while preserving the other arm as generated.
   assert len(candidates)==2,candidates
   target=candidates[0];old=operand(target,0);before=dict(captured_address=old,arm_retirements=len(candidates),selected_arm=0)
   changed=pointer('LLVMConstNull',pointer('LLVMTypeOf',old));set_operand(target,0,changed);after=dict(is_null=number('(int)LLVMIsNull((void*)%d)'%operand(target,0)));assert after['is_null']==1
  elif action=='match-phi':
   candidates=[value for block in body for value in instructions(block) if opcode(value)==44 and number('(unsigned)LLVMCountIncoming((void*)%d)'%value)==3]
   assert len(candidates)==1,candidates
   target=candidates[0];old=operand(target,2);before=integer(old);assert before in (20,22,42)
   set_operand(target,2,replacement(old,7));after=integer(operand(target,2));assert after==7
  elif action=='nested-tag':
   candidates=[]
   for block in body:
    for value in instructions(block):
     if opcode(value)!=42 or number('(int)LLVMGetICmpPredicate((void*)%d)'%value)!=32 or not pointer('LLVMIsAConstantInt',operand(value,1)) or integer(operand(value,1))!=1:continue
     tag=operand(value,0)
     if not pointer('LLVMIsAInstruction',tag) or opcode(tag)!=27:continue
     address=operand(tag,0)
     if not pointer('LLVMIsAInstruction',address) or opcode(address)!=29:continue
     selected=operand(address,0)
     if pointer('LLVMIsAInstruction',selected) and opcode(selected)==29:candidates.append(value)
   assert len(candidates)==1,candidates
   target=candidates[0];old=operand(target,1);before=dict(tag=integer(old),nested_projection=True);set_operand(target,1,replacement(old,0));after=dict(tag=integer(operand(target,1)),nested_projection=True);assert after['tag']==0
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
	extra = []
	if options.feature == 'enum':
		prior.COMPOUND = 'enum Pair { Data(int first,int last) } int main() { var pair = Pair.Data(last: 22,first: 20); return match (pair) { case Pair.Data(first,last) => first+last; }; }\n'
		prior.INTRINSIC = '''[ExceptionRoot] class Error {
	readonly string text;
	init(string message) { this.text = message; }
	virtual property string message { get { return this.text; } }
}
enum Parcel { Data(owned int[] first,owned int[] second,int marker) }
int mark(bool fail) throws Error { if (fail) { throw new Error("stop"); } return 22; }
int main() { try { var value = Parcel.Data(second: new int[13],first: new int[7],marker: mark(true)); return 1; } catch (Error error) { return 42; } }
'''
		prior.CASES = {
			'named-enum-payload-slot': ('compound', 'main', 'named-enum-slot'),
			'named-enum-fresh-retirement': ('intrinsic', 'main', 'named-enum-retirement'),
		}
		enum_mutations = '''  elif action=='named-enum-slot':
   candidates=[value for block in body for value in instructions(block) if opcode(value)==28 and pointer('LLVMIsAConstantInt',operand(value,0)) and integer(operand(value,0))==20]
   assert len(candidates)==1,candidates
   target=candidates[0];old=operand(target,0);before=integer(old);set_operand(target,0,replacement(old,21));after=integer(operand(target,0));assert after==21
  elif action=='named-enum-retirement':
   candidates=[value for block in body for value in instructions(block) if opcode(value)==45 and name(pointer('LLVMGetCalledValue',value))=='free']
   assert len(candidates)==2,candidates
   target=candidates[0];old=operand(target,0);before=dict(argument=old,retirements=len(candidates),selected=0)
   set_operand(target,0,pointer('LLVMConstNull',pointer('LLVMTypeOf',old)));after=dict(is_null=number('(int)LLVMIsNull((void*)%d)'%operand(target,0)));assert after['is_null']
'''
		assert prior.GDB.count(needle) == 1
		prior.GDB = prior.GDB.replace(needle, enum_mutations+needle)
	if options.feature == 'range':
		prior.COMPOUND = 'int main() { var values = (20..=80).step_by(5).collect_array(); return len(values); }\n'
		prior.RECORD = 'int main() { int[13] values = (20..=80).step_by(5).collect_fixed(); return values[0]; }\n'
		prior.PARAMETER = 'int main() { var values = new int[32]; return len(values[2..15]); }\n'
		prior.BOX = 'int main() { return (20..=80).contains(80) ? 42 : 1; }\n'
		prior.CASES = {
			'range-count-limit': ('compound', '@prefix:astra.range.count.', 'range-count-limit'),
			'range-final-advance': ('compound', '@prefix:astra.range.fill.', 'range-final-advance'),
			'range-final-allocation-size': ('compound', 'main', 'collection-element-size'),
			'range-hidden-intermediate': ('compound', 'main', 'collection-extra-allocation'),
			'range-inclusive-bound': ('box', '@prefix:astra.range.query.', 'range-inclusive-bound'),
			'range-slice-bounds': ('parameter', '@prefix:astra.e25a.slice.', 'range-slice-bounds'),
			'range-fixed-backing-alignment': ('record', 'main', 'range-fixed-alignment'),
		}
		lookup = ''' if requested.startswith('@prefix:'):
  function=pointer('LLVMGetFirstFunction',module);matches=[];budget=8192
  while function and budget:
   if name(function).startswith(requested[8:]) and blocks(function):matches.append(function)
   function=pointer('LLVMGetNextFunction',function);budget-=1
  assert len(matches)==1,matches
  return matches[0]
'''
		assert prior.GDB.count('def function_for(module,requested):\n') == 1
		prior.GDB = prior.GDB.replace('def function_for(module,requested):\n', 'def function_for(module,requested):\n'+lookup)
		range_mutations = '''  elif action=='range-count-limit':
   candidates=[value for block in body for value in instructions(block) if opcode(value)==10 and pointer('LLVMIsAConstantInt',operand(value,0)) and integer(operand(value,0))==2147483647]
   assert len(candidates)==1,candidates
   target=candidates[0];old=operand(target,0);before=integer(old);set_operand(target,0,replacement(old,2147483646));after=integer(operand(target,0));assert after==2147483646
  elif action=='range-final-advance':
   target=pointer('LLVMGetBasicBlockTerminator',body[2]);assert opcode(target)==71
   before=[number('(void*)LLVMGetSuccessor((void*)%d,%d)'%(target,n)) for n in (0,1)];assert before[0]!=before[1]
   for n in (0,1):gdb.parse_and_eval('(void)LLVMSetSuccessor((void*)%d,%d,(void*)%d)'%(target,n,before[1-n]))
   after=[number('(void*)LLVMGetSuccessor((void*)%d,%d)'%(target,n)) for n in (0,1)];assert after==before[::-1]
  elif action=='range-inclusive-bound':
   candidates=[value for block in body for value in instructions(block) if opcode(value)==42 and number('(int)LLVMGetICmpPredicate((void*)%d)'%value)==41]
   assert len(candidates)==1,candidates
   target=candidates[0];old=operand(target,1);before=dict(end_parameter=old);assert old==number('(void*)LLVMGetParam((void*)%d,1)'%function)
   changed=number('(void*)LLVMGetParam((void*)%d,0)'%function);set_operand(target,1,changed);after=dict(start_parameter=operand(target,1));assert after['start_parameter']==changed
  elif action=='range-slice-bounds':
   target=instructions(body[0])[5];assert opcode(target)==42 and number('(int)LLVMGetICmpPredicate((void*)%d)'%target)==41
   old=operand(target,1);before=dict(remaining_capacity=old);assert opcode(old)==10
   length=number('(void*)LLVMGetParam((void*)%d,3)'%function);set_operand(target,1,length);after=dict(length_compared_with_itself=operand(target,0)==operand(target,1));assert after['length_compared_with_itself']
  elif action=='range-fixed-alignment':
   candidates=[value for value in instructions(body[0]) if opcode(value)==26 and pointer('LLVMIsAConstantInt',operand(value,0)) and integer(operand(value,0))==13]
   assert len(candidates)==1,candidates
   target=candidates[0];before=number('(unsigned)LLVMGetAlignment((void*)%d)'%target);assert before==4
   gdb.parse_and_eval('(void)LLVMSetAlignment((void*)%d,8)'%target);after=number('(unsigned)LLVMGetAlignment((void*)%d)'%target);assert after==8
'''
		assert prior.GDB.count(needle) == 1
		prior.GDB = prior.GDB.replace(needle, range_mutations+needle)
	if options.feature == 'lazy':
		prior.COMPOUND = 'int main() { return (0..13).map(i => i+7).sum(); }\n'
		prior.CONDITIONAL = 'int main() { return (0..13).map(i => i+7).filter(x => x>10).sum(); }\n'
		prior.PARAMETER = 'int main() { return (0..13).map(i => (i as f64)*0.5d).sum() == 39.0d ? 42 : 1; }\n'
		prior.RECORD = 'int main() { int bias = 7; var values = (0..13).map(i => i+bias); bias = 9; return values.sum(); }\n'
		prior.CASES = {
			'lazy-reduction-overflow-flag': ('compound', 'main', 'lazy-overflow-flag'),
			'lazy-reduction-fast-math': ('parameter', 'main', 'lazy-fast-math'),
			'lazy-filter-skip-edge': ('conditional', 'main', 'lazy-filter-edge'),
			'lazy-captured-value': ('record', 'main', 'lazy-capture'),
		}
	if options.feature == 'collection':
		prior.COMPOUND = 'int main() { var values = (0..13).map(i => i+7).filter(x => x>10).collect_array(); return len(values); }\n'
		prior.RECORD = 'int main() { var values = [for (var i in 0..13) => i*i]; return len(values); }\n'
		prior.PARAMETER = 'int main() { int[3] data = {20,21,22}; var values = data.iter().map(i => i+1).collect_array(); return len(values); }\n'
		prior.INTRINSIC = '''[ExceptionRoot] class Error {
	readonly string text;
	init(string message) { this.text = message; }
	virtual property string message { get { return this.text; } }
}
int probe(int value) throws Error { if (value == 2) { throw new Error("stop"); } return value; }
int main() { try { var values = (0..13).map(i => probe(i)).collect_array(); return len(values); } catch (Error error) { return 42; } }
'''
		prior.CASES = {
			'collection-element-allocation-size': ('compound', 'main', 'collection-element-size'),
			'collection-logical-length': ('compound', 'main', 'collection-length'),
			'collection-hidden-intermediate': ('compound', 'main', 'collection-extra-allocation'),
			'collection-partial-retirement': ('intrinsic', 'main', 'collection-retirement'),
			'comprehension-hidden-intermediate': ('record', 'main', 'collection-extra-allocation'),
			'collection-borrowed-read-flags': ('parameter', 'main', 'collection-read-flags'),
		}
	if options.feature in ('lazy', 'collection', 'range'):
		collection_mutations = '''  elif action in ('lazy-overflow-flag','lazy-fast-math','lazy-capture'):
   candidates=[]
   for block in body:
    for value in instructions(block):
     if action=='lazy-fast-math' and opcode(value)==9:candidates.append(value)
     if opcode(value)!=8:continue
     right=operand(value,1)
     if action=='lazy-overflow-flag' and pointer('LLVMIsAInstruction',operand(value,0)) and opcode(operand(value,0))==27 and not pointer('LLVMIsAConstantInt',right):candidates.append(value)
     if action=='lazy-capture' and pointer('LLVMIsAInstruction',right) and opcode(right)==53:candidates.append(value)
   assert len(candidates)==1,candidates
   target=candidates[0]
   if action=='lazy-fast-math':
    before=number('(unsigned)LLVMGetFastMathFlags((void*)%d)'%target);assert before==0
    gdb.parse_and_eval('(void)LLVMSetFastMathFlags((void*)%d,1)'%target);after=number('(unsigned)LLVMGetFastMathFlags((void*)%d)'%target);assert after==1
   elif action=='lazy-overflow-flag':
    before=number('(int)LLVMGetNSW((void*)%d)'%target);assert before==0
    gdb.parse_and_eval('(void)LLVMSetNSW((void*)%d,1)'%target);after=number('(int)LLVMGetNSW((void*)%d)'%target);assert after==1
   else:
    old=operand(target,1);before=dict(captured_value=old)
    set_operand(target,1,replacement(old,8));after=dict(literal=integer(operand(target,1)));assert after['literal']==8
  elif action=='lazy-filter-edge':
   candidates=[]
   for block in body:
    term=pointer('LLVMGetBasicBlockTerminator',block)
    if opcode(term)!=71:continue
    condition=operand(term,0)
    if opcode(condition)==42 and number('(int)LLVMGetICmpPredicate((void*)%d)'%condition)==38:candidates.append(term)
   assert len(candidates)==1,candidates
   target=candidates[0];before=[number('(void*)LLVMGetSuccessor((void*)%d,%d)'%(target,n)) for n in (0,1)];assert before[0]!=before[1]
   for n in (0,1):gdb.parse_and_eval('(void)LLVMSetSuccessor((void*)%d,%d,(void*)%d)'%(target,n,before[1-n]))
   after=[number('(void*)LLVMGetSuccessor((void*)%d,%d)'%(target,n)) for n in (0,1)];assert after==before[::-1]
  elif action in ('collection-element-size','collection-extra-allocation'):
   candidates=[value for block in body for value in instructions(block) if opcode(value)==45 and name(pointer('LLVMGetCalledValue',value))=='astra.e25a.buffer.allocate']
   assert len(candidates)==1,candidates
   target=candidates[0]
   if action=='collection-element-size':
    old=operand(target,1);before=integer(old);assert before==4
    set_operand(target,1,replacement(old,8));after=integer(operand(target,1));assert after==8
   else:
    # The cloned call follows its dominating capacity value. Corrupted IR
    # is structurally verified and refused, never executed as a target.
    before=dict(allocation_calls=1);next_value=pointer('LLVMGetNextInstruction',target);assert next_value
    clone=pointer('LLVMInstructionClone',target);assert clone
    builder=pointer('LLVMCreateBuilderInContext',pointer('LLVMGetModuleContext',module));assert builder
    gdb.parse_and_eval('(void)LLVMPositionBuilderBefore((void*)%d,(void*)%d)'%(builder,next_value))
    gdb.parse_and_eval('(void)LLVMInsertIntoBuilder((void*)%d,(void*)%d)'%(builder,clone))
    gdb.parse_and_eval('(void)LLVMDisposeBuilder((void*)%d)'%builder)
    after=dict(allocation_calls=sum(opcode(value)==45 and name(pointer('LLVMGetCalledValue',value))=='astra.e25a.buffer.allocate' for block in body for value in instructions(block)));assert after['allocation_calls']==2
  elif action=='collection-length':
   candidates=[]
   for block in body:
    for value in instructions(block):
     if opcode(value)!=54 or number('(unsigned)LLVMGetNumIndices((void*)%d)'%value)!=1 or number('*(unsigned*)LLVMGetIndices((void*)%d)'%value)!=1:continue
     kind=pointer('LLVMTypeOf',value)
     if number('(unsigned)LLVMCountStructElementTypes((void*)%d)'%kind)!=2 or number('(int)LLVMGetTypeKind((void*)LLVMStructGetTypeAtIndex((void*)%d,0))'%kind)!=12:continue
     length=operand(value,1)
     if pointer('LLVMIsAInstruction',length) and opcode(length)==27:candidates.append(value)
   assert len(candidates)==1,candidates
   target=candidates[0];old=operand(target,1);before=dict(logical_length=old)
   set_operand(target,1,replacement(old,13));after=dict(capacity_substituted=integer(operand(target,1)));assert after['capacity_substituted']==13
  elif action=='collection-retirement':
   candidates=[]
   for block in body:
    for value in instructions(block):
     if opcode(value)!=45 or name(pointer('LLVMGetCalledValue',value))!='free':continue
     argument=operand(value,0)
     if not pointer('LLVMIsAInstruction',argument) or opcode(argument)!=53:continue
     descriptor=operand(argument,0)
     # The partial temporary has its actual allocation descriptor. Normal
     # local cleanup instead loads the final descriptor from an owner slot.
     if pointer('LLVMIsAInstruction',descriptor) and opcode(descriptor)==54:candidates.append(value)
   assert len(candidates)==1,candidates
   target=candidates[0];old=operand(target,0);before=dict(partial_buffer=old)
   set_operand(target,0,pointer('LLVMConstNull',pointer('LLVMTypeOf',old)));after=dict(is_null=number('(int)LLVMIsNull((void*)%d)'%operand(target,0)));assert after['is_null']
  elif action=='collection-read-flags':
   candidates=[value for block in body for value in instructions(block) if opcode(value)==29 and pointer('LLVMIsAInstruction',operand(value,0)) and opcode(operand(value,0))==53]
   assert len(candidates)==1,candidates
   target=candidates[0];before=number('(unsigned)LLVMGEPGetNoWrapFlags((void*)%d)'%target);assert before==0
   gdb.parse_and_eval('(void)LLVMGEPSetNoWrapFlags((void*)%d,1)'%target);after=number('(unsigned)LLVMGEPGetNoWrapFlags((void*)%d)'%target);assert after&1 and after!=before
'''
		assert prior.GDB.count(needle) == 1
		prior.GDB = prior.GDB.replace(needle, collection_mutations+needle)
	if options.feature == 'format':
		# Reuse the existing public-CLI/process-local mutation driver. These
		# specimens load their actual library dependencies as distinct sources.
		extra = [ROOT/('lib/astra/'+n+'.astra') for n in ('base/errors', 'base/diagnostics', 'text/utf8-message', 'text/utf8-byte-builder', 'text/scalar-format', 'hosted/text-ops', 'collections/bag', 'hosted/text')]
		prior.COMPOUND = '''int main() {
	try {
		var builder = new Utf8ByteBuilder(); f64 value = 1.0d;
		if (!format_into(builder, $"prefix {value} suffix")) return 1;
		return 42;
	} catch (Error error) { return 2; }
}
'''
		prior.RECORD = '''int main() {
	try { var text = format_text($"value {42}"); if (text.text == "value 42") return 42; return 1; }
	catch (Error error) { return 2; }
}
'''
		prior.CASES = {
			'format-fragment-length': ('compound', '@prefix:astra.format.into.', 'format-fragment-length'),
			'format-nonfinite-mask': ('compound', '@prefix:astra.format.into.', 'format-nonfinite-mask'),
			'format-failure-branch': ('compound', '@prefix:astra.format.into.', 'format-failure-branch'),
			'format-owned-output': ('record', '@prefix:astra.format.text.', 'format-owned-output'),
			'format-owned-retirement': ('record', '@prefix:astra.format.text.', 'format-owned-retirement'),
			'format-owned-error': ('record', '@prefix:astra.format.text.', 'format-owned-error'),
		}
		lookup = ''' if requested.startswith('@prefix:'):
  function=pointer('LLVMGetFirstFunction',module);matches=[];budget=8192
  while function and budget:
   if name(function).startswith(requested[8:]) and blocks(function):matches.append(function)
   function=pointer('LLVMGetNextFunction',function);budget-=1
  assert len(matches)==1,matches
  return matches[0]
'''
		assert prior.GDB.count('def function_for(module,requested):\n') == 1
		prior.GDB = prior.GDB.replace('def function_for(module,requested):\n', 'def function_for(module,requested):\n'+lookup)
		format_mutations = '''  elif action=='format-fragment-length':
   candidates=[value for value in instructions(body[1]) if opcode(value)==45 and number('(unsigned)LLVMGetNumArgOperands((void*)%d)'%value)==3]
   assert len(candidates)==1,candidates
   target=candidates[0];old=operand(target,2);before=integer(old);assert before==7
   set_operand(target,2,replacement(old,8));after=integer(operand(target,2));assert after==8
  elif action=='format-nonfinite-mask':
   candidates=[value for value in instructions(body[0]) if opcode(value)==23 and pointer('LLVMIsAConstantInt',operand(value,1)) and integer(operand(value,1))==9218868437227405312]
   assert len(candidates)==1,candidates
   target=candidates[0];old=operand(target,1);before=integer(old)
   set_operand(target,1,replacement(old,0));after=integer(operand(target,1));assert after==0
  elif action=='format-failure-branch':
   target=pointer('LLVMGetBasicBlockTerminator',body[1]);assert opcode(target)==71 and number('(unsigned)LLVMGetNumSuccessors((void*)%d)'%target)==2
   first=number('(void*)LLVMGetSuccessor((void*)%d,0)'%target);last=number('(void*)LLVMGetSuccessor((void*)%d,1)'%target);assert first!=last
   before=[first,last]
   gdb.parse_and_eval('(void)LLVMSetSuccessor((void*)%d,0,(void*)%d)'%(target,last));gdb.parse_and_eval('(void)LLVMSetSuccessor((void*)%d,1,(void*)%d)'%(target,first))
   after=[number('(void*)LLVMGetSuccessor((void*)%d,%d)'%(target,n)) for n in (0,1)];assert after==[last,first]
  elif action=='format-owned-output':
   target=instructions(body[1])[0];assert opcode(target)==45 and number('(unsigned)LLVMGetNumArgOperands((void*)%d)'%target)==2
   old=operand(target,0);before=dict(is_output_slot=old==number('(void*)LLVMGetParam((void*)%d,0)'%function));assert before['is_output_slot']
   set_operand(target,0,pointer('LLVMConstNull',pointer('LLVMTypeOf',old)));after=dict(is_null=number('(int)LLVMIsNull((void*)%d)'%operand(target,0)));assert after['is_null']
  elif action=='format-owned-retirement':
   target=instructions(body[1])[1];assert opcode(target)==45 and number('(unsigned)LLVMGetNumArgOperands((void*)%d)'%target)==1
   old=operand(target,0);before=dict(builder=old);assert old==instructions(body[0])[0]
   set_operand(target,0,pointer('LLVMConstNull',pointer('LLVMTypeOf',old)));after=dict(is_null=number('(int)LLVMIsNull((void*)%d)'%operand(target,0)));assert after['is_null']
  elif action=='format-owned-error':
   target=pointer('LLVMGetBasicBlockTerminator',body[2]);assert opcode(target)==1
   old=operand(target,0);before=dict(error_constructor=old);assert opcode(old)==45
   set_operand(target,0,pointer('LLVMConstNull',pointer('LLVMTypeOf',old)));after=dict(is_null=number('(int)LLVMIsNull((void*)%d)'%operand(target,0)));assert after['is_null']
'''
		assert prior.GDB.count(needle) == 1
		prior.GDB = prior.GDB.replace(needle, format_mutations+needle)
		original_execute = prior.execute
		def with_sources(argv, *args, **kwargs):
			if argv[0] == 'gdb':
				argv.extend(extra)
				write(Path(args[0]).parent/'extension-inputs.json', identity)
			return original_execute(argv, *args, **kwargs)
		prior.execute = with_sources
	identity = {str(path):sha(path) for path in (Path(__file__), Path(__file__).with_name('named.py'), PRIOR/'physical.py', PRIOR/'support.py')}
	identity.update({str(path):sha(path) for path in extra})
	prior.main()
	assert all(sha(path) == h for path,h in identity.items())
	arguments = sys.argv[1:]
	runtime = Path(arguments[arguments.index('--runtime')+1])
	result = json.loads((runtime/'result.json').read_text())
	result['extension_inputs'] = identity
	result['feature'] = options.feature
	scopes = dict(existing='named ABI operands, match phi values, nested tag tests, enum stores/layout and fresh temporary retirement', format='typed formatting fragments, finite prechecks, failure edges, owned output and retirement', lazy='integer/floating reduction flags, filter skip edges and captured values', collection='element allocation sizes, logical lengths, hidden intermediate allocations, partial retirement and borrowed reads', range='count limits, final advancement, allocation size/intermediates, inclusive bounds, checked slice bounds and fixed backing alignment', enum='named enum payload storage slots and fresh-buffer retirement on later argument failure')
	result['scope'] = 'Selected 27-C actual '+scopes[options.feature]+'. The unchanged 27-B driver observes structural LLVM acceptance and independent physical refusal with preserved sentinels. No complete milestone, source, owner or memory credit.'
	write(runtime/'result.json', result)


if __name__ == '__main__': main()
