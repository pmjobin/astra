// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <assert.h>
#include <stddef.h>
#include <llvm-c/Analysis.h>
#include <llvm-c/Core.h>
#include <llvm/Config/llvm-config.h>

#if LLVM_VERSION_MAJOR != 23
#error LLVM 23 required
#endif

int main(void) {
	LLVMContextRef context = LLVMContextCreate();
	LLVMModuleRef module = LLVMModuleCreateWithNameInContext("astra-branch-api", context);
	LLVMTypeRef predicate = LLVMInt1TypeInContext(context);
	LLVMTypeRef result = LLVMInt32TypeInContext(context);
	LLVMTypeRef signature = LLVMFunctionType(result, &predicate, 1, 0);
	LLVMValueRef function = LLVMAddFunction(module, "choose", signature);
	LLVMBasicBlockRef entry = LLVMAppendBasicBlockInContext(context, function, "entry");
	LLVMBasicBlockRef yes = LLVMAppendBasicBlockInContext(context, function, "yes");
	LLVMBasicBlockRef no = LLVMAppendBasicBlockInContext(context, function, "no");
	LLVMBasicBlockRef done = LLVMAppendBasicBlockInContext(context, function, "done");
	LLVMBuilderRef builder = LLVMCreateBuilderInContext(context);
	LLVMPositionBuilderAtEnd(builder, entry);
	LLVMValueRef condition = LLVMGetParam(function, 0);
	LLVMValueRef branch = LLVMBuildCondBr(builder, condition, yes, no);
	assert(LLVMGetInstructionOpcode(branch) == LLVMCondBr);
	assert(LLVMGetNumSuccessors(branch) == 2 && LLVMGetCondition(branch) == condition);
	assert(LLVMGetSuccessor(branch, 0) == yes && LLVMGetSuccessor(branch, 1) == no);
	// LLVM 23 operands follow successor order; LLVM 22 reversed these two.
	assert(LLVMValueAsBasicBlock(LLVMGetOperand(branch, 1)) == yes);
	assert(LLVMValueAsBasicBlock(LLVMGetOperand(branch, 2)) == no);
	LLVMSetSuccessor(branch, 0, no);
	LLVMSetSuccessor(branch, 1, yes);
	assert(LLVMValueAsBasicBlock(LLVMGetOperand(branch, 1)) == no);
	assert(LLVMValueAsBasicBlock(LLVMGetOperand(branch, 2)) == yes);
	LLVMSetSuccessor(branch, 0, yes);
	LLVMSetSuccessor(branch, 1, no);
	LLVMPositionBuilderAtEnd(builder, yes);
	LLVMBuildRet(builder, LLVMConstInt(result, 17, 0));
	LLVMPositionBuilderAtEnd(builder, no);
	LLVMValueRef jump = LLVMBuildBr(builder, done);
	assert(LLVMGetInstructionOpcode(jump) == LLVMUncondBr);
	assert(LLVMGetNumSuccessors(jump) == 1 && LLVMGetSuccessor(jump, 0) == done);
	assert(LLVMValueAsBasicBlock(LLVMGetOperand(jump, 0)) == done);
	LLVMPositionBuilderAtEnd(builder, done);
	LLVMBuildRet(builder, LLVMConstInt(result, 29, 0));
	char *message = NULL;
	assert(!LLVMVerifyModule(module, LLVMReturnStatusAction, &message));
	LLVMDisposeMessage(message);
	LLVMDisposeBuilder(builder);
	LLVMDisposeModule(module);
	LLVMContextDispose(context);
	return 0;
}
