// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.EnumLlvm {
private LlvmModuleArtifact artifact() throws GLib.Error {
	ParseResult? parsed = Parser.parse (new SourceFile.from_text ("sum-lifetime.astra", "enum Pair{Value(int left,int right),Empty} Pair produce(int a,int b){return Pair.Value(a,b);} Pair identity(Pair a,Pair b){return a;} int read(Pair p){match(p){case Pair.Value(right=y,left=x):{return x*10+y;}else:{return -1;}}} struct Header{int version;int size;} enum Composite{Ready(Header header,Pair pair),Empty} Composite pack(Pair pair){Header header={version=7,size=211};return Composite.Ready(header,pair);} int read_composite(Composite value){match(value){case Composite.Ready(header,pair):{return header.version+read(pair);}else:{return 0;}}} enum VectorPayload{Value(f32<4> value),Empty} VectorPayload vector_put(f32<4> value){return VectorPayload.Value(value);} Pair review_empty(){return Pair.Empty();} Composite review_empty_composite(){return Composite.Empty();} VectorPayload review_empty_vector(){return VectorPayload.Empty();} Pair review_pair(int a,int b){var first=Pair.Value(a,b);var second=Pair.Value(b,a);return identity(first,second);} int main(){var a=produce(2,3);var b=produce(4,5);var c=identity(a,b);return read(c)-23;}"));
	assert (parsed.diagnostic == null);
	var syntax = WeakRef (parsed.unit);
	SemanticResult? checked = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked.diagnostic == null);
	parsed = null;
	assert (syntax.get () == null);
	var checked_function = WeakRef (checked.program.functions[0]);
	CoreProgram? core = CoreBuilder.build (checked.program);
	checked = null;
	assert (checked_function.get () == null);
	CoreVerifier.verify (core);
	var core_function = WeakRef (core.functions[0]);
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	assert (core_function.get () == null);
	CfgVerifier.verify (cfg);
	var cfg_function = WeakRef (cfg.functions[0]);
	SsaProgram? ssa = SsaBuilder.build (cfg);
	cfg = null;
	assert (cfg_function.get () == null);
	SsaVerifier.verify (ssa);
	var ssa_function = WeakRef (ssa.functions[0]);
	NativeAbiProgram? native = NativeAbiBuilder.build (ssa);
	CAbiProgram? foreign = CAbiBuilder.build (ssa, native);
	var native_function = WeakRef (native.functions[0]);
	var result = LlvmLowering.lower (ssa, native, foreign);
	ssa = null;
	native = null;
	foreign = null;
	assert (ssa_function.get () == null && native_function.get () == null);
	result.verify ();
	return result;
}

private void ordinary_llvm_accepts(LlvmModuleArtifact artifact) {
	char* message;
	int failed = CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message);
	string text = message == null ? "" : (string) message;
	if (message != null) {
		CApi.dispose_message (message);
	}
	if (failed != 0) {
		GLib.error ("ordinary LLVM mutation failed: %s", text);
	}
	Test.message ("ordinary LLVM accepted structurally valid mutation: %s", text);
}

