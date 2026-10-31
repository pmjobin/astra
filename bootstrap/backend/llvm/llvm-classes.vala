// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Ssa;
using Astra.Semantic;
using Astra.NativeAbi;

namespace Astra.Backend.LLVM {
// Purpose-specific relationships are supplied by lowering intent, before
// verification reads the emitted operands. Only physical handles survive.
internal class LlvmClassAddressBinding : Object {
	internal CApi.ValueRef instruction;
	private CApi.ValueRef root;
	private CApi.TypeRef layout;
	private uint member;
	private bool aggregate;
	private CApi.ValueRef lexical_function;
	private CApi.BasicBlockRef lexical_block;
	internal bool is_private { get { return (void*) lexical_function != null; } }
	internal LlvmClassAddressBinding (CApi.ValueRef instruction, CApi.ValueRef root, CApi.TypeRef layout, uint member, bool aggregate = true, CApi.ValueRef lexical_function = (CApi.ValueRef) null, CApi.BasicBlockRef lexical_block = (CApi.BasicBlockRef) null) {
		this.lexical_block = lexical_block;
		this.lexical_function = lexical_function;
		this.instruction = instruction;
		this.root = root;
		this.layout = layout;
		this.member = member;
		this.aggregate = aggregate;
	}
	internal void verify() throws LlvmError {
		// A constant-root GEP may fold to a constant (notably after an always
		// trapping null guard). Retain its actual authorized emission block;
		// materialized instructions must also remain in that lexical function.
		if ((void*) lexical_function != null && ((void*) lexical_block == null || (void*) CApi.block_parent (lexical_block) != (void*) lexical_function || ((void*) CApi.is_instruction (instruction) != null && (void*) CApi.block_parent (CApi.instruction_parent (instruction)) != (void*) lexical_function))) {
			throw new LlvmError.VERIFICATION ("private field address escaped its exact authorized lexical function");
		}
		uint count = aggregate ? 3 : 2;
		if ((void*) CApi.is_instruction (instruction) == null && CApi.is_constant (root) != 0) {
			var context = CApi.type_context (layout);
			CApi.ValueRef expected;
			if (aggregate) {
				// Struct GEP includes LLVM-version-specific nowrap flags. Rebuild
				// the intended constant with that exact operation, not plain GEP.
				var witness = CApi.create_builder_in_context (context);
				expected = CApi.build_struct_gep (witness, layout, root, member, "");
				CApi.dispose_builder (witness);
			} else {
				var integer = CApi.int32_type_in_context (context);
				var index = CApi.const_int (integer, member, 0);
				expected = CApi.const_gep (layout, root, &index, 1);
			}
			if ((void*) instruction == (void*) expected) {
				return;
			}
			throw new LlvmError.VERIFICATION ("class folded address lost intended complete layout, receiver and member");
		}
		if ((void*) CApi.is_instruction (instruction) == null || CApi.opcode (instruction) != CApi.Opcode.GEP || CApi.operand_count (instruction) != count || (void*) CApi.gep_source_type (instruction) != (void*) layout || (void*) CApi.operand (instruction, 0) != (void*) root) {
			throw new LlvmError.VERIFICATION ("class address lost intended complete layout and exact backing receiver (member=%u, aggregate=%s, operands=%d, layout=%s, root=%s)", member, aggregate.to_string (), CApi.operand_count (instruction), ((void*) CApi.gep_source_type (instruction) == (void*) layout).to_string (), ((void*) CApi.operand (instruction, 0) == (void*) root).to_string ());
		}
		if (aggregate && ((void*) CApi.is_constant_int (CApi.operand (instruction, 1)) == null || CApi.const_int_zext (CApi.operand (instruction, 1)) != 0)) {
			throw new LlvmError.VERIFICATION ("class address lost zero-offset complete parent path");
		}
		var index = CApi.operand (instruction, count - 1);
		if ((void*) CApi.is_constant_int (index) == null || CApi.const_int_zext (index) != member) {
			throw new LlvmError.VERIFICATION ("class address lost exact field/header/virtual slot selection");
		}
	}
}
internal class LlvmClassValueBinding : Object {
	internal CApi.ValueRef instruction;
	private CApi.Opcode operation;
	private void*[] operands;
	private CApi.TypeRef type;
	private string purpose;
	internal bool initializes_lazy_cache { get { return purpose == "lazy exact declaring cache construction Empty"; } }
	private int member;
	private int comparison;
	private int alignment;
	internal LlvmClassValueBinding (CApi.ValueRef instruction, CApi.Opcode operation, CApi.TypeRef type, CApi.ValueRef[] operands, string purpose, int member = -1, int comparison = -1, int alignment = -1) {
		this.alignment = alignment;
		this.comparison = comparison;
		this.instruction = instruction;
		this.operation = operation;
		this.type = type;
		this.purpose = purpose;
		this.member = member;
		this.operands = new void*[operands.length];
		for (int i = 0; i < operands.length; i++) {
			this.operands[i] = (void*) operands[i];
		}
	}
	internal void verify() throws LlvmError {
		if ((void*) CApi.is_instruction (instruction) == null || CApi.opcode (instruction) != operation || (void*) CApi.type_of (instruction) != (void*) type || CApi.operand_count (instruction) != operands.length) {
			throw new LlvmError.VERIFICATION ("class %s lost intended operation and complete channel type", purpose);
		}
		for (int i = 0; i < operands.length; i++) {
			if ((void*) CApi.operand (instruction, i) != operands[i]) {
				throw new LlvmError.VERIFICATION ("class %s lost exact owner/backing/channel association", purpose);
			}
		}
		if (alignment >= 0 && CApi.get_alignment (instruction) != alignment) {
			throw new LlvmError.VERIFICATION ("class %s lost prescribed memory alignment", purpose);
		}
		if (comparison >= 0 && (int) CApi.predicate (instruction) != comparison) {
			throw new LlvmError.VERIFICATION ("class %s lost exact subtype/origin comparison", purpose);
		}
		if (member >= 0 && (CApi.index_count (instruction) != 1 || CApi.indices (instruction)[0] != member)) {
			throw new LlvmError.VERIFICATION ("class %s lost exact pointer/count component selection", purpose);
		}
		if ((operation == CApi.Opcode.LOAD || operation == CApi.Opcode.STORE) && (CApi.get_volatile (instruction) != 0 || CApi.get_ordering (instruction) != 0)) {
			throw new LlvmError.VERIFICATION ("class %s changed ordinary read/write effects", purpose);
		}
	}
}
internal class LlvmClassPhiBinding : Object {
	private CApi.ValueRef instruction;
	private void*[] values;
	private void*[] blocks;
	internal LlvmClassPhiBinding (CApi.ValueRef instruction, CApi.ValueRef[] values, CApi.BasicBlockRef[] blocks) {
		this.instruction = instruction;
		this.values = new void*[values.length];
		this.blocks = new void*[blocks.length];
		for (int i = 0; i < values.length; i++) {
			this.values[i] = (void*) values[i];
			this.blocks[i] = (void*) blocks[i];
		}
	}
	internal void verify() throws LlvmError {
		if (CApi.opcode (instruction) != CApi.Opcode.PHI || CApi.incoming_count (instruction) != values.length || blocks.length != values.length) {
			throw new LlvmError.VERIFICATION ("checked admission lost complete original predecessor/result association");
		}
		for (uint i = 0; i < values.length; i++) {
			if ((void*) CApi.operand (instruction, i) != values[i] || (void*) CApi.incoming_block (instruction, i) != blocks[i]) {
				throw new LlvmError.VERIFICATION ("checked admission changed exact original predecessor or result");
			}
		}
	}
}
internal class LlvmClassCallBinding : Object {
	internal CApi.ValueRef instruction;
	private CApi.ValueRef target;
	private CApi.TypeRef signature;
	private void*[] arguments;
	private uint convention;
	private string purpose;
	internal LlvmClassCallBinding (CApi.ValueRef instruction, CApi.ValueRef target, CApi.TypeRef signature, CApi.ValueRef[] arguments, uint convention, string purpose) {
		this.instruction = instruction;
		this.target = target;
		this.signature = signature;
		this.convention = convention;
		this.purpose = purpose;
		this.arguments = new void*[arguments.length];
		for (int i = 0; i < arguments.length; i++) {
			this.arguments[i] = (void*) arguments[i];
		}
	}
	internal void verify() throws LlvmError {
		if ((void*) CApi.is_instruction (instruction) == null || CApi.opcode (instruction) != CApi.Opcode.CALL || (void*) CApi.called_value (instruction) != (void*) target || (void*) CApi.called_function_type (instruction) != (void*) signature || CApi.argument_count (instruction) != arguments.length || CApi.instruction_call_conv (instruction) != convention) {
			throw new LlvmError.VERIFICATION ("class %s lost exact target, signature or call convention", purpose);
		}
		for (int i = 0; i < arguments.length; i++) {
			if ((void*) CApi.operand (instruction, i) != arguments[i]) {
				throw new LlvmError.VERIFICATION ("class %s lost intended receiver/input/success/cleanup channel", purpose);
			}
		}
	}
}
internal class LlvmClassAllocationBinding : Object {
	private CApi.TypeRef complete_type;
	private uint64 size;
	private uint alignment;
	internal LlvmClassAllocationBinding (CApi.TypeRef complete_type, CApi.TargetDataRef data) {
		this.complete_type = complete_type;
		this.size = CApi.abi_size_of_type (data, complete_type);
		this.alignment = CApi.abi_alignment_of_type (data, complete_type);
	}
	internal void verify(CApi.TargetDataRef data) throws LlvmError {
		if (size == 0 || size != CApi.abi_size_of_type (data, complete_type) || alignment != CApi.abi_alignment_of_type (data, complete_type) || alignment == 0 || alignment > 16 || size % alignment != 0) {
			throw new LlvmError.VERIFICATION ("class allocation lost complete target extent and qualified calloc alignment");
		}
	}
}
internal class LlvmClassBranchBinding : Object {
	internal CApi.ValueRef instruction;
	private CApi.ValueRef condition;
	private CApi.BasicBlockRef matched;
	private CApi.BasicBlockRef next;
	internal LlvmClassBranchBinding (CApi.ValueRef instruction, CApi.ValueRef condition, CApi.BasicBlockRef matched, CApi.BasicBlockRef next) {
		this.instruction = instruction;
		this.condition = condition;
		this.matched = matched;
		this.next = next;
	}
	internal void verify() throws LlvmError {
		if (CApi.opcode (instruction) != CApi.Opcode.BR || CApi.successor_count (instruction) != 2 || (void*) CApi.operand (instruction, 0) != (void*) condition || (void*) CApi.successor (instruction, 0) != (void*) matched || (void*) CApi.successor (instruction, 1) != (void*) next) {
			throw new LlvmError.VERIFICATION ("class handler lost exact guarded condition and source-ordered target association");
		}
	}
}
internal class LlvmClassLayoutBinding : Object {
	internal CApi.TypeRef type;
	private CApi.TypeRef[] expected;
	internal LlvmClassLayoutBinding (CApi.TypeRef type, CApi.TypeRef[] expected) {
		this.type = type;
		this.expected = expected;
	}
	internal void verify() throws LlvmError {
		if (CApi.is_packed_struct (type) != 0 || CApi.count_struct_element_types (type) != expected.length) {
			throw new LlvmError.VERIFICATION ("native class layout lost complete naturally aligned parent/header/field shape");
		}
		for (int f = 0; f < expected.length; f++) {
			if ((void*) CApi.struct_get_type_at_index (type, f) != (void*) expected[f]) {
				throw new LlvmError.VERIFICATION ("native class layout lost exact copied field channel or zero-offset complete parent");
			}
		}
	}
}
internal class LlvmClassGlobalBinding : Object {
	internal CApi.ValueRef value;
	private void* initializer;
	private CApi.TypeRef type;
	private CApi.Linkage linkage;
	private CApi.Visibility visibility;
	private string? symbol;
	internal LlvmClassGlobalBinding (CApi.ValueRef value, CApi.ValueRef initializer, string? symbol = null, bool imported = false, bool windows_unit = false) {
		this.value = value;
		this.initializer = imported ? null : (void*) initializer;
		type = CApi.global_value_type (value);
		linkage = symbol == null ? CApi.Linkage.PRIVATE : CApi.Linkage.EXTERNAL;
		visibility = symbol != null && windows_unit ? CApi.Visibility.HIDDEN : CApi.Visibility.DEFAULT;
		this.symbol = symbol;
	}
	internal void verify() throws LlvmError {
		if ((void*) CApi.get_initializer (value) != initializer || (void*) CApi.global_value_type (value) != (void*) type ||
		    CApi.is_global_constant (value) != 1 || CApi.get_linkage (value) != linkage || CApi.get_visibility (value) != visibility) {
			throw new LlvmError.VERIFICATION ("native class descriptor, virtual table or original origin lost exact immutable publication correspondence");
		}
		if (symbol != null) {
			size_t length;
			if (CApi.value_name (value, out length) != symbol || length != symbol.length) {
				throw new LlvmError.VERIFICATION ("native class descriptor lost its original external symbol");
			}
		}
	}
}
internal class LlvmClassFunctionBinding : Object {
	internal CApi.ValueRef value;
	private CApi.TypeRef type;
	private uint parameters;
	private LlvmSumSequence sequence;
	internal LlvmClassFunctionBinding (CApi.ValueRef value, CApi.TypeRef type) {
		this.value = value;
		this.type = type;
		parameters = CApi.count_params (value);
		sequence = new LlvmSumSequence (value, true);
	}
	internal void verify() throws LlvmError {
		if ((void*) CApi.global_value_type (value) != (void*) type || CApi.count_params (value) != parameters || CApi.function_call_conv (value) != LlvmLowering.CALL_CONVENTION) {
			throw new LlvmError.VERIFICATION ("native class/exception function lost exact signature and call convention");
		}
		sequence.verify ();
	}
}
internal class LlvmClassRuntime : Object {
	private LlvmModuleArtifact artifact;
	private LlvmTypeMapper types;
	private LlvmStructRegistry structs;
	private NativeAbiProgram native;
	private HashTable<SsaFunction, LlvmFunctionBinding> functions;
	private HashTable<int, SsaClass> source_classes = new HashTable<int, SsaClass> (direct_hash, direct_equal);
	private HashTable<SsaStruct, int> source_record_ordinals = new HashTable<SsaStruct, int> (direct_hash, direct_equal);
	internal SsaClass? declaration(ClassType type) {
		foreach (var owner in source_classes.get_values ()) {
			if (owner.semantic_type == type) {
				return owner;
			}
		}
		return null;
	}
	internal SsaClass? declaration_ordinal(int ordinal) {
		return source_classes.lookup (ordinal);
	}
	internal void retire_foreign_wrapper(CApi.BuilderRef builder, CApi.ValueRef function, CApi.ValueRef root, SsaClass owner, LlvmBlockState state, LlvmBufferAllocation allocator) throws LlvmError {
		LlvmForeignClasses.retire_cache (artifact, types, structs, native, builder, function, root, owner, state, allocator);
	}
	internal void begin_foreign_retirement(CApi.BuilderRef builder, CApi.ValueRef function, CApi.ValueRef root, SsaClass owner, LlvmBlockState state) throws LlvmError {
		LlvmForeignClasses.begin_retirement (artifact, types, structs, native, builder, function, root, owner, state);
	}
	internal void release_owned(CApi.BuilderRef builder, CApi.ValueRef function, LlvmBufferAllocation allocator, SsaClass owner, CApi.ValueRef pointer, LlvmBlockState state, string name) throws LlvmError {
		if (((ClassType) owner.semantic_type).intrinsically_shared) {
			var scalars = new LlvmScalarLowering (artifact, types, builder, function);
			new LlvmSharedLowering (artifact, types, builder, function, scalars, allocator, this, functions).release_payload (pointer, owner, false, state);
			return;
		}
		if (owner.polymorphic) {
			destroy (builder, function, pointer, name, state, allocator, true, (ClassType) owner.semantic_type);
			return;
		}
		begin_foreign_retirement (builder, function, pointer, owner, state);
		if (owner.destructor != null) {
			var target = functions.lookup (owner.destructor);
			if (target == null) {
				throw new LlvmError.LOWERING ("aggregate Class cleanup lost its original destructor");
			}
			var arguments = new CApi.ValueRef[] {
				pointer
			};
			var call = CApi.build_call (builder, target.type, target.value, arguments, 1, "");
			CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
			artifact.class_calls.add (new LlvmClassCallBinding (call, target.value, target.type, arguments, LlvmLowering.CALL_CONVENTION, "aggregate exact Class destructor"));
		}
		retire_monitor (builder, pointer, (ClassType) owner.semantic_type, state);
		if (owner.foreign_export != null && owner.foreign_export.declared_api != null) {
			retire_foreign_wrapper (builder, function, pointer, owner, state, allocator);
		}
		allocator.deallocate (pointer, name + ".free", state, owner.allocation_policy, owner.name);
	}
	internal void release_scalar(CApi.BuilderRef builder, CApi.ValueRef function, LlvmBufferAllocation allocator, NativeScalarOwner owner, CApi.ValueRef pointer, LlvmBlockState state, string name) throws LlvmError {
		exact_class (owner);
		var declaration = source_classes.lookup (owner.class_ordinal);
		if (declaration == null) {
			throw new LlvmError.LOWERING ("aggregate Class cleanup lost its exact SSA owner");
		}
		release_owned (builder, function, allocator, declaration, pointer, state, name);
	}
	internal NativeStructValuePlan inline_record(SsaStructField field) throws LlvmError {
		var owner = field.containing_type as SsaClass;
		if (owner == null || owner.ordinal < 0 || owner.ordinal >= native.classes.length || field.record_owner == null || field.ordinal < 0 || field.ordinal >= native.classes[owner.ordinal].fields.length) {
			throw new LlvmError.LOWERING ("inline record lost exact declaring Class and field");
		}
		var declared = native.classes[owner.ordinal].fields[field.ordinal];
		// Native record ordinals index the retained declaration array. SSA keeps
		// the original source ordinal when unused export anchors are pruned.
		if (!source_record_ordinals.contains (field.record_owner) || !declared.owns_record || declared.record_ordinal != source_record_ordinals.lookup (field.record_owner) || declared.type_name != field.semantic_type.display_name ()) {
			throw new LlvmError.LOWERING ("inline record lost independent native ownership layout");
		}
		foreach (var plan in native.struct_values) {
			if (plan.struct_ordinal == declared.record_ordinal && plan.struct_name == declared.type_name && plan.mode == NativeStructValueMode.MOVE_VALUE) {
				return plan;
			}
		}
		throw new LlvmError.LOWERING ("inline record lost complete native leaf and retirement plan");
	}

