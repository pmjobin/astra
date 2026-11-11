#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Original-C0 differential and physical mutations for guarded floating casts."""
import argparse
import json
import os
from pathlib import Path
import signal
import struct
import subprocess
import time

from run import C0_SHA256, ROOT, WORK, sha, write

KINDS = [('int', 'u32'), ('i8', 'u8'), ('u8', 'u8'), ('i16', 'u16'), ('u16', 'u16'), ('u32', 'u32'), ('i64', 'u64'), ('u64', 'u64'), ('isize', 'usize'), ('usize', 'usize')]
MUTATIONS = ['lower-predicate', 'lower-bound', 'upper-bound', 'unordered-nan', 'guard-input', 'guard-or', 'guard-edges', 'cast-signedness', 'cast-input', 'return-value', 'extension-input', 'compare-fastmath', 'extra-instruction', 'calling-convention', 'function-memory', 'trap-memory']

PROVIDER = r'''#include <stdint.h>
#include <stdio.h>
#include <llvm-c/Core.h>
#include <llvm-c/Analysis.h>
static LLVMContextRef context;
static LLVMModuleRef module;
static LLVMBuilderRef builder;
static LLVMValueRef trap;
static LLVMBasicBlockRef block(LLVMValueRef function, unsigned index) {
	LLVMBasicBlockRef result = LLVMGetFirstBasicBlock(function);
	while (index--) result = LLVMGetNextBasicBlock(result);
	return result;
}
static LLVMValueRef instruction(LLVMValueRef function, unsigned number, unsigned index) {
	LLVMValueRef result = LLVMGetFirstInstruction(block(function, number));
	while (index--) result = LLVMGetNextInstruction(result);
	return result;
}
void float_integer_open(void) {
	context = LLVMContextCreate();
	module = LLVMModuleCreateWithNameInContext("float-integer-preflight", context);
	builder = LLVMCreateBuilderInContext(context);
	trap = LLVMAddFunction(module, "llvm.trap", LLVMFunctionType(LLVMVoidTypeInContext(context), NULL, 0, 0));
}
void *float_integer_handle(int32_t which) {
	if (which == 0) return context;
	if (which == 1) return module;
	if (which == 2) return builder;
	return trap;
}
static LLVMValueRef helper(unsigned index) {
	char name[64];
	snprintf(name, sizeof name, "fixture.float.integer.%u", index);
	return LLVMGetNamedFunction(module, name);
}
static void wrappers(void) {
	LLVMTypeRef word = LLVMInt64TypeInContext(context);
	for (unsigned index = 0; index < 20; index++) {
		char name[64];
		snprintf(name, sizeof name, "candidate_%u", index);
		LLVMValueRef target = helper(index);
		LLVMValueRef function = LLVMAddFunction(module, name, LLVMFunctionType(word, &word, 1, 0));
		LLVMPositionBuilderAtEnd(builder, LLVMAppendBasicBlockInContext(context, function, "entry"));
		LLVMValueRef bits = LLVMGetParam(function, 0);
		if (index < 10) bits = LLVMBuildTrunc(builder, bits, LLVMInt32TypeInContext(context), "");
		LLVMValueRef input = LLVMBuildBitCast(builder, bits, LLVMTypeOf(LLVMGetParam(target, 0)), "");
		LLVMValueRef result = LLVMBuildCall2(builder, LLVMGlobalGetValueType(target), target, &input, 1, "");
		LLVMSetInstructionCallConv(result, 8);
		if (LLVMTypeOf(result) != word) result = LLVMBuildZExt(builder, result, word, "");
		LLVMBuildRet(builder, result);
	}
}
int32_t float_integer_finish(int32_t variant) {
	LLVMValueRef function = helper(10);
	LLVMValueRef above = instruction(function, 0, 0);
	LLVMValueRef below = instruction(function, 0, 1);
	LLVMValueRef accepted = instruction(function, 0, 2);
	LLVMValueRef branch = instruction(function, 0, 3);
	LLVMValueRef cast = instruction(function, 2, 0);
	if (variant == 1 || variant == 4) {
		LLVMPositionBuilderBefore(builder, above);
		LLVMRealPredicate predicate = variant == 1 ? LLVMRealOGE : LLVMRealUGT;
		LLVMValueRef changed = LLVMBuildFCmp(builder, predicate, LLVMGetOperand(above, 0), LLVMGetOperand(above, 1), "");
		LLVMReplaceAllUsesWith(above, changed);
		LLVMInstructionEraseFromParent(above);
	}
	if (variant == 2) LLVMSetOperand(above, 1, LLVMConstReal(LLVMDoubleTypeInContext(context), -2147483648.0));
	if (variant == 3) LLVMSetOperand(below, 1, LLVMConstReal(LLVMDoubleTypeInContext(context), 2147483649.0));
	if (variant == 5) LLVMSetOperand(above, 0, LLVMConstNull(LLVMDoubleTypeInContext(context)));
	if (variant == 6) {
		LLVMPositionBuilderBefore(builder, accepted);
		LLVMValueRef changed = LLVMBuildOr(builder, LLVMGetOperand(accepted, 0), LLVMGetOperand(accepted, 1), "");
		LLVMReplaceAllUsesWith(accepted, changed);
		LLVMInstructionEraseFromParent(accepted);
	}
	if (variant == 7) {
		LLVMSetSuccessor(branch, 0, block(function, 1));
		LLVMSetSuccessor(branch, 1, block(function, 2));
	}
	if (variant == 8) {
		LLVMPositionBuilderBefore(builder, cast);
		LLVMValueRef changed = LLVMBuildFPToUI(builder, LLVMGetOperand(cast, 0), LLVMTypeOf(cast), "");
		LLVMReplaceAllUsesWith(cast, changed);
		LLVMInstructionEraseFromParent(cast);
	}
	if (variant == 9) LLVMSetOperand(cast, 0, LLVMConstNull(LLVMDoubleTypeInContext(context)));
	if (variant == 10) LLVMSetOperand(instruction(function, 2, 1), 0, LLVMConstNull(LLVMTypeOf(cast)));
	if (variant == 11) LLVMSetOperand(instruction(helper(0), 0, 0), 0, LLVMConstNull(LLVMFloatTypeInContext(context)));
	if (variant == 12) LLVMSetFastMathFlags(above, LLVMFastMathNoNaNs);
	if (variant == 13) {
		LLVMPositionBuilderBefore(builder, above);
		(void)LLVMBuildFAdd(builder, LLVMGetParam(function, 0), LLVMGetParam(function, 0), "extra");
	}
	if (variant == 14) LLVMSetFunctionCallConv(function, 0);
	if (variant == 15 || variant == 16) {
		unsigned kind = LLVMGetEnumAttributeKindForName("memory", 6);
		LLVMAttributeRef attribute = LLVMCreateEnumAttribute(context, kind, 0);
		if (variant == 15) LLVMAddAttributeAtIndex(function, LLVMAttributeFunctionIndex, attribute);
		else LLVMAddCallSiteAttribute(instruction(function, 1, 0), LLVMAttributeFunctionIndex, attribute);
	}
	if (variant == 0) wrappers();
	char *error = NULL;
	int failed = LLVMVerifyModule(module, LLVMReturnStatusAction, &error);
	if (error) {
		if (failed) fputs(error, stderr);
		LLVMDisposeMessage(error);
	}
	char path[64];
	snprintf(path, sizeof path, "float-integer-%d.ll", variant);
	error = NULL;
	if (LLVMPrintModuleToFile(module, path, &error)) failed = 1;
	if (error) LLVMDisposeMessage(error);
	return !failed;
}
void float_integer_close(void) {
	LLVMDisposeBuilder(builder);
	LLVMDisposeModule(module);
	LLVMContextDispose(context);
}
'''