private void positive() {
	try {
		var result = artifact ();
		assert (result.sum_layouts.length == 3 && result.sum_accesses.length >= 3 && result.sum_copies.length >= 3 && result.sum_calls.length >= 4);
		var target = new LlvmTargetMachineArtifact ();
		target.configure (result);
		result.verify ();
		assert (result.sum_layouts[0].size == 12 && result.sum_layouts[0].alignment == 4);
		assert (result.sum_layouts[1].size == 24 && result.sum_layouts[1].alignment == 4);
		assert (result.sum_layouts[2].size == 32 && result.sum_layouts[2].alignment == 16);
		foreach (var layout in result.sum_layouts) {
			Test.message ("carrier %s size=%s alignment=%u payload_offset=%s", layout.plan.identity.name, layout.size.to_string (), layout.alignment, layout.payload_offset.to_string ());
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void malformed() {
	for (int mutation = 0; mutation < 16; mutation++) {
		try {
			var result = artifact ();
			var access = result.sum_accesses[1];
			var right = result.sum_accesses[2];
			var projection = result.sum_projections[0];
			var copy = result.sum_copies[0];
			var left_value = CApi.operand (access.instruction, 0);
			var right_address = CApi.operand (right.instruction, 1);
			var field_index = CApi.operand (projection.address, 2);
			var field = projection.field;
			var root = projection.root;
			var copy_destination = CApi.operand (copy.instruction, 0);
			var copy_bytes = CApi.operand (copy.instruction, 2);
			var copy_next = CApi.next_instruction (copy.instruction);
			CApi.ValueRef auxiliary = (CApi.ValueRef) null;
			CApi.ValueRef auxiliary_operand = (CApi.ValueRef) null;
			uint auxiliary_index = 0;
			CApi.ValueRef moved_instruction = (CApi.ValueRef) null;
			CApi.ValueRef moved_next = (CApi.ValueRef) null;
			var tag_value = CApi.operand (result.sum_accesses[0].instruction, 0);
			CApi.ValueRef changed_call = (CApi.ValueRef) null;
			CApi.ValueRef call_result = (CApi.ValueRef) null;
			if (mutation == 0) {
				CApi.set_operand (access.instruction, 0, CApi.operand (right.instruction, 0));
			}
			if (mutation == 1) {
				CApi.set_operand (right.instruction, 1, CApi.operand (access.instruction, 1));
			}
			if (mutation == 2 || mutation == 3) {
				CApi.set_operand (projection.address, 2, CApi.const_int (CApi.int32_type_in_context (result.context), 1, 0));
				if (mutation == 3) {
					projection.field = projection.layout.plan.variants[0].fields[1].identity;
				}
			}
			if (mutation == 4) {
				CApi.set_operand (copy.instruction, 0, CApi.operand (copy.instruction, 1));
			}
			if (mutation == 5) {
				CApi.set_operand (copy.instruction, 2, CApi.const_int (CApi.int_type_in_context (result.context, 64), 8, 0));
			}
			if (mutation == 6) {
				var builder = CApi.create_builder_in_context (result.context);
				CApi.remove_instruction (copy.instruction);
				CApi.position_builder_before (builder, right.instruction);
				CApi.insert_instruction (builder, copy.instruction);
				CApi.dispose_builder (builder);
			}
			if (mutation == 7) {
				projection.root = CApi.operand (copy.instruction, 0);
				CApi.set_operand (projection.payload, 0, projection.root);
			}
			if (mutation == 8) {
				CApi.set_operand (result.sum_accesses[0].instruction, 0, CApi.const_int (CApi.int32_type_in_context (result.context), 1, 0));
			}
			if (mutation == 9) {
				bool changed = false;
				foreach (var call in result.sum_calls) {
					if (CApi.argument_count (call.instruction) == 3 && (void*) CApi.type_of (CApi.operand (call.instruction, 1)) == (void*) CApi.pointer_type_in_context (result.context, 0)) {
						changed_call = call.instruction;
						call_result = CApi.operand (call.instruction, 0);
						CApi.set_operand (call.instruction, 0, CApi.operand (call.instruction, 1));
						changed = true;
						break;
					}
				}
				assert (changed);
			}
			if (mutation == 10) {
				foreach (var address in result.sum_addresses) {
					size_t length;
					if (CApi.value_name (address.instruction, out length).has_prefix ("sum.record.leaf")) {
						auxiliary = address.instruction;
						auxiliary_index = 2;
						auxiliary_operand = CApi.operand (auxiliary, 2);
						CApi.set_operand (auxiliary, 2, CApi.const_int (CApi.int32_type_in_context (result.context), CApi.const_int_zext (auxiliary_operand) == 0 ? 1 : 0, 0));
						break;
					}
				}
				assert ((void*) auxiliary != null);
			}
			if (mutation == 11) {
				auxiliary = result.sum_reads[1].instruction;
				auxiliary_operand = CApi.operand (auxiliary, 0);
				CApi.set_operand (auxiliary, 0, CApi.operand (result.sum_reads[0].instruction, 0));
			}
			if (mutation == 12) {
				auxiliary = result.sum_dispatches[0].instruction;
				auxiliary_operand = CApi.operand (auxiliary, 0);
				CApi.set_operand (auxiliary, 0, CApi.const_int (CApi.int32_type_in_context (result.context), 1, 0));
			}
			if (mutation == 13) {
				foreach (var binding in result.sum_copies) {
					size_t length;
					if (CApi.value_name (CApi.operand (binding.instruction, 0), out length).has_prefix ("sum.field.address")) {
						auxiliary = binding.instruction;
						auxiliary_index = 1;
						auxiliary_operand = CApi.operand (auxiliary, 1);
						CApi.set_operand (auxiliary, 1, CApi.operand (auxiliary, 0));
						break;
					}
				}
				assert ((void*) auxiliary != null);
			}
			if (mutation == 14) {
				foreach (var call in result.sum_calls) {
					foreach (var binding in result.sum_copies) {
						if ((void*) CApi.operand (binding.instruction, 1) == (void*) CApi.operand (call.instruction, 0) && LlvmBufferExchangeOrder.precedes (call.instruction, binding.instruction)) {
							moved_instruction = binding.instruction;
							moved_next = CApi.next_instruction (moved_instruction);
							var builder = CApi.create_builder_in_context (result.context);
							CApi.remove_instruction (moved_instruction);
							CApi.position_builder_before (builder, call.instruction);
							CApi.insert_instruction (builder, moved_instruction);
							CApi.dispose_builder (builder);
							break;
						}
					}
					if ((void*) moved_instruction != null) {
						break;
					}
				}
				assert ((void*) moved_instruction != null);
			}
			if (mutation == 15) {
				moved_instruction = access.instruction;
				moved_next = CApi.next_instruction (moved_instruction);
				var builder = CApi.create_builder_in_context (result.context);
				CApi.remove_instruction (moved_instruction);
				CApi.position_builder_before (builder, copy_next);
				CApi.insert_instruction (builder, moved_instruction);
				CApi.dispose_builder (builder);
			}
			Test.message ("testing physical mutation %d", mutation);
			ordinary_llvm_accepts (result);
			bool rejected = false;
			try {
				result.verify ();
			} catch (LlvmError error) {
				Test.message ("Astra mutation %d rejected: %s", mutation, error.message);
				rejected = true;
			}
			assert (rejected);
			CApi.set_operand (access.instruction, 0, left_value);
			CApi.set_operand (right.instruction, 1, right_address);
			CApi.set_operand (projection.address, 2, field_index);
			projection.field = field;
			projection.root = root;
			CApi.set_operand (projection.payload, 0, root);
			CApi.set_operand (copy.instruction, 0, copy_destination);
			CApi.set_operand (copy.instruction, 2, copy_bytes);
			CApi.set_operand (result.sum_accesses[0].instruction, 0, tag_value);
			if (mutation == 6) {
				var builder = CApi.create_builder_in_context (result.context);
				CApi.remove_instruction (copy.instruction);
				CApi.position_builder_before (builder, copy_next);
				CApi.insert_instruction (builder, copy.instruction);
				CApi.dispose_builder (builder);
			}
			if (mutation == 9) {
				CApi.set_operand (changed_call, 0, call_result);
			}
			if ((void*) moved_instruction != null) {
				var builder = CApi.create_builder_in_context (result.context);
				CApi.remove_instruction (moved_instruction);
				CApi.position_builder_before (builder, moved_next);
				CApi.insert_instruction (builder, moved_instruction);
				CApi.dispose_builder (builder);
			}
			if ((void*) auxiliary != null) {
				CApi.set_operand (auxiliary, auxiliary_index, auxiliary_operand);
			}
			ordinary_llvm_accepts (result);
			result.verify ();
			Test.message ("restored physical mutation %d accepted", mutation);
		} catch (GLib.Error error) {
			GLib.error ("%s", error.message);
		}
	}
}

// Review tests to insert inside Astra.Tests.EnumLlvm in the expendable baseline.
// PROPOSED: not compiled with Vala or run against Astra in the reviewer container.
// Reuses artifact() and ordinary_llvm_accepts() from tests/enum-1/llvm.vala.
// Never emit, link or execute any mutated graph.

private CApi.ValueRef review_clear_with_other_carrier(LlvmModuleArtifact module, out CApi.ValueRef other) {
	other = (CApi.ValueRef) null;
	string name = "llvm.memset";
	uint identity = CApi.lookup_intrinsic_id (name, (size_t) name.length);
	assert (identity != 0);
	for (var function = CApi.first_function (module.module); (void*) function != null; function = CApi.next_function (function)) {
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.CALL || CApi.argument_count (instruction) != 4) {
					continue;
				}
				var target = CApi.called_value (instruction);
				if ((void*) CApi.is_instruction (target) != null || CApi.intrinsic_id (target) != identity) {
					continue;
				}
				var root = CApi.operand (instruction, 0);
				if ((void*) CApi.is_instruction (root) == null || CApi.opcode (root) != CApi.Opcode.ALLOCA) {
					continue;
				}
				if ((void*) CApi.is_constant_int (CApi.operand (instruction, 2)) == null || CApi.const_int_zext (CApi.operand (instruction, 2)) == 0) {
					continue;
				}
				// Only choose a distinct same-layout alloca in the same block,
				// already defined before the clear. This avoids a dominance/type
				// failure masking the exact-carrier correspondence question.
				for (var prior = CApi.first_instruction (block); (void*) prior != null && (void*) prior != (void*) instruction; prior = CApi.next_instruction (prior)) {
					if ((void*) prior != (void*) root && CApi.opcode (prior) == CApi.Opcode.ALLOCA && (void*) CApi.allocated_type (prior) == (void*) CApi.allocated_type (root)) {
						other = prior;
						return instruction;
					}
				}
			}
		}
	}
	return (CApi.ValueRef) null;
}

