// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.NativeAbi;

namespace Astra.Backend.LLVM {
internal class LlvmArguments : Object {
	internal static void qualify(string triple) throws LlvmError {
		if (!(triple.has_prefix ("x86_64-") && triple.contains ("-linux-"))) {
			throw new LlvmError.TARGET ("native text-slice layout and hosted arguments are not qualified for target '%s'", triple);
		}
	}
	internal static void emit(LlvmModuleArtifact artifact) throws LlvmError {
		if (artifact.entry_kind != NativeEntryKind.TEXT_ARGUMENTS || artifact.text_slice_layout == null || !artifact.text_slice_layout.qualified ()) {
			throw new LlvmError.INVALID_INPUT ("hosted arguments require a verified entry plan and target descriptor layout");
		}
		var module = artifact.module;
		var context = artifact.context;
		foreach (string symbol in new string[] { NativeProgramEntryPlan.PREPARE_SYMBOL, NativeProgramEntryPlan.DISPOSE_SYMBOL }) {
			if ((void*) CApi.named_function (module, symbol) != null || (void*) CApi.named_global (module, symbol) != null) {
				throw new LlvmError.INVALID_INPUT ("private hosted argument symbol '%s' conflicts with a source boundary", symbol);
			}
		}
		var i32 = CApi.int32_type_in_context (context);
		var pointer = CApi.pointer_type_in_context (context, 0);
		CApi.TypeRef[] host_parameters = {
			i32, pointer
		};
		CApi.TypeRef[] prepare_parameters = {
			i32, pointer, pointer
		};
		CApi.TypeRef[] dispose_parameters = {
			pointer
		};
		var host_type = CApi.function_type (i32, host_parameters, 2, 0);
		var prepare_type = CApi.function_type (i32, prepare_parameters, 3, 0);
		var dispose_type = CApi.function_type (CApi.void_type_in_context (context), dispose_parameters, 1, 0);
		var prepare = CApi.add_function (module, NativeProgramEntryPlan.PREPARE_SYMBOL, prepare_type);
		var dispose = CApi.add_function (module, NativeProgramEntryPlan.DISPOSE_SYMBOL, dispose_type);
		var wrapper = CApi.add_function (module, "main", host_type);
		CApi.set_function_call_conv (wrapper, CApi.CallConv.C);
		var entry = CApi.append_basic_block_in_context (context, wrapper, "entry");
		var failure = CApi.append_basic_block_in_context (context, wrapper, "args.failure");
		var ready = CApi.append_basic_block_in_context (context, wrapper, "args.ready");
		var builder = CApi.create_builder_in_context (context);
		CApi.position_builder_at_end (builder, entry);
		if (artifact.debug_info != null) {
			artifact.debug_info.attach_launch (wrapper, builder);
		}
		var slot = CApi.build_alloca (builder, pointer, "args.output");
		CApi.build_store (builder, CApi.const_null (pointer), slot);
		CApi.ValueRef[] capture = {
			CApi.get_param (wrapper, 0), CApi.get_param (wrapper, 1), slot
		};
		var status = CApi.build_call (builder, prepare_type, prepare, capture, 3, "args.status");
		CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, status, CApi.const_int (i32, 0, 0), "args.valid"), ready, failure);
		CApi.position_builder_at_end (builder, failure);
		CApi.build_ret (builder, status);
		CApi.position_builder_at_end (builder, ready);
		var items = CApi.build_load (builder, pointer, slot, "args.items");
		CApi.ValueRef[] arguments = {
			items, CApi.get_param (wrapper, 0)
		};
		var result = CApi.build_call (builder, artifact.entry_type, artifact.entry_function, arguments, 2, "result");
		CApi.set_instruction_call_conv (result, LlvmLowering.CALL_CONVENTION);
		CApi.ValueRef[] release = {
			items
		};
		CApi.build_call (builder, dispose_type, dispose, release, 1, "");
		CApi.build_ret (builder, result);
		CApi.dispose_builder (builder);
	}
}
}
