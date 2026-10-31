// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

[CCode (cheader_filename = "llvm-c/Core.h,llvm-c/Target.h")]
namespace Astra.Tests.VectorMemory.MemoryCApi {
[CCode (cname = "LLVMGetModuleDataLayout")]
public static Astra.Backend.LLVM.CApi.TargetDataRef module_data_layout(Astra.Backend.LLVM.CApi.ModuleRef module);
[CCode (cname = "LLVMABIAlignmentOfType")]
public static uint abi_alignment(Astra.Backend.LLVM.CApi.TargetDataRef data, Astra.Backend.LLVM.CApi.TypeRef type);
[CCode (cname = "LLVMGetAlignment")]
public static uint alignment(Astra.Backend.LLVM.CApi.ValueRef value);
[CCode (cname = "LLVMGetAllocatedType")]
public static Astra.Backend.LLVM.CApi.TypeRef allocated_type(Astra.Backend.LLVM.CApi.ValueRef value);
[CCode (cname = "LLVMIsAAllocaInst")]
public static Astra.Backend.LLVM.CApi.ValueRef is_alloca(Astra.Backend.LLVM.CApi.ValueRef value);
[CCode (cname = "LLVMIsALoadInst")]
public static Astra.Backend.LLVM.CApi.ValueRef is_load(Astra.Backend.LLVM.CApi.ValueRef value);
[CCode (cname = "LLVMIsAStoreInst")]
public static Astra.Backend.LLVM.CApi.ValueRef is_store(Astra.Backend.LLVM.CApi.ValueRef value);
}
