// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
// Exact, independent permissions. These bits deliberately match LLVM's
// public FMF encoding, but their admission and checked domain are Astra's.
public class FloatingPointPolicy : Object {
	public const uint REASSOCIATE = 1;
	public const uint NO_NAN = 2;
	public const uint NO_INFINITY = 4;
	public const uint NO_SIGNED_ZERO = 8;
	public const uint RECIPROCAL = 16;
	public const uint CONTRACT = 32;
	public const uint SUPPORTED = Astra.Source.FloatingPointPermissions.SUPPORTED;

	public static bool valid(uint permissions) {
		return Astra.Source.FloatingPointPermissions.valid (permissions);
	}
	public static bool floating(SemanticType type) {
		return type is FloatingType || (type is VectorType && ((VectorType) type).element_type is FloatingType);
	}
	public static uint option(string name) {
		switch (name) {
		case "contract":
			return CONTRACT;
		case "reassociate":
			return REASSOCIATE;
		case "reciprocal":
			return RECIPROCAL;
		case "finite":
			return NO_NAN | NO_INFINITY;
		case "no_nan":
			return NO_NAN;
		case "no_signed_zero":
			return NO_SIGNED_ZERO;
		default:
			return 0;
		}
	}
}
}
