// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Feed existing IR through the unchanged mechanical C adapter, without Astra.
#include <llvm-c/Core.h>
#include <llvm-c/IRReader.h>
#include <llvm-c/TargetMachine.h>
#include <stdint.h>
#include <stdio.h>

extern LLVMTargetMachineRef llvm12_machine(int32_t level);
extern int32_t llvm12_optimize(LLVMModuleRef module, LLVMTargetMachineRef target, int32_t level);

int main(int argc, char **argv) {
	if (argc != 2) return 2;
	LLVMContextRef context = LLVMContextCreate();
	LLVMModuleRef module = NULL;
	LLVMTargetMachineRef target = NULL;
	LLVMMemoryBufferRef buffer = NULL;
	char *message = NULL;
	int result = 1;
	if (LLVMCreateMemoryBufferWithContentsOfFile(argv[1], &buffer, &message)) goto done;
	// The parser consumes buffer, including when it reports a parse error.
	if (LLVMParseIRInContext(context, buffer, &module, &message)) goto done;
	target = llvm12_machine(2);
	if (!target) goto done;
	result = llvm12_optimize(module, target, 2);
done:
	if (message) {
		fputs(message, stderr);
		LLVMDisposeMessage(message);
	}
	if (module) LLVMDisposeModule(module);
	if (target) LLVMDisposeTargetMachine(target);
	LLVMContextDispose(context);
	LLVMShutdown();
	return result;
}
