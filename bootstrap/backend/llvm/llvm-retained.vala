// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.NativeAbi;
namespace Astra.Backend.LLVM {
// A finite C adapter, distinct from native fastcc code/environment authority.
// Only opaque registrar tokens cross the provider interface.
internal class LlvmRetainedHelperBinding : Object {
	private CApi.ValueRef value;
	private CApi.TypeRef type;
	private uint convention;
	private string symbol;
	private LlvmSumSequence sequence;
	internal LlvmRetainedHelperBinding (CApi.ValueRef value, CApi.TypeRef type, uint convention, string symbol) {
		this.value = value;
		this.type = type;
		this.convention = convention;
		this.symbol = symbol;
		sequence = new LlvmSumSequence (value, true);
	}

	internal void verify() throws LlvmError {
		size_t length;
		unowned string name = CApi.value_name (value, out length);
		if (name != symbol || length != symbol.length || (void*) CApi.global_value_type (value) != (void*) type || CApi.function_call_conv (value) != convention || CApi.get_linkage (value) != CApi.Linkage.INTERNAL || CApi.count_basic_blocks (value) != 1) {
			throw new LlvmError.VERIFICATION ("retained adapter lost exact compiler-private symbol, signature or convention");
		}
		sequence.verify ();
	}

}
internal class LlvmRetainedLowering : Object {
	private LlvmModuleArtifact artifact;
	private LlvmTypeMapper types;
	private CApi.BuilderRef builder;
	private CApi.ValueRef function;
	private LlvmScalarLowering scalars;
	private CApi.TypeRef pointer_type;
	private CApi.TypeRef integer_type;
	private CApi.TypeRef layout;
	private int serial;
	internal LlvmRetainedLowering (LlvmModuleArtifact artifact, LlvmTypeMapper types, CApi.BuilderRef builder, CApi.ValueRef function, LlvmScalarLowering scalars) throws LlvmError {
		this.artifact = artifact;
		this.types = types;
		this.builder = builder;
		this.function = function;
		this.scalars = scalars;
		pointer_type = types.scalar (NativeScalarType.PTR);
		integer_type = types.scalar (NativeScalarType.I32);
		CApi.TypeRef[] fields = {
			pointer_type, pointer_type, pointer_type, pointer_type, pointer_type
		};
		layout = CApi.struct_type_in_context (artifact.context, fields, fields.length, 0);
		artifact.class_layouts.add (new LlvmClassLayoutBinding (layout, fields));
	}

	private CApi.ValueRef address(CApi.BuilderRef active, CApi.ValueRef root, uint member) {
		var result = CApi.build_struct_gep (active, layout, root, member, "retained.member");
		artifact.class_addresses.add (new LlvmClassAddressBinding (result, root, layout, member));
		return result;
	}

	private CApi.ValueRef read(CApi.BuilderRef active, CApi.ValueRef root, uint member) {
		var place = address (active, root, member);
		var result = CApi.build_load (active, pointer_type, place, "retained.read");
		artifact.class_values.add (new LlvmClassValueBinding (result, CApi.Opcode.LOAD, pointer_type, new CApi.ValueRef[] { place }, "private retained attachment read"));
		return result;
	}

	private void write(CApi.ValueRef root, uint member, CApi.ValueRef value) {
		var place = address (builder, root, member);
		var result = CApi.build_store (builder, value, place);
		artifact.class_values.add (new LlvmClassValueBinding (result, CApi.Opcode.STORE, CApi.void_type_in_context (artifact.context), new CApi.ValueRef[] { value, place }, "private retained attachment publication"));
	}

	private CApi.ValueRef declaration(string symbol, CApi.TypeRef type) throws LlvmError {
		var target = CApi.named_function (artifact.module, symbol);
		var registered = (void*) artifact.retained_runtime_symbols.lookup (symbol);
		if (registered == null) {
			if ((void*) target != null) {
				throw new LlvmError.LOWERING ("retained runtime protocol name conflicts with a source-declared physical identity");
			}
			target = CApi.add_function (artifact.module, symbol, type);
			CApi.set_function_call_conv (target, CApi.CallConv.C);
			artifact.retained_runtime_symbols.insert (symbol, (void*) target);
		} else if ((void*) target != registered || CApi.count_basic_blocks (target) != 0) {
			throw new LlvmError.LOWERING ("retained provider lost its exact external runtime identity");
		}
		if ((void*) CApi.global_value_type (target) != (void*) type || CApi.function_call_conv (target) != CApi.CallConv.C) {
			throw new LlvmError.LOWERING ("retained provider symbol has incompatible exact C signature");
		}
		return target;
	}

