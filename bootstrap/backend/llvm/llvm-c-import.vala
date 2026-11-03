// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Backend.LLVM {
// Copy the physical attribute authority; the artifact keeps no CABI graph.
internal class LlvmCRecordStackSlot : Object {
	private CApi.ValueRef slot;
	private CApi.ValueRef function;
	private CApi.TypeRef layout;
	private uint alignment;
	internal LlvmCRecordStackSlot (CApi.ValueRef slot, CApi.ValueRef function, CApi.TypeRef layout, uint alignment) {
		this.slot = slot;
		this.function = function;
		this.layout = layout;
		this.alignment = alignment;
	}

	internal void verify() throws LlvmError {
		if ((void*) CApi.is_instruction (slot) == null || CApi.opcode (slot) != CApi.Opcode.ALLOCA || (void*) CApi.instruction_parent (slot) != (void*) CApi.first_block (function) || (void*) CApi.allocated_type (slot) != (void*) layout || CApi.get_alignment (slot) != alignment || CApi.operand_count (slot) != 1 || (void*) CApi.operand (slot, 0) != (void*) CApi.const_int (CApi.type_of (CApi.operand (slot, 0)), 1, 0)) {
			throw new LlvmError.VERIFICATION ("C record staging requires one exact bounded entry allocation");
		}
	}

}
internal class LlvmCRecordAttributes : Object {
	private CApi.ValueRef value;
	private bool call;
	private uint[] indices = null;
	private uint[] kinds = null;
	private void*[] types = null;
	private uint[] alignments = null;
	private uint[] boolean_indices = null;
	internal bool requires_c_bool { get { return boolean_indices.length != 0; } }
	internal LlvmCRecordAttributes (CAbi.CAbiSignature signature, LlvmCTypeMapper mapper, CApi.ValueRef value, bool call = false) throws LlvmError {
		this.value = value;
		this.call = call;
		if (signature.result != null && signature.result.record == null && signature.result.scalar_type == CAbi.CAbiScalarType.CBOOL) {
			boolean_indices += 0;
		}
		foreach (var parameter in signature.parameters) {
			if (parameter.record == null && parameter.text == null && parameter.buffer == null && parameter.scalar_type == CAbi.CAbiScalarType.CBOOL) {
				boolean_indices += (uint) parameter.physical_ordinal + 1;
			}
		}
		if (signature.result != null && signature.result.record != null && signature.result.record.memory) {
			add (mapper, signature.result.record, 1, "sret");
		}
		foreach (var parameter in signature.parameters) {
			if (parameter.record != null && parameter.record.memory) {
				add (mapper, parameter.record, (uint) parameter.physical_ordinal + 1, "byval");
			}
		}
	}

	private void add(LlvmCTypeMapper mapper, CAbi.CAbiRecordPlan record, uint index, string name) throws LlvmError {
		indices += index;
		kinds += CApi.enum_attribute_kind (name, name.length);
		types += (void*) mapper.record_type (record);
		alignments += record.alignment;
	}

