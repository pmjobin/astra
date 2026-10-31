// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Qualification utility only: measured offsets are not language semantics.
#include <llvm-c/Core.h>
#include <llvm-c/IRReader.h>
#include <llvm-c/Target.h>
#include <llvm-c/TargetMachine.h>
#include <stdio.h>

int main(int argc, char **argv) {
	if (argc < 3 || LLVMInitializeNativeTarget() || LLVMInitializeNativeAsmPrinter()) {
		return 1;
	}
	LLVMContextRef context = LLVMContextCreate();
	LLVMMemoryBufferRef buffer = NULL;
	LLVMModuleRef module = NULL;
	char *error = NULL;
	if (LLVMCreateMemoryBufferWithContentsOfFile(argv[1], &buffer, &error) || LLVMParseIRInContext(context, buffer, &module, &error)) {
		fprintf(stderr, "%s\n", error);
		LLVMDisposeMessage(error);
		LLVMContextDispose(context);
		return 1;
	}
	char *triple = LLVMGetDefaultTargetTriple();
	LLVMTargetRef target;
	if (LLVMGetTargetFromTriple(triple, &target, &error)) {
		fprintf(stderr, "%s\n", error);
		return 1;
	}
	LLVMTargetMachineRef machine = LLVMCreateTargetMachine(target, triple, "", "", LLVMCodeGenLevelNone, LLVMRelocPIC, LLVMCodeModelDefault);
	LLVMTargetDataRef data = LLVMCreateTargetDataLayout(machine);
	char *layout = LLVMCopyStringRepOfTargetData(data);
	printf("target %s\nDataLayout %s\n", triple, layout);
	for (int i = 2; i < argc; i++) {
		LLVMTypeRef type = LLVMGetTypeByName2(context, argv[i]);
		if (!type) {
			fprintf(stderr, "missing type %s\n", argv[i]);
			return 1;
		}
		printf("%s size=%llu alignment=%u fields=", argv[i], LLVMABISizeOfType(data, type), LLVMABIAlignmentOfType(data, type));
		for (unsigned f = 0; f < LLVMCountStructElementTypes(type); f++) {
			printf("%s%llu", f ? "," : "", LLVMOffsetOfElement(data, type, f));
		}
		printf("\n");
	}
	LLVMDisposeMessage(layout);
	LLVMDisposeTargetData(data);
	LLVMDisposeTargetMachine(machine);
	LLVMDisposeMessage(triple);
	LLVMDisposeModule(module);
	LLVMContextDispose(context);
	return 0;
}
