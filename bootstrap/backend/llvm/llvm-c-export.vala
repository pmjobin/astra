// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.CAbi;

namespace Astra.Backend.LLVM {
// A selected tagged projection is admitted only after this exact check.
// No source or C ABI graph survives in the completed physical snapshot.
internal class LlvmCUnionGuard : Object {
	internal static CApi.BasicBlockRef emit(LlvmModuleArtifact artifact, CApi.BuilderRef builder, CApi.ValueRef function, CApi.ValueRef tag, int64 selected) throws LlvmError {
		if ((void*) CApi.is_instruction (tag) != null && CApi.opcode (tag) == CApi.Opcode.EXTRACT_VALUE) {
			artifact.class_values.add (new LlvmClassValueBinding (tag, CApi.Opcode.EXTRACT_VALUE, CApi.type_of (tag), new CApi.ValueRef[] { CApi.operand (tag, 0) }, "C union exact tag projection", 0));
		}
		var expected = CApi.const_int (CApi.type_of (tag), (uint64) selected, 0);
		var valid = CApi.build_icmp (builder, CApi.IntPredicate.EQ, tag, expected, "c.union.active.tag");
		if ((void*) CApi.is_instruction (valid) != null) {
			artifact.class_values.add (new LlvmClassValueBinding (valid, CApi.Opcode.ICMP, CApi.int1_type_in_context (artifact.context), new CApi.ValueRef[] { tag, expected }, "C union active member tag", -1, (int) CApi.IntPredicate.EQ));
		}
		var accepted = CApi.append_basic_block_in_context (artifact.context, function, "c.union.accepted");
		var refused = CApi.append_basic_block_in_context (artifact.context, function, "c.union.incompatible");
		CApi.build_cond_br (builder, valid, accepted, refused);
		CApi.position_builder_at_end (builder, refused);
		uint id = CApi.lookup_intrinsic_id ("llvm.trap", 9);
		if (id == 0) {
			throw new LlvmError.LOWERING ("C union contract requires the LLVM trap intrinsic");
		}
		var trap = CApi.get_intrinsic_declaration (artifact.module, id, null, 0);
		CApi.build_call (builder, CApi.intrinsic_get_type (artifact.context, id, null, 0), trap, null, 0, "");
		CApi.build_unreachable (builder);
		CApi.position_builder_at_end (builder, accepted);
		return accepted;
	}
}
// Completed contract owns only copied text and borrowed LLVM handles.
// No CABI, NABI or SSA identity survives into the artifact.
internal class LlvmCExportBinding : Object {
	internal bool requires_c_bool { get { return record_attributes != null && record_attributes.requires_c_bool; } }
	internal CApi.ValueRef value;
	internal CApi.ValueRef native_target;
	internal CApi.ValueRef call;
	private CApi.ValueRef returned;
	private CApi.TypeRef type;
	private CApi.TypeRef native_type;
	private string external_symbol;
	private bool returns_value;
	private bool adapts_records;
	private LlvmCRecordAttributes? record_attributes;
	private GenericArray<LlvmClassValueBinding> adapters = new GenericArray<LlvmClassValueBinding> ();
	private LlvmClassCallBinding? forwarding;
	private GenericArray<void*> sequence = new GenericArray<void*> ();
	private LlvmSumSequence? union_sequence;

	internal static LlvmCExportBinding create(LlvmModuleArtifact artifact, LlvmCTypeMapper types, CAbiExport exported, LlvmFunctionBinding target) throws LlvmError {
		var binding = new LlvmCExportBinding ();
		binding.type = types.signature (exported.signature);
		binding.native_type = target.type;
		binding.native_target = target.value;
		binding.external_symbol = exported.external_symbol;
		binding.returns_value = exported.signature.result != null;
		binding.value = CApi.add_function (artifact.module, exported.external_symbol, binding.type);
		CApi.set_linkage (binding.value, CApi.Linkage.EXTERNAL);
		CApi.set_function_call_conv (binding.value, CApi.CallConv.C);
		types.attributes (exported.signature, binding.value);
		binding.record_attributes = new LlvmCRecordAttributes (exported.signature, types, binding.value);
		binding.adapts_records = exported.signature.has_record;
		if (binding.adapts_records) {
			binding.build_record_adapter (artifact, types, exported.signature, target);
			return binding;
		}
		var arguments = new CApi.ValueRef[exported.signature.parameters.length];
		for (int p = 0; p < arguments.length; p++) {
			// Corresponding I32/PTR/F32/F64 payloads match; ABI domains remain distinct.
			arguments[p] = CApi.get_param (binding.value, p);
		}
		var block = CApi.append_basic_block_in_context (artifact.context, binding.value, "entry");
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_at_end (builder, block);
		binding.call = CApi.build_call (builder, target.type, target.value, arguments, arguments.length, binding.returns_value ? "result" : "");
		CApi.set_instruction_call_conv (binding.call, LlvmLowering.CALL_CONVENTION);
		binding.returned = binding.returns_value ? CApi.build_ret (builder, binding.call) : CApi.build_ret_void (builder);
		CApi.dispose_builder (builder);
		return binding;
	}

