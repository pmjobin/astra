// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Cfg {
// Internal debugging format, not a serialization contract. Verification
// precedes formatting so malformed IR cannot produce partial output.
public class CfgDump : Object {
	private StringBuilder output = new StringBuilder ();
	private HashTable<CfgCallResultValue, int> results = new HashTable<CfgCallResultValue, int> (direct_hash, direct_equal);
	private HashTable<CfgEvaluatedValue, int> evaluations = new HashTable<CfgEvaluatedValue, int> (direct_hash, direct_equal);

	private GenericArray<Astra.Semantic.EnumDefinition> enums;
	private Astra.Semantic.EnumDefinition? enum_definition (Astra.Semantic.EnumType type) {
		foreach (var candidate in enums) {
			if (candidate.semantic_type == type) {
				return candidate;
			}
		}
		return null;
	}

	public static string format(CfgProgram program) throws CfgError {
		CfgVerifier.verify (program);
		if (program.enums.length == 0 && program.functions.length == 0 && program.c_functions.length == 0 && program.c_exports.length == 0 && program.structs.length == 0 && program.classes.length == 0 && program.cleanups.length == 0) {
			return "(cfg-program)\n";
		}
		var dump = new CfgDump ();
		dump.enums = program.enums;
		dump.line (0, "(cfg-program");
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
			if (structure is CfgStruct && ((CfgStruct) structure).representation != null && ((CfgStruct) structure).representation.is_union) {
				dump.line (1, ((CfgStruct) structure).representation.dump ());
			}
			dump.line (1, (structure is CfgClass) ? "(class #%d \"%s\"".printf (structure.ordinal, structure.name.escape ()) : "(struct \"%s\"".printf (structure.name.escape ()));
			if (structure is CfgClass && ((CfgClass) structure).allocation_policy != null) {
				dump.line (2, ((CfgClass) structure).allocation_policy.dump ());
			}
			if (structure is CfgClass && ((CfgClass) structure).foreign_export != null) {
				dump.line (2, ((CfgClass) structure).foreign_export.dump ());
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
				dump.line (2, "(field #%d \"%s\" : %s)".printf (field.ordinal, field.name.escape (), field.semantic_type.display_name ()));
			}
			dump.line (1, ")");
		}
		foreach (var cleanup in program.cleanups) {
			if (cleanup.record_type != null) {
				dump.line (1, "(cleanup #%d record-field-obligations type=%s)".printf (cleanup.ordinal, cleanup.record_type.name));
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

	private void write_function(CfgFunction function) throws CfgError {
		if (function.floating_policy != 0) {
			line (1, "(floating-policy permissions=%u checked-domain=bounded)".printf (function.floating_policy));
		}
		results.remove_all ();
		evaluations.remove_all ();
		int next_evaluation = 0;
		int next_result = 0;
		for (int b = 0; b < function.blocks.length; b++) {
			var instructions = function.blocks[b].instructions;
			for (int i = 0; i < instructions.length; i++) {
				var allocation = instructions[i] as CfgBufferAllocate;
				if (allocation != null) {
					results.insert (allocation.results.owner, next_result++);
				}
				var capture = instructions[i] as CfgOwnedArgumentCapture;
				if (capture != null) {
					evaluations.insert (capture.transfer, next_evaluation++);
				}
				var owned_return = instructions[i] as CfgOwnershipReturnInstruction;
				if (owned_return != null) {
					evaluations.insert (owned_return.result, next_evaluation++);
				}
				var evaluation = instructions[i] as CfgEvaluateInstruction;
				if (instructions[i] is CfgTaskMove) {
					evaluations.insert (((CfgTaskMove) instructions[i]).result, next_evaluation++);
				}
				if (instructions[i] is CfgTaskBorrow) {
					evaluations.insert (((CfgTaskBorrow) instructions[i]).result, next_evaluation++);
				}
				if (instructions[i] is CfgAsyncDelay) {
					evaluations.insert (((CfgAsyncDelay) instructions[i]).exception, next_evaluation++);
				}
				if (instructions[i] is CfgTaskWait) {
					evaluations.insert (((CfgTaskWait) instructions[i]).exception, next_evaluation++);
				}
				if (instructions[i] is CfgTaskSuccess) {
					var success = (CfgTaskSuccess) instructions[i];
					if (success.struct_result != null) {
						foreach (var leaf in success.struct_result.leaves) {
							results.insert (leaf, next_result++);
						}
					} else if (success.enum_result != null) {
					} else if (success.buffer_cleanup == null) {
						evaluations.insert ((CfgEvaluatedValue) success.result, next_evaluation++);
					} else {
						results.insert ((CfgCallResultValue) success.result, next_result++);
					}
				}
				if (instructions[i] is CfgAsyncOperation) {
					var operation = (CfgAsyncOperation) instructions[i];
					if (operation.result != null) {
						evaluations.insert (operation.result, next_evaluation++);
					}
					if (operation.exception != null) {
						evaluations.insert (operation.exception, next_evaluation++);
					}
				}
				if (evaluation != null) {
					evaluations.insert (evaluation.result, next_evaluation++);
				}
				var c_call = instructions[i] as CfgCCallInstruction;
				if (c_call != null && c_call.result != null) {
					results.insert (c_call.result, next_result++);
				}
				var call = instructions[i] as CfgCallInstruction;
				if (call != null && call.struct_result != null) {
					foreach (var leaf in call.struct_result.leaves) {
						results.insert (leaf, next_result++);
					}
				}
				if (instructions[i] is CfgStructInvoke) {
					foreach (var leaf in ((CfgStructInvoke) instructions[i]).results.leaves) {
						results.insert (leaf, next_result++);
					}
				}
				if (call != null && call.result != null) {
					results.insert (call.result, next_result++);
				}
			}
		}
		var method = function as CfgMethod;
		if (function is CfgPropertyAccessor) {
			var accessor = (CfgPropertyAccessor) function;
			var property = accessor.property_member;
			line (1, "(property-%s #%d (property %s::%s #%d) (declaring-%s #%d) -> %s".printf ((function is CfgPropertyGetter) ? "getter" : "setter", property.ordinal, property.declaring_type.name, property.name, property.ordinal, (property.declaring_type is CfgClass) ? "class" : "struct", property.declaring_type.ordinal, function.return_type.display_name ()));
			line (2, "(receiver : %s live mutable nonnull non-owning)".printf (accessor.receiver.contract.display_name ()));
		} else if (function is CfgLifecycle) {
			var lifecycle = (CfgLifecycle) function;
			line (1, "(%s (class #%d) (member #%d)".printf ((function is CfgConstructor) ? "constructor" : "destructor", lifecycle.declaring_class.ordinal, lifecycle.member_ordinal));
			line (2, "(receiver %s %s nonnull mutable)".printf ((function is CfgConstructor) ? "initializing" : "live", lifecycle.declaring_class.name));
		} else if (method == null) {
			line (1, "(function #%d \"%s\" -> %s".printf (function.ordinal, function.name.escape (), function.return_type.display_name ()));
		} else {
			line (1, "(method #%d \"%s\" (declaring-%s #%d \"%s\") (member #%d) -> %s".printf (method.method_ordinal, method.name.escape (), (method.declaring_type is CfgClass) ? "class" : "struct", method.declaring_type.ordinal, method.declaring_type.name.escape (), method.member_ordinal, method.return_type.display_name ()));
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
		foreach (var group in function.struct_parameters) {
			line (2, "(struct-parameter #%d : %s %s (leaves %d %u))".printf (group.source_ordinal, group.shape.semantic_type.display_name (), group.shape.mode.spelling (), group.first_leaf, group.shape.leaves.length));
		}
		if (function.struct_result != null) {
			line (2, "(struct-result : %s (leaves %u))".printf (function.struct_result.semantic_type.display_name (), function.struct_result.leaves.length));
		}
		if (function.parameters.length == 0) {
			line (2, "(parameters)");
		} else {
			line (2, "(parameters");
			for (int i = 0; i < function.parameters.length; i++) {
				var parameter = function.parameters[i];
				line (3, "(parameter #%d \"%s\" : %s%s)".printf (parameter.ordinal, parameter.name.escape (), parameter.semantic_type.display_name (), parameter.pointer_contract.dump_suffix ()));
			}
			line (2, ")");
		}
		if (function.locals.length > 0) {
			line (2, "(locals");
			for (int i = 0; i < function.locals.length; i++) {
				var local = function.locals[i];
				if (local.buffer_group != null) {
					line (3, "(buffer-owner #%d : %s (components PTR I32) (cleanup #%d) whole-group)".printf (local.ordinal, local.semantic_type.display_name (), local.cleanup.ordinal));
				}
				if (local.cleanup != null && local.cleanup.is_object) {
					line (3, "(ownership (owner #%d) transferable-object (cleanup #%d)%s)".printf (local.ordinal, local.cleanup.ordinal, local.object_storage == null ? (local.incoming_parameter == null ? " nullable-result" : " incoming-parameter") : " (storage #%d)".printf (local.object_storage.ordinal)));
				}
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
		if (function.temporaries.length > 0) {
			line (2, "(temporaries");
			for (int i = 0; i < function.temporaries.length; i++) {
				write_place (function.temporaries[i], 3);
			}
			line (2, ")");
		}
		line (2, "(entry #%d)".printf (function.entry.ordinal));
		var reachability = CfgReachability.analyze (function);
		for (int i = 0; i < function.blocks.length; i++) {
			var block = function.blocks[i];
			line (2, "(block #%d %s".printf (block.ordinal, reachability.is_reachable (block) ? "reachable" : "unreachable"));
			for (int j = 0; j < block.instructions.length; j++) {
				write_instruction (block.instructions[j], 3);
			}
			write_terminator (block.terminator, 3);
			line (2, ")");
		}
		line (1, ")");
	}

	private void write_instruction(CfgInstruction instruction, int indentation) throws CfgError {
		if (instruction is CfgTaskCreate) {
			var task = (CfgTaskCreate) instruction;
			line (indentation, "(task-create cold " + task.target.name);
			foreach (var capture in task.arguments) {
				write_value (capture, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		if (instruction is CfgTaskBorrow) {
			line (indentation, "(task-borrow local#%d)".printf (((CfgTaskBorrow) instruction).source.ordinal));
			return;
		}
		if (instruction is CfgTaskStarted) {
			line (indentation, "(task-started local#%d)".printf (((CfgTaskStarted) instruction).source.ordinal));
			return;
		}
		if (instruction is CfgExecutorEnd) {
			line (indentation, "(executor-scope-end local#%d)".printf (((CfgExecutorEnd) instruction).source.ordinal));
			return;
		}
		if (instruction is CfgAsyncRunStatus) {
			line (indentation, "(run-status-publish)");
			return;
		}
		if (instruction is CfgAsyncOperation) {
			var operation = (CfgAsyncOperation) instruction;
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
		if (instruction is CfgTaskMove) {
			line (indentation, "(task-move local#%d)".printf (((CfgTaskMove) instruction).source.ordinal));
			return;
		}
		if (instruction is CfgTaskEnd) {
			line (indentation, "(task-scope-end local#%d)".printf (((CfgTaskEnd) instruction).source.ordinal));
			return;
		}
		if (instruction is CfgTaskWait) {
			var wait = (CfgTaskWait) instruction;
			line (indentation, "(task-wait%s".printf (wait.discard ? " discard-and-drain" : ""));
			if (wait.bridge_executor != null) {
				line (indentation + 1, "(worker-bridge");
				write_value (wait.bridge_executor, indentation + 2);
				line (indentation + 1, ")");
			}
			write_value (wait.child, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (instruction is CfgTaskSuccess) {
			line (indentation, "(task-success %s)".printf (((CfgTaskSuccess) instruction).success_type.display_name ()));
			return;
		}
		if (instruction is CfgAsyncDelay) {
			line (indentation, ((CfgAsyncDelay) instruction).payload ? "(linux-payload-suspend" : "(virtual-suspend");
			write_value (((CfgAsyncDelay) instruction).ticks, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (instruction is CfgActorSend) {
			var send = (CfgActorSend) instruction;
			line (indentation, "(actor-%d checked=%s error=eval#%d".printf ((int) send.action, send.error_type.display_name (), evaluations.lookup (send.result)));
			write_value (send.sender, indentation + 1);
			if (send.message != null) {
				write_value (send.message, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		if (instruction is CfgStructInvoke) {
			var invocation = (CfgStructInvoke) instruction;
			line (indentation, "(struct-indirect-result " + invocation.results.shape.mode.spelling () + " : " + invocation.call.semantic_type.display_name ());
			write_value (invocation.call, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (instruction is CfgCheckedClosureInvoke) {
			var invocation = (CfgCheckedClosureInvoke) instruction;
			line (indentation, "(checked-closure-call error=eval#%d".printf (evaluations.lookup (invocation.result)));
			write_value (invocation.call, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (instruction is CfgClosureCallSuccess) {
			var success = (CfgClosureCallSuccess) instruction;
			line (indentation, "(checked-closure-success eval#%d error=eval#%d)".printf (evaluations.lookup (success.result), evaluations.lookup (success.invocation.result)));
			return;
		}
		if (instruction is CfgConstructorAbort) {
			var abort = (CfgConstructorAbort) instruction;
			line (indentation, "(constructor-abort fields=%u lazy=%u reverse-acquisition conditional-initialization)".printf (abort.fields.length, abort.lazy_properties.length));
			return;
		}
		if (instruction is CfgExceptionStamp) {
			line (indentation, "(exception-original-origin");
			write_value (((CfgExceptionStamp) instruction).exception, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (instruction is CfgOwnedArgumentAbort) {
			var transfer = ((CfgOwnedArgumentAbort) instruction).transfer;
			var direct = transfer.consumer as CfgCallInstruction;
			line (indentation, "(argument-abort consumer#%d capture#%d)".printf (direct == null ? -1 : direct.target.ordinal, evaluations.lookup (transfer)));
			return;
		}
		if (instruction is CfgGroupCallSuccess) {
			line (indentation, "(call-success-group target#%d)".printf (((CfgGroupCallSuccess) instruction).call.target.ordinal));
			return;
		}

		if (instruction is CfgTextLoanEnd) {
			line (indentation, "(text-loan-end local#%d)".printf (((CfgTextLoanEnd) instruction).local.ordinal));
			return;
		}
		if (instruction is CfgLazyDrop) {
			var property = ((CfgLazyDrop) instruction).property_member;
			line (indentation, "(lazy-owner-retire %s::%s)".printf (property.declaring_type.name, property.name));
			return;
		}
		if (instruction is CfgSlotsRecordTransfer) {
			var transfer = (CfgSlotsRecordTransfer) instruction;
			line (indentation, "(record-slots-%s %s : %s".printf (transfer.index == null ? "append" : "replace", transfer.shape.mode.spelling (), transfer.shape.semantic_type.display_name ()));
			write_place (transfer.store, indentation + 1);
			if (transfer.index != null) {
				write_value (transfer.index, indentation + 1);
			}
			foreach (var leaf in transfer.leaves) {
				write_value (leaf, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		if (instruction is CfgSlotsRecordRead) {
			var read = (CfgSlotsRecordRead) instruction;
			line (indentation, "(record-slots-%s %s : %s".printf (read.remove ? "take" : "copy", read.results.shape.mode.spelling (), read.results.shape.semantic_type.display_name ()));
			write_place (read.store, indentation + 1);
			write_value (read.index, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (instruction is CfgSlotsReplace) {
			var replace = (CfgSlotsReplace) instruction;
			line (indentation, "(owner-slots-replace");
			write_place (replace.store, indentation + 1);
			write_value (replace.index, indentation + 1);
			write_place (replace.incoming, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (instruction is CfgSlotsInitialize || instruction is CfgSlotsAppend || instruction is CfgSlotsDrop || instruction is CfgSlotsBorrow) {
			CfgIndirectFieldPlace store = (instruction is CfgSlotsInitialize) ? ((CfgSlotsInitialize) instruction).store : (instruction is CfgSlotsAppend) ? ((CfgSlotsAppend) instruction).store : (instruction is CfgSlotsDrop) ? ((CfgSlotsDrop) instruction).store : ((CfgSlotsBorrow) instruction).result.store;
			line (indentation, "(owner-slots-%s".printf ((instruction is CfgSlotsInitialize) ? "empty" : (instruction is CfgSlotsAppend) ? "append-move" : (instruction is CfgSlotsDrop) ? "reverse-drop" : "borrow"));
			write_place (store, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (instruction is CfgTextSnapshotDestroy) {
			line (indentation, "(snapshot-destroy");
			write_place (((CfgTextSnapshotDestroy) instruction).field, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (instruction is CfgEnumBufferAbort) {
			line (indentation, "(enum-buffer-abort local#%d)".printf (((CfgEnumBufferAbort) instruction).capture.source.ordinal));
			return;
		}
		if (instruction is CfgEnumBufferCapture) {
			var capture = (CfgEnumBufferCapture) instruction;
			line (indentation, "(enum-buffer-capture");
			if (capture.source != null) {
				line (indentation + 1, "(reserve local#%d)".printf (capture.source.ordinal));
			} else {
				write_value (capture.producer, indentation + 1);
			} line (indentation, ")");
			return;
		}
		if (instruction is CfgEnumScalarCapture) {
			var capture = (CfgEnumScalarCapture) instruction;
			line (indentation, "(enum-scalar-capture local#%d result=%%%d cleanup=#%d)".printf (capture.source.ordinal, evaluations.lookup (capture.result), capture.cleanup.ordinal));
			return;
		}
		if (instruction is CfgEnumScalarAbort) {
			line (indentation, "(enum-scalar-abort local#%d retain-owner)".printf (((CfgEnumScalarAbort) instruction).capture.source.ordinal));
			return;
		}
		if (instruction is CfgEnumCommit) {
			line (indentation, "(enum-commit slot#%d)".printf (((CfgEnumCommit) instruction).captured.ordinal));
			return;
		}
		if (instruction is CfgEnumDrop) {
			line (indentation, "(enum-drop-active slot#%d)".printf (((CfgEnumDrop) instruction).source.ordinal));
			return;
		}
		if (instruction is CfgEnumEndInspection) {
			line (indentation, "(enum-end-inspection slot#%d)".printf (((CfgEnumEndInspection) instruction).source.ordinal));
			return;
		}
		if (instruction is CfgEnumExtractBuffer) {
			var extract = (CfgEnumExtractBuffer) instruction;
			line (indentation, "(enum-extract-buffer slot#%d field#%d -> local#%d)".printf (extract.source.ordinal, extract.field.identity.ordinal, extract.destination.ordinal));
			return;
		}
		if (instruction is CfgEnumExtractRecord) {
			var extract = (CfgEnumExtractRecord) instruction;
			line (indentation, "(enum-extract-record slot#%d field#%d -> local#%d leaves=%u)".printf (extract.source.ordinal, extract.field.identity.ordinal, extract.destination.ordinal, extract.results.leaves.length));
			return;
		}
		if (instruction is CfgEnumExtractScalar) {
			var extract = (CfgEnumExtractScalar) instruction;
			line (indentation, "(enum-extract-scalar slot#%d field#%d -> local#%d)".printf (extract.source.ordinal, extract.field.identity.ordinal, extract.destination.ordinal));
			return;
		}
		if (instruction is CfgEnumFinishArm) {
			var finish = (CfgEnumFinishArm) instruction;
			var text = new StringBuilder ("(enum-finish-arm slot#%d retain".printf (finish.source.ordinal));
			for (uint f = 0; f < finish.retained_count; f++) {
				text.append (" field#%d".printf (finish.field (f).identity.ordinal));
			}
			text.append (")");
			line (indentation, text.str);
			return;
		}
		if (instruction is CfgEnumConstruct) {
			var construct = (CfgEnumConstruct) instruction;
			line (indentation, "(enum-construct slot#%d %s.%s".printf (construct.destination.ordinal, construct.destination.definition.semantic_type.display_name (), construct.variant.identity.name));
			foreach (var field in construct.fields) {
				line (indentation + 1, "(field#%d %s".printf (field.field.identity.ordinal, field.field.identity.name));
				if (field.sum != null) {
					line (indentation + 2, "(sum-slot #%d)".printf (field.sum.ordinal));
				}
				foreach (var leaf in field.leaves) {
					write_value (leaf, indentation + 2);
				}
				line (indentation + 1, ")");
			}
			line (indentation, ")");
			return;
		}
		if (instruction is CfgEnumCopy) {
			var copy = (CfgEnumCopy) instruction;
			line (indentation, "(enum-copy slot#%d <- slot#%d %s)".printf (copy.destination.ordinal, copy.source.ordinal, copy.initializes_destination ? "initialize" : "assign"));
			return;
		}
		if (instruction is CfgEnumAcquire) {
			var acquire = (CfgEnumAcquire) instruction;
			line (indentation, "(enum-acquire slot#%d parameter#%d snapshot)".printf (acquire.destination.ordinal, acquire.parameter.ordinal));
			return;
		}
		if (instruction is CfgEnumExtractSum) {
			var extract = (CfgEnumExtractSum) instruction;
			line (indentation, "(enum-extract slot#%d field#%d -> slot#%d snapshot)".printf (extract.source.ordinal, extract.field.identity.ordinal, extract.destination.ordinal));
			return;
		}
		if (instruction is CfgCallInstruction && ((CfgCallInstruction) instruction).enum_result != null) {
			line (indentation, "(enum-call-result slot#%d caller-storage)".printf (((CfgCallInstruction) instruction).enum_result.ordinal));
		}
		if (instruction is CfgBufferAllocate) {
			var allocation = (CfgBufferAllocate) instruction;
			if (allocation.failure != null) {
				line (indentation, "(owned-buffer-publish (result #%d) element=%s (cleanup #%d) allocation-success)".printf (results.lookup (allocation.results.owner), allocation.cleanup.buffer_type.element_type.display_name (), allocation.cleanup.ordinal));
				return;
			}
			line (indentation, "(owned-buffer-allocate (result #%d) element=%s (cleanup #%d) zero-initialize checked-count checked-byte-size trap-on-failure empty=null+0".printf (results.lookup (allocation.results.owner), allocation.cleanup.buffer_type.element_type.display_name (), allocation.cleanup.ordinal));
			write_value (allocation.count, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (instruction is CfgStructResultConsume) {
			var consumption = (CfgStructResultConsume) instruction;
			line (indentation, "(consume-struct-result %d : %s".printf ((int) consumption.use_kind, consumption.results.shape.semantic_type.display_name ()));
			foreach (var leaf in consumption.results.leaves) {
				write_value (leaf, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		var array = instruction as CfgArrayInitialize;
		if (array != null) {
			line (indentation, "(array-initialize #%d %s".printf (array.storage.ordinal, array.storage.semantic_type.display_name ()));
			if (array.record_root != null) {
				line (indentation + 1, "(record-entry %d complete=%s)".printf (array.record_ordinal, array.completes_array.to_string ()));
				foreach (var field in array.record_fields) {
					write_place (field, indentation + 1);
				}
			}
			foreach (var element in array.elements) {
				write_value (element, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		var capture = instruction as CfgOwnedArgumentCapture;
		if (capture != null) {
			var pending = capture.transfer;
			line (indentation, "(capture-owned-argument (evaluation #%d) (parameter #%d) %s (cleanup #%d) semantic-move)".printf (evaluations.lookup (pending), pending.parameter.ordinal, pending.source == null ? "owned-null" : "(owner #%d)".printf (pending.source.ordinal), pending.cleanup.ordinal));
			return;
		}
		var commit = instruction as CfgOwnedCallTransferCommit;
		if (commit != null) {
			var direct = commit.call as CfgCallInstruction;
			line (indentation, direct == null ? "(owned-call-transfer-commit (indirect)" : "(owned-call-transfer-commit (target #%d)".printf (direct.target.ordinal));
			foreach (var pending in commit.transfers) {
				line (indentation + 1, "(evaluation #%d %s)".printf (evaluations.lookup (pending), pending.source == null ? "owned-null" : "(clear owner #%d)".printf (pending.source.ordinal)));
			}
			line (indentation, ")");
			return;
		}
		var owned_return = instruction as CfgOwnershipReturnInstruction;
		if (owned_return != null) {
			var result = owned_return.result;
			if (result.provenance != Astra.Semantic.ObjectResultProvenance.NONE) {
				line (indentation, "(result-provenance %s)".printf (result.provenance.label ()));
			}
			if (result.producer != null) {
				line (indentation, "(ownership-return-capture (evaluation #%d) (producer".printf (evaluations.lookup (result)));
				write_value (result.producer, indentation + 1);
				line (indentation, "))");
				return;
			}
			line (indentation, "(ownership-return-capture (evaluation #%d) %s (cleanup #%d))".printf (evaluations.lookup (result), result.source == null ? "owned-null" : "(move-and-clear owner #%d)".printf (result.source.ordinal), result.cleanup.ordinal));
			return;
		}
		var parameter_acquire = instruction as CfgAcquireParameter;
		if (parameter_acquire != null) {
			line (indentation, "(acquire-parameter #%d (owner #%d) OWNED)".printf (parameter_acquire.acquisition.incoming_parameter.ordinal, parameter_acquire.acquisition.ordinal));
			return;
		}
		var rearm = instruction as CfgOwnershipRearmInstruction;
		if (rearm != null) {
			line (indentation, "(ownership-rearm (owner #%d \"%s\") (cleanup #%d)".printf (rearm.owner.ordinal, rearm.owner.name, rearm.cleanup.ordinal));
			if (rearm.source != null) {
				line (indentation + 1, "(move-owner #%d)".printf (rearm.source.ordinal));
			} else {
				write_value (rearm.value, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		var slot_capture = instruction as CfgBufferSlotCapture;
		if (slot_capture != null) {
			line (indentation, "(buffer-slot-capture");
			write_place (slot_capture.place, indentation + 1);
			line (indentation, ")");
			return;
		}
		var exchange = instruction as CfgBufferExchange;
		if (exchange != null) {
			line (indentation, "(owned-buffer-exchange (cleanup #%d) capture-both-before-store".printf (exchange.cleanup.ordinal));
			write_place (exchange.left, indentation + 1);
			write_place (exchange.right, indentation + 1);
			line (indentation, ")");
			return;
		}
		var release = instruction as CfgOwnershipReleaseInstruction;
		if (release != null) {
			line (indentation, "(ownership-release (owner #%d \"%s\") (cleanup #%d))".printf (release.owner.ordinal, release.owner.name, release.cleanup.ordinal));
			return;
		}
		var borrow = instruction as CfgOwnedBorrowInstruction;
		if (borrow != null) {
			line (indentation, "(borrow-owner #%d \"%s\" : %s)".printf (borrow.result.source.ordinal, borrow.result.source.name, borrow.result.semantic_type.display_name ()));
			return;
		}
		var cleanup = instruction as CfgCleanupInstruction;
		var transfer = instruction as CfgOwnershipTransferInstruction;
		if (instruction is CfgStructParameterBorrow) {
			var binding = (CfgStructParameterBorrow) instruction;
			line (indentation, "(record-parameter-borrow destination=#%d leaves=%u)".printf (binding.destination.ordinal, binding.leaves.length));
			return;
		}
		if (instruction is CfgStructBoundaryAcquire) {
			var acquire = (CfgStructBoundaryAcquire) instruction;
			line (indentation, "(record-move-value-acquire destination=#%d projection=%s leaves=%u)".printf (acquire.destination.ordinal, acquire.projection == null ? "root" : acquire.projection.storage_path ().spelling (), acquire.leaves.length));
			return;
		}
		if (instruction is CfgStructBoundaryMove) {
			var move = (CfgStructBoundaryMove) instruction;
			line (indentation, "(record-move-value-commit source=#%d leaves=%u)".printf (move.source.ordinal, move.leaves.length));
			return;
		}
		if (instruction is CfgRecordFieldCommit) {
			var record_commit = (CfgRecordFieldCommit) instruction;
			line (indentation, "(record-field-commit %s leaves=%u initializes=%s)".printf (record_commit.destination.field.name, record_commit.leaves.length, record_commit.initializes.to_string ()));
			return;
		}
		if (instruction is CfgRecordFieldDrop) {
			line (indentation, "(record-field-drop %s)".printf (((CfgRecordFieldDrop) instruction).source.field.name));
			return;
		}
		if (instruction is CfgRecordTake) {
			var take = (CfgRecordTake) instruction;
			line (indentation, "(record-field-take source=#%d path=%s destination=#%d)".printf (take.source.ordinal, take.field.storage_path ().spelling (), take.destination.ordinal));
			return;
		}
		if (instruction is CfgRecordReplace) {
			var replace = (CfgRecordReplace) instruction;
			line (indentation, "(record-field-replace root=#%d path=%s)".printf (replace.owner.ordinal, replace.field.storage_path ().spelling ()));
			return;
		}
		if (transfer != null) {
			line (indentation, "(ownership-transfer (source owner #%d \"%s\") (destination owner #%d \"%s\") (cleanup #%d))".printf (transfer.source.ordinal, transfer.source.name, transfer.destination.ordinal, transfer.destination.name, transfer.cleanup.ordinal));
			return;
		}
		if (cleanup != null) {
			line (indentation, "(cleanup via #%d".printf (cleanup.cleanup.ordinal));
			write_value (cleanup.value, indentation + 1);
			line (indentation, ")");
			return;
		}
		var slice_bounds = instruction as CfgSliceBoundsCheck;
		if (slice_bounds != null) {
			line (indentation, "(slice-bounds-check runtime-length trap-before-use");
			write_value (slice_bounds.slice, indentation + 1);
			line (indentation, ")");
		}
		var numeric_guard = instruction as CfgNumericGuard;
		if (numeric_guard != null) {
			line (indentation, "(numeric-guard (to %s) finite truncate-toward-zero range-check trap-before-convert)".printf (numeric_guard.destination_type.display_name ()));
		}
		var bounds = instruction as CfgArrayBoundsCheck;
		if (bounds != null) {
			line (indentation, "(array-bounds-check #%d length %d trap-before-use)".printf (bounds.storage.ordinal, ((Astra.Semantic.ArrayType) bounds.storage.semantic_type).length));
		}
		var validation = instruction as CfgValidatePlace;
		if (validation != null) {
			line (indentation, "(validate-place null-traps");
			write_place (validation.place, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (instruction is CfgResourceCapture) {
			var resource_capture = (CfgResourceCapture) instruction;
			line (indentation, "(resource-capture %%%d : %s (cleanup #%d) %s".printf (evaluations.lookup (resource_capture.result), resource_capture.result.semantic_type.display_name (), resource_capture.cleanup.ordinal, resource_capture.source == null ? "consume-result" : "consume-owner #%d".printf (resource_capture.source.ordinal)));
			write_value (resource_capture.value, indentation + 1);
			line (indentation, ")");
			return;
		}
		var evaluation = instruction as CfgEvaluateInstruction;
		if (evaluation != null) {
			if (evaluation is CfgRecordBufferCapture) {
				line (indentation, "(record-buffer-capture complete-pair)");
			}
			line (indentation, "(evaluate %%%d : %s".printf (evaluations.lookup (evaluation.result), evaluation.result.semantic_type.display_name ()));
			write_value (evaluation.value, indentation + 1);
			line (indentation, ")");
			return;
		}
		var c_call = instruction as CfgCCallInstruction;
		if (c_call != null) {
			line (indentation, "(c-call #%d \"%s\" -> %s".printf (c_call.target.ordinal, c_call.target.name.escape (), c_call.target.return_type.display_name ()));
			if (c_call.arguments.length == 0) {
				line (indentation + 1, "(arguments)");
			} else {
				line (indentation + 1, "(arguments");
				for (int i = 0; i < c_call.arguments.length; i++) {
					write_value (c_call.arguments[i], indentation + 2);
				}
				line (indentation + 1, ")");
			}
			if (c_call.result != null) {
				line (indentation + 1, "(result %%%d : %s)".printf (results.lookup (c_call.result), c_call.result.semantic_type.display_name ()));
			}
			line (indentation, ")");
			return;
		}
		var call = instruction as CfgCallInstruction;
		if (call != null) {
			line (indentation, "(%scall #%d \"%s\" -> %s".printf ((call is CfgResultConstructionInstruction) ? "result-construct-" : (call is CfgLifecycleCallInstruction) ? (((CfgLifecycleCallInstruction) call).constructs ? "construct-" : "object-deinit-") : (call.target is CfgPropertyGetter) ? "property-get-" : (call.target is CfgPropertySetter) ? "property-set-" : call.receiver == null ? "" : "method-", call.target.ordinal, call.target.name.escape (), call.target.return_type.display_name ()));
			foreach (var group in call.struct_arguments) {
				line (indentation + 1, "(struct-argument #%d : %s (leaves %d %u))".printf (group.source_ordinal, group.shape.semantic_type.display_name (), group.first_leaf, group.shape.leaves.length));
			}
			if (call.struct_result != null) {
				line (indentation + 1, "(struct-result-group : " + call.struct_result.shape.semantic_type.display_name ());
				foreach (var leaf in call.struct_result.leaves) {
					line (indentation + 2, "(result %%%d : %s)".printf (results.lookup (leaf), leaf.semantic_type.display_name ()));
				}
				line (indentation + 1, ")");
			}
			if (call.candidate_storage != null) {
				line (indentation + 1, "(candidate-storage #%d)".printf (call.candidate_storage.ordinal));
			}
			if (call.result_storage != null) {
				line (indentation + 1, "(forward-result-storage)");
			}
			if (call is CfgResultConstructionInstruction) {
				line (indentation + 1, "(result-storage constructor-direct-emplacement)");
			} else if (call is CfgLifecycleCallInstruction) {
				line (indentation + 1, "(storage #%d)".printf (((CfgLifecycleCallInstruction) call).storage.ordinal));
			} else if (call is CfgBaseLifecycleCall) {
				line (indentation + 1, "(base-lifecycle class#%d)".printf (((CfgLifecycle) call.target).declaring_class.ordinal));
			} else if (call.receiver != null) {
				var accessor = call.target as CfgPropertyAccessor;
				if (accessor != null) {
					var property = accessor.property_member;
					line (indentation + 1, "(property #%d %s::%s) (%s #%d) effectful".printf (property.ordinal, property.declaring_type.name, property.name, (accessor is CfgPropertyGetter) ? "getter" : "setter", property.ordinal));
				}
				var method = call.target as CfgMethod;
				if (method != null) {
					line (indentation + 1, "(method-target %s::%s #%d)".printf (method.declaring_type.name, method.name, method.method_ordinal));
				}
				line (indentation + 1, "(receiver");
				write_value (call.receiver, indentation + 2);
				line (indentation + 1, ")");
			}
			if (call.arguments.length == 0) {
				line (indentation + 1, "(arguments)");
			} else {
				line (indentation + 1, "(arguments");
				for (int i = 0; i < call.arguments.length; i++) {
					write_value (call.arguments[i], indentation + 2);
				}
				line (indentation + 1, ")");
			}
			if (call.result != null) {
				line (indentation + 1, "(result %%%d : %s)".printf (results.lookup (call.result), call.result.semantic_type.display_name ()));
			}
			line (indentation, ")");
			return;
		}
		var initialization = instruction as CfgInitialize;
		if (initialization != null) {
			line (indentation, "(initialize");
			write_place (initialization.target, indentation + 1);
			write_value (initialization.value, indentation + 1);
			line (indentation, ")");
			return;
		}
		var store = instruction as CfgStore;
		if (store != null) {
			line (indentation, store.volatile_enabled ? "(volatile-store" : "(store");
			write_place (store.target, indentation + 1);
			write_value (store.value, indentation + 1);
			line (indentation, ")");
			return;
		}
		throw new CfgError.INVALID_CFG ("internal CFG dump error: unsupported CFG instruction");
	}

	private void write_place(CfgPlace place, int indentation) throws CfgError {
		var object_field = place as CfgObjectFieldPlace;
		if (object_field != null) {
			line (indentation, "(object-field-initialize-place (storage #%d) (field #%d) : %s)".printf (object_field.storage.ordinal, object_field.field.ordinal, place.semantic_type.display_name ()));
			return;
		}
		var slice = place as CfgSliceElementPlace;
		if (slice != null) {
			line (indentation, "(slice-element-place : %s runtime-bounds-trap".printf (place.semantic_type.display_name ()));
			write_value (slice.slice, indentation + 1);
			write_value (slice.index, indentation + 1);
			line (indentation, ")");
			return;
		}
		var array = place as CfgArrayElementPlace;
		if (array != null) {
			line (indentation, "(array-element-place #%d %s (bounds 0 %d trap)".printf (array.storage.ordinal, array.array_type.display_name (), array.array_type.length));
			write_value (array.index, indentation + 1);
			line (indentation, ")");
			return;
		}
		var dereference = place as CfgDereferencePlace;
		if (dereference != null) {
			line (indentation, "(dereference-place : %s null-traps".printf (place.semantic_type.display_name ()));
			write_value (dereference.pointer, indentation + 1);
			line (indentation, ")");
			return;
		}
		var indirect = place as CfgIndirectFieldPlace;
		if (indirect != null) {
			line (indentation, "(%s : %s".printf ((indirect.pointer.semantic_type is Astra.Semantic.ClassType) ? "object-field-place null-traps" : "indirect-field-place", place.semantic_type.display_name ()));
			write_value (indirect.pointer, indentation + 1);
			line (indentation + 1, "(field #%d \"%s\")".printf (indirect.field.ordinal, indirect.field.name));
			line (indentation, ")");
			return;
		}
		var temporary = place as CfgTemporaryPlace;
		if (temporary != null) {
			line (indentation, "(temporary-place #%d : %s)".printf (temporary.ordinal, temporary.semantic_type.display_name ()));
			return;
		}
		var projection = place as CfgFieldPlace;
		if (projection != null) {
			var aggregate = projection.aggregate as CfgLocalPlace;
			if (aggregate == null) {
				line (indentation, "(field-place : %s (field %s::%s #%d)".printf (place.semantic_type.display_name (), projection.field.containing_type.name, projection.field.name, projection.field.ordinal));
				write_place (projection.aggregate, indentation + 1);
				line (indentation, ")");
				return;
			}
			line (indentation, "(field-place (base struct-local-place #%d : %s) (field #%d \"%s\") : %s)".printf (aggregate.ordinal, aggregate.semantic_type.display_name (), projection.field.ordinal, projection.field.name.escape (), projection.semantic_type.display_name ()));
			return;
		}
		var local = place as CfgLocalPlace;
		if (local == null) {
			throw new CfgError.INVALID_CFG ("internal CFG dump error: unsupported CFG place");
		}
		line (indentation, "(local-place #%d : %s)".printf (local.ordinal, local.semantic_type.display_name ()));
	}

	private void write_terminator(CfgTerminator terminator, int indentation) throws CfgError {
		if (terminator is CfgExceptionUnreachable) {
			line (indentation, "(exception-exhaustive-unreachable");
			write_value (((CfgExceptionUnreachable) terminator).exception, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (terminator is CfgEnumReturn) {
			line (indentation, "(enum-return slot#%d caller-storage)".printf (((CfgEnumReturn) terminator).source.ordinal));
			return;
		}
		if (terminator is CfgEnumInvalidTag) {
			line (indentation, "(enum-invalid-tag trap)");
			return;
		}
		if (terminator is CfgEnumDispatch) {
			var dispatch = (CfgEnumDispatch) terminator;
			line (indentation, "(enum-dispatch slot#%d".printf (dispatch.source.ordinal));
			foreach (var branch in dispatch.cases) {
				line (indentation + 1, "(case #%d %s block#%d)".printf (branch.variant.identity.ordinal, branch.variant.identity.name, branch.target.ordinal));
			}
			line (indentation + 1, "(invalid block#%d)".printf (dispatch.invalid_target.ordinal));
			line (indentation, ")");
			return;
		}
		var request = terminator as CfgBufferAllocationBranch;
		if (request != null) {
			line (indentation, "(buffer-allocation-branch checked-count checked-size (success #%d) (allocator-null #%d)".printf (request.success_target.ordinal, request.failure_target.ordinal));
			write_value (request.allocation.count, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (terminator is CfgAllocationFailureTrap) {
			line (indentation, "(allocation-failure-trap)");
			return;
		}
		var branch = terminator as CfgBranch;
		if (branch != null) {
			line (indentation, "(branch #%d)".printf (branch.target.ordinal));
			return;
		}
		var conditional = terminator as CfgConditionalBranch;
		if (conditional != null) {
			line (indentation, "(conditional-branch");
			write_value (conditional.condition, indentation + 1);
			line (indentation + 1, "(true #%d)".printf (conditional.true_target.ordinal));
			line (indentation + 1, "(false #%d)".printf (conditional.false_target.ordinal));
			line (indentation, ")");
			return;
		}
		if (terminator is CfgForeignSignalReturn) {
			line (indentation, "(native-signal synchronous-return " + ((CfgForeignSignalReturn) terminator).binding.identity () + ")");
			return;
		}
		if (terminator is CfgForeignReturn) {
			line (indentation, "(CImport declarations-v1 status-out checked-return " + "consumed=" + ((CfgForeignReturn) terminator).consumed.length.to_string () + " " + ((CfgForeignReturn) terminator).binding.identity () + ")");
			return;
		}
		if (terminator is CfgFunctionEnd) {
			line (indentation, "(function-end)");
			return;
		}
		if (terminator is CfgStructReturn) {
			var returned = (CfgStructReturn) terminator;
			line (indentation, "(struct-return : " + returned.shape.semantic_type.display_name ());
			foreach (var leaf in returned.leaves) {
				write_value (leaf, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		var returned = terminator as CfgReturn;
		if (returned == null) {
			throw new CfgError.INVALID_CFG ("internal CFG dump error: unsupported CFG terminator");
		}
		if (returned.value == null) {
			line (indentation, "(return)");
		} else {
			line (indentation, "(return");
			write_value (returned.value, indentation + 1);
			line (indentation, ")");
		}
	}

	private void write_value(CfgValue value, int indentation) throws CfgError {
		if (value is CfgRecordBufferView) {
			var view = (CfgRecordBufferView) value;
			line (indentation, "(record-buffer-view bounded-receiver-loan");
			write_value (view.source, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (value is CfgRecordParameterBufferView) {
			var view = (CfgRecordParameterBufferView) value;
			line (indentation, "(record-parameter-buffer-view bounded-entry-loan");
			write_value (view.source, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (value is CfgLazyObserve) {
			var property = ((CfgLazyObserve) value).property_member;
			line (indentation, "(lazy-observe receiver-borrow %s::%s)".printf (property.declaring_type.name, property.name));
			return;
		}
		if (value is CfgSharedOperation) {
			var operation = (CfgSharedOperation) value;
			line (indentation, "(shared-%s : %s".printf (operation.action.to_string (), value.semantic_type.display_name ()));
			write_value (operation.operand, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (value is CfgCallbackParameterView) {
			line (indentation, "(captured-callback-parameter " + ((CfgCallbackParameterView) value).source.name + " : " + value.semantic_type.display_name () + ")");
			return;
		}
		if (value is CfgFunctionAddress) {
			line (indentation, "(function-address %s : %s)".printf (((CfgFunctionAddress) value).target.name, value.semantic_type.display_name ()));
			return;
		}
		if (value is CfgRetainedOperation) {
			var operation = (CfgRetainedOperation) value;
			line (indentation, "(retained-callback action=%d".printf ((int) operation.action));
			write_value (operation.callee, indentation + 1);
			foreach (var argument in operation.arguments) {
				write_value (argument, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		if (value is CfgClosureBind) {
			var closure = (CfgClosureBind) value;
			line (indentation, "(closure-bind %s code=%s%s)".printf (value.semantic_type.display_name (), closure.target.name, closure.actor_binding == null ? "" : " " + closure.actor_binding.dump ()));
			return;
		}
		if (value is CfgClosureCall) {
			var call = (CfgClosureCall) value;
			line (indentation, "(invoke-closure");
			write_value (call.callee, indentation + 1);
			foreach (var argument in call.arguments) {
				write_value (argument, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		if (value is CfgFunctionValueCall) {
			var call = (CfgFunctionValueCall) value;
			line (indentation, "(invoke-function-value");
			write_value (call.callee, indentation + 1);
			foreach (var argument in call.arguments) {
				write_value (argument, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		if (value is CfgSlotsValue) {
			var v = (CfgSlotsValue) value;
			line (indentation, "(owner-slots-%s".printf (v.action.to_string ()));
			write_place (v.store, indentation + 1);
			if (v.operand != null) {
				write_value (v.operand, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		if (value is CfgClassUpcast) {
			var cast = (CfgClassUpcast) value;
			line (indentation, "(class-upcast class#%d -> class#%d : %s".printf (cast.source_class.ordinal, cast.target_class.ordinal, value.semantic_type.display_name ()));
			write_value (cast.reference, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (value is CfgExceptionMatch) {
			var match = (CfgExceptionMatch) value;
			line (indentation, "(exception-subtype %s".printf (match.match_type.display_name ()));
			write_value (match.exception, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (value is CfgCatchBorrow) {
			line (indentation, "(catch-borrow : %s".printf (value.semantic_type.display_name ()));
			write_value (((CfgCatchBorrow) value).exception, indentation + 1);
			line (indentation, ")");
			return;
		}

		if (value is CfgEnumArgument) {
			line (indentation, "(enum-argument slot#%d snapshot)".printf (((CfgEnumArgument) value).source.ordinal));
			return;
		}
		if (value is CfgEnumTag) {
			line (indentation, "(enum-tag slot#%d)".printf (((CfgEnumTag) value).source.ordinal));
			return;
		}
		if (value is CfgEnumPayloadValue) {
			var payload = (CfgEnumPayloadValue) value;
			line (indentation, "(enum-payload slot#%d variant#%d field#%d%s : %s)".printf (payload.source.ordinal, payload.field.identity.variant.ordinal, payload.field.identity.ordinal, payload.record_path == null ? "" : " path=" + payload.record_path.spelling (), value.semantic_type.display_name ()));
			return;
		}
		if (value is CfgResultObjectStorage || value is CfgResultStorageReceiverValue) {
			line (indentation, "(result-storage : %s)".printf (value.semantic_type.display_name ()));
			return;
		}
		var object_reference = value as CfgObjectReferenceValue;
		if (object_reference != null) {
			line (indentation, "(object-ref (storage #%d) : %s complete)".printf (object_reference.storage.ordinal, value.semantic_type.display_name ()));
			return;
		}
		var object_validation = value as CfgObjectValidateValue;
		if (object_validation != null) {
			line (indentation, "(object-validate : %s null-traps".printf (value.semantic_type.display_name ()));
			write_value (object_validation.reference, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (value is CfgReceiverValue) {
			line (indentation, "(this : %s)".printf (value.semantic_type.display_name ()));
			return;
		}
		var slice = value as CfgSliceFromArrayValue;
		if (slice != null) {
			line (indentation, "(slice-from-array (storage #%d : %s) : %s (region #%d)%s".printf (slice.storage.ordinal, slice.array_type.display_name (), value.semantic_type.display_name (), slice.provenance.region_ordinal, slice.start == null ? " full" : " range-trap"));
			if (slice.start != null) {
				write_value (slice.start, indentation + 1);
				write_value (slice.count, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		var length = value as CfgSliceLengthValue;
		if (length != null) {
			line (indentation, "(slice-length : int");
			write_value (length.slice, indentation + 1);
			line (indentation, ")");
			return;
		}
		var borrow = value as CfgOwnedBorrowValue;
		if (borrow != null) {
			line (indentation, "(borrowed-owner #%d : %s)".printf (borrow.source.ordinal, borrow.semantic_type.display_name ()));
			return;
		}
		var address = value as CfgAddressOfValue;
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
		var evaluated = value as CfgEvaluatedValue;
		if (evaluated != null) {
			line (indentation, "(evaluated %%%d : %s)".printf (evaluations.lookup (evaluated), evaluated.semantic_type.display_name ()));
			return;
		}
		var result = value as CfgCallResultValue;
		if (result != null) {
			line (indentation, "(call-result %%%d : %s)".printf (results.lookup (result), result.semantic_type.display_name ()));
			return;
		}
		var load = value as CfgLoadValue;
		if (load != null) {
			line (indentation, "(%s : %s".printf (load.volatile_enabled ? "volatile-load" : "load", load.semantic_type.display_name ()));
			write_place (load.source, indentation + 1);
			line (indentation, ")");
			return;
		}
		string type_name = value.semantic_type.display_name ();
		if (value is CfgNullPointerValue) {
			line (indentation, "(null : %s)".printf (type_name));
			return;
		}
		var boolean = value as CfgBooleanValue;
		if (boolean != null) {
			line (indentation, "(bool %s : %s)".printf (boolean.literal.spelling (), type_name));
			return;
		}
		var dot = value as CfgVectorDotValue;
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
		var dsp = value as CfgDspValue;
		if (dsp != null) {
			line (indentation, "(%s (from %s) (to %s)".printf (dsp.primitive_kind.spelling (), dsp.source_type.display_name (), dsp.destination_type.display_name ()));
			write_value (dsp.first, indentation + 1);
			if (dsp.second != null) {
				write_value (dsp.second, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		var shift = value as CfgIntegerShiftValue;
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
		var numeric_conversion = value as CfgNumericConversionValue;
		if (numeric_conversion != null) {
			line (indentation, "(numeric-convert (from %s) (to %s) (kind %s) (policy %s)".printf (numeric_conversion.source_type.display_name (), numeric_conversion.destination_type.display_name (), numeric_conversion.conversion_kind.spelling (), numeric_conversion.policy.spelling ()));
			write_value (numeric_conversion.operand, indentation + 1);
			line (indentation, ")");
			return;
		}
		var floating_conversion = value as CfgFloatConversionValue;
		if (floating_conversion != null) {
			line (indentation, "(float-convert (from %s) (to %s) (mode %s)".printf (floating_conversion.source_type.display_name (), floating_conversion.destination_type.display_name (), floating_conversion.conversion_kind.mode ()));
			write_value (floating_conversion.operand, indentation + 1);
			line (indentation, ")");
			return;
		}
		var conversion = value as CfgIntegerConversionValue;
		if (conversion != null) {
			line (indentation, "(%s (from %s) (to %s)".printf ((conversion.source_type is Semantic.VectorType) ? "integer-vector-convert" : "integer-convert", conversion.source_type.display_name (), conversion.destination_type.display_name ()));
			line (indentation + 1, "(value");
			write_value (conversion.operand, indentation + 2);
			line (indentation + 1, ")");
			line (indentation, ")");
			return;
		}
		var splat = value as CfgVectorSplatValue;
		if (splat != null) {
			line (indentation, "(vector-splat : %s".printf (value.semantic_type.display_name ()));
			line (indentation + 1, "(lanes %d)".printf (splat.lane_count));
			line (indentation + 1, "(value");
			write_value (splat.operand, indentation + 2);
			line (indentation + 1, ")");
			line (indentation, ")");
			return;
		}
		var extract = value as CfgVectorExtractValue;
		if (extract != null) {
			line (indentation, "(vector-extract : %s".printf (value.semantic_type.display_name ()));
			line (indentation + 1, "(lane %d)".printf (extract.index.ordinal));
			line (indentation + 1, "(vector");
			write_value (extract.vector, indentation + 2);
			line (indentation + 1, ")");
			line (indentation, ")");
			return;
		}
		var insert = value as CfgVectorInsertValue;
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
		var shuffle = value as CfgVectorShuffleValue;
		if (shuffle != null) {
			line (indentation, "(vector-shuffle : %s".printf (value.semantic_type.display_name ()));
			line (indentation + 1, "(lanes %s)".printf (shuffle.selectors.spelling ()));
			line (indentation + 1, "(vector");
			write_value (shuffle.vector, indentation + 2);
			line (indentation + 1, ")");
			line (indentation, ")");
			return;
		}
		if (value is CfgVectorMemoryValue) {
			var memory = (CfgVectorMemoryValue) value;
			line (indentation, "(vector-memory-%s align=%u : %s".printf (memory.stored == null ? "load" : "store", memory.contract.alignment, memory.contract.vector_type.display_name ()));
			write_value (memory.view, indentation + 1);
			write_value (memory.offset, indentation + 1);
			if (memory.stored != null) {
				write_value (memory.stored, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		var select = value as CfgVectorSelectValue;
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
		var vector = value as CfgVectorConstructValue;
		if (vector != null) {
			line (indentation, "(vector-init : %s".printf (value.semantic_type.display_name ()));
			foreach (var lane in vector.lanes) {
				write_value (lane, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		var reduction = value as CfgVectorReductionValue;
		if (reduction != null) {
			line (indentation, "(vector-%s : %s".printf (reduction.operator_kind.spelling (), value.semantic_type.display_name ()));
			write_value (reduction.operand, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (value is CfgUtf8FactoryValue) {
			var operation = (CfgUtf8FactoryValue) value;
			line (indentation, "(utf8-%s parameter#%d : %s)".printf (operation.validates ? "validate" : "certified-copy-input", operation.input.ordinal, value.semantic_type.display_name ()));
			return;
		}
		if (value is CfgTextValue) {
			var payload = ((CfgTextValue) value).payload;
			line (indentation, "(text (bytes %s) (hex %s) : string)".printf (payload.byte_length.to_string (), payload.hex ()));
			return;
		}
		if (value is CfgTextLengthValue) {
			line (indentation, "(text-byte-length : int");
			write_value (((CfgTextLengthValue) value).receiver, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (value is CfgFloatValue) {
			line (indentation, "(%s %s : %s)".printf (((CfgFloatValue) value).value.format.spelling (), ((CfgFloatValue) value).value.to_string (), value.semantic_type.display_name ()));
			return;
		}
		var integer = value as CfgIntegerValue;
		if (integer != null) {
			line (indentation, "(integer %s : %s)".printf (integer.value.to_string (), type_name));
			return;
		}
		var reference = value as CfgParameterValue;
		if (reference != null) {
			line (indentation, "(parameter #%d : %s)".printf (reference.parameter.ordinal, type_name));
			return;
		}
		var prefix = value as CfgPrefixValue;
		if (prefix != null) {
			line (indentation, "(prefix %s : %s".printf (prefix.operator_kind.spelling (), type_name));
			write_value (prefix.operand, indentation + 1);
			line (indentation, ")");
			return;
		}
		var binary = value as CfgBinaryValue;
		if (binary != null) {
			line (indentation, "(binary %s : %s".printf (binary.operator_kind.spelling (), type_name));
			write_value (binary.left, indentation + 1);
			write_value (binary.right, indentation + 1);
			line (indentation, ")");
			return;
		}
		throw new CfgError.INVALID_CFG ("internal CFG dump error: unsupported CFG value");
	}
}
}
