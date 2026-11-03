// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Semantic {

public class EnumField : Object {
	public bool owns_record { get; private set; }
	public bool owns_buffer { get; private set; }
	public bool owns_child { get; private set; }
	public Astra.Foreign.CForeignCleanupContract? owned_cleanup { get; private set; }
	public bool owns_scalar { get { return owns_child || owned_cleanup != null; } }
	public EnumFieldIdentity identity { get; private set; }
	public SemanticType semantic_type { get; private set; }
	public SourceSpan span { get; private set; }
	internal EnumField (EnumFieldIdentity identity, SemanticType semantic_type, SourceSpan span, bool owns_buffer = false, Astra.Foreign.CForeignCleanupContract? owned_cleanup = null, bool owns_child = false, bool owns_record = false) {
		this.identity = identity;
		this.semantic_type = semantic_type;
		this.span = span;
		this.owns_buffer = owns_buffer;
		this.owned_cleanup = owned_cleanup;
		this.owns_child = owns_child;
		this.owns_record = owns_record;
	}

}

public class EnumVariant : Object {
	public EnumVariantIdentity identity { get; private set; }
	public SourceSpan span { get; private set; }
	private GenericArray<EnumField> payload;
	public uint field_count { get { return payload.length; } }
	public EnumField field(uint ordinal) {
		return payload[ordinal];
	}

	public EnumField? find_field(string name) {
		foreach (var field in payload) {
			if (field.identity.name == name) {
				return field;
			}
		}
		return null;
	}

	internal EnumVariant (EnumVariantIdentity identity, SourceSpan span, GenericArray<EnumField> fields) {
		this.identity = identity;
		this.span = span;
		payload = new GenericArray<EnumField> ();
		foreach (var field in fields) {
			payload.add (field);
		}
	}

}

// Frozen all-variant schema; private arrays cannot be mutated by retained users.
public class EnumDefinition : Object {
	public IntegerType tag_type { get; private set; }
	public EnumType semantic_type { get; private set; }
	public SourceSpan span { get; private set; }
	private GenericArray<EnumVariant> alternatives;
	public uint variant_count { get { return alternatives.length; } }
	public bool payload_free {
		get {
			foreach (var variant in alternatives) {
				if (variant.field_count != 0) {
					return false;
				}
			}
			return true;
		}
	}
	public EnumVariant variant(uint ordinal) {
		return alternatives[ordinal];
	}

	public EnumVariant? find_variant(string name) {
		foreach (var variant in alternatives) {
			if (variant.identity.name == name) {
				return variant;
			}
		}
		return null;
	}

	public GenericArray<SemanticType> value_fields() {
		var fields = new GenericArray<SemanticType> ();
		foreach (var variant in alternatives) {
			for (uint f = 0; f < variant.field_count; f++) {
				fields.add (variant.field (f).semantic_type);
			}
		}
		return fields;
	}

	public EnumDefinition application(EnumType type, TypeSubstitution substitution) {
		assert (semantic_type.origin == type.origin);
		var variants = new GenericArray<EnumVariant> ();
		foreach (var variant in alternatives) {
			var identity = new EnumVariantIdentity (type.identity, variant.identity.name, variant.identity.ordinal);
			var fields = new GenericArray<EnumField> ();
			for (uint f = 0; f < variant.field_count; f++) {
				var field = variant.field (f);
				fields.add (new EnumField (new EnumFieldIdentity (identity, field.identity.name, field.identity.ordinal), substitution.apply (field.semantic_type), field.span, field.owns_buffer, field.owned_cleanup, field.owns_child, field.owns_record));
			}
			variants.add (new EnumVariant (identity, variant.span, fields));
		}
		return new EnumDefinition (type, span, variants, tag_type);
	}

	internal EnumDefinition (EnumType semantic_type, SourceSpan span, GenericArray<EnumVariant> variants, IntegerType tag_type) {
		this.tag_type = tag_type;
		this.semantic_type = semantic_type;
		this.span = span;
		alternatives = new GenericArray<EnumVariant> ();
		foreach (var variant in variants) {
			alternatives.add (variant);
		}
	}

}

public delegate EnumDefinition? EnumDefinitions(EnumType type);
public delegate bool EnumScalarOwnership(EnumField field);
public errordomain EnumContractError {
	INVALID_GRAPH
}

public class EnumValueAuthority : Object {
	public static bool owns(EnumDefinition definition, EnumDefinitions definitions) {
		return owns_graph (definition, definitions, new HashTable<EnumType, bool> (direct_hash, direct_equal));
	}

	private static bool owns_graph(EnumDefinition definition, EnumDefinitions definitions, HashTable<EnumType, bool> seen) {
		if (seen.contains (definition.semantic_type)) {
			return false;
		}
		seen.insert (definition.semantic_type, true);
		for (uint v = 0; v < definition.variant_count; v++) {
			for (uint f = 0; f < definition.variant (v).field_count; f++) {
				var field = definition.variant (v).field (f);
				if (field.owns_buffer || field.owns_scalar || field.owns_record) {
					return true;
				}
				if (field.semantic_type is EnumType) {
					var nested = definitions ((EnumType) field.semantic_type);
					if (nested != null && owns_graph (nested, definitions, seen)) {
						return true;
					}
				}
			}
		}
		return false;
	}

