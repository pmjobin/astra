#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Isolated production floating-cast emission, physical checks and C0 oracle."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time

from run import C0_SHA256, ROOT, WORK, sha, write

KINDS = ['int', 'i8', 'u8', 'i16', 'u16', 'u32', 'i64', 'u64', 'isize', 'usize', 'f32', 'f64']
MUTATIONS = ['integer-signedness', 'unsigned-nneg', 'cast-fastmath', 'cast-metadata', 'cast-operand', 'identity-result', 'constant-substitution', 'extra-fp-operation']
BRIDGE = r'''#include <stdint.h>
#include <string.h>
float cast_from_f32(uint64_t bits) { uint32_t word = (uint32_t)bits; float value; memcpy(&value, &word, 4); return value; }
double cast_from_f64(uint64_t bits) { double value; memcpy(&value, &bits, 8); return value; }
uint64_t cast_bits_f32(float value) { uint32_t bits; memcpy(&bits, &value, 4); return bits; }
uint64_t cast_bits_f64(double value) { uint64_t bits; memcpy(&bits, &value, 8); return bits; }
'''
PROVIDER = r'''#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <llvm-c/Core.h>
#include <llvm-c/Analysis.h>
static LLVMContextRef context;
static LLVMModuleRef module;
static LLVMBuilderRef builder;
static LLVMValueRef functions[24];
static unsigned widths[] = {32,8,8,16,16,32,64,64,64,64,32,64};
void cast_test_open(void) { context = LLVMContextCreate(); module = LLVMModuleCreateWithNameInContext("floating-cast-preflight", context); builder = LLVMCreateBuilderInContext(context); }
void *cast_test_builder(void) { return builder; }
static LLVMTypeRef scalar(unsigned kind) { return kind == 11 ? LLVMFloatTypeInContext(context) : kind == 12 ? LLVMDoubleTypeInContext(context) : LLVMIntTypeInContext(context, widths[kind-1]); }
void *cast_test_type(int32_t kind) { return scalar((unsigned)kind); }
void *cast_test_begin(int32_t source, int32_t target) {
	unsigned index = ((unsigned)source-1)*2+(unsigned)target-11;
	LLVMTypeRef input = scalar((unsigned)source); char name[64]; snprintf(name, sizeof name, "cast.body.%u", index);
	LLVMValueRef function = LLVMAddFunction(module, name, LLVMFunctionType(scalar((unsigned)target), &input, 1, 0));
	functions[index] = function; LLVMSetLinkage(function, LLVMInternalLinkage); LLVMSetFunctionCallConv(function, 8);
	LLVMPositionBuilderAtEnd(builder, LLVMAppendBasicBlockInContext(context, function, "entry"));
	return LLVMGetParam(function, 0);
}
void cast_test_return(void *value) { LLVMBuildRet(builder, value); }
void *cast_test_operand(int32_t index) { return LLVMGetParam(functions[index], 0); }
void *cast_test_value(int32_t index) { return LLVMGetOperand(LLVMGetBasicBlockTerminator(LLVMGetFirstBasicBlock(functions[index])), 0); }
void *cast_test_constant(int32_t kind, int32_t sample) {
	static uint64_t words[] = {0,1,42,UINT64_MAX,UINT64_C(0x8000000000000000),UINT64_C(0x7fffffffffffffff),UINT64_C(0x1000001),UINT64_C(0xffffffffff000001)};
	static uint32_t singles[] = {0,UINT32_C(0x80000000),UINT32_C(0x3f800001),1,UINT32_C(0x7f800000),UINT32_C(0xff800000),UINT32_C(0x7fc12345),UINT32_C(0x7f812345)};
	static uint64_t doubles[] = {0,UINT64_C(0x8000000000000000),UINT64_C(0x3ff0000000000001),1,UINT64_C(0x7ff0000000000000),UINT64_C(0xfff0000000000000),UINT64_C(0x7ff8123456789abc),UINT64_C(0x7ff0123456789abc)};
	LLVMTypeRef type = scalar((unsigned)kind);
	if (kind <= 10) { unsigned width = widths[kind-1]; uint64_t mask = width == 64 ? UINT64_MAX : (UINT64_C(1) << width)-1; return LLVMConstInt(type, words[sample] & mask, 0); }
	if (kind == 11) { float value; memcpy(&value, &singles[sample], 4); return LLVMConstReal(type, value); }
	double value; memcpy(&value, &doubles[sample], 8); return LLVMConstReal(type, value);
}
void cast_test_failure(int32_t source, int32_t target, int32_t sample, void *operand, void *value) {
	char *input = LLVMPrintValueToString(operand), *output = LLVMPrintValueToString(value);
	fprintf(stderr, "CAST_CONSTANT_REFUSAL source=%d target=%d sample=%d input=%s output=%s\n", source, target, sample, input, output);
	LLVMDisposeMessage(input); LLVMDisposeMessage(output);
}
static void replace_value(unsigned index, LLVMValueRef value) { LLVMSetOperand(LLVMGetBasicBlockTerminator(LLVMGetFirstBasicBlock(functions[index])), 0, value); }
static void wrappers(void) {
	LLVMTypeRef word = LLVMInt64TypeInContext(context);
	for (unsigned index = 0; index < 24; index++) {
		unsigned source = index/2+1, target = index%2+11; char name[64]; snprintf(name, sizeof name, "candidate_%u", index);
		LLVMValueRef f = LLVMAddFunction(module, name, LLVMFunctionType(word, &word, 1, 0));
		LLVMPositionBuilderAtEnd(builder, LLVMAppendBasicBlockInContext(context, f, "entry"));
		LLVMValueRef input = LLVMGetParam(f, 0);
		if (widths[source-1] < 64) input = LLVMBuildTrunc(builder, input, LLVMIntTypeInContext(context, widths[source-1]), "");
		if (source >= 11) input = LLVMBuildBitCast(builder, input, scalar(source), "");
		LLVMValueRef result = LLVMBuildCall2(builder, LLVMGlobalGetValueType(functions[index]), functions[index], &input, 1, ""); LLVMSetInstructionCallConv(result, 8);
		result = LLVMBuildBitCast(builder, result, LLVMIntTypeInContext(context, widths[target-1]), "");
		if (target == 11) result = LLVMBuildZExt(builder, result, word, "");
		LLVMBuildRet(builder, result);
	}
}
int32_t cast_test_finish(int32_t variant) {
	LLVMValueRef integer = cast_test_value(15), narrow = cast_test_value(22), extend = cast_test_value(21);
	if (variant == 1) { LLVMPositionBuilderBefore(builder, integer); LLVMValueRef value = LLVMBuildSIToFP(builder, LLVMGetOperand(integer, 0), LLVMTypeOf(integer), ""); LLVMReplaceAllUsesWith(integer, value); LLVMInstructionEraseFromParent(integer); }
	if (variant == 2) LLVMSetNNeg(integer, 1);
	if (variant == 3) LLVMSetFastMathFlags(narrow, LLVMFastMathAll);
	if (variant == 4) { LLVMMetadataRef text = LLVMMDStringInContext2(context, "changed", 7); LLVMMetadataRef node = LLVMMDNodeInContext2(context, &text, 1); LLVMSetMetadata(narrow, LLVMGetMDKindIDInContext(context, "proof", 5), LLVMMetadataAsValue(context, node)); }
	if (variant == 5) LLVMSetOperand(narrow, 0, LLVMConstReal(scalar(12), 1.0));
	if (variant == 6) replace_value(23, LLVMConstReal(scalar(12), 0.0));
	if (variant == 7) replace_value(14, LLVMConstReal(scalar(11), 0.0));
	if (variant == 8) { LLVMPositionBuilderBefore(builder, LLVMGetBasicBlockTerminator(LLVMGetFirstBasicBlock(functions[21]))); replace_value(21, LLVMBuildFAdd(builder, extend, extend, "changed")); }
	if (variant == 0) wrappers();
	char *error = NULL; int failed = LLVMVerifyModule(module, LLVMReturnStatusAction, &error); if (error) { if (failed) fputs(error, stderr); LLVMDisposeMessage(error); }
	char path[64]; snprintf(path, sizeof path, "cast-%d.ll", variant); error = NULL; if (LLVMPrintModuleToFile(module, path, &error)) failed = 1; if (error) LLVMDisposeMessage(error);
	return !failed;
}
void cast_test_close(void) { LLVMDisposeBuilder(builder); LLVMDisposeModule(module); LLVMContextDispose(context); }
'''


