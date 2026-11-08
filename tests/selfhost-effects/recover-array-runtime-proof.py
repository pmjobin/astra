#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual bounds helpers, independent LLVM-valid controls, unchanged C0 oracle."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
from state import ROOT, C0, load_module, bounded_run, sha

PROVIDER = r'''#include <stdint.h>
#include <stdio.h>
#include <llvm-c/Core.h>
#include <llvm-c/Analysis.h>
static LLVMContextRef context;
static LLVMModuleRef module;
static LLVMBuilderRef builder;
static LLVMValueRef trap;
static LLVMValueRef instruction(LLVMValueRef f, unsigned b, unsigned n) {
	LLVMBasicBlockRef block = LLVMGetFirstBasicBlock(f);
	while (b--) block = LLVMGetNextBasicBlock(block);
	LLVMValueRef p = LLVMGetFirstInstruction(block);
	while (n--) p = LLVMGetNextInstruction(p);
	return p;
}
void array_test_open(void) {
	context = LLVMContextCreate(); module = LLVMModuleCreateWithNameInContext("independent-array-preflight", context); builder = LLVMCreateBuilderInContext(context);
	trap = LLVMAddFunction(module, "llvm.trap", LLVMFunctionType(LLVMVoidTypeInContext(context), NULL, 0, 0));
}
void *array_test_handle(int32_t which) {
	LLVMTypeRef fields[] = {LLVMPointerTypeInContext(context, 0), LLVMInt32TypeInContext(context)};
	return which == 0 ? (void *)context : which == 1 ? (void *)module : which == 2 ? (void *)builder : which == 3 ? (void *)trap : which == 4 ? (void *)LLVMInt8TypeInContext(context) : (void *)LLVMStructTypeInContext(context, fields, 2, 0);
}
static void wrappers(LLVMValueRef index, LLVMValueRef slice) {
	LLVMTypeRef word = LLVMInt32TypeInContext(context), pointer = LLVMPointerTypeInContext(context, 0), args[] = {pointer, word, word, word};
	LLVMValueRef f = LLVMAddFunction(module, "array_candidate_read", LLVMFunctionType(word, args, 3, 0));
	LLVMPositionBuilderAtEnd(builder, LLVMAppendBasicBlockInContext(context, f, "entry"));
	LLVMValueRef inputs[] = {LLVMGetParam(f, 0), LLVMGetParam(f, 1), LLVMGetParam(f, 2), NULL};
	LLVMValueRef address = LLVMBuildCall2(builder, LLVMGlobalGetValueType(index), index, inputs, 3, ""); LLVMSetInstructionCallConv(address, 8);
	LLVMBuildRet(builder, LLVMBuildZExt(builder, LLVMBuildLoad2(builder, LLVMInt8TypeInContext(context), address, ""), word, ""));
	f = LLVMAddFunction(module, "array_candidate_slice", LLVMFunctionType(word, args, 4, 0));
	LLVMBasicBlockRef entry = LLVMAppendBasicBlockInContext(context, f, "entry"), empty = LLVMAppendBasicBlockInContext(context, f, "empty"), bytes = LLVMAppendBasicBlockInContext(context, f, "bytes");
	LLVMPositionBuilderAtEnd(builder, entry);
	for (unsigned p = 0; p < 4; p++) inputs[p] = LLVMGetParam(f, p);
	LLVMValueRef view = LLVMBuildCall2(builder, LLVMGlobalGetValueType(slice), slice, inputs, 4, ""); LLVMSetInstructionCallConv(view, 8);
	LLVMValueRef backing = LLVMBuildExtractValue(builder, view, 0, ""), count = LLVMBuildExtractValue(builder, view, 1, "");
	LLVMBuildCondBr(builder, LLVMBuildICmp(builder, LLVMIntEQ, count, LLVMConstInt(word, 0, 0), ""), empty, bytes);
	LLVMPositionBuilderAtEnd(builder, empty); LLVMBuildRet(builder, LLVMConstInt(word, 0, 0));
	LLVMPositionBuilderAtEnd(builder, bytes);
	LLVMValueRef last = LLVMBuildSub(builder, count, LLVMConstInt(word, 1, 0), "");
	LLVMValueRef end = LLVMBuildGEP2(builder, LLVMInt8TypeInContext(context), backing, &last, 1, "");
	LLVMValueRef first_value = LLVMBuildZExt(builder, LLVMBuildLoad2(builder, LLVMInt8TypeInContext(context), backing, ""), word, "");
	LLVMValueRef last_value = LLVMBuildZExt(builder, LLVMBuildLoad2(builder, LLVMInt8TypeInContext(context), end, ""), word, "");
	LLVMBuildRet(builder, LLVMBuildAdd(builder, LLVMBuildAdd(builder, LLVMBuildMul(builder, first_value, LLVMConstInt(word, 257, 0), ""), last_value, ""), count, ""));
}
int32_t array_test_finish(int32_t variant) {
	LLVMValueRef index = LLVMGetNamedFunction(module, "fixture.index"), slice = LLVMGetNamedFunction(module, "fixture.slice");
	LLVMTypeRef word = LLVMInt32TypeInContext(context);
	if (variant == 1 || variant == 2 || variant == 3) {
		LLVMValueRef old = instruction(index, 0, variant); LLVMPositionBuilderBefore(builder, old);
		LLVMValueRef value = LLVMBuildICmp(builder, variant == 3 ? LLVMIntSLE : LLVMIntSGT, LLVMGetOperand(old, 0), LLVMGetOperand(old, 1), ""); LLVMReplaceAllUsesWith(old, value); LLVMInstructionEraseFromParent(old);
	}
	if (variant == 4) LLVMSetCondition(instruction(index, 0, 7), LLVMConstInt(LLVMInt1TypeInContext(context), 1, 0));
	if (variant == 5) { LLVMValueRef old = instruction(index, 2, 0), offset = LLVMGetOperand(old, 1); LLVMPositionBuilderBefore(builder, old); LLVMValueRef value = LLVMBuildGEP2(builder, word, LLVMGetOperand(old, 0), &offset, 1, ""); LLVMReplaceAllUsesWith(old, value); LLVMInstructionEraseFromParent(old); }
	if (variant == 6) LLVMSetOperand(instruction(index, 2, 0), 1, LLVMConstInt(word, 0, 0));
	if (variant == 7) LLVMGEPSetNoWrapFlags(instruction(index, 2, 0), LLVMGEPFlagInBounds);
	if (variant == 8) LLVMSetOperand(instruction(index, 2, 1), 0, LLVMGetParam(index, 0));
	if (variant == 9) { unsigned kind = LLVMGetEnumAttributeKindForName("memory", 6); LLVMAddAttributeAtIndex(index, LLVMAttributeFunctionIndex, LLVMCreateEnumAttribute(context, kind, 0)); }
	if (variant == 10) LLVMSetOperand(instruction(slice, 0, 4), 0, LLVMGetParam(slice, 2));
	if (variant == 11) LLVMSetOperand(instruction(slice, 0, 11), 0, LLVMConstInt(LLVMInt1TypeInContext(context), 1, 0));
	if (variant == 12) LLVMSetOperand(instruction(slice, 2, 2), 1, LLVMGetParam(slice, 2));
	if (variant == 13) LLVMSetOperand(instruction(slice, 2, 0), 1, LLVMGetParam(slice, 3));
	if (variant == 14) { LLVMValueRef old = instruction(slice, 0, 8); LLVMPositionBuilderBefore(builder, old); LLVMValueRef value = LLVMBuildAnd(builder, LLVMGetOperand(old, 0), LLVMGetOperand(old, 1), ""); LLVMReplaceAllUsesWith(old, value); LLVMInstructionEraseFromParent(old); }
	if (variant == 15) LLVMSetICmpSameSign(instruction(slice, 0, 3), 1);
	if (variant == 16) { LLVMPositionBuilderBefore(builder, instruction(slice, 2, 3)); LLVMBuildAdd(builder, LLVMGetParam(slice, 2), LLVMGetParam(slice, 3), "unaccounted"); }
	if (variant == 0) wrappers(index, slice);
	char *error = NULL; int failed = LLVMVerifyModule(module, LLVMReturnStatusAction, &error); if (error) { if (failed) fputs(error, stderr); LLVMDisposeMessage(error); }
	char path[64]; snprintf(path, sizeof path, "array-%d.ll", variant); error = NULL; if (LLVMPrintModuleToFile(module, path, &error)) failed = 1; if (error) LLVMDisposeMessage(error);
	return !failed;
}
static LLVMValueRef cast_function;
static int cast_variant;
void array_cast_begin(int32_t variant) {
	cast_variant = variant;
	unsigned width = variant == 0 || variant == 3 || variant == 4 || variant == 5 ? 8 : 32;
	unsigned target = variant == 0 || variant == 3 || variant == 4 || variant == 5 || variant == 6 ? 32 : 8;
	LLVMTypeRef source = LLVMIntTypeInContext(context, width), parameters[] = {source, source};
	cast_function = LLVMAddFunction(module, "candidate_cast", LLVMFunctionType(LLVMIntTypeInContext(context, target), parameters, 2, 0));
	LLVMPositionBuilderAtEnd(builder, LLVMAppendBasicBlockInContext(context, cast_function, "entry"));
}
void *array_cast_input(void) { return cast_variant == 7 ? LLVMConstInt(LLVMInt32TypeInContext(context), 42, 0) : LLVMGetParam(cast_function, 0); }
void *array_cast_type(void) { return LLVMGetReturnType(LLVMGlobalGetValueType(cast_function)); }
void *array_cast_change(void *raw) {
	LLVMValueRef value = raw;
	if (cast_variant == 1) LLVMSetNSW(value, 1);
	if (cast_variant == 2) LLVMSetNUW(value, 1);
	if (cast_variant == 3) LLVMSetNNeg(value, 1);
	if (cast_variant == 4 || cast_variant == 5) {
		LLVMPositionBuilderBefore(builder, value);
		LLVMValueRef changed = cast_variant == 4 ? LLVMBuildZExt(builder, LLVMGetOperand(value, 0), LLVMTypeOf(value), "") : LLVMBuildSExt(builder, LLVMGetOperand(value, 0), LLVMTypeOf(value), "");
		LLVMInstructionEraseFromParent(value); value = changed;
		LLVMPositionBuilderAtEnd(builder, LLVMGetEntryBasicBlock(cast_function));
	}
	if (cast_variant == 6) value = LLVMGetParam(cast_function, 1);
	if (cast_variant == 7) value = LLVMConstInt(LLVMTypeOf(value), 43, 0);
	if (cast_variant == 8) LLVMSetMetadata(value, LLVMGetMDKindIDInContext(context, "proof", 5), LLVMMetadataAsValue(context, LLVMMDNodeInContext2(context, NULL, 0)));
	LLVMBuildRet(builder, value);
	return value;
}
int32_t array_cast_finish(void) {
	char *error = NULL; int failed = LLVMVerifyModule(module, LLVMReturnStatusAction, &error); if (error) { if (failed) fputs(error, stderr); LLVMDisposeMessage(error); }
	char path[64]; snprintf(path, sizeof path, "array-cast-%d.ll", cast_variant); error = NULL; if (LLVMPrintModuleToFile(module, path, &error)) failed = 1; if (error) LLVMDisposeMessage(error);
	return !failed;
}

void array_test_close(void) { LLVMDisposeBuilder(builder); LLVMDisposeModule(module); LLVMContextDispose(context); }
'''

