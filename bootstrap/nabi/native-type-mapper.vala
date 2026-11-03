// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;

namespace Astra.NativeAbi {
// The single semantic-to-physical scalar mapping authority. This boundary
// depends on semantic types; the completed model/verifier/dumper do not.
public class NativeTypeMapper : Object {
	internal static NativeContextSliceType? context_buffer_type(SliceType type) throws NativeAbiError {
		if (!(type is ContextBytesType)) {
			return null;
		}
		var mapped = map_type (type);
		return mapped as NativeContextSliceType;
	}

	public static NativeStructValueMode record_mode(StructValueMode mode) {
		return mode == StructValueMode.COPY_VALUE ? NativeStructValueMode.COPY_VALUE :
		       mode == StructValueMode.MOVE_VALUE ? NativeStructValueMode.MOVE_VALUE : NativeStructValueMode.BORROW_VALUE;
	}

	public static GenericArray<NativeStructLeafChannel> map_record_leaves(StructValueShape shape) throws NativeAbiError {
		var leaves = new GenericArray<NativeStructLeafChannel> ();
		foreach (var leaf in shape.leaves) {
			if (leaf.semantic_type is SliceType) {
				if (shape.mode == StructValueMode.COPY_VALUE) {
					throw new NativeAbiError.INVALID_TYPE ("record buffer requires its exact owning callable group");
				}
				leaves.add (new NativeStructLeafChannel (leaf.spelling () + "@base", new NativeScalarAbiType (NativeScalarType.PTR), leaf.spelling (), 0));
				leaves.add (new NativeStructLeafChannel (leaf.spelling () + "@length", new NativeScalarAbiType (NativeScalarType.I32), leaf.spelling (), 1));
			} else {
				var buffer = leaf as StructBufferLeafPath;
				leaves.add (new NativeStructLeafChannel (leaf.spelling (), map_parameter (leaf.semantic_type, PointerParameterContract.UNMANAGED, null, shape.mode != StructValueMode.COPY_VALUE), leaf.storage_path ().spelling (), buffer == null ? -1 : buffer.component));
			}
		}
		return leaves;
	}

	public static GenericArray<NativeCallableRecordParameter> map_function_records(GenericArray<StructBoundaryGroup> groups) throws NativeAbiError {
		var result = new GenericArray<NativeCallableRecordParameter> ();
		int expansion = 0;
		foreach (var group in groups) {
			if (group.shape.mode != StructValueMode.COPY_VALUE && group.shape.mode != StructValueMode.MOVE_VALUE && group.shape.mode != StructValueMode.BORROW_VALUE) {
				throw new NativeAbiError.INVALID_TYPE ("function record channel requires its exact copied or owning mode");
			}
			var leaves = map_record_leaves (group.shape);
			result.add (new NativeCallableRecordParameter (group.source_ordinal, group.first_leaf + expansion, group.shape.semantic_type.display_name (), leaves, record_mode (group.shape.mode)));
			expansion += (int) leaves.length - (int) group.shape.leaves.length;
		}
		return result;
	}

	public static NativeSharedHandleType map_shared_operation(SemanticType type) throws NativeAbiError {
		if (type is ClosureHandleType && ((ClosureHandleType) type).actor) {
			return new NativeSharedHandleType (((ClosureHandleType) type).environment_type.name, false, false, (NativeClosureHandleType) map_type (type));
		}
		if (type is ClassType && ((ClassType) type).intrinsically_shared) {
			return new NativeSharedHandleType (((ClassType) type).name, false, true);
		}
		var mapped = map_type (type) as NativeSharedHandleType;
		if (mapped == null) {
			throw new NativeAbiError.INVALID_TYPE ("shared operation requires its declared lifetime carrier");
		}
		return mapped;
	}