private void review_sum_boundary(int mutation) {
	try {
		var module = artifact ();
		CApi.ValueRef changed = (CApi.ValueRef) null;
		CApi.ValueRef original = (CApi.ValueRef) null;
		CApi.ValueRef replacement = (CApi.ValueRef) null;
		uint operand_index = 0;
		uint old_convention = 0;
		if (mutation < 4) {
			CApi.ValueRef other;
			changed = review_clear_with_other_carrier (module, out other);
			// A missing fixture is setup failure, not a reproduced omission.
			assert ((void*) changed != null && (void*) other != null);
			operand_index = mutation < 2 ? 2U : mutation == 2 ? 1U : 0U;
			original = CApi.operand (changed, operand_index);
			if (mutation == 0) {
				replacement = CApi.const_int (CApi.type_of (original), 0, 0);
			}
			if (mutation == 1) {
				replacement = CApi.const_int (CApi.type_of (original), CApi.const_int_zext (original) + 64, 0);
			}
			if (mutation == 2) {
				replacement = CApi.const_int (CApi.type_of (original), 1, 0);
			}
			if (mutation == 3) {
				replacement = other;
			}
		} else if (mutation == 4) {
			assert (module.sum_copies.length > 0);
			changed = module.sum_copies[0].instruction;
			operand_index = (uint) (CApi.operand_count (changed) - 1);
			original = CApi.operand (changed, operand_index);
			assert ((void*) original == (void*) CApi.called_value (changed));
			// This ordinary declaration is added BEFORE the positive control.
			// It is not linked or executed, even when the mutation is accepted.
			replacement = CApi.add_function (module.module, "review_not_a_copy", CApi.called_function_type (changed));
			CApi.set_function_call_conv (replacement, CApi.function_call_conv (original));
			assert (CApi.intrinsic_id (replacement) == 0);
		} else {
			assert (module.sum_calls.length > 0);
			changed = module.sum_calls[0].instruction;
			if (mutation == 6) {
				changed = CApi.called_value (changed);
			}
			old_convention = mutation == 5 ? CApi.instruction_call_conv (changed) : CApi.function_call_conv (changed);
			assert (old_convention != (uint) CApi.CallConv.C);
		}
		ordinary_llvm_accepts (module);
		module.verify ();
		if (mutation < 5) {
			CApi.set_operand (changed, operand_index, replacement);
		} else if (mutation == 5) {
			CApi.set_instruction_call_conv (changed, CApi.CallConv.C);
		} else {
			CApi.set_function_call_conv (changed, CApi.CallConv.C);
		}
		ordinary_llvm_accepts (module);
		bool rejected = false;
		try {
			module.verify ();
		} catch (LlvmError error) {
			Test.message ("Astra review mutation %d rejected: %s", mutation, error.message);
			rejected = true;
		}
		Test.message ("Astra review mutation %d rejected=%s", mutation, rejected.to_string ());
		if (mutation < 5) {
			CApi.set_operand (changed, operand_index, original);
		} else if (mutation == 5) {
			CApi.set_instruction_call_conv (changed, old_convention);
		} else {
			CApi.set_function_call_conv (changed, old_convention);
		}
		ordinary_llvm_accepts (module);
		module.verify ();
		Test.message ("restored review mutation %d passes", mutation);
		// Assert only after restoration, so a baseline acceptance cannot
		// masquerade as failure to reach the restored positive control.
		assert (rejected);
	} catch (GLib.Error error) {
		GLib.error ("review setup or positive-control error: %s", error.message);
	}
}

