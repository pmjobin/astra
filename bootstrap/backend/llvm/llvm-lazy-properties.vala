// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.NativeAbi;
using Astra.Ssa;

namespace Astra.Backend.LLVM {
// Exact gate blocks and ordered roles, supplied by first-success lowering.
// Physical handles only; the artifact can outlive every predecessor.
internal class LlvmLazyBlock : Object {
	private CApi.BasicBlockRef block;
	private void*[] instructions;
	internal LlvmLazyBlock (CApi.BasicBlockRef block, CApi.ValueRef[] instructions) {
		this.block = block;
		this.instructions = new void*[instructions.length];
		for (int i = 0; i < instructions.length; i++) {
			this.instructions[i] = (void*) instructions[i];
		}
	}

	internal void verify() throws LlvmError {
		var current = CApi.first_instruction (block);
		for (int i = 0; i < instructions.length; i++) {
			if ((void*) current != instructions[i]) {
				throw new LlvmError.VERIFICATION ("lazy gate lost exact guarded initialization/cleanup/publication/reset order");
			}
			if (CApi.opcode (current) == CApi.Opcode.CALL) {
				if (CApi.call_attribute_count (current, uint.MAX) != 0) {
					throw new LlvmError.VERIFICATION ("lazy call gained an undeclared memory/effect promise");
				}
				for (uint p = 0; p <= CApi.argument_count (current); p++) {
					if (CApi.call_attribute_count (current, p) != 0) {
						throw new LlvmError.VERIFICATION ("lazy call gained an undeclared receiver/result/input promise");
					}
				}
			}
			current = CApi.next_instruction (current);
		}
		if ((void*) current != null) {
			throw new LlvmError.VERIFICATION ("lazy gate contains an undeclared transition or effect");
		}
	}

}
internal class LlvmLazyGateBinding : Object {
	private CApi.ValueRef function;
	private CApi.ValueRef body;
	private GenericArray<LlvmLazyBlock> blocks = new GenericArray<LlvmLazyBlock> ();
	private CApi.ValueRef result_slot;
	private CApi.TypeRef result_type;
	internal LlvmLazyGateBinding (CApi.ValueRef function, CApi.ValueRef body) {
		this.function = function;
		this.body = body;
	}

	internal void expect(CApi.BasicBlockRef block, CApi.ValueRef[] instructions) {
		blocks.add (new LlvmLazyBlock (block, instructions));
	}

	internal void expect_result(CApi.ValueRef slot, CApi.TypeRef type) {
		result_slot = slot;
		result_type = type;
	}

	internal void verify() throws LlvmError {
		verify_attributes (function);
		verify_attributes (body);
		if (CApi.count_basic_blocks (function) != blocks.length) {
			throw new LlvmError.VERIFICATION ("lazy gate lost exact first-success control shape");
		}
		foreach (var block in blocks) {
			block.verify ();
		}
		if ((void*) result_slot != null && (CApi.opcode (result_slot) != CApi.Opcode.ALLOCA || (void*) CApi.allocated_type (result_slot) != (void*) result_type || CApi.operand_count (result_slot) != 1 || (void*) CApi.operand (result_slot, 0) != (void*) CApi.const_int (CApi.type_of (CApi.operand (result_slot, 0)), 1, 0) || CApi.get_alignment (result_slot) != 1)) {
			throw new LlvmError.VERIFICATION ("lazy initializer lost complete private copied success storage");
		}
	}

	private static void verify_attributes(CApi.ValueRef value) throws LlvmError {
		if (CApi.attribute_count (value, uint.MAX) != 0) {
			throw new LlvmError.VERIFICATION ("lazy gate/initializer gained an undeclared memory/effect promise");
		}
		for (uint p = 0; p <= CApi.count_params (value); p++) {
			if (CApi.attribute_count (value, p) != 0) {
				throw new LlvmError.VERIFICATION ("lazy gate/initializer gained an undeclared receiver/result/input promise");
			}
		}
	}

}
internal class LlvmLazyProperties : Object {
	internal static void retain_construction_order(LlvmModuleArtifact artifact) {
		var seen = new HashTable<void*, bool> (direct_hash, direct_equal);
		foreach (var binding in artifact.class_values) {
			if (!binding.initializes_lazy_cache) {
				continue;
			}
			var function = CApi.block_parent (CApi.instruction_parent (binding.instruction));
			if (seen.contains ((void*) function)) {
				continue;
			}
			seen.insert ((void*) function, true);
			artifact.sum_sequences.add (new LlvmSumSequence (function, true));
		}
	}

