// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Ssa;
using Astra.Semantic;

namespace Astra.NativeAbi {
// Temporary SSA lookup used only while copying independent native paths.
private class NativeRecordSourceFields : Object {
	private SsaProgram source;
	public NativeRecordSourceFields (SsaProgram source) {
		this.source = source;
	}

	private SsaStruct? structure(SemanticType type) {
		foreach (var record in source.structs) {
			if (record.semantic_type == type) {
				return record;
			}
		}
		return null;
	}

	public GenericArray<SemanticType>? fields(SemanticType type) {
		var record = structure (type);
		if (record == null) {
			return null;
		}
		var result = new GenericArray<SemanticType> ();
		foreach (var field in record.fields) {
			result.add (field.semantic_type);
		}
		return result;
	}

	public BufferValueShape? buffer_shape(SliceType type) {
		foreach (var cleanup in source.cleanups) {
			if (cleanup.is_buffer && cleanup.buffer_type == type) {
				return cleanup.buffer_shape;
			}
		}
		return null;
	}

	public SsaStructField? leaf(SemanticType type, owned StructLeafPath path) {
		path = path.storage_path ();
		SsaStructField? field = null;
		for (int i = 0; i < path.depth; i++) {
			var record = structure (type);
			int ordinal = path.field_ordinal (i);
			if (record == null || ordinal < 0 || ordinal >= record.fields.length) {
				return null;
			}
			field = record.fields[ordinal];
			type = field.semantic_type;
		}
		return type == path.semantic_type ? field : null;
	}

}
public class NativeAbiBuilder : Object {
	internal static NativeStructValueMode record_mode(StructValueMode mode) {
		return NativeTypeMapper.record_mode (mode);
	}

	private static SemanticType materialized_record_type(SemanticType type, SsaProgram source) throws NativeAbiError {
		if (type.kind != TypeKind.GENERIC_STRUCT_APPLICATION) {
			return type;
		}
		SemanticType? result = null;
		foreach (var record in source.structs) {
			if (record.semantic_type.logical_identity != type.logical_identity) {
				continue;
			}
			if (result != null) {
				throw new NativeAbiError.INVALID_SSA ("ambiguous materialized nominal record application");
			}
			result = record.semantic_type;
		}
		if (result == null) {
			throw new NativeAbiError.INVALID_SSA ("declared generic argument lost its exact materialized record application");
		}
		return result;
	}

	internal static NativeDeclaredType declared_type(SemanticType type, SsaProgram source,
		GenericArray<NativeStructValuePlan> records, HashTable<SsaFunction, NativeFunction> callees, SsaStructField? field = null) throws NativeAbiError {
		type = materialized_record_type (type, source);
		if (type is FunctionValueType) {
			var signature = (FunctionValueType) type;
			var parameters = new GenericArray<SemanticType> ();
			foreach (var parameter in signature.parameter_types) {
				parameters.add (materialized_record_type (parameter, source));
			}
			signature = (FunctionValueType) CallableTypes.with_parameters (signature, parameters);
			var source_fields = new NativeRecordSourceFields (source);
			try {
				signature.complete_records (source_fields.fields);
			} catch (StructLeafError error) {
				throw new NativeAbiError.INVALID_SSA (error.message);
			}
			var arguments = signature.generic_arguments ();
			var declared = new NativeDeclaredType[arguments.length];
			for (int a = 0; a < arguments.length; a++) {
				declared[a] = declared_type (arguments.at (a), source, records, callees);
			}
			string nominal = ((signature is CallbackType) ? "Callback<" : "Fn<") + (signature.result_contract == ResultOwnershipContract.OWNED_TRANSFER ? "owned " : "") + declared[0].nominal_name;
			for (int a = 1; a < declared.length; a++) {
				nominal += "," + (signature.parameter_contract (a - 1) == PointerParameterContract.BORROWED_NOESCAPE ? "borrowed " : signature.parameter_contract (a - 1) == PointerParameterContract.OWNED_TRANSFER ? "owned " : "") + declared[a].nominal_name;
			}
			return new NativeDeclaredType (signature.display_name (), NativeTypeMapper.map_type (signature), -1, null, null, (signature is CallbackType) ? "Callback" : "Fn", declared, nominal + ">");
		}
		if (type is ClassType) {
			foreach (var owner in source.classes) {
				if (owner.semantic_type == type) {
					return new NativeDeclaredType (owner.name, new NativeScalarAbiType (NativeScalarType.PTR), owner.ordinal);
				}
			}
			throw new NativeAbiError.INVALID_SSA ("declared generic type lost its exact Class declaration");
		}
		if (type is StructType) {
			NativeStructValuePlan? plan = null;
			foreach (var record in records) {
				if (record.struct_name == type.display_name ()) {
					plan = record;
				}
			}
			if (plan == null) {
				plan = struct_value_plan (record_storage_shape ((StructType) type, source), source);
				records.add (plan);
			}
			var origin = type.generic_definition_name ();
			if (origin == null) {
				return new NativeDeclaredType (plan.struct_name, null, -1, plan);
			}
			var arguments = type.generic_arguments ();
			var declared = new NativeDeclaredType[arguments.length];
			for (int a = 0; a < arguments.length; a++) {
				declared[a] = declared_type (arguments.at (a), source, records, callees);
			}
			return new NativeDeclaredType (plan.struct_name, null, -1, plan, null, origin, declared, NativeRecordApplicationPlan.spelling (origin, declared));
		}
		if (type is ContextBytesType) {
			var bytes = (ContextBytesType) type;
			return new NativeDeclaredType (bytes.display_name (), NativeTypeMapper.map_type (bytes), -1, null, null, "ContextBytes", new NativeDeclaredType[] { declared_type (bytes.allocator_type, source, records, callees) }, bytes.display_name ());
		}
		if (type is SliceType) {
			var element = declared_type (((SliceType) type).element_type, source, records, callees);
			return new NativeDeclaredType (type.display_name (), new NativeSliceType (), -1, null, null,
				"@slice", new NativeDeclaredType[] { element }, element.nominal_name + "[]");
		}
		if (type is OwnerSlotsType) {
			if (field == null) {
				throw new NativeAbiError.INVALID_SSA ("owner slots require their declared field");
			}
			return new NativeDeclaredType (type.display_name (), slots_type (field, callees, source, records));
		}
		return new NativeDeclaredType (type.display_name (), type.kind == TypeKind.VOID ? null : NativeTypeMapper.map_type (type), -1, null, resource_owner (type, source));
	}

	private static NativeDeclaredMember declared_member(Astra.Source.GenericMemberPattern member, SsaFunction function,
		SsaProgram source, GenericArray<NativeStructValuePlan> records, HashTable<SsaFunction, NativeFunction> callees) throws NativeAbiError {
		NativeDeclaredType[] parameters = {};
		var heap_parameters = new bool[member.parameter_count];
		for (int p = 0; p < function.parameters.length;) {
			StructBoundaryGroup? group = null;
			foreach (var candidate in function.struct_parameters) {
				if (candidate.first_leaf == p) {
					group = candidate;
				}
			}
			if (group != null) {
				parameters += declared_type (group.shape.semantic_type, source, records, callees);
				p += group.shape.leaves.length;
			} else {
				heap_parameters[parameters.length] = function.parameters[p].heap_object;
				parameters += declared_type (function.parameters[p].semantic_type, source, records, callees);
				p++;
			}
		}
		var method = (function is SsaMethod) ? ((SsaMethod) function).generic_method_instance : null;
		NativeDeclaredType[] arguments = {};
		if (method != null) {
			foreach (var type in method.arguments.copy_values ()) {
				arguments += declared_type (type, source, records, callees);
			}
		}
		return new NativeDeclaredMember (member, callees.lookup (function).ordinal, declared_type (function.return_type, source, records, callees), parameters, heap_parameters, function.heap_result, arguments);
	}

	internal static NativeDeclaredClass declared_class(SsaClass owner, SsaProgram source,
		GenericArray<NativeStructValuePlan> records, HashTable<SsaFunction, NativeFunction> callees) throws NativeAbiError {
		var key = owner.generic_instance;
		var structure = key.definition.structure;
		NativeDeclaredType[] arguments = {};
		for (int a = 0; a < key.arguments.length; a++) {
			ClassTypeArgument? fact = null;
			foreach (var argument in source.class_type_arguments) {
				if (argument.owner_type == owner.semantic_type && argument.ordinal == a) {
					fact = argument;
				}
			}
			if (fact == null) {
				throw new NativeAbiError.INVALID_SSA ("declared Class lost its original concrete type argument fact");
			}
			arguments += declared_type (fact.semantic_type, source, records, callees);
		}
		NativeDeclaredType[] fields = {};
		foreach (var field in owner.fields) {
			fields += declared_type (field.semantic_type, source, records, callees, field);
		}
		NativeDeclaredMember[] members = {};
		for (int m = 0; m < structure.member_count; m++) {
			var member = structure.member (m);
			if (member.kind == Astra.Source.GenericMemberPatternKind.CONSTRUCTOR) {
				members += declared_member (member, owner.constructor, source, records, callees);
			} else if (member.kind == Astra.Source.GenericMemberPatternKind.DESTRUCTOR) {
				members += declared_member (member, owner.destructor, source, records, callees);
			} else {
				foreach (var method in owner.methods) {
					string name = method.generic_method_instance == null ? method.name : key.definition.generic_method_name (method.generic_method_instance.member);
					if (name == member.name) {
						members += declared_member (member, method, source, records, callees);
					}
				}
			}
		}
		for (int p = 0; p < structure.property_count; p++) {
			var declared = structure.property (p);
			var property = owner.properties[p];
			members += declared_member (declared.getter, property.getter, source, records, callees);
			if (declared.setter != null) {
				members += declared_member (declared.setter, property.setter, source, records, callees);
			}
		}
		return new NativeDeclaredClass (key.definition, arguments, fields, members);
	}

