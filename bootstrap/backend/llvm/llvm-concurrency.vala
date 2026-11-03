// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.NativeAbi;

namespace Astra.Backend.LLVM {
internal class LlvmConcurrencyRuntime : Object {
	internal static CApi.ValueRef singleton_key(LlvmModuleArtifact artifact, string owner) throws LlvmError {
		string name = "astra.singleton.key." + owner;
		var prior = CApi.named_global (artifact.module, name);
		if ((void*) prior != null) {
			return prior;
		}
		var byte = CApi.int_type_in_context (artifact.context, 8);
		var data = owner.data;
		var values = new CApi.ValueRef[data.length + 1];
		for (int i = 0; i < data.length; i++) {
			values[i] = CApi.const_int (byte, data[i], 0);
		}
		values[data.length] = CApi.const_null (byte);
		var initializer = CApi.const_array (byte, values, values.length);
		var value = CApi.add_global (artifact.module, CApi.type_of (initializer), name);
		CApi.set_linkage (value, CApi.Linkage.PRIVATE);
		CApi.set_global_constant (value, 1);
		CApi.set_initializer (value, initializer);
		artifact.class_globals.add (new LlvmClassGlobalBinding (value, initializer));
		return value;
	}

	internal static CApi.ValueRef call(LlvmModuleArtifact artifact, CApi.BuilderRef builder, string name, CApi.TypeRef result_type, CApi.TypeRef[]? parameters, CApi.ValueRef[]? arguments) throws LlvmError {
		var signature = CApi.function_type (result_type, parameters, parameters.length, 0);
		var target = CApi.named_function (artifact.module, name);
		var original = (void*) artifact.concurrency_symbols.lookup (name);
		if (original == null) {
			if ((void*) target != null) {
				throw new LlvmError.LOWERING ("concurrency runtime conflicts with a source-declared symbol");
			}
			target = CApi.add_function (artifact.module, name, signature);
			CApi.set_function_call_conv (target, CApi.CallConv.C);
			artifact.concurrency_symbols.insert (name, (void*) target);
		} else if ((void*) target != original) {
			throw new LlvmError.LOWERING ("concurrency runtime lost its admitted provider");
		}
		if ((void*) CApi.global_value_type (target) != (void*) signature || CApi.function_call_conv (target) != CApi.CallConv.C || CApi.count_basic_blocks (target) != 0) {
			throw new LlvmError.LOWERING ("concurrency runtime lost its exact C signature");
		}
		var result = CApi.build_call (builder, signature, target, arguments, arguments.length, (void*) result_type == (void*) CApi.void_type_in_context (artifact.context) ? "" : "concurrency.result");
		CApi.set_instruction_call_conv (result, CApi.CallConv.C);
		artifact.class_calls.add (new LlvmClassCallBinding (result, target, signature, arguments, CApi.CallConv.C, "admitted concurrency lifetime/guard operation"));
		return result;
	}

	internal static CApi.ValueRef member(LlvmModuleArtifact artifact, CApi.BuilderRef builder, CApi.ValueRef root, uint member, bool integer = false) {
		var pointer = CApi.pointer_type_in_context (artifact.context, 0);
		var count = CApi.int_type_in_context (artifact.context, 64);
		CApi.TypeRef[] fields = {
			pointer, pointer, count, count, pointer, count
		};
		var header = CApi.struct_type_in_context (artifact.context, fields, fields.length, 0);
		var address = CApi.build_struct_gep (builder, header, root, member, "concurrency.member");
		artifact.class_addresses.add (new LlvmClassAddressBinding (address, root, header, member));
		var type = integer ? count : pointer;
		var result = CApi.build_load (builder, type, address, "concurrency.state");
		artifact.class_values.add (new LlvmClassValueBinding (result, CApi.Opcode.LOAD, type, new CApi.ValueRef[] { address }, "immutable concurrency metadata read"));
		return result;
	}

}
}