	private static CApi.ValueRef address(LlvmModuleArtifact artifact, CApi.BuilderRef builder, CApi.TypeRef layout, CApi.ValueRef receiver, uint member, string name) {
		var result = CApi.build_struct_gep (builder, layout, receiver, member, name);
		artifact.class_addresses.add (new LlvmClassAddressBinding (result, receiver, layout, member));
		return result;
	}

	private static CApi.ValueRef read(LlvmModuleArtifact artifact, CApi.BuilderRef builder, CApi.TypeRef type, CApi.ValueRef source, string name) {
		var result = CApi.build_load (builder, type, source, name);
		CApi.set_alignment (result, 1);
		artifact.class_values.add (new LlvmClassValueBinding (result, CApi.Opcode.LOAD, type, new CApi.ValueRef[] { source }, "lazy guarded exact cache/result read", -1, -1, 1));
		return result;
	}

	private static CApi.ValueRef store(LlvmModuleArtifact artifact, CApi.BuilderRef builder, CApi.ValueRef value, CApi.ValueRef destination, string purpose) {
		var result = CApi.build_store (builder, value, destination);
		CApi.set_alignment (result, 1);
		artifact.class_values.add (new LlvmClassValueBinding (result, CApi.Opcode.STORE, CApi.void_type_in_context (artifact.context), new CApi.ValueRef[] { value, destination }, purpose, -1, -1, 1));
		return result;
	}

	private static CApi.ValueRef equal(LlvmModuleArtifact artifact, CApi.BuilderRef builder, CApi.ValueRef left, CApi.ValueRef right, string name) {
		var result = CApi.build_icmp (builder, CApi.IntPredicate.EQ, left, right, name);
		artifact.class_values.add (new LlvmClassValueBinding (result, CApi.Opcode.ICMP, CApi.int1_type_in_context (artifact.context), new CApi.ValueRef[] { left, right }, "lazy exact state/exception test", -1, (int) CApi.IntPredicate.EQ));
		return result;
	}

	private static CApi.ValueRef branch(LlvmModuleArtifact artifact, CApi.BuilderRef builder, CApi.ValueRef condition, CApi.BasicBlockRef yes, CApi.BasicBlockRef no) {
		var result = CApi.build_cond_br (builder, condition, yes, no);
		artifact.class_branches.add (new LlvmClassBranchBinding (result, condition, yes, no));
		return result;
	}

	private static CApi.ValueRef finish(LlvmModuleArtifact artifact, CApi.BuilderRef builder, CApi.ValueRef value) {
		var result = CApi.build_ret (builder, value);
		artifact.class_values.add (new LlvmClassValueBinding (result, CApi.Opcode.RET, CApi.void_type_in_context (artifact.context), new CApi.ValueRef[] { value }, "lazy unchanged success/exception return"));
		return result;
	}

	internal static void initialize(LlvmModuleArtifact artifact, LlvmTypeMapper types, LlvmStructRegistry structs, NativeAbiProgram native, CApi.BuilderRef builder, SsaClass owner, CApi.ValueRef receiver, string name) throws LlvmError {
		var plan = native.classes[owner.ordinal];
		if (plan.parent_ordinal >= 0) {
			bool inherited = false;
			for (int c = plan.parent_ordinal; c >= 0; c = native.classes[c].parent_ordinal) {
				if (native.classes[c].lazy_caches.length != 0) {
					inherited = true;
				}
			}
			if (inherited) {
				var parent = address (artifact, builder, structs.lookup (owner), receiver, 0, name + ".lazy.base");
				initialize (artifact, types, structs, native, builder, owner.parent_class, parent, name + ".base");
			}
		}
		foreach (var cache in plan.lazy_caches) {
			var state = address (artifact, builder, structs.lookup (owner), receiver, (uint) cache.state_member, name + ".lazy.%d.state".printf (cache.property_ordinal));
			store (artifact, builder, CApi.const_int (types.scalar (NativeScalarType.U8), 0, 0), state, "lazy exact declaring cache construction Empty");
		}
	}

