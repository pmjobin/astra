#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Guarded shift helper differential and physical mutation preflight under C0."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time

from run import C0_SHA256, ROOT, WORK, sha, write

KINDS = [('int', 'u32'), ('i8', 'u8'), ('u8', 'u8'), ('i16', 'u16'), ('u16', 'u16'), ('u32', 'u32'), ('i64', 'u64'), ('u64', 'u64'), ('isize', 'usize'), ('usize', 'usize')]
MUTATIONS = ['guard-predicate', 'guard-bound', 'guard-edges', 'guard-input', 'guard-condition', 'count-input', 'trunc-nuw', 'shift-exact', 'shift-signedness', 'shift-operands', 'return-value', 'calling-convention', 'function-memory', 'compare-samesign', 'zext-nneg', 'extra-instruction', 'shl-nsw', 'shl-nuw', 'trap-memory', 'count-sign-extension']

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
void shift_test_open(void) {
	context = LLVMContextCreate(); module = LLVMModuleCreateWithNameInContext("shift-runtime-preflight", context); builder = LLVMCreateBuilderInContext(context);
	trap = LLVMAddFunction(module, "llvm.trap", LLVMFunctionType(LLVMVoidTypeInContext(context), NULL, 0, 0));
}
void *shift_test_handle(int32_t which) { return which == 0 ? (void *)context : which == 1 ? (void *)module : which == 2 ? (void *)builder : (void *)trap; }
static LLVMValueRef helper(unsigned index) {
	char name[64]; snprintf(name, sizeof name, "fixture.shift.%u", index); return LLVMGetNamedFunction(module, name);
}
static void wrappers(void) {
	LLVMTypeRef word = LLVMInt64TypeInContext(context), args[] = {word, word};
	for (unsigned index = 0; index < 200; index++) {
		char name[64]; snprintf(name, sizeof name, "candidate_%u", index);
		LLVMValueRef f = helper(index), wrapper = LLVMAddFunction(module, name, LLVMFunctionType(word, args, 2, 0));
		LLVMPositionBuilderAtEnd(builder, LLVMAppendBasicBlockInContext(context, wrapper, "entry"));
		LLVMValueRef values[] = {LLVMGetParam(wrapper, 0), LLVMGetParam(wrapper, 1)};
		for (unsigned p = 0; p < 2; p++) {
			LLVMTypeRef actual = LLVMTypeOf(LLVMGetParam(f, p));
			if (actual != word) values[p] = LLVMBuildTrunc(builder, values[p], actual, "");
		}
		LLVMValueRef result = LLVMBuildCall2(builder, LLVMGlobalGetValueType(f), f, values, 2, ""); LLVMSetInstructionCallConv(result, 8);
		if (LLVMTypeOf(result) != word) result = LLVMBuildZExt(builder, result, word, "");
		LLVMBuildRet(builder, result);
	}
}
int32_t shift_test_finish(int32_t variant) {
	/* int >> i64 supplies truncation. int >> i8 supplies zero extension. */
	LLVMValueRef f = helper(13), guard = instruction(f, 0, 0), branch = instruction(f, 0, 1), count = instruction(f, 2, 0), shift = instruction(f, 2, 1);
	LLVMValueRef narrow = helper(3), extension = instruction(narrow, 2, 0), left = helper(12);
	if (variant == 1) { LLVMPositionBuilderBefore(builder, guard); LLVMValueRef value = LLVMBuildICmp(builder, LLVMIntULE, LLVMGetOperand(guard, 0), LLVMGetOperand(guard, 1), ""); LLVMReplaceAllUsesWith(guard, value); LLVMInstructionEraseFromParent(guard); }
	if (variant == 2) LLVMSetOperand(guard, 1, LLVMConstInt(LLVMTypeOf(LLVMGetParam(f, 1)), 31, 0));
	if (variant == 3) { LLVMSetSuccessor(branch, 0, block(f, 1)); LLVMSetSuccessor(branch, 1, block(f, 2)); }
	if (variant == 4) LLVMSetOperand(guard, 0, LLVMConstInt(LLVMTypeOf(LLVMGetParam(f, 1)), 0, 0));
	if (variant == 5) LLVMSetCondition(branch, LLVMConstInt(LLVMInt1TypeInContext(context), 1, 0));
	if (variant == 6) LLVMSetOperand(count, 0, LLVMConstInt(LLVMTypeOf(LLVMGetParam(f, 1)), 0, 0));
	if (variant == 7) LLVMSetNUW(count, 1);
	if (variant == 8) LLVMSetExact(shift, 1);
	if (variant == 9) { LLVMPositionBuilderBefore(builder, shift); LLVMValueRef value = LLVMBuildLShr(builder, LLVMGetOperand(shift, 0), LLVMGetOperand(shift, 1), ""); LLVMReplaceAllUsesWith(shift, value); LLVMInstructionEraseFromParent(shift); }
	if (variant == 10) { LLVMValueRef a = LLVMGetOperand(shift, 0); LLVMSetOperand(shift, 0, LLVMGetOperand(shift, 1)); LLVMSetOperand(shift, 1, a); }
	if (variant == 11) LLVMSetOperand(instruction(f, 2, 2), 0, LLVMGetParam(f, 0));
	if (variant == 12) LLVMSetFunctionCallConv(f, 0);
	if (variant == 13) { unsigned kind = LLVMGetEnumAttributeKindForName("memory", 6); LLVMAddAttributeAtIndex(f, LLVMAttributeFunctionIndex, LLVMCreateEnumAttribute(context, kind, 0)); }
	if (variant == 14) LLVMSetICmpSameSign(guard, 1);
	if (variant == 15) LLVMSetNNeg(extension, 1);
	if (variant == 16) { LLVMPositionBuilderBefore(builder, shift); (void)LLVMBuildAdd(builder, LLVMGetParam(f, 0), LLVMGetParam(f, 0), "extra"); }
	if (variant == 17) LLVMSetNSW(instruction(left, 2, 1), 1);
	if (variant == 18) LLVMSetNUW(instruction(left, 2, 1), 1);
	if (variant == 19) { unsigned kind = LLVMGetEnumAttributeKindForName("memory", 6); LLVMAddCallSiteAttribute(instruction(f, 1, 0), LLVMAttributeFunctionIndex, LLVMCreateEnumAttribute(context, kind, 0)); }
	if (variant == 20) { LLVMPositionBuilderBefore(builder, extension); LLVMValueRef value = LLVMBuildSExt(builder, LLVMGetOperand(extension, 0), LLVMTypeOf(extension), ""); LLVMReplaceAllUsesWith(extension, value); LLVMInstructionEraseFromParent(extension); }
	if (variant == 0) wrappers();
	char *error = NULL; int failed = LLVMVerifyModule(module, LLVMReturnStatusAction, &error); if (error) { if (failed) fputs(error, stderr); LLVMDisposeMessage(error); }
	char path[64]; snprintf(path, sizeof path, "shift-%d.ll", variant); error = NULL; if (LLVMPrintModuleToFile(module, path, &error)) failed = 1; if (error) LLVMDisposeMessage(error);
	return !failed;
}
void shift_test_close(void) { LLVMDisposeBuilder(builder); LLVMDisposeModule(module); LLVMContextDispose(context); }
'''


def combinations():
	for kind in range(1, 11):
		for count_kind in range(1, 11):
			for right in (False, True):
				yield ((kind-1)*10+count_kind-1)*2+int(right), kind, count_kind, right


def caller():
	lines = ['extern(C) void shift_test_open();', 'extern(C) void* shift_test_handle(int which);', 'extern(C) int shift_test_finish(int variant);', 'extern(C) void shift_test_close();', 'int main() {', '\tint variant = 0;', f'\twhile (variant <= {len(MUTATIONS)}) {{', '\t\tshift_test_open();', '\t\tvar handles = llvm12_handles();', '\t\tvar runtime = new RecoverShiftRuntime(shift_test_handle(0), shift_test_handle(1), shift_test_handle(2), handles, shift_test_handle(3));']
	for index, kind, count_kind, right in combinations():
		lines.append(f'\t\tvar h{index} = runtime.build_helper({kind}, {count_kind}, {str(right).lower()}, "fixture.shift.{index}");')
	for when in ('before', 'after'):
		if when == 'after':
			lines += ['\t\tif (shift_test_finish(variant) != 1) return 60 + variant;', '\t\tbool valid = true;']
		for index, kind, count_kind, right in combinations():
			check = f'recover_shift_helper_verified(h{index}, {kind}, {count_kind}, {str(right).lower()}, "fixture.shift.{index}", shift_test_handle(3))'
			lines.append(f'\t\tif (!{check}) '+('return 100;' if when == 'before' else 'valid = false;'))
	lines += ['\t\tllvm12_handles_dispose(handles);', '\t\tshift_test_close();', '\t\tif (valid != (variant == 0)) return 10 + variant;', '\t\tvariant = variant + 1;', '\t}', '\treturn 42;', '}']
	return '\n'.join(lines)+'\n'


def reference():
	lines = []
	for index, kind, count_kind, right in combinations():
		value_type, unsigned = KINDS[kind-1]
		count_type = KINDS[count_kind-1][0]
		lines += [f'export(C) u64 reference_{index}(u64 a, u64 b) {{', f'\t{value_type} value = a as {value_type};', f'\t{count_type} count = b as {count_type};', f'\treturn ((value {">>" if right else "<<"} count) as {unsigned}) as u64;', '}']
	return '\n'.join(lines)+'\n'


def probe():
	lines = ['#include <stdint.h>', '#include <stdio.h>', '#include <stdlib.h>', '#include <string.h>']
	for index, *_ in combinations():
		lines += [f'extern uint64_t candidate_{index}(uint64_t, uint64_t);', f'extern uint64_t reference_{index}(uint64_t, uint64_t);']
	lines += ['typedef uint64_t (*operation)(uint64_t, uint64_t);']
	for producer in ('candidate', 'reference'):
		lines.append(f'static operation {producer}[] = {{'+','.join(f'{producer}_{index}' for index, *_ in combinations())+'};')
	lines += [r'''static unsigned long observations;