	public static NativeAbiType map_parameter(SemanticType type, PointerParameterContract contract, NativeRecordElement? record = null, bool record_class_leaf = false) throws NativeAbiError {
		if (type is EnumType) {
			if (contract != PointerParameterContract.UNMANAGED) {
				throw new NativeAbiError.INVALID_TYPE ("copyable enum input requires an unmanaged snapshot contract");
			}
			return new NativeSumType (((EnumType) type).identity);
		}
		if (type is StringType) {
			if (contract != PointerParameterContract.BORROWED_NOESCAPE) {
				throw new NativeAbiError.INVALID_TYPE ("native text parameter requires borrowed-noescape");
			}
			return new NativeTextType (NativeTextContract.BORROWED_NOESCAPE);
		}
		if (type is ClassType) {
			if (contract != PointerParameterContract.BORROWED_NOESCAPE && contract != PointerParameterContract.OWNED_TRANSFER && !(contract == PointerParameterContract.UNMANAGED && record_class_leaf)) {
				throw new NativeAbiError.INVALID_TYPE ("native object parameter requires borrowed-noescape, owned-transfer or an exact MOVE_VALUE leaf");
			}
			return new NativeScalarAbiType (NativeScalarType.PTR);
		}
		var slice = type as SliceType;
		if (slice != null) {
			if (contract != PointerParameterContract.BORROWED_NOESCAPE || !SliceType.supports (slice.element_type)) {
				throw new NativeAbiError.INVALID_TYPE ("native slice parameter requires an exact supported SliceType and borrowed-noescape contract");
			}
			if (slice is ContextBytesType) {
				return map_type (slice);
			}
			if (slice.element_type is StructType) {
				if (record == null) {
					throw new NativeAbiError.INVALID_TYPE ("record slice requires its exact independent element storage plan");
				}
				return new NativeRecordSliceType (record);
			}
			if (slice.deep_borrow) {
				return new NativeTextSliceType ();
			}
			var element = map_type (slice.element_type) as NativeScalarAbiType;
			return element == null ? new NativeSliceType () : new NativeSliceType.borrowed (element);
		}
		return map_type (type);
	}

	private static NativeAbiType callable_parameter_type(SemanticType type, int ordinal, GenericArray<StructBoundaryGroup> records) throws NativeAbiError {
		foreach (var group in records) {
			if (ordinal >= group.first_leaf && ordinal < group.first_leaf + group.shape.leaves.length) {
				return map_parameter (type, PointerParameterContract.UNMANAGED, null, group.shape.mode == StructValueMode.MOVE_VALUE);
			}
		}
		return map_type (type);
	}

	private static GenericArray<NativeCallableOwnedChannel> owned_callable_channels(CallableSignature signature) throws NativeAbiError {
		var result = new GenericArray<NativeCallableOwnedChannel> ();
		GenericArray<SemanticType> physical;
		if (signature is FunctionValueType) {
			physical = ((FunctionValueType) signature).physical_parameters ();
		} else {
			physical = ((ClosureHandleType) signature).physical_parameters ();
		}
		var contracts = signature.physical_contracts ();
		int ordinal = 0;
		for (int p = 0; p < physical.length; p++) {
			int current = ordinal;
			if (physical[p] is SliceType) {
				ordinal += 2;
			} else {
				ordinal++;
			}
			if (contracts[p] != PointerParameterContract.OWNED_TRANSFER) {
				continue;
			}
			if (!(physical[p] is ClassType) && physical[p].get_type () != typeof (HandleType)) {
				throw new NativeAbiError.INVALID_TYPE ("owned callable channel requires its complete nominal Class or Resource contract");
			}
			result.add (new NativeCallableOwnedChannel (current, physical[p].display_name (), physical[p] is ClassType));
		}
		return result;
	}

	private static NativeScalarType? callable_result_scalar(CallableSignature signature, SemanticType type) throws NativeAbiError {
		if (type.kind == TypeKind.VOID || type.is_struct_storage ()) {
			return null;
		}
		if (signature.result_contract == ResultOwnershipContract.OWNED_TRANSFER && type is ClassType) {
			return NativeScalarType.PTR;
		}
		return map_scalar (type);
	}

	private static NativeCallableRecordResult? callable_record_result(CallableSignature signature) throws NativeAbiError {
		var shape = signature.record_result;
		return shape == null ? null : new NativeCallableRecordResult (shape.semantic_type.display_name (), map_record_leaves (shape), shape.mode == StructValueMode.MOVE_VALUE ? NativeStructValueMode.MOVE_VALUE : NativeStructValueMode.COPY_VALUE);
	}

	private static NativeCallableOwnedChannel? owned_callable_result(CallableSignature signature, SemanticType type) throws NativeAbiError {
		if (signature.result_contract == ResultOwnershipContract.UNMANAGED) {
			return null;
		}
		if (signature.result_contract != ResultOwnershipContract.OWNED_TRANSFER || (type.get_type () != typeof (HandleType) && !(type is ClassType))) {
			throw new NativeAbiError.INVALID_TYPE ("callable result requires its exact supported owned Class or Resource identity");
		}
		return new NativeCallableOwnedChannel (-1, type.display_name (), type is ClassType);
	}

