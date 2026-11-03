// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
// Internal debugging format; deliberately not a public serialization API.
public class SemanticDump : Object {
	private StringBuilder output = new StringBuilder ();
	private bool include_regions;
	private GenericArray<EnumDefinition> enums;

	private EnumDefinition? enum_definition(EnumType type) {
		foreach (var candidate in enums) {
			if (candidate.semantic_type == type) {
				return candidate;
			}
		}
		return null;
	}

	public static string format(CheckedProgram program, bool include_regions = false) {
		if (program.enums.length == 0 && program.functions.length == 0 && program.generic_functions.length == 0 && program.generic_structs.length == 0 && program.c_functions.length == 0 && program.c_exports.length == 0 && program.structs.length == 0 && program.classes.length == 0 && program.constants.length == 0) {
			return "(program)\n";
		}
		var dump = new SemanticDump ();
		dump.enums = program.enums;
		dump.include_regions = include_regions;
		dump.line (0, "(program");
		foreach (var definition in program.enums) {
			dump.line (1, "(enum %s %s".printf (definition.semantic_type.display_name (), EnumValueAuthority.owns (definition, dump.enum_definition) ? "concrete-owning" : "concrete-copyable"));
			for (uint v = 0; v < definition.variant_count; v++) {
				var variant = definition.variant (v);
				dump.line (2, "(variant #%d %s".printf (variant.identity.ordinal, variant.identity.name));
				for (uint f = 0; f < variant.field_count; f++) {
					var field = variant.field (f);
					dump.line (3, "(payload #%d %s : %s)".printf (field.identity.ordinal, field.identity.name, field.semantic_type.display_name ()));
				}
				dump.line (2, ")");
			}
			dump.line (1, ")");
		}
		foreach (var constant in program.constants) {
			dump.line (1, "(const \"%s\" %s)".printf (constant.name, format_expression (constant.value.expression (constant.span))));
		}
		foreach (var checked_struct in program.generic_structs) {
			var definition = checked_struct.definition;
			dump.line (1, "(generic-struct #%d \"%s\"".printf (definition.ordinal, definition.name));
			foreach (var parameter in definition.type_parameters) {
				dump.line (2, "(type-parameter #%d \"%s\" (baseline GEN1_PLAIN_COPY))".printf (parameter.ordinal, parameter.name));
			}
			foreach (var field in definition.fields) {
				dump.line (2, "(generic-field #%d \"%s\" : %s)".printf (field.ordinal, field.name, field.semantic_type.display_name ()));
			}
			dump.line (1, ")");
		}
		foreach (var handle in program.handles) {
			if (handle.c_import != null) {
				dump.line (2, "(CImport declarations-v1 " + handle.c_import.api.identity () + ")");
			}
			if (handle.com_import != null) {
				dump.line (1, "(" + handle.com_import.identity () + ")");
			}
			dump.line (1, "(handle-type #%d \"%s\" (cleanup \"%s\")".printf (handle.ordinal, handle.name.escape (), handle.cleanup.external_symbol.escape ()));
			if (handle.header != null) {
				dump.line (2, "(header \"%s\")".printf (handle.header.name.escape ()));
			}
			dump.line (1, ")");
		}
		foreach (var structure in program.native_instances ()) {
			if (structure is StructSymbol && ((StructSymbol) structure).representation != null && ((StructSymbol) structure).representation.is_union) {
				dump.line (1, ((StructSymbol) structure).representation.dump ());
			}
			dump.line (1, (structure is ClassSymbol) ? "(class #%d \"%s\"".printf (structure.ordinal, structure.name) : "(struct \"%s\"".printf (structure.name));
			if (structure is ClassSymbol && ((ClassSymbol) structure).allocation_policy != null) {
				dump.line (2, ((ClassSymbol) structure).allocation_policy.dump ());
			}
			if (structure is ClassSymbol && ((ClassSymbol) structure).foreign_export != null) {
				dump.line (2, ((ClassSymbol) structure).foreign_export.dump ());
			}
			foreach (var field in structure.fields) {
				if (field.is_private) {
					dump.line (2, "(private-field #%d lexical-declaring-class)".printf (field.ordinal));
				}
				if (field.owns_buffer) {
					dump.line (2, "(field #%d %s : %s owned-buffer cleanup=native-buffer-deallocate)".printf (field.ordinal, field.name, field.semantic_type.display_name ()));
					continue;
				}
				if (field.owned_cleanup != null) {
					dump.line (2, "(field #%d \"%s\" : %s (ownership owned-field) (cleanup %s))".printf (field.ordinal, field.name, field.semantic_type.display_name (), field.owned_cleanup.external_symbol));
					continue;
				}
				dump.line (2, "(field #%d \"%s\" : %s)".printf (field.ordinal, field.name, field.semantic_type.display_name ()));
			}
			foreach (var property in structure.properties) {
				dump.line (2, "(property #%d \"%s\" : %s (member #%d)".printf (property.ordinal, property.name.escape (), property.semantic_type.display_name (), property.member_ordinal));
				if (property.is_lazy) {
					dump.line (3, "(lazy first-success empty/evaluating/ready)");
				}
				if (property.is_owned_lazy) {
					dump.line (3, "(owned-factory %s receiver-borrow-observation)".printf (property.factory.name));
				}
				if (property.is_borrowed) {
					dump.line (3, "(borrowed receiver-owned-field temporary-use)");
				}
				foreach (var body in program.functions) {
					if (body.symbol == property.getter || (property.setter != null && body.symbol == property.setter)) {
						dump.write_function (body, 3);
					}
				}
				dump.line (2, ")");
			}
			foreach (var method in structure.methods) {
				foreach (var body in program.functions) {
					if (body.symbol == method) {
						dump.write_function (body, 2);
					}
				}
			}
			foreach (var body in program.functions) {
				if (body.symbol is LifecycleSymbol && ((LifecycleSymbol) body.symbol).declaring_class == structure) {
					dump.write_function (body, 2);
				}
			}
			for (int i = (int) structure.fields.length - 1; i >= 0; i--) {
				var field = structure.fields[i];
				if (field.owns_buffer) {
					dump.line (2, "(automatic-field-cleanup #%d native-buffer-deallocate after-normal-deinit current-value)".printf (field.ordinal));
				}
				if (field.owned_cleanup != null) {
					dump.line (2, "(automatic-field-cleanup #%d (cleanup %s) after-normal-deinit current-value)".printf (field.ordinal, field.owned_cleanup.external_symbol));
				}
			}
			dump.line (1, ")");
		}
		foreach (var function in program.c_functions) {
			dump.line (1, "(extern-function \"%s\" (abi C) (symbol \"%s\")".printf (function.name.escape (), function.external_symbol.escape ()));
			if (function.metadata.owned_result != null) {
				dump.line (2, "(owned-result (cleanup \"%s\"))".printf (function.metadata.owned_result.cleanup.external_symbol.escape ()));
			}
			if (function.metadata.text_abi != Astra.Foreign.CTextAbi.NONE) {
				dump.line (2, function.metadata.text_abi.dump_suffix ().strip ());
			}
			if (function.metadata.buffer_abi != Astra.Foreign.CBufferAbi.NONE) {
				dump.line (2, function.metadata.buffer_abi.dump_suffix ().strip ());
			}
			if (function.metadata.record_abi != Astra.Foreign.CRecordAbi.NONE) {
				dump.line (2, function.metadata.record_abi.dump_suffix ().strip ());
			}
			if (function.metadata.pointer_abi != Astra.Foreign.CPointerAbi.NONE) {
				dump.line (2, function.metadata.pointer_abi.dump_suffix ().strip ());
			}
			if (function.metadata.bool_abi == Astra.Foreign.CBoolAbi.C99) {
				dump.line (2, "(C99-bool copied explicit zeroext)");
			}
			if (function.metadata.import_policy == Astra.Source.DeclarationPolicyId.GOBJECT_IMPORT) {
				dump.line (2, "(policy GObjectImport typed-C-bridge explicit-header)");
			}
			if (function.metadata.callback != null) {
				dump.line (2, function.metadata.callback_dump_suffix ().strip ());
			}
			if (function.metadata.header_count > 0) {
				dump.line (2, "(headers");
				for (int h = 0; h < function.metadata.header_count; h++) {
					dump.line (3, "\"%s\"".printf (function.metadata.header_at (h).name.escape ()));
				}
				dump.line (2, ")");
			}
			dump.line (2, "(parameters");
			foreach (var parameter in function.parameters) {
				dump.line (3, "(parameter #%d \"%s\" : %s%s)".printf (parameter.ordinal, parameter.name, parameter.semantic_type.display_name (), parameter.pointer_contract.dump_suffix ()));
			}
			dump.line (2, ")");
			dump.line (2, "(result %s))".printf (function.return_type.display_name ()));
		}
		foreach (var exported in program.c_exports) {
			if (exported.bool_abi == Astra.Foreign.CBoolAbi.C99) {
				dump.line (1, "(C99-bool export copied explicit zeroext)");
			}
			var target = exported.target;
			dump.line (1, "(c-export #%d (abi C) (target-function \"%s\") (symbol \"%s\"))".printf (exported.ordinal, target == null ? "<expired>" : target.name.escape (), exported.external_symbol.escape ()));
		}
		foreach (var generic in program.generic_functions) {
			dump.write_function (generic);
		}
		for (int i = 0; i < program.functions.length; i++) {
			if (!(program.functions[i] is CheckedMethod) && !(program.functions[i].symbol is LifecycleSymbol) && !(program.functions[i].symbol is PropertyAccessorSymbol)) {
				dump.write_function (program.functions[i]);
			}
		}
		dump.line (0, ")");
		return dump.output.str;
	}

