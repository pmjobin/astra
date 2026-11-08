#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual Error snapshot helpers against unchanged C0 constructor IR."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
from state import ROOT, C0, load_module, read, sha, bounded_run

PROVIDER = r'''#include <stdint.h>
#include <stdio.h>
#include <llvm-c/Core.h>
#include <llvm-c/Analysis.h>
#include <llvm-c/IRReader.h>
static LLVMContextRef context;
static LLVMModuleRef module;
static LLVMBuilderRef builder;
static LLVMValueRef allocator, trap, copy;
static LLVMTypeRef payload;
static LLVMValueRef instruction(LLVMValueRef f, unsigned b, unsigned n) {
	LLVMBasicBlockRef block = LLVMGetFirstBasicBlock(f);
	while (b--) block = LLVMGetNextBasicBlock(block);
	LLVMValueRef value = LLVMGetFirstInstruction(block);
	while (n--) value = LLVMGetNextInstruction(value);
	return value;
}
static LLVMValueRef checked_allocator(LLVMModuleRef target) {
	LLVMTypeRef word = LLVMInt64TypeInContext(context), args[] = {word, word};
	LLVMTypeRef signature = LLVMFunctionType(LLVMPointerTypeInContext(context, 0), args, 2, 0);
	LLVMValueRef external = LLVMAddFunction(target, "oracle_checked_allocate", signature);
	LLVMValueRef f = LLVMAddFunction(target, "fixture.checked.allocate", signature);
	LLVMSetLinkage(f, LLVMInternalLinkage); LLVMSetFunctionCallConv(f, 8);
	LLVMAddAttributeAtIndex(f, LLVMAttributeFunctionIndex, LLVMCreateEnumAttribute(context, LLVMGetEnumAttributeKindForName("noinline", 8), 0));
	LLVMPositionBuilderAtEnd(builder, LLVMAppendBasicBlockInContext(context, f, "entry"));
	LLVMValueRef values[] = {LLVMGetParam(f, 0), LLVMGetParam(f, 1)};
	LLVMValueRef value = LLVMBuildCall2(builder, signature, external, values, 2, "");
	LLVMBuildRet(builder, value);
	return f;
}
void error_test_open(void) {
	context = LLVMContextCreate(); module = LLVMModuleCreateWithNameInContext("independent-error-snapshot", context); builder = LLVMCreateBuilderInContext(context);
	LLVMTypeRef pointer = LLVMPointerTypeInContext(context, 0), word = LLVMInt64TypeInContext(context), integer = LLVMInt32TypeInContext(context);
	LLVMTypeRef fields[] = {pointer, pointer, pointer, integer}; payload = LLVMStructTypeInContext(context, fields, 4, 0);
	allocator = checked_allocator(module);
	trap = LLVMAddFunction(module, "llvm.trap", LLVMFunctionType(LLVMVoidTypeInContext(context), NULL, 0, 0));
	LLVMTypeRef args[] = {pointer, pointer, word}; copy = LLVMAddFunction(module, "memcpy", LLVMFunctionType(pointer, args, 3, 0));
}
void *error_test_handle(int32_t which) { return which == 0 ? (void *)context : which == 1 ? (void *)module : which == 2 ? (void *)builder : which == 3 ? (void *)allocator : which == 4 ? (void *)trap : which == 5 ? (void *)payload : (void *)copy; }
static void candidate_wrapper(LLVMValueRef constructor) {
	LLVMTypeRef type = LLVMGlobalGetValueType(constructor);
	LLVMValueRef f = LLVMAddFunction(module, "candidate_construct", type);
	LLVMPositionBuilderAtEnd(builder, LLVMAppendBasicBlockInContext(context, f, "entry"));
	LLVMValueRef args[] = {LLVMGetParam(f, 0), LLVMGetParam(f, 1), LLVMGetParam(f, 2)};
	LLVMValueRef value = LLVMBuildCall2(builder, type, constructor, args, 3, ""); LLVMSetInstructionCallConv(value, 8); LLVMBuildRet(builder, value);
}
static int reference_wrapper(void) {
	LLVMMemoryBufferRef buffer = NULL; char *error = NULL; LLVMModuleRef reference = NULL;
	if (LLVMCreateMemoryBufferWithContentsOfFile("reference.ll", &buffer, &error)) { if (error) LLVMDisposeMessage(error); return 0; }
	if (LLVMParseIRInContext(context, buffer, &reference, &error)) { if (error) LLVMDisposeMessage(error); return 0; }
	LLVMValueRef constructor = LLVMGetNamedFunction(reference, "astra.ctor.0");
	if (!constructor || LLVMCountParams(constructor) != 3 || LLVMGetFunctionCallConv(constructor) != 8 || LLVMGetTypeKind(LLVMGetReturnType(LLVMGlobalGetValueType(constructor))) != LLVMVoidTypeKind) return 0;
	char *before = LLVMPrintValueToString(constructor);
	LLVMValueRef main = LLVMGetNamedFunction(reference, "main"); if (main) LLVMDeleteFunction(main);
	LLVMValueRef allocate = checked_allocator(reference);
	LLVMTypeRef pointer = LLVMPointerTypeInContext(context, 0), integer = LLVMInt32TypeInContext(context), word = LLVMInt64TypeInContext(context), parameters[] = {pointer, pointer, integer};
	LLVMValueRef f = LLVMAddFunction(reference, "reference_construct", LLVMFunctionType(pointer, parameters, 3, 0));
	LLVMPositionBuilderAtEnd(builder, LLVMAppendBasicBlockInContext(context, f, "entry"));
	LLVMValueRef sizes[] = {LLVMConstInt(word, 1, 0), LLVMConstInt(word, 32, 0)};
	LLVMValueRef object = LLVMBuildCall2(builder, LLVMGlobalGetValueType(allocate), allocate, sizes, 2, ""); LLVMSetInstructionCallConv(object, 8);
	LLVMValueRef descriptor = LLVMBuildStructGEP2(builder, payload, object, 0, ""); LLVMGEPSetNoWrapFlags(descriptor, 0); LLVMBuildStore(builder, LLVMGetParam(f, 0), descriptor);
	LLVMValueRef args[] = {object, LLVMGetParam(f, 1), LLVMGetParam(f, 2)};
	LLVMValueRef call = LLVMBuildCall2(builder, LLVMGlobalGetValueType(constructor), constructor, args, 3, ""); LLVMSetInstructionCallConv(call, 8); LLVMBuildRet(builder, object);
	char *after = LLVMPrintValueToString(constructor);
	int identical = 1; for (unsigned p = 0; before[p] || after[p]; p++) if (before[p] != after[p]) { identical = 0; break; }
	LLVMDisposeMessage(before); LLVMDisposeMessage(after);
	error = NULL; int failed = LLVMVerifyModule(reference, LLVMReturnStatusAction, &error); if (error) { if (failed) fputs(error, stderr); LLVMDisposeMessage(error); }
	error = NULL; if (LLVMPrintModuleToFile(reference, "reference-wrapped.ll", &error)) failed = 1; if (error) LLVMDisposeMessage(error);
	LLVMDisposeModule(reference);
	return identical && !failed;
}
int32_t error_test_finish(int32_t variant) {
	LLVMValueRef constructor = LLVMGetNamedFunction(module, "astra.e25a.construct"), snapshot = LLVMGetNamedFunction(module, "astra.e25a.snapshot.allocate");
	LLVMTypeRef word = LLVMInt64TypeInContext(context), integer = LLVMInt32TypeInContext(context);
	if (variant == 1) LLVMSetOperand(instruction(constructor, 0, 2), 1, LLVMConstInt(word, 1, 0));
	if (variant == 2) LLVMSetOperand(instruction(snapshot, 2, 1), 0, LLVMConstInt(LLVMInt1TypeInContext(context), 0, 0));
	if (variant == 3) LLVMSetOperand(instruction(snapshot, 0, 1), 0, LLVMConstInt(LLVMInt1TypeInContext(context), 1, 0));
	if (variant == 4) LLVMSetOperand(instruction(snapshot, 4, 0), 1, LLVMConstInt(word, 2, 0));
	if (variant == 5) LLVMSetOperand(instruction(constructor, 0, 3), 0, LLVMConstInt(word, 0, 0));
	if (variant == 6) LLVMAddCallSiteAttribute(instruction(constructor, 0, 4), LLVMAttributeFunctionIndex, LLVMCreateEnumAttribute(context, LLVMGetEnumAttributeKindForName("memory", 6), 0));
	if (variant == 7) LLVMSetOperand(instruction(constructor, 0, 12), 0, LLVMConstInt(integer, 0, 0));
	if (variant == 8) LLVMSetICmpSameSign(instruction(snapshot, 0, 0), 1);
	if (variant == 9) LLVMAddAttributeAtIndex(snapshot, LLVMAttributeFunctionIndex, LLVMCreateEnumAttribute(context, LLVMGetEnumAttributeKindForName("memory", 6), 0));
	if (variant == 10) LLVMSetAlignment(instruction(constructor, 0, 12), 8);
	if (variant == 0) { candidate_wrapper(constructor); if (!reference_wrapper()) return 0; }
	char *error = NULL; int failed = LLVMVerifyModule(module, LLVMReturnStatusAction, &error); if (error) { if (failed) fputs(error, stderr); LLVMDisposeMessage(error); }
	char path[64]; snprintf(path, sizeof path, "error-snapshot-%d.ll", variant); error = NULL; if (LLVMPrintModuleToFile(module, path, &error)) failed = 1; if (error) LLVMDisposeMessage(error);
	return !failed;
}
void error_test_close(void) { LLVMDisposeBuilder(builder); LLVMDisposeModule(module); LLVMContextDispose(context); }
'''