private void review_clear_zero() {
	review_sum_boundary (0);
}

private void review_clear_extent() {
	review_sum_boundary (1);
}

private void review_clear_fill() {
	review_sum_boundary (2);
}

private void review_clear_destination() {
	review_sum_boundary (3);
}

private void review_copy_callee() {
	review_sum_boundary (4);
}

private void review_call_convention() {
	review_sum_boundary (5);
}

private void review_callee_convention() {
	review_sum_boundary (6);
}

private void review_companion(int mutation) {
	try {
		var module = artifact ();
		assert (module.sum_clears.length > 0 && module.sum_copies.length > 0 && module.sum_calls.length > 0);
		var clear = module.sum_clears[0].instruction;
		var copy = module.sum_copies[0].instruction;
		var call = module.sum_calls[0].instruction;
		var instruction = mutation < 3 ? clear : copy;
		uint index = mutation == 0 ? (uint) (CApi.operand_count (clear) - 1) : 3U;
		var original = CApi.operand (instruction, index);
		var callee = CApi.called_value (call);
		var convention = CApi.instruction_call_conv (call);
		var target_convention = CApi.function_call_conv (callee);
		var alignment_kind = CApi.enum_attribute_kind ("align", 5);
		uint parameter = mutation == 4 ? 2U : 1U;
		var alignment = CApi.call_enum_attribute (instruction, parameter, alignment_kind);
		CApi.ValueRef replacement = (CApi.ValueRef) null;
		if (mutation == 0) {
			replacement = CApi.add_function (module.module, "review_not_a_clear", CApi.called_function_type (clear));
			assert (CApi.intrinsic_id (replacement) == 0);
		}
		ordinary_llvm_accepts (module);
		module.verify ();
		if (mutation == 0) {
			CApi.set_operand (clear, index, replacement);
		}
		if (mutation == 1 || mutation == 3) {
			CApi.set_operand (instruction, 3, CApi.const_int (CApi.type_of (original), 1, 0));
		}
		if (mutation == 2 || mutation == 4 || mutation == 6) {
			CApi.add_call_attribute (instruction, parameter, CApi.create_enum_attribute (module.context, alignment_kind, 1));
		}
		if (mutation == 5) {
			CApi.set_instruction_call_conv (call, CApi.CallConv.C);
			CApi.set_function_call_conv (callee, CApi.CallConv.C);
		}
		ordinary_llvm_accepts (module);
		bool rejected = false;
		try {
			module.verify ();
		} catch (LlvmError error) {
			Test.message ("Astra companion mutation %d rejected: %s", mutation, error.message);
			rejected = true;
		}
		if (mutation == 0 || mutation == 1 || mutation == 3) {
			CApi.set_operand (instruction, index, original);
		}
		if (mutation == 2 || mutation == 4 || mutation == 6) {
			CApi.add_call_attribute (instruction, parameter, alignment);
		}
		if (mutation == 5) {
			CApi.set_instruction_call_conv (call, convention);
			CApi.set_function_call_conv (callee, target_convention);
		}
		ordinary_llvm_accepts (module);
		module.verify ();
		assert (rejected);
	} catch (GLib.Error error) {
		GLib.error ("companion setup or control error: %s", error.message);
	}
}

