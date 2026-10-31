// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Ssa;
using Astra.NativeAbi;
using Astra.Semantic;

namespace Astra.Backend.LLVM {
// One exact leaf responsibility map serves aggregate storage and sum payloads.
internal class LlvmRecordOwnership : Object {
	private LlvmModuleArtifact artifact;
	private LlvmTypeMapper types;
	private LlvmClassRuntime classes;
	private HashTable<SsaCleanupContract, Astra.CAbi.CAbiCleanupFunction> cleanup_correspondence;
	private HashTable<Astra.CAbi.CAbiCleanupFunction, LlvmCFunctionBinding> cleanup_functions;
	internal LlvmRecordOwnership (LlvmModuleArtifact artifact, LlvmTypeMapper types, LlvmClassRuntime classes, HashTable<SsaCleanupContract, Astra.CAbi.CAbiCleanupFunction> cleanup_correspondence, HashTable<Astra.CAbi.CAbiCleanupFunction, LlvmCFunctionBinding> cleanup_functions) {
		this.artifact = artifact;
		this.types = types;
		this.classes = classes;
		this.cleanup_correspondence = cleanup_correspondence;
		this.cleanup_functions = cleanup_functions;
	}
	internal void destroy_record(CApi.BuilderRef builder, CApi.ValueRef function, LlvmBufferAllocation allocator, NativeStructValuePlan plan, CApi.ValueRef[] leaves, LlvmBlockState state, string name) throws LlvmError {
		if (leaves.length != plan.leaves.length) {
			throw new LlvmError.LOWERING ("record cleanup requires every original physical channel");
		}
		for (int f = plan.ownership.length - 1; f >= 0; f--) {
			var owner = plan.ownership[f];
			int channel = -1;
			for (int l = 0; l < plan.leaves.length; l++) {
				var leaf = plan.leaves[l];
				if (leaf.storage_path == owner.field_path && leaf.buffer_component <= 0) {
					if (channel >= 0) {
						throw new LlvmError.LOWERING ("record cleanup has duplicate pointer channels");
					}
					channel = l;
				}
			}
			if (channel < 0) {
				throw new LlvmError.LOWERING ("record cleanup lost an original owner channel");
			}
			if (owner.buffer_cleanup != null) {
				allocator.deallocate_buffer (leaves[channel], name + ".buffer%d".printf (f), state, owner.buffer_cleanup.context_origin);
			} else {
				destroy_scalar (builder, function, allocator, new NativeScalarOwner (owner.type_name, owner.cleanup_symbol, owner.cleanup_class_ordinal), leaves[channel], state, name + ".field%d".printf (f));
			}
		}
	}
	internal void destroy_scalar(CApi.BuilderRef builder, CApi.ValueRef function, LlvmBufferAllocation allocator, NativeScalarOwner owner, CApi.ValueRef pointer, LlvmBlockState state, string name) throws LlvmError {
		LlvmCFunctionBinding? foreign = null;
		LlvmFunctionBinding? destructor = null;
		if (owner.class_ordinal >= 0) {
			classes.exact_class (owner);
		} else {
			foreach (var contract in cleanup_correspondence.get_keys ()) {
				if (contract.external_symbol != owner.cleanup_symbol) {
					continue;
				}
				foreign = cleanup_functions.lookup (cleanup_correspondence.lookup (contract));
				break;
			}
			if (foreign == null) {
				throw new LlvmError.LOWERING ("Resource lost its original declared foreign cleanup binding");
			}
		}
		var dispose = CApi.append_basic_block_in_context (artifact.context, function, name + ".dispose");
		var next = CApi.append_basic_block_in_context (artifact.context, function, name + ".done");
		var is_null = CApi.build_icmp (builder, CApi.IntPredicate.EQ, pointer, CApi.const_null (types.scalar (NativeScalarType.PTR)), name + ".null");
		CApi.build_cond_br (builder, is_null, next, dispose);
		CApi.position_builder_at_end (builder, dispose);
		state.end = dispose;
		if (owner.class_ordinal >= 0) {
			classes.release_scalar (builder, function, allocator, owner, pointer, state, name);
		}
		if (foreign != null || destructor != null) {
			var target = foreign != null ? foreign.value : destructor.value;
			var signature = foreign != null ? foreign.type : destructor.type;
			uint convention = foreign != null ? (uint) CApi.CallConv.C : LlvmLowering.CALL_CONVENTION;
			var arguments = new CApi.ValueRef[] {
				pointer
			};
			var call = CApi.build_call (builder, signature, target, arguments, 1, "");
			CApi.set_instruction_call_conv (call, convention);
			if (foreign != null) {
				foreign.calls.add ((void*) call);
			}
			artifact.class_calls.add (new LlvmClassCallBinding (call, target, signature, arguments, convention, "exact scalar owner cleanup"));
		}
		CApi.build_br (builder, next);
		CApi.position_builder_at_end (builder, next);
		state.end = next;
	}
}

internal class LlvmRecordLayoutBinding : Object {
	internal NativeRecordElement element;
	internal CApi.TypeRef type;
	internal NativeRecordLayout? layout;
	internal uint fixed_count;
	internal bool allocated;
	internal LlvmRecordLayoutBinding (NativeRecordElement element, CApi.TypeRef type) {
		this.element = element;
		this.type = type;
	}
}

// Compiler-internal target-dependent layout, never a language aggregate ABI.
// Registry keys are exact SSA descriptors; LLVM context owns the type handles.
internal class LlvmStructRegistry : Object {
	private HashTable<SsaNativeInstance, void*> types = new HashTable<SsaNativeInstance, void*> (direct_hash, direct_equal);
	private HashTable<SsaStructField, LlvmBufferFieldBinding> buffer_fields = new HashTable<SsaStructField, LlvmBufferFieldBinding> (direct_hash, direct_equal);

