// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
// Finite LP64 C record authority. No bool, pointer, nested record, vector,
// ownership or hidden runtime fields are admitted by this boundary.
public class CPlainRecordTypes : Object {
	public static bool i32_pointer(SemanticType type) {
		return type is TypedPointerType && ((TypedPointerType) type).pointee.kind == TypeKind.INT;
	}

	public static uint scalar_bytes(SemanticType type) {
		switch (type.kind) {
		case TypeKind.I8:
		case TypeKind.U8:
			return 1;
		case TypeKind.I16:
		case TypeKind.U16:
			return 2;
		case TypeKind.INT:
		case TypeKind.U32:
		case TypeKind.F32:
			return 4;
		case TypeKind.I64:
		case TypeKind.U64:
		case TypeKind.ISIZE:
		case TypeKind.USIZE:
		case TypeKind.F64:
			return 8;
		default:
			return 0;
		}
	}

	// Each supported field occupies its own eightbyte. The f32/f64 pair
	// admits explicit natural padding without coalescing unrelated fields.
	public static bool value(SemanticType type, CopyabilityFields fields) {
		if (!(type is StructType)) {
			return false;
		}
		var members = fields (type);
		if (members == null || members.length == 0 || members.length > 3) {
			return false;
		}
		for (int i = 0; i < members.length; i++) {
			if (scalar_bytes (members[i]) == 8) {
				continue;
			}
			if (members[i].kind == TypeKind.F32 && (members.length == 1 || (i == 0 && members.length == 2 && members[1].kind == TypeKind.F64))) {
				continue;
			}
			return false;
		}
		return true;
	}

	public static bool pointer(SemanticType type, CopyabilityFields fields) {
		if (!(type is TypedPointerType) || !(((TypedPointerType) type).pointee is StructType)) {
			return false;
		}
		var members = fields (((TypedPointerType) type).pointee);
		if (members == null || members.length == 0 || members.length > 32) {
			return false;
		}
		foreach (var member in members) {
			if (scalar_bytes (member) == 0) {
				return false;
			}
		}
		return true;
	}

}
}
