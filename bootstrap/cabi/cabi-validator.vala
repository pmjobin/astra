// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Ssa;
using Astra.Semantic;
using Astra.NativeAbi;

namespace Astra.CAbi {
// Construction-time compatibility checks, separate from model verification.
// Inputs are verified SSA/CABI and the builder's exact temporary identity map.
internal class CAbiValidator : Object {
	private static bool same_record(CAbiRecordPlan? actual, CAbiRecordPlan? expected) {
		if (actual == null || expected == null) {
			return actual == expected;
		}
		if (actual.projection_identity != expected.projection_identity) {
			return false;
		}
		if (actual.name != expected.name || actual.by_value != expected.by_value || actual.size != expected.size || actual.alignment != expected.alignment || actual.fields.length != expected.fields.length) {
			return false;
		}
		for (int f = 0; f < actual.fields.length; f++) {
			if (actual.fields[f].name != expected.fields[f].name || actual.fields[f].scalar_name != expected.fields[f].scalar_name || actual.fields[f].offset != expected.fields[f].offset) {
				return false;
			}
		}
		return true;
	}

	private static void fail(string path, string message) throws CAbiError {
		throw new CAbiError.INCOMPATIBLE_CALL ("internal C ABI compatibility error at %s: %s", path, message);
	}

	private static bool retained_signal_matches(CAbiRetainedPlan plan, SsaRetainedOperation operation) {
		try {
			var handle = NativeTypeMapper.map_type (operation.callee.semantic_type) as NativeClosureHandleType;
			var signature = handle == null ? null : NativeRetainedPlan.signal_callback (handle);
			return signature != null && plan.signal_callback != null && plan.signal_callback.equal (signature);
		} catch (NativeAbiError failure) {
			return false;
		}
	}

