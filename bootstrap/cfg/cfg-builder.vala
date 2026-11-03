// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Core;
using Astra.Source;
using Astra.Semantic;

namespace Astra.Cfg {
// Temporary lowering state, not runtime storage or an ownership solver.
private class CleanupScope : Object {
	public CoreBlock scope;
	public CfgEnumSlot? inspection;
	public CfgTemporaryPlace? exception_owner;
	public CfgCleanupContract? exception_cleanup;
	public GenericArray<CfgLocalPlace> text_loans = new GenericArray<CfgLocalPlace> ();
	public GenericArray<Object> acquired = new GenericArray<Object> ();
	private HashTable<Object, int> parameter_ordinals = new HashTable<Object, int> (direct_hash, direct_equal);
	public void acquire_parameter(Object action, int ordinal) {
		int position = 0;
		while (position < acquired.length && parameter_ordinals.contains (acquired[position]) && parameter_ordinals.lookup (acquired[position]) < ordinal) {
			position++;
		}
		acquired.insert (position, action);
		parameter_ordinals.insert (action, ordinal);
	}

	public CleanupScope (CoreBlock scope) {
		this.scope = scope;
	}

}

private class ExceptionTarget : Object {
	internal CfgBlock destination;
	internal CfgTemporaryPlace slot;
	internal int retained_depth;
	internal ExceptionTarget (CfgBlock destination, CfgTemporaryPlace slot, int retained_depth) {
		this.destination = destination;
		this.slot = slot;
		this.retained_depth = retained_depth;
	}

}
private class ArgumentFrame : Object {
	// Acquisition order spans named reservations and completed fresh producers.
	// Completed inner consumers leave their frame before invocation and cannot
	// be rolled back when an enclosing argument subsequently fails.
	internal GenericArray<Object> staged = new GenericArray<Object> ();
}
public class CfgBuilder : Object {
	private ReadonlyCallContext call_context = new ReadonlyCallContext ();
	private bool closed_substitution;

	private static bool has_closed_substitution(CoreFunction source) {
		if (source.generic_instance != null) {
			return true;
		}
		CoreNativeInstance? owner = null;
		var method = source as CoreMethod;
		if (method != null) {
			if (method.generic_method_instance != null) {
				return true;
			}
			owner = method.declaring_type;
		}
		var accessor = source as CorePropertyAccessor;
		if (accessor != null) {
			owner = accessor.property_member.declaring_type;
		}
		var lifecycle = source as CoreLifecycle;
		if (lifecycle != null) {
			owner = lifecycle.declaring_class;
		}
		return owner is CoreClass && ((CoreClass) owner).generic_instance != null;
	}

	private HashTable<CoreWithContract, CfgValue> with_captures = new HashTable<CoreWithContract, CfgValue> (direct_hash, direct_equal);
	private GenericArray<ExceptionTarget> exception_targets = new GenericArray<ExceptionTarget> ();
	private HashTable<CoreLocalPlace, CfgTemporaryPlace> catch_owners = new HashTable<CoreLocalPlace, CfgTemporaryPlace> (direct_hash, direct_equal);
	private ClassType? exception_root_type;
	private SemanticType? exception_bool_type;
	private HashTable<EnumType, EnumDefinition> enum_definitions = new HashTable<EnumType, EnumDefinition> (direct_hash, direct_equal);
	private HashTable<CoreLocalPlace, CfgEnumSlot> enum_locals = new HashTable<CoreLocalPlace, CfgEnumSlot> (direct_hash, direct_equal);
	private CfgValue? allocation_receiver;
	private HashTable<SemanticType, StructValueShape> struct_shapes = new HashTable<SemanticType, StructValueShape> (direct_hash, direct_equal);
	private HashTable<SemanticType, StructValueShape> borrowed_struct_shapes = new HashTable<SemanticType, StructValueShape> (direct_hash, direct_equal);
	private HashTable<GenericArray<CfgValue>, GenericArray<CfgStructBoundaryMove>> record_argument_moves = new HashTable<GenericArray<CfgValue>, GenericArray<CfgStructBoundaryMove>> (direct_hash, direct_equal);
	private HashTable<GenericArray<CfgValue>, CfgStructCallResults> record_result_groups = new HashTable<GenericArray<CfgValue>, CfgStructCallResults> (direct_hash, direct_equal);
	private HashTable<CoreParameter, StructBoundaryGroup> struct_parameters = new HashTable<CoreParameter, StructBoundaryGroup> (direct_hash, direct_equal);
	private HashTable<CoreParameter, GenericArray<CfgParameter>> struct_parameter_leaves = new HashTable<CoreParameter, GenericArray<CfgParameter>> (direct_hash, direct_equal);
	private GenericArray<ArgumentFrame> argument_frames = new GenericArray<ArgumentFrame> ();
	private GenericArray<CleanupScope> cleanup_scopes = new GenericArray<CleanupScope> ();
	private HashTable<CoreLoopTarget, int> loop_cleanup_depths = new HashTable<CoreLoopTarget, int> (direct_hash, direct_equal);
	private HashTable<CoreCleanupContract, CfgCleanupContract> cleanups = new HashTable<CoreCleanupContract, CfgCleanupContract> (direct_hash, direct_equal);
	private HashTable<CoreCFunction, CfgCFunction> c_callees = new HashTable<CoreCFunction, CfgCFunction> (direct_hash, direct_equal);
	private HashTable<CoreFunction, CfgFunction> callees = new HashTable<CoreFunction, CfgFunction> (direct_hash, direct_equal);
	private HashTable<CoreObjectStorage, CfgObjectStorage> object_storage = new HashTable<CoreObjectStorage, CfgObjectStorage> (direct_hash, direct_equal);
	private HashTable<CoreProperty, CfgProperty> properties = new HashTable<CoreProperty, CfgProperty> (direct_hash, direct_equal);
	private HashTable<CoreReceiver, CfgReceiver> receivers = new HashTable<CoreReceiver, CfgReceiver> (direct_hash, direct_equal);
	private HashTable<CoreParameter, CfgParameter> parameters = new HashTable<CoreParameter, CfgParameter> (direct_hash, direct_equal);
	private HashTable<CoreLocalPlace, CfgLocalPlace> locals = new HashTable<CoreLocalPlace, CfgLocalPlace> (direct_hash, direct_equal);
	private HashTable<CoreLoopTarget, CfgBlock> loop_headers = new HashTable<CoreLoopTarget, CfgBlock> (direct_hash, direct_equal);
	private HashTable<CoreLoopTarget, CfgBlock> loop_exits = new HashTable<CoreLoopTarget, CfgBlock> (direct_hash, direct_equal);

	private HashTable<SemanticType, CoreStruct> copy_structs = new HashTable<SemanticType, CoreStruct> (direct_hash, direct_equal);

	private HashTable<CoreNativeInstance, CfgNativeInstance> structs = new HashTable<CoreNativeInstance, CfgNativeInstance> (direct_hash, direct_equal);
	private HashTable<CoreStructField, CfgStructField> fields = new HashTable<CoreStructField, CfgStructField> (direct_hash, direct_equal);
	private CoreDestructor? destructor_epilogue;
	private CoreConstructor? constructor_unwind;
	private HashTable<CoreFieldPlace, CfgFieldPlace> projections = new HashTable<CoreFieldPlace, CfgFieldPlace> (direct_hash, direct_equal);

	// Sole continuation authority for statement and expression lowering.
	private CfgFunction function;
	private CfgBlock? current;

	private CfgBuilder () {
	}

	public static CfgProgram build(CoreProgram program) throws CfgError {
		// Enforce the input boundary even for direct API callers.
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			throw new CfgError.INVALID_CORE ("internal CFG construction error: %s", error.message);
		}
		var builder = new CfgBuilder ();
		builder.exception_bool_type = program.exception_bool_type;
		foreach (var owner in program.classes) {
			if (owner.exception_root) {
				builder.exception_root_type = (ClassType) owner.semantic_type;
			}
		}
		foreach (var definition in program.enums) {
			builder.enum_definitions.insert (definition.semantic_type, definition);
		}
		var structures = new GenericArray<CfgStruct> ();
		var classes = new GenericArray<CfgClass> ();
		foreach (var structure in program.structs) {
			builder.copy_structs.insert (structure.semantic_type, structure);
		}
		foreach (var source in program.native_instances ()) {
			builder.call_context.add_type (source.semantic_type);
			foreach (var field in source.fields) {
				builder.call_context.add_field (source.semantic_type, field.semantic_type);
			}
			foreach (var property in source.properties) {
				if (property.is_owned_lazy) {
					builder.call_context.add_field (source.semantic_type, property.semantic_type);
				}
			}
			CfgNativeInstance structure = (source.semantic_type is ClassType) ? (CfgNativeInstance) new CfgClass (source.span, source.name_span, source.name, (ClassType) source.semantic_type, source.ordinal) : new CfgStruct (source.span, source.name_span, source.name, source.semantic_type, source.ordinal);
			if (source is CoreStruct) {
				var original = ((CoreStruct) source).representation;
				((CfgStruct) structure).representation = original == null ? null : original.copy ();
				foreach (var argument in ((CoreStruct) source).owning_arguments) {
					((CfgStruct) structure).owning_arguments.add (argument);
				}
			}
			if (structure is CfgClass) {
				classes.add ((CfgClass) structure);
			} else {
				structures.add ((CfgStruct) structure);
			}
			if (structure is CfgClass) {
				var key = ((CoreClass) source).generic_instance;
				((CfgClass) structure).generic_instance = key == null ? null : key.copy ();
			}
			builder.structs.insert (source, structure);
			foreach (var property in source.properties) {
				var declaration = new CfgProperty (property.span, property.name_span, property.name, structure, property.semantic_type, property.ordinal, property.member_ordinal);
				declaration.is_lazy = property.is_lazy;
				declaration.is_owned_lazy = property.is_owned_lazy;
				declaration.is_borrowed = property.is_borrowed;
				structure.properties.add (declaration);
				builder.properties.insert (property, declaration);
			}
			foreach (var field in source.fields) {
				var descriptor = new CfgStructField (field.span, field.name_span, field.name, structure, field.semantic_type, field.ordinal, field.is_private);
				if (field.requires_nonnull) {
					descriptor.mark_nonnull ();
				}
				descriptor.text_snapshot = field.text_snapshot;
				structure.fields.add (descriptor);
				builder.fields.insert (field, descriptor);
			}
		}
		foreach (var source in program.classes) {
			var owner = (CfgClass) builder.structs.lookup (source);
			owner.foreign_export = source.foreign_export == null ? null : source.foreign_export.copy ();
			owner.allocation_policy = source.allocation_policy == null ? null : source.allocation_policy.copy ();
			owner.concurrency_policy = source.concurrency_policy == null ? null : source.concurrency_policy.copy ();
			owner.parent_class = source.parent_class == null ? null : (CfgClass) builder.structs.lookup (source.parent_class);
			owner.polymorphic = source.polymorphic;
			owner.exception_root = source.exception_root;
		}
		var cleanup_contracts = new GenericArray<CfgCleanupContract> ();
		foreach (var source in program.cleanups) {
			var cleanup = source.record_type != null ? new CfgCleanupContract.for_record ((CfgStruct) builder.structs.lookup (source.record_type), source.ordinal) : source.is_buffer ? new CfgCleanupContract.for_buffer (source.buffer_shape, source.symbol_span, source.ordinal) : source.is_object ? new CfgCleanupContract.for_object ((CfgClass) builder.structs.lookup (source.object_class), source.ordinal, source.is_heap_object) : new CfgCleanupContract (source.external_symbol, source.symbol_span, source.ordinal);
			cleanup.closure_type = source.closure_type;
			if (source.closure_environment != null) {
				cleanup.closure_environment = (CfgClass) builder.structs.lookup (source.closure_environment);
			}
			cleanup.shared_type = source.shared_type;
			if (source.shared_payload != null) {
				cleanup.shared_payload = (CfgClass) builder.structs.lookup (source.shared_payload);
			}
			cleanup_contracts.add (cleanup);
			builder.cleanups.insert (source, cleanup);
		}
		foreach (var owner in program.native_instances ()) {
			foreach (var field in owner.fields) {
				if (field.slots_cleanup != null) {
					builder.fields.lookup (field).slots_cleanup = builder.cleanups.lookup (field.slots_cleanup);
				}
				if (field.owned_cleanup != null) {
					builder.fields.lookup (field).owned_cleanup = builder.cleanups.lookup (field.owned_cleanup);
				}
			}
		}
		var handle_declarations = new GenericArray<CfgHandle> ();
		var handles = new HashTable<CoreHandle, CfgHandle> (direct_hash, direct_equal);
		foreach (var source in program.handles) {
			var handle = new CfgHandle (source.span, source.name_span, source.semantic_type, builder.cleanups.lookup (source.cleanup), source.header, source.ordinal, source.context_mode);
			handle.c_import = source.c_import;
			handle.com_import = source.com_import == null ? null : source.com_import.copy ();
			handles.insert (source, handle);
			handle_declarations.add (handle);
		}
		var functions = new GenericArray<CfgFunction> ();
		var imports = new GenericArray<CfgCFunction> ();
		foreach (var source in program.c_functions) {
			var parameter_types = new GenericArray<SemanticType> ();
			var import_parameters = new GenericArray<CfgParameter> ();
			foreach (var parameter_type in source.parameter_types) {
				parameter_types.add (parameter_type);
			}
			foreach (var parameter in source.parameters) {
				if (parameter.requires_nonnull) {
					throw new CfgError.INVALID_CORE ("foreign nonnull contracts cannot be assumed");
				}
				var translated = new CfgParameter (parameter.span, parameter.name_span, parameter.name, parameter.semantic_type, parameter.ordinal, parameter.pointer_contract);
				import_parameters.add (translated);
				builder.parameters.insert (parameter, translated);
			}
			var imported = new CfgCFunction (source.span, source.name_span, source.name, source.metadata, source.abi, source.return_type, parameter_types, imports.length, source.owned_cleanup == null ? null : builder.cleanups.lookup (source.owned_cleanup), import_parameters);
			imports.add (imported);
			builder.c_callees.insert (source, imported);
		}
		for (int i = 0; i < program.functions.length; i++) {
			var function = builder.declare_function (program.functions[i], i);
			functions.add (function);
			function.async_body = program.functions[i].async_body;
			function.throws_type = program.functions[i].throws_type;
			function.dispatch_kind = program.functions[i].dispatch_kind;
			function.virtual_slot = program.functions[i].virtual_slot;
			builder.callees.insert (program.functions[i], function);
		}
		foreach (var owner in program.native_instances ()) {
			foreach (var property in owner.properties) {
				if (property.factory != null) {
					builder.properties.lookup (property).factory = (CfgMethod) builder.callees.lookup (property.factory);
				}
			}
		}
		for (int i = 0; i < program.functions.length; i++) {
			var body = program.functions[i].body;
			builder.function = functions[i];
			builder.closed_substitution = has_closed_substitution (program.functions[i]);
			builder.destructor_epilogue = program.functions[i] as CoreDestructor;
			builder.constructor_unwind = program.functions[i] as CoreConstructor;
			builder.loop_headers.remove_all ();
			builder.loop_exits.remove_all ();
			if (program.functions[i].native_declaration != null) {
				functions[i].entry.complete (body.span, new CfgNativeDeclaration (body.span));
				continue;
			}
			builder.lower_block (body, functions[i].entry, new CfgFunctionEnd (body.span), functions[i].blocks);
		}
		var exports = new GenericArray<CfgCExport> ();
		foreach (var exported in program.c_exports) {
			var source_target = exported.target;
			var target = source_target == null ? null : builder.callees.lookup (source_target);
			if (target == null) {
				throw new CfgError.INVALID_CORE ("internal Cfg construction error: C export target is expired or has no exact native mapping");
			}
			exports.add (new CfgCExport (exported.span, exported.name_span, target, exported.external_symbol, exported.abi, exported.ordinal, exported.record_abi, exported.bool_abi));
		}
		foreach (var source in program.classes) {
			var owner = (CfgClass) builder.structs.lookup (source);
			foreach (var entry in source.virtual_entries) {
				owner.virtual_entries.add (builder.callees.lookup (entry));
			}
		}
		var result = new CfgProgram (program.span, functions, imports, exports, structures, cleanup_contracts, handle_declarations);
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
		return result;
	}

