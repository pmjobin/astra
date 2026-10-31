// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.NativeAbi;
using Astra.Continuations;

namespace Astra.Backend.LLVM {
internal class LlvmContinuationProjection : Object {
	private static bool index(CApi.ValueRef value, uint expected) {
		return (void*) CApi.is_constant_int (value) != null && CApi.const_int_zext (value) == expected;
	}
	private static bool root(CApi.ValueRef address, CApi.TypeRef carrier, CApi.ValueRef descriptor) {
		return (void*) CApi.is_instruction (address) != null && CApi.opcode (address) == CApi.Opcode.GEP && CApi.operand_count (address) >= 3 && (void*) CApi.gep_source_type (address) == (void*) carrier && (void*) CApi.operand (address, 0) == (void*) descriptor && index (CApi.operand (address, 1), 0);
	}
	internal static bool field(CApi.ValueRef address, CApi.TypeRef carrier, CApi.ValueRef descriptor, uint slot) {
		return root (address, carrier, descriptor) && CApi.operand_count (address) == 3 && index (CApi.operand (address, 2), slot);
	}
	internal static bool path(CApi.ValueRef address, CApi.TypeRef storage, CApi.ValueRef environment, string path) {
		var parts = path.split (".");
		if (!root (address, storage, environment) || CApi.operand_count (address) != parts.length + 2) {
			return false;
		}
		for (int i = 0; i < parts.length; i++) {
			if (!index (CApi.operand (address, (uint) i + 2), uint.parse (parts[i]))) {
				return false;
			}
		}
		return true;
	}
}

// Expected allocation and stores are captured during lowering, never inferred
// from names. Only native leaves and borrowed handles owned by this artifact.
internal class LlvmContinuationEnvironmentBinding : Object {
	internal NativeContinuationRegionPlan region;
	internal int creation;
	internal int initialization = -1;
	internal CApi.ValueRef descriptor;
	internal CApi.TypeRef carrier;
	internal CApi.TypeRef storage;
	internal CApi.ValueRef zero_store;
	internal CApi.ValueRef environment;
	internal CApi.ValueRef environment_store;
	internal CApi.ValueRef[] initializers;
	internal CApi.ValueRef[] values;
	internal NativeContinuationFamily family { get { return region.families[region.actions[creation].family]; } }
	internal CApi.ValueRef ready() {
		return family.environment == null ? zero_store : environment_store;
	}
	internal LlvmContinuationEnvironmentBinding (NativeContinuationRegionPlan region, int creation, CApi.ValueRef descriptor, CApi.TypeRef carrier, CApi.ValueRef zero_store) {
		this.region = region;
		this.creation = creation;
		this.descriptor = descriptor;
		this.carrier = carrier;
		this.zero_store = zero_store;
	}
	internal void verify() throws LlvmError {
		try {
			region.verify ();
		} catch (NativeAbiError error) {
			throw new LlvmError.VERIFICATION ("%s", error.message);
		}
		if (creation < 0 || creation >= region.actions.length || region.actions[creation].kind != ContinuationActionKind.CREATE || CApi.opcode (descriptor) != CApi.Opcode.ALLOCA || (void*) CApi.allocated_type (descriptor) != (void*) carrier || CApi.opcode (zero_store) != CApi.Opcode.STORE || CApi.operand_count (zero_store) != 2 || (void*) CApi.operand (zero_store, 0) != (void*) CApi.const_null (carrier) || (void*) CApi.operand (zero_store, 1) != (void*) descriptor) {
			throw new LlvmError.VERIFICATION ("continuation environment requires its exact created owner carrier");
		}
		var env = family.environment;
		if (env == null) {
			if (initialization != -1 || (void*) environment_store != null) {
				throw new LlvmError.VERIFICATION ("environment-free continuation must retain its zero publication");
			}
			return;
		}
		if (initialization <= creation || initialization >= region.actions.length || region.actions[initialization].kind != ContinuationActionKind.INITIALIZE || region.actions[initialization].owner != region.actions[creation].owner || (void*) CApi.is_instruction (environment) == null || initializers.length != env.leaves.length + (env.buffer == null ? 0 : 2) || values.length != initializers.length) {
			throw new LlvmError.VERIFICATION ("continuation environment requires complete initialization for its exact instance");
		}
		if (CApi.opcode (environment_store) != CApi.Opcode.STORE || CApi.operand_count (environment_store) != 2 || (void*) CApi.operand (environment_store, 0) != (void*) environment || !LlvmContinuationProjection.field (CApi.operand (environment_store, 1), carrier, descriptor, 3)) {
			throw new LlvmError.VERIFICATION ("continuation environment publication allocation/instance correspondence mismatch");
		}
		for (int i = 0; i < initializers.length; i++) {
			var store = initializers[i];
			string path = i < env.leaves.length ? env.leaves[i].field_path : (i - env.leaves.length + 1).to_string ();
			if (CApi.opcode (store) != CApi.Opcode.STORE || CApi.operand_count (store) != 2 || (void*) CApi.operand (store, 0) != (void*) values[i] || !LlvmContinuationProjection.path (CApi.operand (store, 1), storage, environment, path) || !LlvmBufferExchangeOrder.precedes (zero_store, store) || !LlvmBufferExchangeOrder.precedes (environment, store) || !LlvmBufferExchangeOrder.precedes (store, environment_store) || (i > 0 && !LlvmBufferExchangeOrder.precedes (initializers[i - 1], store))) {
				throw new LlvmError.VERIFICATION ("continuation initialized capture must precede environment publication");
			}
		}
	}
}

internal class LlvmContinuationPublicationBinding : Object {
	internal LlvmContinuationEnvironmentBinding origin;
	internal NativeContinuationFamily plan;
	internal CApi.ValueRef descriptor;
	internal CApi.TypeRef carrier;
	internal CApi.ValueRef selected;
	internal CApi.ValueRef predicate;
	internal CApi.ValueRef first;
	internal CApi.ValueRef second;
	internal CApi.ValueRef cancel;
	internal CApi.ValueRef destroy;
	internal CApi.ValueRef[] stores;
	internal LlvmContinuationPublicationBinding (NativeContinuationFamily plan, CApi.ValueRef descriptor, CApi.TypeRef carrier, CApi.ValueRef selected, CApi.ValueRef predicate, CApi.ValueRef first, CApi.ValueRef second, CApi.ValueRef cancel, CApi.ValueRef destroy, CApi.ValueRef[] stores, LlvmContinuationEnvironmentBinding origin) {
		this.plan = plan;
		this.descriptor = descriptor;
		this.carrier = carrier;
		this.selected = selected;
		this.predicate = predicate;
		this.first = first;
		this.second = second;
		this.cancel = cancel;
		this.destroy = destroy;
		this.stores = stores;
		this.origin = origin;
	}
	internal void verify() throws LlvmError {
		if (origin.family != plan || (void*) origin.descriptor != (void*) descriptor || (void*) origin.carrier != (void*) carrier) {
			throw new LlvmError.VERIFICATION ("continuation publication belongs to a different environment owner");
		}
		if (stores.length != 3 || (void*) first != (void*) second && (CApi.opcode (selected) != CApi.Opcode.SELECT || (void*) CApi.operand (selected, 0) != (void*) predicate || (void*) CApi.operand (selected, 1) != (void*) first || (void*) CApi.operand (selected, 2) != (void*) second) || (void*) first == (void*) second && (void*) selected != (void*) first) {
			throw new LlvmError.VERIFICATION ("continuation runtime selection code-family correspondence mismatch");
		}
		for (int i = 0; i < stores.length; i++) {
			var store = stores[i];
			var expected = i == 0 ? selected : i == 1 ? cancel : destroy;
			if (CApi.opcode (store) != CApi.Opcode.STORE || CApi.operand_count (store) != 2 || (void*) CApi.operand (store, 0) != (void*) expected || !LlvmContinuationProjection.field (CApi.operand (store, 1), carrier, descriptor, (uint) i) || !LlvmBufferExchangeOrder.precedes (origin.ready (), store) || (i > 0 && !LlvmBufferExchangeOrder.precedes (stores[i - 1], store))) {
				throw new LlvmError.VERIFICATION ("continuation publication operation-family/role correspondence mismatch");
			}
		}
		if (CApi.function_call_conv (first) != LlvmLowering.CALL_CONVENTION || CApi.function_call_conv (second) != LlvmLowering.CALL_CONVENTION || CApi.function_call_conv (cancel) != LlvmLowering.CALL_CONVENTION || (plan.environment != null && CApi.function_call_conv (destroy) != LlvmLowering.CALL_CONVENTION)) {
			throw new LlvmError.VERIFICATION ("continuation publication calling convention mismatch");
		}
	}
}

internal class LlvmContinuationMoveBinding : Object {
	internal CApi.ValueRef source;
	internal CApi.ValueRef destination;
	internal CApi.ValueRef snapshot;
	internal CApi.ValueRef store;
	internal CApi.ValueRef disarm;
	internal CApi.TypeRef carrier;
	internal LlvmContinuationMoveBinding (CApi.ValueRef source, CApi.ValueRef destination, CApi.ValueRef snapshot, CApi.ValueRef store, CApi.ValueRef disarm, CApi.TypeRef carrier) {
		this.source = source;
		this.destination = destination;
		this.snapshot = snapshot;
		this.store = store;
		this.disarm = disarm;
		this.carrier = carrier;
	}
	internal void verify() throws LlvmError {
		if (CApi.opcode (snapshot) != CApi.Opcode.LOAD || (void*) CApi.type_of (snapshot) != (void*) carrier || (void*) CApi.operand (snapshot, 0) != (void*) source || CApi.opcode (store) != CApi.Opcode.STORE || (void*) CApi.operand (store, 0) != (void*) snapshot || (void*) CApi.operand (store, 1) != (void*) destination || CApi.opcode (disarm) != CApi.Opcode.STORE || (void*) CApi.operand (disarm, 0) != (void*) CApi.const_null (carrier) || (void*) CApi.operand (disarm, 1) != (void*) source || (void*) CApi.next_instruction (snapshot) != (void*) store || (void*) CApi.next_instruction (store) != (void*) disarm) {
			throw new LlvmError.VERIFICATION ("continuation move requires one complete snapshot/store/source disarm");
		}
	}
}

internal class LlvmContinuationCallBinding : Object {
	internal NativeContinuationRegionPlan plan;
	internal ContinuationRole role;
	internal CApi.TypeRef signature;
	internal CApi.ValueRef call;
	internal CApi.ValueRef code;
	internal CApi.ValueRef environment;
	internal CApi.ValueRef argument;
	internal CApi.ValueRef descriptor;
	internal CApi.ValueRef code_address;
	internal CApi.ValueRef environment_address;
	internal CApi.TypeRef carrier;
	internal LlvmContinuationCallBinding (NativeContinuationRegionPlan plan, ContinuationRole role, CApi.TypeRef signature, CApi.ValueRef call, CApi.ValueRef code, CApi.ValueRef environment, CApi.ValueRef argument, CApi.ValueRef descriptor, CApi.ValueRef code_address, CApi.ValueRef environment_address, CApi.TypeRef carrier) {
		this.plan = plan;
		this.role = role;
		this.signature = signature;
		this.call = call;
		this.code = code;
		this.environment = environment;
		this.argument = argument;
		this.descriptor = descriptor;
		this.code_address = code_address;
		this.environment_address = environment_address;
		this.carrier = carrier;
	}
	internal void verify() throws LlvmError {
		try {
			plan.verify ();
		} catch (NativeAbiError error) {
			throw new LlvmError.VERIFICATION ("%s", error.message);
		}
		uint slot = role == ContinuationRole.STEP ? 0 : role == ContinuationRole.CANCEL_DRAIN ? 1 : 2;
		if (CApi.opcode (call) != CApi.Opcode.CALL || (void*) CApi.called_function_type (call) != (void*) signature || (void*) CApi.called_value (call) != (void*) code || CApi.instruction_call_conv (call) != LlvmLowering.CALL_CONVENTION || CApi.argument_count (call) != (role == ContinuationRole.DESTROY ? 1 : 2) || (void*) CApi.operand (call, 0) != (void*) environment || (role != ContinuationRole.DESTROY && (void*) CApi.operand (call, 1) != (void*) argument)) {
			throw new LlvmError.VERIFICATION ("continuation physical call signature/code/environment correspondence mismatch");
		}
		if (CApi.opcode (code) != CApi.Opcode.LOAD || CApi.opcode (environment) != CApi.Opcode.LOAD || (void*) CApi.operand (code, 0) != (void*) code_address || (void*) CApi.operand (environment, 0) != (void*) environment_address || !LlvmContinuationProjection.field (code_address, carrier, descriptor, slot) || !LlvmContinuationProjection.field (environment_address, carrier, descriptor, 3)) {
			throw new LlvmError.VERIFICATION ("continuation physical descriptor role/environment mismatch");
		}
	}
}

private class LlvmContinuationFamilyBinding : Object {
	internal NativeContinuationFamily plan;
	internal CApi.TypeRef storage;
	internal CApi.TypeRef invoke_type;
	internal CApi.TypeRef destroy_type;
	internal CApi.ValueRef[] entries;
	internal CApi.ValueRef destroy;
	internal int cancel;
	internal LlvmContinuationFamilyBinding (NativeContinuationFamily plan) {
		this.plan = plan;
		this.entries = new CApi.ValueRef[plan.entries.length];
	}
}

internal class LlvmContinuationLowering : Object {
	private LlvmModuleArtifact artifact;
	private LlvmTypeMapper types;
	private CApi.TypeRef pointer;
	private CApi.TypeRef integer;
	private CApi.TypeRef carrier;
	internal LlvmContinuationLowering (LlvmModuleArtifact artifact, LlvmTypeMapper types) {
		this.artifact = artifact;
		this.types = types;
		pointer = CApi.pointer_type_in_context (artifact.context, 0);
		integer = CApi.int32_type_in_context (artifact.context);
	}
	private CApi.TypeRef storage_type(NativeRecordElement record) throws LlvmError {
		var fields = new CApi.TypeRef[record.fields.length];
		for (int i = 0; i < fields.length; i++) {
			fields[i] = record.fields[i].record == null ? types.abi_type(record.fields[i].leaf) : storage_type (record.fields[i].record);
		}
		return CApi.struct_type_in_context (artifact.context, fields, fields.length, 0);
	}
	private CApi.ValueRef leaf_address(CApi.BuilderRef builder, CApi.TypeRef storage, CApi.ValueRef environment, string path) {
		var parts = path.split (".");
		var indices = new CApi.ValueRef[parts.length + 1];
		indices[0] = CApi.const_int (integer, 0, 0);
		for (int i = 0; i < parts.length; i++) {
			indices[i + 1] = CApi.const_int (integer, int.parse (parts[i]), 0);
		}
		return CApi.build_gep (builder, storage, environment, indices, indices.length, "continuation.state.address");
	}
	private CApi.ValueRef declare_entry(string symbol, CApi.TypeRef signature) {
		var entry = CApi.add_function (artifact.module, symbol, signature);
		CApi.set_linkage (entry, CApi.Linkage.INTERNAL);
		CApi.set_function_call_conv (entry, LlvmLowering.CALL_CONVENTION);
		return entry;
	}
	private LlvmContinuationFamilyBinding bind_family(NativeContinuationFamily plan, GenericArray<LlvmFunctionBinding> functions) throws LlvmError, NativeAbiError {
		var binding = new LlvmContinuationFamilyBinding (plan);
		CApi.TypeRef[] parameters = {
			pointer, integer
		};
		binding.invoke_type = CApi.function_type (integer, parameters, parameters.length, 0);
		binding.destroy_type = CApi.function_type (CApi.void_type_in_context (artifact.context), &pointer, 1, 0);
		int serial = artifact.continuation_family_count++;
		if (plan.environment != null) {
			binding.storage = storage_type (plan.environment.storage);
			var layout = new LlvmRecordLayoutBinding (plan.environment.storage, binding.storage);
			layout.allocated = true;
			artifact.record_layouts.add (layout);
		}
		for (int i = 0; i < plan.entries.length; i++) {
			var entry = plan.entries[i];
			var target = functions[entry.target_ordinal];
			var wrapper = declare_entry ("astra.continuation.%d.%d".printf (serial, i), binding.invoke_type);
			binding.entries[i] = wrapper;
			if (entry.role == ContinuationRole.CANCEL_DRAIN) {
				binding.cancel = i;
			}
			var builder = CApi.create_builder_in_context (artifact.context);
			var block = CApi.append_basic_block_in_context (artifact.context, wrapper, "entry");
			CApi.position_builder_at_end (builder, block);
			var env = plan.environment;
			int leaves = env == null ? 0 : (int) env.leaves.length;
			var arguments = new CApi.ValueRef[leaves + 1 + (env != null && env.buffer != null ? 2 : 0)];
			for (int n = 0; n < leaves; n++) {
				arguments[n] = CApi.build_load (builder, types.abi_type (env.leaves[n].abi_type), leaf_address (builder, binding.storage, CApi.get_param (wrapper, 0), env.leaves[n].field_path), "continuation.snapshot");
			}
			arguments[leaves] = CApi.get_param (wrapper, 1);
			if (env != null && env.buffer != null) {
				arguments[leaves + 1] = CApi.build_load (builder, pointer, CApi.build_struct_gep (builder, binding.storage, CApi.get_param (wrapper, 0), 1, "buffer.address"), "buffer.view.base");
				arguments[leaves + 2] = CApi.build_load (builder, integer, CApi.build_struct_gep (builder, binding.storage, CApi.get_param (wrapper, 0), 2, "count.address"), "buffer.view.count");
			}
			var result = CApi.build_call (builder, target.type, target.value, arguments, arguments.length, "continuation.body.result");
			CApi.set_instruction_call_conv (result, LlvmLowering.CALL_CONVENTION);
			CApi.ValueRef first = result;
			for (int n = 0; n < leaves; n++) {
				var leaf = leaves == 1 ? result : CApi.build_extract_value (builder, result, n, "continuation.result.leaf");
				if (n == 0) {
					first = leaf;
				}
				CApi.build_store (builder, leaf, leaf_address (builder, binding.storage, CApi.get_param (wrapper, 0), env.leaves[n].field_path));
			}
			CApi.build_ret (builder, first);
			CApi.dispose_builder (builder);
		}
		// No-environment descriptors have no allocation or destructor call.
		if (plan.environment != null) {
			binding.destroy = declare_entry ("astra.continuation.%d.destroy".printf (serial), binding.destroy_type);
			var builder = CApi.create_builder_in_context (artifact.context);
			var block = CApi.append_basic_block_in_context (artifact.context, binding.destroy, "entry");
			CApi.position_builder_at_end (builder, block);
			var scalars = new LlvmScalarLowering (artifact, types, builder, binding.destroy);
			var allocator = new LlvmBufferAllocation (artifact, builder, binding.destroy, scalars);
			var state = new LlvmBlockState (block);
			var environment = CApi.get_param (binding.destroy, 0);
			if (plan.environment.buffer != null) {
				var owner = CApi.build_load (builder, pointer, CApi.build_struct_gep (builder, binding.storage, environment, 1, "captured.owner.address"), "captured.owner");
				allocator.deallocate_buffer (owner, "continuation.buffer.destroy", state, plan.environment.buffer.context_origin);
			}
			allocator.deallocate (environment, "continuation.environment.destroy", state);
			CApi.build_ret_void (builder);
			CApi.dispose_builder (builder);
		}
		return binding;
	}
	internal CApi.ValueRef lower(NativeContinuationRegionPlan plan, CApi.ValueRef[] operands, GenericArray<LlvmFunctionBinding> functions, CApi.BuilderRef builder, LlvmBufferAllocation allocator, LlvmBlockState state) throws LlvmError, NativeAbiError {
		plan.verify ();
		carrier = storage_type (plan.descriptor_storage);
		var descriptor_layout = new LlvmRecordLayoutBinding (plan.descriptor_storage, carrier);
		descriptor_layout.fixed_count = 1;
		artifact.record_layouts.add (descriptor_layout);
		var families = new GenericArray<LlvmContinuationFamilyBinding> ();
		foreach (var family in plan.families) {
			families.add (bind_family (family, functions));
		}
		var descriptors = new HashTable<int, void*> (direct_hash, direct_equal);
		var owner_families = new HashTable<int, LlvmContinuationFamilyBinding> (direct_hash, direct_equal);
		var environments = new HashTable<int, LlvmContinuationEnvironmentBinding> (direct_hash, direct_equal);
		CApi.ValueRef result = CApi.const_null (integer);
		for (int position = 0; position < plan.actions.length; position++) {
			var action = plan.actions[position];
			if (action.kind == ContinuationActionKind.CREATE) {
				var slot = CApi.build_alloca (builder, carrier, "continuation.owner.%d".printf (action.owner));
				var zero_store = CApi.build_store (builder, CApi.const_null (carrier), slot);
				descriptors.insert (action.owner, (void*) slot);
				owner_families.insert (action.owner, families[action.family]);
				var origin = new LlvmContinuationEnvironmentBinding (plan, position, slot, carrier, zero_store);
				environments.insert (action.owner, origin);
				artifact.continuation_environments.add (origin);
				continue;
			}
			var descriptor = (CApi.ValueRef) descriptors.lookup (action.owner);
			var family = owner_families.lookup (action.owner);
			var env = family.plan.environment;
			switch (action.kind) {
			case ContinuationActionKind.INITIALIZE:
				var environment = allocator.allocate (CApi.const_int (integer, 1, 0), family.storage, "continuation.environment", state, true);
				var origin = environments.lookup (action.owner);
				origin.initialization = position;
				origin.storage = family.storage;
				origin.environment = environment;
				origin.initializers = new CApi.ValueRef[action.capture_count + (env.buffer == null ? 0 : 2)];
				origin.values = new CApi.ValueRef[origin.initializers.length];
				for (int i = 0; i < action.capture_count; i++) {
					origin.values[i] = operands[action.capture (i)];
					origin.initializers[i] = CApi.build_store (builder, operands[action.capture (i)], leaf_address (builder, family.storage, environment, env.leaves[i].field_path));
				}
				if (env.buffer != null) {
					var count = operands[action.operand];
					var buffer = allocator.allocate (count, integer, "continuation.capture.buffer", state);
					origin.values[action.capture_count] = buffer;
					origin.values[action.capture_count + 1] = count;
					origin.initializers[action.capture_count] = CApi.build_store (builder, buffer, CApi.build_struct_gep (builder, family.storage, environment, 1, "capture.base"));
					origin.initializers[action.capture_count + 1] = CApi.build_store (builder, count, CApi.build_struct_gep (builder, family.storage, environment, 2, "capture.count"));
				}
				origin.environment_store = CApi.build_store (builder, environment, CApi.build_struct_gep (builder, carrier, descriptor, 3, "continuation.publish.environment"));
				break;
			case ContinuationActionKind.PUBLISH:
				var selected = CApi.build_select (builder, operands[action.operand], family.entries[action.first_entry], family.entries[action.second_entry], "continuation.runtime.code");
				var destroy = env == null ? CApi.const_null(pointer) : family.destroy;
				CApi.ValueRef[] stores = {
					CApi.build_store (builder, selected, CApi.build_struct_gep (builder, carrier, descriptor, 0, "continuation.publish.step")), CApi.build_store (builder, family.entries[family.cancel], CApi.build_struct_gep (builder, carrier, descriptor, 1, "continuation.publish.cancel")), CApi.build_store (builder, destroy, CApi.build_struct_gep (builder, carrier, descriptor, 2, "continuation.publish.destroy"))
				};
				artifact.continuation_publications.add (new LlvmContinuationPublicationBinding (family.plan, descriptor, carrier, selected, operands[action.operand], family.entries[action.first_entry], family.entries[action.second_entry], family.entries[family.cancel], destroy, stores, environments.lookup (action.owner)));
				break;
			case ContinuationActionKind.MOVE:
				var destination = CApi.build_alloca (builder, carrier, "continuation.moved.%d".printf (action.destination));
				var whole = CApi.build_load (builder, carrier, descriptor, "continuation.whole.move");
				var store = CApi.build_store (builder, whole, destination);
				var disarm = CApi.build_store (builder, CApi.const_null (carrier), descriptor);
				artifact.continuation_moves.add (new LlvmContinuationMoveBinding (descriptor, destination, whole, store, disarm, carrier));
				descriptors.insert (action.destination, (void*) destination);
				owner_families.insert (action.destination, family);
				break;
			case ContinuationActionKind.CALL:
			case ContinuationActionKind.DESTROY:
				if (action.kind == ContinuationActionKind.DESTROY && env == null) {
					CApi.build_store (builder, CApi.const_null (carrier), descriptor);
					break;
				}
				var role = action.kind == ContinuationActionKind.DESTROY ? ContinuationRole.DESTROY : action.role;
				uint slot = role == ContinuationRole.STEP ? 0 : role == ContinuationRole.CANCEL_DRAIN ? 1 : 2;
				var code_address = CApi.build_struct_gep (builder, carrier, descriptor, slot, "continuation.code.address");
				var env_address = CApi.build_struct_gep (builder, carrier, descriptor, 3, "continuation.environment.address");
				var code = CApi.build_load (builder, pointer, code_address, "continuation.code");
				var address = CApi.build_load (builder, pointer, env_address, "continuation.environment");
				var signature = role == ContinuationRole.DESTROY ? family.destroy_type : family.invoke_type;
				var argument = role == ContinuationRole.DESTROY ? CApi.const_null (integer) : operands[action.operand];
				CApi.ValueRef[] arguments = {
					address, argument
				};
				var call = CApi.build_call (builder, signature, code, arguments, role == ContinuationRole.DESTROY ? 1 : 2, role == ContinuationRole.DESTROY ? "" : "continuation.invoked");
				CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
				artifact.continuation_calls.add (new LlvmContinuationCallBinding (plan, role, signature, call, code, address, argument, descriptor, code_address, env_address, carrier));
				if (role == ContinuationRole.DESTROY) {
					CApi.build_store (builder, CApi.const_null (carrier), descriptor);
				} else {
					result = call;
				} break;
			case ContinuationActionKind.RETAIN:
			case ContinuationActionKind.RELEASE:
			case ContinuationActionKind.BEGIN:
			case ContinuationActionKind.END:
				break;
			default:
				throw new LlvmError.LOWERING ("unknown verified continuation action");
			}
		}
		return result;
	}
}
}
