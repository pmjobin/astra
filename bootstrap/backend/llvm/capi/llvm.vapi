// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

// Mechanical declarations of only the public LLVM 22 C APIs used by this backend.
// These opaque references are backend implementation details, not Astra types.
[CCode (cheader_filename = "llvm-c/Core.h,llvm-c/Analysis.h")]
namespace Astra.Backend.LLVM.CApi {
[SimpleType]
[CCode (cname = "LLVMMemoryBufferRef", has_type_id = false)]
public struct MemoryBufferRef {}
[CCode (cname = "LLVMGetBufferStart")]
public static unowned string buffer_start(MemoryBufferRef buffer);
[CCode (cname = "LLVMGetBufferSize")]
public static size_t buffer_size(MemoryBufferRef buffer);
[CCode (cname = "LLVMDisposeMemoryBuffer")]
public static void dispose_memory_buffer(MemoryBufferRef buffer);
[CCode (cname = "LLVMTypeKind", has_type_id = false)]
public enum TypeKind {
	[CCode (cname = "LLVMStructTypeKind")]
	STRUCT,
	[CCode (cname = "LLVMVoidTypeKind")]
	VOID,
	[CCode (cname = "LLVMIntegerTypeKind")]
	INTEGER,
	[CCode (cname = "LLVMPointerTypeKind")]
	POINTER
}
[CCode (cname = "LLVMGetTypeKind")]
public static TypeKind type_kind(TypeRef type);
[CCode (cname = "LLVMGetIncomingValue")]
public static ValueRef incoming_value(ValueRef phi, uint index);
[CCode (cname = "LLVMIsAFunction")]
public static ValueRef is_function(ValueRef value);
[CCode (cname = "LLVMPositionBuilderBefore")]
public static void position_builder_before(BuilderRef builder, ValueRef instruction);
[CCode (cname = "LLVMGetInlineAsm")]
public static ValueRef inline_assembly(TypeRef type, string assembly, size_t assembly_length, string constraints, size_t constraints_length, int side_effects, int align_stack, int dialect, int can_throw);
[CCode (cname = "LLVMConstIntToPtr")]
public static ValueRef const_int_to_ptr(ValueRef value, TypeRef type);
[CCode (cname = "LLVMSetOrdering")]
public static void set_ordering(ValueRef instruction, int ordering);
[CCode (cname = "LLVMBuildAtomicRMW")]
public static ValueRef build_atomic_rmw(BuilderRef builder, int operation, ValueRef pointer, ValueRef value, int ordering, int single_thread);
[CCode (cname = "LLVMGetAtomicRMWBinOp")]
public static int atomic_rmw_operation(ValueRef instruction);
[CCode (cname = "LLVMBuildAtomicCmpXchg")]
public static ValueRef build_atomic_cmp_xchg(BuilderRef builder, ValueRef pointer, ValueRef expected, ValueRef replacement, int success_order, int failure_order, int single_thread);
[CCode (cname = "LLVMGetCmpXchgSuccessOrdering")]
public static int cmp_xchg_success_order(ValueRef instruction);
[CCode (cname = "LLVMGetCmpXchgFailureOrdering")]
public static int cmp_xchg_failure_order(ValueRef instruction);
[CCode (cname = "LLVMGetWeak")]
public static int cmp_xchg_weak(ValueRef instruction);
[CCode (cname = "LLVMIsAtomicSingleThread")]
public static int atomic_single_thread(ValueRef instruction);
[CCode (cname = "LLVMGetFirstFunction")]
public static ValueRef first_function(ModuleRef module);
[CCode (cname = "LLVMGetNextFunction")]
public static ValueRef next_function(ValueRef function);
[CCode (cname = "LLVMSetVolatile")]
public static void set_volatile(ValueRef value, int volatile_value);
[CCode (cname = "LLVMBuildPtrToInt")]
public static ValueRef build_ptr_to_int(BuilderRef builder, ValueRef value, TypeRef destination, string name);
[CCode (cname = "LLVMCanValueUseFastMathFlags")]
public static int can_use_fast_math_flags(ValueRef instruction);
[CCode (cname = "LLVMSetFastMathFlags")]
public static void set_fast_math_flags(ValueRef instruction, uint flags);
[CCode (cname = "LLVMGetFastMathFlags")]
public static uint get_fast_math_flags(ValueRef instruction);
[CCode (cname = "LLVMGetFCmpPredicate")]
public static RealPredicate real_predicate(ValueRef instruction);
[SimpleType]
[CCode (cname = "LLVMContextRef", has_type_id = false)]
public struct ContextRef {}

[SimpleType]
[CCode (cname = "LLVMModuleRef", has_type_id = false)]
public struct ModuleRef {}

[SimpleType]
[CCode (cname = "LLVMTypeRef", has_type_id = false)]
public struct TypeRef {}

[SimpleType]
[CCode (cname = "LLVMValueRef", has_type_id = false)]
public struct ValueRef {}

[SimpleType]
[CCode (cname = "LLVMUseRef", has_type_id = false)]
public struct UseRef {}
[CCode (cname = "LLVMGetFirstUse")]
public static UseRef first_use(ValueRef value);
[CCode (cname = "LLVMGetNextUse")]
public static UseRef next_use(UseRef use);
[CCode (cname = "LLVMGetUser")]
public static ValueRef user(UseRef use);

[SimpleType]
[CCode (cname = "LLVMAttributeRef", has_type_id = false)]
public struct AttributeRef {}

[CCode (cname = "LLVMGetNamedGlobal")]
public static ValueRef named_global(ModuleRef module, string name);
[CCode (cname = "LLVMAddGlobal")]
public static ValueRef add_global(ModuleRef module, TypeRef type, string name);
[CCode (cname = "LLVMGetInitializer")]
public static ValueRef get_initializer(ValueRef global);
[CCode (cname = "LLVMIsGlobalConstant")]
public static int is_global_constant(ValueRef global);
[CCode (cname = "LLVMSetInitializer")]
public static void set_initializer(ValueRef global, ValueRef initializer);
[CCode (cname = "LLVMSetGlobalConstant")]
public static void set_global_constant(ValueRef global, int constant);
[CCode (cname = "LLVMConstArray2")]
public static ValueRef const_array(TypeRef element, ValueRef* values, uint64 count);
[CCode (cname = "LLVMConstStructInContext")]
public static ValueRef const_struct(ContextRef context, ValueRef* values, uint count, int packed);
[CCode (cname = "LLVMCreateStringAttribute")]
public static AttributeRef create_string_attribute(ContextRef context, string key, uint key_length, string value, uint value_length);

[CCode (cname = "LLVMGetEnumAttributeKindForName")]
public static uint enum_attribute_kind(string name, size_t length);
[CCode (cname = "LLVMCreateEnumAttribute")]
public static AttributeRef create_enum_attribute(ContextRef context, uint kind, uint64 value);
[CCode (cname = "LLVMCreateTypeAttribute")]
public static AttributeRef create_type_attribute(ContextRef context, uint kind, TypeRef type);
[CCode (cname = "LLVMAddAttributeAtIndex")]
public static void add_attribute(ValueRef function, uint index, AttributeRef attribute);
[CCode (cname = "LLVMGetAttributeCountAtIndex")]
public static uint attribute_count(ValueRef function, uint index);
[CCode (cname = "LLVMGetCallSiteAttributeCount")]
public static uint call_attribute_count(ValueRef instruction, uint index);
[CCode (cname = "LLVMGetCallSiteEnumAttribute")]
public static AttributeRef call_enum_attribute(ValueRef call, uint index, uint kind);
[CCode (cname = "LLVMGetEnumAttributeAtIndex")]
public static AttributeRef enum_attribute(ValueRef function, uint index, uint kind);
[CCode (cname = "LLVMGetTypeAttributeValue")]
public static TypeRef type_attribute_value(AttributeRef attribute);
[CCode (cname = "LLVMGetEnumAttributeValue")]
public static uint64 enum_attribute_value(AttributeRef attribute);
[CCode (cname = "LLVMAddCallSiteAttribute")]
public static void add_call_attribute(ValueRef call, uint index, AttributeRef attribute);

[SimpleType]
[CCode (cname = "LLVMBasicBlockRef", has_type_id = false)]
public struct BasicBlockRef {}

[SimpleType]
[CCode (cname = "LLVMBuilderRef", has_type_id = false)]
public struct BuilderRef {}

[CCode (cname = "LLVMVerifierFailureAction", has_type_id = false)]
public enum VerifierFailureAction {
	[CCode (cname = "LLVMReturnStatusAction")]
	RETURN_STATUS
}

[CCode (cname = "LLVMOpcode", has_type_id = false)]
public enum Opcode {
	[CCode (cname = "LLVMAtomicCmpXchg")]
	ATOMIC_CMP_XCHG,
	[CCode (cname = "LLVMAtomicRMW")]
	ATOMIC_RMW,
	[CCode (cname = "LLVMAlloca")]
	ALLOCA,
	[CCode (cname = "LLVMLoad")]
	LOAD,
	[CCode (cname = "LLVMStore")]
	STORE,
	[CCode (cname = "LLVMGetElementPtr")]
	GEP,
	[CCode (cname = "LLVMRet")]
	RET,
	[CCode (cname = "LLVMSwitch")]
	SWITCH,
	[CCode (cname = "LLVMBr")]
	BR,
	[CCode (cname = "LLVMUnreachable")]
	UNREACHABLE,
	[CCode (cname = "LLVMAdd")]
	ADD,
	[CCode (cname = "LLVMSub")]
	SUB,
	[CCode (cname = "LLVMMul")]
	MUL,
	[CCode (cname = "LLVMSDiv")]
	SDIV,
	[CCode (cname = "LLVMSRem")]
	SREM,
	[CCode (cname = "LLVMAnd")]
	AND,
	[CCode (cname = "LLVMXor")]
	XOR,
	[CCode (cname = "LLVMFCmp")]
	FCMP,
	[CCode (cname = "LLVMFMul")]
	FMUL,
	[CCode (cname = "LLVMICmp")]
	ICMP,
	[CCode (cname = "LLVMPHI")]
	PHI,
	[CCode (cname = "LLVMSelect")]
	SELECT,
	[CCode (cname = "LLVMCall")]
	CALL,
	[CCode (cname = "LLVMExtractValue")]
	EXTRACT_VALUE,
	[CCode (cname = "LLVMInsertValue")]
	INSERT_VALUE,
	[CCode (cname = "LLVMZExt")]
	ZEXT,
	[CCode (cname = "LLVMTrunc")]
	TRUNC,
	[CCode (cname = "LLVMSExt")]
	SEXT,
	[CCode (cname = "LLVMBitCast")]
	BITCAST
}

[CCode (cname = "LLVMLinkage", has_type_id = false)]
public enum Linkage {
	[CCode (cname = "LLVMLinkOnceODRLinkage")]
	LINK_ONCE_ODR,
	[CCode (cname = "LLVMExternalLinkage")]
	EXTERNAL,
	[CCode (cname = "LLVMInternalLinkage")]
	INTERNAL,
	[CCode (cname = "LLVMPrivateLinkage")]
	PRIVATE
}

[CCode (cname = "LLVMCallConv", has_type_id = false)]
public enum CallConv {
	[CCode (cname = "LLVMCCallConv")]
	C,
	[CCode (cname = "LLVMFastCallConv")]
	FAST
}

[CCode (cname = "LLVMIntPredicate", has_type_id = false)]
public enum IntPredicate {
	[CCode (cname = "LLVMIntEQ")]
	EQ,
	[CCode (cname = "LLVMIntNE")]
	NE,
	[CCode (cname = "LLVMIntULT")]
	ULT,
	[CCode (cname = "LLVMIntULE")]
	ULE,
	[CCode (cname = "LLVMIntUGT")]
	UGT,
	[CCode (cname = "LLVMIntUGE")]
	UGE,
	[CCode (cname = "LLVMIntSLT")]
	SLT,
	[CCode (cname = "LLVMIntSLE")]
	SLE,
	[CCode (cname = "LLVMIntSGT")]
	SGT,
	[CCode (cname = "LLVMIntSGE")]
	SGE
}

[CCode (cname = "LLVMRealPredicate", has_type_id = false)]
public enum RealPredicate {
	[CCode (cname = "LLVMRealOEQ")]
	OEQ,
	[CCode (cname = "LLVMRealUNE")]
	UNE,
	[CCode (cname = "LLVMRealOLT")]
	OLT,
	[CCode (cname = "LLVMRealOLE")]
	OLE,
	[CCode (cname = "LLVMRealOGT")]
	OGT,
	[CCode (cname = "LLVMRealOGE")]
	OGE
}

[CCode (cname = "LLVMDoubleTypeInContext")]
public static TypeRef double_type_in_context(ContextRef context);
[CCode (cname = "LLVMBuildSIToFP")]
public static ValueRef build_sitofp(BuilderRef builder, ValueRef value, TypeRef destination, string name);
[CCode (cname = "LLVMBuildUIToFP")]
public static ValueRef build_uitofp(BuilderRef builder, ValueRef value, TypeRef destination, string name);
[CCode (cname = "LLVMBuildFPToSI")]
public static ValueRef build_fptosi(BuilderRef builder, ValueRef value, TypeRef destination, string name);
[CCode (cname = "LLVMBuildFPToUI")]
public static ValueRef build_fptoui(BuilderRef builder, ValueRef value, TypeRef destination, string name);
[CCode (cname = "LLVMBuildFPExt")]
public static ValueRef build_fpext(BuilderRef builder, ValueRef value, TypeRef destination, string name);
[CCode (cname = "LLVMBuildFPTrunc")]
public static ValueRef build_fptrunc(BuilderRef builder, ValueRef value, TypeRef destination, string name);
[CCode (cname = "LLVMFloatTypeInContext")]
public static TypeRef float_type_in_context(ContextRef context);
[CCode (cname = "LLVMConstBitCast")]
public static ValueRef const_bit_cast(ValueRef value, TypeRef type);
[CCode (cname = "LLVMBuildFNeg")]
public static ValueRef build_fneg(BuilderRef builder, ValueRef value, string name);
[CCode (cname = "LLVMBuildFAdd")]
public static ValueRef build_fadd(BuilderRef builder, ValueRef left, ValueRef right, string name);
[CCode (cname = "LLVMBuildFSub")]
public static ValueRef build_fsub(BuilderRef builder, ValueRef left, ValueRef right, string name);
[CCode (cname = "LLVMBuildFMul")]
public static ValueRef build_fmul(BuilderRef builder, ValueRef left, ValueRef right, string name);
[CCode (cname = "LLVMBuildFDiv")]
public static ValueRef build_fdiv(BuilderRef builder, ValueRef left, ValueRef right, string name);
[CCode (cname = "LLVMBuildFCmp")]
public static ValueRef build_fcmp(BuilderRef builder, RealPredicate predicate, ValueRef left, ValueRef right, string name);

[CCode (cname = "LLVMContextCreate")]
public static ContextRef context_create();
[CCode (cname = "LLVMContextDispose")]
public static void context_dispose(ContextRef context);
[CCode (cname = "LLVMModuleCreateWithNameInContext")]
public static ModuleRef module_create_with_name_in_context(string name, ContextRef context);
[CCode (cname = "LLVMGetModuleContext")]
public static ContextRef module_context(ModuleRef module);
[CCode (cname = "LLVMDisposeModule")]
public static void dispose_module(ModuleRef module);
[CCode (cname = "LLVMPointerTypeInContext")]
public static TypeRef pointer_type_in_context(ContextRef context, uint address_space);
[CCode (cname = "LLVMConstPointerNull")]
public static ValueRef const_pointer_null(TypeRef pointer_type);
[CCode (cname = "LLVMIntTypeInContext")]
public static TypeRef int_type_in_context(ContextRef context, uint bits);
[CCode (cname = "LLVMInt32TypeInContext")]
public static TypeRef int32_type_in_context(ContextRef context);
[CCode (cname = "LLVMInt1TypeInContext")]
public static TypeRef int1_type_in_context(ContextRef context);
[CCode (cname = "LLVMVoidTypeInContext")]
public static TypeRef void_type_in_context(ContextRef context);
[CCode (cname = "LLVMStructTypeInContext")]
public static TypeRef struct_type_in_context(ContextRef context, TypeRef* elements, uint count, int packed);
[CCode (cname = "LLVMBuildInsertValue")]
public static ValueRef build_insert_value(BuilderRef builder, ValueRef aggregate, ValueRef element, uint index, string name);
[CCode (cname = "LLVMBuildExtractValue")]
public static ValueRef build_extract_value(BuilderRef builder, ValueRef aggregate, uint index, string name);
[CCode (cname = "LLVMGetNumIndices")]
public static uint index_count(ValueRef instruction);
[CCode (cname = "LLVMGetIndices", type = "const unsigned*")]
public static unowned uint* indices(ValueRef instruction);
[CCode (cname = "LLVMStructCreateNamed")]
public static TypeRef struct_create_named(ContextRef context, string name);
[CCode (cname = "LLVMVectorType")]
public static TypeRef vector_type(TypeRef element, uint lanes);
[CCode (cname = "LLVMConstNull")]
public static ValueRef const_null(TypeRef type);
[CCode (cname = "LLVMConstAllOnes")]
public static ValueRef const_all_ones(TypeRef type);
[CCode (cname = "LLVMConstVector")]
public static ValueRef const_vector(ValueRef* lanes, uint count);
[CCode (cname = "LLVMIsConstant")]
public static int is_constant(ValueRef value);
[CCode (cname = "LLVMBuildInsertElement")]
public static ValueRef build_insert_element(BuilderRef builder, ValueRef vector, ValueRef lane, ValueRef index, string name);
[CCode (cname = "LLVMBuildSExt")]
public static ValueRef build_sext(BuilderRef builder, ValueRef value, TypeRef destination, string name);
[CCode (cname = "LLVMBuildZExt")]
public static ValueRef build_zext(BuilderRef builder, ValueRef value, TypeRef destination, string name);
[CCode (cname = "LLVMBuildTrunc")]
public static ValueRef build_trunc(BuilderRef builder, ValueRef value, TypeRef destination, string name);
[CCode (cname = "LLVMBuildBitCast")]
public static ValueRef build_bit_cast(BuilderRef builder, ValueRef value, TypeRef destination, string name);
[CCode (cname = "LLVMBuildExtractElement")]
public static ValueRef build_extract_element(BuilderRef builder, ValueRef vector, ValueRef index, string name);
[CCode (cname = "LLVMBuildShuffleVector")]
public static ValueRef build_shuffle_vector(BuilderRef builder, ValueRef first, ValueRef second, ValueRef selectors, string name);
[CCode (cname = "LLVMBuildSelect")]
public static ValueRef build_select(BuilderRef builder, ValueRef mask, ValueRef true_value, ValueRef false_value, string name);
[CCode (cname = "LLVMBuildOr")]
public static ValueRef build_or(BuilderRef builder, ValueRef left, ValueRef right, string name);
[CCode (cname = "LLVMCountStructElementTypes")]
public static uint count_struct_element_types(TypeRef type);
[CCode (cname = "LLVMStructGetTypeAtIndex")]
public static TypeRef struct_get_type_at_index(TypeRef type, uint index);
[CCode (cname = "LLVMIsPackedStruct")]
public static int is_packed_struct(TypeRef type);
[CCode (cname = "LLVMStructSetBody")]
public static void struct_set_body(TypeRef type, TypeRef* fields, uint count, int packed);
[CCode (cname = "LLVMSizeOf")]
public static ValueRef size_of(TypeRef type);
[CCode (cname = "LLVMGetAlignment")]
public static uint get_alignment(ValueRef value);
[CCode (cname = "LLVMSetAlignment")]
public static void set_alignment(ValueRef value, uint alignment);
[CCode (cname = "LLVMBuildAlloca")]
public static ValueRef build_alloca(BuilderRef builder, TypeRef type, string name);
[CCode (cname = "LLVMStructGetTypeAtIndex")]
public static TypeRef struct_type_at_index(TypeRef type, uint index);
[CCode (cname = "LLVMBuildStructGEP2")]
public static ValueRef build_struct_gep(BuilderRef builder, TypeRef type, ValueRef pointer, uint field, string name);
[CCode (cname = "LLVMBuildLoad2")]
public static ValueRef build_load(BuilderRef builder, TypeRef type, ValueRef pointer, string name);
[CCode (cname = "LLVMBuildStore")]
public static ValueRef build_store(BuilderRef builder, ValueRef value, ValueRef pointer);
[CCode (cname = "LLVMFunctionType")]
public static TypeRef function_type(TypeRef return_type, TypeRef* parameter_types, uint parameter_count, int is_var_arg);
[CCode (cname = "LLVMAddFunction")]
public static ValueRef add_function(ModuleRef module, string name, TypeRef function_type);
[CCode (cname = "LLVMSetLinkage")]
public static void set_linkage(ValueRef function, Linkage linkage);
[CCode (cname = "LLVMVisibility", has_type_id = false)]
public enum Visibility {
	[CCode (cname = "LLVMDefaultVisibility")] DEFAULT,
	[CCode (cname = "LLVMHiddenVisibility")] HIDDEN,
	[CCode (cname = "LLVMProtectedVisibility")] PROTECTED
}
[CCode (cname = "LLVMSetVisibility")]
public static void set_visibility(ValueRef value, Visibility visibility);
[CCode (cname = "LLVMGetVisibility")]
public static Visibility get_visibility(ValueRef value);
[CCode (cname = "LLVMSetFunctionCallConv")]
public static void set_function_call_conv(ValueRef function, uint convention);
[CCode (cname = "LLVMGetParam")]
public static ValueRef get_param(ValueRef function, uint index);
[CCode (cname = "LLVMSetValueName2")]
public static void set_value_name(ValueRef value, string name, size_t length);
[CCode (cname = "LLVMTypeOf")]
public static TypeRef type_of(ValueRef value);
[CCode (cname = "LLVMAppendBasicBlockInContext")]
public static BasicBlockRef append_basic_block_in_context(ContextRef context, ValueRef function, string name);
[CCode (cname = "LLVMCountBasicBlocks")]
public static uint count_basic_blocks(ValueRef function);
[CCode (cname = "LLVMCreateBuilderInContext")]
public static BuilderRef create_builder_in_context(ContextRef context);
[CCode (cname = "LLVMPositionBuilderAtEnd")]
public static void position_builder_at_end(BuilderRef builder, BasicBlockRef block);
[CCode (cname = "LLVMConstInt")]
public static ValueRef const_int(TypeRef int_type, uint64 value, int sign_extend);
[CCode (cname = "LLVMIsAConstantInt")]
public static ValueRef is_constant_int(ValueRef value);
[CCode (cname = "LLVMConstIntGetSExtValue")]
public static int64 constant_signed(ValueRef value);
[CCode (cname = "LLVMBuildRet")]
public static ValueRef build_ret(BuilderRef builder, ValueRef value);
[CCode (cname = "LLVMBuildRetVoid")]
public static ValueRef build_ret_void(BuilderRef builder);
[CCode (cname = "LLVMBuildBr")]
public static ValueRef build_br(BuilderRef builder, BasicBlockRef target);
[CCode (cname = "LLVMBuildCondBr")]
public static ValueRef build_cond_br(BuilderRef builder, ValueRef condition, BasicBlockRef true_block, BasicBlockRef false_block);
[CCode (cname = "LLVMBuildUnreachable")]
public static ValueRef build_unreachable(BuilderRef builder);
[CCode (cname = "LLVMBuildSwitch")]
public static ValueRef build_switch(BuilderRef builder, ValueRef value, BasicBlockRef fallback, uint count);
[CCode (cname = "LLVMGetInsertBlock")]
public static BasicBlockRef insert_block(BuilderRef builder);
[CCode (cname = "LLVMGetLastInstruction")]
public static ValueRef last_instruction(BasicBlockRef block);
[CCode (cname = "LLVMAddCase")]
public static void add_case(ValueRef dispatch, ValueRef tag, BasicBlockRef target);
[CCode (cname = "LLVMBuildMemSet")]
public static ValueRef build_mem_set(BuilderRef builder, ValueRef destination, ValueRef byte, ValueRef length, uint alignment);
[CCode (cname = "LLVMBuildMemCpy")]
public static ValueRef build_mem_copy(BuilderRef builder, ValueRef destination, uint destination_alignment, ValueRef source, uint source_alignment, ValueRef length);
[CCode (cname = "LLVMBuildPhi")]
public static ValueRef build_phi(BuilderRef builder, TypeRef type, string name);
[CCode (cname = "LLVMAddIncoming")]
public static void add_incoming(ValueRef phi, ValueRef* values, BasicBlockRef* blocks, uint count);
[CCode (cname = "LLVMCountIncoming")]
public static uint incoming_count(ValueRef phi);
[CCode (cname = "LLVMGetIncomingBlock")]
public static BasicBlockRef incoming_block(ValueRef phi, uint index);
[CCode (cname = "LLVMArrayType2")]
public static TypeRef array_type(TypeRef element, uint64 length);
[CCode (cname = "LLVMBuildGEP2")]
public static ValueRef build_gep(BuilderRef builder, TypeRef type, ValueRef pointer, ValueRef* indices, uint count, string name);
[CCode (cname = "LLVMBuildAdd")]
public static ValueRef build_add(BuilderRef builder, ValueRef left, ValueRef right, string name);
[CCode (cname = "LLVMBuildSub")]
public static ValueRef build_sub(BuilderRef builder, ValueRef left, ValueRef right, string name);
[CCode (cname = "LLVMBuildMul")]
public static ValueRef build_mul(BuilderRef builder, ValueRef left, ValueRef right, string name);
[CCode (cname = "LLVMBuildUDiv")]
public static ValueRef build_udiv(BuilderRef builder, ValueRef left, ValueRef right, string name);
[CCode (cname = "LLVMBuildURem")]
public static ValueRef build_urem(BuilderRef builder, ValueRef left, ValueRef right, string name);
[CCode (cname = "LLVMBuildSDiv")]
public static ValueRef build_sdiv(BuilderRef builder, ValueRef left, ValueRef right, string name);
[CCode (cname = "LLVMBuildSRem")]
public static ValueRef build_srem(BuilderRef builder, ValueRef left, ValueRef right, string name);
[CCode (cname = "LLVMBuildAnd")]
public static ValueRef build_and(BuilderRef builder, ValueRef left, ValueRef right, string name);
[CCode (cname = "LLVMBuildShl")]
public static ValueRef build_shl(BuilderRef builder, ValueRef left, ValueRef right, string name);
[CCode (cname = "LLVMBuildAShr")]
public static ValueRef build_ashr(BuilderRef builder, ValueRef left, ValueRef right, string name);
[CCode (cname = "LLVMBuildLShr")]
public static ValueRef build_lshr(BuilderRef builder, ValueRef left, ValueRef right, string name);
[CCode (cname = "LLVMBuildXor")]
public static ValueRef build_xor(BuilderRef builder, ValueRef left, ValueRef right, string name);
[CCode (cname = "LLVMBuildICmp")]
public static ValueRef build_icmp(BuilderRef builder, IntPredicate predicate, ValueRef left, ValueRef right, string name);
[CCode (cname = "LLVMBuildCall2")]
public static ValueRef build_call(BuilderRef builder, TypeRef signature, ValueRef function, ValueRef* arguments, uint count, string name);
[CCode (cname = "LLVMSetInstructionCallConv")]
public static void set_instruction_call_conv(ValueRef call, uint convention);
[CCode (cname = "LLVMGetIntrinsicID")]
public static uint intrinsic_id(ValueRef function);
[CCode (cname = "LLVMLookupIntrinsicID")]
public static uint lookup_intrinsic_id(string name, size_t length);
[CCode (cname = "LLVMGetIntrinsicDeclaration")]
public static ValueRef get_intrinsic_declaration(ModuleRef module, uint id, TypeRef* types, size_t count);
[CCode (cname = "LLVMIntrinsicGetType")]
public static TypeRef intrinsic_get_type(ContextRef context, uint id, TypeRef* types, size_t count);
[CCode (cname = "LLVMDisposeBuilder")]
public static void dispose_builder(BuilderRef builder);
[CCode (cname = "LLVMVerifyModule")]
public static int verify_module(ModuleRef module, VerifierFailureAction action, out char* message);
[CCode (cname = "LLVMDisposeMessage")]
public static void dispose_message(char* message);
[CCode (cname = "LLVMPrintModuleToString")]
public static char* print_module_to_string(ModuleRef module);

[CCode (cname = "LLVMGetLinkage")]
public static Linkage get_linkage(ValueRef function);
[CCode (cname = "LLVMGetFunctionCallConv")]
public static uint function_call_conv(ValueRef function);
[CCode (cname = "LLVMGlobalGetValueType")]
public static TypeRef global_value_type(ValueRef function);
[CCode (cname = "LLVMGetFirstBasicBlock")]
public static BasicBlockRef first_block(ValueRef function);
[CCode (cname = "LLVMGetCalledValue")]
public static ValueRef called_value(ValueRef call);
[CCode (cname = "LLVMGetInstructionCallConv")]
public static uint instruction_call_conv(ValueRef call);
[CCode (cname = "LLVMGetCalledFunctionType")]
public static TypeRef called_function_type(ValueRef call);
[CCode (cname = "LLVMGetValueName2")]
public static unowned string value_name(ValueRef value, out size_t length);

[CCode (cname = "LLVMCountParams")]
public static uint count_params(ValueRef function);
[CCode (cname = "LLVMGetNextBasicBlock")]
public static BasicBlockRef next_block(BasicBlockRef block);
[CCode (cname = "LLVMGetFirstInstruction")]
public static ValueRef first_instruction(BasicBlockRef block);
[CCode (cname = "LLVMGetNextInstruction")]
public static ValueRef next_instruction(ValueRef instruction);
[CCode (cname = "LLVMGetOperand")]
public static ValueRef operand(ValueRef value, uint index);
[CCode (cname = "LLVMGetNamedFunction")]
public static ValueRef named_function(ModuleRef module, string name);
[CCode (cname = "LLVMGetNumOperands")]
public static int operand_count(ValueRef value);
[CCode (cname = "LLVMGetNumArgOperands")]
public static uint argument_count(ValueRef call);
[CCode (cname = "LLVMGetInstructionParent")]
public static BasicBlockRef instruction_parent(ValueRef instruction);
[CCode (cname = "LLVMGetInstructionOpcode")]
public static Opcode opcode(ValueRef instruction);
[CCode (cname = "LLVMIsAInstruction")]
public static ValueRef is_instruction(ValueRef value);
[CCode (cname = "LLVMConstIntGetZExtValue")]
public static uint64 const_int_zext(ValueRef value);
[CCode (cname = "LLVMGetSwitchCaseValue")]
public static ValueRef switch_case_value(ValueRef instruction, uint index);
[CCode (cname = "LLVMGetGEPSourceElementType")]
public static TypeRef gep_source_type(ValueRef value);
[CCode (cname = "LLVMConstGEP2")]
public static ValueRef const_gep(TypeRef type, ValueRef root, ValueRef* indices, uint count);
[CCode (cname = "LLVMGetTypeContext")]
public static ContextRef type_context(TypeRef type);
[CCode (cname = "LLVMGetAllocatedType")]
public static TypeRef allocated_type(ValueRef value);
[CCode (cname = "LLVMGetVolatile")]
public static int get_volatile(ValueRef instruction);
[CCode (cname = "LLVMGetOrdering")]
public static int get_ordering(ValueRef instruction);
[CCode (cname = "LLVMIsAConstantPointerNull")]
public static ValueRef is_constant_pointer_null(ValueRef value);
[CCode (cname = "LLVMGetEntryBasicBlock")]
public static BasicBlockRef entry_block(ValueRef function);
[CCode (cname = "LLVMGetBasicBlockTerminator")]
public static ValueRef block_terminator(BasicBlockRef block);
[CCode (cname = "LLVMGetICmpPredicate")]
public static IntPredicate predicate(ValueRef instruction);
[CCode (cname = "LLVMGetNumSuccessors")]
public static uint successor_count(ValueRef terminator);
[CCode (cname = "LLVMGetSuccessor")]
public static BasicBlockRef successor(ValueRef terminator, uint index);
[CCode (cname = "LLVMGetCondition")]
public static ValueRef condition(ValueRef branch);
[CCode (cname = "LLVMGetBasicBlockParent")]
public static ValueRef block_parent(BasicBlockRef block);
}