	internal static void validate_ssa_calls(SsaProgram source, CAbiProgram program, HashTable<SsaCFunction, CAbiFunction> callees) throws CAbiError {
		int retained_count = 0;
		for (int f = 0; f < source.functions.length; f++) {
			foreach (var block in source.functions[f].blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var operation = block.instructions[i] as SsaRetainedOperation;
					if (operation == null) {
						continue;
					}
					retained_count++;
					CAbiRetainedPlan? plan = null;
					foreach (var candidate in program.retained_operations) {
						if (candidate.caller == f && candidate.block == block.ordinal && candidate.instruction == i) {
							plan = candidate;
						}
					}
					if (plan == null || plan.action != (int) operation.action || plan.environment != ((Astra.Semantic.ClosureHandleType) operation.callee.semantic_type).environment_type.name || !Astra.Semantic.RetainedContracts.accepts (operation.action, operation.callee.semantic_type) || Astra.Semantic.RetainedContracts.signal (operation.action) && !retained_signal_matches (plan, operation)) {
						fail ("retained C callback", "exact native environment and finite C adapter action correspondence required");
					}
				}
			}
		}
		if (retained_count != program.retained_operations.length) {
			fail ("retained C callback", "missing or unrelated C adapter plan");
		}
		if (source.c_functions.length != program.functions.length || callees.size () != source.c_functions.length) {
			fail ("program", "function correspondence must be one-to-one");
		}
		for (int f = 0; f < source.c_functions.length; f++) {
			var function = source.c_functions[f];
			string path = "function #%d".printf (f);
			var c_function = callees.lookup (function);
			if (c_function != program.functions[f] || c_function.owner != program || c_function.external_symbol != function.external_symbol) {
				fail (path, "function correspondence must preserve exact identity and source order");
			}
			if (c_function.metadata.bool_abi != function.metadata.bool_abi || c_function.signature.bool_abi != function.metadata.bool_abi) {
				fail (path, "C99 boolean declaration policy differs from exact SSA origin");
			}
			if (c_function.metadata.text_abi != function.metadata.text_abi) {
				fail (path, "text ABI mode does not match SSA declaration");
			}
			if (c_function.metadata.buffer_abi != function.metadata.buffer_abi) {
				fail (path, "buffer ABI mode does not match SSA declaration");
			}
			if (c_function.metadata.record_abi != function.metadata.record_abi) {
				fail (path, "record ABI mode does not match SSA declaration");
			}
			if ((c_function.metadata.com_import == null) != (function.metadata.com_import == null) || c_function.metadata.com_role != function.metadata.com_role || c_function.metadata.com_import != null && c_function.metadata.com_import.identity () != function.metadata.com_import.identity ()) {
				fail (path, "COM import lost exact admitted IID/vtable/role/context identity");
			}
			if (c_function.metadata.pointer_abi != function.metadata.pointer_abi) {
				fail (path, "pointer ABI mode does not match SSA declaration");
			}
			if (c_function.metadata.import_policy != function.metadata.import_policy) {
				fail (path, "foreign declaration policy differs from its admitted SSA origin");
			}
			if (c_function.metadata.callback != function.metadata.callback || c_function.metadata.callback_abi != function.metadata.callback_abi) {
				fail (path, "callback metadata does not match exact SSA declaration");
			}
			var signature = c_function.signature;
			var callback = CAbiBuilder.callback_plan (source, function);
			if ((signature.callback == null) != (callback == null) || (callback != null && (signature.callback.native_function_ordinal != callback.native_function_ordinal || signature.callback.target_name != callback.target_name))) {
				fail (path, "C callback lost exact source function ordinal and identity");
			}
			if (function.parameter_types.length != signature.parameters.length) {
				fail (path, "parameter channel count does not match SSA function");
			}
			for (int p = 0; p < function.parameter_types.length; p++) {
				if (signature.parameters[p].record != null) {
					var actual = signature.parameters[p].record;
					var expected = CAbiBuilder.record_plan (source, function.parameter_types[p]);
					if (actual.projection_identity != expected.projection_identity) {
						fail (path, "C union lost its admitted active member/tag correspondence");
					}
					if (actual.name != expected.name || actual.size != expected.size || actual.alignment != expected.alignment || actual.fields.length != expected.fields.length) {
						fail (path, "C record layout lost exact SSA declaration");
					}
					for (uint field = 0; field < actual.fields.length; field++) {
						if (actual.fields[field].name != expected.fields[field].name || actual.fields[field].scalar_name != expected.fields[field].scalar_name || actual.fields[field].offset != expected.fields[field].offset) {
							fail (path, "C record field lost exact SSA nominal identity/order/type/layout");
						}
					}
				}
				if (function.parameters[p].pointer_contract != signature.parameters[p].pointer_contract) {
					fail (path, "parameter behavioral contract does not match SSA function");
				}
				if (!CAbiTypeMapper.matches_parameter (function.parameter_types[p], signature.parameters[p], function.metadata.bool_abi)) {
					fail (path + "/parameter #%d".printf (p), "parameter channel type does not match SSA function");
				}
			}
			var result = CAbiBuilder.result_plan (source, function.return_type, function.metadata.bool_abi);
			if ((result == null) != (signature.result == null) || (result != null && (result.scalar_type != signature.result.scalar_type || !same_record (result.record, signature.result.record)))) {
				fail (path + "/result", "result channel does not match SSA function");
			}
		}
		for (int f = 0; f < source.functions.length; f++) {
			var function = source.functions[f];
			for (int b = 0; b < function.blocks.length; b++) {
				var block = function.blocks[b];
				for (int i = 0; i < block.instructions.length; i++) {
					var call = block.instructions[i] as SsaCCallInstruction;
					if (call != null) {
						validate_call (call, program, callees, "function #%d/block #%d/instruction #%d".printf (f, b, i));
					}
				}
			}
		}
	}

