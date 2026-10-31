// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Ssa;
using Astra.Semantic;
namespace Astra.NativeAbi {
public class NativeAsyncFrameBuilder : Object {
	private weak SsaProgram enum_program;
	private EnumDefinition? enum_definition(EnumType type) {
		foreach (var definition in enum_program.enums) {
			if (definition.semantic_type == type) {
				return definition;
			}
		}
		return null;
	}
	private static NativeAbiType field_type(SemanticType type) throws NativeAbiError {
		if (type is ClassType || type is ReceiverType) {
			return new NativeScalarAbiType (NativeScalarType.PTR);
		}
		if (type is ContextBytesType) {
			return NativeTypeMapper.map_type (type);
		}
		if (type is SliceType) {
			return new NativeSliceType ();
		}
		if (type is StringType) {
			return new NativeTextType (NativeTextContract.RECEIVER_TEXT);
		}
		return NativeTypeMapper.map_type (type);
	}
	private static void add(GenericArray<NativeAsyncField> fields, SsaDefinition value, int block, int position) throws NativeAbiError {
		foreach (var field in fields) {
			if (field.definition == value.ordinal) {
				return;
			}
		}
		fields.add (new NativeAsyncField (value.ordinal, block, position, field_type (value.semantic_type)));
	}
	public static NativeAsyncFramePlan build(SsaFunction source, SsaProgram program) throws NativeAbiError {
		if (source.async_body != null && (source.async_body.declaration.file != source.span.file || source.async_body.declaration.start != source.span.start || source.async_body.declaration.end != source.span.end)) {
			throw new NativeAbiError.INVALID_SSA ("async body lost exact original declaration identity");
		}
		if (source.async_body == null || source.async_body.success_type.logical_identity != source.return_type.logical_identity || source.async_body.exception_bound != source.throws_type || source.async_body.success_mode != source.result_contract || source.implicit_receiver != null) {
			throw new NativeAbiError.INVALID_SSA ("async frame lost exact native body/result/effect contract");
		}
		if ((source.owned_cleanup != null && !source.owned_cleanup.is_buffer)) {
			throw new NativeAbiError.INVALID_SSA ("native frame planning for this owned/aggregate storage state is not yet supported");
		}
		foreach (var storage in source.object_storage) {
			if (!storage.heap_allocated) {
				throw new NativeAbiError.INVALID_SSA ("lexical object capture requires exact persistent object storage planning");
			}
		}

		foreach (var parameter in source.parameters) {
			bool owned_class = parameter.semantic_type is ClassType && (parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER && parameter.heap_object || NativeAbiBuilder.move_class_parameter (source, parameter.ordinal));
			if (parameter.semantic_type is ClassType && !owned_class || parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && !(parameter.semantic_type is SliceType) || parameter.semantic_type.is_lexically_borrowed_value () && !(parameter.semantic_type is SliceType) && !owned_class) {
				throw new NativeAbiError.INVALID_SSA ("native frame capture requires the exact proved suspension-loan or owner plan");
			}
		}
		int count = source.blocks.length;
		// Build the incoming graph once. Rebuilding every successor list for
		// every candidate dominator made larger structured task bodies cubic.
		var predecessors = new GenericArray<GenericArray<SsaBlock>> ();
		for (int b = 0; b < count; b++) {
			predecessors.add (new GenericArray<SsaBlock> ());
		}
		foreach (var prior in source.blocks) {
			foreach (var next in prior.terminator.successors ()) {
				if (next.ordinal < 0 || next.ordinal >= count || source.blocks[next.ordinal] != next) {
					throw new NativeAbiError.INVALID_SSA ("async frame edge lost exact program-owned block identity");
				}
				predecessors[next.ordinal].add (prior);
			}
		}
		bool[,] dominates = new bool[count, count];
		for (int b = 0; b < count; b++) {
			for (int d = 0; d < count; d++) {
				dominates[d, b] = b != source.entry.ordinal || d == b;
			}
		}
		bool changed = false;
		do {
			changed = false;
			foreach (var block in source.blocks) {
				if (block == source.entry) {
					continue;
				}
				for (int d = 0; d < count; d++) {
					bool incoming = true;
					foreach (var prior in predecessors[block.ordinal]) {
						incoming = incoming && dominates[d, prior.ordinal];
					}
					bool next = d == block.ordinal || incoming;
					if (next != dominates[d, block.ordinal]) {
						dominates[d, block.ordinal] = next;
						changed = true;
					}
				}
			}
		} while (changed);
		var loans = new GenericArray<NativeAsyncLoan> ();
		foreach (var block in source.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var creation = block.instructions[i] as SsaTaskCreate;
				if (creation == null) {
					continue;
				}
				foreach (var loan in creation.loans) {
					var view = loan.view as SsaDefinition;
					if (view == null) {
						throw new NativeAbiError.INVALID_SSA ("suspension capture requires its exact constructed view definition");
					}
					loans.add (new NativeAsyncLoan (loan.identity, block.ordinal, i, creation.direct_wait_position (block, i), creation.result.ordinal, creation.target.ordinal, loan.parameter_ordinal, view.ordinal, loan.storage.ordinal));
				}
			}
		}
		var waits = new GenericArray<NativeAsyncWait> ();
		foreach (var block in source.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var wait = block.instructions[i] as SsaTaskWait;
				if (wait == null) {
					continue;
				}
				var child = wait.child as SsaDefinition;
				if (child == null) {
					throw new NativeAbiError.INVALID_SSA ("pending task right has no exact child definition");
				}
				var leaves = new GenericArray<int> ();
				var success = wait.success;
				int enum_ordinal = -1;
				Astra.Source.EnumInstanceIdentity? enum_instance = null;
				if (success != null && !wait.discard) {
					if (success.struct_result != null) {
						foreach (var leaf in success.struct_result.leaves) {
							leaves.add (leaf.ordinal);
						}
					} else if (success.buffer_result != null) {
						leaves.add (((SsaDefinition) success.buffer_result.base_value).ordinal);
						leaves.add (((SsaDefinition) success.buffer_result.length_value).ordinal);
					} else if (success.enum_result != null) {
						enum_ordinal = success.enum_result.ordinal;
						enum_instance = success.enum_result.instance;
					} else if (success.result != null) {
						leaves.add (success.result.ordinal);
					}
				}
				waits.add (new NativeAsyncWait (block.ordinal, i, child.ordinal, wait.result.ordinal, wait.discard, ((TaskType) wait.child.semantic_type).identity, leaves, enum_ordinal, enum_instance, wait.bridge_executor == null ? -1 : ((SsaDefinition) wait.bridge_executor).ordinal, wait.bridge_owner == null ? -1 : wait.bridge_owner.ordinal, wait.bridge_executor == null ? Astra.Source.AsyncProviderKind.VIRTUAL : ((TaskType) wait.child.semantic_type).runtime.provider, wait.bridge_executor != null && AsyncBridgeTypes.compatible (wait.body.runtime, ((TaskType) wait.child.semantic_type).runtime)));
			}
		}
		// Only acquisitions before an incoming value's first ownership move
		// initialize cold frame captures. Later record/local transfers may
		// still use that same SSA parameter without creating another capture.
		var incoming = new HashTable<SsaValue, int> (direct_hash, direct_equal);
		for (int p = 0; p < source.parameters.length; p++) {
			incoming.insert (source.parameters[p], p);
		}
		var moved_inputs = new HashTable<SsaValue, bool> (direct_hash, direct_equal);
		var cold_owners = new HashTable<SsaHeapOwner, int> (direct_hash, direct_equal);
		foreach (var instruction in source.entry.instructions) {
			var event = instruction as SsaHeapOwnerEvent;
			if (event == null || !incoming.contains (event.value)) {
				continue;
			}
			if (event.action == SsaHeapOwnerAction.MOVE || event.action == SsaHeapOwnerAction.RETURN || event.action == SsaHeapOwnerAction.RELEASE || event.action == SsaHeapOwnerAction.END) {
				moved_inputs.insert (event.value, true);
			} else if (event.action == SsaHeapOwnerAction.ACQUIRE && event.owner != null && !moved_inputs.contains (event.value)) {
				int position = incoming.lookup (event.value);
				if (cold_owners.contains (event.owner) && cold_owners.lookup (event.owner) != position) {
					throw new NativeAbiError.INVALID_SSA ("cold owner acquired competing incoming parameters");
				}
				cold_owners.insert (event.owner, position);
			}
		}
		var fields = new GenericArray<NativeAsyncField> ();
		var owners = new GenericArray<NativeAsyncOwner> ();
		foreach (var owner in source.heap_owners) {
			int class_ordinal = -1;
			for (int c = 0; c < program.classes.length; c++) {
				if (program.classes[c] == owner.cleanup.object_class) {
					class_ordinal = c;
				}
			}
			int capture_first_leaf = cold_owners.contains (owner) ? cold_owners.lookup (owner) : -1;
			// Keep an owned local: a cast of an owning temporary in a nullable
			// conditional can retire that temporary before the constructor call.
			NativeClosureHandleType? closure = null;
			NativeContextHandleType? context = null;
			foreach (var block in source.blocks) {
				foreach (var instruction in block.instructions) {
					var event = instruction as SsaHeapOwnerEvent;
					if (event == null || event.owner != owner || event.action != SsaHeapOwnerAction.ACQUIRE) {
						continue;
					}
					var handle = event.value.semantic_type as HandleType;
					if (handle == null || handle.context_mode == "") {
						continue;
					}
					var mapped = NativeTypeMapper.map_type (handle) as NativeContextHandleType;
					if (mapped == null || context != null && !context.same_type (mapped)) {
						throw new NativeAbiError.INVALID_SSA ("async allocator context changed its nominal lifetime/thread contract across acquisitions");
					}
					context = mapped;
				}
			}
			if (owner.cleanup.closure_type != null) {
				var mapped = NativeTypeMapper.map_type (owner.cleanup.closure_type);
				closure = mapped as NativeClosureHandleType;
				if (closure == null) {
					throw new NativeAbiError.INVALID_SSA ("async closure lost its complete native callable type");
				}
			}
			owners.add (new NativeAsyncOwner (owners.length, owner.source_ordinal, class_ordinal, false,
				owner.cleanup.is_object ? "" : owner.cleanup.external_symbol, capture_first_leaf, owner.cleanup_position, closure, context, owner.record_rank));
		}
		foreach (var owner in source.frame_catch_owners) {
			int class_ordinal = -1;
			for (int c = 0; c < program.classes.length; c++) {
				if (program.classes[c].semantic_type == owner.semantic_type) {
					class_ordinal = c;
				}
			}
			owners.add (new NativeAsyncOwner (owners.length, owner.source_ordinal, class_ordinal, true, "", -1, owner.cleanup_position));
		}
		var definitions = new NativeAsyncFrameBuilder ();
		definitions.enum_program = program;
		var enums = new GenericArray<NativeAsyncEnumStorage> ();
		foreach (var slot in source.enum_slots) {
			bool owning = EnumValueAuthority.owns (slot.definition, definitions.enum_definition);
			enums.add (new NativeAsyncEnumStorage (slot.ordinal, slot.source_ordinal, slot.parameter_ordinal, slot.inspection_root == null ? -1 : slot.inspection_root.ordinal, slot.reservation_source == null ? -1 : slot.reservation_source.ordinal, slot.definition.semantic_type.identity, slot.instance, owning, slot.span.start));
		}
		var records = new HashTable<SemanticType, NativeRecordElement> (direct_hash, direct_equal);
		var storage = new GenericArray<NativeAsyncStorage> ();
		foreach (var slot in source.storage) {
			var array = slot.semantic_type as ArrayType;
			var element = array == null ? slot.semantic_type : array.element_type;
			var record = (element is StructType) ? NativeAbiBuilder.record_plan (element, program, records) : null;
			storage.add (new NativeAsyncStorage (slot.ordinal, slot.source_local_ordinal, array == null ? -1 : array.length, record == null ? field_type (element) : null, record));
		}
		var buffers = new GenericArray<NativeAsyncBuffer> ();
		foreach (var slot in source.buffer_storage) {
			int capture_first_leaf = -1;
			foreach (var group in source.buffer_parameters) {
				foreach (var instruction in source.entry.instructions) {
					var acquisition = instruction as SsaBufferWriteInstruction;
					if (acquisition != null && acquisition.initializes && acquisition.place.storage == slot && acquisition.pair == group.pair) {
						if (capture_first_leaf != -1) {
							throw new NativeAbiError.INVALID_SSA ("async capture has duplicate incoming buffer acquisition");
						}
						capture_first_leaf = group.first_leaf;
					}
				}
			}
			foreach (var instruction in source.entry.instructions) {
				var record = instruction as SsaStructBoundaryAcquire;
				if (record == null || record.parameter == null) {
					continue;
				}
				for (int b = 0; b < record.buffers.length; b++) {
					if (record.buffers[b] != slot) {
						continue;
					}
					for (int p = 0; p + 1 < source.parameters.length; p++) {
						var pair = record.buffer_pairs[b];
						if (pair.base_value == source.parameters[p] && pair.length_value == source.parameters[p + 1]) {
							if (capture_first_leaf != -1) {
								throw new NativeAbiError.INVALID_SSA ("record capture has duplicate incoming buffer acquisition");
							}
							capture_first_leaf = p;
						}
					}
				}
			}
			buffers.add ((slot.cleanup.buffer_type.element_type is StructType) ? new NativeAsyncBuffer.for_record (slot.ordinal, slot.owner_ordinal, NativeAbiBuilder.record_plan (slot.cleanup.buffer_type.element_type, program, records), capture_first_leaf, slot.cleanup_position, slot.record_rank) : new NativeAsyncBuffer (slot.ordinal, slot.owner_ordinal, NativeTypeMapper.map_type (slot.cleanup.buffer_type.element_type), capture_first_leaf, slot.cleanup_position, NativeTypeMapper.context_buffer_type (slot.cleanup.buffer_type), slot.record_rank));
		}
		foreach (var parameter in source.parameters) {
			add (fields, parameter, -1, -1);
		}
		foreach (var block in source.blocks) {
			foreach (var parameter in block.parameters) {
				add (fields, parameter, block.ordinal, -1);
			}
			for (int i = 0; i < block.instructions.length; i++) {
				var instruction = block.instructions[i];
				if (instruction.result != null) {
					add (fields, instruction.result, block.ordinal, i);
				}
				SsaBufferPair? pair = null;
				if (instruction is SsaTaskSuccess) {
					pair = ((SsaTaskSuccess) instruction).buffer_result;
				} else if (instruction is SsaBufferAllocateInstruction) {
					pair = ((SsaBufferAllocateInstruction) instruction).pair;
				} else if (instruction is SsaBufferReadInstruction) {
					pair = ((SsaBufferReadInstruction) instruction).pair;
				} else if (instruction is SsaFrameBufferRestore) {
					pair = ((SsaFrameBufferRestore) instruction).pair;
				} else if (instruction is SsaEnumReadBuffer) {
					pair = ((SsaEnumReadBuffer) instruction).pair;
				} else if (instruction is SsaGroupCallSuccess) {
					pair = ((SsaGroupCallSuccess) instruction).call.buffer_result;
				} else if (instruction is SsaCallInstruction && ((SsaCallInstruction) instruction).exception_result == null) {
					pair = ((SsaCallInstruction) instruction).buffer_result;
				}
				if (pair != null) {
					add (fields, (SsaDefinition) pair.base_value, block.ordinal, i);
					add (fields, (SsaDefinition) pair.length_value, block.ordinal, i);
				}
				if (instruction is SsaRecordAdmissionRestore) {
					foreach (var leaf in ((SsaRecordAdmissionRestore) instruction).results.leaves) {
						add (fields, leaf, block.ordinal, i);
					}
				}
				var operation = instruction as SsaAsyncOperation;
				if (operation != null && operation.exception != null) {
					add (fields, operation.exception, block.ordinal, i);
				}
				var call = instruction as SsaCallInstruction;
				if (call != null && call.exception_result != null) {
					add (fields, call.exception_result, block.ordinal, i);
				}
			}
		}
		var states = new GenericArray<NativeAsyncState> ();
		// Synchronous record calls retain every independently verified leaf,
		// including calls executed after a prior suspension.
		foreach (var block in source.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var instruction = block.instructions[i];
				var success = instruction as SsaGroupCallSuccess;
				var call = success != null ? success.call : instruction as SsaCallInstruction;
				var success_group = (instruction is SsaTaskSuccess) ? ((SsaTaskSuccess) instruction).struct_result : null;
				if (success_group != null) {
					foreach (var leaf in success_group.leaves) {
						add (fields, leaf, block.ordinal, i);
					}
				}
				if (call != null && !(call is SsaTaskCreate) && call.struct_result != null && (success != null || call.exception_result == null)) {
					foreach (var leaf in call.struct_result.leaves) {
						add (fields, leaf, block.ordinal, i);
					}
				}
			}
		}
		var initial = new GenericArray<int> ();
		for (int f = 0; f < fields.length; f++) {
			if (fields[f].block == -1) {
				initial.add (f);
			}
		}
		states.add (new NativeAsyncState (0, source.entry.ordinal, -1, initial));
		foreach (var block in source.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				if (!(block.instructions[i] is SsaAsyncDelay) && !(block.instructions[i] is SsaTaskWait)) {
					continue;
				}
				var initialized = new GenericArray<int> ();
				for (int f = 0; f < fields.length; f++) {
					var field = fields[f];
					if (field.block == -1 || (dominates[field.block, block.ordinal] && (field.block != block.ordinal || field.position < i))) {
						initialized.add (f);
					}
				}
				var payload = block.instructions[i] as SsaAsyncDelay;
				var definition = payload == null || !payload.payload ? null : payload.ticks as SsaDefinition;
				if (payload != null && payload.payload && (definition == null || payload.source_owner == null)) {
					throw new NativeAbiError.INVALID_SSA ("payload frame requires its exact unique fd/buffer owner");
				}
				states.add (new NativeAsyncState (states.length, block.ordinal, i, initialized, definition == null ? -1 : definition.ordinal, definition == null ? -1 : payload.source_owner.ordinal));
			}
		}
		var plan = new NativeAsyncFramePlan (source.ordinal, source.span, source.return_type.kind == TypeKind.VOID || source.struct_result != null ? null : field_type (source.return_type), fields, states, source.object_storage.length, source.heap_owners.length + source.frame_catch_owners.length, buffers, owners, storage, enums, source.struct_result == null ? null : NativeAbiBuilder.struct_value_plan (source.struct_result, program), loans, waits, source.async_body.runtime.provider);
		plan.verify ();
		return plan;
	}
	private static bool same_leaf(NativeAbiType? a, NativeAbiType? b) {
		return (a == null) == (b == null) && (a == null || a.same_type (b));
	}
	private static bool same_record(NativeRecordElement? a, NativeRecordElement? b) {
		if ((a == null) != (b == null)) {
			return false;
		}
		if (a == null) {
			return true;
		}
		if (a.struct_ordinal != b.struct_ordinal || a.struct_name != b.struct_name || a.fields.length != b.fields.length || a.natural_layout != b.natural_layout || a.structural_zero != b.structural_zero || a.trivial_destruction != b.trivial_destruction) {
			return false;
		}
		for (int f = 0; f < a.fields.length; f++) {
			if (a.fields[f].ordinal != b.fields[f].ordinal || a.fields[f].name != b.fields[f].name || !same_leaf (a.fields[f].leaf, b.fields[f].leaf) || !same_record (a.fields[f].record, b.fields[f].record)) {
				return false;
			}
		}
		return true;
	}
	public static void validate(NativeAsyncFramePlan plan, SsaFunction source, SsaProgram program) throws NativeAbiError {
		plan.verify ();
		var expected = build (source, program);
		if (plan.provider != expected.provider) {
			throw new NativeAbiError.INVALID_SSA ("async frame provider differs from original source nomination");
		}
		if (plan.loan_count != expected.loan_count) {
			throw new NativeAbiError.INVALID_SSA ("async loan count lost source correspondence");
		}
		for (uint l = 0; l < plan.loan_count; l++) {
			var a = plan.loan (l);
			var b = expected.loan (l);
			if (a.identity != b.identity || a.block != b.block || a.creation_position != b.creation_position || a.wait_position != b.wait_position || a.child_definition != b.child_definition || a.child_body != b.child_body || a.parameter_ordinal != b.parameter_ordinal || a.view_definition != b.view_definition || a.storage_ordinal != b.storage_ordinal) {
				throw new NativeAbiError.INVALID_SSA ("suspension loan lost original view/child/direct wait/parent storage correspondence");
			}
		}
		if (NativeAsyncFramePlan.record_identity (plan.record_result) != NativeAsyncFramePlan.record_identity (expected.record_result)) {
			throw new NativeAbiError.INVALID_SSA ("async record result lost complete original carrier or cleanup correspondence");
		}
		if ((plan.record_result == null) != (expected.record_result == null)) {
			throw new NativeAbiError.INVALID_SSA ("async record result lost source grouping");
		}
		if (plan.record_result != null) {
			var a = plan.record_result;
			var b = expected.record_result;
			if (a.struct_ordinal != b.struct_ordinal || a.struct_name != b.struct_name || a.result_carrier != b.result_carrier || a.leaves.length != b.leaves.length) {
				throw new NativeAbiError.INVALID_SSA ("async record result lost original declaration/carrier");
			}
			for (int l = 0; l < a.leaves.length; l++) {
				if (a.leaves[l].field_path != b.leaves[l].field_path || !a.leaves[l].abi_type.same_type (b.leaves[l].abi_type)) {
					throw new NativeAbiError.INVALID_SSA ("async record result lost original ordered leaf channel");
				}
			}
		}
		if (plan.enum_count != expected.enum_count) {
			throw new NativeAbiError.INVALID_SSA ("async enum count lost source correspondence");
		}
		for (uint e = 0; e < plan.enum_count; e++) {
			var a = plan.enum_slot (e);
			var b = expected.enum_slot (e);
			if (a.ordinal != b.ordinal || a.source_ordinal != b.source_ordinal || a.capture_first_leaf != b.capture_first_leaf || a.inspection_root != b.inspection_root || a.reservation_source != b.reservation_source || a.identity != b.identity || a.instance != b.instance || a.owning != b.owning || a.cleanup_position != b.cleanup_position) {
				throw new NativeAbiError.INVALID_SSA ("async enum storage lost original nominal/instance/capture/owner correspondence");
			}
		}
		if (plan.storage_count != expected.storage_count) {
			throw new NativeAbiError.INVALID_SSA ("async storage count lost source correspondence");
		}
		for (uint s = 0; s < plan.storage_count; s++) {
			var a = plan.storage_slot (s);
			var b = expected.storage_slot (s);
			if (a.ordinal != b.ordinal || a.source_ordinal != b.source_ordinal || a.array_count != b.array_count || !same_leaf (a.leaf, b.leaf) || !same_record (a.record, b.record)) {
				throw new NativeAbiError.INVALID_SSA ("async storage lost original declared record/array/local identity");
			}
		}
		if (plan.owner_count != expected.owner_count) {
			throw new NativeAbiError.INVALID_SSA ("async owner count lost source correspondence");
		}
		for (uint o = 0; o < plan.owner_count; o++) {
			var actual = plan.owner (o);
			var wanted = expected.owner (o);
			if (actual.ordinal != wanted.ordinal || actual.source_ordinal != wanted.source_ordinal || actual.class_ordinal != wanted.class_ordinal || actual.catch_owner != wanted.catch_owner || actual.cleanup_symbol != wanted.cleanup_symbol || actual.capture_first_leaf != wanted.capture_first_leaf || actual.cleanup_position != wanted.cleanup_position || actual.record_rank != wanted.record_rank || (actual.context == null ? wanted.context != null : wanted.context == null || !actual.context.same_type (wanted.context)) || (actual.closure == null ? wanted.closure != null : wanted.closure == null || !actual.closure.same_type (wanted.closure))) {
				throw new NativeAbiError.INVALID_SSA ("async frame owner lost exact original local/catch/class/context/closure correspondence");
			}
		}
		if (plan.buffer_count != expected.buffer_count) {
			throw new NativeAbiError.INVALID_SSA ("async buffer count lost source storage correspondence");
		}
		for (uint b = 0; b < plan.buffer_count; b++) {
			var actual = plan.buffer (b);
			var wanted = expected.buffer (b);
			if (actual.ordinal != wanted.ordinal || actual.owner_ordinal != wanted.owner_ordinal || actual.capture_first_leaf != wanted.capture_first_leaf || actual.cleanup_position != wanted.cleanup_position || actual.record_rank != wanted.record_rank || !same_leaf (actual.element, wanted.element) || !same_leaf (actual.context_origin, wanted.context_origin) || !same_record (actual.record_element, wanted.record_element)) {
				throw new NativeAbiError.INVALID_SSA ("async buffer lost original complete element/owner/storage association");
			}
		}
		if (plan.function_ordinal != expected.function_ordinal || plan.declaration.file != expected.declaration.file || plan.declaration.start != expected.declaration.start || plan.declaration.end != expected.declaration.end || plan.object_count != expected.object_count || plan.owner_count != expected.owner_count || plan.field_count != expected.field_count || plan.state_count != expected.state_count || (plan.result == null) != (expected.result == null) || (plan.result != null && !plan.result.same_type (expected.result))) {
			throw new NativeAbiError.INVALID_SSA ("async frame/body/result/source correspondence mismatch");
		}
		for (uint f = 0; f < plan.field_count; f++) {
			var actual = plan.field (f);
			var wanted = expected.field (f);
			if (actual.definition != wanted.definition || actual.block != wanted.block || actual.position != wanted.position || !actual.abi_type.same_type (wanted.abi_type)) {
				throw new NativeAbiError.INVALID_SSA ("async frame field lost exact original definition/type/site correspondence");
			}
		}
		if (plan.wait_count != expected.wait_count) {
			throw new NativeAbiError.INVALID_SSA ("pending task right count lost source correspondence");
		}
		for (uint w = 0; w < plan.wait_count; w++) {
			var a = plan.wait (w);
			var b = expected.wait (w);
			if (a.block != b.block || a.position != b.position || a.child_definition != b.child_definition || a.exception_definition != b.exception_definition || a.discard != b.discard || a.identity != b.identity || a.enum_ordinal != b.enum_ordinal || a.enum_instance != b.enum_instance || a.leaf_count != b.leaf_count || a.bridge_definition != b.bridge_definition || a.bridge_owner != b.bridge_owner || a.target_provider != b.target_provider || a.composed != b.composed) {
				throw new NativeAbiError.INVALID_SSA ("pending waiter lost original child/right/exception/result correspondence");
			}
			for (uint l = 0; l < a.leaf_count; l++) {
				if (a.leaf (l) != b.leaf (l)) {
					throw new NativeAbiError.INVALID_SSA ("pending task success lost original complete ordered result group");
				}
			}
		}
		for (uint s = 0; s < plan.state_count; s++) {
			var actual = plan.state (s);
			var wanted = expected.state (s);
			if (actual.payload_definition != wanted.payload_definition || actual.payload_owner != wanted.payload_owner || actual.pc != wanted.pc || actual.block != wanted.block || actual.position != wanted.position || actual.initialized_count != wanted.initialized_count) {
				throw new NativeAbiError.INVALID_SSA ("async resume state lost source suspension and initialized field correspondence");
			}
			for (uint f = 0; f < actual.initialized_count; f++) {
				if (actual.initialized_field (f) != wanted.initialized_field (f)) {
					throw new NativeAbiError.INVALID_SSA ("async resume initialization belongs to a different frame field");
				}
			}
		}
	}
}
}
