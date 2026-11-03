// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
public enum Copyability {
	COPYABLE, NOT_COPYABLE
}

// The caller supplies its own exact field graph. No stage descriptors, layout,
// ownership contracts or physical transport enter the rule. Symbolic proofs
// additionally supply exact scoped plain-copy premises.
public delegate GenericArray<SemanticType>? CopyabilityFields(SemanticType type);
public delegate bool CopyabilityPremise(TypeParameterType parameter);

public class CopyabilityAuthority : Object {
	public static Copyability of(SemanticType type, CopyabilityFields fields) {
		return visit (type, fields, null, false, new HashTable<SemanticType, bool> (direct_hash, direct_equal), 0);
	}

	// Premises belong to the caller's exact lexical scope. This does not make a
	// symbolic type ordinary concrete storage, zeroable, or ownership-bearing.
	public static Copyability value_copy(SemanticType type, CopyabilityFields fields, CopyabilityPremise? premise = null) {
		return visit (type, fields, premise, true, new HashTable<SemanticType, bool> (direct_hash, direct_equal), 0);
	}

	private static Copyability visit(SemanticType type, CopyabilityFields fields, CopyabilityPremise? premise, bool value_storage, HashTable<SemanticType, bool> visited, int depth) {
		if (type is TypeParameterType) {
			var parameter = (TypeParameterType) type;
			return premise != null && parameter.transport_mode == GenericTransportMode.PLAIN_COPY && premise (parameter) ? Copyability.COPYABLE : Copyability.NOT_COPYABLE;
		}
		if (type is CallbackType) {
			return Copyability.NOT_COPYABLE;
		}
		if (type is IntegerType || type is FloatingType || type.kind == TypeKind.BOOL || type is FunctionValueType || type.is_void_pointer ()) {
			return Copyability.COPYABLE;
		}
		if (type is VectorType) {
			return VectorType.supports (((VectorType) type).element_type, ((VectorType) type).lane_count) ? Copyability.COPYABLE : Copyability.NOT_COPYABLE;
		}
		if (!(type.is_struct_storage () || type is EnumType) || (premise == null && type.is_parameterized ())) {
			return Copyability.NOT_COPYABLE;
		}
		// Concrete field graphs reuse ordinary copyability without a size/leaf
		// cutoff. Only expansion of type applications needs a proof budget.
		if (type.kind == TypeKind.GENERIC_STRUCT_APPLICATION && ++depth > 256) {
			return Copyability.NOT_COPYABLE;
		}
		// False means in progress or rejected. Valid by-value graphs are acyclic;
		// malformed cycles fail closed, while completed shared subgraphs are reused.
		if (visited.contains (type)) {
			return visited.lookup (type) ? Copyability.COPYABLE : Copyability.NOT_COPYABLE;
		}
		visited.insert (type, false);
		var exact_fields = fields (type);
		if (exact_fields == null || (value_storage && exact_fields.length == 0 && !(type is EnumType))) {
			return Copyability.NOT_COPYABLE;
		}
		foreach (var field in exact_fields) {
			if (visit (field, fields, premise, value_storage, visited, depth) != Copyability.COPYABLE) {
				return Copyability.NOT_COPYABLE;
			}
		}
		visited.insert (type, true);
		return Copyability.COPYABLE;
	}

}
}