	private static NativeAbiVersion include_type(NativeAbiVersion version, SemanticType type) {
		if (type is FunctionValueType || type is ClosureHandleType) {
			var result = (type is FunctionValueType) ? ((FunctionValueType) type).result_type : ((ClosureHandleType) type).result_type;
			var parameters = (type is FunctionValueType) ? ((FunctionValueType) type).parameter_types : ((ClosureHandleType) type).parameter_types;
			if (version == NativeAbiVersion.SCALAR_V0) {
				version = NativeAbiVersion.SCALAR_PTR_V1;
			}
			version = include_type (version, result);
			foreach (var parameter in parameters) {
				version = include_type (version, parameter);
			}
			return version;
		}
		if (type.is_text_slice ()) {
			return version;
		}
		if (version == NativeAbiVersion.BUFFER_V8) {
			return version;
		}
		if (version == NativeAbiVersion.AGGREGATE_V7 || type.is_struct_storage ()) {
			return NativeAbiVersion.AGGREGATE_V7;
		}
		if (version == NativeAbiVersion.FP64_V6 || type is F64Type || (type is VectorType && ((VectorType) type).element_type is F64Type)) {
			return NativeAbiVersion.FP64_V6;
		}
		if (version == NativeAbiVersion.SLICE_V5 || type is SliceType) {
			return NativeAbiVersion.SLICE_V5;
		}
		if (version == NativeAbiVersion.VECTOR_V4 || type is VectorType) {
			return NativeAbiVersion.VECTOR_V4;
		}
		if (version == NativeAbiVersion.SCALAR_FP_V3 || type is F32Type) {
			return NativeAbiVersion.SCALAR_FP_V3;
		}
		if (version == NativeAbiVersion.SCALAR_INT_V2 || (type is IntegerType && type.kind != TypeKind.INT)) {
			return NativeAbiVersion.SCALAR_INT_V2;
		}
		return type.is_nullable_pointer_value () ? NativeAbiVersion.SCALAR_PTR_V1 : version;
	}

	internal static NativeRecordElement record_plan(SemanticType type, SsaProgram source, HashTable<SemanticType, NativeRecordElement> plans) throws NativeAbiError {
		var prior = plans.lookup (type);
		if (prior != null) {
			return prior;
		}
		SsaStruct? structure = null;
		int ordinal = -1;
		for (int i = 0; i < source.structs.length; i++) {
			if (source.structs[i].semantic_type == type) {
				structure = source.structs[i];
				ordinal = i;
				break;
			}
		}
		if (structure == null) {
			throw new NativeAbiError.INVALID_SSA ("record element requires exact completed SSA storage declaration");
		}
		var fields = new GenericArray<NativeRecordField> ();
		foreach (var field in structure.fields) {
			var child = (field.semantic_type is StructType) ? record_plan (field.semantic_type, source, plans) : null;
			fields.add (new NativeRecordField (field.ordinal, field.name, child == null ? NativeTypeMapper.map_type (field.semantic_type) : null, child));
		}
		var result = new NativeRecordElement (ordinal, structure.name, fields);
		plans.insert (type, result);
		return result;
	}

	internal static StructValueShape record_storage_shape(StructType type, SsaProgram source) throws NativeAbiError {
		var fields = new NativeRecordSourceFields (source);
		try {
			var leaves = StructLeafOrder.enumerate_storage (type, fields.fields);
			var mode = CopyabilityAuthority.of (type, fields.fields) == Copyability.COPYABLE ? StructValueMode.COPY_VALUE : StructValueMode.MOVE_VALUE;
			return new StructValueShape (type, leaves, mode).flatten_buffers (fields.buffer_shape);
		} catch (StructLeafError error) {
			throw new NativeAbiError.INVALID_SSA ("owning record storage shape: %s", error.message);
		}
	}

	internal static bool move_class_parameter(SsaFunction function, int ordinal) {
		foreach (var group in function.struct_parameters) {
			if (group.shape.mode == StructValueMode.MOVE_VALUE && ordinal >= group.first_leaf && ordinal < group.first_leaf + group.shape.leaves.length && group.shape.leaves[ordinal - group.first_leaf].semantic_type is ClassType) {
				return true;
			}
		}
		return false;
	}

	internal static NativeStructValuePlan struct_value_plan(StructValueShape shape, SsaProgram source, HashTable<SemanticType, NativeRecordElement>? element_records = null) throws NativeAbiError {
		for (int i = 0; i < source.structs.length; i++) {
			var structure = source.structs[i];
			if (structure.semantic_type != shape.semantic_type) {
				continue;
			}
			var leaves = new GenericArray<NativeStructLeafChannel> ();
			var ownership = new GenericArray<NativeRecordResource> ();
			var fields = new NativeRecordSourceFields (source);
			var records = element_records ?? new HashTable<SemanticType, NativeRecordElement> (direct_hash, direct_equal);
			foreach (var leaf in shape.leaves) {
				var field = fields.leaf (shape.semantic_type, leaf);
				if (field == null) {
					throw new NativeAbiError.INVALID_SSA ("record transport lost exact declaration field membership");
				}
				if (leaf.semantic_type is ClassType && (shape.mode != StructValueMode.MOVE_VALUE || field.owned_cleanup == null || !field.owned_cleanup.is_heap_object)) {
					throw new NativeAbiError.INVALID_SSA ("record Class transport requires exact heap ownership");
				}
				var abi_type = (leaf.semantic_type is ClassType) ? new NativeScalarAbiType (NativeScalarType.PTR) : NativeTypeMapper.map_type (leaf.semantic_type);
				var buffer = leaf as StructBufferLeafPath;
				leaves.add (new NativeStructLeafChannel (leaf.spelling (), abi_type, leaf.storage_path ().spelling (), buffer == null ? -1 : buffer.component));
				if (field.owned_cleanup == null) {
					continue;
				}
				if (shape.mode != StructValueMode.MOVE_VALUE || (field.owned_cleanup.is_buffer && buffer == null)) {
					throw new NativeAbiError.INVALID_SSA ("record transport requires distinct move responsibility and complete supported channels");
				}
				if (buffer != null && buffer.component != 0) {
					continue;
				}
				if (field.owned_cleanup.is_buffer && field.owned_cleanup.buffer_type.element_type is StructType) {
					record_plan (field.owned_cleanup.buffer_type.element_type, source, records);
				}
				ownership.add (record_resource (leaf.storage_path (), field.semantic_type, field.owned_cleanup, (int) ownership.length, records));
			}
			return new NativeStructValuePlan (i, structure.name, leaves, leaves.length == 1 ? NativeStructResultCarrier.SINGLE_LEAF : NativeStructResultCarrier.LEAF_AGGREGATE, shape.mode == StructValueMode.MOVE_VALUE ? NativeStructValueMode.MOVE_VALUE : NativeStructValueMode.COPY_VALUE, ownership);
		}
		throw new NativeAbiError.INVALID_SSA ("record value requires its exact completed declaration and leaf shape");
	}

	private static NativeBufferValuePlan buffer_plan(SliceType type, HashTable<SemanticType, NativeRecordElement> records) throws NativeAbiError {
		var element = type.element_type;
		if (element is StructType) {
			return new NativeBufferValuePlan.for_record (records.lookup (element));
		}
		var origin = NativeTypeMapper.context_buffer_type (type);
		return new NativeBufferValuePlan (NativeTypeMapper.map_type (element), origin);
	}

	internal static NativeCopyType copy_type(SemanticType type, SsaProgram source, GenericArray<NativeStructValuePlan> values) throws NativeAbiError {
		if (type is StructType) {
			foreach (var plan in values) {
				if (plan.struct_name == type.display_name ()) {
					return new NativeCopyType (type.display_name (), null, plan);
				}
			}
			throw new NativeAbiError.INVALID_SSA ("generic method argument lost its canonical complete record layout");
		}
		return new NativeCopyType (type.display_name (), NativeTypeMapper.map_type (type));
	}

	internal static NativeScalarOwner? resource_owner(SemanticType type, SsaProgram source) {
		if (type.get_type () != typeof (HandleType)) {
			return null;
		}
		foreach (var handle in source.handles) {
			if (handle.semantic_type == type) {
				return new NativeScalarOwner (type.display_name (), handle.cleanup.external_symbol);
			}
		}
		return null;
	}

