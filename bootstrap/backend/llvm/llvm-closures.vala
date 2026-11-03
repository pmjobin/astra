// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;
namespace Astra.Backend.LLVM {
// Linear triple: native code, exact owned environment, exact destructor code.
// Neither environment nor destructor is reconstructed from an untyped address.
internal class LlvmClosureLowering : Object {
	private LlvmModuleArtifact artifact;
	private LlvmTypeMapper types;
	private CApi.BuilderRef builder;
	private CApi.ValueRef function;
	private LlvmScalarLowering scalars;
	private LlvmBufferAllocation allocator;
	private HashTable<SsaFunction, LlvmFunctionBinding> functions;
	private LlvmClassRuntime classes;
	private CApi.TypeRef layout;
	private CApi.TypeRef pointer_type;
	private int serial;
	internal LlvmClosureLowering (LlvmModuleArtifact artifact, LlvmTypeMapper types, CApi.BuilderRef builder, CApi.ValueRef function, LlvmScalarLowering scalars, LlvmBufferAllocation allocator, HashTable<SsaFunction, LlvmFunctionBinding> functions, LlvmClassRuntime classes) throws LlvmError {
		this.classes = classes;
		this.artifact = artifact;
		this.types = types;
		this.builder = builder;
		this.function = function;
		this.scalars = scalars;
		this.allocator = allocator;
		this.functions = functions;
		pointer_type = types.scalar (NativeScalarType.PTR);
		CApi.TypeRef[] fields = {
			pointer_type, pointer_type, pointer_type, pointer_type, pointer_type
		};
		layout = CApi.struct_type_in_context (artifact.context, fields, fields.length, 0);
		artifact.class_layouts.add (new LlvmClassLayoutBinding (layout, fields));
	}

	private CApi.BasicBlockRef block(string name) {
		return CApi.append_basic_block_in_context (artifact.context, function, "closure.%d.%s".printf (serial++, name));
	}

	private CApi.ValueRef address(CApi.ValueRef carrier, uint member) {
		var result = CApi.build_struct_gep (builder, layout, carrier, member, "closure.member");
		artifact.class_addresses.add (new LlvmClassAddressBinding (result, carrier, layout, member));
		return result;
	}

	private CApi.ValueRef read(CApi.ValueRef carrier, uint member) {
		var place = address (carrier, member);
		var result = CApi.build_load (builder, pointer_type, place, "closure.read");
		artifact.class_values.add (new LlvmClassValueBinding (result, CApi.Opcode.LOAD, pointer_type, new CApi.ValueRef[] { place }, "typed closure carrier read"));
		return result;
	}

	private void write(CApi.ValueRef carrier, uint member, CApi.ValueRef value) {
		var place = address (carrier, member);
		var result = CApi.build_store (builder, value, place);
		artifact.class_values.add (new LlvmClassValueBinding (result, CApi.Opcode.STORE, CApi.void_type_in_context (artifact.context), new CApi.ValueRef[] { value, place }, "typed closure carrier publication"));
	}

	private CApi.ValueRef is_null(CApi.ValueRef value) throws LlvmError {
		var empty = CApi.const_null (pointer_type);
		var result = CApi.build_icmp (builder, CApi.IntPredicate.EQ, value, empty, "closure.null");
		if ((void*) CApi.is_instruction (result) != null) {
			artifact.class_values.add (new LlvmClassValueBinding (result, CApi.Opcode.ICMP, types.scalar (NativeScalarType.B1), new CApi.ValueRef[] { value, empty }, "closure ownership null guard", -1, (int) CApi.IntPredicate.EQ));
		}
		return result;
	}

	private void branch(CApi.ValueRef condition, CApi.BasicBlockRef yes, CApi.BasicBlockRef no) {
		var result = CApi.build_cond_br (builder, condition, yes, no);
		artifact.class_branches.add (new LlvmClassBranchBinding (result, condition, yes, no));
	}

