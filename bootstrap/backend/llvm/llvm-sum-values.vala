// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.NativeAbi;

namespace Astra.Backend.LLVM {
// Sum storage remains memory across branches. Freeze the emitted operation
// sequence and actual predecessor edges after SSA/native correspondence has
// been checked, so a later well-typed edit cannot read a carrier before its
// call/copy producer, publish a partial value, or use a stale predecessor.
// Only LLVM handles survive; no upstream function or value graph is retained.
internal class LlvmSumOperandContract : Object {
	private CApi.ValueRef instruction;
	private CApi.Opcode opcode;
	private void*[] operands;
	private void* type;
	private void*[] cases;
	private uint convention;
	internal LlvmSumOperandContract (CApi.ValueRef instruction) {
		this.instruction = instruction;
		opcode = CApi.opcode (instruction);
		type = (void*) CApi.type_of (instruction);
		operands = new void*[CApi.operand_count (instruction)];
		for (int i = 0; i < operands.length; i++) {
			operands[i] = (void*) CApi.operand (instruction, i);
		}
		if (opcode == CApi.Opcode.CALL) {
			convention = CApi.instruction_call_conv (instruction);
		}
		cases = new void*[opcode == CApi.Opcode.SWITCH ? CApi.successor_count (instruction) - 1 : 0];
		for (int i = 0; i < cases.length; i++) {
			cases[i] = (void*) CApi.switch_case_value (instruction, (uint) i + 1);
		}
	}
	internal void verify() throws LlvmError {
		if (CApi.opcode (instruction) != opcode || (void*) CApi.type_of (instruction) != type || CApi.operand_count (instruction) != operands.length || (opcode == CApi.Opcode.CALL && CApi.instruction_call_conv (instruction) != convention)) {
			throw new LlvmError.VERIFICATION ("owning sum effect lost its exact operation/type/call convention");
		}
		for (int i = 0; i < operands.length; i++) {
			if ((void*) CApi.operand (instruction, i) != operands[i]) {
				throw new LlvmError.VERIFICATION ("owning sum effect changed live flag, source disarm, active disposal or exact owner operands");
			}
		}
		for (int i = 0; i < cases.length; i++) {
			if ((void*) CApi.switch_case_value (instruction, (uint) i + 1) != cases[i]) {
				throw new LlvmError.VERIFICATION ("owning sum effect changed its exact switch case value");
			}
		}
	}
}

internal class LlvmSumBlockSequence : Object {
	private CApi.BasicBlockRef block;
	private GenericArray<void*> instructions = new GenericArray<void*> ();
	private void*[] successors;
	private GenericArray<LlvmSumOperandContract> effects = new GenericArray<LlvmSumOperandContract> ();
	internal LlvmSumBlockSequence (CApi.BasicBlockRef block, bool owning = false) {
		this.block = block;
		for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
			instructions.add ((void*) instruction);
			if (owning) {
				effects.add (new LlvmSumOperandContract (instruction));
			}
		}
		var end = CApi.block_terminator (block);
		successors = new void*[CApi.successor_count (end)];
		for (int i = 0; i < successors.length; i++) {
			successors[i] = (void*) CApi.successor (end, i);
		}
	}
	internal void verify() throws LlvmError {
		foreach (var effect in effects) {
			effect.verify ();
		}
		var next = CApi.first_instruction (block);
		foreach (void* expected in instructions) {
			if ((void*) next != expected) {
				throw new LlvmError.VERIFICATION ("sum storage lost exact producer/store/call/read publication order or predecessor block");
			}
			next = CApi.next_instruction (next);
		}
		if ((void*) next != null) {
			throw new LlvmError.VERIFICATION ("sum storage has an unassociated physical operation");
		}
		var end = CApi.block_terminator (block);
		if (CApi.successor_count (end) != successors.length) {
			throw new LlvmError.VERIFICATION ("sum storage lost complete physical predecessor correspondence");
		}
		for (int i = 0; i < successors.length; i++) {
			if ((void*) CApi.successor (end, i) != successors[i]) {
				throw new LlvmError.VERIFICATION ("sum storage changed an intended predecessor/result edge");
			}
		}
	}
}
internal class LlvmSumSequence : Object {
	internal bool owns_values { get; private set; }
	private CApi.ValueRef function;
	private GenericArray<void*> blocks = new GenericArray<void*> ();
	private GenericArray<LlvmSumBlockSequence> sequences = new GenericArray<LlvmSumBlockSequence> ();
	internal LlvmSumSequence (CApi.ValueRef function, bool owning = false) {
		this.owns_values = owning;
		this.function = function;
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			blocks.add ((void*) block);
			sequences.add (new LlvmSumBlockSequence (block, owning));
		}
	}
	internal void verify() throws LlvmError {
		var next = CApi.first_block (function);
		for (int i = 0; i < blocks.length; i++) {
			if ((void*) next != blocks[i]) {
				throw new LlvmError.VERIFICATION ("sum function lost its exact emitted predecessor/slot sequence");
			}
			sequences[i].verify ();
			next = CApi.next_block (next);
		}
		if ((void*) next != null) {
			throw new LlvmError.VERIFICATION ("sum function has an unassociated physical block");
		}
	}
}
// These bindings preserve full physical paths and reads without retaining IR.
internal class LlvmSumAddress : Object {
	internal CApi.ValueRef instruction;
	private CApi.ValueRef root;
	private CApi.TypeRef type;
	private uint member;
	internal LlvmSumAddress (CApi.ValueRef instruction, CApi.ValueRef root, CApi.TypeRef type, uint member) {
		this.instruction = instruction;
		this.root = root;
		this.type = type;
		this.member = member;
	}
	internal void verify() throws LlvmError {
		if ((void*) CApi.is_instruction (instruction) == null || CApi.opcode (instruction) != CApi.Opcode.GEP || CApi.operand_count (instruction) != 3 || (void*) CApi.gep_source_type (instruction) != (void*) type || (void*) CApi.operand (instruction, 0) != (void*) root || (void*) CApi.is_constant_int (CApi.operand (instruction, 1)) == null || CApi.const_int_zext (CApi.operand (instruction, 1)) != 0 || (void*) CApi.is_constant_int (CApi.operand (instruction, 2)) == null || CApi.const_int_zext (CApi.operand (instruction, 2)) != member) {
			throw new LlvmError.VERIFICATION ("sum tag/record projection lost complete base and physical path");
		}
	}
}
internal class LlvmSumRead : Object {
	internal CApi.ValueRef instruction;
	private CApi.ValueRef address;
	private CApi.TypeRef type;
	internal LlvmSumRead (CApi.ValueRef instruction, CApi.ValueRef address, CApi.TypeRef type) {
		this.instruction = instruction;
		this.address = address;
		this.type = type;
	}
	internal void verify() throws LlvmError {
		if ((void*) CApi.is_instruction (instruction) == null || CApi.opcode (instruction) != CApi.Opcode.LOAD || CApi.operand_count (instruction) != 1 || (void*) CApi.operand (instruction, 0) != (void*) address || (void*) CApi.type_of (instruction) != (void*) type || CApi.get_volatile (instruction) != 0 || CApi.get_ordering (instruction) != 0) {
			throw new LlvmError.VERIFICATION ("sum selected payload/tag read lost its intended instance and address");
		}
	}
}
internal class LlvmSumDispatch : Object {
	internal CApi.ValueRef instruction;
	private void*[] operands;
	private void*[] cases;
	internal LlvmSumDispatch (CApi.ValueRef instruction) {
		this.instruction = instruction;
		operands = new void*[CApi.operand_count (instruction)];
		for (int i = 0; i < operands.length; i++) {
			operands[i] = (void*) CApi.operand (instruction, i);
		}
		cases = new void*[CApi.successor_count (instruction) - 1];
		for (int i = 0; i < cases.length; i++) {
			cases[i] = (void*) CApi.switch_case_value (instruction, (uint) i + 1);
		}
	}
	internal void verify() throws LlvmError {
		if ((void*) CApi.is_instruction (instruction) == null || CApi.opcode (instruction) != CApi.Opcode.SWITCH || CApi.operand_count (instruction) != operands.length) {
			throw new LlvmError.VERIFICATION ("sum dispatch lost tag/complete case correspondence");
		}
		for (int i = 0; i < operands.length; i++) {
			if ((void*) CApi.operand (instruction, i) != operands[i]) {
				throw new LlvmError.VERIFICATION ("sum dispatch changed selected tag or exact active case edge");
			}
		}
		if (CApi.successor_count (instruction) != cases.length + 1) {
			throw new LlvmError.VERIFICATION ("sum dispatch lost its complete case values");
		}
		for (int i = 0; i < cases.length; i++) {
			if ((void*) CApi.switch_case_value (instruction, (uint) i + 1) != cases[i]) {
				throw new LlvmError.VERIFICATION ("sum dispatch changed its selected case value");
			}
		}
	}
}
internal class LlvmSumCall : Object {
	internal CApi.ValueRef instruction;
	private CApi.ValueRef callee;
	private CApi.TypeRef signature;
	private void*[] arguments;
	internal LlvmSumCall (CApi.ValueRef instruction, CApi.ValueRef callee, CApi.TypeRef signature, CApi.ValueRef[] arguments) {
		this.instruction = instruction;
		this.callee = callee;
		this.signature = signature;
		this.arguments = new void*[arguments.length];
		for (int i = 0; i < arguments.length; i++) {
			this.arguments[i] = (void*) arguments[i];
		}
	}
	internal void verify() throws LlvmError {
		if ((void*) CApi.is_instruction (instruction) == null || CApi.opcode (instruction) != CApi.Opcode.CALL || (void*) CApi.called_value (instruction) != (void*) callee || (void*) CApi.called_function_type (instruction) != (void*) signature || CApi.argument_count (instruction) != arguments.length || CApi.instruction_call_conv (instruction) != LlvmLowering.CALL_CONVENTION || CApi.function_call_conv (callee) != LlvmLowering.CALL_CONVENTION) {
			throw new LlvmError.VERIFICATION ("sum call lost exact callee/signature/native convention publication correspondence");
		}
		for (int i = 0; i < arguments.length; i++) {
			if ((void*) CApi.operand (instruction, i) != arguments[i]) {
				throw new LlvmError.VERIFICATION ("sum call lost exact instance/input/result storage channel order");
			}
		}
	}
}
internal class LlvmSumAccess : Object {
	internal CApi.ValueRef instruction;
	private CApi.ValueRef expected_address;
	private CApi.ValueRef expected_value;
	internal LlvmSumAccess (CApi.ValueRef instruction, CApi.ValueRef expected_address, CApi.ValueRef expected_value) {
		this.instruction = instruction;
		this.expected_address = expected_address;
		this.expected_value = expected_value;
	}
	internal void verify() throws LlvmError {
		if ((void*) CApi.is_instruction (instruction) == null || CApi.opcode (instruction) != CApi.Opcode.STORE || (void*) CApi.operand (instruction, 0) != (void*) expected_value || (void*) CApi.operand (instruction, 1) != (void*) expected_address || CApi.get_volatile (instruction) != 0 || CApi.get_ordering (instruction) != 0) {
			throw new LlvmError.VERIFICATION ("sum payload store lost intended field/address/value correspondence");
		}
	}
}