	internal static NativeOwnerSlotsType slots_type(SsaStructField field, HashTable<SsaFunction, NativeFunction> callees, SsaProgram source, GenericArray<NativeStructValuePlan>? values = null) throws NativeAbiError {
		var type = field.semantic_type as OwnerSlotsType;
		var cleanup = field.slots_cleanup;
		if (type == null) {
			throw new NativeAbiError.INVALID_SSA ("slots require exact element authority");
		}
		if (type.element is StructType) {
			if (values != null) {
				foreach (var plan in values) {
					if (plan.struct_name == type.element.display_name ()) {
						if (cleanup != null) {
							break;
						}
						return new NativeOwnerSlotsType (-1, plan.struct_name, -1, NativeScalarType.PTR, NativeScalarType.I32, NativeScalarType.I32, null, plan);
					}
				}
			}
			throw new NativeAbiError.INVALID_SSA ("record slots require their complete canonical value and ownership plan");
		}
		if (cleanup == null) {
			throw new NativeAbiError.INVALID_SSA ("scalar slots lost exact cleanup authority");
		}
		var resource = resource_owner (type.element, source);
		if (resource != null) {
			return new NativeOwnerSlotsType (-1, resource.type_name, -1, NativeScalarType.PTR, NativeScalarType.I32, NativeScalarType.I32, resource);
		}
		if (!cleanup.is_heap_object || cleanup.object_class.semantic_type != type.element) {
			throw new NativeAbiError.INVALID_SSA ("slots lost exact Class or Resource cleanup");
		}
		return new NativeOwnerSlotsType (cleanup.object_class.ordinal, cleanup.object_class.name, cleanup.destructor == null ? -1 : callees.lookup (cleanup.destructor).ordinal);
	}

	private static NativeRecordResource record_resource(StructLeafPath path, SemanticType type, SsaCleanupContract cleanup, int rank, HashTable<SemanticType, NativeRecordElement> records) throws NativeAbiError {
		var buffer = cleanup.is_buffer ? buffer_plan (cleanup.buffer_type, records) : null;
		int[] ordinals = new int[path.depth];
		for (int i = 0; i < path.depth; i++) {
			ordinals[i] = path.field_ordinal (i);
		}
		return new NativeRecordResource.projected (ordinals, type.display_name (), cleanup.external_symbol, rank,
			cleanup.is_heap_object ? cleanup.object_class.ordinal : -1, buffer);
	}

	private static NativeRecordDeclarationPlan? record_declaration(SsaStruct record, int ordinal, NativeRecordSourceFields fields, HashTable<SemanticType, NativeRecordElement> records) throws NativeAbiError {
		if (CopyabilityAuthority.of (record.semantic_type, fields.fields) == Copyability.COPYABLE) {
			return null;
		}
		var members = new GenericArray<NativeRecordResource> ();
		try {
			foreach (var path in StructLeafOrder.enumerate_storage (record.semantic_type, fields.fields)) {
				var field = fields.leaf (record.semantic_type, path);
				if (field == null) {
					throw new NativeAbiError.INVALID_SSA ("record declaration lost exact field membership");
				}
				if (field.owned_cleanup != null) {
					members.add (record_resource (path, field.semantic_type, field.owned_cleanup, -1, records));
				}
			}
		} catch (StructLeafError error) {
			throw new NativeAbiError.INVALID_SSA ("record declaration paths: %s", error.message);
		}
		return members.length == 0 ? null : new NativeRecordDeclarationPlan (ordinal, record.name, members);
	}

	private static NativeRecordOwnerPlan record_owner_plan(NativeFunction function, int source_ordinal, SsaStruct record, HashTable<SemanticType, NativeRecordDeclarationPlan> declarations) throws NativeAbiError {
		foreach (var candidate in function.record_owners) {
			if (candidate.source_ordinal == source_ordinal) {
				return candidate;
			}
		}
		var plan = new NativeRecordOwnerPlan (source_ordinal, record.name);
		plan.declaration = declarations.lookup (record.semantic_type);
		if (plan.declaration == null) {
			throw new NativeAbiError.INVALID_SSA ("record owner lost its exact native declaration");
		}
		foreach (var field in plan.declaration.fields) {
			plan.fields.add (field);
		}
		function.record_owners.add (plan);
		return plan;
	}

	private static NativeSumPlan sum_plan(EnumDefinition definition, SsaProgram source, HashTable<EnumType, NativeSumPlan> plans, HashTable<SemanticType, NativeRecordElement> records, HashTable<StructType, NativeStructValuePlan> record_values) throws NativeAbiError {
		var prior = plans.lookup (definition.semantic_type);
		if (prior != null) {
			return prior;
		}
		var variants = new GenericArray<NativeSumVariant> ();
		for (uint v = 0; v < definition.variant_count; v++) {
			var variant = definition.variant (v);
			var fields = new GenericArray<NativeSumField> ();
			for (uint f = 0; f < variant.field_count; f++) {
				var field = variant.field (f);
				NativeSumPlan? child = null;
				if (field.semantic_type is EnumType) {
					foreach (var candidate in source.enums) {
						if (candidate.semantic_type == field.semantic_type) {
							child = sum_plan (candidate, source, plans, records, record_values);
						}
					}
					if (child == null) {
						throw new NativeAbiError.INVALID_SSA ("nested enum requires its exact completed definition");
					}
				}
				var record = (field.semantic_type is StructType && !field.owns_record) ? record_plan (field.semantic_type, source, records) : null;
				if (field.owns_buffer && ((SliceType) field.semantic_type).element_type is StructType) {
					record_plan (((SliceType) field.semantic_type).element_type, source, records);
				}
				var buffer = field.owns_buffer ? buffer_plan ((SliceType) field.semantic_type, records) : null;
				var record_value = field.owns_record ? record_values.lookup ((StructType) field.semantic_type) : null;
				if (field.owns_record && record_value == null) {
					throw new NativeAbiError.INVALID_SSA ("owning enum record lost its completed physical value plan");
				}
				NativeScalarOwner? scalar_owner = null;
				if (field.owns_scalar) {
					int class_ordinal = -1;
					if (field.owns_child) {
						foreach (var owner in source.classes) {
							if (owner.semantic_type == field.semantic_type) {
								class_ordinal = owner.ordinal;
							}
						}
						if (class_ordinal < 0) {
							throw new NativeAbiError.INVALID_SSA ("owned enum Class requires exact completed heap declaration");
						}
					}
					scalar_owner = new NativeScalarOwner (field.semantic_type.display_name (), field.owned_cleanup == null ? "" : field.owned_cleanup.external_symbol, class_ordinal);
				}
				fields.add (new NativeSumField (field.identity, scalar_owner != null ? new NativeScalarAbiType (NativeScalarType.PTR) : child == null && record == null && buffer == null && record_value == null ? NativeTypeMapper.map_type (field.semantic_type) : null, record, child, buffer, scalar_owner, record_value));
			}
			variants.add (new NativeSumVariant (variant.identity, fields));
		}
		var result = new NativeSumPlan (definition.semantic_type.identity, variants);
		plans.insert (definition.semantic_type, result);
		return result;
	}

	private static GenericArray<NativeCallableBorrowChannel> callable_borrows(SsaCallableInvocation call) {
		var borrowed = new GenericArray<NativeCallableBorrowChannel> ();
		foreach (var loan in call.borrowed_arguments) {
			borrowed.add (new NativeCallableBorrowChannel (loan.ordinal, loan.value.semantic_type.display_name (), loan.value.semantic_type is ClassType));
		}
		return borrowed;
	}

	private static NativeScalarOwner? callable_result_owner(SsaCallableInvocation call) throws NativeAbiError {
		var cleanup = call.result_cleanup ();
		if (cleanup == null) {
			return null;
		}
		var value = call.owned_result_value ();
		if (value != null && value.semantic_type is ClassType) {
			if (!cleanup.is_heap_object || cleanup.object_class == null || cleanup.object_class.semantic_type != value.semantic_type) {
				throw new NativeAbiError.INVALID_ABI ("callable Class result requires its exact independent heap cleanup");
			}
			return new NativeScalarOwner (value.semantic_type.display_name (), cleanup.external_symbol, cleanup.object_class.ordinal);
		}
		if (value == null || value.semantic_type.get_type () != typeof (HandleType) || cleanup.external_symbol == "") {
			throw new NativeAbiError.INVALID_ABI ("callable result lost its exact Resource cleanup and guarded value");
		}
		return new NativeScalarOwner (value.semantic_type.display_name (), cleanup.external_symbol);
	}

	private static GenericArray<NativeCallableOwnedArgument> callable_transfers(SsaCallableInvocation call) throws NativeAbiError {
		var result = new GenericArray<NativeCallableOwnedArgument> ();
		foreach (var transfer in call.owned_arguments) {
			int class_ordinal = -1;
			if (transfer.value.semantic_type is ClassType) {
				if (!transfer.cleanup.is_heap_object || transfer.cleanup.object_class.semantic_type != transfer.value.semantic_type) {
					throw new NativeAbiError.INVALID_SSA ("indirect Class transfer requires its exact heap cleanup plan");
				}
				class_ordinal = transfer.cleanup.object_class.ordinal;
			} else if (transfer.value.semantic_type.get_type () != typeof (HandleType) || transfer.cleanup.is_object || transfer.cleanup.is_buffer || transfer.cleanup.external_symbol == "") {
				throw new NativeAbiError.INVALID_SSA ("indirect Resource transfer requires its exact scalar destructor plan");
			}
			result.add (new NativeCallableOwnedArgument (transfer.ordinal, new NativeScalarOwner (transfer.value.semantic_type.display_name (), transfer.cleanup.external_symbol, class_ordinal), transfer.source_ordinal,
				transfer.value is SsaNullPointerConstant, transfer.source_after_commit != null));
		}
		return result;
	}