static int same(unsigned index, uint64_t a, uint64_t b) {
	uint64_t x = candidate[index](a, b), y = reference[index](a, b);
	observations++;
	if (x != y) { fprintf(stderr, "SHIFT mismatch index %u a %llx b %llx actual %llx expected %llx\n", index, (unsigned long long)a, (unsigned long long)b, (unsigned long long)x, (unsigned long long)y); return 0; }
	return 1;
}
int main(int argc, char **argv) {
	if (argc == 5) { unsigned index = (unsigned)strtoul(argv[2], NULL, 10); if (index >= 200) return 90; operation f = strcmp(argv[1], "candidate") == 0 ? candidate[index] : reference[index]; volatile uint64_t result = f(strtoull(argv[3], NULL, 0), strtoull(argv[4], NULL, 0)); return (int)result; }
	unsigned widths[] = {32, 8, 8, 16, 16, 32, 64, 64, 64, 64};
	uint64_t seed = 0x728344998abcde01ULL;
	for (unsigned kind = 0; kind < 10; kind++) for (unsigned count_kind = 0; count_kind < 10; count_kind++) {
		unsigned width = widths[kind]; uint64_t mask = width == 64 ? UINT64_MAX : (1ULL << width) - 1, sign = 1ULL << (width - 1);
		uint64_t values[] = {0, 1, 2, 3, 10, 42, mask, mask - 1, sign, sign - 1, sign + 1};
		for (unsigned right = 0; right < 2; right++) {
			unsigned index = (kind * 10 + count_kind) * 2 + right;
			for (unsigned a = 0; a < sizeof values / sizeof *values; a++) for (unsigned count = 0; count < width; count++) if (!same(index, values[a], count)) return 2;
			for (unsigned n = 0; n < 500; n++) { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; uint64_t a = seed & mask; seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; if (!same(index, a, seed % width)) return 3; }
		}
	}
	printf("SHIFT_DIFFERENTIAL observations=%lu helpers=200\n", observations);
	return 42;
}''']
	return '\n'.join(lines)+'\n'


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--build-root', type=Path, required=True)
	p.add_argument('--runtime-root', type=Path, required=True)
	p.add_argument('--version', required=True)
	a = p.parse_args()
	assert a.version.isalnum() and sha(a.compiler) == C0_SHA256
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	for path, parent in ((a.build_root, WORK/'build'), (a.runtime_root, WORK/'runtime')):
		assert path.is_absolute() and path.resolve().is_relative_to(parent.resolve()) and path.is_dir()
	leaf = a.runtime_root/('shift-runtime-'+a.version)
	build = a.build_root/leaf.name
	leaf.mkdir()
	build.mkdir()
	witnesses = leaf/'source-inputs'
	witnesses.mkdir()
	def snapshot(source):
		target = witnesses/source.relative_to(ROOT)
		target.parent.mkdir(parents=True, exist_ok=True)
		if not target.exists():
			target.write_bytes(source.read_bytes())
			target.chmod(0o444)
		assert sha(target) == sha(source)
		return target
	snapshot(Path(__file__).resolve())
	for name, text in [('provider.c', PROVIDER), ('caller.astra', caller()), ('reference.astra', reference()), ('probe.c', probe())]:
		(leaf/name).write_text(text)
	views = []
	for relative, start, end in [('compiler/backend/llvm/recover-check.astra', None, b'bool recover_llvm_literal('), ('compiler/backend/llvm/recover-helpers-check.astra', None, b'bool recover_llvm_external_verified('), ('compiler/backend/llvm/recover-instructions.astra', b'bool recover_llvm_native_attributes(', b'int recover_llvm_extract_instructions('), ('compiler/semantic/types.astra', b'bool type_integer(', None), ('compiler/backend/llvm/recover-shift-check.astra', None, b'bool recover_shift_call_verified(')]:
		source = ROOT/relative
		witness = snapshot(source)
		data = witness.read_bytes()
		first = data.index(start) if start else 0
		last = data.index(end) if end else len(data)
		target = leaf/source.name
		target.write_bytes(data[first:last])
		views.append(dict(source=str(source), source_sha256=sha(witness), source_witness=str(witness), first=first, last=last, view=str(target), sha256=sha(target), classification='Complete pure helper definitions selected byte-for-byte for isolated C0 preflight.'))
	commands = []
	def run(argv, name, cwd=build, allowed=(0,)):
		argv = list(map(str, argv))
		start = time.monotonic()
		process = subprocess.Popen(['/usr/bin/time', '-v', '-o', str(leaf/(name+'.time')), *argv], cwd=cwd, env=dict(os.environ, CCACHE_DISABLE='1'), stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
		try:
			out, err = process.communicate(timeout=600)
		except subprocess.TimeoutExpired:
			os.killpg(process.pid, signal.SIGKILL)
			out, err = process.communicate()
			(leaf/(name+'.stdout')).write_bytes(out)
			(leaf/(name+'.stderr')).write_bytes(err)
			raise
		(leaf/(name+'.stdout')).write_bytes(out)
		(leaf/(name+'.stderr')).write_bytes(err)
		commands.append(dict(name=name, argv=argv, exit=process.returncode, seconds=time.monotonic()-start, stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		write(leaf/'commands.json', commands)
		assert process.returncode in allowed, (name, process.returncode, out[-2000:], err[-4000:])
		return subprocess.CompletedProcess(argv, process.returncode, out, err)
	flags = subprocess.check_output(['llvm-config', '--cflags'], text=True).split()
	library = subprocess.check_output(['llvm-config', '--link-shared', '--libs', 'core', 'analysis'], text=True).strip()
	assert library.startswith('-l') and ' ' not in library
	obj = build/'provider.o'
	run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *flags, '-c', leaf/'provider.c', '-o', obj], 'provider-build')
	shim = build/'llvm-capi.o'
	run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *flags, '-c', snapshot(ROOT/'compiler/backend/llvm/capi.c'), '-o', shim], 'shim-build')
	sources = [snapshot(ROOT/('compiler/backend/llvm/'+name+'.astra')) for name in ('capi', 'recover-capi', 'recover-shared-capi', 'recover-array-capi', 'recover-shift-emit')]
	rows = []
	for mode in ('O0', 'O2'):
		working = build/mode
		working.mkdir()
		oracle = working/'reference.o'
		run([a.compiler, '-'+mode, '-c', leaf/'reference.astra', '-o', oracle], mode+'-reference-build')
		exe = working/'proof'
		run([a.compiler, '-'+mode, *sources, *[row['view'] for row in views], leaf/'caller.astra', '--link-object', obj, '--link-object', shim, '--link-library', library[2:], '-o', exe], mode+'-build')
		run([exe], mode+'-execute', cwd=working, allowed=(42,))
		for physical in sorted(working.glob('shift-*.ll')):
			run(['opt', '-passes=verify', '-disable-output', physical], mode+'-verify-'+physical.stem)
		for target_mode in ('O0', 'O2'):
			target = working/('helper-'+target_mode)
			label = mode+'-'+target_mode
			run(['clang', '-'+target_mode, working/'shift-0.ll', oracle, leaf/'probe.c', '-o', target], label+'-helper-build')
			observed = run([target], label+'-helper-execute', allowed=(42,))
			assert b'SHIFT_DIFFERENTIAL observations=' in observed.stdout
			memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', target], label+'-helper-memory', allowed=(42,))
			assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr and observed.stdout == memory.stdout
			# Both directions, every physical count kind, out-of-range positive and
			# negative bit patterns. Children execute actual guarded operations.
			for count_kind in range(10):
				for right in (0, 1):
					for bad_count in ('32', '18446744073709551615'):
						index = count_kind*2+right
						fatal = [run([target, who, index, 42, bad_count], label+f'-fatal-{index}-{bad_count}-{who}', allowed=(132, -4)).returncode for who in ('candidate', 'reference')]
						assert fatal[0] == fatal[1]
		rows.append(dict(C0_producer_profile=mode, producer_ELF_sha256=sha(exe), C0_oracle_object_sha256=sha(oracle), physical_inputs={p.name: sha(p) for p in sorted(working.glob('shift-*.ll'))}))
	write(leaf/'result.json', dict(status='INDEPENDENT_SHIFT_RUNTIME_PREFLIGHT', profiles=rows, helpers=200, LLVM_valid_mutation_categories=MUTATIONS, source_sha256={str(p): sha(p) for p in sources}, helper_views=views, Astra_native_credit=0, limitation='C0 executes complete helper emitters and independent physical consumers. Isolated helper differential and unsuppressed memory evidence. Whole original source and Astra pipeline qualification remain pending.'))
	print('Guarded shift helper preflight passed with 200 helpers and 20 LLVM-valid mutation categories', flush=True)


if __name__ == '__main__':
	main()