// Derive operation authority from the selected LLVM intrinsic and overloads,
// never from the mutable call's current target, signature or attributes.
internal class LlvmSumMemoryOperation : Object {
	private CApi.ValueRef target;
	private CApi.TypeRef signature;
	private uint identity;
	private uint alignment;
	private bool copy;
	internal LlvmSumMemoryOperation (LlvmModuleArtifact artifact, uint alignment, bool copy) {
		this.alignment = alignment;
		this.copy = copy;
		string name = copy ? "llvm.memcpy" : "llvm.memset";
		identity = CApi.lookup_intrinsic_id (name, name.length);
		var pointer = CApi.pointer_type_in_context (artifact.context, 0);
		var length = CApi.int_type_in_context (artifact.context, 64);
		var overloads = new CApi.TypeRef[copy ? 3 : 2];
		overloads[0] = pointer;
		overloads[1] = copy ? pointer : length;
		if (copy) {
			overloads[2] = length;
		}
		target = CApi.get_intrinsic_declaration (artifact.module, identity, overloads, overloads.length);
		signature = CApi.intrinsic_get_type (artifact.context, identity, overloads, overloads.length);
	}
	private bool aligned(CApi.ValueRef instruction, uint parameter) {
		var attribute = CApi.call_enum_attribute (instruction, parameter, CApi.enum_attribute_kind ("align", 5));
		return (void*) attribute != null && CApi.enum_attribute_value (attribute) == alignment;
	}
	internal void verify(CApi.ValueRef instruction) throws LlvmError {
		if ((void*) CApi.is_instruction (instruction) == null || CApi.opcode (instruction) != CApi.Opcode.CALL || CApi.argument_count (instruction) != 4 || (void*) CApi.called_value (instruction) != (void*) target || CApi.intrinsic_id (target) != identity || (void*) CApi.called_function_type (instruction) != (void*) signature || (void*) CApi.global_value_type (target) != (void*) signature || CApi.instruction_call_conv (instruction) != CApi.CallConv.C || CApi.function_call_conv (target) != CApi.CallConv.C || !aligned (instruction, 1) || (copy && !aligned (instruction, 2))) {
			throw new LlvmError.VERIFICATION ("sum memory operation lost exact intrinsic/overload/signature/convention/alignment correspondence");
		}
	}
}
internal class LlvmSumClear : Object {
	internal CApi.ValueRef instruction;
	private CApi.ValueRef destination;
	private uint64 bytes;
	private LlvmSumMemoryOperation operation;
	internal LlvmSumClear (LlvmModuleArtifact artifact, CApi.ValueRef instruction, CApi.ValueRef destination, LlvmSumLayout layout) {
		this.instruction = instruction;
		this.destination = destination;
		bytes = layout.size;
		operation = new LlvmSumMemoryOperation (artifact, layout.alignment, false);
	}
	internal void verify() throws LlvmError {
		operation.verify (instruction);
		if ((void*) CApi.operand (instruction, 0) != (void*) destination || (void*) CApi.is_constant_int (CApi.operand (instruction, 1)) == null || CApi.const_int_zext (CApi.operand (instruction, 1)) != 0 || (void*) CApi.is_constant_int (CApi.operand (instruction, 2)) == null || CApi.const_int_zext (CApi.operand (instruction, 2)) != bytes || (void*) CApi.is_constant_int (CApi.operand (instruction, 3)) == null || CApi.const_int_zext (CApi.operand (instruction, 3)) != 0) {
			throw new LlvmError.VERIFICATION ("sum clear lost exact destination, zero fill, full carrier extent or nonvolatile initialization");
		}
	}
}

