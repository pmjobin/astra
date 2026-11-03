// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.NativeAbi;
namespace Astra.Backend.LLVM {
internal class LlvmCallbackCBoolBinding : Object {
	private CApi.ValueRef call;
	private bool is_call;
	private uint[] indices = null;
	internal bool requires_c_bool { get { return indices.length != 0; } }
	internal LlvmCallbackCBoolBinding.physical (LlvmModuleArtifact artifact, CApi.ValueRef value, uint[] indices, bool is_call) {
		call = value;
		this.is_call = is_call;
		this.indices = indices.copy ();
		foreach (uint index in indices) {
			var attribute = CApi.create_enum_attribute (artifact.context, CApi.enum_attribute_kind ("zeroext", 7), 0);
			if (is_call) {
				CApi.add_call_attribute (value, index, attribute);
			} else {
				CApi.add_attribute (value, index, attribute);
			}
		}
		artifact.requires_c_bool |= requires_c_bool;
	}
	internal LlvmCallbackCBoolBinding (LlvmModuleArtifact artifact, CApi.ValueRef call, ForeignValueType type, bool is_call = true) {
		this.call = call;
		this.is_call = is_call;
		if (type.callback_result.kind == ForeignValueKind.BOOL) {
			indices += 0;
		}
		for (uint p = 0; p < type.callback_parameter_count; p++) {
			if (type.callback_parameter (p).kind == ForeignValueKind.BOOL) {
				indices += p + 2;
			}
		}
		foreach (uint index in indices) {
			var attribute = CApi.create_enum_attribute (artifact.context, CApi.enum_attribute_kind ("zeroext", 7), 0);
			if (is_call) {
				CApi.add_call_attribute (call, index, attribute);
			} else {
				CApi.add_attribute (call, index, attribute);
			}
		}
		artifact.requires_c_bool |= requires_c_bool;
	}

	internal void verify() throws LlvmError {
		foreach (uint index in indices) {
			var attribute = is_call ? CApi.call_enum_attribute (call, index, CApi.enum_attribute_kind ("zeroext", 7)) : CApi.enum_attribute (call, index, CApi.enum_attribute_kind ("zeroext", 7));
			if ((void*) attribute == null || CApi.enum_attribute_value (attribute) != 0) {
				throw new LlvmError.VERIFICATION ("typed C callback lost exact C99 bool extension");
			}
		}
	}

}
// Native Callback values point at a call-scoped {native code, opaque context}
// view. Foreign adapters construct their own checked views of this same type.
internal class LlvmCallbackRuntime : Object {
	private LlvmModuleArtifact artifact;
	private LlvmTypeMapper types;
	private CApi.TypeRef pointer;
	private CApi.TypeRef layout;
	internal LlvmCallbackRuntime (LlvmModuleArtifact artifact, LlvmTypeMapper types) throws LlvmError {
		this.artifact = artifact;
		this.types = types;
		pointer = types.scalar (NativeScalarType.PTR);
		CApi.TypeRef[] fields = {
			pointer, pointer
		};
		layout = CApi.struct_type_in_context (artifact.context, fields, fields.length, 0);
		artifact.class_layouts.add (new LlvmClassLayoutBinding (layout, fields));
	}

	private CApi.TypeRef code_type(CallbackType signature) throws LlvmError, NativeAbiError {
		var parameters = new CApi.TypeRef[signature.parameter_types.length + 1];
		parameters[0] = pointer;
		for (int p = 0; p < signature.parameter_types.length; p++) {
			parameters[p + 1] = types.value_type (signature.parameter_types[p]);
		}
		return CApi.function_type (types.callable_result_type (signature), parameters, parameters.length, 0);
	}

	private CApi.ValueRef read(CApi.BuilderRef builder, CApi.ValueRef carrier, uint member) {
		var address = CApi.build_struct_gep (builder, layout, carrier, member, "callback.member");
		artifact.class_addresses.add (new LlvmClassAddressBinding (address, carrier, layout, member));
		var result = CApi.build_load (builder, pointer, address, "callback.component");
		CApi.ValueRef[] operands = {
			address
		};
		artifact.class_values.add (new LlvmClassValueBinding (result, CApi.Opcode.LOAD, pointer, operands, "exact callback code/context component"));
		return result;
	}

	private CApi.ValueRef write(CApi.BuilderRef builder, CApi.ValueRef carrier, uint member, CApi.ValueRef value) {
		var address = CApi.build_struct_gep (builder, layout, carrier, member, "callback.member");
		artifact.class_addresses.add (new LlvmClassAddressBinding (address, carrier, layout, member));
		var result = CApi.build_store (builder, value, address);
		CApi.ValueRef[] operands = {
			value, address
		};
		artifact.class_values.add (new LlvmClassValueBinding (result, CApi.Opcode.STORE, CApi.void_type_in_context (artifact.context), operands, "exact callback code/context publication"));
		return result;
	}

