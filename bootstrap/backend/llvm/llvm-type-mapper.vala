// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.NativeAbi;
using Astra.Semantic;

namespace Astra.Backend.LLVM {
internal class LlvmTypeMapper : Object {
	private CApi.ContextRef context;
	private HashTable<SemanticType, void*> records = new HashTable<SemanticType, void*> (direct_hash, direct_equal);
	internal void bind_storage(SemanticType type, CApi.TypeRef storage) {
		records.insert (type, (void*) storage);
	}
	internal bool uses_text_slices;
	internal bool uses_vectors { get; private set; }
	internal bool uses_f32 { get; private set; }
	internal bool uses_f64 { get; private set; }
	internal bool uses_wide { get; private set; }

	internal LlvmTypeMapper (CApi.ContextRef context) {
		this.context = context;
	}

	internal CApi.TypeRef scalar(NativeScalarType type) throws LlvmError {
		switch (type) {
		case NativeScalarType.F64:
			uses_f64 = true;
			return CApi.double_type_in_context (context);
		case NativeScalarType.F32:
			uses_f32 = true;
			return CApi.float_type_in_context (context);
		case NativeScalarType.PTR:
			return CApi.pointer_type_in_context (context, 0);
		case NativeScalarType.I8:
		case NativeScalarType.U8:
			return CApi.int_type_in_context (context, 8);
		case NativeScalarType.I16:
		case NativeScalarType.U16:
			return CApi.int_type_in_context (context, 16);
		case NativeScalarType.U32:
		case NativeScalarType.I32:
			return CApi.int32_type_in_context (context);
		case NativeScalarType.B1:
			return CApi.int1_type_in_context (context);
		case NativeScalarType.I64:
		case NativeScalarType.U64:
			uses_wide = true;
			return CApi.int_type_in_context (context, 64);
		default:
			throw new LlvmError.LOWERING ("internal LLVM lowering error: unsupported native scalar type");
		}
	}

	internal CApi.TypeRef abi_type(NativeAbiType type) throws LlvmError {
		if (type is NativeOwnerSlotsType) {
			return owner_slots_descriptor ();
		}
		if (type is NativeExecutorHandleType) {
			return scalar (NativeScalarType.PTR);
		}
		if (type is NativeTaskHandleType) {
			return scalar (NativeScalarType.PTR);
		}
		if (type is NativeSumType) {
			return scalar (NativeScalarType.PTR);
		}
		if (type is NativeTextType) {
			return buffer_carrier ();
		}
		if (type is NativeSliceType) {
			throw new LlvmError.LOWERING ("slice ABI groups require parameter component expansion");
		}
		var vector = type as NativeVectorType;
		if (vector != null) {
			uses_vectors = true;
			return CApi.vector_type (scalar (vector.element), vector.lanes);
		}
		return scalar (((NativeScalarAbiType) type).scalar_type);
	}

	internal CApi.TypeRef float_bits_type(BinaryFloatFormat format) {
		return CApi.int_type_in_context (context, format.bit_width ());
	}

	internal CApi.TypeRef integer_type(IntegerType type) {
		if (type.bit_width == 64) {
			uses_wide = true;
		}
		return CApi.int_type_in_context (context, type.bit_width);
	}

	internal CApi.TypeRef storage_type(SemanticType type) throws LlvmError, NativeAbiError {
		var array = type as ArrayType;
		if (type is StructType) {
			if (!records.contains (type)) {
				throw new LlvmError.LOWERING ("record storage requires an exact physical type binding");
			}
			return (CApi.TypeRef) records.lookup (type);
		}
		return array == null ? value_type(type) : CApi.array_type (storage_type (array.element_type), array.length);
	}

	internal CApi.TypeRef value_type(SemanticType type) throws LlvmError, NativeAbiError {
		if (type is OwnerSlotsType) {
			return owner_slots_descriptor ();
		}
		if (type is ExecutorType) {
			return scalar (NativeScalarType.PTR);
		}
		if (type is TaskType) {
			return scalar (NativeScalarType.PTR);
		}
		if (type is ReceiverType || type is ClassType) {
			return scalar (NativeScalarType.PTR);
		}
		if (type is StringType) {
			return text_descriptor ();
		}
		if (type is SliceType) {
			if (type.is_text_slice ()) {
				uses_text_slices = true;
			}
			// One backend value, also reconstructed from native entry components.
			CApi.TypeRef[] fields = {
				CApi.pointer_type_in_context (context, 0), CApi.int32_type_in_context (context)
			};
			return CApi.struct_type_in_context (context, fields, fields.length, 0);
		}
		return abi_type (NativeTypeMapper.map_type (type));
	}

