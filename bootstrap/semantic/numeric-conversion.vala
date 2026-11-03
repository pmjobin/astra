// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
public enum NumericConversionPolicy {
	NEAREST_TIES_EVEN,
	TRUNCATE_TRAP;

	public string spelling() {
		return this == NEAREST_TIES_EVEN ? "nearest-ties-even" : "truncate-toward-zero-trap";
	}

}

// Concrete scalar capability. IntegerType and FloatingType remain the only
// range/format authorities; neither source symbols nor physical opcodes enter.
public enum NumericConversionKind {
	INVALID,
	SIGNED_INT_TO_F32,
	UNSIGNED_INT_TO_F32,
	SIGNED_INT_TO_F64,
	UNSIGNED_INT_TO_F64,
	F32_TO_SIGNED_INT,
	F32_TO_UNSIGNED_INT,
	F64_TO_SIGNED_INT,
	F64_TO_UNSIGNED_INT;

	public bool traps() {
		return this >= F32_TO_SIGNED_INT && this <= F64_TO_UNSIGNED_INT;
	}

	public NumericConversionPolicy policy() {
		return traps () ? NumericConversionPolicy.TRUNCATE_TRAP : NumericConversionPolicy.NEAREST_TIES_EVEN;
	}

	public static NumericConversionKind select(SemanticType source, SemanticType destination) {
		var from = source as IntegerType;
		var to = destination as IntegerType;
		if (from != null && destination is F32Type) {
			return from.is_signed ? SIGNED_INT_TO_F32 : UNSIGNED_INT_TO_F32;
		}
		if (from != null && destination is F64Type) {
			return from.is_signed ? SIGNED_INT_TO_F64 : UNSIGNED_INT_TO_F64;
		}
		if (source is F32Type && to != null) {
			return to.is_signed ? F32_TO_SIGNED_INT : F32_TO_UNSIGNED_INT;
		}
		if (source is F64Type && to != null) {
			return to.is_signed ? F64_TO_SIGNED_INT : F64_TO_UNSIGNED_INT;
		}
		return INVALID;
	}

	public bool accepts(SemanticType source, SemanticType destination, NumericConversionPolicy policy) {
		return this != INVALID && this == select (source, destination) && policy == this.policy ();
	}

	public string spelling() {
		switch (this) {
		case SIGNED_INT_TO_F32:
			return "signed-int-to-f32";
		case UNSIGNED_INT_TO_F32:
			return "unsigned-int-to-f32";
		case SIGNED_INT_TO_F64:
			return "signed-int-to-f64";
		case UNSIGNED_INT_TO_F64:
			return "unsigned-int-to-f64";
		case F32_TO_SIGNED_INT:
			return "f32-to-signed-int";
		case F32_TO_UNSIGNED_INT:
			return "f32-to-unsigned-int";
		case F64_TO_SIGNED_INT:
			return "f64-to-signed-int";
		case F64_TO_UNSIGNED_INT:
			return "f64-to-unsigned-int";
		default:
			return "invalid";
		}
	}

}

}
