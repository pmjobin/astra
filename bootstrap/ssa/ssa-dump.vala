// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Ssa {
// Verified internal debugging format, not a serialization contract.
public class SsaDump : Object {
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

	public static string format(SsaProgram program, bool explain_optimizations = false) throws SsaError {
		SsaVerifier.verify (program);
		if (program.enums.length == 0 && program.functions.length == 0 && program.c_functions.length == 0 && program.c_exports.length == 0 && program.structs.length == 0 && program.classes.length == 0 && program.cleanups.length == 0) {
			return "(ssa-program)\n";
		}
		var dump = new SsaDump ();
		dump.enums = program.enums;
		dump.line (0, "(ssa-program");
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
			if (structure is SsaStruct && ((SsaStruct) structure).representation != null && ((SsaStruct) structure).representation.is_union) {
				dump.line (1, ((SsaStruct) structure).representation.dump ());
			}
			dump.line (1, (structure is SsaClass) ? "(class #%d \"%s\"".printf (structure.ordinal, structure.name) : "(struct \"%s\"".printf (structure.name));
			if (structure is SsaClass && ((SsaClass) structure).allocation_policy != null) {
				dump.line (2, ((SsaClass) structure).allocation_policy.dump ());
			}
			if (structure is SsaClass && ((SsaClass) structure).foreign_export != null) {
				dump.line (2, ((SsaClass) structure).foreign_export.dump ());
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
				dump.line (2, "(field #%d \"%s\" : %s)".printf (field.ordinal, field.name, field.semantic_type.display_name ()));
			}
			dump.line (1, ")");
		}
		foreach (var cleanup in program.cleanups) {
			if (cleanup.is_buffer) {
				dump.line (1, "(cleanup #%d native-buffer-deallocate : %s)".printf (cleanup.ordinal, cleanup.buffer_type.display_name ()));
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
		for (int i = 0; i < program.functions.length; i++) {
			if (explain_optimizations && program.functions[i].effect_facts != null) {
				dump.line (1, "(derived-effects #%d flags=%u)".printf (i, program.functions[i].effect_facts.flags));
			}
			if (explain_optimizations) {
				foreach (var root in program.functions[i].stack_objects) {
					dump.line (1, "(stack-object function=#%d storage=#%d exact-call-local)".printf (i, root.ordinal));
				}
			}
			if (explain_optimizations) {
				foreach (var block in program.functions[i].blocks) {
					foreach (var instruction in block.instructions) {
						var call = instruction as SsaCallInstruction;
						if (call != null && call.exact_target != null) {
							dump.line (1, "(exact-call function=#%d block=#%d target=#%d)".printf (i, block.ordinal, call.exact_target.ordinal));
						}
					}
				}
			}
			if (explain_optimizations) {
				foreach (var plan in program.functions[i].shared_elisions) {
					dump.line (1, "(shared-elision function=#%d result=%%%d fresh-count-one-unused-temporary)".printf (i, plan.acquisition.result.ordinal));
				}
			}
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

	private string value(SsaValue value) {
		if (value is SsaCallbackView) {
			return "(captured-callback-view " + this.value (((SsaCallbackView) value).closure) + " : " + value.semantic_type.display_name () + ")";
		}
		if (value is SsaFunctionAddress) {
			return "(function-address %s : %s)".printf (((SsaFunctionAddress) value).target.name, value.semantic_type.display_name ());
		}
		if (value is SsaTaskAbsent) {
			return "task-absent";
		}
		if (value is SsaEnumArgument) {
			return "(enum-argument slot#%d snapshot)".printf (((SsaEnumArgument) value).source.ordinal);
		}
		if (value is SsaResultObjectStorage || value is SsaResultStorageReceiverValue) {
			return "%result.storage";
		}
		if (value is SsaTextConstant) {
			var payload = ((SsaTextConstant) value).payload;
			return "(text (bytes %s) (hex %s) : string)".printf (payload.byte_length.to_string (), payload.hex ());
		}
		if (value is SsaFloatConstant) {
			return "(%s %s : %s)".printf (((SsaFloatConstant) value).value.format.spelling (), ((SsaFloatConstant) value).value.to_string (), value.semantic_type.display_name ());
		}
		var integer = value as SsaIntegerConstant;
		if (integer != null) {
			return "(integer %s : %s)".printf (integer.value.to_string (), integer.semantic_type.display_name ());
		}
		if (value is SsaNullPointerConstant) {
			return "(null : %s)".printf (value.semantic_type.display_name ());
		}
		var boolean = value as SsaBooleanConstant;
		if (boolean != null) {
			return "(bool %s : bool)".printf (boolean.literal.spelling ());
		}
		return "%%%d".printf (((SsaDefinition) value).ordinal);
	}

	private string place(SsaMemoryPlace place) {
		var object_field = place as SsaObjectFieldPlace;
		if (object_field != null) {
			return "(object-field-initialize-place (storage #%d) (field #%d) : %s)".printf (object_field.storage.ordinal, object_field.field.ordinal, place.semantic_type.display_name ());
		}
		var slice = place as SsaSliceElementPlace;
		if (slice != null) {
			return "(slice-element-place (slice %s) (index %s) : %s runtime-bounds-trap)".printf (value (slice.slice), value (slice.index), slice.semantic_type.display_name ());
		}
		var array = place as SsaArrayElementPlace;
		if (array != null) {
			return "(array-element-place (storage #%d) %s : %s bounds-trap)".printf (array.storage.ordinal, value (array.index), array.array_type.display_name ());
		}
		var local = place as SsaLocalMemoryPlace;
		if (local != null) {
			return "(local-memory (storage #%d) : %s)".printf (local.storage.ordinal, place.semantic_type.display_name ());
		}
		var dereference = place as SsaDereferencePlace;
		if (dereference != null) {
			return "(dereference-place %s : %s null-traps)".printf (value (dereference.pointer), place.semantic_type.display_name ());
		}
		var projection = (SsaFieldPlace) place;
		if (projection.aggregate != null) {
			return "(field-place (base %s) (field %s::%s #%d) : %s)".printf (this.place (projection.aggregate), projection.field.containing_type.name, projection.field.name, projection.field.ordinal, place.semantic_type.display_name ());
		}
		var field = ((SsaFieldPlace) place).field;
		var direct = place as SsaDirectFieldPlace;
		string base_name = direct != null ? "direct-field (storage #%d)".printf (direct.storage.ordinal) : "indirect-field " + value (((SsaIndirectFieldPlace) place).pointer);
		return "(%s (%s \"%s\" field #%d \"%s\") : %s)".printf (base_name, (field.containing_type is SsaClass) ? "class" : "struct", field.containing_type.name, field.ordinal, field.name, place.semantic_type.display_name ());
	}

	private string edge(string name, SsaEdge edge) {
		var text = new StringBuilder ("(%s #%d (".printf (name, edge.target.ordinal));
		for (int i = 0; i < edge.arguments.length; i++) {
			if (i > 0) {
				text.append_c (' ');
			}
			text.append (value (edge.arguments[i]));
		}
		text.append ("))");
		return text.str;
	}

	private string buffer_pair(SsaBufferPair pair) {
		return "(PTR " + value (pair.base_value) + " I32 " + value (pair.length_value) + ")";
	}
	private string buffer_place(SsaBufferPlace target) {
		return target.record_projection != null ? "(record-buffer-observation " + place (target.record_projection) + ")" : target.storage == null ? place(target.field) : "(buffer-storage #%d owner #%d)".printf (target.storage.ordinal, target.storage.owner_ordinal);
	}

	private void write_function(SsaFunction function) {
		if (function.floating_policy != 0) {
			line (1, "(floating-policy permissions=%u checked-domain=bounded)".printf (function.floating_policy));
		}
		var method = function as SsaMethod;
		if (function is SsaPropertyAccessor) {
			var accessor = (SsaPropertyAccessor) function;
			var property = accessor.property_member;
			line (1, "(property-%s #%d (property %s::%s #%d) (declaring-%s #%d) -> %s".printf ((function is SsaPropertyGetter) ? "getter" : "setter", property.ordinal, property.declaring_type.name, property.name, property.ordinal, (property.declaring_type is SsaClass) ? "class" : "struct", property.declaring_type.ordinal, function.return_type.display_name ()));
			line (2, "(receiver %%%d : %s live mutable nonnull non-owning)".printf (accessor.receiver.ordinal, accessor.receiver.contract.display_name ()));
		} else if (function is SsaLifecycle) {
			var lifecycle = (SsaLifecycle) function;
			line (1, "(%s (class #%d) (member #%d)".printf ((function is SsaConstructor) ? "constructor" : "destructor", lifecycle.declaring_class.ordinal, lifecycle.member_ordinal));
			line (2, "(receiver %s %s nonnull mutable)".printf ((function is SsaConstructor) ? "initializing" : "live", lifecycle.declaring_class.name));
		} else if (method == null) {
			line (1, "(function #%d \"%s\" -> %s".printf (function.ordinal, function.name.escape (), function.return_type.display_name ()));
		} else {
			line (1, "(method #%d \"%s\" (declaring-%s #%d \"%s\") (member #%d) -> %s".printf (method.method_ordinal, method.name.escape (), (method.declaring_type is SsaClass) ? "class" : "struct", method.declaring_type.ordinal, method.declaring_type.name.escape (), method.member_ordinal, method.return_type.display_name ()));
			line (2, "(receiver %%%d : %s mutable nonnull non-owning)".printf (method.receiver.ordinal, method.receiver.contract.display_name ()));
		}
		foreach (var group in function.struct_parameters) {
			line (2, "(struct-parameter #%d : %s %s (leaves %d %u))".printf (group.source_ordinal, group.shape.semantic_type.display_name (), group.shape.mode.spelling (), group.first_leaf, group.shape.leaves.length));
		}
		if (function.struct_result != null) {
			line (2, "(struct-result : %s (leaves %u))".printf (function.struct_result.semantic_type.display_name (), function.struct_result.leaves.length));
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
		if (function.parameters.length == 0) {
			line (2, "(parameters)");
		} else {
			line (2, "(parameters");
			for (int i = 0; i < function.parameters.length; i++) {
				var parameter = function.parameters[i];
				line (3, "(%%%d \"%s\" : %s%s)".printf (parameter.ordinal, parameter.name.escape (), parameter.semantic_type.display_name (), parameter.pointer_contract.dump_suffix ()));
			}
			line (2, ")");
		}
		foreach (var storage in function.storage) {
			line (2, "(storage #%d \"%s\" (local #%d) : %s address-taken)".printf (storage.ordinal, storage.name, storage.source_local_ordinal, storage.semantic_type.display_name ()));
		}
		foreach (var slot in function.enum_slots) {
			line (2, "(enum-slot #%d : %s source-local#%d stack-value)".printf (slot.ordinal, slot.definition.semantic_type.display_name (), slot.source_ordinal));
		}
		line (2, "(entry #%d)".printf (function.entry.ordinal));
		foreach (var slot in function.buffer_storage) {
			line (2, "(buffer-storage #%d (owner #%d) PTR+I32 (cleanup #%d))".printf (slot.ordinal, slot.owner_ordinal, slot.cleanup.ordinal));
		}
		foreach (var parameter in function.buffer_parameters) {
			line (2, "(owned-buffer-parameter #%d %s (cleanup #%d))".printf (parameter.source_ordinal, buffer_pair (parameter.pair), parameter.cleanup.ordinal));
		}

		for (int b = 0; b < function.blocks.length; b++) {
			var block = function.blocks[b];
			line (2, "(block #%d".printf (block.ordinal));
			if (block.parameters.length > 0) {
				line (3, "(arguments");
				for (int p = 0; p < block.parameters.length; p++) {
					var parameter = block.parameters[p];
					if (parameter.origin_kind == SsaPromotionOrigin.FIELD) {
						line (4, "(%%%d \"%s\" (local #%d field #%d) : %s)".printf (parameter.ordinal, parameter.name.escape (), parameter.origin_ordinal, parameter.source_field_ordinal, parameter.semantic_type.display_name ()));
						continue;
					}
					if (parameter.origin_kind == SsaPromotionOrigin.TEMPORARY) {
						line (4, "(%%%d (temporary #%d) : %s)".printf (parameter.ordinal, parameter.origin_ordinal, parameter.semantic_type.display_name ()));
					} else {
						line (4, "(%%%d \"%s\" : %s)".printf (parameter.ordinal, parameter.name.escape (), parameter.semantic_type.display_name ()));
					}
				}
				line (3, ")");
			}
			for (int i = 0; i < block.instructions.length; i++) {
				var instruction = block.instructions[i];
				if (instruction is SsaTaskCreate) {
					var task = (SsaTaskCreate) instruction;
					var captures = new StringBuilder ();
					if (task.allocation_context != null) {
						captures.append (" (frame-context " + value (task.allocation_context) + ")");
					}
					foreach (var capture in task.arguments) {
						captures.append (" " + value (capture));
					}
					line (3, "(%%%d = task-create cold %s%s)".printf (task.result.ordinal, task.target.name, captures.str));
					continue;
				}
				if (instruction is SsaFrameCatchEvent) {
					var event = (SsaFrameCatchEvent) instruction;
					line (3, "(frame-catch-owner #%d %s)".printf (event.owner.ordinal, value (event.source)));
					continue;
				}
				if (instruction is SsaTaskWait) {
					var wait = (SsaTaskWait) instruction;
					line (3, "(%%%d = task-wait%s %s)".printf (wait.result.ordinal, wait.discard ? " discard-and-drain" : "", value (wait.child)) + (wait.bridge_executor == null ? "" : " (worker-bridge " + value (wait.bridge_executor) + ")"));
					continue;
				}
				if (instruction is SsaTaskBorrow) {
					var task = (SsaTaskBorrow) instruction;
					line (3, "(%%%d = task-borrow local#%d %s)".printf (task.result.ordinal, task.owner_ordinal, value (task.source)));
					continue;
				}
				if (instruction is SsaTaskStarted) {
					line (3, "(task-started local#%d)".printf (((SsaTaskStarted) instruction).owner_ordinal));
					continue;
				}
				if (instruction is SsaExecutorEnd) {
					line (3, "(executor-scope-end %s)".printf (value (((SsaExecutorEnd) instruction).source)));
					continue;
				}
				if (instruction is SsaAsyncRunStatus) {
					line (3, "(run-status-publish)");
					continue;
				}
				if (instruction is SsaAsyncOperation) {
					var operation = (SsaAsyncOperation) instruction;
					line (3, "(virtual-%s%s%s%s%s)".printf (operation.contract.kind.to_string (), operation.result == null ? "" : " result=%" + operation.result.ordinal.to_string (), operation.executor == null ? "" : " " + value (operation.executor), operation.task == null ? "" : " " + value (operation.task), operation.argument == null ? "" : " " + value (operation.argument)));
					continue;
				}
				if (instruction is SsaTaskSuccess) {
					var success = (SsaTaskSuccess) instruction;
					line (3, "(task-success%s %s)".printf (success.buffer_result == null ? "" : " owned-buffer", value (success.operation.result)));
					continue;
				}
				if (instruction is SsaTaskAcquire) {
					var task = (SsaTaskAcquire) instruction;
					line (3, "(task-acquire local#%d %s)".printf (task.owner_ordinal, value (task.source)));
					continue;
				}
				if (instruction is SsaTaskMove) {
					line (3, "(%%%d = task-move local#%d %s)".printf (instruction.result.ordinal, ((SsaTaskMove) instruction).owner_ordinal, value (((SsaTaskMove) instruction).source)));
					continue;
				}
				if (instruction is SsaTaskEnd) {
					line (3, "(task-scope-end local#%d %s)".printf (((SsaTaskEnd) instruction).owner_ordinal, value (((SsaTaskEnd) instruction).source)));
					continue;
				}
				if (instruction is SsaAsyncDelay) {
					line (3, (((SsaAsyncDelay) instruction).payload ? "(linux-payload-suspend %s)" : "(virtual-suspend %s)").printf (value (((SsaAsyncDelay) instruction).ticks)));
					continue;
				}
				if (instruction is SsaOwnedArgumentReservation) {
					var reservation = (SsaOwnedArgumentReservation) instruction;
					line (3, "(argument-reserve consumer#%d owner#%d %s)".printf (((reservation.consumer as SsaCallInstruction) != null ? ((SsaCallInstruction) reservation.consumer).target.ordinal : -1), reservation.owner_ordinal, reservation.pair == null ? value (reservation.value) : buffer_pair (reservation.pair)));
					continue;
				}
				if (instruction is SsaOwnedArgumentAbort) {
					var reservation = ((SsaOwnedArgumentAbort) instruction).reservation;
					line (3, "(argument-abort consumer#%d owner#%d)".printf (((reservation.consumer as SsaCallInstruction) != null ? ((SsaCallInstruction) reservation.consumer).target.ordinal : -1), reservation.owner_ordinal));
					continue;
				}
				if (instruction is SsaExceptionTransfer) {
					var transfer = (SsaExceptionTransfer) instruction;
					line (3, "(%%%d = exception-transfer %s owner#%d disarm=%s)".printf (transfer.result.ordinal, value (transfer.source), transfer.owner_ordinal, value (transfer.disarmed)));
					continue;
				}
				if (instruction is SsaConstructorAbort) {
					var abort = (SsaConstructorAbort) instruction;
					line (3, "(constructor-abort fields=%u lazy=%u reverse-acquisition conditional-initialization)".printf (abort.fields.length, abort.lazy_properties.length));
					continue;
				}
				if (instruction is SsaExceptionStamp) {
					line (3, "(exception-original-origin %s)".printf (value (((SsaExceptionStamp) instruction).exception)));
					continue;
				}
				if (instruction is SsaExceptionMatch) {
					var match = (SsaExceptionMatch) instruction;
					line (3, "(%%%d = exception-subtype %s class=%s)".printf (match.result.ordinal, value (match.exception), match.match_type.display_name ()));
					continue;
				}
				if (instruction is SsaLazyObserve) {
					var observe = (SsaLazyObserve) instruction;
					line (3, "(%%%d = lazy-observe receiver-borrow %s::%s)".printf (observe.result.ordinal, observe.property_member.declaring_type.name, observe.property_member.name));
					continue;
				}
				if (instruction is SsaLazyDrop) {
					var property = ((SsaLazyDrop) instruction).property_member;
					line (3, "(lazy-owner-retire %s::%s)".printf (property.declaring_type.name, property.name));
					continue;
				}
				if (instruction is SsaCatchBorrow) {
					var caught = (SsaCatchBorrow) instruction;
					line (3, "(%%%d = catch-borrow %s : %s)".printf (caught.result.ordinal, value (caught.exception), caught.result.semantic_type.display_name ()));
					continue;
				}
				if (instruction is SsaCallSuccess) {
					var success = (SsaCallSuccess) instruction;
					line (3, "(%%%d = call-success target#%d private=%s)".printf (success.result.ordinal, success.call.target.ordinal, value (success.call.exception_result)));
					continue;
				}
				if (instruction is SsaGroupCallSuccess) {
					var success = (SsaGroupCallSuccess) instruction;
					line (3, "(call-success-group target#%d private=%s)".printf (success.call.target.ordinal, value (success.call.exception_result)));
					continue;
				}
				if (instruction is SsaClassUpcast) {
					var cast = (SsaClassUpcast) instruction;
					line (3, "(%%%d = class-upcast %s class#%d -> class#%d : %s)".printf (cast.result.ordinal, value (cast.reference), cast.source_class.ordinal, cast.target_class.ordinal, cast.result.semantic_type.display_name ()));
					continue;
				}

				if (instruction is SsaEnumScalarCapture) {
					var capture = (SsaEnumScalarCapture) instruction;
					line (3, "(enum-scalar-reserve owner#%d %s cleanup=#%d)".printf (capture.owner.source_ordinal, value (capture.pointer), capture.owner.cleanup.ordinal));
					continue;
				}
				if (instruction is SsaEnumScalarAbort) {
					line (3, "(enum-scalar-abort owner#%d)".printf (((SsaEnumScalarAbort) instruction).capture.owner.source_ordinal));
					continue;
				}
				if (instruction is SsaEnumScalarCommit) {
					var commit = (SsaEnumScalarCommit) instruction;
					line (3, "(enum-scalar-commit owner#%d field#%d)".printf (commit.capture.owner.source_ordinal, commit.field.identity.ordinal));
					continue;
				}
				if (instruction is SsaEnumReadRecord) {
					var read = (SsaEnumReadRecord) instruction;
					line (3, "(enum-extract-record slot#%d field#%d binding#%d leaves=%u)".printf (read.source.ordinal, read.field.identity.ordinal, read.binding.local_ordinal, read.results.leaves.length));
					continue;
				}
				if (instruction is SsaEnumReadScalar) {
					var read = (SsaEnumReadScalar) instruction;
					line (3, "(%%%d = enum-extract-owner slot#%d field#%d owner#%d cleanup=#%d)".printf (read.result.ordinal, read.source.ordinal, read.field.identity.ordinal, read.owner.source_ordinal, read.owner.cleanup.ordinal));
					continue;
				}
				if (instruction is SsaEnumCommit) {
					line (3, "(enum-commit slot#%d)".printf (((SsaEnumCommit) instruction).captured.ordinal));
					continue;
				}
				if (instruction is SsaEnumDrop) {
					line (3, "(enum-drop-active slot#%d)".printf (((SsaEnumDrop) instruction).source.ordinal));
					continue;
				}
				if (instruction is SsaEnumEndInspection) {
					line (3, "(enum-end-inspection slot#%d)".printf (((SsaEnumEndInspection) instruction).source.ordinal));
					continue;
				}
				if (instruction is SsaEnumReadBuffer) {
					var extract = (SsaEnumReadBuffer) instruction;
					line (3, "(enum-extract-buffer slot#%d field#%d -> %s %s)".printf (extract.source.ordinal, extract.field.identity.ordinal, value (extract.pair.base_value), value (extract.pair.length_value)));
					continue;
				}
				if (instruction is SsaEnumFinishArm) {
					var finish = (SsaEnumFinishArm) instruction;
					var text = new StringBuilder ("(enum-finish-arm slot#%d retain".printf (finish.source.ordinal));
					for (uint f = 0; f < finish.retained_count; f++) {
						text.append (" field#%d".printf (finish.field (f).identity.ordinal));
					}
					text.append (")");
					line (3, text.str);
					continue;
				}
				if (instruction is SsaStructParameterBorrow) {
					var binding = (SsaStructParameterBorrow) instruction;
					line (3, "(record-parameter-borrow parameter=#%d leaves=%u)".printf (binding.parameter.source_ordinal, binding.leaves.length));
					continue;
				}
				if (instruction is SsaStructBoundary) {
					var record = (SsaStructBoundary) instruction;
					line (3, "(record-move-value-%s #%d projection=%s leaves=%u owners=%u)".printf ((record is SsaStructBoundaryAcquire) ? "acquire" : "commit", record.source_ordinal, record.projection == null ? "root" : record.projection.spelling (), record.leaves.length, record.owners.length));
					continue;
				}
				if (instruction is SsaRecordAcquire) {
					var record = (SsaRecordAcquire) instruction;
					line (3, "(record-acquire #%d path=%s %s)".printf (record.owner.source_ordinal, record.path.spelling (), value (record.pointer)));
					continue;
				}
				if (instruction is SsaRecordTake) {
					var take = (SsaRecordTake) instruction;
					line (3, "(record-field-take #%d path=%s destination=#%d %s)".printf (take.source.source_ordinal, take.path.spelling (), take.destination.source_ordinal, value (take.pointer)));
					continue;
				}
				if (instruction is SsaRecordReplace) {
					var replace = (SsaRecordReplace) instruction;
					line (3, "(record-field-replace #%d path=%s old=%s incoming=%s)".printf (replace.owner.source_ordinal, replace.path.spelling (), value (replace.old_value), value (replace.incoming)));
					continue;
				}
				if (instruction is SsaRecordMove) {
					var record = (SsaRecordMove) instruction;
					line (3, "(record-move #%d -> #%d %s)".printf (record.source.source_ordinal, record.destination.source_ordinal, value (record.pointer)));
					continue;
				}
				if (instruction is SsaHeapOwnerEvent) {
					var event = (SsaHeapOwnerEvent) instruction;
					line (3, "(heap-owner #%d %s %s)".printf (event.owner == null ? -1 : event.owner.source_ordinal, event.action.to_string (), value (event.value)));
					continue;
				}
				if (instruction is SsaEnumBufferCapture) {
					var capture = (SsaEnumBufferCapture) instruction;
					line (3, "(enum-buffer-reserve %s fresh=%s)".printf (buffer_pair (capture.pair), capture.fresh.to_string ()));
					continue;
				}
				if (instruction is SsaEnumBufferAbort) {
					line (3, "(enum-buffer-abort %s)".printf (buffer_pair (((SsaEnumBufferAbort) instruction).capture.pair)));
					continue;
				}
				if (instruction is SsaEnumConstruct) {
					var construct = (SsaEnumConstruct) instruction;
					line (3, "(enum-construct slot#%d %s.%s".printf (construct.destination.ordinal, construct.destination.definition.semantic_type.display_name (), construct.variant.identity.name));
					foreach (var field in construct.fields) {
						var text = new StringBuilder ("(field#%d %s".printf (field.field.identity.ordinal, field.field.identity.name));
						if (field.sum != null) {
							text.append (" slot#%d".printf (field.sum.ordinal));
						}
						foreach (var leaf in field.leaves) {
							text.append (" " + value (leaf));
						}
						text.append (")");
						line (4, text.str);
					}
					line (3, ")");
					continue;
				}
				if (instruction is SsaEnumCopy) {
					var copy = (SsaEnumCopy) instruction;
					line (3, "(enum-copy slot#%d <- slot#%d %s)".printf (copy.destination.ordinal, copy.source.ordinal, copy.initializes_destination ? "initialize" : "assign"));
					continue;
				}
				if (instruction is SsaEnumAcquire) {
					var acquire = (SsaEnumAcquire) instruction;
					line (3, "(enum-acquire slot#%d parameter#%d snapshot)".printf (acquire.destination.ordinal, acquire.parameter.ordinal));
					continue;
				}
				if (instruction is SsaEnumExtractSum) {
					var extract = (SsaEnumExtractSum) instruction;
					line (3, "(enum-extract slot#%d field#%d -> slot#%d snapshot)".printf (extract.source.ordinal, extract.field.identity.ordinal, extract.destination.ordinal));
					continue;
				}
				if (instruction is SsaEnumRead) {
					var read = (SsaEnumRead) instruction;
					line (3, "(%%%d = enum-payload slot#%d variant#%d field#%d%s : %s)".printf (read.result.ordinal, read.source.ordinal, read.field.identity.variant.ordinal, read.field.identity.ordinal, read.record_path == null ? "" : " path=" + read.record_path.spelling (), read.result.semantic_type.display_name ()));
					continue;
				}
				if (instruction is SsaEnumTagInstruction) {
					var tag = (SsaEnumTagInstruction) instruction;
					line (3, "(%%%d = enum-tag slot#%d)".printf (tag.result.ordinal, tag.source.ordinal));
					continue;
				}
				if (instruction is SsaBufferAllocateInstruction) {
					var operation = (SsaBufferAllocateInstruction) instruction;
					if (operation.failure != null) {
						line (3, "(owned-buffer-publish %s allocation-success)".printf (buffer_pair (operation.pair)));
						continue;
					}
					line (3, "(owned-buffer-allocate %s element=%s count=%s zero-initialize checked-count checked-size empty=null+0 trap-on-failure)".printf (buffer_pair (operation.pair), operation.pair.shape.slice_type.element_type.display_name (), value (operation.count)));
					continue;
				}
				if (instruction is SsaBufferSlotCaptureInstruction) {
					line (3, "(buffer-slot-capture %s)".printf (buffer_place (((SsaBufferSlotCaptureInstruction) instruction).place)));
					continue;
				}
				if (instruction is SsaBufferExchangeInstruction) {
					var operation = (SsaBufferExchangeInstruction) instruction;
					line (3, "(buffer-exchange %s %s capture-both-before-store)".printf (buffer_place (operation.left), buffer_place (operation.right)));
					continue;
				}
				if (instruction is SsaBufferReadInstruction) {
					var operation = (SsaBufferReadInstruction) instruction;
					line (3, "(buffer-read %s %s)".printf (buffer_place (operation.place), buffer_pair (operation.pair)));
					continue;
				}
				if (instruction is SsaBufferWriteInstruction) {
					var operation = (SsaBufferWriteInstruction) instruction;
					line (3, "(buffer-%s %s %s whole-group)".printf (operation.initializes ? "initialize" : operation.pair.is_empty ? "disarm" : "store", buffer_place (operation.place), buffer_pair (operation.pair)));
					continue;
				}
				if (instruction is SsaBufferDeallocateInstruction) {
					var operation = (SsaBufferDeallocateInstruction) instruction;
					line (3, "(buffer-deallocate %s (cleanup #%d) empty-no-op)".printf (buffer_pair (operation.pair), operation.cleanup.ordinal));
					continue;
				}
				if (instruction is SsaBufferBorrowInstruction) {
					var operation = (SsaBufferBorrowInstruction) instruction;
					line (3, "(%%%d : %s = buffer-borrow %s nonowning)".printf (operation.result.ordinal, operation.result.semantic_type.display_name (), buffer_pair (operation.pair)));
					continue;
				}
				if (instruction is SsaContinuationRegion) {
					var region = (SsaContinuationRegion) instruction;
					line (3, "(%%%d : int = internal-continuation-region families=%u actions=%u)".printf (region.result.ordinal, region.families.length, region.actions.length));
					continue;
				}
				if (instruction is SsaFallibleInputRestore) {
					var restore = (SsaFallibleInputRestore) instruction;
					line (3, "(%%%d = fallible-input-restore owner#%d original=%s if-allocation-refused else-empty)".printf (restore.result.ordinal, restore.owner.source_ordinal, value (restore.argument.value)));
					continue;
				}
				if (instruction is SsaFallibleBufferRestore) {
					var restore = (SsaFallibleBufferRestore) instruction;
					line (3, "(fallible-buffer-restore buffer#%d original=%s/%s if-allocation-refused else-empty)".printf (restore.argument.disarm.place.storage.owner_ordinal, value (restore.argument.pair.base_value), value (restore.argument.pair.length_value)));
					continue;
				}
				if (instruction is SsaFrameInputRestore) {
					var restore = (SsaFrameInputRestore) instruction;
					line (3, "(%%%d = frame-input-restore owner#%d original=%s if-frame-refused else-empty)".printf (restore.result.ordinal, restore.owner.source_ordinal, value (restore.argument.value)));
					continue;
				}
				if (instruction is SsaFrameBufferRestore) {
					var restore = (SsaFrameBufferRestore) instruction;
					line (3, "(frame-buffer-restore buffer#%d original=%s/%s if-frame-refused else-empty)".printf (restore.argument.disarm.place.storage.owner_ordinal, value (restore.argument.pair.base_value), value (restore.argument.pair.length_value)));
					continue;
				}
				if (instruction is SsaFallibleRecordRestore) {
					var restore = (SsaFallibleRecordRestore) instruction;
					line (3, "(fallible-record-restore local#%d : %s if-allocation-refused else-empty-owners copied-leaves-preserved)".printf (restore.original.source_ordinal, restore.results.shape.semantic_type.display_name ()));
					continue;
				}
				if (instruction is SsaFrameRecordRestore) {
					var restore = (SsaFrameRecordRestore) instruction;
					line (3, "(frame-record-restore local#%d : %s if-frame-refused else-empty-owners copied-leaves-preserved)".printf (restore.original.source_ordinal, restore.results.shape.semantic_type.display_name ()));
					continue;
				}
				var storage_receiver = instruction as SsaStorageReceiverInstruction;
				if (storage_receiver != null) {
					line (3, "(%%%d = storage-receiver #%d %s)".printf (storage_receiver.result.ordinal, storage_receiver.storage.ordinal, ((Astra.Semantic.ReceiverType) storage_receiver.result.semantic_type).mode == Astra.Semantic.ReceiverMode.INITIALIZING ? "initializing" : "live"));
					continue;
				}
				var object_reference = instruction as SsaObjectReferenceInstruction;
				if (object_reference != null) {
					line (3, "(%%%d : %s = object-ref (storage #%d))".printf (object_reference.result.ordinal, object_reference.result.semantic_type.display_name (), object_reference.storage.ordinal));
					continue;
				}
				var object_validation = instruction as SsaObjectValidateInstruction;
				if (object_validation != null) {
					line (3, "(%%%d : %s = object-validate %s null-traps)".printf (object_validation.result.ordinal, object_validation.result.semantic_type.display_name (), value (object_validation.reference)));
					continue;
				}
				var validation = instruction as SsaValidatePlaceInstruction;
				if (validation != null) {
					line (3, "(validate-place %s null-traps)".printf (place (validation.place)));
					continue;
				}
				var initialization = instruction as SsaInitializeInstruction;
				var slice = instruction as SsaSliceConstructInstruction;
				if (slice != null) {
					line (3, "(%%%d : %s = slice-from-array (storage #%d : %s)%s (region #%d))".printf (slice.result.ordinal, slice.result.semantic_type.display_name (), slice.storage.ordinal, slice.array_type.display_name (), slice.start == null ? " full" : " (start " + value (slice.start) + ") (count " + value (slice.count) + ") range-trap", slice.provenance.region_ordinal));
					continue;
				}
				if (instruction is SsaUtf8FactoryInstruction) {
					var operation = (SsaUtf8FactoryInstruction) instruction;
					line (3, "(%%%d : %s = utf8-%s %s)".printf (operation.result.ordinal, operation.result.semantic_type.display_name (), operation.validates ? "validate" : "certified-copy-input", value (operation.input)));
					continue;
				}
				if (instruction is SsaTextLengthInstruction) {
					var text_length = (SsaTextLengthInstruction) instruction;
					line (3, "(%%%d : int = text-byte-length %s)".printf (text_length.result.ordinal, value (text_length.receiver)));
					continue;
				}
				var length = instruction as SsaSliceLengthInstruction;
				if (length != null) {
					line (3, "(%%%d : int = slice-length %s)".printf (length.result.ordinal, value (length.slice)));
					continue;
				}
				var slice_bounds = instruction as SsaSliceBoundsCheck;
				if (slice_bounds != null) {
					line (3, "(%%%d : %s = slice-bounds-check (slice %s) (index %s) runtime-length trap)".printf (slice_bounds.result.ordinal, slice_bounds.result.semantic_type.display_name (), value (slice_bounds.slice), value (slice_bounds.index)));
					continue;
				}
				var array = instruction as SsaArrayInitialize;
				if (array != null) {
					var text = new StringBuilder ("(array-initialize (storage #%d)".printf (array.storage.ordinal));
					if (array.record_root != null) {
						text.append (" (record-entry %d complete=%s)".printf (array.record_ordinal, array.completes_array.to_string ()));
						foreach (var field in array.record_fields) {
							text.append (" " + place (field));
						}
					}
					foreach (var element in array.elements) {
						text.append (" " + value (element));
					}
					line (3, text.str + ")");
					continue;
				}
				var bounds = instruction as SsaArrayBoundsCheck;
				if (bounds != null) {
					line (3, "(%%%d : %s = array-bounds-check (storage #%d length %d) %s trap)".printf (bounds.result.ordinal, bounds.result.semantic_type.display_name (), bounds.storage.ordinal, ((Astra.Semantic.ArrayType) bounds.storage.semantic_type).length, value (bounds.index)));
					continue;
				}
				var store = instruction as SsaStoreInstruction;
				if (initialization != null || store != null) {
					line (3, "(%s %s %s)".printf (store != null ? (store.volatile_enabled ? "volatile-store" : "store") : "initialize", place (store != null ? store.target : initialization.target), value (store != null ? store.value : initialization.value)));
					continue;
				}
				var load = instruction as SsaLoadInstruction;
				if (load != null) {
					line (3, "(%%%d : %s = %s %s)".printf (load.result.ordinal, load.result.semantic_type.display_name (), load.volatile_enabled ? "volatile-load" : "load", place (load.source)));
					continue;
				}
				var address = instruction as SsaAddressOfInstruction;
				if (address != null && address.receiver_place != null) {
					line (3, "(%%%d : %s = receiver-address %s)".printf (address.result.ordinal, address.result.semantic_type.display_name (), place (address.receiver_place)));
					continue;
				}
				if (address != null) {
					line (3, "(%%%d : %s = address-of (storage #%d))".printf (address.result.ordinal, address.result.semantic_type.display_name (), address.target.ordinal));
					continue;
				}
				var cleanup = instruction as SsaCleanupInstruction;
				if (instruction is SsaTextLoanBind) {
					var binding = (SsaTextLoanBind) instruction;
					line (3, "(text-loan-bind local#%d %s)".printf (binding.loan.local_ordinal, value (binding.value)));
					continue;
				}
				if (instruction is SsaNonNullUse) {
					var use = (SsaNonNullUse) instruction;
					line (3, "(nonnull-use local#%d %s)".printf (use.source_ordinal, value (use.value)));
					continue;
				}
				if (instruction is SsaTextLoanUse) {
					var use = (SsaTextLoanUse) instruction;
					line (3, "(text-loan-use local#%d %s)".printf (use.loan.local_ordinal, value (use.value)));
					continue;
				}
				if (instruction is SsaTextLoanEnd) {
					line (3, "(text-loan-end local#%d)".printf (((SsaTextLoanEnd) instruction).loan.local_ordinal));
					continue;
				}
				if (instruction is SsaSlotsRecordTransfer) {
					var transfer = (SsaSlotsRecordTransfer) instruction;
					line (3, "(record-slots-%s %s : %s %s)".printf (transfer.index == null ? "append" : "replace", transfer.shape.mode.spelling (), transfer.shape.semantic_type.display_name (), place (transfer.store)));
					continue;
				}
				if (instruction is SsaRecordFieldCommit) {
					var commit = (SsaRecordFieldCommit) instruction;
					line (3, "(record-field-commit %s initializes=%s leaves=%u)".printf (place (commit.destination), commit.initializes.to_string (), commit.leaves.length));
					continue;
				}
				if (instruction is SsaRecordFieldDrop) {
					line (3, "(record-field-drop %s)".printf (place (((SsaRecordFieldDrop) instruction).source)));
					continue;
				}
				if (instruction is SsaSlotsRecordRead) {
					var read = (SsaSlotsRecordRead) instruction;
					line (3, "(record-slots-%s %s : %s %s %s)".printf (read.remove ? "take" : "copy", read.results.shape.mode.spelling (), read.results.shape.semantic_type.display_name (), place (read.store), value (read.index)));
					continue;
				}
				if (instruction is SsaSlotsEffect) {
					var op = (SsaSlotsEffect) instruction;
					line (3, "(owner-slots-%s %s %s)".printf (op.action.to_string (), place (op.store), op.incoming == null ? "" : value (op.incoming)));
					continue;
				}
				if (instruction is SsaSlotsValueInstruction) {
					var op = (SsaSlotsValueInstruction) instruction;
					line (3, "(%%%d = owner-slots-%s %s %s)".printf (op.result.ordinal, op.action.to_string (), place (op.store), op.operand == null ? "" : value (op.operand)));
					continue;
				}
				if (instruction is SsaTextSnapshotDestroy) {
					line (3, "(snapshot-destroy %s)".printf (place (((SsaTextSnapshotDestroy) instruction).field)));
					continue;
				}
				if (cleanup != null) {
					line (3, "(cleanup %s via #%d)".printf (value (cleanup.value), cleanup.cleanup.ordinal));
					continue;
				}
				var c_call = instruction as SsaCCallInstruction;
				if (c_call != null) {
					var text = new StringBuilder ("(");
					if (c_call.result != null) {
						text.append ("%%%d : %s = ".printf (c_call.result.ordinal, c_call.result.semantic_type.display_name ()));
					}
					text.append ("c-call #%d \"%s\" -> %s (arguments".printf (c_call.target.ordinal, c_call.target.name.escape (), c_call.target.return_type.display_name ()));
					for (int a = 0; a < c_call.arguments.length; a++) {
						text.append (" " + value (c_call.arguments[a]));
					}
					text.append ("))");
					line (3, text.str);
					continue;
				}
				if (instruction is SsaStructResultConsume) {
					var consumption = (SsaStructResultConsume) instruction;
					var text = new StringBuilder ("(consume-struct-result %d : %s".printf ((int) consumption.use_kind, consumption.results.shape.semantic_type.display_name ()));
					foreach (var leaf in consumption.results.leaves) {
						text.append (" " + value (leaf));
					}
					text.append (")");
					line (3, text.str);
					continue;
				}
				if (instruction is SsaActorSend) {
					var send = (SsaActorSend) instruction;
					line (4, "%%%d = actor-%d sender=%s checked=%s message=%s".printf (send.result.ordinal, (int) send.action, value (send.sender), send.error_type.display_name (), send.message == null ? "none" : value (send.message)));
					continue;
				}
				if (instruction is SsaRetainedOperation) {
					var operation = (SsaRetainedOperation) instruction;
					line (4, "%%%d = retained-callback action=%d %s".printf (operation.result.ordinal, (int) operation.action, value (operation.callee)));
					continue;
				}
				if (instruction is SsaScopedAllocator) {
					var scoped = (SsaScopedAllocator) instruction;
					line (4, "%%%d = scoped-allocator backing=#%d pair=(%s,%s) kind=%s slots=%s %s".printf (scoped.result.ordinal, scoped.backing.owner_ordinal, value (scoped.pair.base_value), value (scoped.pair.length_value), value (scoped.kind), value (scoped.slots), scoped.loan.identity ()));
					continue;
				}
				if (instruction is SsaClosureBind) {
					var closure = (SsaClosureBind) instruction;
					line (4, "%%%d = closure-bind %s code=%s%s".printf (closure.result.ordinal, value (closure.environment), closure.target.name, closure.actor_binding == null ? "" : " " + closure.actor_binding.dump ()));
					continue;
				}
				if (instruction is SsaClosureCallSuccess) {
					var success = (SsaClosureCallSuccess) instruction;
					if (success.struct_result != null) {
						var leaves = new StringBuilder ("checked-closure-record-success error=%%%d".printf (success.call.result.ordinal));
						foreach (var leaf in success.struct_result.leaves) {
							leaves.append_printf (" (%%%d : %s)", leaf.ordinal, leaf.semantic_type.display_name ());
						}
						line (4, leaves.str);
					} else if (success.result == null) {
						line (4, "checked-closure-void-success error=%%%d".printf (success.call.result.ordinal));
					} else {
						line (4, "%%%d = checked-closure-success error=%%%d".printf (success.result.ordinal, success.call.result.ordinal));
					} continue;
				}
				if (instruction is SsaClosureCall) {
					var call = (SsaClosureCall) instruction;
					if (call.struct_result != null) {
						var leaves = new StringBuilder ("invoke-closure-record " + value (call.callee));
						foreach (var leaf in call.struct_result.leaves) {
							leaves.append_printf (" (%%%d : %s)", leaf.ordinal, leaf.semantic_type.display_name ());
						}
						line (4, leaves.str);
					} else if (call.result == null) {
						line (4, "invoke-closure-void " + value (call.callee));
					} else {
						line (4, "%%%d = %s %s".printf (call.result.ordinal, ((Semantic.ClosureHandleType) call.callee.semantic_type).throws_type == null ? "invoke-closure" : "checked-invoke-closure", value (call.callee)));
					} continue;
				}
				if (instruction is SsaSharedOperation) {
					var operation = (SsaSharedOperation) instruction;
					line (3, "(%%%d = shared-%s %s : %s)".printf (operation.result.ordinal, operation.action.to_string (), value (operation.operand), operation.result.semantic_type.display_name ()));
					continue;
				}
				if (instruction is SsaFunctionValueCall) {
					var invocation = (SsaFunctionValueCall) instruction;
					if (invocation.struct_result != null) {
						var leaves = new StringBuilder ("invoke-function-value-record " + value (invocation.callee));
						foreach (var leaf in invocation.struct_result.leaves) {
							leaves.append_printf (" (%%%d : %s)", leaf.ordinal, leaf.semantic_type.display_name ());
						}
						line (4, leaves.str);
					} else if (invocation.result == null) {
						line (4, "invoke-function-value-void " + value (invocation.callee));
					} else {
						line (4, "%%%d = invoke-function-value %s".printf (invocation.result.ordinal, value (invocation.callee)));
					} continue;
				}
				var call = instruction as SsaCallInstruction;
				if (call != null && call.enum_result != null) {
					line (3, "(enum-call-result slot#%d caller-storage)".printf (call.enum_result.ordinal));
				}
				if (call != null && call.buffer_result != null) {
					line (3, "(buffer-call-result %s owned-transfer)".printf (buffer_pair (call.buffer_result)));
				}
				if (call != null) {
					foreach (var group in call.struct_arguments) {
						line (3, "(struct-argument #%d : %s (leaves %d %u))".printf (group.source_ordinal, group.shape.semantic_type.display_name (), group.first_leaf, group.shape.leaves.length));
					}
					if (call.struct_result != null) {
						var results = new StringBuilder ("(struct-call-results : " + call.struct_result.shape.semantic_type.display_name ());
						foreach (var leaf in call.struct_result.leaves) {
							results.append (" (%%%d : %s)".printf (leaf.ordinal, leaf.semantic_type.display_name ()));
						}
						results.append (")");
						line (3, results.str);
					}
					var text = new StringBuilder ("(");
					if (call.result != null) {
						text.append ("%%%d : %s = ".printf (call.result.ordinal, call.result.semantic_type.display_name ()));
					}
					foreach (var argument in call.owned_arguments) {
						line (3, "(owned-call-commit (parameter %%%d) (captured %s) %s)".printf (argument.parameter.ordinal, value (argument.value), argument.source_ordinal < 0 ? "owned-null" : "(owner #%d = null)".printf (argument.source_ordinal)));
					}
					if (call.owned_result_use != SsaOwnedResultUse.NONE) {
						line (3, "(owned-result-consumption %s)".printf (call.owned_result_use == SsaOwnedResultUse.ACQUIRE ? "acquire" : call.owned_result_use == SsaOwnedResultUse.FORWARD ? "forward" : "rearm"));
					}
					if (call is SsaBaseLifecycleCall) {
						text.append ("base-lifecycle class#%d (receiver %s) (arguments".printf (((SsaLifecycle) call.target).declaring_class.ordinal, value (call.receiver)));
					} else if (call is SsaLifecycleCallInstruction) {
						var lifecycle = (SsaLifecycleCallInstruction) call;
						text.append ("%s (storage #%d) (class #%d) (receiver %s) (arguments".printf (lifecycle.constructs ? "construct" : "object-deinit", lifecycle.storage.ordinal, lifecycle.storage.object_class.ordinal, value (call.receiver)));
					} else if (call is SsaResultConstructionInstruction) {
						text.append ("result-construct (result-storage %result.storage) (arguments");
					} else if (call.target is SsaPropertyAccessor) {
						var accessor = (SsaPropertyAccessor) call.target;
						var property = accessor.property_member;
						text.append ("property-%s (property #%d %s::%s) (%s #%d) (receiver %s) -> %s effectful (arguments".printf ((accessor is SsaPropertyGetter) ? "get" : "set", property.ordinal, property.declaring_type.name, property.name, (accessor is SsaPropertyGetter) ? "getter" : "setter", property.ordinal, value (call.receiver), accessor.return_type.display_name ()));
					} else if (call.receiver != null) {
						var target = (SsaMethod) call.target;
						text.append ("method-call (target %s::%s #%d) (receiver %s) -> %s (arguments".printf (target.declaring_type.name, target.name, target.method_ordinal, value (call.receiver), target.return_type.display_name ()));
					} else {
						text.append ("call #%d \"%s\" -> %s (arguments".printf (call.target.ordinal, call.target.name.escape (), call.target.return_type.display_name ()));
					}
					if (call.candidate_storage != null) {
						line (3, "(candidate-storage #%d)".printf (call.candidate_storage.ordinal));
					}
					if (call.result_storage != null) {
						line (3, "(forward-result-storage %result.storage)");
					}
					for (int a = 0; a < call.arguments.length; a++) {
						text.append (" " + value (call.arguments[a]));
					}
					text.append ("))");
					line (3, text.str);
					continue;
				}
				string result = "%%%d : %s".printf (instruction.result.ordinal, instruction.result.semantic_type.display_name ());
				var dot = instruction as SsaVectorDotInstruction;
				if (dot != null) {
					line (3, "(%s = %s (source %s) (accumulator %s) (order %s)%s %s %s)".printf (result, dot.dot_kind.spelling (), dot.source_type.display_name (), dot.destination_type.display_name (), dot.dot_kind.order (), dot.accumulator == null ? "" : " (acc " + value (dot.accumulator) + ")", value (dot.first), value (dot.second)));
					continue;
				}
				var dsp = instruction as SsaDspInstruction;
				if (dsp != null) {
					line (3, "(%s = %s (from %s) (to %s) %s%s)".printf (result, dsp.primitive_kind.spelling (), dsp.source_type.display_name (), dsp.destination_type.display_name (), value (dsp.first), dsp.second == null ? "" : " " + value (dsp.second)));
					continue;
				}
				var shift = instruction as SsaIntegerShiftInstruction;
				if (shift != null) {
					line (3, "(%s = %s (value %s) (count %s) (valid-range 0 %u) (invalid-count trap))".printf (result, shift.shift_kind.operation_name (instruction.result.semantic_type), value (shift.operand), value (shift.count), shift.element_bit_width - 1));
					continue;
				}
				var numeric_guard = instruction as SsaNumericGuard;
				if (numeric_guard != null) {
					line (3, "(%s = numeric-guard (to %s) finite truncate-toward-zero range-check trap-before-convert %s)".printf (result, numeric_guard.destination_type.display_name (), value (numeric_guard.operand)));
					continue;
				}
				var numeric_conversion = instruction as SsaNumericConversionInstruction;
				if (numeric_conversion != null) {
					line (3, "(%s = numeric-convert (from %s) (to %s) (kind %s) (policy %s) (value %s))".printf (result, numeric_conversion.source_type.display_name (), numeric_conversion.destination_type.display_name (), numeric_conversion.conversion_kind.spelling (), numeric_conversion.policy.spelling (), value (numeric_conversion.operand)));
					continue;
				}
				var floating_conversion = instruction as SsaFloatConversionInstruction;
				if (floating_conversion != null) {
					line (3, "(%s = float-convert (from %s) (to %s) (mode %s) (value %s))".printf (result, floating_conversion.source_type.display_name (), floating_conversion.destination_type.display_name (), floating_conversion.conversion_kind.mode (), value (floating_conversion.operand)));
					continue;
				}
				var conversion = instruction as SsaIntegerConversionInstruction;
				if (conversion != null) {
					line (3, "(%s = %s (from %s) (to %s) (value %s))".printf (result, (conversion.source_type is Semantic.VectorType) ? "integer-vector-convert" : "integer-convert", conversion.source_type.display_name (), conversion.destination_type.display_name (), value (conversion.operand)));
					continue;
				}
				var splat = instruction as SsaVectorSplatInstruction;
				if (splat != null) {
					var text = new StringBuilder ("(%s = vector-splat".printf (result));
					text.append_printf (" (lanes %d)", splat.lane_count);
					text.append (" (value " + value (splat.operand) + ")");
					text.append (")");
					line (3, text.str);
					continue;
				}
				var extract = instruction as SsaVectorExtractInstruction;
				if (extract != null) {
					var text = new StringBuilder ("(%s = vector-extract".printf (result));
					text.append_printf (" (lane %d)", extract.index.ordinal);
					text.append (" (vector " + value (extract.vector) + ")");
					text.append (")");
					line (3, text.str);
					continue;
				}
				var insert = instruction as SsaVectorInsertInstruction;
				if (insert != null) {
					var text = new StringBuilder ("(%s = vector-insert".printf (result));
					text.append_printf (" (lane %d)", insert.index.ordinal);
					text.append (" (vector " + value (insert.vector) + ")");
					text.append (" (value " + value (insert.replacement) + ")");
					text.append (")");
					line (3, text.str);
					continue;
				}
				var shuffle = instruction as SsaVectorShuffleInstruction;
				if (shuffle != null) {
					var text = new StringBuilder ("(%s = vector-shuffle".printf (result));
					text.append_printf (" (lanes %s)", shuffle.selectors.spelling ());
					text.append (" (vector " + value (shuffle.vector) + ")");
					text.append (")");
					line (3, text.str);
					continue;
				}
				if (instruction is SsaVectorMemoryInstruction) {
					var memory = (SsaVectorMemoryInstruction) instruction;
					line (3, "(%s = vector-memory-%s align=%u view=%s offset=%s%s)".printf (result, memory.stored == null ? "load" : "store", memory.contract.alignment, value (memory.view), value (memory.offset), memory.stored == null ? "" : " stored=" + value (memory.stored)));
					continue;
				}
				var select = instruction as SsaVectorSelectInstruction;
				if (select != null) {
					var text = new StringBuilder ("(%s = vector-select".printf (result));
					text.append (" (mask " + value (select.mask) + ")");
					text.append (" (true " + value (select.true_value) + ")");
					text.append (" (false " + value (select.false_value) + ")");
					text.append (")");
					line (3, text.str);
					continue;
				}
				var vector = instruction as SsaVectorConstructInstruction;
				if (vector != null) {
					var text = new StringBuilder ("(%s = vector-init".printf (result));
					foreach (var lane in vector.lanes) {
						text.append (" " + value (lane));
					}
					text.append (")");
					line (3, text.str);
					continue;
				}
				var reduction = instruction as SsaVectorReductionInstruction;
				if (reduction != null) {
					line (3, "(%s = vector-%s %s)".printf (result, reduction.operator_kind.spelling (), value (reduction.operand)));
					continue;
				}
				var prefix = instruction as SsaPrefixInstruction;
				if (prefix != null) {
					line (3, "(%s = prefix %s %s)".printf (result, prefix.operator_kind.spelling (), value (prefix.operand)));
				} else {
					var binary = (SsaBinaryInstruction) instruction;
					line (3, "(%s = binary %s %s %s)".printf (result, binary.operator_kind.spelling (), value (binary.left), value (binary.right)));
				}
			}
			var terminator = block.terminator;
			var branch = terminator as SsaBranch;
			var conditional = terminator as SsaConditionalBranch;
			var request = terminator as SsaBufferAllocationBranch;
			if (terminator is SsaExceptionUnreachable) {
				line (3, "(exception-exhaustive-unreachable %s)".printf (value (((SsaExceptionUnreachable) terminator).exception)));
			} else if (terminator is SsaExceptionReturn) {
				line (3, "(exception-return %s)".printf (value (((SsaExceptionReturn) terminator).value)));
			} else if (terminator is SsaEnumReturn) {
				line (3, "(enum-return slot#%d caller-storage)".printf (((SsaEnumReturn) terminator).source.ordinal));
			} else if (terminator is SsaEnumInvalidTag) {
				line (3, "(enum-invalid-tag trap)");
			} else if (terminator is SsaEnumDispatch) {
				var dispatch = (SsaEnumDispatch) terminator;
				line (3, "(enum-dispatch slot#%d".printf (dispatch.source.ordinal));
				foreach (var alternative in dispatch.cases) {
					line (4, edge ("case " + alternative.variant.identity.name, alternative.edge));
				}
				line (4, edge ("invalid", dispatch.invalid_edge));
				line (3, ")");
			} else if (request != null) {
				line (3, "(buffer-allocation-branch count=%s checked-count checked-size".printf (value (request.allocation.count)));
				line (4, edge ("success", request.success_edge));
				line (4, edge ("allocator-null", request.failure_edge));
				line (3, ")");
			} else if (terminator is SsaAllocationFailureTrap) {
				line (3, "(allocation-failure-trap)");
			} else if (branch != null) {
				line (3, edge ("branch", branch.edge));
			} else if (conditional != null) {
				line (3, "(conditional-branch %s".printf (value (conditional.condition)));
				line (4, edge ("true", conditional.true_edge));
				line (4, edge ("false", conditional.false_edge));
				line (3, ")");
			} else if (terminator is SsaBufferReturn) {
				var returned = (SsaBufferReturn) terminator;
				line (3, "(owned-buffer-return %s (cleanup #%d))".printf (buffer_pair (returned.pair), returned.cleanup.ordinal));
			} else if (terminator is SsaStructReturn) {
				var returned = (SsaStructReturn) terminator;
				var text = new StringBuilder ("(struct-return : " + returned.shape.semantic_type.display_name ());
				foreach (var leaf in returned.leaves) {
					text.append (" " + value (leaf));
				}
				text.append (")");
				line (3, text.str);
			} else if (terminator is SsaForeignSignalReturn) {
				line (3, "(native-signal synchronous-return " + ((SsaForeignSignalReturn) terminator).binding.identity () + ")");
			} else if (terminator is SsaForeignReturn) {
				line (3, "(CImport declarations-v1 status-out checked-return " + "consumed=" + ((SsaForeignReturn) terminator).consumed.length.to_string () + " " + ((SsaForeignReturn) terminator).binding.identity () + ")");
			} else if (terminator is SsaFunctionEnd) {
				line (3, "(function-end)");
			} else {
				var returned = (SsaReturn) terminator;
				if (returned is SsaOwnershipReturn && ((SsaOwnershipReturn) returned).provenance != Semantic.ObjectResultProvenance.NONE) {
					line (3, "(result-provenance %s)".printf (((SsaOwnershipReturn) returned).provenance.label ()));
				}
				line (3, (returned is SsaOwnershipReturn) ? "(ownership-return %s)".printf (value (returned.value)) : returned.value == null ? "(return)" : "(return %s)".printf (value (returned.value)));
			}
			line (2, ")");
		}
		line (1, ")");
	}
}
}
