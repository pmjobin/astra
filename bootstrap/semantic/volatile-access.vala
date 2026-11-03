// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
namespace Astra.Semantic {
// Immutable source intent survives separately from each mutable stage flag.
// The normal Place remains the address/bounds/lifetime authority.
public class VolatileAccessContract : Object {
	public SemanticType value_type { get; private set; }
	public uint alignment { get { return value_type.kind == TypeKind.U32 ? 4 : 8; } }
	public VolatileAccessContract (SemanticType type) {
		value_type = type;
	}

	public static bool supports(SemanticType type) {
		return type.kind == TypeKind.U32 || type.kind == TypeKind.U64;
	}

	public bool matches(SemanticType type) {
		return type == value_type && supports (type);
	}

	public VolatileAccessContract copy() {
		return new VolatileAccessContract (value_type);
	}

	public static bool valid(VolatileAccessContract? contract, bool enabled, SemanticType type) {
		return enabled == (contract != null) && (contract == null || contract.matches (type));
	}

}
}