	internal void verify() throws LlvmError {
		foreach (uint index in boolean_indices) {
			var attribute = call ? CApi.call_enum_attribute (value, index, CApi.enum_attribute_kind ("zeroext", 7)) : CApi.enum_attribute (value, index, CApi.enum_attribute_kind ("zeroext", 7));
			if ((void*) attribute == null || CApi.enum_attribute_value (attribute) != 0) {
				throw new LlvmError.VERIFICATION ("C99 bool lost exact zero-extension on a declaration, wrapper or call");
			}
		}
		for (int i = 0; i < indices.length; i++) {
			var type = call ? CApi.call_enum_attribute (value, indices[i], kinds[i]) : CApi.enum_attribute (value, indices[i], kinds[i]);
			var alignment = call ? CApi.call_enum_attribute (value, indices[i], CApi.enum_attribute_kind ("align", 5)) : CApi.enum_attribute (value, indices[i], CApi.enum_attribute_kind ("align", 5));
			if ((void*) type == null || (void*) alignment == null || (void*) CApi.type_attribute_value (type) != types[i] || CApi.enum_attribute_value (alignment) != alignments[i]) {
				throw new LlvmError.VERIFICATION ("C by-value aggregate lost exact byval/sret layout and natural alignment");
			}
		}
	}

}
internal class LlvmCCallbackBinding : Object {
	internal CApi.ValueRef value;
	private CApi.TypeRef type;
	private CApi.ValueRef native_target;
	private CApi.TypeRef native_type;
	private CApi.ValueRef call;
	private CApi.ValueRef returned;
	private string symbol;
	internal LlvmCCallbackBinding (LlvmModuleArtifact artifact, LlvmFunctionBinding target, int ordinal) throws LlvmError {
		var signature = target.signature;
		if (signature.receiver != null || signature.exception_plan != null || signature.parameters.length != 2 || !(signature.parameters[0].abi_type is NativeAbi.NativeScalarAbiType) || signature.parameters[0].scalar_type != NativeAbi.NativeScalarType.PTR || !(signature.parameters[1].abi_type is NativeAbi.NativeScalarAbiType) || signature.parameters[1].scalar_type != NativeAbi.NativeScalarType.I32 || signature.result == null || signature.result.scalar_type != NativeAbi.NativeScalarType.I32 || target.async_frame != null) {
			throw new LlvmError.INVALID_INPUT ("C callback requires an exact nonthrowing direct native I32(PTR,I32) plan");
		}
		var parameters = new CApi.TypeRef[] {
			CApi.pointer_type_in_context (artifact.context, 0), CApi.int32_type_in_context (artifact.context)
		};
		type = CApi.function_type (CApi.int32_type_in_context (artifact.context), parameters, 2, 0);
		symbol = "astra.c.callback.%d".printf (ordinal);
		value = CApi.add_function (artifact.module, symbol, type);
		CApi.set_linkage (value, CApi.Linkage.INTERNAL);
		CApi.set_function_call_conv (value, CApi.CallConv.C);
		native_target = target.value;
		native_type = target.type;
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_at_end (builder, CApi.append_basic_block_in_context (artifact.context, value, "entry"));
		var arguments = new CApi.ValueRef[] {
			CApi.get_param (value, 0), CApi.get_param (value, 1)
		};
		call = CApi.build_call (builder, native_type, native_target, arguments, 2, "result");
		CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
		returned = CApi.build_ret (builder, call);
		CApi.dispose_builder (builder);
	}

	internal void verify() throws LlvmError {
		size_t length;
		unowned string name = CApi.value_name (value, out length);
		var block = CApi.first_block (value);
		if (name != symbol || length != symbol.length || (void*) CApi.global_value_type (value) != (void*) type || CApi.get_linkage (value) != CApi.Linkage.INTERNAL || CApi.function_call_conv (value) != CApi.CallConv.C || CApi.count_params (value) != 2 || (void*) block == null || (void*) CApi.next_block (block) != null || (void*) CApi.first_instruction (block) != (void*) call || (void*) CApi.next_instruction (call) != (void*) returned || (void*) CApi.next_instruction (returned) != null || CApi.argument_count (call) != 2 || CApi.operand_count (returned) != 1 || (void*) CApi.operand (returned, 0) != (void*) call) {
			throw new LlvmError.VERIFICATION ("C callback lost exact C wrapper, forwarding call and return");
		}
		if (CApi.get_linkage (native_target) != CApi.Linkage.INTERNAL || CApi.function_call_conv (native_target) != LlvmLowering.CALL_CONVENTION || (void*) CApi.first_block (native_target) == null || (void*) CApi.global_value_type (native_target) != (void*) native_type || (void*) CApi.called_value (call) != (void*) native_target || (void*) CApi.called_function_type (call) != (void*) native_type || CApi.instruction_call_conv (call) != LlvmLowering.CALL_CONVENTION || (void*) CApi.operand (call, 0) != (void*) CApi.get_param (value, 0) || (void*) CApi.operand (call, 1) != (void*) CApi.get_param (value, 1)) {
			throw new LlvmError.VERIFICATION ("C callback lost exact native identity, convention or typed context/value forwarding");
		}
	}

}
internal class LlvmCRecordLayoutBinding : Object {
	private CApi.TypeRef layout;
	private CApi.TypeRef[] fields;
	private uint[] offsets;
	private uint[] widths;
	private uint size;
	private uint alignment;
	internal LlvmCRecordLayoutBinding (CAbi.CAbiRecordPlan plan, CApi.TypeRef layout, CApi.ContextRef context) throws LlvmError {
		try {
			CAbi.CAbiVerifier.verify_record (plan);
		} catch (CAbi.CAbiError error) {
			throw new LlvmError.VERIFICATION ("C record plan rejected: %s", error.message);
		}
		this.layout = layout;
		this.size = plan.size;
		this.alignment = plan.alignment;
		fields = new CApi.TypeRef[plan.fields.length];
		offsets = new uint[plan.fields.length];
		widths = new uint[plan.fields.length];
		for (int f = 0; f < fields.length; f++) {
			var field = plan.fields[f];
			offsets[f] = field.offset;
			widths[f] = field.bytes;
			switch (field.scalar_name) {
			case "f32":
				fields[f] = CApi.float_type_in_context (context);
				break;
			case "f64":
				fields[f] = CApi.double_type_in_context (context);
				break;
			default:
				if (field.bytes == 0) {
					throw new LlvmError.LOWERING ("C record has an unsupported scalar field");
				}
				fields[f] = CApi.int_type_in_context (context, field.bytes * 8);
				break;
			}
		}
	}