	public static void verify(EnumDefinition definition, EnumDefinitions definitions, CopyabilityFields records, CopyabilityPremise? premise = null, CopyabilityPremise? elements = null, EnumScalarOwnership? scalar_owners = null) throws EnumContractError {
		visit (definition, definitions, records, premise, elements, scalar_owners, new HashTable<EnumType, bool> (direct_hash, direct_equal), definition.semantic_type.display_name ());
	}

	private static void visit(EnumDefinition definition, EnumDefinitions definitions, CopyabilityFields records, CopyabilityPremise? premise, CopyabilityPremise? elements, EnumScalarOwnership? scalar_owners, HashTable<EnumType, bool> visited, string path) throws EnumContractError {
		if (definition.tag_type.kind != TypeKind.INT) {
			throw new EnumContractError.INVALID_GRAPH ("enum tag requires internal canonical i32");
		}
		var type = definition.semantic_type;
		if (definitions (type) != definition) {
			throw new EnumContractError.INVALID_GRAPH ("enum graph has a substituted nominal definition at %s", path);
		}
		if (visited.contains (type)) {
			if (!visited.lookup (type)) {
				throw new EnumContractError.INVALID_GRAPH ("by-value enum cycle at %s", path);
			}
			return;
		}
		visited.insert (type, false);
		if (type.origin == type) {
			for (uint a = 0; a < type.argument_count; a++) {
				var parameter = type.argument (a) as TypeParameterType;
				if (parameter == null) {
					throw new EnumContractError.INVALID_GRAPH ("generic enum origin requires exact lexical parameter identities");
				}
				bool required = false;
				for (uint v = 0; v < definition.variant_count; v++) {
					for (uint f = 0; f < definition.variant (v).field_count; f++) {
						var field = definition.variant (v).field (f);
						var slice = field.semantic_type as SliceType;
						var child = field.semantic_type as EnumType;
						if ((field.owns_buffer && slice != null && slice.element_type == parameter) || (child != null && child.declares_element (parameter))) {
							required = true;
						}
					}
				}
				if (required != type.requires_array_element (a)) {
					throw new EnumContractError.INVALID_GRAPH ("enum element premise does not derive from exact declared payloads");
				}
			}
		}
		if (definition.variant_count == 0) {
			throw new EnumContractError.INVALID_GRAPH ("enum '%s' must contain at least one variant", type.display_name ());
		}
		var names = new HashTable<string, bool> (str_hash, str_equal);
		for (uint v = 0; v < definition.variant_count; v++) {
			var variant = definition.variant (v);
			if (variant.identity.enumeration != type.identity || variant.identity.ordinal != v || names.contains (variant.identity.name)) {
				throw new EnumContractError.INVALID_GRAPH ("invalid or duplicate enum variant identity at %s", path);
			}
			names.insert (variant.identity.name, true);
			var fields = new HashTable<string, bool> (str_hash, str_equal);
			for (uint f = 0; f < variant.field_count; f++) {
				var field = variant.field (f);
				string next = path + "." + variant.identity.name + "." + field.identity.name;
				if (field.identity.variant != variant.identity || field.identity.ordinal != f || fields.contains (field.identity.name)) {
					throw new EnumContractError.INVALID_GRAPH ("invalid or duplicate enum field identity at %s", next);
				}
				fields.insert (field.identity.name, true);
				var child = field.semantic_type as EnumType;
				if ((field.owns_buffer ? 1 : 0) + (field.owns_child ? 1 : 0) + (field.owned_cleanup != null ? 1 : 0) + (field.owns_record ? 1 : 0) > 1) {
					throw new EnumContractError.INVALID_GRAPH ("enum field has conflicting ownership kinds at %s", next);
				}
				if (field.owns_record) {
					if (!(field.semantic_type is StructType) || field.semantic_type.is_parameterized () || CopyabilityAuthority.of (field.semantic_type, records) == Copyability.COPYABLE) {
						throw new EnumContractError.INVALID_GRAPH ("owned enum record requires its exact concrete recursively owning declaration at %s", next);
					}
				} else if (field.owns_scalar) {
					var object_type = field.semantic_type as ClassType;
					if (field.owns_child ? object_type == null || object_type.is_interface : field.semantic_type.get_type () != typeof (HandleType) || field.owned_cleanup.external_symbol == "") {
						throw new EnumContractError.INVALID_GRAPH ("owned enum scalar field requires an exact Resource cleanup or native Class at %s", next);
					}
					if (scalar_owners == null || !scalar_owners (field)) {
						throw new EnumContractError.INVALID_GRAPH ("owned enum scalar field lost its exact stage declaration cleanup at %s", next);
					}
				} else if (field.owns_buffer) {
					var slice = field.semantic_type as SliceType;
					if (slice == null || !GenericSliceObligations.accepts (slice.element_type, records, elements)) {
						throw new EnumContractError.INVALID_GRAPH ("owned enum field at %s requires an exact supported owned-array element contract", next);
					}
				} else if (child != null) {
					var nested = definitions (child);
					if (nested == null) {
						throw new EnumContractError.INVALID_GRAPH ("missing enum payload definition at %s", next);
					}
					visit (nested, definitions, records, premise, elements, scalar_owners, visited, next);
				} else if (CopyabilityAuthority.value_copy (field.semantic_type, records, premise) != Copyability.COPYABLE) {
					throw new EnumContractError.INVALID_GRAPH ("unsupported enum payload '%s' at %s; requires a copyable value or an owned array", field.semantic_type.display_name (), next);
				}
			}
		}
		visited.insert (type, true);
	}

}
}
