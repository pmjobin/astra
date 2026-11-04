// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

// Mechanical declarations from the qualified LLVM 23 Target/TargetMachine C API.
[CCode (cheader_filename = "llvm-c/Target.h,llvm-c/TargetMachine.h")]
namespace Astra.Backend.LLVM.CApi {
[SimpleType]
[CCode (cname = "LLVMTargetRef", has_type_id = false, cheader_filename = "llvm-c/Target.h,llvm-c/TargetMachine.h")]
public struct TargetRef {}

[SimpleType]
[CCode (cname = "LLVMTargetMachineRef", has_type_id = false, cheader_filename = "llvm-c/Target.h,llvm-c/TargetMachine.h")]
public struct TargetMachineRef {}

[SimpleType]
[CCode (cname = "LLVMTargetDataRef", has_type_id = false, cheader_filename = "llvm-c/Target.h,llvm-c/TargetMachine.h")]
public struct TargetDataRef {}

[CCode (cname = "LLVMCodeGenOptLevel", has_type_id = false, cheader_filename = "llvm-c/Target.h,llvm-c/TargetMachine.h")]
public enum CodeGenOptLevel {
	[CCode (cname = "LLVMCodeGenLevelNone", cheader_filename = "llvm-c/Target.h,llvm-c/TargetMachine.h")]
	NONE,
	[CCode (cname = "LLVMCodeGenLevelLess")]
	LESS,
	[CCode (cname = "LLVMCodeGenLevelDefault")]
	DEFAULT
}

[CCode (cname = "LLVMRelocMode", has_type_id = false, cheader_filename = "llvm-c/Target.h,llvm-c/TargetMachine.h")]
public enum RelocMode {
	[CCode (cname = "LLVMRelocPIC", cheader_filename = "llvm-c/Target.h,llvm-c/TargetMachine.h")]
	PIC
}

[CCode (cname = "LLVMCodeModel", has_type_id = false, cheader_filename = "llvm-c/Target.h,llvm-c/TargetMachine.h")]
public enum CodeModel {
	[CCode (cname = "LLVMCodeModelDefault", cheader_filename = "llvm-c/Target.h,llvm-c/TargetMachine.h")]
	DEFAULT
}

[CCode (cname = "LLVMCodeGenFileType", has_type_id = false, cheader_filename = "llvm-c/Target.h,llvm-c/TargetMachine.h")]
public enum CodeGenFileType {
	[CCode (cname = "LLVMObjectFile", cheader_filename = "llvm-c/Target.h,llvm-c/TargetMachine.h")]
	OBJECT
}

[CCode (cname = "LLVMInitializeNativeTarget", cheader_filename = "llvm-c/Target.h,llvm-c/TargetMachine.h")]
public static int initialize_native_target();
[CCode (cname = "LLVMInitializeNativeAsmPrinter", cheader_filename = "llvm-c/Target.h,llvm-c/TargetMachine.h")]
public static int initialize_native_asm_printer();
[CCode (cname = "LLVMInitializeNativeAsmParser", cheader_filename = "llvm-c/Target.h")]
public static int initialize_native_asm_parser();
[CCode (cname = "LLVMInitializeAllTargetInfos")]
public static void initialize_all_target_infos();
[CCode (cname = "LLVMInitializeAllTargets")]
public static void initialize_all_targets();
[CCode (cname = "LLVMInitializeAllTargetMCs")]
public static void initialize_all_target_mcs();
[CCode (cname = "LLVMInitializeAllAsmPrinters")]
public static void initialize_all_asm_printers();
[CCode (cname = "LLVMInitializeAllAsmParsers", cheader_filename = "llvm-c/Target.h")]
public static void initialize_all_asm_parsers();
[CCode (cname = "LLVMGetDefaultTargetTriple", cheader_filename = "llvm-c/Target.h,llvm-c/TargetMachine.h")]
public static char* default_target_triple();
[CCode (cname = "LLVMGetTargetFromTriple", cheader_filename = "llvm-c/Target.h,llvm-c/TargetMachine.h")]
public static int target_from_triple(string triple, out TargetRef target, out char* message);
[CCode (cname = "LLVMCreateTargetMachine", cheader_filename = "llvm-c/Target.h,llvm-c/TargetMachine.h")]
public static TargetMachineRef create_target_machine(TargetRef target, string triple, string cpu, string features, CodeGenOptLevel level, RelocMode relocation, CodeModel model);
[CCode (cname = "LLVMDisposeTargetMachine", cheader_filename = "llvm-c/Target.h,llvm-c/TargetMachine.h")]
public static void dispose_target_machine(TargetMachineRef machine);
[CCode (cname = "LLVMCreateTargetDataLayout", cheader_filename = "llvm-c/Target.h,llvm-c/TargetMachine.h")]
public static TargetDataRef create_target_data_layout(TargetMachineRef machine);
[CCode (cname = "LLVMDisposeTargetData", cheader_filename = "llvm-c/Target.h,llvm-c/TargetMachine.h")]
public static void dispose_target_data(TargetDataRef data);
[CCode (cname = "LLVMCopyStringRepOfTargetData", cheader_filename = "llvm-c/Target.h,llvm-c/TargetMachine.h")]
public static char* copy_target_data_string(TargetDataRef data);
[CCode (cname = "LLVMSetTarget", cheader_filename = "llvm-c/Core.h")]
public static void set_target(ModuleRef module, string triple);
[CCode (cname = "LLVMGetTarget", cheader_filename = "llvm-c/Core.h")]
public static unowned string get_target(ModuleRef module);
[CCode (cname = "LLVMSetModuleDataLayout", cheader_filename = "llvm-c/Target.h,llvm-c/TargetMachine.h")]
public static void set_module_data_layout(ModuleRef module, TargetDataRef data);
[CCode (cname = "LLVMGetDataLayoutStr", cheader_filename = "llvm-c/Core.h")]
public static unowned string get_data_layout(ModuleRef module);
[CCode (cname = "LLVMTargetMachineEmitToFile", cheader_filename = "llvm-c/Target.h,llvm-c/TargetMachine.h")]
public static int target_machine_emit_to_file(TargetMachineRef machine, ModuleRef module, string path, CodeGenFileType file_type, out char* message);
[CCode (cname = "LLVMTargetMachineEmitToMemoryBuffer")]
public static int target_machine_emit_to_buffer(TargetMachineRef machine, ModuleRef module, CodeGenFileType file_type, out char* message, out MemoryBufferRef buffer);
[CCode (cname = "LLVMOffsetOfElement")]
public static uint64 offset_of_element(TargetDataRef data, TypeRef type, uint element);
[CCode (cname = "LLVMABISizeOfType")]
public static uint64 abi_size_of_type(TargetDataRef data, TypeRef type);
[CCode (cname = "LLVMABIAlignmentOfType")]
public static uint abi_alignment_of_type(TargetDataRef data, TypeRef type);
[CCode (cname = "LLVMPointerSize")]
public static uint pointer_size(TargetDataRef data);

[CCode (cname = "LLVMCloneModule", cheader_filename = "llvm-c/Core.h")]
public static ModuleRef clone_module(ModuleRef module);
[SimpleType]
[CCode (cname = "LLVMPassBuilderOptionsRef", has_type_id = false, cheader_filename = "llvm-c/Transforms/PassBuilder.h")]
public struct PassBuilderOptionsRef {}

[SimpleType]
[CCode (cname = "LLVMErrorRef", has_type_id = false, cheader_filename = "llvm-c/Error.h")]
public struct ErrorRef {}

[CCode (cname = "LLVMCreatePassBuilderOptions", cheader_filename = "llvm-c/Transforms/PassBuilder.h")]
public static PassBuilderOptionsRef create_pass_builder_options();
[CCode (cname = "LLVMPassBuilderOptionsSetVerifyEach", cheader_filename = "llvm-c/Transforms/PassBuilder.h")]
public static void pass_builder_verify_each(PassBuilderOptionsRef options, int verify);
[CCode (cname = "LLVMDisposePassBuilderOptions", cheader_filename = "llvm-c/Transforms/PassBuilder.h")]
public static void dispose_pass_builder_options(PassBuilderOptionsRef options);
[CCode (cname = "LLVMRunPasses", cheader_filename = "llvm-c/Transforms/PassBuilder.h")]
public static ErrorRef run_passes(ModuleRef module, string passes, TargetMachineRef machine, PassBuilderOptionsRef options);
[CCode (cname = "LLVMGetErrorMessage", cheader_filename = "llvm-c/Error.h")]
public static char* get_error_message(ErrorRef error);
[CCode (cname = "LLVMDisposeErrorMessage", cheader_filename = "llvm-c/Error.h")]
public static void dispose_error_message(char* message);

}