	internal GenericArray<SemanticType>? fields(SemanticType type) {
		foreach (var structure in types.get_keys ()) {
			if (structure.semantic_type != type) {
				continue;
			}
			var result = new GenericArray<SemanticType> ();
			foreach (var field in structure.fields) {
				result.add (field.semantic_type);
			}
			return result;
		}
		return null;
	}
	internal SsaStruct? debug_record(SemanticType type) {
		foreach (var structure in types.get_keys ()) {
			if (structure.semantic_type == type) {
				return structure as SsaStruct;
			}
		}
		return null;
	}
	internal SsaClass? debug_class(SemanticType type) {
		foreach (var structure in types.get_keys ()) {
			if (structure.semantic_type == type) {
				return structure as SsaClass;
			}
		}
		return null;
	}

	internal LlvmStructRegistry (LlvmModuleArtifact artifact, LlvmTypeMapper mapper, SsaProgram program, NativeAbiProgram native, string[]? required_layouts = null) throws LlvmError, NativeAbiError {
		var needed = new HashTable<SsaNativeInstance, SsaNativeInstance> (direct_hash, direct_equal);
		foreach (var function in native.functions) {
			if (function.declaring_type_is_class && LlvmScopedBorrowBinding.requires_layout (function)) {
				int ordinal = function.declaring_type_ordinal;
				if (ordinal < 0 || ordinal >= native.classes.length || ordinal >= program.classes.length || native.classes[ordinal].name != program.classes[ordinal].name) {
					throw new LlvmError.INVALID_INPUT ("receiver Class layout lost its exact source/native correspondence");
				}
				var owner = program.classes[ordinal];
				needed.insert (owner, owner);
			}
		}
		foreach (string name in required_layouts ?? new string[0]) {
			foreach (var structure in program.structs) {
				if (structure.semantic_type.nominal_name () == name) {
					needed.insert (structure, structure);
				}
			}
			foreach (var owner in program.classes) {
				if (owner.semantic_type.nominal_name () == name) {
					needed.insert (owner, owner);
				}
			}
		}
		foreach (var owner in program.classes) {
			if (owner.foreign_export != null) {
				needed.insert (owner, owner);
			}
			foreach (var property in owner.properties) {
				if (property.is_lazy) {
					needed.insert (owner, owner);
				}
			}
		}
		foreach (var function in native.functions) {
			foreach (var group in function.signature.struct_parameters) {
				foreach (var field in group.value_plan.ownership) {
					if (field.cleanup_class_ordinal < 0) {
						continue;
					}
					int ordinal = field.cleanup_class_ordinal;
					if (ordinal >= native.classes.length || ordinal >= program.classes.length || native.classes[ordinal].name != program.classes[ordinal].name) {
						throw new LlvmError.INVALID_INPUT ("record Class layout lost its exact source/native correspondence");
					}
					var policy = native.classes[ordinal].allocation_policy;
					if (policy != null && policy.kind == Astra.Source.AllocationKind.CONTEXT && policy.context_mode == "scoped-affine") {
						var owner = program.classes[ordinal];
						needed.insert (owner, owner);
					}
				}
			}
		}
		var exchange_fields = new HashTable<SsaStructField, bool> (direct_hash, direct_equal);
		foreach (var function in program.functions) {
			foreach (var parameter in function.parameters) {
				if (parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE && (!parameter.heap_object || parameter.pointer_contract != PointerParameterContract.OWNED_TRANSFER)) {
					continue;
				}
				foreach (var owner in program.classes) {
					if (owner.semantic_type == parameter.semantic_type && owner.allocation_policy != null && owner.allocation_policy.kind == Astra.Source.AllocationKind.CONTEXT && owner.allocation_policy.context_mode == "scoped-affine") {
						needed.insert (owner, owner);
					}
				}
			}
			if (function.async_body != null) {
				foreach (var owner in program.classes) {
					if (owner.semantic_type == function.async_body.runtime.error_type) {
						needed.insert (owner, owner);
					}
				}
			}
			foreach (var storage in function.object_storage) {
				needed.insert (storage.object_class, storage.object_class);
			}
			foreach (var storage in function.storage) {
				if (storage.structure != null) {
					needed.insert (storage.structure, storage.structure);
				}
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var async_operation = instruction as SsaAsyncOperation;
					if (async_operation != null) {
						foreach (var owner in program.classes) {
							if (owner.semantic_type == async_operation.contract.runtime.error_type) {
								needed.insert (owner, owner);
							}
						}
					}
					var capture = instruction as SsaBufferSlotCaptureInstruction;
					if (capture != null && capture.place.field != null) {
						var structure = capture.place.field.field.containing_type;
						needed.insert (structure, structure);
						exchange_fields.insert (capture.place.field.field, true);
					}
					var load = instruction as SsaLoadInstruction;
					var store = instruction as SsaStoreInstruction;
					var initialization = instruction as SsaInitializeInstruction;
					var buffer_read = instruction as SsaBufferReadInstruction;
					var buffer_write = instruction as SsaBufferWriteInstruction;
					var slots_effect = instruction as SsaSlotsEffect;
					var slots_value = instruction as SsaSlotsValueInstruction;
					var record_commit = instruction as SsaRecordFieldCommit;
					var record_drop = instruction as SsaRecordFieldDrop;
					// A borrowed-only Class may have no local allocation or ordinary
					// field load. Slots operations still demand its exact layout.
					SsaMemoryPlace? place = record_commit != null ? record_commit.destination : record_drop != null ? record_drop.source : slots_effect != null ? slots_effect.store : slots_value != null ? slots_value.store : buffer_read != null ? buffer_read.place.field : buffer_write != null ? buffer_write.place.field : load != null ? load.source : store != null ? store.target : initialization != null ? initialization.target : null;
					while (place is SsaFieldPlace) {
						var field = (SsaFieldPlace) place;
						var structure = field.field.containing_type;
						needed.insert (structure, structure);
						place = field.aggregate;
					}
				}
			}
		}
		var declarations = new HashTable<SemanticType, SsaNativeInstance> (direct_hash, direct_equal);
		foreach (var structure in program.native_instances ()) {
			declarations.insert (structure.semantic_type, structure);
		}
		foreach (var structure in program.structs) {
			if (structure.representation != null) {
				needed.insert (structure, structure);
			}
		}
		foreach (var imported in program.c_functions) {
			if (imported.return_type is StructType) {
				var declaration = declarations.lookup (imported.return_type);
				if (declaration == null) {
					throw new LlvmError.LOWERING ("C record result lost its exact storage declaration");
				}
				needed.insert (declaration, declaration);
			}
			foreach (var parameter in imported.parameters) {
				var type = parameter.semantic_type;
				if (type is StructType || type.is_struct_pointer ()) {
					bool value_record = type is StructType;
					var declaration = declarations.lookup (value_record ? type : ((TypedPointerType) type).pointee);
					if (declaration == null) {
						throw new LlvmError.LOWERING ("C record parameter lost its exact storage declaration");
					}
					needed.insert (declaration, declaration);
				}
			}
		}
		foreach (var exported in program.c_exports) {
			if (exported.target.return_type is StructType) {
				var declaration = declarations.lookup (exported.target.return_type);
				if (declaration == null) {
					throw new LlvmError.LOWERING ("C export record result lost its exact storage declaration");
				}
				needed.insert (declaration, declaration);
			}
			foreach (var group in exported.target.struct_parameters) {
				var declaration = declarations.lookup (group.shape.semantic_type);
				if (declaration == null) {
					throw new LlvmError.LOWERING ("C export record parameter lost its exact storage declaration");
				}
				needed.insert (declaration, declaration);
			}
		}
		foreach (var definition in program.enums) {
			for (uint v = 0; v < definition.variant_count; v++) {
				var variant = definition.variant (v);
				for (uint f = 0; f < variant.field_count; f++) {
					var type = variant.field (f).semantic_type;
					if (type is StructType) {
						needed.insert (declarations.lookup (type), declarations.lookup (type));
					}
				}
			}
		}
		foreach (var cleanup in program.cleanups) {
			if (cleanup.is_buffer && cleanup.buffer_type.element_type is StructType) {
				needed.insert (declarations.lookup (cleanup.buffer_type.element_type), declarations.lookup (cleanup.buffer_type.element_type));
			}
		}
		foreach (var function in program.functions) {
			foreach (var parameter in function.parameters) {
				var slice = parameter.semantic_type as SliceType;
				if (slice != null && slice.element_type is StructType) {
					needed.insert (declarations.lookup (slice.element_type), declarations.lookup (slice.element_type));
				}
			}
			foreach (var storage in function.storage) {
				var array = storage.semantic_type as ArrayType;
				if (array != null && array.element_type is StructType) {
					needed.insert (declarations.lookup (array.element_type), declarations.lookup (array.element_type));
				}
			}
		}
		bool changed = true;
		while (changed) {
			changed = false;
			foreach (var structure in program.native_instances ()) {
				if (!needed.contains (structure)) {
					continue;
				}
				if (structure is SsaClass && ((SsaClass) structure).parent_class != null && !needed.contains (((SsaClass) structure).parent_class)) {
					needed.insert (((SsaClass) structure).parent_class, ((SsaClass) structure).parent_class);
					changed = true;
				}
				foreach (var field in structure.fields) {
					if (!(field.semantic_type is StructType)) {
						continue;
					}
					var child = declarations.lookup (field.semantic_type);
					if (!needed.contains (child)) {
						needed.insert (child, child);
						changed = true;
					}
				}
			}
		}
		int ordinal = 0;
		foreach (var structure in program.native_instances ()) {
			if (!needed.contains (structure)) {
				continue;
			}
			var type = CApi.struct_create_named (artifact.context, (structure is SsaClass) ? "astra.class.%d".printf (structure.ordinal) : "astra.struct.%d".printf (ordinal++));
			types.insert (structure, (void*) type);
			mapper.bind_storage (structure.semantic_type, type);
		}
		foreach (var structure in program.native_instances ()) {
			if (!needed.contains (structure)) {
				continue;
			}
			var object_class = structure as SsaClass;
			int prefix = object_class == null ? 0 : object_class.parent_class != null ? 1 : object_class.concurrency_policy != null ? 6 : object_class.polymorphic ? 2 : 0;
			int caches = object_class == null ? 0 : (int) native.classes[object_class.ordinal].lazy_caches.length * 2;
			if (object_class != null && object_class.foreign_export != null) {
				caches += object_class.foreign_export.declared_api == null ? 1 : 2;
			}
			var fields = new CApi.TypeRef[prefix + structure.fields.length + caches == 0 ? 1 : prefix + structure.fields.length + caches];
			if (object_class != null && object_class.parent_class != null) {
				fields[0] = lookup (object_class.parent_class);
			} else {
				for (int h = 0; h < prefix; h++) {
					fields[h] = mapper.scalar (h == 2 || h == 3 || h == 5 ? NativeScalarType.U64 : NativeScalarType.PTR);
				}
			}
			if (prefix + structure.fields.length + caches == 0) {
				fields[0] = CApi.int_type_in_context (artifact.context, 8);
			}
			for (int f = 0; f < structure.fields.length; f++) {
				var type = structure.fields[f].semantic_type;
				fields[prefix + f] = (type is StructType) ? lookup (declarations.lookup (type)) : mapper.value_type (type);
			}
			if (object_class != null) {
				foreach (var cache in native.classes[object_class.ordinal].lazy_caches) {
					fields[cache.state_member] = mapper.scalar (NativeScalarType.U8);
					fields[cache.value_member] = mapper.abi_type (cache.value_type);
				}
			}
			if (object_class != null && object_class.foreign_export != null) {
				fields[fields.length - 1] = mapper.scalar (NativeScalarType.PTR);
				if (object_class.foreign_export.declared_api != null) {
					fields[fields.length - 2] = mapper.scalar (NativeScalarType.U64);
				}
			}
			CApi.struct_set_body (lookup (structure), fields, fields.length, 0);
		}
		foreach (var owner in program.classes) {
			if (!needed.contains (owner)) {
				continue;
			}
			var plan = native.classes[owner.ordinal];
			int prefix = plan.parent_ordinal >= 0 ? 1 : plan.concurrency_policy != null ? 6 : plan.polymorphic ? 2 : 0;
			int caches = (int) plan.lazy_caches.length * 2;
			if (plan.foreign_export != null) {
				caches += plan.foreign_export.declared_api == null ? 1 : 2;
			}
			var expected = new CApi.TypeRef[prefix + plan.fields.length + caches == 0 ? 1 : prefix + plan.fields.length + caches];
			if (plan.parent_ordinal >= 0) {
				expected[0] = lookup (program.classes[plan.parent_ordinal]);
			} else {
				for (int h = 0; h < prefix; h++) {
					expected[h] = mapper.scalar (h == 2 || h == 3 || h == 5 ? NativeScalarType.U64 : NativeScalarType.PTR);
				}
			}
			if (prefix + plan.fields.length + caches == 0) {
				expected[0] = CApi.int_type_in_context (artifact.context, 8);
			}
			for (int f = 0; f < plan.fields.length; f++) {
				var field = plan.fields[f];
				expected[prefix + f] = field.record_ordinal >= 0 ? lookup (program.structs[field.record_ordinal]) : (field.storage_type is NativeSliceType) ? mapper.buffer_carrier () : mapper.abi_type (field.storage_type);
			}
			foreach (var cache in plan.lazy_caches) {
				expected[cache.state_member] = mapper.scalar (NativeScalarType.U8);
				expected[cache.value_member] = mapper.abi_type (cache.value_type);
			}
			if (plan.foreign_export != null) {
				expected[expected.length - 1] = mapper.scalar (NativeScalarType.PTR);
				if (plan.foreign_export.declared_api != null) {
					expected[expected.length - 2] = mapper.scalar (NativeScalarType.U64);
				}
			}
			var binding = new LlvmClassLayoutBinding (lookup (owner), expected);
			binding.verify ();
			artifact.class_layouts.add (binding);
		}
		foreach (var structure in program.structs) {
			if (structure.representation == null) {
				continue;
			}
			if (artifact.class_target == null) {
				artifact.class_target = new LlvmTargetMachineArtifact (0, artifact.selected_target);
			}
			if (artifact.class_target.triple != LlvmTargetMachineArtifact.PC_BARE_METAL) {
				LlvmBufferAllocation.qualify (artifact.class_target.triple);
			}
			var binding = new LlvmPodLayoutBinding (structure.representation, lookup (structure), artifact.context);
			binding.verify (artifact.class_target.enum_target_data (artifact));
			artifact.pod_layouts.add (binding);
		}
		foreach (var field in exchange_fields.get_keys ()) {
			buffer_fields.insert (field, new LlvmBufferFieldBinding (field, lookup (field.containing_type)));
		}
	}

	internal uint field_index(SsaStructField field) {
		var owner = field.containing_type as SsaClass;
		return (uint) (field.ordinal + (owner == null ? 0 : owner.parent_class != null ? 1 : owner.concurrency_policy != null ? 6 : owner.polymorphic ? 2 : 0));
	}

	internal LlvmBufferFieldBinding buffer_field(SsaStructField field) throws LlvmError {
		var binding = buffer_fields.lookup (field);
		if (binding == null) {
			throw new LlvmError.LOWERING ("exchange field has no exact physical layout binding");
		}
		return binding;
	}

	internal CApi.TypeRef class_layout(int ordinal, string name) throws LlvmError {
		foreach (var structure in types.get_keys ()) {
			if (structure is SsaClass && structure.ordinal == ordinal && structure.name == name) {
				return lookup (structure);
			}
		}
		throw new LlvmError.LOWERING ("owned scoped input lost its exact physical Class layout");
	}
	internal CApi.TypeRef lookup(SsaNativeInstance structure) throws LlvmError {
		if (!types.contains (structure)) {
			throw new LlvmError.LOWERING ("internal LLVM lowering error: addressable struct has no exact physical type binding");
		}
		return (CApi.TypeRef) types.lookup (structure);
	}
}
}