	private CfgFunction declare_function(CoreFunction function, int ordinal) throws CfgError {
		var declarations = new GenericArray<CfgParameter> ();
		for (int i = 0; i < function.parameters.length; i++) {
			var parameter = function.parameters[i];
			if (parameter.struct_value_contract != null) {
				var shape = struct_shape (parameter.semantic_type, parameter.struct_value_contract.mode == StructValueMode.BORROW_VALUE);
				var group = new StructBoundaryGroup (i, declarations.length, shape);
				struct_parameters.insert (parameter, group);
				var leaves = new GenericArray<CfgParameter> ();
				foreach (var leaf in shape.leaves) {
					var contract = shape.mode == StructValueMode.BORROW_VALUE && (leaf.semantic_type is ClassType || leaf.semantic_type is HandleType || leaf.semantic_type is SliceType) ? PointerParameterContract.BORROWED_NOESCAPE : PointerParameterContract.UNMANAGED;
					var incoming = new CfgParameter (parameter.span, parameter.name_span, parameter.name + "." + leaf.spelling (), leaf.semantic_type, declarations.length, contract);
					declarations.add (incoming);
					leaves.add (incoming);
				}
				struct_parameter_leaves.insert (parameter, leaves);
				continue;
			}
			var declaration = new CfgParameter (parameter.span, parameter.name_span, parameter.name, parameter.semantic_type, declarations.length, parameter.pointer_contract);
			declaration.heap_object = parameter.heap_object;
			if (parameter.requires_nonnull) {
				declaration.mark_nonnull ();
			}
			declarations.add (declaration);
			parameters.insert (parameter, declaration);
		}
		var local_places = new GenericArray<CfgLocalPlace> ();
		var owned_places = new HashTable<CoreLocalPlace, CoreCleanupContract> (direct_hash, direct_equal);
		foreach (var owner in function.owned_locals) {
			owned_places.insert (owner.place, owner.cleanup);
		}
		for (int i = 0; i < function.locals.length; i++) {
			var local = function.locals[i];
			var contract = owned_places.lookup (local);
			var place = new CfgLocalPlace (local.span, local.name_span, local.name, local.semantic_type, i, local.address_taken, contract == null ? null : cleanups.lookup (contract), local.incoming_parameter == null ? null : parameters.lookup (local.incoming_parameter));
			if (local.requires_nonnull) {
				place.mark_nonnull ();
			}
			place.text_extent = local.text_extent;
			place.text_loan = local.text_loan;
			if (local.incoming_parameter != null) {
				place.struct_parameter = struct_parameters.lookup (local.incoming_parameter);
			}
			local_places.add (place);
			locals.insert (local, place);
		}
		var blocks = new GenericArray<CfgBlock> ();
		var entry = reserve_block (function.body.span, blocks);
		CfgFunction result;
		foreach (var source in function.object_storage) {
			var storage = new CfgObjectStorage (source.span, (CfgClass) structs.lookup (source.object_class), source.ordinal, source.region_ordinal, source.fallible);
			storage.transferable = source.transferable;
			storage.heap_allocated = source.heap_allocated;
			storage.result_candidate = source.result_candidate;
			object_storage.insert (source, storage);
		}
		foreach (var owner in function.owned_locals) {
			if (owner.object_storage != null) {
				locals.lookup (owner.place).object_storage = object_storage.lookup (owner.object_storage);
			}
		}
		var method = function as CoreMethod;
		var cleanup = function.owned_cleanup == null ? null : cleanups.lookup (function.owned_cleanup);
		var lifecycle = function as CoreLifecycle;
		if (lifecycle != null) {
			var receiver = new CfgReceiver (lifecycle.receiver.span, lifecycle.receiver.contract);
			receivers.insert (lifecycle.receiver, receiver);
			var object_class = (CfgClass) structs.lookup (lifecycle.declaring_class);
			if (function is CoreConstructor) {
				var constructor = new CfgConstructor (function.span, function.name_span, object_class, receiver, lifecycle.member_ordinal, function.return_type, ordinal, declarations, local_places, blocks, entry);
				object_class.constructor = constructor;
				result = constructor;
			} else {
				var destructor = new CfgDestructor (function.span, function.name_span, object_class, receiver, lifecycle.member_ordinal, function.return_type, ordinal, declarations, local_places, blocks, entry);
				object_class.destructor = destructor;
				result = destructor;
			}
		} else if (function is CorePropertyAccessor) {
			var accessor = (CorePropertyAccessor) function;
			var property = properties.lookup (accessor.property_member);
			var receiver = new CfgReceiver (accessor.receiver.span, accessor.receiver.contract);
			receivers.insert (accessor.receiver, receiver);
			if (function is CorePropertyGetter) {
				var getter = new CfgPropertyGetter (function.span, function.name_span, function.name, property, receiver, function.return_type, ordinal, declarations, local_places, blocks, entry, cleanup);
				property.getter = getter;
				result = getter;
			} else {
				var setter = new CfgPropertySetter (function.span, function.name_span, function.name, property, receiver, function.return_type, ordinal, declarations, local_places, blocks, entry);
				property.setter = setter;
				result = setter;
			}
		} else if (method != null) {
			var receiver = new CfgReceiver (method.receiver.span, method.receiver.contract);
			receivers.insert (method.receiver, receiver);
			var structure = structs.lookup (method.declaring_type);
			var declaration = new CfgMethod (function.span, function.name_span, function.name, structure, receiver, method.method_ordinal, method.member_ordinal, function.return_type, ordinal, declarations, local_places, blocks, entry, cleanup);
			declaration.generic_method_instance = method.generic_method_instance == null ? null : method.generic_method_instance.copy ();
			structure.methods.add (declaration);
			result = declaration;
		} else {
			result = new CfgFunction (function.span, function.name_span, function.name, function.return_type, ordinal, declarations, local_places, blocks, entry, cleanup);
		}
		foreach (var owner in function.owned_locals) {
			foreach (var field in owner.record_fields) {
				locals.lookup (owner.place).record_order.add (field.storage_path ());
			}
		}
		foreach (var source in function.field_places) {
			var place = new CfgFieldPlace (source.span, (source.aggregate is CoreLocalPlace) ? (CfgPlace) locals.lookup ((CoreLocalPlace) source.aggregate) : projections.lookup ((CoreFieldPlace) source.aggregate), fields.lookup (source.field));
			result.field_places.add (place);
			projections.insert (source, place);
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
			var receiver = result.implicit_receiver;
			result.bind_native_declaration (function.native_declaration.lowered (result.return_type, result.result_contract,
				result.heap_result, result.nonnull_result, receiver == null ? null : receiver.contract.instance_type,
				function.throws_type, types, contracts, heaps, nonnull));
		}
		if (function.result_storage != null) {
			result.result_storage = new CfgResultObjectStorage (function.span, (CfgClass) structs.lookup (function.result_storage.object_class));
		}
		foreach (var parameter in function.parameters) {
			var group = struct_parameters.lookup (parameter);
			if (group != null) {
				result.struct_parameters.add (group);
			}
		}
		if (function.struct_result_contract != null) {
			result.struct_result = struct_shape (function.return_type, function.struct_result_contract.mode == StructValueMode.BORROW_VALUE);
		}
		foreach (var local in function.locals) {
			if (local.semantic_type is EnumType) {
				var slot = new CfgEnumSlot (local.span, enum_definitions.lookup ((EnumType) local.semantic_type), result.enum_slots.length, locals.lookup (local));
				result.enum_slots.add (slot);
				enum_locals.insert (local, slot);
			}
		}
		foreach (var source in function.object_storage) {
			result.object_storage.add (object_storage.lookup (source));
		}
		return result;
	}

	private CfgBlock reserve_block(SourceSpan span, GenericArray<CfgBlock> blocks) {
		var block = new CfgBlock.reserve (span, blocks.length);
		blocks.add (block);
		return block;
	}

	// The supplied terminator is the enclosing continuation. Return, break,
	// and continue end their path; subsequent source starts disconnected blocks.
	private void lower_block(CoreBlock body, CfgBlock entry, CfgTerminator? completion, GenericArray<CfgBlock> blocks, GenericArray<CoreCleanupAction>? acquisitions = null, CfgEnumSlot? inspection = null, CfgTemporaryPlace? exception_owner = null, CfgCleanupContract? exception_cleanup = null) throws CfgError {
		var cleanup_scope = new CleanupScope (body);
		cleanup_scope.exception_owner = exception_owner;
		cleanup_scope.exception_cleanup = exception_cleanup;
		cleanup_scope.inspection = inspection;
		if (acquisitions != null) {
			foreach (var action in acquisitions) {
				cleanup_scope.acquired.add (action);
			}
		}
		cleanup_scopes.add (cleanup_scope);
		current = entry;
		var pending_span = body.span;
		for (int i = 0; i < body.statements.length; i++) {
			var statement = body.statements[i];
			if (current == null) {
				current = reserve_block (statement.span, blocks);
			}
			if (current.instructions.length == 0) {
				pending_span = statement.span;
			}
			if (statement is CoreTry) {
				lower_try ((CoreTry) statement);
				continue;
			}
			if (statement is CoreVectorMemoryStatement) {
				build_value (((CoreVectorMemoryStatement) statement).operation);
				continue;
			}
			if (statement is CoreThrow) {
				var thrown = (CoreThrow) statement;
				CfgValue exception;
				if (thrown.rethrows) {
					var slot = catch_owners.lookup (thrown.source);
					if (slot == null) {
						throw new CfgError.INVALID_CORE ("bare throw lost nearest lexical catch ownership");
					}
					exception = capture_before_transfer (new CfgLoadValue (statement.span, slot));
					current.instructions.add (new CfgStore (statement.span, slot, new CfgNullPointerValue (statement.span, slot.semantic_type)));
				} else {
					var take = new CfgExceptionTake (statement.span, locals.lookup (thrown.source));
					current.instructions.add (take);
					exception = take.result;
					current.instructions.add (new CfgExceptionStamp (statement.span, exception));
				} if (exception.semantic_type != exception_root_type) {
					var source_class = (CfgClass) structs.lookup (thrown.owner.cleanup.object_class);
					var target_class = (CfgClass) structs.lookup (thrown.cleanup.object_class);
					exception = capture_before_transfer (new CfgClassUpcast (statement.span, exception, source_class, target_class, exception_root_type));
				}
				route_exception (statement.span, exception);
				current = null;
				continue;
			}
			if (statement is CoreAcquireEnumParameter) {
				var acquisition = (CoreAcquireEnumParameter) statement;
				current.instructions.add (new CfgEnumAcquire (statement.span, enum_locals.lookup (acquisition.destination), parameters.lookup (acquisition.parameter)));
				if (enum_owns (enum_locals.lookup (acquisition.destination).definition)) {
					cleanup_scope.acquire_parameter (new CoreCleanupAction.for_enum (acquisition.destination), acquisition.parameter.ordinal);
				}
				continue;
			}
			if (statement is CoreEnumStore) {
				var store = (CoreEnumStore) statement;
				var incoming = lower_enum_producer (store.producer);
				commit_enum (incoming);
				var destination = enum_locals.lookup (store.destination);
				if (enum_owns (destination.definition)) {
					if (!store.initializes_destination) {
						current.instructions.add (new CfgEnumDrop (store.span, destination));
					}
					if (store.initializes_destination) {
						cleanup_scope.acquired.add (new CoreCleanupAction.for_enum (store.destination));
					}
				}
				current.instructions.add (new CfgEnumCopy (statement.span, destination, incoming, store.initializes_destination, enum_owns (destination.definition) ? EnumUse.MOVE : EnumUse.COPY));
				continue;
			}
			if (statement is CoreEnumReturn) {
				var incoming = lower_enum_producer (((CoreEnumReturn) statement).producer);
				commit_enum (incoming);
				emit_cleanups (0, statement.span);
				current.complete (SourceSpan.cover (pending_span, statement.span), new CfgEnumReturn (statement.span, incoming));
				current = null;
				continue;
			}
			if (statement is CoreEnumMatch) {
				lower_enum_match ((CoreEnumMatch) statement);
				pending_span = statement.span;
				continue;
			}
			if (statement is CoreWithScope) {
				var scoped = (CoreWithScope) statement;
				var captured = capture_before_transfer (new CfgLoadValue (scoped.span, locals.lookup (scoped.source)));
				with_captures.insert (scoped.contract, validate_object (captured, captured.semantic_type));
				call_context.enter (scoped.source.semantic_type);
				lower_block (scoped.body, current, null, blocks);
				call_context.leave ();
				with_captures.remove (scoped.contract);
				continue;
			}
			var scope = statement as CoreScope;
			if (scope != null) {
				// A lexical scope needs cleanup, but no control-flow edge of
				// its own. Preserve null after return/break/continue, rather
				// than manufacturing a disconnected continuation/backedge.
				lower_block (scope.body, current, null, blocks);
				continue;
			}
			var c_call = statement as CoreCCallStatement;
			if (statement is CoreActorSend) {
				var operation = (CoreActorSend) statement;
				var sender = build_value (operation.sender);
				CfgValue? message = operation.scalar == null ? null : evaluate_before_effect (build_value (operation.scalar));
				if (operation.message != null) {
					var source = locals.lookup (operation.message.place);
					var capture = new CfgResourceCapture (statement.span, new CfgLoadValue (statement.span, source), source, source.cleanup);
					current.instructions.add (capture);
					message = capture.result;
				}
				var send = new CfgActorSend (statement.span, operation.action, sender, message, operation.error_type);
				current.instructions.add (send);
				var success = reserve_block (statement.span, function.blocks);
				var failure = reserve_block (statement.span, function.blocks);
				var condition = new CfgBinaryValue (statement.span, exception_bool_type, BinaryOperator.EQUAL, send.result, new CfgNullPointerValue (statement.span, operation.error_type));
				current.complete (statement.span, new CfgConditionalBranch (statement.span, condition, success, failure));
				current = failure;
				route_exception (statement.span, send.result);
				current = success;
				continue;
			}
			if (statement is CoreValueStatement) {
				var value = build_value (((CoreValueStatement) statement).value);
				if (!(value is CfgEvaluatedValue)) {
					current.instructions.add (new CfgEvaluateInstruction (statement.span, value, new CfgEvaluatedValue (statement.span, value.semantic_type)));
				}
				continue;
			}
			if (statement is CoreAsyncOperationStatement) {
				build_value (((CoreAsyncOperationStatement) statement).operation);
				continue;
			}
			if (statement is CoreTaskAwaitStatement) {
				build_value (((CoreTaskAwaitStatement) statement).operation);
				continue;
			}
			if (statement is CoreAsyncDelay) {
				var delay = (CoreAsyncDelay) statement;
				var operation = new CfgAsyncDelay (statement.span, delay.body, delay.payload ? build_value (delay.ticks) : evaluate_before_effect (build_value (delay.ticks)), exception_root_type, delay.payload);
				current.instructions.add (operation);
				var success = reserve_block (statement.span, function.blocks);
				var failure = reserve_block (statement.span, function.blocks);
				var condition = new CfgBinaryValue (statement.span, exception_bool_type, BinaryOperator.EQUAL, operation.exception, new CfgNullPointerValue (statement.span, exception_root_type));
				current.complete (statement.span, new CfgConditionalBranch (statement.span, condition, success, failure));
				current = failure;
				route_exception (statement.span, operation.exception);
				current = success;
				continue;
			}
			if (c_call != null) {
				lower_c_call (c_call.span, c_call.target, c_call.arguments);
				continue;
			}
			var call = statement as CoreCallStatement;
			if (call != null) {
				var lowered = lower_call (call.span, call.target, call.arguments, call.receiver, null, false, null, null, call is CoreBaseLifecycleCall);
				if (call is CoreDiscardOwnedSuccess) {
					current.instructions.add (new CfgCleanupInstruction (call.span, lowered.result, cleanups.lookup (((CoreDiscardOwnedSuccess) call).cleanup)));
				}
				if (lowered.enum_result != null && enum_owns (lowered.enum_result.definition) && call.target.throws_type != null) {
					current.instructions.add (new CfgEnumDrop (call.span, lowered.enum_result));
				}
				continue;
			}
			var exchange = statement as CoreOwnedBufferExchange;
			if (exchange != null) {
				var left = new CfgBufferSlotCapture (exchange.left.span, find_place (exchange.left.place), cleanups.lookup (exchange.left.cleanup));
				current.instructions.add (left);
				var right = new CfgBufferSlotCapture (exchange.right.span, find_place (exchange.right.place), cleanups.lookup (exchange.right.cleanup));
				current.instructions.add (right);
				current.instructions.add (new CfgBufferExchange (statement.span, left, right));
				continue;
			}
			var rearm = statement as CoreOwnershipRearm;
			if (statement is CoreSlotsRecordTransfer) {
				var transfer = (CoreSlotsRecordTransfer) statement;
				var store = (CfgIndirectFieldPlace) find_place (transfer.store);
				var index = transfer.index == null ? null : capture_before_transfer (build_value (transfer.index));
				var leaves = lower_struct_producer (transfer.value, StructResultUseKind.CONTAINER_ELEMENT);
				var inserted = new CfgSlotsRecordTransfer (statement.span, store, index, struct_shape (transfer.value.semantic_type), leaves);
				var moves = record_argument_moves.lookup (leaves);
				if (moves != null) {
					if (moves.length != 1) {
						throw new CfgError.INVALID_CORE ("record slot insertion requires one complete move");
					}
					inserted.record_move = moves[0];
					moves[0].consumer = inserted;
					current.instructions.add (moves[0]);
				}
				current.instructions.add (inserted);
				continue;
			}
			if (statement is CoreSlotsInitialize) {
				current.instructions.add (new CfgSlotsInitialize (statement.span, (CfgIndirectFieldPlace) find_place (((CoreSlotsInitialize) statement).store)));
				continue;
			}
			if (statement is CoreSlotsReplace) {
				var replace = (CoreSlotsReplace) statement;
				var index = capture_before_transfer (build_value (replace.index));
				current.instructions.add (new CfgSlotsReplace (replace.span, (CfgIndirectFieldPlace) find_place (replace.store), index, locals.lookup (replace.incoming.place)));
				continue;
			}
			if (statement is CoreSlotsAppend) {
				var s = (CoreSlotsAppend) statement;
				current.instructions.add (new CfgSlotsAppend (s.span, (CfgIndirectFieldPlace) find_place (s.store), locals.lookup (s.incoming.place)));
				continue;
			}
			if (statement is CoreOwnedFieldTransfer) {
				var transfer = (CoreOwnedFieldTransfer) statement;
				// Resolve and validate the receiver before even producing the RHS.
				var destination = find_place (transfer.destination);
				var source = transfer.source == null ? null : locals.lookup (transfer.source.place);
				var previous_receiver = allocation_receiver;
				allocation_receiver = ((CfgIndirectFieldPlace) destination).pointer;
				var incoming = source == null ? build_value(transfer.producer) : new CfgLoadValue (transfer.span, source);
				allocation_receiver = previous_receiver;
				var capture = new CfgResourceCapture (transfer.span, incoming, source, cleanups.lookup (transfer.cleanup));
				current.instructions.add (capture);
				if (!transfer.initializes) {
					current.instructions.add (new CfgCleanupInstruction (transfer.span, new CfgLoadValue (transfer.span, destination), capture.cleanup));
				}
				current.instructions.add (transfer.initializes ? (CfgInstruction) new CfgInitialize (transfer.span, destination, capture.result) : new CfgStore (transfer.span, destination, capture.result));
				continue;
			}
			if (rearm != null) {
				if (rearm.source != null) {
					current.instructions.add (new CfgOwnershipRearmInstruction.from_owner (rearm.span, locals.lookup (rearm.owner.place), locals.lookup (rearm.source.place), cleanups.lookup (rearm.cleanup)));
					continue;
				}
				var value = build_value (rearm.producer);
				current.instructions.add (new CfgOwnershipRearmInstruction (rearm.span, locals.lookup (rearm.owner.place), value, cleanups.lookup (rearm.cleanup)));
				continue;
			}
			var release = statement as CoreOwnershipRelease;
			if (release != null) {
				current.instructions.add (new CfgOwnershipReleaseInstruction (release.span, locals.lookup (release.owner.place), cleanups.lookup (release.cleanup)));
				continue;
			}
			var array = statement as CoreArrayInitialize;
			if (array != null) {
				if (array.records.length != 0) {
					foreach (var record_entry in array.records) {
						var root = (CfgArrayElementPlace) find_place (record_entry.target);
						var targets = new GenericArray<CfgPlace> ();
						var values = new GenericArray<CfgValue> ();
						if (record_entry.producer != null) {
							values = lower_struct_producer (record_entry.producer, StructResultUseKind.INITIALIZE, root);
							foreach (var leaf in struct_shape (record_entry.target.semantic_type).leaves) {
								targets.add (struct_leaf (root, leaf));
							}
						} else {
							lower_array_fields (root, record_entry.initializers, targets, values);
						}
						current.instructions.add (new CfgArrayInitialize.record (record_entry.span, root, targets, values));
					}
					continue;
				}
				var elements = new GenericArray<CfgValue> ();
				foreach (var element in array.elements) {
					var value = build_value (element);
					var captured = new CfgEvaluatedValue (element.span, element.semantic_type);
					current.instructions.add (new CfgEvaluateInstruction (element.span, value, captured));
					elements.add (captured);
				}
				current.instructions.add (new CfgArrayInitialize (array.span, locals.lookup (array.storage), elements));
				continue;
			}
			if (statement is CoreAcquireStructParameter) {
				lower_struct_parameter ((CoreAcquireStructParameter) statement);
				continue;
			}
			if (statement is CoreStructResultStore) {
				lower_struct_result_store ((CoreStructResultStore) statement);
				continue;
			}
			if (statement is CoreStructReturn) {
				var producer = ((CoreStructReturn) statement).producer;
				var leaves = lower_struct_producer (producer, StructResultUseKind.RETURN);
				var returned = new CfgStructReturn (statement.span, function.struct_result, leaves);
				var moves = record_argument_moves.lookup (leaves);
				if (moves != null) {
					assert (moves.length == 1);
					returned.record_move = moves[0];
					moves[0].consumer = returned;
					current.instructions.add (moves[0]);
				}
				emit_cleanups (0, statement.span);
				current.complete (SourceSpan.cover (pending_span, statement.span), returned);
				current = null;
				continue;
			}
			if (statement is CoreStructAcquire) {
				lower_record_acquire ((CoreStructAcquire) statement);
				continue;
			}
			if (statement is CoreStructMove) {
				var move = (CoreStructMove) statement;
				current.instructions.add (new CfgOwnershipTransferInstruction (move.span, locals.lookup (move.source.place), locals.lookup (move.destination.place), cleanups.lookup (move.source.cleanup)));
				bool first = true;
				foreach (var field in move.destination.record_fields) {
					var action = new CoreCleanupAction.for_owner (move.destination);
					action.record_field = field;
					action.record_final = first;
					first = false;
					cleanup_scope.acquired.add (action);
				}
				continue;
			}
			if (statement is CoreRecordTake) {
				var take = (CoreRecordTake) statement;
				current.instructions.add (new CfgRecordTake (take.span, locals.lookup (take.source.place), (CfgFieldPlace) find_place (take.field), locals.lookup (take.destination.place)));
				cleanup_scope.acquired.add (new CoreCleanupAction.for_owner (take.destination));
				continue;
			}
			if (statement is CoreRecordReplace) {
				var replace = (CoreRecordReplace) statement;
				var source = replace.source == null ? null : locals.lookup (replace.source.place);
				var incoming = source == null ? build_value(replace.producer) : new CfgLoadValue (replace.span, source);
				current.instructions.add (new CfgRecordReplace (replace.span, locals.lookup (replace.owner.place), (CfgFieldPlace) find_place (replace.field), source, incoming));
				continue;
			}
			if (statement is CoreStructCopy) {
				lower_struct_copy ((CoreStructCopy) statement);
				continue;
			}
			if (statement is CoreStructInitialize) {
				lower_struct_initializer ((CoreStructInitialize) statement);
				continue;
			}
			var initialization = statement as CoreInitialize;
			var transfer = statement as CoreOwnershipTransfer;
			if (transfer != null) {
				current.instructions.add (new CfgOwnershipTransferInstruction (transfer.span, locals.lookup (transfer.source.place), locals.lookup (transfer.destination.place), cleanups.lookup (transfer.cleanup)));
				assert (transfer.destination.scope == cleanup_scope.scope);
				cleanup_scope.acquired.add (new CoreCleanupAction.for_owner (transfer.destination));
				continue;
			}
			if (initialization != null) {
				if (initialization.target is CoreLocalPlace && ((CoreLocalPlace) initialization.target).text_loan) {
					cleanup_scope.text_loans.add (locals.lookup ((CoreLocalPlace) initialization.target));
				}
				var value = build_value (initialization.value);
				if (initialization is CoreAcquireParameter) {
					current.instructions.add (new CfgAcquireParameter (initialization.span, locals.lookup (initialization.acquisition.place), ((CfgParameterValue) value).parameter));
				} else {
					current.instructions.add (new CfgInitialize (initialization.span, find_place (initialization.target), value, initialization.acquisition == null ? null : locals.lookup (initialization.acquisition.place)));
				}
				if (initialization.acquisition != null) {
					assert (initialization.acquisition.scope == cleanup_scope.scope);
					var action = new CoreCleanupAction.for_owner (initialization.acquisition);
					if (initialization is CoreAcquireParameter) {
						cleanup_scope.acquire_parameter (action, initialization.acquisition.place.incoming_parameter.ordinal);
					} else {
						cleanup_scope.acquired.add (action);
					}
				}
				if (initialization.target is CoreLocalPlace && initialization.target.semantic_type is ExecutorType) {
					cleanup_scope.acquired.add (new CoreCleanupAction.for_executor ((CoreLocalPlace) initialization.target));
				}
				if (initialization.target is CoreLocalPlace && initialization.target.semantic_type is TaskType) {
					cleanup_scope.acquired.add (new CoreCleanupAction.for_task ((CoreLocalPlace) initialization.target));
				}
				continue;
			}
			var construction = statement as CoreObjectConstruction;
			if (construction != null) {
				var storage = object_storage.lookup (construction.storage);
				storage.cleanup_rank = construction.storage.cleanup_rank;
				var invocation = construction as CoreConstructorObjectInitialization;
				if (invocation != null) {
					lower_call (statement.span, invocation.constructor, invocation.arguments, null, storage, false, null, null, false, invocation.allocation_context);
				}
				foreach (var initializer in construction.initializers) {
					var value = build_value (initializer.value);
					current.instructions.add (new CfgInitialize (initializer.span, new CfgObjectFieldPlace (initializer.span, storage, fields.lookup (initializer.field)), value));
				}
				if (construction.acquisition != null) {
					cleanup_scope.acquired.add (new CoreCleanupAction.for_owner (construction.acquisition));
				} else if (construction.storage.destructor != null) {
					cleanup_scope.acquired.add (new CoreCleanupAction.object (construction.storage));
				}
				var reference = new CfgObjectReferenceValue (statement.span, storage);
				var captured = new CfgEvaluatedValue (statement.span, storage.semantic_type);
				current.instructions.add (new CfgEvaluateInstruction (statement.span, reference, captured));
				current.instructions.add (new CfgInitialize (statement.span, find_place (construction.target), captured, construction.acquisition == null ? null : locals.lookup (construction.target)));
				continue;
			}
			var store = statement as CoreStore;
			if (store != null) {
				if ((store.target is CoreFieldPlace && ((CoreFieldPlace) store.target).root_local () == null) || store.target is CoreDereferencePlace || store.target is CoreArrayElementPlace || store.target is CoreSliceElementPlace || (store.target is CoreIndirectFieldPlace && ((CoreIndirectFieldPlace) store.target).pointer.semantic_type is ClassType)) {
					var target = find_place (store.target);
					var value = build_value (store.value);
					current.instructions.add (new CfgStore (store.span, target, value, store.volatile_access == null ? null : store.volatile_access.copy ()));
					continue;
				}
				var value = build_value (store.value);
				current.instructions.add (new CfgStore (store.span, find_place (store.target), value, store.volatile_access == null ? null : store.volatile_access.copy ()));
				continue;
			}
			if (statement is CoreBreak || statement is CoreContinue) {
				var target = (statement is CoreBreak) ? ((CoreBreak) statement).target : ((CoreContinue) statement).target;
				var destination = target == null ? null : ((statement is CoreBreak) ? loop_exits.lookup (target) : loop_headers.lookup (target));
				if (destination == null) {
					throw new CfgError.INVALID_CORE ("internal CFG construction error: loop-control target is expired or has no header/exit mapping");
				}
				emit_cleanups (loop_cleanup_depths.lookup (target), statement.span);
				current.complete (SourceSpan.cover (pending_span, statement.span), new CfgBranch (statement.span, destination));
				current = null;
				continue;
			}
			var owned_return = statement as CoreOwnershipReturn;
			if (owned_return != null) {
				var value = new CfgOwnedReturnValue (statement.span, owned_return.semantic_type, cleanups.lookup (owned_return.cleanup), owned_return.source == null ? null : locals.lookup (owned_return.source.place), owned_return.producer == null ? null : build_value (owned_return.producer), owned_return.provenance);
				current.instructions.add (new CfgOwnershipReturnInstruction (statement.span, value));
				emit_cleanups (0, statement.span);
				current.complete (SourceSpan.cover (pending_span, statement.span), new CfgOwnershipReturn (statement.span, value));
				current = null;
				continue;
			}
			if (statement is CoreForeignSignalReturn) {
				current.complete (statement.span, new CfgForeignSignalReturn (statement.span, ((CoreForeignSignalReturn) statement).binding));
				current = null;
				continue;
			}
			if (statement is CoreForeignReturn) {
				var imported = (CoreForeignReturn) statement;
				var consumed = new GenericArray<CfgLocalPlace> ();
				foreach (var owner in imported.consumed) {
					consumed.add (locals.lookup (owner.place));
				}
				current.complete (statement.span, new CfgForeignReturn (statement.span, imported.binding, callees.lookup (imported.factory), consumed));
				current = null;
				continue;
			}
			var returned = statement as CoreReturn;
			if (returned != null) {
				var value = returned.value == null ? null : build_value (returned.value);
				// Snapshot the complete return expression before every cleanup,
				// including pure arithmetic whose evaluation can trap.
				if (value != null && has_active_cleanup ()) {
					var evaluated = new CfgEvaluatedValue (value.span, value.semantic_type);
					current.instructions.add (new CfgEvaluateInstruction (value.span, value, evaluated));
					value = evaluated;
				}
				emit_cleanups (0, returned.span);
				current.complete (SourceSpan.cover (pending_span, returned.span), new CfgReturn (returned.span, value));
				current = null;
				continue;
			}
			var loop = statement as CoreWhile;
			if (loop != null) {
				// Reserve all three identities before recursively lowering the
				// body. The current block is the existing preheader.
				var header = reserve_block (loop.condition.span, blocks);
				var loop_body = reserve_block (loop.body.span, blocks);
				var step = loop.step == null ? null : reserve_block (loop.step.span, blocks);
				var exit = reserve_block (loop.span, blocks);
				loop_cleanup_depths.insert (loop.target, cleanup_scopes.length);
				loop_headers.insert (loop.target, step ?? header);
				loop_exits.insert (loop.target, exit);
				current.complete (SourceSpan.cover (pending_span, loop.span), new CfgBranch (loop.span, header));
				current = header;
				var condition = build_value (loop.condition);
				current.complete (loop.condition.span, conditional_branch (loop.condition.span, condition, loop_body, exit));
				// Explicit transfers ignore this continuation. Their source tails
				// receive it only in disconnected, still unreachable blocks.
				lower_block (loop.body, loop_body, new CfgBranch (loop.body.span, step ?? header), blocks);
				if (step != null) {
					bool incoming_step = false;
					foreach (var candidate in blocks) {
						if (!candidate.is_complete) {
							continue;
						}
						foreach (var successor in candidate.terminator.successors ()) {
							if (successor == step) {
								incoming_step = true;
							}
						}
					}
					if (incoming_step) {
						lower_block (loop.step, step, new CfgBranch (loop.step.span, header), blocks);
					} else {
						step.complete (loop.step.span, new CfgFunctionEnd (loop.step.span));
					}
				}
				current = exit;
				pending_span = loop.span;
				continue;
			}
			var conditional = statement as CoreIf;
			if (conditional != null) {
				// Reserve then, optional else, join before visiting either arm.
				// Nested allocations follow these slots, never ordinal adjacency.
				var then_block = reserve_block (conditional.then_block.span, blocks);
				var else_block = conditional.else_block == null ? null : reserve_block (conditional.else_block.span, blocks);
				var join = reserve_block (conditional.span, blocks);
				var condition = build_value (conditional.condition);
				current.complete (SourceSpan.cover (pending_span, conditional.span), conditional_branch (conditional.span, condition, then_block, else_block ?? join));
				lower_block (conditional.then_block, then_block, new CfgBranch (conditional.then_block.span, join), blocks);
				if (conditional.else_block != null) {
					lower_block (conditional.else_block, else_block, new CfgBranch (conditional.else_block.span, join), blocks);
				}
				current = join;
				pending_span = conditional.span;
				continue;
			}
			throw new CfgError.INVALID_CORE ("internal CFG construction error: unsupported Core statement");
		}
		if (current != null) {
			emit_cleanups (cleanup_scopes.length - 1, body.span);
			if (completion != null) {
				current.complete (SourceSpan (body.span.file, pending_span.start, body.span.end), completion);
			}
		}
		cleanup_scopes.remove_index (cleanup_scopes.length - 1);
	}