	internal void verify(CApi.TargetDataRef data) throws LlvmError {
		if (CApi.is_packed_struct (layout) != 0 || CApi.count_struct_element_types (layout) != fields.length || CApi.abi_size_of_type (data, layout) != size || CApi.abi_alignment_of_type (data, layout) != alignment) {
			throw new LlvmError.VERIFICATION ("C record lost exact natural extent/alignment/field count");
		}
		for (uint f = 0; f < fields.length; f++) {
			if ((void*) CApi.struct_type_at_index (layout, f) != (void*) fields[f] || CApi.offset_of_element (data, layout, f) != offsets[f] || CApi.abi_size_of_type (data, fields[f]) != widths[f] || CApi.abi_alignment_of_type (data, fields[f]) != widths[f]) {
				throw new LlvmError.VERIFICATION ("C record field lost exact type/offset/extent/alignment");
			}
		}
	}

}
internal class LlvmCGroupBinding : Object {
	private CApi.ValueRef group;
	private CApi.ValueRef data;
	private CApi.ValueRef length;
	internal LlvmCGroupBinding (CApi.ValueRef group, CApi.ValueRef data, CApi.ValueRef length) {
		this.group = group;
		this.data = data;
		this.length = length;
	}

	internal void verify() throws LlvmError {
		CApi.ValueRef[] components = {
			data, length
		};
		for (uint c = 0; c < 2; c++) {
			var component = components[c];
			if (CApi.is_constant (group) != 0) {
				var builder = CApi.create_builder_in_context (CApi.type_context (CApi.type_of (group)));
				var expected = CApi.build_extract_value (builder, group, c, "");
				CApi.dispose_builder (builder);
				if ((void*) component != (void*) expected) {
					throw new LlvmError.VERIFICATION ("C counted view lost exact constant component");
				}
			} else if ((void*) CApi.is_instruction (component) == null || CApi.opcode (component) != CApi.Opcode.EXTRACT_VALUE || CApi.operand_count (component) != 1 || (void*) CApi.operand (component, 0) != (void*) group || CApi.index_count (component) != 1 || CApi.indices (component)[0] != c) {
				throw new LlvmError.VERIFICATION ("C counted view lost exact paired pointer/count extraction");
			}
		}
	}

}
// Artifact-owned physical contract: copied symbol and borrowed LLVM handles
// only. LLVM's general verifier does not enforce Astra's ABI domain rules.
internal class LlvmCFunctionBinding : Object {
	internal bool requires_c_bool {
		get {
			foreach (var attributes in record_attributes) {
				if (attributes.requires_c_bool) {
					return true;
				}
			}
			return false;
		}
	}
	private LlvmSumSequence? imported_cleanup;
	internal void define_class_import(LlvmModuleArtifact artifact, LlvmTypeMapper types, Astra.Source.ForeignImportContract root) throws LlvmError {
		imported_cleanup = LlvmForeignImports.cleanup (artifact, types, root, value);
	}

	private Astra.Foreign.PcDeviceContract? device;
	private LlvmSumSequence? device_sequence;
	internal void define_device(LlvmModuleArtifact artifact, Astra.Foreign.PcDeviceContract contract) throws LlvmError {
		device = contract.copy ();
		device_sequence = LlvmPcDevices.emit (artifact, value, type, contract);
	}