internal class LlvmSumCopy : Object {
	internal CApi.ValueRef instruction;
	private CApi.ValueRef destination;
	private CApi.ValueRef source;
	private uint64 bytes;
	private void* required_ready;
	private LlvmSumMemoryOperation operation;
	internal LlvmSumCopy (LlvmModuleArtifact artifact, CApi.ValueRef instruction, CApi.ValueRef destination, CApi.ValueRef source, LlvmSumLayout layout, void* required_ready) {
		this.instruction = instruction;
		this.destination = destination;
		this.source = source;
		bytes = layout.size;
		this.required_ready = required_ready;
		operation = new LlvmSumMemoryOperation (artifact, layout.alignment, true);
	}
	internal void verify() throws LlvmError {
		operation.verify (instruction);
		if ((void*) CApi.operand (instruction, 0) != (void*) destination || (void*) CApi.operand (instruction, 1) != (void*) source || (void*) CApi.is_constant_int (CApi.operand (instruction, 2)) == null || CApi.const_int_zext (CApi.operand (instruction, 2)) != bytes || (void*) CApi.is_constant_int (CApi.operand (instruction, 3)) == null || CApi.const_int_zext (CApi.operand (instruction, 3)) != 0 || (required_ready != null && !LlvmBufferExchangeOrder.precedes ((CApi.ValueRef) required_ready, instruction))) {
			throw new LlvmError.VERIFICATION ("sum copy lost exact source/result destination, complete byte publication or required stores");
		}
	}
}
internal class LlvmSumLayout : Object {
	internal NativeSumPlan plan;
	internal CApi.TypeRef carrier;
	internal void*[] variants;
	internal uint64 size;
	internal uint alignment;
	internal uint64 payload_offset;
	internal LlvmSumLayout (NativeSumPlan plan, CApi.TypeRef carrier, void*[] variants, uint64 size, uint alignment, uint64 payload_offset) {
		this.plan = plan;
		this.carrier = carrier;
		this.variants = variants;
		this.size = size;
		this.alignment = alignment;
		this.payload_offset = payload_offset;
	}