	private CApi.TypeRef foreign_code_type(ForeignValueType signature) throws LlvmError {
		var parameters = new CApi.TypeRef[signature.callback_parameter_count + 1];
		parameters[0] = pointer;
		for (uint p = 0; p < signature.callback_parameter_count; p++) {
			parameters[p + 1] = types.scalar (NativeForeignApi.scalar (signature.callback_parameter (p).kind));
		}
		var result = signature.callback_result.kind == ForeignValueKind.VOID ? CApi.void_type_in_context (artifact.context) : types.scalar (NativeForeignApi.scalar (signature.callback_result.kind));
		return CApi.function_type (result, parameters, parameters.length, 0);
	}

	private CApi.ValueRef from_c_thunk(ForeignValueType signature) throws LlvmError {
		string name = "astra.callback.from.c." + Checksum.compute_for_string (ChecksumType.SHA256, signature.identity ());
		var prior = (void*) artifact.retained_helpers.lookup (name);
		if (prior != null) {
			return (CApi.ValueRef) prior;
		}
		if ((void*) CApi.named_function (artifact.module, name) != null) {
			throw new LlvmError.LOWERING ("typed C callback thunk conflicts with a source symbol");
		}
		var type = foreign_code_type (signature);
		var thunk = CApi.add_function (artifact.module, name, type);
		CApi.set_linkage (thunk, CApi.Linkage.INTERNAL);
		CApi.set_function_call_conv (thunk, LlvmLowering.CALL_CONVENTION);
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_at_end (builder, CApi.append_basic_block_in_context (artifact.context, thunk, "entry"));
		var code = read (builder, CApi.get_param (thunk, 0), 0);
		var data = read (builder, CApi.get_param (thunk, 0), 1);
		var arguments = new CApi.ValueRef[signature.callback_parameter_count + 1];
		arguments[0] = data;
		for (uint p = 0; p < signature.callback_parameter_count; p++) {
			arguments[p + 1] = CApi.get_param (thunk, p + 1);
		}
		var call = CApi.build_call (builder, type, code, arguments, arguments.length, signature.callback_result.kind == ForeignValueKind.VOID ? "" : "callback.c.result");
		CApi.set_instruction_call_conv (call, CApi.CallConv.C);
		artifact.class_calls.add (new LlvmClassCallBinding (call, code, type, arguments, CApi.CallConv.C, "typed synchronous C callback and original userdata"));
		artifact.callback_c_bool.add (new LlvmCallbackCBoolBinding (artifact, call, signature));
		if (signature.callback_result.kind == ForeignValueKind.VOID) {
			CApi.build_ret_void (builder);
		} else {
			CApi.build_ret (builder, call);
		}
		CApi.dispose_builder (builder);
		artifact.retained_helpers.insert (name, (void*) thunk);
		artifact.concurrency_guards.add (new LlvmSumSequence (thunk, true));
		return thunk;
	}

	internal CApi.ValueRef from_c(CApi.BuilderRef builder, ForeignValueType signature, CApi.ValueRef code, CApi.ValueRef data, bool nullable) throws LlvmError {
		var context = CApi.build_alloca (builder, layout, "callback.c.context");
		write (builder, context, 0, code);
		write (builder, context, 1, data);
		var view = CApi.build_alloca (builder, layout, "callback.native.view");
		write (builder, view, 0, from_c_thunk (signature));
		write (builder, view, 1, context);
		if (!nullable) {
			return view;
		}
		var empty = CApi.build_icmp (builder, CApi.IntPredicate.EQ, code, CApi.const_null (pointer), "callback.null");
		CApi.ValueRef[] operands = {
			code, CApi.const_null (pointer)
		};
		artifact.class_values.add (new LlvmClassValueBinding (empty, CApi.Opcode.ICMP, types.scalar (NativeScalarType.B1), operands, "nullable callback admission", -1, (int) CApi.IntPredicate.EQ));
		var result = CApi.build_select (builder, empty, CApi.const_null (pointer), view, "callback.optional.view");
		CApi.ValueRef[] selected = {
			empty, CApi.const_null (pointer), view
		};
		artifact.class_values.add (new LlvmClassValueBinding (result, CApi.Opcode.SELECT, pointer, selected, "nullable callback view"));
		return result;
	}