	internal static void retire(LlvmModuleArtifact artifact, LlvmTypeMapper types, LlvmStructRegistry structs, CApi.BuilderRef builder, CApi.ValueRef function, SsaClass owner, NativeLazyCache cache, CApi.ValueRef receiver, LlvmFunctionBinding? destructor, LlvmBufferAllocation allocator, LlvmBlockState state, string name, LlvmClassRuntime classes, SsaClass cached_owner) throws LlvmError {
		var byte = types.scalar (NativeScalarType.U8);
		var pointer = types.scalar (NativeScalarType.PTR);
		var state_address = address (artifact, builder, structs.lookup (owner), receiver, (uint) cache.state_member, name + ".state.address");
		var value_address = address (artifact, builder, structs.lookup (owner), receiver, (uint) cache.value_member, name + ".value.address");
		var status = read (artifact, builder, byte, state_address, name + ".state");
		var ready = equal (artifact, builder, status, CApi.const_int (byte, 2, 0), name + ".ready");
		var release = CApi.append_basic_block_in_context (artifact.context, function, name + ".retire");
		var call = CApi.append_basic_block_in_context (artifact.context, function, name + ".destroy");
		var done = CApi.append_basic_block_in_context (artifact.context, function, name + ".done");
		branch (artifact, builder, ready, release, done);
		CApi.position_builder_at_end (builder, release);
		var cached = read (artifact, builder, pointer, value_address, name + ".owner");
		store (artifact, builder, CApi.const_null (pointer), value_address, "owned lazy cache disarm exact owner before destruction");
		store (artifact, builder, CApi.const_int (byte, 0, 0), state_address, "owned lazy Ready to Empty once before destruction");
		var vacant = equal (artifact, builder, cached, CApi.const_null (pointer), name + ".null");
		branch (artifact, builder, vacant, done, call);
		CApi.position_builder_at_end (builder, call);
		state.end = call;
		classes.release_owned (builder, function, allocator, cached_owner, cached, state, name);
		var finished = CApi.build_br (builder, done);
		artifact.class_values.add (new LlvmClassValueBinding (finished, CApi.Opcode.UNCOND_BR, CApi.void_type_in_context (artifact.context), new CApi.ValueRef[] { CApi.operand (finished, 0) }, "owned lazy retirement continuation"));
		CApi.position_builder_at_end (builder, done);
		state.end = done;
	}

	internal static LlvmFunctionBinding declare_body(LlvmModuleArtifact artifact, LlvmFunctionBinding gate, NativeLazyCache cache) {
		var body = CApi.add_function (artifact.module, "astra.lazy.body.%d.%d".printf (cache.class_ordinal, cache.property_ordinal), gate.type);
		CApi.set_linkage (body, CApi.Linkage.INTERNAL);
		CApi.set_function_call_conv (body, LlvmLowering.CALL_CONVENTION);
		return new LlvmFunctionBinding (gate.signature, gate.type, body);
	}