	private CApi.ValueRef actor_drop(SsaClass owner) throws LlvmError {
		string name = "astra.actor.drop." + owner.name;
		var prior = (void*) artifact.retained_helpers.lookup (name);
		if (prior != null) {
			return (CApi.ValueRef) prior;
		}
		if ((void*) CApi.named_function (artifact.module, name) != null) {
			throw new LlvmError.LOWERING ("Actor drop thunk conflicts with source identity");
		}
		CApi.TypeRef[] parameters = {
			pointer_type
		};
		var type = CApi.function_type (CApi.void_type_in_context (artifact.context), parameters, parameters.length, 0);
		var value = CApi.add_function (artifact.module, name, type);
		CApi.set_linkage (value, CApi.Linkage.INTERNAL);
		CApi.set_function_call_conv (value, CApi.CallConv.C);
		var active = CApi.create_builder_in_context (artifact.context);
		var entry = CApi.append_basic_block_in_context (artifact.context, value, "entry");
		CApi.position_builder_at_end (active, entry);
		var state = new LlvmBlockState (entry);
		var scalar = new LlvmScalarLowering (artifact, types, active, value);
		var allocation = new LlvmBufferAllocation (artifact, active, value, scalar);
		classes.release_owned (active, value, allocation, owner, CApi.get_param (value, 0), state, "actor.drop");
		CApi.build_ret_void (active);
		CApi.dispose_builder (active);
		artifact.retained_helpers.insert (name, (void*) value);
		artifact.concurrency_guards.add (new LlvmSumSequence (value, true));
		return value;
	}

	private CApi.ValueRef actor_bits(CApi.BuilderRef active, CApi.ValueRef value, SemanticType type, bool encode) throws LlvmError {
		uint width = (type is IntegerType) ? ((IntegerType) type).bit_width : type.kind == TypeKind.BOOL ? 1 : type.kind == TypeKind.F32 ? 32 : 64;
		var bits_type = CApi.int_type_in_context (artifact.context, width);
		var wide = CApi.int_type_in_context (artifact.context, 64);
		bool floating = type is FloatingType;
		if (encode && floating) {
			var original = value;
			value = CApi.build_bit_cast (active, original, bits_type, "actor.scalar.bits");
			if ((void*) CApi.is_instruction (value) != null) {
				artifact.class_values.add (new LlvmClassValueBinding (value, CApi.Opcode.BITCAST, bits_type, new CApi.ValueRef[] { original }, "Actor exact floating message bits"));
			}
		}
		if (width < 64) {
			var original = value;
			var destination = encode ? wide : bits_type;
			value = encode ? CApi.build_zext (active, original, destination, "actor.scalar.pack") : CApi.build_trunc (active, original, destination, "actor.scalar.unpack");
			if ((void*) CApi.is_instruction (value) != null) {
				artifact.class_values.add (new LlvmClassValueBinding (value, encode ? CApi.Opcode.ZEXT : CApi.Opcode.TRUNC, destination, new CApi.ValueRef[] { original }, "Actor exact scalar mailbox transport"));
			}
		}
		if (!encode && floating) {
			var original = value;
			var destination = types.scalar (type.kind == TypeKind.F32 ? NativeScalarType.F32 : NativeScalarType.F64);
			value = CApi.build_bit_cast (active, original, destination, "actor.scalar.value");
			artifact.class_values.add (new LlvmClassValueBinding (value, CApi.Opcode.BITCAST, destination, new CApi.ValueRef[] { original }, "Actor exact floating handler argument"));
		}
		return value;
	}