	private static void callable_record_types(SemanticType type, HashTable<SemanticType, bool> records) {
		var signature = type as CallableSignature;
		if (signature == null) {
			return;
		}
		SemanticType result;
		if (type is FunctionValueType) {
			result = ((FunctionValueType) type).result_type;
		} else {
			result = ((ClosureHandleType) type).result_type;
		}
		if (result is StructType) {
			records.insert (result, true);
		} else {
			callable_record_types (result, records);
		}
		foreach (var parameter in signature.parameter_types) {
			if (parameter is StructType) {
				records.insert (parameter, true);
			} else {
				callable_record_types (parameter, records);
			}
		}
	}

	internal static HashTable<SsaFunction, string> lifetime_descriptors(SsaProgram source) throws NativeAbiError {
		var result = new HashTable<SsaFunction, string> (direct_hash, direct_equal);
		try {
			var summaries = SsaRuntimeLifetimes.analyze (source);
			foreach (var function in source.functions) {
				var summary = summaries.lookup (function);
				result.insert (function, summary == null ? "runtime-lifetime-summary/1:incomplete" : summary.encode ());
			}
		} catch (GLib.Error failure) {
			throw new NativeAbiError.INVALID_SSA ("runtime lifetime correspondence: %s", failure.message);
		}
		return result;
	}

