// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
// Distinct from ICONV's modulo semantics. No identity, integer or vector cast.
public enum FloatConversionKind {
	FLOAT_WIDEN,
	FLOAT_NARROW;

	public string mode() {
		return this == FLOAT_WIDEN ? "widen-exact" : "nearest-ties-even";
	}

	public bool accepts(SemanticType source, SemanticType destination) {
		if (this == FLOAT_WIDEN) {
			return source is F32Type && destination is F64Type;
		}
		if (this == FLOAT_NARROW) {
			return source is F64Type && destination is F32Type;
		}
		return false;
	}
}
}