	internal static void lower_gate(LlvmModuleArtifact artifact, LlvmTypeMapper types, LlvmStructRegistry structs, SsaClass owner, NativeLazyCache cache, LlvmFunctionBinding gate, LlvmFunctionBinding body) throws LlvmError {
		var builder = CApi.create_builder_in_context (artifact.context);
		var witness = new LlvmLazyGateBinding (gate.value, body.value);
		var entry = CApi.append_basic_block_in_context (artifact.context, gate.value, "lazy.entry");
		var hit = CApi.append_basic_block_in_context (artifact.context, gate.value, "lazy.ready");
		var empty = CApi.append_basic_block_in_context (artifact.context, gate.value, "lazy.check.empty");
		var cold = CApi.append_basic_block_in_context (artifact.context, gate.value, "lazy.initialize");
		var trap = CApi.append_basic_block_in_context (artifact.context, gate.value, "lazy.recursive.trap");
		var receiver = CApi.get_param (gate.value, 0);
		var byte = types.scalar (NativeScalarType.U8);
		var value_type = types.abi_type (cache.value_type);
		var pointer = types.scalar (NativeScalarType.PTR);
		bool throwing = gate.signature.exception_plan != null;
		CApi.position_builder_at_end (builder, entry);
		var state_address = address (artifact, builder, structs.lookup (owner), receiver, (uint) cache.state_member, "lazy.state.address");
		var value_address = address (artifact, builder, structs.lookup (owner), receiver, (uint) cache.value_member, "lazy.value.address");
		var state = read (artifact, builder, byte, state_address, "lazy.state");
		var ready = equal (artifact, builder, state, CApi.const_int (byte, 2, 0), "lazy.is.ready");
		var selected = branch (artifact, builder, ready, hit, empty);
		witness.expect (entry, new CApi.ValueRef[] { state_address, value_address, state, ready, selected });
		CApi.position_builder_at_end (builder, hit);
		var cached = read (artifact, builder, value_type, value_address, "lazy.cached");
		if (throwing) {
			var published = store (artifact, builder, cached, CApi.get_param (gate.value, 1), "lazy Ready copied success channel");
			var returned = finish (artifact, builder, CApi.const_null (pointer));
			witness.expect (hit, new CApi.ValueRef[] { cached, published, returned });
		} else {
			var returned = finish (artifact, builder, cached);
			witness.expect (hit, new CApi.ValueRef[] { cached, returned });
		}
		CApi.position_builder_at_end (builder, empty);
		var vacant = equal (artifact, builder, state, CApi.const_int (byte, 0, 0), "lazy.is.empty");
		var entered = branch (artifact, builder, vacant, cold, trap);
		witness.expect (empty, new CApi.ValueRef[] { vacant, entered });
		CApi.position_builder_at_end (builder, trap);
		uint id = CApi.lookup_intrinsic_id ("llvm.trap", 9);
		var fatal = CApi.get_intrinsic_declaration (artifact.module, id, null, 0);
		var fatal_type = CApi.intrinsic_get_type (artifact.context, id, null, 0);
		var trapped = CApi.build_call (builder, fatal_type, fatal, null, 0, "");
		CApi.set_instruction_call_conv (trapped, CApi.CallConv.C);
		artifact.class_calls.add (new LlvmClassCallBinding (trapped, fatal, fatal_type, new CApi.ValueRef[CApi.count_params (fatal)], CApi.CallConv.C, "lazy recursive non-unwinding trap"));
		var unreachable = CApi.build_unreachable (builder);
		witness.expect (trap, new CApi.ValueRef[] { trapped, unreachable });
		CApi.position_builder_at_end (builder, cold);
		var evaluating = store (artifact, builder, CApi.const_int (byte, 1, 0), state_address, "lazy Empty to Evaluating before initializer and local cleanup");
		CApi.ValueRef computed;
		if (throwing) {
			var success = CApi.append_basic_block_in_context (artifact.context, gate.value, "lazy.success");
			var failure = CApi.append_basic_block_in_context (artifact.context, gate.value, "lazy.failure");
			var result_slot = CApi.build_alloca (builder, value_type, "lazy.completed.result");
			CApi.set_alignment (result_slot, 1);
			witness.expect_result (result_slot, value_type);
			CApi.ValueRef[] arguments = {
				receiver, result_slot
			};
			var exception = CApi.build_call (builder, body.type, body.value, arguments, arguments.length, "lazy.original.exception");
			CApi.set_instruction_call_conv (exception, LlvmLowering.CALL_CONVENTION);
			artifact.class_calls.add (new LlvmClassCallBinding (exception, body.value, body.type, arguments, LlvmLowering.CALL_CONVENTION, "lazy initializer with exact receiver and private success channel"));
			var succeeded = equal (artifact, builder, exception, CApi.const_null (pointer), "lazy.succeeded");
			var outcome = branch (artifact, builder, succeeded, success, failure);
			witness.expect (cold, new CApi.ValueRef[] { evaluating, result_slot, exception, succeeded, outcome });
			CApi.position_builder_at_end (builder, failure);
			var reset = store (artifact, builder, CApi.const_int (byte, 0, 0), state_address, "lazy exact failed cache reset after initializer cleanup");
			var propagated = finish (artifact, builder, exception);
			witness.expect (failure, new CApi.ValueRef[] { reset, propagated });
			CApi.position_builder_at_end (builder, success);
			computed = read (artifact, builder, value_type, result_slot, "lazy.completed.value");
			var cached_value = store (artifact, builder, computed, value_address, "lazy exact successful copied value before Ready");
			var publication = store (artifact, builder, CApi.const_int (byte, 2, 0), state_address, "lazy Evaluating to Ready after initializer cleanup and cache value");
			var published = store (artifact, builder, computed, CApi.get_param (gate.value, 1), "lazy cold copied success channel");
			var returned = finish (artifact, builder, CApi.const_null (pointer));
			witness.expect (success, new CApi.ValueRef[] { computed, cached_value, publication, published, returned });
		} else {
			CApi.ValueRef[] arguments = {
				receiver
			};
			computed = CApi.build_call (builder, body.type, body.value, arguments, arguments.length, "lazy.completed.value");
			CApi.set_instruction_call_conv (computed, LlvmLowering.CALL_CONVENTION);
			artifact.class_calls.add (new LlvmClassCallBinding (computed, body.value, body.type, arguments, LlvmLowering.CALL_CONVENTION, "lazy initializer with exact receiver"));
			var cached_value = store (artifact, builder, computed, value_address, "lazy exact successful copied value before Ready");
			var publication = store (artifact, builder, CApi.const_int (byte, 2, 0), state_address, "lazy Evaluating to Ready after initializer cleanup and cache value");
			var returned = finish (artifact, builder, computed);
			witness.expect (cold, new CApi.ValueRef[] { evaluating, computed, cached_value, publication, returned });
		}
		CApi.dispose_builder (builder);
		artifact.lazy_gates.add (witness);
		artifact.class_functions.add (new LlvmClassFunctionBinding (gate.value, gate.type));
		artifact.class_functions.add (new LlvmClassFunctionBinding (body.value, body.type));
	}

}
}