	private void line(int indentation, string text) {
		for (int i = 0; i < indentation; i++) {
			output.append_c ('\t');
		}
		output.append (text);
		output.append_c ('\n');
	}

	private void write_function(CheckedFunction function, int indentation = 1) {
		if (function.symbol.floating_policy != 0) {
			line (indentation, "(floating-policy permissions=%u checked-domain=bounded)".printf (function.symbol.floating_policy));
		}
		var symbol = function.symbol;
		var method = symbol as MethodSymbol;
		if (symbol is GenericFunctionSymbol) {
			bool has_owners = false;
			foreach (var parameter in ((GenericFunctionSymbol) symbol).type_parameters) {
				if (parameter.transport_mode == GenericTransportMode.OWNABLE) {
					has_owners = true;
				}
			}
			line (indentation, "(generic-definition \"%s\" checked-once%s)".printf (symbol.name, has_owners ? "" : " GEN1_PLAIN_COPY"));
			foreach (var parameter in ((GenericFunctionSymbol) symbol).type_parameters) {
				line (indentation, "(type-parameter #%d %s%s)".printf (parameter.ordinal, parameter.name, parameter.transport_mode == GenericTransportMode.OWNABLE ? " (transport OWNABLE)" : ""));
			}
			foreach (var parameter in ((GenericFunctionSymbol) symbol).type_parameters) {
				if (((GenericFunctionSymbol) symbol).element_obligations.contains (parameter.semantic_type)) {
					line (indentation, "(slice-element #%d %s mutable-storage)".printf (parameter.ordinal, parameter.name));
				}
			}
			foreach (var requirement in ((GenericFunctionSymbol) symbol).capability_requirements) {
				line (indentation, "(requires #%d %s %s)".printf (requirement.type_parameter.ordinal, requirement.type_parameter.name, requirement.capability.name));
			}
		}
		if (symbol is PropertyAccessorSymbol) {
			var accessor = (PropertyAccessorSymbol) symbol;
			line (indentation, "(%s #%d -> %s".printf ((symbol is PropertyGetterSymbol) ? "getter" : "setter", accessor.property_symbol.ordinal, symbol.return_type.display_name ()));
			line (indentation + 1, "(receiver %s live mutable nonnull non-owning)".printf (accessor.receiver.semantic_type.display_name ()));
		} else if (symbol is LifecycleSymbol) {
			var lifecycle = (LifecycleSymbol) symbol;
			line (indentation, "(%s #%d (member #%d)".printf ((symbol is ConstructorSymbol) ? "constructor" : "destructor", lifecycle.ordinal, lifecycle.member_ordinal));
			line (indentation + 1, "(receiver %s %s nonnull mutable)".printf ((symbol is ConstructorSymbol) ? "initializing" : "live", lifecycle.declaring_class.name));
		} else if (method == null) {
			line (indentation + 0, "(function \"%s\" -> %s".printf (symbol.name, symbol.return_type.display_name ()));
		} else {
			line (indentation + 0, "(method #%d \"%s\" (member #%d) -> %s".printf (method.ordinal, symbol.name, method.member_ordinal, symbol.return_type.display_name ()));
			line (indentation + 1, "(receiver %s mutable nonnull non-owning)".printf (method.receiver.semantic_type.display_name ()));
		}
		if (symbol.return_type is TypeParameterType && symbol.result_contract == ResultOwnershipContract.OWNED_TRANSFER) {
			line (indentation + 1, "(result %s (contract owned-transfer) (requires Ownable))".printf (symbol.return_type.display_name ()));
		}
		if (symbol.return_type is SliceType && symbol.result_contract == ResultOwnershipContract.OWNED_TRANSFER) {
			line (indentation + 1, "(result %s (contract owned-transfer) (cleanup native-buffer-deallocate) base+len)".printf (symbol.return_type.display_name ()));
		}
		if (symbol.struct_result_contract != null) {
			line (indentation + 1, "(struct-result %s exact-nominal snapshot)".printf (symbol.struct_result_contract.mode.spelling ()));
		}
		if (symbol.result_storage != null) {
			line (indentation + 1, "(result %s (contract owned-transfer) (storage-mode caller-provided))".printf (symbol.return_type.display_name ()));
		}
		if (symbol.owned_cleanup != null) {
			line (indentation + 1, "(result %s (contract owned-transfer) (cleanup \"%s\"))".printf (symbol.return_type.display_name (), symbol.owned_cleanup.external_symbol));
		}
		if (symbol.parameters.length == 0) {
			line (indentation + 1, "(parameters)");
		} else {
			line (indentation + 1, "(parameters");
			for (int i = 0; i < symbol.parameters.length; i++) {
				var parameter = symbol.parameters[i];
				if (parameter.caller_information != null) {
					line (indentation + 2, "(caller-information #%d%s)".printf (parameter.ordinal, parameter.caller_information.dump_suffix ()));
				}
				if (parameter.struct_value_contract != null) {
					line (indentation + 2, "(struct-parameter #%d %s %sindependent-local)".printf (parameter.ordinal, parameter.struct_value_contract.mode.spelling (), parameter.struct_value_contract.mode == StructValueMode.COPY_VALUE ? "read-only " : ""));
				}
				if (include_regions && parameter.semantic_type.is_typed_pointer ()) {
					line (indentation + 2, "(parameter-borrow #%d region #%d)".printf (parameter.ordinal, parameter.lexical_region.ordinal));
				}
				line (indentation + 2, "(parameter #%d \"%s\" : %s%s)".printf (parameter.ordinal, parameter.name, parameter.semantic_type.display_name (), parameter.pointer_contract.dump_suffix ()));
			}
			line (indentation + 1, ")");
		}
		if (function.locals.length > 0) {
			line (indentation + 1, "(locals");
			for (int i = 0; i < function.locals.length; i++) {
				var local = function.locals[i];
				if (local.object_owner != null) {
					line (indentation + 2, "(ownership (owner #%d) transferable-object (class #%d)%s)".printf (local.ordinal, local.object_owner.ordinal, local.object_storage == null ? (local.incoming_parameter == null ? " nullable-result" : " incoming-parameter") : " (storage #%d)".printf (local.object_storage.ordinal)));
				}
				if (include_regions) {
					line (indentation + 2, "(local-region #%d region #%d%s)".printf (local.ordinal, local.lexical_region.ordinal, local.semantic_type.is_typed_pointer () ? " borrow-required" : ""));
				}
				line (indentation + 2, "(local #%d \"%s\" : %s%s)".printf (local.ordinal, local.name, local.semantic_type.display_name (), local.address_taken ? " address-taken" : ""));
			}
			line (indentation + 1, ")");
		}
		write_statement (function.body, indentation + 1);
		line (indentation + 0, ")");
	}

