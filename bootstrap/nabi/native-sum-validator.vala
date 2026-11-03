// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Ssa;

namespace Astra.NativeAbi {
internal class NativeSumValidator : Object {
	internal static void validate(SsaProgram source, NativeAbiProgram program, HashTable<SemanticType, NativeRecordElement> records) throws NativeAbiError {
		if (source.enums.length != program.sum_values.length) {
			throw new NativeAbiError.INCOMPATIBLE_CALL ("sum plan count lost complete source correspondence");
		}
		var plans = new HashTable<EnumType, NativeSumPlan> (direct_hash, direct_equal);
		for (int i = 0; i < source.enums.length; i++) {
			var definition = source.enums[i];
			var plan = program.sum_values[i];
			if (plan.identity != definition.semantic_type.identity || plan.variants.length != definition.variant_count) {
				throw new NativeAbiError.INCOMPATIBLE_CALL ("sum plan lost exact nominal definition/variant association");
			}
			plans.insert (definition.semantic_type, plan);
		}
		for (int i = 0; i < source.enums.length; i++) {
			var definition = source.enums[i];
			var plan = program.sum_values[i];
			for (uint v = 0; v < definition.variant_count; v++) {
				var variant = definition.variant (v);
				var planned = plan.variants[v];
				if (variant.identity != planned.identity || variant.field_count != planned.fields.length) {
					throw new NativeAbiError.INCOMPATIBLE_CALL ("sum variant/complete field correspondence mismatch");
				}
				for (uint f = 0; f < variant.field_count; f++) {
					var field = variant.field (f);
					var physical = planned.fields[f];
					if (field.identity != physical.identity || (!field.owns_buffer && physical.buffer != null) || (field.owns_scalar != (physical.scalar_owner != null)) || (field.owns_record != (physical.record_value != null))) {
						throw new NativeAbiError.INCOMPATIBLE_CALL ("sum field identity/order or ownership role mismatch");
					}
					if (field.owns_record) {
						NativeAbiValidator.validate_struct_association (NativeAbiBuilder.record_storage_shape ((StructType) field.semantic_type, source), physical.record_value, source, "enum record payload");
					} else if (field.owns_scalar) {
						int class_ordinal = -1;
						if (field.owns_child) {
							foreach (var owner in source.classes) {
								if (owner.semantic_type == field.semantic_type) {
									class_ordinal = owner.ordinal;
								}
							}
						}
						var owned = physical.scalar_owner;
						if (physical.sum != null || physical.record != null || physical.buffer != null || physical.leaf == null || !physical.leaf.same_type (new NativeScalarAbiType (NativeScalarType.PTR)) || owned.type_name != field.semantic_type.display_name () || owned.class_ordinal != class_ordinal || (field.owns_child && class_ordinal < 0) || owned.cleanup_symbol != (field.owned_cleanup == null ? "" : field.owned_cleanup.external_symbol)) {
							throw new NativeAbiError.INCOMPATIBLE_CALL ("owned sum scalar lost its exact nominal type and original cleanup");
						}
					} else if (field.owns_buffer) {
						var slice = (SliceType) field.semantic_type;
						if (physical.buffer == null || physical.sum != null || physical.record != null || physical.leaf != null || ((slice.element_type is StructType) ? physical.buffer.record_element != records.lookup (slice.element_type) : physical.buffer.record_element != null || !physical.buffer.element_type.same_type (NativeTypeMapper.map_type (slice.element_type)))) {
							throw new NativeAbiError.INCOMPATIBLE_CALL ("owned sum buffer lost exact element and complete descriptor plan");
						}
					} else if (field.semantic_type is EnumType) {
						if (physical.sum != plans.lookup ((EnumType) field.semantic_type) || physical.record != null || physical.leaf != null) {
							throw new NativeAbiError.INCOMPATIBLE_CALL ("nested sum nominal payload mismatch");
						}
					} else if (field.semantic_type is StructType) {
						if (physical.record != records.lookup (field.semantic_type) || physical.sum != null || physical.leaf != null) {
							throw new NativeAbiError.INCOMPATIBLE_CALL ("sum record payload nominal mismatch");
						}
					} else if (physical.sum != null || physical.record != null || physical.leaf == null || !physical.leaf.same_type (NativeTypeMapper.map_type (field.semantic_type))) {
						throw new NativeAbiError.INCOMPATIBLE_CALL ("sum scalar/vector payload exact channel mismatch");
					}
				}
			}
		}
		for (int f = 0; f < source.functions.length; f++) {
			var result = source.functions[f].return_type as EnumType;
			var signature = program.functions[f].signature;
			if ((result == null) != (signature.sum_result == null) || (result != null && result.identity != signature.sum_result.identity)) {
				throw new NativeAbiError.INCOMPATIBLE_CALL ("sum function result nominal storage correspondence mismatch");
			}
		}
	}

}
}