	private void build_record_adapter(LlvmModuleArtifact artifact, LlvmCTypeMapper types, CAbiSignature signature, LlvmFunctionBinding target) throws LlvmError {
		var block = CApi.append_basic_block_in_context (artifact.context, value, "entry");
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_at_end (builder, block);
		var arguments = new CApi.ValueRef[target.signature.parameters.length];
		int leaf = 0;
		foreach (var parameter in signature.parameters) {
			if (parameter.record != null) {
				var record = parameter.record;
				if (record.union_projection != null && record.union_projection.tagged_union) {
					LlvmCUnionGuard.emit (artifact, builder, value, CApi.get_param (value, parameter.physical_ordinal), record.union_projection.union_tag);
				}
				for (uint f = 0; f < record.fields.length; f++) {
					arguments[leaf++] = record.memory ? CApi.build_load (builder, types.field_type (record.fields[f]), CApi.build_struct_gep (builder, types.record_type (record), CApi.get_param (value, parameter.physical_ordinal), f, "c.input.field"), "c.input.value") : CApi.get_param (value, parameter.physical_ordinal + f);
				}
			} else {
				arguments[leaf++] = CApi.get_param (value, parameter.physical_ordinal);
			}
		}
		call = CApi.build_call (builder, native_type, native_target, arguments, arguments.length, signature.result == null ? "" : "native.result");
		CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
		forwarding = new LlvmClassCallBinding (call, native_target, native_type, arguments, LlvmLowering.CALL_CONVENTION, "C by-value exact native leaf adapter");
		if (signature.result == null) {
			returned = CApi.build_ret_void (builder);
		} else if (signature.result.record == null) {
			returned = CApi.build_ret (builder, call);
		} else {
			var record = signature.result.record;
			CApi.ValueRef result = CApi.const_null (types.record_type (record));
			if (record.union_projection != null && record.union_projection.tagged_union) {
				LlvmCUnionGuard.emit (artifact, builder, value, CApi.build_extract_value (builder, call, 0, "c.union.result.tag"), record.union_projection.union_tag);
			}
			for (uint f = 0; f < record.fields.length; f++) {
				var field = target.signature.struct_result.result_carrier == NativeAbi.NativeStructResultCarrier.SINGLE_LEAF ? call : CApi.build_extract_value (builder, call, f, "native.result.field");
				if (record.memory) {
					CApi.build_store (builder, field, CApi.build_struct_gep (builder, types.record_type (record), CApi.get_param (value, 0), f, "c.output.field"));
				} else {
					result = CApi.build_insert_value (builder, result, field, f, "c.output.value");
				}
			}
			returned = record.memory ? CApi.build_ret_void (builder) : CApi.build_ret (builder, record.fields.length == 1 ? call : result);
		}
		CApi.dispose_builder (builder);
		bool tagged = signature.result != null && signature.result.record != null && signature.result.record.union_projection != null && signature.result.record.union_projection.tagged_union;
		foreach (var parameter in signature.parameters) {
			tagged |= parameter.record != null && parameter.record.union_projection != null && parameter.record.union_projection.tagged_union;
		}
		if (tagged) {
			union_sequence = new LlvmSumSequence (value, true);
			for (var cursor = CApi.first_block (value); (void*) cursor != null; cursor = CApi.next_block (cursor)) {
				for (var instruction = CApi.first_instruction (cursor); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					var opcode = CApi.opcode (instruction);
					if (opcode != CApi.Opcode.EXTRACT_VALUE && opcode != CApi.Opcode.INSERT_VALUE) {
						continue;
					}
					var operands = new CApi.ValueRef[CApi.operand_count (instruction)];
					for (int o = 0; o < operands.length; o++) {
						operands[o] = CApi.operand (instruction, o);
					}
					adapters.add (new LlvmClassValueBinding (instruction, opcode, CApi.type_of (instruction), operands, "C union exact tag/payload carrier", (int) CApi.indices (instruction)[0]));
				}
			}
			return;
		}
		for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
			sequence.add ((void*) instruction);
			if ((void*) instruction == (void*) call) {
				continue;
			}
			var operands = new CApi.ValueRef[CApi.operand_count (instruction)];
			for (int o = 0; o < operands.length; o++) {
				operands[o] = CApi.operand (instruction, o);
			}
			var opcode = CApi.opcode (instruction);
			int member = opcode == CApi.Opcode.EXTRACT_VALUE || opcode == CApi.Opcode.INSERT_VALUE ? (int) CApi.indices (instruction)[0] : -1;
			adapters.add (new LlvmClassValueBinding (instruction, opcode, CApi.type_of (instruction), operands, "C by-value adapter", member));
		}
	}

