// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Mechanical LLVM C ABI/resource/text adapters only. No source/SSA lowering.
#define _POSIX_C_SOURCE 200809L
#include <llvm-c/Core.h>
#include <llvm-c/Analysis.h>
#include <llvm-c/Target.h>
#include <llvm-c/TargetMachine.h>
#include <llvm-c/Transforms/PassBuilder.h>
#include <llvm/Config/llvm-config.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#if LLVM_VERSION_MAJOR != 23
#error LLVM 23 required
#endif
_Static_assert(sizeof(void *) == 8, "qualified x86-64 pointers required");

const char *llvm12_empty(void) {
	return "";
}

static char *text_copy(const char *p, int32_t n) {
	if (!p || n < 0 || n > 4096 || memchr(p, 0, (size_t)n)) return NULL;
	char *out = malloc((size_t)n + 1);
	if (out) {
		memcpy(out, p, (size_t)n);
		out[n] = 0;
	}
	return out;
}

LLVMTypeRef llvm15_struct(LLVMContextRef context, const char *p, int32_t n) {
	char *name = text_copy(p, n);
	if (!name) return NULL;
	LLVMTypeRef type = LLVMStructCreateNamed(context, name);
	free(name);
	return type;
}

int32_t llvm15_struct_named(LLVMTypeRef type, const char *p, int32_t n) {
	if (!type || !p || n < 1 || n > 4096 || LLVMGetTypeKind(type) != LLVMStructTypeKind) return 0;
	const char *name = LLVMGetStructName(type);
	return name && strlen(name) == (size_t)n && memcmp(name, p, (size_t)n) == 0;
}

LLVMValueRef llvm13_real(LLVMTypeRef type, const char *p, int32_t n, int32_t count) {
	if (!p || count < 1 || count > n || n > 4096 || memchr(p, 0, (size_t)n)) return NULL;
	return LLVMConstRealOfStringAndSize(type, p, (unsigned)count);
}

double llvm13_real_value(LLVMValueRef value) {
	LLVMBool loses = 0;
	return LLVMConstRealGetDouble(value, &loses);
}

int32_t llvm13_named(LLVMValueRef value, const char *p, int32_t n) {
	if (!value || !p || n < 1 || n > 4096) return 0;
	size_t length = 0;
	const char *actual = LLVMGetValueName2(value, &length);
	return length == (size_t)n && !memcmp(actual, p, length);
}

int32_t llvm13_index(LLVMValueRef instruction, int32_t ordinal, int32_t expected) {
	if (ordinal < 0 || expected < 0 || (unsigned)ordinal >= LLVMGetNumIndices(instruction)) return 0;
	return LLVMGetIndices(instruction)[ordinal] == (unsigned)expected;
}

int32_t llvm13_attribute(LLVMValueRef value, int32_t index, int32_t call, const char *p, int32_t n) {
	if (!value || !p || n < 1 || n > 128 || index < -1 || index > 512) return 1;
	unsigned kind = LLVMGetEnumAttributeKindForName(p, (size_t)n);
	if (!kind) return 0;
	LLVMAttributeRef attribute = call ? LLVMGetCallSiteEnumAttribute(value, (LLVMAttributeIndex)index, kind) : LLVMGetEnumAttributeAtIndex(value, (LLVMAttributeIndex)index, kind);
	return attribute != NULL;
}

void llvm13_rename(LLVMValueRef value, const char *p, int32_t n) {
	if (value && p && n > 0 && n <= 4096) LLVMSetValueName2(value, p, (size_t)n);
}

void llvm13_false_align(LLVMContextRef context, LLVMValueRef function, int32_t parameter) {
	unsigned kind = LLVMGetEnumAttributeKindForName("align", 5);
	LLVMAddAttributeAtIndex(function, (LLVMAttributeIndex)(parameter + 1), LLVMCreateEnumAttribute(context, kind, 64));
}