	internal CApi.ValueRef to_c(CApi.BuilderRef builder, ForeignValueType signature, CApi.ValueRef view, bool nullable) throws LlvmError {
		string name = "astra.callback.to.c." + Checksum.compute_for_string (ChecksumType.SHA256, signature.identity ());
		var prior = (void*) artifact.retained_helpers.lookup (name);
		CApi.ValueRef thunk;
		if (prior != null) {
			thunk = (CApi.ValueRef) prior;
		} else {
			if ((void*) CApi.named_function (artifact.module, name) != null) {
				throw new LlvmError.LOWERING ("typed native callback thunk conflicts with a source symbol");
			}
			var type = foreign_code_type (signature);
			thunk = CApi.add_function (artifact.module, name, type);
			CApi.set_linkage (thunk, CApi.Linkage.INTERNAL);
			CApi.set_function_call_conv (thunk, CApi.CallConv.C);
			artifact.callback_c_bool.add (new LlvmCallbackCBoolBinding (artifact, thunk, signature, false));
			var body = CApi.create_builder_in_context (artifact.context);
			CApi.position_builder_at_end (body, CApi.append_basic_block_in_context (artifact.context, thunk, "entry"));
			var code = read (body, CApi.get_param (thunk, 0), 0);
			var context = read (body, CApi.get_param (thunk, 0), 1);
			var arguments = new CApi.ValueRef[signature.callback_parameter_count + 1];
			arguments[0] = context;
			for (uint p = 0; p < signature.callback_parameter_count; p++) {
				arguments[p + 1] = CApi.get_param (thunk, p + 1);
			}
			var call = CApi.build_call (body, type, code, arguments, arguments.length, signature.callback_result.kind == ForeignValueKind.VOID ? "" : "callback.native.result");
			CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
			artifact.class_calls.add (new LlvmClassCallBinding (call, code, type, arguments, LlvmLowering.CALL_CONVENTION, "typed imported callback with exact native code/context"));
			if (signature.callback_result.kind == ForeignValueKind.VOID) {
				CApi.build_ret_void (body);
			} else {
				CApi.build_ret (body, call);
			}
			CApi.dispose_builder (body);
			artifact.retained_helpers.insert (name, (void*) thunk);
			artifact.concurrency_guards.add (new LlvmSumSequence (thunk, true));
		}
		if (!nullable) {
			return thunk;
		}
		var empty = CApi.build_icmp (builder, CApi.IntPredicate.EQ, view, CApi.const_null (pointer), "callback.null");
		CApi.ValueRef[] operands = {
			view, CApi.const_null (pointer)
		};
		artifact.class_values.add (new LlvmClassValueBinding (empty, CApi.Opcode.ICMP, types.scalar (NativeScalarType.B1), operands, "nullable native callback admission", -1, (int) CApi.IntPredicate.EQ));
		var result = CApi.build_select (builder, empty, CApi.const_null (pointer), thunk, "callback.optional.code");
		CApi.ValueRef[] selected = {
			empty, CApi.const_null (pointer), thunk
		};
		artifact.class_values.add (new LlvmClassValueBinding (result, CApi.Opcode.SELECT, pointer, selected, "nullable C callback thunk"));
		return result;
	}

	internal CApi.ValueRef address(CallbackType signature, LlvmFunctionBinding target, int ordinal) throws LlvmError, NativeAbiError {
		string name = "astra.callback.address.%d.%s".printf (ordinal, Checksum.compute_for_string (ChecksumType.SHA256, signature.nominal_name ()));
		var prior = (void*) artifact.callback_views.lookup (name);
		if (prior != null) {
			return (CApi.ValueRef) prior;
		}
		if ((void*) CApi.named_function (artifact.module, name) != null) {
			throw new LlvmError.LOWERING ("callback native thunk conflicts with a source symbol");
		}
		var type = code_type (signature);
		var thunk = CApi.add_function (artifact.module, name, type);
		CApi.set_linkage (thunk, CApi.Linkage.INTERNAL);
		CApi.set_function_call_conv (thunk, LlvmLowering.CALL_CONVENTION);
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_at_end (builder, CApi.append_basic_block_in_context (artifact.context, thunk, "entry"));
		var arguments = new CApi.ValueRef[signature.parameter_types.length];
		for (int p = 0; p < arguments.length; p++) {
			arguments[p] = CApi.get_param (thunk, (uint) p + 1);
		}
		var call = CApi.build_call (builder, target.type, target.value, arguments, arguments.length, signature.result_type.kind == TypeKind.VOID ? "" : "callback.native.result");
		CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
		artifact.class_calls.add (new LlvmClassCallBinding (call, target.value, target.type, arguments, LlvmLowering.CALL_CONVENTION, "callback exact native function address"));
		if (signature.result_type.kind == TypeKind.VOID) {
			CApi.build_ret_void (builder);
		} else {
			CApi.build_ret (builder, call);
		}
		CApi.dispose_builder (builder);
		artifact.concurrency_guards.add (new LlvmSumSequence (thunk, true));
		CApi.ValueRef[] fields = {
			thunk, CApi.const_null (pointer)
		};
		var initializer = CApi.const_struct (artifact.context, fields, fields.length, 0);
		var view = CApi.add_global (artifact.module, layout, name + ".view");
		CApi.set_linkage (view, CApi.Linkage.PRIVATE);
		CApi.set_global_constant (view, 1);
		CApi.set_initializer (view, initializer);
		artifact.class_globals.add (new LlvmClassGlobalBinding (view, initializer));
		artifact.callback_views.insert (name, (void*) view);
		return view;
	}

