#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual guarded integer helpers, LLVM-valid mutations and original C0 oracle."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
from state import ROOT, C0, load_module, bounded_run, sha

KINDS = [('int', 'u32'), ('i8', 'u8'), ('u8', 'u8'), ('i16', 'u16'), ('u16', 'u16'), ('u32', 'u32'), ('i64', 'u64'), ('u64', 'u64'), ('isize', 'usize'), ('usize', 'usize')]

PROVIDER = r'''#include <stdint.h>
#include <stdio.h>
#include <llvm-c/Core.h>
#include <llvm-c/Analysis.h>
static LLVMContextRef context;
static LLVMModuleRef module;
static LLVMBuilderRef builder;
static LLVMValueRef trap;
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
void integer_test_open(void) {
	context = LLVMContextCreate(); module = LLVMModuleCreateWithNameInContext("independent-integer-preflight", context); builder = LLVMCreateBuilderInContext(context);
	trap = LLVMAddFunction(module, "llvm.trap", LLVMFunctionType(LLVMVoidTypeInContext(context), NULL, 0, 0));
}
void *integer_test_handle(int32_t which) { return which == 0 ? (void *)context : which == 1 ? (void *)module : which == 2 ? (void *)builder : (void *)trap; }
static LLVMValueRef helper(unsigned kind, unsigned rem) {
	char name[64]; snprintf(name, sizeof name, "fixture.integer.%u.%s", kind, rem ? "rem" : "div"); return LLVMGetNamedFunction(module, name);
}
static void wrappers(void) {
	LLVMTypeRef word = LLVMInt64TypeInContext(context), args[] = {word, word};
	for (unsigned kind = 1; kind <= 10; kind++) for (unsigned rem = 0; rem < 2; rem++) {
		char name[64]; snprintf(name, sizeof name, "candidate_%u_%s", kind, rem ? "rem" : "div");
		LLVMValueRef f = helper(kind, rem), wrapper = LLVMAddFunction(module, name, LLVMFunctionType(word, args, 2, 0));
		LLVMPositionBuilderAtEnd(builder, LLVMAppendBasicBlockInContext(context, wrapper, "entry"));
		LLVMTypeRef actual = LLVMTypeOf(LLVMGetParam(f, 0));
		LLVMValueRef values[] = {LLVMGetParam(wrapper, 0), LLVMGetParam(wrapper, 1)};
		if (actual != word) for (unsigned p = 0; p < 2; p++) values[p] = LLVMBuildTrunc(builder, values[p], actual, "");
		LLVMValueRef result = LLVMBuildCall2(builder, LLVMGlobalGetValueType(f), f, values, 2, ""); LLVMSetInstructionCallConv(result, 8);
		if (actual != word) result = LLVMBuildZExt(builder, result, word, "");
		LLVMBuildRet(builder, result);
	}
}
int32_t integer_test_finish(int32_t variant) {
	LLVMValueRef f = helper(1, 0), normal = instruction(f, 4, 0);
	LLVMTypeRef type = LLVMInt32TypeInContext(context);
	if (variant == 1) { LLVMValueRef old = instruction(f, 0, 0); LLVMPositionBuilderBefore(builder, old); LLVMValueRef value = LLVMBuildICmp(builder, LLVMIntNE, LLVMGetOperand(old, 0), LLVMGetOperand(old, 1), ""); LLVMReplaceAllUsesWith(old, value); LLVMInstructionEraseFromParent(old); }
	if (variant == 2) LLVMSetCondition(instruction(f, 0, 1), LLVMConstInt(LLVMInt1TypeInContext(context), 0, 0));
	if (variant == 3) LLVMSetOperand(instruction(f, 2, 0), 1, LLVMConstInt(type, 0, 0));
	if (variant == 4) LLVMSetOperand(instruction(f, 2, 1), 1, LLVMConstInt(type, 1, 0));
	if (variant == 5) { LLVMValueRef old = instruction(f, 2, 2); LLVMPositionBuilderBefore(builder, old); LLVMValueRef value = LLVMBuildOr(builder, LLVMGetOperand(old, 0), LLVMGetOperand(old, 1), ""); LLVMReplaceAllUsesWith(old, value); LLVMInstructionEraseFromParent(old); }
	if (variant == 6) LLVMSetOperand(instruction(f, 3, 0), 0, LLVMConstInt(type, 0, 0));
	if (variant == 7) { LLVMPositionBuilderBefore(builder, normal); LLVMValueRef value = LLVMBuildUDiv(builder, LLVMGetOperand(normal, 0), LLVMGetOperand(normal, 1), ""); LLVMReplaceAllUsesWith(normal, value); LLVMInstructionEraseFromParent(normal); }
	if (variant == 8) LLVMSetExact(normal, 1);
	if (variant == 9) { LLVMValueRef first = LLVMGetOperand(normal, 0); LLVMSetOperand(normal, 0, LLVMGetOperand(normal, 1)); LLVMSetOperand(normal, 1, first); }
	if (variant == 10) LLVMSetICmpSameSign(instruction(f, 2, 0), 1);
	if (variant == 11) LLVMSetOperand(instruction(f, 4, 1), 0, LLVMGetParam(f, 0));
	if (variant == 12) { unsigned kind = LLVMGetEnumAttributeKindForName("memory", 6); LLVMAddAttributeAtIndex(f, LLVMAttributeFunctionIndex, LLVMCreateEnumAttribute(context, kind, 0)); }
	if (variant == 0) wrappers();
	char *error = NULL; int failed = LLVMVerifyModule(module, LLVMReturnStatusAction, &error); if (error) { if (failed) fputs(error, stderr); LLVMDisposeMessage(error); }
	char path[64]; snprintf(path, sizeof path, "integer-%d.ll", variant); error = NULL; if (LLVMPrintModuleToFile(module, path, &error)) failed = 1; if (error) LLVMDisposeMessage(error);
	return !failed;
}
void integer_test_close(void) { LLVMDisposeBuilder(builder); LLVMDisposeModule(module); LLVMContextDispose(context); }
'''