	internal void verify(CApi.TargetDataRef data) throws LlvmError {
		uint64 maximum = 0;
		uint active_alignment = 1;
		foreach (void* variant in variants) {
			maximum = uint64.max (maximum, CApi.abi_size_of_type (data, (CApi.TypeRef) variant));
			active_alignment = uint.max (active_alignment, CApi.abi_alignment_of_type (data, (CApi.TypeRef) variant));
		}
		uint expected_alignment = uint.max (4, active_alignment);
		uint64 expected_offset = ((4 + active_alignment - 1) / active_alignment) * active_alignment;
		uint64 expected_size = ((expected_offset + maximum + expected_alignment - 1) / expected_alignment) * expected_alignment;
		if (CApi.abi_size_of_type (data, carrier) != expected_size || CApi.abi_alignment_of_type (data, carrier) != expected_alignment || CApi.offset_of_element (data, carrier, 0) != 0 || CApi.offset_of_element (data, carrier, 1) != expected_offset || size != expected_size || alignment != expected_alignment || payload_offset != expected_offset) {
			throw new LlvmError.VERIFICATION ("sum carrier differs from tag plus maximum active payload target layout");
		}
	}
}

// Physical bindings carry only frozen nominal plans and LLVM handles. Slot
// projections are checked against the allocation and complete field identity.
internal class LlvmSumProjection : Object {
	private CApi.ValueRef original_root;
	private EnumFieldIdentity original_field;
	internal LlvmSumLayout layout;
	internal EnumFieldIdentity field;
	internal CApi.ValueRef root;
	internal CApi.ValueRef payload;
	internal CApi.ValueRef address;
	internal LlvmSumProjection (LlvmSumLayout layout, EnumFieldIdentity field, CApi.ValueRef root, CApi.ValueRef payload, CApi.ValueRef address) {
		this.layout = layout;
		this.field = field;
		this.root = root;
		this.payload = payload;
		this.address = address;
		original_root = root;
		original_field = field;
	}
	private static bool index(CApi.ValueRef value, uint expected) {
		return (void*) CApi.is_constant_int (value) != null && CApi.const_int_zext (value) == expected;
	}
	private static bool gep(CApi.ValueRef value, CApi.ValueRef base_address, CApi.TypeRef type, uint member) {
		return (void*) CApi.is_instruction (value) != null && CApi.opcode (value) == CApi.Opcode.GEP && CApi.operand_count (value) == 3 && (void*) CApi.operand (value, 0) == (void*) base_address && (void*) CApi.gep_source_type (value) == (void*) type && index (CApi.operand (value, 1), 0) && index (CApi.operand (value, 2), member);
	}
	internal void verify() throws LlvmError {
		if ((void*) root != (void*) original_root || field != original_field || field.variant.enumeration != layout.plan.identity || field.variant.ordinal < 0 || field.variant.ordinal >= layout.plan.variants.length) {
			throw new LlvmError.VERIFICATION ("sum projection lost intended instance or nominal variant identity");
		}
		var variant = layout.plan.variants[field.variant.ordinal];
		if (variant.identity != field.variant || field.ordinal < 0 || field.ordinal >= variant.fields.length || variant.fields[field.ordinal].identity != field || !gep (payload, root, layout.carrier, 1) || !gep (address, payload, (CApi.TypeRef) layout.variants[field.variant.ordinal], (uint) field.ordinal)) {
			throw new LlvmError.VERIFICATION ("sum projection lost exact base/variant/selected-field correspondence");
		}
	}
}