CALLER = '''extern(C) void array_test_open();
extern(C) void* array_test_handle(int which);
extern(C) int array_test_finish(int variant);
extern(C) void array_test_close();
extern(C) void array_cast_begin(int variant);
extern(C) void* array_cast_input();
extern(C) void* array_cast_type();
extern(C) void* array_cast_change(void* value);
extern(C) int array_cast_finish();
int main() {
	int variant = 0;
	while (variant <= 16) {
		array_test_open();
		var handles = llvm12_handles();
		var runtime = new RecoverArrayRuntime(array_test_handle(0), array_test_handle(1), array_test_handle(2), handles, array_test_handle(3));
		var index = runtime.index_helper(array_test_handle(4), "fixture.index");
		var view = runtime.slice_helper(array_test_handle(4), array_test_handle(5), "fixture.slice");
		if (array_test_finish(variant) != 1) return 60 + variant;
		bool valid = recover_array_index_helper(index, array_test_handle(4), "fixture.index", array_test_handle(3)) && recover_array_slice_helper(view, array_test_handle(4), array_test_handle(5), "fixture.slice", array_test_handle(3));
		llvm12_handles_dispose(handles);
		array_test_close();
		if (valid != (variant == 0)) return 10 + variant;
		variant = variant + 1;
	}
	variant = 0;
	while (variant <= 8) {
		array_test_open();
		array_cast_begin(variant);
		int source = 1;
		int target = 2;
		if (variant == 0 || variant == 4) { source = 2; target = 1; }
		if (variant == 3 || variant == 5) { source = 3; target = 1; }
		if (variant == 6) target = 6;
		var input = array_cast_input();
		var value = recover_array_integer_cast(array_test_handle(2), source, target, input, array_cast_type(), llvm12_empty());
		if (!recover_array_cast_verified(source, target, value, input)) return 90 + variant;
		var changed = array_cast_change(value);
		if (array_cast_finish() != 1) return 110 + variant;
		bool valid = recover_array_cast_verified(source, target, changed, input);
		array_test_close();
		if (valid != (variant == 0)) return 130 + variant;
		variant = variant + 1;
	}
	return 42;
}
'''