CALLER = '''extern(C) void error_test_open();
extern(C) void* error_test_handle(int which);
extern(C) int error_test_finish(int variant);
extern(C) void error_test_close();
int main() {
	int variant = 0;
	while (variant <= 10) {
		error_test_open();
		var handles = llvm12_handles();
		var runtime = new RecoverErrorSnapshotRuntime(error_test_handle(0), error_test_handle(1), error_test_handle(2), handles, error_test_handle(3), error_test_handle(4));
		var snapshot = runtime.build_helper();
		var constructor = runtime.build_constructor(error_test_handle(5), snapshot, error_test_handle(6));
		if (!recover_error_snapshot_verified(snapshot, error_test_handle(3), error_test_handle(4)) || !recover_error_constructor_verified(constructor, error_test_handle(5), error_test_handle(3), snapshot, error_test_handle(6))) return 90 + variant;
		if (error_test_finish(variant) != 1) return 60 + variant;
		bool valid = recover_error_snapshot_verified(snapshot, error_test_handle(3), error_test_handle(4)) && recover_error_constructor_verified(constructor, error_test_handle(5), error_test_handle(3), snapshot, error_test_handle(6));
		llvm12_handles_dispose(handles);
		error_test_close();
		if (valid != (variant == 0)) return 10 + variant;
		variant = variant + 1;
	}
	return 42;
}
'''

