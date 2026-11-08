#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual Shared emitter/consumer preflight, independently verified by LLVM."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
from state import ROOT, C0, load_module, bounded_run, sha

PROVIDER = r'''#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <llvm-c/Core.h>
#include <llvm-c/Analysis.h>
#include <llvm-c/Target.h>
struct independent_shared { uint64_t strong, weak; void *payload; };
_Static_assert(sizeof(struct independent_shared) == 24, "Shared control size");
_Static_assert(_Alignof(struct independent_shared) == 8, "Shared control alignment");
_Static_assert(offsetof(struct independent_shared, strong) == 0 && offsetof(struct independent_shared, weak) == 8 && offsetof(struct independent_shared, payload) == 16, "Shared control offsets");
static LLVMContextRef context;
static LLVMModuleRef module;
static LLVMBuilderRef builder;
static LLVMTargetDataRef layout;
static LLVMValueRef allocate, free_value, trap, destroy, drops;
static LLVMTypeRef ptr, i32, i64;
static LLVMValueRef call(LLVMValueRef f, LLVMValueRef *args, unsigned count, int native) {
	LLVMValueRef value = LLVMBuildCall2(builder, LLVMGlobalGetValueType(f), f, args, count, "");
	if (native) LLVMSetInstructionCallConv(value, 8);
	return value;
}
static LLVMValueRef function(const char *name, LLVMTypeRef result, LLVMTypeRef *args, unsigned count, int native) {
	LLVMValueRef value = LLVMAddFunction(module, name, LLVMFunctionType(result, args, count, 0));
	if (native) { LLVMSetFunctionCallConv(value, 8); LLVMSetLinkage(value, LLVMInternalLinkage); }
	return value;
}
static LLVMBasicBlockRef block(LLVMValueRef f, unsigned n) {
	LLVMBasicBlockRef p = LLVMGetFirstBasicBlock(f);
	while (n--) p = LLVMGetNextBasicBlock(p);
	return p;
}
static LLVMValueRef instruction(LLVMValueRef f, unsigned b, unsigned n) {
	LLVMValueRef p = LLVMGetFirstInstruction(block(f, b));
	while (n--) p = LLVMGetNextInstruction(p);
	return p;
}
static void predicate(LLVMValueRef function_value, unsigned b, unsigned n, LLVMIntPredicate condition) {
	LLVMValueRef old = instruction(function_value, b, n);
	LLVMPositionBuilderBefore(builder, old);
	LLVMValueRef replacement = LLVMBuildICmp(builder, condition, LLVMGetOperand(old, 0), LLVMGetOperand(old, 1), "");
	LLVMReplaceAllUsesWith(old, replacement); LLVMInstructionEraseFromParent(old);
}
void shared_test_open(void) {
	context = LLVMContextCreate(); module = LLVMModuleCreateWithNameInContext("independent-shared-preflight", context);
	builder = LLVMCreateBuilderInContext(context); layout = LLVMCreateTargetData("e-p:64:64-i64:64-n8:16:32:64-S128"); LLVMSetModuleDataLayout(module, layout);
	ptr = LLVMPointerTypeInContext(context, 0); i32 = LLVMInt32TypeInContext(context); i64 = LLVMInt64TypeInContext(context);
	LLVMTypeRef sizes[] = {i64, i64}, pointers[] = {ptr};
	LLVMValueRef calloc_value = function("calloc", ptr, sizes, 2, 0);
	free_value = function("free", LLVMVoidTypeInContext(context), pointers, 1, 0);
	trap = function("llvm.trap", LLVMVoidTypeInContext(context), NULL, 0, 0);
	allocate = function("fixture.allocate", ptr, sizes, 2, 1);
	LLVMBasicBlockRef entry = LLVMAppendBasicBlockInContext(context, allocate, "entry"), valid = LLVMAppendBasicBlockInContext(context, allocate, "valid"), fatal = LLVMAppendBasicBlockInContext(context, allocate, "fatal");
	LLVMPositionBuilderAtEnd(builder, entry); LLVMValueRef allocation_args[] = {LLVMGetParam(allocate, 0), LLVMGetParam(allocate, 1)};
	LLVMValueRef allocation = call(calloc_value, allocation_args, 2, 0);
	LLVMBuildCondBr(builder, LLVMBuildICmp(builder, LLVMIntNE, allocation, LLVMConstNull(ptr), ""), valid, fatal);
	LLVMPositionBuilderAtEnd(builder, valid); LLVMBuildRet(builder, allocation);
	LLVMPositionBuilderAtEnd(builder, fatal); call(trap, NULL, 0, 0); LLVMBuildUnreachable(builder);
	drops = LLVMAddGlobal(module, i32, "fixture.drops"); LLVMSetInitializer(drops, LLVMConstNull(i32));
	destroy = function("fixture.destroy.exact", LLVMVoidTypeInContext(context), pointers, 1, 1);
	LLVMPositionBuilderAtEnd(builder, LLVMAppendBasicBlockInContext(context, destroy, "entry"));
	LLVMValueRef before = LLVMBuildLoad2(builder, i32, drops, ""); LLVMBuildStore(builder, LLVMBuildAdd(builder, before, LLVMConstInt(i32, 1, 0), ""), drops);
	LLVMValueRef drop_args[] = {LLVMGetParam(destroy, 0)}; call(free_value, drop_args, 1, 0); LLVMBuildRetVoid(builder);
}
void *shared_test_handle(int32_t which) {
	switch (which) { case 0: return context; case 1: return module; case 2: return builder; case 3: return layout; case 4: return allocate; case 5: return free_value; case 6: return trap; default: return destroy; }
}
static void executable(void) {
	LLVMValueRef acquire = LLVMGetNamedFunction(module, "astra.e25a.shared.acquire"), clone = LLVMGetNamedFunction(module, "astra.e25a.shared.clone"), borrow = LLVMGetNamedFunction(module, "astra.e25a.shared.borrow"), release = LLVMGetNamedFunction(module, "fixture.release");
	LLVMValueRef main_value = function("main", i32, NULL, 0, 0); LLVMPositionBuilderAtEnd(builder, LLVMAppendBasicBlockInContext(context, main_value, "entry"));
	LLVMValueRef sizes[] = {LLVMConstInt(i64, 1, 0), LLVMConstInt(i64, 4, 0)}, payload = call(allocate, sizes, 2, 1); LLVMBuildStore(builder, LLVMConstInt(i32, 42, 0), payload);
	LLVMValueRef args[] = {payload}; LLVMValueRef original = call(acquire, args, 1, 1); args[0] = original;
	LLVMValueRef retained = call(clone, args, 1, 1); args[0] = LLVMConstNull(ptr); LLVMValueRef absent = call(clone, args, 1, 1);
	args[0] = original; call(release, args, 1, 1); args[0] = retained; LLVMValueRef view = call(borrow, args, 1, 1);
	LLVMValueRef observed = LLVMBuildLoad2(builder, i32, view, ""), same = LLVMBuildICmp(builder, LLVMIntEQ, view, payload, ""); call(release, args, 1, 1);
	args[0] = LLVMConstNull(ptr); call(release, args, 1, 1);
	LLVMValueRef count = LLVMBuildLoad2(builder, i32, drops, ""), correct = LLVMBuildICmp(builder, LLVMIntEQ, count, LLVMConstInt(i32, 1, 0), "");
	correct = LLVMBuildAnd(builder, correct, same, ""); correct = LLVMBuildAnd(builder, correct, LLVMBuildICmp(builder, LLVMIntEQ, observed, LLVMConstInt(i32, 42, 0), ""), ""); correct = LLVMBuildAnd(builder, correct, LLVMBuildICmp(builder, LLVMIntEQ, absent, LLVMConstNull(ptr), ""), "");
	LLVMBuildRet(builder, LLVMBuildSelect(builder, correct, LLVMConstInt(i32, 42, 0), LLVMConstInt(i32, 3, 0), ""));
}
int32_t shared_test_finish(int32_t variant) {
	LLVMValueRef increment = LLVMGetNamedFunction(module, "astra.e25a.shared.increment"), decrement = LLVMGetNamedFunction(module, "astra.e25a.shared.decrement"), acquire = LLVMGetNamedFunction(module, "astra.e25a.shared.acquire"), clone = LLVMGetNamedFunction(module, "astra.e25a.shared.clone"), borrow = LLVMGetNamedFunction(module, "astra.e25a.shared.borrow"), release = LLVMGetNamedFunction(module, "fixture.release");
	if (variant == 1) LLVMSetOperand(instruction(increment, 1, 2), 1, LLVMConstInt(i64, 100, 0));
	if (variant == 2) { LLVMSetCmpXchgSuccessOrdering(instruction(increment, 2, 1), LLVMAtomicOrderingMonotonic); LLVMSetCmpXchgFailureOrdering(instruction(increment, 2, 1), LLVMAtomicOrderingMonotonic); }
	if (variant == 3) LLVMSetWeak(instruction(increment, 2, 1), 1);
	if (variant == 4) LLVMSetOperand(instruction(clone, 1, 0), 2, LLVMConstInt(i32, 1, 0));
	if (variant == 5) { LLVMValueRef old = instruction(clone, 1, 1); LLVMSetOperand(old, LLVMGetNumOperands(old) - 1, decrement); }
	if (variant == 6) LLVMSetArgOperand(instruction(release, 2, 3), 0, LLVMGetParam(release, 0));
	if (variant == 7) predicate(release, 2, 6, LLVMIntNE);
	if (variant == 8) LLVMSetCondition(instruction(borrow, 1, 3), LLVMConstInt(LLVMInt1TypeInContext(context), 1, 0));
	if (variant == 9) predicate(borrow, 0, 0, LLVMIntEQ);
	if (variant == 10) LLVMSetArgOperand(instruction(acquire, 1, 0), 1, LLVMConstInt(i64, 8, 0));
	if (variant == 11) LLVMSetOperand(instruction(acquire, 1, 5), 0, LLVMGetParam(acquire, 0));
	if (variant == 12) predicate(release, 1, 2, LLVMIntNE);
	if (variant == 13) { unsigned kind = LLVMGetEnumAttributeKindForName("memory", 6); LLVMAddCallSiteAttribute(instruction(release, 3, 0), LLVMAttributeFunctionIndex, LLVMCreateEnumAttribute(context, kind, 0)); }
	if (variant == 14) LLVMSetOrdering(instruction(borrow, 1, 1), LLVMAtomicOrderingMonotonic);
	if (variant == 15) LLVMSetOperand(instruction(decrement, 2, 0), 1, LLVMConstInt(i64, 2, 0));
	if (variant == 16) LLVMSetICmpSameSign(instruction(increment, 1, 1), 1);
	if (variant == 17) {
		LLVMMetadataRef range[] = {LLVMValueAsMetadata(LLVMConstInt(i64, 1, 0)), LLVMValueAsMetadata(LLVMConstInt(i64, 10, 0))};
		LLVMSetMetadata(instruction(increment, 0, 0), LLVMGetMDKindIDInContext(context, "range", 5), LLVMMetadataAsValue(context, LLVMMDNodeInContext2(context, range, 2)));
	}
	if (variant == 0) executable();
	char *error = NULL; int failed = LLVMVerifyModule(module, LLVMReturnStatusAction, &error); if (error) { if (failed) fputs(error, stderr); LLVMDisposeMessage(error); }
	char path[64]; snprintf(path, sizeof path, "shared-%d.ll", variant); error = NULL; if (LLVMPrintModuleToFile(module, path, &error)) failed = 1; if (error) LLVMDisposeMessage(error);
	return !failed;
}
void shared_test_close(void) { LLVMDisposeBuilder(builder); LLVMDisposeModule(module); LLVMDisposeTargetData(layout); LLVMContextDispose(context); }
'''

