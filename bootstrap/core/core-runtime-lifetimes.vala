// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Text;

namespace Astra.Core {
private class CoreRuntimeStorage : Object {
	internal int binding;
	internal string path;
	internal CoreRuntimeStorage (int binding, string path = "") {
		this.binding = binding;
		this.path = path;
	}
}
private class CoreRuntimeObligation : Object {
	internal int value;
	internal int destination;
	internal CoreRuntimeObligation (int value, int destination) {
		this.value = value;
		this.destination = destination;
	}
}
// Reconstruct from Core nodes. No CheckedFunction summary is consulted or
// retained; callers can keep a neutral result after the entire Core is freed.
public class CoreRuntimeLifetimes : Object {
	private CoreProgram program;
	private HashTable<CoreFunction, RuntimeLifetimeSummary> summaries = new HashTable<CoreFunction, RuntimeLifetimeSummary> (direct_hash, direct_equal);
	private HashTable<CoreFunction, bool> visiting = new HashTable<CoreFunction, bool> (direct_hash, direct_equal);
	public static HashTable<CoreFunction, RuntimeLifetimeSummary> analyze(CoreProgram program) throws CoreError {
		var analysis = new CoreRuntimeLifetimes ();
		analysis.program = program;
		foreach (var function in program.all_definitions ()) {
			analysis.summary (function);
		}
		return analysis.summaries;
	}
	public static void verify(CoreProgram program, GenericArray<CoreFunction>? required = null) throws CoreError {
		var summaries = analyze (program);
		if (required != null) {
			foreach (var function in required) {
				var result = summaries.lookup (function);
				if (result == null || !result.complete) {
					throw new CoreError.INVALID_IR ("Core scoped construction requires its complete actual function lifetime proof");
				}
			}
		}
	}
	internal RuntimeLifetimeSummary? summary(CoreFunction? function) throws CoreError {
		if (function == null || visiting.contains (function) || !program.functions.find (function) && !(function is CoreGenericFunction && program.generic_functions.find ((CoreGenericFunction) function))) {
			return null;
		}
		var existing = summaries.lookup (function);
		if (existing != null) {
			return existing;
		}
		if (function.native_declaration != null) {
			try {
				var imported = function.native_declaration.runtime_lifetime_summary ();
				if (imported != null) {
					summaries.insert (function, imported);
				}
				return imported;
			} catch (RuntimeLifetimeError failure) {
				throw new CoreError.INVALID_IR ("Core native lifetime contract: %s", failure.message);
			}
		}
		visiting.insert (function, true);
		var body = new CoreRuntimeLifetimeBody (this, program, function);
		RuntimeLifetimeSummary result;
		try {
			result = body.analyze ();
		} catch (RuntimeLifetimeError failure) {
			if (failure is RuntimeLifetimeError.LOCAL_ESCAPE) {
				throw new CoreError.INVALID_IR ("Core runtime lifetime: %s", failure.message);
			}
			result = body.incomplete (failure.message);
		}
		if (body.requires_scope && !result.complete) {
			throw new CoreError.INVALID_IR ("Core scoped lifetime proof is incomplete: %s", result.limitation);
		}
		visiting.remove (function);
		summaries.insert (function, result);
		return result;
	}
}
private class CoreRuntimeLifetimeBody : Object {
	private CoreRuntimeLifetimes analysis;
	private CoreProgram program;
	private CoreFunction function;
	private RuntimeLifetimeFlow flow = new RuntimeLifetimeFlow ();
	private RuntimeLifetimeRegions regions = new RuntimeLifetimeRegions ();
	private HashTable<TextLoanExtent, int> region_ids = new HashTable<TextLoanExtent, int> (direct_hash, direct_equal);
	private HashTable<CoreObjectStorage, CoreLocalPlace> objects = new HashTable<CoreObjectStorage, CoreLocalPlace> (direct_hash, direct_equal);
	private HashTable<CoreLocalPlace, CoreScopedAllocator> contexts = new HashTable<CoreLocalPlace, CoreScopedAllocator> (direct_hash, direct_equal);
	private HashTable<CoreLocalPlace, bool> owners = new HashTable<CoreLocalPlace, bool> (direct_hash, direct_equal);
	private HashTable<int, int> initial_inputs = new HashTable<int, int> (direct_hash, direct_equal);
	private HashTable<int, int> exits = new HashTable<int, int> (direct_hash, direct_equal);
	private GenericArray<RuntimeLifetimeStore> stores = new GenericArray<RuntimeLifetimeStore> ();
	private GenericArray<CoreRuntimeObligation> obligations = new GenericArray<CoreRuntimeObligation> ();
	private string unsupported = "";
	private int returned;
	private int exceptional_result;
	private HashTable<int, ClassType> exception_types = new HashTable<int, ClassType> (direct_hash, direct_equal);
	private int exit_count;
	private bool scoped_construction;
	internal bool requires_scope { get { return scoped_construction || graph.has_scope_roots; } }
	private static bool scoped_class(CoreClass? owner) {
		return owner != null && owner.allocation_policy != null && owner.allocation_policy.kind == AllocationKind.CONTEXT && owner.allocation_policy.context_mode == "scoped-affine";
	}
	private static bool scoped_value(CoreValue? value) {
		if (value is CoreOwnedObjectResultConstruction) {
			return scoped_class (((CoreOwnedObjectResultConstruction) value).storage.object_class);
		}
		return value is CoreOwnedBufferAllocate && ((CoreOwnedBufferAllocate) value).allocation_context != null && ((CoreOwnedBufferAllocate) value).allocation_context.semantic_type.is_scoped_allocator ();
	}
	private static bool scoped_block(CoreBlock block) {
		foreach (var source in block.statements) {
			if (source is CoreConstructorObjectInitialization && scoped_class (((CoreConstructorObjectInitialization) source).storage.object_class) || source is CoreInitialize && scoped_value (((CoreInitialize) source).value) || source is CoreOwnershipReturn && scoped_value (((CoreOwnershipReturn) source).producer) || source is CoreStructAcquire && scoped_value (((CoreStructAcquire) source).producer) || source is CoreOwnedFieldTransfer && scoped_value (((CoreOwnedFieldTransfer) source).producer)) {
				return true;
			}
			if (source is CoreScope && scoped_block (((CoreScope) source).body) || source is CoreIf && (scoped_block (((CoreIf) source).then_block) || ((CoreIf) source).else_block != null && scoped_block (((CoreIf) source).else_block)) || source is CoreWhile && (scoped_block (((CoreWhile) source).body) || ((CoreWhile) source).step != null && scoped_block (((CoreWhile) source).step))) {
				return true;
			}
			if (source is CoreTry) {
				var guarded = (CoreTry) source;
				if (scoped_block (guarded.body)) {
					return true;
				}
				foreach (var caught in guarded.catches) {
					if (scoped_block (caught.body)) {
						return true;
					}
				}
			}
			if (source is CoreEnumMatch) {
				foreach (var arm in ((CoreEnumMatch) source).arms) {
					if (scoped_block (arm.body)) {
						return true;
					}
				}
			}
		}
		return false;
	}
	internal CoreRuntimeLifetimeBody (CoreRuntimeLifetimes analysis, CoreProgram program, CoreFunction function) {
		this.analysis = analysis;
		this.program = program;
		this.function = function;
		scoped_construction = scoped_block (function.body);
		scoped_construction |= scoped_type (function.return_type) || function.implicit_receiver != null && scoped_type (function.implicit_receiver.contract) || function.throws_type != null && scoped_type (function.throws_type);
		foreach (var parameter in function.parameters) {
			scoped_construction |= scoped_type (parameter.semantic_type);
		}
		foreach (var local in function.locals) {
			scoped_construction |= scoped_type (local.semantic_type);
		}
	}
	private RuntimeLifetimeEquations graph { get { return flow.equations; } }
	private void unsupported_node(string reason) {
		if (unsupported == "") {
			unsupported = reason;
		}
	}
	private static int parameter_binding(int parameter) {
		return -parameter - 2;
	}
	private static bool graph_input(SemanticType type) {
		return !(type is HandleType && ((HandleType) type).context_mode != "") && (type is ClassType || type is ReceiverType || type is HandleType || type.is_struct_storage () || type is TypeParameterType || type is TaskType);
	}
	private int region_id(TextLoanExtent? extent) throws RuntimeLifetimeError {
		if (extent == null) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("Core lifetime requires actual lexical cleanup extents");
		}
		if (!region_ids.contains (extent)) {
			int parent = extent.parent == null ? -1 : region_id (extent.parent);
			region_ids.insert (extent, regions.add_region (parent));
		}
		return region_ids.lookup (extent);
	}
	private CoreNativeInstance? instance(SemanticType type) {
		if (type is ReceiverType) {
			type = ((ReceiverType) type).instance_type;
		}
		foreach (var owner in program.native_instances ()) {
			if (owner.semantic_type == type) {
				return owner;
			}
		}
		foreach (var owner in program.class_applications) {
			if (owner.semantic_type == type) {
				return owner;
			}
		}
		return null;
	}
	private bool scoped_type(SemanticType type) {
		return RuntimeScopeTypes.contains (type, expand_scoped_type);
	}
	private bool expand_scoped_type(SemanticType type, GenericArray<SemanticType> following) {
		var owner = instance (type);
		if (owner != null) {
			var object_class = owner as CoreClass;
			if (object_class != null) {
				var policy = object_class.allocation_policy;
				if (policy != null && policy.kind == AllocationKind.CONTEXT && policy.context_mode == "scoped-affine") {
					return true;
				}
				if (object_class.parent_class != null) {
					following.add (object_class.parent_class.semantic_type);
				}
			}
			foreach (var field in owner.fields) {
				if (field.owned_cleanup != null || field.slots_cleanup != null || field.semantic_type.is_struct_storage ()) {
					following.add (field.semantic_type);
				}
			}
		}
		if (type is CoreGenericStructApplicationType) {
			var record = (CoreGenericStructApplicationType) type;
			foreach (var field in record.definition.fields) {
				following.add (record.field_type (field));
			}
		}
		foreach (var definition in program.enums) {
			if (definition.semantic_type == type) {
				foreach (var field in definition.value_fields ()) {
					following.add (field);
				}
			}
		}
		return false;
	}
	private int product(SemanticType type, CoreValue? context = null) throws RuntimeLifetimeError {
		var roots = new GenericArray<RuntimeScopeOrigin> ();
		var origin = context_origin (context);
		if (origin != null) {
			roots.add (origin);
		}
		var fields = new HashTable<string, int> (str_hash, str_equal);
		var owner = instance (type);
		if (owner != null) {
			if (owner is CoreClass && ((CoreClass) owner).parent_class != null) {
				unsupported_node ("inherited paths require exact nominal owners");
			}
			foreach (var field in owner.fields) {
				fields.insert ("f%d".printf (field.ordinal), graph.absent ());
			}
		} else if (type.is_struct_storage ()) {
			unsupported_node ("record product requires its materialized Core field inventory");
		}
		return graph.product (roots, fields);
	}
	private int allocation(CoreClass owner, CoreValue? context) throws RuntimeLifetimeError {
		var policy = owner.allocation_policy;
		HandleType? handle = null;
		if (context != null) {
			handle = context.semantic_type as HandleType;
		}
		if (policy != null && policy.kind == AllocationKind.CONTEXT ? !policy.valid () || handle == null || handle.context_mode != policy.context_mode : context != null) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("Core allocation lost exact context mode");
		}
		return product (owner.semantic_type, context);
	}
	private RuntimeScopeOrigin? context_origin(CoreValue? value) throws RuntimeLifetimeError {
		if (value == null || !value.semantic_type.is_scoped_allocator ()) {
			return null;
		}
		if (value is CoreParameterValue) {
			return new RuntimeScopeOrigin.context_input (((CoreParameterValue) value).parameter.ordinal);
		}
		CoreLocalPlace? local = null;
		if (value is CoreLoadValue) {
			local = ((CoreLoadValue) value).source as CoreLocalPlace;
		} else if (value is CoreOwnedBorrowValue) {
			local = ((CoreOwnedBorrowValue) value).source.place;
		}
		var factory = local == null ? null : contexts.lookup (local);
		if (factory == null || !function.locals.find (local) || !factory.loan.valid () || factory.loan.context_ordinal != local.ordinal || factory.loan.region_ordinal != local.text_extent.ordinal) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("Core scope origin requires its exact local factory and cleanup extent");
		}
		return new RuntimeScopeOrigin.local (local.ordinal, region_id (local.text_extent));
	}
	private CoreRuntimeStorage? reference(CoreValue? value) {
		if (value is CoreStructProjectionValue) {
			var projected = (CoreStructProjectionValue) value;
			var storage = producer_reference (projected.source);
			if (storage != null) {
				storage.path += (storage.path == "" ? "" : ".") + path (projected.path);
			}
			return storage;
		}
		if (value is CoreOwnedFieldBorrow) {
			return place (((CoreOwnedFieldBorrow) value).source);
		}
		if (value is CoreLoadValue) {
			return place (((CoreLoadValue) value).source);
		}
		if (value is CoreParameterValue) {
			return new CoreRuntimeStorage (parameter_binding (((CoreParameterValue) value).parameter.ordinal));
		}
		if (value is CoreReceiverValue) {
			return new CoreRuntimeStorage (-1);
		}
		if (value is CoreOwnedBorrowValue) {
			return new CoreRuntimeStorage (((CoreOwnedBorrowValue) value).source.place.ordinal);
		}
		if (value is CoreWithReference) {
			return new CoreRuntimeStorage (((CoreWithReference) value).contract.source.ordinal);
		}
		if (value is CoreClassUpcast) {
			return reference (((CoreClassUpcast) value).reference);
		}
		if (value is CoreObjectReceiverValue) {
			return reference (((CoreObjectReceiverValue) value).reference);
		}
		if (value is CoreStorageReceiverValue) {
			var local = objects.lookup (((CoreStorageReceiverValue) value).storage);
			return local == null ? null : new CoreRuntimeStorage (local.ordinal);
		}
		if (value is CoreAddressOfValue) {
			var address = (CoreAddressOfValue) value;
			return address.target == null ? place(address.receiver_place) : new CoreRuntimeStorage (address.target.ordinal);
		}
		return null;
	}
	private CoreRuntimeStorage? producer_reference(CoreStructProducer producer) {
		if (producer is CoreStructSnapshot) {
			return place (((CoreStructSnapshot) producer).source);
		}
		if (producer is CoreStructBorrowSnapshot) {
			return place (((CoreStructBorrowSnapshot) producer).source);
		}
		if (producer is CoreStructProjectionProducer) {
			var projected = (CoreStructProjectionProducer) producer;
			var storage = producer_reference (projected.source);
			if (storage != null) {
				storage.path += (storage.path == "" ? "" : ".") + path (projected.path);
			}
			return storage;
		}
		return null;
	}
	private CoreRuntimeStorage? field(CoreRuntimeStorage? root, int ordinal) {
		if (root != null) {
			root.path += (root.path == "" ? "" : ".") + "f%d".printf (ordinal);
		}
		return root;
	}
	private CoreRuntimeStorage? place(CorePlace? place) {
		if (place is CoreLocalPlace) {
			return new CoreRuntimeStorage (((CoreLocalPlace) place).ordinal);
		}
		if (place is CoreFieldPlace) {
			return field (this.place (((CoreFieldPlace) place).aggregate), ((CoreFieldPlace) place).field.ordinal);
		}
		if (place is CoreIndirectFieldPlace) {
			return field (reference (((CoreIndirectFieldPlace) place).pointer), ((CoreIndirectFieldPlace) place).field.ordinal);
		}
		unsupported_node ("Core indirect/indexed storage needs an exact ownership path");
		return null;
	}
	private int read(CoreRuntimeStorage? storage) throws RuntimeLifetimeError {
		if (storage == null) {
			unsupported_node ("Core read has no exact owning storage");
			return graph.absent ();
		}
		int value = flow.read (storage.binding);
		return storage.path == "" ? value : graph.project (value, storage.path);
	}
	private int replace_path(int root, string path, int incoming) throws RuntimeLifetimeError {
		int dot = path.index_of_char ('.');
		if (dot < 0) {
			return graph.replace (root, path, incoming);
		}
		string head = path.substring (0, dot);
		return graph.replace (root, head, replace_path (graph.project (root, head), path.substring (dot + 1), incoming));
	}
	private void write(CoreRuntimeStorage? storage, int incoming, bool effect = true) throws RuntimeLifetimeError {
		if (storage == null) {
			unsupported_node ("Core write has no exact owning storage");
			return;
		}
		int result = storage.path == "" ? incoming : replace_path (flow.read (storage.binding), storage.path, incoming);
		flow.write (storage.binding, result);
		if (storage.binding >= 0) {
			obligations.add (new CoreRuntimeObligation (result, storage.binding));
		} else if (effect) {
			stores.add (new RuntimeLifetimeStore (storage.binding == -1 ? -1 : -storage.binding - 2, incoming));
		}
	}
	private int take(CoreOwnedLocal? source, CoreValue? produced = null) throws RuntimeLifetimeError, CoreError {
		if (source == null) {
			return value (produced);
		}
		int incoming = flow.read (source.place.ordinal);
		flow.write (source.place.ordinal, graph.absent ());
		return incoming;
	}
	private int foreign_call(CoreCFunction? target, GenericArray<CoreValue> arguments) throws RuntimeLifetimeError, CoreError {
		foreach (var argument in arguments) {
			value (argument);
			context_origin (argument);
		}
		bool admitted = target != null && arguments.length == target.parameters.length && RuntimeForeignLifetimes.result (target.return_type, target.owned_cleanup == null ? null : target.owned_cleanup.external_symbol);
		if (target != null) {
			foreach (var parameter in target.parameters) {
				admitted = admitted && RuntimeForeignLifetimes.input (parameter.semantic_type, parameter.pointer_contract, target.owned_cleanup != null);
			}
		}
		if (!admitted) {
			unsupported_node ("Core foreign call requires an exact owner/pointer/callback lifetime effect");
		}
		return graph.absent ();
	}
	private int invoke(CoreFunction? target, GenericArray<CoreValue> arguments, CoreValue? receiver, int constructed = -1) throws RuntimeLifetimeError, CoreError {
		var inputs = new HashTable<int, int> (direct_hash, direct_equal);
		var anchors = new HashTable<int, RuntimeScopeOrigin> (direct_hash, direct_equal);
		var destinations = new HashTable<int, CoreRuntimeStorage> (direct_hash, direct_equal);
		var pending = new HashTable<int, int> (direct_hash, direct_equal);
		var commits = new GenericArray<CoreLocalPlace> ();
		if (receiver != null) {
			inputs.insert (-1, value (receiver));
			var destination = reference (receiver);
			if (destination != null) {
				destinations.insert (-1, destination);
				pending.insert (-1, flow.read (destination.binding));
			}
		} else if (constructed >= 0) {
			inputs.insert (-1, constructed);
		}
		for (int i = 0; i < arguments.length; i++) {
			var argument = arguments[i] as CoreOwnedArgumentValue;
			if (argument != null && argument.source != null) {
				var local = argument.source.place;
				inputs.insert (i, flow.read (local.ordinal));
				commits.add (local);
			} else {
				inputs.insert (i, value (arguments[i]));
			} var anchor = context_origin (arguments[i]);
			if (anchor != null) {
				anchors.insert (i, anchor);
			}
			var destination = reference (arguments[i]);
			if (destination != null) {
				destinations.insert (i, destination);
				pending.insert (i, flow.read (destination.binding));
			}
		}
		// Reservation abort preserves the named owner if a later argument fails.
		foreach (var local in commits) {
			flow.write (local.ordinal, graph.absent ());
		}
		foreach (int parameter in pending.get_keys ()) {
			if (parameter >= 0 && target != null && parameter < target.parameters.length && target.parameters[parameter].pointer_contract == PointerParameterContract.OWNED_TRANSFER) {
				continue;
			}
			if (flow.read (destinations.lookup (parameter).binding) != pending.lookup (parameter)) {
				unsupported_node ("Core argument evaluation changes a pending borrowed owner");
			}
		}
		var summary = analysis.summary (target);
		if (summary == null || !summary.complete || target.dispatch_kind != ClassDispatchKind.DIRECT) {
			unsupported_node ("Core call requires a complete direct lifetime summary");
			return constructed >= 0 ? constructed : graph.absent ();
		}
		for (uint i = 0; i < summary.store_count; i++) {
			var store = summary.store (i);
			int incoming = summary.equations.instantiate (store.value, graph, inputs, anchors);
			var destination = destinations.lookup (store.parameter);
			if (destination == null) {
				if (!(constructed >= 0 && store.parameter == -1)) {
					unsupported_node ("Core call store lacks its actual cleanup extent");
				}
			} else if (destination.binding >= 0) {
				obligations.add (new CoreRuntimeObligation (incoming, destination.binding));
			} else {
				stores.add (new RuntimeLifetimeStore (destination.binding == -1 ? -1 : -destination.binding - 2, incoming));
			}
		}
		int result = constructed >= 0 ? constructed : summary.equations.instantiate (summary.result, graph, inputs, anchors);
		var updates = summary.updated_inputs ();
		for (int i = 0; i < updates.length; i++) {
			int parameter = updates[i];
			int incoming = summary.equations.instantiate (summary.update (parameter), graph, inputs, anchors);
			if (constructed >= 0 && parameter == -1) {
				result = incoming;
			} else {
				write (destinations.lookup (parameter), incoming, false);
			}
		}
		if (target.throws_type != null) {
			if (!summary.has_exception) {
				unsupported_node ("Core throwing call requires its exact exceptional lifetime result");
			} else {
				exception (summary.equations.instantiate (summary.exception, graph, inputs, anchors), target.throws_type);
			}
		} else if (summary.has_exception) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("Core nonthrowing call has an exceptional lifetime result");
		}
		return result;
	}
	private int task_create(CoreTaskCreate creation) throws RuntimeLifetimeError, CoreError {
		var inputs = new HashTable<int, int> (direct_hash, direct_equal);
		var anchors = new HashTable<int, RuntimeScopeOrigin> (direct_hash, direct_equal);
		var commits = new GenericArray<CoreLocalPlace> ();
		for (int p = 0; p < creation.arguments.length; p++) {
			var argument = creation.arguments[p] as CoreOwnedArgumentValue;
			if (argument != null && argument.source != null) {
				inputs.insert (p, flow.read (argument.source.place.ordinal));
				commits.add (argument.source.place);
			} else if (creation.arguments[p] is CoreStructArgument && ((CoreStructArgument) creation.arguments[p]).producer is CoreStructMoveProducer) {
				var local = ((CoreStructMoveProducer) ((CoreStructArgument) creation.arguments[p]).producer).source.place;
				inputs.insert (p, flow.read (local.ordinal));
				commits.add (local);
			} else {
				inputs.insert (p, value (creation.arguments[p]));
			} var anchor = context_origin (creation.arguments[p]);
			if (anchor != null) {
				anchors.insert (p, anchor);
			}
		}
		var summary = analysis.summary (creation.target);
		if (summary == null || !summary.complete || summary.has_exception || summary.store_count != 0 || summary.updated_inputs ().length != 0) {
			unsupported_node ("Core task creation requires its complete cold-frame lifetime summary");
			return graph.absent ();
		}
		if (creation.checked_admission) {
			exception (graph.absent (), creation.target.async_body.runtime.error_type);
		}
		foreach (var local in commits) {
			flow.write (local.ordinal, graph.absent ());
		}
		int task = summary.equations.instantiate (summary.result, graph, inputs, anchors);
		var root = context_origin (creation.allocation_context);
		if (root == null) {
			return task;
		}
		var roots = new GenericArray<RuntimeScopeOrigin> ();
		roots.add (root);
		var fields = new HashTable<string, int> (str_hash, str_equal);
		for (int f = 0; f < 3; f++) {
			fields.insert ("f%d".printf (f), graph.project (task, "f%d".printf (f)));
		}
		return graph.product (roots, fields);
	}
	private int task_await(CoreTaskAwait operation) throws RuntimeLifetimeError, CoreError {
		value (operation.bridge_executor);
		int task = value (operation.child);
		if (operation.discard) {
			return graph.absent ();
		}
		var type = operation.child.semantic_type as TaskType;
		if (type == null) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("Core task observation lost its exact typed result contract");
		}
		exception (graph.project (task, "f1"), type.exception_bound ?? type.runtime.error_type);
		return graph.project (task, "f0");
	}
	private int async_operation(CoreAsyncOperation operation) throws RuntimeLifetimeError, CoreError {
		value (operation.executor);
		value (operation.argument);
		int task = value (operation.task);
		if (operation.contract.kind == AsyncOperationKind.RUN) {
			exception (graph.project (task, "f1"), ((TaskType) operation.task.semantic_type).exception_bound ?? operation.contract.runtime.error_type);
		} else if (operation.contract.raises) {
			exception (graph.absent (), operation.contract.runtime.error_type);
		}
		return graph.absent ();
	}
	private int enum_value(CoreEnumProducer producer) throws RuntimeLifetimeError, CoreError {
		if (producer is CoreAsyncRun) {
			return async_operation (((CoreAsyncRun) producer).operation);
		}
		if (producer is CoreEnumSnapshot && producer.definition.value_fields ().length == 0) {
			return flow.read (((CoreEnumSnapshot) producer).source.ordinal);
		}
		unsupported_node ("Core enum lifetime requires its exact copied/owning operation");
		return graph.absent ();
	}
	private static string path(StructLeafPath path) {
		var result = new StringBuilder ();
		for (int i = 0; i < path.depth; i++) {
			if (i != 0) {
				result.append (".");
			}
			result.append_printf ("f%d", path.field_ordinal (i));
		}
		return result.str;
	}
	private int producer(CoreStructProducer source) throws RuntimeLifetimeError, CoreError {
		if (source is CoreStructAwait) {
			return task_await (((CoreStructAwait) source).operation);
		}
		if (source is CoreStructMoveProducer) {
			return take (((CoreStructMoveProducer) source).source);
		}
		if (source is CoreStructSnapshot) {
			return read (place (((CoreStructSnapshot) source).source));
		}
		if (source is CoreStructBorrowSnapshot) {
			return read (place (((CoreStructBorrowSnapshot) source).source));
		}
		if (source is CoreStructInvocationResult) {
			return value (((CoreStructInvocationResult) source).invocation);
		}
		if (source is CoreStructCallResult) {
			var call = (CoreStructCallResult) source;
			return invoke (call.target, call.arguments, call.receiver);
		}
		if (source is CoreStructProjectionProducer) {
			var projection = (CoreStructProjectionProducer) source;
			return graph.project (producer (projection.source), path (projection.path));
		}
		unsupported_node ("Core record producer requires its exact lifetime operation");
		return graph.absent ();
	}
	private int value(CoreValue? source) throws RuntimeLifetimeError, CoreError {
		if (source == null) {
			return graph.absent ();
		}
		if (source is CoreOwnedArgumentValue) {
			var input = (CoreOwnedArgumentValue) source;
			return take (input.source, input.producer);
		}
		if (source is CoreStructArgument) {
			return producer (((CoreStructArgument) source).producer);
		}
		if (source is CoreOwnedFieldBorrow) {
			return read (place (((CoreOwnedFieldBorrow) source).source));
		}
		if (source is CoreOwnedBufferBorrow) {
			return flow.read (((CoreOwnedBufferBorrow) source).source.place.ordinal);
		}
		if (source is CoreLoadValue || source is CoreParameterValue || source is CoreReceiverValue || source is CoreOwnedBorrowValue || source is CoreWithReference || source is CoreClassUpcast || source is CoreObjectReceiverValue || source is CoreStorageReceiverValue || source is CoreAddressOfValue) {
			int loaded = read (reference (source));
			return (source.semantic_type.kind == TypeKind.BOOL || source.semantic_type is IntegerType || source.semantic_type is FloatingType || source.semantic_type is VectorType) ? graph.absent () : loaded;
		}
		if (source is CoreTaskCreate) {
			return task_create ((CoreTaskCreate) source);
		}
		if (source is CoreTaskMove) {
			var local = ((CoreTaskMove) source).source;
			int incoming = flow.read (local.ordinal);
			flow.write (local.ordinal, graph.absent ());
			return incoming;
		}
		if (source is CoreTaskBorrow) {
			return flow.read (((CoreTaskBorrow) source).source.ordinal);
		}
		if (source is CoreExecutorBorrow) {
			return graph.absent ();
		}
		if (source is CoreTaskAwait) {
			return task_await ((CoreTaskAwait) source);
		}
		if (source is CoreAsyncOperation) {
			return async_operation ((CoreAsyncOperation) source);
		}
		if (source is CoreCallValue) {
			var call = (CoreCallValue) source;
			return invoke (call.target, call.arguments, call.receiver);
		}
		if (source is CoreCCallValue) {
			var call = (CoreCCallValue) source;
			return foreign_call (call.target, call.arguments);
		}
		if (source is CoreOwnedObjectResultConstruction) {
			var construction = (CoreOwnedObjectResultConstruction) source;
			return invoke (construction.constructor, construction.arguments, null, allocation (construction.storage.object_class, null));
		}
		if (source is CoreOwnedBufferAllocate) {
			var allocation = (CoreOwnedBufferAllocate) source;
			value (allocation.count);
			if (allocation.failure_call != null) {
				unsupported_node ("Core buffer failure action needs exceptional effects");
			}
			return product (source.semantic_type, allocation.allocation_context);
		}
		if (source is CoreScopedAllocator) {
			value (((CoreScopedAllocator) source).kind);
			value (((CoreScopedAllocator) source).slots);
			return graph.absent ();
		}
		if (source is CoreSliceLengthValue) {
			value (((CoreSliceLengthValue) source).slice);
			return graph.absent ();
		}
		if (source is CoreStructProjectionValue) {
			var projection = (CoreStructProjectionValue) source;
			return graph.project (producer (projection.source), path (projection.path));
		}
		if (source is CoreBinaryValue) {
			value (((CoreBinaryValue) source).left);
			value (((CoreBinaryValue) source).right);
			return graph.absent ();
		}
		if (source is CoreShortCircuitValue) {
			var branch = (CoreShortCircuitValue) source;
			value (branch.left);
			var entry = flow.state.snapshot ();
			value (branch.right);
			flow.merge (entry, entry, flow.state);
			return graph.absent ();
		}
		if (source is CoreComparisonChain) {
			var operands = ((CoreComparisonChain) source).operands;
			for (int i = 0; i < operands.length; i++) {
				var entry = flow.state.snapshot ();
				value (operands[i]);
				if (i >= 2) {
					flow.merge (entry, entry, flow.state);
				}
			}
			return graph.absent ();
		}
		if (source is CorePrefixValue) {
			value (((CorePrefixValue) source).operand);
			return graph.absent ();
		}
		if (source is CoreIntegerConversionValue) {
			value (((CoreIntegerConversionValue) source).operand);
			return graph.absent ();
		}
		if (source is CoreFloatConversionValue) {
			value (((CoreFloatConversionValue) source).operand);
			return graph.absent ();
		}
		if (source is CoreNumericConversionValue) {
			value (((CoreNumericConversionValue) source).operand);
			return graph.absent ();
		}
		if (source is CoreIntegerValue || source is CoreBooleanValue || source is CoreFloatValue || source is CoreTextValue || source is CoreNullPointerValue) {
			return graph.absent ();
		}
		unsupported_node ("Core value requires its exact lifetime operation: " + source.get_type ().name ());
		return graph.absent ();
	}
	private void exit() throws RuntimeLifetimeError {
		if (flow.state.reachable) {
			exit_count++;
			foreach (int binding in exits.get_keys ()) {
				graph.alternative (exits.lookup (binding), flow.read (binding));
			}
		}
	}
	private void block(CoreBlock block) throws RuntimeLifetimeError, CoreError {
		foreach (var child in block.statements) {
			statement (child);
		}
		foreach (var local in function.locals) {
			if (local.text_extent == block.text_extent && local.incoming_parameter == null) {
				flow.write (local.ordinal, graph.absent ());
			}
		}
	}
	private void exception(int value, ClassType type) throws RuntimeLifetimeError {
		int site = (int) exception_types.size ();
		exception_types.insert (site, type);
		flow.exception (value, site);
	}
	private bool exception_subtype(ClassType type, ClassType bound) throws RuntimeLifetimeError {
		var owner = instance (type) as CoreClass;
		var target = instance (bound) as CoreClass;
		if (owner == null || target == null) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("Core exception effect lacks its current nominal Class inventory");
		}
		var seen = new HashTable<CoreClass, bool> (direct_hash, direct_equal);
		while (owner != null) {
			if (owner == target) {
				return true;
			}
			if (seen.contains (owner)) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("Core exception ancestry contains a cycle");
			}
			seen.insert (owner, true);
			owner = owner.parent_class;
		}
		return false;
	}
	private void guarded(CoreTry source) throws RuntimeLifetimeError, CoreError {
		var entry = flow.state.snapshot ();
		flow.begin_try ();
		block (source.body);
		var normal = flow.state.snapshot ();
		var pending = flow.end_try ();
		int pending_count = (int) pending.length;
		if (pending_count < 0) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("Core exception event count exceeds the supported array extent");
		}
		bool[] handled = new bool[pending_count];
		foreach (var caught in source.catches) {
			if (caught.body.text_extent == null || caught.binding.text_extent != caught.body.text_extent) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("Core catch lost its exact cleanup extent");
			}
			flow.state = entry.snapshot ();
			flow.state.reachable = false;
			int failure = graph.join ();
			bool reachable = false;
			var bound = caught.binding.semantic_type as ClassType;
			if (bound == null) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("Core catch requires its exact exception Class");
			}
			for (int e = 0; e < pending.length; e++) {
				if (handled[e]) {
					continue;
				}
				var event = pending[e];
				var type = exception_types.lookup (event.site);
				if (type == null) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("Core exception lost its actual effect type");
				}
				bool consumed = exception_subtype (type, bound);
				if (!consumed && !exception_subtype (bound, type)) {
					continue;
				}
				var incoming = event.state.snapshot ();
				foreach (var local in function.locals) {
					if (local.text_extent == null || !local.text_extent.outlives (caught.body.text_extent)) {
						incoming.bindings.insert (local.ordinal, graph.absent ());
					}
				}
				flow.merge (entry, flow.state, incoming);
				graph.alternative (failure, event.value);
				reachable = true;
				if (consumed) {
					handled[e] = true;
				}
			}
			if (reachable) {
				write (new CoreRuntimeStorage (caught.binding.ordinal), failure);
				block (caught.body);
				flow.merge (entry, normal, flow.state);
				normal = flow.state.snapshot ();
			}
		}
		for (int e = 0; e < pending.length; e++) {
			if (!handled[e]) {
				flow.state = pending[e].state.snapshot ();
				flow.exception (pending[e].value, pending[e].site);
			}
		}
		flow.state = normal;
	}
	private void statement(CoreStatement source) throws RuntimeLifetimeError, CoreError {
		if (!flow.state.reachable) {
			return;
		}
		if (source is CoreScope) {
			block (((CoreScope) source).body);
		} else if (source is CoreAsyncDelay) {
			var delay = (CoreAsyncDelay) source;
			value (delay.ticks);
			exception (graph.absent (), delay.body.runtime.error_type);
		} else if (source is CoreTaskAwaitStatement) {
			task_await (((CoreTaskAwaitStatement) source).operation);
		} else if (source is CoreAsyncOperationStatement) {
			async_operation (((CoreAsyncOperationStatement) source).operation);
		} else if (source is CoreEnumStore) {
			var store = (CoreEnumStore) source;
			write (place (store.destination), enum_value (store.producer));
		} else if (source is CoreEnumMatch) {
			var match = (CoreEnumMatch) source;
			enum_value (match.scrutinee);
			var entry = flow.state.snapshot ();
			RuntimeLifetimeState? joined = null;
			foreach (var arm in match.arms) {
				if (arm.bindings.length != 0) {
					unsupported_node ("Core enum matching requires exact payload lifetime bindings");
				}
				flow.state = entry.snapshot ();
				block (arm.body);
				if (joined == null) {
					joined = flow.state.snapshot ();
				} else {
					flow.merge (entry, joined, flow.state);
					joined = flow.state.snapshot ();
				}
			}
			if (joined != null) {
				flow.state = joined;
			}
		} else if (source is CoreTry) {
			guarded ((CoreTry) source);
		} else if (source is CoreThrow) {
			var thrown = (CoreThrow) source;
			var type = thrown.source.semantic_type as ClassType;
			if (type == null) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("Core throw lost its exception Class");
			}
			int failure = flow.read (thrown.source.ordinal);
			flow.write (thrown.source.ordinal, graph.absent ());
			exception (failure, type);
			flow.state.reachable = false;
		} else if (source is CoreIf) {
			var branch = (CoreIf) source;
			value (branch.condition);
			var entry = flow.state.snapshot ();
			block (branch.then_block);
			var left = flow.state;
			flow.state = entry.snapshot ();
			if (branch.else_block != null) {
				block (branch.else_block);
			}
			flow.merge (entry, left, flow.state);
		} else if (source is CoreWhile) {
			var loop = (CoreWhile) source;
			if (loop.has_sequence || loop.has_iteration) {
				unsupported_node ("Core iteration requires element lifetime effects");
			}
			flow.begin_loop ();
			value (loop.condition);
			block (loop.body);
			flow.begin_step ();
			if (loop.step != null) {
				block (loop.step);
			}
			flow.end_loop ();
		} else if (source is CoreBreak || source is CoreContinue) {
			flow.jump (source is CoreBreak);
		} else if (source is CoreConstructorObjectInitialization) {
			var construction = (CoreConstructorObjectInitialization) source;
			RuntimeLifetimeState? refused = construction.storage.fallible ? flow.state.snapshot () : null;
			int root = construction.storage.heap_allocated ? allocation (construction.storage.object_class, construction.allocation_context) : product (construction.storage.semantic_type);
			write (place (construction.target), invoke (construction.constructor, construction.arguments, null, root));
			if (refused != null) {
				flow.merge (refused, refused, flow.state);
			}
		} else if (source is CoreObjectConstruction) {
			var construction = (CoreObjectConstruction) source;
			int result = product (construction.storage.semantic_type);
			foreach (var initial in construction.initializers) {
				result = graph.replace (result, "f%d".printf (initial.field.ordinal), value (initial.value));
			}
			write (place (construction.target), result);
		} else if (source is CoreInitialize) {
			var initial = (CoreInitialize) source;
			if (initial.target is CoreLocalPlace && initial.target.semantic_type is ClassType && !owners.contains ((CoreLocalPlace) initial.target)) {
				unsupported_node ("Core borrowed Class locals require alias-sensitive storage effects");
			}
			write (place (initial.target), value (initial.value));
		} else if (source is CoreStore) {
			write (place (((CoreStore) source).target), value (((CoreStore) source).value));
		} else if (source is CoreOwnershipTransfer) {
			var transfer = (CoreOwnershipTransfer) source;
			write (place (transfer.destination.place), take (transfer.source));
		} else if (source is CoreOwnershipRearm) {
			var rearm = (CoreOwnershipRearm) source;
			write (place (rearm.owner.place), take (rearm.source, rearm.producer));
		} else if (source is CoreOwnershipRelease) {
			flow.write (((CoreOwnershipRelease) source).owner.place.ordinal, graph.absent ());
		} else if (source is CoreOwnedFieldTransfer) {
			var transfer = (CoreOwnedFieldTransfer) source;
			write (place (transfer.destination), take (transfer.source, transfer.producer));
		} else if (source is CoreAcquireStructParameter) {
			var acquired = (CoreAcquireStructParameter) source;
			write (place (acquired.destination), flow.read (parameter_binding (acquired.parameter.ordinal)));
		} else if (source is CoreStructAcquire) {
			var acquired = (CoreStructAcquire) source;
			write (place (acquired.field), take (acquired.source, acquired.producer));
		} else if (source is CoreStructInitialize) {
			var initial = (CoreStructInitialize) source;
			if (initial.producer != null) {
				write (place (initial.target), producer (initial.producer));
			} else {
				write (place (initial.target), product (initial.target.semantic_type));
				foreach (var child in initial.initializers) {
					statement (child);
				}
			}
		} else if (source is CoreStructResultStore) {
			var stored = (CoreStructResultStore) source;
			write (place (stored.destination), producer (stored.producer));
		} else if (source is CoreStructMove) {
			var moved = (CoreStructMove) source;
			write (place (moved.destination.place), take (moved.source));
		} else if (source is CoreStructCopy) {
			var copied = (CoreStructCopy) source;
			write (place (copied.destination), read (place (copied.source)));
		} else if (source is CoreRecordTake) {
			var taken = (CoreRecordTake) source;
			var storage = place (taken.field);
			int incoming = read (storage);
			write (storage, graph.absent ());
			write (place (taken.destination.place), incoming);
		} else if (source is CoreRecordReplace) {
			var replaced = (CoreRecordReplace) source;
			write (place (replaced.field), take (replaced.source, replaced.producer));
		} else if (source is CoreOwnedBufferExchange) {
			var exchange = (CoreOwnedBufferExchange) source;
			var left = place (exchange.left.place);
			var right = place (exchange.right.place);
			int old_left = read (left);
			int old_right = read (right);
			write (left, old_right);
			write (right, old_left);
		} else if (source is CoreCallStatement) {
			var call = (CoreCallStatement) source;
			invoke (call.target, call.arguments, call.receiver);
		} else if (source is CoreCCallStatement) {
			var call = (CoreCCallStatement) source;
			foreign_call (call.target, call.arguments);
		} else if (source is CoreValueStatement) {
			value (((CoreValueStatement) source).value);
		} else if (source is CoreOwnershipReturn) {
			var result = (CoreOwnershipReturn) source;
			graph.alternative (returned, take (result.source, result.producer));
			exit ();
			flow.state.reachable = false;
		} else if (source is CoreStructReturn) {
			graph.alternative (returned, producer (((CoreStructReturn) source).producer));
			exit ();
			flow.state.reachable = false;
		} else if (source is CoreReturn) {
			int result = value (((CoreReturn) source).value);
			graph.alternative (returned, graph_input (function.return_type) ? result : graph.absent ());
			exit ();
			flow.state.reachable = false;
		} else {
			unsupported_node ("Core statement requires its exact lifetime operation: " + source.get_type ().name ());
		}
	}
	private void inventory(CoreBlock block) throws RuntimeLifetimeError {
		if (block.text_extent != null) {
			region_id (block.text_extent);
		}
		foreach (var source in block.statements) {
			if (source is CoreObjectConstruction) {
				var construction = (CoreObjectConstruction) source;
				region_id (block.text_extent);
				if (construction.storage.scope != block || construction.target.text_extent != block.text_extent || construction.storage.region_ordinal != block.text_extent.ordinal || construction.storage.heap_allocated && construction.storage.cleanup_rank != construction.target.ordinal) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("Core object lifetime differs from its actual cleanup scope/rank");
				}
				objects.insert (construction.storage, construction.target);
			}
			if (source is CoreInitialize && ((CoreInitialize) source).value is CoreScopedAllocator) {
				var initial = (CoreInitialize) source;
				var local = initial.target as CoreLocalPlace;
				var factory = (CoreScopedAllocator) initial.value;
				region_id (block.text_extent);
				if (local == null || contexts.contains (local) || local.text_extent != block.text_extent || factory.loan.context_ordinal != local.ordinal || factory.loan.region_ordinal != block.text_extent.ordinal) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("Core scope declaration lost its exact factory and extent");
				}
				contexts.insert (local, factory);
				regions.context (local.ordinal, region_id (local.text_extent));
			}
			if (source is CoreTry) {
				var guarded = (CoreTry) source;
				inventory (guarded.body);
				foreach (var caught in guarded.catches) {
					inventory (caught.body);
				}
			} else if (source is CoreScope) {
				inventory (((CoreScope) source).body);
			} else if (source is CoreIf) {
				inventory (((CoreIf) source).then_block);
				if (((CoreIf) source).else_block != null) {
					inventory (((CoreIf) source).else_block);
				}
			} else if (source is CoreWhile) {
				inventory (((CoreWhile) source).body);
				if (((CoreWhile) source).step != null) {
					inventory (((CoreWhile) source).step);
				}
			}
		}
	}
	internal RuntimeLifetimeSummary incomplete(string reason) {
		graph.seal ();
		return new RuntimeLifetimeSummary (graph, graph.absent (), new HashTable<int, int> (direct_hash, direct_equal), new GenericArray<RuntimeLifetimeStore> (), reason);
	}
	internal RuntimeLifetimeSummary analyze() throws RuntimeLifetimeError, CoreError {
		inventory (function.body);
		returned = graph.join ();
		exceptional_result = graph.join ();
		flow.begin_try ();
		foreach (var owner in function.owned_locals) {
			if (owner.scope == null || owner.place.text_extent != owner.scope.text_extent || owner.object_storage != null && (owner.object_storage.scope != owner.scope || owner.object_storage.cleanup_rank != owner.place.ordinal)) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("Core owner lifetime differs from its actual cleanup scope/rank");
			}
			owners.insert (owner.place, true);
		}
		foreach (var parameter in function.parameters) {
			bool allocator = parameter.semantic_type.is_scoped_allocator ();
			bool owning = parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER || parameter.struct_value_contract != null && parameter.struct_value_contract.mode == StructValueMode.MOVE_VALUE;
			if (allocator || owning || graph_input (parameter.semantic_type)) {
				regions.input (parameter.ordinal, allocator);
			}
			int incoming = allocator || !owning && !graph_input (parameter.semantic_type) ? graph.absent () : graph.input (parameter.ordinal);
			int binding = parameter_binding (parameter.ordinal);
			flow.declare (binding, incoming);
			if (!owning && graph_input (parameter.semantic_type)) {
				initial_inputs.insert (binding, incoming);
				exits.insert (binding, graph.join ());
			}
		}
		if (function.implicit_receiver != null) {
			regions.input (-1);
			int incoming = graph.input (-1);
			flow.declare (-1, incoming);
			initial_inputs.insert (-1, incoming);
			exits.insert (-1, graph.join ());
		}
		foreach (var local in function.locals) {
			if (graph_input (local.semantic_type) || local.semantic_type.is_scoped_allocator () || owners.contains (local)) {
				regions.owner (local.ordinal, region_id (local.text_extent));
			}
			flow.declare (local.ordinal, local.incoming_parameter != null ? flow.read (parameter_binding (local.incoming_parameter.ordinal)) : local.semantic_type.is_struct_storage () ? product (local.semantic_type) : graph.absent ());
		}
		regions.seal ();
		block (function.body);
		if (flow.state.reachable) {
			graph.alternative (returned, graph.absent ());
			exit ();
		}
		int normal_exits = exit_count;
		var normal = flow.state.snapshot ();
		var escaped = flow.end_try ();
		if (escaped.length != 0 && function.throws_type == null && function.async_body == null) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("Core exception lifetime escapes a nonthrowing function");
		}
		foreach (var failure in escaped) {
			var type = exception_types.lookup (failure.site);
			if (type == null || !(function.throws_type != null && exception_subtype (type, function.throws_type) || function.async_body != null && exception_subtype (type, function.async_body.runtime.error_type))) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("Core exceptional result differs from its declared throws bound");
			}
			graph.alternative (exceptional_result, failure.value);
			flow.state = failure.state.snapshot ();
			exit ();
		}
		flow.state = normal;
		if (escaped.length == 0) {
			graph.alternative (exceptional_result, graph.absent ());
		}
		if (normal_exits == 0) {
			graph.alternative (returned, graph.absent ());
		}
		if (exit_count == 0) {
			foreach (int binding in exits.get_keys ()) {
				graph.alternative (exits.lookup (binding), initial_inputs.lookup (binding));
			}
		}
		int factory_result = -1;
		if (function.async_body != null) {
			var captures = new HashTable<string, int> (str_hash, str_equal);
			foreach (var parameter in function.parameters) {
				bool owning = parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER || parameter.struct_value_contract != null && parameter.struct_value_contract.mode == StructValueMode.MOVE_VALUE;
				captures.insert ("f%d".printf (parameter.ordinal), graph_input (parameter.semantic_type) || owning ? graph.input (parameter.ordinal) : graph.absent ());
			}
			var fields = new HashTable<string, int> (str_hash, str_equal);
			fields.insert ("f0", returned);
			fields.insert ("f1", exceptional_result);
			fields.insert ("f2", graph.product (new GenericArray<RuntimeScopeOrigin> (), captures));
			factory_result = graph.product (new GenericArray<RuntimeScopeOrigin> (), fields);
		}
		graph.seal ();
		if (unsupported != "") {
			return new RuntimeLifetimeSummary (graph, returned, new HashTable<int, int> (direct_hash, direct_equal), stores, unsupported);
		}
		foreach (var obligation in obligations) {
			if (graph.requirements (obligation.value).length != 0) {
				regions.validate (graph, obligation.value, obligation.destination);
			}
		}
		foreach (var origin in graph.requirements (returned)) {
			if (origin.kind == RuntimeScopeOriginKind.LOCAL_CONTEXT) {
				throw new RuntimeLifetimeError.LOCAL_ESCAPE ("result retains a scoped local allocation");
			}
		}
		foreach (var origin in graph.requirements (exceptional_result)) {
			if (origin.kind == RuntimeScopeOriginKind.LOCAL_CONTEXT) {
				throw new RuntimeLifetimeError.LOCAL_ESCAPE ("exception retains a scoped local allocation");
			}
		}
		var updates = new HashTable<int, int> (direct_hash, direct_equal);
		int borrowed_inputs = 0;
		foreach (int binding in exits.get_keys ()) {
			borrowed_inputs++;
			int updated = exits.lookup (binding);
			var original = graph.requirements (initial_inputs.lookup (binding));
			var output = graph.requirements (updated);
			bool changed = original.length != output.length;
			if (!changed) {
				for (int i = 0; i < original.length; i++) {
					if (original[i].identity () != output[i].identity ()) {
						changed = true;
					}
				}
			}
			if (changed || stores.length != 0) {
				updates.insert (binding == -1 ? -1 : -binding - 2, updated);
			}
			foreach (var origin in output) {
				if (origin.kind == RuntimeScopeOriginKind.LOCAL_CONTEXT) {
					throw new RuntimeLifetimeError.LOCAL_ESCAPE ("input storage retains a scoped local allocation");
				}
			}
		}
		if (borrowed_inputs > 1 && stores.length != 0) {
			unsupported_node ("Core mutating borrowed aliases require alias-sensitive effects");
		}
		if (function.async_body != null) {
			if (updates.size () != 0 || stores.length != 0) {
				unsupported_node ("Core async factory needs deferred borrowed-storage effects");
			}
			return new RuntimeLifetimeSummary (graph, factory_result, new HashTable<int, int> (direct_hash, direct_equal), new GenericArray<RuntimeLifetimeStore> (), unsupported);
		}
		return new RuntimeLifetimeSummary (graph, returned, updates, stores, unsupported, function.throws_type == null ? -1 : exceptional_result);
	}
}
}
