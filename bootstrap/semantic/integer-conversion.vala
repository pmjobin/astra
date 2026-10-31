// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
// Capability shared by checking and every IR verifier. This is one total
// mathematical-value modulo destination-width operation, never a family of
// independent sign/extension/truncation source operations (ADR 0039).
public class IntegerConversion : Object {
	public static IntegerType? element_type(SemanticType type) {
		return ((type is VectorType) ? ((VectorType) type).element_type : type) as IntegerType;
	}

	public static bool accepts(SemanticType source, SemanticType destination) {
		if (source is IntegerType && destination is IntegerType) {
			return true;
		}
		var from = source as VectorType;
		var to = destination as VectorType;
		return from != null && to != null && from.element_type is IntegerType && to.element_type is IntegerType && from.lane_count == to.lane_count && VectorType.supports (from.element_type, from.lane_count) && VectorType.supports (to.element_type, to.lane_count);
	}
}
}