CALLER = '''extern(C) void shared_test_open();
extern(C) void* shared_test_handle(int which);
extern(C) int shared_test_finish(int variant);
extern(C) void shared_test_close();
int main() {
	int variant = 0;
	while (variant <= 17) {
		shared_test_open();
		var handles = llvm12_handles();
		var runtime = new RecoverSharedRuntime(shared_test_handle(0), shared_test_handle(1), shared_test_handle(2), handles, shared_test_handle(4), shared_test_handle(5), shared_test_handle(6));
		runtime.build_helpers();
		var drop = runtime.build_release(shared_test_handle(7), true, "fixture.release");
		if (shared_test_finish(variant) != 1) return 60 + variant;
		bool valid = recover_shared_control_verified(runtime.control, shared_test_handle(3)) && recover_shared_adjust_verified(runtime.increment, runtime.trap, true) && recover_shared_adjust_verified(runtime.decrement, runtime.trap, false) && recover_shared_acquire_verified(runtime.acquire, runtime.control, runtime.allocate, runtime.trap) && recover_shared_clone_verified(runtime.clone, runtime.control, runtime.increment) && recover_shared_borrow_verified(runtime.borrow, runtime.control, runtime.trap) && recover_shared_release_verified(drop, runtime.control, runtime.decrement, shared_test_handle(7), true, runtime.free, "fixture.release");
		llvm12_handles_dispose(handles);
		shared_test_close();
		if (valid != (variant == 0)) return 10 + variant;
		variant = variant + 1;
	}
	return 42;
}
'''


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--version', required=True)
	a = p.parse_args()
	assert a.version.isalnum()
	paths = load_module('shared_runtime_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	leaf = paths.RUNTIME/('shared-runtime-'+a.version)
	build = paths.BUILD/leaf.name
	leaf.mkdir()
	build.mkdir()
	provider = leaf/'provider.c'
	provider.write_text(PROVIDER)
	caller = leaf/'caller.astra'
	caller.write_text(CALLER)
	views = []
	for relative, end in [('compiler/backend/llvm/recover-check.astra', b'bool recover_llvm_literal('), ('compiler/backend/llvm/recover-helpers-check.astra', b'bool recover_llvm_external_verified(')]:
		source = ROOT/relative
		data = source.read_bytes()
		stop = data.index(end)
		target = leaf/source.name
		target.write_bytes(data[:stop])
		views.append(dict(source=str(source), source_sha256=sha(source), end=stop, view=str(target), sha256=sha(target), classification='Unchanged complete pure LLVM helper definitions; unrelated semantic consumers omitted.'))
	(leaf/'helper-views.json').write_text(json.dumps(views, indent=2)+'\n')
	commands = []
	def run(argv, name, cwd=build, allowed=(0,)):
		argv = list(map(str, argv))
		start = time.monotonic()
		r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=cwd, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=300)
		(leaf/(name+'.stdout')).write_bytes(r.stdout)
		(leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode in allowed, (name, r.returncode, r.stderr[-5000:])
		return r
	flags = subprocess.check_output(['llvm-config', '--cflags'], text=True).split()
	library = subprocess.check_output(['llvm-config', '--link-shared', '--libs', 'core', 'analysis', 'native'], text=True).strip()
	assert library.startswith('-l') and ' ' not in library
	obj = build/'provider.o'
	run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *flags, '-c', provider, '-o', obj], 'provider-build')
	shim = build/'llvm-capi.o'
	run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *flags, '-c', ROOT/'compiler/backend/llvm/capi.c', '-o', shim], 'shim-build')
	sources = [ROOT/('compiler/backend/llvm/'+name+'.astra') for name in ('capi', 'recover-capi', 'recover-shared-capi', 'recover-shared-emit', 'recover-shared-check')]
	rows = []
	for mode in ('O0', 'O2'):
		working = build/mode
		working.mkdir()
		exe = working/'proof'
		run([C0, '-'+mode, *sources, *[row['view'] for row in views], caller, '--link-object', obj, '--link-object', shim, '--link-library', library[2:], '-o', exe], mode+'-build')
		run([exe], mode+'-execute', cwd=working, allowed=(42,))
		for ir in sorted(working.glob('shared-*.ll')):
			run(['opt', '-passes=verify', '-disable-output', ir], mode+'-verify-'+ir.stem)
		for target_mode in ('O0', 'O2'):
			target = working/('helper-'+target_mode)
			run(['clang', '-'+target_mode, working/'shared-0.ll', '-o', target], mode+'-'+target_mode+'-helper-build')
			run([target], mode+'-'+target_mode+'-helper-execute', allowed=(42,))
			memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', target], mode+'-'+target_mode+'-helper-memory', allowed=(42,))
			assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
		rows.append(dict(C0_producer_profile=mode, producer_ELF_sha256=sha(exe), physical_inputs={p.name: sha(p) for p in sorted(working.glob('shared-*.ll'))}))
	result = dict(status='INDEPENDENT_SHARED_RUNTIME_PREFLIGHT', profiles=rows, LLVM_valid_mutation_categories=17, source_sha256={str(p): sha(p) for p in sources}, helper_views=views, Astra_native_credit=0, limitation='Actual source emitter and independent consumer run under C0. Each mutated module passes independent LLVM verification before rejection. The emitted helper-only native programs test retain/release, borrowed payload identity, null clone/drop, single destruction and unsuppressed memory; these are not Astra source-to-native pipeline or original-function execution credit.')
	(leaf/'result.json').write_text(json.dumps(result, indent=2)+'\n')
	print('Shared helper preflight passed; 17 independently LLVM-valid physical categories, zero Astra target execution credit', flush=True)


if __name__ == '__main__':
	main()
