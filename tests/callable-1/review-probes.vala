// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Regression probes reproduced on the exact CALLABLE-1 baseline before repair.
// Generic LLVM validity and restored controls are checked separately.
// Never execute a corrupted LLVM artifact. Only its verifiers are exercised.
using Astra.NativeAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.Continuations {
private void review_slice_channels(bool wrong_base) {
	try {
		var source = build ();
		var native = NativeAbiBuilder.build (source);
		var plan = native.continuations[0];
		plan.verify ();
		var family = plan.families[0];
		assert (family.environment != null && family.environment.buffer != null);
		var signature = family.entries[0].body_signature;
		assert (signature != null);
		int position = (int) family.environment.leaves.length + 1;
		var old = signature.parameters[position];
		var original = old.abi_type as NativeSliceType;
		assert (original != null && original.base_type == NativeScalarType.PTR && original.length_type == NativeScalarType.I32);
		var malformed = new NativeSliceType (wrong_base ? NativeScalarType.I32 : NativeScalarType.PTR, wrong_base ? NativeScalarType.I32 : NativeScalarType.F64);
		signature.parameters[position] = new NativeParameter.typed (old.span, old.name_span, old.name, old.ordinal, malformed);
		bool detached_rejected = false;
		try {
			plan.verify ();
		} catch (NativeAbiError error) {
			detached_rejected = true;
			Test.message ("detached rejection: %s", error.message);
		}
		// A whole-program guard is a control, not a substitute for detached verification.
		bool enclosing_rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			enclosing_rejected = true;
			Test.message ("enclosing rejection: %s", error.message);
		}
		signature.parameters[position] = old;
		plan.verify ();
		NativeAbiVerifier.verify (native);
		Test.message ("detached_rejected=%s enclosing_rejected=%s", detached_rejected.to_string (), enclosing_rejected.to_string ());
		assert (enclosing_rejected);
		assert (detached_rejected);
	} catch (GLib.Error error) {
		GLib.error ("probe setup failed: %s", error.message);
	}
}

private void review_bad_slice_base() {
	review_slice_channels (true);
}

private void review_bad_slice_length() {
	review_slice_channels (false);
}

private void review_generic_llvm_valid(LlvmModuleArtifact lowered) {
	char* message;
	int failed = CApi.verify_module (lowered.module, CApi.VerifierFailureAction.RETURN_STATUS, out message);
	if (failed != 0 && message != null) {
		Test.message ("ordinary LLVM verifier: %s", (string) message);
	}
	if (message != null) {
		CApi.dispose_message (message);
	}
	// Failure here invalidates the test setup: it did not isolate Astra correspondence.
	assert (failed == 0);
	Test.message ("ordinary LLVM verification passed");
}

private bool review_astra_rejects(LlvmModuleArtifact lowered) {
	try {
		lowered.verify ();
	} catch (LlvmError error) {
		Test.message ("Astra rejection: %s", error.message);
		return true;
	}
	return false;
}

private void review_nonzero_descriptor_index(bool code_slot) {
	try {
		var lowered = artifact ();
		var binding = lowered.continuation_calls[0];
		var address = code_slot ? binding.code_address : binding.environment_address;
		assert (CApi.opcode (address) == CApi.Opcode.GEP);
		assert (CApi.operand_count (address) == 3);
		var original = CApi.operand (address, 1);
		assert (CApi.const_int_zext (original) == 0);
		// Same descriptor SSA base and same final role field, but one complete
		// descriptor past the allocation. This remains well-typed LLVM.
		CApi.set_operand (address, 1, CApi.const_int (CApi.type_of (original), 1, 0));
		review_generic_llvm_valid (lowered);
		bool rejected = review_astra_rejects (lowered);
		CApi.set_operand (address, 1, original);
		lowered.verify ();
		Test.message ("restored artifact verification passed");
		assert (rejected);
	} catch (GLib.Error error) {
		GLib.error ("probe setup failed: %s", error.message);
	}
}

private void review_bad_code_base_index() {
	review_nonzero_descriptor_index (true);
}

private void review_bad_environment_base_index() {
	review_nonzero_descriptor_index (false);
}

private CApi.ValueRef review_environment_store(LlvmModuleArtifact lowered, LlvmContinuationPublicationBinding publication) {
	int ordinal = lowered.continuation_calls[0].plan.function_ordinal;
	var function = CApi.named_function (lowered.module, "astra.fn.%d".printf (ordinal));
	assert ((void*) function != null);
	for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
		for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
			if (CApi.opcode (instruction) != CApi.Opcode.STORE) {
				continue;
			}
			var destination = CApi.operand (instruction, 1);
			if ((void*) CApi.is_instruction (destination) == null || CApi.opcode (destination) != CApi.Opcode.GEP) {
				continue;
			}
			if (CApi.operand_count (destination) != 3 || (void*) CApi.gep_source_type (destination) != (void*) publication.carrier || (void*) CApi.operand (destination, 0) != (void*) publication.descriptor) {
				continue;
			}
			if (CApi.const_int_zext (CApi.operand (destination, 1)) == 0 && CApi.const_int_zext (CApi.operand (destination, 2)) == 3) {
				return instruction;
			}
		}
	}
	assert_not_reached ();
}