	public static NativeAbiType map_type(SemanticType type) throws NativeAbiError {
		if (type is ContextBytesType) {
			var bytes = (ContextBytesType) type;
			if (!bytes.valid ()) {
				throw new NativeAbiError.INVALID_TYPE ("context byte pair lost its owned allocator contract");
			}
			return new NativeContextSliceType ((NativeContextHandleType) map_type (bytes.allocator_type));
		}
		if (type is CallbackType) {
			var callback = (CallbackType) type;
			if (!callback.supported () || callback.is_parameterized ()) {
				throw new NativeAbiError.INVALID_TYPE ("Callback requires a complete copied scalar/void signature");
			}
			var parameters = new GenericArray<NativeAbiType> ();
			foreach (var parameter in callback.parameter_types) {
				parameters.add (map_type (parameter));
			}
			NativeScalarType? result = null;
			if (callback.result_type.kind != TypeKind.VOID) {
				result = map_scalar (callback.result_type);
			}
			return new NativeCallbackType (result, parameters, callback.result_type.kind == TypeKind.VOID);
		}
		if (type is HandleType && ((HandleType) type).context_mode != "") {
			var context = (HandleType) type;
			var result = new NativeContextHandleType (context.name, context.context_mode, context.context_cleanup);
			if (!result.valid ()) {
				throw new NativeAbiError.INVALID_TYPE ("allocator context lost its exact nominal lifetime/thread/release ABI");
			}
			return result;
		}
		if (type is ClosureHandleType) {
			var closure = (ClosureHandleType) type;
			var parameters = new GenericArray<NativeAbiType> ();
			var borrows = new GenericArray<NativeCallableBorrowChannel> ();
			var physical = closure.physical_parameters ();
			var contracts = closure.physical_contracts ();
			for (int p = 0; p < physical.length; p++) {
				var parameter = physical[p];
				int ordinal = (int) parameters.length;
				if (parameter is SliceType) {
					parameters.add (new NativeScalarAbiType (NativeScalarType.PTR));
					parameters.add (new NativeScalarAbiType (NativeScalarType.I32));
					continue;
				}
				bool borrowed = contracts[p] == PointerParameterContract.BORROWED_NOESCAPE;
				if (closure.actor && parameter is ClassType || borrowed || contracts[p] == PointerParameterContract.OWNED_TRANSFER && parameter is ClassType) {
					parameters.add (new NativeScalarAbiType (NativeScalarType.PTR));
				} else {
					parameters.add (callable_parameter_type (parameter, p, closure.record_parameters));
				}
				if (borrowed && !CallableRecordGroups.borrowed_record_leaf (closure.record_parameters, p)) {
					borrows.add (new NativeCallableBorrowChannel (ordinal, parameter.display_name (), parameter is ClassType));
				}
			}
			return new NativeClosureHandleType (closure.environment_type.name, new NativeFunctionPointerType (callable_result_scalar (closure, closure.result_type), parameters, map_function_records (closure.record_parameters), borrows, owned_callable_channels (closure), owned_callable_result (closure, closure.result_type), callable_record_result (closure), closure.result_type.kind == TypeKind.VOID), closure.throws_type == null ? null : closure.throws_type.name, closure.threaded, closure.actor, (closure.actor_message is ClassType) ? ((ClassType) closure.actor_message).name : null);
		}
		if (type is SharedHandleType) {
			var handle = (SharedHandleType) type;
			return new NativeSharedHandleType (handle.payload_type.name, handle.is_weak, handle.payload_type.intrinsically_shared);
		}
		if (type is FunctionValueType) {
			var signature = (FunctionValueType) type;
			var parameters = new GenericArray<NativeAbiType> ();
			var borrows = new GenericArray<NativeCallableBorrowChannel> ();
			var physical = signature.physical_parameters ();
			var contracts = signature.physical_contracts ();
			for (int p = 0; p < physical.length; p++) {
				int ordinal = (int) parameters.length;
				if (physical[p] is SliceType) {
					parameters.add (new NativeScalarAbiType (NativeScalarType.PTR));
					parameters.add (new NativeScalarAbiType (NativeScalarType.I32));
					continue;
				}
				if (contracts[p] == PointerParameterContract.BORROWED_NOESCAPE || contracts[p] == PointerParameterContract.OWNED_TRANSFER && physical[p] is ClassType) {
					parameters.add (new NativeScalarAbiType (NativeScalarType.PTR));
				} else {
					parameters.add (callable_parameter_type (physical[p], p, signature.record_parameters));
				}
				if (contracts[p] == PointerParameterContract.BORROWED_NOESCAPE && !CallableRecordGroups.borrowed_record_leaf (signature.record_parameters, p)) {
					if (!(physical[p] is ClassType) && physical[p].get_type () != typeof (HandleType)) {
						throw new NativeAbiError.INVALID_TYPE ("borrowed function channel requires an exact nominal Class or Resource");
					}
					borrows.add (new NativeCallableBorrowChannel (ordinal, physical[p].display_name (), physical[p] is ClassType));
				}
			}
			return new NativeFunctionPointerType (callable_result_scalar (signature, signature.result_type), parameters, map_function_records (signature.record_parameters), borrows, owned_callable_channels (signature), owned_callable_result (signature, signature.result_type), callable_record_result (signature), signature.result_type.kind == TypeKind.VOID);
		}
		if (type is ExecutorType) {
			return new NativeExecutorHandleType (((ExecutorType) type).identity);
		}
		if (type is TaskType) {
			var task = (TaskType) type;
			return new NativeTaskHandleType (task.identity, task.success_type.kind == TypeKind.VOID ? null : (task.success_type is ContextBytesType) ? map_type (task.success_type) : (task.success_type is SliceType) ? (NativeAbiType) new NativeSliceType () : task.success_type.is_struct_storage () ? (NativeAbiType) new NativeTaskRecordSuccessType (task.identity, task.success_type.nominal_name ()) : map_type (task.success_type), task.success_mode == ResultOwnershipContract.OWNED_TRANSFER);
		}
		if (type is EnumType) {
			return new NativeSumType (((EnumType) type).identity);
		}
		var vector = type as VectorType;
		if (vector != null) {
			if (!VectorType.supports (vector.element_type, vector.lane_count)) {
				throw new NativeAbiError.INVALID_TYPE ("internal native ABI mapping error: unsupported vector shape");
			}
			return new NativeVectorType (map_scalar (vector.element_type), vector.lane_count);
		}
		return new NativeScalarAbiType (map_scalar (type));
	}

