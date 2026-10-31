// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Cfg;
using Astra.Semantic;

namespace Astra.Ssa {
private class PlaceDefinitions : Object {
	public CfgBlock? initialization;
	public GenericArray<CfgBlock> sites = new GenericArray<CfgBlock> ();
	public GenericArray<SsaValue> stack = new GenericArray<SsaValue> ();
}

// All CFG identities below are temporary construction maps. No completed
// SSA node contains one; the builder dies before its result is consumed.
public class SsaBuilder : Object {
	private SsaValue owned_pointer(Source.SourceSpan span, SsaValue value, SemanticType type, SsaBlock block) throws SsaError {
		if (value.semantic_type == type) {
			return value;
		}
		if (!(value.semantic_type is ClassType && type is ClassType && ((ClassType) value.semantic_type).derives_from ((ClassType) type))) {
			throw new SsaError.INVALID_CFG ("owned pointer changed its exact transfer type");
		}
		var cast = new SsaClassUpcast (span, value, (SsaClass) structs.lookup (value.semantic_type), (SsaClass) structs.lookup (type), type, next_value++);
		block.instructions.add (cast);
		return cast.result;
	}
	private HashTable<CfgEnumSlot, SsaEnumSlot> enum_slots = new HashTable<CfgEnumSlot, SsaEnumSlot> (direct_hash, direct_equal);
	private HashTable<CfgEnumBufferCapture, SsaBufferPair> enum_buffers = new HashTable<CfgEnumBufferCapture, SsaBufferPair> (direct_hash, direct_equal);
	private HashTable<CfgEnumBufferCapture, SsaEnumBufferCapture> enum_buffer_captures = new HashTable<CfgEnumBufferCapture, SsaEnumBufferCapture> (direct_hash, direct_equal);
	private HashTable<CfgEnumScalarCapture, SsaEnumScalarCapture> enum_scalar_captures = new HashTable<CfgEnumScalarCapture, SsaEnumScalarCapture> (direct_hash, direct_equal);
	private HashTable<CfgBufferSlotCapture, SsaBufferSlotCaptureInstruction> buffer_slots = new HashTable<CfgBufferSlotCapture, SsaBufferSlotCaptureInstruction> (direct_hash, direct_equal);
	private HashTable<CfgBufferAllocate, SsaBufferAllocateInstruction> guarded_allocations = new HashTable<CfgBufferAllocate, SsaBufferAllocateInstruction> (direct_hash, direct_equal);
	private HashTable<CfgAllocationFailure, SsaAllocationFailure> allocation_failures = new HashTable<CfgAllocationFailure, SsaAllocationFailure> (direct_hash, direct_equal);
	private HashTable<CfgInstruction, SsaAllocationFailure> failure_calls = new HashTable<CfgInstruction, SsaAllocationFailure> (direct_hash, direct_equal);
	private HashTable<CfgPlace, SsaBufferStorage> buffer_storage = new HashTable<CfgPlace, SsaBufferStorage> (direct_hash, direct_equal);
	private HashTable<StructValueShape, StructValueShape> physical_record_shapes = new HashTable<StructValueShape, StructValueShape> (direct_hash, direct_equal);
	private HashTable<CfgValue, SsaBufferPair> buffer_values = new HashTable<CfgValue, SsaBufferPair> (direct_hash, direct_equal);
	private HashTable<CfgParameter, SsaBufferPair> buffer_parameters = new HashTable<CfgParameter, SsaBufferPair> (direct_hash, direct_equal);
	private HashTable<CfgPlace, SsaBufferPair> borrowed_record_buffers = new HashTable<CfgPlace, SsaBufferPair> (direct_hash, direct_equal);
	private HashTable<CfgPendingOwnedArgument, SsaBufferWriteInstruction> buffer_disarms = new HashTable<CfgPendingOwnedArgument, SsaBufferWriteInstruction> (direct_hash, direct_equal);
	private HashTable<CfgStructCallResults, SsaStructCallResults> struct_results = new HashTable<CfgStructCallResults, SsaStructCallResults> (direct_hash, direct_equal);
	private HashTable<StructBoundaryGroup, StructBoundaryGroup> record_parameters = new HashTable<StructBoundaryGroup, StructBoundaryGroup> (direct_hash, direct_equal);
	private HashTable<CfgStructBoundaryMove, SsaStructBoundaryMove> record_boundary_moves = new HashTable<CfgStructBoundaryMove, SsaStructBoundaryMove> (direct_hash, direct_equal);
	private HashTable<CfgCallResultValue, SsaCallInstruction> native_producers = new HashTable<CfgCallResultValue, SsaCallInstruction> (direct_hash, direct_equal);
	private GenericArray<SsaValue> disarmed_pointers = new GenericArray<SsaValue> ();
	private HashTable<CfgCleanupContract, SsaCleanupContract> cleanups;
	private HashTable<CfgProperty, SsaProperty> properties;
	private HashTable<CfgFunction, SsaFunction> callees;
	private HashTable<CfgCFunction, SsaCFunction> c_callees;
	private HashTable<CfgCallResultValue, SsaInstructionResult> call_results = new HashTable<CfgCallResultValue, SsaInstructionResult> (direct_hash, direct_equal);
	private HashTable<CfgOwnedBorrowValue, SsaValue> borrowed_values = new HashTable<CfgOwnedBorrowValue, SsaValue> (direct_hash, direct_equal);
	private HashTable<CfgPendingOwnedArgument, SsaOwnedArgumentReservation> argument_reservations = new HashTable<CfgPendingOwnedArgument, SsaOwnedArgumentReservation> (direct_hash, direct_equal);
	private HashTable<CfgAsyncOperation, SsaAsyncOperation> async_operations = new HashTable<CfgAsyncOperation, SsaAsyncOperation> (direct_hash, direct_equal);
	private HashTable<CfgTaskWait, SsaTaskWait> task_waits = new HashTable<CfgTaskWait, SsaTaskWait> (direct_hash, direct_equal);
	private HashTable<CfgCheckedClosureInvoke, SsaClosureCall> checked_closure_calls = new HashTable<CfgCheckedClosureInvoke, SsaClosureCall> (direct_hash, direct_equal);
	private HashTable<CfgCallInstruction, SsaCallInstruction> exception_calls = new HashTable<CfgCallInstruction, SsaCallInstruction> (direct_hash, direct_equal);
	private HashTable<CfgEvaluatedValue, SsaValue> evaluated_values = new HashTable<CfgEvaluatedValue, SsaValue> (direct_hash, direct_equal);
	private CfgFunction function;
	private CfgDominance dominance;
	private GenericArray<CfgBlock> reachable;
	private HashTable<CfgBlock, SsaBlock> blocks = new HashTable<CfgBlock, SsaBlock> (direct_hash, direct_equal);
	private HashTable<CfgObjectStorage, SsaObjectStorage> object_storage = new HashTable<CfgObjectStorage, SsaObjectStorage> (direct_hash, direct_equal);
	private HashTable<CfgStorageReceiverValue, SsaValue> storage_receivers = new HashTable<CfgStorageReceiverValue, SsaValue> (direct_hash, direct_equal);
	private SsaReceiver? receiver;
	private HashTable<CfgParameter, SsaFunctionParameter> slots_parameters;
	private HashTable<CfgParameter, SsaFunctionParameter> parameters = new HashTable<CfgParameter, SsaFunctionParameter> (direct_hash, direct_equal);
	private HashTable<CfgFieldPlace, SsaHeapOwner> record_owners = new HashTable<CfgFieldPlace, SsaHeapOwner> (direct_hash, direct_equal);
	private HashTable<CfgValue, SsaHeapOwner> record_incoming_sources = new HashTable<CfgValue, SsaHeapOwner> (direct_hash, direct_equal);
	private HashTable<CfgPlace, PlaceDefinitions> definitions = new HashTable<CfgPlace, PlaceDefinitions> (direct_hash, direct_equal);
	// Preserve scalar locals, field projections, then generated temporaries. These
	// construction-only maps use exact Place identity, never debug origin.
	// Includes raw-pointer locals: no address-of/ref/out/capture can expose
	// their storage. Borrowed pointee fields are separately memory-backed.
	private GenericArray<CfgPlace> places = new GenericArray<CfgPlace> ();
	private HashTable<SsaBlockParameter, CfgPlace> promoted_parameters = new HashTable<SsaBlockParameter, CfgPlace> (direct_hash, direct_equal);
	private HashTable<SemanticType, SsaNativeInstance> structs;
	private HashTable<CfgStructField, SsaStructField> fields;
	private HashTable<CfgExceptionMatch, SsaExceptionMatch> handler_selections = new HashTable<CfgExceptionMatch, SsaExceptionMatch> (direct_hash, direct_equal);
	private HashTable<CfgCatchBorrow, SsaCatchBorrow> handler_borrows = new HashTable<CfgCatchBorrow, SsaCatchBorrow> (direct_hash, direct_equal);
	private HashTable<CfgExceptionStorage, SsaFrameCatchOwner> frame_catch_owners = new HashTable<CfgExceptionStorage, SsaFrameCatchOwner> (direct_hash, direct_equal);
	private HashTable<CfgLocalPlace, SsaHeapOwner> heap_owners = new HashTable<CfgLocalPlace, SsaHeapOwner> (direct_hash, direct_equal);
	private HashTable<CfgLocalPlace, SsaTextLoan> text_loans = new HashTable<CfgLocalPlace, SsaTextLoan> (direct_hash, direct_equal);
	private HashTable<CfgLocalPlace, SsaAddressableLocal> storage = new HashTable<CfgLocalPlace, SsaAddressableLocal> (direct_hash, direct_equal);
	private HashTable<CfgPlace, SsaMemoryPlace> indexed_roots = new HashTable<CfgPlace, SsaMemoryPlace> (direct_hash, direct_equal);
	private HashTable<CfgFieldPlace, SsaMemoryPlace> memory_fields = new HashTable<CfgFieldPlace, SsaMemoryPlace> (direct_hash, direct_equal);
	private int next_value = 0;
	private OwnershipFlowResult replacement_flow;

	private SsaBuilder (CfgFunction function, HashTable<CfgFunction, SsaFunction> callees, HashTable<CfgCFunction, SsaCFunction> c_callees, HashTable<SemanticType, SsaNativeInstance> structs, HashTable<CfgStructField, SsaStructField> fields, HashTable<CfgCleanupContract, SsaCleanupContract> cleanups, HashTable<CfgProperty, SsaProperty> properties) {
		this.properties = properties;
		this.cleanups = cleanups;
		this.function = function;
		this.callees = callees;
		this.c_callees = c_callees;
		this.structs = structs;
		this.fields = fields;
		for (int i = 0; i < function.locals.length; i++) {
			if (function.locals[i].buffer_group == null && function.locals[i].is_promotable ()) {
				places.add (function.locals[i]);
			}
		}
		// Verifier guarantees canonical projection order: local ordinal,
		// then field declaration ordinal. Bases themselves never promote.
		foreach (var field in function.field_places) {
			if (field.is_promotable ()) {
				places.add (field);
			}
		}
		for (int i = 0; i < function.temporaries.length; i++) {
			places.add (function.temporaries[i]);
		}
		dominance = CfgDominance.analyze (function);
		reachable = CfgPredecessors.analyze (function).blocks ();
	}

	private static void retain_argument_type(SemanticType type, HashTable<SemanticType, SemanticType> needed) {
		if (type is StructType) {
			needed.insert (type, type);
		}
		if (type is FunctionValueType) {
			retain_argument_type (((FunctionValueType) type).result_type, needed);
		} else if (type is ClosureHandleType) {
			retain_argument_type (((ClosureHandleType) type).result_type, needed);
		}
		var signature = type as CallableSignature;
		if (signature != null) {
			foreach (var parameter in signature.parameter_types) {
				retain_argument_type (parameter, needed);
			}
		}
	}

	public static SsaProgram build(CfgProgram program, string[]? required_types = null) throws SsaError {
		// Direct API callers receive the same validated-input boundary as CLI.
		try {
			var flow = CfgFlowChecker.check (program);
			if (flow.diagnostic != null) {
				throw new SsaError.INVALID_CFG ("internal SSA construction error: CFG is not flow-valid: %s", flow.diagnostic.message);
			}
		} catch (CfgError error) {
			throw new SsaError.INVALID_CFG ("internal SSA construction error: %s", error.message);
		}
		var needed = new HashTable<SemanticType, SemanticType> (direct_hash, direct_equal);
		// A published type remains a metadata root even when no current body
		// transports a value. The module binder validates the exact inventory.
		foreach (string name in required_types ?? new string[0]) {
			foreach (var structure in program.structs) {
				if (structure.semantic_type.nominal_name () == name) {
					retain_argument_type (structure.semantic_type, needed);
				}
			}
		}
		foreach (var argument in program.class_type_arguments) {
			retain_argument_type (argument.semantic_type, needed);
		}
		foreach (var record in program.structs) {
			foreach (var argument in record.owning_arguments) {
				retain_argument_type (argument, needed);
			}
		}
		// An explicit C representation remains an admitted declaration even
		// when every current value was promoted into scalar SSA channels.
		foreach (var structure in program.structs) {
			if (structure.representation != null) {
				needed.insert (structure.semantic_type, structure.semantic_type);
			}
		}
		foreach (var owner in program.classes) {
			foreach (var method in owner.methods) {
				var key = method.generic_method_instance;
				if (key != null && key.argument is StructType) {
					needed.insert (key.argument, key.argument);
				}
			}
		}
		foreach (var owner in program.classes) {
			foreach (var field in owner.fields) {
				var slots = field.semantic_type as OwnerSlotsType;
				if (slots != null && slots.element is StructType) {
					needed.insert (slots.element, slots.element);
				}
			}
		}

		foreach (var definition in program.enums) {
			for (uint v = 0; v < definition.variant_count; v++) {
				var variant = definition.variant (v);
				for (uint f = 0; f < variant.field_count; f++) {
					var type = variant.field (f).semantic_type;
					if (type is StructType) {
						needed.insert (type, type);
					}
				}
			}
		}
		foreach (var cleanup in program.cleanups) {
			if (cleanup.is_buffer && cleanup.buffer_type.element_type is StructType) {
				var element = cleanup.buffer_type.element_type;
				needed.insert (element, element);
			}
		}
		foreach (var owner in program.classes) {
			foreach (var field in owner.fields) {
				retain_argument_type (field.semantic_type, needed);
			}
		}
		foreach (var function in program.functions) {
			retain_argument_type (function.return_type, needed);
			if (function.struct_result != null) {
				var type = function.struct_result.semantic_type;
				needed.insert (type, type);
			}
			foreach (var group in function.struct_parameters) {
				var type = group.shape.semantic_type;
				needed.insert (type, type);
			}
			if (function.implicit_receiver != null) {
				var type = function.implicit_receiver.contract.instance_type;
				needed.insert (type, type);
			}
			foreach (var parameter in function.parameters) {
				retain_argument_type (parameter.semantic_type, needed);
				var slice = parameter.semantic_type as SliceType;
				if (slice != null && slice.element_type is StructType) {
					needed.insert (slice.element_type, slice.element_type);
				}
				if (parameter.semantic_type.is_struct_pointer ()) {
					var pointee = ((TypedPointerType) parameter.semantic_type).pointee;
					needed.insert (pointee, pointee);
				}
			}
			foreach (var local in function.locals) {
				if (local.semantic_type is CallableSignature) {
					retain_argument_type (local.semantic_type, needed);
				}
				if (local.cleanup != null && local.semantic_type is StructType) {
					needed.insert (local.semantic_type, local.semantic_type);
				}
				var element = (local.semantic_type is ArrayType) ? ((ArrayType) local.semantic_type).element_type : (local.semantic_type is SliceType) ? ((SliceType) local.semantic_type).element_type : null;
				if (element is StructType) {
					needed.insert (element, element);
				}
				if (local.address_taken) {
					needed.insert (local.semantic_type, local.semantic_type);
				} else if (local.semantic_type.is_struct_pointer ()) {
					var pointee = ((TypedPointerType) local.semantic_type).pointee;
					needed.insert (pointee, pointee);
				}
			}
		}
		foreach (var imported in program.c_functions) {
			if (imported.return_type is StructType) {
				needed.insert (imported.return_type, imported.return_type);
			}
			foreach (var parameter in imported.parameter_types) {
				if (parameter is StructType) {
					needed.insert (parameter, parameter);
				}
			}
		}
		// Retain the transitive graph for memory roots and exact boundary verification.
		bool changed = true;
		while (changed) {
			changed = false;
			foreach (var structure in program.structs) {
				if (!needed.contains (structure.semantic_type)) {
					continue;
				}
				foreach (var field in structure.fields) {
					uint before = needed.size ();
					retain_argument_type (field.semantic_type, needed);
					changed |= needed.size () != before;
				}
			}
		}
		var structures = new GenericArray<SsaStruct> ();
		var classes = new GenericArray<SsaClass> ();
		var structs = new HashTable<SemanticType, SsaNativeInstance> (direct_hash, direct_equal);
		var properties = new HashTable<CfgProperty, SsaProperty> (direct_hash, direct_equal);
		var fields = new HashTable<CfgStructField, SsaStructField> (direct_hash, direct_equal);
		foreach (var source in program.native_instances ()) {
			if (!(source.semantic_type is ClassType) && !needed.contains (source.semantic_type)) {
				continue;
			}
			SsaNativeInstance structure = (source.semantic_type is ClassType) ? (SsaNativeInstance) new SsaClass (source.span, source.name_span, source.name, (ClassType) source.semantic_type, source.ordinal) : new SsaStruct (source.span, source.name_span, source.name, source.semantic_type, source.ordinal);
			if (source is CfgStruct) {
				var original = ((CfgStruct) source).representation;
				((SsaStruct) structure).representation = original == null ? null : original.copy ();
				foreach (var argument in ((CfgStruct) source).owning_arguments) {
					((SsaStruct) structure).owning_arguments.add (argument);
				}
			}
			if (structure is SsaClass) {
				classes.add ((SsaClass) structure);
			} else {
				structures.add ((SsaStruct) structure);
			}
			if (structure is SsaClass) {
				var key = ((CfgClass) source).generic_instance;
				((SsaClass) structure).generic_instance = key == null ? null : key.copy ();
			}
			structs.insert (source.semantic_type, structure);
			foreach (var property in source.properties) {
				var declaration = new SsaProperty (property.span, property.name_span, property.name, structure, property.semantic_type, property.ordinal, property.member_ordinal);
				declaration.is_lazy = property.is_lazy;
				declaration.is_owned_lazy = property.is_owned_lazy;
				declaration.is_borrowed = property.is_borrowed;
				structure.properties.add (declaration);
				properties.insert (property, declaration);
			}
			foreach (var field in source.fields) {
				var descriptor = new SsaStructField (field.span, field.name_span, field.name, structure, field.semantic_type, field.ordinal, field.is_private);
				if (field.requires_nonnull) {
					descriptor.mark_nonnull ();
				}
				descriptor.text_snapshot = field.text_snapshot;
				structure.fields.add (descriptor);
				fields.insert (field, descriptor);
			}
		}
		foreach (var source in program.classes) {
			var owner = (SsaClass) structs.lookup (source.semantic_type);
			owner.foreign_export = source.foreign_export == null ? null : source.foreign_export.copy ();
			owner.allocation_policy = source.allocation_policy == null ? null : source.allocation_policy.copy ();
			owner.concurrency_policy = source.concurrency_policy == null ? null : source.concurrency_policy.copy ();
			owner.parent_class = source.parent_class == null ? null : (SsaClass) structs.lookup (source.parent_class.semantic_type);
			owner.polymorphic = source.polymorphic;
			owner.exception_root = source.exception_root;
		}
		var cleanup_contracts = new GenericArray<SsaCleanupContract> ();
		var cleanups = new HashTable<CfgCleanupContract, SsaCleanupContract> (direct_hash, direct_equal);
		foreach (var source in program.cleanups) {
			// Root records are expanded into independently typed leaf obligations.
			if (source.record_type != null) {
				continue;
			}
			int ordinal = (int) cleanup_contracts.length;
			var cleanup = source.is_buffer ? new SsaCleanupContract.for_buffer (source.buffer_shape, source.symbol_span, ordinal) : source.is_object ? new SsaCleanupContract.for_object ((SsaClass) structs.lookup (source.object_class.semantic_type), ordinal, source.is_heap_object) : new SsaCleanupContract (source.external_symbol, source.symbol_span, ordinal);
			cleanup.closure_type = source.closure_type;
			if (source.closure_environment != null) {
				cleanup.closure_environment = (SsaClass) structs.lookup (source.closure_environment.semantic_type);
			}
			cleanup.shared_type = source.shared_type;
			if (source.shared_payload != null) {
				cleanup.shared_payload = (SsaClass) structs.lookup (source.shared_payload.semantic_type);
			}
			cleanup_contracts.add (cleanup);
			cleanups.insert (source, cleanup);
		}
		foreach (var owner in program.native_instances ()) {
			// Unused value-struct declarations are deliberately absent from SSA.
			if (!structs.contains (owner.semantic_type)) {
				continue;
			}
			foreach (var field in owner.fields) {
				if (field.slots_cleanup != null) {
					fields.lookup (field).slots_cleanup = cleanups.lookup (field.slots_cleanup);
				}
				if (field.owned_cleanup != null) {
					fields.lookup (field).owned_cleanup = cleanups.lookup (field.owned_cleanup);
				}
				if (field.owned_cleanup != null && field.owned_cleanup.record_type != null) {
					fields.lookup (field).record_owner = (SsaStruct) structs.lookup (field.semantic_type);
				}
			}
		}
		var handle_declarations = new GenericArray<SsaHandle> ();
		var handles = new HashTable<CfgHandle, SsaHandle> (direct_hash, direct_equal);
		foreach (var source in program.handles) {
			var handle = new SsaHandle (source.span, source.name_span, source.semantic_type, cleanups.lookup (source.cleanup), source.header, source.ordinal, source.context_mode);
			handle.c_import = source.c_import;
			handle.com_import = source.com_import == null ? null : source.com_import.copy ();
			handles.insert (source, handle);
			handle_declarations.add (handle);
		}
		var functions = new GenericArray<SsaFunction> ();
		var callees = new HashTable<CfgFunction, SsaFunction> (direct_hash, direct_equal);
		var imports = new GenericArray<SsaCFunction> ();
		var c_callees = new HashTable<CfgCFunction, SsaCFunction> (direct_hash, direct_equal);
		foreach (var source in program.c_functions) {
			var parameter_types = new GenericArray<SemanticType> ();
			var import_parameters = new GenericArray<SsaFunctionParameter> ();
			foreach (var parameter_type in source.parameter_types) {
				parameter_types.add (parameter_type);
			}
			foreach (var parameter in source.parameters) {
				if (parameter.requires_nonnull) {
					throw new SsaError.INVALID_CFG ("foreign nonnull contracts cannot be assumed");
				}
				var translated = new SsaFunctionParameter (parameter.span, parameter.name_span, parameter.name, parameter.semantic_type, parameter.ordinal, parameter.pointer_contract);
				import_parameters.add (translated);
			}
			var imported = new SsaCFunction (source.span, source.name_span, source.name, source.metadata, source.abi, source.return_type, parameter_types, imports.length, source.owned_cleanup == null ? null : cleanups.lookup (source.owned_cleanup), import_parameters);
			imports.add (imported);
			c_callees.insert (source, imported);
		}
		var builders = new GenericArray<SsaBuilder> ();
		var record_shapes = new HashTable<StructValueShape, StructValueShape> (direct_hash, direct_equal);
		for (int i = 0; i < program.functions.length; i++) {
			var builder = new SsaBuilder (program.functions[i], callees, c_callees, structs, fields, cleanups, properties);
			builder.physical_record_shapes = record_shapes;
			var function = builder.declare_function ();
			functions.add (function);
			function.async_body = program.functions[i].async_body;
			function.throws_type = program.functions[i].throws_type;
			function.dispatch_kind = program.functions[i].dispatch_kind;
			function.virtual_slot = program.functions[i].virtual_slot;
			callees.insert (program.functions[i], function);
			builders.add (builder);
		}
		foreach (var owner in program.native_instances ()) {
			foreach (var property in owner.properties) {
				if (property.factory != null) {
					properties.lookup (property).factory = (SsaMethod) callees.lookup (property.factory);
				}
			}
		}
		var all_parameters = new HashTable<CfgParameter, SsaFunctionParameter> (direct_hash, direct_equal);
		foreach (var builder in builders) {
			foreach (var parameter in builder.parameters.get_keys ()) {
				all_parameters.insert (parameter, builder.parameters.lookup (parameter));
			}
			builder.slots_parameters = all_parameters;
		}
		for (int i = 0; i < builders.length; i++) {
			try {
				builders[i].replacement_flow = OwnershipFlow.analyze (program.functions[i]);
			} catch (CfgError error) {
				throw new SsaError.INVALID_CFG (error.message);
			}
			builders[i].place_parameters ();
			builders[i].rename (program.functions[i].entry);
			foreach (var handler in program.functions[i].handlers) {
				var dispatch = builders[i].blocks.lookup (handler.dispatch);
				var matched = builders[i].blocks.lookup (handler.matched);
				var next = builders[i].blocks.lookup (handler.next);
				var selection = builders[i].handler_selections.lookup (handler.selection);
				var borrow = builders[i].handler_borrows.lookup (handler.borrow);
				if (dispatch != null && matched != null && next != null && selection != null && borrow != null) {
					functions[i].handlers.add (new SsaExceptionHandler (dispatch, matched, next, selection, borrow));
				}
			}
		}
		var exports = new GenericArray<SsaCExport> ();
		foreach (var exported in program.c_exports) {
			var source_target = exported.target;
			var target = source_target == null ? null : callees.lookup (source_target);
			if (target == null) {
				throw new SsaError.INVALID_CFG ("internal Ssa construction error: C export target is expired or has no exact native mapping");
			}
			exports.add (new SsaCExport (exported.span, exported.name_span, target, exported.external_symbol, exported.abi, exported.ordinal, exported.record_abi, exported.bool_abi));
		}
		foreach (var source in program.classes) {
			var owner = (SsaClass) structs.lookup (source.semantic_type);
			foreach (var entry in source.virtual_entries) {
				owner.virtual_entries.add (callees.lookup (entry));
			}
		}
		var result = new SsaProgram (program.span, functions, imports, exports, structures, cleanup_contracts, handle_declarations);
		foreach (var argument in program.class_type_arguments) {
			result.class_type_arguments.add (argument.copy ());
		}
		foreach (var definition in program.enums) {
			result.enums.add (definition);
		}
		foreach (var payload in program.text_literals) {
			result.text_literals.add (payload);
		}
		foreach (var object_class in classes) {
			result.classes.add (object_class);
		}
		SsaVerifier.verify (result);
		reanalyze_optimizations (result);
		for (int i = 0; i < builders.length; i++) {
			builders[i].verify_disarmed_pointers (functions[i]);
		}
		return result;
	}

