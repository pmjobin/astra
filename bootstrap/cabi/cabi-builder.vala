// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Ssa;
using Astra.Semantic;
using Astra.NativeAbi;

namespace Astra.CAbi {
public class CAbiBuilder : Object {
	internal static CAbiCallbackPlan? callback_plan(SsaProgram source, SsaCFunction imported) throws CAbiError {
		if (imported.metadata.callback == null) {
			return null;
		}
		for (int f = 0; f < source.functions.length; f++) {
			var candidate = source.functions[f];
			if (candidate.name == imported.metadata.callback) {
				return new CAbiCallbackPlan (f, candidate.name);
			}
		}
		throw new CAbiError.INVALID_TYPE ("C callback requires an exact concrete native function");
	}
	internal static CAbiRecordPlan record_plan(SsaProgram program, SemanticType type) throws CAbiError {
		if (!(type is StructType) && (!(type is TypedPointerType) || !(((TypedPointerType) type).pointee is StructType))) {
			throw new CAbiError.INVALID_TYPE ("C record requires an exact native Struct*");
		}
		bool is_value = type is StructType;
		SemanticType record_type = is_value ? type : ((TypedPointerType) type).pointee;
		SsaStruct? declaration = null;
		foreach (var structure in program.structs) {
			if (structure.semantic_type == record_type) {
				declaration = structure;
				break;
			}
		}
		if (declaration == null || declaration.fields.length == 0 || declaration.fields.length > 32) {
			throw new CAbiError.INVALID_TYPE ("C record requires 1..32 scalar fields");
		}
		var fields = new GenericArray<CAbiRecordField> ();
		uint offset = 0;
		uint alignment = 1;
		foreach (var field in declaration.fields) {
			uint bytes = CPlainRecordTypes.scalar_bytes (field.semantic_type);
			if (bytes == 0) {
				throw new CAbiError.INVALID_TYPE ("C record field must be a copied numeric scalar");
			}
			offset = (offset + bytes - 1) / bytes * bytes;
			alignment = uint.max (alignment, bytes);
			fields.add (new CAbiRecordField (field.name, field.semantic_type.display_name (), offset));
			offset += bytes;
		}
		var projection = declaration.representation != null && declaration.representation.is_union ? declaration.representation : null;
		if (projection != null && !is_value) {
			throw new CAbiError.INVALID_TYPE ("C union projection requires by-value transport");
		}
		return new CAbiRecordPlan (declaration.name, fields, (offset + alignment - 1) / alignment * alignment, alignment, type is StructType, projection);
	}
	internal static CAbiResult? result_plan(SsaProgram source, SemanticType type, Astra.Foreign.CBoolAbi bool_abi = Astra.Foreign.CBoolAbi.NONE) throws CAbiError {
		return type.is_struct_storage () ? new CAbiResult.record_value (record_plan (source, type)) : CAbiTypeMapper.map_result (type, bool_abi);
	}
	private static Astra.Source.ForeignValueType retained_signal_signature(SemanticType type) throws CAbiError {
		try {
			var handle = NativeTypeMapper.map_type (type) as NativeClosureHandleType;
			var signature = handle == null ? null : NativeRetainedPlan.signal_callback (handle);
			if (signature == null) {
				throw new CAbiError.INVALID_TYPE ("typed retained signal lost its exact native callback signature");
			}
			return signature;
		} catch (NativeAbiError failure) {
			throw new CAbiError.INVALID_NATIVE_ABI ("typed retained signal: %s", failure.message);
		}
	}
	private static bool wide_type(SemanticType type) {
		return type.kind == TypeKind.I64 || type.kind == TypeKind.U64 || type.kind == TypeKind.ISIZE || type.kind == TypeKind.USIZE;
	}
	public static CAbiProgram build(SsaProgram source, NativeAbiProgram nabi) throws CAbiError {
		try {
			SsaVerifier.verify (source);
		} catch (SsaError error) {
			throw new CAbiError.INVALID_SSA ("internal C ABI planning error: %s", error.message);
		}
		var native_targets = new HashTable<SsaFunction, NativeFunction> (direct_hash, direct_equal);
		try {
			NativeAbiVerifier.verify (nabi);
			if (source.functions.length != nabi.functions.length) {
				throw new CAbiError.INVALID_NATIVE_ABI ("internal C ABI planning error: SSA/NABI function counts differ");
			}
			for (int f = 0; f < source.functions.length; f++) {
				native_targets.insert (source.functions[f], nabi.functions[f]);
			}
			NativeAbiValidator.validate_ssa_calls (source, nabi, native_targets);
		} catch (NativeAbiError error) {
			throw new CAbiError.INVALID_NATIVE_ABI ("internal C ABI planning error: %s", error.message);
		}
		var profile = CAbiProfile.SCALAR_V0;
		foreach (var owner in source.classes) {
			if (owner.foreign_export != null) {
				profile = CAbiProfile.SCALAR_PTR_V1;
			}
		}
		foreach (var function in source.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					if (instruction is SsaRetainedOperation) {
						profile = CAbiProfile.SCALAR_PTR_V1;
					}
				}
			}
		}
		foreach (var function in source.c_functions) {
			if (function.metadata.record_abi == Astra.Foreign.CRecordAbi.NATURAL_LP64) {
				profile = CAbiProfile.SCALAR_PTR_V1;
			}
			if (function.metadata.pointer_abi == Astra.Foreign.CPointerAbi.I32_NOESCAPE && profile < CAbiProfile.SCALAR_PTR_V1) {
				profile = CAbiProfile.SCALAR_PTR_V1;
			}
			if (function.return_type.is_nullable_pointer_value ()) {
				profile = CAbiProfile.SCALAR_PTR_V1;
			}
			foreach (var parameter in function.parameter_types) {
				if (parameter.is_nullable_pointer_value ()) {
					profile = CAbiProfile.SCALAR_PTR_V1;
				}
			}
		}
		foreach (var exported in source.c_exports) {
			if (exported.target.return_type.is_nullable_pointer_value ()) {
				profile = CAbiProfile.SCALAR_PTR_V1;
			}
			foreach (var parameter in exported.target.parameters) {
				if (parameter.semantic_type.is_nullable_pointer_value ()) {
					profile = CAbiProfile.SCALAR_PTR_V1;
				}
			}
		}
		foreach (var cleanup in source.cleanups) {
			if (!cleanup.is_object && !cleanup.is_buffer && cleanup.shared_type == null && cleanup.closure_type == null) {
				profile = CAbiProfile.SCALAR_PTR_V1;
			}
		}
		// Floating channels select the superset after pointer/cleanup discovery.
		foreach (var function in source.c_functions) {
			if (function.return_type is F64Type || function.return_type is F32Type) {
				profile = CAbiProfile.SCALAR_FP_V2;
			}
			foreach (var parameter in function.parameter_types) {
				if (parameter is F64Type || parameter is F32Type) {
					profile = CAbiProfile.SCALAR_FP_V2;
				}
			}
		}
		foreach (var exported in source.c_exports) {
			if (exported.target.return_type is F64Type || exported.target.return_type is F32Type) {
				profile = CAbiProfile.SCALAR_FP_V2;
			}
			foreach (var parameter in exported.target.parameters) {
				if (parameter.semantic_type is F64Type || parameter.semantic_type is F32Type) {
					profile = CAbiProfile.SCALAR_FP_V2;
				}
			}
		}
		foreach (var function in source.c_functions) {
			if (wide_type (function.return_type)) {
				profile = CAbiProfile.WIDE_INT_V5;
			}
			foreach (var parameter in function.parameter_types) {
				if (wide_type (parameter)) {
					profile = CAbiProfile.WIDE_INT_V5;
				}
			}
		}
		foreach (var exported in source.c_exports) {
			if (wide_type (exported.target.return_type)) {
				profile = CAbiProfile.WIDE_INT_V5;
			}
			foreach (var parameter in exported.target.parameters) {
				if (wide_type (parameter.semantic_type)) {
					profile = CAbiProfile.WIDE_INT_V5;
				}
			}
		}
		foreach (var function in source.c_functions) {
			if (function.metadata.record_abi == Astra.Foreign.CRecordAbi.VALUE_LP64) {
				profile = CAbiProfile.POD_VALUE_V6;
			}
		}
		foreach (var exported in source.c_exports) {
			if (exported.record_abi == Astra.Foreign.CRecordAbi.VALUE_LP64) {
				profile = CAbiProfile.POD_VALUE_V6;
			}
		}
		foreach (var function in source.c_functions) {
			if (function.metadata.bool_abi == Astra.Foreign.CBoolAbi.C99) {
				profile = CAbiProfile.C_BOOL_V7;
			}
		}
		foreach (var exported in source.c_exports) {
			if (exported.bool_abi == Astra.Foreign.CBoolAbi.C99) {
				profile = CAbiProfile.C_BOOL_V7;
			}
		}
		var cleanup_functions = new GenericArray<CAbiCleanupFunction> ();
		var cleanups = new HashTable<SsaCleanupContract, CAbiCleanupFunction> (direct_hash, direct_equal);
		foreach (var source_cleanup in source.cleanups) {
			if (source_cleanup.is_object || source_cleanup.is_buffer || source_cleanup.shared_type != null || source_cleanup.closure_type != null) {
				continue;
			}
			var parameters = new GenericArray<CAbiParameter> ();
			parameters.add (new CAbiParameter (source_cleanup.symbol_span, source_cleanup.symbol_span, "resource", 0, CAbiScalarType.PTR));
			var signature = new CAbiSignature (profile, parameters, null);
			var cleanup = new CAbiCleanupFunction (source_cleanup.external_symbol, source_cleanup.symbol_span, cleanup_functions.length, signature);
			cleanup_functions.add (cleanup);
			cleanups.insert (source_cleanup, cleanup);
		}
		var module_profile = profile;
		var functions = new GenericArray<CAbiFunction> ();
		// Exact identity map, discarded before the completed sidecar escapes.
		var callees = new HashTable<SsaCFunction, CAbiFunction> (direct_hash, direct_equal);
		for (int f = 0; f < source.c_functions.length; f++) {
			var function = source.c_functions[f];
			var parameters = new GenericArray<CAbiParameter> ();
			var callback = callback_plan (source, function);
			var imported_result = result_plan (source, function.return_type, function.metadata.bool_abi);
			int physical_ordinal = (callback == null ? 0 : 1) + (imported_result != null && imported_result.record != null && imported_result.record.memory ? 1 : 0);
			for (int p = 0; p < function.parameter_types.length; p++) {
				var parameter = function.parameters[p];
				if (parameter.semantic_type is StringType) {
					var components = new GenericArray<CAbiTextComponent> ();
					components.add (new CAbiTextComponent (CAbiTextComponentRole.DATA, CAbiScalarType.PTR, physical_ordinal, p));
					components.add (new CAbiTextComponent (CAbiTextComponentRole.BYTE_LENGTH, CAbiScalarType.I32, physical_ordinal + 1, p));
					var text = new CAbiTextParameterPlan (function.metadata.text_abi, CAbiTextRole.IMPORT_PARAMETER, parameter.pointer_contract, components);
					parameters.add (new CAbiParameter.text_view (parameter.span, parameter.name_span, parameter.name, p, physical_ordinal, text, parameter.pointer_contract));
					physical_ordinal += 2;
				} else if (parameter.semantic_type is SliceType) {
					if (((SliceType) parameter.semantic_type).element_type.kind != TypeKind.U8 || function.metadata.buffer_abi != Astra.Foreign.CBufferAbi.U8_I32 || parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
						throw new CAbiError.INVALID_TYPE ("foreign buffer requires exact borrowed u8[] and u8-i32 metadata");
					}
					var components = new GenericArray<CAbiBufferComponent> ();
					components.add (new CAbiBufferComponent (CAbiBufferComponentRole.DATA, CAbiScalarType.PTR, physical_ordinal, p));
					components.add (new CAbiBufferComponent (CAbiBufferComponentRole.BYTE_LENGTH, CAbiScalarType.I32, physical_ordinal + 1, p));
					var buffer = new CAbiBufferParameterPlan (function.metadata.buffer_abi, CAbiBufferRole.IMPORT_PARAMETER, parameter.pointer_contract, components);
					parameters.add (new CAbiParameter.buffer_view (parameter.span, parameter.name_span, parameter.name, p, physical_ordinal, buffer, parameter.pointer_contract));
					physical_ordinal += 2;
				} else if (parameter.semantic_type.is_struct_storage ()) {
					var record = record_plan (source, parameter.semantic_type);
					parameters.add (new CAbiParameter.record_value (parameter.span, parameter.name_span, parameter.name, p, physical_ordinal, record));
					physical_ordinal += record.channel_count;
				} else if (parameter.semantic_type.is_struct_pointer ()) {
					if (function.metadata.record_abi != Astra.Foreign.CRecordAbi.NATURAL_LP64 || parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
						throw new CAbiError.INVALID_TYPE ("C record requires explicit natural-lp64 borrowed Struct*");
					}
					parameters.add (new CAbiParameter.record_view (parameter.span, parameter.name_span, parameter.name, p, physical_ordinal++, record_plan (source, parameter.semantic_type)));
				} else if (CPlainRecordTypes.i32_pointer (parameter.semantic_type)) {
					if (function.metadata.pointer_abi != Astra.Foreign.CPointerAbi.I32_NOESCAPE || parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
						throw new CAbiError.INVALID_TYPE ("C int pointer requires explicit i32-noescape borrowed int*");
					}
					parameters.add (new CAbiParameter.i32_view (parameter.span, parameter.name_span, parameter.name, p, physical_ordinal++));
				} else {
					parameters.add (new CAbiParameter (parameter.span, parameter.name_span, parameter.name, p, CAbiTypeMapper.map_scalar (parameter.semantic_type, function.metadata.bool_abi), parameter.pointer_contract, physical_ordinal++));
				}
			}
			bool has_text = function.metadata.text_abi == Astra.Foreign.CTextAbi.UTF8_I32;
			bool has_buffer = function.metadata.buffer_abi == Astra.Foreign.CBufferAbi.U8_I32;
			var signature_profile = profile;
			if (has_text && signature_profile < CAbiProfile.TEXT_VIEW_V3) {
				signature_profile = CAbiProfile.TEXT_VIEW_V3;
			}
			if (has_buffer && signature_profile < CAbiProfile.BUFFER_VIEW_V4) {
				signature_profile = CAbiProfile.BUFFER_VIEW_V4;
			}
			if (signature_profile > module_profile) {
				module_profile = signature_profile;
			}
			var signature = new CAbiSignature (signature_profile, parameters, imported_result, callback, function.metadata.bool_abi);
			var c_function = new CAbiFunction (function.span, function.name_span, function.name, f, signature, function.metadata, function.owned_cleanup == null ? null : cleanups.lookup (function.owned_cleanup));
			functions.add (c_function);
			callees.insert (function, c_function);
		}
		var exports = new GenericArray<CAbiExport> ();
		foreach (var exported in source.c_exports) {
			var target = exported.target;
			var native_target = native_targets.lookup (target);
			var parameters = new GenericArray<CAbiParameter> ();
			var exported_result = result_plan (source, target.return_type, exported.bool_abi);
			int physical_ordinal = exported_result != null && exported_result.record != null && exported_result.record.memory ? 1 : 0;
			int logical = 0;
			for (int p = 0; p < target.parameters.length;) {
				var parameter = target.parameters[p];
				StructBoundaryGroup? group = null;
				foreach (var candidate in target.struct_parameters) {
					if (candidate.first_leaf == p) {
						group = candidate;
						break;
					}
				}
				if (group != null) {
					var record = record_plan (source, group.shape.semantic_type);
					parameters.add (new CAbiParameter.record_value (parameter.span, parameter.name_span, parameter.name, logical, physical_ordinal, record));
					physical_ordinal += record.channel_count;
					p += (int) group.shape.leaves.length;
				} else {
					parameters.add (new CAbiParameter (parameter.span, parameter.name_span, parameter.name, logical, CAbiTypeMapper.map_scalar (parameter.semantic_type, exported.bool_abi), PointerParameterContract.UNMANAGED, physical_ordinal++));
					p++;
				}
				logical++;
			}
			var signature = new CAbiSignature (profile, parameters, exported_result, null, exported.bool_abi);
			exports.add (new CAbiExport (exported.span, exported.name_span, exported.external_symbol, exported.ordinal, signature, native_target.ordinal));
		}
		var class_adapters = new GenericArray<CAbiClassAdapter> ();
		foreach (var owner in nabi.classes) {
			if (owner.foreign_export != null) {
				class_adapters.add (new CAbiClassAdapter (owner.foreign_export, owner.span, class_adapters.length, owner.ordinal, owner.foreign_constructor, owner.foreign_getter, owner.foreign_setter, owner.foreign_export.declared_api == null ? null : owner.foreign_targets ()));
			}
		}
		var result = new CAbiProgram (source.span, module_profile, functions, exports, cleanup_functions, class_adapters);
		foreach (var root in nabi.class_imports) {
			result.class_import_roots.add (root);
		}
		foreach (var function in nabi.functions) {
			if (function.foreign_import != null) {
				result.class_imports.add (new CAbiForeignImport (function.foreign_import.binding, function.ordinal, function.foreign_import.error_factory));
			}
		}
		for (int f = 0; f < source.functions.length; f++) {
			foreach (var block in source.functions[f].blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var operation = block.instructions[i] as SsaRetainedOperation;
					if (operation != null) {
						result.bind_retained_operation (new CAbiRetainedPlan (f, block.ordinal, i, (int) operation.action, ((ClosureHandleType) operation.callee.semantic_type).environment_type.name, CAbiScalarType.I32, RetainedContracts.signal (operation.action) ? retained_signal_signature (operation.callee.semantic_type) : null));
					}
				}
			}
		}
		foreach (var projection in nabi.callback_views) {
			result.bind_callback_view (projection);
		}
		foreach (var function in nabi.functions) {
			if (function.foreign_signal != null) {
				result.bind_foreign_signal (new CAbiForeignSignal (function.foreign_signal.binding, function.ordinal));
			}
		}
		CAbiVerifier.verify (result);
		// Every identity/signature is complete before any call is inspected.
		CAbiValidator.validate_ssa_calls (source, result, callees);
		CAbiValidator.validate_cleanups (source, result, cleanups);
		CAbiValidator.validate_exports (source, nabi, result, native_targets);
		return result;
	}
}
}