PROBE = r'''#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef struct { void *descriptor, *origin; unsigned char *bytes; int32_t count; } header;
_Static_assert(sizeof(header) == 32, "approved Error header");
extern void *candidate_construct(void *, const void *, int32_t);
extern void *reference_construct(void *, const void *, int32_t);
extern void *__real_calloc(size_t, size_t);
static unsigned calls, fail_step;
static size_t ns[4], sizes[4], fail_bytes;
void *__wrap_calloc(size_t n, size_t size) {
	calls++; if (calls <= 4) { ns[calls - 1] = n; sizes[calls - 1] = size; }
	if (calls == fail_step || (fail_bytes && n * size == fail_bytes)) return NULL;
	return __real_calloc(n, size);
}
void *oracle_checked_allocate(uint64_t n, uint64_t size) { void *p = calloc((size_t)n, (size_t)size); if (!p) __builtin_trap(); return p; }
typedef void *(*constructor)(void *, const void *, int32_t);
static int descriptor;
static int check(constructor construct, unsigned count) {
	unsigned char input[257]; for (unsigned p = 0; p < sizeof input; p++) input[p] = (unsigned char)(p * 73 + count);
	calls = 0; header *object = construct(&descriptor, input, (int32_t)count);
	if (!object || object->descriptor != &descriptor || object->origin || object->count != (int32_t)count || calls != (count ? 2U : 1U) || ns[0] != 1 || sizes[0] != 32) return 0;
	if (count) { if (!object->bytes || object->bytes == input || ns[1] != count || sizes[1] != 1 || memcmp(object->bytes, input, count)) return 0; unsigned char first = object->bytes[0]; input[0] ^= 1; if (object->bytes[0] != first) return 0; }
	else if (object->bytes) return 0;
	free(object->bytes); free(object); return 1;
}
int main(int argc, char **argv) {
	if (argc > 1) { constructor f = strcmp(argv[1], "candidate") == 0 ? candidate_construct : reference_construct; unsigned count = (unsigned)strtoul(argv[2], NULL, 10); fail_step = (unsigned)strtoul(argv[3], NULL, 10); fail_bytes = (size_t)strtoull(argv[4], NULL, 10); return check(f, count) ? 42 : 3; }
	for (unsigned count = 0; count <= 256; count++) if (!check(candidate_construct, count) || !check(reference_construct, count)) return 2;
	puts("ERROR_SNAPSHOT_C0_BYTES_COUNTS_EMPTY_COPY 514"); return 42;
}
'''


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--version', required=True)
	a = p.parse_args()
	assert a.version.isalnum()
	paths = load_module('error_snapshot_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	leaf = paths.RUNTIME/('error-snapshot-'+a.version)
	build = paths.BUILD/leaf.name
	leaf.mkdir()
	build.mkdir()
	for name, data in [('provider.c', PROVIDER), ('caller.astra', CALLER), ('probe.c', PROBE)]:
		(leaf/name).write_text(data)
	views = []
	for relative, first, end in [('recover-check.astra', None, b'bool recover_llvm_literal('), ('recover-helpers-check.astra', None, b'bool recover_llvm_external_verified('), ('recover-shared-check.astra', None, b'bool recover_shared_control_verified('), ('recover-instructions.astra', b'bool recover_llvm_native_attributes(', b'int recover_llvm_extract_instructions(')]:
		source = ROOT/'compiler/backend/llvm'/relative
		data = source.read_bytes()
		start = data.index(first) if first else 0
		last = data.index(end)
		target = leaf/relative
		target.write_bytes(data[start:last])
		views.append(dict(source=str(source), source_sha256=sha(source), first=start, last=last, view=str(target), sha256=sha(target), classification='Unchanged complete pure helper definitions.'))
	oracle = read(paths.RUNTIME/'error-layout-oracles-source1/result.json')
	reference = next(row for row in oracle['observations'] if row['name'] == 'derived-error-computed-base' and row['mode'] == 'O0')
	assert sha(reference['LLVM_path']) == reference['LLVM_sha256'] and all(sha(row['path']) == row['sha256'] for row in reference['inputs'])
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
	library = subprocess.check_output(['llvm-config', '--link-shared', '--libs', 'core', 'analysis', 'irreader'], text=True).strip()
	assert library.startswith('-l') and ' ' not in library
	obj = build/'provider.o'
	run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *flags, '-c', leaf/'provider.c', '-o', obj], 'provider-build')
	shim = build/'llvm-capi.o'
	run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *flags, '-c', ROOT/'compiler/backend/llvm/capi.c', '-o', shim], 'shim-build')
	sources = [ROOT/('compiler/backend/llvm/'+name+'.astra') for name in ('capi', 'recover-capi', 'recover-shared-capi', 'recover-array-capi', 'recover-error-snapshot')]
	profiles = []
	for mode in ('O0', 'O2'):
		working = build/mode
		working.mkdir()
		(working/'reference.ll').write_bytes(Path(reference['LLVM_path']).read_bytes())
		exe = working/'proof'
		run([C0, '-'+mode, *sources, *[row['view'] for row in views], leaf/'caller.astra', '--link-object', obj, '--link-object', shim, '--link-library', library[2:], '-o', exe], mode+'-build')
		run([exe], mode+'-execute', cwd=working, allowed=(42,))
		for physical in sorted(working.glob('*.ll')):
			run(['opt', '-passes=verify', '-disable-output', physical], mode+'-verify-'+physical.stem)
		for target_mode in ('O0', 'O2'):
			target = working/('helper-'+target_mode)
			run(['clang', '-'+target_mode, '-fno-builtin-calloc', '-no-pie', working/'error-snapshot-0.ll', working/'reference-wrapped.ll', leaf/'probe.c', '-Wl,--wrap=calloc', '-o', target], mode+'-'+target_mode+'-helper-build')
			observed = run([target], mode+'-'+target_mode+'-helper-execute', allowed=(42,))
			memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', target], mode+'-'+target_mode+'-helper-memory', allowed=(42,))
			assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr and memory.stdout == observed.stdout
			for count, step, size, fatal in [(3, 1, 0, True), (3, 2, 0, True), (3, 0, 3, True), (3, 0, 4, False), (0, 2, 0, False)]:
				label = f'{count}-{step}-{size}'
				expected = (132, -4) if fatal else (42,)
				codes = [run([target, who, str(count), str(step), str(size)], mode+'-'+target_mode+'-'+who+'-allocation-'+label, allowed=expected).returncode for who in ('candidate', 'reference')]
				assert codes[0] == codes[1]
		profiles.append(dict(C0_producer=mode, producer_ELF_sha256=sha(exe), LLVM_inputs={p.name: sha(p) for p in sorted(working.glob('*.ll'))}))
	(leaf/'result.json').write_text(json.dumps(dict(status='INDEPENDENT_ERROR_SNAPSHOT_PREFLIGHT', profiles=profiles, original_C0_reference=reference, source_sha256={str(path): sha(path) for path in sources}, helper_views=views, LLVM_valid_mutation_categories=10, Astra_native_execution_credit=0, limitation='Actual production Error snapshot producer/constructor and independent consumers under C0 O0/O2. Ten independently LLVM-valid alternatives with positive twins. Four helper-only native profiles execute unchanged C0 constructor IR, exact byte/allocation shapes including empty text, independent copy, unsuppressed returning Valgrind and matching fatal allocation ordinal/size controls. The Error header/E25-A-v1 transport is unchanged; zero Astra source pipeline/original-function credit.'), indent=2)+'\n')
	print('Error snapshot helper preflight passed: exact C0 count/empty/size-failure behavior, 10 LLVM-valid categories; zero Astra pipeline credit', flush=True)


if __name__ == '__main__':
	main()