	public static NativeAbiProgram build(SsaProgram source) throws NativeAbiError {
		var record_fields = new NativeRecordSourceFields (source);
		var private_accesses = new GenericArray<SsaPrivateFieldAccess> ();
		try {
			SsaVerifier.verify (source, private_accesses);
		} catch (SsaError error) {
			throw new NativeAbiError.INVALID_SSA ("internal native ABI planning error: %s", error.message);
		}
		var records = new HashTable<SemanticType, NativeRecordElement> (direct_hash, direct_equal);
		foreach (var cleanup in source.cleanups) {
			if (cleanup.is_buffer && cleanup.buffer_type.element_type is StructType) {
				record_plan (cleanup.buffer_type.element_type, source, records);
			}
		}
		foreach (var function in source.functions) {
			foreach (var parameter in function.parameters) {
				var slice = parameter.semantic_type as SliceType;
				if (slice != null && slice.element_type is StructType) {
					record_plan (slice.element_type, source, records);
				}
			}
			foreach (var storage in function.storage) {
				var array = storage.semantic_type as ArrayType;
				if (array != null && array.element_type is StructType) {
					record_plan (array.element_type, source, records);
				}
			}
		}
		var sums = new HashTable<EnumType, NativeSumPlan> (direct_hash, direct_equal);
		var record_declarations = new HashTable<SemanticType, NativeRecordDeclarationPlan> (direct_hash, direct_equal);
		for (int i = 0; i < source.structs.length; i++) {
			var declaration = record_declaration (source.structs[i], i, record_fields, records);
			if (declaration != null) {
				record_declarations.insert (source.structs[i].semantic_type, declaration);
			}
		}
		var version = NativeAbiVersion.SCALAR_V0;
		// Imported declarations retain cleanup contracts without local buffer
		// acquisitions. Their record/Class storage still requires this ABI.
		foreach (var cleanup in source.cleanups) {
			if (cleanup.is_buffer) {
				version = NativeAbiVersion.BUFFER_V8;
			}
		}
		foreach (var structure in source.structs) {
			if (structure.semantic_type.generic_definition_name () != null) {
				version = include_type (version, structure.semantic_type);
			}
		}
		foreach (var function in source.functions) {
			foreach (var slot in function.buffer_storage) {
				if (slot.record_type != null) {
					version = NativeAbiVersion.BUFFER_V8;
				}
			}
		}
		foreach (var function in source.functions) {
			if (function.buffer_parameters.length != 0 || (function.owned_cleanup != null && function.owned_cleanup.is_buffer)) {
				version = NativeAbiVersion.BUFFER_V8;
			}
			if (version != NativeAbiVersion.BUFFER_V8 && function.struct_parameters.length != 0) {
				version = NativeAbiVersion.AGGREGATE_V7;
			}
			if (function.implicit_receiver != null && version == NativeAbiVersion.SCALAR_V0) {
				version = NativeAbiVersion.SCALAR_PTR_V1;
			}
			version = include_type (version, function.return_type);
			foreach (var parameter in function.parameters) {
				version = include_type (version, parameter.semantic_type);
			}
		}
		bool has_text_slice = false;
		bool has_receiver_text = false;
		foreach (var owner in source.classes) {
			if (owner.polymorphic) {
				has_receiver_text = true;
			}
		}
		foreach (var function in source.functions) {
			if (function.result_contract == ResultOwnershipContract.RECEIVER_TEXT) {
				has_receiver_text = true;
			}
		}
		bool has_text = false;
		foreach (var function in source.functions) {
			if (function.return_type is StringType) {
				has_text = true;
			}
			foreach (var parameter in function.parameters) {
				if (parameter.semantic_type is StringType) {
					has_text = true;
				}
				if (parameter.semantic_type.is_text_slice ()) {
					has_text_slice = true;
				}
			}
		}
		var callable_records = new HashTable<SemanticType, bool> (direct_hash, direct_equal);
		foreach (var function in source.functions) {
			callable_record_types (function.return_type, callable_records);
			foreach (var parameter in function.parameters) {
				callable_record_types (parameter.semantic_type, callable_records);
			}
		}
		foreach (var owner in source.native_instances ()) {
			foreach (var field in owner.fields) {
				callable_record_types (field.semantic_type, callable_records);
			}
		}
		var plans = new GenericArray<NativeStructValuePlan> ();
		var struct_plans = new HashTable<StructType, NativeStructValuePlan> (direct_hash, direct_equal);
		for (int i = 0; i < source.structs.length; i++) {
			var structure = source.structs[i];
			StructValueShape? shape = null;
			if (callable_records.contains (structure.semantic_type)) {
				shape = record_storage_shape ((StructType) structure.semantic_type, source);
			}
			foreach (var function in source.functions) {
				if (function.struct_result != null && function.struct_result.semantic_type == structure.semantic_type) {
					shape = function.struct_result;
				}
				foreach (var group in function.struct_parameters) {
					if (group.shape.semantic_type == structure.semantic_type) {
						shape = group.shape;
					}
				}
			}
			foreach (var definition in source.enums) {
				for (uint v = 0; v < definition.variant_count; v++) {
					for (uint f = 0; f < definition.variant (v).field_count; f++) {
						var field = definition.variant (v).field (f);
						if (field.owns_record && field.semantic_type == structure.semantic_type && shape == null) {
							shape = record_storage_shape ((StructType) field.semantic_type, source);
						}
					}
				}
			}
			foreach (var owner in source.classes) {
				foreach (var field in owner.fields) {
					var slots = field.semantic_type as OwnerSlotsType;
					if (slots != null && slots.element == structure.semantic_type && shape == null) {
						shape = record_storage_shape ((StructType) slots.element, source);
					}
				}
			}
			foreach (var owner in source.classes) {
				foreach (var field in owner.fields) {
					if (field.record_owner == structure && shape == null) {
						shape = record_storage_shape ((StructType) field.semantic_type, source);
					}
				}
			}
			foreach (var owner in source.classes) {
				foreach (var method in owner.methods) {
					var key = method.generic_method_instance;
					if (key == null) {
						continue;
					}
					foreach (var argument in key.arguments.copy_values ()) {
						if (argument == structure.semantic_type && shape == null) {
							shape = record_storage_shape ((StructType) argument, source);
						}
					}
				}
			}
			// Nominal generic applications are ABI metadata demands as well as
			// value-channel demands. Build their canonical storage/declaration
			// together, including an owning nested record used only inline.
			if (shape == null && structure.semantic_type.generic_definition_name () != null) {
				shape = record_storage_shape ((StructType) structure.semantic_type, source);
			}
			if (shape == null) {
				continue;
			}
			// A record has one nominal storage/cleanup graph. Each signature binds
			// its separate copy, move or bounded observation operation below.
			shape = record_storage_shape ((StructType) structure.semantic_type, source);
			var plan = struct_value_plan (shape, source, records);
			plan.bind_foreign_record (SsaForeignApi.record (source, structure.semantic_type));
			plan.declaration = record_declarations.lookup (shape.semantic_type);
			plans.add (plan);
			struct_plans.insert (shape.semantic_type, plan);
		}
		foreach (var definition in source.enums) {
			sum_plan (definition, source, sums, records, struct_plans);
		}
		foreach (var owner in source.classes) {
			// Independent storage fields need the same physical type profile as
			// signature channels, even when no accessor exposes their type.
			foreach (var field in owner.fields) {
				version = include_type (version, field.semantic_type);
			}
			if (owner.generic_instance != null) {
				foreach (var argument in owner.generic_instance.arguments.copy_values ()) {
					version = include_type (version, argument);
				}
			}
		}
		var functions = new GenericArray<NativeFunction> ();
		var readonly_effects = new SsaReadonlyInference (source);
		var lifetime_contracts = lifetime_descriptors (source);
		var callback_effects = new SsaCallbackPreconditions (source, readonly_effects);
		// Exact identity map, discarded before the completed sidecar escapes.
		var callees = new HashTable<SsaFunction, NativeFunction> (direct_hash, direct_equal);
		for (int f = 0; f < source.functions.length; f++) {
			var function = source.functions[f];
			var parameters = new GenericArray<NativeParameter> ();
			for (int p = 0; p < function.parameters.length; p++) {
				var parameter = function.parameters[p];
				var mapped = (parameter.semantic_type is EnumType) && sums.lookup ((EnumType) parameter.semantic_type).owning ? new NativeSumType (((EnumType) parameter.semantic_type).identity, NativeSumRole.OWNED_TRANSFER) : NativeTypeMapper.map_parameter (parameter.semantic_type, parameter.pointer_contract, (parameter.semantic_type is SliceType) ? records.lookup (((SliceType) parameter.semantic_type).element_type) : null, move_class_parameter (function, p));
				int borrowed_class = -1;
				if (parameter.semantic_type is ClassType && parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE) {
					foreach (var owner in source.classes) {
						if (owner.semantic_type == parameter.semantic_type) {
							borrowed_class = owner.ordinal;
						}
					}
				}
				var scalar_pointee = parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && ForeignApiTypes.scalar_pointee (parameter.semantic_type) != null ? new NativeScalarAbiType (NativeTypeMapper.map_scalar (((TypedPointerType) parameter.semantic_type).pointee)) : null;
				parameters.add (new NativeParameter.typed (parameter.span, parameter.name_span, parameter.name, p, mapped, borrowed_class, parameter.requires_nonnull, scalar_pointee));
				var resource = resource_owner (parameter.semantic_type, source);
				if (resource != null) {
					parameters[p].bind_resource (resource, parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER);
				}
				if (parameter.semantic_type is ExactGenericClassType && parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE) {
					foreach (var owner in source.classes) {
						if (owner.semantic_type == parameter.semantic_type) {
							parameters[p].bind_generic_borrow (owner.ordinal, owner.generic_instance.definition);
						}
					}
				}
				if (parameter.semantic_type is ClassType && parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER) {
					foreach (var owner in source.classes) {
						if (owner.semantic_type == parameter.semantic_type) {
							parameters[p].object_origin = new NativeObjectOriginPlan (owner.ordinal, owner.name, parameter.heap_object);
						}
					}
				}
				if (GenericClassTypes.general (parameter.semantic_type) && parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER) {
					foreach (var owner in source.classes) {
						if (owner.semantic_type == parameter.semantic_type) {
							parameters[p].bind_generic_owner (owner.ordinal, owner.generic_instance.definition);
						}
					}
				}
			}
			var method = function as SsaMethod;
			bool record_signature = function.owned_cleanup != null && function.owned_cleanup.is_buffer && function.owned_cleanup.buffer_type.element_type is StructType;
			foreach (var group in function.buffer_parameters) {
				if (group.cleanup.buffer_type.element_type is StructType) {
					record_signature = true;
				}
			}
			foreach (var parameter in function.parameters) {
				if (parameter.semantic_type is SliceType && ((SliceType) parameter.semantic_type).element_type is StructType) {
					record_signature = true;
				}
			}
			bool text_slice_signature = false;
			bool text_signature = function.return_type is StringType;
			foreach (var parameter in function.parameters) {
				if (parameter.semantic_type is StringType) {
					text_signature = true;
				}
				if (parameter.semantic_type.is_text_slice ()) {
					text_slice_signature = true;
				}
			}
			bool sum_signature = function.return_type is EnumType;
			foreach (var parameter in function.parameters) {
				if (parameter.semantic_type is EnumType) {
					sum_signature = true;
				}
			}
			bool owning_signature = (function.return_type is EnumType) && sums.lookup ((EnumType) function.return_type).owning;
			foreach (var parameter in function.parameters) {
				if (parameter.semantic_type is EnumType && sums.lookup ((EnumType) parameter.semantic_type).owning) {
					owning_signature = true;
				}
			}
			var signature = new NativeSignature (function.throws_type != null || function.result_contract == ResultOwnershipContract.RECEIVER_TEXT || function.dispatch_kind != ClassDispatchKind.DIRECT ? NativeAbiVersion.NATIVE_EXCEPTIONS_V14 : owning_signature ? NativeAbiVersion.OWNED_SUMS_V13 : sum_signature ? NativeAbiVersion.SUM_VALUES_V12 : record_signature ? NativeAbiVersion.STRUCT_ELEMENTS_V11 : text_slice_signature ? NativeAbiVersion.TEXT_SLICE_V10 : text_signature ? NativeAbiVersion.TEXT_V9 : version, parameters, function.struct_result == null && !(function.owned_cleanup != null && function.owned_cleanup.is_buffer) ? NativeTypeMapper.map_result (function.return_type, function.result_contract) : null, function.implicit_receiver == null ? null : new NativeScalarAbiType (NativeScalarType.PTR), function.result_storage == null ? null : new NativeOwnedObjectResultPlan.typed (new NativeObjectOriginPlan (function.result_storage.object_class.ordinal, function.result_storage.object_class.name, false)), function.nonnull_result);
			if (function.throws_type != null) {
				SsaClass? bound = null;
				SsaClass? root = null;
				foreach (var owner in source.classes) {
					if (owner.semantic_type == function.throws_type) {
						bound = owner;
					}
					if (owner.exception_root) {
						root = owner;
					}
				}
				if (bound == null || root == null || !function.throws_type.derives_from ((ClassType) root.semantic_type)) {
					throw new NativeAbiError.INVALID_SSA ("throws requires an exact nominated native exception hierarchy");
				}
				signature.exception_plan = new NativeExceptionPlan (bound.ordinal, bound.name, root.ordinal, root.name);
			}
			if (function.return_type is EnumType) {
				signature.sum_result = new NativeSumType (((EnumType) function.return_type).identity, sums.lookup ((EnumType) function.return_type).owning ? NativeSumRole.OWNED_RESULT_STORAGE : NativeSumRole.RESULT_CALLER_STORAGE);
			}
			var resource_result = resource_owner (function.return_type, source);
			if (resource_result != null && function.result_contract == ResultOwnershipContract.OWNED_TRANSFER) {
				signature.bind_resource_result (resource_result);
			}
			if (function.heap_result) {
				foreach (var owner in source.classes) {
					if (owner.semantic_type == function.return_type) {
						signature.heap_result = new NativeObjectOriginPlan (owner.ordinal, owner.name, true);
					}
				}
			}
			if (GenericClassTypes.general (function.return_type) && function.result_contract == ResultOwnershipContract.OWNED_TRANSFER) {
				foreach (var owner in source.classes) {
					if (owner.semantic_type == function.return_type) {
						signature.bind_generic_owner_result (owner.ordinal, owner.generic_instance.definition, function.heap_result);
					}
				}
			}
			if (function.owned_cleanup != null && function.owned_cleanup.is_buffer) {
				signature.buffer_result = buffer_plan (function.owned_cleanup.buffer_type, records);
			}
			foreach (var group in function.buffer_parameters) {
				signature.buffer_parameters.add (new NativeBufferParameterPlan (group.source_ordinal, group.first_leaf, buffer_plan (group.cleanup.buffer_type, records)));
			}
			if (function.struct_result != null) {
				signature.struct_result = struct_plans.lookup (function.struct_result.semantic_type);
				signature.struct_result_mode = NativeAbiBuilder.record_mode (function.struct_result.mode);
			}
			foreach (var group in function.struct_parameters) {
				signature.struct_parameters.add (new NativeStructParameterPlan (group.source_ordinal, group.first_leaf, struct_plans.lookup (group.shape.semantic_type), NativeAbiBuilder.record_mode (group.shape.mode)));
			}
			signature.bind_struct_transport (function.struct_parameters.length, function.struct_result == null ? null : struct_plans.lookup (function.struct_result.semantic_type));
			signature.bind_buffer_transport ();
			var accessor = function as SsaPropertyAccessor;
			var property = accessor == null ? null : accessor.property_member;
			var lifecycle = function as SsaLifecycle;
			var kind = (function is SsaPropertyGetter) ? NativeCallableKind.PROPERTY_GETTER : (function is SsaPropertySetter) ? NativeCallableKind.PROPERTY_SETTER : (function is SsaConstructor) ? NativeCallableKind.CONSTRUCTOR : (function is SsaDestructor) ? NativeCallableKind.DESTRUCTOR : method == null ? NativeCallableKind.FUNCTION : NativeCallableKind.METHOD;
			var native_function = new NativeFunction (function.span, function.name_span, function.name, f, signature, NativeLinkage.NATIVE_INTERNAL, property != null ? property.declaring_type.ordinal : lifecycle != null ? lifecycle.declaring_class.ordinal : method == null ? -1 : method.declaring_type.ordinal, method == null ? -1 : method.method_ordinal, property != null ? (property.declaring_type is SsaClass) : lifecycle != null || (method != null && method.declaring_type is SsaClass), kind, property == null ? -1 : property.ordinal);
			if (function.entry.terminator is SsaForeignSignalReturn) {
				native_function.foreign_signal = new NativeForeignSignalPlan (((SsaForeignSignalReturn) function.entry.terminator).binding);
			}
			if (function.entry.terminator is SsaForeignReturn) {
				var imported = (SsaForeignReturn) function.entry.terminator;
				native_function.foreign_import = new NativeForeignImportPlan (imported.binding, imported.factory.ordinal);
				if (imported.binding.root.com != null && imported.binding.member.kind == Astra.Source.ForeignMemberKind.CONSTRUCTOR) {
					if (function.parameters.length != 1 || !function.parameters[0].semantic_type.is_void_pointer () || function.parameters[0].pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
						throw new NativeAbiError.INVALID_ABI ("COM acquisition lost exact IUnknown borrow provenance");
					}
					native_function.signature.parameters[0].bind_com_unknown (imported.binding.root.com);
				}
			}
			if (function.async_body != null) {
				native_function.bind_async_callable (new NativeAsyncCallablePlan (
					function.async_body.runtime.provider, function.async_body.runtime.error_type.nominal_name (),
					function.return_type.nominal_name (), (int) function.result_contract, signature, function.native_declaration != null, function.async_body.runtime.composable));
			}
			native_function.bind_runtime_lifetimes (lifetime_contracts.lookup (function));
			var readonly_summary = readonly_effects.summary (function);
			var callback_summary = callback_effects.summary (function);
			var code_inputs = SsaReadonlyInference.code_inputs (function);
			native_function.bind_scoped_readonly (readonly_summary.eligible,
				readonly_summary.eligible ? Astra.Code.CodeInputSet.encode (readonly_summary, code_inputs) : "",
				callback_summary.eligible ? Astra.Code.CodeInputSet.encode (callback_summary, code_inputs) : "",
				(int) code_inputs.length, callback_summary.eligible);
			native_function.utf8_factory = function.utf8_factory;
			native_function.bind_floating_policy (function.floating_policy);
			native_function.bind_effects (function.effect_facts, function.checked_native_optimizer);
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var scoped = block.instructions[i] as SsaScopedAllocator;
					if (scoped == null) {
						continue;
					}
					var ends = new GenericArray<int> ();
					foreach (var candidate in function.blocks) {
						for (int e = 0; e < candidate.instructions.length; e++) {
							var event = candidate.instructions[e] as SsaHeapOwnerEvent;
							if (event != null && event.owner == scoped.owner && event.action == SsaHeapOwnerAction.END) {
								ends.add (candidate.ordinal);
								ends.add (e - 1);
							}
						}
					}
					native_function.bind_scoped_backing (new NativeScopedBackingPlan (block.ordinal, i, scoped.result.ordinal, scoped.owner.source_ordinal, scoped.owner.ordinal, scoped.backing.owner_ordinal, scoped.backing.ordinal, ((SsaDefinition) scoped.pair.base_value).ordinal, ((SsaDefinition) scoped.pair.length_value).ordinal, scoped.loan.region_ordinal, scoped.result.semantic_type.nominal_name (), NativeAbiValidator.scoped_backing_value_identity (scoped.kind), NativeAbiValidator.scoped_backing_value_identity (scoped.slots), ends));
				}
			}
			foreach (var storage in function.object_storage) {
				if (storage.fallible) {
					var inputs = new GenericArray<NativeAllocationInput> ();
					var buffers = new GenericArray<NativeFrameBufferInput> ();
					var record_inputs = new GenericArray<NativeFrameRecordInput> ();
					foreach (var block in function.blocks) {
						foreach (var instruction in block.instructions) {
							var call = instruction as SsaLifecycleCallInstruction;
							if (call == null || !call.constructs || call.storage != storage) {
								continue;
							}
							foreach (var input in call.owned_arguments) {
								int parameter_index = 0;
								while (parameter_index < call.target.parameters.length && call.target.parameters[parameter_index] != input.parameter) {
									parameter_index++;
								}
								var cleanup = input.cleanup;
								inputs.add (new NativeAllocationInput (parameter_index, input.source_ordinal, cleanup.is_object ? cleanup.object_class.ordinal : -1, cleanup.is_heap_object, cleanup.is_object ? "" : input.value.semantic_type.nominal_name (), cleanup.is_object ? "" : cleanup.external_symbol));
							}
							foreach (var input in call.buffer_arguments) {
								buffers.add (new NativeFrameBufferInput (input.parameter.first_leaf, input.disarm.place.storage.owner_ordinal, buffer_plan (input.pair.shape.slice_type, records)));
							}
							int record_index = 0;
							foreach (var group in call.struct_arguments) {
								if (group.shape.mode != StructValueMode.MOVE_VALUE) {
									continue;
								}
								var moved = call.record_moves[record_index++];
								record_inputs.add (new NativeFrameRecordInput (group.first_leaf, moved.source_ordinal, struct_plans.lookup (group.shape.semantic_type)));
							}
						}
					}
					native_function.bind_allocation_site (new NativeAllocationSite (storage.ordinal, storage.object_class.ordinal, storage.object_class.constructor.ordinal, storage.heap_allocated, storage.fallible, inputs, buffers, record_inputs));
				}
			}
			foreach (var plan in function.shared_elisions) {
				native_function.bind_shared_elision (plan.acquisition.result.ordinal);
			}
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var creation = block.instructions[i] as SsaTaskCreate;
					if (creation == null || !creation.checked_admission) {
						continue;
					}
					var inputs = new GenericArray<NativeAllocationInput> ();
					foreach (var input in creation.owned_arguments) {
						int parameter = 0;
						while (parameter < creation.target.parameters.length && creation.target.parameters[parameter] != input.parameter) {
							parameter++;
						}
						var cleanup = input.cleanup;
						inputs.add (new NativeAllocationInput (parameter, input.source_ordinal, cleanup.is_object ? cleanup.object_class.ordinal : -1, cleanup.is_heap_object, cleanup.is_object ? "" : input.value.semantic_type.nominal_name (), cleanup.is_object ? "" : cleanup.external_symbol));
					}
					var buffers = new GenericArray<NativeFrameBufferInput> ();
					foreach (var input in creation.buffer_arguments) {
						buffers.add (new NativeFrameBufferInput (input.parameter.first_leaf, input.disarm.place.storage.owner_ordinal, buffer_plan (input.pair.shape.slice_type, records)));
					}
					var record_inputs = new GenericArray<NativeFrameRecordInput> ();
					int record_index = 0;
					foreach (var group in creation.struct_arguments) {
						if (group.shape.mode != StructValueMode.MOVE_VALUE) {
							continue;
						}
						var moved = creation.record_moves[record_index++];
						record_inputs.add (new NativeFrameRecordInput (group.first_leaf, moved.source_ordinal, struct_plans.lookup (group.shape.semantic_type)));
					}
					native_function.bind_frame_admission (new NativeFrameAdmissionSite (block.ordinal, i, creation.result.ordinal, creation.target.ordinal, creation.exception_result.ordinal, ((HandleType) creation.allocation_context.semantic_type).context_mode, inputs, buffers, record_inputs));
				}
			}
			foreach (var root in function.stack_objects) {
				native_function.bind_stack_object (root.ordinal);
			}
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var instruction = block.instructions[i];
					if (instruction is SsaVectorMemoryInstruction) {
						var contract = ((SsaVectorMemoryInstruction) instruction).contract;
						native_function.bind_vector_memory (new NativeVectorMemoryPlan ((NativeVectorType) NativeTypeMapper.map_type (contract.vector_type), contract.alignment, contract.store));
					}
					var call = instruction as SsaCallInstruction;
					if (call != null && call.exact_target != null) {
						native_function.bind_exact_call (block.ordinal, i, call.exact_target.ordinal);
					}
				}
			}
			native_function.seal_optimizer_facts ();
			native_function.receiver_borrow = function.result_contract == ResultOwnershipContract.RECEIVER_BORROW;
			if (native_function.receiver_borrow && function.struct_result != null) {
				SsaStructField? origin = null;
				if (function.native_declaration != null) {
					var getter = function as SsaPropertyGetter;
					if (getter != null) {
						foreach (var field in getter.property_member.declaring_type.fields) {
							if (field.name == function.native_declaration.identity.record_field && field.semantic_type == function.return_type && field.record_owner != null) {
								origin = field;
							}
						}
					}
				} else {
					var validation = function.entry.instructions.length == 0 ? null : function.entry.instructions[0] as SsaValidatePlaceInstruction;
					var field = validation == null ? null : validation.place as SsaIndirectFieldPlace;
					if (field != null && field.pointer == function.implicit_receiver) {
						origin = field.field;
					}
				}
				if (origin == null || !(origin.containing_type is SsaClass)) {
					throw new NativeAbiError.INVALID_SSA ("record observation lost its exact verified receiver field");
				}
				native_function.bind_record_observation (new NativeRecordObservation (((SsaClass) origin.containing_type).ordinal, origin.ordinal, signature.struct_result));
			}
			foreach (var owner in function.heap_owners) {
				if (owner.record_type == null) {
					continue;
				}
				var plan = record_owner_plan (native_function, owner.source_ordinal, owner.record_type, record_declarations);
				plan.obligations.add (record_resource (owner.record_path, owner.record_field.semantic_type, owner.cleanup, owner.record_rank, records));
			}
			foreach (var slot in function.buffer_storage) {
				if (slot.record_type == null) {
					continue;
				}
				var plan = record_owner_plan (native_function, slot.record_source_ordinal, slot.record_type, record_declarations);
				plan.obligations.add (record_resource (slot.record_path, slot.cleanup.buffer_type, slot.cleanup, slot.record_rank, records));
			}
			native_function.virtual_slot = function.virtual_slot;
			functions.add (native_function);
			callees.insert (function, native_function);
		}
		bool owns_sums = false;
		foreach (var plan in sums.get_values ()) {
			if (plan.owning) {
				owns_sums = true;
			}
		}
		bool has_owner_slots = false;
		foreach (var owner in source.classes) {
			foreach (var field in owner.fields) {
				if (field.semantic_type is OwnerSlotsType) {
					has_owner_slots = true;
				}
			}
		}
		var result = new NativeAbiProgram (source.span, has_owner_slots ? NativeAbiVersion.OWNER_SLOTS_V15 : has_receiver_text ? NativeAbiVersion.NATIVE_EXCEPTIONS_V14 : owns_sums ? NativeAbiVersion.OWNED_SUMS_V13 : source.enums.length != 0 ? NativeAbiVersion.SUM_VALUES_V12 : records.size () != 0 ? NativeAbiVersion.STRUCT_ELEMENTS_V11 : has_text_slice ? NativeAbiVersion.TEXT_SLICE_V10 : has_text ? NativeAbiVersion.TEXT_V9 : version, functions);
		foreach (var handle in source.handles) {
			var resource = resource_owner (handle.semantic_type, source);
			if (resource != null) {
				result.bind_callable_resource (resource);
			}
		}
		var native_private_accesses = new GenericArray<NativePrivateFieldAccess> ();
		for (int f = 0; f < source.c_functions.length; f++) {
			if (source.c_functions[f].metadata.import_policy == Astra.Source.DeclarationPolicyId.GOBJECT_IMPORT) {
				result.bind_gobject_import (f, source.c_functions[f].metadata.policy_identity ());
			}
		}
		for (int f = 0; f < source.c_functions.length; f++) {
			if (source.c_functions[f].metadata.bool_abi == Astra.Foreign.CBoolAbi.C99) {
				result.bind_c_bool_policy ("c99;import;%d;%s".printf (f, source.c_functions[f].metadata.policy_identity ()));
			}
		}
		foreach (var exported in source.c_exports) {
			if (exported.bool_abi == Astra.Foreign.CBoolAbi.C99) {
				result.bind_c_bool_policy ("c99;export;%d;%d;%s".printf (exported.ordinal, exported.target.ordinal, exported.external_symbol));
			}
		}
		foreach (var handle in source.handles) {
			if (handle.c_import != null) {
				result.bind_class_import (handle.c_import);
			}
		}
		foreach (var handle in source.handles) {
			if (handle.com_import != null) {
				result.bind_com_import (handle.com_import);
			}
		}
		foreach (var access in private_accesses) {
			native_private_accesses.add (new NativePrivateFieldAccess (access.class_ordinal, access.field_ordinal, access.function_ordinal));
		}
		result.bind_private_accesses (native_private_accesses);
		foreach (var structure in source.structs) {
			if (structure.representation != null) {
				result.bind_pod_layout (structure.representation);
			}
		}
		foreach (var owner in source.classes) {
			var fields = new GenericArray<NativeClassField> ();
			foreach (var field in owner.fields) {
				int record_ordinal = -1;
				for (int r = 0; r < source.structs.length; r++) {
					if (source.structs[r].semantic_type == field.semantic_type) {
						record_ordinal = r;
					}
				}
				NativeAbiType? storage_type = null;
				if (record_ordinal < 0) {
					storage_type = (field.semantic_type is OwnerSlotsType) ? (NativeAbiType) slots_type (field, callees, source, plans) : (field.semantic_type is StringType) ? (NativeAbiType) new NativeTextType (NativeTextContract.RECEIVER_TEXT) : (field.semantic_type is ContextBytesType) ? NativeTypeMapper.map_type (field.semantic_type) : (field.semantic_type is SliceType) ? (NativeAbiType) new NativeSliceType () : (field.semantic_type is ClassType) ? (NativeAbiType) new NativeScalarAbiType (NativeScalarType.PTR) : NativeTypeMapper.map_type (field.semantic_type);
				}
				fields.add (new NativeClassField (field.span, field.name, field.semantic_type.display_name (), field.ordinal, field.text_snapshot, storage_type, record_ordinal, field.is_private, field.owned_cleanup != null && field.owned_cleanup.is_heap_object ? field.owned_cleanup.object_class.ordinal : -1, field.owned_cleanup != null && field.owned_cleanup.is_buffer, field.owned_cleanup == null ? null : resource_owner (field.semantic_type, source), field.record_owner != null, field.owned_cleanup != null && field.owned_cleanup.is_buffer ? buffer_plan (field.owned_cleanup.buffer_type, records) : null, field.record_owner == null ? null : struct_plans.lookup ((StructType) field.semantic_type)));
			}
			var slots = new GenericArray<int> ();
			foreach (var target in owner.virtual_entries) {
				slots.add (callees.lookup (target).ordinal);
			}
			result.classes.add (new NativeClassPlan (owner.span, owner.name, owner.ordinal, owner.parent_class == null ? -1 : owner.parent_class.ordinal, owner.destructor == null ? -1 : callees.lookup (owner.destructor).ordinal, owner.polymorphic, owner.exception_root, fields, slots, ((ClassType) owner.semantic_type).is_interface));
			if (((ClassType) owner.semantic_type).is_interface) {
				result.interface_count++;
			}
		}
		foreach (var owner in source.classes) {
			var plan = result.classes[owner.ordinal];
			plan.bind_allocation_policy (owner.allocation_policy, ((ClassType) owner.semantic_type).allocation_policy_identity);
			plan.bind_concurrency_policy (owner.concurrency_policy, ((ClassType) owner.semantic_type).concurrency_policy_identity);
			if (owner.foreign_export != null && owner.foreign_export.declared_api != null) {
				var api = owner.foreign_export.declared_api;
				var targets = new int[api.member_count];
				for (uint m = 0; m < api.member_count; m++) {
					var target = SsaForeignApi.target (owner, api.member (m));
					if (target == null || !callees.contains (target)) {
						throw new NativeAbiError.INVALID_SSA ("declared foreign API lost its actual SSA member target");
					}
					targets[m] = callees.lookup (target).ordinal;
				}
				plan.bind_declared_foreign (owner.foreign_export, ((ClassType) owner.semantic_type).foreign_policy_identity, targets);
			} else if (owner.foreign_export == null) {
				plan.bind_foreign_export (null, ((ClassType) owner.semantic_type).foreign_policy_identity);
			} else {
				var property = owner.properties[owner.foreign_export.property_ordinal];
				plan.bind_foreign_export (owner.foreign_export, ((ClassType) owner.semantic_type).foreign_policy_identity, callees.lookup (owner.constructor).ordinal, callees.lookup (property.getter).ordinal, callees.lookup (property.setter).ordinal);
			}
			if (owner.generic_instance != null) {
				var key = owner.generic_instance;
				var targets = new int[key.definition.member_count];
				for (int i = 0; i < key.definition.member_count; i++) {
					targets[i] = -1;
					if (key.definition.operation (i) == Astra.Source.ExactClassOperation.INITIALIZE) {
						targets[i] = callees.lookup (owner.constructor).ordinal;
					} else {
						foreach (var method in owner.methods) {
							if (method.name == key.definition.member_name (i)) {
								targets[i] = callees.lookup (method).ordinal;
							}
						}
					}
				}
				if (key.definition.structure != null) {
					var properties = new int[owner.properties.length];
					for (int p = 0; p < properties.length; p++) {
						properties[p] = callees.lookup (owner.properties[p].getter).ordinal;
					}
					plan.bind_generic (new NativeExactClassInstance.declared (key.definition, declared_class (owner, source, plans, callees), targets, properties));
					foreach (var method in owner.methods) {
						var request = method.generic_method_instance;
						if (request == null) {
							continue;
						}
						var target = callees.lookup (method);
						NativeDeclaredType[] arguments = {};
						foreach (var argument in request.arguments.copy_values ()) {
							arguments += declared_type (argument, source, plans, callees);
						}
						var instance = new NativeGenericMethodInstance.declared (key.definition, owner.ordinal, request.member, target.ordinal, arguments);
						target.bind_generic_method (instance);
						plan.generic_instance.generic_methods.add (instance);
					}
				} else {
					var methods = new GenericArray<NativeGenericMethodInstance> ();
					foreach (var method in owner.methods) {
						var request = method.generic_method_instance;
						if (request == null) {
							continue;
						}
						var target = callees.lookup (method);
						var instance = new NativeGenericMethodInstance (key.definition, owner.ordinal, request.member, target.ordinal, copy_type (request.argument, source, plans));
						target.bind_generic_method (instance);
						methods.add (instance);
					}
					var argument = (NativeOwnerSlotsType) plan.fields[0].storage_type;
					var properties = new int[owner.properties.length];
					for (int p = 0; p < owner.properties.length; p++) {
						properties[p] = callees.lookup (owner.properties[p].getter).ordinal;
					}
					plan.bind_generic (new NativeExactClassInstance (key.definition, argument.element_ordinal, targets, argument.resource, argument.record_value, methods, properties));
				}
			}
			foreach (var property in owner.properties) {
				if (!property.is_lazy) {
					continue;
				}
				var getter = callees.lookup (property.getter);
				int rank = (int) plan.lazy_caches.length;
				int prefix = plan.parent_ordinal >= 0 ? 1 : plan.concurrency_policy != null ? 6 : plan.polymorphic ? 2 : 0;
				var cache = new NativeLazyCache (property.span, property.name, owner.ordinal, property.ordinal, getter.ordinal, rank, prefix + plan.fields.length + rank * 2, (property.is_owned_lazy ? (NativeAbiType) new NativeScalarAbiType (NativeScalarType.PTR) : NativeTypeMapper.map_type (property.semantic_type)));
				if (property.is_owned_lazy) {
					cache.bind_owned_factory (callees.lookup (property.factory).ordinal, callees.lookup (property.factory).signature.heap_result.class_ordinal);
				}
				plan.lazy_caches.add (cache);
				getter.lazy_cache = cache;
			}
		}
		foreach (var owner in source.classes) {
			if (owner.constructor == null || !ConstructorContracts.admitted (owner.foreign_export, owner.allocation_policy, owner.constructor.member_ordinal, owner.constructor.throws_type)) {
				continue;
			}
			int[] fields = null, lazy = null;
			for (int f = owner.fields.length - 1; f >= 0; f--) {
				var field = owner.fields[f];
				if (field.owned_cleanup != null || field.record_owner != null || field.text_snapshot || field.semantic_type is OwnerSlotsType) {
					fields += f;
				}
			}
			for (int p = owner.properties.length - 1; p >= 0; p--) {
				if (owner.properties[p].is_owned_lazy) {
					lazy += p;
				}
			}
			callees.lookup (owner.constructor).constructor_unwind = new NativeConstructorUnwindPlan (owner.ordinal, fields, lazy);
		}
		foreach (var structure in source.structs) {
			var origin = structure.semantic_type.generic_definition_name ();
			if (origin == null) {
				continue;
			}
			var arguments = structure.semantic_type.generic_arguments ();
			var declared = new NativeDeclaredType[arguments.length];
			for (int a = 0; a < arguments.length; a++) {
				declared[a] = declared_type (arguments.at (a), source, plans, callees);
			}
			var record = declared_type (structure.semantic_type, source, plans, callees).record;
			NativeOwnedRecordDeclaration? owned_record = null;
			var record_type = structure.semantic_type as StructType;
			var contract = record_type == null ? null : record_type.owning_application;
			if (contract != null) {
				var patterns = new Astra.Source.GenericFieldPattern[contract.definition.field_count];
				var owner_parameters = new bool[contract.definition.parameter_count];
				var types = new NativeDeclaredType[structure.fields.length];
				var owns = new bool[structure.fields.length];
				var visibility = new bool[structure.fields.length];
				for (int p = 0; p < owner_parameters.length; p++) {
					owner_parameters[p] = contract.definition.owned_parameter (p);
				}
				for (int f = 0; f < types.length; f++) {
					patterns[f] = contract.definition.field (f);
					types[f] = declared_type (structure.fields[f].semantic_type, source, plans, callees, structure.fields[f]);
					owns[f] = structure.fields[f].owned_cleanup != null;
					visibility[f] = structure.fields[f].is_private;
				}
				owned_record = new NativeOwnedRecordDeclaration (patterns, owner_parameters, types, owns, visibility);
			}
			result.bind_record_application (new NativeRecordApplicationPlan (origin, declared, record, owned_record));
		}
		// Late nominal-only demands can discover an earlier record. Publish
		// all physical plans in the original declaration order.
		for (int ordinal = 0; ordinal < source.structs.length; ordinal++) {
			foreach (var plan in plans) {
				if (plan.struct_ordinal == ordinal) {
					result.struct_values.add (plan);
				}
			}
		}
		for (int f = 0; f < source.functions.length; f++) {
			foreach (var block in source.functions[f].blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var instruction = block.instructions[i];
					var direct = instruction as SsaCallInstruction;
					var foreign = instruction as SsaCCallInstruction;
					var indirect = instruction as SsaCallableInvocation;
					var arguments = direct != null ? direct.arguments : foreign != null ? foreign.arguments : indirect != null ? indirect.arguments : null;
					if (arguments == null) {
						continue;
					}
					for (int a = 0; a < arguments.length; a++) {
						var view = arguments[a] as SsaCallbackView;
						if (view != null) {
							result.bind_callback_view (new NativeCallbackViewPlan (f, block.ordinal, i, a, (NativeClosureHandleType) NativeTypeMapper.map_type (view.closure.semantic_type), (NativeCallbackType) NativeTypeMapper.map_type (view.semantic_type)));
						}
					}
				}
			}
		}
		for (int f = 0; f < source.functions.length; f++) {
			foreach (var block in source.functions[f].blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var operation = block.instructions[i] as SsaActorSend;
					if (operation != null) {
						int error = -1;
						foreach (var owner in source.classes) {
							if (owner.semantic_type == operation.error_type) {
								error = owner.ordinal;
							}
						}
						result.actor_operations.add (new NativeActorPlan (f, block.ordinal, i, operation.action, (NativeClosureHandleType) NativeTypeMapper.map_type (operation.sender.semantic_type), error));
					}
				}
			}
		}
		for (int f = 0; f < source.functions.length; f++) {
			foreach (var block in source.functions[f].blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var operation = block.instructions[i] as SsaRetainedOperation;
					if (operation != null) {
						result.bind_retained_operation (new NativeRetainedPlan (f, block.ordinal, i, (int) operation.action, (NativeClosureHandleType) NativeTypeMapper.map_type (operation.callee.semantic_type)));
					}
				}
			}
		}
		for (int f = 0; f < source.functions.length; f++) {
			foreach (var block in source.functions[f].blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var binding = block.instructions[i] as SsaClosureBind;
					var invocation = block.instructions[i] as SsaClosureCall;
					if (binding != null) {
						var owner = binding.cleanup.closure_environment;
						result.closures.add (new NativeClosurePlan (f, block.ordinal, i, true, (NativeClosureHandleType) NativeTypeMapper.map_type (binding.result.semantic_type), callees.lookup (binding.target).ordinal, owner.destructor == null ? -1 : callees.lookup (owner.destructor).ordinal, binding.actor_binding));
					} else if (invocation != null) {
						result.closures.add (new NativeClosurePlan (f, block.ordinal, i, false, (NativeClosureHandleType) NativeTypeMapper.map_type (invocation.callee.semantic_type), -1, -1, null, callable_borrows (invocation), NativeTypeMapper.map_function_records (invocation.struct_arguments), callable_transfers (invocation), callable_result_owner (invocation), invocation.struct_result != null ? struct_plans.lookup (invocation.struct_result.shape.semantic_type) : invocation.owned_success == null || invocation.owned_success.struct_result == null ? null : struct_plans.lookup (invocation.owned_success.struct_result.shape.semantic_type)));
					}
				}
			}
		}
		for (int f = 0; f < source.functions.length; f++) {
			foreach (var block in source.functions[f].blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var operation = block.instructions[i] as SsaSharedOperation;
					if (operation != null) {
						var handle = operation.action == SharedAction.ACQUIRE ? operation.result.semantic_type : operation.operand.semantic_type;
						result.shared_operations.add (new NativeSharedOperationPlan (f, block.ordinal, i, (int) operation.action, NativeTypeMapper.map_shared_operation (handle)));
					}
				}
			}
		}
		for (int f = 0; f < source.functions.length; f++) {
			foreach (var block in source.functions[f].blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var call = block.instructions[i] as SsaFunctionValueCall;
					if (call != null) {
						var borrowed = callable_borrows (call);
						result.function_values.add (new NativeFunctionValuePlan (f, block.ordinal, i, (NativeFunctionPointerType) NativeTypeMapper.map_type (call.callee.semantic_type), NativeTypeMapper.map_function_records (call.struct_arguments), borrowed, callable_transfers (call), callable_result_owner (call), call.struct_result == null ? null : struct_plans.lookup (call.struct_result.shape.semantic_type)));
					}
				}
			}
		}
		foreach (var definition in source.enums) {
			result.sum_values.add (sums.lookup (definition.semantic_type));
		}
		foreach (var structure in source.structs) {
			var record = records.lookup (structure.semantic_type);
			if (record != null) {
				result.record_elements.add (record);
			}
		}
		foreach (var structure in source.structs) {
			var declaration = record_declarations.lookup (structure.semantic_type);
			if (declaration != null) {
				result.record_declarations.add (declaration);
			}
		}
		// Complete task membership before publishing any verified ABI plan.
		foreach (var function in source.functions) {
			if (function.async_body != null && function.native_declaration == null) {
				result.async_frames.add (NativeAsyncFrameBuilder.build (function, source));
			}
		}
		NativeAbiVerifier.verify (result);
		for (int f = 0; f < source.functions.length; f++) {
			foreach (var block in source.functions[f].blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					if (block.instructions[i] is SsaContinuationRegion) {
						result.continuations.add (NativeContinuationBuilder.build (source, result, f, block.ordinal, i));
					}
				}
			}
		}
		NativeAbiVerifier.verify (result);
		// Every identity/signature is complete before any call is inspected.
		NativeAbiValidator.validate_ssa_calls (source, result, callees);
		return result;
	}

}
}