internal class LlvmSumRegistry : Object {
	private HashTable<void*, void*> ready = new HashTable<void*, void*> (direct_hash, direct_equal);
	private LlvmModuleArtifact artifact;
	private LlvmTypeMapper mapper;
	private LlvmTargetMachineArtifact target;
	private HashTable<EnumIdentity, LlvmSumLayout> layouts = new HashTable<EnumIdentity, LlvmSumLayout> (direct_hash, direct_equal);
	private HashTable<NativeRecordElement, void*> records = new HashTable<NativeRecordElement, void*> (direct_hash, direct_equal);
	private HashTable<NativeStructValuePlan, void*> record_values = new HashTable<NativeStructValuePlan, void*> (direct_hash, direct_equal);
	internal LlvmSumRegistry (LlvmModuleArtifact artifact, LlvmTypeMapper mapper, GenericArray<NativeSumPlan> plans) throws LlvmError {
		this.artifact = artifact;
		this.mapper = mapper;
		target = new LlvmTargetMachineArtifact ();
		artifact.sum_target = target;
		foreach (var binding in artifact.record_layouts) {
			records.insert (binding.element, (void*) binding.type);
		}
		foreach (var plan in plans) {
			build (plan);
		}
		artifact.sum_target_triple = target.triple;
		artifact.sum_data_layout = target.data_layout;
	}
	internal LlvmSumLayout lookup(EnumIdentity identity) throws LlvmError {
		var layout = layouts.lookup (identity);
		if (layout == null) {
			throw new LlvmError.LOWERING ("sum storage requires exact retained nominal layout");
		}
		return layout;
	}
	private CApi.TypeRef record_value_type(NativeStructValuePlan plan) throws LlvmError {
		if (record_values.contains (plan)) {
			return (CApi.TypeRef) record_values.lookup (plan);
		}
		var fields = new CApi.TypeRef[plan.leaves.length];
		for (int l = 0; l < fields.length; l++) {
			fields[l] = mapper.abi_type (plan.leaves[l].abi_type);
		}
		var result = CApi.struct_type_in_context (artifact.context, fields, fields.length, 0);
		record_values.insert (plan, (void*) result);
		return result;
	}
	internal CApi.ValueRef record_leaf(CApi.BuilderRef builder, NativeStructValuePlan plan, CApi.ValueRef root, uint ordinal) throws LlvmError {
		if (ordinal >= plan.leaves.length) {
			throw new LlvmError.LOWERING ("enum record lost its complete physical channel index");
		}
		return address (builder, record_value_type (plan), root, ordinal, "sum.record.value.leaf");
	}
	private LlvmSumLayout build(NativeSumPlan plan) throws LlvmError {
		var prior = layouts.lookup (plan.identity);
		if (prior != null) {
			return prior;
		}
		var variants = new void*[plan.variants.length];
		uint64 size = 0;
		uint alignment = 1;
		for (int v = 0; v < plan.variants.length; v++) {
			var variant = plan.variants[v];
			var fields = new CApi.TypeRef[variant.fields.length];
			for (int f = 0; f < fields.length; f++) {
				var field = variant.fields[f];
				fields[f] = field.record_value != null ? record_value_type(field.record_value) : field.buffer != null ? mapper.buffer_carrier() : field.sum != null ? build(field.sum).carrier : field.record != null ? (CApi.TypeRef) records.lookup (field.record) : mapper.abi_type (field.leaf);
			}
			var type = CApi.struct_type_in_context (artifact.context, fields, fields.length, 0);
			variants[v] = (void*) type;
			size = uint64.max (size, CApi.abi_size_of_type (target.enum_target_data (artifact), type));
			alignment = uint.max (alignment, CApi.abi_alignment_of_type (target.enum_target_data (artifact), type));
		}
		var unit = alignment == 16 ? CApi.vector_type (CApi.int_type_in_context (artifact.context, 8), 16) : CApi.int_type_in_context (artifact.context, alignment * 8);
		if (CApi.abi_size_of_type (target.enum_target_data (artifact), unit) != alignment || CApi.abi_alignment_of_type (target.enum_target_data (artifact), unit) != alignment) {
			throw new LlvmError.TARGET ("sum payload alignment has no exact target storage unit");
		}
		CApi.TypeRef[] fields = {
			CApi.int32_type_in_context (artifact.context), CApi.array_type (unit, (size + alignment - 1) / alignment)
		};
		var carrier = CApi.struct_type_in_context (artifact.context, fields, fields.length, 0);
		var result = new LlvmSumLayout (plan, carrier, variants, CApi.abi_size_of_type (target.enum_target_data (artifact), carrier), CApi.abi_alignment_of_type (target.enum_target_data (artifact), carrier), CApi.offset_of_element (target.enum_target_data (artifact), carrier, 1));
		result.verify (target.enum_target_data (artifact));
		layouts.insert (plan.identity, result);
		artifact.sum_layouts.add (result);
		return result;
	}
	internal CApi.ValueRef tag(CApi.BuilderRef builder, LlvmSumLayout layout, CApi.ValueRef root) {
		return address (builder, layout.carrier, root, 0, "sum.tag.address");
	}
	internal CApi.ValueRef field(CApi.BuilderRef builder, LlvmSumLayout layout, CApi.ValueRef root, EnumFieldIdentity identity) {
		var payload = CApi.build_struct_gep (builder, layout.carrier, root, 1, "sum.payload.address");
		var address = CApi.build_struct_gep (builder, (CApi.TypeRef) layout.variants[identity.variant.ordinal], payload, identity.ordinal, "sum.field.address");
		artifact.sum_projections.add (new LlvmSumProjection (layout, identity, root, payload, address));
		return address;
	}
	internal CApi.ValueRef address(CApi.BuilderRef builder, CApi.TypeRef type, CApi.ValueRef root, uint member, string name) {
		var result = CApi.build_struct_gep (builder, type, root, member, name);
		artifact.sum_addresses.add (new LlvmSumAddress (result, root, type, member));
		return result;
	}
	internal CApi.ValueRef read(CApi.BuilderRef builder, CApi.TypeRef type, CApi.ValueRef address, string name) {
		var result = CApi.build_load (builder, type, address, name);
		artifact.sum_reads.add (new LlvmSumRead (result, address, type));
		return result;
	}
	internal void publish(CApi.BuilderRef builder, CApi.ValueRef root) {
		ready.insert ((void*) root, (void*) CApi.last_instruction (CApi.insert_block (builder)));
	}
	internal void copy(CApi.BuilderRef builder, LlvmSumLayout layout, CApi.ValueRef destination, CApi.ValueRef source) {
		var instruction = CApi.build_mem_copy (builder, destination, layout.alignment, source, layout.alignment, CApi.const_int (CApi.int_type_in_context (artifact.context, 64), layout.size, 0));
		artifact.sum_copies.add (new LlvmSumCopy (artifact, instruction, destination, source, layout, (void*) ready.lookup ((void*) source)));
	}
	internal void store(CApi.BuilderRef builder, CApi.ValueRef value, CApi.ValueRef address) {
		var instruction = CApi.build_store (builder, value, address);
		artifact.sum_accesses.add (new LlvmSumAccess (instruction, address, value));
	}
	internal void clear(CApi.BuilderRef builder, LlvmSumLayout layout, CApi.ValueRef destination) {
		var instruction = CApi.build_mem_set (builder, destination, CApi.const_int (CApi.int_type_in_context (artifact.context, 8), 0, 0), CApi.const_int (CApi.int_type_in_context (artifact.context, 64), layout.size, 0), layout.alignment);
		artifact.sum_clears.add (new LlvmSumClear (artifact, instruction, destination, layout));
	}
}
}