LLVMValueRef llvm12_function(LLVMModuleRef m, LLVMTypeRef t, const char *p, int32_t n) {
	char *name = text_copy(p, n);
	if (!name) return NULL;
	LLVMValueRef result = LLVMGetNamedFunction(m, name);
	if (result && LLVMGlobalGetValueType(result) != t) {
		free(name);
		return NULL;
	}
	if (!result) result = LLVMAddFunction(m, name, t);
	free(name);
	return result;
}

LLVMBasicBlockRef llvm12_block(LLVMContextRef c, LLVMValueRef f, const char *p, int32_t n) {
	char *name = text_copy(p, n);
	if (!name) return NULL;
	LLVMBasicBlockRef result = LLVMAppendBasicBlockInContext(c, f, name);
	free(name);
	return result;
}

LLVMTargetMachineRef llvm12_machine(int32_t level) {
	if (level != 0 && level != 2) return NULL;
	if (LLVMInitializeNativeTarget() || LLVMInitializeNativeAsmPrinter()) return NULL;
	char *triple = LLVMGetDefaultTargetTriple(), *error = NULL;
	LLVMTargetRef target = NULL;
	LLVMTargetMachineRef result = NULL;
	if (triple && !strncmp(triple, "x86_64-", 7) && strstr(triple, "linux") && !LLVMGetTargetFromTriple(triple, &target, &error))
		result = LLVMCreateTargetMachine(target, triple, "", "", level == 0 ? LLVMCodeGenLevelNone : LLVMCodeGenLevelDefault, LLVMRelocPIC, LLVMCodeModelDefault);
	if (error) LLVMDisposeMessage(error);
	if (triple) LLVMDisposeMessage(triple);
	return result;
}

int32_t llvm12_target(LLVMModuleRef m, LLVMTargetMachineRef t) {
	char *triple = LLVMGetTargetMachineTriple(t);
	if (!triple) return 1;
	LLVMSetTarget(m, triple);
	LLVMDisposeMessage(triple);
	return 0;
}

int32_t llvm12_verify(LLVMModuleRef m) {
	char *error = NULL;
	int result = LLVMVerifyModule(m, LLVMReturnStatusAction, &error);
	if (result && error) fprintf(stderr, "LLVM_INVALID_IR: %s", error);
	if (error) LLVMDisposeMessage(error);
	return result;
}

int32_t llvm12_optimize(LLVMModuleRef m, LLVMTargetMachineRef t, int32_t level) {
	if (llvm12_verify(m)) return 1;
	if (level == 0) return 0;
	if (level != 2) return 1;
	LLVMPassBuilderOptionsRef options = LLVMCreatePassBuilderOptions();
	LLVMPassBuilderOptionsSetVerifyEach(options, 1);
	LLVMErrorRef error = LLVMRunPasses(m, "default<O2>", t, options);
	LLVMDisposePassBuilderOptions(options);
	if (error) {
		char *message = LLVMGetErrorMessage(error);
		fprintf(stderr, "LLVM_INVALID_IR: %s\n", message);
		LLVMDisposeErrorMessage(message);
		return 1;
	}
	return llvm12_verify(m);
}