	private CApi.ValueRef actor_dispatch(SsaClosureBind closure) throws LlvmError {
		var target = functions.lookup (closure.target);
		var signature = (ClosureHandleType) closure.result.semantic_type;
		string name = "astra.actor.dispatch." + closure.target.name;
		var prior = (void*) artifact.retained_helpers.lookup (name);
		if (prior != null) {
			return (CApi.ValueRef) prior;
		}
		if (target == null || (void*) CApi.named_function (artifact.module, name) != null) {
			throw new LlvmError.LOWERING ("Actor dispatcher lost exact private handler binding");
		}
		var wide = CApi.int_type_in_context (artifact.context, 64);
		var nothing = CApi.void_type_in_context (artifact.context);
		CApi.TypeRef[] parameters = {
			pointer_type, pointer_type, wide
		};
		var type = CApi.function_type (nothing, parameters, parameters.length, 0);
		var value = CApi.add_function (artifact.module, name, type);
		CApi.set_linkage (value, CApi.Linkage.INTERNAL);
		CApi.set_function_call_conv (value, CApi.CallConv.C);
		var active = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_at_end (active, CApi.append_basic_block_in_context (artifact.context, value, "entry"));
		var message = (signature.actor_message is ClassType) ? CApi.get_param (value, 1) : actor_bits (active, CApi.get_param (value, 2), signature.actor_message, false);
		var arguments = new CApi.ValueRef[] {
			CApi.get_param (value, 0), message
		};
		var call = CApi.build_call (active, target.type, target.value, arguments, 2, "actor.handled");
		CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
		artifact.class_calls.add (new LlvmClassCallBinding (call, target.value, target.type, arguments, LlvmLowering.CALL_CONVENTION, "exact native Actor handler consuming one owned message"));
		CApi.build_ret_void (active);
		CApi.dispose_builder (active);
		artifact.retained_helpers.insert (name, (void*) value);
		artifact.concurrency_guards.add (new LlvmSumSequence (value, true));
		return value;
	}

	private CApi.ValueRef bind_actor(SsaClosureBind closure, CApi.ValueRef environment, LlvmBlockState state) throws LlvmError {
		var signature = (ClosureHandleType) closure.result.semantic_type;
		var spec = closure.actor_binding;
		if (spec == null || !spec.valid () || !signature.supported ()) {
			throw new LlvmError.LOWERING ("Actor binding lost admitted FIFO/executor contract");
		}
		var owner = closure.cleanup.closure_environment;
		CApi.ValueRef message_drop = CApi.const_null (pointer_type);
		if (signature.actor_message is ClassType) {
			var message = classes.declaration ((ClassType) signature.actor_message);
			if (message == null) {
				throw new LlvmError.LOWERING ("Actor message lost exact destruction identity");
			}
			message_drop = actor_drop (message);
		}
		var i32 = types.scalar (NativeScalarType.I32);
		var result = LlvmConcurrencyRuntime.call (artifact, builder, "astra_actor_open", pointer_type, new CApi.TypeRef[] { pointer_type, pointer_type, pointer_type, pointer_type, i32, pointer_type, i32 }, new CApi.ValueRef[] { actor_dispatch (closure), environment, actor_drop (owner), message_drop, CApi.const_int (i32, (uint64) spec.capacity, 0), LlvmConcurrencyRuntime.singleton_key (artifact, spec.name), CApi.const_int (i32, spec.name.length, 0) });
		scalars.guard_nonnull (result, "actor.admission", state, true);
		return result;
	}

	internal CApi.ValueRef bind(SsaClosureBind closure, CApi.ValueRef environment, LlvmBlockState state) throws LlvmError {
		if (((ClosureHandleType) closure.result.semantic_type).actor) {
			return bind_actor (closure, environment, state);
		}
		var target = functions.lookup (closure.target);
		var owner = closure.cleanup.closure_environment;
		if (target == null || owner == null || owner.polymorphic) {
			throw new LlvmError.LOWERING ("closure binding lost exact native code or nonpolymorphic environment destruction identity");
		}
		scalars.guard_nonnull (environment, "closure.environment", state, true);
		var context = owner.allocation_policy != null && owner.allocation_policy.kind == Astra.Source.AllocationKind.CONTEXT ? new LlvmPolicyAllocation (artifact).origin (builder, environment, owner.name) : (CApi.ValueRef) null;
		var carrier = allocator.allocate (CApi.const_int (CApi.int32_type_in_context (artifact.context), 1, 0), layout, "closure.carrier", state, false, null, true, owner.allocation_policy, owner.name, "closure", false, context);
		write (carrier, 0, target.value);
		write (carrier, 1, environment);
		write (carrier, 3, CApi.const_null (pointer_type));
		write (carrier, 4, CApi.const_null (pointer_type));
		var destructor = owner.destructor == null ? null : functions.lookup (owner.destructor);
		if (owner.destructor != null && destructor == null) {
			throw new LlvmError.LOWERING ("closure environment destructor has no exact native code binding");
		}
		write (carrier, 2, destructor == null ? CApi.const_null (pointer_type) : destructor.value);
		return carrier;
	}

