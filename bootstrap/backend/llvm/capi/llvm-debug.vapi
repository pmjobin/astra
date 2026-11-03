// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

[CCode (cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
namespace Astra.Backend.LLVM.CApi {
[CCode (cname = "LLVMDWARFSourceLanguage", has_type_id = false, cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public enum DebugLanguage {
	[CCode (cname = "LLVMDWARFSourceLanguageC11", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
	C11
}

[CCode (cname = "LLVMDWARFEmissionKind", has_type_id = false, cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public enum DebugEmission {
	[CCode (cname = "LLVMDWARFEmissionFull", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
	FULL
}

[CCode (cname = "LLVMModuleFlagBehavior", has_type_id = false, cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public enum ModuleFlagBehavior {
	[CCode (cname = "LLVMModuleFlagBehaviorWarning", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
	WARNING
}

[SimpleType]
[CCode (cname = "LLVMMetadataRef", has_type_id = false, cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public struct MetadataRef {}

[SimpleType]
[CCode (cname = "LLVMDIBuilderRef", has_type_id = false, cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public struct DIBuilderRef {}

[SimpleType]
[CCode (cname = "LLVMDbgRecordRef", has_type_id = false, cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public struct DbgRecordRef {}

[CCode (cname = "LLVMCreateDIBuilder", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static DIBuilderRef create_di_builder(ModuleRef module);
[CCode (cname = "LLVMDisposeDIBuilder", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static void dispose_di_builder(DIBuilderRef builder);
[CCode (cname = "LLVMDIBuilderFinalize", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static void di_finalize(DIBuilderRef builder);
[CCode (cname = "LLVMSetIsNewDbgInfoFormat", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static void set_new_debug_format(ModuleRef module, int enabled);
[CCode (cname = "LLVMDebugMetadataVersion", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static uint debug_metadata_version();
[CCode (cname = "LLVMValueAsMetadata", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static MetadataRef value_as_metadata(ValueRef value);
[CCode (cname = "LLVMAddModuleFlag", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static void add_module_flag(ModuleRef module, ModuleFlagBehavior behavior, string key, size_t length, MetadataRef value);
[CCode (cname = "LLVMDIBuilderCreateFile", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static MetadataRef di_file(DIBuilderRef builder, string filename, size_t filename_length, string directory, size_t directory_length);
[CCode (cname = "LLVMDIBuilderCreateCompileUnit", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static MetadataRef di_compile_unit(DIBuilderRef builder, DebugLanguage language, MetadataRef file, string producer, size_t producer_length, int optimized, string flags, size_t flags_length, uint runtime_version, string split_name, size_t split_length, DebugEmission kind, uint dwo_id, int split_inlining, int profiling, string sysroot, size_t sysroot_length, string sdk, size_t sdk_length);
[CCode (cname = "LLVMDIBuilderCreateBasicType", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static MetadataRef di_basic_type(DIBuilderRef builder, string name, size_t length, uint64 bits, uint encoding, uint flags);
[CCode (cname = "LLVMDIBuilderCreateUnspecifiedType", cheader_filename = "llvm-c/DebugInfo.h")]
public static MetadataRef di_unspecified_type(DIBuilderRef builder, string name, size_t length);
[CCode (cname = "LLVMDIBuilderCreatePointerType", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static MetadataRef di_pointer_type(DIBuilderRef builder, MetadataRef pointee, uint64 bits, uint alignment, uint address_space, string name, size_t length);
[CCode (cname = "LLVMDIBuilderCreateStructType", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static MetadataRef di_struct_type(DIBuilderRef builder, MetadataRef scope, string name, size_t length, MetadataRef file, uint line, uint64 bits, uint alignment, uint flags, MetadataRef parent, MetadataRef* fields, uint count, uint runtime_language, MetadataRef vtable, string identity, size_t identity_length);
[CCode (cname = "LLVMDIBuilderCreateMemberType", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static MetadataRef di_member_type(DIBuilderRef builder, MetadataRef scope, string name, size_t length, MetadataRef file, uint line, uint64 bits, uint alignment, uint64 offset, uint flags, MetadataRef type);
[CCode (cname = "LLVMDITypeGetName", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static unowned string di_type_name(MetadataRef type, out size_t length);
[CCode (cname = "LLVMDITypeGetSizeInBits", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static uint64 di_type_size(MetadataRef type);
[CCode (cname = "LLVMDITypeGetOffsetInBits", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static uint64 di_type_offset(MetadataRef type);
[CCode (cname = "LLVMDITypeGetAlignInBits", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static uint di_type_alignment(MetadataRef type);
[CCode (cname = "LLVMDIBuilderCreateSubroutineType", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static MetadataRef di_subroutine_type(DIBuilderRef builder, MetadataRef file, MetadataRef* types, uint count, uint flags);
[CCode (cname = "LLVMDIBuilderCreateFunction", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static MetadataRef di_function(DIBuilderRef builder, MetadataRef scope, string name, size_t name_length, string linkage, size_t linkage_length, MetadataRef file, uint line, MetadataRef type, int local, int definition, uint scope_line, uint flags, int optimized);
[CCode (cname = "LLVMSetSubprogram", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static void set_subprogram(ValueRef function, MetadataRef scope);
[CCode (cname = "LLVMGetSubprogram", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static MetadataRef get_subprogram(ValueRef function);
[CCode (cname = "LLVMDIBuilderCreateDebugLocation", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static MetadataRef di_location(ContextRef context, uint line, uint column, MetadataRef scope, MetadataRef inlined_at);
[CCode (cname = "LLVMSetCurrentDebugLocation2", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static void set_debug_location(BuilderRef builder, MetadataRef location);
[CCode (cname = "LLVMInstructionGetDebugLoc", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static MetadataRef instruction_debug_location(ValueRef instruction);
[CCode (cname = "LLVMInstructionSetDebugLoc", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static void set_instruction_debug_location(ValueRef instruction, MetadataRef location);
[CCode (cname = "LLVMDILocationGetLine", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static uint di_location_line(MetadataRef location);
[CCode (cname = "LLVMDILocationGetColumn", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static uint di_location_column(MetadataRef location);
[CCode (cname = "LLVMDILocationGetScope", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static MetadataRef di_location_scope(MetadataRef location);
[CCode (cname = "LLVMDIScopeGetFile", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static MetadataRef di_scope_file(MetadataRef scope);
[CCode (cname = "LLVMDIFileGetFilename", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static unowned string di_filename(MetadataRef file, out uint length);
[CCode (cname = "LLVMDIFileGetDirectory", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static unowned string di_directory(MetadataRef file, out uint length);
[CCode (cname = "LLVMDIBuilderCreateExpression", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static MetadataRef di_expression(DIBuilderRef builder, uint64* operations, size_t count);
[CCode (cname = "LLVMDIBuilderCreateParameterVariable", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static MetadataRef di_parameter(DIBuilderRef builder, MetadataRef scope, string name, size_t length, uint argument, MetadataRef file, uint line, MetadataRef type, int preserve, uint flags);
[CCode (cname = "LLVMDIBuilderCreateAutoVariable", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static MetadataRef di_local(DIBuilderRef builder, MetadataRef scope, string name, size_t length, MetadataRef file, uint line, MetadataRef type, int preserve, uint flags, uint alignment);
[CCode (cname = "LLVMDIBuilderInsertDbgValueRecordAtEnd", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static DbgRecordRef di_value(DIBuilderRef builder, ValueRef value, MetadataRef variable, MetadataRef expression, MetadataRef location, BasicBlockRef block);
[CCode (cname = "LLVMDIBuilderInsertDbgValueRecordBefore", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static DbgRecordRef di_value_before(DIBuilderRef builder, ValueRef value, MetadataRef variable, MetadataRef expression, MetadataRef location, ValueRef instruction);
[CCode (cname = "LLVMDIBuilderInsertDeclareRecordAtEnd", cheader_filename = "llvm-c/Core.h,llvm-c/DebugInfo.h")]
public static DbgRecordRef di_declare(DIBuilderRef builder, ValueRef storage, MetadataRef variable, MetadataRef expression, MetadataRef location, BasicBlockRef block);
}
