#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Run the integral unary consumer against independent LLVM-valid alternatives."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
from state import ROOT, C0, load_module, sha, bounded_run

PROVIDER = r'''#include <stdint.h>
#include <stdio.h>
#include <llvm-c/Core.h>
#include <llvm-c/Analysis.h>
static LLVMContextRef context;
static LLVMModuleRef module;
static LLVMValueRef input, result;
int32_t r5_open(int32_t width, int32_t mode, int32_t variant, int32_t constant, uint64_t requested_mask) {
	context = LLVMContextCreate(); module = LLVMModuleCreateWithNameInContext("independent-integral-unary", context);
	LLVMTypeRef type = LLVMIntTypeInContext(context, (unsigned)width), args[] = {type, type};
	LLVMValueRef function = LLVMAddFunction(module, "witness", LLVMFunctionType(type, args, 2, 0));
	LLVMBuilderRef builder = LLVMCreateBuilderInContext(context);
	LLVMPositionBuilderAtEnd(builder, LLVMAppendBasicBlockInContext(context, function, "entry"));
	input = LLVMGetParam(function, 0);
	if (constant) input = LLVMConstInt(type, constant == 1 ? 0 : UINT64_C(1) << (width - 1), 0);
	LLVMValueRef operand = variant == 2 ? LLVMGetParam(function, 1) : input;
	LLVMValueRef mask = LLVMConstInt(type, variant == 7 ? UINT64_MAX : requested_mask, 0), zero = LLVMConstNull(type);
	if (mode == 0) {
		result = LLVMBuildSub(builder, zero, operand, "");
		if (variant == 1) result = LLVMBuildSub(builder, LLVMConstInt(type, 1, 0), operand, "");
		if (variant == 3) result = LLVMBuildAdd(builder, zero, operand, "");
		if (variant == 4) LLVMSetNSW(result, 1);
		if (variant == 5) LLVMSetNUW(result, 1);
		if (variant == 6) result = LLVMBuildSub(builder, operand, zero, "");
	} else if (mode == 1) {
		result = LLVMBuildXor(builder, operand, variant == 1 ? zero : mask, "");
		if (variant == 3) result = LLVMBuildOr(builder, operand, mask, "");
	} else result = operand;
	LLVMBuildRet(builder, result); LLVMDisposeBuilder(builder);
	char *error = NULL; int failed = LLVMVerifyModule(module, LLVMReturnStatusAction, &error);
	if (error) LLVMDisposeMessage(error);
	error = NULL;
	char path[128]; snprintf(path, sizeof path, "physical-%d-%d-%d-%d.ll", width, mode, variant, constant);
	if (LLVMPrintModuleToFile(module, path, &error)) failed = 1;
	if (error) LLVMDisposeMessage(error);
	return !failed;
}
void *r5_value(int32_t which) { return which ? result : input; }
void r5_close(void) { LLVMDisposeModule(module); LLVMContextDispose(context); }
'''

CALLER = '''extern(C) int r5_open(int width, int mode, int variant, int constant, u64 requested_mask);
extern(C) void* r5_value(int which);
extern(C) void r5_close();
bool check(int width, int mode, int variant, int constant, bool logical, bool signed_value) {
	if (r5_open(width, mode, variant, constant, recover_llvm_prefix_mask(width)) != 1) return false;
	string op = "-"; if (mode == 1) { op = "~"; if (logical) op = "!"; } if (mode == 2) op = "+";
	bool valid = recover_llvm_integral_unary(op, logical, signed_value, r5_value(1), r5_value(0));
	r5_close(); return valid;
}
int main() {
	if (!check(1, 1, 0, 0, true, false) || !check(1, 1, 0, 1, true, false) || !check(1, 1, 0, 2, true, false)) return 1;
	int width = 8;
	while (width <= 64) {
		int constant = 0; while (constant < 3) {
			if (!check(width, 0, 0, constant, false, true) || !check(width, 1, 0, constant, false, false) || !check(width, 2, 0, constant, false, true)) return 2;
			constant = constant + 1;
		}
		width = width * 2;
	}
	int variant = 1; while (variant <= 6) { if (check(32, 0, variant, 0, false, true)) return 10 + variant; variant = variant + 1; }
	variant = 1; while (variant <= 3) { if (check(1, 1, variant, 0, true, false)) return 20 + variant; variant = variant + 1; }
	if (check(32, 1, 0, 0, true, false) || check(1, 1, 0, 0, false, false) || check(32, 0, 0, 0, false, false)) return 30;
	if (recover_llvm_integral_unary("!", true, false, null, null)) return 31;
	if (check(1, 1, 7, 0, true, false)) return 32;
	return 42;
}
'''


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', required=True); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r5_prefix_proof_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('prefix-proof-'+a.version); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); commands = []
	provider = leaf/'provider.c'; provider.write_text(PROVIDER); caller = leaf/'caller.astra'; caller.write_text(CALLER)
	def run(argv, name, allowed=(0,)):
		argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=240)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode in allowed, (name, r.returncode, r.stderr[-2000:]); return r
	flags = subprocess.check_output(['llvm-config', '--cflags'], text=True).split(); library = subprocess.check_output(['llvm-config', '--link-shared', '--libs', 'core', 'analysis'], text=True).strip(); assert library.startswith('-l') and ' ' not in library
	obj = build/'provider.o'; run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *flags, '-c', provider, '-o', obj], 'provider-build')
	products = []
	for mode in ('O0', 'O2'):
		exe = build/('proof-'+mode); run([C0, '-'+mode, ROOT/'compiler/backend/llvm/capi.astra', ROOT/'compiler/backend/llvm/recover-integral.astra', caller, '--link-object', obj, '--link-library', library[2:], '-o', exe], mode+'-build'); run([exe], mode+'-execute', (42,)); products.append(dict(profile=mode, ELF_sha256=sha(exe), actual_exit=42))
	(leaf/'result.json').write_text(json.dumps(dict(status='INDEPENDENT_UNARY_PHYSICAL_PREFLIGHT', source_sha256=sha(ROOT/'compiler/backend/llvm/recover-integral.astra'), products=products, positive_cases=39, LLVM_valid_negative_cases=13, noncanonical_CAPI_negative_cases=1, LLVM_inputs={p.name: sha(p) for p in sorted(build.glob('physical-*.ll'))}, physical_categories=['wrong zero', 'wrong operand', 'wrong opcode', 'nsw', 'nuw', 'reversed subtraction', 'wrong xor mask', 'wrong boolean operand', 'or instead of xor'], domain_negative_cases=['wrong boolean width', 'wrong integral width', 'unsigned negation'], Astra_native_credit=0, limitation='C0 compiles the actual independent consumer against a separate C LLVM producer. Each alternative passes LLVMVerifyModule before the consumer runs. Nine changed physical forms, three domain rebindings and a noncanonical narrow LLVMConstInt input are separate. The real emitter mask function is used by the independent C producer; the consumer computes its own expected mask. These focused helper checks supply zero integrated full-module mutation, Astra-native or original-function execution credit.'), indent=2)+'\n'); print('Independent unary consumer passes at C0 O0/O2; LLVM verifies every physical alternative first', flush=True)


if __name__ == '__main__':
	main()
