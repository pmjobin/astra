#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""LLVM-valid wrong specializations rejected by independent ABI/runtime oracles.

Mutants are private post-emission candidates, never compiler outputs credited as
qualified. This is distinct from the inherited retained-module audit mutations.
"""
import argparse
from collections import Counter
import ctypes as c
import json
import os
from pathlib import Path
import resource
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from state import ROOT, RUNTIME, BUILD, C0, read, sha

DECLS = {
	'identity': 'T identity<T>(T value) { return value; }',
	'choose': 'T choose<T>(T first, T second) { return first; }',
	'right': 'U right<U>(U first, U second) { return second; }',
	'relay': 'owned T[] relay<T>(owned T[] value) { return move value; }',
}
RECORDS = {'A':'struct A { int x; int y; }', 'B':'struct B { int x; int y; }'}
SOURCE = '\n'.join([*RECORDS.values(), *DECLS.values()])+'''
int main() {
	A a = {x = 7, y = 11}; B b = {x = 13, y = 17};
	var left = identity<A>(a); var other = identity<B>(b);
	int first = choose<int>(23, 29); int last = right<int>(31, 37);
	var buffer = new int[2]; buffer[1] = 41; var result = relay<int>(move buffer);
	if (left.x != 7 || left.y != 11 || other.x != 13 || other.y != 17 || first != 23 || last != 37 || len(result) != 2 || result[1] != 41) return 99;
	return 53;
}
'''


class LLVM:
	def __init__(self):
		self.path = Path(subprocess.check_output(['llvm-config','--link-shared','--libfiles','core','irreader'], text=True).strip()).resolve()
		self.lib = c.CDLL(str(self.path)); P = c.c_void_p; U = c.c_uint
		for name, ret, args in [
			('LLVMContextCreate',P,[]), ('LLVMContextDispose',None,[P]), ('LLVMDisposeModule',None,[P]),
			('LLVMCreateMemoryBufferWithContentsOfFile',c.c_int,[c.c_char_p,c.POINTER(P),c.POINTER(P)]),
			('LLVMParseIRInContext',c.c_int,[P,P,c.POINTER(P),c.POINTER(P)]),
			('LLVMPrintModuleToFile',c.c_int,[P,c.c_char_p,c.POINTER(P)]),
			('LLVMGetFirstFunction',P,[P]), ('LLVMGetNextFunction',P,[P]),
			('LLVMGetValueName2',P,[P,c.POINTER(c.c_size_t)]),
			('LLVMGetFirstBasicBlock',P,[P]), ('LLVMGetNextBasicBlock',P,[P]),
			('LLVMGetFirstInstruction',P,[P]), ('LLVMGetNextInstruction',P,[P]),
			('LLVMGetInstructionOpcode',U,[P]), ('LLVMGetCalledValue',P,[P]),
			('LLVMGetNumOperands',c.c_int,[P]), ('LLVMGetOperand',P,[P,U]),
			('LLVMSetOperand',None,[P,U,P]), ('LLVMGetNumArgOperands',U,[P]), ('LLVMGetArgOperand',P,[P,U]),
			('LLVMGlobalGetValueType',P,[P]), ('LLVMTypeOf',P,[P]), ('LLVMGetTypeKind',c.c_int,[P]),
			('LLVMConstNull',P,[P]), ('LLVMSetFunctionCallConv',None,[P,U]),
			('LLVMSetInstructionCallConv',None,[P,U]), ('LLVMGetFunctionCallConv',U,[P]),
			('LLVMGetInstructionCallConv',U,[P]), ('LLVMDisposeMessage',None,[P]),
		]:
			fn = getattr(self.lib,name); fn.restype = ret; fn.argtypes = args; setattr(self,name,fn)

	def name(self, value):
		size = c.c_size_t(); pointer = self.LLVMGetValueName2(value,c.byref(size))
		return c.string_at(pointer,size.value).decode()

	def instructions(self, function):
		block = self.LLVMGetFirstBasicBlock(function)
		while block:
			instruction = self.LLVMGetFirstInstruction(block)
			while instruction:
				yield instruction; instruction = self.LLVMGetNextInstruction(instruction)
			block = self.LLVMGetNextBasicBlock(block)

	def load(self, path):
		context = self.LLVMContextCreate(); memory = c.c_void_p(); module = c.c_void_p(); message = c.c_void_p()
		assert self.LLVMCreateMemoryBufferWithContentsOfFile(os.fsencode(path),c.byref(memory),c.byref(message)) == 0
		assert self.LLVMParseIRInContext(context,memory,c.byref(module),c.byref(message)) == 0
		return context,module

	def inventory(self, module):
		groups = {}; functions = []; function = self.LLVMGetFirstFunction(module)
		while function:
			functions.append(function); name = self.name(function)
			if name.startswith('astra.g.'):
				key = bytes.fromhex(name[len('astra.g.'):]).decode()
				for group, source in DECLS.items():
					if ':source:'+source.encode().hex()+':end-source' in key:
						label = group
						if group == 'identity':
							label += '-'+next(record for record, declaration in RECORDS.items() if ':source:'+declaration.encode().hex()+':end-source' in key)
						assert label not in groups; groups[label] = function
			function = self.LLVMGetNextFunction(function)
		assert set(groups) == {'identity-A','identity-B','choose','right','relay'}
		calls = [inst for fn in functions for inst in self.instructions(fn) if self.LLVMGetInstructionOpcode(inst) == 45]
		return groups,calls

	def oracle(self, module):
		groups,calls = self.inventory(module); actual = Counter(self.LLVMGetCalledValue(call) for call in calls)
		# This fixture declares exactly one source call per specialization. The
		# expected multiset comes from its source, not a producer's emitted IR.
		identities = all(actual[fn] == 1 for fn in groups.values())
		conventions = all(self.LLVMGetFunctionCallConv(fn) == 0 for fn in groups.values()) and all(self.LLVMGetInstructionCallConv(call) == 0 for call in calls if self.LLVMGetCalledValue(call) in groups.values())
		return dict(exact_source_specialization_calls=identities, private_ABI_C_convention=conventions)

	def mutate(self, module, category):
		groups,calls = self.inventory(module)
		def call_to(label): return next(call for call in calls if self.LLVMGetCalledValue(call) == groups[label])
		if category in (0,1):
			old,new = ('identity-A','identity-B') if category == 0 else ('choose','right')
			assert self.LLVMGlobalGetValueType(groups[old]) == self.LLVMGlobalGetValueType(groups[new])
			call = call_to(old); self.LLVMSetOperand(call,self.LLVMGetNumOperands(call)-1,groups[new])
		elif category == 2:
			call = call_to('choose'); assert self.LLVMGetNumArgOperands(call) == 2
			first = self.LLVMGetArgOperand(call,0); second = self.LLVMGetArgOperand(call,1)
			self.LLVMSetOperand(call,0,second); self.LLVMSetOperand(call,1,first)
		elif category == 3:
			call = call_to('relay'); count = self.LLVMGetNumArgOperands(call); argument = self.LLVMGetArgOperand(call,count-1)
			assert self.LLVMGetTypeKind(self.LLVMTypeOf(argument)) in (10,12)
			self.LLVMSetOperand(call,count-1,self.LLVMConstNull(self.LLVMTypeOf(argument)))
		elif category == 4:
			transport = next(inst for inst in self.instructions(groups['identity-A']) if self.LLVMGetInstructionOpcode(inst) in (1,28) and self.LLVMGetNumOperands(inst) > 0 and self.LLVMGetTypeKind(self.LLVMTypeOf(self.LLVMGetOperand(inst,0))) == 10)
			value = self.LLVMGetOperand(transport,0); self.LLVMSetOperand(transport,0,self.LLVMConstNull(self.LLVMTypeOf(value)))
		else:
			assert category == 5
			self.LLVMSetFunctionCallConv(groups['choose'],8)
			for call in calls:
				if self.LLVMGetCalledValue(call) == groups['choose']: self.LLVMSetInstructionCallConv(call,8)


def main():
	resource.setrlimit(resource.RLIMIT_CORE,(0,0))
	p = argparse.ArgumentParser(); p.add_argument('--prepare',action='store_true'); p.add_argument('--pilot',action='store_true'); p.add_argument('--component',type=Path); p.add_argument('--mode',choices=('O0','O2')); p.add_argument('--name'); a = p.parse_args()
	inputs = RUNTIME/'physical-input-v1'; inputs.mkdir(exist_ok=True); path = inputs/'specializations.astra'
	if path.exists(): assert path.read_text() == SOURCE
	else: path.write_text(SOURCE)
	selection = [dict(name='specialization-machine-oracles',sources=[dict(path=str(path),bytes=path.stat().st_size,sha256=sha(path))],expected_exit=53,oracle='Explicit field, argument-order, ownership and length assertions; manual 53; one call per exact source specialization and C calling convention required by the separate ABI')]
	selected = inputs/'selection.json'
	if not selected.exists(): selected.write_text(json.dumps(selection,indent=2)+'\n')
	else: assert read(selected) == selection
	if a.prepare: return
	assert a.component and a.mode and a.name and a.name.replace('-','').isalnum()
	leaf = RUNTIME/a.name; build = BUILD/a.name; leaf.mkdir(exist_ok=False); build.mkdir(exist_ok=False); commands = []
	env = dict(os.environ,CCACHE_DISABLE='1'); env.pop('VALGRIND_OPTS',None)
	def run(argv,name):
		start = time.monotonic(); r = subprocess.run(['/usr/bin/time','-v','-o',leaf/(name+'.time'),*map(str,argv)],cwd=build,capture_output=True,env=env,timeout=240)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name,argv=list(map(str,argv)),exit=r.returncode,start=start,end=time.monotonic(),stdout_sha256=sha(leaf/(name+'.stdout')),stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands,indent=2)+'\n'); return r
	if a.pilot:
		identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256']
		for file, expected in identity['identity']['sources'].items():
			file = Path(file)
			if sha(file) != expected:
				assert file.is_relative_to(ROOT) and sha(RUNTIME/'source-baseline'/file.relative_to(ROOT)) == expected
		raw = build/'diagnostic-twin.raw.ll'
		assert run([a.component,'--classstorage-llvm-raw',a.mode,raw,path],'diagnostic-twin').returncode == 0
	else:
		assert run([sys.executable,'-B',ROOT/'tests/selfhost-classstorage/run.py','--compiler',C0,'--compiler-sha256',sha(C0),'--component',a.component,'--mode',a.mode,'--selection',selected,'--build',build/'valid','--runtime',leaf/'valid'],'valid-twin').returncode == 0
		assert all(row['baseline_complete'] for row in read(leaf/'valid/results.json'))
		raw = build/'valid'/('specialization-machine-oracles-'+a.mode+'.raw.ll')
	original = sha(raw)
	api = LLVM(); results = []; categories = ['nominal-specialization-collapse','lexical-generic-callee-replacement','generic-channel-permutation','null-owned-generic-channel','stale-zero-record-product','consistent-wrong-specialization-convention']
	for category,label in enumerate(categories):
		context,module = api.load(raw)
		try:
			assert all(api.oracle(module).values()); api.mutate(module,category); oracle = api.oracle(module)
			mutant = build/(label+'.ll'); message = c.c_void_p(); assert api.LLVMPrintModuleToFile(module,os.fsencode(mutant),c.byref(message)) == 0
		finally:
			api.LLVMDisposeModule(module); api.LLVMContextDispose(context)
		assert run(['opt','-passes=verify','-disable-output',mutant],label+'-LLVM-verify').returncode == 0
		obj = mutant.with_suffix('.o'); app = mutant.with_suffix('')
		assert run(['llc','-'+a.mode,'-relocation-model=pic','-filetype=obj',mutant,'-o',obj],label+'-lower').returncode == 0
		assert run(['gcc',obj,'-o',app],label+'-link').returncode == 0
		xml = leaf/(label+'.xml')
		r = run(['valgrind','--command-line-only=yes','--default-suppressions=no','--error-exitcode=97','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=all','--track-origins=yes','--xml=yes','--xml-file='+str(xml),app],label+'-native')
		errors = len(ET.parse(xml).getroot().findall('error')); refused = not all(oracle.values()) or r.returncode != 53 or errors != 0
		assert refused and sha(raw) == original
		if category in (0,5): assert not all(oracle.values())
		else: assert r.returncode != 53 or errors != 0
		results.append(dict(category=category,label=label,LLVM_valid=True,independent_oracle=oracle,native_exit=r.returncode,Valgrind_errors=errors,qualification_rejected=True,original_twin_sha256=original,mutant_sha256=sha(mutant),object_sha256=sha(obj),ELF_sha256=sha(app)))
		(leaf/'mutations.json').write_text(json.dumps(results,indent=2)+'\n'); print(label,'LLVM_VALID REJECTED',flush=True)
	(leaf/'result.json').write_text(json.dumps(dict(status='DIAGNOSTIC_ONLY' if a.pilot else 'PASS',mode=a.mode,component_sha256=sha(a.component),recipe_sha256=sha(__file__),LLVM_library_sha256=sha(api.path),mutations=results,commands=commands,limitation='Six post-emission candidates are independently rejected by source/ABI/runtime qualification; no claim that the compiler retained-module audit consumed these external candidates. The inherited physical audit gate is rerun separately. A pilot has no final valid-twin qualification.'),indent=2)+'\n')


if __name__ == '__main__':
	main()