	private CApi.ValueRef helper(string symbol, CApi.TypeRef type, uint convention) throws LlvmError {
		var target = CApi.named_function (artifact.module, symbol);
		var registered = (void*) artifact.retained_helpers.lookup (symbol);
		if (registered == null) {
			if ((void*) target != null) {
				throw new LlvmError.LOWERING ("retained adapter name conflicts with a source-declared physical identity");
			}
			return target;
		}
		if ((void*) target != registered || (void*) CApi.global_value_type (target) != (void*) type || CApi.function_call_conv (target) != convention || CApi.get_linkage (target) != CApi.Linkage.INTERNAL || CApi.count_basic_blocks (target) != 1) {
			throw new LlvmError.LOWERING ("retained adapter lost registered compiler-private identity");
		}
		return target;
	}

	private CApi.ValueRef call(string symbol, CApi.TypeRef result_type, CApi.TypeRef[] parameter_types, CApi.ValueRef[] arguments) throws LlvmError {
		var type = CApi.function_type (result_type, parameter_types, parameter_types.length, 0);
		var callee = declaration (symbol, type);
		var result = CApi.build_call (builder, type, callee, arguments, arguments.length, "retained.provider.result");
		CApi.set_instruction_call_conv (result, CApi.CallConv.C);
		artifact.class_calls.add (new LlvmClassCallBinding (result, callee, type, arguments, CApi.CallConv.C, "finite retained C provider lifecycle operation"));
		return result;
	}

	private CApi.ValueRef compare(CApi.ValueRef left, CApi.ValueRef right) throws LlvmError {
		var result = CApi.build_icmp (builder, CApi.IntPredicate.EQ, left, right, "retained.equal");
		if ((void*) CApi.is_instruction (result) != null) {
			artifact.class_values.add (new LlvmClassValueBinding (result, CApi.Opcode.ICMP, types.scalar (NativeScalarType.B1), new CApi.ValueRef[] { left, right }, "retained exact attachment identity", -1, (int) CApi.IntPredicate.EQ));
		}
		return result;
	}

	private CApi.BasicBlockRef block(string name) {
		return CApi.append_basic_block_in_context (artifact.context, function, "retained.%d.%s".printf (serial++, name));
	}

	private void branch(CApi.ValueRef condition, CApi.BasicBlockRef yes, CApi.BasicBlockRef no) {
		var result = CApi.build_cond_br (builder, condition, yes, no);
		artifact.class_branches.add (new LlvmClassBranchBinding (result, condition, yes, no));
	}

	private CApi.ValueRef thunk() throws LlvmError {
		var parameters = new CApi.TypeRef[] {
			pointer_type, integer_type
		};
		var type = CApi.function_type (integer_type, parameters, 2, 0);
		var existing = helper ("astra.retained.i32.thunk", type, CApi.CallConv.C);
		if ((void*) existing != null) {
			return existing;
		}
		var value = CApi.add_function (artifact.module, "astra.retained.i32.thunk", type);
		CApi.set_linkage (value, CApi.Linkage.INTERNAL);
		CApi.set_function_call_conv (value, CApi.CallConv.C);
		var active = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_at_end (active, CApi.append_basic_block_in_context (artifact.context, value, "entry"));
		var carrier = CApi.get_param (value, 0);
		var code = read (active, carrier, 0);
		var environment = read (active, carrier, 1);
		var arguments = new CApi.ValueRef[] {
			environment, CApi.get_param (value, 1)
		};
		var result = CApi.build_call (active, type, code, arguments, 2, "retained.native.result");
		CApi.set_instruction_call_conv (result, LlvmLowering.CALL_CONVENTION);
		artifact.class_calls.add (new LlvmClassCallBinding (result, code, type, arguments, LlvmLowering.CALL_CONVENTION, "typed C thunk to exact nonthrowing native environment"));
		CApi.build_ret (active, result);
		CApi.dispose_builder (active);
		artifact.retained_helpers.insert ("astra.retained.i32.thunk", (void*) value);
		artifact.retained_bindings.add (new LlvmRetainedHelperBinding (value, type, CApi.CallConv.C, "astra.retained.i32.thunk"));
		return value;
	}

