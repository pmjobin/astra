// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <llvm-c/Core.h>
#include <llvm-c/TargetMachine.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern LLVMTargetMachineRef llvm12_machine(int32_t level);
extern int32_t llvm12_target(LLVMModuleRef module, LLVMTargetMachineRef machine);
extern int32_t llvm12_write(LLVMModuleRef module, LLVMTargetMachineRef machine, int32_t object, int32_t limit, const char *path, int32_t length);
extern int32_t llvm26_write_ir(LLVMModuleRef module, int32_t limit, const char *path, int32_t length);

enum { LEGACY_LIMIT = 16777216,
	   MODULE_LIMIT = 134217728 };

static const char sentinel[] = "ASTRA_IR_TRANSPORT_SENTINEL\n";

static void require(int value) {
	if (!value) exit(91);
}

static void protect(const char *path) {
	FILE *file = fopen(path, "wb");
	require(file && fwrite(sentinel, 1, sizeof(sentinel) - 1, file) == sizeof(sentinel) - 1 && fclose(file) == 0);
}

static void preserved(const char *path) {
	char buffer[sizeof(sentinel)];
	FILE *file = fopen(path, "rb");
	require(file && fread(buffer, 1, sizeof(buffer), file) == sizeof(sentinel) - 1 && fclose(file) == 0 && memcmp(buffer, sentinel, sizeof(sentinel) - 1) == 0);
}

int main(int argc, char **argv) {
	require(argc == 2);
	char old_path[4096], new_path[4096], object_path[4096], refused[4096], large[4096];
	require(snprintf(old_path, sizeof(old_path), "%s/legacy.ll", argv[1]) < (int)sizeof(old_path));
	require(snprintf(new_path, sizeof(new_path), "%s/module.ll", argv[1]) < (int)sizeof(new_path));
	require(snprintf(object_path, sizeof(object_path), "%s/legacy.o", argv[1]) < (int)sizeof(object_path));
	require(snprintf(refused, sizeof(refused), "%s/refused.ll", argv[1]) < (int)sizeof(refused));
	require(snprintf(large, sizeof(large), "%s/large.ll", argv[1]) < (int)sizeof(large));
	LLVMContextRef context = LLVMContextCreate();
	LLVMModuleRef module = LLVMModuleCreateWithNameInContext("transport", context);
	LLVMTypeRef signature = LLVMFunctionType(LLVMInt32TypeInContext(context), NULL, 0, 0);
	LLVMValueRef function = LLVMAddFunction(module, "f", signature);
	LLVMBasicBlockRef entry = LLVMAppendBasicBlockInContext(context, function, "entry");
	LLVMBasicBlockRef a = LLVMAppendBasicBlockInContext(context, function, "b");
	LLVMBasicBlockRef b = LLVMAppendBasicBlockInContext(context, function, "b");
	LLVMBasicBlockRef unreachable = LLVMAppendBasicBlockInContext(context, function, "b");
	LLVMBuilderRef builder = LLVMCreateBuilderInContext(context);
	LLVMPositionBuilderAtEnd(builder, entry);
	LLVMBuildBr(builder, a);
	LLVMPositionBuilderAtEnd(builder, a);
	LLVMBuildBr(builder, b);
	LLVMPositionBuilderAtEnd(builder, b);
	LLVMBuildRet(builder, LLVMConstInt(LLVMInt32TypeInContext(context), 42, 0));
	LLVMPositionBuilderAtEnd(builder, unreachable);
	LLVMBuildRet(builder, LLVMConstInt(LLVMInt32TypeInContext(context), 42, 0));
	require(llvm12_write(module, NULL, 0, LEGACY_LIMIT, old_path, (int32_t)strlen(old_path)) == 0);
	require(llvm26_write_ir(module, LEGACY_LIMIT, new_path, (int32_t)strlen(new_path)) == 0);
	LLVMTargetMachineRef machine = llvm12_machine(TRANSPORT_LEVEL);
	require(machine && llvm12_target(module, machine) == 0);
	require(llvm12_write(module, machine, 1, LEGACY_LIMIT, object_path, (int32_t)strlen(object_path)) == 0);
	LLVMDisposeTargetMachine(machine);
	LLVMDisposeBuilder(builder);
	LLVMDisposeModule(module);
	module = LLVMModuleCreateWithNameInContext("transport-large", context);
	char *bytes = malloc(LEGACY_LIMIT);
	require(bytes != NULL);
	memset(bytes, 'A', LEGACY_LIMIT);
	LLVMValueRef data = LLVMConstStringInContext2(context, bytes, LEGACY_LIMIT, 1);
	free(bytes);
	LLVMValueRef global = LLVMAddGlobal(module, LLVMTypeOf(data), "bytes");
	LLVMSetInitializer(global, data);
	LLVMSetGlobalConstant(global, 1);
	protect(refused);
	require(llvm12_write(module, NULL, 0, LEGACY_LIMIT, refused, (int32_t)strlen(refused)) == 2);
	preserved(refused);
	require(llvm12_write(module, NULL, 0, LEGACY_LIMIT + 1, refused, (int32_t)strlen(refused)) == 1);
	preserved(refused);
	require(llvm26_write_ir(module, LEGACY_LIMIT, refused, (int32_t)strlen(refused)) == 2);
	preserved(refused);
	require(llvm26_write_ir(module, MODULE_LIMIT + 1, refused, (int32_t)strlen(refused)) == 1);
	preserved(refused);
	require(llvm26_write_ir(module, 0, refused, (int32_t)strlen(refused)) == 1);
	preserved(refused);
	require(llvm26_write_ir(module, -1, refused, (int32_t)strlen(refused)) == 1);
	preserved(refused);
	require(llvm26_write_ir(NULL, MODULE_LIMIT, refused, (int32_t)strlen(refused)) == 1);
	preserved(refused);
	require(llvm26_write_ir(module, MODULE_LIMIT, refused, -1) == 1);
	preserved(refused);
	require(llvm26_write_ir(module, MODULE_LIMIT, large, (int32_t)strlen(large)) == 0);
	function = LLVMAddFunction(module, "invalid", signature);
	LLVMAppendBasicBlockInContext(context, function, "missing-terminator");
	require(llvm12_write(module, NULL, 0, LEGACY_LIMIT, refused, (int32_t)strlen(refused)) == 1);
	preserved(refused);
	require(llvm26_write_ir(module, MODULE_LIMIT, refused, (int32_t)strlen(refused)) == 1);
	preserved(refused);
	LLVMDeleteFunction(function);
	LLVMDisposeModule(module);
	LLVMContextDispose(context);
	LLVMShutdown();
	puts("SMALL_IDENTITY LARGE_IR LEGACY_CAP MODULE_CAP INVALID_IR SENTINELS");
	return 42;
}