REFERENCE = '''owned u8[] array_reference_bytes(int count) { var bytes = new u8[count]; int p = 0; while (p < count) { bytes[p] = (p * 71) as u8; p = p + 1; } return move bytes; }
export(C) int array_reference_read(int count, int index) { var bytes = array_reference_bytes(count); return bytes[index] as int; }
int checksum(u8[] bytes) { if (len(bytes) == 0) return 0; return (bytes[0] as int) * 257 + (bytes[len(bytes) - 1] as int) + len(bytes); }
export(C) int array_reference_slice(int size, int start, int count) { if (size != 128) return -5; u8[128] bytes = {INITIALIZERS}; int p = 0; while (p < 128) { bytes[p] = (p * 71) as u8; p = p + 1; } return checksum(slice(bytes, start, count)); }
'''

REFERENCE = REFERENCE.replace('INITIALIZERS', ', '.join(['0'] * 128))

PROBE = r'''#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
extern int32_t array_candidate_read(uint8_t *, int32_t, int32_t);
extern int32_t array_reference_read(int32_t, int32_t);
extern int32_t array_candidate_slice(uint8_t *, int32_t, int32_t, int32_t);
extern int32_t array_reference_slice(int32_t, int32_t, int32_t);
int main(int argc, char **argv) {
	uint8_t bytes[128]; for (unsigned p = 0; p < sizeof bytes; p++) bytes[p] = (uint8_t)(p * 71);
	if (argc > 1) {
		int candidate = strcmp(argv[1], "candidate") == 0, test = atoi(argv[2]);
		if (test < 3) return candidate ? array_candidate_read(bytes, 128, test == 0 ? -1 : test == 1 ? 128 : 129) : array_reference_read(128, test == 0 ? -1 : test == 1 ? 128 : 129);
		int start = test == 3 ? -1 : test == 4 ? 129 : test == 5 ? 128 : 0, count = test == 5 ? 1 : test == 6 ? -1 : 0;
		return candidate ? array_candidate_slice(bytes, 128, start, count) : array_reference_slice(128, start, count);
	}
	unsigned observations = 0;
	for (int count = 0; count <= 128; count++) {
		for (int p = 0; p < count; p++) { if (array_candidate_read(bytes, count, p) != array_reference_read(count, p)) return 2; observations++; }
		if (count == 128) for (int start = 0; start <= count; start++) for (int size = 0; size <= count - start; size++) { if (array_candidate_slice(bytes, count, start, size) != array_reference_slice(count, start, size)) return 3; observations++; }
	}
	if (array_candidate_slice(NULL, 0, 0, 0) != 0) return 4;
	printf("ARRAY_C0_DIFFERENTIAL %u\n", observations + 1);
	return 42;
}
'''


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--version', required=True)
	a = p.parse_args()
	assert a.version.isalnum()
	paths = load_module('array_runtime_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	leaf = paths.RUNTIME/('array-runtime-'+a.version)
	build = paths.BUILD/leaf.name
	leaf.mkdir()
	build.mkdir()
	for name, data in [('provider.c', PROVIDER), ('caller.astra', CALLER), ('reference.astra', REFERENCE), ('probe.c', PROBE)]:
		(leaf/name).write_text(data)
	views = []
	for relative, end in [('recover-check.astra', b'bool recover_llvm_literal('), ('recover-helpers-check.astra', b'bool recover_llvm_external_verified('), ('recover-carrier-check.astra', b'bool recover_llvm_group('), ('recover-shared-check.astra', b'bool recover_shared_control_verified('), ('recover-array-instructions.astra', b'bool recover_array_memory(')]:
		source = ROOT/'compiler/backend/llvm'/relative
		data = source.read_bytes()
		last = data.index(end)
		target = leaf/relative
		target.write_bytes(data[:last])
		views.append(dict(source=str(source), source_sha256=sha(source), first=0, last=last, view=str(target), sha256=sha(target), classification='Unchanged complete pure helper definitions; unrelated consumers omitted.'))
	source = ROOT/'compiler/backend/llvm/recover-instructions.astra'
	data = source.read_bytes()
	first = data.index(b'bool recover_llvm_native_attributes(')
	last = data.index(b'int recover_llvm_extract_instructions(')
	target = leaf/'recover-native-attributes.astra'
	target.write_bytes(data[first:last])
	views.append(dict(source=str(source), source_sha256=sha(source), first=first, last=last, view=str(target), sha256=sha(target), classification='Unchanged complete pure helper definition.'))
	source = ROOT/'compiler/semantic/types.astra'
	data = source.read_bytes()
	first = data.index(b'bool type_integer(')
	target = leaf/'integer-types.astra'
	target.write_bytes(data[first:])
	views.append(dict(source=str(source), source_sha256=sha(source), first=first, last=len(data), view=str(target), sha256=sha(target), classification='Unchanged complete pure integer type definitions.'))
	commands = []
	def run(argv, name, cwd=build, allowed=(0,)):
		argv = list(map(str, argv))
		start = time.monotonic()
		r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=cwd, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=300)
		(leaf/(name+'.stdout')).write_bytes(r.stdout)
		(leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode in allowed, (name, r.returncode, r.stdout[-2000:], r.stderr.splitlines()[:4])
		return r
	flags = subprocess.check_output(['llvm-config', '--cflags'], text=True).split()
	library = subprocess.check_output(['llvm-config', '--link-shared', '--libs', 'core', 'analysis'], text=True).strip()
	assert library.startswith('-l') and ' ' not in library
	obj = build/'provider.o'
	run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *flags, '-c', leaf/'provider.c', '-o', obj], 'provider-build')
	shim = build/'llvm-capi.o'
	run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *flags, '-c', ROOT/'compiler/backend/llvm/capi.c', '-o', shim], 'shim-build')
	sources = [ROOT/('compiler/backend/llvm/'+name+'.astra') for name in ('capi', 'recover-capi', 'recover-shared-capi', 'recover-array-capi', 'recover-array-emit', 'recover-array-check')]
	rows = []
	for mode in ('O0', 'O2'):
		working = build/mode
		working.mkdir()
		oracle = working/'reference.o'
		run([C0, '-'+mode, '-c', leaf/'reference.astra', '-o', oracle], mode+'-reference-build')
		exe = working/'proof'
		run([C0, '-'+mode, *sources, *[row['view'] for row in views], leaf/'caller.astra', '--link-object', obj, '--link-object', shim, '--link-library', library[2:], '-o', exe], mode+'-build')
		run([exe], mode+'-execute', cwd=working, allowed=(42,))
		for physical in sorted(working.glob('array-*.ll')):
			run(['opt', '-passes=verify', '-disable-output', physical], mode+'-verify-'+physical.stem)
		for target_mode in ('O0', 'O2'):
			target = working/('helper-'+target_mode)
			run(['clang', '-'+target_mode, working/'array-0.ll', oracle, leaf/'probe.c', '-o', target], mode+'-'+target_mode+'-helper-build')
			observed = run([target], mode+'-'+target_mode+'-helper-execute', allowed=(42,))
			memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', target], mode+'-'+target_mode+'-helper-memory', allowed=(42,))
			assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr and observed.stdout == memory.stdout
			for test in range(7):
				fatal = [run([target, who, str(test)], mode+'-'+target_mode+'-'+who+'-fatal-'+str(test), allowed=(132, -4)).returncode for who in ('candidate', 'reference')]
				assert fatal[0] == fatal[1]
		rows.append(dict(C0_producer_profile=mode, producer_ELF_sha256=sha(exe), C0_oracle_object_sha256=sha(oracle), physical_inputs={p.name: sha(p) for p in sorted(working.glob('array-*.ll'))}))
	(leaf/'result.json').write_text(json.dumps(dict(status='INDEPENDENT_ARRAY_RUNTIME_PREFLIGHT', profiles=rows, LLVM_valid_mutation_categories=24, bounds_categories=16, integer_cast_categories=8, source_sha256={str(p): sha(p) for p in sources}, helper_views=views, Astra_native_credit=0, limitation='Actual helper emitter and independent physical consumer under C0. Every mutation is independently LLVM-valid. Four helper-only native ELF differentials against original C0 indexed reads/slices, empty null slice, negative/boundary fatal cases and returning unsuppressed Valgrind. Zero Astra pipeline/original-function execution credit.'), indent=2)+'\n')
	print('Bounds/cast helper preflight passed; 24 LLVM-valid mutation categories, zero Astra pipeline execution credit', flush=True)


if __name__ == '__main__':
	main()