	// Import authority is checked after typed native binding. Rebuild all
	// annotations before constructing a fresh native plan; never patch a seal.
	public static void reanalyze_optimizations(SsaProgram result) throws SsaError {
		foreach (var function in result.functions) {
			function.stack_objects.remove_range (0, function.stack_objects.length);
			function.shared_elisions.remove_range (0, function.shared_elisions.length);
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var call = instruction as SsaCallInstruction;
					if (call != null) {
						call.exact_target = null;
					}
				}
			}
		}
		SsaEffectAnalysis.annotate (result);
		SsaEffectAnalysis.verify (result);
		SsaFormalEffectVerifier.verify (result);
		SsaStackObjects.annotate (result);
		SsaStackObjects.verify (result);
		SsaExactCalls.annotate (result);
		SsaExactCalls.verify (result);
		SsaSharedElision.annotate (result);
		SsaSharedElision.verify (result);
	}

	// Check the physical consequence of already validated rearm events. This
	// construction-only proof follows pointer phis, including cycles; it never
	// authorizes source ownership operations from pointer nullness.
	private void verify_disarmed_pointers(SsaFunction function) throws SsaError {
		if (disarmed_pointers.length == 0) {
			return;
		}
		var incoming = new HashTable<SsaValue, GenericArray<SsaValue>> (direct_hash, direct_equal);
		foreach (var block in function.blocks) {
			foreach (var parameter in block.parameters) {
				incoming.insert (parameter, new GenericArray<SsaValue> ());
			}
		}
		foreach (var block in function.blocks) {
			var edges = new GenericArray<SsaEdge> ();
			var allocation = block.terminator as SsaBufferAllocationBranch;
			if (allocation != null) {
				edges.add (allocation.success_edge);
				edges.add (allocation.failure_edge);
			}
			var branch = block.terminator as SsaBranch;
			var conditional = block.terminator as SsaConditionalBranch;
			if (branch != null) {
				edges.add (branch.edge);
			}
			if (conditional != null) {
				edges.add (conditional.true_edge);
				edges.add (conditional.false_edge);
			}
			foreach (var edge in edges) {
				for (int i = 0; i < edge.arguments.length; i++) {
					incoming.lookup (edge.target.parameters[i]).add (edge.arguments[i]);
				}
			}
		}
		foreach (var root in disarmed_pointers) {
			var pending = new GenericArray<SsaValue> ();
			var visited = new HashTable<SsaValue, SsaValue> (direct_hash, direct_equal);
			pending.add (root);
			bool grounded = false;
			for (int i = 0; i < pending.length; i++) {
				var value = pending[i];
				if (!visited.insert (value, value)) {
					continue;
				}
				if (value is SsaNullPointerConstant) {
					grounded = true;
					continue;
				}
				var inputs = incoming.lookup (value);
				if (inputs == null || inputs.length == 0) {
					throw new SsaError.INVALID_CFG ("internal SSA construction error: definitely disarmed owner must have a null current pointer before rearm");
				}
				foreach (var input in inputs) {
					pending.add (input);
				}
			}
			if (!grounded) {
				throw new SsaError.INVALID_CFG ("internal SSA construction error: disarmed pointer cycle has no null input");
			}
		}
	}

	private bool record_buffer_parameter(int ordinal) {
		foreach (var group in function.struct_parameters) {
			if (ordinal >= group.first_leaf && ordinal < group.first_leaf + group.shape.leaves.length) {
				return group.shape.mode != StructValueMode.COPY_VALUE && function.parameters[ordinal].semantic_type is SliceType;
			}
		}
		return false;
	}

	private StructValueShape physical_record_shape(StructValueShape shape) throws SsaError {
		var prior = physical_record_shapes.lookup (shape);
		if (prior != null) {
			return prior;
		}
		try {
			var result = shape.flatten_buffers ((type) => { var cleanup = buffer_cleanup (type);
				                                            return cleanup == null ? null : cleanup.buffer_shape;
			});
			physical_record_shapes.insert (shape, result);
			return result;
		} catch (StructLeafError error) {
			throw new SsaError.INVALID_CFG ("record physical channels: %s", error.message);
		}
	}

	private GenericArray<SsaValue> lower_record_values(GenericArray<CfgValue> values, CfgBlock source) throws SsaError {
		var result = new GenericArray<SsaValue> ();
		foreach (var value in values) {
			if (value.semantic_type is SliceType) {
				var pair = lower_buffer_value (value, source);
				result.add (pair.base_value);
				result.add (pair.length_value);
			} else {
				result.add (lower_value (value, source));
			}
		}
		return result;
	}

	private SsaStructCallResults declare_record_results(CfgStructCallResults source) throws SsaError {
		var leaves = new GenericArray<SsaInstructionResult> ();
		var buffers = new GenericArray<SsaBufferPair> ();
		foreach (var leaf in source.leaves) {
			if (leaf.semantic_type is SliceType) {
				var pair = new SsaBufferPair.results (leaf.span, buffer_cleanup (leaf.semantic_type).buffer_shape, next_value);
				next_value += 2;
				buffer_values.insert (leaf, pair);
				buffers.add (pair);
				leaves.add ((SsaInstructionResult) pair.base_value);
				leaves.add ((SsaInstructionResult) pair.length_value);
			} else {
				var result = new SsaInstructionResult (leaf.span, leaf.semantic_type, next_value++);
				leaves.add (result);
				call_results.insert (leaf, result);
			}
		}
		var result = new SsaStructCallResults (source.span, physical_record_shape (source.shape), leaves);
		foreach (var pair in buffers) {
			result.buffers.add (pair);
		}
		struct_results.insert (source, result);
		return result;
	}

	private SsaFunction declare_function() throws SsaError {
		var method = function as CfgMethod;
		if (function.implicit_receiver != null) {
			receiver = new SsaReceiver (function.implicit_receiver.span, function.implicit_receiver.contract, next_value++);
		}
		var declarations = new GenericArray<SsaFunctionParameter> ();
		var buffer_groups = new GenericArray<SsaBufferParameter> ();
		for (int i = 0; i < function.parameters.length; i++) {
			var source = function.parameters[i];
			bool embedded = record_buffer_parameter (i);
			if (source.semantic_type is SliceType && (source.pointer_contract == PointerParameterContract.OWNED_TRANSFER || embedded)) {
				var contract = buffer_cleanup (source.semantic_type);
				var shape = contract.buffer_shape;
				var pointer = new SsaFunctionParameter (source.span, source.name_span, source.name, shape.base_type, next_value++);
				var length = new SsaFunctionParameter (source.span, source.name_span, source.name, shape.length_type, next_value++);
				var pair = new SsaBufferPair (source.span, shape, pointer, length);
				int logical = i;
				foreach (var aggregate in function.struct_parameters) {
					if (aggregate.first_leaf < i) {
						logical -= (int) aggregate.shape.leaves.length - 1;
					}
				}
				if (!embedded) {
					buffer_groups.add (new SsaBufferParameter (source.span, (int) declarations.length, logical, contract, pair));
				}
				declarations.add (pointer);
				declarations.add (length);
				buffer_parameters.insert (source, pair);
				continue;
			}
			var parameter = new SsaFunctionParameter (source.span, source.name_span, source.name, source.semantic_type, next_value++, source.pointer_contract);
			parameter.heap_object = source.heap_object;
			if (source.requires_nonnull) {
				parameter.mark_nonnull ();
			}
			declarations.add (parameter);
			parameters.insert (source, parameter);
		}
		var projected = new GenericArray<SsaBlock> ();
		for (int i = 0; i < reachable.length; i++) {
			var source = reachable[i];
			var block = new SsaBlock (source.span, i, source.ordinal);
			projected.add (block);
			blocks.insert (source, block);
		}
		SsaFunction result;
		var cleanup = function.owned_cleanup == null ? null : cleanups.lookup (function.owned_cleanup);
		var lifecycle = function as CfgLifecycle;
		if (lifecycle != null) {
			var object_class = (SsaClass) structs.lookup (lifecycle.declaring_class.semantic_type);
			if (function is CfgConstructor) {
				var constructor = new SsaConstructor (function.span, function.name_span, object_class, receiver, lifecycle.member_ordinal, function.return_type, function.ordinal, declarations, projected, blocks.lookup (function.entry));
				object_class.constructor = constructor;
				result = constructor;
			} else {
				var destructor = new SsaDestructor (function.span, function.name_span, object_class, receiver, lifecycle.member_ordinal, function.return_type, function.ordinal, declarations, projected, blocks.lookup (function.entry));
				object_class.destructor = destructor;
				result = destructor;
			}
		} else if (function is CfgPropertyAccessor) {
			var accessor = (CfgPropertyAccessor) function;
			var property = properties.lookup (accessor.property_member);
			if (function is CfgPropertyGetter) {
				var getter = new SsaPropertyGetter (function.span, function.name_span, function.name, property, receiver, function.return_type, function.ordinal, declarations, projected, blocks.lookup (function.entry), cleanup);
				property.getter = getter;
				result = getter;
			} else {
				var setter = new SsaPropertySetter (function.span, function.name_span, function.name, property, receiver, function.return_type, function.ordinal, declarations, projected, blocks.lookup (function.entry));
				property.setter = setter;
				result = setter;
			}
		} else if (method != null) {
			var structure = structs.lookup (method.declaring_type.semantic_type);
			var declaration = new SsaMethod (function.span, function.name_span, function.name, structure, receiver, method.method_ordinal, method.member_ordinal, function.return_type, function.ordinal, declarations, projected, blocks.lookup (function.entry), cleanup);
			declaration.generic_method_instance = method.generic_method_instance == null ? null : method.generic_method_instance.copy ();
			structure.methods.add (declaration);
			result = declaration;
		} else {
			result = new SsaFunction (function.span, function.name_span, function.name, function.return_type, function.ordinal, declarations, projected, blocks.lookup (function.entry), cleanup);
		}
		foreach (var group in buffer_groups) {
			result.buffer_parameters.add (group);
		}
		result.struct_result = function.struct_result == null ? null : physical_record_shape (function.struct_result);
		foreach (var group in function.struct_parameters) {
			int offset = group.first_leaf;
			for (int i = 0; i < group.first_leaf; i++) {
				if (function.parameters[i].semantic_type is SliceType && (function.parameters[i].pointer_contract == PointerParameterContract.OWNED_TRANSFER || record_buffer_parameter (i))) {
					offset++;
				}
			}
			var parameter = new StructBoundaryGroup (group.source_ordinal, offset, physical_record_shape (group.shape));
			result.struct_parameters.add (parameter);
			record_parameters.insert (group, parameter);
		}
		result.heap_result = function.heap_result;
		result.utf8_factory = function.utf8_factory;
		result.bind_floating_policy (function.floating_policy);
		if (function.nonnull_result) {
			result.mark_nonnull_result ();
		}
		if (function.native_declaration != null) {
			var types = new GenericArray<SemanticType> ();
			var contracts = new GenericArray<PointerParameterContract> ();
			var heaps = new bool[result.parameters.length];
			var nonnull = new bool[result.parameters.length];
			for (int p = 0; p < result.parameters.length; p++) {
				var parameter = result.parameters[p];
				types.add (parameter.semantic_type);
				contracts.add (parameter.pointer_contract);
				heaps[p] = parameter.heap_object;
				nonnull[p] = parameter.requires_nonnull;
			}
			var declared_receiver = result.implicit_receiver;
			result.bind_native_declaration (function.native_declaration.lowered (result.return_type, result.result_contract,
				result.heap_result, result.nonnull_result, declared_receiver == null ? null : declared_receiver.contract.instance_type,
				function.throws_type, types, contracts, heaps, nonnull));
		}
		if (function.result_storage != null) {
			result.result_storage = new SsaResultObjectStorage (function.span, (SsaClass) structs.lookup (function.return_type));
		}
		foreach (var source in function.object_storage) {
			var storage = new SsaObjectStorage (source.span, (SsaClass) structs.lookup (source.semantic_type), source.ordinal, source.region_ordinal, source.fallible);
			storage.cleanup_rank = source.cleanup_rank;
			foreach (var local in function.locals) {
				if (local.object_storage == source) {
					storage.text_extent = local.text_extent;
					break;
				}
			}
			storage.transferable = source.transferable;
			storage.heap_allocated = source.heap_allocated;
			storage.result_candidate = source.result_candidate;
			object_storage.insert (source, storage);
			result.object_storage.add (storage);
		}
		foreach (var slot in function.enum_slots) {
			var declared = new SsaEnumSlot (slot.span, slot.definition, result.enum_slots.length, slot.local == null ? -1 : slot.local.ordinal, slot.instance, slot.local == null || slot.local.incoming_parameter == null ? -1 : parameters.lookup (slot.local.incoming_parameter).ordinal);
			result.enum_slots.add (declared);
			enum_slots.insert (slot, declared);
		}
		foreach (var slot in function.enum_slots) {
			var declared = enum_slots.lookup (slot);
			declared.reservation_source = slot.reservation_source == null ? null : enum_slots.lookup (slot.reservation_source);
			declared.inspection_root = slot.inspection_root == null ? null : enum_slots.lookup (slot.inspection_root);
		}
		foreach (var temporary in function.temporaries) {
			if (function.async_body != null && temporary is CfgExceptionStorage) {
				var owner = new SsaFrameCatchOwner (result.frame_catch_owners.length, temporary.ordinal, (ClassType) temporary.semantic_type, temporary.span.start);
				result.frame_catch_owners.add (owner);
				frame_catch_owners.insert ((CfgExceptionStorage) temporary, owner);
			}
		}
		foreach (var local in function.locals) {
			if (local.semantic_type is TaskType) {
				result.task_owners.add (new SsaTaskOwner (local.ordinal, (TaskType) local.semantic_type, null, local.text_extent));
			}
			if (local.cleanup != null && local.semantic_type is StructType) {
				foreach (var field in function.field_places) {
					if (field.root_local () != local || field.field.owned_cleanup == null) {
						continue;
					}
					if (field.field.owned_cleanup.is_buffer) {
						var slot = new SsaBufferStorage (field.span, cleanups.lookup (field.field.owned_cleanup), (int) result.buffer_storage.length, (int) (function.locals.length + result.buffer_storage.length), local.span.start);
						slot.text_extent = local.text_extent;
						slot.record_type = (SsaStruct) structs.lookup (local.semantic_type);
						slot.record_path = field.storage_path ();
						slot.record_source_ordinal = local.ordinal;
						for (int r = 0; r < local.record_order.length; r++) {
							if (local.record_order[r].same_path (slot.record_path)) {
								slot.record_rank = r;
							}
						}
						result.buffer_storage.add (slot);
						buffer_storage.insert (field, slot);
						continue;
					}
					var owner = new SsaHeapOwner (result.heap_owners.length, local.ordinal, cleanups.lookup (field.field.owned_cleanup), local.span.start, (SsaStruct) structs.lookup (local.semantic_type));
					owner.text_extent = local.text_extent;
					owner.record_field = fields.lookup (field.field);
					owner.record_path = field.storage_path ();
					for (int r = 0; r < local.record_order.length; r++) {
						if (local.record_order[r].same_path (owner.record_path)) {
							owner.record_rank = r;
						}
					}
					result.heap_owners.add (owner);
					record_owners.insert (field, owner);
				}
			} else if (local.cleanup != null && persistent_owner (local.cleanup)) {
				var owner = new SsaHeapOwner (result.heap_owners.length, local.ordinal, cleanups.lookup (local.cleanup), local.span.start);
				owner.text_extent = local.text_extent;
				result.heap_owners.add (owner);
				heap_owners.insert (local, owner);
			}
			if (local.text_loan) {
				var loan = new SsaTextLoan (local.ordinal, local.text_extent);
				result.text_loans.add (loan);
				text_loans.insert (local, loan);
			}
			if (local.semantic_type is EnumType) {
				continue;
			}
			if (local.buffer_group != null) {
				var slot = new SsaBufferStorage (local.span, cleanups.lookup (local.cleanup), (int) result.buffer_storage.length, local.ordinal);
				slot.text_extent = local.text_extent;
				result.buffer_storage.add (slot);
				buffer_storage.insert (local, slot);
				continue;
			}
			if (local.address_taken || local.semantic_type is ArrayType) {
				var object = new SsaAddressableLocal (local.span, local.name_span, local.name, local.semantic_type, result.storage.length, local.ordinal, structs.lookup (local.semantic_type) as SsaStruct);
				result.storage.add (object);
				storage.insert (local, object);
			}
		}
		foreach (var field in function.field_places) {
			var root = field.root_local ();
			if (root == null || !root.address_taken) {
				continue;
			}
			if (field.aggregate is CfgLocalPlace) {
				memory_fields.insert (field, new SsaDirectFieldPlace (field.span, storage.lookup (root), fields.lookup (field.field)));
			} else {
				memory_fields.insert (field, new SsaFieldPlace.projection (field.span, memory_fields.lookup ((CfgFieldPlace) field.aggregate), fields.lookup (field.field)));
			}
		}
		return result;
	}

	private static string field_debug_name(CfgFieldPlace field) {
		return ((field.aggregate is CfgFieldPlace) ? field_debug_name ((CfgFieldPlace) field.aggregate) : field.root_local ().name) + "." + field.field.name;
	}

	private static int[] field_ordinals(CfgFieldPlace field) {
		int[] result = (field.aggregate is CfgFieldPlace) ? field_ordinals ((CfgFieldPlace) field.aggregate) : null;
		result += field.field.ordinal;
		return result;
	}

	private GenericArray<CfgFieldPlace> boundary_fields(CfgPlace root, StructValueShape shape) throws SsaError {
		var result = new GenericArray<CfgFieldPlace> ();
		foreach (var leaf in shape.leaves) {
			CfgFieldPlace? found = null;
			foreach (var field in function.field_places) {
				CfgPlace ancestor = field;
				bool matches = true;
				for (int d = leaf.depth - 1; d >= 0; d--) {
					var projection = ancestor as CfgFieldPlace;
					if (projection == null || projection.field.ordinal != leaf.field_ordinal (d)) {
						matches = false;
						break;
					}
					ancestor = projection.aggregate;
				}
				if (matches && ancestor == root && field.semantic_type == leaf.semantic_type) {
					found = field;
					break;
				}
			}
			if (found == null) {
				throw new SsaError.INVALID_CFG ("record boundary lost a declared field path");
			}
			result.add (found);
		}
		return result;
	}

	private void place_parameters() throws SsaError {
		for (int i = 0; i < places.length; i++) {
			definitions.insert (places[i], new PlaceDefinitions ());
		}

		for (int i = 0; i < reachable.length; i++) {
			var block = reachable[i];
			for (int j = 0; j < block.instructions.length; j++) {
				// A consuming task operation changes the local pointer to absent.
				// Its definition must participate in the same merge placement as
				// acquisition, including two consuming arms of a source branch.
				if (block.instructions[j] is CfgTaskMove) {
					definitions.lookup (((CfgTaskMove) block.instructions[j]).source).sites.add (block);
					continue;
				}
				if (block.instructions[j] is CfgTaskEnd) {
					definitions.lookup (((CfgTaskEnd) block.instructions[j]).source).sites.add (block);
					continue;
				}
				var borrowed_record = block.instructions[j] as CfgStructParameterBorrow;
				if (borrowed_record != null) {
					foreach (var field in boundary_fields (borrowed_record.destination, borrowed_record.parameter.shape)) {
						if (field.semantic_type is SliceType) {
							continue;
						}
						var state = definitions.lookup (field);
						state.initialization = block;
						state.sites.add (block);
					}
					continue;
				}
				var enum_scalar = block.instructions[j] as CfgEnumExtractScalar;
				if (enum_scalar != null) {
					var state = definitions.lookup (enum_scalar.destination);
					state.initialization = block;
					state.sites.add (block);
					continue;
				}
				var enum_construction = block.instructions[j] as CfgEnumConstruct;
				if (enum_construction != null) {
					foreach (var input in enum_construction.fields) {
						if (input.scalar_owner != null) {
							definitions.lookup (input.scalar_owner.source).sites.add (block);
						}
					}
				}
				var acquired_record = block.instructions[j] as CfgStructBoundaryAcquire;
				var moved_record = block.instructions[j] as CfgStructBoundaryMove;
				if (acquired_record != null || moved_record != null) {
					var root = acquired_record == null ? moved_record.source : acquired_record.destination;
					var shape = acquired_record == null ? moved_record.shape : acquired_record.shape;
					foreach (var field in boundary_fields (acquired_record == null ? (CfgPlace) root : acquired_record.target, shape)) {
						if (field.semantic_type is SliceType) {
							continue;
						}
						if (moved_record != null && field.field.owned_cleanup == null) {
							continue;
						}
						var state = definitions.lookup (field);
						if (state == null) {
							throw new SsaError.INVALID_CFG ("record boundary requires direct promoted local fields");
						}
						if (acquired_record != null) {
							state.initialization = block;
						}
						state.sites.add (block);
					}
					continue;
				}
				var commit = block.instructions[j] as CfgOwnedCallTransferCommit;
				if (commit != null) {
					foreach (var transfer in commit.transfers) {
						if (transfer.source != null && transfer.source.buffer_group == null) {
							definitions.lookup (transfer.source).sites.add (block);
						}
					}
					continue;
				}
				if (block.instructions[j] is CfgExceptionTake) {
					definitions.lookup (((CfgExceptionTake) block.instructions[j]).owner).sites.add (block);
				}
				if (block.instructions[j] is CfgSlotsReplace) {
					definitions.lookup (((CfgSlotsReplace) block.instructions[j]).incoming).sites.add (block);
					continue;
				}
				if (block.instructions[j] is CfgSlotsAppend) {
					definitions.lookup (((CfgSlotsAppend) block.instructions[j]).incoming).sites.add (block);
					continue;
				}
				var resource_capture = block.instructions[j] as CfgResourceCapture;
				if (block.instructions[j] is CfgRecordTake) {
					var take = (CfgRecordTake) block.instructions[j];
					if (!(take.field.semantic_type is SliceType)) {
						definitions.lookup (take.field).sites.add (block);
						definitions.lookup (take.destination).initialization = block;
						definitions.lookup (take.destination).sites.add (block);
					}
					continue;
				}
				if (block.instructions[j] is CfgRecordReplace) {
					var replace = (CfgRecordReplace) block.instructions[j];
					if (!(replace.field.semantic_type is SliceType)) {
						definitions.lookup (replace.field).sites.add (block);
						if (replace.source != null) {
							definitions.lookup (replace.source).sites.add (block);
						}
					}
					continue;
				}
				if (resource_capture != null && resource_capture.source != null) {
					if (resource_capture.source.buffer_group == null) {
						definitions.lookup (resource_capture.source).sites.add (block);
					}
					continue;
				}
				var owned_return = block.instructions[j] as CfgOwnershipReturnInstruction;
				if (owned_return != null && owned_return.result.source != null) {
					if (owned_return.result.source.buffer_group == null) {
						definitions.lookup (owned_return.result.source).sites.add (block);
					}
					continue;
				}
				var rearm = block.instructions[j] as CfgOwnershipRearmInstruction;
				if (rearm != null) {
					if (rearm.cleanup.is_buffer) {
						continue;
					}
					definitions.lookup (rearm.owner).sites.add (block);
					if (rearm.source != null) {
						definitions.lookup (rearm.source).sites.add (block);
					}
					continue;
				}
				var release = block.instructions[j] as CfgOwnershipReleaseInstruction;
				if (release != null) {
					if (release.cleanup.is_buffer) {
						continue;
					}
					definitions.lookup (release.owner).sites.add (block);
					continue;
				}
				var transfer = block.instructions[j] as CfgOwnershipTransferInstruction;
				if (transfer != null) {
					if (transfer.source.buffer_group != null) {
						continue;
					}
					if (transfer.destination.semantic_type is StructType) {
						foreach (var field in function.field_places) {
							if (!field.is_promotable ()) {
								continue;
							}
							if (field.root_local () == transfer.destination) {
								definitions.lookup (field).initialization = block;
								definitions.lookup (field).sites.add (block);
							} else if (field.root_local () == transfer.source && field.field.owned_cleanup != null) {
								definitions.lookup (field).sites.add (block);
							}
						}
						continue;
					}
					definitions.lookup (transfer.source).sites.add (block);
					var destination = definitions.lookup (transfer.destination);
					destination.initialization = block;
					destination.sites.add (block);
					continue;
				}
				var initialization = block.instructions[j] as CfgInitialize;
				if (initialization != null) {
					var state = definitions.lookup (initialization.target);
					if (state != null) {
						state.initialization = block;
						state.sites.add (block);
					}
				} else if (block.instructions[j] is CfgStore) {
					var store = (CfgStore) block.instructions[j];
					if (definitions.contains (store.target)) {
						definitions.lookup (store.target).sites.add (block);
					}
				}
			}
		}
		var placed = new bool[function.blocks.length, places.length];
		for (int p = 0; p < places.length; p++) {
			var state = definitions.lookup (places[p]);
			var pending = new GenericArray<CfgBlock> ();
			var queued = new bool[function.blocks.length];
			for (int i = 0; i < state.sites.length; i++) {
				var site = state.sites[i];
				if (!queued[site.ordinal]) {
					pending.add (site);
					queued[site.ordinal] = true;
				}
			}
			for (int i = 0; i < pending.length; i++) {
				var frontier = dominance.dominance_frontier (pending[i]);
				for (int j = 0; j < frontier.length; j++) {
					var join = frontier[j];
					// A Place has no value outside its initialization's
					// dominated region. This availability boundary needs no
					// liveness analysis; dead merges inside it are retained.
					if (state.initialization == null || !dominance.dominates (state.initialization, join) || placed[join.ordinal, p]) {
						continue;
					}
					placed[join.ordinal, p] = true;
					if (!queued[join.ordinal]) {
						queued[join.ordinal] = true;
						pending.add (join);
					}
				}
			}
		}
		// Number block parameters by block, scalar locals, fields, temporaries
		// before numbering computation in dominator-tree preorder.
		for (int b = 0; b < reachable.length; b++) {
			var source = reachable[b];
			var block = blocks.lookup (source);
			for (int l = 0; l < places.length; l++) {
				if (placed[source.ordinal, l]) {
					var place = places[l];
					var local = place as CfgLocalPlace;
					SsaBlockParameter parameter;
					var field = place as CfgFieldPlace;
					if (local != null) {
						parameter = new SsaBlockParameter (local.span, local.name_span, local.name, local.semantic_type, next_value++, local.ordinal);
					} else if (field != null) {
						var aggregate = field.root_local ();
						parameter = new SsaBlockParameter.field (place.span, field.field.name_span, field_debug_name (field), place.semantic_type, next_value++, aggregate.ordinal, field.field.ordinal, field_ordinals (field));
					} else {
						parameter = new SsaBlockParameter.temporary (place.span, place.semantic_type, next_value++, ((CfgTemporaryPlace) place).ordinal);
					}
					block.parameters.add (parameter);
					promoted_parameters.insert (parameter, place);
				}
			}
		}
	}

	private SsaCleanupContract? buffer_cleanup(SemanticType type) {
		foreach (var cleanup in cleanups.get_values ()) {
			if (cleanup.is_buffer && cleanup.buffer_type == type) {
				return cleanup;
			}
		}
		return null;
	}

	private SsaBufferPlace buffer_place(CfgPlace place, CfgBlock source) throws SsaError {
		if (buffer_storage.contains (place)) {
			return new SsaBufferPlace (place.span, buffer_storage.lookup (place).cleanup, buffer_storage.lookup (place));
		}
		var projected = lower_place (place, source);
		var field = projected as SsaIndirectFieldPlace;
		var cleanup = buffer_cleanup (place.semantic_type);
		if (projected is SsaFieldPlace && ((SsaFieldPlace) projected).aggregate != null && cleanup != null) {
			return new SsaBufferPlace.projection (place.span, cleanup, (SsaFieldPlace) projected);
		}
		if (field == null || cleanup == null) {
			throw new SsaError.INVALID_CFG ("buffer requires an exact local or class field owner slot");
		}
		return new SsaBufferPlace (place.span, cleanup, null, field);
	}

	private SsaBufferPair read_buffer(Astra.Source.SourceSpan span, SsaBufferPlace place, CfgBlock source) {
		var instruction = new SsaBufferReadInstruction (span, place, next_value);
		next_value += 2;
		blocks.lookup (source).instructions.add (instruction);
		return instruction.pair;
	}

	private SsaBufferWriteInstruction write_buffer(Astra.Source.SourceSpan span, SsaBufferPlace place, SsaBufferPair pair, CfgBlock source) {
		var instruction = new SsaBufferWriteInstruction (span, place, pair);
		blocks.lookup (source).instructions.add (instruction);
		return instruction;
	}

	private SsaBufferWriteInstruction disarm_buffer(CfgPlace local, CfgBlock source) throws SsaError {
		var place = buffer_place (local, source);
		return write_buffer (local.span, place, new SsaBufferPair.empty (local.span, place.cleanup.buffer_shape), source);
	}

	private SsaBufferPair lower_buffer_value(CfgValue value, CfgBlock source) throws SsaError {
		var pair = buffer_values.lookup (value);
		if (pair != null) {
			return pair;
		}
		if (value is CfgParameterValue) {
			pair = buffer_parameters.lookup (((CfgParameterValue) value).parameter);
		}
		if (value is CfgLoadValue) {
			var place = ((CfgLoadValue) value).source;
			pair = borrowed_record_buffers.lookup (place);
			if (pair == null) {
				pair = read_buffer (value.span, buffer_place (place, source), source);
			}
		}
		if (pair == null) {
			throw new SsaError.INVALID_CFG ("buffer owner producer has no complete PTR/I32 group");
		}
		return pair;
	}

	private void consume_buffer_result(CfgValue? value, SsaOwnedResultUse use) {
		var token = value as CfgCallResultValue;
		var producer = token == null ? null : native_producers.lookup (token);
		if (producer != null) {
			producer.owned_result_use = use;
		}
	}

	private bool lower_buffer_instruction(CfgInstruction instruction, CfgBlock source) throws SsaError {
		if (instruction is CfgSlotsRecordTransfer) {
			var transfer = (CfgSlotsRecordTransfer) instruction;
			var values = lower_record_values (transfer.leaves, source);
			var inserted = new SsaSlotsRecordTransfer (instruction.span, (SsaIndirectFieldPlace) lower_place (transfer.store, source), transfer.index == null ? null : lower_value (transfer.index, source), physical_record_shape (transfer.shape), values);
			if (transfer.record_move != null) {
				inserted.record_move = record_boundary_moves.lookup (transfer.record_move);
				if (inserted.record_move == null) {
					throw new SsaError.INVALID_CFG ("record slot insertion lost exact complete move");
				}
				inserted.record_move.consumer = inserted;
			}
			blocks.lookup (source).instructions.add (inserted);
			return true;
		}
		if (instruction is CfgRecordFieldCommit) {
			var commit = (CfgRecordFieldCommit) instruction;
			var values = lower_record_values (commit.leaves, source);
			var inserted = new SsaRecordFieldCommit (instruction.span,
				(SsaIndirectFieldPlace) lower_place (commit.destination, source), physical_record_shape (commit.shape),
				values, commit.initializes, commit.results == null ? null : struct_results.lookup (commit.results));
			if (commit.record_move != null) {
				inserted.record_move = record_boundary_moves.lookup (commit.record_move);
				if (inserted.record_move == null) {
					throw new SsaError.INVALID_CFG ("record field lost its exact complete move");
				}
				inserted.record_move.consumer = inserted;
			}
			blocks.lookup (source).instructions.add (inserted);
			return true;
		}
		if (instruction is CfgRecordFieldDrop) {
			var drop = (CfgRecordFieldDrop) instruction;
			blocks.lookup (source).instructions.add (new SsaRecordFieldDrop (instruction.span,
				(SsaIndirectFieldPlace) lower_place (drop.source, source), physical_record_shape (drop.shape)));
			return true;
		}
		if (instruction is CfgSlotsRecordRead) {
			var read = (CfgSlotsRecordRead) instruction;
			blocks.lookup (source).instructions.add (new SsaSlotsRecordRead (instruction.span, (SsaIndirectFieldPlace) lower_place (read.store, source), lower_value (read.index, source), read.remove, declare_record_results (read.results)));
			return true;
		}

		var block = blocks.lookup (source);
		if (instruction is CfgRecordTake && ((CfgRecordTake) instruction).field.semantic_type is SliceType) {
			var take = (CfgRecordTake) instruction;
			var pair = read_buffer (take.span, buffer_place (take.field, source), source);
			disarm_buffer (take.field, source);
			var write = write_buffer (take.span, buffer_place (take.destination, source), pair, source);
			write.initializes = true;
			write.record_take_source = buffer_storage.lookup (take.field);
			return true;
		}
		if (instruction is CfgRecordReplace && ((CfgRecordReplace) instruction).field.semantic_type is SliceType) {
			var replace = (CfgRecordReplace) instruction;
			var incoming = lower_buffer_value (replace.incoming, source);
			consume_buffer_result (replace.incoming, SsaOwnedResultUse.ACQUIRE);
			if (replace.source != null) {
				disarm_buffer (replace.source, source);
			}
			var place = buffer_place (replace.field, source);
			var old = read_buffer (replace.span, place, source);
			var retirement = new SsaBufferDeallocateInstruction (replace.span, old, place.cleanup);
			block.instructions.add (retirement);
			write_buffer (replace.span, place, incoming, source).record_retirement = retirement;
			return true;
		}
		var slot_capture = instruction as CfgBufferSlotCapture;
		if (slot_capture != null) {
			var slot = new SsaBufferSlotCaptureInstruction (instruction.span, buffer_place (slot_capture.place, source));
			buffer_slots.insert (slot_capture, slot);
			block.instructions.add (slot);
			return true;
		}
		var exchange = instruction as CfgBufferExchange;
		if (exchange != null) {
			var left = buffer_slots.lookup (exchange.left_capture);
			var right = buffer_slots.lookup (exchange.right_capture);
			if (left == null || right == null) {
				throw new SsaError.INVALID_CFG ("buffer exchange is missing an ordered slot capture");
			}
			block.instructions.add (new SsaBufferExchangeInstruction (instruction.span, left, right));
			return true;
		}
		var allocation = instruction as CfgBufferAllocate;
		if (allocation != null) {
			var context = allocation.allocation_context == null ? null : lower_value (allocation.allocation_context, source);
			var context_load = allocation.allocation_context as CfgLoadValue;
			var context_owner = context_load == null ? null : heap_owners.lookup (context_load.source as CfgLocalPlace);
			var lowered = allocation.failure == null ? new SsaBufferAllocateInstruction (instruction.span, lower_value (allocation.count, source), cleanups.lookup (allocation.cleanup), next_value, null, context, context_owner) : guarded_allocations.lookup (allocation);
			if (allocation.failure == null) {
				next_value += 2;
			}
			if (context_owner != null && allocation.failure == null) {
				block.instructions.add (new SsaHeapOwnerEvent (instruction.span, context_owner, SsaHeapOwnerAction.READ, context, lowered));
			}
			block.instructions.add (lowered);
			buffer_values.insert (allocation.results.owner, lowered.pair);
			return true;
		}
		var capture = instruction as CfgOwnedArgumentCapture;
		if (capture != null && capture.transfer.cleanup.is_buffer) {
			var pair = read_buffer (instruction.span, buffer_place (capture.transfer.source, source), source);
			buffer_values.insert (capture.transfer, pair);
			if (capture.transfer.exceptional_abort) {
				var reservation = new SsaOwnedArgumentReservation (instruction.span, null, pair, capture.transfer.source.ordinal);
				argument_reservations.insert (capture.transfer, reservation);
				block.instructions.add (reservation);
			}
			return true;
		}
		var commit = instruction as CfgOwnedCallTransferCommit;
		if (commit != null) {
			foreach (var transfer in commit.transfers) {
				if (transfer.cleanup.is_buffer) {
					buffer_disarms.insert (transfer, disarm_buffer (transfer.source, source));
				}
			}
			return false;
		}
		var returned = instruction as CfgOwnershipReturnInstruction;
		if (returned != null && function.owned_cleanup.is_buffer) {
			var value = returned.result;
			var pair = value.producer == null ? read_buffer(instruction.span, buffer_place (value.source, source), source) : lower_buffer_value (value.producer, source);
			buffer_values.insert (value, pair);
			consume_buffer_result (value.producer, SsaOwnedResultUse.FORWARD);
			if (value.source != null) {
				disarm_buffer (value.source, source);
			}
			return true;
		}
		var rearm = instruction as CfgOwnershipRearmInstruction;
		if (rearm != null && rearm.cleanup.is_buffer) {
			var place = buffer_place (rearm.owner, source);
			var pair = rearm.source == null ? lower_buffer_value(rearm.value, source) : read_buffer (instruction.span, buffer_place (rearm.source, source), source);
			if (rearm.source != null) {
				disarm_buffer (rearm.source, source);
			}
			consume_buffer_result (rearm.value, SsaOwnedResultUse.REARM);
			if (replacement_flow.rearm_states.lookup (rearm).may_own ()) {
				block.instructions.add (new SsaBufferDeallocateInstruction (instruction.span, read_buffer (instruction.span, place, source), place.cleanup));
			}
			write_buffer (instruction.span, place, pair, source);
			return true;
		}
		var transfer = instruction as CfgOwnershipTransferInstruction;
		if (transfer != null && transfer.source.buffer_group != null) {
			var pair = read_buffer (instruction.span, buffer_place (transfer.source, source), source);
			disarm_buffer (transfer.source, source);
			write_buffer (instruction.span, buffer_place (transfer.destination, source), pair, source);
			return true;
		}
		var release = instruction as CfgOwnershipReleaseInstruction;
		if (release != null && release.cleanup.is_buffer) {
			var place = buffer_place (release.owner, source);
			block.instructions.add (new SsaBufferDeallocateInstruction (instruction.span, read_buffer (instruction.span, place, source), place.cleanup));
			disarm_buffer (release.owner, source);
			return true;
		}
		var cleanup = instruction as CfgCleanupInstruction;
		if (cleanup != null && cleanup.cleanup.is_buffer) {
			block.instructions.add (new SsaBufferDeallocateInstruction (instruction.span, lower_buffer_value (cleanup.value, source), cleanups.lookup (cleanup.cleanup)));
			consume_buffer_result (cleanup.value, SsaOwnedResultUse.DISCARD);
			return true;
		}
		var borrow = instruction as CfgOwnedBorrowInstruction;
		if (borrow != null && borrow.result.source.buffer_group != null) {
			var pair = read_buffer (instruction.span, buffer_place (borrow.result.source, source), source);
			var view = new SsaBufferBorrowInstruction (instruction.span, pair, next_value++, (SliceType) borrow.result.semantic_type);
			block.instructions.add (view);
			borrowed_values.insert (borrow.result, view.result);
			return true;
		}
		var field_capture = instruction as CfgResourceCapture;
		if (field_capture != null && field_capture.cleanup.is_buffer) {
			var pair = lower_buffer_value (field_capture.value, source);
			buffer_values.insert (field_capture.result, pair);
			if (field_capture.source != null) {
				disarm_buffer (field_capture.source, source);
			}
			consume_buffer_result (field_capture.value, SsaOwnedResultUse.ACQUIRE);
			return true;
		}
		var initialization = instruction as CfgInitialize;
		if (initialization != null && initialization.target.semantic_type is SliceType && (initialization.target is CfgIndirectFieldPlace || buffer_storage.contains (initialization.target))) {
			var pair = lower_buffer_value (initialization.value, source);
			consume_buffer_result (initialization.value, SsaOwnedResultUse.ACQUIRE);
			write_buffer (instruction.span, buffer_place (initialization.target, source), pair, source).initializes = true;
			return true;
		}
		var store = instruction as CfgStore;
		if (store != null && store.target.semantic_type is SliceType && store.target is CfgIndirectFieldPlace) {
			write_buffer (instruction.span, buffer_place (store.target, source), lower_buffer_value (store.value, source), source);
			return true;
		}
		return false;
	}

	private SsaValue current(CfgPlace place, CfgBlock block) throws SsaError {
		var state = definitions.lookup (place);
		if (state == null || state.stack.length == 0) {
			string origin;
			if (place is CfgFieldPlace) {
				var field = (CfgFieldPlace) place;
				origin = "local #%d.field #%d".printf (field.root_local ().ordinal, field.field.ordinal);
			} else {
				origin = (place is CfgLocalPlace) ? "local #%d".printf (((CfgLocalPlace) place).ordinal) : "temporary #%d".printf (((CfgTemporaryPlace) place).ordinal);
			}
			throw new SsaError.INVALID_CFG ("internal SSA construction error at function #%d/block #%d: %s has no reaching definition", function.ordinal, block.ordinal, origin);
		}
		return state.stack[state.stack.length - 1];
	}

	private SsaTextLoanBind text_loan_binding(CfgValue input, SsaTextLoan loan, SsaValue value, CfgBlock source) throws SsaError {
		if (input.text_loan_intent == null) {
			throw new SsaError.INVALID_CFG ("stored text loan requires its retained receiver intent");
		}
		var owners = new GenericArray<Object> ();
		for (uint i = 0; i < input.text_loan_intent.count; i++) {
			var owner = input.text_loan_intent.owner (i);
			SsaValue? mapped = null;
			if (owner is CfgLocalPlace) {
				mapped = lower_value (new CfgLoadValue (input.span, (CfgLocalPlace) owner), source);
			} else if (owner is CfgParameter) {
				mapped = parameters.lookup ((CfgParameter) owner);
			} else if (owner is CfgReceiver) {
				mapped = receiver;
			}
			if (mapped == null) {
				throw new SsaError.INVALID_CFG ("text loan backing lacks an exact predecessor mapping");
			}
			owners.add (mapped);
		}
		return new SsaTextLoanBind (input.span, loan, value, new Astra.Text.TextLoanIntent (owners));
	}
	// Keep the instruction-lowering frame out of the recursive dominator walk.
	// Large inherited slice matrices otherwise retain every lowering temporary
	// at each dominator depth, exhausting the ordinary native stack.
	private void rename(CfgBlock source) throws SsaError {
		var depths = rename_block (source);
		var children = dominance.children (source);
		for (int i = 0; i < children.length; i++) {
			rename (children[i]);
		}
		for (int i = 0; i < depths.length; i++) {
			var stack = definitions.lookup (places[i]).stack;
			while (stack.length > depths[i]) {
				stack.remove_index (stack.length - 1);
			}
		}
	}

	private void add_catch_event(Astra.Source.SourceSpan span, SsaFrameCatchOwner owner, SsaValue value, SsaBlock block) {
		var event = new SsaFrameCatchEvent (span, owner, value);
		owner.retain_event (event);
		block.instructions.add (event);
	}
	private bool persistent_owner(CfgCleanupContract cleanup) {
		if (cleanup.record_type != null) {
			return true;
		}
		if (cleanup.is_object && cleanup.object_class.allocation_policy != null && cleanup.object_class.allocation_policy.context_mode == "scoped-affine") {
			return true;
		}
		if (cleanup.is_buffer) {
			return false;
		}
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var frame = instruction as CfgTaskCreate;
				if (frame != null && frame.checked_admission) {
					foreach (var input in frame.arguments) {
						var captured = input as CfgPendingOwnedArgument;
						if (captured != null && captured.cleanup == cleanup) {
							return true;
						}
					}
				}
			}
		}
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var call = instruction as CfgLifecycleCallInstruction;
				if (call != null && call.constructs && call.storage.fallible) {
					foreach (var input in call.arguments) {
						var captured = input as CfgPendingOwnedArgument;
						if (captured != null && captured.cleanup == cleanup) {
							return true;
						}
					}
				}
			}
		}
		foreach (var local in function.locals) {
			var context = local.semantic_type as HandleType;
			if (local.cleanup == cleanup && context != null && context.context_mode != "") {
				return true;
			}
		}
		foreach (var candidate in function.blocks) {
			foreach (var instruction in candidate.instructions) {
				var evaluation = instruction as CfgEvaluateInstruction;
				var call = evaluation == null ? null : evaluation.value as CfgInvocation;
				if (call != null && call.result_cleanup () == cleanup) {
					return true;
				}
			}
		}
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var evaluation = instruction as CfgEvaluateInstruction;
				var invocation = evaluation == null ? null : evaluation.value as CfgFunctionValueCall;
				var closure = evaluation == null ? null : evaluation.value as CfgClosureCall;
				if (invocation == null && closure == null) {
					continue;
				}
				foreach (var argument in invocation == null ? closure.arguments : invocation.arguments) {
					var borrow = argument as CfgOwnedBorrowValue;
					if (borrow != null && borrow.source.cleanup == cleanup) {
						return true;
					}
				}
			}
		}
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var append = instruction as CfgSlotsAppend;
				var replace = instruction as CfgSlotsReplace;
				var initialize = instruction as CfgInitialize;
				var take = initialize == null ? null : initialize.value as CfgSlotsValue;
				if (append != null && append.store.field.slots_cleanup == cleanup || replace != null && replace.store.field.slots_cleanup == cleanup || take != null && take.action == OwnerSlotsAction.TAKE && take.store.field.slots_cleanup == cleanup) {
					return true;
				}
			}
		}
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var capture = instruction as CfgEnumScalarCapture;
				var extraction = instruction as CfgEnumExtractScalar;
				if ((capture != null && capture.cleanup == cleanup) || (extraction != null && extraction.destination.cleanup == cleanup)) {
					return true;
				}
			}
		}
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var ended = instruction as CfgCleanupInstruction;
				if (ended != null && ended.record_owner != null && ended.cleanup == cleanup) {
					return true;
				}
			}
		}
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var transfer = instruction as CfgOwnershipTransferInstruction;
				if (transfer != null && transfer.source.incoming_parameter != null && transfer.cleanup == cleanup && !cleanup.is_buffer) {
					return true;
				}
			}
		}
		return cleanup.shared_type != null || cleanup.closure_type != null || cleanup.is_heap_object || (function.async_body != null && !cleanup.is_object && !cleanup.is_buffer);
	}

	private void nonnull_write(CfgPlace target, SsaValue value, SsaBlock block, Source.SourceSpan span) {
		var local = target as CfgLocalPlace;
		if (local == null || (!local.requires_nonnull && (local.incoming_parameter == null || !local.incoming_parameter.requires_nonnull))) {
			return;
		}
		var use = new SsaNonNullUse (span, value, local.ordinal, block, block.instructions.length);
		block.instructions.add (use);
		callees.lookup (function).retain_nonnull_use (use);
	}
	private int[] rename_block(CfgBlock source) throws SsaError {
		var block = blocks.lookup (source);
		var depths = new int[places.length];
		for (int i = 0; i < depths.length; i++) {
			depths[i] = definitions.lookup (places[i]).stack.length;
		}
		for (int i = 0; i < block.parameters.length; i++) {
			var parameter = block.parameters[i];
			definitions.lookup (promoted_parameters.lookup (parameter)).stack.add (parameter);
		}
		for (int i = 0; i < source.instructions.length; i++) {
			if (source.instructions[i] is CfgSlotsInitialize) {
				var operation = (CfgSlotsInitialize) source.instructions[i];
				block.instructions.add (new SsaSlotsEffect (operation.span, SsaSlotsAction.INITIALIZE, (SsaIndirectFieldPlace) lower_place (operation.store, source)));
				continue;
			}
			if (source.instructions[i] is CfgSlotsDrop) {
				var operation = (CfgSlotsDrop) source.instructions[i];
				block.instructions.add (new SsaSlotsEffect (operation.span, SsaSlotsAction.DROP, (SsaIndirectFieldPlace) lower_place (operation.store, source)));
				continue;
			}
			if (source.instructions[i] is CfgSlotsReplace) {
				var operation = (CfgSlotsReplace) source.instructions[i];
				var index = lower_value (operation.index, source);
				var incoming = current (operation.incoming, source);
				var replace = new SsaSlotsEffect (operation.span, SsaSlotsAction.REPLACE, (SsaIndirectFieldPlace) lower_place (operation.store, source), incoming, heap_owners.lookup (operation.incoming));
				replace.index = index;
				block.instructions.add (replace);
				block.instructions.add (new SsaHeapOwnerEvent (replace.span, replace.owner, SsaHeapOwnerAction.MOVE, incoming, replace));
				definitions.lookup (operation.incoming).stack.add (new SsaNullPointerConstant (replace.span, incoming.semantic_type));
				continue;
			}
			if (source.instructions[i] is CfgSlotsAppend) {
				var operation = (CfgSlotsAppend) source.instructions[i];
				var incoming = current (operation.incoming, source);
				var append = new SsaSlotsEffect (operation.span, SsaSlotsAction.APPEND, (SsaIndirectFieldPlace) lower_place (operation.store, source), incoming, heap_owners.lookup (operation.incoming));
				block.instructions.add (append);
				block.instructions.add (new SsaHeapOwnerEvent (append.span, append.owner, SsaHeapOwnerAction.MOVE, incoming, append));
				definitions.lookup (operation.incoming).stack.add (new SsaNullPointerConstant (append.span, incoming.semantic_type));
				continue;
			}
			if (source.instructions[i] is CfgSlotsBorrow) {
				var loan = ((CfgSlotsBorrow) source.instructions[i]).result;
				var index = lower_value (loan.index, source);
				var instruction = new SsaSlotsValueInstruction (loan.span, loan.semantic_type, next_value++, (SsaIndirectFieldPlace) lower_place (loan.store, source), OwnerSlotsAction.BORROW, index, slots_parameters.lookup (loan.borrower), loan.readonly_required);
				block.instructions.add (instruction);
				evaluated_values.insert (loan, instruction.result);
				continue;
			}

			if (source.instructions[i] is CfgAsyncRunStatus) {
				var run = (CfgAsyncRunStatus) source.instructions[i];
				block.instructions.add (new SsaAsyncRunStatus (run.span, async_operations.lookup (run.operation), enum_slots.lookup (run.destination)));
				continue;
			}
			if (source.instructions[i] is CfgExecutorEnd) {
				var end = (CfgExecutorEnd) source.instructions[i];
				block.instructions.add (new SsaExecutorEnd (end.span, current (end.source, source)));
				continue;
			}
			if (source.instructions[i] is CfgTaskBorrow) {
				var borrow = (CfgTaskBorrow) source.instructions[i];
				var value = new SsaTaskBorrow (borrow.span, current (borrow.source, source), borrow.source.ordinal, next_value++);
				block.instructions.add (value);
				evaluated_values.insert (borrow.result, value.result);
				continue;
			}
			if (source.instructions[i] is CfgTaskStarted) {
				var started = (CfgTaskStarted) source.instructions[i];
				block.instructions.add (new SsaTaskStarted (started.span, started.source.ordinal, async_operations.lookup (started.operation)));
				continue;
			}
			if (source.instructions[i] is CfgAsyncOperation) {
				var operation = (CfgAsyncOperation) source.instructions[i];
				var instruction = new SsaAsyncOperation (operation.span, operation.contract, operation.executor == null ? null : lower_value (operation.executor, source), operation.task == null ? null : lower_value (operation.task, source), operation.argument == null ? null : lower_value (operation.argument, source), operation.exception == null ? null : (ClassType) operation.exception.semantic_type, operation.task_owner, operation.executor_owner, operation.result == null ? -1 : next_value++, operation.exception == null ? -1 : next_value++);
				block.instructions.add (instruction);
				async_operations.insert (operation, instruction);
				if (operation.result != null) {
					evaluated_values.insert (operation.result, instruction.result);
				}
				if (operation.exception != null) {
					evaluated_values.insert (operation.exception, instruction.exception);
				}
				continue;
			}
			if (source.instructions[i] is CfgTaskWait) {
				var wait = (CfgTaskWait) source.instructions[i];
				var child = lower_value (wait.child, source);
				var bridge = wait.bridge_executor == null ? null : lower_value (wait.bridge_executor, source);
				var load = wait.bridge_executor as CfgLoadValue;
				var owner = load == null ? null : heap_owners.lookup (load.source as CfgLocalPlace);
				var operation = new SsaTaskWait (wait.span, wait.body, child, (ClassType) wait.exception.semantic_type, wait.discard, next_value++, bridge, owner);
				if (owner != null) {
					block.instructions.add (new SsaHeapOwnerEvent (wait.span, owner, SsaHeapOwnerAction.READ, bridge, operation));
				}
				block.instructions.add (operation);
				task_waits.insert (wait, operation);
				evaluated_values.insert (wait.exception, operation.result);
				continue;
			}
			if (source.instructions[i] is CfgTaskSuccess) {
				var success = (CfgTaskSuccess) source.instructions[i];
				var wait = task_waits.lookup (success.operation);
				SsaTaskSuccess loaded;
				if (success.enum_result != null) {
					loaded = new SsaTaskSuccess.for_enum (success.span, wait, enum_slots.lookup (success.enum_result));
				} else if (success.struct_result != null) {
					loaded = new SsaTaskSuccess.for_record (success.span, wait, declare_record_results (success.struct_result));
				} else {
					loaded = success.buffer_cleanup == null ? new SsaTaskSuccess (success.span, wait, success.result.semantic_type, next_value++) : new SsaTaskSuccess.for_buffer (success.span, wait, cleanups.lookup (success.buffer_cleanup), next_value);
					if (loaded.buffer_result != null) {
						next_value += 2;
						buffer_values.insert (success.result, loaded.buffer_result);
					} else {
						evaluated_values.insert ((CfgEvaluatedValue) success.result, loaded.result);
					}
				}
				wait.success = loaded;
				block.instructions.add (loaded);
				continue;
			}
			if (source.instructions[i] is CfgTaskMove) {
				var move = (CfgTaskMove) source.instructions[i];
				var captured = new SsaTaskMove (move.span, current (move.source, source), move.source.ordinal, next_value++);
				block.instructions.add (captured);
				evaluated_values.insert (move.result, captured.result);
				definitions.lookup (move.source).stack.add (new SsaTaskAbsent (move.span, (TaskType) move.source.semantic_type));
				continue;
			}
			if (source.instructions[i] is CfgTaskEnd) {
				var end = (CfgTaskEnd) source.instructions[i];
				block.instructions.add (new SsaTaskEnd (end.span, current (end.source, source), end.source.ordinal));
				definitions.lookup (end.source).stack.add (new SsaTaskAbsent (end.span, (TaskType) end.source.semantic_type));
				continue;
			}
			if (source.instructions[i] is CfgAsyncDelay) {
				var delay = (CfgAsyncDelay) source.instructions[i];
				var operand = lower_value (delay.ticks, source);
				var load = delay.ticks as CfgLoadValue;
				var owner = !delay.payload || load == null ? null : heap_owners.lookup (load.source as CfgLocalPlace);
				var operation = new SsaAsyncDelay (delay.span, delay.body, operand, (ClassType) delay.exception.semantic_type, next_value++, delay.payload, owner);
				if (owner != null) {
					block.instructions.add (new SsaHeapOwnerEvent (delay.span, owner, SsaHeapOwnerAction.READ, operand, operation));
				}
				block.instructions.add (operation);
				evaluated_values.insert (delay.exception, operation.result);
				continue;
			}
			if (source.instructions[i] is CfgOwnedArgumentAbort) {
				var aborted = (CfgOwnedArgumentAbort) source.instructions[i];
				var reservation = argument_reservations.lookup (aborted.transfer);
				if (reservation == null) {
					throw new SsaError.INVALID_CFG ("exception abort lost exact reservation capture");
				}
				block.instructions.add (new SsaOwnedArgumentAbort (aborted.span, reservation));
				continue;
			}
			if (lower_buffer_instruction (source.instructions[i], source)) {
				continue;
			}
			if (source.instructions[i] is CfgStructParameterBorrow) {
				var binding = (CfgStructParameterBorrow) source.instructions[i];
				var values = lower_record_values (binding.leaves, source);
				var marker = new SsaStructParameterBorrow (binding.span, record_parameters.lookup (binding.parameter), values);
				var fields = boundary_fields (binding.destination, binding.parameter.shape);
				int physical = 0;
				for (int f = 0; f < fields.length; f++) {
					if (fields[f].semantic_type is SliceType) {
						var pair = lower_buffer_value (binding.leaves[f], source);
						borrowed_record_buffers.insert (fields[f], pair);
						marker.buffers.add (pair);
						physical += 2;
					} else {
						definitions.lookup (fields[f]).stack.add (values[physical++]);
					}
				}
				block.instructions.add (marker);
				continue;
			}
			if (source.instructions[i] is CfgStructBoundaryAcquire || source.instructions[i] is CfgStructBoundaryMove) {
				var acquire = source.instructions[i] as CfgStructBoundaryAcquire;
				var move = source.instructions[i] as CfgStructBoundaryMove;
				var construction = move == null ? null : move.consumer as CfgLifecycleCallInstruction;
				if (construction != null && construction.constructs && construction.receiver is CfgStorageReceiverValue) {
					// Capture constructor storage after argument evaluation and before
					// any aggregate responsibility is disarmed for the call.
					lower_value (construction.receiver, source);
				}
				var root = acquire == null ? move.source : acquire.destination;
				var shape = acquire == null ? move.shape : acquire.shape;
				var incoming = acquire == null ? move.leaves : acquire.leaves;
				var fields = boundary_fields (acquire == null ? (CfgPlace) root : acquire.target, shape);
				var values = lower_record_values (incoming, source);
				var physical_shape = physical_record_shape (shape);
				var owners = new GenericArray<SsaHeapOwner> ();
				foreach (var field in fields) {
					if (field.field.owned_cleanup != null && !(field.semantic_type is SliceType)) {
						owners.add (record_owners.lookup (field));
					}
				}
				SsaStructBoundary marker;
				if (acquire != null) {
					var acquired = new SsaStructBoundaryAcquire (acquire.span, (SsaStruct) structs.lookup (root.semantic_type), root.ordinal, physical_shape, values, owners, acquire.parameter == null ? null : record_parameters.lookup (acquire.parameter), acquire.results == null ? null : struct_results.lookup (acquire.results), acquire.projection == null ? null : acquire.projection.storage_path ());
					if (acquire.record_move != null) {
						acquired.record_move = record_boundary_moves.lookup (acquire.record_move);
						if (acquired.record_move == null) {
							throw new SsaError.INVALID_CFG ("record subobject lost its complete source move");
						}
						acquired.record_move.consumer = acquired;
					}
					marker = acquired;
				} else {
					var moved = new SsaStructBoundaryMove (move.span, (SsaStruct) structs.lookup (root.semantic_type), root.ordinal, physical_shape, values, owners, move.use_kind);
					record_boundary_moves.insert (move, moved);
					marker = moved;
				}
				block.instructions.add (marker);
				int physical = 0;
				for (int f = 0; f < fields.length; f++) {
					var field = fields[f];
					if (field.semantic_type is SliceType) {
						marker.add_buffer (buffer_storage.lookup (field), lower_buffer_value (incoming[f], source));
						physical += 2;
						continue;
					}
					if (field.field.owned_cleanup != null) {
						block.instructions.add (new SsaHeapOwnerEvent (marker.span, record_owners.lookup (field), acquire == null ? SsaHeapOwnerAction.MOVE : SsaHeapOwnerAction.ACQUIRE, values[physical], marker));
					}
					if (acquire != null) {
						definitions.lookup (field).stack.add (values[physical]);
					} else if (field.field.owned_cleanup != null) {
						definitions.lookup (field).stack.add (new SsaNullPointerConstant (marker.span, field.semantic_type));
					}
					physical++;
				}
				for (int b = 0; b < marker.buffers.length; b++) {
					var place = new SsaBufferPlace (marker.span, marker.buffers[b].cleanup, marker.buffers[b]);
					var pair = acquire == null ? new SsaBufferPair.empty (marker.span, place.cleanup.buffer_shape) : marker.buffer_pairs[b];
					var write = write_buffer (marker.span, place, pair, source);
					write.initializes = acquire != null;
					write.record_boundary = marker;
				}
				continue;
			}
			if (source.instructions[i] is CfgActorSend) {
				var send = (CfgActorSend) source.instructions[i];
				var sender = lower_value (send.sender, source);
				var message = send.message == null ? null : lower_value (send.message, source);
				var load = send.sender as CfgLoadValue;
				var sender_owner = load == null ? null : heap_owners.lookup (load.source as CfgLocalPlace);
				var message_owner = (send.message is CfgEvaluatedValue) ? record_incoming_sources.lookup ((CfgEvaluatedValue) send.message) : null;
				var instruction = new SsaActorSend (send.span, send.action, sender, message, send.error_type, next_value++, sender_owner, message_owner);
				if (sender_owner != null) {
					block.instructions.add (new SsaHeapOwnerEvent (send.span, sender_owner, SsaHeapOwnerAction.READ, sender, instruction));
				}
				block.instructions.add (instruction);
				evaluated_values.insert (send.result, instruction.result);
				continue;
			}
			if (source.instructions[i] is CfgStructInvoke) {
				var invocation = (CfgStructInvoke) source.instructions[i];
				var group = declare_record_results (invocation.results);
				if (invocation.checked_call != null) {
					var success = new SsaClosureCallSuccess (invocation.span, checked_closure_calls.lookup (invocation.checked_call), -1);
					success.struct_result = group;
					block.instructions.add (success);
				} else {
					var call = lower_callable_invocation (invocation.call, source);
					if (call is SsaFunctionValueCall) {
						((SsaFunctionValueCall) call).struct_result = group;
					} else {
						((SsaClosureCall) call).struct_result = group;
					}
				}
				continue;
			}
			if (source.instructions[i] is CfgCheckedClosureInvoke) {
				var invocation = (CfgCheckedClosureInvoke) source.instructions[i];
				var call = invocation.call;
				var callee = lower_value (call.callee, source);
				int[] first_leaves;
				var arguments = lower_invocation_arguments (call.arguments, source, out first_leaves);
				var load = call.callee as CfgLoadValue;
				var owner = load == null ? null : heap_owners.lookup (load.source as CfgLocalPlace);
				var instruction = new SsaClosureCall (call.span, (ClosureHandleType) call.callee.semantic_type, callee, arguments, next_value++, owner, (ClassType) invocation.result.semantic_type, call.owned_cleanup == null ? null : cleanups.lookup (call.owned_cleanup));
				lower_record_arguments (call.span, call.struct_arguments, instruction.struct_arguments, call.arguments, first_leaves, source);
				retain_callable_arguments (instruction, instruction, call.arguments, (ClosureHandleType) call.callee.semantic_type, source, call.record_moves, first_leaves);
				if (owner != null) {
					block.instructions.add (new SsaHeapOwnerEvent (call.span, owner, SsaHeapOwnerAction.READ, callee, instruction));
				}
				block.instructions.add (instruction);
				checked_closure_calls.insert (invocation, instruction);
				evaluated_values.insert (invocation.result, instruction.result);
				continue;
			}
			if (source.instructions[i] is CfgClosureCallSuccess) {
				var success = (CfgClosureCallSuccess) source.instructions[i];
				var loaded = new SsaClosureCallSuccess (success.span, checked_closure_calls.lookup (success.invocation), next_value++);
				block.instructions.add (loaded);
				evaluated_values.insert (success.result, loaded.result);
				continue;
			}
			if (source.instructions[i] is CfgExceptionTake) {
				var take = (CfgExceptionTake) source.instructions[i];
				var pointer = current (take.owner, source);
				var disarmed = new SsaNullPointerConstant (take.span, pointer.semantic_type);
				var moved = new SsaExceptionTransfer (take.span, pointer, disarmed, take.owner.ordinal, next_value++);
				block.instructions.add (moved);
				block.instructions.add (new SsaHeapOwnerEvent (take.span, heap_owners.lookup (take.owner), SsaHeapOwnerAction.MOVE, pointer, moved));
				evaluated_values.insert (take.result, moved.result);
				definitions.lookup (take.owner).stack.add (disarmed);
				continue;
			}
			if (source.instructions[i] is CfgExceptionStamp) {
				var stamp = (CfgExceptionStamp) source.instructions[i];
				block.instructions.add (new SsaExceptionStamp (stamp.span, lower_value (stamp.exception, source)));
				continue;
			}
			if (source.instructions[i] is CfgConstructorAbort) {
				var abort = (CfgConstructorAbort) source.instructions[i];
				var lowered = new SsaConstructorAbort (abort.span, callees.lookup (function).implicit_receiver);
				foreach (var recipe in abort.fields) {
					lowered.fields.add (new SsaConstructorUnwindField (fields.lookup (recipe.field), recipe.cleanup == null ? null : cleanups.lookup (recipe.cleanup), recipe.shape == null ? null : physical_record_shape (recipe.shape)));
				}
				foreach (var property in abort.lazy_properties) {
					lowered.lazy_properties.add (properties.lookup (property));
				}
				block.instructions.add (lowered);
				continue;
			}
			if (source.instructions[i] is CfgGroupCallSuccess) {
				var success = (CfgGroupCallSuccess) source.instructions[i];
				block.instructions.add (new SsaGroupCallSuccess (success.span, exception_calls.lookup (success.call)));
				continue;
			}
			if (source.instructions[i] is CfgCallSuccess) {
				var success = (CfgCallSuccess) source.instructions[i];
				var loaded = new SsaCallSuccess (success.span, exception_calls.lookup (success.call), next_value++);
				block.instructions.add (loaded);
				evaluated_values.insert (success.result, loaded.result);
				if (success.call.target.owned_cleanup != null) {
					loaded.call.owned_success = loaded;
					call_results.insert (success.call.result, loaded.result);
				}
				continue;
			}
			var capture = source.instructions[i] as CfgOwnedArgumentCapture;
			if (capture != null) {
				var transfer = capture.transfer;
				var pointer = transfer.source == null ? new SsaNullPointerConstant (transfer.span, transfer.semantic_type) : current (transfer.source, source);
				pointer = owned_pointer (transfer.span, pointer, transfer.semantic_type, block);
				evaluated_values.insert (transfer, pointer);
				if (transfer.exceptional_abort) {
					var reservation = new SsaOwnedArgumentReservation (transfer.span, pointer, null, transfer.source == null ? -1 : transfer.source.ordinal);
					argument_reservations.insert (transfer, reservation);
					block.instructions.add (reservation);
				}
				continue;
			}
			var commit = source.instructions[i] as CfgOwnedCallTransferCommit;
			if (commit != null) {
				foreach (var transfer in commit.transfers) {
					if (transfer.source != null && transfer.source.buffer_group == null) {
						definitions.lookup (transfer.source).stack.add (new SsaNullPointerConstant (transfer.span, transfer.source.semantic_type));
					}
				}
				continue;
			}
			var consumption = source.instructions[i] as CfgStructResultConsume;
			if (consumption != null) {
				block.instructions.add (new SsaStructResultConsume (consumption.span, struct_results.lookup (consumption.results), consumption.use_kind));
				continue;
			}
			var owned_return = source.instructions[i] as CfgOwnershipReturnInstruction;
			if (owned_return != null) {
				var value = owned_return.result;
				evaluated_values.insert (value, owned_pointer (value.span, value.producer != null ? lower_value (value.producer, source) : value.source == null ? new SsaNullPointerConstant (value.span, value.semantic_type) : current (value.source, source), value.semantic_type, block));
				if (value.producer is CfgCallResultValue) {
					var producer = native_producers.lookup ((CfgCallResultValue) value.producer);
					if (producer != null) {
						producer.owned_result_use = SsaOwnedResultUse.FORWARD;
					}
				}
				if (persistent_owner (value.cleanup)) {
					block.instructions.add (new SsaHeapOwnerEvent (value.span, value.source == null ? null : heap_owners.lookup (value.source), SsaHeapOwnerAction.RETURN, evaluated_values.lookup (value)));
				}
				if (value.source != null) {
					definitions.lookup (value.source).stack.add (new SsaNullPointerConstant (value.span, value.source.semantic_type));
				}
				continue;
			}
			var rearm = source.instructions[i] as CfgOwnershipRearmInstruction;
			if (rearm != null) {
				// Flow already proved disarmament. The slot keeps its identity;
				// only its ordinary pointer reaching definition changes.
				var token = rearm.value as CfgCallResultValue;
				var native_producer = token == null ? null : native_producers.lookup (token);
				if (native_producer != null) {
					native_producer.owned_result_use = SsaOwnedResultUse.REARM;
				}
				var incoming = rearm.source == null ? lower_value(rearm.value, source) : current (rearm.source, source);
				nonnull_write (rearm.owner, incoming, block, rearm.span);
				if (rearm.source != null) {
					definitions.lookup (rearm.source).stack.add (new SsaNullPointerConstant (rearm.span, rearm.source.semantic_type));
				}
				if (persistent_owner (rearm.cleanup) && rearm.source != null) {
					block.instructions.add (new SsaHeapOwnerEvent (rearm.span, heap_owners.lookup (rearm.source), SsaHeapOwnerAction.MOVE, incoming));
				}
				if (replacement_flow.rearm_states.lookup (rearm).may_own ()) {
					var retired = new SsaCleanupInstruction (rearm.span, current (rearm.owner, source), cleanups.lookup (rearm.cleanup));
					block.instructions.add (retired);
					callees.lookup (function).retain_cleanup_effect (retired, block);
					if (persistent_owner (rearm.cleanup)) {
						block.instructions.add (new SsaHeapOwnerEvent (rearm.span, heap_owners.lookup (rearm.owner), SsaHeapOwnerAction.END, retired.value, retired));
					}
				} else {
					disarmed_pointers.add (current (rearm.owner, source));
				}
				if (persistent_owner (rearm.cleanup)) {
					block.instructions.add (new SsaHeapOwnerEvent (rearm.span, heap_owners.lookup (rearm.owner), SsaHeapOwnerAction.ACQUIRE, incoming));
				}
				definitions.lookup (rearm.owner).stack.add (incoming);
				continue;
			}
			var release = source.instructions[i] as CfgOwnershipReleaseInstruction;
			if (release != null) {
				// Responsibility was checked by CFG flow. Preserve the effect's
				// position, then define null for every downstream pointer use.
				var released = new SsaCleanupInstruction (release.span, current (release.owner, source), cleanups.lookup (release.cleanup));
				block.instructions.add (released);
				callees.lookup (function).retain_cleanup_effect (released, block);
				if (persistent_owner (release.cleanup)) {
					block.instructions.add (new SsaHeapOwnerEvent (release.span, heap_owners.lookup (release.owner), SsaHeapOwnerAction.RELEASE, released.value, released));
				}
				definitions.lookup (release.owner).stack.add (new SsaNullPointerConstant (release.span, release.owner.semantic_type));
				continue;
			}
			var transfer = source.instructions[i] as CfgOwnershipTransferInstruction;
			if (source.instructions[i] is CfgRecordTake) {
				var take = (CfgRecordTake) source.instructions[i];
				var pointer = current (take.field, source);
				var marker = new SsaRecordTake (take.span, record_owners.lookup (take.field), heap_owners.lookup (take.destination), pointer);
				block.instructions.add (marker);
				block.instructions.add (new SsaHeapOwnerEvent (take.span, marker.source, SsaHeapOwnerAction.MOVE, pointer, marker));
				block.instructions.add (new SsaHeapOwnerEvent (take.span, marker.destination, SsaHeapOwnerAction.ACQUIRE, pointer));
				definitions.lookup (take.field).stack.add (new SsaNullPointerConstant (take.span, take.field.semantic_type));
				definitions.lookup (take.destination).stack.add (pointer);
				continue;
			}
			if (source.instructions[i] is CfgRecordReplace) {
				var replace = (CfgRecordReplace) source.instructions[i];
				var incoming = lower_value (replace.incoming, source);
				var old = current (replace.field, source);
				var owner = record_owners.lookup (replace.field);
				var retirement = new SsaCleanupInstruction (replace.span, old, owner.cleanup);
				var marker = new SsaRecordReplace (replace.span, owner, replace.source == null ? null : heap_owners.lookup (replace.source), incoming, old, retirement);
				block.instructions.add (marker);
				if (replace.source != null) {
					block.instructions.add (new SsaHeapOwnerEvent (replace.span, marker.source_owner, SsaHeapOwnerAction.MOVE, incoming));
					definitions.lookup (replace.source).stack.add (new SsaNullPointerConstant (replace.span, replace.source.semantic_type));
				}
				block.instructions.add (retirement);
				callees.lookup (function).retain_cleanup_effect (retirement, block);
				block.instructions.add (new SsaHeapOwnerEvent (replace.span, owner, SsaHeapOwnerAction.END, old, retirement));
				block.instructions.add (new SsaHeapOwnerEvent (replace.span, owner, SsaHeapOwnerAction.ACQUIRE, incoming, marker));
				definitions.lookup (replace.field).stack.add (incoming);
				var token = replace.incoming as CfgCallResultValue;
				var producer = token == null ? null : native_producers.lookup (token);
				if (producer != null) {
					producer.owned_result_use = SsaOwnedResultUse.ACQUIRE;
				}
				continue;
			}
			if (transfer != null) {
				// Flow validation has completed. Transfer is now only pointer
				// definitions, at the original ordered instruction position.
				if (transfer.source.semantic_type is StructType) {
					foreach (var target in function.field_places) {
						if (target.root_local () != transfer.destination) {
							continue;
						}
						CfgFieldPlace? from = null;
						foreach (var field in function.field_places) {
							if (field.root_local () == transfer.source && field.storage_path ().same_path (target.storage_path ())) {
								from = field;
							}
						}
						if (target.semantic_type is SliceType && buffer_storage.contains (target)) {
							if (from == null || !buffer_storage.contains (from)) {
								throw new SsaError.INVALID_CFG ("record move lost full buffer field path");
							}
							var pair = read_buffer (transfer.span, buffer_place (from, source), source);
							disarm_buffer (from, source);
							var write = write_buffer (transfer.span, buffer_place (target, source), pair, source);
							write.initializes = true;
							write.record_move_source = buffer_storage.lookup (from);
							continue;
						}
						if (!target.is_promotable ()) {
							continue;
						}
						assert (from != null);
						var incoming = current (from, source);
						definitions.lookup (target).stack.add (incoming);
						if (record_owners.contains (from)) {
							var values = new GenericArray<SsaValue> ();
							values.add (incoming);
							var marker = new SsaRecordMove (transfer.span, record_owners.lookup (from), record_owners.lookup (target), incoming, values);
							block.instructions.add (marker);
							block.instructions.add (new SsaHeapOwnerEvent (transfer.span, marker.source, SsaHeapOwnerAction.MOVE, incoming, marker));
							block.instructions.add (new SsaHeapOwnerEvent (transfer.span, marker.destination, SsaHeapOwnerAction.ACQUIRE, incoming));
							definitions.lookup (from).stack.add (new SsaNullPointerConstant (transfer.span, incoming.semantic_type));
						}
					}
					continue;
				}
				var value = current (transfer.source, source);
				nonnull_write (transfer.destination, value, block, transfer.span);
				if (persistent_owner (transfer.source.cleanup)) {
					block.instructions.add (new SsaHeapOwnerEvent (transfer.span, heap_owners.lookup (transfer.source), SsaHeapOwnerAction.MOVE, value));
					block.instructions.add (new SsaHeapOwnerEvent (transfer.span, heap_owners.lookup (transfer.destination), SsaHeapOwnerAction.ACQUIRE, value));
				}
				definitions.lookup (transfer.destination).stack.add (value);
				definitions.lookup (transfer.source).stack.add (new SsaNullPointerConstant (transfer.span, transfer.source.semantic_type));
				continue;
			}
			if (source.instructions[i] is CfgLazyDrop) {
				block.instructions.add (new SsaLazyDrop (source.instructions[i].span, properties.lookup (((CfgLazyDrop) source.instructions[i]).property_member)));
				continue;
			}
			var cleanup = source.instructions[i] as CfgCleanupInstruction;
			if (cleanup != null) {
				var value = lower_value (cleanup.value, source);
				var ended = new SsaCleanupInstruction (cleanup.span, value, cleanups.lookup (cleanup.cleanup));
				block.instructions.add (ended);
				callees.lookup (function).retain_cleanup_effect (ended, block);
				if (cleanup.cleanup.is_heap_object && (cleanup.value is CfgLoadValue) && ((CfgLoadValue) cleanup.value).source is CfgExceptionStorage) {
					callees.lookup (function).retain_exception_disposition (ended, value);
					if (function.async_body != null) {
						var owner = frame_catch_owners.lookup ((CfgExceptionStorage) ((CfgLoadValue) cleanup.value).source);
						add_catch_event (cleanup.span, owner, new SsaNullPointerConstant (cleanup.span, owner.semantic_type), block);
					}
				}
				if (persistent_owner (cleanup.cleanup)) {
					var loaded = cleanup.value as CfgLoadValue;
					block.instructions.add (new SsaHeapOwnerEvent (cleanup.span, loaded == null ? null : (cleanup.record_owner == null ? heap_owners.lookup (loaded.source as CfgLocalPlace) : record_owners.lookup ((CfgFieldPlace) loaded.source)), SsaHeapOwnerAction.END, value, ended));
				}
				continue;
			}
			var borrow = source.instructions[i] as CfgOwnedBorrowInstruction;
			if (borrow != null) {
				var original = current (borrow.result.source, source);
				borrowed_values.insert (borrow.result, (borrow.result.semantic_type is CallbackType) ? (SsaValue) new SsaCallbackView (borrow.span, (CallbackType) borrow.result.semantic_type, original) : original);
				continue;
			}
			var array = source.instructions[i] as CfgArrayInitialize;
			if (array != null) {
				var elements = new GenericArray<SsaValue> ();
				foreach (var element in array.elements) {
					elements.add (lower_value (element, source));
				}
				if (array.record_root != null) {
					var root = (SsaArrayElementPlace) lower_place (array.record_root, source);
					var targets = new GenericArray<SsaMemoryPlace> ();
					foreach (var field in array.record_fields) {
						targets.add (lower_array_field (field, array.record_root, root));
					}
					block.instructions.add (new SsaArrayInitialize.record (array.span, root, targets, elements));
				} else {
					block.instructions.add (new SsaArrayInitialize (array.span, storage.lookup (array.storage), elements));
				}
				continue;
			}
			var numeric_guard = source.instructions[i] as CfgNumericGuard;
			if (numeric_guard != null) {
				var operand = lower_value (numeric_guard.value, source);
				var instruction = new SsaNumericGuard (numeric_guard.span, numeric_guard.destination_type, operand, next_value++, numeric_guard.policy);
				block.instructions.add (instruction);
				evaluated_values.insert (numeric_guard.result, instruction.result);
				continue;
			}
			var slice_bounds = source.instructions[i] as CfgSliceBoundsCheck;
			if (slice_bounds != null) {
				var view = lower_value (slice_bounds.slice, source);
				var index = lower_value (slice_bounds.value, source);
				var instruction = new SsaSliceBoundsCheck (slice_bounds.span, view, index, next_value++);
				block.instructions.add (instruction);
				evaluated_values.insert (slice_bounds.result, instruction.result);
				continue;
			}
			var bounds = source.instructions[i] as CfgArrayBoundsCheck;
			if (bounds != null) {
				var index = lower_value (bounds.value, source);
				var instruction = new SsaArrayBoundsCheck (bounds.span, storage.lookup (bounds.storage), index, next_value++);
				block.instructions.add (instruction);
				evaluated_values.insert (bounds.result, instruction.result);
				continue;
			}
			var validation = source.instructions[i] as CfgValidatePlace;
			if (validation != null) {
				block.instructions.add (new SsaValidatePlaceInstruction (validation.span, lower_place (validation.place, source)));
				continue;
			}
			var resource_capture = source.instructions[i] as CfgResourceCapture;
			if (resource_capture != null) {
				var incoming = lower_value (resource_capture.value, source);
				evaluated_values.insert (resource_capture.result, incoming);
				if (resource_capture.source != null && heap_owners.contains (resource_capture.source)) {
					record_incoming_sources.insert (resource_capture.result, heap_owners.lookup (resource_capture.source));
				}
				if (resource_capture.source != null && persistent_owner (resource_capture.cleanup)) {
					block.instructions.add (new SsaHeapOwnerEvent (resource_capture.span, heap_owners.lookup (resource_capture.source), SsaHeapOwnerAction.MOVE, incoming));
				}
				if (resource_capture.source != null) {
					definitions.lookup (resource_capture.source).stack.add (new SsaNullPointerConstant (resource_capture.span, resource_capture.source.semantic_type));
				}
				var producer_value = resource_capture.value as CfgCallResultValue;
				var producer = producer_value == null ? null : native_producers.lookup (producer_value);
				if (producer != null) {
					producer.owned_result_use = SsaOwnedResultUse.ACQUIRE;
				}
				continue;
			}
			var evaluation = source.instructions[i] as CfgEvaluateInstruction;
			if (evaluation != null) {
				if (evaluation.value.semantic_type.kind == TypeKind.VOID) {
					lower_callable_invocation (evaluation.value, source);
					continue;
				}
				if (evaluation is CfgEnumScalarCapture) {
					lower_enum_instruction (evaluation, source);
					continue;
				}
				if (evaluation is CfgRecordBufferCapture) {
					buffer_values.insert (evaluation.result, lower_buffer_value (evaluation.value, source));
				} else {
					evaluated_values.insert (evaluation.result, lower_value (evaluation.value, source));
				}
				continue;
			}
			var c_call = source.instructions[i] as CfgCCallInstruction;
			if (c_call != null) {
				lower_c_call (c_call, source);
				continue;
			}
			var call = source.instructions[i] as CfgCallInstruction;
			if (call != null) {
				lower_call (call, source);
				continue;
			}
			if (source.instructions[i] is CfgTextLoanEnd) {
				var end = (CfgTextLoanEnd) source.instructions[i];
				Astra.Text.TextLoanIntent? authority = null;
				foreach (var candidate in block.text_exits) {
					if (candidate.count != end.exit_authority.count) {
						continue;
					}
					bool equal = true;
					for (uint n = 0; n < candidate.count; n++) {
						equal = equal && candidate.owner (n) == text_loans.lookup ((CfgLocalPlace) end.exit_authority.owner (n));
					}
					if (equal) {
						authority = candidate;
						break;
					}
				}
				if (authority == null) {
					var loans = new GenericArray<Object> ();
					for (uint n = 0; n < end.exit_authority.count; n++) {
						loans.add (text_loans.lookup ((CfgLocalPlace) end.exit_authority.owner (n)));
					}
					authority = new Astra.Text.TextLoanIntent (loans);
					block.text_exits.add (authority);
				}
				block.instructions.add (new SsaTextLoanEnd (end.span, text_loans.lookup (end.local), authority));
				continue;
			}
			if (source.instructions[i] is CfgTextSnapshotDestroy) {
				var snapshot = (CfgTextSnapshotDestroy) source.instructions[i];
				block.instructions.add (new SsaTextSnapshotDestroy (snapshot.span, (SsaIndirectFieldPlace) lower_place (snapshot.field, source)));
				continue;
			}
			if (lower_enum_instruction (source.instructions[i], source)) {
				continue;
			}
			var initialization = source.instructions[i] as CfgInitialize;
			if (initialization != null) {
				var producer_value = initialization.value as CfgCallResultValue;
				var native_producer = producer_value == null ? null : native_producers.lookup (producer_value);
				if (native_producer != null && initialization.acquisition != null) {
					native_producer.owned_result_use = SsaOwnedResultUse.ACQUIRE;
				}
				var value = lower_value (initialization.value, source);
				nonnull_write (initialization.target, value, block, initialization.span);
				if (function.async_body != null && initialization.target is CfgExceptionStorage) {
					add_catch_event (initialization.span, frame_catch_owners.lookup ((CfgExceptionStorage) initialization.target), value, block);
				}
				if (initialization.target.semantic_type is TaskType) {
					var acquired = new SsaTaskAcquire (initialization.span, value, ((CfgLocalPlace) initialization.target).ordinal);
					block.instructions.add (acquired);
					foreach (var owner in callees.lookup (function).task_owners) {
						if (owner.source_ordinal == acquired.owner_ordinal) {
							owner.retain_acquisition (acquired);
						}
					}
				}
				if (initialization.acquisition != null && persistent_owner (initialization.acquisition.cleanup)) {
					SsaInstruction? marker = null;
					var producer_definition = value as SsaInstructionResult;
					if (producer_definition != null) {
						foreach (var prior in block.instructions) {
							var scoped = prior as SsaScopedAllocator;
							if (scoped != null && scoped.result == value) {
								marker = scoped;
							}
						}
					}
					if (initialization.acquisition.semantic_type is StructType) {
						var values = new GenericArray<SsaValue> ();
						values.add (value);
						marker = new SsaRecordAcquire (initialization.span, record_owners.lookup ((CfgFieldPlace) initialization.target), record_incoming_sources.lookup (initialization.value), value, values);
						block.instructions.add (marker);
					}
					var slots_value = initialization.value as CfgSlotsValue;
					if (slots_value != null && slots_value.action == OwnerSlotsAction.TAKE) {
						var take = block.instructions[block.instructions.length - 1] as SsaSlotsValueInstruction;
						if (take == null || take.result != value || take.action != OwnerSlotsAction.TAKE) {
							throw new SsaError.INVALID_CFG ("slot take lost direct acquisition instruction");
						}
						take.owner = heap_owners.lookup (initialization.acquisition);
						marker = take;
					}
					block.instructions.add (new SsaHeapOwnerEvent (initialization.span, ((initialization.acquisition.semantic_type is StructType) ? record_owners.lookup ((CfgFieldPlace) initialization.target) : heap_owners.lookup (initialization.acquisition)), SsaHeapOwnerAction.ACQUIRE, value, marker));
				}
				if (initialization.target is CfgLocalPlace && ((CfgLocalPlace) initialization.target).text_loan) {
					block.instructions.add (text_loan_binding (initialization.value, text_loans.lookup ((CfgLocalPlace) initialization.target), value, source));
				}
				if (initialization.target.is_promotable ()) {
					definitions.lookup (initialization.target).stack.add (value);
				} else {
					block.instructions.add (new SsaInitializeInstruction (initialization.span, lower_place (initialization.target, source), value));
				}
			} else {
				var store = source.instructions[i] as CfgStore;
				if (store == null) {
					throw new SsaError.INVALID_CFG ("SSA lowering has no typed handler for %s", source.instructions[i].get_type ().name ());
				}
				var value = lower_value (store.value, source);
				nonnull_write (store.target, value, block, store.span);
				if (function.async_body != null && store.target is CfgExceptionStorage) {
					add_catch_event (store.span, frame_catch_owners.lookup ((CfgExceptionStorage) store.target), value, block);
				}
				if (store.target is CfgLocalPlace && ((CfgLocalPlace) store.target).text_loan) {
					block.instructions.add (text_loan_binding (store.value, text_loans.lookup ((CfgLocalPlace) store.target), value, source));
				}
				if (store.target.is_promotable ()) {
					definitions.lookup (store.target).stack.add (value);
				} else {
					// Dereference bases are already captured by CFG before the RHS.
					// Existing indirect field assignments retain RHS-first semantics.
					var operation = new SsaStoreInstruction (store.span, lower_place (store.target, source), value, store.volatile_access == null ? null : store.volatile_access.copy ());
					block.instructions.add (operation);
					if (operation.volatile_access != null) {
						callees.lookup (function).retain_volatile_effect (operation, block);
					}
				}
			}
		}
		block.complete (lower_terminator (source));
		return depths;
	}

	private SsaEdge edge(CfgBlock source, CfgBlock target) throws SsaError {
		var successor = blocks.lookup (target);
		var arguments = new GenericArray<SsaValue> ();
		for (int i = 0; i < successor.parameters.length; i++) {
			arguments.add (current (promoted_parameters.lookup (successor.parameters[i]), source));
		}
		return new SsaEdge (successor, arguments);
	}

	private SsaTerminator lower_terminator(CfgBlock source) throws SsaError {
		var terminator = source.terminator;
		if (terminator is CfgForeignSignalReturn) {
			return new SsaForeignSignalReturn (terminator.span, ((CfgForeignSignalReturn) terminator).binding);
		}
		if (terminator is CfgForeignReturn) {
			var imported = (CfgForeignReturn) terminator;
			var consumed = new GenericArray<SsaValue> ();
			foreach (var owner in imported.consumed) {
				consumed.add (current (owner, source));
			}
			return new SsaForeignReturn (terminator.span, imported.binding, callees.lookup (imported.factory), consumed);
		}
		if (terminator is CfgNativeDeclaration) {
			return new SsaNativeDeclaration (terminator.span);
		}
		if (terminator is CfgExceptionReturn) {
			var value = lower_value (((CfgExceptionReturn) terminator).value, source);
			var returned = new SsaExceptionReturn (terminator.span, value);
			callees.lookup (function).retain_exception_disposition (returned, value);
			return returned;
		}
		if (terminator is CfgExceptionUnreachable) {
			return new SsaExceptionUnreachable (terminator.span, lower_value (((CfgExceptionUnreachable) terminator).exception, source));
		}
		if (terminator is CfgEnumInvalidTag) {
			return new SsaEnumInvalidTag (terminator.span);
		}
		if (terminator is CfgEnumDispatch) {
			var dispatch = (CfgEnumDispatch) terminator;
			var cases = new GenericArray<SsaEnumCase> ();
			foreach (var branch in dispatch.cases) {
				cases.add (new SsaEnumCase (branch.variant, edge (source, branch.target)));
			}
			return new SsaEnumDispatch (terminator.span, enum_slots.lookup (dispatch.source), cases, edge (source, dispatch.invalid_target));
		}
		var request = terminator as CfgBufferAllocationBranch;
		if (request != null) {
			var action = request.allocation.failure;
			var failure = new SsaAllocationFailure (action.span, action.target == null ? null : callees.lookup (action.target), action.c_target == null ? null : c_callees.lookup (action.c_target));
			failure.captured_receiver = action.captured_receiver == null ? null : lower_value (action.captured_receiver, source);
			allocation_failures.insert (action, failure);
			failure_calls.insert (action.action, failure);
			var context = request.allocation.allocation_context == null ? null : lower_value (request.allocation.allocation_context, source);
			var context_load = request.allocation.allocation_context as CfgLoadValue;
			var context_owner = context_load == null ? null : heap_owners.lookup (context_load.source as CfgLocalPlace);
			var allocation = new SsaBufferAllocateInstruction (request.allocation.span, lower_value (request.allocation.count, source), cleanups.lookup (request.allocation.cleanup), next_value, failure, context, context_owner);
			next_value += 2;
			if (context_owner != null) {
				blocks.lookup (source).instructions.add (new SsaHeapOwnerEvent (request.allocation.span, context_owner, SsaHeapOwnerAction.READ, context, allocation));
			}
			guarded_allocations.insert (request.allocation, allocation);
			return new SsaBufferAllocationBranch (terminator.span, allocation, edge (source, request.success_target), edge (source, request.failure_target));
		}
		if (terminator is CfgAllocationFailureTrap) {
			return new SsaAllocationFailureTrap (terminator.span, allocation_failures.lookup (((CfgAllocationFailureTrap) terminator).failure));
		}
		var returned = terminator as CfgReturn;
		if (returned != null) {
			if (returned is CfgEnumReturn) {
				return new SsaEnumReturn (returned.span, enum_slots.lookup (((CfgEnumReturn) returned).source));
			}
			if (returned is CfgStructReturn) {
				var aggregate = (CfgStructReturn) returned;
				var leaves = lower_record_values (aggregate.leaves, source);
				var result = new SsaStructReturn (returned.span, physical_record_shape (aggregate.shape), leaves);
				if (aggregate.record_move != null) {
					result.record_move = record_boundary_moves.lookup (aggregate.record_move);
					if (result.record_move == null) {
						throw new SsaError.INVALID_CFG ("record return lost its complete ownership commit");
					}
					result.record_move.consumer = result;
				}
				return result;
			}
			if (returned is CfgOwnershipReturn && function.owned_cleanup.is_buffer) {
				return new SsaBufferReturn (returned.span, buffer_values.lookup (returned.value), cleanups.lookup (function.owned_cleanup));
			}
			if (returned is CfgOwnershipReturn) {
				var value = (CfgOwnedReturnValue) returned.value;
				var result = lower_value (value, source);
				var parameter = value.provenance == ObjectResultProvenance.OWNED_PARAMETER_STORAGE ? result as SsaFunctionParameter
				        : value.source == null || value.source.incoming_parameter == null ? null : parameters.lookup (value.source.incoming_parameter);
				return new SsaOwnershipReturn (returned.span, result, value.provenance, parameter);
			}
			return new SsaReturn (returned.span, returned.value == null ? null : lower_value (returned.value, source));
		}
		if (terminator is CfgFunctionEnd) {
			return new SsaFunctionEnd (terminator.span);
		}
		var branch = terminator as CfgBranch;
		if (branch != null) {
			return new SsaBranch (branch.span, edge (source, branch.target));
		}
		var conditional = (CfgConditionalBranch) terminator;
		var condition = lower_value (conditional.condition, source);
		var true_edge = edge (source, conditional.true_target);
		var false_edge = edge (source, conditional.false_target);
		return new SsaConditionalBranch (conditional.span, condition, true_edge, false_edge);
	}

	private bool lower_enum_instruction(CfgInstruction source_instruction, CfgBlock source) throws SsaError {
		var block = blocks.lookup (source);
		if (source_instruction is CfgEnumScalarCapture) {
			var capture = (CfgEnumScalarCapture) source_instruction;
			var pointer = current (capture.source, source);
			var marker = new SsaEnumScalarCapture (capture.span, heap_owners.lookup (capture.source), pointer);
			block.instructions.add (new SsaHeapOwnerEvent (capture.span, marker.owner, SsaHeapOwnerAction.READ, pointer, marker));
			block.instructions.add (marker);
			evaluated_values.insert (capture.result, pointer);
			enum_scalar_captures.insert (capture, marker);
			return true;
		}
		if (source_instruction is CfgEnumScalarAbort) {
			var abort = (CfgEnumScalarAbort) source_instruction;
			block.instructions.add (new SsaEnumScalarAbort (abort.span, enum_scalar_captures.lookup (abort.capture)));
			return true;
		}
		if (source_instruction is CfgEnumExtractRecord) {
			var extraction = (CfgEnumExtractRecord) source_instruction;
			var results = declare_record_results (extraction.results);
			block.instructions.add (new SsaEnumReadRecord (extraction.span, enum_slots.lookup (extraction.source), extraction.field, extraction.binding, results));
			return true;
		}
		if (source_instruction is CfgEnumExtractScalar) {
			var extraction = (CfgEnumExtractScalar) source_instruction;
			var owner = heap_owners.lookup (extraction.destination);
			var read = new SsaEnumReadScalar (extraction.span, enum_slots.lookup (extraction.source), extraction.field, extraction.binding, owner, next_value++);
			block.instructions.add (read);
			block.instructions.add (new SsaHeapOwnerEvent (read.span, owner, SsaHeapOwnerAction.ACQUIRE, read.result, read));
			definitions.lookup (extraction.destination).stack.add (read.result);
			return true;
		}
		if (source_instruction is CfgEnumBufferAbort) {
			var aborted = (CfgEnumBufferAbort) source_instruction;
			var capture = enum_buffer_captures.lookup (aborted.capture);
			if (capture == null) {
				throw new SsaError.INVALID_CFG ("enum abort lost exact buffer reservation");
			}
			block.instructions.add (new SsaEnumBufferAbort (aborted.span, capture));
			return true;
		}
		if (source_instruction is CfgEnumEndInspection) {
			var end = (CfgEnumEndInspection) source_instruction;
			block.instructions.add (new SsaEnumEndInspection (end.span, enum_slots.lookup (end.source)));
			return true;
		}
		if (source_instruction is CfgEnumFinishArm) {
			var finish = (CfgEnumFinishArm) source_instruction;
			var fields = new GenericArray<EnumField> ();
			for (uint f = 0; f < finish.retained_count; f++) {
				fields.add (finish.field (f));
			}
			block.instructions.add (new SsaEnumFinishArm (finish.span, enum_slots.lookup (finish.source), finish.variant, fields));
			return true;
		}
		if (source_instruction is CfgEnumExtractBuffer) {
			var extraction = (CfgEnumExtractBuffer) source_instruction;
			var read = new SsaEnumReadBuffer (extraction.span, enum_slots.lookup (extraction.source), extraction.field, extraction.binding, cleanups.lookup (extraction.destination.cleanup).buffer_shape, next_value);
			next_value += 2;
			block.instructions.add (read);
			var write = write_buffer (extraction.span, buffer_place (extraction.destination, source), read.pair, source);
			write.initializes = true;
			return true;
		}
		if (source_instruction is CfgEnumCommit) {
			var commit = (CfgEnumCommit) source_instruction;
			block.instructions.add (new SsaEnumCommit (commit.span, enum_slots.lookup (commit.captured)));
			return true;
		}
		if (source_instruction is CfgEnumDrop) {
			var drop = (CfgEnumDrop) source_instruction;
			block.instructions.add (new SsaEnumDrop (drop.span, enum_slots.lookup (drop.source)));
			return true;
		}

		var capture = source_instruction as CfgEnumBufferCapture;
		if (capture != null) {
			var place = buffer_place (capture.source, source);
			var pair = read_buffer (capture.span, place, source);
			enum_buffers.insert (capture, pair);
			var reservation = new SsaEnumBufferCapture (capture.span, pair, place, capture.fresh_staged);
			enum_buffer_captures.insert (capture, reservation);
			block.instructions.add (reservation);
			return true;
		}

		var copy = source_instruction as CfgEnumCopy;
		if (copy != null) {
			block.instructions.add (new SsaEnumCopy (copy.span, enum_slots.lookup (copy.destination), enum_slots.lookup (copy.source), copy.initializes_destination, copy.mode));
			return true;
		}
		var acquisition = source_instruction as CfgEnumAcquire;
		if (acquisition != null) {
			block.instructions.add (new SsaEnumAcquire (acquisition.span, enum_slots.lookup (acquisition.destination), parameters.lookup (acquisition.parameter)));
			return true;
		}
		var extraction = source_instruction as CfgEnumExtractSum;
		if (extraction != null) {
			block.instructions.add (new SsaEnumExtractSum (extraction.span, enum_slots.lookup (extraction.source), extraction.field, enum_slots.lookup (extraction.destination), extraction.binding));
			return true;
		}
		var construction = source_instruction as CfgEnumConstruct;
		if (construction == null) {
			return false;
		}
		var fields = new GenericArray<SsaEnumFieldInput> ();
		foreach (var input in construction.fields) {
			var leaves = new GenericArray<SsaValue> ();
			if (input.field.owns_record) {
				leaves = lower_record_values (input.leaves, source);
			} else {
				foreach (var leaf in input.leaves) {
					leaves.add (lower_value (leaf, source));
				}
			}
			if (input.buffer != null && input.buffer.source != null) {
				disarm_buffer (input.buffer.source, source);
			}
			fields.add (new SsaEnumFieldInput (input.span, input.field, leaves, input.sum == null ? null : enum_slots.lookup (input.sum), input.buffer == null ? null : enum_buffers.lookup (input.buffer), input.scalar_owner == null ? null : enum_scalar_captures.lookup (input.scalar_owner), input.record_move == null ? null : record_boundary_moves.lookup (input.record_move)));
		}
		var constructed = new SsaEnumConstruct (construction.span, enum_slots.lookup (construction.destination), construction.variant, fields);
		foreach (var input in fields) {
			if (input.record_move != null) {
				input.record_move.consumer = constructed;
			}
		}
		foreach (var input in construction.fields) {
			if (input.scalar_owner == null) {
				continue;
			}
			var reserved = enum_scalar_captures.lookup (input.scalar_owner);
			var commit = new SsaEnumScalarCommit (input.span, reserved, input.field, constructed);
			block.instructions.add (commit);
			block.instructions.add (new SsaHeapOwnerEvent (input.span, reserved.owner, SsaHeapOwnerAction.MOVE, reserved.pointer, commit));
			definitions.lookup (input.scalar_owner.source).stack.add (new SsaNullPointerConstant (input.span, input.field.semantic_type));
		}
		block.instructions.add (constructed);
		return true;
	}

	private GenericArray<SsaValue> lower_invocation_arguments(GenericArray<CfgValue> actuals, CfgBlock source, out int[] first_leaves) throws SsaError {
		var arguments = new GenericArray<SsaValue> ();
		first_leaves = new int[actuals.length];
		for (int i = 0; i < actuals.length; i++) {
			first_leaves[i] = (int) arguments.length;
			var pending = actuals[i] as CfgPendingOwnedArgument;
			if (pending != null && pending.cleanup.is_buffer) {
				var pair = lower_buffer_value (pending, source);
				arguments.add (pair.base_value);
				arguments.add (pair.length_value);
			} else if (buffer_values.contains (actuals[i])) {
				var pair = lower_buffer_value (actuals[i], source);
				arguments.add (pair.base_value);
				arguments.add (pair.length_value);
			} else {
				arguments.add (lower_value (actuals[i], source));
			}
		}
		return arguments;
	}

	private void lower_record_arguments(Astra.Source.SourceSpan span, GenericArray<StructBoundaryGroup> groups, GenericArray<StructBoundaryGroup> output, GenericArray<CfgValue> original_arguments, int[] first_leaves, CfgBlock source) throws SsaError {
		foreach (var group in groups) {
			var borrowed = group as CfgStructBorrowArgument;
			var shape = physical_record_shape (group.shape);
			var result_loan = group as CfgStructBorrowResultArgument;
			if (result_loan != null) {
				var results = struct_results.lookup (result_loan.results);
				if (results == null) {
					throw new SsaError.INVALID_CFG ("record getter argument lost its exact complete observed result group");
				}
				output.add (new SsaStructBorrowResultArgument (group.source_ordinal, first_leaves[group.first_leaf], shape, results));
				continue;
			}
			if (borrowed == null) {
				output.add (new StructBoundaryGroup (group.source_ordinal, first_leaves[group.first_leaf], shape));
				continue;
			}
			var root = borrowed.source;
			var incoming = root.struct_parameter != null && root.struct_parameter.shape.mode == StructValueMode.BORROW_VALUE ? record_parameters.lookup (root.struct_parameter) : null;
			var loan = new SsaStructBorrowArgument (group.source_ordinal, first_leaves[group.first_leaf], shape, (SsaStruct) structs.lookup (root.semantic_type), root.ordinal, incoming);
			int physical = 0;
			var fields = boundary_fields (root, group.shape);
			for (int f = 0; f < fields.length; f++) {
				var field = fields[f];
				if (field.semantic_type is SliceType) {
					if (incoming == null) {
						var view = new SsaBufferBorrowInstruction (span, lower_buffer_value (original_arguments[group.first_leaf + f], source), next_value++);
						blocks.lookup (source).instructions.add (view);
						loan.buffers.add (view);
					}
					physical += 2;
					continue;
				}
				if (field.field.owned_cleanup != null && incoming == null) {
					loan.add_owner (record_owners.lookup (field), physical);
				}
				physical++;
			}
			output.add (loan);
		}
	}

	private void lower_call(CfgCallInstruction call, CfgBlock source) throws SsaError {
		var target = call.target == null ? null : callees.lookup (call.target);
		if (target == null) {
			throw new SsaError.INVALID_CFG ("internal SSA construction error: call target has no program-owned function mapping");
		}
		var receiver_value = call.receiver == null || (call is CfgResultConstructionInstruction) ? null : lower_value (call.receiver, source);
		int[] first_leaves;
		var arguments = lower_invocation_arguments (call.arguments, source, out first_leaves);
		var task_creation = call as CfgTaskCreate;
		var frame_context = task_creation == null || task_creation.allocation_context == null ? null : lower_value (task_creation.allocation_context, source);
		var frame_context_load = task_creation == null ? null : task_creation.allocation_context as CfgLoadValue;
		var frame_context_owner = frame_context_load == null ? null : heap_owners.lookup (frame_context_load.source as CfgLocalPlace);
		SsaCallInstruction instruction = (call is CfgTaskCreate) ? (SsaCallInstruction) new SsaTaskCreate (call.span, (TaskType) call.result.semantic_type, next_value++, target, arguments, frame_context, frame_context_owner, ((CfgTaskCreate) call).checked_admission) : (call is CfgBaseLifecycleCall) ? (SsaCallInstruction) new SsaBaseLifecycleCall (call.span, (SsaLifecycle) target, arguments, receiver_value) : (call is CfgLifecycleCallInstruction) ? (SsaCallInstruction) new SsaLifecycleCallInstruction (call.span, (SsaLifecycle) target, object_storage.lookup (((CfgLifecycleCallInstruction) call).storage), arguments, receiver_value) : new SsaCallInstruction (call.span, call.result == null || call.buffer_result != null ? null : call.result.semantic_type, call.result == null || call.buffer_result != null ? -1 : next_value++, target, arguments, receiver_value);
		if (call is CfgResultConstructionInstruction) {
			instruction = new SsaResultConstructionInstruction (call.span, (SsaConstructor) target, callees.lookup (function).result_storage, arguments);
		}
		instruction.bind_readonly_context (call.readonly_required);
		if (call is CfgTaskCreate) {
			foreach (var loan in ((CfgTaskCreate) call).loans) {
				int ordinal = first_leaves[loan.parameter_ordinal];
				((SsaTaskCreate) instruction).loans.add (new SsaSuspensionLoan (loan.identity, ordinal, storage.lookup (loan.storage), arguments[ordinal]));
			}
		}
		lower_record_arguments (call.span, call.struct_arguments, instruction.struct_arguments, call.arguments, first_leaves, source);
		if (call.buffer_result != null) {
			instruction.buffer_result = new SsaBufferPair.results (call.span, call.buffer_result.shape, next_value);
			next_value += 2;
			buffer_values.insert (call.result, instruction.buffer_result);
		}
		instruction.bind_enum_result (call.enum_result == null ? null : enum_slots.lookup (call.enum_result));
		foreach (var move in call.record_moves) {
			var marker = record_boundary_moves.lookup (move);
			if (marker == null) {
				throw new SsaError.INVALID_CFG ("record argument lost its complete ownership commit");
			}
			marker.consumer = instruction;
			instruction.record_moves.add (marker);
		}
		if (call.struct_result != null) {
			instruction.struct_result = declare_record_results (call.struct_result);
		}
		instruction.candidate_storage = call.candidate_storage == null ? null : object_storage.lookup (call.candidate_storage);
		instruction.result_storage = call.result_storage == null ? null : callees.lookup (function).result_storage;
		for (int i = 0; i < call.arguments.length; i++) {
			var transfer = call.arguments[i] as CfgPendingOwnedArgument;
			if (transfer == null) {
				continue;
			}
			int first = first_leaves[i];
			var reservation = argument_reservations.lookup (transfer);
			if (reservation != null) {
				reservation.consumer = instruction;
				instruction.reservations.add (reservation);
			}
			if (transfer.cleanup.is_buffer) {
				SsaBufferParameter? group = null;
				foreach (var candidate in target.buffer_parameters) {
					if (candidate.first_leaf == first) {
						group = candidate;
						break;
					}
				}
				if (group == null || !buffer_disarms.contains (transfer)) {
					throw new SsaError.INVALID_CFG ("owned buffer call requires its exact parameter group and complete source disarm");
				}
				instruction.buffer_arguments.add (new SsaBufferArgument (transfer.span, group, lower_buffer_value (transfer, source), buffer_disarms.lookup (transfer)));
				continue;
			}
			var after = transfer.source == null ? null : current (transfer.source, source) as SsaNullPointerConstant;
			if (transfer.source != null && after == null) {
				throw new SsaError.INVALID_CFG ("internal SSA construction error: committed owned argument source must be null immediately before invocation");
			}
			var owned = new SsaOwnedArgument (transfer.span, target.parameters[first], arguments[first], cleanups.lookup (transfer.cleanup), transfer.source == null ? -1 : transfer.source.ordinal, after, transfer.source == null || transfer.source.object_storage == null ? null : object_storage.lookup (transfer.source.object_storage));
			instruction.owned_arguments.add (owned);
			if (transfer.source != null && persistent_owner (transfer.cleanup)) {
				blocks.lookup (source).instructions.add (new SsaHeapOwnerEvent (transfer.span, heap_owners.lookup (transfer.source), SsaHeapOwnerAction.MOVE, owned.value, owned));
			}
		}
		var fallible = instruction as SsaLifecycleCallInstruction;
		if (fallible != null && fallible.constructs && fallible.storage.fallible) {
			foreach (var argument in fallible.owned_arguments) {
				if (argument.source_ordinal < 0) {
					continue;
				}
				var local = function.locals[argument.source_ordinal];
				var restore = new SsaFallibleInputRestore (call.span, fallible, argument, heap_owners.lookup (local), next_value++);
				fallible.input_restores.add (restore);
				blocks.lookup (source).instructions.add (restore);
				blocks.lookup (source).instructions.add (new SsaHeapOwnerEvent (call.span, restore.owner, SsaHeapOwnerAction.ACQUIRE, restore.result, restore));
				definitions.lookup (local).stack.add (restore.result);
			}
			foreach (var argument in fallible.buffer_arguments) {
				var restore = new SsaFallibleBufferRestore (call.span, fallible, argument, next_value);
				next_value += 2;
				fallible.buffer_restores.add (restore);
				blocks.lookup (source).instructions.add (restore);
				write_buffer (call.span, argument.disarm.place, restore.pair, source);
			}
			foreach (var original in call.record_moves) {
				var moved = record_boundary_moves.lookup (original);
				var results = record_restore_results (call.span, moved);
				var restored = new SsaFallibleRecordRestore (call.span, fallible, moved, results);
				fallible.record_restores.add (restored);
				acquire_restored_record (call.span, restored, original, source);
			}
		}
		if (!(call is CfgTaskCreate) && call.result != null && target.owned_cleanup != null) {
			native_producers.insert (call.result, instruction);
		}
		if (call.exception_result != null) {
			instruction.exception_result = new SsaInstructionResult (call.span, call.exception_result.semantic_type, next_value++);
			evaluated_values.insert (call.exception_result, instruction.exception_result);
			exception_calls.insert (call, instruction);
		}
		foreach (var group in instruction.struct_arguments) {
			var loan = group as SsaStructBorrowArgument;
			if (loan == null) {
				continue;
			}
			for (int o = 0; o < loan.owners.length; o++) {
				blocks.lookup (source).instructions.add (new SsaHeapOwnerEvent (call.span, loan.owners[o], SsaHeapOwnerAction.READ, instruction.arguments[loan.first_leaf + loan.owner_leaf (o)]));
			}
		}
		if (instruction is SsaTaskCreate && frame_context_owner != null) {
			blocks.lookup (source).instructions.add (new SsaHeapOwnerEvent (call.span, frame_context_owner, SsaHeapOwnerAction.READ, frame_context, instruction));
		}
		blocks.lookup (source).instructions.add (instruction);
		var checked_frame = instruction as SsaTaskCreate;
		if (checked_frame != null && checked_frame.checked_admission) {
			foreach (var argument in checked_frame.owned_arguments) {
				if (argument.source_ordinal < 0) {
					continue;
				}
				var local = function.locals[argument.source_ordinal];
				var restore = new SsaFrameInputRestore (call.span, checked_frame, argument, heap_owners.lookup (local), next_value++);
				checked_frame.input_restores.add (restore);
				blocks.lookup (source).instructions.add (restore);
				blocks.lookup (source).instructions.add (new SsaHeapOwnerEvent (call.span, restore.owner, SsaHeapOwnerAction.ACQUIRE, restore.result, restore));
				definitions.lookup (local).stack.add (restore.result);
			}
			foreach (var argument in checked_frame.buffer_arguments) {
				var restore = new SsaFrameBufferRestore (call.span, checked_frame, argument, next_value);
				next_value += 2;
				checked_frame.buffer_restores.add (restore);
				blocks.lookup (source).instructions.add (restore);
				write_buffer (call.span, argument.disarm.place, restore.pair, source);
			}
			foreach (var original in call.record_moves) {
				var moved = record_boundary_moves.lookup (original);
				var results = record_restore_results (call.span, moved);
				var restored = new SsaFrameRecordRestore (call.span, checked_frame, moved, results);
				checked_frame.record_restores.add (restored);
				acquire_restored_record (call.span, restored, original, source);
			}
		}
		if (failure_calls.contains (call)) {
			failure_calls.lookup (call).action = instruction;
		}
		if (call.result != null && call.buffer_result == null) {
			call_results.insert (call.result, instruction.result);
		}
	}

	private SsaStructCallResults record_restore_results(Astra.Source.SourceSpan span, SsaStructBoundaryMove moved) {
		var leaves = new GenericArray<SsaInstructionResult> ();
		foreach (var leaf in moved.shape.leaves) {
			leaves.add (new SsaInstructionResult (span, leaf.semantic_type, next_value++));
		}
		var results = new SsaStructCallResults (span, moved.shape, leaves);
		for (int l = 0; l < moved.shape.leaves.length; l++) {
			var component = moved.shape.leaves[l] as StructBufferLeafPath;
			if (component != null && component.component == 0) {
				results.buffers.add (new SsaBufferPair (span, component.buffer_shape, leaves[l], leaves[l + 1]));
			}
		}
		return results;
	}
	private void acquire_restored_record(Astra.Source.SourceSpan span, SsaRecordAdmissionRestore restored, CfgStructBoundaryMove original, CfgBlock source) throws SsaError {
		var moved = restored.original;
		var results = restored.results;
		var values = new GenericArray<SsaValue> ();
		foreach (var leaf in results.leaves) {
			values.add (leaf);
		}
		blocks.lookup (source).instructions.add (restored);
		blocks.lookup (source).instructions.add (new SsaStructResultConsume (span, results, StructResultUseKind.INITIALIZE));
		var acquired = new SsaStructBoundaryAcquire (span, moved.record_type, moved.source_ordinal, moved.shape, values, moved.owners, null, results);
		acquired.admission_restore = restored;
		restored.acquisition = acquired;
		blocks.lookup (source).instructions.add (acquired);
		var fields = boundary_fields (original.source, original.shape);
		int physical = 0, buffer = 0;
		foreach (var field in fields) {
			if (field.semantic_type is SliceType) {
				acquired.add_buffer (moved.buffers[buffer], results.buffers[buffer]);
				buffer++;
				physical += 2;
				continue;
			}
			if (field.field.owned_cleanup != null) {
				blocks.lookup (source).instructions.add (new SsaHeapOwnerEvent (span, record_owners.lookup (field), SsaHeapOwnerAction.ACQUIRE, values[physical], acquired));
			}
			definitions.lookup (field).stack.add (values[physical++]);
		}
		for (int b = 0; b < acquired.buffers.length; b++) {
			var place = new SsaBufferPlace (span, acquired.buffers[b].cleanup, acquired.buffers[b]);
			var write = write_buffer (span, place, acquired.buffer_pairs[b], source);
			write.initializes = true;
			write.record_boundary = acquired;
		}
	}
	private void lower_c_call(CfgCCallInstruction call, CfgBlock source) throws SsaError {
		var target = call.target == null ? null : c_callees.lookup (call.target);
		if (target == null) {
			throw new SsaError.INVALID_CFG ("internal SSA construction error: call target has no program-owned function mapping");
		}
		var arguments = new GenericArray<SsaValue> ();
		for (int i = 0; i < call.arguments.length; i++) {
			arguments.add (lower_value (call.arguments[i], source));
		}
		var instruction = new SsaCCallInstruction (call.span, call.result == null ? null : call.result.semantic_type, call.result == null ? -1 : next_value++, target, arguments);
		foreach (var group in call.struct_arguments) {
			instruction.struct_arguments.add (new StructBoundaryGroup (group.source_ordinal, group.first_leaf, group.shape));
		}
		if (call.struct_result != null) {
			var leaves = new GenericArray<SsaInstructionResult> ();
			foreach (var leaf in call.struct_result.leaves) {
				var result = new SsaInstructionResult (leaf.span, leaf.semantic_type, next_value++);
				leaves.add (result);
				call_results.insert (leaf, result);
			}
			instruction.struct_result = new SsaStructCallResults (call.span, call.struct_result.shape, leaves);
			struct_results.insert (call.struct_result, instruction.struct_result);
		}
		blocks.lookup (source).instructions.add (instruction);
		if (failure_calls.contains (call)) {
			failure_calls.lookup (call).action = instruction;
		}
		if (call.result != null) {
			call_results.insert (call.result, instruction.result);
		}
	}

	private SsaMemoryPlace lower_array_field(CfgPlace place, CfgArrayElementPlace root, SsaArrayElementPlace mapped) throws SsaError {
		if (place == root) {
			return mapped;
		}
		var field = place as CfgFieldPlace;
		if (field == null) {
			throw new SsaError.INVALID_CFG ("record array initialization lost its exact indexed field root");
		}
		return new SsaFieldPlace.projection (place.span, lower_array_field (field.aggregate, root, mapped), fields.lookup (field.field));
	}

	private SsaMemoryPlace lower_place(CfgPlace place, CfgBlock source) throws SsaError {
		if (place.semantic_type is StructType && (place is CfgArrayElementPlace || place is CfgSliceElementPlace)) {
			var prior = indexed_roots.lookup (place);
			if (prior != null) {
				return prior;
			}
			SsaMemoryPlace result;
			if (place is CfgSliceElementPlace) {
				var slice = (CfgSliceElementPlace) place;
				result = new SsaSliceElementPlace (place.span, lower_value (slice.slice, source), slice.slice_type, lower_value (slice.index, source), slice.provenance);
			} else {
				var array = (CfgArrayElementPlace) place;
				result = new SsaArrayElementPlace (place.span, storage.lookup (array.storage), array.array_type, lower_value (array.index, source), array.provenance);
			}
			indexed_roots.insert (place, result);
			return result;
		}
		var object_field = place as CfgObjectFieldPlace;
		if (object_field != null) {
			return new SsaObjectFieldPlace (place.span, object_storage.lookup (object_field.storage), fields.lookup (object_field.field));
		}
		var slice = place as CfgSliceElementPlace;
		if (slice != null) {
			return new SsaSliceElementPlace (place.span, lower_value (slice.slice, source), slice.slice_type, lower_value (slice.index, source), slice.provenance);
		}
		var array = place as CfgArrayElementPlace;
		if (array != null) {
			return new SsaArrayElementPlace (place.span, storage.lookup (array.storage), array.array_type, lower_value (array.index, source), array.provenance);
		}
		var local = place as CfgLocalPlace;
		if (local != null && storage.contains (local)) {
			return new SsaLocalMemoryPlace (place.span, storage.lookup (local));
		}
		var dereference = place as CfgDereferencePlace;
		if (dereference != null) {
			return new SsaDereferencePlace (place.span, lower_value (dereference.pointer, source), place.semantic_type, dereference.provenance);
		}
		var direct = place as CfgFieldPlace;
		if (direct != null && memory_fields.contains (direct)) {
			return memory_fields.lookup (direct);
		}
		if (direct != null) {
			return new SsaFieldPlace.projection (place.span, lower_place (direct.aggregate, source), fields.lookup (direct.field));
		}
		var indirect = place as CfgIndirectFieldPlace;
		if (indirect != null) {
			return new SsaIndirectFieldPlace (place.span, lower_value (indirect.pointer, source), fields.lookup (indirect.field));
		}
		throw new SsaError.INVALID_CFG ("internal SSA construction error: non-promotable place must be an exact addressable field");
	}

	private void retain_callable_arguments(SsaInstruction consumer, SsaCallableInvocation invocation, GenericArray<CfgValue> actuals, CallableSignature signature, CfgBlock source, GenericArray<CfgStructBoundaryMove> record_moves, int[] first_leaves) throws SsaError {
		foreach (var move in record_moves) {
			var marker = record_boundary_moves.lookup (move);
			if (marker == null) {
				throw new SsaError.INVALID_CFG ("indirect record argument lost its complete ownership commit");
			}
			marker.consumer = consumer;
			invocation.record_moves.add (marker);
		}
		var contracts = signature.physical_contracts ();
		for (int p = 0; p < actuals.length; p++) {
			if (contracts[p] != PointerParameterContract.OWNED_TRANSFER) {
				continue;
			}
			var transfer = actuals[p] as CfgPendingOwnedArgument;
			if (transfer == null || transfer.cleanup.is_buffer) {
				throw new SsaError.INVALID_CFG ("indirect owned argument requires its complete scalar capture contract");
			}
			var after = transfer.source == null ? null : current (transfer.source, source) as SsaNullPointerConstant;
			if (transfer.source != null && after == null) {
				throw new SsaError.INVALID_CFG ("indirect owned argument requires its exact source disarm before invocation");
			}
			var owned = new SsaCallableOwnedArgument (transfer.span, first_leaves[p], invocation.arguments[first_leaves[p]], cleanups.lookup (transfer.cleanup), transfer.source == null ? -1 : transfer.source.ordinal, after,
				transfer.source == null || transfer.source.object_storage == null ? null : object_storage.lookup (transfer.source.object_storage));
			invocation.owned_arguments.add (owned);
			var reservation = argument_reservations.lookup (transfer);
			if (reservation != null) {
				reservation.consumer = consumer;
				invocation.reservations.add (reservation);
			}
			if (transfer.source != null && persistent_owner (transfer.cleanup)) {
				blocks.lookup (source).instructions.add (new SsaHeapOwnerEvent (transfer.span, heap_owners.lookup (transfer.source), SsaHeapOwnerAction.MOVE, owned.value, owned));
			}
		}
		var code = consumer as SsaFunctionValueCall;
		var groups = code == null ? ((SsaClosureCall) consumer).struct_arguments : code.struct_arguments;
		foreach (var group in groups) {
			var loan = group as SsaStructBorrowArgument;
			if (loan == null) {
				continue;
			}
			for (int o = 0; o < loan.owners.length; o++) {
				blocks.lookup (source).instructions.add (new SsaHeapOwnerEvent (consumer.span, loan.owners[o], SsaHeapOwnerAction.READ, invocation.arguments[loan.first_leaf + loan.owner_leaf (o)]));
			}
		}
		for (int p = 0; p < actuals.length; p++) {
			if (contracts[p] != PointerParameterContract.BORROWED_NOESCAPE) {
				continue;
			}
			if (CallableRecordGroups.borrowed_record_leaf ((signature is FunctionValueType) ? ((FunctionValueType) signature).record_parameters : ((ClosureHandleType) signature).record_parameters, p)) {
				continue;
			}
			var borrow = actuals[p] as CfgOwnedBorrowValue;
			var owner = borrow == null ? null : heap_owners.lookup (borrow.source);
			if (borrow != null && owner == null) {
				throw new SsaError.INVALID_CFG ("callable owner loan lost exact source ownership authority");
			}
			invocation.borrowed_arguments.add (new SsaCallableBorrowArgument (first_leaves[p], invocation.arguments[first_leaves[p]], owner));
			if (owner != null) {
				blocks.lookup (source).instructions.add (new SsaHeapOwnerEvent (consumer.span, owner, SsaHeapOwnerAction.READ, invocation.arguments[first_leaves[p]], consumer));
			}
		}


	}

	private SsaInstruction lower_callable_invocation(CfgValue value, CfgBlock source) throws SsaError {
		if (value is CfgClosureCall) {
			var call = (CfgClosureCall) value;
			var callee = lower_value (call.callee, source);
			int[] first_leaves;
			var arguments = lower_invocation_arguments (call.arguments, source, out first_leaves);
			var load = call.callee as CfgLoadValue;
			var owner = load == null ? null : heap_owners.lookup (load.source as CfgLocalPlace);
			var instruction = new SsaClosureCall (value.span, (ClosureHandleType) call.callee.semantic_type, callee, arguments, next_value++, owner, null, call.owned_cleanup == null ? null : cleanups.lookup (call.owned_cleanup));
			lower_record_arguments (call.span, call.struct_arguments, instruction.struct_arguments, call.arguments, first_leaves, source);
			retain_callable_arguments (instruction, instruction, call.arguments, (ClosureHandleType) call.callee.semantic_type, source, call.record_moves, first_leaves);
			if (owner != null) {
				blocks.lookup (source).instructions.add (new SsaHeapOwnerEvent (value.span, owner, SsaHeapOwnerAction.READ, callee, instruction));
			}
			blocks.lookup (source).instructions.add (instruction);
			return instruction;
		}
		if (value is CfgFunctionValueCall) {
			var call = (CfgFunctionValueCall) value;
			var callee = lower_value (call.callee, source);
			int[] first_leaves;
			var arguments = lower_invocation_arguments (call.arguments, source, out first_leaves);
			var instruction = new SsaFunctionValueCall (value.span, (FunctionValueType) call.callee.semantic_type, callee, arguments, next_value++, call.owned_cleanup == null ? null : cleanups.lookup (call.owned_cleanup));
			lower_record_arguments (call.span, call.struct_arguments, instruction.struct_arguments, call.arguments, first_leaves, source);
			retain_callable_arguments (instruction, instruction, call.arguments, (FunctionValueType) call.callee.semantic_type, source, call.record_moves, first_leaves);
			blocks.lookup (source).instructions.add (instruction);
			return instruction;
		}
		throw new SsaError.INVALID_CFG ("record invocation requires an exact Fn or Closure call");
	}

	private SsaValue lower_value(CfgValue value, CfgBlock source) throws SsaError {
		if (value is CfgScopedAllocator) {
			var scoped = (CfgScopedAllocator) value;
			SsaHeapOwner? owner = null;
			foreach (var local in function.locals) {
				if (local.ordinal == scoped.loan.context_ordinal) {
					owner = heap_owners.lookup (local);
				}
			}
			var kind = lower_value (scoped.kind, source);
			var slots = lower_value (scoped.slots, source);
			var place = buffer_place (scoped.backing, source);
			var pair = read_buffer (value.span, place, source);
			var instruction = new SsaScopedAllocator (value.span, (HandleType) value.semantic_type, scoped.loan, place.storage, pair, owner, kind, slots, next_value++);
			blocks.lookup (source).instructions.add (instruction);
			return instruction.result;
		}
		if (value is CfgLazyObserve) {
			var observe = new SsaLazyObserve (value.span, properties.lookup (((CfgLazyObserve) value).property_member), next_value++);
			blocks.lookup (source).instructions.add (observe);
			return observe.result;
		}
		if (value is CfgRetainedOperation) {
			var operation = (CfgRetainedOperation) value;
			var callee = lower_value (operation.callee, source);
			var arguments = new GenericArray<SsaValue> ();
			foreach (var argument in operation.arguments) {
				arguments.add (lower_value (argument, source));
			}
			var load = operation.callee as CfgLoadValue;
			var owner = load == null ? null : heap_owners.lookup (load.source as CfgLocalPlace);
			var instruction = new SsaRetainedOperation (value.span, operation.action, callee, arguments, next_value++, owner, value.semantic_type);
			if (owner != null) {
				blocks.lookup (source).instructions.add (new SsaHeapOwnerEvent (value.span, owner, SsaHeapOwnerAction.READ, callee, instruction));
			}
			blocks.lookup (source).instructions.add (instruction);
			return instruction.result;
		}
		if (value is CfgClosureBind) {
			var closure = (CfgClosureBind) value;
			var instruction = new SsaClosureBind (value.span, (ClosureHandleType) value.semantic_type, lower_value (closure.environment, source), callees.lookup (closure.target), cleanups.lookup (closure.cleanup), next_value++, closure.actor_binding);
			blocks.lookup (source).instructions.add (instruction);
			return instruction.result;
		}
		if (value is CfgClosureCall || value is CfgFunctionValueCall) {
			return lower_callable_invocation (value, source).result;
		}
		if (value is CfgSharedOperation) {
			var operation = (CfgSharedOperation) value;
			var operand = lower_value (operation.operand, source);
			var load = operation.operand as CfgLoadValue;
			var owner = operation.action == SharedAction.ACQUIRE || load == null ? null : heap_owners.lookup (load.source as CfgLocalPlace);
			var lowered = new SsaSharedOperation (value.span, value.semantic_type, operation.action, operand, operation.cleanup == null ? null : cleanups.lookup (operation.cleanup), operation.borrower == null ? null : slots_parameters.lookup (operation.borrower), next_value++, owner);
			if (owner != null) {
				blocks.lookup (source).instructions.add (new SsaHeapOwnerEvent (value.span, owner, SsaHeapOwnerAction.READ, operand, lowered));
			}
			blocks.lookup (source).instructions.add (lowered);
			return lowered.result;
		}
		if (value is CfgCallbackParameterView) {
			var view = (CfgCallbackParameterView) value;
			return new SsaCallbackView (value.span, (CallbackType) value.semantic_type, parameters.lookup (view.source));
		}
		if (value is CfgFunctionAddress) {
			var address = (CfgFunctionAddress) value;
			return new SsaFunctionAddress (value.span, (FunctionValueType) value.semantic_type, callees.lookup (address.target));
		}

		if (value is CfgExceptionMatch) {
			var match = (CfgExceptionMatch) value;
			var instruction = new SsaExceptionMatch (value.span, value.semantic_type, lower_value (match.exception, source), match.match_type, next_value++);
			blocks.lookup (source).instructions.add (instruction);
			handler_selections.insert (match, instruction);
			return instruction.result;
		}
		if (value is CfgCatchBorrow) {
			var caught = (CfgCatchBorrow) value;
			var instruction = new SsaCatchBorrow (value.span, lower_value (caught.exception, source), (ClassType) value.semantic_type, next_value++);
			blocks.lookup (source).instructions.add (instruction);
			handler_borrows.insert (caught, instruction);
			return instruction.result;
		}
		if (value is CfgClassUpcast) {
			var cast = (CfgClassUpcast) value;
			var instruction = new SsaClassUpcast (value.span, lower_value (cast.reference, source), (SsaClass) structs.lookup (cast.source_class.semantic_type), (SsaClass) structs.lookup (cast.target_class.semantic_type), value.semantic_type, next_value++);
			if (cast.reference is CfgOwnedBorrowValue) {
				instruction.borrowed_parameter = parameters.lookup (((CfgOwnedBorrowValue) cast.reference).parameter);
			}
			blocks.lookup (source).instructions.add (instruction);
			return instruction.result;
		}
		if (value is CfgEnumArgument) {
			return new SsaEnumArgument (value.span, enum_slots.lookup (((CfgEnumArgument) value).source));
		}
		if (value is CfgEnumTag) {
			var tag = (CfgEnumTag) value;
			var instruction = new SsaEnumTagInstruction (value.span, value.semantic_type, enum_slots.lookup (tag.source), next_value++);
			blocks.lookup (source).instructions.add (instruction);
			return instruction.result;
		}
		if (value is CfgEnumPayloadValue) {
			var payload = (CfgEnumPayloadValue) value;
			var instruction = new SsaEnumRead (value.span, enum_slots.lookup (payload.source), payload.field, next_value++, payload.binding, payload.record_path);
			callees.lookup (function).enum_projections.add (new SsaEnumProjectionContract (instruction));
			blocks.lookup (source).instructions.add (instruction);
			return instruction.result;
		}
		if (value is CfgResultObjectStorage) {
			return callees.lookup (function).result_storage;
		}
		var storage_receiver = value as CfgStorageReceiverValue;
		if (storage_receiver != null) {
			var captured = storage_receivers.lookup (storage_receiver);
			if (captured != null) {
				return captured;
			}
			var context_value = storage_receiver.allocation_context == null ? null : lower_value (storage_receiver.allocation_context, source);
			var context_load = storage_receiver.allocation_context as CfgLoadValue;
			var context_owner = context_load == null ? null : heap_owners.lookup (context_load.source as CfgLocalPlace);
			var instruction = new SsaStorageReceiverInstruction (value.span, object_storage.lookup (storage_receiver.storage), (ReceiverType) value.semantic_type, next_value++, context_value, context_owner);
			if (context_owner != null) {
				blocks.lookup (source).instructions.add (new SsaHeapOwnerEvent (value.span, context_owner, SsaHeapOwnerAction.READ, context_value, instruction));
			}
			blocks.lookup (source).instructions.add (instruction);
			storage_receivers.insert (storage_receiver, instruction.result);
			return instruction.result;
		}
		var object_reference = value as CfgObjectReferenceValue;
		if (object_reference != null) {
			var instruction = new SsaObjectReferenceInstruction (value.span, object_storage.lookup (object_reference.storage), next_value++);
			blocks.lookup (source).instructions.add (instruction);
			return instruction.result;
		}
		var object_validation = value as CfgObjectValidateValue;
		if (object_validation != null) {
			var reference = lower_value (object_validation.reference, source);
			var instruction = new SsaObjectValidateInstruction (value.span, reference, value.semantic_type, next_value++);
			blocks.lookup (source).instructions.add (instruction);
			return instruction.result;
		}
		if (value is CfgReceiverValue) {
			return receiver;
		}
		var slice = value as CfgSliceFromArrayValue;
		if (slice != null) {
			var start = slice.start == null ? null : lower_value (slice.start, source);
			var count = slice.count == null ? null : lower_value (slice.count, source);
			var instruction = new SsaSliceConstructInstruction (value.span, (SliceType) value.semantic_type, storage.lookup (slice.storage), slice.array_type, start, count, slice.provenance, next_value++);
			blocks.lookup (source).instructions.add (instruction);
			return instruction.result;
		}
		if (value is CfgSlotsValue) {
			var v = (CfgSlotsValue) value;
			var instruction = new SsaSlotsValueInstruction (v.span, v.semantic_type, next_value++, (SsaIndirectFieldPlace) lower_place (v.store, source), v.action, v.operand == null ? null : lower_value (v.operand, source));
			blocks.lookup (source).instructions.add (instruction);
			return instruction.result;
		}
		var length = value as CfgSliceLengthValue;
		if (length != null) {
			var view = lower_value (length.slice, source);
			var instruction = new SsaSliceLengthInstruction (value.span, value.semantic_type, view, next_value++);
			blocks.lookup (source).instructions.add (instruction);
			return instruction.result;
		}
		var borrow = value as CfgOwnedBorrowValue;
		if (borrow != null) {
			var result = borrowed_values.lookup (borrow);
			if (result == null) {
				throw new SsaError.INVALID_CFG ("internal SSA construction error: borrow has no preceding pointer value");
			}
			return result;
		}
		var evaluated = value as CfgEvaluatedValue;
		if (evaluated != null) {
			var result = evaluated_values.lookup (evaluated);
			if (result == null) {
				throw new SsaError.INVALID_CFG ("internal SSA construction error: evaluated value has no preceding definition mapping");
			}
			return result;
		}
		if (value is CfgRecordBufferView) {
			var view = (CfgRecordBufferView) value;
			var group = struct_results.lookup (view.group);
			var pair = buffer_values.lookup (view.source);
			if (group == null || pair == null) {
				throw new SsaError.INVALID_CFG ("record buffer view lost its exact complete borrowed result pair");
			}
			var instruction = new SsaBufferBorrowInstruction.for_record (value.span, pair, group, next_value++);
			blocks.lookup (source).instructions.add (instruction);
			return instruction.result;
		}
		if (value is CfgRecordParameterBufferView) {
			var view = (CfgRecordParameterBufferView) value;
			var group = record_parameters.lookup (view.parameter);
			var pair = lower_buffer_value (view.source, source);
			if (group == null || group.shape.mode != StructValueMode.BORROW_VALUE) {
				throw new SsaError.INVALID_CFG ("record parameter buffer view lost its exact borrowed entry group");
			}
			var instruction = new SsaBufferBorrowInstruction.for_parameter (value.span, pair, group, view.field.storage_path (), next_value++);
			blocks.lookup (source).instructions.add (instruction);
			return instruction.result;
		}
		var call_result = value as CfgCallResultValue;
		if (call_result != null) {
			var result = call_results.lookup (call_result);
			if (result == null) {
				throw new SsaError.INVALID_CFG ("internal SSA construction error: call result has no preceding definition mapping");
			}
			return result;
		}
		var load = value as CfgLoadValue;
		if (load != null) {
			if (load.source.semantic_type is SliceType && load.source is CfgIndirectFieldPlace) {
				var pair = read_buffer (load.span, buffer_place (load.source, source), source);
				var field_view = new SsaBufferBorrowInstruction (load.span, pair, next_value++);
				blocks.lookup (source).instructions.add (field_view);
				return field_view.result;
			}
			if (load.source.is_promotable ()) {
				var result = current (load.source, source);
				var loan = text_loans.lookup (load.source as CfgLocalPlace);
				if (loan != null) {
					var use = new SsaTextLoanUse (load.span, loan, result);
					blocks.lookup (source).instructions.add (use);
					callees.lookup (function).retain_text_use (use);
				}
				return result;
			}
			var instruction = new SsaLoadInstruction (value.span, lower_place (load.source, source), next_value++, load.volatile_access == null ? null : load.volatile_access.copy ());
			blocks.lookup (source).instructions.add (instruction);
			if (instruction.volatile_access != null) {
				callees.lookup (function).retain_volatile_effect (instruction, blocks.lookup (source));
			}
			return instruction.result;
		}
		var address = value as CfgAddressOfValue;
		if (address != null) {
			var instruction = address.receiver_place == null ? new SsaAddressOfInstruction (value.span, value.semantic_type, next_value++, storage.lookup (address.target), address.provenance) : new SsaAddressOfInstruction.projection (value.span, (ReceiverType) value.semantic_type, next_value++, lower_place (address.receiver_place, source));
			blocks.lookup (source).instructions.add (instruction);
			return instruction.result;
		}
		var parameter = value as CfgParameterValue;
		if (parameter != null) {
			return parameters.lookup (parameter.parameter);
		}
		if (value is CfgUtf8FactoryValue) {
			var operation = (CfgUtf8FactoryValue) value;
			var instruction = new SsaUtf8FactoryInstruction (value.span, value.semantic_type, parameters.lookup (operation.input), operation.validates, next_value++);
			blocks.lookup (source).instructions.add (instruction);
			return instruction.result;
		}
		if (value is CfgTextValue) {
			return new SsaTextConstant (value.span, value.semantic_type, ((CfgTextValue) value).payload);
		}
		if (value is CfgTextLengthValue) {
			var receiver = lower_value (((CfgTextLengthValue) value).receiver, source);
			var instruction = new SsaTextLengthInstruction (value.span, value.semantic_type, receiver, next_value++);
			blocks.lookup (source).instructions.add (instruction);
			return instruction.result;
		}
		if (value is CfgFloatValue) {
			return new SsaFloatConstant (value.span, value.semantic_type, ((CfgFloatValue) value).value);
		}
		if (value is CfgIntegerValue) {
			return new SsaIntegerConstant.typed (value.span, value.semantic_type, ((CfgIntegerValue) value).value);
		}
		if (value is CfgNullPointerValue) {
			return new SsaNullPointerConstant (value.span, value.semantic_type);
		}
		var boolean = value as CfgBooleanValue;
		if (boolean != null) {
			return new SsaBooleanConstant (boolean.span, boolean.semantic_type, boolean.literal);
		}
		var dot = value as CfgVectorDotValue;
		if (dot != null) {
			var accumulator = dot.accumulator == null ? null : lower_value (dot.accumulator, source);
			var first = lower_value (dot.first, source);
			var second = lower_value (dot.second, source);
			var instruction = new SsaVectorDotInstruction (value.span, dot.dot_kind, dot.source_type, dot.destination_type, next_value++, accumulator, first, second);
			blocks.lookup (source).instructions.add (instruction);
			return instruction.result;
		}
		var dsp = value as CfgDspValue;
		if (dsp != null) {
			var first = lower_value (dsp.first, source);
			var second = dsp.second == null ? null : lower_value (dsp.second, source);
			var instruction = new SsaDspInstruction (value.span, dsp.primitive_kind, dsp.source_type, dsp.destination_type, next_value++, first, second, dsp.destination_element);
			blocks.lookup (source).instructions.add (instruction);
			return instruction.result;
		}
		var shift = value as CfgIntegerShiftValue;
		if (shift != null) {
			var operand = lower_value (shift.operand, source);
			var count = lower_value (shift.count, source);
			var instruction = new SsaIntegerShiftInstruction (value.span, value.semantic_type, next_value++, shift.shift_kind, operand, count);
			blocks.lookup (source).instructions.add (instruction);
			return instruction.result;
		}
		var numeric_conversion = value as CfgNumericConversionValue;
		if (numeric_conversion != null) {
			var operand = lower_value (numeric_conversion.operand, source);
			var instruction = new SsaNumericConversionInstruction (value.span, numeric_conversion.source_type, numeric_conversion.destination_type, numeric_conversion.conversion_kind, next_value++, operand, numeric_conversion.policy);
			blocks.lookup (source).instructions.add (instruction);
			return instruction.result;
		}
		var floating_conversion = value as CfgFloatConversionValue;
		if (floating_conversion != null) {
			var operand = lower_value (floating_conversion.operand, source);
			var instruction = new SsaFloatConversionInstruction (value.span, floating_conversion.source_type, floating_conversion.destination_type, floating_conversion.conversion_kind, next_value++, operand);
			blocks.lookup (source).instructions.add (instruction);
			return instruction.result;
		}
		var conversion = value as CfgIntegerConversionValue;
		if (conversion != null) {
			var operand = lower_value (conversion.operand, source);
			var instruction = new SsaIntegerConversionInstruction (value.span, conversion.source_type, conversion.destination_type, next_value++, operand);
			blocks.lookup (source).instructions.add (instruction);
			return instruction.result;
		}
		var splat = value as CfgVectorSplatValue;
		if (splat != null) {
			var operand = lower_value (splat.operand, source);
			var instruction = new SsaVectorSplatInstruction (value.span, value.semantic_type, next_value++, operand, splat.lane_count, splat.lane_count_span);
			blocks.lookup (source).instructions.add (instruction);
			return instruction.result;
		}
		var extract = value as CfgVectorExtractValue;
		if (extract != null) {
			var vector = lower_value (extract.vector, source);
			var instruction = new SsaVectorExtractInstruction (value.span, value.semantic_type, next_value++, vector, extract.index);
			blocks.lookup (source).instructions.add (instruction);
			return instruction.result;
		}
		var insert = value as CfgVectorInsertValue;
		if (insert != null) {
			var vector = lower_value (insert.vector, source);
			var replacement = lower_value (insert.replacement, source);
			var instruction = new SsaVectorInsertInstruction (value.span, value.semantic_type, next_value++, vector, insert.index, replacement);
			blocks.lookup (source).instructions.add (instruction);
			return instruction.result;
		}
		var shuffle = value as CfgVectorShuffleValue;
		if (shuffle != null) {
			var vector = lower_value (shuffle.vector, source);
			var instruction = new SsaVectorShuffleInstruction (value.span, value.semantic_type, next_value++, vector, shuffle.selectors);
			blocks.lookup (source).instructions.add (instruction);
			return instruction.result;
		}
		if (value is CfgVectorMemoryValue) {
			var memory = (CfgVectorMemoryValue) value;
			var view = lower_value (memory.view, source);
			var offset = lower_value (memory.offset, source);
			var stored = memory.stored == null ? null : lower_value (memory.stored, source);
			var instruction = new SsaVectorMemoryInstruction (value.span, memory.contract, view, offset, stored, next_value++);
			blocks.lookup (source).instructions.add (instruction);
			callees.lookup (function).retain_vector_memory (instruction, blocks.lookup (source));
			return instruction.result;
		}
		var select = value as CfgVectorSelectValue;
		if (select != null) {
			var mask = lower_value (select.mask, source);
			var true_value = lower_value (select.true_value, source);
			var false_value = lower_value (select.false_value, source);
			var instruction = new SsaVectorSelectInstruction (value.span, value.semantic_type, next_value++, mask, true_value, false_value);
			blocks.lookup (source).instructions.add (instruction);
			return instruction.result;
		}
		var vector = value as CfgVectorConstructValue;
		if (vector != null) {
			var lanes = new GenericArray<SsaValue> ();
			foreach (var lane in vector.lanes) {
				lanes.add (lower_value (lane, source));
			}
			var construct = new SsaVectorConstructInstruction (value.span, value.semantic_type, next_value++, lanes);
			blocks.lookup (source).instructions.add (construct);
			return construct.result;
		}
		var reduction = value as CfgVectorReductionValue;
		if (reduction != null) {
			var operand = lower_value (reduction.operand, source);
			var reduce = new SsaVectorReductionInstruction (value.span, value.semantic_type, next_value++, reduction.operator_kind, operand);
			blocks.lookup (source).instructions.add (reduce);
			return reduce.result;
		}
		var prefix = value as CfgPrefixValue;
		SsaInstruction instruction;
		if (prefix != null) {
			var operand = lower_value (prefix.operand, source);
			instruction = new SsaPrefixInstruction (prefix.span, prefix.semantic_type, next_value++, prefix.operator_kind, operand);
		} else {
			var binary = (CfgBinaryValue) value;
			// Preserve left-to-right operand construction. CFG evaluation
			// instructions keep earlier traps ahead of later ordered calls.
			var left = lower_value (binary.left, source);
			var right = lower_value (binary.right, source);
			instruction = new SsaBinaryInstruction (binary.span, binary.semantic_type, next_value++, binary.operator_kind, left, right);
		}
		blocks.lookup (source).instructions.add (instruction);
		return instruction.result;
	}
}
}