private void review_wrong_published_environment() {
	try {
		var lowered = artifact ();
		assert (lowered.continuation_publications.length >= 2);
		var first_publication = lowered.continuation_publications[0];
		var second_publication = lowered.continuation_publications[1];
		assert (first_publication.plan == second_publication.plan);
		assert ((void*) first_publication.descriptor != (void*) second_publication.descriptor);
		var first_store = review_environment_store (lowered, first_publication);
		var second_store = review_environment_store (lowered, second_publication);
		var first_environment = CApi.operand (first_store, 0);
		var second_environment = CApi.operand (second_store, 0);
		assert ((void*) first_environment != (void*) second_environment);
		// Earlier first allocation dominates the second descriptor publication.
		// Change only the stored pointer, not code slots, metadata, or call operands.
		CApi.set_operand (second_store, 0, first_environment);
		review_generic_llvm_valid (lowered);
		bool rejected = review_astra_rejects (lowered);
		CApi.set_operand (second_store, 0, second_environment);
		lowered.verify ();
		Test.message ("restored artifact verification passed");
		assert (rejected);
	} catch (GLib.Error error) {
		GLib.error ("probe setup failed: %s", error.message);
	}
}

private void review_retained_signature(int variant) {
	try {
		Astra.Ssa.SsaProgram? source = build ();
		var predecessor = WeakRef (source);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		var graph = WeakRef (native);
		var plan = native.continuations[0];
		source = null;
		native = null;
		assert (predecessor.get () == null && graph.get () == null);
		plan.verify ();
		var family = plan.families[0];
		var entry = family.entries[0];
		var original = entry.body_signature;
		var parameters = new GenericArray<NativeParameter> ();
		foreach (var parameter in original.parameters) {
			parameters.add (parameter);
		}
		int position = (int) family.environment.leaves.length + 1;
		var old = parameters[position];
		NativeAbiType replacement = old.abi_type;
		if (variant == 0) {
			replacement = new NativeSliceType (NativeScalarType.I32, NativeScalarType.I32);
		}
		if (variant == 1) {
			replacement = new NativeSliceType (NativeScalarType.PTR, NativeScalarType.F64);
		}
		if (variant == 4) {
			replacement = new NativeTextSliceType ();
		}
		if (variant == 5) {
			replacement = new NativeRecordSliceType (family.environment.state_record);
		}
		parameters[position] = new NativeParameter.typed (old.span, old.name_span, old.name, variant == 3 ? 0 : old.ordinal, replacement);
		var signature = new NativeSignature (variant == 2 ? NativeAbiVersion.SCALAR_V0 : variant == 4 || variant == 5 ? NativeAbiVersion.STRUCT_ELEMENTS_V11 : original.abi_version, parameters, original.result);
		signature.struct_result = original.struct_result;
		foreach (var group in original.struct_parameters) {
			signature.struct_parameters.add (variant == 6 ? new NativeStructParameterPlan (1, group.first_leaf, group.value_plan) : group);
		}
		family.entries[0] = new NativeContinuationEntry (entry.identity, entry.role, entry.environment, entry.target_ordinal, signature);
		bool rejected = false;
		try {
			plan.verify ();
		} catch (NativeAbiError error) {
			Test.message ("retained signature rejection: %s", error.message);
			rejected = true;
		}
		family.entries[0] = entry;
		plan.verify ();
		assert (rejected == (variant != 7));
	} catch (GLib.Error error) {
		GLib.error ("retained signature setup failed: %s", error.message);
	}
}

private void review_signature_case() {
	var path = Test.get_path ();
	review_retained_signature (int.parse (path.substring (path.length - 2)));
}