	private void write_statement(CheckedStatement statement, int indentation) {
		if (statement is CheckedActorSend) {
			var send = (CheckedActorSend) statement;
			line (indentation, "(actor-%d checked=%s %s".printf ((int) send.action, send.error_type.display_name (), format_expression (send.sender)));
			if (send.message != null) {
				line (indentation + 1, "(consume-heap-message " + send.message.name + ")");
			}
			if (send.scalar != null) {
				line (indentation + 1, format_expression (send.scalar));
			}
			line (indentation, ")");
			return;
		}
		if (statement is CheckedTaskAwaitStatement) {
			line (indentation, "(await " + format_expression (((CheckedTaskAwaitStatement) statement).operation) + ")");
			return;
		}
		if (statement is CheckedValueStatement) {
			line (indentation, format_expression (((CheckedValueStatement) statement).value));
			return;
		}
		if (statement is CheckedAsyncOperationStatement) {
			line (indentation, format_expression (((CheckedAsyncOperationStatement) statement).operation));
			return;
		}
		if (statement is CheckedAsyncDelay) {
			line (indentation, (((CheckedAsyncDelay) statement).payload ? "(linux-payload-suspend " : "(virtual-suspend ") + format_expression (((CheckedAsyncDelay) statement).ticks) + ")");
			return;
		}
		if (statement is CheckedTry) {
			var guarded = (CheckedTry) statement;
			line (indentation, "(try");
			write_statement (guarded.body, indentation + 1);
			foreach (var caught in guarded.catches) {
				line (indentation + 1, "(catch %s local#%d".printf (caught.binding.semantic_type.display_name (), caught.binding.ordinal));
				write_statement (caught.body, indentation + 2);
				line (indentation + 1, ")");
			}
			line (indentation, ")");
			return;
		}
		if (statement is CheckedVectorMemoryStatement) {
			line (indentation, format_expression (((CheckedVectorMemoryStatement) statement).operation));
			return;
		}
		if (statement is CheckedThrow) {
			var thrown = (CheckedThrow) statement;
			if (thrown.construction != null) {
				write_statement (thrown.construction, indentation);
			}
			line (indentation, "(%s local#%d : %s)".printf (thrown.rethrows ? "rethrow" : "throw-move", thrown.owner.ordinal, thrown.owner.semantic_type.display_name ()));
			return;
		}

		if (statement is CheckedEnumStore) {
			var store = (CheckedEnumStore) statement;
			line (indentation, "(enum-store local#%d %s %s)".printf (store.destination.ordinal, store.initializes_destination ? "initialize" : "assign", format_enum_producer (store.producer)));
			return;
		}
		if (statement is CheckedEnumReturn) {
			line (indentation, "(enum-return " + format_enum_producer (((CheckedEnumReturn) statement).producer) + ")");
			return;
		}
		if (statement is CheckedEnumMatch) {
			var match = (CheckedEnumMatch) statement;
			line (indentation, "(match-snapshot " + format_enum_producer (match.scrutinee));
			foreach (var arm in match.arms) {
				line (indentation + 1, arm.variant == null ? "(else" : "(case " + arm.variant.identity.name);
				foreach (var binding in arm.bindings) {
					line (indentation + 2, "(bind field#%d %s local#%d)".printf (binding.field.identity.ordinal, binding.field.identity.name, binding.destination.ordinal));
				}
				write_statement (arm.body, indentation + 2);
				line (indentation + 1, ")");
			}
			line (indentation, ")");
			return;
		}
		if (statement is CheckedConstantDeclaration) {
			var constant = ((CheckedConstantDeclaration) statement).constant;
			line (indentation, "(const \"%s\" %s)".printf (constant.name, format_expression (constant.value.expression (constant.span))));
			return;
		}
		if (statement is CheckedOwnedBufferReplace) {
			var replacement = (CheckedOwnedBufferReplace) statement;
			line (indentation, "(owned-buffer-replace (owner #%d) (incoming %s) capture-clean-store)".printf (replacement.owner.ordinal, format_expression (replacement.incoming)));
			return;
		}
		if (statement is CheckedSlotsInitialize) {
			line (indentation, "(owner-slots-empty " + format_place (((CheckedSlotsInitialize) statement).store) + ")");
			return;
		}
		if (statement is CheckedSlotsReplace) {
			var replace = (CheckedSlotsReplace) statement;
			line (indentation, "(owner-slots-replace " + format_place (replace.store) + " " + format_expression (replace.index) + " " + format_expression (replace.incoming) + ")");
			return;
		}
		if (statement is CheckedSlotsAppend) {
			var s = (CheckedSlotsAppend) statement;
			line (indentation, "(owner-slots-append " + format_place (s.store) + " " + format_expression (s.incoming) + ")");
			return;
		}
		if (statement is CheckedOwnedFieldTransfer) {
			var transfer = (CheckedOwnedFieldTransfer) statement;
			line (indentation, "(%s (field %s::%s) (destination %s) (incoming %s))".printf (transfer.initializes ? "owned-field-init" : "owned-field-replace", transfer.field.containing_type.name, transfer.field.name, format_place (transfer.destination), format_expression (transfer.incoming)));
			return;
		}
		if (statement is CheckedSlotsRecordTransfer) {
			var transfer = (CheckedSlotsRecordTransfer) statement;
			line (indentation, "(record-slots-%s %s %s %s)".printf (transfer.index == null ? "append" : "replace", transfer.value.contract.mode.spelling (), format_place (transfer.store), format_struct_producer (transfer.value)));
			return;
		}
		if (statement is CheckedStructReturn) {
			line (indentation, "(struct-return %s snapshot-before-cleanup)".printf (format_struct_producer (((CheckedStructReturn) statement).producer)));
			return;
		}
		if (statement is CheckedStructResultStore) {
			var store = (CheckedStructResultStore) statement;
			line (indentation, "(struct-result-store %s (destination %s) %s)".printf (store.initializes_destination ? "initialize" : "assign", format_place (store.destination), format_struct_producer (store.producer)));
			return;
		}
		var owned_return = statement as CheckedOwnershipReturn;
		if (owned_return != null) {
			if (owned_return.object_owner != null) {
				line (indentation, "(result-provenance %s)".printf (owned_return.provenance.label ()));
			}
			line (indentation, "(ownership-return %s : %s)".printf (owned_return.producer != null ? format_expression (owned_return.producer) : owned_return.transfer == null ? "owned-null" : format_expression (owned_return.transfer), owned_return.semantic_type.display_name ()));
			return;
		}
		if (statement is CheckedStructMove) {
			var move = (CheckedStructMove) statement;
			line (indentation, "(whole-owning-record-move #%d -> #%d)".printf (move.source.ordinal, move.destination.ordinal));
			return;
		}
		if (statement is CheckedRecordTake) {
			var take = (CheckedRecordTake) statement;
			line (indentation, "(record-field-take root=#%d destination=#%d)".printf (take.source.ordinal, take.destination.ordinal));
			return;
		}
		if (statement is CheckedRecordReplace) {
			var replace = (CheckedRecordReplace) statement;
			line (indentation, "(record-field-replace root=#%d)".printf (replace.owner.ordinal));
			return;
		}
		var copy = statement as CheckedStructCopy;
		if (copy != null) {
			line (indentation, "(struct-copy (type %s) %s (destination %s) (source %s) copyable snapshot-before-write)".printf (copy.semantic_type.display_name (), copy.initializes_destination ? "initialize" : "assign", format_place (copy.destination), format_place (copy.source)));
			return;
		}
		var rearm = statement as CheckedOwnershipRearmAssignment;
		if (rearm != null) {
			line (indentation, "(ownership-rearm (owner #%d \"%s\") (producer %s) (cleanup \"%s\"))".printf (rearm.owner.ordinal, rearm.owner.name, format_expression (rearm.incoming), rearm.cleanup.external_symbol.escape ()));
			return;
		}
		var exchange = statement as CheckedOwnedBufferExchange;
		if (exchange != null) {
			line (indentation, "(owned-buffer-exchange %s %s live-slots native-buffer-deallocate)".printf (format_place (exchange.left.place), format_place (exchange.right.place)));
			return;
		}
		var release = statement as CheckedOwnershipRelease;
		if (release != null) {
			if (release.owner.is_buffer_owner) {
				line (indentation, "(owned-buffer-release (owner #%d) native-buffer-deallocate)".printf (release.owner.ordinal));
				return;
			}
			if (release.owner.heap_object) {
				line (indentation, "(owned-object-release (owner #%d) native-object-destroy-and-deallocate)".printf (release.owner.ordinal));
				return;
			}
			line (indentation, "(release (owner #%d \"%s\") (cleanup \"%s\"))".printf (release.owner.ordinal, release.owner.name, release.cleanup.external_symbol.escape ()));
			return;
		}
		if (statement is CheckedBreak || statement is CheckedContinue) {
			var target = (statement is CheckedBreak) ? ((CheckedBreak) statement).target : ((CheckedContinue) statement).target;
			line (indentation, "(%s %s)".printf ((statement is CheckedBreak) ? "break" : "continue", target == null ? "<expired>" : "#%d".printf (target.ordinal)));
			return;
		}
		var loop = statement as CheckedWhile;
		if (loop != null) {
			line (indentation, "(while #%d".printf (loop.target.ordinal));
			line (indentation + 1, "(condition %s)".printf (format_expression (loop.condition)));
			line (indentation + 1, "(body");
			write_statement (loop.body, indentation + 2);
			line (indentation + 1, ")");
			if (loop.step != null) {
				line (indentation + 1, "(step");
				write_statement (loop.step, indentation + 2);
				line (indentation + 1, ")");
			}
			line (indentation, ")");
			return;
		}
		var call = statement as CheckedCallStatement;
		if (call != null) {
			line (indentation, format_call ("call-statement", call.target, call.arguments, call.receiver, (call is CheckedGenericCallStatement) ? ((CheckedGenericCallStatement) call).type_arguments : null));
			return;
		}
		var conditional = statement as CheckedIf;
		if (conditional != null) {
			line (indentation, "(if");
			line (indentation + 1, "(condition %s)".printf (format_expression (conditional.condition)));
			line (indentation + 1, "(then");
			write_statement (conditional.then_body, indentation + 2);
			line (indentation + 1, ")");
			if (conditional.else_body != null) {
				line (indentation + 1, "(else");
				write_statement (conditional.else_body, indentation + 2);
				line (indentation + 1, ")");
			}
			line (indentation, ")");
			return;
		}
		if (statement is CheckedFieldInitialize) {
			var initialization = (CheckedFieldInitialize) statement;
			line (indentation, "(initialize-receiver-field #%d \"%s\" %s)".printf (initialization.target.field.ordinal, initialization.target.field.name, format_expression (initialization.value)));
			return;
		}
		var construction = statement as CheckedObjectConstruction;
		if (construction != null) {
			if (construction.local.object_owner != null) {
				line (indentation, "(local #%d \"%s\" : %s (ownership transferable-owned) (storage #%d))".printf (construction.local.ordinal, construction.local.name, construction.local.semantic_type.display_name (), construction.storage.ordinal));
			}
			line (indentation, "(object-storage #%d (class #%d \"%s\") (region #%d))".printf (construction.storage.ordinal, construction.storage.object_class.ordinal, construction.storage.object_class.name, construction.storage.lexical_region.ordinal));
			line (indentation, "(object-construct (storage #%d) (ref-local #%d \"%s\")".printf (construction.storage.ordinal, construction.local.ordinal, construction.local.name));
			if (construction.local.object_owner != null) {
				line (indentation + 1, "(cleanup transferable-owner #%d null-disarm exact-class #%d after-success)".printf (construction.local.ordinal, construction.storage.object_class.ordinal));
			} else if (construction.storage.destructor != null) {
				line (indentation + 1, "(cleanup destructor #%d storage #%d rank #%d after-success)".printf (construction.storage.destructor.ordinal, construction.storage.ordinal, construction.local.ordinal));
			}
			if (construction is CheckedConstructorObjectInitialization) {
				var invocation = (CheckedConstructorObjectInitialization) construction;
				line (indentation + 1, "(construct constructor #%d".printf (invocation.constructor.ordinal));
				if (invocation.allocation_context != null) {
					line (indentation + 2, "(allocation-context " + format_expression (invocation.allocation_context) + ")");
				}
				foreach (var argument in invocation.arguments) {
					line (indentation + 2, format_expression (argument));
				}
				line (indentation + 1, ")");
			}
			foreach (var initializer in construction.initializers) {
				line (indentation + 1, "(field-init #%d %s)".printf (initializer.field.ordinal, format_expression (initializer.expression)));
			}
			line (indentation + 1, format_expression (construction.reference));
			line (indentation, ")");
			return;
		}
		var aggregate = statement as CheckedStructLocalDeclaration;
		if (aggregate != null) {
			var local = aggregate.local;
			line (indentation, "(struct-local #%d \"%s\" : %s".printf (local.ordinal, local.name, local.semantic_type.display_name ()));
			foreach (var initializer in aggregate.initializers) {
				write_field_initializer (initializer, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		var array = statement as CheckedArrayLocalDeclaration;
		if (array != null) {
			line (indentation, "(array-initialize #%d %s".printf (array.local.ordinal, array.local.semantic_type.display_name ()));
			foreach (var element in array.elements) {
				line (indentation + 1, format_expression (element));
			}
			foreach (var record in array.records) {
				line (indentation + 1, "(record-entry");
				if (record.producer != null) {
					line (indentation + 2, format_struct_producer (record.producer));
				} else {
					foreach (var field in record.initializer.fields) {
						write_field_initializer (field, indentation + 2);
					}
				}
				line (indentation + 1, ")");
			}
			line (indentation, ")");
			return;
		}
		var store = statement as CheckedStore;
		if (store != null) {
			line (indentation, "(store %s %s)".printf (format_place (store.target), format_expression (store.value)));
			return;
		}
		var indirect = statement as CheckedIndirectFieldAssignment;
		if (indirect != null) {
			line (indentation, "(assign-indirect-field %s (field #%d \"%s\" : %s) %s)".printf (format_expression (indirect.pointer), indirect.field.ordinal, indirect.field.name, indirect.field.semantic_type.display_name (), format_expression (indirect.expression)));
			return;
		}
		var field_assignment = statement as CheckedFieldAssignment;
		if (field_assignment != null) {
			line (indentation, "(assign %s %s)".printf (format_field (field_assignment.local, field_assignment.field), format_expression (field_assignment.expression)));
			return;
		}
		if (statement is CheckedLocalDeclaration) {
			var declaration = (CheckedLocalDeclaration) statement;
			var local = declaration.local;
			if (local.is_buffer_owner) {
				line (indentation, "(owned-buffer element=%s owner=local#%d base+len cleanup=native-buffer-deallocate %s)".printf (((SliceType) local.semantic_type).element_type.display_name (), local.ordinal, format_expression (declaration.initializer)));
				return;
			}
			if (local.cleanup != null) {
				line (indentation, "(owned-local #%d \"%s\" : %s (region #%d) (cleanup \"%s\") %s)".printf (local.ordinal, local.name, local.semantic_type.display_name (), local.lexical_region.ordinal, local.cleanup.external_symbol.escape (), format_expression (declaration.initializer)));
				return;
			}
			line (indentation, "(local-init #%d \"%s\" : %s %s)".printf (local.ordinal, local.name, local.semantic_type.display_name (), format_expression (declaration.initializer)));
			return;
		}
		if (statement is CheckedAssignment) {
			var assignment = (CheckedAssignment) statement;
			var local = assignment.target;
			line (indentation, "(assign (local-ref #%d \"%s\" : %s) %s)".printf (local.ordinal, local.name, local.semantic_type.display_name (), format_expression (assignment.expression)));
			return;
		}
		if (statement is CheckedBlockStatement) {
			var block = (CheckedBlockStatement) statement;
			if (include_regions) {
				var parent = block.region.parent;
				line (indentation, "(region #%d parent %s)".printf (block.region.ordinal, parent == null ? "none" : "#%d".printf (parent.ordinal)));
			}
			if (block.statements.length == 0) {
				line (indentation, "(block)");
				return;
			}
			line (indentation, "(block");
			for (int i = 0; i < block.statements.length; i++) {
				write_statement (block.statements[i], indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		if (statement is CheckedForeignSignalReturn) {
			line (indentation, "(native-signal synchronous-return " + ((CheckedForeignSignalReturn) statement).binding.identity () + ")");
			return;
		}
		if (statement is CheckedForeignReturn) {
			line (indentation, "(CImport declarations-v1 status-out checked-return " + ((CheckedForeignReturn) statement).binding.identity () + ")");
			return;
		}
		if (statement is CheckedReturnStatement) {
			var returned = (CheckedReturnStatement) statement;
			line (indentation, returned.expression == null ? "(return)" : "(return %s)".printf (format_expression (returned.expression)));
			return;
		}
		assert_not_reached ();
	}

	private void write_field_initializer(CheckedFieldInitializer field, int indentation) {
		if (field.producer != null) {
			line (indentation, "(initialize-field #%d \"%s\" %s)".printf (field.field.ordinal, field.field.name, format_struct_producer (field.producer)));
			return;
		}
		if (field.initializer == null) {
			line (indentation, "(initialize-field #%d \"%s\" %s)".printf (field.field.ordinal, field.field.name, format_expression (field.expression)));
			return;
		}
		line (indentation, "(initialize-field #%d \"%s\"".printf (field.field.ordinal, field.field.name) + " (storage-initializer");
		foreach (var child in field.initializer.fields) {
			write_field_initializer (child, indentation + 1);
		}
		line (indentation, "))");
	}

	private static string format_field(LocalSymbol local, StructFieldSymbol field) {
		return "(field-ref (local #%d \"%s\" : %s) (field #%d \"%s\" : %s))".printf (local.ordinal, local.name, local.semantic_type.display_name (), field.ordinal, field.name, field.semantic_type.display_name ());
	}

	private static string format_call(string kind, DirectCallableSymbol target, GenericArray<CheckedExpression> arguments, CheckedExpression? receiver = null, GenericArray<SemanticType>? type_arguments = null, SemanticType? result = null) {
		var accessor = target as PropertyAccessorSymbol;
		if (accessor != null) {
			var property = accessor.property_symbol;
			return "(property-%s (property #%d %s::%s) (%s #%d) (receiver %s)%s : %s effectful)".printf ((accessor is PropertyGetterSymbol) ? "get" : "set", property.ordinal, property.declaring_type.name, property.name, (accessor is PropertyGetterSymbol) ? "getter" : "setter", property.ordinal, format_expression (receiver), arguments.length == 0 ? "" : " (value %s)".printf (format_expression (arguments[0])), target.return_type.display_name ());
		}
		string call_kind = type_arguments != null ? "generic-" + kind : target.domain == CallableDomain.METHOD ? "method-" + kind : target.domain == CallableDomain.C ? "c-" + kind : kind;
		var imported = target as CFunctionSymbol;
		string result_name = ((imported != null && imported.metadata.owned_result != null) || (target is FunctionSymbol && ((FunctionSymbol) target).result_contract == ResultOwnershipContract.OWNED_TRANSFER) ? "owned " : "") + (result ?? target.return_type).display_name ();
		var method = target as MethodSymbol;
		string member = method == null ? "" : " (target %s::%s #%d) (receiver %s)".printf (method.declaring_type.name, method.name, method.ordinal, format_expression (receiver));
		if (type_arguments != null) {
			member += " (type-arguments";
			foreach (var type in type_arguments) {
				member += " " + type.display_name ();
			}
			member += ")";
		}
		var text = new StringBuilder ("(%s \"%s\" -> %s%s (arguments".printf (call_kind, target.name, result_name, member));
		for (int i = 0; i < arguments.length; i++) {
			text.append (" " + format_expression (arguments[i]));
		}
		text.append ("))");
		return text.str;
	}

	private static string format_place(CheckedPlace place) {
		var generic = place as CheckedGenericStructFieldPlace;
		if (generic != null) {
			return "(generic-field-place (owner %s) (base %s) (field %s::%s #%d) : %s)".printf (generic.application.display_name (), format_place (generic.aggregate), generic.field.definition.name, generic.field.name, generic.field.ordinal, place.semantic_type.display_name ());
		}
		var local = place as CheckedLocalPlace;
		if (local != null) {
			return "(local-place #%d : %s)".printf (local.local.ordinal, place.semantic_type.display_name ());
		}
		var projection = place as CheckedFieldPlace;
		if (projection != null) {
			return "(field-place (base %s) (field %s::%s #%d) : %s)".printf (format_place (projection.aggregate), projection.field.containing_type.name, projection.field.name, projection.field.ordinal, place.semantic_type.display_name ());
		}
		var object_field = place as CheckedObjectFieldPlace;
		if (object_field != null) {
			return "(object-field-place (base %s) (field #%d \"%s\") : %s null-traps)".printf (format_expression (object_field.reference), object_field.field.ordinal, object_field.field.name, place.semantic_type.display_name ());
		}
		var field = place as CheckedReceiverFieldPlace;
		if (field != null) {
			return "(field-place (receiver %s) (field #%d \"%s\" : %s))".printf (format_expression (field.receiver), field.field.ordinal, field.field.name, field.semantic_type.display_name ());
		}
		var slice = place as CheckedSliceElementPlace;
		if (slice != null) {
			return "(slice-element-place : %s (slice %s) (index %s) runtime-bounds-trap)".printf (slice.semantic_type.display_name (), format_expression (slice.slice), format_expression (slice.index));
		}
		var array = place as CheckedArrayElementPlace;
		if (array != null) {
			return "(array-element-place #%d %s (bounds 0 %d trap) %s)".printf (array.local.ordinal, array.array_type.display_name (), array.array_type.length, format_expression (array.index));
		}
		var dereference = (CheckedDereferencePlace) place;
		return "(dereference-place : %s null-traps %s)".printf (place.semantic_type.display_name (), format_expression (dereference.pointer));
	}

	private static string format_struct_producer(CheckedStructProducer producer) {
		if (producer is CheckedStructInvocationResult) {
			return "(struct-indirect-result " + producer.contract.mode.spelling () + " " + format_expression (((CheckedStructInvocationResult) producer).invocation) + ")";
		}
		if (producer is CheckedStructProjectionProducer) {
			var projection = (CheckedStructProjectionProducer) producer;
			return "(struct-project %s : %s %s)".printf (projection.path.spelling (), producer.semantic_type.display_name (), format_struct_producer (projection.source));
		}
		if (producer is CheckedSlotsRecordRead) {
			var read = (CheckedSlotsRecordRead) producer;
			return "(record-slots-%s %s : %s %s %s)".printf (read.remove ? "take" : "copy", read.contract.mode.spelling (), producer.semantic_type.display_name (), format_place (read.store), format_expression (read.index));
		}
		if (producer is CheckedStructMoveProducer) {
			return "(record-move-value : %s %s)".printf (producer.semantic_type.display_name (), ((CheckedStructMoveProducer) producer).source.name);
		}
		if (producer is CheckedStructAwait) {
			return "(struct-await " + format_expression (((CheckedStructAwait) producer).operation) + ")";
		}
		if (producer is CheckedStructBorrowSnapshot) {
			return "(struct-borrow-snapshot : %s %s)".printf (producer.semantic_type.display_name (), format_place (((CheckedStructBorrowSnapshot) producer).source));
		}
		if (producer is CheckedStructSnapshot) {
			return "(struct-snapshot : %s %s)".printf (producer.semantic_type.display_name (), format_place (((CheckedStructSnapshot) producer).source));
		}
		if (producer is CheckedCStructCallResult) {
			var foreign_call = (CheckedCStructCallResult) producer;
			var text = new StringBuilder ("(c-struct-call-result " + foreign_call.target.name);
			foreach (var argument in foreign_call.arguments) {
				text.append (" " + format_expression (argument));
			}
			text.append (")");
			return text.str;
		}
		var call = (CheckedStructCallResult) producer;
		var text = new StringBuilder ("(struct-call-result ");
		text.append ((call.target == null ? "<expired>" : call.target.name) + " : " + producer.semantic_type.display_name ());
		if (call.type_arguments != null) {
			foreach (var argument in call.type_arguments) {
				text.append (" (type-argument " + argument.display_name () + ")");
			}
		}
		if (call.receiver != null) {
			text.append (" " + format_expression (call.receiver));
		}
		foreach (var argument in call.arguments) {
			text.append (" " + format_expression (argument));
		}
		text.append (")");
		return text.str;
	}

	private static string format_enum_producer(CheckedEnumProducer producer) {
		if (producer is CheckedEnumAwait) {
			return "(enum-await " + format_expression (((CheckedEnumAwait) producer).operation) + ")";
		}
		if (producer is CheckedAsyncRun) {
			return "(run-status " + format_expression (((CheckedAsyncRun) producer).operation) + ")";
		}
		if (producer is CheckedEnumSnapshot) {
			return "(enum-snapshot local#%d : %s)".printf (((CheckedEnumSnapshot) producer).source.ordinal, producer.semantic_type.display_name ());
		}
		var construction = producer as CheckedEnumConstruct;
		if (construction != null) {
			var text = new StringBuilder ("(enum-construct %s.%s".printf (producer.semantic_type.display_name (), construction.variant.identity.name));
			foreach (var field in construction.fields) {
				text.append (" (field#%d ".printf (field.field.identity.ordinal) + (field.scalar != null ? format_expression (field.scalar) : field.record != null ? format_struct_producer (field.record) : format_enum_producer (field.sum)) + ")");
			}
			text.append (")");
			return text.str;
		}
		var call = (CheckedEnumCallResult) producer;
		var text = new StringBuilder ("(enum-call-result " + (call.target == null ? "<expired>" : call.target.name));
		if (call.receiver != null) {
			text.append (" " + format_expression (call.receiver));
		}
		foreach (var argument in call.arguments) {
			text.append (" " + format_expression (argument));
		}
		text.append (")");
		return text.str;
	}

	internal static string format_expression(CheckedExpression expression) {
		if (expression is CheckedStructProjectionValue) {
			var projection = (CheckedStructProjectionValue) expression;
			return "(struct-project %s : %s %s)".printf (projection.path.spelling (), expression.semantic_type.display_name (), format_struct_producer (projection.source));
		}
		if (expression is CheckedLazyObserve) {
			var property = ((CheckedLazyObserve) expression).property_symbol;
			return "(lazy-observe receiver-borrow %s::%s)".printf (property.declaring_type.name, property.name);
		}
		if (expression is CheckedRetainedOperation) {
			var operation = (CheckedRetainedOperation) expression;
			var text = new StringBuilder ("(retained-callback action=%d ".printf ((int) operation.action) + format_expression (operation.callee));
			foreach (var argument in operation.arguments) {
				text.append (" " + format_expression (argument));
			}
			text.append (")");
			return text.str;
		}
		if (expression is CheckedSharedOperation) {
			var operation = (CheckedSharedOperation) expression;
			return "(shared-%s : %s %s)".printf (operation.action.to_string (), expression.semantic_type.display_name (), format_expression (operation.operand));
		}
		if (expression is CheckedClosureBind) {
			var closure = (CheckedClosureBind) expression;
			return "(closure-bind %s environment=%s code=%s%s)".printf (expression.semantic_type.display_name (), closure.source.name, closure.target.name, closure.actor_binding == null ? "" : " " + closure.actor_binding.dump ());
		}
		if (expression is CheckedClosureCall) {
			var call = (CheckedClosureCall) expression;
			var text = new StringBuilder ("(invoke-closure " + format_expression (call.callee));
			foreach (var argument in call.arguments) {
				text.append (" " + format_expression (argument));
			}
			text.append (")");
			return text.str;
		}
		if (expression is CheckedCallbackParameterView) {
			return "(captured-callback-parameter " + ((CheckedCallbackParameterView) expression).source.name + " : " + expression.semantic_type.display_name () + ")";
		}
		if (expression is CheckedFunctionAddress) {
			return "(function-address %s : %s)".printf (((CheckedFunctionAddress) expression).target.name, expression.semantic_type.display_name ());
		}
		if (expression is CheckedFunctionValueCall) {
			return "(invoke-function-value : %s)".printf (expression.semantic_type.display_name ());
		}
		if (expression is CheckedAsyncOperation) {
			var operation = (CheckedAsyncOperation) expression;
			return "(virtual-%s%s%s%s)".printf (operation.contract.kind.to_string (), operation.executor == null ? "" : " " + format_expression (operation.executor), operation.task == null ? "" : " " + format_expression (operation.task), operation.argument == null ? "" : " " + format_expression (operation.argument));
		}
		if (expression is CheckedTaskBorrow) {
			return "(task-borrow local#%d)".printf (((CheckedTaskBorrow) expression).source.ordinal);
		}
		if (expression is CheckedExecutorBorrow) {
			return "(executor-borrow local#%d)".printf (((CheckedExecutorBorrow) expression).source.ordinal);
		}
		if (expression is CheckedTaskAwait) {
			var wait = (CheckedTaskAwait) expression;
			return "(await%s %s)".printf (wait.discard ? " discard-and-drain" : "", format_expression (wait.child)) + (wait.bridge_executor == null ? "" : " (worker-bridge " + format_expression (wait.bridge_executor) + ")");
		}
		if (expression is CheckedTaskMove) {
			return "(task-move local#%d)".printf (((CheckedTaskMove) expression).source.ordinal);
		}
		if (expression is CheckedTaskCreate) {
			var task = (CheckedTaskCreate) expression;
			var text = new StringBuilder ("(task-create cold %s captures".printf (task.target.name));
			if (task.allocation_context != null) {
				text.append (" (frame-context " + format_expression (task.allocation_context) + ")");
			}
			foreach (var argument in task.arguments) {
				text.append (" " + format_expression (argument));
			}
			text.append (")");
			return text.str;
		}
		if (expression is CheckedClassUpcast) {
			var cast = (CheckedClassUpcast) expression;
			return "(class-upcast %s -> %s %s)".printf (cast.source_class.name, cast.target_class.name, format_expression (cast.reference));
		}
		if (expression is CheckedEnumArgument) {
			return "(enum-argument " + format_enum_producer (((CheckedEnumArgument) expression).producer) + ")";
		}
		if (expression is CheckedEnumEquality) {
			var equality = (CheckedEnumEquality) expression;
			return "(enum-%s %s %s)".printf (equality.unequal ? "not-equal" : "equal", format_enum_producer (equality.left), format_enum_producer (equality.right));
		}
		if (expression is CheckedUtf8FactoryExpression) {
			var operation = (CheckedUtf8FactoryExpression) expression;
			return "(utf8-%s parameter#%d : %s)".printf (operation.validates ? "validate" : "certified-copy-input", operation.input.ordinal, expression.semantic_type.display_name ());
		}
		if (expression is CheckedTextExpression) {
			var payload = ((CheckedTextExpression) expression).payload;
			return "(text (bytes %s) (hex %s) : string)".printf (payload.byte_length.to_string (), payload.hex ());
		}
		if (expression is CheckedTextLengthExpression) {
			return "(text-byte-length %s : int)".printf (format_expression (((CheckedTextLengthExpression) expression).receiver));
		}
		if (expression is CheckedConstantReference) {
			return "(constant-ref \"%s\" %s)".printf (((CheckedConstantReference) expression).constant.name, format_expression (((CheckedConstantReference) expression).constant.value.expression (expression.span)));
		}
		if (expression is CheckedOwnedBufferAllocate) {
			var allocation = (CheckedOwnedBufferAllocate) expression;
			var action = allocation.failure_call;
			return "(owned-buffer-allocate element=%s (count %s) zero-initialize%s)".printf (((SliceType) expression.semantic_type).element_type.display_name (), format_expression (allocation.count), action == null ? "" : " (allocator-null " + format_call ("call-statement", action.target, action.arguments, action.receiver, (action is CheckedGenericCallStatement) ? ((CheckedGenericCallStatement) action).type_arguments : null) + " trap-if-returned)");
		}
		if (expression is CheckedOwnedBufferBorrow) {
			var borrow = (CheckedOwnedBufferBorrow) expression;
			return "(owned-buffer-borrow owner=local#%d slice=%s bounded non-owning)".printf (borrow.source.ordinal, expression.semantic_type.display_name ());
		}
		if (expression is CheckedOwnershipMove && ((CheckedOwnershipMove) expression).source.is_buffer_owner) {
			return "(owned-buffer-move owner=local#%d base+len)".printf (((CheckedOwnershipMove) expression).source.ordinal);
		}
		if (expression is CheckedSlotsTake) {
			var take = (CheckedSlotsTake) expression;
			return "(owner-slots-take %s %s unique-heap-owner)".printf (format_place (take.store), format_expression (take.index));
		}
		if (expression is CheckedSlotsValue) {
			var v = (CheckedSlotsValue) expression;
			return "(owner-slots-%s %s %s)".printf (v.action.to_string (), format_place (v.store), v.operand == null ? "" : format_expression (v.operand));
		}
		if (expression is CheckedOwnedFieldBorrow) {
			var borrow = (CheckedOwnedFieldBorrow) expression;
			return "(owned-field-borrow %s temporary-noescape)".printf (format_place (borrow.source));
		}
		if (expression is CheckedStructArgument) {
			var argument = (CheckedStructArgument) expression;
			return argument.parameter == null ? "(struct-argument callable-signature snapshot-at-argument %s)".printf (format_struct_producer (argument.producer)) : "(struct-argument #%d snapshot-at-argument %s)".printf (argument.parameter.ordinal, format_struct_producer (argument.producer));
		}
		var result_construction = expression as CheckedOwnedObjectResultConstruction;
		if (result_construction != null) {
			var text = new StringBuilder ("(return-object-construct (result-storage) (constructor %s::init) (arguments".printf (result_construction.storage.object_class.name));
			foreach (var argument in result_construction.arguments) {
				text.append (" " + format_expression (argument));
			}
			text.append ("))");
			return text.str;
		}
		var object_reference = expression as CheckedObjectReferenceExpression;
		if (object_reference != null) {
			return "(object-ref : %s (storage #%d) (region #%d))".printf (expression.semantic_type.display_name (), object_reference.storage.ordinal, object_reference.storage.lexical_region.ordinal);
		}
		var object_receiver = expression as CheckedObjectReceiverExpression;
		if (object_receiver != null) {
			return "(object-receiver %s : %s null-traps-before-arguments)".printf (format_expression (object_receiver.reference), expression.semantic_type.display_name ());
		}
		if (expression is CheckedThisExpression) {
			return "(this : %s)".printf (expression.semantic_type.display_name ());
		}
		var receiver = expression as CheckedReceiverAddressExpression;
		if (receiver != null && receiver.receiver_place != null) {
			return "(receiver-address %s : %s)".printf (format_place (receiver.receiver_place), receiver.semantic_type.display_name ());
		}
		if (receiver != null) {
			return "(receiver-address (local #%d \"%s\") : %s)".printf (receiver.local.ordinal, receiver.local.name, receiver.semantic_type.display_name ());
		}

		var slice = expression as CheckedSliceFromArrayExpression;
		if (slice != null) {
			return "(slice-from-array (array #%d \"%s\" : %s)%s (region #%d) : %s)".printf (slice.local.ordinal, slice.local.name, slice.array_type.display_name (), slice.start == null ? " full" : " (start " + format_expression (slice.start) + ") (count " + format_expression (slice.count) + ") range-trap", slice.provenance.region_ordinal, slice.semantic_type.display_name ());
		}
		var length = expression as CheckedLengthExpression;
		if (length != null) {
			return length.array == null ? "(slice-length %s : int)".printf (format_expression (length.slice)) : "(array-length (array #%d) %d : int)".printf (length.array.ordinal, ((ArrayType) length.array.semantic_type).length);
		}
		var argument = expression as CheckedOwnedArgument;
		if (argument != null) {
			if (argument.semantic_type is SliceType) {
				return "(owned-buffer-argument (parameter #%d) %s cleanup=native-buffer-deallocate)".printf (argument.parameter.ordinal, format_expression (argument.transfer));
			}
			if (argument.semantic_type is TypeParameterType) {
				return "(owned-transfer-argument (parameter #%d) %s : %s (requires Ownable))".printf (argument.parameter.ordinal, format_expression (argument.transfer), argument.semantic_type.display_name ());
			}
			if (argument.object_owner != null) {
				return "(owned-transfer-argument (parameter #%d) %s : %s (domain object) (class #%d))".printf (argument.parameter.ordinal, argument.transfer == null ? "owned-null" : format_expression (argument.transfer), argument.semantic_type.display_name (), argument.object_owner.ordinal);
			}
			return "(owned-transfer-argument (parameter #%d) %s : %s (cleanup \"%s\"))".printf (argument.parameter.ordinal, argument.transfer == null ? "owned-null" : format_expression (argument.transfer), argument.semantic_type.display_name (), argument.cleanup.external_symbol);
		}
		var borrow = expression as CheckedOwnedBorrowValue;
		if (borrow != null) {
			return "(borrow-owner #%d \"%s\" : %s)".printf (borrow.source.ordinal, borrow.source.name, borrow.semantic_type.display_name ());
		}
		var move = expression as CheckedOwnershipMove;
		if (move != null) {
			if (move.source.is_generic_owner) {
				return "(move (owner #%d) : %s (requires Ownable) (provenance incoming-owner))".printf (move.source.ordinal, move.semantic_type.display_name ());
			}
			if (move.object_owner != null) {
				return "(move (owner #%d) (domain object) (class #%d)%s)".printf (move.source.ordinal, move.object_owner.ordinal, move.object_storage == null ? "" : " (storage #%d)".printf (move.object_storage.ordinal));
			}
			return "(move (local-ref #%d \"%s\") : %s (cleanup \"%s\"))".printf (move.source.ordinal, move.source.name, move.semantic_type.display_name (), move.cleanup.external_symbol.escape ());
		}
		var load = expression as CheckedLoadExpression;
		if (load != null) {
			return "(load %s)".printf (format_place (load.source));
		}
		var address = expression as CheckedAddressOfExpression;
		if (address != null) {
			return "(address-of (local #%d \"%s\" : %s) : %s)".printf (address.local.ordinal, address.local.name, address.local.semantic_type.display_name (), address.semantic_type.display_name ());
		}
		var indirect = expression as CheckedIndirectFieldReference;
		if (indirect != null) {
			return "(indirect-field-ref %s (field #%d \"%s\" : %s))".printf (format_expression (indirect.pointer), indirect.field.ordinal, indirect.field.name, indirect.field.semantic_type.display_name ());
		}
		var field = expression as CheckedFieldReferenceExpression;
		if (field != null) {
			return format_field (field.local, field.field);
		}
		var call = expression as CheckedCallExpression;
		if (call != null) {
			return format_call ("call", call.target, call.arguments, call.receiver, (call is CheckedGenericCall) ? ((CheckedGenericCall) call).type_arguments : null, call.semantic_type) + (call.candidate_storage != null ? " (candidate-storage #%d caller-lifetime)".printf (call.candidate_storage.ordinal) : call.result_storage != null ? " (forward-result-storage)" : "");
		}
		string type_name = expression.semantic_type.display_name ();
		if (expression is CheckedNullPointerExpression) {
			return "(null : %s)".printf (type_name);
		}
		var boolean = expression as CheckedBooleanExpression;
		if (boolean != null) {
			return "(bool %s : %s)".printf (boolean.literal.spelling (), type_name);
		}
		var dot = expression as CheckedVectorDotExpression;
		if (dot != null) {
			return "(%s (source %s) (accumulator %s) (order %s)%s %s %s)".printf (dot.dot_kind.spelling (), dot.source_type.display_name (), dot.destination_type.display_name (), dot.dot_kind.order (), dot.accumulator == null ? "" : " (acc " + format_expression (dot.accumulator) + ")", format_expression (dot.first), format_expression (dot.second));
		}
		var dsp = expression as CheckedDspExpression;
		if (dsp != null) {
			return "(%s (from %s) (to %s) %s%s)".printf (dsp.primitive_kind.spelling (), dsp.source_type.display_name (), dsp.destination_type.display_name (), format_expression (dsp.first), dsp.second == null ? "" : " " + format_expression (dsp.second));
		}
		var capability = expression as CheckedGenericCapabilityOperation;
		if (capability != null) {
			return "(generic-op %s (capability %s) (type-parameter %s) : %s %s%s)".printf (capability.operator_kind.operation_name (), capability.capability.name, capability.type_parameter.name, capability.semantic_type.display_name (), format_expression (capability.left), capability.right == null ? "" : " " + format_expression (capability.right));
		}
		var shift = expression as CheckedIntegerShiftExpression;
		if (shift != null) {
			return "(%s : %s (value %s) (count %s) (valid-range 0 %u) (invalid-count trap))".printf (shift.shift_kind.operation_name (expression.semantic_type), type_name, format_expression (shift.operand), format_expression (shift.count), shift.element_bit_width - 1);
		}
		var numeric_conversion = expression as CheckedNumericConversionExpression;
		if (numeric_conversion != null) {
			return "(numeric-convert (from %s) (to %s) (kind %s) (policy %s) (value %s))".printf (numeric_conversion.source_type.display_name (), numeric_conversion.destination_type.display_name (), numeric_conversion.conversion_kind.spelling (), numeric_conversion.policy.spelling (), format_expression (numeric_conversion.operand));
		}
		var floating_conversion = expression as CheckedFloatConversionExpression;
		if (floating_conversion != null) {
			return "(float-convert (from %s) (to %s) (mode %s) (value %s))".printf (floating_conversion.source_type.display_name (), floating_conversion.destination_type.display_name (), floating_conversion.conversion_kind.mode (), format_expression (floating_conversion.operand));
		}
		var conversion = expression as CheckedIntegerConversionExpression;
		if (conversion != null) {
			return "(%s (from %s) (to %s) (value %s))".printf ((conversion.source_type is VectorType) ? "integer-vector-convert" : "integer-convert", conversion.source_type.display_name (), conversion.destination_type.display_name (), format_expression (conversion.operand));
		}
		var splat = expression as CheckedVectorSplatExpression;
		if (splat != null) {
			var text = new StringBuilder ("(vector-splat : %s".printf (expression.semantic_type.display_name ()));
			text.append_printf (" (lanes %d)", splat.lane_count);
			text.append (" (value " + format_expression (splat.operand) + ")");
			text.append (")");
			return text.str;
		}
		var extract = expression as CheckedVectorExtractExpression;
		if (extract != null) {
			var text = new StringBuilder ("(vector-extract : %s".printf (expression.semantic_type.display_name ()));
			text.append_printf (" (lane %d)", extract.index.ordinal);
			text.append (" (vector " + format_expression (extract.vector) + ")");
			text.append (")");
			return text.str;
		}
		var insert = expression as CheckedVectorInsertExpression;
		if (insert != null) {
			var text = new StringBuilder ("(vector-insert : %s".printf (expression.semantic_type.display_name ()));
			text.append_printf (" (lane %d)", insert.index.ordinal);
			text.append (" (vector " + format_expression (insert.vector) + ")");
			text.append (" (value " + format_expression (insert.replacement) + ")");
			text.append (")");
			return text.str;
		}
		var shuffle = expression as CheckedVectorShuffleExpression;
		if (shuffle != null) {
			var text = new StringBuilder ("(vector-shuffle : %s".printf (expression.semantic_type.display_name ()));
			text.append_printf (" (lanes %s)", shuffle.selectors.spelling ());
			text.append (" (vector " + format_expression (shuffle.vector) + ")");
			text.append (")");
			return text.str;
		}
		if (expression is CheckedVectorMemoryExpression) {
			var memory = (CheckedVectorMemoryExpression) expression;
			return "(vector-memory-%s align=%u view=%s offset=%s%s : %s)".printf (memory.stored == null ? "load" : "store", memory.contract.alignment, format_expression (memory.view), format_expression (memory.offset), memory.stored == null ? "" : " stored=" + format_expression (memory.stored), memory.contract.vector_type.display_name ());
		}
		var select = expression as CheckedVectorSelectExpression;
		if (select != null) {
			var text = new StringBuilder ("(vector-select : %s".printf (expression.semantic_type.display_name ()));
			text.append (" (mask " + format_expression (select.mask) + ")");
			text.append (" (true " + format_expression (select.true_value) + ")");
			text.append (" (false " + format_expression (select.false_value) + ")");
			text.append (")");
			return text.str;
		}
		var vector = expression as CheckedVectorConstructExpression;
		if (vector != null) {
			var text = new StringBuilder ("(vector-init : %s".printf (expression.semantic_type.display_name ()));
			foreach (var lane in vector.lanes) {
				text.append (" " + format_expression (lane));
			}
			text.append (")");
			return text.str;
		}
		var reduction = expression as CheckedVectorReductionExpression;
		if (reduction != null) {
			return "(vector-%s : bool %s)".printf (reduction.operator_kind.spelling (), format_expression (reduction.operand));
		}
		if (expression is CheckedFloatExpression) {
			return "(%s %s : %s)".printf (((CheckedFloatExpression) expression).value.format.spelling (), ((CheckedFloatExpression) expression).value.to_string (), expression.semantic_type.display_name ());
		}
		if (expression is CheckedIntegerExpression) {
			return "(integer %s : %s)".printf (((CheckedIntegerExpression) expression).value.to_string (), type_name);
		}
		if (expression is CheckedParameterReferenceExpression) {
			var parameter = ((CheckedParameterReferenceExpression) expression).parameter;
			return "(parameter-ref #%d \"%s\" : %s)".printf (parameter.ordinal, parameter.name, type_name);
		}
		if (expression is CheckedPrefixExpression) {
			var prefix = (CheckedPrefixExpression) expression;
			return "(prefix %s : %s %s)".printf (prefix.operator_kind.spelling (), type_name, format_expression (prefix.operand));
		}
		if (expression is CheckedWithReference) {
			return "(with-reference " + ((CheckedWithReference) expression).contract.source.name + ")";
		}
		if (expression is CheckedLocalReferenceExpression) {
			var local = ((CheckedLocalReferenceExpression) expression).local;
			return "(local-ref #%d \"%s\" : %s)".printf (local.ordinal, local.name, type_name);
		}
		var short_circuit = expression as CheckedShortCircuitExpression;
		if (short_circuit != null) {
			return "(short-circuit %s : %s %s %s)".printf (short_circuit.operator_kind.spelling (), type_name, format_expression (short_circuit.left), format_expression (short_circuit.right));
		}
		if (expression is CheckedComparisonChain) {
			var chain = (CheckedComparisonChain) expression;
			var text = new StringBuilder ("(comparison-chain : bool");
			for (int i = 0; i < chain.operands.length; i++) {
				if (i > 0) {
					text.append (" " + chain.operators[i - 1].spelling ());
				}
				text.append (" " + format_expression (chain.operands[i]));
			}
			text.append (")");
			return text.str;
		}
		if (expression is CheckedBinaryExpression) {
			var binary = (CheckedBinaryExpression) expression;
			return "(binary %s : %s %s %s)".printf (binary.operator_kind.spelling (), type_name, format_expression (binary.left), format_expression (binary.right));
		}
		assert_not_reached ();
	}

}
}