	internal CApi.ValueRef actor_operation(SsaActorSend send, CApi.ValueRef sender, CApi.ValueRef message, LlvmBlockState state) throws LlvmError {
		var i32 = types.scalar (NativeScalarType.I32);
		var signature = (ClosureHandleType) send.sender.semantic_type;
		if (send.action != Astra.Source.ActorAction.SEND) {
			return LlvmConcurrencyRuntime.call (artifact, builder, send.action == Astra.Source.ActorAction.SHUTDOWN ? "astra_actor_shutdown" : "astra_actor_cancel", i32, new CApi.TypeRef[] { pointer_type }, new CApi.ValueRef[] { sender });
		}
		var wide = CApi.int_type_in_context (artifact.context, 64);
		CApi.ValueRef payload = CApi.const_null (pointer_type);
		CApi.ValueRef scalar = CApi.const_null (wide);
		CApi.ValueRef drop = CApi.const_null (pointer_type);
		if (signature.actor_message is ClassType) {
			var owner = classes.declaration ((ClassType) signature.actor_message);
			if (owner == null) {
				throw new LlvmError.LOWERING ("Actor message operation lost exact destructor");
			}
			payload = message;
			drop = actor_drop (owner);
		} else {
			scalar = actor_bits (builder, message, signature.actor_message, true);
		}
		return LlvmConcurrencyRuntime.call (artifact, builder, "astra_actor_send", i32, new CApi.TypeRef[] { pointer_type, pointer_type, wide, pointer_type }, new CApi.ValueRef[] { sender, payload, scalar, drop });
	}

	internal CApi.ValueRef invoke(SsaClosureCall call, CApi.ValueRef carrier, CApi.ValueRef[] scalar_arguments, LlvmBlockState state, CApi.ValueRef success_slot) throws LlvmError, NativeAbiError {
		var signature = (ClosureHandleType) call.callee.semantic_type;
		scalars.guard_nonnull (carrier, "closure.invoke", state, true);
		var code = read (carrier, 0);
		var environment = read (carrier, 1);
		bool success_result = signature.throws_type != null && signature.result_type.kind != TypeKind.VOID;
		int prefix = success_result ? 2 : 1;
		var physical = CallableRecordGroups.physical_parameters (signature, call.struct_arguments);
		var parameter_types = new CApi.TypeRef[physical.length + prefix];
		var arguments = new CApi.ValueRef[scalar_arguments.length + prefix];
		if (success_result) {
			if ((void*) success_slot == null) {
				throw new LlvmError.LOWERING ("checked closure lost private scalar success storage");
			}
			parameter_types[0] = pointer_type;
			arguments[0] = success_slot;
		}
		parameter_types[prefix - 1] = pointer_type;
		arguments[prefix - 1] = environment;
		for (int p = 0; p < scalar_arguments.length; p++) {
			parameter_types[p + prefix] = types.value_type (physical[p]);
			arguments[p + prefix] = scalar_arguments[p];
		}
		var type = CApi.function_type (signature.throws_type == null ? types.callable_result_type (signature) : pointer_type, parameter_types, parameter_types.length, 0);
		var result = CApi.build_call (builder, type, code, arguments, arguments.length, signature.throws_type == null && signature.result_type.kind == TypeKind.VOID ? "" : "closure.invoke.result");
		CApi.set_instruction_call_conv (result, LlvmLowering.CALL_CONVENTION);
		artifact.class_calls.add (new LlvmClassCallBinding (result, code, type, arguments, LlvmLowering.CALL_CONVENTION, "typed borrowed closure environment invocation"));
		return result;
	}

