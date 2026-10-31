// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
[Flags]
public enum GenericElementRequirements {
	COPY = 1,
	STORAGE = 2,
	ZERO = 4,
	DESTRUCTION = 8,
	BUFFER = COPY | STORAGE | ZERO | DESTRUCTION
}

// Immutable representation authority, not a semantic type or SSA value.
public class BufferValueShape : Object {
	public SliceType slice_type { get; private set; }
	public RawPointerType base_type { get; private set; }
	public IntegerType length_type { get; private set; }
	internal BufferValueShape (SliceType slice_type, RawPointerType base_type, IntegerType length_type) {
		this.slice_type = slice_type;
		this.base_type = base_type;
		this.length_type = length_type;
	}
	public bool is_valid(CopyabilityFields? fields = null) {
		return BufferElementTypes.supports (slice_type.element_type, fields) && base_type.is_void_pointer () && length_type.kind == TypeKind.INT;
	}
}
// Signature-derived evidence owns only immutable lexical type tokens. Both
// semantic checking and parameterized Core validate the same obligations.
public class GenericSliceObligations : Object {
	private HashTable<TypeParameterType, GenericElementRequirements> elements = new HashTable<TypeParameterType, GenericElementRequirements> (direct_hash, direct_equal);
	public uint length { get { return elements.size (); } }
	public void require(TypeParameterType parameter, GenericElementRequirements requirements = GenericElementRequirements.BUFFER) {
		elements.insert (parameter, requirements);
	}
	public bool contains(TypeParameterType parameter) {
		return elements.contains (parameter);
	}
	public GenericElementRequirements requirements(TypeParameterType parameter) {
		return elements.lookup (parameter);
	}
	public bool establishes(TypeParameterType parameter, GenericElementRequirements required) {
		return (requirements (parameter) & required) == required;
	}
	public static bool accepts(SemanticType type, CopyabilityFields? fields = null, CopyabilityPremise? premise = null) {
		if (type is TypeParameterType) {
			return ((TypeParameterType) type).transport_mode == GenericTransportMode.PLAIN_COPY && premise != null && premise ((TypeParameterType) type);
		}
		// Reuse the accepted composite concrete eligibility rule. Its zero and
		// destruction checks are independent of copying; no allocation occurs.
		return GenericArgumentTypes.supports (type, fields) && BufferElementTypes.supports (type, fields);
	}
}

// Independent structural questions, not generic-argument capability aliases.
public class BufferElementTypes : Object {
	// Interning a nominal collection type does not certify its field graph.
	// Each consuming stage supplies its own complete graph before using storage.
	public static bool candidate(SemanticType type) {
		return !type.is_parameterized () && (leaf_storage (type) || type.is_struct_storage ());
	}
	private static bool leaf_storage(SemanticType type) {
		return type is IntegerType || type is FloatingType || type.kind == TypeKind.BOOL || type.is_void_pointer () || (type is VectorType && VectorType.supports (((VectorType) type).element_type, ((VectorType) type).lane_count));
	}
	public static bool fixed_storage(SemanticType type, CopyabilityFields? fields = null) {
		return problem (type, fields, ElementRequirement.STORAGE) == null;
	}
	public static bool trivial_destruction(SemanticType type, CopyabilityFields? fields = null) {
		return problem (type, fields, ElementRequirement.DESTRUCTION) == null;
	}
	public static bool defined_zero(SemanticType type, CopyabilityFields? fields = null) {
		return problem (type, fields, ElementRequirement.ZERO) == null;
	}
	public static bool supports(SemanticType type, CopyabilityFields? fields = null) {
		if (type.is_parameterized () || !fixed_storage (type, fields) || !trivial_destruction (type, fields) || !defined_zero (type, fields)) {
			return false;
		}
		return fields == null ? CopyabilityAuthority.of(type, (aggregate) => null) == Copyability.COPYABLE : CopyabilityAuthority.of (type, fields) == Copyability.COPYABLE;
	}

	private enum ElementRequirement {
		STORAGE, DESTRUCTION, ZERO
	}
	private static string? problem(SemanticType type, CopyabilityFields? fields, ElementRequirement requirement) {
		return visit (type, fields, requirement, new HashTable<SemanticType, bool> (direct_hash, direct_equal), "");
	}
	public static string? invalid_field(SemanticType type, CopyabilityFields fields) {
		return problem (type, fields, ElementRequirement.STORAGE);
	}
	private static string? visit(SemanticType type, CopyabilityFields? fields, ElementRequirement requirement, HashTable<SemanticType, bool> visited, string path) {
		if (leaf_storage (type)) {
			// These are separate obligations. In this bounded domain each leaf
			// has fixed storage, no destruction action, and an explicit zero.
			switch (requirement) {
			case ElementRequirement.STORAGE: case ElementRequirement.DESTRUCTION: case ElementRequirement.ZERO: return null;
				default: assert_not_reached ();
			}
		}
		if (!type.is_struct_storage () || type.is_parameterized () || fields == null) {
			return path;
		}
		if (visited.contains (type)) {
			return visited.lookup (type) ? null : path;
		}
		visited.insert (type, false);
		var children = fields (type);
		if (children == null || children.length == 0) {
			return path;
		}
		for (int i = 0; i < children.length; i++) {
			var failure = visit (children[i], fields, requirement, visited, path == "" ? i.to_string () : path + "." + i.to_string ());
			if (failure != null) {
				return failure;
			}
		}
		visited.insert (type, true);
		return null;
	}
}
}