	internal CApi.TypeRef result_type(NativeResult? result) throws LlvmError {
		return result == null ? CApi.void_type_in_context(context) : abi_type (result.abi_type);
	}

	internal CApi.TypeRef owner_slots_descriptor() {
		CApi.TypeRef[] fields = {
			CApi.pointer_type_in_context (context, 0), CApi.int32_type_in_context (context), CApi.int32_type_in_context (context)
		};
		return CApi.struct_type_in_context (context, fields, fields.length, 0);
	}

	internal CApi.TypeRef buffer_carrier() {
		CApi.TypeRef[] components = {
			CApi.pointer_type_in_context (context, 0), CApi.int32_type_in_context (context)
		};
		return CApi.struct_type_in_context (context, components, components.length, 0);
	}

	// The target witness queries this same memory type used for element GEP
	// and paired loads. It is not inferred from a register result's carrier.
	internal CApi.TypeRef text_descriptor() throws LlvmError {
		var shape = new NativeTextDescriptor ();
		CApi.TypeRef[] components = {
			scalar (shape.text.base_type), scalar (shape.text.length_type)
		};
		return CApi.struct_type_in_context (context, components, components.length, 0);
	}

	internal CApi.TypeRef boundary_result_type(NativeSignature signature) throws LlvmError {
		if (signature.exception_plan != null) {
			return scalar (NativeScalarType.PTR);
		}
		return success_result_type (signature);
	}

	internal CApi.TypeRef success_result_type(NativeSignature signature) throws LlvmError {
		if (signature.sum_result != null) {
			return CApi.void_type_in_context (context);
		}
		if (signature.buffer_result != null) {
			return buffer_carrier ();
		}
		var plan = signature.struct_result;
		if (plan == null) {
			return result_type (signature.result);
		}
		return record_carrier_type (plan.leaves);
	}

	private CApi.TypeRef record_carrier_type(GenericArray<NativeStructLeafChannel> leaves) throws LlvmError {
		if (leaves.length == 1) {
			return abi_type (leaves[0].abi_type);
		}
		var fields = new CApi.TypeRef[leaves.length];
		for (int i = 0; i < fields.length; i++) {
			fields[i] = abi_type (leaves[i].abi_type);
		}
		// Backend-only return carrier, independent of Astra struct storage layout.
		return CApi.struct_type_in_context (context, fields, fields.length, 0);
	}

	internal CApi.TypeRef callable_result_type(CallableSignature signature) throws LlvmError, NativeAbiError {
		var mapped = NativeTypeMapper.map_type ((SemanticType) signature);
		var code = (mapped is NativeClosureHandleType) ? ((NativeClosureHandleType) mapped).signature : (NativeFunctionPointerType) mapped;
		return code.void_result ? CApi.void_type_in_context (context) : code.record_result == null ? scalar(code.result_scalar ()) : record_carrier_type (code.record_result.leaves);
	}

	internal CApi.TypeRef signature(NativeSignature signature) throws LlvmError {
		var parameters = new CApi.TypeRef[signature.physical_parameter_count];
		int component = 0;
		if (signature.sum_result != null) {
			parameters[component++] = scalar (NativeScalarType.PTR);
		}
		if (signature.object_result != null) {
			parameters[component++] = scalar (NativeScalarType.PTR);
		}
		if (signature.receiver != null) {
			parameters[component++] = scalar (signature.receiver.scalar_type);
		}
		if (signature.has_exception_success_slot) {
			parameters[component++] = scalar (NativeScalarType.PTR);
		}
		foreach (var parameter in signature.parameters) {
			if (parameter.abi_type is NativeTextType) {
				var text = (NativeTextType) parameter.abi_type;
				parameters[component++] = scalar (text.base_type);
				parameters[component++] = scalar (text.length_type);
				continue;
			}
			var slice = parameter.abi_type as NativeSliceType;
			if (slice != null) {
				parameters[component++] = scalar (slice.base_type);
				parameters[component++] = scalar (slice.length_type);
			} else {
				parameters[component++] = abi_type (parameter.abi_type);
			}
		}
		return CApi.function_type (boundary_result_type (signature), parameters, parameters.length, 0);
	}
}
}
