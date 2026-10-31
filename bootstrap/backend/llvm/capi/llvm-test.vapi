// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

// Structural inspection and malformed-test mutation APIs, excluded from astrac.
[CCode (cheader_filename = "llvm-c/Core.h,llvm-c/Analysis.h")]
namespace Astra.Backend.LLVM.CApi {
[CCode (cname = "LLVMDeleteFunction")]
public static void delete_function(ValueRef function);
[CCode (cname = "LLVMDeleteGlobal")]
public static void delete_global(ValueRef global);
[CCode (cname = "LLVMDeleteBasicBlock")]
public static void delete_basic_block(BasicBlockRef block);
[CCode (cname = "LLVMGetReturnType")]
public static TypeRef return_type(TypeRef signature);
[CCode (cname = "LLVMGetIntTypeWidth")]
public static uint int_width(TypeRef type);
[CCode (cname = "LLVMGetBasicBlockName")]
public static unowned string block_name(BasicBlockRef block);
[CCode (cname = "LLVMGetNSW")]
public static int get_nsw(ValueRef instruction);
[CCode (cname = "LLVMGetNUW")]
public static int get_nuw(ValueRef instruction);
[CCode (cname = "LLVMSetOperand")]
public static void set_operand(ValueRef value, uint index, ValueRef operand);
[CCode (cname = "LLVMRemoveEnumAttributeAtIndex")]
public static void remove_enum_attribute(ValueRef function, uint index, uint kind);
[CCode (cname = "LLVMRemoveCallSiteEnumAttribute")]
public static void remove_call_enum_attribute(ValueRef call, uint index, uint kind);
[CCode (cname = "LLVMSetSwitchCaseValue")]
public static void set_switch_case_value(ValueRef instruction, uint index, ValueRef value);
[CCode (cname = "LLVMSetSuccessor")]
public static void set_successor(ValueRef terminator, uint index, BasicBlockRef block);
[CCode (cname = "LLVMInstructionRemoveFromParent")]
public static void remove_instruction(ValueRef instruction);
[CCode (cname = "LLVMInstructionEraseFromParent")]
public static void erase_instruction(ValueRef instruction);
[CCode (cname = "LLVMInsertIntoBuilder")]
public static void insert_instruction(BuilderRef builder, ValueRef instruction);
}