def caller():
	lines = ['extern(C) void cast_test_open();', 'extern(C) void* cast_test_builder();', 'extern(C) void* cast_test_type(int kind);', 'extern(C) void* cast_test_begin(int source, int target);', 'extern(C) void cast_test_return(void* value);', 'extern(C) void* cast_test_operand(int index);', 'extern(C) void* cast_test_value(int index);', 'extern(C) void* cast_test_constant(int kind, int sample);', 'extern(C) void cast_test_failure(int source, int target, int sample, void* operand, void* value);', 'extern(C) int cast_test_finish(int variant);', 'extern(C) void cast_test_close();', 'int main() {', '\tint variant = 0;', f'\twhile (variant <= {len(MUTATIONS)}) {{', '\t\tcast_test_open();', '\t\tvar empty = llvm12_empty();']
	for source in range(1, 13):
		for target in (11, 12):
			index = (source-1)*2+target-11
			lines += [f'\t\tvar input{index} = cast_test_begin({source}, {target});', f'\t\tvar value{index} = recover_array_numeric_cast(cast_test_builder(), {source}, {target}, input{index}, cast_test_type({target}), empty);', f'\t\tif (!recover_array_cast_verified({source}, {target}, value{index}, input{index})) return 100;', f'\t\tcast_test_return(value{index});']
	lines += ['\t\tint source = 1;', '\t\twhile (source <= 12) {', '\t\t\tint target = 11;', '\t\t\twhile (target <= 12) {', '\t\t\t\tint sample = 0;', '\t\t\t\twhile (sample < 8) {', '\t\t\t\t\tvar operand = cast_test_constant(source, sample);', '\t\t\t\t\tvar value = recover_array_numeric_cast(cast_test_builder(), source, target, operand, cast_test_type(target), empty);', '\t\t\t\t\tif (!recover_array_cast_verified(source, target, value, operand)) {', '\t\t\t\t\t\tcast_test_failure(source, target, sample, operand, value);', '\t\t\t\t\t\treturn 101;', '\t\t\t\t\t}', '\t\t\t\t\tsample = sample + 1;', '\t\t\t\t}', '\t\t\t\ttarget = target + 1;', '\t\t\t}', '\t\t\tsource = source + 1;', '\t\t}', '\t\tif (cast_test_finish(variant) != 1) return 60 + variant;', '\t\tbool valid = true;']
	for source in range(1, 13):
		for target in (11, 12):
			index = (source-1)*2+target-11
			lines.append(f'\t\tif (!recover_array_cast_verified({source}, {target}, cast_test_value({index}), cast_test_operand({index}))) valid = false;')
	lines += ['\t\tcast_test_close();', '\t\tif (valid != (variant == 0)) return 10 + variant;', '\t\tvariant = variant + 1;', '\t}', '\treturn 42;', '}']
	return '\n'.join(lines)+'\n'


