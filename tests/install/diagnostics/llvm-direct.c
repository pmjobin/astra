// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Independent LLVM C API oracle: no Astra adapter, providers or frontend.
#include <llvm-c/Analysis.h>
#include <llvm-c/Core.h>
#include <llvm-c/Error.h>
#include <llvm-c/IRReader.h>
#include <llvm-c/Target.h>
#include <llvm-c/TargetMachine.h>
#include <llvm-c/Transforms/PassBuilder.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
	if (argc != 5) return 2;
	unsigned major, minor, patch;
	LLVMGetVersion(&major, &minor, &patch);
	if (major != 23 || minor != 1 || patch != 4) return 3;
	LLVMContextRef context = LLVMContextCreate();
	LLVMModuleRef module = NULL;
	LLVMTargetMachineRef machine = NULL;
	LLVMMemoryBufferRef buffer = NULL;
	LLVMPassBuilderOptionsRef options = NULL;
	char *message = NULL;
	int result = 1;
	if (LLVMCreateMemoryBufferWithContentsOfFile(argv[1], &buffer, &message)) goto done;
	// LLVMParseIRInContext consumes the buffer on success and failure.
	if (LLVMParseIRInContext(context, buffer, &module, &message)) goto done;
	if (LLVMVerifyModule(module, LLVMReturnStatusAction, &message)) goto done;
	LLVMDisposeMessage(message);
	message = NULL;
	if (!strcmp(argv[3], "native")) {
		if (LLVMInitializeNativeTarget() || LLVMInitializeNativeAsmPrinter()) goto done;
		char *triple = LLVMGetDefaultTargetTriple();
		LLVMTargetRef target = NULL;
		if (!LLVMGetTargetFromTriple(triple, &target, &message))
			machine = LLVMCreateTargetMachine(target, triple, "", "", LLVMCodeGenLevelDefault, LLVMRelocPIC, LLVMCodeModelDefault);
		LLVMDisposeMessage(triple);
		if (!machine) goto done;
	} else if (strcmp(argv[3], "none"))
		goto done;
	options = LLVMCreatePassBuilderOptions();
	LLVMPassBuilderOptionsSetVerifyEach(options, 1);
	LLVMErrorRef error = LLVMRunPasses(module, argv[2], machine, options);
	if (error) {
		char *detail = LLVMGetErrorMessage(error);
		fputs(detail, stderr);
		LLVMDisposeErrorMessage(detail);
		goto done;
	}
	if (LLVMVerifyModule(module, LLVMReturnStatusAction, &message)) goto done;
	LLVMDisposeMessage(message);
	message = NULL;
	result = LLVMPrintModuleToFile(module, argv[4], &message);
done:
	if (message) {
		fputs(message, stderr);
		LLVMDisposeMessage(message);
	}
	if (options) LLVMDisposePassBuilderOptions(options);
	if (machine) LLVMDisposeTargetMachine(machine);
	if (module) LLVMDisposeModule(module);
	LLVMContextDispose(context);
	LLVMShutdown();
	return result;
}