private void review_clear_callee() {
	review_companion (0);
}

private void review_clear_volatile() {
	review_companion (1);
}

private void review_clear_alignment() {
	review_companion (2);
}

private void review_copy_volatile() {
	review_companion (3);
}

private void review_copy_source_alignment() {
	review_companion (4);
}

private void review_call_both_conventions() {
	review_companion (5);
}

private void review_copy_destination_alignment() {
	review_companion (6);
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/enum/llvm/stage-lifetimes-target-layout", positive);
	Test.add_func ("/enum/llvm/ordinary-valid-physical-correspondence", malformed);
	Test.add_func ("/enum/review/clear-zero", review_clear_zero);
	Test.add_func ("/enum/review/clear-extent", review_clear_extent);
	Test.add_func ("/enum/review/clear-fill", review_clear_fill);
	Test.add_func ("/enum/review/clear-destination", review_clear_destination);
	Test.add_func ("/enum/review/copy-callee", review_copy_callee);
	Test.add_func ("/enum/review/call-convention", review_call_convention);
	Test.add_func ("/enum/review/callee-convention", review_callee_convention);
	Test.add_func ("/enum/review/clear-callee", review_clear_callee);
	Test.add_func ("/enum/review/clear-volatile", review_clear_volatile);
	Test.add_func ("/enum/review/clear-alignment", review_clear_alignment);
	Test.add_func ("/enum/review/copy-volatile", review_copy_volatile);
	Test.add_func ("/enum/review/copy-source-alignment", review_copy_source_alignment);
	Test.add_func ("/enum/review/call-both-conventions", review_call_both_conventions);
	Test.add_func ("/enum/review/copy-destination-alignment", review_copy_destination_alignment);
	return Test.run ();
}

}
