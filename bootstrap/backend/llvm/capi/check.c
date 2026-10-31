// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

// Configure-time C API/link check; never linked into astrac.
#include <stddef.h>
#include <llvm-c/Analysis.h>
#include <llvm-c/Core.h>
#include <llvm-c/Target.h>
#include <llvm-c/TargetMachine.h>
#include <llvm-c/Transforms/PassBuilder.h>
#include <llvm/Config/llvm-config.h>

#if LLVM_VERSION_MAJOR != 22
#error "ASTRA-PTR-1 requires LLVM 22 headers"
#endif

int main(void) {
	if (LLVMInitializeNativeTarget() || LLVMInitializeNativeAsmPrinter()) {
		return 1;
	}
	char *triple = LLVMGetDefaultTargetTriple();
	LLVMTargetRef target = NULL;
	char *target_error = NULL;
	if (LLVMGetTargetFromTriple(triple, &target, &target_error)) {
		LLVMDisposeMessage(target_error);
		LLVMDisposeMessage(triple);
		return 1;
	}
	LLVMTargetMachineRef machine = LLVMCreateTargetMachine(target, triple, "", "", LLVMCodeGenLevelNone, LLVMRelocPIC, LLVMCodeModelDefault);
	if (machine == NULL) {
		LLVMDisposeMessage(triple);
		return 1;
	}
	LLVMContextRef context = LLVMContextCreate();
	LLVMModuleRef module = LLVMModuleCreateWithNameInContext("astra-api-check", context);
	LLVMTargetDataRef data = LLVMCreateTargetDataLayout(machine);
	LLVMSetTarget(module, triple);
	LLVMSetModuleDataLayout(module, data);
	LLVMTypeRef i32 = LLVMInt32TypeInContext(context);
	LLVMTypeRef signature = LLVMFunctionType(i32, NULL, 0, 0);
	LLVMValueRef function = LLVMAddFunction(module, "astra_api_check", signature);
	LLVMSetLinkage(function, LLVMInternalLinkage);
	LLVMSetFunctionCallConv(function, LLVMFastCallConv);
	LLVMValueRef imported = LLVMAddFunction(module, "astra_c_api_check", signature);
	LLVMSetLinkage(imported, LLVMExternalLinkage);
	LLVMSetFunctionCallConv(imported, LLVMCCallConv);
	LLVMBasicBlockRef block = LLVMAppendBasicBlockInContext(context, function, "entry");
	LLVMBuilderRef builder = LLVMCreateBuilderInContext(context);
	LLVMPositionBuilderAtEnd(builder, block);
	LLVMValueRef call = LLVMBuildCall2(builder, signature, imported, NULL, 0, "result");
	LLVMSetInstructionCallConv(call, LLVMCCallConv);
	LLVMBuildRet(builder, call);
	size_t name_length = 0;
	const char *name = LLVMGetValueName2(imported, &name_length);
	int invalid_import = name == NULL || name_length == 0 || LLVMGetFirstBasicBlock(imported) != NULL || LLVMGetLinkage(imported) != LLVMExternalLinkage || LLVMGetFunctionCallConv(imported) != LLVMCCallConv || LLVMGetInstructionCallConv(call) != LLVMCCallConv || LLVMGetCalledValue(call) != imported || LLVMGetCalledFunctionType(call) != LLVMGlobalGetValueType(imported);
	LLVMValueRef exported = LLVMAddFunction(module, "astra_export_api_check", signature);
	LLVMSetLinkage(exported, LLVMExternalLinkage);
	LLVMSetFunctionCallConv(exported, LLVMCCallConv);
	LLVMBasicBlockRef export_block = LLVMAppendBasicBlockInContext(context, exported, "entry");
	LLVMPositionBuilderAtEnd(builder, export_block);
	LLVMValueRef forwarded = LLVMBuildCall2(builder, signature, function, NULL, 0, "result");
	LLVMSetInstructionCallConv(forwarded, LLVMFastCallConv);
	LLVMValueRef returned = LLVMBuildRet(builder, forwarded);
	int invalid_export = LLVMGetNamedFunction(module, "astra_export_api_check") != exported || LLVMGetNextBasicBlock(export_block) != NULL || LLVMGetFirstInstruction(export_block) != forwarded || LLVMGetNextInstruction(forwarded) != returned || LLVMGetNextInstruction(returned) != NULL || LLVMCountParams(exported) != 0 || LLVMGetNumArgOperands(forwarded) != 0 || LLVMGetNumOperands(returned) != 1 || LLVMGetOperand(returned, 0) != forwarded || LLVMGetCalledValue(forwarded) != function || LLVMGetInstructionCallConv(forwarded) != LLVMFastCallConv;
	LLVMTypeRef ptr = LLVMPointerTypeInContext(context, 0);
	LLVMValueRef text_bytes[] = {LLVMConstInt(LLVMInt8TypeInContext(context), 'a', 0), LLVMConstInt(LLVMInt8TypeInContext(context), 0, 0)};
	LLVMValueRef text_data = LLVMConstArray2(LLVMInt8TypeInContext(context), text_bytes, 2);
	LLVMValueRef text_global = LLVMAddGlobal(module, LLVMTypeOf(text_data), "astra.text.check");
	LLVMSetLinkage(text_global, LLVMPrivateLinkage);
	LLVMSetGlobalConstant(text_global, 1);
	LLVMSetInitializer(text_global, text_data);
	LLVMValueRef text_fields[] = {text_global, LLVMConstInt(i32, 2, 0)};
	LLVMValueRef text_view = LLVMConstStructInContext(context, text_fields, 2, 0);
	LLVMAddAttributeAtIndex(function, LLVMAttributeFunctionIndex, LLVMCreateStringAttribute(context, "no-builtins", 11, "", 0));
	int invalid_text = LLVMGetNamedGlobal(module, "astra.text.check") != text_global || !LLVMIsGlobalConstant(text_global) || LLVMGetLinkage(text_global) != LLVMPrivateLinkage || LLVMCountStructElementTypes(LLVMTypeOf(text_view)) != 2;
	LLVMValueRef pointer_null = LLVMConstPointerNull(ptr);
	LLVMValueRef pointer_function = LLVMAddFunction(module, "astra_pointer_api_check", LLVMFunctionType(ptr, NULL, 0, 0));
	LLVMPositionBuilderAtEnd(builder, LLVMAppendBasicBlockInContext(context, pointer_function, "entry"));
	LLVMBuildRet(builder, pointer_null);
	char *message = NULL;
	LLVMBool failed = LLVMVerifyModule(module, LLVMReturnStatusAction, &message);
	if (message != NULL) {
		LLVMDisposeMessage(message);
	}
	LLVMDisposeBuilder(builder);
	LLVMModuleRef copy = LLVMCloneModule(module);
	LLVMPassBuilderOptionsRef options = LLVMCreatePassBuilderOptions();
	LLVMPassBuilderOptionsSetVerifyEach(options, 1);
	LLVMErrorRef optimization = LLVMRunPasses(copy, "default<O2>", machine, options);
	if (optimization) {
		char *diagnostic = LLVMGetErrorMessage(optimization);
		LLVMDisposeErrorMessage(diagnostic);
		failed = 1;
	}
	LLVMDisposePassBuilderOptions(options);
	LLVMDisposeModule(copy);
	LLVMDisposeModule(module);
	LLVMContextDispose(context);
	LLVMDisposeTargetData(data);
	LLVMDisposeTargetMachine(machine);
	LLVMDisposeMessage(triple);
	return failed != 0 || invalid_import || invalid_export || invalid_text;
}
