// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.CAbi;

namespace Astra.Backend.LLVM {
internal class LlvmCTypeMapper : Object {
	private CApi.ContextRef context;

	internal LlvmCTypeMapper (CApi.ContextRef context) {
		this.context = context;
	}

	internal CApi.TypeRef scalar(CAbiScalarType type) throws LlvmError {
		switch (type) {
		case CAbiScalarType.F32:
			return CApi.float_type_in_context (context);
		case CAbiScalarType.F64:
			return CApi.double_type_in_context (context);
		case CAbiScalarType.PTR:
			return CApi.pointer_type_in_context (context, 0);
		case CAbiScalarType.I32:
			return CApi.int32_type_in_context (context);
		case CAbiScalarType.CBOOL:
			return CApi.int1_type_in_context (context);
		case CAbiScalarType.I64:
		case CAbiScalarType.U64:
			return CApi.int_type_in_context (context, 64);
		default:
			throw new LlvmError.LOWERING ("internal LLVM lowering error: unsupported C ABI scalar type");
		}
	}

	internal CApi.TypeRef field_type(CAbiRecordField field) throws LlvmError {
		if (field.scalar_name == "f32") {
			return CApi.float_type_in_context (context);
		}
		if (field.scalar_name == "f64") {
			return CApi.double_type_in_context (context);
		}
		return CApi.int_type_in_context (context, field.bytes * 8);
	}
	internal CApi.TypeRef record_type(CAbiRecordPlan record) throws LlvmError {
		var fields = new CApi.TypeRef[record.fields.length];
		for (int f = 0; f < fields.length; f++) {
			fields[f] = field_type (record.fields[f]);
		}
		return CApi.struct_type_in_context (context, fields, fields.length, 0);
	}
	internal void attributes(CAbiSignature signature, CApi.ValueRef value, bool call = false) throws LlvmError {
		if (signature.result != null && signature.result.record == null && signature.result.scalar_type == CAbiScalarType.CBOOL) {
			boolean_attribute (value, 0, call);
		}
		foreach (var parameter in signature.parameters) {
			if (parameter.record == null && parameter.text == null && parameter.buffer == null && parameter.scalar_type == CAbiScalarType.CBOOL) {
				boolean_attribute (value, (uint) parameter.physical_ordinal + 1, call);
			}
		}
		if (signature.result != null && signature.result.record != null && signature.result.record.memory) {
			record_attribute (value, 1, "sret", signature.result.record, call);
		}
		foreach (var parameter in signature.parameters) {
			if (parameter.record != null && parameter.record.memory) {
				record_attribute (value, (uint) parameter.physical_ordinal + 1, "byval", parameter.record, call);
			}
		}
	}
	private void boolean_attribute(CApi.ValueRef value, uint index, bool call) {
		var attribute = CApi.create_enum_attribute (context, CApi.enum_attribute_kind ("zeroext", 7), 0);
		if (call) {
			CApi.add_call_attribute (value, index, attribute);
		} else {
			CApi.add_attribute (value, index, attribute);
		}
	}
	private void record_attribute(CApi.ValueRef value, uint index, string name, CAbiRecordPlan record, bool call) throws LlvmError {
		var attribute = CApi.create_type_attribute (context, CApi.enum_attribute_kind (name, name.length), record_type (record));
		var alignment = CApi.create_enum_attribute (context, CApi.enum_attribute_kind ("align", 5), record.alignment);
		if (call) {
			CApi.add_call_attribute (value, index, attribute);
			CApi.add_call_attribute (value, index, alignment);
		} else {
			CApi.add_attribute (value, index, attribute);
			CApi.add_attribute (value, index, alignment);
		}
	}

	internal CApi.TypeRef result_type(CAbiResult? result) throws LlvmError {
		if (result == null || (result.record != null && result.record.memory)) {
			return CApi.void_type_in_context (context);
		}
		if (result.record != null) {
			return result.record.fields.length == 1 ? field_type (result.record.fields[0]) : record_type (result.record);
		}
		return scalar (result.scalar_type);
	}

	internal CApi.TypeRef signature(CAbiSignature signature) throws LlvmError {
		var parameters = new CApi.TypeRef[signature.physical_parameter_count];
		if (signature.result != null && signature.result.record != null && signature.result.record.memory) {
			parameters[0] = scalar (CAbiScalarType.PTR);
		}
		if (signature.callback != null) {
			parameters[0] = scalar (CAbiScalarType.PTR);
		}
		foreach (var parameter in signature.parameters) {
			if (parameter.record != null && parameter.record.by_value) {
				if (parameter.record.memory) {
					parameters[parameter.physical_ordinal] = scalar (CAbiScalarType.PTR);
				} else {
					for (int f = 0; f < parameter.record.fields.length; f++) {
						parameters[parameter.physical_ordinal + f] = field_type (parameter.record.fields[f]);
					}
				}
			} else if (parameter.text != null) {
				foreach (var component in parameter.text.components) {
					parameters[component.physical_ordinal] = scalar (component.scalar_type);
				}
			} else if (parameter.buffer != null) {
				foreach (var component in parameter.buffer.components) {
					parameters[component.physical_ordinal] = scalar (component.scalar_type);
				}
			} else {
				parameters[parameter.physical_ordinal] = scalar (parameter.scalar_type);
			}
		}
		return CApi.function_type (result_type (signature.result), parameters, parameters.length, 0);
	}
}
}