private void review_publication_mutation(int variant) {
	try {
		var lowered = artifact ();
		var publication = lowered.continuation_publications[0];
		var origin = publication.origin;
		CApi.ValueRef instruction;
		CApi.ValueRef replacement;
		uint operand;
		if (variant == 0) {
			instruction = CApi.operand (publication.stores[0], 1);
			operand = 1;
			replacement = CApi.const_int (CApi.type_of (CApi.operand (instruction, operand)), 1, 0);
		} else if (variant == 1) {
			instruction = lowered.continuation_publications[1].origin.environment_store;
			operand = 1;
			replacement = CApi.operand (origin.environment_store, 1);
		} else if (variant == 2) {
			instruction = CApi.operand (origin.environment_store, 1);
			operand = 1;
			replacement = CApi.const_int (CApi.type_of (CApi.operand (instruction, operand)), 1, 0);
		} else if (variant == 3) {
			instruction = CApi.operand (origin.initializers[0], 1);
			operand = 1;
			replacement = CApi.const_int (CApi.type_of (CApi.operand (instruction, operand)), 1, 0);
		} else if (variant == 4) {
			instruction = origin.initializers[0];
			operand = 0;
			replacement = CApi.const_null (CApi.type_of (CApi.operand (instruction, 0)));
		} else if (variant == 7) {
			instruction = lowered.continuation_publications[3].origin.zero_store;
			operand = 1;
			replacement = publication.descriptor;
		} else {
			instruction = variant == 5 ? origin.initializers[origin.initializers.length - 1] : publication.stores[0];
			var next = CApi.next_instruction (instruction);
			var builder = CApi.create_builder_in_context (lowered.context);
			CApi.remove_instruction (instruction);
			CApi.position_builder_before (builder, variant == 5 ? publication.selected : lowered.continuation_calls[0].call);
			CApi.insert_instruction (builder, instruction);
			review_generic_llvm_valid (lowered);
			bool rejected = review_astra_rejects (lowered);
			CApi.remove_instruction (instruction);
			CApi.position_builder_before (builder, next);
			CApi.insert_instruction (builder, instruction);
			CApi.dispose_builder (builder);
			lowered.verify ();
			assert (rejected);
			return;
		}
		var original = CApi.operand (instruction, operand);
		CApi.set_operand (instruction, operand, replacement);
		review_generic_llvm_valid (lowered);
		bool rejected = review_astra_rejects (lowered);
		CApi.set_operand (instruction, operand, original);
		lowered.verify ();
		assert (rejected);
	} catch (GLib.Error error) {
		GLib.error ("publication mutation setup failed: %s", error.message);
	}
}

private void review_publication_case() {
	var path = Test.get_path ();
	review_publication_mutation (int.parse (path.substring (path.length - 2)));
}

private void review_all_operation_projections() {
	try {
		var lowered = artifact ();
		bool step = false;
		bool cancel = false;
		bool destroy = false;
		foreach (var call in lowered.continuation_calls) {
			step |= call.role == Astra.Continuations.ContinuationRole.STEP;
			cancel |= call.role == Astra.Continuations.ContinuationRole.CANCEL_DRAIN;
			destroy |= call.role == Astra.Continuations.ContinuationRole.DESTROY;
			CApi.ValueRef[] addresses = {
				call.code_address, call.environment_address
			};
			foreach (var address in addresses) {
				var original = CApi.operand (address, 1);
				CApi.set_operand (address, 1, CApi.const_int (CApi.type_of (original), 1, 0));
				review_generic_llvm_valid (lowered);
				bool rejected = review_astra_rejects (lowered);
				CApi.set_operand (address, 1, original);
				lowered.verify ();
				assert (rejected);
			}
		}
		assert (step && cancel && destroy);
		var address = lowered.continuation_calls[0].code_address;
		var original = CApi.operand (address, 1);
		CApi.set_operand (address, 1, CApi.const_int (CApi.int_type_in_context (lowered.context, 64), 0, 0));
		review_generic_llvm_valid (lowered);
		lowered.verify ();
		CApi.set_operand (address, 1, original);
		lowered.verify ();
	} catch (GLib.Error error) {
		GLib.error ("operation projection setup failed: %s", error.message);
	}
}

private void review_environment_free_move() {
	try {
		Astra.Ssa.SsaProgram? source = build ();
		var region = region_of (source);
		int insertion = (int) region.actions.length - 4;
		region.actions.insert (insertion, new Astra.Continuations.ContinuationAction (Astra.Continuations.ContinuationActionKind.MOVE, 4, 5));
		for (int i = insertion + 1; i < region.actions.length; i++) {
			region.actions[i] = replace_owner (region.actions[i], 5);
		}
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		Astra.CAbi.CAbiProgram? foreign = Astra.CAbi.CAbiBuilder.build (source, native);
		var lowered = LlvmLowering.lower (source, native, foreign);
		source = null;
		native = null;
		foreign = null;
		lowered.verify ();
		assert (lowered.continuation_moves.length == 2 && lowered.continuation_calls.length == 11);
	} catch (GLib.Error error) {
		GLib.error ("environment-free move setup failed: %s", error.message);
	}
}

private void register_review_probes() {
	Test.add_func ("/review-callable/v01/wrong-slice-base", review_bad_slice_base);
	Test.add_func ("/review-callable/v01/wrong-slice-length", review_bad_slice_length);
	Test.add_func ("/review-callable/v02/nonzero-code-base-index", review_bad_code_base_index);
	Test.add_func ("/review-callable/v02/nonzero-environment-base-index", review_bad_environment_base_index);
	Test.add_func ("/review-callable/v03/wrong-published-environment", review_wrong_published_environment);
	for (int i = 0; i < 8; i++) {
		Test.add_func ("/review-callable/retained-signature/%02d".printf (i), review_signature_case);
		Test.add_func ("/review-callable/publication/%02d".printf (i), review_publication_case);
	}
	Test.add_func ("/review-callable/all-operation-projections", review_all_operation_projections);
	Test.add_func ("/review-callable/environment-free-move", review_environment_free_move);
}

}