	internal void verify() throws LlvmError {
		if (record_attributes != null) {
			record_attributes.verify ();
		}
		size_t length;
		unowned string name = CApi.value_name (value, out length);
		var block = CApi.first_block (value);
		if (length != external_symbol.length || name != external_symbol || (void*) CApi.global_value_type (value) != (void*) type || CApi.get_linkage (value) != CApi.Linkage.EXTERNAL || CApi.function_call_conv (value) != CApi.CallConv.C || (void*) block == null) {
			throw new LlvmError.VERIFICATION ("internal LLVM C export verification error: expected exact external C wrapper '%s'", external_symbol);
		}
		if (CApi.get_linkage (native_target) != CApi.Linkage.INTERNAL || CApi.function_call_conv (native_target) != LlvmLowering.CALL_CONVENTION || (void*) CApi.first_block (native_target) == null || (void*) CApi.global_value_type (native_target) != (void*) native_type || (void*) CApi.called_value (call) != (void*) native_target || (void*) CApi.called_function_type (call) != (void*) native_type || CApi.instruction_call_conv (call) != LlvmLowering.CALL_CONVENTION) {
			throw new LlvmError.VERIFICATION ("internal LLVM C export verification error: wrapper '%s' must call its exact internal fastcc target", external_symbol);
		}
		if (union_sequence != null) {
			if (forwarding == null) {
				throw new LlvmError.VERIFICATION ("C union lost its native forwarding contract");
			}
			forwarding.verify ();
			foreach (var adapter in adapters) {
				adapter.verify ();
			}
			union_sequence.verify ();
			return;
		}
		if (adapts_records) {
			if ((void*) CApi.next_block (block) != null || forwarding == null) {
				throw new LlvmError.VERIFICATION ("C record wrapper lost exact adapter block");
			}
			forwarding.verify ();
			foreach (var adapter in adapters) {
				adapter.verify ();
			}
			int index = 0;
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (index >= sequence.length || (void*) instruction != sequence[index++]) {
					throw new LlvmError.VERIFICATION ("C record wrapper changed ordered adapter instructions");
				}
			}
			if (index != sequence.length) {
				throw new LlvmError.VERIFICATION ("C record wrapper lost adapter instructions");
			}
			return;
		}
		if ((void*) CApi.next_block (block) != null || (void*) CApi.first_instruction (block) != (void*) call || (void*) CApi.next_instruction (call) != (void*) returned || (void*) CApi.next_instruction (returned) != null || CApi.argument_count (call) != CApi.count_params (value) || CApi.operand_count (returned) != (returns_value ? 1 : 0)) {
			throw new LlvmError.VERIFICATION ("internal LLVM C export verification error: wrapper '%s' must contain only call forwarding and return", external_symbol);
		}
		for (uint p = 0; p < CApi.count_params (value); p++) {
			if ((void*) CApi.operand (call, p) != (void*) CApi.get_param (value, p)) {
				throw new LlvmError.VERIFICATION ("internal LLVM C export verification error: wrapper '%s' must forward exact arguments", external_symbol);
			}
		}
		if (returns_value && (void*) CApi.operand (returned, 0) != (void*) call) {
			throw new LlvmError.VERIFICATION ("internal LLVM C export verification error: wrapper '%s' must return its native result", external_symbol);
		}
	}
}
}
