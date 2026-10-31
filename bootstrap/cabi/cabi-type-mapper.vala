// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;

namespace Astra.CAbi {
// The single semantic-to-physical scalar mapping authority. This boundary
// depends on semantic types; the completed model/verifier/dumper do not.
public class CAbiTypeMapper : Object {
	public static CAbiScalarType map_scalar(SemanticType type, Astra.Foreign.CBoolAbi bool_abi = Astra.Foreign.CBoolAbi.NONE) throws CAbiError {
		if (type is ClosureHandleType) {
			throw new CAbiError.INVALID_TYPE ("native Closure/CheckedClosure code/environment authority cannot cross a raw C ABI channel");
		}
		if (type is SharedHandleType) {
			throw new CAbiError.INVALID_TYPE ("Shared/Weak native lifetime authority cannot cross the C ABI");
		}
		switch (type.kind) {
		case TypeKind.F32:
			return CAbiScalarType.F32;
		case TypeKind.F64:
			return CAbiScalarType.F64;
		case TypeKind.HANDLE:
			return CAbiScalarType.PTR;
		case TypeKind.TYPED_POINTER:
			throw new CAbiError.INVALID_TYPE (type.is_struct_pointer () ? "internal C ABI mapping error: typed native struct pointers are unsupported" : "internal C ABI mapping error: typed data pointers are unsupported");
		case TypeKind.RAW_POINTER:
			if (!type.is_void_pointer ()) {
				throw new CAbiError.INVALID_TYPE ("internal C ABI mapping error: typed native struct pointers are unsupported");
			}
			return CAbiScalarType.PTR;
		case TypeKind.INT:
			return CAbiScalarType.I32;
		case TypeKind.I64:
		case TypeKind.ISIZE:
			return CAbiScalarType.I64;
		case TypeKind.U64:
		case TypeKind.USIZE:
			return CAbiScalarType.U64;
		case TypeKind.BOOL:
			if (bool_abi == Astra.Foreign.CBoolAbi.C99) {
				return CAbiScalarType.CBOOL;
			}
			throw new CAbiError.INVALID_TYPE ("internal C ABI mapping error: foreign bool is unsupported");
		case TypeKind.VOID:
			throw new CAbiError.INVALID_TYPE ("internal C ABI mapping error: void is not a direct scalar channel type");
		default:
			throw new CAbiError.INVALID_TYPE ("internal C ABI mapping error: unsupported semantic type");
		}
	}

	public static bool matches_parameter(SemanticType type, CAbiParameter parameter, Astra.Foreign.CBoolAbi bool_abi = Astra.Foreign.CBoolAbi.NONE) throws CAbiError {
		if (parameter.i32_pointer) {
			return CPlainRecordTypes.i32_pointer (type) && parameter.scalar_type == CAbiScalarType.PTR && parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && parameter.record == null && parameter.text == null && parameter.buffer == null;
		}
		if (parameter.record != null && parameter.record.by_value) {
			return type is StructType && ((StructType) type).name == parameter.record.name && parameter.pointer_contract == PointerParameterContract.UNMANAGED && parameter.scalar_type == (CAbiScalarType) (-1);
		}
		if (parameter.record != null) {
			return type is TypedPointerType && ((TypedPointerType) type).pointee is StructType && ((StructType) ((TypedPointerType) type).pointee).name == parameter.record.name && parameter.text == null && parameter.buffer == null && parameter.scalar_type == CAbiScalarType.PTR && parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE;
		}
		if (type is StringType) {
			return parameter.text != null && parameter.buffer == null;
		}
		if (type is SliceType) {
			return ((SliceType) type).element_type.kind == TypeKind.U8 && parameter.buffer != null && parameter.text == null;
		}
		return parameter.text == null && parameter.buffer == null && map_scalar (type, bool_abi) == parameter.scalar_type;
	}

	public static CAbiResult? map_result(SemanticType type, Astra.Foreign.CBoolAbi bool_abi = Astra.Foreign.CBoolAbi.NONE) throws CAbiError {
		return type.kind == TypeKind.VOID ? null : new CAbiResult (map_scalar (type, bool_abi));
	}
}
}