	internal NativeStructValuePlan? slot_record(SsaStructField field) throws LlvmError {
		var owner = field.containing_type as SsaClass;
		if (owner == null || owner.ordinal < 0 || owner.ordinal >= native.classes.length || native.classes[owner.ordinal].name != owner.name || field.ordinal < 0 || field.ordinal >= native.classes[owner.ordinal].fields.length) {
			throw new LlvmError.LOWERING ("slot layout lost its exact native declaring Class/field");
		}
		var slot = native.classes[owner.ordinal].fields[field.ordinal].storage_type as NativeOwnerSlotsType;
		if (slot == null || !slot.matches_record_layout ()) {
			throw new LlvmError.LOWERING ("slot layout lost its original native element declaration");
		}
		return slot.record_value;
	}
	private HashTable<int, LlvmFunctionBinding> exact_destructors = new HashTable<int, LlvmFunctionBinding> (direct_hash, direct_equal);
	internal LlvmFunctionBinding? exact_destructor(NativeScalarOwner owner) throws LlvmError {
		int ordinal = owner.class_ordinal;
		if (ordinal < 0 || ordinal >= native.classes.length || native.classes[ordinal].name != owner.type_name || native.classes[ordinal].polymorphic || native.classes[ordinal].is_interface) {
			throw new LlvmError.LOWERING ("sum heap owner lost its exact native Class declaration");
		}
		return exact_destructors.lookup (ordinal);
	}
	internal NativeClassPlan exact_class(NativeScalarOwner owner) throws LlvmError {
		exact_destructor (owner);
		return native.classes[owner.class_ordinal];
	}
	private HashTable<SsaClass, void*> descriptors = new HashTable<SsaClass, void*> (direct_hash, direct_equal);
	private HashTable<ClassType, void*> nominal_descriptors = new HashTable<ClassType, void*> (direct_hash, direct_equal);
	private int origin_count;
	private int match_count;
	private CApi.TypeRef header;
	private CApi.TypeRef descriptor;
	private CApi.ValueRef field_address(CApi.BuilderRef builder, CApi.TypeRef layout, CApi.ValueRef root, uint member, string name) {
		var instruction = CApi.build_struct_gep (builder, layout, root, member, name);
		artifact.class_addresses.add (new LlvmClassAddressBinding (instruction, root, layout, member));
		return instruction;
	}
	private CApi.ValueRef compare(CApi.BuilderRef builder, CApi.ValueRef left, CApi.ValueRef right, string name) {
		var instruction = CApi.build_icmp (builder, CApi.IntPredicate.EQ, left, right, name);
		if ((void*) CApi.is_instruction (instruction) != null) {
			artifact.class_values.add (new LlvmClassValueBinding (instruction, CApi.Opcode.ICMP, CApi.int1_type_in_context (artifact.context), new CApi.ValueRef[] { left, right }, "subtype/origin comparison", -1, (int) CApi.IntPredicate.EQ));
		}
		return instruction;
	}
	private CApi.ValueRef read(CApi.BuilderRef builder, CApi.TypeRef type, CApi.ValueRef address, string name) {
		var instruction = CApi.build_load (builder, type, address, name);
		artifact.class_values.add (new LlvmClassValueBinding (instruction, CApi.Opcode.LOAD, type, new CApi.ValueRef[] { address }, "header/descriptor read"));
		return instruction;
	}
	private void store(CApi.BuilderRef builder, CApi.ValueRef value, CApi.ValueRef address) {
		var instruction = CApi.build_store (builder, value, address);
		artifact.class_values.add (new LlvmClassValueBinding (instruction, CApi.Opcode.STORE, CApi.void_type_in_context (artifact.context), new CApi.ValueRef[] { value, address }, "header/origin publication"));
	}
	internal LlvmClassRuntime (LlvmModuleArtifact artifact, LlvmTypeMapper types, SsaProgram program, HashTable<SsaFunction, LlvmFunctionBinding> functions, LlvmStructRegistry structs, NativeAbiProgram native, LlvmNativeModulePlan? modules = null) throws LlvmError {
		this.artifact = artifact;
		this.types = types;
		this.structs = structs;
		this.native = native;
		this.functions = functions;
		for (int i = 0; i < program.structs.length; i++) {
			source_record_ordinals.insert (program.structs[i], i);
		}
		var pointer = types.scalar (NativeScalarType.PTR);
		CApi.TypeRef[] header_fields = {
			pointer, pointer
		};
		header = CApi.struct_type_in_context (artifact.context, header_fields, header_fields.length, 0);
		CApi.TypeRef[] descriptor_fields = {
			pointer, pointer, pointer
		};
		descriptor = CApi.struct_type_in_context (artifact.context, descriptor_fields, descriptor_fields.length, 0);
		foreach (var owner in program.classes) {
			source_classes.insert (owner.ordinal, owner);
			if (owner.destructor != null) {
				exact_destructors.insert (owner.ordinal, functions.lookup (owner.destructor));
			}
			if (!owner.polymorphic) {
				continue;
			}
			string? symbol = modules == null ? null : modules.descriptor_symbol (owner);
			var value = CApi.add_global (artifact.module, descriptor, symbol ?? "astra.class.descriptor.%d".printf (owner.ordinal));
			CApi.set_linkage (value, symbol == null ? CApi.Linkage.PRIVATE : CApi.Linkage.EXTERNAL);
			// Opaque Windows units link native descriptors within the same image.
			// Hidden visibility makes that authority local to the image, avoiding
			// a second public COFF .refptr symbol for an imported descriptor.
			if (symbol != null && artifact.selected_target == LlvmTargetMachineArtifact.WINDOWS_INTEROP) {
				CApi.set_visibility (value, CApi.Visibility.HIDDEN);
			}
			CApi.set_global_constant (value, 1);
			descriptors.insert (owner, (void*) value);
			nominal_descriptors.insert ((ClassType) owner.semantic_type, (void*) value);
		}
		foreach (var owner in program.classes) {
			if (!owner.polymorphic) {
				continue;
			}
			string? symbol = modules == null ? null : modules.descriptor_symbol (owner);
			var parent = owner.parent_class == null ? CApi.const_null(pointer) : (CApi.ValueRef) descriptors.lookup (owner.parent_class);
			var destroy = owner.destructor == null ? CApi.const_null(pointer) : functions.lookup (owner.destructor).value;
			if (symbol != null && modules.descriptor_imported (owner)) {
				var value = (CApi.ValueRef) descriptors.lookup (owner);
				var global = new LlvmClassGlobalBinding (value, value, symbol, true, artifact.selected_target == LlvmTargetMachineArtifact.WINDOWS_INTEROP);
				artifact.class_globals.add (global);
				artifact.scoped_descriptors.insert (owner.ordinal, new LlvmScopedDescriptorAuthority (value, parent, destroy, global, true));
				continue;
			}
			var table = CApi.const_null (pointer);
			if (owner.virtual_entries.length != 0) {
				var entries = new CApi.ValueRef[owner.virtual_entries.length * 2];
				for (int v = 0; v < owner.virtual_entries.length; v++) {
					var implementation = functions.lookup (owner.virtual_entries[v]);
					var declaration = owner.virtual_entries[v];
					for (var ancestor = owner.parent_class; ancestor != null; ancestor = ancestor.parent_class) {
						if (ancestor.virtual_entries.length > v) {
							declaration = ancestor.virtual_entries[v];
						}
					}
					var inherited = functions.lookup (declaration);
					entries[v * 2] = implementation.value;
					entries[v * 2 + 1] = implementation.value;
					if (inherited.signature.exception_plan != null && implementation.signature.exception_plan == null) {
						entries[v * 2 + 1] = nonthrowing_adapter (owner.ordinal, v, inherited, implementation);
					}
				}
				table = CApi.add_global (artifact.module, CApi.array_type (pointer, entries.length), "astra.class.slots.%d".printf (owner.ordinal));
				CApi.set_linkage (table, CApi.Linkage.PRIVATE);
				CApi.set_global_constant (table, 1);
				var expected_table = CApi.const_array (pointer, entries, entries.length);
				CApi.set_initializer (table, expected_table);
				artifact.class_globals.add (new LlvmClassGlobalBinding (table, expected_table));
			}
			CApi.ValueRef[] fields = {
				parent, destroy, table
			};
			var expected_descriptor = CApi.const_struct (artifact.context, fields, fields.length, 0);
			CApi.set_initializer ((CApi.ValueRef) descriptors.lookup (owner), expected_descriptor);
			var global = new LlvmClassGlobalBinding ((CApi.ValueRef) descriptors.lookup (owner), expected_descriptor, symbol, false, artifact.selected_target == LlvmTargetMachineArtifact.WINDOWS_INTEROP);
			artifact.class_globals.add (global);
			artifact.scoped_descriptors.insert (owner.ordinal, new LlvmScopedDescriptorAuthority ((CApi.ValueRef) descriptors.lookup (owner), parent, destroy, global, false));
		}
	}
	private CApi.ValueRef nonthrowing_adapter(int owner, int slot, LlvmFunctionBinding inherited, LlvmFunctionBinding implementation) throws LlvmError {
		var adapter = CApi.add_function (artifact.module, "astra.virtual.adapter.%d.%d".printf (owner, slot), inherited.type);
		CApi.set_linkage (adapter, CApi.Linkage.INTERNAL);
		CApi.set_function_call_conv (adapter, LlvmLowering.CALL_CONVENTION);
		var block = CApi.append_basic_block_in_context (artifact.context, adapter, "entry");
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_at_end (builder, block);
		var arguments = new CApi.ValueRef[implementation.signature.physical_parameter_count];
		int component = 0;
		for (int p = 0; p < inherited.signature.physical_parameter_count; p++) {
			if (inherited.signature.has_exception_success_slot && p == 1) {
				continue;
			}
			arguments[component++] = CApi.get_param (adapter, p);
		}
		var called = CApi.build_call (builder, implementation.type, implementation.value, arguments, arguments.length, implementation.signature.result == null ? "" : "override.success");
		CApi.set_instruction_call_conv (called, LlvmLowering.CALL_CONVENTION);
		artifact.class_calls.add (new LlvmClassCallBinding (called, implementation.value, implementation.type, arguments, LlvmLowering.CALL_CONVENTION, "nonthrowing override adapter"));
		if (inherited.signature.has_exception_success_slot) {
			var destination = CApi.get_param (adapter, 1);
			var publication = CApi.build_store (builder, called, destination);
			artifact.class_values.add (new LlvmClassValueBinding (publication, CApi.Opcode.STORE, CApi.void_type_in_context (artifact.context), new CApi.ValueRef[] { called, destination }, "nonthrowing override success publication"));
		}
		CApi.build_ret (builder, CApi.const_null (types.scalar (NativeScalarType.PTR)));
		CApi.dispose_builder (builder);
		artifact.class_functions.add (new LlvmClassFunctionBinding (adapter, inherited.type));
		return adapter;
	}
	internal void initialize(CApi.BuilderRef builder, SsaClass owner, CApi.ValueRef pointer, string name) throws LlvmError {
		if (owner.foreign_export != null) {
			store (builder, CApi.const_null (types.scalar (NativeScalarType.PTR)), LlvmForeignClasses.cache_address (artifact, structs, native, builder, pointer, owner));
		}
		if (owner.foreign_export != null && owner.foreign_export.declared_api != null) {
			store (builder, LlvmForeignClasses.context_identity (artifact, types, builder), LlvmForeignClasses.root_context_address (artifact, structs, native, builder, pointer, owner));
		}
		LlvmLazyProperties.initialize (artifact, types, structs, native, builder, owner, pointer, name);
		if (owner.concurrency_policy != null) {
			var root = owner;
			while (root.parent_class != null) {
				root = root.parent_class;
			}
			var layout = structs.lookup (root);
			var count_type = types.scalar (NativeScalarType.U64);
			for (uint index = 2; index <= 3; index++) {
				var place = field_address (builder, layout, pointer, index, "shared.initial.count");
				var initial = CApi.const_int (count_type, owner.concurrency_policy.shared ? 1 : 0, 0);
				var publication = CApi.build_store (builder, initial, place);
				CApi.set_alignment (publication, 8);
				CApi.set_ordering (publication, 2);
				artifact.shared_atomics.add (new LlvmSharedAtomicBinding (publication, place, CApi.Opcode.STORE, 2, (CApi.ValueRef) null, initial));
			}
			var monitor = owner.concurrency_policy.monitor ? LlvmConcurrencyRuntime.call (artifact, builder, "astra_monitor_create", types.scalar (NativeScalarType.PTR), null, null) : CApi.const_null (types.scalar (NativeScalarType.PTR));
			store (builder, monitor, field_address (builder, layout, pointer, 4, "monitor.initial"));
			var thread = owner.concurrency_policy.thread_bound ? LlvmConcurrencyRuntime.call (artifact, builder, "astra_concurrency_thread_identity", count_type, null, null) : CApi.const_null (count_type);
			store (builder, thread, field_address (builder, layout, pointer, 5, "thread.initial"));
		}

		if (!owner.polymorphic) {
			return;
		}
		var class_address = field_address (builder, header, pointer, 0, name + ".class.address");
		store (builder, (CApi.ValueRef) descriptors.lookup (owner), class_address);
		var origin_address = field_address (builder, header, pointer, 1, name + ".origin.address");
		store (builder, CApi.const_null (CApi.struct_type_at_index (header, 1)), origin_address);
	}
	internal void retire_monitor(CApi.BuilderRef builder, CApi.ValueRef pointer, ClassType type, LlvmBlockState state) throws LlvmError {
		if (!type.monitored) {
			return;
		}
		var function = CApi.block_parent (CApi.insert_block (builder));
		var live = CApi.append_basic_block_in_context (artifact.context, function, "monitor.retire.live");
		var done = CApi.append_basic_block_in_context (artifact.context, function, "monitor.retire.done");
		var empty = compare (builder, pointer, CApi.const_null (types.scalar (NativeScalarType.PTR)), "monitor.retire.empty");
		var branch = CApi.build_cond_br (builder, empty, done, live);
		artifact.class_branches.add (new LlvmClassBranchBinding (branch, empty, done, live));
		CApi.position_builder_at_end (builder, live);
		var monitor = LlvmConcurrencyRuntime.member (artifact, builder, pointer, 4);
		LlvmConcurrencyRuntime.call (artifact, builder, "astra_monitor_destroy", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { types.scalar (NativeScalarType.PTR) }, new CApi.ValueRef[] { monitor });
		CApi.build_br (builder, done);
		CApi.position_builder_at_end (builder, done);
		state.end = done;
	}
	private CApi.ValueRef class_descriptor(CApi.BuilderRef builder, CApi.ValueRef pointer, string name) throws LlvmError {
		var address = field_address (builder, header, pointer, 0, name + ".class.address");
		return read (builder, types.scalar (NativeScalarType.PTR), address, name + ".class");
	}
	internal CApi.ValueRef virtual_target(CApi.BuilderRef builder, CApi.ValueRef receiver, int slot, bool throwing, string name) throws LlvmError {
		var owner = class_descriptor (builder, receiver, name);
		var table_address = field_address (builder, descriptor, owner, 2, name + ".table.address");
		var table = read (builder, types.scalar (NativeScalarType.PTR), table_address, name + ".table");
		var index = CApi.const_int (types.scalar (NativeScalarType.I32), slot * 2 + (throwing ? 1 : 0), 0);
		var slot_address = CApi.build_gep (builder, types.scalar (NativeScalarType.PTR), table, &index, 1, name + ".slot.address");
		artifact.class_addresses.add (new LlvmClassAddressBinding (slot_address, table, types.scalar (NativeScalarType.PTR), slot * 2 + (throwing ? 1 : 0), false));
		return read (builder, types.scalar (NativeScalarType.PTR), slot_address, name + ".implementation");
	}
	internal void stamp_origin(CApi.BuilderRef builder, CApi.ValueRef exception, Astra.Source.SourceSpan span) throws LlvmError {
		string name = "astra.exception.origin.%d".printf (origin_count++);
		string path = span.file.path;
		var byte = types.scalar (NativeScalarType.U8);
		var bytes = new CApi.ValueRef[path.length];
		for (int i = 0; i < bytes.length; i++) {
			bytes[i] = CApi.const_int (byte, (uint8) path[i], 0);
		}
		var data = CApi.const_array (byte, bytes, bytes.length);
		var file = CApi.add_global (artifact.module, CApi.type_of (data), name + ".file");
		CApi.set_linkage (file, CApi.Linkage.PRIVATE);
		CApi.set_global_constant (file, 1);
		CApi.set_initializer (file, data);
		artifact.class_globals.add (new LlvmClassGlobalBinding (file, data));
		int line;
		int column;
		span.file.locate (span.start, out line, out column);
		var integer = types.scalar (NativeScalarType.I32);
		CApi.ValueRef[] fields = {
			file, CApi.const_int (integer, path.length, 0), CApi.const_int (integer, line, 0), CApi.const_int (integer, column, 0)
		};
		var token = CApi.const_struct (artifact.context, fields, fields.length, 0);
		var origin = CApi.add_global (artifact.module, CApi.type_of (token), name);
		CApi.set_linkage (origin, CApi.Linkage.PRIVATE);
		CApi.set_global_constant (origin, 1);
		CApi.set_initializer (origin, token);
		artifact.class_globals.add (new LlvmClassGlobalBinding (origin, token));
		var address = field_address (builder, header, exception, 1, name + ".address");
		var prior = read (builder, types.scalar (NativeScalarType.PTR), address, name + ".prior");
		var fresh = compare (builder, prior, CApi.const_null (types.scalar (NativeScalarType.PTR)), name + ".fresh");
		var original = CApi.build_select (builder, fresh, origin, prior, name + ".original");
		artifact.class_values.add (new LlvmClassValueBinding (original, CApi.Opcode.SELECT, types.scalar (NativeScalarType.PTR), new CApi.ValueRef[] { fresh, origin, prior }, "original throw origin"));
		store (builder, original, address);
	}
	internal CApi.ValueRef matches(CApi.BuilderRef builder, CApi.ValueRef function, CApi.ValueRef exception, ClassType match_type, LlvmBlockState state) throws LlvmError {
		string name = "exception.match.%d".printf (match_count++);
		var pointer = types.scalar (NativeScalarType.PTR);
		var boolean = types.scalar (NativeScalarType.B1);
		var wanted = (CApi.ValueRef) nominal_descriptors.lookup (match_type);
		if ((void*) wanted == null) {
			throw new LlvmError.LOWERING ("catch class has no exact native descriptor");
		}
		var live = CApi.append_basic_block_in_context (artifact.context, function, name + ".live");
		var loop = CApi.append_basic_block_in_context (artifact.context, function, name + ".ancestry");
		var advance = CApi.append_basic_block_in_context (artifact.context, function, name + ".parent");
		var yes = CApi.append_basic_block_in_context (artifact.context, function, name + ".yes");
		var no = CApi.append_basic_block_in_context (artifact.context, function, name + ".no");
		var joined = CApi.append_basic_block_in_context (artifact.context, function, name + ".done");
		CApi.build_cond_br (builder, compare (builder, exception, CApi.const_null (pointer), name + ".null"), no, live);
		CApi.position_builder_at_end (builder, live);
		var first = class_descriptor (builder, exception, name);
		CApi.build_br (builder, loop);
		CApi.position_builder_at_end (builder, loop);
		var current = CApi.build_phi (builder, pointer, name + ".class");
		CApi.build_cond_br (builder, compare (builder, current, wanted, name + ".is.subtype"), yes, advance);
		CApi.position_builder_at_end (builder, advance);
		var address = field_address (builder, descriptor, current, 0, name + ".parent.address");
		var parent = read (builder, pointer, address, name + ".parent.class");
		CApi.build_cond_br (builder, compare (builder, parent, CApi.const_null (pointer), name + ".root"), no, loop);
		CApi.ValueRef[] ancestors = {
			first, parent
		};
		CApi.BasicBlockRef[] ancestor_blocks = {
			live, advance
		};
		CApi.add_incoming (current, ancestors, ancestor_blocks, ancestors.length);
		CApi.position_builder_at_end (builder, yes);
		CApi.build_br (builder, joined);
		CApi.position_builder_at_end (builder, no);
		CApi.build_br (builder, joined);
		CApi.position_builder_at_end (builder, joined);
		state.end = joined;
		var result = CApi.build_phi (builder, boolean, name + ".result");
		CApi.ValueRef[] values = {
			CApi.const_int (boolean, 1, 0), CApi.const_int (boolean, 0, 0)
		};
		CApi.BasicBlockRef[] branches = {
			yes, no
		};
		CApi.add_incoming (result, values, branches, values.length);
		return result;
	}
	internal void destroy(CApi.BuilderRef builder, CApi.ValueRef function, CApi.ValueRef pointer, string name, LlvmBlockState state, LlvmBufferAllocation allocator, bool release_allocation = true, ClassType? owner_type = null) throws LlvmError {
		var pointer_type = types.scalar (NativeScalarType.PTR);
		var live = CApi.append_basic_block_in_context (artifact.context, function, name + ".live");
		var joined = CApi.append_basic_block_in_context (artifact.context, function, name + ".done");
		CApi.build_cond_br (builder, compare (builder, pointer, CApi.const_null (pointer_type), name + ".null"), joined, live);
		CApi.position_builder_at_end (builder, live);
		state.end = live;
		var owner = class_descriptor (builder, pointer, name);
		var entry_address = field_address (builder, descriptor, owner, 1, name + ".destroy.address");
		var entry = read (builder, pointer_type, entry_address, name + ".destroy");
		var invokes = CApi.append_basic_block_in_context (artifact.context, function, name + ".invoke");
		var releases = CApi.append_basic_block_in_context (artifact.context, function, name + ".release");
		CApi.build_cond_br (builder, compare (builder, entry, CApi.const_null (pointer_type), name + ".no.deinit"), releases, invokes);
		CApi.position_builder_at_end (builder, invokes);
		var signature = CApi.function_type (CApi.void_type_in_context (artifact.context), &pointer_type, 1, 0);
		var call = CApi.build_call (builder, signature, entry, &pointer, 1, "");
		CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
		artifact.class_calls.add (new LlvmClassCallBinding (call, entry, signature, new CApi.ValueRef[] { pointer }, LlvmLowering.CALL_CONVENTION, "complete dynamic destruction"));
		CApi.build_br (builder, releases);
		CApi.position_builder_at_end (builder, releases);
		state.end = releases;
		if (owner_type != null) {
			retire_monitor (builder, pointer, owner_type, state);
		}
		if (release_allocation) {
			allocator.deallocate (pointer, name + ".free", state);
		}
		CApi.build_br (builder, joined);
		CApi.position_builder_at_end (builder, joined);
		state.end = joined;
	}
}
}
