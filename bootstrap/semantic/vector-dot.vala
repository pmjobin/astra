// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
// Each mode fixes its domain, accumulator arity and reduction contract.
// Integer grouping is free modulo D; F32 is ordered and never fused.
public enum VectorDotKind {
	INTEGER_WRAP_DOT,
	INTEGER_WRAP_MAC,
	F32_DOT,
	F32_MAC,
	F64_DOT,
	F64_MAC;

	public bool is_integer() {
		return this == INTEGER_WRAP_DOT || this == INTEGER_WRAP_MAC;
	}
	public bool is_mac() {
		return this == INTEGER_WRAP_MAC || this == F32_MAC || this == F64_MAC;
	}
	public string order() {
		return is_integer () ? "modular" : "ascending-lane";
	}
	public string spelling() {
		switch (this) {
		case INTEGER_WRAP_DOT:
			return "dot-wrap";
		case INTEGER_WRAP_MAC:
			return "mac-wrap";
		case F32_DOT:
			return "dot-f32";
		case F32_MAC:
			return "mac-f32";
		case F64_DOT:
			return "dot-f64";
		case F64_MAC:
			return "mac-f64";
		default:
			return "invalid-dot";
		}
	}

	public string? type_error(SemanticType source, SemanticType first, SemanticType second, SemanticType result, SemanticType? accumulator) {
		if (this != INTEGER_WRAP_DOT && this != INTEGER_WRAP_MAC && this != F32_DOT && this != F32_MAC && this != F64_DOT && this != F64_MAC) {
			return "invalid dot/MAC semantic mode";
		}
		var vector = source as VectorType;
		if (vector == null || !VectorType.supports (vector.element_type, vector.lane_count)) {
			return "dot/MAC requires a supported source VectorType";
		}
		if (first != source || second != source) {
			return "dot/MAC operands must have the exact same source VectorType";
		}
		if (is_mac () ? accumulator != result : accumulator != null) {
			return "dot/MAC accumulator must have the exact scalar result type and match the semantic mode";
		}
		if (is_integer ()) {
			var element = vector.element_type as IntegerType;
			var destination = result as IntegerType;
			if (element == null || destination == null) {
				return "dot_wrap/mac_wrap requires integer vectors and a scalar IntegerType accumulator";
			}
			if (destination.bit_width < element.bit_width) {
				return "integer dot/MAC accumulator width must be at least the source element width";
			}
		} else if (this == F64_DOT || this == F64_MAC) {
			if (vector.element_type.kind != TypeKind.F64 || result != vector.element_type) {
				return "dot/mac requires f64 vectors and a scalar f64 accumulator/result";
			}
		} else if (vector.element_type.kind != TypeKind.F32 || result != vector.element_type) {
			return "dot/mac requires f32 vectors and a scalar f32 accumulator/result";
		}
		return null;
	}
}
}
