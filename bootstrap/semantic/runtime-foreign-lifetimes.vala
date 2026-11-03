// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;

namespace Astra.Semantic {
// A trusted C implementation must honor the declared borrow: it cannot
// retire that owner, retain it, or obtain ownership through a scalar channel.
// Pointer/aggregate/callback/resource transport needs its own effect contract.
public class RuntimeForeignLifetimes : Object {
	public static bool scalar(SemanticType type) {
		return type is IntegerType || type is FloatingType || type.kind == TypeKind.BOOL;
	}

	public static bool result(SemanticType type, string? cleanup = null) {
		if (cleanup == null) {
			return type.kind == TypeKind.VOID || scalar (type);
		}
		var context = type as HandleType;
		return context != null && AllocationPolicy.valid_context_mode (context.context_mode) && context.context_mode != "scoped-affine" && context.context_cleanup != "" && cleanup == context.context_cleanup;
	}

	public static bool input(SemanticType type, PointerParameterContract contract, bool factory = false) {
		if (scalar (type)) {
			return contract == PointerParameterContract.UNMANAGED;
		}
		// A scalar-only owned factory cannot derive backing from a scoped
		// input. Factories borrowing backing need a separate lease effect.
		if (factory) {
			return false;
		}
		var context = type as HandleType;
		return context != null && AllocationPolicy.valid_context_mode (context.context_mode) && context.context_cleanup != "" && contract == PointerParameterContract.BORROWED_NOESCAPE;
	}

}
}