	private CfgTerminator conditional_branch(SourceSpan span, CfgValue condition, CfgBlock yes, CfgBlock no) {
		var constant = condition as CfgBooleanValue;
		// Closed template bodies have already resolved their ownership choices.
		// Ordinary functions retain the existing structural flow policy.
		if (constant != null && (function is CfgConstructor || closed_substitution)) {
			return new CfgBranch (span, constant.literal == BooleanLiteral.TRUE ? yes : no);
		}
		return new CfgConditionalBranch (span, condition, yes, no);
	}

	private bool has_active_cleanup() {
		foreach (var scope in cleanup_scopes) {
			if (scope.acquired.length > 0 || scope.exception_owner != null || scope.text_loans.length != 0) {
				return true;
			}
		}
		return false;
	}

	private void emit_cleanups(int retained_depth, SourceSpan span) throws CfgError {
		for (int s = cleanup_scopes.length - 1; s >= retained_depth; s--) {
			if (cleanup_scopes[s].text_loans.length != 0) {
				var loans = new GenericArray<Object> ();
				foreach (var local in cleanup_scopes[s].text_loans) {
					loans.add (local);
				}
				var authority = new Astra.Text.TextLoanIntent (loans);
				current.text_exits.add (authority);
				foreach (var local in cleanup_scopes[s].text_loans) {
					current.instructions.add (new CfgTextLoanEnd (span, local, authority));
				}
			}
			if (cleanup_scopes[s].inspection != null) {
				current.instructions.add (new CfgEnumEndInspection (span, cleanup_scopes[s].inspection));
			}
			var acquired = cleanup_scopes[s].acquired;
			for (int i = acquired.length - 1; i >= 0; i--) {
				var boundary = acquired[i] as CfgLocalPlace;
				if (boundary != null) {
					emit_boundary_record_cleanup (boundary, span);
					continue;
				}
				var action = (CoreCleanupAction) acquired[i];
				if (action.kind == CleanupActionKind.EXECUTOR_END) {
					current.instructions.add (new CfgExecutorEnd (span, locals.lookup (action.task)));
					continue;
				}
				if (action.kind == CleanupActionKind.TASK_END) {
					current.instructions.add (new CfgTaskEnd (span, locals.lookup (action.task)));
					continue;
				}
				if (action.kind == CleanupActionKind.ENUM_DESTROY) {
					current.instructions.add (new CfgEnumDrop (span, enum_locals.lookup (action.enumeration)));
					continue;
				}
				if (action.kind == CleanupActionKind.OBJECT_DEINIT) {
					var storage = object_storage.lookup (action.storage);
					current.instructions.add (new CfgLifecycleCallInstruction (span, (CfgDestructor) callees.lookup (action.storage.destructor), storage, new GenericArray<CfgValue> ()));
					continue;
				}
				var owner = action.owner;
				CfgPlace target = action.record_field == null ? find_place(owner.place) : find_place (action.record_field);
				var value = new CfgLoadValue (span, target);
				var cleanup = new CfgCleanupInstruction (span, value, cleanups.lookup (action.record_field == null ? owner.cleanup : action.record_field.field.owned_cleanup));
				if (action.record_field != null) {
					cleanup.record_owner = locals.lookup (owner.place);
					cleanup.record_final = action.record_final;
				}
				current.instructions.add (cleanup);
			}
			if (cleanup_scopes[s].exception_owner != null) {
				current.instructions.add (new CfgCleanupInstruction (span, new CfgLoadValue (span, cleanup_scopes[s].exception_owner), cleanup_scopes[s].exception_cleanup));
			}
		}
		if (retained_depth == 0 && destructor_epilogue != null) {
			foreach (var property in destructor_epilogue.lazy_cleanups) {
				current.instructions.add (new CfgLazyDrop (span, properties.lookup (property)));
			}
			foreach (var action in destructor_epilogue.field_cleanups) {
				var place = new CfgIndirectFieldPlace (action.span, new CfgReceiverValue (span, ((CfgDestructor) function).receiver), fields.lookup (action.field));
				if (action.field.semantic_type is OwnerSlotsType) {
					current.instructions.add (new CfgSlotsDrop (span, place));
				} else if (action.cleanup != null && action.cleanup.record_type != null) {
					current.instructions.add (new CfgRecordFieldDrop (span, place, struct_shape (place.semantic_type)));
				} else if (action.field.text_snapshot) {
					current.instructions.add (new CfgTextSnapshotDestroy (span, place));
				} else {
					current.instructions.add (new CfgCleanupInstruction (span, new CfgLoadValue (span, place), cleanups.lookup (action.cleanup)));
				}
			}
			var owner = destructor_epilogue.declaring_class;
			if (owner.parent_class != null && owner.parent_class.destructor != null) {
				var source_class = (CfgClass) structs.lookup (owner);
				var target_class = (CfgClass) structs.lookup (owner.parent_class);
				var target = (CfgDestructor) callees.lookup (owner.parent_class.destructor);
				var cast = new CfgClassUpcast (span, new CfgReceiverValue (span, ((CfgDestructor) function).receiver), source_class, target_class, target.receiver.contract);
				var evaluated = new CfgEvaluatedValue (span, target.receiver.contract);
				current.instructions.add (new CfgEvaluateInstruction (span, cast, evaluated));
				current.instructions.add (new CfgBaseLifecycleCall (span, target, new GenericArray<CfgValue> (), evaluated));
			}
		}
	}

	private CfgEvaluatedValue validate_object(CfgValue reference, SemanticType result_type) {
		var value = new CfgObjectValidateValue (reference.span, reference, result_type);
		var result = new CfgEvaluatedValue (reference.span, result_type);
		current.instructions.add (new CfgEvaluateInstruction (reference.span, value, result));
		return result;
	}

	private CfgPlace copy_leaf(CfgPlace aggregate, CoreStructLeafPath path) throws CfgError {
		CfgPlace result = aggregate;
		foreach (var field in path.fields) {
			var descriptor = fields.lookup (field);
			CfgFieldPlace? projection = null;
			foreach (var candidate in function.field_places) {
				if (candidate.aggregate == result && candidate.field == descriptor) {
					projection = candidate;
					break;
				}
			}
			result = projection ?? new CfgFieldPlace (aggregate.span, result, descriptor);
		}
		return result;
	}

	private void validate_copy_place(CfgPlace place) {
		if (place is CfgLocalPlace || (place is CfgFieldPlace && ((CfgFieldPlace) place).root_local () != null)) {
			return;
		}
		current.instructions.add (new CfgValidatePlace (place.span, place));
	}

