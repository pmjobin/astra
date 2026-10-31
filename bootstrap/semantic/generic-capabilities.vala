// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
// Borrowing selects no cleanup or allocation
// origin: the exact source owner retains both, including for heap Classes.
public class GenericBorrowTypes : Object {
	public static bool symbolic(SemanticType? type) {
		return type is TypeParameterType && ((TypeParameterType) type).transport_mode == GenericTransportMode.OWNABLE;
	}
	public static bool accepts(SemanticType type) {
		return symbolic (type) || type is HandleType || type is ClassType;
	}
	public static bool scalar(SemanticType type) {
		return type is IntegerType || type is FloatingType || type.kind == TypeKind.BOOL;
	}
}

public class GenericCapabilityAuthority : Object {
	// The sole concrete capability matrix. Vectors retain only GEN1_PLAIN_COPY.
	public static uint capabilities_of(SemanticType type) {
		switch (type.kind) {
		case TypeKind.I8:
		case TypeKind.U8:
		case TypeKind.I16:
		case TypeKind.U16:
		case TypeKind.INT:
		case TypeKind.U32:
		case TypeKind.I64:
		case TypeKind.U64:
		case TypeKind.ISIZE:
		case TypeKind.USIZE:
			return GenericCapabilityDomain.INTEGER.capabilities ();
		case TypeKind.F32:
		case TypeKind.F64:
			return GenericCapabilityDomain.FLOATING.capabilities ();
		case TypeKind.BOOL:
			return GenericCapabilityDomain.BOOLEAN.capabilities ();
		case TypeKind.HANDLE:
		case TypeKind.CLASS:
			return (type is HandleType || type is ClassType) ? GenericCapabilityDomain.OWNER.capabilities () : 0;
		default:
			return type.is_void_pointer () ? GenericCapabilityDomain.RAW_POINTER.capabilities () : 0;
		}
	}
	public static bool satisfies(SemanticType type, GenericCapabilityIdentity capability) {
		if (!capability.valid ()) {
			return false;
		}
		var parameter = type as TypeParameterType;
		return parameter != null ? parameter.explicit_capabilities.contains(capability) : (capabilities_of (type) & capability.bit ()) != 0;
	}
}

}
