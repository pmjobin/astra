#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Counted UTF8 helper: actual emitter/consumer, LLVM-valid faults and C0 oracle."""
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
#include <llvm-c/IRReader.h>
static LLVMContextRef context;
static LLVMModuleRef module;
static LLVMBuilderRef builder;
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
static void predicate(LLVMValueRef f, unsigned b, unsigned n, LLVMIntPredicate condition) {
	LLVMValueRef old = instruction(f, b, n);
	LLVMPositionBuilderBefore(builder, old);
	LLVMValueRef replacement = LLVMBuildICmp(builder, condition, LLVMGetOperand(old, 0), LLVMGetOperand(old, 1), "");
	LLVMReplaceAllUsesWith(old, replacement);
	LLVMInstructionEraseFromParent(old);
}
static void wrap(LLVMValueRef f, const char *name) {
	LLVMValueRef wrapper = LLVMAddFunction(module, name, LLVMGlobalGetValueType(f));
	LLVMPositionBuilderAtEnd(builder, LLVMAppendBasicBlockInContext(context, wrapper, "entry"));
	LLVMValueRef args[] = {LLVMGetParam(wrapper, 0), LLVMGetParam(wrapper, 1)};
	LLVMValueRef result = LLVMBuildCall2(builder, LLVMGlobalGetValueType(f), f, args, 2, "");
	LLVMSetInstructionCallConv(result, LLVMGetFunctionCallConv(f));
	LLVMBuildRet(builder, result);
}
void utf8_test_open(void) {
	context = LLVMContextCreate();
	module = LLVMModuleCreateWithNameInContext("independent-utf8-preflight", context);
	builder = LLVMCreateBuilderInContext(context);
}
void *utf8_test_handle(int32_t which) {
	return which == 0 ? (void *)context : which == 1 ? (void *)module : (void *)builder;
}
int32_t utf8_test_finish(int32_t variant) {
	LLVMValueRef f = LLVMGetNamedFunction(module, "astra.e25a.utf8.validate");
	LLVMTypeRef i32 = LLVMInt32TypeInContext(context), i8 = LLVMInt8TypeInContext(context);
	if (variant == 1) predicate(f, 0, 0, LLVMIntUGT);
	if (variant == 2) LLVMSetCondition(instruction(f, 1, 1), LLVMConstInt(LLVMInt1TypeInContext(context), 1, 0));
	if (variant == 3) LLVMSetCondition(instruction(f, 2, 1), LLVMConstInt(LLVMInt1TypeInContext(context), 1, 0));
	if (variant == 4) LLVMSetOperand(instruction(f, 3, 0), 0, LLVMConstInt(i32, 1, 0));
	if (variant == 5) LLVMSetOperand(instruction(f, 4, 2), 1, LLVMConstInt(i8, 129, 0));
	if (variant == 6) LLVMSetOperand(instruction(f, 8, 0), 1, LLVMConstInt(i8, 192, 0));
	if (variant == 7) LLVMSetOperand(instruction(f, 16, 1), 1, LLVMConstInt(i8, 245, 0));
	if (variant == 8) LLVMSetOperand(instruction(f, 17, 1), 1, LLVMConstInt(i32, 3, 0));
	if (variant == 9) LLVMSetOperand(instruction(f, 10, 4), 1, LLVMConstInt(i8, 192, 0));
	if (variant == 10) LLVMSetOperand(instruction(f, 14, 7), 1, LLVMConstInt(i8, 159, 0));
	if (variant == 11) LLVMSetOperand(instruction(f, 14, 11), 1, LLVMConstInt(i8, 160, 0));
	if (variant == 12) LLVMSetOperand(instruction(f, 18, 7), 1, LLVMConstInt(i8, 143, 0));
	if (variant == 13) LLVMSetOperand(instruction(f, 18, 11), 1, LLVMConstInt(i8, 144, 0));
	if (variant == 14) LLVMSetOperand(instruction(f, 19, 0), 1, LLVMConstInt(i32, 3, 0));
	if (variant == 15) LLVMSetOperand(instruction(f, 7, 0), 0, LLVMConstInt(LLVMInt1TypeInContext(context), 1, 0));
	if (variant == 16) LLVMSetOperand(instruction(f, 4, 0), 0, LLVMConstNull(LLVMPointerTypeInContext(context, 0)));
	if (variant == 17) LLVMSetICmpSameSign(instruction(f, 4, 2), 1);
	if (variant == 18) {
		LLVMMetadataRef range[] = {LLVMValueAsMetadata(LLVMConstInt(i8, 1, 0)), LLVMValueAsMetadata(LLVMConstInt(i8, 127, 0))};
		LLVMSetMetadata(instruction(f, 4, 1), LLVMGetMDKindIDInContext(context, "range", 5), LLVMMetadataAsValue(context, LLVMMDNodeInContext2(context, range, 2)));
	}
	if (variant == 0) wrap(f, "candidate_validate");
	char *error = NULL;
	int failed = LLVMVerifyModule(module, LLVMReturnStatusAction, &error);
	if (error) { if (failed) fputs(error, stderr); LLVMDisposeMessage(error); }
	char path[64]; snprintf(path, sizeof path, "utf8-%d.ll", variant);
	error = NULL;
	if (LLVMPrintModuleToFile(module, path, &error)) failed = 1;
	if (error) LLVMDisposeMessage(error);
	return !failed;
}
int32_t utf8_test_reference(void) {
	LLVMMemoryBufferRef buffer;
	LLVMModuleRef reference;
	char *error = NULL;
	if (LLVMCreateMemoryBufferWithContentsOfFile("reference.ll", &buffer, &error)) { if (error) LLVMDisposeMessage(error); return 0; }
	if (LLVMParseIRInContext(context, buffer, &reference, &error)) { if (error) LLVMDisposeMessage(error); return 0; }
	LLVMModuleRef saved = module;
	module = reference;
	LLVMValueRef f = LLVMGetNamedFunction(module, "astra.text.validate.utf8"), main_value = LLVMGetNamedFunction(module, "main");
	if (!f) { LLVMDisposeModule(reference); module = saved; return 0; }
	if (main_value) LLVMSetValueName2(main_value, "reference_c0_main", 17);
	wrap(f, "reference_validate");
	int failed = LLVMVerifyModule(module, LLVMReturnStatusAction, &error);
	if (error) { if (failed) fputs(error, stderr); LLVMDisposeMessage(error); }
	error = NULL;
	if (LLVMPrintModuleToFile(module, "reference-wrapped.ll", &error)) failed = 1;
	if (error) LLVMDisposeMessage(error);
	LLVMDisposeModule(reference);
	module = saved;
	return !failed;
}
void utf8_test_close(void) {
	LLVMDisposeBuilder(builder);
	LLVMDisposeModule(module);
	LLVMContextDispose(context);
}
'''

CALLER = '''extern(C) void utf8_test_open();
extern(C) void* utf8_test_handle(int which);
extern(C) int utf8_test_finish(int variant);
extern(C) int utf8_test_reference();
extern(C) void utf8_test_close();
int main() {
	int variant = 0;
	while (variant <= 18) {
		utf8_test_open();
		var handles = llvm12_handles();
		var runtime = new RecoverUtf8Runtime(utf8_test_handle(0), utf8_test_handle(1), utf8_test_handle(2), handles);
		var function = runtime.build_helper();
		if (utf8_test_finish(variant) != 1) return 60 + variant;
		bool valid = recover_utf8_helper_verified(function);
		if (variant == 0 && utf8_test_reference() != 1) return 90;
		llvm12_handles_dispose(handles);
		utf8_test_close();
		if (valid != (variant == 0)) return 10 + variant;
		variant = variant + 1;
	}
	return 42;
}
'''

REFERENCE = '''int main() {
	try {
		var bytes = new u8[0];
		var text = utf8_message(bytes);
		if (text.text == "") return 42;
		return 3;
	} catch (Error caught) { return 4; }
}
'''

PROBE = r'''#define _GNU_SOURCE
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
extern bool candidate_validate(const uint8_t *, int32_t);
extern bool reference_validate(const uint8_t *, int32_t);
static unsigned long observations;
static int same(const uint8_t *p, int32_t n) {
	bool a = candidate_validate(p, n), b = reference_validate(p, n);
	observations++;
	if (a != b) { fprintf(stderr, "UTF8 mismatch length %d bytes %02x %02x %02x %02x\n", n, n > 0 ? p[0] : 0, n > 1 ? p[1] : 0, n > 2 ? p[2] : 0, n > 3 ? p[3] : 0); return 0; }
	return 1;
}
int main(void) {
	uint8_t bytes[8] = {0};
	if (candidate_validate(NULL, -1) || !candidate_validate(NULL, 0) || candidate_validate(NULL, 1)) return 2;
	if (!same(bytes, -1) || !same(bytes, 0)) return 3;
	for (unsigned a = 0; a < 256; a++) {
		bytes[0] = (uint8_t)a;
		if (!same(bytes, 1)) return 4;
		for (unsigned b = 0; b < 256; b++) { bytes[1] = (uint8_t)b; if (!same(bytes, 2)) return 5; }
	}
	for (uint32_t scalar = 0; scalar <= 0x10ffff; scalar++) {
		if (scalar >= 0xd800 && scalar <= 0xdfff) continue;
		int n;
		if (scalar < 0x80) { bytes[0] = (uint8_t)scalar; n = 1; }
		else if (scalar < 0x800) { bytes[0] = 0xc0 | (scalar >> 6); bytes[1] = 0x80 | (scalar & 63); n = 2; }
		else if (scalar < 0x10000) { bytes[0] = 0xe0 | (scalar >> 12); bytes[1] = 0x80 | ((scalar >> 6) & 63); bytes[2] = 0x80 | (scalar & 63); n = 3; }
		else { bytes[0] = 0xf0 | (scalar >> 18); bytes[1] = 0x80 | ((scalar >> 12) & 63); bytes[2] = 0x80 | ((scalar >> 6) & 63); bytes[3] = 0x80 | (scalar & 63); n = 4; }
		for (int count = 0; count <= n; count++) if (!same(bytes, count)) return 6;
	}
	long page = sysconf(_SC_PAGESIZE);
	if (page <= 0) return 7;
	uint8_t *guard = mmap(NULL, (size_t)page * 2, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	if (guard == MAP_FAILED || mprotect(guard + page, (size_t)page, PROT_NONE)) return 8;
	for (int n = 1; n <= 4; n++) {
		uint8_t *p = guard + page - n;
		for (unsigned lead = 0; lead < 256; lead++) {
			for (unsigned second = 0; second < 256; second++) {
				memset(p, 0x80, (size_t)n); p[0] = (uint8_t)lead;
				if (n > 1) p[1] = (uint8_t)second;
				if (!same(p, n)) return 9;
			}
		}
	}
	if (munmap(guard, (size_t)page * 2)) return 10;
	printf("UTF8_C0_DIFFERENTIAL %lu\n", observations);
	return 42;
}
'''


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--version', required=True)
	a = p.parse_args()
	assert a.version.isalnum()
	paths = load_module('utf8_runtime_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	leaf = paths.RUNTIME/('utf8-runtime-'+a.version)
	build = paths.BUILD/leaf.name
	leaf.mkdir()
	build.mkdir()
	for name, content in [('provider.c', PROVIDER), ('caller.astra', CALLER), ('reference.astra', REFERENCE), ('probe.c', PROBE)]:
		(leaf/name).write_text(content)
	views = []
	for relative, marker in [('compiler/backend/llvm/recover-check.astra', b'bool recover_llvm_literal('), ('compiler/backend/llvm/recover-helpers-check.astra', b'bool recover_llvm_external_verified('), ('compiler/backend/llvm/recover-shared-check.astra', b'bool recover_shared_control_verified(')]:
		source = ROOT/relative
		data = source.read_bytes()
		stop = data.index(marker)
		target = leaf/source.name
		target.write_bytes(data[:stop])
		views.append(dict(source=str(source), source_sha256=sha(source), end=stop, view=str(target), sha256=sha(target), classification='Unchanged complete pure LLVM helper definitions; unrelated semantic consumers omitted.'))
	commands = []
	def run(argv, name, cwd=build, allowed=(0,)):
		argv = list(map(str, argv))
		start = time.monotonic()
		r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=cwd, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=300)
		(leaf/(name+'.stdout')).write_bytes(r.stdout)
		(leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode in allowed, (name, r.returncode, r.stdout[-2000:], r.stderr[-5000:])
		return r
	flags = subprocess.check_output(['llvm-config', '--cflags'], text=True).split()
	library = subprocess.check_output(['llvm-config', '--link-shared', '--libs', 'core', 'analysis', 'irreader'], text=True).strip()
	assert library.startswith('-l') and ' ' not in library
	obj = build/'provider.o'
	run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *flags, '-c', leaf/'provider.c', '-o', obj], 'provider-build')
	shim = build/'llvm-capi.o'
	run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *flags, '-c', ROOT/'compiler/backend/llvm/capi.c', '-o', shim], 'shim-build')
	sources = [ROOT/('compiler/backend/llvm/'+name+'.astra') for name in ('capi', 'recover-capi', 'recover-shared-capi', 'recover-utf8-emit', 'recover-utf8-check')]
	reference_sources = [ROOT/'lib/astra/base/errors.astra', ROOT/'lib/astra/text/utf8-message.astra', leaf/'reference.astra']
	rows = []
	for mode in ('O0', 'O2'):
		working = build/mode
		working.mkdir()
		oracle = working/'reference'
		run([C0, '-'+mode, *reference_sources, '-o', oracle], mode+'-reference-build')
		run([oracle], mode+'-reference-execute', allowed=(42,))
		ir = run([C0, '-O0', '--dump-llvm', *reference_sources], mode+'-reference-IR')
		(working/'reference.ll').write_bytes(ir.stdout)
		exe = working/'proof'
		run([C0, '-'+mode, *sources, *[row['view'] for row in views], leaf/'caller.astra', '--link-object', obj, '--link-object', shim, '--link-library', library[2:], '-o', exe], mode+'-build')
		run([exe], mode+'-execute', cwd=working, allowed=(42,))
		for physical in sorted(working.glob('utf8-*.ll')):
			run(['opt', '-passes=verify', '-disable-output', physical], mode+'-verify-'+physical.stem)
		for target_mode in ('O0', 'O2'):
			target = working/('helper-'+target_mode)
			run(['clang', '-'+target_mode, working/'utf8-0.ll', working/'reference-wrapped.ll', leaf/'probe.c', '-o', target], mode+'-'+target_mode+'-helper-build')
			observed = run([target], mode+'-'+target_mode+'-helper-execute', allowed=(42,))
			memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', target], mode+'-'+target_mode+'-helper-memory', allowed=(42,))
			assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
			assert observed.stdout == memory.stdout and observed.stdout.startswith(b'UTF8_C0_DIFFERENTIAL ')
		rows.append(dict(C0_producer_profile=mode, producer_ELF_sha256=sha(exe), original_C0_oracle_sha256=sha(oracle), physical_inputs={p.name: sha(p) for p in sorted(working.glob('utf8-*.ll'))}))
	result = dict(status='INDEPENDENT_UTF8_RUNTIME_PREFLIGHT', profiles=rows, LLVM_valid_mutation_categories=18, source_sha256={str(p): sha(p) for p in sources}, reference_sources={str(p): sha(p) for p in reference_sources}, helper_views=views, Astra_native_credit=0, limitation='Actual source emitter and independent physical consumer under C0; every rejected module independently LLVM-valid. Helper-only native ELF differential against the unchanged original C0 UTF8 validator, all Unicode scalars, all one/two-byte inputs, truncated sequences and inaccessible next page. Zero Astra pipeline or original flow_number execution credit.')
	(leaf/'result.json').write_text(json.dumps(result, indent=2)+'\n')
	print('Counted UTF8 helper preflight passed; 18 independently LLVM-valid physical categories, zero Astra pipeline execution credit', flush=True)


if __name__ == '__main__':
	main()