	internal void release(CApi.ValueRef carrier, SsaCleanupContract cleanup, LlvmBlockState state) throws LlvmError {
		if (cleanup.closure_type != null && cleanup.closure_type.actor) {
			LlvmConcurrencyRuntime.call (artifact, builder, "astra_actor_release", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer_type }, new CApi.ValueRef[] { carrier });
			return;
		}
		if (cleanup.closure_environment == null || cleanup.closure_type == null || cleanup.closure_environment.polymorphic) {
			throw new LlvmError.LOWERING ("closure release lost exact environment destruction authority");
		}
		var live = block ("release.live");
		var done = block ("release.done");
		branch (is_null (carrier), done, live);
		CApi.position_builder_at_end (builder, live);
		state.end = live;
		// The foreign provider must acknowledge observed quiescence before the
		// native environment can be destroyed. Ordinary closures carry null.
		var retire = block ("release.retained");
		var stopped = block ("release.quiesced");
		var invalid = block ("release.unobserved");
		var environment_ready = block ("release.environment");
		var token = read (carrier, 3);
		branch (is_null (token), environment_ready, retire);
		CApi.position_builder_at_end (builder, retire);
		state.end = retire;
		CApi.TypeRef[] retire_parameters = {
			pointer_type
		};
		CApi.ValueRef[] retire_arguments = {
			token
		};
		var retire_code = read (carrier, 4);
		var retire_type = CApi.function_type (CApi.int32_type_in_context (artifact.context), retire_parameters, retire_parameters.length, 0);
		var ack = CApi.build_call (builder, retire_type, retire_code, retire_arguments, retire_arguments.length, "retained.quiescence");
		CApi.set_instruction_call_conv (ack, LlvmLowering.CALL_CONVENTION);
		artifact.class_calls.add (new LlvmClassCallBinding (ack, retire_code, retire_type, new CApi.ValueRef[] { token }, LlvmLowering.CALL_CONVENTION, "observed retained registration quiescence before environment destruction"));
		var acknowledged = CApi.build_icmp (builder, CApi.IntPredicate.EQ, ack, CApi.const_int (CApi.int32_type_in_context (artifact.context), 1, 0), "retained.ack");
		artifact.class_values.add (new LlvmClassValueBinding (acknowledged, CApi.Opcode.ICMP, types.scalar (NativeScalarType.B1), new CApi.ValueRef[] { ack, CApi.const_int (CApi.int32_type_in_context (artifact.context), 1, 0) }, "retained exact quiescence acknowledgement", -1, (int) CApi.IntPredicate.EQ));
		branch (acknowledged, stopped, invalid);
		CApi.position_builder_at_end (builder, invalid);
		scalars.emit_trap ();
		CApi.position_builder_at_end (builder, stopped);
		state.end = stopped;
		write (carrier, 3, CApi.const_null (pointer_type));
		CApi.build_br (builder, environment_ready);
		CApi.position_builder_at_end (builder, environment_ready);
		state.end = environment_ready;
		var environment = read (carrier, 1);
		var destructor = read (carrier, 2);
		write (carrier, 1, CApi.const_null (pointer_type));
		if (cleanup.closure_environment.concurrency_policy != null) {
			classes.release_owned (builder, function, allocator, cleanup.closure_environment, environment, state, "closure.environment");
			allocator.deallocate (carrier, "closure.carrier.free", state, cleanup.closure_environment.allocation_policy, cleanup.closure_environment.name, "closure");
			CApi.build_br (builder, done);
			CApi.position_builder_at_end (builder, done);
			state.end = done;
			return;
		}
		var destroy = block ("release.destroy");
		var free = block ("release.free");
		branch (is_null (destructor), free, destroy);
		CApi.position_builder_at_end (builder, destroy);
		state.end = destroy;
		CApi.TypeRef[] destroy_parameters = {
			pointer_type
		};
		var type = CApi.function_type (CApi.void_type_in_context (artifact.context), destroy_parameters, destroy_parameters.length, 0);
		var call = CApi.build_call (builder, type, destructor, &environment, 1, "");
		CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
		artifact.class_calls.add (new LlvmClassCallBinding (call, destructor, type, new CApi.ValueRef[] { environment }, LlvmLowering.CALL_CONVENTION, "closure carried exact environment destructor"));
		CApi.build_br (builder, free);
		CApi.position_builder_at_end (builder, free);
		state.end = free;
		allocator.deallocate (environment, "closure.environment.free", state, cleanup.closure_environment.allocation_policy, cleanup.closure_environment.name);
		allocator.deallocate (carrier, "closure.carrier.free", state, cleanup.closure_environment.allocation_policy, cleanup.closure_environment.name, "closure");
		CApi.build_br (builder, done);
		CApi.position_builder_at_end (builder, done);
		state.end = done;
	}

}
}