	private void emit_boundary_record_cleanup(CfgLocalPlace owner, SourceSpan span) {
		for (int i = owner.record_order.length - 1; i >= 0; i--) {
			var field = (CfgFieldPlace) struct_leaf (owner, owner.record_order[i]);
			var cleanup = new CfgCleanupInstruction (span, new CfgLoadValue (span, field), field.field.owned_cleanup);
			cleanup.record_owner = owner;
			cleanup.record_final = i == 0;
			current.instructions.add (cleanup);
		}
	}

	private StructValueShape struct_shape(SemanticType type, bool borrowed = false) throws CfgError {
		if (borrowed) {
			var observed = borrowed_struct_shapes.lookup (type);
			if (observed != null) {
				return observed;
			}
			var storage = struct_shape (type);
			if (storage.mode != StructValueMode.MOVE_VALUE) {
				throw new CfgError.INVALID_CORE ("record observation requires its exact owning storage graph");
			}
			observed = new StructValueShape (storage.semantic_type, storage.leaves, StructValueMode.BORROW_VALUE);
			borrowed_struct_shapes.insert (type, observed);
			return observed;
		}
		var shape = struct_shapes.lookup (type);
		if (shape != null) {
			return shape;
		}
		if (!(type is StructType) || copy_structs.lookup (type) == null) {
			throw new CfgError.INVALID_CORE ("struct boundary requires concrete materialized StructType");
		}
		var leaves = new GenericArray<StructLeafPath> ();
		try {
			CopyabilityFields fields = (nested) => {
				var owner = copy_structs.lookup (nested);
				if (owner == null) {
					return null;
				}
				var result = new GenericArray<SemanticType> ();
				foreach (var field in owner.fields) {
					result.add (field.semantic_type);
				}
				return result;
			};
			bool moving = CopyabilityAuthority.of (type, fields) != Copyability.COPYABLE;
			foreach (var path in moving ? StructLeafOrder.enumerate_storage (type, fields) : StructLeafOrder.enumerate (type, fields)) {
				leaves.add (path);
			}
			shape = new StructValueShape ((StructType) type, leaves, moving ? StructValueMode.MOVE_VALUE : StructValueMode.COPY_VALUE);
		} catch (StructLeafError error) {
			throw new CfgError.INVALID_CORE ("struct boundary leaves: %s", error.message);
		}
		struct_shapes.insert (type, shape);
		return shape;
	}

	private CfgPlace struct_leaf(CfgPlace aggregate, StructLeafPath path) {
		CfgPlace result = aggregate;
		for (int d = 0; d < path.depth; d++) {
			int ordinal = path.field_ordinal (d);
			var descriptor = structs.lookup (copy_structs.lookup (result.semantic_type)).fields[ordinal];
			CfgFieldPlace? projection = null;
			foreach (var candidate in function.field_places) {
				if (candidate.aggregate == result && candidate.field == descriptor) {
					projection = candidate;
					break;
				}
			}
			result = projection ?? new CfgFieldPlace (aggregate.span, result, descriptor);
		}
		return result;
	}

	private CfgEnumSlot reserve_enum_slot(SourceSpan span, EnumDefinition definition, EnumInstanceIdentity? instance = null) {
		var slot = new CfgEnumSlot (span, definition, function.enum_slots.length, null, instance);
		function.enum_slots.add (slot);
		return slot;
	}

	private bool enum_owns(EnumDefinition definition) {
		return EnumValueAuthority.owns (definition, (type) => enum_definitions.lookup (type));
	}

	private void commit_enum(CfgEnumSlot slot) {
		if (slot.reservation_source != null) {
			current.instructions.add (new CfgEnumCommit (slot.span, slot));
		}
	}

	private CfgTaskWait lower_task_wait(CoreTaskAwait awaited) throws CfgError {
		CfgValue? bridge = null;
		if (awaited.bridge_executor != null) {
			var load = awaited.bridge_executor as CoreLoadValue;
			if (load != null && load.source is CoreLocalPlace) {
				bridge = new CfgLoadValue (load.span, locals.lookup ((CoreLocalPlace) load.source));
			} else {
				bridge = build_value (awaited.bridge_executor);
			}
		}
		var child = build_value (awaited.child);
		var operation = new CfgTaskWait (awaited.span, awaited.body, child, exception_root_type, awaited.discard, bridge);
		current.instructions.add (operation);
		var success = reserve_block (awaited.span, function.blocks);
		var failure = reserve_block (awaited.span, function.blocks);
		var condition = new CfgBinaryValue (awaited.span, exception_bool_type, BinaryOperator.EQUAL, operation.exception, new CfgNullPointerValue (awaited.span, exception_root_type));
		current.complete (awaited.span, new CfgConditionalBranch (awaited.span, condition, success, failure));
		current = failure;
		if (awaited.discard) {
			current.complete (awaited.span, new CfgExceptionUnreachable (awaited.span, operation.exception));
		} else {
			route_exception (awaited.span, operation.exception);
		}
		current = success;
		return operation;
	}