def caller():
	lines = ['extern(C) void integer_test_open();', 'extern(C) void* integer_test_handle(int which);', 'extern(C) int integer_test_finish(int variant);', 'extern(C) void integer_test_close();', 'int main() {', '\tint variant = 0;', '\twhile (variant <= 12) {', '\t\tinteger_test_open();', '\t\tvar handles = llvm12_handles();', '\t\tvar runtime = new RecoverIntegerRuntime(integer_test_handle(0), integer_test_handle(1), integer_test_handle(2), handles, integer_test_handle(3));']
	for kind in range(1, 11):
		for rem in (False, True):
			op = 'rem' if rem else 'div'
			lines.append(f'\t\tvar h{kind}{op} = runtime.build_helper({kind}, {str(rem).lower()}, "fixture.integer.{kind}.{op}");')
	lines += ['\t\tif (integer_test_finish(variant) != 1) return 60 + variant;', '\t\tbool valid = true;']
	for kind in range(1, 11):
		for rem in (False, True):
			op = 'rem' if rem else 'div'
			lines.append(f'\t\tif (!recover_integer_helper_verified(h{kind}{op}, {kind}, {str(rem).lower()}, "fixture.integer.{kind}.{op}", integer_test_handle(3))) valid = false;')
	lines += ['\t\tllvm12_handles_dispose(handles);', '\t\tinteger_test_close();', '\t\tif (valid != (variant == 0)) return 10 + variant;', '\t\tvariant = variant + 1;', '\t}', '\treturn 42;', '}']
	return '\n'.join(lines)+'\n'


def reference():
	lines = []
	for kind, (signed, unsigned) in enumerate(KINDS, 1):
		for op, token in [('div', '/'), ('rem', '%')]:
			lines += [f'export(C) u64 reference_{kind}_{op}(u64 a, u64 b) {{', f'\t{signed} left = a as {signed};', f'\t{signed} right = b as {signed};', f'\treturn ((left {token} right) as {unsigned}) as u64;', '}']
	return '\n'.join(lines)+'\n'


