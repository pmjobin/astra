#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Run the unchanged declaration verifier against independently built LLVM objects."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
from state import ROOT, C0, load_module, sha, bounded_run

PROVIDER = r'''#include <stdint.h>
#include <llvm-c/Core.h>
static LLVMContextRef context;
static LLVMModuleRef module, alternatives;
static LLVMValueRef functions[8];
void r4_external_setup(void) {
	context = LLVMContextCreate(); module = LLVMModuleCreateWithNameInContext("independent-r4-declarations", context);
	alternatives = LLVMModuleCreateWithNameInContext("independent-r4-alternatives", context);
	LLVMTypeRef pointer = LLVMPointerTypeInContext(context, 0), wide = LLVMInt64TypeInContext(context), number = LLVMInt32TypeInContext(context), empty = LLVMVoidTypeInContext(context);
	LLVMTypeRef allocation[] = {wide, wide}, single[] = {pointer}, bytes[] = {pointer, pointer, wide};
	functions[0] = LLVMAddFunction(module, "calloc", LLVMFunctionType(pointer, allocation, 2, 0));
	functions[1] = LLVMAddFunction(module, "free", LLVMFunctionType(empty, single, 1, 0));
	functions[2] = LLVMAddFunction(module, "memcpy", LLVMFunctionType(pointer, bytes, 3, 0));
	functions[3] = LLVMAddFunction(module, "memcmp", LLVMFunctionType(number, bytes, 3, 0));
	functions[4] = LLVMAddFunction(module, "llvm.trap", LLVMFunctionType(empty, 0, 0, 0));
	functions[5] = LLVMAddFunction(alternatives, "memcmp", LLVMFunctionType(wide, bytes, 3, 0));
	functions[6] = LLVMAddFunction(alternatives, "wrong_name", LLVMFunctionType(number, bytes, 3, 0));
	functions[7] = LLVMAddFunction(alternatives, "calloc", LLVMFunctionType(pointer, allocation, 2, 1));
}
void *r4_external_function(int32_t kind) { return kind >= 0 && kind < 8 ? functions[kind] : 0; }
void r4_external_memory_none(int32_t kind) {
	LLVMAddAttributeAtIndex(functions[kind], LLVMAttributeFunctionIndex, LLVMCreateEnumAttribute(context, LLVMGetEnumAttributeKindForName("memory", 6), 0));
}
void r4_external_return_alias(void) {
	LLVMAddAttributeAtIndex(functions[0], LLVMAttributeReturnIndex, LLVMCreateEnumAttribute(context, LLVMGetEnumAttributeKindForName("noalias", 7), 0));
}
void r4_external_close(void) { LLVMDisposeModule(alternatives); LLVMDisposeModule(module); LLVMContextDispose(context); }
'''

CALLER = '''extern(C) void r4_external_setup();
extern(C) void* r4_external_function(int kind);
extern(C) void r4_external_memory_none(int kind);
extern(C) void r4_external_return_alias();
extern(C) void r4_external_close();
int main() {
	r4_external_setup(); int kind = 0;
	while (kind < 5) { if (!recover_llvm_external_verified(r4_external_function(kind), kind)) return 10 + kind; kind = kind + 1; }
	if (recover_llvm_external_verified(r4_external_function(5), 3) || recover_llvm_external_verified(r4_external_function(6), 3) || recover_llvm_external_verified(r4_external_function(7), 0)) return 20;
	r4_external_return_alias(); if (recover_llvm_external_verified(r4_external_function(0), 0)) return 21;
	r4_external_memory_none(2); if (recover_llvm_external_verified(r4_external_function(2), 2)) return 22;
	r4_external_memory_none(4); if (recover_llvm_external_verified(r4_external_function(4), 4)) return 23;
	r4_external_close(); return 42;
}
'''


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', required=True); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r4_external_proof_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('external-proof-'+a.version); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); commands = []
	file = ROOT/'compiler/backend/llvm/recover-helpers-check.astra'; data = file.read_bytes(); first = data.index(b'bool recover_llvm_external_verified('); last = data.index(b'bool recover_llvm_message_verified(', first); selected = data[first:last]; view = leaf/'verifier.astra'; view.write_bytes(selected); caller = leaf/'caller.astra'; caller.write_text(CALLER); provider = leaf/'provider.c'; provider.write_text(PROVIDER)
	def run(argv, name, allowed=(0,)):
		argv = list(map(str, argv)); env = dict(os.environ, CCACHE_DISABLE='1'); env.pop('LD_PRELOAD', None); env.pop('VALGRIND_OPTS', None); start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=env, capture_output=True, timeout=240); (leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, seconds=time.monotonic()-start, stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode in allowed, (name, r.returncode, r.stderr[-2000:]); return r
	flags = subprocess.check_output(['llvm-config', '--cflags'], text=True).split(); library = subprocess.check_output(['llvm-config', '--link-shared', '--libs', 'core'], text=True).strip(); assert library.startswith('-l') and ' ' not in library
	objects = []
	for source, name in [(provider, 'provider'), (ROOT/'compiler/backend/llvm/capi.c', 'capi')]:
		obj = build/(name+'.o'); run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *flags, '-c', source, '-o', obj], name+'-build'); objects += ['--link-object', obj]
	products = []
	for profile in ('O0', 'O2'):
		exe = build/('proof-'+profile); run([C0, '-'+profile, ROOT/'compiler/backend/llvm/capi.astra', view, caller, *objects, '--link-library', library[2:], '-o', exe], profile+'-build'); run([exe], profile+'-execute', (42,)); products.append(dict(profile=profile, ELF_sha256=sha(exe), actual_exit=42))
	(leaf/'result.json').write_text(json.dumps(dict(status='INDEPENDENT_DECLARATION_VERIFIER_PREFLIGHT', source=str(file), source_sha256=sha(file), first_byte=first, last_byte=last, view_sha256=sha(view), byte_exact=True, products=products, positive_bindings=5, rejected_forms=['wrong name', 'wrong result width', 'variadic signature', 'return alias attribute', 'copy memory(none)', 'trap memory(none)'], Astra_native_credit=0, limitation='C0 executes the complete unchanged verifier function against independently constructed LLVM declarations. This is focused verifier evidence, not an Astra-native program or original-function execution.'), indent=2)+'\n'); print('Complete source verifier passes five bindings and rejects six forged forms at C0 O0/O2; zero Astra-native credit', flush=True)


if __name__ == '__main__':
	main()
