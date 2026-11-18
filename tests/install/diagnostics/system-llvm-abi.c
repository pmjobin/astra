// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Exercise the actual provider and independent raw C API on both branch forms.
#include <llvm-c/Core.h>
#include <llvm/Config/llvm-config.h>
#include <assert.h>
#include <stdint.h>
#include <stdio.h>

_Static_assert(sizeof(LLVMOpcode) == 4 && sizeof(LLVMTypeKind) == 4, "C enum ABI");
_Static_assert(sizeof(LLVMValueRef) == 8 && sizeof(uint64_t) == 8, "LP64 ABI");
_Static_assert(LLVMRet == 1 && LLVMUnreachable == 7 && LLVMAlloca == 26 && LLVMLoad == 27 && LLVMStore == 28 && LLVMGetElementPtr == 29 && LLVMICmp == 42 && LLVMFCmp == 43 && LLVMCall == 45 && LLVMSelect == 46, "physical opcode ABI");

int main(void) {
	LLVMContextRef context = LLVMContextCreate();
	LLVMModuleRef module = LLVMModuleCreateWithNameInContext("abi", context);
	LLVMBuilderRef builder = LLVMCreateBuilderInContext(context);
	LLVMValueRef function = LLVMAddFunction(module, "branch", LLVMFunctionType(LLVMVoidTypeInContext(context), NULL, 0, 0));
	LLVMBasicBlockRef entry = LLVMAppendBasicBlockInContext(context, function, "entry");
	LLVMBasicBlockRef next = LLVMAppendBasicBlockInContext(context, function, "next");
	LLVMBasicBlockRef end = LLVMAppendBasicBlockInContext(context, function, "end");
	LLVMPositionBuilderAtEnd(builder, entry);
	LLVMValueRef conditional = LLVMBuildCondBr(builder, LLVMConstInt(LLVMInt1TypeInContext(context), 1, 0), next, end);
	LLVMPositionBuilderAtEnd(builder, next);
	LLVMValueRef unconditional = LLVMBuildBr(builder, end);
	LLVMPositionBuilderAtEnd(builder, end);
	LLVMValueRef ret = LLVMBuildRetVoid(builder);
	assert((int)LLVMGetInstructionOpcode(conditional) == 71);
	assert((int)LLVMGetInstructionOpcode(unconditional) == 70);
	assert(LLVMGetInstructionOpcode(ret) == LLVMRet);
	assert(LLVMGetNumSuccessors(conditional) == 2 && LLVMGetNumSuccessors(unconditional) == 1);
	assert(LLVMGetSuccessor(conditional, 0) == next && LLVMGetSuccessor(unconditional, 0) == end);
	assert(LLVMGetCondition(conditional) != NULL);
	LLVMDisposeBuilder(builder);
	LLVMDisposeModule(module);
	LLVMContextDispose(context);
	LLVMShutdown();
	puts("SYSTEM_LLVM_BRANCH_AND_LP64_ABI_PASS");
	return 0;
}