	public static NativeScalarType map_scalar(SemanticType type) throws NativeAbiError {
		switch (type.kind) {
		case TypeKind.HANDLE:
		case TypeKind.TYPED_POINTER:
		case TypeKind.RAW_POINTER:
			return NativeScalarType.PTR;
		case TypeKind.I8: return NativeScalarType.I8;
		case TypeKind.U8: return NativeScalarType.U8;
		case TypeKind.I16: return NativeScalarType.I16;
		case TypeKind.U16:
			return NativeScalarType.U16;
		case TypeKind.U32:
			return NativeScalarType.U32;
		case TypeKind.ISIZE:
		case TypeKind.I64:
			return NativeScalarType.I64;
		case TypeKind.USIZE:
		case TypeKind.U64:
			return NativeScalarType.U64;
		case TypeKind.F32:
			return NativeScalarType.F32;
		case TypeKind.F64:
			return NativeScalarType.F64;
		case TypeKind.INT:
			return NativeScalarType.I32;
		case TypeKind.BOOL:
			return NativeScalarType.B1;
		case TypeKind.VOID:
			throw new NativeAbiError.INVALID_TYPE ("internal native ABI mapping error: void is not a direct scalar channel type");
		default:
			throw new NativeAbiError.INVALID_TYPE ("internal native ABI mapping error: unsupported semantic type");
		}
	}

	public static NativeResult? map_result(SemanticType type, ResultOwnershipContract contract = ResultOwnershipContract.UNMANAGED) throws NativeAbiError {
		if (type is EnumType) {
			if (contract != ResultOwnershipContract.UNMANAGED) {
				throw new NativeAbiError.INVALID_TYPE ("copyable enum result requires caller storage without ownership transfer");
			}
			return null;
		}
		if (type is StringType) {
			if (contract != ResultOwnershipContract.STATIC_TEXT && contract != ResultOwnershipContract.RECEIVER_TEXT) {
				throw new NativeAbiError.INVALID_TYPE ("native text result requires static-text");
			}
			return new NativeResult.typed (new NativeTextType (contract == ResultOwnershipContract.RECEIVER_TEXT ? NativeTextContract.RECEIVER_TEXT : NativeTextContract.STATIC_TEXT));
		}
		if (contract == ResultOwnershipContract.RECEIVER_BORROW) {
			if (!(type is ClassType || type is HandleType)) {
				throw new NativeAbiError.INVALID_TYPE ("receiver borrow requires an exact Class or Resource type");
			}
			return new NativeResult (NativeScalarType.PTR);
		}
		if (type is ClassType && contract != ResultOwnershipContract.OWNED_TRANSFER) {
			throw new NativeAbiError.INVALID_TYPE ("ClassType result requires owned-transfer contract and caller-provided storage");
		}
		if (type is ClassType) {
			return new NativeResult (NativeScalarType.PTR);
		}
		return type.kind == TypeKind.VOID ? null : new NativeResult.typed (map_type (type));
	}

}
}