int32_t llvm12_write(LLVMModuleRef m, LLVMTargetMachineRef t, int32_t object, int32_t limit, const char *p, int32_t n) {
	if (limit < 1 || limit > 16777216 || (object != 0 && object != 1) || llvm12_verify(m)) return 1;
	char *path = text_copy(p, n);
	if (!path) return 1;
	LLVMMemoryBufferRef buffer = NULL;
	char *error = NULL, *ir = NULL;
	const char *data = NULL;
	size_t size = 0;
	int result = 1;
	if (object) {
		if (LLVMTargetMachineEmitToMemoryBuffer(t, m, LLVMObjectFile, &error, &buffer)) goto done;
		data = LLVMGetBufferStart(buffer);
		size = LLVMGetBufferSize(buffer);
	} else {
		ir = LLVMPrintModuleToString(m);
		if (!ir) goto done;
		data = ir;
		size = strlen(ir);
	}
	if (size > (size_t)limit) {
		result = 2;
		goto done;
	}
	char *temp = malloc(strlen(path) + 16);
	if (!temp) goto done;
	sprintf(temp, "%s.XXXXXX", path);
	int fd = mkstemp(temp);
	if (fd >= 0) {
		size_t pos = 0;
		while (pos < size) {
			ssize_t wrote = write(fd, data + pos, size - pos);
			if (wrote <= 0) break;
			pos += (size_t)wrote;
		}
		int synced = fsync(fd), closed = close(fd);
		if (pos == size && !synced && !closed && !rename(temp, path)) result = 0;
		unlink(temp);
	}
	free(temp);
done:
	if (error) {
		fprintf(stderr, "LLVM_OUTPUT_FAILURE: %s\n", error);
		LLVMDisposeMessage(error);
	}
	if (buffer) LLVMDisposeMemoryBuffer(buffer);
	if (ir) LLVMDisposeMessage(ir);
	free(path);
	return result;
}

void llvm12_nobuiltin(LLVMContextRef c, LLVMValueRef call) {
	LLVMAddCallSiteAttribute(call, LLVMAttributeFunctionIndex, LLVMCreateEnumAttribute(c, LLVMGetEnumAttributeKindForName("nobuiltin", 9), 0));
}

// The current Astra C boundary cannot address a dynamic buffer element. This
// bounded pointer-vector adapter copies only opaque handles selected in Astra.
void *llvm12_handles(void) {
	return calloc(1024, sizeof(void *));
}

void llvm12_handles_dispose(void *p) {
	free(p);
}

void llvm12_handle_set(void *p, int32_t i, void *value) {
	if (p && i >= 0 && i < 1024) ((void **)p)[i] = value;
}

void *llvm12_handle_offset(void *p, int32_t i) {
	return p && i >= 0 && i < 1024 ? (void *)((void **)p + i) : NULL;
}

void *llvm12_seal(LLVMModuleRef m, int32_t limit) {
	char *s = LLVMPrintModuleToString(m);
	if (s && (limit < 1 || strlen(s) > (size_t)limit)) {
		LLVMDisposeMessage(s);
		return NULL;
	}
	return s;
}

int32_t llvm12_matches(LLVMModuleRef m, const char *seal) {
	if (!seal) return 0;
	char *s = LLVMPrintModuleToString(m);
	int32_t same = s && !strcmp(s, seal);
	if (s) LLVMDisposeMessage(s);
	return same;
}

void llvm12_print_hex(LLVMModuleRef m) {
	char *s = LLVMPrintModuleToString(m);
	if (s) {
		for (size_t i = 0; s[i]; ++i)
			printf("%02x", (unsigned char)s[i]);
		LLVMDisposeMessage(s);
	}
	fflush(stdout);
}

void llvm12_bad_target(LLVMModuleRef m, int32_t bad) {
	char *s = LLVMGetDefaultTargetTriple();
	LLVMSetTarget(m, bad ? "aarch64-unknown-linux-gnu" : s);
	LLVMDisposeMessage(s);
}

void llvm12_bad_layout(LLVMModuleRef m, LLVMTargetMachineRef t, int32_t bad) {
	LLVMTargetDataRef d = LLVMCreateTargetDataLayout(t);
	if (bad)
		LLVMSetDataLayout(m, "e-p:32:32");
	else
		LLVMSetModuleDataLayout(m, d);
	LLVMDisposeTargetData(d);
}

void llvm12_false_noalias(LLVMContextRef c, LLVMValueRef f) {
	LLVMAddAttributeAtIndex(f, 1, LLVMCreateEnumAttribute(c, LLVMGetEnumAttributeKindForName("noalias", 7), 0));
}

void llvm12_noinline(LLVMContextRef c, LLVMValueRef f) {
	LLVMAddAttributeAtIndex(f, LLVMAttributeFunctionIndex, LLVMCreateEnumAttribute(c, LLVMGetEnumAttributeKindForName("noinline", 8), 0));
}