	internal CApi.ValueRef from_closure(CApi.BuilderRef builder, CallbackType signature, CApi.ValueRef source) throws LlvmError {
		CApi.TypeRef[] fields = {
			pointer, pointer, pointer, pointer, pointer
		};
		var closure_layout = CApi.struct_type_in_context (artifact.context, fields, fields.length, 0);
		artifact.class_layouts.add (new LlvmClassLayoutBinding (closure_layout, fields));
		string name = "astra.callback.empty.closure";
		var empty_source = CApi.named_global (artifact.module, name);
		if ((void*) empty_source == null) {
			empty_source = CApi.add_global (artifact.module, closure_layout, name);
			var initializer = CApi.const_null (closure_layout);
			CApi.set_initializer (empty_source, initializer);
			CApi.set_linkage (empty_source, CApi.Linkage.PRIVATE);
			CApi.set_global_constant (empty_source, 1);
			artifact.class_globals.add (new LlvmClassGlobalBinding (empty_source, initializer));
		}
		var empty = CApi.build_icmp (builder, CApi.IntPredicate.EQ, source, CApi.const_null (pointer), "callback.closure.null");
		artifact.class_values.add (new LlvmClassValueBinding (empty, CApi.Opcode.ICMP, types.scalar (NativeScalarType.B1), new CApi.ValueRef[] { source, CApi.const_null (pointer) }, "captured callback null admission", -1, (int) CApi.IntPredicate.EQ));
		var guarded = CApi.build_select (builder, empty, empty_source, source, "callback.closure.guarded");
		artifact.class_values.add (new LlvmClassValueBinding (guarded, CApi.Opcode.SELECT, pointer, new CApi.ValueRef[] { empty, empty_source, source }, "captured callback safe carrier"));
		var view = CApi.build_alloca (builder, layout, "callback.captured.view");
		for (uint field = 0; field < 2; field++) {
			var address = CApi.build_struct_gep (builder, closure_layout, guarded, field, "callback.closure.member");
			artifact.class_addresses.add (new LlvmClassAddressBinding (address, guarded, closure_layout, field));
			var component = CApi.build_load (builder, pointer, address, "callback.closure.component");
			artifact.class_values.add (new LlvmClassValueBinding (component, CApi.Opcode.LOAD, pointer, new CApi.ValueRef[] { address }, "captured Closure code/environment read"));
			write (builder, view, field, component);
		}
		var result = CApi.build_select (builder, empty, CApi.const_null (pointer), view, "callback.captured.optional");
		artifact.class_values.add (new LlvmClassValueBinding (result, CApi.Opcode.SELECT, pointer, new CApi.ValueRef[] { empty, CApi.const_null (pointer), view }, "captured callback exact scoped view"));
		return result;
	}

	internal CApi.ValueRef invoke(CApi.BuilderRef builder, CallbackType signature, CApi.ValueRef carrier, CApi.ValueRef[] incoming) throws LlvmError, NativeAbiError {
		var code = read (builder, carrier, 0);
		var context = read (builder, carrier, 1);
		var arguments = new CApi.ValueRef[incoming.length + 1];
		arguments[0] = context;
		for (int p = 0; p < incoming.length; p++) {
			arguments[p + 1] = incoming[p];
		}
		var type = code_type (signature);
		var result = CApi.build_call (builder, type, code, arguments, arguments.length, signature.result_type.kind == TypeKind.VOID ? "" : "callback.result");
		CApi.set_instruction_call_conv (result, LlvmLowering.CALL_CONVENTION);
		artifact.class_calls.add (new LlvmClassCallBinding (result, code, type, arguments, LlvmLowering.CALL_CONVENTION, "typed native callback code/context invocation"));
		return result;
	}

}
}