	private CfgEnumSlot lower_enum_producer(CoreEnumProducer producer) throws CfgError {
		if (producer is CoreEnumAwait) {
			var wait = lower_task_wait (((CoreEnumAwait) producer).operation);
			var destination = reserve_enum_slot (producer.span, producer.definition, producer.instance);
			var loaded = new CfgTaskSuccess.for_enum (producer.span, wait, destination);
			wait.success = loaded;
			current.instructions.add (loaded);
			return destination;
		}
		if (producer is CoreAsyncRun) {
			var run = (CoreAsyncRun) producer;
			var status = build_value (run.operation);
			CfgAsyncOperation? operation = null;
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var candidate = instruction as CfgAsyncOperation;
					if (candidate != null && candidate.result == status) {
						operation = candidate;
					}
				}
			}
			if (operation == null) {
				throw new CfgError.INVALID_CORE ("run status lost exact consuming root operation");
			}
			var destination = reserve_enum_slot (producer.span, producer.definition, producer.instance);
			current.instructions.add (new CfgAsyncRunStatus (producer.span, operation, destination));
			return destination;
		}

		var call = producer as CoreEnumCallResult;
		if (call != null) {
			return lower_call (producer.span, call.target, call.arguments, call.receiver, null, false, null, producer.instance).enum_result;
		}
		var destination = reserve_enum_slot (producer.span, producer.definition, producer.instance);
		var snapshot = producer as CoreEnumSnapshot;
		if (snapshot != null) {
			var source = enum_locals.lookup (snapshot.source);
			if (snapshot.mode == EnumUse.MOVE) {
				destination.reservation_source = source;
			}
			if (snapshot.mode == EnumUse.INSPECT) {
				destination.inspection_root = source.inspection_root ?? source;
			}
			current.instructions.add (new CfgEnumCopy (producer.span, destination, source, true, snapshot.mode));
			return destination;
		}
		var construction = (CoreEnumConstruct) producer;
		var frame = new ArgumentFrame ();
		argument_frames.add (frame);
		var inputs = new GenericArray<CfgEnumFieldInput> ();
		foreach (var input in construction.fields) {
			var leaves = new GenericArray<CfgValue> ();
			CfgEnumSlot? sum = null;
			CfgEnumBufferCapture? buffer = null;
			CfgEnumScalarCapture? scalar_owner = null;
			CfgStructBoundaryMove? record_move = null;
			if (input.field.owns_buffer) {
				var value = (CoreEnumBufferValue) input.scalar;
				var cleanup = cleanups.lookup (value.cleanup);
				var source = value.source == null ? null : locals.lookup (value.source.place);
				if (source == null) {
					var incoming = build_value (value.producer);
					source = new CfgLocalPlace (input.span, input.span, "$staged-buffer", incoming.semantic_type, function.locals.length, false, cleanup);
					function.locals.add (source);
					current.instructions.add (new CfgInitialize (input.span, source, incoming, source));
				}
				buffer = new CfgEnumBufferCapture (input.span, cleanup, source, null, value.source == null);
				current.instructions.add (buffer);
				frame.staged.add (buffer);
			} else if (input.field.owns_scalar) {
				var value = (CoreEnumScalarValue) input.scalar;
				var captured = new CfgEvaluatedValue (input.span, input.field.semantic_type);
				scalar_owner = new CfgEnumScalarCapture (input.span, locals.lookup (value.source.place), cleanups.lookup (value.cleanup), captured);
				current.instructions.add (scalar_owner);
				frame.staged.add (scalar_owner);
				leaves.add (captured);
			} else if (input.sum != null) {
				sum = lower_enum_producer (input.sum);
				if (enum_owns (sum.definition) && sum.reservation_source == null) {
					frame.staged.add (sum);
				}
			} else if (input.record != null) {
				leaves = lower_struct_producer (input.record, StructResultUseKind.ENUM_PAYLOAD);
				if (input.field.owns_record) {
					var moves = record_argument_moves.lookup (leaves);
					if (moves == null || moves.length != 1) {
						throw new CfgError.INVALID_CORE ("owning enum record requires one exact named whole-record capture");
					}
					record_move = moves[0];
				}
			} else {
				var value = build_value (input.scalar);
				var captured = new CfgEvaluatedValue (input.span, value.semantic_type);
				current.instructions.add (new CfgEvaluateInstruction (input.span, value, captured));
				leaves.add (captured);
			}
			inputs.add (new CfgEnumFieldInput (input.span, input.field, leaves, sum, buffer, scalar_owner, record_move));
		}
		foreach (var input in inputs) {
			if (input.sum != null) {
				commit_enum (input.sum);
			}
		}
		var constructed = new CfgEnumConstruct (producer.span, destination, construction.variant, inputs);
		foreach (var input in inputs) {
			if (input.record_move != null) {
				input.record_move.consumer = constructed;
				current.instructions.add (input.record_move);
			}
		}
		current.instructions.add (constructed);
		foreach (var input in inputs) {
			if (input.buffer != null && input.buffer.fresh_staged) {
				current.instructions.add (new CfgCleanupInstruction (input.span, new CfgLoadValue (input.span, input.buffer.source), input.buffer.cleanup));
			}
		}
		argument_frames.remove_index (argument_frames.length - 1);
		return destination;
	}

	private void lower_enum_match(CoreEnumMatch match) throws CfgError {
		var source = lower_enum_producer (match.scrutinee);
		commit_enum (source);
		var targets = new GenericArray<CfgBlock> ();
		foreach (var arm in match.arms) {
			targets.add (reserve_block (arm.span, function.blocks));
		}
		var invalid = reserve_block (match.span, function.blocks);
		invalid.complete (match.span, new CfgEnumInvalidTag (match.span));
		var join = reserve_block (match.span, function.blocks);
		var cases = new GenericArray<CfgEnumCase> ();
		for (uint v = 0; v < source.definition.variant_count; v++) {
			var variant = source.definition.variant (v);
			CfgBlock? target = null;
			for (uint a = 0; a < match.arms.length; a++) {
				if (match.arms[a].variant == variant || match.arms[a].variant == null) {
					target = targets[a];
					break;
				}
			}
			cases.add (new CfgEnumCase (variant, target));
		}
		current.complete (match.span, new CfgEnumDispatch (match.span, source, cases, invalid));
		for (uint a = 0; a < match.arms.length; a++) {
			var arm = match.arms[a];
			var entry = targets[a];
			var acquisitions = new GenericArray<CoreCleanupAction> ();
			var retained = new GenericArray<EnumField> ();
			foreach (var binding in arm.bindings) {
				if (binding.field.owns_buffer && source.inspection_root == null) {
					entry.instructions.add (new CfgEnumExtractBuffer (binding.span, source, binding.field, locals.lookup (binding.destination), binding.contract));
					acquisitions.add (new CoreCleanupAction.for_owner (binding.acquisition));
					retained.add (binding.field);
				} else if (binding.field.owns_scalar && source.inspection_root == null) {
					entry.instructions.add (new CfgEnumExtractScalar (binding.span, source, binding.field, locals.lookup (binding.destination), binding.contract));
					acquisitions.add (new CoreCleanupAction.for_owner (binding.acquisition));
					retained.add (binding.field);
				} else if (binding.field.owns_record && source.inspection_root == null) {
					var destination = locals.lookup (binding.destination);
					var shape = struct_shape (binding.field.semantic_type);
					var extraction = new CfgEnumExtractRecord (binding.span, source, binding.field, destination, binding.contract, shape);
					entry.instructions.add (extraction);
					entry.instructions.add (new CfgStructResultConsume (binding.span, extraction.results, StructResultUseKind.INITIALIZE, destination));
					var leaves = new GenericArray<CfgValue> ();
					foreach (var leaf in extraction.results.leaves) {
						leaves.add (leaf);
					}
					entry.instructions.add (new CfgStructBoundaryAcquire (binding.span, destination, shape, leaves, null, extraction.results));
					bool first = true;
					foreach (var field in binding.acquisition.record_fields) {
						var action = new CoreCleanupAction.for_owner (binding.acquisition);
						action.record_field = field;
						action.record_final = first;
						first = false;
						acquisitions.add (action);
					}
					retained.add (binding.field);
				} else if (binding.field.semantic_type is EnumType) {
					if (source.inspection_root != null && enum_owns (enum_locals.lookup (binding.destination).definition)) {
						enum_locals.lookup (binding.destination).inspection_root = source.inspection_root;
					} else if (enum_owns (enum_locals.lookup (binding.destination).definition)) {
						acquisitions.add (new CoreCleanupAction.for_enum (binding.destination));
						retained.add (binding.field);
					}
					entry.instructions.add (new CfgEnumExtractSum (binding.span, source, binding.field, enum_locals.lookup (binding.destination), binding.contract));
				} else if (binding.field.semantic_type.is_struct_storage ()) {
					foreach (var path in struct_shape (binding.field.semantic_type).leaves) {
						var value = new CfgEnumPayloadValue (binding.span, source, binding.field, binding.contract, path);
						var captured = new CfgEvaluatedValue (binding.span, path.semantic_type);
						entry.instructions.add (new CfgEvaluateInstruction (binding.span, value, captured));
						entry.instructions.add (new CfgInitialize (binding.span, struct_leaf (locals.lookup (binding.destination), path), captured));
					}
				} else {
					var value = new CfgEnumPayloadValue (binding.span, source, binding.field, binding.contract);
					var captured = new CfgEvaluatedValue (binding.span, binding.field.semantic_type);
					entry.instructions.add (new CfgEvaluateInstruction (binding.span, value, captured));
					entry.instructions.add (new CfgInitialize (binding.span, locals.lookup (binding.destination), captured));
				}
			}
			if (enum_owns (source.definition) && source.inspection_root == null) {
				entry.instructions.add (new CfgEnumFinishArm (arm.span, source, arm.variant, retained));
			}
			lower_block (arm.body, entry, new CfgBranch (arm.span, join), function.blocks, acquisitions, source.inspection_root == null ? null : source);
		}
		current = join;
	}

	private void lower_struct_parameter(CoreAcquireStructParameter acquisition) {
		var incoming = struct_parameter_leaves.lookup (acquisition.parameter);
		var local = locals.lookup (acquisition.destination);
		if (local.struct_parameter.shape.mode == StructValueMode.BORROW_VALUE) {
			var leaves = new GenericArray<CfgValue> ();
			foreach (var parameter in incoming) {
				leaves.add (new CfgParameterValue (acquisition.span, parameter));
			}
			// Intern all declaration projections even when the body reads only
			// a copied leaf. Verification checks the complete incoming binding.
			foreach (var leaf in local.struct_parameter.shape.leaves) {
				struct_leaf (local, leaf);
			}
			current.instructions.add (new CfgStructParameterBorrow (acquisition.span, local, local.struct_parameter, leaves));
			return;
		}
		if (local.struct_parameter.shape.mode == StructValueMode.MOVE_VALUE) {
			var leaves = new GenericArray<CfgValue> ();
			foreach (var parameter in incoming) {
				leaves.add (new CfgParameterValue (acquisition.span, parameter));
			}
			current.instructions.add (new CfgStructBoundaryAcquire (acquisition.span, local, local.struct_parameter.shape, leaves, local.struct_parameter));
			cleanup_scopes[cleanup_scopes.length - 1].acquire_parameter (local, local.struct_parameter.source_ordinal);
			return;
		}
		for (int i = 0; i < incoming.length; i++) {
			current.instructions.add (new CfgInitialize (acquisition.span, struct_leaf (local, local.struct_parameter.shape.leaves[i]), new CfgParameterValue (acquisition.span, incoming[i])));
		}
	}

	private void projection_fields(CfgPlace aggregate) {
		var definition = structs.lookup (copy_structs.lookup (aggregate.semantic_type));
		foreach (var field in definition.fields) {
			var place = new CfgFieldPlace (aggregate.span, aggregate, field);
			function.field_places.add (place);
			if (field.semantic_type is StructType) {
				projection_fields (place);
			}
		}
	}

	private GenericArray<CfgValue> lower_struct_observation(CoreStructProducer source, StructLeafPath path) throws CfgError {
		var complete = lower_struct_producer (source, StructResultUseKind.OBSERVE);
		var shape = struct_shape (source.semantic_type, true);
		var selected = new GenericArray<CfgValue> ();
		for (int i = 0; i < shape.leaves.length; i++) {
			var leaf = shape.leaves[i];
			bool contains = leaf.depth >= path.depth;
			for (int d = 0; contains && d < path.depth; d++) {
				contains = leaf.field_ordinal (d) == path.field_ordinal (d);
			}
			if (contains) {
				selected.add (complete[i]);
			}
		}
		if (selected.length == 0 || (!path.semantic_type.is_struct_storage () && selected.length != 1)) {
			throw new CfgError.INVALID_CORE ("record observation lost its exact nonempty declared field selection");
		}
		var group = record_result_groups.lookup (complete);
		if (group != null) {
			record_result_groups.insert (selected, group);
		}
		return selected;
	}

	private CfgPlace lower_struct_projection(CoreStructProducer source, StructLeafPath path) throws CfgError {
		var storage = new CfgLocalPlace (source.span, source.span, "$record-projection", source.semantic_type, function.locals.length);
		function.locals.add (storage);
		projection_fields (storage);
		var leaves = lower_struct_producer (source, StructResultUseKind.INITIALIZE, storage);
		var shape = struct_shape (source.semantic_type);
		for (int i = 0; i < leaves.length; i++) {
			current.instructions.add (new CfgInitialize (source.span, struct_leaf (storage, shape.leaves[i]), leaves[i]));
		}
		return struct_leaf (storage, path);
	}

	private GenericArray<CfgValue> lower_struct_producer(CoreStructProducer producer, StructResultUseKind use_kind, CfgPlace? destination = null) throws CfgError {
		if (producer is CoreStructInvocationResult) {
			var call = build_value (((CoreStructInvocationResult) producer).invocation);
			var code = call as CfgFunctionValueCall;
			var closure = call as CfgClosureCall;
			if (code == null && closure == null) {
				throw new CfgError.INVALID_CORE ("record invocation requires its exact indirect code node");
			}
			var arguments = code == null ? closure.arguments : code.arguments;
			var group = new CfgStructCallResults (producer.span, struct_shape (producer.semantic_type));
			CfgCheckedClosureInvoke? checked_call = null;
			if (closure != null && ((ClosureHandleType) closure.callee.semantic_type).throws_type != null) {
				checked_call = new CfgCheckedClosureInvoke (producer.span, closure, exception_root_type);
				append_indirect_invocation (checked_call, arguments);
				var success = reserve_block (producer.span, function.blocks);
				var failure = reserve_block (producer.span, function.blocks);
				var condition = new CfgBinaryValue (producer.span, exception_bool_type, BinaryOperator.EQUAL, checked_call.result, new CfgNullPointerValue (producer.span, exception_root_type));
				current.complete (producer.span, new CfgConditionalBranch (producer.span, condition, success, failure));
				current = failure;
				route_exception (producer.span, checked_call.result);
				current = success;
			}
			var invocation = new CfgStructInvoke (producer.span, call, group, checked_call);
			if (checked_call == null) {
				append_indirect_invocation (invocation, arguments);
			} else {
				current.instructions.add (invocation);
			}
			current.instructions.add (new CfgStructResultConsume (producer.span, group, use_kind, destination));
			var leaves = new GenericArray<CfgValue> ();
			foreach (var leaf in group.leaves) {
				leaves.add (leaf);
			}
			record_result_groups.insert (leaves, group);
			return leaves;
		}
		if (producer is CoreStructProjectionProducer) {
			var projection = (CoreStructProjectionProducer) producer;
			if (projection.source.contract.mode == StructValueMode.BORROW_VALUE) {
				return lower_struct_observation (projection.source, projection.path);
			}
			var selected = lower_struct_projection (projection.source, projection.path);
			var values = new GenericArray<CfgValue> ();
			foreach (var leaf in struct_shape (producer.semantic_type).leaves) {
				var captured = new CfgEvaluatedValue (producer.span, leaf.semantic_type);
				current.instructions.add (new CfgEvaluateInstruction (producer.span, new CfgLoadValue (producer.span, struct_leaf (selected, leaf)), captured));
				values.add (captured);
			}
			return values;
		}
		if (producer is CoreSlotsRecordRead) {
			var read = (CoreSlotsRecordRead) producer;
			var store = (CfgIndirectFieldPlace) find_place (read.store);
			var index = capture_before_transfer (build_value (read.index));
			var results = new CfgStructCallResults (producer.span, struct_shape (producer.semantic_type));
			current.instructions.add (new CfgSlotsRecordRead (producer.span, store, index, read.remove, results));
			current.instructions.add (new CfgStructResultConsume (producer.span, results, use_kind, destination));
			var values = new GenericArray<CfgValue> ();
			foreach (var leaf in results.leaves) {
				values.add (leaf);
			}
			record_result_groups.insert (values, results);
			return values;
		}

		var leaves = new GenericArray<CfgValue> ();
		var moved = producer as CoreStructMoveProducer;
		if (moved != null) {
			var source = locals.lookup (moved.source.place);
			var shape = struct_shape (producer.semantic_type);
			foreach (var path in shape.leaves) {
				var value = new CfgEvaluatedValue (producer.span, path.semantic_type);
				var field = (CfgFieldPlace) struct_leaf (source, path);
				if (path.semantic_type is SliceType) {
					current.instructions.add (new CfgRecordBufferCapture (producer.span, field, value));
				} else {
					current.instructions.add (new CfgEvaluateInstruction (producer.span, new CfgLoadValue (producer.span, field), value));
				}
				leaves.add (value);
			}
			var moves = new GenericArray<CfgStructBoundaryMove> ();
			moves.add (new CfgStructBoundaryMove (producer.span, source, shape, leaves, use_kind));
			record_argument_moves.insert (leaves, moves);
			return leaves;
		}
		if (producer is CoreStructAwait) {
			var wait = lower_task_wait (((CoreStructAwait) producer).operation);
			var loaded = new CfgTaskSuccess.for_record (producer.span, wait, struct_shape (producer.semantic_type));
			wait.success = loaded;
			current.instructions.add (loaded);
			current.instructions.add (new CfgStructResultConsume (producer.span, loaded.struct_result, use_kind, destination));
			foreach (var leaf in loaded.struct_result.leaves) {
				leaves.add (leaf);
			}
			record_result_groups.insert (leaves, loaded.struct_result);
			return leaves;
		}
		var observation = producer as CoreStructBorrowSnapshot;
		if (observation != null) {
			var source = find_place (observation.source);
			validate_copy_place (source);
			foreach (var path in struct_shape (producer.semantic_type, true).leaves) {
				var value = new CfgEvaluatedValue (producer.span, path.semantic_type);
				var field = (CfgFieldPlace) struct_leaf (source, path);
				if (path.semantic_type is SliceType) {
					current.instructions.add (new CfgRecordBufferCapture (producer.span, field, value));
				} else {
					current.instructions.add (new CfgEvaluateInstruction (producer.span, new CfgLoadValue (producer.span, field), value));
				}
				leaves.add (value);
			}
			return leaves;
		}
		var snapshot = producer as CoreStructSnapshot;
		if (snapshot != null) {
			var source = find_place (snapshot.source);
			validate_copy_place (source);
			foreach (var path in struct_shape (producer.semantic_type).leaves) {
				var value = new CfgEvaluatedValue (producer.span, path.semantic_type);
				current.instructions.add (new CfgEvaluateInstruction (producer.span, new CfgLoadValue (producer.span, struct_leaf (source, path)), value));
				leaves.add (value);
			}
		} else {
			var foreign_call = producer as CoreCStructCallResult;
			if (foreign_call != null) {
				var result = lower_c_call (producer.span, foreign_call.target, foreign_call.arguments).struct_result;
				current.instructions.add (new CfgStructResultConsume (producer.span, result, use_kind, destination));
				foreach (var leaf in result.leaves) {
					leaves.add (leaf);
				}
				return leaves;
			}
			var call = (CoreStructCallResult) producer;
			var result = lower_call (producer.span, call.target, call.arguments, call.receiver).struct_result;
			current.instructions.add (new CfgStructResultConsume (producer.span, result, use_kind, destination));
			foreach (var leaf in result.leaves) {
				leaves.add (leaf);
			}
			record_result_groups.insert (leaves, result);
		}
		return leaves;
	}

	private void lower_struct_result_store(CoreStructResultStore store) throws CfgError {
		var destination = find_place (store.destination);
		validate_copy_place (destination);
		var leaves = lower_struct_producer (store.producer, store.initializes_destination ? StructResultUseKind.INITIALIZE : StructResultUseKind.ASSIGN, destination);
		var shape = struct_shape (store.producer.semantic_type);
		if (shape.mode == StructValueMode.MOVE_VALUE && destination is CfgIndirectFieldPlace) {
			var commit = new CfgRecordFieldCommit (store.span, (CfgIndirectFieldPlace) destination, shape,
				leaves, store.initializes_destination, record_result_groups.lookup (leaves));
			var moves = record_argument_moves.lookup (leaves);
			if (moves != null) {
				if (moves.length != 1 || commit.results != null) {
					throw new CfgError.INVALID_CORE ("record field requires one complete ownership producer");
				}
				commit.record_move = moves[0];
				moves[0].consumer = commit;
				current.instructions.add (moves[0]);
			}
			current.instructions.add (commit);
			return;
		}
		if (shape.mode == StructValueMode.MOVE_VALUE) {
			if (!store.initializes_destination || !(destination is CfgLocalPlace)) {
				throw new CfgError.INVALID_CORE ("record MOVE_VALUE requires fresh local storage");
			}
			current.instructions.add (new CfgStructBoundaryAcquire (store.span, (CfgLocalPlace) destination, shape, leaves, null, record_result_groups.lookup (leaves)));
			cleanup_scopes[cleanup_scopes.length - 1].acquired.add (destination);
			return;
		}
		for (int i = 0; i < leaves.length; i++) {
			var target = struct_leaf (destination, shape.leaves[i]);
			current.instructions.add (store.initializes_destination ? (CfgInstruction) new CfgInitialize (store.span, target, leaves[i]) : new CfgStore (store.span, target, leaves[i]));
		}
	}

	private void lower_struct_copy(CoreStructCopy copy) throws CfgError {
		// Stabilize and validate both roots once, destination first. Merely
		// copying direct local storage never requests an address.
		var destination = find_place (copy.destination);
		validate_copy_place (destination);
		var source = find_place (copy.source);
		validate_copy_place (source);
		GenericArray<CoreStructLeafPath> leaves;
		try {
			leaves = CoreStructLeaves.enumerate (copy_structs.lookup (copy.semantic_type), (type) => copy_structs.lookup (type));
		} catch (CoreError error) {
			throw new CfgError.INVALID_CORE ("invalid struct copy leaves: %s", error.message);
		}
		var snapshots = new GenericArray<CfgEvaluatedValue> ();
		foreach (var leaf in leaves) {
			var load = new CfgLoadValue (copy.span, copy_leaf (source, leaf));
			var snapshot = new CfgEvaluatedValue (copy.span, leaf.semantic_type);
			current.instructions.add (new CfgEvaluateInstruction (copy.span, load, snapshot));
			snapshots.add (snapshot);
		}
		// No destination write exists until every source leaf has been captured.
		for (int i = 0; i < leaves.length; i++) {
			var target = copy_leaf (destination, leaves[i]);
			current.instructions.add (copy.initializes_destination ? (CfgInstruction) new CfgInitialize (copy.span, target, snapshots[i]) : new CfgStore (copy.span, target, snapshots[i]));
		}
	}

	private void lower_array_fields(CfgPlace target, GenericArray<CoreStatement> initializers, GenericArray<CfgPlace> targets, GenericArray<CfgValue> values) throws CfgError {
		foreach (var child in initializers) {
			var nested = child as CoreStructInitialize;
			var leaf = child as CoreInitialize;
			var field = (CoreFieldPlace) (nested != null ? nested.target : leaf.target);
			var projection = new CfgFieldPlace (child.span, target, fields.lookup (field.field));
			if (nested != null && nested.producer != null) {
				var captured = lower_struct_producer (nested.producer, StructResultUseKind.INITIALIZE, projection);
				var shape = struct_shape (nested.producer.semantic_type);
				for (int i = 0; i < captured.length; i++) {
					targets.add (struct_leaf (projection, shape.leaves[i]));
					values.add (captured[i]);
				}
			} else if (nested != null) {
				lower_array_fields (projection, nested.initializers, targets, values);
			} else {
				var value = build_value (leaf.value);
				var captured = new CfgEvaluatedValue (leaf.span, leaf.value.semantic_type);
				current.instructions.add (new CfgEvaluateInstruction (leaf.span, value, captured));
				targets.add (projection);
				values.add (captured);
			}
		}
	}

	private void lower_record_acquire(CoreStructAcquire acquire) throws CfgError {
		var owner = locals.lookup (acquire.owner.place);
		var incoming = acquire.source == null ? build_value(acquire.producer) : new CfgLoadValue (acquire.span, locals.lookup (acquire.source.place));
		var capture = new CfgResourceCapture (acquire.span, incoming, acquire.source == null ? null : locals.lookup (acquire.source.place), cleanups.lookup (acquire.field.field.owned_cleanup));
		current.instructions.add (capture);
		current.instructions.add (new CfgInitialize (acquire.span, find_place (acquire.field), capture.result, owner));
		var action = new CoreCleanupAction.for_owner (acquire.owner);
		action.record_field = acquire.field;
		action.record_final = true;
		var scope = cleanup_scopes[cleanup_scopes.length - 1];
		foreach (var previous in scope.acquired) {
			var prior = previous as CoreCleanupAction;
			if (prior != null && prior.owner == acquire.owner) {
				action.record_final = false;
			}
		}
		scope.acquired.add (action);
	}

	private void lower_struct_initializer(CoreStructInitialize initializer) throws CfgError {
		if (initializer.producer != null) {
			var destination = find_place (initializer.target);
			var captured = lower_struct_producer (initializer.producer, StructResultUseKind.INITIALIZE, destination);
			var shape = struct_shape (initializer.producer.semantic_type);
			if (shape.mode == StructValueMode.MOVE_VALUE) {
				var owner = initializer.record_owner;
				if (owner == null || !(destination is CfgFieldPlace)) {
					throw new CfgError.INVALID_CORE ("owning subobject lost its exact root and projection");
				}
				var acquire = new CfgStructBoundaryAcquire (initializer.span, locals.lookup (owner.place), shape, captured, null, record_result_groups.lookup (captured), (CfgFieldPlace) destination);
				var moves = record_argument_moves.lookup (captured);
				if (moves != null) {
					if (moves.length != 1) {
						throw new CfgError.INVALID_CORE ("owning subobject requires one complete source move");
					}
					acquire.record_move = moves[0];
					moves[0].consumer = acquire;
					current.instructions.add (moves[0]);
				}
				current.instructions.add (acquire);
				var scope = cleanup_scopes[cleanup_scopes.length - 1];
				foreach (var field in owner.record_fields) {
					if (!acquire.contains ((CfgFieldPlace) find_place (field))) {
						continue;
					}
					var action = new CoreCleanupAction.for_owner (owner);
					action.record_field = field;
					action.record_final = true;
					foreach (var previous in scope.acquired) {
						var prior = previous as CoreCleanupAction;
						if (prior != null && prior.owner == owner) {
							action.record_final = false;
						}
					}
					scope.acquired.add (action);
				}
				return;
			}
			for (int i = 0; i < captured.length; i++) {
				current.instructions.add (new CfgInitialize (initializer.span, struct_leaf (destination, shape.leaves[i]), captured[i]));
			}
			return;
		}
		foreach (var child in initializer.initializers) {
			if (child is CoreStructInitialize) {
				lower_struct_initializer ((CoreStructInitialize) child);
			} else if (child is CoreStructAcquire) {
				lower_record_acquire ((CoreStructAcquire) child);
			} else {
				var leaf = (CoreInitialize) child;
				var value = build_value (leaf.value);
				current.instructions.add (new CfgInitialize (leaf.span, find_place (leaf.target), value));
			}
		}
	}

	private CfgPlace find_place(CorePlace source) throws CfgError {
		var slice = source as CoreSliceElementPlace;
		if (slice != null) {
			var view = capture_before_transfer (build_value (slice.slice));
			if (view is CfgBufferBorrowValue) {
				var captured = new CfgEvaluatedValue (view.span, view.semantic_type);
				current.instructions.add (new CfgEvaluateInstruction (view.span, view, captured));
				view = captured;
			}
			var index = build_value (slice.index);
			var checked_index = new CfgEvaluatedValue (index.span, index.semantic_type);
			current.instructions.add (new CfgSliceBoundsCheck (source.span, view, index, checked_index));
			return new CfgSliceElementPlace (source.span, view, slice.slice_type, checked_index, slice.provenance);
		}
		var array = source as CoreArrayElementPlace;
		if (array != null) {
			var index = build_value (array.index);
			var storage = locals.lookup (array.storage);
			if (!(index is CfgIntegerValue)) {
				var checked_index = new CfgEvaluatedValue (index.span, index.semantic_type);
				current.instructions.add (new CfgArrayBoundsCheck (source.span, storage, index, checked_index));
				index = checked_index;
			}
			return new CfgArrayElementPlace (source.span, storage, array.array_type, index, array.provenance);
		}
		var dereference = source as CoreDereferencePlace;
		if (dereference != null) {
			var pointer = build_value (dereference.pointer);
			var parameter = pointer as CfgParameterValue;
			if (parameter != null && parameter.parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && ForeignApiTypes.scalar_pointee (pointer.semantic_type) != null) {
				// Parameters cannot be rebound. Retain the exact noescape input
				// rather than creating an unrestricted pointer-copy temporary.
				return new CfgDereferencePlace (source.span, pointer, source.semantic_type, dereference.provenance);
			}
			// Snapshot the base now, before a store RHS can emit calls or branches.
			var evaluated = new CfgEvaluatedValue (pointer.span, pointer.semantic_type);
			current.instructions.add (new CfgEvaluateInstruction (pointer.span, pointer, evaluated));
			return new CfgDereferencePlace (source.span, evaluated, source.semantic_type, dereference.provenance);
		}
		var indirect = source as CoreIndirectFieldPlace;
		if (indirect != null) {
			var pointer = build_value (indirect.pointer);
			if (pointer.semantic_type is ClassType) {
				pointer = validate_object (pointer, pointer.semantic_type);
			}
			return new CfgIndirectFieldPlace (source.span, pointer, fields.lookup (indirect.field));
		}
		var projection = source as CoreFieldPlace;
		if (projection != null && !projections.contains (projection)) {
			return new CfgFieldPlace (source.span, find_place (projection.aggregate), fields.lookup (projection.field));
		}
		var local = source as CoreLocalPlace;
		CfgPlace? place = (source is CoreFieldPlace) ? (CfgPlace?) projections.lookup ((CoreFieldPlace) source) : local == null ? null : locals.lookup (local);
		if (place == null) {
			throw new CfgError.INVALID_CORE ("internal CFG construction error: local reference has no declaration in the containing function");
		}
		return place;
	}

	private static bool emits_ordered_evaluation(CoreValue value) {
		if (value is CoreScopedAllocator) {
			return true;
		}
		if (value is CoreStructProjectionValue) {
			return true;
		}
		if (value is CoreFunctionValueCall || value is CoreClosureCall || value is CoreClosureBind || value is CoreRetainedOperation) {
			return true;
		}
		if (value is CoreEnumArgument || value is CoreEnumEquality) {
			return true;
		}
		if (value is CoreStructArgument) {
			return true;
		}
		if (value is CoreTextLengthValue || value is CoreSliceFromArrayValue || value is CoreSliceLengthValue) {
			return true;
		}
		if (value is CoreVectorMemoryValue || value is CoreIntegerShiftValue || value is CoreVectorDotValue || value is CoreDspValue || value is CoreIntegerConversionValue || value is CoreNumericConversionValue || value is CoreFloatConversionValue || value is CoreVectorSplatValue || value is CoreVectorExtractValue || value is CoreVectorInsertValue || value is CoreVectorShuffleValue || value is CoreVectorSelectValue || value is CoreVectorConstructValue || value is CoreVectorReductionValue) {
			return true;
		}
		var load = value as CoreLoadValue;
		if (value is CoreOwnedBorrowValue || value is CoreAddressOfValue || (load != null && !load.source.is_promotable ())) {
			return true;
		}
		if (value is CoreCallValue || value is CoreCCallValue || value is CoreShortCircuitValue || value is CoreComparisonChain) {
			return true;
		}
		var prefix = value as CorePrefixValue;
		if (prefix != null) {
			return emits_ordered_evaluation (prefix.operand);
		}
		var binary = value as CoreBinaryValue;
		return binary != null && (emits_ordered_evaluation (binary.left) || emits_ordered_evaluation (binary.right));
	}

	private static bool requires_ordered_evaluation(CfgValue value) {
		if (value is CfgTextLengthValue) {
			return requires_ordered_evaluation (((CfgTextLengthValue) value).receiver);
		}
		var load = value as CfgLoadValue;
		if (value is CfgAddressOfValue || (load != null && !load.source.is_promotable ())) {
			return true;
		}
		var prefix = value as CfgPrefixValue;
		if (prefix != null) {
			return requires_ordered_evaluation (prefix.operand);
		}
		var binary = value as CfgBinaryValue;
		return binary != null && (binary.operator_kind == BinaryOperator.DIVIDE || binary.operator_kind == BinaryOperator.REMAINDER || requires_ordered_evaluation (binary.left) || requires_ordered_evaluation (binary.right));
	}

	private CfgValue evaluate_before_effect(CfgValue value) {
		if (!requires_ordered_evaluation (value)) {
			return value;
		}
		var result = new CfgEvaluatedValue (value.span, value.semantic_type);
		current.instructions.add (new CfgEvaluateInstruction (value.span, value, result));
		return result;
	}

	private CfgTemporaryPlace exception_slot(SourceSpan span) {
		var slot = new CfgExceptionStorage (span, exception_root_type, function.temporaries.length);
		function.temporaries.add (slot);
		return slot;
	}

	private void route_exception(SourceSpan span, owned CfgValue exception) throws CfgError {
		for (int f = (int) argument_frames.length - 1; f >= 0; f--) {
			var staged = argument_frames[f].staged;
			for (int a = (int) staged.length - 1; a >= 0; a--) {
				var transfer = staged[a] as CfgPendingOwnedArgument;
				if (transfer != null) {
					transfer.exceptional_abort = true;
					current.instructions.add (new CfgOwnedArgumentAbort (span, transfer));
					if (transfer.fresh_staged) {
						current.instructions.add (new CfgOwnershipReleaseInstruction (span, transfer.source, transfer.cleanup));
						current.instructions.add (new CfgCleanupInstruction (span, new CfgLoadValue (span, transfer.source), transfer.cleanup));
					}
				} else if (staged[a] is CfgEnumBufferCapture) {
					var capture = (CfgEnumBufferCapture) staged[a];
					current.instructions.add (new CfgEnumBufferAbort (span, capture));
					if (capture.fresh_staged) {
						current.instructions.add (new CfgOwnershipReleaseInstruction (span, capture.source, capture.cleanup));
						current.instructions.add (new CfgCleanupInstruction (span, new CfgLoadValue (span, capture.source), capture.cleanup));
					}
				} else if (staged[a] is CfgEnumScalarCapture) {
					current.instructions.add (new CfgEnumScalarAbort (span, (CfgEnumScalarCapture) staged[a]));
				} else {
					current.instructions.add (new CfgEnumDrop (span, (CfgEnumSlot) staged[a]));
				}
			}
		}
		if (exception_targets.length != 0) {
			var target = exception_targets[exception_targets.length - 1];
			current.instructions.add (new CfgStore (span, target.slot, exception));
			emit_cleanups (target.retained_depth, span);
			current.complete (span, new CfgBranch (span, target.destination));
		} else {
			if (function.throws_type == null) {
				throw new CfgError.INVALID_CORE ("exception propagation lacks a checked throws bound");
			}
			exception = capture_before_transfer (exception);
			emit_cleanups (0, span);
			if (constructor_unwind != null && ConstructorContracts.admitted (constructor_unwind.declaring_class.foreign_export, constructor_unwind.declaring_class.allocation_policy, constructor_unwind.member_ordinal, constructor_unwind.throws_type)) {
				var abort = new CfgConstructorAbort (span, new CfgReceiverValue (span, function.implicit_receiver));
				foreach (var action in constructor_unwind.unwind_fields) {
					abort.fields.add (new CfgConstructorUnwindField (fields.lookup (action.field), action.cleanup == null ? null : cleanups.lookup (action.cleanup), action.cleanup != null && action.cleanup.record_type != null ? struct_shape (action.field.semantic_type) : null));
				}
				foreach (var property in constructor_unwind.unwind_lazy) {
					abort.lazy_properties.add (properties.lookup (property));
				}
				current.instructions.add (abort);
			}
			current.complete (span, new CfgExceptionReturn (span, exception));
		}
	}

	private void lower_try(CoreTry guarded) throws CfgError {
		bool exhaustive = false;
		foreach (var caught in guarded.catches) {
			exhaustive = exhaustive || caught.binding.semantic_type == exception_root_type;
		}
		var slot = exception_slot (guarded.span);
		var dispatch = reserve_block (guarded.span, function.blocks);
		var join = reserve_block (guarded.span, function.blocks);
		current.instructions.add (new CfgInitialize (guarded.span, slot, new CfgNullPointerValue (guarded.span, slot.semantic_type)));
		exception_targets.add (new ExceptionTarget (dispatch, slot, cleanup_scopes.length));
		lower_block (guarded.body, current, new CfgBranch (guarded.span, join), function.blocks);
		exception_targets.remove_index (exception_targets.length - 1);
		current = dispatch;
		foreach (var caught in guarded.catches) {
			var matched = reserve_block (caught.body.span, function.blocks);
			var next = reserve_block (caught.body.span, function.blocks);
			var exception = capture_before_transfer (new CfgLoadValue (guarded.span, slot));
			var type = (ClassType) caught.binding.semantic_type;
			var selection = new CfgExceptionMatch (guarded.span, exception_bool_type, exception, type);
			var borrow = new CfgCatchBorrow (caught.body.span, exception, type);
			function.handlers.add (new CfgExceptionHandler (current, matched, next, selection, borrow));
			current.complete (guarded.span, new CfgConditionalBranch (guarded.span, selection, matched, next));
			current = matched;
			current.instructions.add (new CfgInitialize (caught.body.span, locals.lookup (caught.binding), borrow));
			catch_owners.insert (caught.binding, slot);
			lower_block (caught.body, matched, new CfgBranch (caught.body.span, join), function.blocks, null, null, slot, cleanups.lookup (guarded.cleanup));
			catch_owners.remove (caught.binding);
			current = next;
		}
		var remaining = capture_before_transfer (new CfgLoadValue (guarded.span, slot));
		if (exhaustive || (function.throws_type == null && exception_targets.length == 0)) {
			current.complete (guarded.span, new CfgExceptionUnreachable (guarded.span, remaining));
		} else {
			current.instructions.add (new CfgStore (guarded.span, slot, new CfgNullPointerValue (guarded.span, slot.semantic_type)));
			route_exception (guarded.span, remaining);
		}
		current = join;
	}

	private CfgCallInstruction lower_call(SourceSpan span, CoreFunction? callee, GenericArray<CoreValue> values, CoreValue? receiver = null, CfgObjectStorage? storage = null, bool result_construction = false, CoreCallValue? producer = null, EnumInstanceIdentity? sum_instance = null, bool base_lifecycle = false, CoreValue? allocation_context = null) throws CfgError {
		var target = callee == null ? null : callees.lookup (callee);
		if (target == null) {
			throw new CfgError.INVALID_CORE ("internal CFG construction error: call target has no program-owned function mapping");
		}
		// Resolve the receiver before evaluating any explicit argument or move.
		var receiver_value = receiver == null ? null : build_value (receiver);
		// The source context is a named binding pinned against argument moves.
		// Keep its exact owner Place until allocation so SSA can record the
		// live-owner read, rather than losing origin in a scalar snapshot.
		var context_load = allocation_context as CoreLoadValue;
		CfgValue? context_value = null;
		if (allocation_context != null) {
			if (context_load != null && context_load.source is CoreLocalPlace) {
				context_value = new CfgLoadValue (context_load.span, find_place (context_load.source));
			} else {
				context_value = build_value (allocation_context);
			}
		}
		var groups = new GenericArray<StructBoundaryGroup> ();
		var arguments = lower_arguments (values, groups);
		var transfers = new GenericArray<CfgPendingOwnedArgument> ();
		foreach (var argument in arguments) {
			if (argument is CfgPendingOwnedArgument) {
				transfers.add ((CfgPendingOwnedArgument) argument);
			}
		}
		var result = target.return_type is EnumType || target.return_type.kind == TypeKind.VOID || target.struct_result != null ? null : new CfgCallResultValue (span, target.return_type);
		CfgCallInstruction call = base_lifecycle ? (CfgCallInstruction) new CfgBaseLifecycleCall (span, (CfgLifecycle) target, arguments, receiver_value) : storage == null ? (CfgCallInstruction) new CfgCallInstruction (span, target, arguments, result, receiver_value) : new CfgLifecycleCallInstruction (span, (CfgConstructor) target, storage, arguments, context_value);
		if (result_construction) {
			call = new CfgResultConstructionInstruction (span, (CfgConstructor) target, function.result_storage, arguments);
		}
		bool protected_call = receiver != null && call_context.overlaps (receiver.semantic_type);
		foreach (var argument in values) {
			protected_call |= call_context.overlaps (argument.semantic_type);
		}
		call.bind_readonly_context (protected_call);
		foreach (var transfer in transfers) {
			transfer.consumer = call;
		}
		foreach (var group in groups) {
			call.struct_arguments.add (group);
		}
		if (target.owned_cleanup != null && target.owned_cleanup.is_buffer) {
			call.buffer_result = new CfgBufferResults (span, target.owned_cleanup.buffer_shape, call.result);
		}
		if (target.return_type is EnumType) {
			call.bind_enum_result (reserve_enum_slot (span, enum_definitions.lookup ((EnumType) target.return_type), sum_instance));
		}
		if (target.struct_result != null) {
			call.struct_result = new CfgStructCallResults (span, target.struct_result);
		}
		if (producer != null) {
			call.candidate_storage = producer.candidate_storage == null ? null : object_storage.lookup (producer.candidate_storage);
			call.result_storage = producer.result_storage == null ? null : function.result_storage;
		}
		var record_moves = record_argument_moves.lookup (arguments);
		if (record_moves != null) {
			foreach (var move in record_moves) {
				move.consumer = call;
				call.record_moves.add (move);
				current.instructions.add (move);
			}
		}
		if (transfers.length > 0) {
			current.instructions.add (new CfgOwnedCallTransferCommit (span, call, transfers));
		}
		foreach (var argument in arguments) {
			if (argument is CfgEnumArgument) {
				commit_enum (((CfgEnumArgument) argument).source);
			}
		}
		if (target.throws_type != null) {
			call.exception_result = new CfgEvaluatedValue (span, exception_root_type);
		}
		current.instructions.add (call);
		if (call.exception_result != null) {
			var success = reserve_block (span, function.blocks);
			var failure = reserve_block (span, function.blocks);
			var exception = call.exception_result;
			var condition = new CfgBinaryValue (span, exception_bool_type, BinaryOperator.EQUAL, exception, new CfgNullPointerValue (span, exception_root_type));
			current.complete (span, new CfgConditionalBranch (span, condition, success, failure));
			current = failure;
			route_exception (span, exception);
			current = success;
			if (call.buffer_result != null || call.struct_result != null || call.enum_result != null) {
				current.instructions.add (new CfgGroupCallSuccess (span, call));
			} else if (call.result != null) {
				var loaded = new CfgCallSuccess (span, call);
				current.instructions.add (loaded);
				call.success_result = loaded.result;
			}
		}
		return call;
	}

	private CfgCCallInstruction lower_c_call(SourceSpan span, CoreCFunction? callee, GenericArray<CoreValue> values) throws CfgError {
		var target = callee == null ? null : c_callees.lookup (callee);
		if (target == null) {
			throw new CfgError.INVALID_CORE ("internal CFG construction error: call target has no program-owned function mapping");
		}
		var groups = new GenericArray<StructBoundaryGroup> ();
		var arguments = lower_arguments (values, groups);
		var result = target.return_type.is_struct_storage () || target.return_type.kind == TypeKind.VOID ? null : new CfgCallResultValue (span, target.return_type);
		var call = new CfgCCallInstruction (span, target, arguments, result);
		foreach (var group in groups) {
			call.struct_arguments.add (group);
		}
		if (target.return_type.is_struct_storage ()) {
			call.struct_result = new CfgStructCallResults (span, struct_shape (target.return_type));
		}
		current.instructions.add (call);
		return call;
	}

	private static bool contains_owned_transfer(CoreValue value) {
		if (value is CoreTextLengthValue) {
			return contains_owned_transfer (((CoreTextLengthValue) value).receiver);
		}
		if (value is CoreStructArgument) {
			var producer = ((CoreStructArgument) value).producer as CoreStructCallResult;
			if (producer != null) {
				foreach (var argument in producer.arguments) {
					if (contains_owned_transfer (argument)) {
						return true;
					}
				}
			}
			return false;
		}
		var construction = value as CoreSliceFromArrayValue;
		if (construction != null) {
			return (construction.start != null && contains_owned_transfer (construction.start)) || (construction.count != null && contains_owned_transfer (construction.count));
		}
		var length = value as CoreSliceLengthValue;
		if (length != null) {
			return contains_owned_transfer (length.slice);
		}
		var read = value as CoreLoadValue;
		var slice = read == null ? null : read.source as CoreSliceElementPlace;
		if (slice != null) {
			return contains_owned_transfer (slice.slice) || contains_owned_transfer (slice.index);
		}
		var load = value as CoreLoadValue;
		var array = load == null ? null : load.source as CoreArrayElementPlace;
		if (array != null) {
			return contains_owned_transfer (array.index);
		}
		var dot = value as CoreVectorDotValue;
		if (dot != null) {
			return (dot.accumulator != null && contains_owned_transfer (dot.accumulator)) || contains_owned_transfer (dot.first) || contains_owned_transfer (dot.second);
		}
		var dsp = value as CoreDspValue;
		if (dsp != null) {
			return contains_owned_transfer (dsp.first) || (dsp.second != null && contains_owned_transfer (dsp.second));
		}
		var shift = value as CoreIntegerShiftValue;
		if (shift != null) {
			return contains_owned_transfer (shift.operand) || contains_owned_transfer (shift.count);
		}
		var numeric_conversion = value as CoreNumericConversionValue;
		if (numeric_conversion != null) {
			return contains_owned_transfer (numeric_conversion.operand);
		}
		var floating_conversion = value as CoreFloatConversionValue;
		if (floating_conversion != null) {
			return contains_owned_transfer (floating_conversion.operand);
		}
		var conversion = value as CoreIntegerConversionValue;
		if (conversion != null) {
			return contains_owned_transfer (conversion.operand);
		}
		var splat = value as CoreVectorSplatValue;
		if (splat != null) {
			return contains_owned_transfer (splat.operand);
		}
		var extract = value as CoreVectorExtractValue;
		if (extract != null) {
			return contains_owned_transfer (extract.vector);
		}
		var insert = value as CoreVectorInsertValue;
		if (insert != null) {
			return contains_owned_transfer (insert.vector) || contains_owned_transfer (insert.replacement);
		}
		var shuffle = value as CoreVectorShuffleValue;
		if (shuffle != null) {
			return contains_owned_transfer (shuffle.vector);
		}
		if (value is CoreVectorMemoryValue) {
			var memory = (CoreVectorMemoryValue) value;
			return contains_owned_transfer (memory.view) || contains_owned_transfer (memory.offset) || (memory.stored != null && contains_owned_transfer (memory.stored));
		}
		var select = value as CoreVectorSelectValue;
		if (select != null) {
			return contains_owned_transfer (select.mask) || contains_owned_transfer (select.true_value) || contains_owned_transfer (select.false_value);
		}
		var vector = value as CoreVectorConstructValue;
		if (vector != null) {
			foreach (var lane in vector.lanes) {
				if (contains_owned_transfer (lane)) {
					return true;
				}
			}
		}
		var reduction = value as CoreVectorReductionValue;
		if (reduction != null) {
			return contains_owned_transfer (reduction.operand);
		}
		if (value is CoreOwnedArgumentValue) {
			return true;
		}
		var native = value as CoreCallValue;
		var foreign = value as CoreCCallValue;
		var arguments = native != null ? native.arguments : foreign == null ? null : foreign.arguments;
		if (arguments != null) {
			foreach (var argument in arguments) {
				if (contains_owned_transfer (argument)) {
					return true;
				}
			}
		}
		var prefix = value as CorePrefixValue;
		if (prefix != null) {
			return contains_owned_transfer (prefix.operand);
		}
		var binary = value as CoreBinaryValue;
		if (binary != null) {
			return contains_owned_transfer (binary.left) || contains_owned_transfer (binary.right);
		}
		if (value is CoreComparisonChain) {
			foreach (var operand in ((CoreComparisonChain) value).operands) {
				if (contains_owned_transfer (operand)) {
					return true;
				}
			}
		}
		var conditional = value as CoreShortCircuitValue;
		return conditional != null && (contains_owned_transfer (conditional.left) || contains_owned_transfer (conditional.right));
	}

	private CfgValue capture_before_transfer(CfgValue value) {
		// These values already have an exact evaluation event, or immutable
		// incoming pointer identity. Do not reinterpret a borrow as a raw read.
		var parameter = value as CfgParameterValue;
		if (value is CfgEvaluatedValue || value is CfgCallResultValue || value is CfgOwnedBorrowValue || (parameter != null && parameter.parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && !(value.semantic_type is SliceType) && !(value.semantic_type is ClassType))) {
			return value;
		}
		var result = new CfgEvaluatedValue (value.span, value.semantic_type);
		current.instructions.add (new CfgEvaluateInstruction (value.span, value, result));
		return result;
	}

	private GenericArray<CfgValue> lower_arguments(GenericArray<CoreValue> values, GenericArray<StructBoundaryGroup>? groups = null) throws CfgError {
		var frame = new ArgumentFrame ();
		argument_frames.add (frame);
		var record_moves = new GenericArray<CfgStructBoundaryMove> ();
		bool commits_owned_arguments = false;
		int last_transfer_argument = -1;
		for (int i = 0; i < values.length; i++) {
			if (values[i] is CoreOwnedArgumentValue) {
				commits_owned_arguments = true;
			}
			var record = values[i] as CoreStructArgument;
			if (record != null && record.producer.contract.mode == StructValueMode.MOVE_VALUE) {
				commits_owned_arguments = true;
			}
			if (contains_owned_transfer (values[i])) {
				last_transfer_argument = i;
			}
		}
		int last_effect_argument = -1;
		for (int i = values.length - 1; i >= 0; i--) {
			if (emits_ordered_evaluation (values[i])) {
				last_effect_argument = i;
				break;
			}
		}
		var arguments = new GenericArray<CfgValue> ();
		for (int i = 0; i < values.length; i++) {
			if (values[i] is CoreEnumArgument) {
				if (groups == null) {
					throw new CfgError.INVALID_CORE ("enum arguments cannot enter a foreign call");
				}
				var source = lower_enum_producer (((CoreEnumArgument) values[i]).producer);
				arguments.add (new CfgEnumArgument (values[i].span, source));
				if (enum_owns (source.definition) && source.reservation_source == null) {
					frame.staged.add (source);
				}
				continue;
			}
			if (values[i] is CoreStructArgument) {
				var producer = ((CoreStructArgument) values[i]).producer;
				if (groups == null) {
					throw new CfgError.INVALID_CORE ("struct arguments cannot enter a foreign call");
				}
				var shape = struct_shape (producer.semantic_type, producer.contract.mode == StructValueMode.BORROW_VALUE);
				var leaves = lower_struct_producer (producer, producer.contract.mode == StructValueMode.BORROW_VALUE ? StructResultUseKind.OBSERVE : StructResultUseKind.ARGUMENT);
				if (producer.contract.mode == StructValueMode.BORROW_VALUE) {
					var snapshot = producer as CoreStructBorrowSnapshot;
					var root = snapshot == null ? null : find_place (snapshot.source) as CfgLocalPlace;
					var result = record_result_groups.lookup (leaves);
					if (root != null) {
						groups.add (new CfgStructBorrowArgument (i, arguments.length, shape, root));
					} else if (result != null && result.shape.mode == StructValueMode.BORROW_VALUE) {
						groups.add (new CfgStructBorrowResultArgument (i, arguments.length, shape, result));
					} else {
						throw new CfgError.INVALID_CORE ("record argument loan requires its exact source binding or observed getter group");
					}
				} else {
					groups.add (new StructBoundaryGroup (i, arguments.length, shape));
				}
				var moves = record_argument_moves.lookup (leaves);
				if (producer.contract.mode == StructValueMode.MOVE_VALUE && moves == null) {
					throw new CfgError.INVALID_CORE ("inline MOVE_VALUE producer requires exception-safe argument staging");
				}
				if (moves != null) {
					foreach (var move in moves) {
						record_moves.add (move);
					}
				}
				foreach (var leaf in leaves) {
					arguments.add (leaf);
				}
				continue;
			}
			var argument = build_value (values[i]);
			// A shared payload projection is a pure loan of a guarded local or
			// parameter. Keep it attached to its exact borrowed call parameter;
			// capturing it as an unrelated evaluation would erase that authority.
			var shared_loan = argument as CfgSharedOperation;
			arguments.add (shared_loan != null && shared_loan.action == SharedAction.BORROW ? argument : commits_owned_arguments || i < last_transfer_argument ? capture_before_transfer (argument) : i < last_effect_argument ? evaluate_before_effect (argument) : argument);
		}
		argument_frames.remove_index (argument_frames.length - 1);
		if (record_moves.length != 0) {
			record_argument_moves.insert (arguments, record_moves);
		}
		return arguments;
	}

	private CfgValue lower_comparison_chain(CoreComparisonChain value) throws CfgError {
		var entry = reserve_block (value.span, function.blocks);
		current.complete (current.span, new CfgBranch (value.span, entry));
		current = entry;
		var temporary = new CfgTemporaryPlace (value.span, value.semantic_type, function.temporaries.length);
		function.temporaries.add (temporary);
		current.instructions.add (new CfgInitialize (value.span, temporary, new CfgBooleanValue (value.span, value.semantic_type, BooleanLiteral.FALSE)));
		var join = reserve_block (value.span, function.blocks);
		var left = capture_before_transfer (build_value (value.operands[0]));
		for (int i = 0; i < value.operators.length; i++) {
			var right = capture_before_transfer (build_value (value.operands[i + 1]));
			var condition = new CfgBinaryValue (value.span, value.semantic_type, value.operators[i], left, right);
			var next = reserve_block (value.operands[i + 1].span, function.blocks);
			current.complete (value.span, conditional_branch (value.span, condition, next, join));
			current = next;
			left = right;
		}
		current.instructions.add (new CfgStore (value.span, temporary, new CfgBooleanValue (value.span, value.semantic_type, BooleanLiteral.TRUE)));
		current.complete (value.span, new CfgBranch (value.span, join));
		current = join;
		return new CfgLoadValue (value.span, temporary);
	}

	private CfgValue lower_short_circuit(CoreShortCircuitValue value) throws CfgError {
		// Backedges/continue still target the enclosing while header, which
		// lies outside this temporary's initialization-validity region.
		var evaluation_entry = reserve_block (value.span, function.blocks);
		current.complete (current.span, new CfgBranch (value.span, evaluation_entry));
		current = evaluation_entry;
		var left = evaluate_before_effect (build_value (value.left));
		var temporary = new CfgTemporaryPlace (value.span, value.semantic_type, function.temporaries.length);
		function.temporaries.add (temporary);
		bool is_and = value.operator_kind == ShortCircuitOperator.AND;
		var initial = new CfgBooleanValue (value.span, value.semantic_type, is_and ? BooleanLiteral.FALSE : BooleanLiteral.TRUE);
		current.instructions.add (new CfgInitialize (value.span, temporary, initial));
		var right_block = reserve_block (value.right.span, function.blocks);
		var join = reserve_block (value.span, function.blocks);
		current.complete (current.span, conditional_branch (value.span, left, is_and ? right_block : join, is_and ? join : right_block));
		current = right_block;
		var right = build_value (value.right);
		current.instructions.add (new CfgStore (value.right.span, temporary, right));
		current.complete (current.span, new CfgBranch (value.span, join));
		current = join;
		return new CfgLoadValue (value.span, temporary);
	}

	private void append_indirect_invocation(CfgInstruction invocation, GenericArray<CfgValue> arguments) throws CfgError {
		var moves = record_argument_moves.lookup (arguments);
		if (moves != null) {
			var carried = CfgInvocationContracts.record_moves (invocation);
			if (carried == null) {
				throw new CfgError.INVALID_CORE ("indirect record transfer requires an exact invocation consumer");
			}
			foreach (var move in moves) {
				move.consumer = invocation;
				carried.add (move);
				current.instructions.add (move);
			}
		}
		var transfers = new GenericArray<CfgPendingOwnedArgument> ();
		foreach (var argument in arguments) {
			var transfer = argument as CfgPendingOwnedArgument;
			if (transfer == null) {
				continue;
			}
			transfer.consumer = invocation;
			transfers.add (transfer);
		}
		if (transfers.length != 0) {
			current.instructions.add (new CfgOwnedCallTransferCommit (invocation.span, invocation, transfers));
		}
		current.instructions.add (invocation);
	}

	private CfgValue build_value(CoreValue value) throws CfgError {
		if (value is CoreComparisonChain) {
			return lower_comparison_chain ((CoreComparisonChain) value);
		}
		if (value is CoreLazyObserve) {
			return new CfgLazyObserve (value.span, properties.lookup (((CoreLazyObserve) value).property_member));
		}
		if (value is CoreTaskBorrow) {
			var borrow = new CfgTaskBorrow (value.span, locals.lookup (((CoreTaskBorrow) value).source));
			current.instructions.add (borrow);
			return borrow.result;
		}
		if (value is CoreExecutorBorrow) {
			return new CfgLoadValue (value.span, locals.lookup (((CoreExecutorBorrow) value).source));
		}
		if (value is CoreAsyncOperation) {
			var source = (CoreAsyncOperation) value;
			var executor = source.executor == null ? null : build_value (source.executor);
			var task = source.task == null ? null : build_value (source.task);
			var argument = source.argument == null ? null : build_value (source.argument);
			var borrowed = source.task as CoreTaskBorrow;
			var moved = source.task as CoreTaskMove;
			var executor_borrow = source.executor as CoreExecutorBorrow;
			var operation = new CfgAsyncOperation (value.span, source.contract, executor, task, argument, exception_root_type, borrowed != null ? borrowed.source.ordinal : moved != null ? moved.source.ordinal : -1, executor_borrow == null ? -1 : executor_borrow.source.ordinal);
			current.instructions.add (operation);
			if (operation.exception != null) {
				var success = reserve_block (value.span, function.blocks);
				var failure = reserve_block (value.span, function.blocks);
				var condition = new CfgBinaryValue (value.span, exception_bool_type, BinaryOperator.EQUAL, operation.exception, new CfgNullPointerValue (value.span, exception_root_type));
				current.complete (value.span, new CfgConditionalBranch (value.span, condition, success, failure));
				current = failure;
				route_exception (value.span, operation.exception);
				current = success;
			}
			if (source.contract.kind == AsyncOperationKind.START) {
				current.instructions.add (new CfgTaskStarted (value.span, locals.lookup (borrowed.source), operation));
			}
			return operation.result == null ? (CfgValue) new CfgNullPointerValue (value.span, exception_root_type) : operation.result;
		}
		if (value is CoreTaskAwait) {
			var awaited = (CoreTaskAwait) value;
			var operation = lower_task_wait (awaited);
			if (value.semantic_type.kind == TypeKind.VOID) {
				return new CfgNullPointerValue (value.span, exception_root_type);
			}
			var loaded = new CfgTaskSuccess (value.span, operation, value.semantic_type, awaited.buffer_cleanup == null ? null : cleanups.lookup (awaited.buffer_cleanup));
			operation.success = loaded;
			current.instructions.add (loaded);
			return loaded.result;
		}
		if (value is CoreTaskCreate) {
			var creation = (CoreTaskCreate) value;
			var target = callees.lookup (creation.target);
			if (target == null || target.async_body == null || creation.semantic_type != target.async_body.task_type) {
				throw new CfgError.INVALID_CORE ("task factory lost exact body contract");
			}
			CfgValue? context = null;
			if (creation.allocation_context != null) {
				var load = creation.allocation_context as CoreLoadValue;
				if (load != null && load.source is CoreLocalPlace) {
					context = new CfgLoadValue (load.span, locals.lookup ((CoreLocalPlace) load.source));
				} else {
					context = build_value (creation.allocation_context);
				}
			}
			var groups = new GenericArray<StructBoundaryGroup> ();
			var arguments = lower_arguments (creation.arguments, groups);
			var result = new CfgCallResultValue (value.span, value.semantic_type);
			var instruction = new CfgTaskCreate (value.span, target, arguments, result, context, creation.checked_admission);
			foreach (var loan in creation.loans) {
				int ordinal = 0;
				for (int p = 0; p < loan.parameter_ordinal; p++) {
					var group = creation.arguments[p] as CoreStructArgument;
					ordinal += group == null ? 1 : (int) struct_shape (group.semantic_type).leaves.length;
				}
				instruction.loans.add (new CfgSuspensionLoan (loan.identity, ordinal, locals.lookup (loan.storage), arguments[ordinal]));
			}
			var transfers = new GenericArray<CfgPendingOwnedArgument> ();
			foreach (var argument in arguments) {
				var transfer = argument as CfgPendingOwnedArgument;
				if (transfer != null) {
					transfer.consumer = instruction;
					transfers.add (transfer);
				}
			}
			foreach (var group in groups) {
				instruction.struct_arguments.add (group);
			}
			var record_moves = record_argument_moves.lookup (arguments);
			if (record_moves != null) {
				foreach (var move in record_moves) {
					move.consumer = instruction;
					instruction.record_moves.add (move);
					current.instructions.add (move);
				}
			}
			if (transfers.length > 0) {
				current.instructions.add (new CfgOwnedCallTransferCommit (value.span, instruction, transfers));
			}
			foreach (var argument in arguments) {
				if (argument is CfgEnumArgument) {
					commit_enum (((CfgEnumArgument) argument).source);
				}
			}
			if (creation.checked_admission) {
				instruction.exception_result = new CfgEvaluatedValue (value.span, exception_root_type);
			}
			current.instructions.add (instruction);
			foreach (var transfer in transfers) {
				if (transfer.fresh_staged) {
					current.instructions.add (new CfgCleanupInstruction (value.span, new CfgLoadValue (value.span, transfer.source), transfer.cleanup));
				}
			}
			if (instruction.exception_result != null) {
				var success = reserve_block (value.span, function.blocks);
				var failure = reserve_block (value.span, function.blocks);
				var condition = new CfgBinaryValue (value.span, exception_bool_type, BinaryOperator.EQUAL, instruction.exception_result, new CfgNullPointerValue (value.span, exception_root_type));
				current.complete (value.span, new CfgConditionalBranch (value.span, condition, success, failure));
				current = failure;
				route_exception (value.span, instruction.exception_result);
				current = success;
			}
			return result;
		}
		if (value is CoreTaskMove) {
			var move = new CfgTaskMove (value.span, locals.lookup (((CoreTaskMove) value).source));
			current.instructions.add (move);
			return move.result;
		}
		var result = build_value_without_text_intent (value);
		if (value.text_loan_intent != null) {
			var owners = new GenericArray<Object> ();
			for (uint i = 0; i < value.text_loan_intent.count; i++) {
				var owner = value.text_loan_intent.owner (i);
				Object? mapped = null;
				if (owner is CoreLocalPlace) {
					mapped = locals.lookup ((CoreLocalPlace) owner);
				} else if (owner is CoreParameter) {
					mapped = parameters.lookup ((CoreParameter) owner);
				} else if (owner is CoreReceiver) {
					mapped = receivers.lookup ((CoreReceiver) owner);
				}
				if (mapped == null) {
					throw new CfgError.INVALID_CORE ("text loan backing lacks an exact predecessor mapping");
				}
				owners.add (mapped);
			}
			result.text_loan_intent = new Astra.Text.TextLoanIntent (owners);
		}
		return result;
	}

	private CfgValue build_value_without_text_intent(CoreValue value) throws CfgError {
		if (value is CoreStructProjectionValue) {
			var projection = (CoreStructProjectionValue) value;
			if (projection.source.contract.mode == StructValueMode.BORROW_VALUE) {
				var selected = lower_struct_observation (projection.source, projection.path);
				if (!(value.semantic_type is SliceType)) {
					return selected[0];
				}
				var group = record_result_groups.lookup (selected);
				if (group != null && selected[0] is CfgCallResultValue) {
					return new CfgRecordBufferView (value.span, group, (CfgCallResultValue) selected[0]);
				}
				var snapshot = projection.source as CoreStructBorrowSnapshot;
				var local = snapshot == null ? null : find_place (snapshot.source) as CfgLocalPlace;
				var captured = selected[0] as CfgEvaluatedValue;
				if (local == null || local.struct_parameter == null || local.struct_parameter.shape.mode != StructValueMode.BORROW_VALUE || captured == null) {
					throw new CfgError.INVALID_CORE ("record buffer projection lost its exact getter or incoming parameter observation");
				}
				return new CfgRecordParameterBufferView (value.span, (CfgFieldPlace) struct_leaf (local, projection.path), captured, local.struct_parameter);
			}
			return new CfgLoadValue (value.span, lower_struct_projection (projection.source, projection.path));
		}
		if (value is CoreRetainedOperation) {
			var operation = (CoreRetainedOperation) value;
			var callee = evaluate_before_effect (build_value (operation.callee));
			var arguments = new GenericArray<CfgValue> ();
			foreach (var argument in operation.arguments) {
				arguments.add (evaluate_before_effect (build_value (argument)));
			}
			return new CfgRetainedOperation (value.span, operation.action, callee, arguments, value.semantic_type);
		}
		if (value is CoreScopedAllocator) {
			var scoped = (CoreScopedAllocator) value;
			var result = new CfgScopedAllocator (value.span, (HandleType) value.semantic_type, scoped.loan, locals.lookup (scoped.backing), build_value (scoped.kind), build_value (scoped.slots), cleanups.lookup (scoped.cleanup));
			var evaluated = new CfgEvaluatedValue (value.span, value.semantic_type);
			current.instructions.add (new CfgEvaluateInstruction (value.span, result, evaluated));
			return evaluated;
		}
		if (value is CoreClosureBind) {
			var closure = (CoreClosureBind) value;
			var source = locals.lookup (closure.source.place);
			var capture = new CfgResourceCapture (value.span, new CfgLoadValue (value.span, source), source, source.cleanup);
			current.instructions.add (capture);
			var result = new CfgClosureBind (value.span, (ClosureHandleType) value.semantic_type, capture.result, callees.lookup (closure.target), cleanups.lookup (closure.cleanup), closure.actor_binding);
			var evaluated = new CfgEvaluatedValue (value.span, value.semantic_type);
			current.instructions.add (new CfgEvaluateInstruction (value.span, result, evaluated));
			return evaluated;
		}
		if (value is CoreClosureCall) {
			var call = (CoreClosureCall) value;
			var channels = new GenericArray<CfgParameter> ();
			foreach (var channel in call.channel_parameters) {
				var mapped = new CfgParameter (channel.span, channel.name_span, channel.name, channel.semantic_type, channel.ordinal, channel.pointer_contract);
				mapped.heap_object = channel.heap_object;
				parameters.insert (channel, mapped);
				channels.add (mapped);
			}
			var callee = evaluate_before_effect (build_value (call.callee));
			var groups = new GenericArray<StructBoundaryGroup> ();
			var arguments = lower_arguments (call.arguments, groups);
			var signature = (ClosureHandleType) call.callee.semantic_type;
			var invocation = new CfgClosureCall (value.span, signature, callee, arguments, call.owned_cleanup == null ? null : cleanups.lookup (call.owned_cleanup));
			foreach (var group in groups) {
				invocation.struct_arguments.add (group);
			}
			foreach (var channel in channels) {
				invocation.channel_parameters.add (channel);
			}
			if (invocation.semantic_type.is_struct_storage ()) {
				return invocation;
			}
			if (signature.throws_type == null) {
				if (channels.length == 0 && groups.length == 0 && invocation.owned_cleanup == null) {
					return invocation;
				}
				var captured = new CfgEvaluatedValue (value.span, invocation.semantic_type);
				append_indirect_invocation (new CfgEvaluateInstruction (value.span, invocation, captured), arguments);
				return captured;
			}
			var checked_call = new CfgCheckedClosureInvoke (value.span, invocation, exception_root_type);
			append_indirect_invocation (checked_call, arguments);
			var success = reserve_block (value.span, function.blocks);
			var failure = reserve_block (value.span, function.blocks);
			var condition = new CfgBinaryValue (value.span, exception_bool_type, BinaryOperator.EQUAL, checked_call.result, new CfgNullPointerValue (value.span, exception_root_type));
			current.complete (value.span, new CfgConditionalBranch (value.span, condition, success, failure));
			current = failure;
			route_exception (value.span, checked_call.result);
			current = success;
			var loaded = new CfgClosureCallSuccess (value.span, checked_call);
			current.instructions.add (loaded);
			return loaded.result;
		}
		if (value is CoreSharedOperation) {
			var operation = (CoreSharedOperation) value;
			CfgValue operand;
			if (operation.action == SharedAction.ACQUIRE) {
				var source = operation.source == null ? null : locals.lookup (operation.source.place);
				if (source == null || !source.cleanup.is_heap_object) {
					throw new CfgError.INVALID_CORE ("shared acquisition requires an exact incoming heap owner");
				}
				var capture = new CfgResourceCapture (value.span, new CfgLoadValue (value.span, source), source, source.cleanup);
				current.instructions.add (capture);
				operand = capture.result;
			} else {
				operand = build_value (operation.operand);
			} var result = new CfgSharedOperation (value.span, value.semantic_type, operation.action, operand, operation.cleanup == null ? null : cleanups.lookup (operation.cleanup), operation.borrower == null ? null : parameters.lookup (operation.borrower));
			if (operation.action == SharedAction.BORROW) {
				return result;
			}
			var evaluated = new CfgEvaluatedValue (value.span, value.semantic_type);
			current.instructions.add (new CfgEvaluateInstruction (value.span, result, evaluated));
			return evaluated;
		}
		if (value is CoreCallbackParameterView) {
			var view = (CoreCallbackParameterView) value;
			return new CfgCallbackParameterView (value.span, (CallbackType) value.semantic_type, parameters.lookup (view.source), parameters.lookup (view.parameter));
		}
		if (value is CoreFunctionAddress) {
			var address = (CoreFunctionAddress) value;
			return new CfgFunctionAddress (value.span, (FunctionValueType) value.semantic_type, callees.lookup (address.target));
		}
		if (value is CoreFunctionValueCall) {
			var call = (CoreFunctionValueCall) value;
			var channels = new GenericArray<CfgParameter> ();
			foreach (var channel in call.channel_parameters) {
				var mapped = new CfgParameter (channel.span, channel.name_span, channel.name, channel.semantic_type, channel.ordinal, channel.pointer_contract);
				mapped.heap_object = channel.heap_object;
				parameters.insert (channel, mapped);
				channels.add (mapped);
			}
			var callee = evaluate_before_effect (build_value (call.callee));
			var groups = new GenericArray<StructBoundaryGroup> ();
			var arguments = lower_arguments (call.arguments, groups);
			var invocation = new CfgFunctionValueCall (value.span, (FunctionValueType) call.callee.semantic_type, callee, arguments, call.owned_cleanup == null ? null : cleanups.lookup (call.owned_cleanup));
			foreach (var group in groups) {
				invocation.struct_arguments.add (group);
			}
			foreach (var channel in channels) {
				invocation.channel_parameters.add (channel);
			}
			if (invocation.semantic_type.is_struct_storage ()) {
				return invocation;
			}
			if (groups.length == 0 && channels.length == 0 && invocation.owned_cleanup == null) {
				return invocation;
			}
			// Record producers have one complete bounded call consumer. Materialize
			// that event before an enclosing expression can reuse its scalar result.
			var captured = new CfgEvaluatedValue (value.span, invocation.semantic_type);
			append_indirect_invocation (new CfgEvaluateInstruction (value.span, invocation, captured), arguments);
			return captured;
		}
		if (value is CoreWithReference) {
			var captured = with_captures.lookup (((CoreWithReference) value).contract);
			if (captured == null) {
				throw new CfgError.INVALID_CORE ("with reference has no active exact capture");
			}
			return captured;
		}
		if (value is CoreClassUpcast) {
			var cast = (CoreClassUpcast) value;
			var mapped = new CfgClassUpcast (value.span, build_value (cast.reference), (CfgClass) structs.lookup (cast.source_class), (CfgClass) structs.lookup (cast.target_class), value.semantic_type);
			var evaluated = new CfgEvaluatedValue (value.span, value.semantic_type);
			current.instructions.add (new CfgEvaluateInstruction (value.span, mapped, evaluated));
			return evaluated;
		}
		if (value is CoreEnumEquality) {
			var equality = (CoreEnumEquality) value;
			var left = lower_enum_producer (equality.left);
			var right = lower_enum_producer (equality.right);
			return new CfgBinaryValue (value.span, value.semantic_type, equality.unequal ? BinaryOperator.NOT_EQUAL : BinaryOperator.EQUAL, new CfgEnumTag (value.span, left.definition.tag_type, left), new CfgEnumTag (value.span, right.definition.tag_type, right));
		}
		if (value is CoreObjectReceiverValue) {
			var object_receiver = (CoreObjectReceiverValue) value;
			return validate_object (build_value (object_receiver.reference), value.semantic_type);
		}
		if (value is CoreReceiverValue) {
			return new CfgReceiverValue (value.span, receivers.lookup (((CoreReceiverValue) value).receiver));
		}
		if (value is CoreOwnedBufferAllocate) {
			var allocation = (CoreOwnedBufferAllocate) value;
			var context = allocation.allocation_context == null ? null : build_value (allocation.allocation_context);
			var count = build_value (allocation.count);
			CfgAllocationFailure? failure = null;
			if (allocation.failure_call != null) {
				count = capture_before_transfer (count);
				var request = current;
				var success = reserve_block (value.span, function.blocks);
				var failed = reserve_block (allocation.failure_call.span, function.blocks);
				current = failed;
				var native = allocation.failure_call as CoreCallStatement;
				if (native != null) {
					var call = lower_call (native.span, native.target, native.arguments, native.receiver);
					failure = new CfgAllocationFailure (native.span, call.target, null);
					failure.action = call;
				} else {
					var foreign = (CoreCCallStatement) allocation.failure_call;
					var call = lower_c_call (foreign.span, foreign.target, foreign.arguments);
					failure = new CfgAllocationFailure (foreign.span, null, call.target);
					failure.action = call;
				}
				failure.captured_receiver = allocation_receiver;
				current.complete (current.span, new CfgAllocationFailureTrap (failure.span, failure));
				var publication = new CfgBufferAllocate (value.span, count, cleanups.lookup (allocation.cleanup), failure, context);
				request.complete (request.span, new CfgBufferAllocationBranch (value.span, publication, success, failed));
				current = success;
				current.instructions.add (publication);
				return publication.results.owner;
			}
			var instruction = new CfgBufferAllocate (value.span, count, cleanups.lookup (allocation.cleanup), null, context);
			current.instructions.add (instruction);
			return instruction.results.owner;
		}
		if (value is CoreOwnedBufferBorrow) {
			var borrow = (CoreOwnedBufferBorrow) value;
			var view = new CfgBufferBorrowValue (value.span, locals.lookup (borrow.source.place), borrow.parameter == null ? null : parameters.lookup (borrow.parameter));
			current.instructions.add (new CfgOwnedBorrowInstruction (value.span, view));
			return view;
		}
		var slice = value as CoreSliceFromArrayValue;
		if (slice != null) {
			// Both operands are evaluated before any range validation.
			var start = slice.start == null ? null : capture_before_transfer (build_value (slice.start));
			var count = slice.count == null ? null : capture_before_transfer (build_value (slice.count));
			var construction = new CfgSliceFromArrayValue (value.span, (SliceType) value.semantic_type, locals.lookup (slice.storage), slice.array_type, start, count, slice.provenance);
			return capture_before_transfer (construction);
		}
		var length = value as CoreSliceLengthValue;
		if (length != null) {
			return capture_before_transfer (new CfgSliceLengthValue (value.span, value.semantic_type, capture_before_transfer (build_value (length.slice))));
		}
		var dot = value as CoreVectorDotValue;
		if (dot != null) {
			// Capture acc, a, b before evaluating each subsequent operand.
			var accumulator = dot.accumulator == null ? null : capture_before_transfer (build_value (dot.accumulator));
			var first = capture_before_transfer (build_value (dot.first));
			var second = capture_before_transfer (build_value (dot.second));
			var instruction = new CfgVectorDotInstruction (value.span, dot.dot_kind, dot.source_type, dot.destination_type, accumulator, first, second);
			current.instructions.add (instruction);
			return instruction.result;
		}
		var dsp = value as CoreDspValue;
		if (dsp != null) {
			// Capture each operand before the next call or owned transfer.
			var first = capture_before_transfer (build_value (dsp.first));
			var second = dsp.second == null ? null : capture_before_transfer (build_value (dsp.second));
			var instruction = new CfgDspInstruction (value.span, dsp.primitive_kind, dsp.source_type, dsp.destination_type, first, second, dsp.destination_element);
			current.instructions.add (instruction);
			return instruction.result;
		}
		var shift = value as CoreIntegerShiftValue;
		if (shift != null) {
			var operand = capture_before_transfer (build_value (shift.operand));
			var count = capture_before_transfer (build_value (shift.count));
			var instruction = new CfgIntegerShiftInstruction (value.span, value.semantic_type, shift.shift_kind, operand, count);
			current.instructions.add (instruction);
			return instruction.result;
		}
		var numeric_conversion = value as CoreNumericConversionValue;
		if (numeric_conversion != null) {
			var operand = build_value (numeric_conversion.operand);
			if (numeric_conversion.conversion_kind.traps ()) {
				var guard = new CfgNumericGuard (value.span, numeric_conversion.destination_type, operand, numeric_conversion.policy);
				current.instructions.add (guard);
				operand = guard.result;
			}
			var instruction = new CfgNumericConversionInstruction (value.span, numeric_conversion.source_type, numeric_conversion.destination_type, numeric_conversion.conversion_kind, operand, numeric_conversion.policy);
			current.instructions.add (instruction);
			return instruction.result;
		}
		var floating_conversion = value as CoreFloatConversionValue;
		if (floating_conversion != null) {
			var operand = build_value (floating_conversion.operand);
			var instruction = new CfgFloatConversionInstruction (value.span, floating_conversion.source_type, floating_conversion.destination_type, floating_conversion.conversion_kind, operand);
			current.instructions.add (instruction);
			return instruction.result;
		}
		var conversion = value as CoreIntegerConversionValue;
		if (conversion != null) {
			var operand = build_value (conversion.operand);
			var instruction = new CfgIntegerConversionInstruction (value.span, conversion.source_type, conversion.destination_type, operand);
			current.instructions.add (instruction);
			return instruction.result;
		}
		var splat = value as CoreVectorSplatValue;
		if (splat != null) {
			var operand = capture_before_transfer (build_value (splat.operand));
			var instruction = new CfgVectorSplatInstruction (value.span, value.semantic_type, operand, splat.lane_count, splat.lane_count_span);
			current.instructions.add (instruction);
			return instruction.result;
		}
		var extract = value as CoreVectorExtractValue;
		if (extract != null) {
			var vector = capture_before_transfer (build_value (extract.vector));
			var instruction = new CfgVectorExtractInstruction (value.span, value.semantic_type, vector, extract.index);
			current.instructions.add (instruction);
			return instruction.result;
		}
		var insert = value as CoreVectorInsertValue;
		if (insert != null) {
			var vector = capture_before_transfer (build_value (insert.vector));
			var replacement = capture_before_transfer (build_value (insert.replacement));
			var instruction = new CfgVectorInsertInstruction (value.span, value.semantic_type, vector, insert.index, replacement);
			current.instructions.add (instruction);
			return instruction.result;
		}
		var shuffle = value as CoreVectorShuffleValue;
		if (shuffle != null) {
			var vector = capture_before_transfer (build_value (shuffle.vector));
			var instruction = new CfgVectorShuffleInstruction (value.span, value.semantic_type, vector, shuffle.selectors);
			current.instructions.add (instruction);
			return instruction.result;
		}
		if (value is CoreVectorMemoryValue) {
			var memory = (CoreVectorMemoryValue) value;
			var view = capture_before_transfer (build_value (memory.view));
			var offset = capture_before_transfer (build_value (memory.offset));
			var stored = memory.stored == null ? null : capture_before_transfer (build_value (memory.stored));
			var operation = new CfgVectorMemoryValue (value.span, memory.contract, view, offset, stored);
			var evaluation = new CfgEvaluateInstruction (value.span, operation, new CfgEvaluatedValue (value.span, value.semantic_type));
			current.instructions.add (evaluation);
			function.retain_vector_memory (evaluation, current);
			return evaluation.result;
		}
		var select = value as CoreVectorSelectValue;
		if (select != null) {
			var mask = capture_before_transfer (build_value (select.mask));
			var true_value = capture_before_transfer (build_value (select.true_value));
			var false_value = capture_before_transfer (build_value (select.false_value));
			var instruction = new CfgVectorSelectInstruction (value.span, value.semantic_type, mask, true_value, false_value);
			current.instructions.add (instruction);
			return instruction.result;
		}
		var vector = value as CoreVectorConstructValue;
		if (vector != null) {
			var lanes = new GenericArray<CfgValue> ();
			// Capture each lane before evaluating the next, including integer
			// traps, memory reads and short-circuit lane expressions.
			foreach (var lane in vector.lanes) {
				lanes.add (capture_before_transfer (build_value (lane)));
			}
			var instruction = new CfgVectorConstructInstruction (value.span, value.semantic_type, lanes);
			current.instructions.add (instruction);
			return instruction.result;
		}
		var reduction = value as CoreVectorReductionValue;
		if (reduction != null) {
			var operand = build_value (reduction.operand);
			var instruction = new CfgVectorReductionInstruction (value.span, value.semantic_type, reduction.operator_kind, operand);
			current.instructions.add (instruction);
			return instruction.result;
		}
		var argument = value as CoreOwnedArgumentValue;
		if (argument != null) {
			var source = argument.source == null ? null : locals.lookup (argument.source.place);
			var cleanup = cleanups.lookup (argument.cleanup);
			if (argument.producer != null) {
				var incoming = build_value (argument.producer);
				source = new CfgLocalPlace (value.span, value.span, "$staged-capture", incoming.semantic_type, function.locals.length, false, cleanup);
				function.locals.add (source);
				current.instructions.add (new CfgInitialize (value.span, source, incoming, source));
			}
			var transfer = new CfgPendingOwnedArgument (value.span, parameters.lookup (argument.parameter), cleanup, source, argument.producer != null);
			if (argument_frames.length == 0) {
				throw new CfgError.INVALID_CORE ("owned argument capture requires its active consumer evaluation");
			}
			argument_frames[argument_frames.length - 1].staged.add (transfer);
			current.instructions.add (new CfgOwnedArgumentCapture (value.span, transfer));
			return transfer;
		}
		if (value is CoreSlotsTake) {
			var take = (CoreSlotsTake) value;
			return new CfgSlotsValue (take.span, take.semantic_type, (CfgIndirectFieldPlace) find_place (take.store), OwnerSlotsAction.TAKE, capture_before_transfer (build_value (take.index)));
		}
		if (value is CoreSlotsValue) {
			var v = (CoreSlotsValue) value;
			var store = (CfgIndirectFieldPlace) find_place (v.store);
			var operand = v.operand == null ? null : capture_before_transfer (build_value (v.operand));
			if (v.action == OwnerSlotsAction.BORROW) {
				var loan = new CfgSlotsLoan (v.span, store, operand, parameters.lookup (v.borrower), v.iteration != null);
				current.instructions.add (new CfgSlotsBorrow (v.span, loan));
				return loan;
			}
			return capture_before_transfer (new CfgSlotsValue (v.span, v.semantic_type, store, v.action, operand));
		}
		if (value is CoreOwnedFieldBorrow) {
			return new CfgLoadValue (value.span, find_place (((CoreOwnedFieldBorrow) value).source));
		}
		var borrow = value as CoreOwnedBorrowValue;
		if (borrow != null) {
			var result = new CfgOwnedBorrowValue (value.span, locals.lookup (borrow.source.place), parameters.lookup (borrow.parameter));
			current.instructions.add (new CfgOwnedBorrowInstruction (value.span, result));
			return result;
		}
		var short_circuit = value as CoreShortCircuitValue;
		if (short_circuit != null) {
			return lower_short_circuit (short_circuit);
		}
		var c_call = value as CoreCCallValue;
		if (c_call != null) {
			return lower_c_call (c_call.span, c_call.target, c_call.arguments).result;
		}
		var construction = value as CoreOwnedObjectResultConstruction;
		if (construction != null) {
			lower_call (value.span, construction.constructor, construction.arguments, null, null, true);
			return function.result_storage;
		}
		var call = value as CoreCallValue;
		if (call != null) {
			var invocation = lower_call (call.span, call.target, call.arguments, call.receiver, null, false, call);
			return invocation.success_result == null || invocation.target.owned_cleanup != null ? (CfgValue) invocation.result : invocation.success_result;
		}
		var load = value as CoreLoadValue;
		if (load != null) {
			// Memory reads are captured at their expression point, before any
			// later operand/call can change aliasable storage.
			return evaluate_before_effect (new CfgLoadValue (load.span, find_place (load.source), load.volatile_access == null ? null : load.volatile_access.copy ()));
		}
		var address = value as CoreAddressOfValue;
		if (address != null) {
			return evaluate_before_effect (address.receiver_place == null ? new CfgAddressOfValue (value.span, value.semantic_type, locals.lookup (address.target), address.provenance) : new CfgAddressOfValue.projection (value.span, (ReceiverType) value.semantic_type, find_place (address.receiver_place)));
		}
		if (value is CoreNullPointerValue) {
			return new CfgNullPointerValue (value.span, value.semantic_type);
		}
		var boolean = value as CoreBooleanValue;
		if (boolean != null) {
			return new CfgBooleanValue (boolean.span, boolean.semantic_type, boolean.literal);
		}
		if (value is CoreUtf8FactoryValue) {
			var operation = (CoreUtf8FactoryValue) value;
			return new CfgUtf8FactoryValue (value.span, value.semantic_type, parameters.lookup (operation.input), operation.validates);
		}
		if (value is CoreTextValue) {
			return new CfgTextValue (value.span, value.semantic_type, ((CoreTextValue) value).payload);
		}
		if (value is CoreTextLengthValue) {
			return capture_before_transfer (new CfgTextLengthValue (value.span, value.semantic_type, capture_before_transfer (build_value (((CoreTextLengthValue) value).receiver))));
		}
		if (value is CoreFloatValue) {
			return new CfgFloatValue (value.span, value.semantic_type, ((CoreFloatValue) value).value);
		}
		if (value is CoreIntegerValue) {
			return new CfgIntegerValue.typed (value.span, value.semantic_type, ((CoreIntegerValue) value).value);
		}
		var reference = value as CoreParameterValue;
		if (reference != null) {
			var parameter = parameters.lookup (reference.parameter);
			if (parameter == null) {
				throw new CfgError.INVALID_CORE ("internal CFG construction error: parameter reference has no declaration in the containing function");
			}
			return new CfgParameterValue (reference.span, parameter);
		}
		var prefix = value as CorePrefixValue;
		if (prefix != null) {
			return new CfgPrefixValue (prefix.span, prefix.semantic_type, prefix.operator_kind, build_value (prefix.operand));
		}
		var binary = value as CoreBinaryValue;
		if (binary != null) {
			// Operand and argument traversal is observable language order.
			var left = build_value (binary.left);
			if (contains_owned_transfer (binary.right)) {
				left = capture_before_transfer (left);
			} else if (emits_ordered_evaluation (binary.right)) {
				left = evaluate_before_effect (left);
			}
			var right = build_value (binary.right);
			return new CfgBinaryValue (binary.span, binary.semantic_type, binary.operator_kind, left, right);
		}
		throw new CfgError.INVALID_CORE ("internal CFG construction error: unsupported Core value");
	}

}
}