	private CApi.ValueRef signal_identity(Astra.Source.ForeignValueType signature) throws LlvmError {
		string identity = signature.identity ();
		string name = "astra.retained.signal.signature." + Checksum.compute_for_string (ChecksumType.SHA256, identity);
		var existing = (void*) artifact.callback_views.lookup (name);
		if (existing != null) {
			return (CApi.ValueRef) existing;
		}
		if ((void*) CApi.named_global (artifact.module, name) != null) {
			throw new LlvmError.LOWERING ("retained signal signature conflicts with an existing symbol");
		}
		var byte = types.scalar (NativeScalarType.U8);
		var bytes = new CApi.ValueRef[identity.length + 1];
		for (int i = 0; i < identity.length; i++) {
			bytes[i] = CApi.const_int (byte, identity[i], 0);
		}
		bytes[identity.length] = CApi.const_null (byte);
		var data = CApi.const_array (byte, bytes, bytes.length);
		var global = CApi.add_global (artifact.module, CApi.type_of (data), name);
		CApi.set_linkage (global, CApi.Linkage.PRIVATE);
		CApi.set_global_constant (global, 1);
		CApi.set_initializer (global, data);
		artifact.class_globals.add (new LlvmClassGlobalBinding (global, data));
		artifact.callback_views.insert (name, (void*) global);
		return global;
	}

	private CApi.ValueRef signal_thunk(Astra.Source.ForeignValueType signature) throws LlvmError {
		if (!signature.valid () || signature.kind != Astra.Source.ForeignValueKind.CALLBACK || signature.callback_result.kind != Astra.Source.ForeignValueKind.VOID) {
			throw new LlvmError.LOWERING ("retained signal requires its normalized void callback descriptor");
		}
		string name = "astra.retained.signal.thunk." + Checksum.compute_for_string (ChecksumType.SHA256, signature.identity ());
		var parameters = new CApi.TypeRef[signature.callback_parameter_count + 1];
		parameters[0] = pointer_type;
		uint[] bools = {};
		for (uint p = 0; p < signature.callback_parameter_count; p++) {
			parameters[p + 1] = types.scalar (NativeForeignApi.scalar (signature.callback_parameter (p).kind));
			if (signature.callback_parameter (p).kind == Astra.Source.ForeignValueKind.BOOL) {
				bools += p + 2;
			}
		}
		var type = CApi.function_type (CApi.void_type_in_context (artifact.context), parameters, parameters.length, 0);
		var existing = helper (name, type, CApi.CallConv.C);
		if ((void*) existing != null) {
			return existing;
		}
		var value = CApi.add_function (artifact.module, name, type);
		CApi.set_linkage (value, CApi.Linkage.INTERNAL);
		CApi.set_function_call_conv (value, CApi.CallConv.C);
		artifact.callback_c_bool.add (new LlvmCallbackCBoolBinding.physical (artifact, value, bools, false));
		var active = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_at_end (active, CApi.append_basic_block_in_context (artifact.context, value, "entry"));
		var carrier = CApi.get_param (value, 0);
		var code = read (active, carrier, 0);
		var environment = read (active, carrier, 1);
		var arguments = new CApi.ValueRef[parameters.length];
		arguments[0] = environment;
		for (uint p = 1; p < parameters.length; p++) {
			arguments[p] = CApi.get_param (value, p);
		}
		var invoked = CApi.build_call (active, type, code, arguments, arguments.length, "");
		CApi.set_instruction_call_conv (invoked, LlvmLowering.CALL_CONVENTION);
		artifact.class_calls.add (new LlvmClassCallBinding (invoked, code, type, arguments, LlvmLowering.CALL_CONVENTION, "typed retained signal exact native code, environment and argument order"));
		CApi.build_ret_void (active);
		CApi.dispose_builder (active);
		artifact.retained_helpers.insert (name, (void*) value);
		artifact.retained_bindings.add (new LlvmRetainedHelperBinding (value, type, CApi.CallConv.C, name));
		return value;
	}