def combinations():
	for source in (11, 12):
		for target in range(1, 11):
			yield (source - 11) * 10 + target - 1, source, target


def caller():
	lines = ['extern(C) void float_integer_open();', 'extern(C) void* float_integer_handle(int which);', 'extern(C) int float_integer_finish(int variant);', 'extern(C) void float_integer_close();', 'int main() {', '\tint variant = 0;', f'\twhile (variant <= {len(MUTATIONS)}) {{', '\t\tfloat_integer_open();', '\t\tvar handles = llvm12_handles();', '\t\tvar runtime = new RecoverFloatIntegerRuntime(float_integer_handle(0), float_integer_handle(1), float_integer_handle(2), handles, float_integer_handle(3));']
	for index, source, target in combinations():
		lines.append(f'\t\tvar h{index} = runtime.build_helper({source}, {target}, "fixture.float.integer.{index}");')
	for phase in ('before', 'after'):
		if phase == 'after':
			lines += ['\t\tif (float_integer_finish(variant) != 1) return 60 + variant;', '\t\tbool valid = true;']
		for index, source, target in combinations():
			check = f'recover_float_integer_helper_verified(h{index}, {source}, {target}, "fixture.float.integer.{index}", float_integer_handle(3))'
			lines.append(f'\t\tif (!{check}) ' + ('return 100;' if phase == 'before' else 'valid = false;'))
	lines += ['\t\tllvm12_handles_dispose(handles);', '\t\tfloat_integer_close();', '\t\tif (valid != (variant == 0)) return 10 + variant;', '\t\tvariant = variant + 1;', '\t}', '\treturn 42;', '}']
	return '\n'.join(lines) + '\n'


