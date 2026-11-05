// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <llvm-c/Core.h>
#include <llvm-c/Analysis.h>
#include <stdint.h>
#include <stdio.h>

LLVMValueRef llvm17_text_literal(LLVMModuleRef module, const char *bytes, int32_t count);
int32_t llvm17_text_literal_matches(LLVMValueRef value, const char *bytes, int32_t count);

int main(void) {
	LLVMContextRef context = LLVMContextCreate();
	LLVMModuleRef module = LLVMModuleCreateWithNameInContext("literal-probe", context);
	const char counted[] = {'a', 0, (char)0xc3, (char)0xa9};
	LLVMValueRef value = llvm17_text_literal(module, counted, 4);
	LLVMValueRef empty = llvm17_text_literal(module, "", 0);
	if (!value || !empty || !llvm17_text_literal_matches(value, counted, 4) || !llvm17_text_literal_matches(empty, "", 0)) return 1;
	if (llvm17_text_literal_matches(value, counted, 1) || llvm17_text_literal_matches(value, "a\0ab", 4)) return 2;
	LLVMValueRef global = LLVMGetOperand(value, 0);
	LLVMValueRef original = LLVMGetInitializer(global);
	LLVMSetInitializer(global, LLVMConstStringInContext2(context, "a\0ab", 4, 1));
	if (llvm17_text_literal_matches(value, counted, 4)) return 3;
	LLVMSetInitializer(global, original);
	if (!llvm17_text_literal_matches(value, counted, 4) || LLVMVerifyModule(module, LLVMReturnStatusAction, NULL)) return 4;
	LLVMDisposeModule(module);
	LLVMContextDispose(context);
	puts("COUNTED_UTF8_NUL_EMPTY_AND_RESTORED_LITERAL_VALID");
	return 0;
}