	internal static void validate_cleanups(SsaProgram source, CAbiProgram program, HashTable<SsaCleanupContract, CAbiCleanupFunction> cleanups) throws CAbiError {
		uint foreign_count = 0;
		foreach (var cleanup in source.cleanups) {
			if (!cleanup.is_object && !cleanup.is_buffer && cleanup.shared_type == null && cleanup.closure_type == null) {
				foreign_count++;
			}
		}
		if (foreign_count != program.cleanups.length || cleanups.size () != foreign_count) {
			fail ("cleanup", "cleanup correspondence must be one-to-one");
		}
		int foreign_ordinal = 0;
		for (int c = 0; c < source.cleanups.length; c++) {
			var source_cleanup = source.cleanups[c];
			if (source_cleanup.is_object || source_cleanup.is_buffer || source_cleanup.shared_type != null || source_cleanup.closure_type != null) {
				if (cleanups.contains (source_cleanup)) {
					fail ("cleanup", "object cleanup must remain native");
				}
				continue;
			}
			var physical = cleanups.lookup (source_cleanup);
			if (physical != program.cleanups[foreign_ordinal++] || physical.owner != program || physical.external_symbol != source_cleanup.external_symbol) {
				fail ("cleanup", "cleanup correspondence must preserve exact identity, symbol and declaration order");
			}
		}
		for (int c = 0; c < source.c_functions.length; c++) {
			var owned_cleanup = source.c_functions[c].owned_cleanup;
			if (program.functions[c].owned_cleanup != (owned_cleanup == null ? null : cleanups.lookup (owned_cleanup))) {
				fail ("owned-result", "producer must retain its exact physical cleanup contract");
			}
		}
		foreach (var function in source.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var cleanup = instruction as SsaCleanupInstruction;
					if (cleanup != null && !cleanup.cleanup.is_object && !cleanup.cleanup.is_buffer && cleanup.cleanup.shared_type == null && cleanup.cleanup.closure_type == null) {
						var physical = cleanups.lookup (cleanup.cleanup);
						if (physical == null || physical.owner != program || CAbiTypeMapper.map_scalar (cleanup.value.semantic_type) != CAbiScalarType.PTR || instruction.result != null) {
							fail ("cleanup", "cleanup instruction must match exact physical PTR -> void authority");
						}
					}
				}
			}
		}
	}

	internal static void validate_exports(SsaProgram source, NativeAbiProgram nabi, CAbiProgram program, HashTable<SsaFunction, NativeFunction> native_targets) throws CAbiError {
		int imported_index = 0;
		foreach (var function in nabi.functions) {
			if (function.foreign_import == null) {
				continue;
			}
			if (imported_index >= program.class_imports.length) {
				fail ("CImport", "missing physical member plan");
			}
			var plan = program.class_imports[imported_index++];
			if (plan.native_function != function.ordinal || plan.error_factory != function.foreign_import.error_factory || plan.binding.identity () != function.foreign_import.binding.identity () || !plan.valid ()) {
				fail ("CImport", "physical member differs from exact native binding");
			}
		}
		if (imported_index != program.class_imports.length) {
			fail ("CImport", "unassociated physical member");
		}
		int adapter_index = 0;
		foreach (var owner in source.classes) {
			if (owner.foreign_export == null) {
				continue;
			}
			if (adapter_index >= program.class_adapters.length || owner.ordinal >= nabi.classes.length) {
				fail ("opaque Class adapter", "missing source/native/C ABI root correspondence");
			}
			var physical = program.class_adapters[adapter_index++];
			var native = nabi.classes[owner.ordinal];
			if (owner.foreign_export.declared_api != null) {
				var api = owner.foreign_export.declared_api;
				if (!physical.valid () || !SsaForeignApi.valid (owner, source) || !NativeForeignApi.valid (nabi, native) || physical.native_class != owner.ordinal || physical.policy.identity () != owner.foreign_export.identity () || native.foreign_export.identity () != physical.policy.identity ()) {
					fail ("declared Class adapter", "lost exact source/native/C ABI correspondence");
				}
				for (uint m = 0; m < api.member_count; m++) {
					var target = SsaForeignApi.target (owner, api.member (m));
					var translated = target == null ? null : native_targets.lookup (target);
					if (translated == null || physical.member_target (m) != translated.ordinal || native.foreign_member (m) != translated.ordinal) {
						fail ("declared Class adapter", "lost exact actual native member target");
					}
				}
				continue;
			}
			var property = owner.properties[owner.foreign_export.property_ordinal];
			if (physical.native_class != owner.ordinal || physical.policy.identity () != owner.foreign_export.identity () || native.foreign_export == null || native.foreign_export.identity () != physical.policy.identity () || physical.constructor != owner.constructor.ordinal || physical.getter != property.getter.ordinal || physical.setter != property.setter.ordinal || physical.constructor != native.foreign_constructor || physical.getter != native.foreign_getter || physical.setter != native.foreign_setter) {
				fail ("opaque Class adapter", "lost exact native root, constructor or property identities");
			}
		}
		if (adapter_index != program.class_adapters.length) {
			fail ("opaque Class adapter", "unassociated physical adapter");
		}
		if (source.c_exports.length != program.exports.length) {
			fail ("program", "export correspondence must be one-to-one");
		}
		for (int e = 0; e < source.c_exports.length; e++) {
			var exported = source.c_exports[e];
			var physical = program.exports[e];
			var target = exported.target;
			var native_target = target == null ? null : native_targets.lookup (target);
			string path = "export #%d".printf (e);
			int ordinal = physical.native_function_ordinal;
			if (native_target == null || native_target.owner != nabi || ordinal < 0 || ordinal >= nabi.functions.length || nabi.functions[ordinal] != native_target || native_target.ordinal != ordinal) {
				fail (path, "export target must identify the exact native function ordinal");
			}
			if (physical.owner != program || physical.ordinal != exported.ordinal || physical.external_symbol != exported.external_symbol) {
				fail (path, "export correspondence must preserve exact identity, symbol and source order");
			}
			var c_signature = physical.signature;
			if (c_signature.bool_abi != exported.bool_abi) {
				fail (path, "C export lost exact admitted boolean ABI authority");
			}
			if (c_signature.has_record != (exported.record_abi == Astra.Foreign.CRecordAbi.VALUE_LP64)) {
				fail (path, "C export lost its explicit source record ABI authority");
			}
			var native_signature = native_target.signature;
			if (native_signature.parameters.length != target.parameters.length) {
				fail (path, "native parameter channels differ from exact SSA leaves");
			}
			try {
				int leaf = 0;
				foreach (var parameter in c_signature.parameters) {
					if (parameter.record != null) {
						StructBoundaryGroup? group = null;
						foreach (var candidate in target.struct_parameters) {
							if (candidate.first_leaf == leaf) {
								group = candidate;
								break;
							}
						}
						if (group == null || group.source_ordinal != parameter.ordinal || !same_record (parameter.record, CAbiBuilder.record_plan (source, group.shape.semantic_type))) {
							fail (path, "C export lost exact native record parameter group");
						}
						leaf += (int) group.shape.leaves.length;
					} else {
						if (leaf >= target.parameters.length || CAbiTypeMapper.map_scalar (target.parameters[leaf].semantic_type, exported.bool_abi) != parameter.scalar_type || NativeTypeMapper.map_scalar (target.parameters[leaf].semantic_type) != native_signature.parameters[leaf].scalar_type) {
							fail (path, "C export lost exact scalar parameter");
						}
						leaf++;
					}
				}
				if (leaf != target.parameters.length) {
					fail (path, "C export has incomplete source leaf coverage");
				}
				var expected_result = CAbiBuilder.result_plan (source, target.return_type, exported.bool_abi);
				if ((expected_result == null) != (c_signature.result == null)) {
					fail (path, "C export result presence differs from source");
				}
				if (expected_result != null) {
					if (expected_result.scalar_type != c_signature.result.scalar_type || !same_record (expected_result.record, c_signature.result.record)) {
						fail (path, "C export result lost exact source type/layout");
					}
					if (expected_result.record != null) {
						if (native_signature.struct_result == null || target.struct_result == null) {
							fail (path, "C export record result lost native group");
						}
					} else if (native_signature.result == null || native_signature.result.scalar_type != NativeTypeMapper.map_scalar (target.return_type)) {
						fail (path, "C export scalar result lost native channel");
					}
				}

			} catch (NativeAbiError error) {
				throw new CAbiError.INVALID_NATIVE_ABI ("internal C ABI compatibility error: %s", error.message);
			}
		}
	}

	internal static CAbiFunction validate_call(SsaCCallInstruction call, CAbiProgram program, HashTable<SsaCFunction, CAbiFunction> callees, string path) throws CAbiError {
		var target = call.target;
		var c_function = target == null ? null : callees.lookup (target);
		if (c_function == null || c_function.owner != program) {
			fail (path, "call target has no exact C import in the program");
		}
		var signature = c_function.signature;
		int leaf = 0;
		int group_index = 0;
		foreach (var parameter in signature.parameters) {
			if (parameter.record != null && parameter.record.by_value) {
				if (group_index >= call.struct_arguments.length) {
					fail (path, "C argument lacks exact record grouping");
				}
				var group = call.struct_arguments[group_index++];
				if (group.first_leaf != leaf || group.source_ordinal != parameter.ordinal || (!(group.shape.semantic_type is Astra.Semantic.StructType) || ((Astra.Semantic.StructType) group.shape.semantic_type).name != parameter.record.name)) {
					fail (path, "C argument lost exact record type/group");
				}
				foreach (var field in group.shape.leaves) {
					if (leaf >= call.arguments.length || call.arguments[leaf++].semantic_type != field.semantic_type) {
						fail (path, "C argument lost exact record leaves");
					}
				}
			} else {
				if (leaf >= call.arguments.length || !CAbiTypeMapper.matches_parameter (call.arguments[leaf++].semantic_type, parameter, signature.bool_abi)) {
					fail (path, "C argument lost exact scalar type");
				}
			}
		}
		if (leaf != call.arguments.length || group_index != call.struct_arguments.length) {
			fail (path, "C argument count/group count differs from signature");
		}
		if (signature.result != null && signature.result.record != null) {
			if (call.result != null || call.struct_result == null || !(call.struct_result.shape.semantic_type is Astra.Semantic.StructType) || ((Astra.Semantic.StructType) call.struct_result.shape.semantic_type).name != signature.result.record.name) {
				fail (path, "C result lost exact record leaf group");
			}
		} else {
			if ((call.result == null) != (signature.result == null) || call.struct_result != null || (call.result != null && CAbiTypeMapper.map_scalar (call.result.semantic_type, signature.bool_abi) != signature.result.scalar_type)) {
				fail (path, "C result differs from exact scalar channel");
			}
		}

		return c_function;
	}

}
}