def reference():
	lines = ['extern(C) f32 float_integer_from_f32(u64 bits);', 'extern(C) f64 float_integer_from_f64(u64 bits);']
	for index, source, target in combinations():
		value_type, unsigned = KINDS[target - 1]
		floating = 'f32' if source == 11 else 'f64'
		lines += [f'export(C) u64 reference_{index}(u64 bits) {{', f'\t{floating} value = float_integer_from_{floating}(bits);', f'\treturn ((value as {value_type}) as {unsigned}) as u64;', '}']
	return '\n'.join(lines) + '\n'


def probe():
	lines = ['#include <stdint.h>', '#include <stdio.h>', '#include <stdlib.h>', '#include <string.h>', '#include <math.h>']
	for index, *_ in combinations():
		lines += [f'extern uint64_t candidate_{index}(uint64_t);', f'extern uint64_t reference_{index}(uint64_t);']
	lines.append('typedef uint64_t (*operation)(uint64_t);')
	for producer in ('candidate', 'reference'):
		lines.append(f'static operation {producer}[] = {{' + ','.join(f'{producer}_{index}' for index, *_ in combinations()) + '};')
	lines.append(r'''float float_integer_from_f32(uint64_t bits) {
	uint32_t word = (uint32_t)bits;
	float value;
	memcpy(&value, &word, sizeof value);
	return value;
}
double float_integer_from_f64(uint64_t bits) {
	double value;
	memcpy(&value, &bits, sizeof value);
	return value;
}
static uint64_t bits_for(unsigned index, double value) {
	uint64_t bits = 0;
	if (index < 10) {
		float narrow = (float)value;
		uint32_t word;
		memcpy(&word, &narrow, sizeof word);
		bits = word;
	} else memcpy(&bits, &value, sizeof bits);
	return bits;
}
static int admitted(unsigned index, uint64_t bits) {
	static const unsigned widths[] = {32,8,8,16,16,32,64,64,64,64};
	static const unsigned signedness[] = {1,1,0,1,0,0,1,0,1,0};
	unsigned target = index % 10;
	long double value = index < 10 ? (long double)float_integer_from_f32(bits) : (long double)float_integer_from_f64(bits);
	long double integer = truncl(value);
	long double low = signedness[target] ? -ldexpl(1.0L, (int)widths[target] - 1) : 0.0L;
	long double high = ldexpl(1.0L, (int)widths[target] - (int)signedness[target]);
	return isfinite(value) && integer >= low && integer < high;
}
int main(int argc, char **argv) {
	if (argc == 4) {
		unsigned index = (unsigned)strtoul(argv[2], NULL, 10);
		uint64_t bits = strtoull(argv[3], NULL, 10);
		if (index >= 20) return 6;
		uint64_t result = strcmp(argv[1], "candidate") == 0 ? candidate[index](bits) : reference[index](bits);
		printf("%llu\n", (unsigned long long)result);
		return 7;
	}
	unsigned long observations = 0;
	for (unsigned index = 0; index < 20; index++) {
		uint64_t state = UINT64_C(0x1020304050607080);
		for (unsigned sample = 0; sample < 6000; sample++) {
			state ^= state << 13;
			state ^= state >> 7;
			state ^= state << 17;
			uint64_t bits = index < 10 ? state & UINT64_C(0xffffffff) : state;
			if (!admitted(index, bits)) continue;
			if (candidate[index](bits) != reference[index](bits)) return 1;
			observations++;
		}
		for (unsigned exponent = 0; exponent <= 64; exponent++) {
			double limit = ldexp(1.0, (int)exponent);
			for (unsigned side = 0; side < 2; side++) {
				double signed_limit = side ? -limit : limit;
				for (int offset = -2; offset <= 2; offset++) {
					double value = signed_limit + (double)offset * 0.5;
					uint64_t words[] = {bits_for(index, value), bits_for(index, nextafter(value, -INFINITY)), bits_for(index, nextafter(value, INFINITY))};
					if (index < 10) {
						words[1] = bits_for(index, nextafterf((float)value, -INFINITY));
						words[2] = bits_for(index, nextafterf((float)value, INFINITY));
					}
					for (unsigned word = 0; word < 3; word++) {
						if (!admitted(index, words[word])) continue;
						if (candidate[index](words[word]) != reference[index](words[word])) return 2;
						observations++;
					}
				}
			}
		}
		if (candidate[index](bits_for(index, -0.0)) != reference[index](bits_for(index, -0.0))) return 3;
		observations++;
	}
	printf("FLOAT_INTEGER_DIFFERENTIAL observations=%lu helpers=20\n", observations);
	return 42;
}''')
	return '\n'.join(lines) + '\n'

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
	leaf = a.runtime_root/('float-integer-runtime-'+a.version)
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
	for relative, start, end in [('compiler/backend/llvm/recover-check.astra', None, b'bool recover_llvm_literal('), ('compiler/backend/llvm/recover-helpers-check.astra', None, b'bool recover_llvm_external_verified('), ('compiler/backend/llvm/recover-instructions.astra', b'bool recover_llvm_native_attributes(', b'int recover_llvm_extract_instructions('), ('compiler/semantic/types.astra', b'bool type_integer(', None), ('compiler/backend/llvm/recover-float-integer-check.astra', None, b'bool recover_float_integer_call_verified(')]:
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
	sources = [snapshot(ROOT/('compiler/backend/llvm/'+name+'.astra')) for name in ('capi', 'recover-capi', 'recover-shared-capi', 'recover-array-capi', 'recover-float-integer-emit')]
	rows = []
	for mode in ('O0', 'O2'):
		working = build/mode
		working.mkdir()
		oracle = working/'reference.o'
		run([a.compiler, '-'+mode, '-c', leaf/'reference.astra', '-o', oracle], mode+'-reference-build')
		exe = working/'proof'
		run([a.compiler, '-'+mode, *sources, *[row['view'] for row in views], leaf/'caller.astra', '--link-object', obj, '--link-object', shim, '--link-library', library[2:], '-o', exe], mode+'-build')
		run([exe], mode+'-execute', cwd=working, allowed=(42,))
		for physical in sorted(working.glob('float-integer-*.ll')):
			run(['opt', '-passes=verify', '-disable-output', physical], mode+'-verify-'+physical.stem)
		for target_mode in ('O0', 'O2'):
			target = working/('helper-'+target_mode)
			label = mode+'-'+target_mode
			run(['clang', '-'+target_mode, working/'float-integer-0.ll', oracle, leaf/'probe.c', '-lm', '-o', target], label+'-helper-build')
			observed = run([target], label+'-helper-execute', allowed=(42,))
			assert b'FLOAT_INTEGER_DIFFERENTIAL observations=' in observed.stdout
			memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', target], label+'-helper-memory', allowed=(42,))
			assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr and observed.stdout == memory.stdout
			widths = (32, 8, 8, 16, 16, 32, 64, 64, 64, 64)
			signed = (True, True, False, True, False, False, True, False, True, False)
			for index, source, destination in combinations():
				width = widths[destination - 1]
				exponent = width - int(signed[destination - 1])
				values = (float(2 ** exponent), -float(2 ** width), float('inf'), float('nan'))
				for sample, value in enumerate(values):
					bits = int.from_bytes(struct.pack('<f' if source == 11 else '<d', value), 'little')
					fatal = [run([target, who, index, bits], label + f'-fatal-{index}-{sample}-{who}', allowed=(132, -4)).returncode for who in ('candidate', 'reference')]
					assert fatal[0] == fatal[1]

		rows.append(dict(C0_producer_profile=mode, producer_ELF_sha256=sha(exe), C0_oracle_object_sha256=sha(oracle), physical_inputs={p.name: sha(p) for p in sorted(working.glob('float-integer-*.ll'))}))
	write(leaf/'result.json', dict(status='INDEPENDENT_FLOAT_INTEGER_RUNTIME_PREFLIGHT', profiles=rows, helpers=20, LLVM_valid_mutation_categories=MUTATIONS, source_sha256={str(p): sha(p) for p in sources}, helper_views=views, Astra_native_credit=0, limitation='C0 executes complete helper emitters and independent physical consumers. Isolated helper differential and unsuppressed memory evidence. Whole original source and Astra pipeline qualification remain pending.'))
	print('Guarded float-integer preflight passed with 20 helpers and 16 LLVM-valid mutation categories', flush=True)


if __name__ == '__main__':
	main()