	private CApi.ValueRef retire_thunk(bool threaded, bool signal = false) throws LlvmError {
		string helper_name = signal ? "astra.retained.signal.retire" : threaded ? "astra.thread.retire" : "astra.retained.retire";
		string provider_name = signal ? "astra_gobject16_signal_retire" : threaded ? "astra_thread_retire" : "astra_retained_retire";
		var parameters = new CApi.TypeRef[] {
			pointer_type
		};
		var type = CApi.function_type (integer_type, parameters, parameters.length, 0);
		var existing = helper (helper_name, type, LlvmLowering.CALL_CONVENTION);
		if ((void*) existing != null) {
			return existing;
		}
		var value = CApi.add_function (artifact.module, helper_name, type);
		CApi.set_linkage (value, CApi.Linkage.INTERNAL);
		CApi.set_function_call_conv (value, LlvmLowering.CALL_CONVENTION);
		var active = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_at_end (active, CApi.append_basic_block_in_context (artifact.context, value, "entry"));
		var target = declaration (provider_name, type);
		var arguments = new CApi.ValueRef[] {
			CApi.get_param (value, 0)
		};
		var result = CApi.build_call (active, type, target, arguments, 1, "retained.retire.ack");
		CApi.set_instruction_call_conv (result, CApi.CallConv.C);
		artifact.class_calls.add (new LlvmClassCallBinding (result, target, type, arguments, CApi.CallConv.C, "exact C provider release adapter"));
		CApi.build_ret (active, result);
		CApi.dispose_builder (active);
		artifact.retained_helpers.insert (helper_name, (void*) value);
		artifact.retained_bindings.add (new LlvmRetainedHelperBinding (value, type, LlvmLowering.CALL_CONVENTION, helper_name));
		return value;
	}

	internal CApi.ValueRef operation(RetainedAction action, CApi.ValueRef carrier, CApi.ValueRef argument, LlvmBlockState state, NativeClosureHandleType? handle = null) throws LlvmError {
		var signal_callback = handle == null ? null : NativeRetainedPlan.signal_callback (handle);
		bool signal = RetainedContracts.signal (action);
		if (signal && signal_callback == null) {
			throw new LlvmError.LOWERING ("typed signal lost its exact nonthrowing scalar Closure signature");
		}
		scalars.guard_nonnull (carrier, "retained.owner", state, true);
		var token = read (builder, carrier, 3);
		bool threaded = RetainedContracts.threaded (action);
		if (action != RetainedAction.REGISTER && action != RetainedAction.THREAD_START && action != RetainedAction.SIGNAL_REGISTER) {
			string symbol = signal ? (action == RetainedAction.SIGNAL_REVOKE ? "astra_gobject16_signal_revoke" : "astra_gobject16_signal_observe") : threaded ? (action == RetainedAction.THREAD_JOIN ? "astra_thread_join" : "astra_thread_cancel") : action == RetainedAction.DISPATCH ? "astra_retained_dispatch" : action == RetainedAction.REVOKE ? "astra_retained_revoke" : "astra_retained_observe";
			return action == RetainedAction.DISPATCH ? call (symbol, integer_type, new CApi.TypeRef[] { pointer_type, integer_type }, new CApi.ValueRef[] { token, argument }) : call (symbol, integer_type, new CApi.TypeRef[] { pointer_type }, new CApi.ValueRef[] { token });
		}
		var fresh = block ("register.fresh");
		var done = block ("register.done");
		var prior = state.end;
		branch (compare (token, CApi.const_null (pointer_type)), fresh, done);
		CApi.position_builder_at_end (builder, fresh);
		state.end = fresh;
		var registered = signal ? call ("astra_gobject16_signal_register", pointer_type, new CApi.TypeRef[] { pointer_type, pointer_type, integer_type, pointer_type }, new CApi.ValueRef[] { signal_thunk (signal_callback), carrier, argument, signal_identity (signal_callback) }) : call (threaded ? "astra_thread_register" : "astra_retained_register", pointer_type, new CApi.TypeRef[] { pointer_type, pointer_type, integer_type }, new CApi.ValueRef[] { thunk (), carrier, argument });
		var retire = retire_thunk (threaded, signal);
		write (carrier, 4, retire);
		write (carrier, 3, registered);
		var failed = compare (registered, CApi.const_null (pointer_type));
		var status = CApi.build_select (builder, failed, CApi.const_int (integer_type, (uint64) (-1), 1), CApi.const_null (integer_type), "retained.registration.status");
		artifact.class_values.add (new LlvmClassValueBinding (status, CApi.Opcode.SELECT, integer_type, new CApi.ValueRef[] { failed, CApi.const_int (integer_type, (uint64) (-1), 1), CApi.const_null (integer_type) }, "checked retained admission status"));
		var fresh_end = state.end;
		CApi.build_br (builder, done);
		CApi.position_builder_at_end (builder, done);
		state.end = done;
		var result = CApi.build_phi (builder, integer_type, "retained.register.result");
		var duplicate = CApi.const_int (integer_type, (uint64) (-2), 1);
		CApi.add_incoming (result, &duplicate, &prior, 1);
		CApi.add_incoming (result, &status, &fresh_end, 1);
		return result;
	}

}
}