def probe():
	lines = ['#include <stdint.h>', '#include <stdio.h>', '#include <string.h>']
	for kind in range(1, 11):
		for op in ('div', 'rem'):
			lines += [f'extern uint64_t candidate_{kind}_{op}(uint64_t, uint64_t);', f'extern uint64_t reference_{kind}_{op}(uint64_t, uint64_t);']
	lines += ['typedef uint64_t (*operation)(uint64_t, uint64_t);', 'static operation candidate[] = {'+','.join(f'candidate_{k}_{o}' for k in range(1, 11) for o in ('div', 'rem'))+'};', 'static operation reference[] = {'+','.join(f'reference_{k}_{o}' for k in range(1, 11) for o in ('div', 'rem'))+'};', r'''static unsigned long observations;
static int same(unsigned k, uint64_t a, uint64_t b) {
	for (unsigned rem = 0; rem < 2; rem++) {
		uint64_t x = candidate[k * 2 + rem](a, b), y = reference[k * 2 + rem](a, b);
		observations++;
		if (x != y) { fprintf(stderr, "INTEGER mismatch kind %u rem %u a %llx b %llx\n", k + 1, rem, (unsigned long long)a, (unsigned long long)b); return 0; }
	}
	return 1;
}
int main(int argc, char **argv) {
	if (argc > 1) { operation f = strcmp(argv[1], "candidate-zero") == 0 ? candidate[0] : reference[0]; volatile uint64_t result = f(42, 0); return (int)result; }
	unsigned widths[] = {32, 8, 8, 16, 16, 32, 64, 64, 64, 64};
	uint64_t seed = 0x728344998abcde01ULL;
	for (unsigned k = 0; k < 10; k++) {
		unsigned width = widths[k]; uint64_t mask = width == 64 ? UINT64_MAX : (1ULL << width) - 1, sign = 1ULL << (width - 1);
		uint64_t values[] = {0, 1, 2, 3, 10, 42, mask, mask - 1, sign, sign - 1, sign + 1};
		for (unsigned a = 0; a < sizeof values / sizeof *values; a++) for (unsigned b = 1; b < sizeof values / sizeof *values; b++) if (!same(k, values[a], values[b])) return 2;
		if (width == 8) { for (unsigned a = 0; a < 256; a++) for (unsigned b = 1; b < 256; b++) if (!same(k, a, b)) return 3; }
		else for (unsigned n = 0; n < 16000; n++) { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; uint64_t a = seed & mask; seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; uint64_t b = seed & mask; if (b && !same(k, a, b)) return 4; }
	}
	printf("INTEGER_C0_DIFFERENTIAL %lu\n", observations);
	return 42;
}''']
	return '\n'.join(lines)+'\n'


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--version', required=True)
	a = p.parse_args()
	assert a.version.isalnum()
	paths = load_module('integer_runtime_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	leaf = paths.RUNTIME/('integer-runtime-'+a.version)
	build = paths.BUILD/leaf.name
	leaf.mkdir()
	build.mkdir()
	for name, text in [('provider.c', PROVIDER), ('caller.astra', caller()), ('reference.astra', reference()), ('probe.c', probe())]:
		(leaf/name).write_text(text)
	views = []
	for relative, start, end in [('compiler/backend/llvm/recover-check.astra', None, b'bool recover_llvm_literal('), ('compiler/backend/llvm/recover-helpers-check.astra', None, b'bool recover_llvm_external_verified('), ('compiler/backend/llvm/recover-instructions.astra', b'bool recover_llvm_native_attributes(', b'int recover_llvm_extract_instructions('), ('compiler/semantic/types.astra', b'bool type_integer(', None)]:
		source = ROOT/relative
		data = source.read_bytes()
		first = data.index(start) if start else 0
		last = data.index(end) if end else len(data)
		target = leaf/source.name
		target.write_bytes(data[first:last])
		views.append(dict(source=str(source), source_sha256=sha(source), first=first, last=last, view=str(target), sha256=sha(target), classification='Unchanged complete pure helper definitions; unrelated consumers omitted.'))
	commands = []
	def run(argv, name, cwd=build, allowed=(0,)):
		argv = list(map(str, argv))
		start = time.monotonic()
		r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=cwd, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=300)
		(leaf/(name+'.stdout')).write_bytes(r.stdout)
		(leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode in allowed, (name, r.returncode, r.stdout[-2000:], r.stderr.splitlines()[:3])
		return r
	flags = subprocess.check_output(['llvm-config', '--cflags'], text=True).split()
	library = subprocess.check_output(['llvm-config', '--link-shared', '--libs', 'core', 'analysis'], text=True).strip()
	assert library.startswith('-l') and ' ' not in library
	obj = build/'provider.o'
	run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *flags, '-c', leaf/'provider.c', '-o', obj], 'provider-build')
	shim = build/'llvm-capi.o'
	run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *flags, '-c', ROOT/'compiler/backend/llvm/capi.c', '-o', shim], 'shim-build')
	sources = [ROOT/('compiler/backend/llvm/'+name+'.astra') for name in ('capi', 'recover-capi', 'recover-shared-capi', 'recover-integer-emit', 'recover-integer-check')]
	rows = []
	for mode in ('O0', 'O2'):
		working = build/mode
		working.mkdir()
		oracle = working/'reference.o'
		run([C0, '-'+mode, '-c', leaf/'reference.astra', '-o', oracle], mode+'-reference-build')
		exe = working/'proof'
		run([C0, '-'+mode, *sources, *[row['view'] for row in views], leaf/'caller.astra', '--link-object', obj, '--link-object', shim, '--link-library', library[2:], '-o', exe], mode+'-build')
		run([exe], mode+'-execute', cwd=working, allowed=(42,))
		for physical in sorted(working.glob('integer-*.ll')):
			run(['opt', '-passes=verify', '-disable-output', physical], mode+'-verify-'+physical.stem)
		for target_mode in ('O0', 'O2'):
			target = working/('helper-'+target_mode)
			run(['clang', '-'+target_mode, working/'integer-0.ll', oracle, leaf/'probe.c', '-o', target], mode+'-'+target_mode+'-helper-build')
			observed = run([target], mode+'-'+target_mode+'-helper-execute', allowed=(42,))
			memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', target], mode+'-'+target_mode+'-helper-memory', allowed=(42,))
			assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr and observed.stdout == memory.stdout
			fatal = [run([target, who+'-zero'], mode+'-'+target_mode+'-'+who+'-zero', allowed=(132, -4)).returncode for who in ('candidate', 'reference')]
			assert fatal[0] == fatal[1]
		rows.append(dict(C0_producer_profile=mode, producer_ELF_sha256=sha(exe), C0_oracle_object_sha256=sha(oracle), physical_inputs={p.name: sha(p) for p in sorted(working.glob('integer-*.ll'))}))
	(leaf/'result.json').write_text(json.dumps(dict(status='INDEPENDENT_INTEGER_RUNTIME_PREFLIGHT', profiles=rows, LLVM_valid_mutation_categories=12, source_sha256={str(p): sha(p) for p in sources}, helper_views=views, Astra_native_credit=0, limitation='Actual source helper emitter and independent LLVM consumer under C0. Every mutation is independently LLVM-valid. Helper-only native differential against original C0 integer operations, all 8-bit pairs, boundary/random wider pairs, signed MIN/-1, fatal zero divisors and returning unsuppressed Valgrind. Zero Astra pipeline/original-function execution credit.'), indent=2)+'\n')
	print('Guarded integer helper preflight passed; 12 LLVM-valid mutation categories, zero Astra pipeline execution credit', flush=True)


if __name__ == '__main__':
	main()
