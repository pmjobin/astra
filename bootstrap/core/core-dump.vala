// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Core {
// Internal debugging format, not a serialization contract. Verification
// precedes formatting so malformed IR cannot produce partial output.
public class CoreDump : Object {
	private StringBuilder output = new StringBuilder ();

	private GenericArray<Astra.Semantic.EnumDefinition> enums;
	private Astra.Semantic.EnumDefinition? enum_definition (Astra.Semantic.EnumType type) {
		foreach (var candidate in enums) {
			if (candidate.semantic_type == type) {
				return candidate;
			}
		}
		return null;
	}

	public static string format(CoreProgram program) throws CoreError {
		CoreVerifier.verify (program);
		if (program.enums.length == 0 && program.functions.length == 0 && program.generic_functions.length == 0 && program.generic_structs.length == 0 && program.c_functions.length == 0 && program.c_exports.length == 0 && program.structs.length == 0 && program.classes.length == 0 && program.cleanups.length == 0) {
			return "(core-program)\n";
		}
		var dump = new CoreDump ();
		dump.enums = program.enums;
		dump.line (0, "(core-program");
		foreach (var definition in program.enums) {
			dump.line (1, "(enum %s %s".printf (definition.semantic_type.display_name (), Astra.Semantic.EnumValueAuthority.owns (definition, dump.enum_definition) ? "concrete-owning" : "concrete-copyable"));
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
		foreach (var definition in program.generic_structs) {
			dump.line (1, "(generic-struct #%d \"%s\"".printf (definition.identity.ordinal, definition.name));
			foreach (var parameter in definition.type_parameters) {
				dump.line (2, "(type-parameter #%d \"%s\" (baseline GEN1_PLAIN_COPY))".printf (parameter.ordinal, parameter.semantic_type.name));
			}
			foreach (var field in definition.fields) {
				dump.line (2, "(generic-field #%d \"%s\" : %s)".printf (field.ordinal, field.name, field.semantic_type.display_name ()));
			}
			dump.line (1, ")");
		}
		foreach (var handle in program.handles) {
			if (handle.com_import != null) {
				dump.line (1, "(" + handle.com_import.identity () + ")");
			}
			dump.line (1, "(handle-type #%d \"%s\" (cleanup #%d)".printf (handle.ordinal, handle.name.escape (), handle.cleanup.ordinal));
			if (handle.header != null) {
				dump.line (2, "(header \"%s\")".printf (handle.header.name.escape ()));
			}
			dump.line (1, ")");
		}
		foreach (var structure in program.native_instances ()) {
			if (structure is CoreStruct && ((CoreStruct) structure).representation != null && ((CoreStruct) structure).representation.is_union) {
				dump.line (1, ((CoreStruct) structure).representation.dump ());
			}
			dump.line (1, (structure is CoreClass) ? "(class #%d \"%s\"".printf (structure.ordinal, structure.name.escape ()) : "(struct \"%s\"".printf (structure.name.escape ()));
			if (structure is CoreClass && ((CoreClass) structure).allocation_policy != null) {
				dump.line (2, ((CoreClass) structure).allocation_policy.dump ());
			}
			if (structure is CoreClass && ((CoreClass) structure).foreign_export != null) {
				dump.line (2, ((CoreClass) structure).foreign_export.dump ());
			}
			var concrete = structure as CoreStruct;
			var generic_class = structure as CoreClass;
			if (generic_class != null && generic_class.generic_instance != null) {
				var key = generic_class.generic_instance;
				int origin = -1;
				for (int i = 0; i < program.generic_classes.length; i++) {
					if (program.generic_classes[i] == key.definition) {
						origin = i;
					}
				}
				dump.line (2, "(generic-class-instance (origin #%d \"%s\") (exact-argument \"%s\") (concrete-class #%d) (state COMPLETE))".printf (origin, key.definition.name, key.argument.display_name (), structure.ordinal));
			}
			if (concrete != null && concrete.generic_instance != null) {
				var instance = concrete.generic_instance;
				dump.line (2, "(generic-struct-instance #%d (origin #%d \"%s\") (application %s) (concrete-struct #%d) (state COMPLETE) (requests %u)".printf (instance.ordinal, instance.origin.ordinal, instance.origin.name, instance.display_name (), concrete.ordinal, instance.requests));
				foreach (var requester in instance.requesters) {
					dump.line (3, "(requester \"%s\")".printf (requester.label.escape ()));
				}
				dump.line (2, ")");
			}
			foreach (var property in structure.properties) {
				dump.line (2, "(property #%d \"%s\" : %s (member #%d) (getter #%d)%s)".printf (property.ordinal, property.name.escape (), property.semantic_type.display_name (), property.member_ordinal, property.ordinal, property.setter == null ? "" : " (setter #%d)".printf (property.ordinal)));
				if (property.is_lazy) {
					dump.line (3, "(lazy first-success empty/evaluating/ready)");
				}
				if (property.is_owned_lazy) {
					dump.line (3, "(owned-factory %s receiver-borrow-observation)".printf (property.factory.name));
				}
				if (property.is_borrowed) {
					dump.line (3, "(borrowed receiver-owned-field temporary-use)");
				}
			}
			foreach (var field in structure.fields) {
				if (field.is_private) {
					dump.line (2, "(private-field #%d lexical-declaring-class)".printf (field.ordinal));
				}
				if (field.owned_cleanup != null) {
					dump.line (2, "(field #%d \"%s\" : %s (ownership owned-field) (cleanup #%d %s))".printf (field.ordinal, field.name, field.semantic_type.display_name (), field.owned_cleanup.ordinal, field.owned_cleanup.external_symbol));
					continue;
				}
				dump.line (2, "(field #%d \"%s\" : %s)".printf (field.ordinal, field.name.escape (), field.semantic_type.display_name ()));
			}
			dump.line (1, ")");
		}
		foreach (var cleanup in program.cleanups) {
			if (cleanup.record_type != null) {
				dump.line (1, "(cleanup #%d record-field-obligations type=%s)".printf (cleanup.ordinal, cleanup.record_type.name));
				continue;
			}
			if (cleanup.type_parameter != null) {
				dump.line (1, "(ownership-contract #%d : %s (requires Ownable))".printf (cleanup.ordinal, cleanup.type_parameter.name));
				continue;
			}
			if (cleanup.is_buffer) {
				dump.line (1, "(cleanup #%d native-buffer-deallocate element=%s)".printf (cleanup.ordinal, cleanup.buffer_type.element_type.display_name ()));
				continue;
			}
			if (cleanup.is_object) {
				dump.line (1, "(cleanup #%d (domain object) (class #%d) %s)".printf (cleanup.ordinal, cleanup.object_class.ordinal, cleanup.destructor == null ? "lifetime-only" : "exact-destructor"));
				continue;
			}
			dump.line (1, "(cleanup #%d (symbol \"%s\") (signature void (void*)))".printf (cleanup.ordinal, cleanup.external_symbol.escape ()));
		}
		foreach (var imported in program.c_functions) {
			dump.line (1, "(extern-function #%d \"%s\" (abi C) (symbol \"%s\")".printf (imported.ordinal, imported.name.escape (), imported.external_symbol.escape ()));
			if (imported.owned_cleanup != null) {
				dump.line (2, "(owned-result (cleanup #%d))".printf (imported.owned_cleanup.ordinal));
			}
			if (imported.metadata.text_abi != Astra.Foreign.CTextAbi.NONE) {
				dump.line (2, imported.metadata.text_abi.dump_suffix ().strip ());
			}
			if (imported.metadata.buffer_abi != Astra.Foreign.CBufferAbi.NONE) {
				dump.line (2, imported.metadata.buffer_abi.dump_suffix ().strip ());
			}
			if (imported.metadata.record_abi != Astra.Foreign.CRecordAbi.NONE) {
				dump.line (2, imported.metadata.record_abi.dump_suffix ().strip ());
			}
			if (imported.metadata.pointer_abi != Astra.Foreign.CPointerAbi.NONE) {
				dump.line (2, imported.metadata.pointer_abi.dump_suffix ().strip ());
			}
			if (imported.metadata.bool_abi == Astra.Foreign.CBoolAbi.C99) {
				dump.line (2, "(C99-bool copied explicit zeroext)");
			}
			if (imported.metadata.import_policy == Astra.Source.DeclarationPolicyId.GOBJECT_IMPORT) {
				dump.line (2, "(policy GObjectImport typed-C-bridge explicit-header)");
			}
			if (imported.metadata.callback != null) {
				dump.line (2, imported.metadata.callback_dump_suffix ().strip ());
			}
			if (imported.metadata.header_count > 0) {
				dump.line (2, "(headers");
				for (int h = 0; h < imported.metadata.header_count; h++) {
					dump.line (3, "\"%s\"".printf (imported.metadata.header_at (h).name.escape ()));
				}
				dump.line (2, ")");
			}
			dump.line (2, "(parameters");
			for (int p = 0; p < imported.parameter_types.length; p++) {
				dump.line (3, "(parameter #%d : %s%s)".printf (p, imported.parameter_types[p].display_name (), imported.parameters[p].pointer_contract.dump_suffix ()));
			}
			dump.line (2, ")");
			dump.line (2, "(result %s))".printf (imported.return_type.display_name ()));
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
			dump.write_function (program.functions[i]);
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

	private void write_function(CoreFunction function) throws CoreError {
		if (function.floating_policy != 0) {
			line (1, "(floating-policy permissions=%u checked-domain=bounded)".printf (function.floating_policy));
		}
		var method = function as CoreMethod;
		if (function is CoreGenericFunction) {
			var generic = (CoreGenericFunction) function;
			bool has_owners = false;
			foreach (var parameter in generic.type_parameters) {
				if (parameter.transport_mode == Astra.Semantic.GenericTransportMode.OWNABLE) {
					has_owners = true;
				}
			}
			line (1, "(generic-definition #%d \"%s\"%s)".printf (generic.identity.ordinal, generic.name, has_owners ? "" : " GEN1_PLAIN_COPY"));
			foreach (var parameter in generic.type_parameters) {
				line (1, "(type-parameter #%d %s%s)".printf (parameter.ordinal, parameter.semantic_type.display_name (), parameter.transport_mode == Astra.Semantic.GenericTransportMode.OWNABLE ? " (transport OWNABLE)" : ""));
			}
			foreach (var parameter in generic.type_parameters) {
				if (generic.element_obligations.contains (parameter.semantic_type)) {
					line (1, "(slice-element #%d %s mutable-storage)".printf (parameter.ordinal, parameter.semantic_type.name));
				}
			}
			foreach (var requirement in generic.capability_requirements) {
				line (1, "(requires #%d %s %s)".printf (requirement.type_parameter.ordinal, requirement.type_parameter.semantic_type.name, requirement.capability.spelling ()));
			}
		}
		if (function.generic_instance != null) {
			var instance = function.generic_instance;
			var key = new StringBuilder ("(generic-instance #%d (origin #%d \"%s\") (type-arguments".printf (instance.ordinal, instance.origin.ordinal, instance.origin.name));
			foreach (var type in instance.type_arguments) {
				key.append (" " + type.display_name ());
			}
			key.append (")");
			for (int p = 0; p < instance.storage.count; p++) {
				key.append (" (heap-owned-parameter #%d)".printf (instance.storage.parameter (p)));
			}
			key.append (" (requests %u) (callers".printf (instance.requests));
			foreach (var caller in instance.callers) {
				key.append (" \"%s\"".printf (caller.label.escape ()));
			}
			key.append ("))");
			line (1, key.str);
		}
		if (function is CorePropertyAccessor) {
			var accessor = (CorePropertyAccessor) function;
			var property = accessor.property_member;
			line (1, "(property-%s #%d (property %s::%s #%d) (declaring-%s #%d) -> %s".printf ((function is CorePropertyGetter) ? "getter" : "setter", property.ordinal, property.declaring_type.name, property.name, property.ordinal, (property.declaring_type is CoreClass) ? "class" : "struct", property.declaring_type.ordinal, function.return_type.display_name ()));
			line (2, "(receiver : %s live mutable nonnull non-owning)".printf (accessor.receiver.contract.display_name ()));
		} else if (function is CoreLifecycle) {
			var lifecycle = (CoreLifecycle) function;
			line (1, "(%s (class #%d) (member #%d)".printf ((function is CoreConstructor) ? "constructor" : "destructor", lifecycle.declaring_class.ordinal, lifecycle.member_ordinal));
			line (2, "(receiver %s %s nonnull mutable)".printf ((function is CoreConstructor) ? "initializing" : "live", lifecycle.declaring_class.name));
		} else if (method == null) {
			line (1, "(function \"%s\" -> %s".printf (function.name.escape (), function.return_type.display_name ()));
		} else {
			line (1, "(method #%d \"%s\" (declaring-%s #%d \"%s\") (member #%d) -> %s".printf (method.method_ordinal, method.name.escape (), (method.declaring_type is CoreClass) ? "class" : "struct", method.declaring_type.ordinal, method.declaring_type.name.escape (), method.member_ordinal, method.return_type.display_name ()));
			line (2, "(receiver : %s mutable nonnull non-owning)".printf (method.receiver.contract.display_name ()));
		}
		if (function.result_storage != null) {
			line (2, "(result-storage : %s caller-provided hidden-input)".printf (function.return_type.display_name ()));
		}
		foreach (var storage in function.object_storage) {
			if (storage.fallible) {
				line (2, "(fallible-allocation #%d null-before-construction)".printf (storage.ordinal));
			}
			if (storage.result_candidate) {
				line (2, "(candidate-storage #%d (class #%d) unused-until-owned-result)".printf (storage.ordinal, storage.object_class.ordinal));
				continue;
			}
			line (2, "(object-storage #%d (class #%d) : %s (region #%d) lexical-memory)".printf (storage.ordinal, storage.object_class.ordinal, storage.semantic_type.display_name (), storage.region_ordinal));
		}
		foreach (var storage in function.object_storage) {
			if (storage.result_candidate) {
				continue;
			}
			if (storage.transferable) {
				line (2, "(object-cleanup (storage #%d) transferable-owner null-disarm)".printf (storage.ordinal));
			} else if (storage.destructor != null) {
				line (2, "(object-cleanup (storage #%d) (destructor class #%d) (rank #%d) after-success)".printf (storage.ordinal, storage.object_class.ordinal, storage.cleanup_rank));
			}
		}
		if (function.owned_cleanup != null) {
			line (2, "(result %s (contract owned-transfer) (cleanup #%d))".printf (function.return_type.display_name (), function.owned_cleanup.ordinal));
		}
		if (function.struct_result_contract != null) {
			line (2, "(struct-result %s exact-nominal snapshot)".printf (function.struct_result_contract.mode.spelling ()));
		}
		if (function.parameters.length == 0) {
			line (2, "(parameters)");
		} else {
			line (2, "(parameters");
			for (int i = 0; i < function.parameters.length; i++) {
				var parameter = function.parameters[i];
				if (parameter.struct_value_contract != null) {
					line (3, "(struct-parameter #%d %s %sindependent-local)".printf (parameter.ordinal, parameter.struct_value_contract.mode.spelling (), parameter.struct_value_contract.mode == Astra.Semantic.StructValueMode.COPY_VALUE ? "read-only " : ""));
				}
				line (3, "(parameter #%d \"%s\" : %s%s)".printf (parameter.ordinal, parameter.name.escape (), parameter.semantic_type.display_name (), parameter.pointer_contract.dump_suffix ()));
			}
			line (2, ")");
		}
		foreach (var owner in function.owned_locals) {
			if (owner.cleanup.is_object) {
				line (2, "(ownership (owner #%d) transferable-object%s)".printf (owner.place.ordinal, owner.object_storage == null ? (owner.place.incoming_parameter == null ? " nullable-result" : " incoming-parameter") : " (storage #%d)".printf (owner.object_storage.ordinal)));
			}
			if (owner.place.incoming_parameter != null) {
				line (2, "(owned-parameter #%d (owner #%d) function-root)".printf (owner.place.incoming_parameter.ordinal, owner.place.ordinal));
			}
			line (2, "(owned-local (local-place #%d) (cleanup #%d) lexical-block)".printf (owner.place.ordinal, owner.cleanup.ordinal));
		}
		if (function.locals.length > 0) {
			line (2, "(locals");
			for (int i = 0; i < function.locals.length; i++) {
				var local = function.locals[i];
				line (3, "(%slocal-place #%d \"%s\" : %s%s)".printf (local.semantic_type.kind == Astra.Semantic.TypeKind.STRUCT ? "struct-" : "", local.ordinal, local.name.escape (), local.semantic_type.display_name (), local.address_taken ? " address-taken" : ""));
			}
			line (2, ")");
		}
		if (function.field_places.length > 0) {
			line (2, "(field-places");
			foreach (var place in function.field_places) {
				write_place (place, 3);
			}
			line (2, ")");
		}
		write_block (function.body, 2);
		if (function is CoreDestructor) {
			foreach (var action in ((CoreDestructor) function).field_cleanups) {
				line (2, "(owned-field-cleanup (field %s::%s #%d) (cleanup #%d) after-user-deinit-normal-return)".printf (action.field.containing_type.name, action.field.name, action.field.ordinal, action.cleanup == null ? -1 : action.cleanup.ordinal));
			}
		}
		line (1, ")");
	}

	private void write_block(CoreBlock block, int indentation) throws CoreError {
		if (block.statements.length == 0) {
			line (indentation, "(block)");
			return;
		}
		line (indentation, "(block");
		for (int i = 0; i < block.statements.length; i++) {
			write_statement (block.statements[i], indentation + 1);
		}
		line (indentation, ")");
	}

	private void write_statement(CoreStatement statement, int indentation) throws CoreError {
		if (statement is CoreActorSend) {
			var send = (CoreActorSend) statement;
			line (indentation, "(actor-%d checked=%s".printf ((int) send.action, send.error_type.display_name ()));
			write_value (send.sender, indentation + 1);
			if (send.message != null) {
				line (indentation + 1, "(consume-heap-message " + send.message.place.name + ")");
			}
			if (send.scalar != null) {
				write_value (send.scalar, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		if (statement is CoreTaskAwaitStatement) {
			write_value (((CoreTaskAwaitStatement) statement).operation, indentation);
			return;
		}
		if (statement is CoreValueStatement) {
			write_value (((CoreValueStatement) statement).value, indentation);
			return;
		}
		if (statement is CoreAsyncOperationStatement) {
			write_value (((CoreAsyncOperationStatement) statement).operation, indentation);
			return;
		}
		if (statement is CoreAsyncDelay) {
			line (indentation, ((CoreAsyncDelay) statement).payload ? "(linux-payload-suspend" : "(virtual-suspend");
			write_value (((CoreAsyncDelay) statement).ticks, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (statement is CoreTry) {
			var guarded = (CoreTry) statement;
			line (indentation, "(try");
			write_block (guarded.body, indentation + 1);
			foreach (var caught in guarded.catches) {
				line (indentation + 1, "(catch %s local#%d".printf (caught.binding.semantic_type.display_name (), caught.binding.ordinal));
				write_block (caught.body, indentation + 2);
				line (indentation + 1, ")");
			}
			line (indentation, ")");
			return;
		}
		if (statement is CoreVectorMemoryStatement) {
			write_value (((CoreVectorMemoryStatement) statement).operation, indentation);
			return;
		}
		if (statement is CoreThrow) {
			var thrown = (CoreThrow) statement;
			line (indentation, "(%s local#%d : %s)".printf (thrown.rethrows ? "rethrow" : "throw-move", thrown.source.ordinal, thrown.source.semantic_type.display_name ()));
			return;
		}
		if (statement is CoreBaseLifecycleCall) {
			var call = (CoreBaseLifecycleCall) statement;
			line (indentation, "(base-lifecycle class#%d".printf (((CoreLifecycle) call.target).declaring_class.ordinal));
			write_value (call.receiver, indentation + 1);
			foreach (var argument in call.arguments) {
				write_value (argument, indentation + 1);
			}
			line (indentation, ")");
			return;
		}

		if (statement is CoreAcquireEnumParameter) {
			var acquire = (CoreAcquireEnumParameter) statement;
			line (indentation, "(acquire-enum-parameter #%d local#%d snapshot)".printf (acquire.parameter.ordinal, acquire.destination.ordinal));
			return;
		}
		if (statement is CoreEnumStore) {
			var store = (CoreEnumStore) statement;
			line (indentation, "(enum-store local#%d %s".printf (store.destination.ordinal, store.initializes_destination ? "initialize" : "assign"));
			write_enum_producer (store.producer, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (statement is CoreEnumReturn) {
			line (indentation, "(enum-return snapshot-before-cleanup");
			write_enum_producer (((CoreEnumReturn) statement).producer, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (statement is CoreEnumMatch) {
			var match = (CoreEnumMatch) statement;
			line (indentation, "(match-snapshot");
			write_enum_producer (match.scrutinee, indentation + 1);
			foreach (var arm in match.arms) {
				line (indentation + 1, arm.variant == null ? "(else" : "(case " + arm.variant.identity.name);
				foreach (var binding in arm.bindings) {
					line (indentation + 2, "(bind field#%d %s local#%d)".printf (binding.field.identity.ordinal, binding.field.identity.name, binding.destination.ordinal));
				}
				write_block (arm.body, indentation + 2);
				line (indentation + 1, ")");
			}
			line (indentation, ")");
			return;
		}
		if (statement is CoreSlotsRecordTransfer) {
			var transfer = (CoreSlotsRecordTransfer) statement;
			line (indentation, "(record-slots-%s %s".printf (transfer.index == null ? "append" : "replace", transfer.value.contract.mode.spelling ()));
			write_place (transfer.store, indentation + 1);
			if (transfer.index != null) {
				write_value (transfer.index, indentation + 1);
			}
			write_struct_producer (transfer.value, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (statement is CoreSlotsInitialize) {
			line (indentation, "(owner-slots-empty");
			write_place (((CoreSlotsInitialize) statement).store, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (statement is CoreSlotsReplace) {
			var op = (CoreSlotsReplace) statement;
			line (indentation, "(owner-slots-replace");
			write_place (op.store, indentation + 1);
			write_value (op.index, indentation + 1);
			write_place (op.incoming.place, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (statement is CoreSlotsAppend) {
			var s = (CoreSlotsAppend) statement;
			line (indentation, "(owner-slots-append source#%d".printf (s.incoming.place.ordinal));
			write_place (s.store, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (statement is CoreOwnedFieldTransfer) {
			var transfer = (CoreOwnedFieldTransfer) statement;
			line (indentation, "(%s (cleanup #%d)".printf (transfer.initializes ? "owned-field-init" : "owned-field-replace", transfer.cleanup.ordinal));
			write_place (transfer.destination, indentation + 1);
			if (transfer.source != null) {
				line (indentation + 1, "(move-source #%d)".printf (transfer.source.place.ordinal));
			} else {
				write_value (transfer.producer, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		if (statement is CoreAcquireStructParameter) {
			var acquire = (CoreAcquireStructParameter) statement;
			line (indentation, "(acquire-struct-parameter #%d %s (local #%d) all-leaves)".printf (acquire.parameter.ordinal, acquire.parameter.struct_value_contract.mode.spelling (), acquire.destination.ordinal));
			return;
		}
		if (statement is CoreStructReturn) {
			line (indentation, "(struct-return snapshot-before-cleanup");
			write_struct_producer (((CoreStructReturn) statement).producer, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (statement is CoreStructResultStore) {
			var store = (CoreStructResultStore) statement;
			line (indentation, "(struct-result-store %s".printf (store.initializes_destination ? "initialize" : "assign"));
			write_place (store.destination, indentation + 1);
			write_struct_producer (store.producer, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (statement is CoreConstructorObjectInitialization) {
			var invocation = (CoreConstructorObjectInitialization) statement;
			line (indentation, "(construct (storage #%d) (constructor class #%d) (ref-local #%d)".printf (invocation.storage.ordinal, invocation.constructor.declaring_class.ordinal, invocation.target.ordinal));
			if (invocation.allocation_context != null) {
				line (indentation + 1, "(allocation-context");
				write_value (invocation.allocation_context, indentation + 2);
				line (indentation + 1, ")");
			}
			foreach (var argument in invocation.arguments) {
				write_value (argument, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		var construction = statement as CoreObjectConstruction;
		if (construction != null) {
			line (indentation, "(object-construct (storage #%d) (ref-local #%d) : %s".printf (construction.storage.ordinal, construction.target.ordinal, construction.storage.semantic_type.display_name ()));
			foreach (var initializer in construction.initializers) {
				line (indentation + 1, "(field-init #%d".printf (initializer.field.ordinal));
				write_value (initializer.value, indentation + 2);
				line (indentation + 1, ")");
			}
			line (indentation, ")");
			return;
		}
		if (statement is CoreScope) {
			write_block (((CoreScope) statement).body, indentation);
			return;
		}
		var array = statement as CoreArrayInitialize;
		if (array != null) {
			line (indentation, "(array-initialize #%d %s".printf (array.storage.ordinal, array.storage.semantic_type.display_name ()));
			foreach (var element in array.elements) {
				write_value (element, indentation + 1);
			}
			foreach (var record in array.records) {
				line (indentation + 1, "(record-entry");
				write_place (record.target, indentation + 2);
				if (record.producer != null) {
					write_struct_producer (record.producer, indentation + 2);
				} else {
					foreach (var field in record.initializers) {
						write_statement (field, indentation + 2);
					}
				}
				line (indentation + 1, ")");
			}
			line (indentation, ")");
			return;
		}
		var owned_return = statement as CoreOwnershipReturn;
		if (owned_return != null) {
			if (owned_return.provenance != Astra.Semantic.ObjectResultProvenance.NONE) {
				line (indentation, "(result-provenance %s)".printf (owned_return.provenance.label ()));
			}
			if (owned_return.producer != null) {
				line (indentation, "(ownership-return");
				write_value (owned_return.producer, indentation + 1);
				line (indentation, ")");
				return;
			}
			line (indentation, "(ownership-return %s : %s (cleanup #%d))".printf (owned_return.source == null ? "owned-null" : "(move owner #%d)".printf (owned_return.source.place.ordinal), owned_return.semantic_type.display_name (), owned_return.cleanup.ordinal));
			return;
		}
		var parameter_acquire = statement as CoreAcquireParameter;
		if (parameter_acquire != null) {
			line (indentation, "(acquire-parameter #%d (owner #%d) (cleanup #%d))".printf (parameter_acquire.acquisition.place.incoming_parameter.ordinal, parameter_acquire.acquisition.place.ordinal, parameter_acquire.acquisition.cleanup.ordinal));
			return;
		}
		var rearm = statement as CoreOwnershipRearm;
		if (rearm != null) {
			line (indentation, "(ownership-rearm (owner #%d \"%s\") (cleanup #%d)".printf (rearm.owner.place.ordinal, rearm.owner.place.name, rearm.cleanup.ordinal));
			if (rearm.source != null) {
				line (indentation + 1, "(move-owner #%d)".printf (rearm.source.place.ordinal));
			} else {
				write_value (rearm.producer, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		var exchange = statement as CoreOwnedBufferExchange;
		if (exchange != null) {
			line (indentation, "(owned-buffer-exchange (cleanup #%d)".printf (exchange.left.cleanup.ordinal));
			write_place (exchange.left.place, indentation + 1);
			write_place (exchange.right.place, indentation + 1);
			line (indentation, ")");
			return;
		}
		var release = statement as CoreOwnershipRelease;
		if (release != null) {
			line (indentation, "(ownership-release (owner #%d \"%s\") (cleanup #%d))".printf (release.owner.place.ordinal, release.owner.place.name, release.cleanup.ordinal));
			return;
		}
		if (statement is CoreBreak || statement is CoreContinue) {
			var target = (statement is CoreBreak) ? ((CoreBreak) statement).target : ((CoreContinue) statement).target;
			line (indentation, "(%s #%d)".printf ((statement is CoreBreak) ? "break" : "continue", target.ordinal));
			return;
		}
		var loop = statement as CoreWhile;
		if (loop != null) {
			line (indentation, "(while #%d".printf (loop.target.ordinal));
			line (indentation + 1, "(condition");
			write_value (loop.condition, indentation + 2);
			line (indentation + 1, ")");
			line (indentation + 1, "(body");
			write_block (loop.body, indentation + 2);
			line (indentation + 1, ")");
			if (loop.step != null) {
				line (indentation + 1, "(step");
				write_block (loop.step, indentation + 2);
				line (indentation + 1, ")");
			}
			line (indentation, ")");
			return;
		}
		var c_call = statement as CoreCCallStatement;
		if (c_call != null) {
			write_call ("c-call-statement", c_call.target.name, c_call.target.return_type.display_name (), c_call.arguments, indentation);
			return;
		}
		var call = statement as CoreCallStatement;
		if (call != null) {
			write_call ("call-statement", call.target.name, call.target.return_type.display_name (), call.arguments, indentation, call.target as CoreMethod, call.receiver, call.target as CorePropertyAccessor, (call is CoreGenericCallStatement) ? ((CoreGenericCallStatement) call).type_arguments : null);
			return;
		}
		var conditional = statement as CoreIf;
		if (conditional != null) {
			line (indentation, "(if");
			line (indentation + 1, "(condition");
			write_value (conditional.condition, indentation + 2);
			line (indentation + 1, ")");
			line (indentation + 1, "(then");
			write_block (conditional.then_block, indentation + 2);
			line (indentation + 1, ")");
			if (conditional.else_block != null) {
				line (indentation + 1, "(else");
				write_block (conditional.else_block, indentation + 2);
				line (indentation + 1, ")");
			}
			line (indentation, ")");
			return;
		}
		if (statement is CoreStructAcquire) {
			var acquire = (CoreStructAcquire) statement;
			line (indentation, "(owning-record-acquire local #%d Resource field #%s cleanup #%d)".printf (acquire.owner.place.ordinal, acquire.field.storage_path ().spelling (), acquire.field.field.owned_cleanup.ordinal));
			return;
		}
		if (statement is CoreRecordTake) {
			var take = (CoreRecordTake) statement;
			line (indentation, "(owning-record-take local #%d path=%s destination=#%d)".printf (take.source.place.ordinal, take.field.storage_path ().spelling (), take.destination.place.ordinal));
			return;
		}
		if (statement is CoreRecordReplace) {
			var replace = (CoreRecordReplace) statement;
			line (indentation, "(owning-record-replace local #%d path=%s)".printf (replace.owner.place.ordinal, replace.field.storage_path ().spelling ()));
			return;
		}
		if (statement is CoreStructMove) {
			var move = (CoreStructMove) statement;
			line (indentation, "(owning-record-move local #%d -> #%d)".printf (move.source.place.ordinal, move.destination.place.ordinal));
			return;
		}
		var copy = statement as CoreStructCopy;
		if (copy != null) {
			line (indentation, "(struct-copy (type %s) %s snapshot-before-write".printf (copy.semantic_type.display_name (), copy.initializes_destination ? "initialize" : "assign"));
			line (indentation + 1, "(destination");
			write_place (copy.destination, indentation + 2);
			line (indentation + 1, ")");
			line (indentation + 1, "(source");
			write_place (copy.source, indentation + 2);
			line (indentation + 1, ")");
			line (indentation, ")");
			return;
		}
		var nested = statement as CoreStructInitialize;
		if (nested != null) {
			line (indentation, "(struct-initialize-storage");
			if (nested.record_owner != null) {
				line (indentation + 1, "(record-owner #%d)".printf (nested.record_owner.place.ordinal));
			}
			write_place (nested.target, indentation + 1);
			if (nested.producer != null) {
				write_struct_producer (nested.producer, indentation + 1);
			}
			foreach (var child in nested.initializers) {
				write_statement (child, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		var initialization = statement as CoreInitialize;
		var transfer = statement as CoreOwnershipTransfer;
		if (transfer != null) {
			line (indentation, "(ownership-transfer (source owner #%d \"%s\") (destination owner #%d \"%s\") (cleanup #%d))".printf (transfer.source.place.ordinal, transfer.source.place.name, transfer.destination.place.ordinal, transfer.destination.place.name, transfer.cleanup.ordinal));
			return;
		}
		if (initialization != null) {
			line (indentation, initialization.acquisition == null ? "(initialize" : "(owned-initialize (cleanup #%d)".printf (initialization.acquisition.cleanup.ordinal));
			write_place (initialization.target, indentation + 1);
			write_value (initialization.value, indentation + 1);
			line (indentation, ")");
			return;
		}
		var store = statement as CoreStore;
		if (store != null) {
			line (indentation, store.volatile_enabled ? "(volatile-store" : "(store");
			write_place (store.target, indentation + 1);
			write_value (store.value, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (statement is CoreForeignSignalReturn) {
			line (indentation, "(native-signal synchronous-return " + ((CoreForeignSignalReturn) statement).binding.identity () + ")");
			return;
		}
		if (statement is CoreForeignReturn) {
			line (indentation, "(CImport declarations-v1 status-out checked-return " + "consumed=" + ((CoreForeignReturn) statement).consumed.length.to_string () + " " + ((CoreForeignReturn) statement).binding.identity () + ")");
			return;
		}
		var returned = statement as CoreReturn;
		if (returned == null) {
			throw new CoreError.INVALID_IR ("internal Core dump error: unsupported Core statement");
		}
		if (returned.value == null) {
			line (indentation, "(return)");
		} else {
			line (indentation, "(return");
			write_value (returned.value, indentation + 1);
			line (indentation, ")");
		}
	}

	private void write_place(CorePlace place, int indentation) throws CoreError {
		var generic = place as CoreGenericStructFieldPlace;
		if (generic != null) {
			line (indentation, "(generic-field-place (owner %s) (field %s::%s #%d) : %s".printf (generic.application.display_name (), generic.field.definition.name, generic.field.name, generic.field.ordinal, generic.semantic_type.display_name ()));
			write_place (generic.aggregate, indentation + 1);
			line (indentation, ")");
			return;
		}
		var slice = place as CoreSliceElementPlace;
		if (slice != null) {
			line (indentation, "(slice-element-place : %s runtime-bounds-trap".printf (place.semantic_type.display_name ()));
			write_value (slice.slice, indentation + 1);
			write_value (slice.index, indentation + 1);
			line (indentation, ")");
			return;
		}
		var array = place as CoreArrayElementPlace;
		if (array != null) {
			line (indentation, "(array-element-place #%d %s (bounds 0 %d trap)".printf (array.storage.ordinal, array.array_type.display_name (), array.array_type.length));
			write_value (array.index, indentation + 1);
			line (indentation, ")");
			return;
		}
		var dereference = place as CoreDereferencePlace;
		if (dereference != null) {
			line (indentation, "(dereference-place : %s null-traps".printf (place.semantic_type.display_name ()));
			write_value (dereference.pointer, indentation + 1);
			line (indentation, ")");
			return;
		}
		var indirect = place as CoreIndirectFieldPlace;
		if (indirect != null) {
			line (indentation, "(%s : %s".printf ((indirect.pointer.semantic_type is Astra.Semantic.ClassType) ? "object-field-place null-traps" : "indirect-field-place", place.semantic_type.display_name ()));
			write_value (indirect.pointer, indentation + 1);
			line (indentation + 1, "(field #%d \"%s\")".printf (indirect.field.ordinal, indirect.field.name));
			line (indentation, ")");
			return;
		}
		var projection = place as CoreFieldPlace;
		if (projection != null) {
			var aggregate = projection.aggregate as CoreLocalPlace;
			if (aggregate == null) {
				line (indentation, "(field-place : %s (field %s::%s #%d)".printf (place.semantic_type.display_name (), projection.field.containing_type.name, projection.field.name, projection.field.ordinal));
				write_place (projection.aggregate, indentation + 1);
				line (indentation, ")");
				return;
			}
			line (indentation, "(field-place (base struct-local-place #%d : %s) (field #%d \"%s\") : %s)".printf (aggregate.ordinal, aggregate.semantic_type.display_name (), projection.field.ordinal, projection.field.name.escape (), projection.semantic_type.display_name ()));
			return;
		}
		var local = place as CoreLocalPlace;
		if (local == null) {
			throw new CoreError.INVALID_IR ("internal Core dump error: unsupported Core place");
		}
		line (indentation, "(local-place #%d : %s)".printf (local.ordinal, local.semantic_type.display_name ()));
	}

	private void write_call(string kind, string target_name, string result_type, GenericArray<CoreValue> arguments, int indentation, CoreMethod? method = null, CoreValue? receiver = null, CorePropertyAccessor? accessor = null, GenericArray<Astra.Semantic.SemanticType>? type_arguments = null) throws CoreError {
		line (indentation, "(%s \"%s\" -> %s".printf (type_arguments != null ? "generic-" + kind : accessor != null ? ((accessor is CorePropertyGetter) ? "property-get" : "property-set") : method == null ? kind : "method-" + kind, target_name.escape (), result_type));
		if (type_arguments != null) {
			var types = new StringBuilder ("(type-arguments");
			foreach (var type in type_arguments) {
				types.append (" " + type.display_name ());
			}
			types.append (")");
			line (indentation + 1, types.str);
		}
		if (accessor != null) {
			var property = accessor.property_member;
			line (indentation + 1, "(property #%d %s::%s) (%s #%d) effectful".printf (property.ordinal, property.declaring_type.name, property.name, (accessor is CorePropertyGetter) ? "getter" : "setter", property.ordinal));
		}
		if (method != null || accessor != null) {
			if (method != null) {
				line (indentation + 1, "(target %s::%s #%d)".printf (method.declaring_type.name, method.name, method.method_ordinal));
			}
			line (indentation + 1, "(receiver");
			write_value (receiver, indentation + 2);
			line (indentation + 1, ")");
		}
		if (arguments.length == 0) {
			line (indentation + 1, "(arguments)");
		} else {
			line (indentation + 1, "(arguments");
			for (int i = 0; i < arguments.length; i++) {
				write_value (arguments[i], indentation + 2);
			}
			line (indentation + 1, ")");
		}
		line (indentation, ")");
	}

	private void write_struct_producer(CoreStructProducer producer, int indentation) throws CoreError {
		if (producer is CoreStructInvocationResult) {
			line (indentation, "(struct-indirect-result " + producer.contract.mode.spelling () + " : " + producer.semantic_type.display_name ());
			write_value (((CoreStructInvocationResult) producer).invocation, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (producer is CoreStructProjectionProducer) {
			var projection = (CoreStructProjectionProducer) producer;
			line (indentation, "(struct-project %s : %s".printf (projection.path.spelling (), producer.semantic_type.display_name ()));
			write_struct_producer (projection.source, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (producer is CoreSlotsRecordRead) {
			var read = (CoreSlotsRecordRead) producer;
			line (indentation, "(record-slots-%s %s : %s".printf (read.remove ? "take" : "copy", read.contract.mode.spelling (), producer.semantic_type.display_name ()));
			write_place (read.store, indentation + 1);
			write_value (read.index, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (producer is CoreStructMoveProducer) {
			line (indentation, "(record-move-value : " + producer.semantic_type.display_name () + " " + ((CoreStructMoveProducer) producer).source.place.name + ")");
			return;
		}
		if (producer is CoreStructAwait) {
			line (indentation, "(struct-await : " + producer.semantic_type.display_name ());
			write_value (((CoreStructAwait) producer).operation, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (producer is CoreStructBorrowSnapshot) {
			line (indentation, "(struct-borrow-snapshot : " + producer.semantic_type.display_name ());
			write_place (((CoreStructBorrowSnapshot) producer).source, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (producer is CoreStructSnapshot) {
			line (indentation, "(struct-snapshot : " + producer.semantic_type.display_name ());
			write_place (((CoreStructSnapshot) producer).source, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (producer is CoreCStructCallResult) {
			var foreign_call = (CoreCStructCallResult) producer;
			write_call ("c-struct-call-result", foreign_call.target.name, producer.semantic_type.display_name (), foreign_call.arguments, indentation);
			return;
		}
		var call = (CoreStructCallResult) producer;
		line (indentation, "(struct-call-result : " + producer.semantic_type.display_name ());
		if (call.type_arguments != null) {
			foreach (var argument in call.type_arguments) {
				line (indentation + 1, "(type-argument " + argument.display_name () + ")");
			}
		}
		write_call ("call", call.target == null ? "<expired>" : call.target.name, producer.semantic_type.display_name (), call.arguments, indentation + 1, call.target as CoreMethod, call.receiver);
		line (indentation, ")");
	}

	private void write_enum_producer(CoreEnumProducer producer, int indentation) throws CoreError {
		if (producer is CoreEnumAwait) {
			line (indentation, "(enum-await : " + producer.semantic_type.display_name ());
			write_value (((CoreEnumAwait) producer).operation, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (producer is CoreAsyncRun) {
			line (indentation, "(run-status");
			write_value (((CoreAsyncRun) producer).operation, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (producer is CoreEnumSnapshot) {
			line (indentation, "(enum-snapshot local#%d : %s)".printf (((CoreEnumSnapshot) producer).source.ordinal, producer.semantic_type.display_name ()));
			return;
		}
		var construction = producer as CoreEnumConstruct;
		if (construction != null) {
			line (indentation, "(enum-construct %s.%s".printf (producer.semantic_type.display_name (), construction.variant.identity.name));
			foreach (var field in construction.fields) {
				line (indentation + 1, "(field#%d %s".printf (field.field.identity.ordinal, field.field.identity.name));
				if (field.scalar != null) {
					write_value (field.scalar, indentation + 2);
				} else if (field.record != null) {
					write_struct_producer (field.record, indentation + 2);
				} else {
					write_enum_producer (field.sum, indentation + 2);
				} line (indentation + 1, ")");
			}
			line (indentation, ")");
			return;
		}
		var call = (CoreEnumCallResult) producer;
		line (indentation, "(enum-call-result " + (call.target == null ? "<expired>" : call.target.name));
		if (call.receiver != null) {
			write_value (call.receiver, indentation + 1);
		}
		foreach (var argument in call.arguments) {
			write_value (argument, indentation + 1);
		}
		line (indentation, ")");
	}

	private void write_value(CoreValue value, int indentation) throws CoreError {
		if (value is CoreStructProjectionValue) {
			var projection = (CoreStructProjectionValue) value;
			line (indentation, "(struct-project %s : %s".printf (projection.path.spelling (), value.semantic_type.display_name ()));
			write_struct_producer (projection.source, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (value is CoreLazyObserve) {
			var property = ((CoreLazyObserve) value).property_member;
			line (indentation, "(lazy-observe receiver-borrow %s::%s)".printf (property.declaring_type.name, property.name));
			return;
		}
		if (value is CoreSharedOperation) {
			var operation = (CoreSharedOperation) value;
			line (indentation, "(shared-%s : %s".printf (operation.action.to_string (), value.semantic_type.display_name ()));
			write_value (operation.operand, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (value is CoreCallbackParameterView) {
			line (indentation, "(captured-callback-parameter " + ((CoreCallbackParameterView) value).source.name + " : " + value.semantic_type.display_name () + ")");
			return;
		}
		if (value is CoreFunctionAddress) {
			line (indentation, "(function-address %s : %s)".printf (((CoreFunctionAddress) value).target.name, value.semantic_type.display_name ()));
			return;
		}
		if (value is CoreRetainedOperation) {
			var operation = (CoreRetainedOperation) value;
			line (indentation, "(retained-callback action=%d".printf ((int) operation.action));
			write_value (operation.callee, indentation + 1);
			foreach (var argument in operation.arguments) {
				write_value (argument, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		if (value is CoreClosureBind) {
			var closure = (CoreClosureBind) value;
			line (indentation, "(closure-bind %s code=%s%s)".printf (value.semantic_type.display_name (), closure.target.name, closure.actor_binding == null ? "" : " " + closure.actor_binding.dump ()));
			return;
		}
		if (value is CoreClosureCall) {
			var call = (CoreClosureCall) value;
			line (indentation, "(invoke-closure");
			write_value (call.callee, indentation + 1);
			foreach (var argument in call.arguments) {
				write_value (argument, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		if (value is CoreFunctionValueCall) {
			var call = (CoreFunctionValueCall) value;
			line (indentation, "(invoke-function-value");
			write_value (call.callee, indentation + 1);
			foreach (var argument in call.arguments) {
				write_value (argument, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		if (value is CoreTaskAwait) {
			var wait = (CoreTaskAwait) value;
			line (indentation, "(await%s".printf (wait.discard ? " discard-and-drain" : ""));
			if (wait.bridge_executor != null) {
				line (indentation + 1, "(worker-bridge");
				write_value (wait.bridge_executor, indentation + 2);
				line (indentation + 1, ")");
			}
			write_value (wait.child, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (value is CoreTaskMove) {
			line (indentation, "(task-move local#%d)".printf (((CoreTaskMove) value).source.ordinal));
			return;
		}
		if (value is CoreTaskCreate) {
			var task = (CoreTaskCreate) value;
			line (indentation, "(task-create cold " + task.target.name);
			if (task.allocation_context != null) {
				line (indentation + 1, "(frame-context");
				write_value (task.allocation_context, indentation + 2);
				line (indentation + 1, ")");
			}
			foreach (var capture in task.arguments) {
				write_value (capture, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		if (value is CoreTaskBorrow) {
			line (indentation, "(task-borrow local#%d)".printf (((CoreTaskBorrow) value).source.ordinal));
			return;
		}
		if (value is CoreExecutorBorrow) {
			line (indentation, "(executor-borrow local#%d)".printf (((CoreExecutorBorrow) value).source.ordinal));
			return;
		}
		if (value is CoreAsyncOperation) {
			var operation = (CoreAsyncOperation) value;
			line (indentation, "(virtual-" + operation.contract.kind.to_string ());
			if (operation.executor != null) {
				write_value (operation.executor, indentation + 1);
			}
			if (operation.task != null) {
				write_value (operation.task, indentation + 1);
			}
			if (operation.argument != null) {
				write_value (operation.argument, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		if (value is CoreClassUpcast) {
			var cast = (CoreClassUpcast) value;
			line (indentation, "(class-upcast class#%d -> class#%d : %s".printf (cast.source_class.ordinal, cast.target_class.ordinal, value.semantic_type.display_name ()));
			write_value (cast.reference, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (value is CoreEnumBufferValue) {
			var buffer = (CoreEnumBufferValue) value;
			line (indentation, "(enum-buffer-capture : " + value.semantic_type.display_name ());
			if (buffer.source != null) {
				line (indentation + 1, "(reserve local#%d)".printf (buffer.source.place.ordinal));
			} else {
				write_value (buffer.producer, indentation + 1);
			} line (indentation, ")");
			return;
		}
		if (value is CoreEnumScalarValue) {
			var scalar = (CoreEnumScalarValue) value;
			line (indentation, "(enum-scalar-capture : %s reserve=local#%d cleanup=#%d)".printf (value.semantic_type.display_name (), scalar.source.place.ordinal, scalar.cleanup.ordinal));
			return;
		}
		if (value is CoreEnumArgument) {
			line (indentation, "(enum-argument");
			write_enum_producer (((CoreEnumArgument) value).producer, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (value is CoreEnumEquality) {
			var equality = (CoreEnumEquality) value;
			line (indentation, equality.unequal ? "(enum-not-equal" : "(enum-equal");
			write_enum_producer (equality.left, indentation + 1);
			write_enum_producer (equality.right, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (value is CoreOwnedBufferAllocate) {
			var allocation = (CoreOwnedBufferAllocate) value;
			line (indentation, "(owned-buffer-allocate element=%s (cleanup #%d) zero-initialize".printf (((Astra.Semantic.SliceType) value.semantic_type).element_type.display_name (), allocation.cleanup.ordinal));
			write_value (allocation.count, indentation + 1);
			if (allocation.failure_call != null) {
				line (indentation + 1, "(allocator-null trap-if-returned");
				write_statement (allocation.failure_call, indentation + 2);
				line (indentation + 1, ")");
			}
			line (indentation, ")");
			return;
		}
		if (value is CoreOwnedBufferBorrow) {
			var borrow = (CoreOwnedBufferBorrow) value;
			line (indentation, "(owned-buffer-borrow owner=local#%d slice=%s bounded non-owning)".printf (borrow.source.place.ordinal, value.semantic_type.display_name ()));
			return;
		}
		if (value is CoreSlotsTake) {
			var take = (CoreSlotsTake) value;
			line (indentation, "(owner-slots-take");
			write_place (take.store, indentation + 1);
			write_value (take.index, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (value is CoreSlotsValue) {
			var v = (CoreSlotsValue) value;
			line (indentation, "(owner-slots-%s".printf (v.action.to_string ()));
			write_place (v.store, indentation + 1);
			if (v.operand != null) {
				write_value (v.operand, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		if (value is CoreOwnedFieldBorrow) {
			line (indentation, "(owned-field-borrow temporary-noescape");
			write_place (((CoreOwnedFieldBorrow) value).source, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (value is CoreStructArgument) {
			var argument = (CoreStructArgument) value;
			line (indentation, argument.parameter == null ? "(struct-argument callable-signature snapshot-at-argument" : "(struct-argument #%d snapshot-at-argument".printf (argument.parameter.ordinal));
			write_struct_producer (argument.producer, indentation + 1);
			line (indentation, ")");
			return;
		}
		var construction = value as CoreOwnedObjectResultConstruction;
		if (construction != null) {
			line (indentation, "(return-object-construct (result-storage) (constructor %s::init)".printf (construction.storage.object_class.name));
			foreach (var argument in construction.arguments) {
				write_value (argument, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		var object_receiver = value as CoreObjectReceiverValue;
		if (object_receiver != null) {
			line (indentation, "(object-receiver : %s null-traps-before-arguments".printf (value.semantic_type.display_name ()));
			write_value (object_receiver.reference, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (value is CoreReceiverValue) {
			line (indentation, "(this : %s)".printf (value.semantic_type.display_name ()));
			return;
		}
		var slice = value as CoreSliceFromArrayValue;
		if (slice != null) {
			line (indentation, "(slice-from-array (storage #%d : %s) : %s (region #%d)%s".printf (slice.storage.ordinal, slice.array_type.display_name (), value.semantic_type.display_name (), slice.provenance.region_ordinal, slice.start == null ? " full" : " range-trap"));
			if (slice.start != null) {
				write_value (slice.start, indentation + 1);
				write_value (slice.count, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		var length = value as CoreSliceLengthValue;
		if (length != null) {
			line (indentation, "(slice-length : int");
			write_value (length.slice, indentation + 1);
			line (indentation, ")");
			return;
		}
		var argument = value as CoreOwnedArgumentValue;
		if (argument != null) {
			line (indentation, "(owned-transfer-argument (parameter #%d) %s : %s (cleanup #%d))".printf (argument.parameter.ordinal, argument.producer != null ? "fresh-owned-producer" : argument.source == null ? "owned-null" : "(move owner #%d)".printf (argument.source.place.ordinal), argument.semantic_type.display_name (), argument.cleanup.ordinal));
			if (argument.producer != null) {
				write_value (argument.producer, indentation + 1);
			}
			return;
		}
		var borrow = value as CoreOwnedBorrowValue;
		if (borrow != null) {
			line (indentation, "(borrow-owner #%d \"%s\" : %s)".printf (borrow.source.place.ordinal, borrow.source.place.name, borrow.semantic_type.display_name ()));
			return;
		}
		var address = value as CoreAddressOfValue;
		if (address != null && address.receiver_place != null) {
			line (indentation, "(receiver-address : %s".printf (value.semantic_type.display_name ()));
			write_place (address.receiver_place, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (address != null) {
			line (indentation, "(address-of : %s".printf (value.semantic_type.display_name ()));
			write_place (address.target, indentation + 1);
			line (indentation, ")");
			return;
		}
		var c_call = value as CoreCCallValue;
		if (c_call != null) {
			write_call ("c-call", c_call.target.name, c_call.target.return_type.display_name (), c_call.arguments, indentation);
			return;
		}
		var call = value as CoreCallValue;
		if (call != null) {
			if (call.candidate_storage != null) {
				line (indentation, "(candidate-storage #%d)".printf (call.candidate_storage.ordinal));
			}
			if (call.result_storage != null) {
				line (indentation, "(forward-result-storage)");
			}
			write_call ("call", call.target.name, call.semantic_type.display_name (), call.arguments, indentation, call.target as CoreMethod, call.receiver, call.target as CorePropertyAccessor, (call is CoreGenericCall) ? ((CoreGenericCall) call).type_arguments : null);
			return;
		}
		var load = value as CoreLoadValue;
		if (load != null) {
			line (indentation, "(%s : %s".printf (load.volatile_enabled ? "volatile-load" : "load", load.semantic_type.display_name ()));
			write_place (load.source, indentation + 1);
			line (indentation, ")");
			return;
		}
		string type_name = value.semantic_type.display_name ();
		if (value is CoreNullPointerValue) {
			line (indentation, "(null : %s)".printf (type_name));
			return;
		}
		var boolean = value as CoreBooleanValue;
		if (boolean != null) {
			line (indentation, "(bool %s : %s)".printf (boolean.literal.spelling (), type_name));
			return;
		}
		var dot = value as CoreVectorDotValue;
		if (dot != null) {
			line (indentation, "(%s (source %s) (accumulator %s) (order %s)".printf (dot.dot_kind.spelling (), dot.source_type.display_name (), dot.destination_type.display_name (), dot.dot_kind.order ()));
			if (dot.accumulator != null) {
				write_value (dot.accumulator, indentation + 1);
			}
			write_value (dot.first, indentation + 1);
			write_value (dot.second, indentation + 1);
			line (indentation, ")");
			return;
		}
		var dsp = value as CoreDspValue;
		if (dsp != null) {
			line (indentation, "(%s (from %s) (to %s)".printf (dsp.primitive_kind.spelling (), dsp.source_type.display_name (), dsp.destination_type.display_name ()));
			write_value (dsp.first, indentation + 1);
			if (dsp.second != null) {
				write_value (dsp.second, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		var capability = value as CoreGenericCapabilityOperation;
		if (capability != null) {
			line (indentation, "(generic-op %s (capability %s) (type-parameter #%d %s) : %s".printf (capability.operator_kind.operation_name (), capability.capability.spelling (), capability.type_parameter.ordinal, capability.type_parameter.semantic_type.name, capability.semantic_type.display_name ()));
			write_value (capability.left, indentation + 1);
			if (capability.right != null) {
				write_value (capability.right, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		var shift = value as CoreIntegerShiftValue;
		if (shift != null) {
			line (indentation, "(%s : %s (valid-range 0 %u) (invalid-count trap)".printf (shift.shift_kind.operation_name (value.semantic_type), type_name, shift.element_bit_width - 1));
			line (indentation + 1, "(value");
			write_value (shift.operand, indentation + 2);
			line (indentation + 1, ")");
			line (indentation + 1, "(count");
			write_value (shift.count, indentation + 2);
			line (indentation + 1, ")");
			line (indentation, ")");
			return;
		}
		var numeric_conversion = value as CoreNumericConversionValue;
		if (numeric_conversion != null) {
			line (indentation, "(numeric-convert (from %s) (to %s) (kind %s) (policy %s)".printf (numeric_conversion.source_type.display_name (), numeric_conversion.destination_type.display_name (), numeric_conversion.conversion_kind.spelling (), numeric_conversion.policy.spelling ()));
			write_value (numeric_conversion.operand, indentation + 1);
			line (indentation, ")");
			return;
		}
		var floating_conversion = value as CoreFloatConversionValue;
		if (floating_conversion != null) {
			line (indentation, "(float-convert (from %s) (to %s) (mode %s)".printf (floating_conversion.source_type.display_name (), floating_conversion.destination_type.display_name (), floating_conversion.conversion_kind.mode ()));
			write_value (floating_conversion.operand, indentation + 1);
			line (indentation, ")");
			return;
		}
		var conversion = value as CoreIntegerConversionValue;
		if (conversion != null) {
			line (indentation, "(%s (from %s) (to %s)".printf ((conversion.source_type is Semantic.VectorType) ? "integer-vector-convert" : "integer-convert", conversion.source_type.display_name (), conversion.destination_type.display_name ()));
			line (indentation + 1, "(value");
			write_value (conversion.operand, indentation + 2);
			line (indentation + 1, ")");
			line (indentation, ")");
			return;
		}
		var splat = value as CoreVectorSplatValue;
		if (splat != null) {
			line (indentation, "(vector-splat : %s".printf (value.semantic_type.display_name ()));
			line (indentation + 1, "(lanes %d)".printf (splat.lane_count));
			line (indentation + 1, "(value");
			write_value (splat.operand, indentation + 2);
			line (indentation + 1, ")");
			line (indentation, ")");
			return;
		}
		var extract = value as CoreVectorExtractValue;
		if (extract != null) {
			line (indentation, "(vector-extract : %s".printf (value.semantic_type.display_name ()));
			line (indentation + 1, "(lane %d)".printf (extract.index.ordinal));
			line (indentation + 1, "(vector");
			write_value (extract.vector, indentation + 2);
			line (indentation + 1, ")");
			line (indentation, ")");
			return;
		}
		var insert = value as CoreVectorInsertValue;
		if (insert != null) {
			line (indentation, "(vector-insert : %s".printf (value.semantic_type.display_name ()));
			line (indentation + 1, "(lane %d)".printf (insert.index.ordinal));
			line (indentation + 1, "(vector");
			write_value (insert.vector, indentation + 2);
			line (indentation + 1, ")");
			line (indentation + 1, "(value");
			write_value (insert.replacement, indentation + 2);
			line (indentation + 1, ")");
			line (indentation, ")");
			return;
		}
		var shuffle = value as CoreVectorShuffleValue;
		if (shuffle != null) {
			line (indentation, "(vector-shuffle : %s".printf (value.semantic_type.display_name ()));
			line (indentation + 1, "(lanes %s)".printf (shuffle.selectors.spelling ()));
			line (indentation + 1, "(vector");
			write_value (shuffle.vector, indentation + 2);
			line (indentation + 1, ")");
			line (indentation, ")");
			return;
		}
		if (value is CoreVectorMemoryValue) {
			var memory = (CoreVectorMemoryValue) value;
			line (indentation, "(vector-memory-%s align=%u : %s".printf (memory.stored == null ? "load" : "store", memory.contract.alignment, memory.contract.vector_type.display_name ()));
			write_value (memory.view, indentation + 1);
			write_value (memory.offset, indentation + 1);
			if (memory.stored != null) {
				write_value (memory.stored, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		var select = value as CoreVectorSelectValue;
		if (select != null) {
			line (indentation, "(vector-select : %s".printf (value.semantic_type.display_name ()));
			line (indentation + 1, "(mask");
			write_value (select.mask, indentation + 2);
			line (indentation + 1, ")");
			line (indentation + 1, "(true");
			write_value (select.true_value, indentation + 2);
			line (indentation + 1, ")");
			line (indentation + 1, "(false");
			write_value (select.false_value, indentation + 2);
			line (indentation + 1, ")");
			line (indentation, ")");
			return;
		}
		var vector = value as CoreVectorConstructValue;
		if (vector != null) {
			line (indentation, "(vector-init : %s".printf (value.semantic_type.display_name ()));
			foreach (var lane in vector.lanes) {
				write_value (lane, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		var reduction = value as CoreVectorReductionValue;
		if (reduction != null) {
			line (indentation, "(vector-%s : %s".printf (reduction.operator_kind.spelling (), value.semantic_type.display_name ()));
			write_value (reduction.operand, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (value is CoreUtf8FactoryValue) {
			var operation = (CoreUtf8FactoryValue) value;
			line (indentation, "(utf8-%s parameter#%d : %s)".printf (operation.validates ? "validate" : "certified-copy-input", operation.input.ordinal, value.semantic_type.display_name ()));
			return;
		}
		if (value is CoreTextValue) {
			var payload = ((CoreTextValue) value).payload;
			line (indentation, "(text (bytes %s) (hex %s) : string)".printf (payload.byte_length.to_string (), payload.hex ()));
			return;
		}
		if (value is CoreTextLengthValue) {
			line (indentation, "(text-byte-length : int");
			write_value (((CoreTextLengthValue) value).receiver, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (value is CoreFloatValue) {
			line (indentation, "(%s %s : %s)".printf (((CoreFloatValue) value).value.format.spelling (), ((CoreFloatValue) value).value.to_string (), value.semantic_type.display_name ()));
			return;
		}
		if (value is CoreWithReference) {
			line (indentation, "(with-reference " + ((CoreWithReference) value).contract.source.name + ")");
			return;
		}
		var integer = value as CoreIntegerValue;
		if (integer != null) {
			line (indentation, "(integer %s : %s)".printf (integer.value.to_string (), type_name));
			return;
		}
		var reference = value as CoreParameterValue;
		if (reference != null) {
			line (indentation, "(parameter #%d : %s)".printf (reference.parameter.ordinal, type_name));
			return;
		}
		var prefix = value as CorePrefixValue;
		if (prefix != null) {
			line (indentation, "(prefix %s : %s".printf (prefix.operator_kind.spelling (), type_name));
			write_value (prefix.operand, indentation + 1);
			line (indentation, ")");
			return;
		}
		var short_circuit = value as CoreShortCircuitValue;
		if (short_circuit != null) {
			line (indentation, "(short-circuit %s : %s".printf (short_circuit.operator_kind.spelling (), type_name));
			write_value (short_circuit.left, indentation + 1);
			write_value (short_circuit.right, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (value is CoreComparisonChain) {
			var chain = (CoreComparisonChain) value;
			line (indentation, "(comparison-chain : bool");
			for (int i = 0; i < chain.operands.length; i++) {
				if (i > 0) {
					line (indentation + 1, chain.operators[i - 1].spelling ());
				}
				write_value (chain.operands[i], indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		var binary = value as CoreBinaryValue;
		if (binary != null) {
			line (indentation, "(binary %s : %s".printf (binary.operator_kind.spelling (), type_name));
			write_value (binary.left, indentation + 1);
			write_value (binary.right, indentation + 1);
			line (indentation, ")");
			return;
		}
		throw new CoreError.INVALID_IR ("internal Core dump error: unsupported Core value");
	}

}
}