	internal CApi.ValueRef callback_value;
	internal CApi.TypeRef type;
	internal CApi.ValueRef value;
	internal GenericArray<void*> calls = new GenericArray<void*> ();
	private GenericArray<LlvmClassCallBinding> argument_bindings = new GenericArray<LlvmClassCallBinding> ();
	private GenericArray<LlvmCRecordAttributes> record_attributes = new GenericArray<LlvmCRecordAttributes> ();
	internal void record_record_attributes(CAbi.CAbiSignature signature, LlvmCTypeMapper mapper, CApi.ValueRef value, bool call = false) throws LlvmError {
		record_attributes.add (new LlvmCRecordAttributes (signature, mapper, value, call));
	}

	private GenericArray<LlvmCGroupBinding> group_bindings = new GenericArray<LlvmCGroupBinding> ();
	private string external_symbol;

	internal LlvmCFunctionBinding (CApi.TypeRef type, CApi.ValueRef value, string external_symbol) {
		this.type = type;
		this.value = value;
		this.external_symbol = external_symbol;
	}

	internal void record_call(CApi.ValueRef call, CApi.ValueRef[] arguments) {
		calls.add ((void*) call);
		argument_bindings.add (new LlvmClassCallBinding (call, value, type, arguments, CApi.CallConv.C, "foreign exact counted/scalar inputs"));
	}

	internal void record_group(CApi.ValueRef group, CApi.ValueRef data, CApi.ValueRef length) {
		group_bindings.add (new LlvmCGroupBinding (group, data, length));
	}

	// A source C declaration supplies ABI/lifetime authority, not libc purity.
	// Apply this only to the optimization clone, preserving legacy O0 dumps.
	internal void preserve_foreign_effects(CApi.ModuleRef copy) throws LlvmError {
		if (device != null || imported_cleanup != null) {
			return;
		}
		var imported = CApi.named_function (copy, external_symbol);
		if ((void*) imported == null) {
			throw new LlvmError.VERIFICATION ("optimization clone lost exact C import");
		}
		var context = CApi.type_context (CApi.global_value_type (imported));
		var attribute = CApi.create_enum_attribute (context, CApi.enum_attribute_kind ("nobuiltin", 9), 0);
		CApi.add_attribute (imported, uint.MAX, attribute);
		for (var use = CApi.first_use (imported); (void*) use != null; use = CApi.next_use (use)) {
			var call = CApi.user (use);
			if ((void*) CApi.is_instruction (call) == null || CApi.opcode (call) != CApi.Opcode.CALL || (void*) CApi.called_value (call) != (void*) imported) {
				throw new LlvmError.VERIFICATION ("C import has an unqualified escaping function use");
			}
			CApi.add_call_attribute (call, uint.MAX, attribute);
		}
	}

	internal void verify() throws LlvmError {
		size_t length;
		unowned string name = CApi.value_name (value, out length);
		bool body = (void*) CApi.first_block (value) != null;
		bool device_valid = device != null && device.valid () && device_sequence != null && body && CApi.get_linkage (value) == CApi.Linkage.INTERNAL;
		if (length != external_symbol.length || name != external_symbol || (void*) CApi.global_value_type (value) != (void*) type || (imported_cleanup != null ? !body || CApi.get_linkage (value) != CApi.Linkage.INTERNAL : device != null ? !device_valid : body || CApi.get_linkage (value) != CApi.Linkage.EXTERNAL) || CApi.function_call_conv (value) != CApi.CallConv.C) {
			throw new LlvmError.VERIFICATION ("internal LLVM C import verification error: expected exact external C declaration '%s'", external_symbol);
		}
		if (device_sequence != null) {
			device_sequence.verify ();
		}
		if (imported_cleanup != null) {
			imported_cleanup.verify ();
		}
		foreach (var handle in calls) {
			var call = (CApi.ValueRef) handle;
			if ((void*) CApi.called_value (call) != (void*) value || (void*) CApi.called_function_type (call) != (void*) type || CApi.instruction_call_conv (call) != CApi.CallConv.C) {
				throw new LlvmError.VERIFICATION ("internal LLVM C import verification error: C call type, convention or exact target mismatch for '%s'", external_symbol);
			}
		}
		foreach (var binding in argument_bindings) {
			binding.verify ();
		}
		foreach (var binding in group_bindings) {
			binding.verify ();
		}
		foreach (var binding in record_attributes) {
			binding.verify ();
		}
	}

}
}