def reference():
	lines = ['extern(C) f32 cast_from_f32(u64 bits);', 'extern(C) f64 cast_from_f64(u64 bits);', 'extern(C) u64 cast_bits_f32(f32 value);', 'extern(C) u64 cast_bits_f64(f64 value);']
	for source in range(1, 13):
		for target in (11, 12):
			index = (source-1)*2+target-11
			input_value = f'bits as {KINDS[source-1]}' if source <= 10 else f'cast_from_{KINDS[source-1]}(bits)'
			converted = 'input' if source == target else f'input as {KINDS[target-1]}'
			lines += [f'export(C) u64 reference_{index}(u64 bits) {{', f'\t{KINDS[source-1]} input = {input_value};', f'\treturn cast_bits_{KINDS[target-1]}({converted});', '}']
	return '\n'.join(lines)+'\n'


def probe():
	lines = ['#include <stdint.h>', '#include <stdio.h>']
	for producer in ('candidate', 'reference'):
		for index in range(24):
			lines.append(f'extern uint64_t {producer}_{index}(uint64_t);')
		lines.append(f'static uint64_t (*{producer}[])(uint64_t) = {{'+','.join(f'{producer}_{index}' for index in range(24))+'};')
	lines.append(r'''int main(void) {
	uint64_t seed = UINT64_C(0x721894ae39203f19); unsigned long observations = 0;
	uint64_t samples[] = {0,1,42,UINT64_MAX,UINT64_C(0x8000000000000000),UINT64_C(0x7fffffffffffffff),UINT64_C(0x7ff0000000000000),UINT64_C(0xfff0000000000000),UINT64_C(0x7ff8123456789abc),UINT64_C(0x7ff0123456789abc),UINT64_C(0x80000000),UINT64_C(0x7f800000),UINT64_C(0xff800000),UINT64_C(0x7fc12345),UINT64_C(0x7f812345),UINT64_C(0x1000001)};
	for (unsigned index = 0; index < 24; index++) for (unsigned n = 0; n < 5016; n++) {
		seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17;
		uint64_t bits = n < 16 ? samples[n] : seed;
		uint64_t actual = candidate[index](bits), expected = reference[index](bits);
		if (actual != expected) { fprintf(stderr, "CAST mismatch index %u input %llx actual %llx expected %llx\n", index, (unsigned long long)bits, (unsigned long long)actual, (unsigned long long)expected); return 2; }
		observations++;
	}
	printf("CAST_DIFFERENTIAL observations=%lu casts=24\n", observations);
	return 42;
}''')
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
	leaf = a.runtime_root/('floating-cast-runtime-'+a.version)
	build = a.build_root/leaf.name
	leaf.mkdir()
	build.mkdir()
	witnesses = leaf/'source-inputs'
	witnesses.mkdir()
	def snapshot(source):
		target = witnesses/source.relative_to(ROOT)
		target.parent.mkdir(parents=True, exist_ok=True)
		target.write_bytes(source.read_bytes())
		target.chmod(0o444)
		return target
	snapshot(Path(__file__).resolve())
	for name, text in [('provider.c', PROVIDER), ('bridge.c', BRIDGE), ('caller.astra', caller()), ('reference.astra', reference()), ('probe.c', probe())]:
		(leaf/name).write_text(text)
	views = []
	for relative, start, end in [('compiler/backend/llvm/recover-array-emit.astra', None, b'class RecoverArrayRuntime'), ('compiler/backend/llvm/recover-array-instructions.astra', None, b'bool recover_array_memory('), ('compiler/semantic/types.astra', b'bool type_integer(', None)]:
		source = snapshot(ROOT/relative)
		data = source.read_bytes()
		first = data.index(start) if start else 0
		last = data.index(end) if end else len(data)
		target = leaf/source.name
		target.write_bytes(data[first:last])
		views.append(dict(source=str(source), source_sha256=sha(source), first=first, last=last, view=str(target), sha256=sha(target), classification='Byte-exact complete pure helper definitions for isolated C0 preflight.'))
	commands = []
	def run(argv, name, cwd=build, expected=0):
		argv = list(map(str, argv))
		start = time.monotonic()
		process = subprocess.Popen(['/usr/bin/time', '-v', '-o', str(leaf/(name+'.time')), *argv], cwd=cwd, env=dict(os.environ, CCACHE_DISABLE='1'), stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
		try:
			out, err = process.communicate(timeout=300)
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
		assert process.returncode == expected, (name, process.returncode, out[-1500:], err[-4000:])
		return subprocess.CompletedProcess(argv, process.returncode, out, err)
	flags = subprocess.check_output(['llvm-config', '--cflags'], text=True).split()
	library = subprocess.check_output(['llvm-config', '--link-shared', '--libs', 'core', 'analysis'], text=True).strip()
	assert library.startswith('-l') and ' ' not in library
	obj = build/'provider.o'
	run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *flags, '-c', leaf/'provider.c', '-o', obj], 'provider-build')
	shim = build/'llvm-capi.o'
	run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *flags, '-c', snapshot(ROOT/'compiler/backend/llvm/capi.c'), '-o', shim], 'shim-build')
	sources = [snapshot(ROOT/('compiler/backend/llvm/'+name+'.astra')) for name in ('capi', 'recover-capi', 'recover-shared-capi', 'recover-array-capi')]
	rows = []
	for mode in ('O0', 'O2'):
		working = build/mode
		working.mkdir()
		oracle = working/'reference.o'
		run([a.compiler, '-'+mode, '-c', leaf/'reference.astra', '-o', oracle], mode+'-reference-build')
		exe = working/'proof'
		run([a.compiler, '-'+mode, *sources, *[row['view'] for row in views], leaf/'caller.astra', '--link-object', obj, '--link-object', shim, '--link-library', library[2:], '-o', exe], mode+'-build')
		run([exe], mode+'-execute', cwd=working, expected=42)
		for physical in sorted(working.glob('cast-*.ll')):
			run(['opt', '-passes=verify', '-disable-output', physical], mode+'-verify-'+physical.stem)
		for target_mode in ('O0', 'O2'):
			target = working/('cast-'+target_mode)
			label = mode+'-'+target_mode
			run(['clang', '-'+target_mode, working/'cast-0.ll', oracle, leaf/'probe.c', leaf/'bridge.c', '-o', target], label+'-link')
			observed = run([target], label+'-execute', expected=42)
			assert b'CAST_DIFFERENTIAL observations=120384 casts=24' in observed.stdout
			memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', target], label+'-memory', expected=42)
			assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr and observed.stdout == memory.stdout
		rows.append(dict(C0_producer_profile=mode, producer_ELF_sha256=sha(exe), C0_oracle_object_sha256=sha(oracle), physical_inputs={p.name: sha(p) for p in sorted(working.glob('cast-*.ll'))}))
	write(leaf/'result.json', dict(status='INDEPENDENT_FLOATING_CAST_PREFLIGHT', profiles=rows, casts=22, carrier_identity_controls=2, constant_cases_each=192, LLVM_valid_mutation_categories=MUTATIONS, helper_views=views, source_sha256={str(p): sha(p) for p in sources}, Astra_native_credit=0, limitation='Complete helper definitions run under C0. Bitwise native differential, LLVM-valid physical mutations and unsuppressed memory evidence. Same-type floating cases compare descriptor-free identity transport. Complete Astra pipeline qualification remains pending.'))
	print('Floating cast preflight passed with 22 casts, two identity controls and eight LLVM-valid mutations', flush=True)


if __name__ == '__main__':
	main()
