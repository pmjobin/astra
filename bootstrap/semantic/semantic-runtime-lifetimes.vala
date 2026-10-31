// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;

namespace Astra.Semantic {
private class SemanticRuntimeStorage : Object {
	internal int binding;
	internal string path;
	internal SemanticRuntimeStorage (int binding, string path = "") {
		this.binding = binding;
		this.path = path;
	}
}
private class SemanticRuntimeObligation : Object {
	internal int value;
	internal int destination;
	internal SourceSpan span;
	internal SemanticRuntimeObligation (int value, int destination, SourceSpan span) {
		this.value = value;
		this.destination = destination;
		this.span = span;
	}
}
internal class SemanticRuntimeLifetimes : Object {
	private CheckedProgram program;
	private HashTable<FunctionSymbol, CheckedFunction> definitions = new HashTable<FunctionSymbol, CheckedFunction> (direct_hash, direct_equal);
	private HashTable<FunctionSymbol, bool> visiting = new HashTable<FunctionSymbol, bool> (direct_hash, direct_equal);
	private Diagnostic? diagnostic;
	internal static Diagnostic? check(CheckedProgram program) {
		var analysis = new SemanticRuntimeLifetimes ();
		analysis.program = program;
		foreach (var definition in program.all_definitions ()) {
			definition.runtime_lifetimes = null;
			analysis.definitions.insert (definition.symbol, definition);
		}
		foreach (var definition in program.all_definitions ()) {
			analysis.summary (definition.symbol);
			if (analysis.diagnostic != null) {
				return analysis.diagnostic;
			}
		}
		return null;
	}
	internal RuntimeLifetimeSummary? summary(FunctionSymbol? symbol) {
		if (symbol == null) {
			return null;
		}
		var definition = definitions.lookup (symbol);
		if (definition == null || visiting.contains (symbol)) {
			return null;
		}
		if (definition.runtime_lifetimes != null) {
			return definition.runtime_lifetimes;
		}
		if (definition.native_declaration != null) {
			try {
				definition.runtime_lifetimes = definition.native_declaration.runtime_lifetime_summary ();
			} catch (RuntimeLifetimeError failure) {
				diagnostic = new Diagnostic (symbol.span, "native lifetime contract: " + failure.message);
			}
			return definition.runtime_lifetimes;
		}
		visiting.insert (symbol, true);
		var body = new SemanticRuntimeLifetimeBody (this, program, definition);
		try {
			definition.runtime_lifetimes = body.analyze ();
		} catch (RuntimeLifetimeError failure) {
			if (failure is RuntimeLifetimeError.LOCAL_ESCAPE) {
				diagnostic = new Diagnostic (body.current_span, failure.message);
			}
			definition.runtime_lifetimes = body.incomplete (failure.message);
		}
		if (body.requires_scope && !definition.runtime_lifetimes.complete && diagnostic == null) {
			diagnostic = new Diagnostic (body.current_span, "scoped lifetime proof is incomplete: " + definition.runtime_lifetimes.limitation);
		}
		visiting.remove (symbol);
		return definition.runtime_lifetimes;
	}
}
private class SemanticRuntimeLifetimeBody : Object {
	private SemanticRuntimeLifetimes analysis;
	private CheckedProgram program;
	private CheckedFunction definition;
	private RuntimeLifetimeFlow flow = new RuntimeLifetimeFlow ();
	private RuntimeLifetimeRegions regions = new RuntimeLifetimeRegions ();
	private HashTable<LexicalRegion, int> region_ids = new HashTable<LexicalRegion, int> (direct_hash, direct_equal);
	private HashTable<LexicalObjectStorageSymbol, LocalSymbol> objects = new HashTable<LexicalObjectStorageSymbol, LocalSymbol> (direct_hash, direct_equal);
	private HashTable<int, int> initial_inputs = new HashTable<int, int> (direct_hash, direct_equal);
	private HashTable<int, int> exits = new HashTable<int, int> (direct_hash, direct_equal);
	private GenericArray<RuntimeLifetimeStore> stores = new GenericArray<RuntimeLifetimeStore> ();
	private GenericArray<SemanticRuntimeObligation> obligations = new GenericArray<SemanticRuntimeObligation> ();
	private string unsupported = "";
	private int returned;
	private int exceptional_result;
	private HashTable<int, ClassType> exception_types = new HashTable<int, ClassType> (direct_hash, direct_equal);
	private int exit_count;
	private bool scope_requested;
	internal bool requires_scope { get { return scope_requested || graph.has_scope_roots; } }
	internal SourceSpan current_span;
	internal SemanticRuntimeLifetimeBody (SemanticRuntimeLifetimes analysis, CheckedProgram program, CheckedFunction definition) {
		this.analysis = analysis;
		this.program = program;
		this.definition = definition;
		current_span = definition.span;
		scope_requested = scoped_statement (definition.body) || scoped_type (definition.symbol.return_type) || definition.symbol.implicit_receiver != null && scoped_type (definition.symbol.implicit_receiver.semantic_type) || definition.symbol.throws_type != null && scoped_type (definition.symbol.throws_type);
		foreach (var parameter in definition.symbol.parameters) {
			scope_requested |= scoped_type (parameter.semantic_type);
		}
		foreach (var local in definition.locals) {
			scope_requested |= scoped_type (local.semantic_type);
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
	private int region_id(LexicalRegion region) throws RuntimeLifetimeError {
		if (!region_ids.contains (region)) {
			int parent = region.parent == null ? -1 : region_id (region.parent);
			region_ids.insert (region, regions.add_region (parent));
		}
		return region_ids.lookup (region);
	}
	private static bool graph_input(SemanticType type) {
		return !(type is HandleType && ((HandleType) type).context_mode != "") && (type is ClassType || type is ReceiverType || type is HandleType || type.is_struct_storage () || type is TypeParameterType || type is TaskType);
	}
	private NativeInstanceSymbol? instance(SemanticType type) {
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
			var object_class = owner as ClassSymbol;
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
				if (field.is_owned_field || field.semantic_type.is_struct_storage ()) {
					following.add (field.semantic_type);
				}
			}
		}
		if (type is GenericStructApplicationType) {
			var record = (GenericStructApplicationType) type;
			foreach (var field in record.definition.fields) {
				var actual = record.field_type (field);
				if (field.is_owned_field || actual.is_struct_storage ()) {
					following.add (actual);
				}
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
	private bool scoped_arguments(GenericArray<CheckedExpression> arguments, CheckedExpression? receiver = null) {
		if (scoped_expression (receiver)) {
			return true;
		}
		foreach (var argument in arguments) {
			if (scoped_expression (argument)) {
				return true;
			}
		}
		return false;
	}
	private bool scoped_producer(CheckedStructProducer producer) {
		if (producer is CheckedStructInvocationResult) {
			return scoped_expression (((CheckedStructInvocationResult) producer).invocation);
		}
		if (producer is CheckedStructCallResult) {
			var call = (CheckedStructCallResult) producer;
			return scoped_arguments (call.arguments, call.receiver);
		}
		if (producer is CheckedStructProjectionProducer) {
			return scoped_producer (((CheckedStructProjectionProducer) producer).source);
		}
		if (producer is CheckedStructAwait) {
			return scoped_expression (((CheckedStructAwait) producer).operation);
		}
		return false;
	}
	private bool scoped_initializers(GenericArray<CheckedFieldInitializer> fields) {
		foreach (var field in fields) {
			if (scoped_expression (field.expression) || field.initializer != null && scoped_initializers (field.initializer.fields) || field.producer != null && scoped_producer (field.producer)) {
				return true;
			}
		}
		return false;
	}
	private bool scoped_expression(CheckedExpression? value) {
		if (value == null) {
			return false;
		}
		if (scoped_type (value.semantic_type)) {
			return true;
		}
		if (value is CheckedOwnedObjectResultConstruction) {
			var construction = (CheckedOwnedObjectResultConstruction) value;
			return scoped_type (construction.storage.semantic_type) || scoped_arguments (construction.arguments);
		}
		if (value is CheckedOwnedBufferAllocate) {
			var allocation = (CheckedOwnedBufferAllocate) value;
			return allocation.allocation_context != null && allocation.allocation_context.semantic_type.is_scoped_allocator () || scoped_expression (allocation.count);
		}
		if (value is CheckedTaskCreate) {
			var creation = (CheckedTaskCreate) value;
			return creation.allocation_context != null && creation.allocation_context.semantic_type.is_scoped_allocator () || scoped_arguments (creation.arguments);
		}
		if (value is CheckedTaskAwait) {
			return scoped_expression (((CheckedTaskAwait) value).child);
		}
		if (value is CheckedCallExpression) {
			var call = (CheckedCallExpression) value;
			return scoped_arguments (call.arguments, call.receiver);
		}
		if (value is CheckedOwnedArgument) {
			var argument = (CheckedOwnedArgument) value;
			return scoped_expression ((CheckedExpression?) argument.transfer ?? argument.producer);
		}
		if (value is CheckedStructArgument) {
			return scoped_producer (((CheckedStructArgument) value).producer);
		}
		if (value is CheckedStructProjectionValue) {
			return scoped_producer (((CheckedStructProjectionValue) value).source);
		}
		if (value is CheckedBinaryExpression) {
			return scoped_expression (((CheckedBinaryExpression) value).left) || scoped_expression (((CheckedBinaryExpression) value).right);
		}
		if (value is CheckedShortCircuitExpression) {
			return scoped_expression (((CheckedShortCircuitExpression) value).left) || scoped_expression (((CheckedShortCircuitExpression) value).right);
		}
		if (value is CheckedComparisonChain) {
			foreach (var operand in ((CheckedComparisonChain) value).operands) {
				if (scoped_expression (operand)) {
					return true;
				}
			}
		}
		if (value is CheckedPrefixExpression) {
			return scoped_expression (((CheckedPrefixExpression) value).operand);
		}
		if (value is CheckedIntegerConversionExpression) {
			return scoped_expression (((CheckedIntegerConversionExpression) value).operand);
		}
		if (value is CheckedFloatConversionExpression) {
			return scoped_expression (((CheckedFloatConversionExpression) value).operand);
		}
		if (value is CheckedNumericConversionExpression) {
			return scoped_expression (((CheckedNumericConversionExpression) value).operand);
		}
		if (value is CheckedLengthExpression) {
			var length = (CheckedLengthExpression) value;
			return scoped_expression (length.slice) || length.array != null && scoped_type (length.array.semantic_type);
		}
		return false;
	}
	// Inventory runs before inference, including bodies whose operation family
	// is still unsupported. An opaque statement cannot hide scoped allocation.
	private bool scoped_statement(CheckedStatement source) {
		if (source is CheckedBlockStatement) {
			foreach (var child in ((CheckedBlockStatement) source).statements) {
				if (scoped_statement (child)) {
					return true;
				}
			}
		} else if (source is CheckedIf) {
			var branch = (CheckedIf) source;
			return scoped_expression (branch.condition) || scoped_statement (branch.then_body) || branch.else_body != null && scoped_statement (branch.else_body);
		} else if (source is CheckedWhile) {
			var loop = (CheckedWhile) source;
			return scoped_expression (loop.condition) || scoped_statement (loop.body) || loop.step != null && scoped_statement (loop.step);
		} else if (source is CheckedTry) {
			var guarded = (CheckedTry) source;
			if (scoped_statement (guarded.body)) {
				return true;
			}
			foreach (var caught in guarded.catches) {
				if (scoped_statement (caught.body)) {
					return true;
				}
			}
		} else if (source is CheckedEnumMatch) {
			foreach (var arm in ((CheckedEnumMatch) source).arms) {
				if (scoped_statement (arm.body)) {
					return true;
				}
			}
		} else if (source is CheckedConstructorObjectInitialization) {
			var construction = (CheckedConstructorObjectInitialization) source;
			return scoped_type (construction.storage.semantic_type) || construction.allocation_context != null && construction.allocation_context.semantic_type.is_scoped_allocator () || scoped_arguments (construction.arguments);
		} else if (source is CheckedObjectConstruction) {
			return scoped_initializers (((CheckedObjectConstruction) source).initializers);
		} else if (source is CheckedLocalDeclaration) {
			return scoped_expression (((CheckedLocalDeclaration) source).initializer);
		} else if (source is CheckedStructLocalDeclaration) {
			return scoped_initializers (((CheckedStructLocalDeclaration) source).initializers);
		} else if (source is CheckedStructResultStore) {
			return scoped_producer (((CheckedStructResultStore) source).producer);
		} else if (source is CheckedStructReturn) {
			return scoped_producer (((CheckedStructReturn) source).producer);
		} else if (source is CheckedOwnershipReturn) {
			var returned = (CheckedOwnershipReturn) source;
			return scoped_expression ((CheckedExpression?) returned.transfer ?? returned.producer);
		} else if (source is CheckedReturnStatement) {
			return scoped_expression (((CheckedReturnStatement) source).expression);
		} else if (source is CheckedValueStatement) {
			return scoped_expression (((CheckedValueStatement) source).value);
		} else if (source is CheckedCallStatement) {
			var call = (CheckedCallStatement) source;
			return scoped_arguments (call.arguments, call.receiver);
		} else if (source is CheckedFieldInitialize) {
			return scoped_expression (((CheckedFieldInitialize) source).value);
		} else if (source is CheckedOwnedFieldTransfer) {
			return scoped_expression (((CheckedOwnedFieldTransfer) source).incoming);
		} else if (source is CheckedAssignment) {
			return scoped_expression (((CheckedAssignment) source).expression);
		} else if (source is CheckedFieldAssignment) {
			return scoped_expression (((CheckedFieldAssignment) source).expression);
		} else if (source is CheckedOwnershipRearmAssignment) {
			return scoped_expression (((CheckedOwnershipRearmAssignment) source).incoming);
		} else if (source is CheckedOwnedBufferReplace) {
			return scoped_expression (((CheckedOwnedBufferReplace) source).incoming);
		}
		return false;
	}
	private int empty_product(SemanticType type, CheckedExpression? context = null) throws RuntimeLifetimeError {
		var roots = new GenericArray<RuntimeScopeOrigin> ();
		var anchor = context_origin (context);
		if (anchor != null) {
			roots.add (anchor);
		}
		var fields = new HashTable<string, int> (str_hash, str_equal);
		var owner = instance (type);
		if (owner != null) {
			if (owner is ClassSymbol && ((ClassSymbol) owner).parent_class != null) {
				unsupported_node ("inherited field paths require nominal owner identities");
			}
			foreach (var field in owner.fields) {
				fields.insert ("f%d".printf (field.ordinal), graph.absent ());
			}
		}
		if (type is GenericStructApplicationType) {
			foreach (var field in ((GenericStructApplicationType) type).definition.fields) {
				fields.insert ("f%d".printf (field.ordinal), graph.absent ());
			}
		}
		return graph.product (roots, fields);
	}
	private int allocation(ClassSymbol owner, CheckedExpression? context) throws RuntimeLifetimeError {
		var policy = owner.allocation_policy;
		var handle = context == null ? null : context.semantic_type as HandleType;
		if (policy != null && policy.kind == AllocationKind.CONTEXT ? !policy.valid () || handle == null || handle.context_mode != policy.context_mode : context != null) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("allocation lifetime requires the exact selected allocator context mode");
		}
		return empty_product (owner.semantic_type, context);
	}
	private static string field_path(StructLeafPath path) {
		var result = new StringBuilder ();
		for (int i = 0; i < path.depth; i++) {
			if (i != 0) {
				result.append (".");
			}
			result.append_printf ("f%d", path.field_ordinal (i));
		}
		return result.str;
	}
	private RuntimeScopeOrigin? context_origin(CheckedExpression? expression) throws RuntimeLifetimeError {
		if (expression == null || !expression.semantic_type.is_scoped_allocator ()) {
			return null;
		}
		if (expression is CheckedParameterReferenceExpression) {
			return new RuntimeScopeOrigin.context_input (((CheckedParameterReferenceExpression) expression).parameter.ordinal);
		}
		LocalSymbol? local = null;
		if (expression is CheckedLocalReferenceExpression) {
			local = ((CheckedLocalReferenceExpression) expression).local;
		} else if (expression is CheckedOwnedBorrowValue) {
			local = ((CheckedOwnedBorrowValue) expression).source;
		}
		if (local == null || local.scoped_backing == null) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("scoped allocation requires its exact context declaration or borrowed formal");
		}
		return new RuntimeScopeOrigin.local (local.ordinal, region_id (local.lexical_region));
	}
	private SemanticRuntimeStorage? reference(CheckedExpression? expression) {
		if (expression is CheckedStructProjectionValue) {
			var projected = (CheckedStructProjectionValue) expression;
			var storage = producer_reference (projected.source);
			if (storage != null) {
				storage.path += (storage.path == "" ? "" : ".") + field_path (projected.path);
			}
			return storage;
		}
		if (expression is CheckedFieldReferenceExpression) {
			var field = (CheckedFieldReferenceExpression) expression;
			return field_storage (new SemanticRuntimeStorage (field.local.ordinal), field.field);
		}
		if (expression is CheckedOwnedFieldBorrow) {
			return place (((CheckedOwnedFieldBorrow) expression).source);
		}
		if (expression is CheckedLocalReferenceExpression) {
			return new SemanticRuntimeStorage (((CheckedLocalReferenceExpression) expression).local.ordinal);
		}
		if (expression is CheckedParameterReferenceExpression) {
			return new SemanticRuntimeStorage (parameter_binding (((CheckedParameterReferenceExpression) expression).parameter.ordinal));
		}
		if (expression is CheckedThisExpression) {
			return new SemanticRuntimeStorage (-1);
		}
		if (expression is CheckedObjectReferenceExpression) {
			var local = objects.lookup (((CheckedObjectReferenceExpression) expression).storage);
			return local == null ? null : new SemanticRuntimeStorage (local.ordinal);
		}
		if (expression is CheckedOwnedBorrowValue) {
			return new SemanticRuntimeStorage (((CheckedOwnedBorrowValue) expression).source.ordinal);
		}
		if (expression is CheckedWithReference) {
			return new SemanticRuntimeStorage (((CheckedWithReference) expression).contract.source.ordinal);
		}
		if (expression is CheckedClassUpcast) {
			return reference (((CheckedClassUpcast) expression).reference);
		}
		if (expression is CheckedObjectReceiverExpression) {
			return reference (((CheckedObjectReceiverExpression) expression).reference);
		}
		if (expression is CheckedReceiverAddressExpression) {
			var receiver = (CheckedReceiverAddressExpression) expression;
			return receiver.local == null ? place(receiver.receiver_place) : new SemanticRuntimeStorage (receiver.local.ordinal);
		}
		if (expression is CheckedLoadExpression) {
			return place (((CheckedLoadExpression) expression).source);
		}
		return null;
	}
	private SemanticRuntimeStorage? producer_reference(CheckedStructProducer producer) {
		if (producer is CheckedStructSnapshot) {
			return place (((CheckedStructSnapshot) producer).source);
		}
		if (producer is CheckedStructBorrowSnapshot) {
			return place (((CheckedStructBorrowSnapshot) producer).source);
		}
		if (producer is CheckedStructProjectionProducer) {
			var projected = (CheckedStructProjectionProducer) producer;
			var storage = producer_reference (projected.source);
			if (storage != null) {
				storage.path += (storage.path == "" ? "" : ".") + field_path (projected.path);
			}
			return storage;
		}
		return null;
	}
	private SemanticRuntimeStorage? field_storage(SemanticRuntimeStorage? storage, FieldSymbol field) {
		if (storage != null) {
			storage.path += (storage.path == "" ? "" : ".") + "f%d".printf (field.ordinal);
		}
		return storage;
	}
	private SemanticRuntimeStorage? place(CheckedPlace? source) {
		if (source is CheckedLocalPlace) {
			return new SemanticRuntimeStorage (((CheckedLocalPlace) source).local.ordinal);
		}
		if (source is CheckedFieldPlace) {
			return field_storage (place (((CheckedFieldPlace) source).aggregate), ((CheckedFieldPlace) source).field);
		}
		if (source is CheckedGenericStructFieldPlace) {
			return field_storage (place (((CheckedGenericStructFieldPlace) source).aggregate), ((CheckedGenericStructFieldPlace) source).field);
		}
		if (source is CheckedReceiverFieldPlace) {
			return field_storage (reference (((CheckedReceiverFieldPlace) source).receiver), ((CheckedReceiverFieldPlace) source).field);
		}
		if (source is CheckedObjectFieldPlace) {
			return field_storage (reference (((CheckedObjectFieldPlace) source).reference), ((CheckedObjectFieldPlace) source).field);
		}
		unsupported_node ("indirect or indexed storage requires an exact owning path");
		return null;
	}
	private int read(SemanticRuntimeStorage? storage) throws RuntimeLifetimeError {
		if (storage == null) {
			unsupported_node ("value has no exact source storage");
			return graph.absent ();
		}
		int result = flow.read (storage.binding);
		return storage.path == "" ? result : graph.project (result, storage.path);
	}
	private int replace_path(int root, string path, int incoming) throws RuntimeLifetimeError {
		int dot = path.index_of_char ('.');
		if (dot < 0) {
			return graph.replace (root, path, incoming);
		}
		string head = path.substring (0, dot);
		return graph.replace (root, head, replace_path (graph.project (root, head), path.substring (dot + 1), incoming));
	}
	private void write(SemanticRuntimeStorage? storage, int incoming, SourceSpan span, bool effect = true) throws RuntimeLifetimeError {
		if (storage == null) {
			unsupported_node ("write has no exact destination storage");
			return;
		}
		int value = storage.path == "" ? incoming : replace_path (flow.read (storage.binding), storage.path, incoming);
		flow.write (storage.binding, value);
		if (storage.binding >= 0) {
			obligations.add (new SemanticRuntimeObligation (value, storage.binding, span));
		} else if (effect) {
			stores.add (new RuntimeLifetimeStore (storage.binding == -1 ? -1 : -storage.binding - 2, incoming));
		}
	}
	private int invoke(DirectCallableSymbol? target, GenericArray<CheckedExpression> arguments, CheckedExpression? receiver, SourceSpan span, int constructed = -1) throws RuntimeLifetimeError {
		var inputs = new HashTable<int, int> (direct_hash, direct_equal);
		var contexts = new HashTable<int, RuntimeScopeOrigin> (direct_hash, direct_equal);
		var destinations = new HashTable<int, SemanticRuntimeStorage> (direct_hash, direct_equal);
		var pending = new HashTable<int, int> (direct_hash, direct_equal);
		var commits = new GenericArray<LocalSymbol> ();
		if (receiver != null) {
			inputs.insert (-1, value (receiver));
			var storage = reference (receiver);
			if (storage != null) {
				destinations.insert (-1, storage);
				pending.insert (-1, flow.read (storage.binding));
			}
		} else if (constructed >= 0) {
			inputs.insert (-1, constructed);
		}
		for (int i = 0; i < arguments.length; i++) {
			var argument = arguments[i] as CheckedOwnedArgument;
			if (argument != null && argument.transfer != null) {
				var local = argument.transfer.source;
				inputs.insert (i, flow.read (local.ordinal));
				commits.add (local);
			} else {
				inputs.insert (i, value (arguments[i]));
			} var anchor = context_origin (arguments[i]);
			if (anchor != null) {
				contexts.insert (i, anchor);
			}
			var destination = reference (arguments[i]);
			if (destination != null) {
				destinations.insert (i, destination);
				pending.insert (i, flow.read (destination.binding));
			}
		}
		// Named inputs stay reserved while later arguments may throw. The call
		// consumes them only after every argument has been evaluated.
		foreach (var local in commits) {
			flow.write (local.ordinal, graph.absent ());
		}
		foreach (int parameter in pending.get_keys ()) {
			if (parameter >= 0 && target != null && parameter < target.parameters.length && target.parameters[parameter].pointer_contract == PointerParameterContract.OWNED_TRANSFER) {
				continue;
			}
			if (flow.read (destinations.lookup (parameter).binding) != pending.lookup (parameter)) {
				unsupported_node ("argument evaluation changes a pending borrowed owner; alias-sensitive call effects are required");
			}
		}
		if (target is CFunctionSymbol) {
			var metadata = ((CFunctionSymbol) target).metadata;
			bool admitted = receiver == null && constructed < 0 && arguments.length == target.parameters.length && RuntimeForeignLifetimes.result (target.return_type, metadata.owned_result == null ? null : metadata.owned_result.cleanup.external_symbol);
			foreach (var parameter in target.parameters) {
				admitted = admitted && RuntimeForeignLifetimes.input (parameter.semantic_type, parameter.pointer_contract, metadata.owned_result != null);
			}
			if (!admitted) {
				unsupported_node ("foreign call requires an exact owner/pointer/callback lifetime effect");
			}
			return graph.absent ();
		}
		var summary = analysis.summary (target as FunctionSymbol);
		if (summary == null || !summary.complete || target is FunctionSymbol && ((FunctionSymbol) target).dispatch_kind != ClassDispatchKind.DIRECT) {
			unsupported_node ("call requires a complete direct lifetime summary: " + (target == null ? "unknown" : target.name));
			return constructed >= 0 ? constructed : graph.absent ();
		}
		for (uint i = 0; i < summary.store_count; i++) {
			var store = summary.store (i);
			int incoming = summary.equations.instantiate (store.value, graph, inputs, contexts);
			var destination = destinations.lookup (store.parameter);
			if (destination == null) {
				if (!(constructed >= 0 && store.parameter == -1)) {
					unsupported_node ("call store requires its actual destination cleanup extent");
				}
			} else if (destination.binding >= 0) {
				obligations.add (new SemanticRuntimeObligation (incoming, destination.binding, span));
			} else {
				stores.add (new RuntimeLifetimeStore (destination.binding == -1 ? -1 : -destination.binding - 2, incoming));
			}
		}
		var updates = summary.updated_inputs ();
		int result = constructed >= 0 ? constructed : summary.equations.instantiate (summary.result, graph, inputs, contexts);
		for (int i = 0; i < updates.length; i++) {
			int parameter = updates[i];
			int updated = summary.equations.instantiate (summary.update (parameter), graph, inputs, contexts);
			if (constructed >= 0 && parameter == -1) {
				result = updated;
			} else {
				write (destinations.lookup (parameter), updated, span, false);
			}
		}
		var callable = target as FunctionSymbol;
		if (callable != null && callable.throws_type != null) {
			if (!summary.has_exception) {
				unsupported_node ("throwing call requires its exact exceptional lifetime result");
			} else {
				exception (summary.equations.instantiate (summary.exception, graph, inputs, contexts), callable.throws_type);
			}
		} else if (summary.has_exception) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("nonthrowing call has an exceptional lifetime result");
		}
		return result;
	}
	// A cold task carries separate future success/error values and all
	// captures. Observation projects the outcome; moving/dropping the task
	// retains the complete frame/capture debt until that owned operation.
	private int task_create(CheckedTaskCreate creation) throws RuntimeLifetimeError {
		var inputs = new HashTable<int, int> (direct_hash, direct_equal);
		var contexts = new HashTable<int, RuntimeScopeOrigin> (direct_hash, direct_equal);
		var commits = new GenericArray<LocalSymbol> ();
		for (int p = 0; p < creation.arguments.length; p++) {
			var argument = creation.arguments[p] as CheckedOwnedArgument;
			if (argument != null && argument.transfer != null) {
				inputs.insert (p, flow.read (argument.transfer.source.ordinal));
				commits.add (argument.transfer.source);
			} else if (creation.arguments[p] is CheckedStructArgument && ((CheckedStructArgument) creation.arguments[p]).producer is CheckedStructMoveProducer) {
				var local = ((CheckedStructMoveProducer) ((CheckedStructArgument) creation.arguments[p]).producer).source;
				inputs.insert (p, flow.read (local.ordinal));
				commits.add (local);
			} else {
				inputs.insert (p, value (creation.arguments[p]));
			} var context = context_origin (creation.arguments[p]);
			if (context != null) {
				contexts.insert (p, context);
			}
		}
		var summary = analysis.summary (creation.target);
		if (summary == null || !summary.complete || summary.has_exception || summary.store_count != 0 || summary.updated_inputs ().length != 0) {
			unsupported_node ("task creation requires its complete cold-frame lifetime summary");
			return graph.absent ();
		}
		if (creation.checked_admission) {
			exception (graph.absent (), creation.target.async_body.runtime.error_type);
		}
		foreach (var local in commits) {
			flow.write (local.ordinal, graph.absent ());
		}
		int task = summary.equations.instantiate (summary.result, graph, inputs, contexts);
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
	private int task_await(CheckedTaskAwait operation) throws RuntimeLifetimeError {
		value (operation.bridge_executor);
		int task = value (operation.child);
		if (operation.discard) {
			return graph.absent ();
		}
		var type = operation.child.semantic_type as TaskType;
		if (type == null) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("task observation lost its exact typed result contract");
		}
		exception (graph.project (task, "f1"), type.exception_bound ?? type.runtime.error_type);
		return graph.project (task, "f0");
	}
	private int async_operation(CheckedAsyncOperation operation) throws RuntimeLifetimeError {
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
	private int enum_value(CheckedEnumProducer producer) throws RuntimeLifetimeError {
		if (producer is CheckedAsyncRun) {
			return async_operation (((CheckedAsyncRun) producer).operation);
		}
		if (producer is CheckedEnumSnapshot && producer.definition.value_fields ().length == 0) {
			return flow.read (((CheckedEnumSnapshot) producer).source.ordinal);
		}
		unsupported_node ("enum lifetime requires its exact copied/owning operation");
		return graph.absent ();
	}
	private int initializer(SemanticType type, GenericArray<CheckedFieldInitializer> initializers) throws RuntimeLifetimeError {
		int result = empty_product (type);
		foreach (var field in initializers) {
			int incoming = field.initializer != null ? initializer(field.initializer.semantic_type, field.initializer.fields) : field.producer != null ? producer(field.producer) : value (field.expression);
			result = graph.replace (result, "f%d".printf (field.field.ordinal), incoming);
		}
		return result;
	}
	private int producer(CheckedStructProducer source) throws RuntimeLifetimeError {
		if (source is CheckedStructAwait) {
			return task_await (((CheckedStructAwait) source).operation);
		}
		if (source is CheckedStructMoveProducer) {
			var local = ((CheckedStructMoveProducer) source).source;
			int result = flow.read (local.ordinal);
			flow.write (local.ordinal, graph.absent ());
			return result;
		}
		if (source is CheckedStructSnapshot) {
			return read (place (((CheckedStructSnapshot) source).source));
		}
		if (source is CheckedStructBorrowSnapshot) {
			return read (place (((CheckedStructBorrowSnapshot) source).source));
		}
		if (source is CheckedStructCallResult) {
			var call = (CheckedStructCallResult) source;
			return invoke (call.target, call.arguments, call.receiver, source.span);
		}
		if (source is CheckedStructInvocationResult) {
			return value (((CheckedStructInvocationResult) source).invocation);
		}
		if (source is CheckedStructProjectionProducer) {
			var projected = (CheckedStructProjectionProducer) source;
			return graph.project (producer (projected.source), field_path (projected.path));
		}
		unsupported_node ("record producer requires its exact lifetime operation");
		return graph.absent ();
	}
	private int value(CheckedExpression? source) throws RuntimeLifetimeError {
		if (source == null) {
			return graph.absent ();
		}
		current_span = source.span;
		if (source is CheckedFieldReferenceExpression) {
			int incoming = read (reference (source));
			if (graph_input (source.semantic_type)) {
				return incoming;
			}
			if (!(source.semantic_type.kind == TypeKind.BOOL || source.semantic_type is IntegerType || source.semantic_type is FloatingType || source.semantic_type is VectorType)) {
				unsupported_node ("field reference requires its exact nonowning value lifetime");
			}
			return graph.absent ();
		}
		if (source is CheckedOwnershipMove) {
			var local = ((CheckedOwnershipMove) source).source;
			int result = flow.read (local.ordinal);
			flow.write (local.ordinal, graph.absent ());
			return result;
		}
		if (source is CheckedOwnedArgument) {
			var argument = (CheckedOwnedArgument) source;
			return value ((CheckedExpression?) argument.transfer ?? argument.producer);
		}
		if (source is CheckedStructArgument) {
			return producer (((CheckedStructArgument) source).producer);
		}
		if (source is CheckedOwnedFieldBorrow) {
			return read (place (((CheckedOwnedFieldBorrow) source).source));
		}
		if (source is CheckedOwnedBufferBorrow) {
			return flow.read (((CheckedOwnedBufferBorrow) source).source.ordinal);
		}
		if (source is CheckedLocalReferenceExpression || source is CheckedParameterReferenceExpression || source is CheckedThisExpression || source is CheckedObjectReferenceExpression || source is CheckedOwnedBorrowValue || source is CheckedClassUpcast || source is CheckedObjectReceiverExpression || source is CheckedReceiverAddressExpression || source is CheckedWithReference) {
			return read (reference (source));
		}
		if (source is CheckedTaskCreate) {
			return task_create ((CheckedTaskCreate) source);
		}
		if (source is CheckedTaskMove) {
			var local = ((CheckedTaskMove) source).source;
			int incoming = flow.read (local.ordinal);
			flow.write (local.ordinal, graph.absent ());
			return incoming;
		}
		if (source is CheckedTaskBorrow) {
			return flow.read (((CheckedTaskBorrow) source).source.ordinal);
		}
		if (source is CheckedExecutorBorrow) {
			return graph.absent ();
		}
		if (source is CheckedTaskAwait) {
			return task_await ((CheckedTaskAwait) source);
		}
		if (source is CheckedAsyncOperation) {
			return async_operation ((CheckedAsyncOperation) source);
		}
		if (source is CheckedCallExpression) {
			var call = (CheckedCallExpression) source;
			return invoke (call.target, call.arguments, call.receiver, source.span);
		}
		if (source is CheckedOwnedObjectResultConstruction) {
			var construction = (CheckedOwnedObjectResultConstruction) source;
			return invoke (construction.constructor, construction.arguments, null, source.span, allocation (construction.storage.object_class, null));
		}
		if (source is CheckedOwnedBufferAllocate) {
			var allocation = (CheckedOwnedBufferAllocate) source;
			value (allocation.count);
			if (allocation.failure_call != null) {
				unsupported_node ("allocation failure action requires an exceptional lifetime summary");
			}
			return empty_product (source.semantic_type, allocation.allocation_context);
		}
		if (source is CheckedScopedAllocator) {
			value (((CheckedScopedAllocator) source).kind);
			value (((CheckedScopedAllocator) source).slots);
			return graph.absent ();
		}
		if (source is CheckedLengthExpression) {
			var length = (CheckedLengthExpression) source;
			if (length.array != null) {
				flow.read (length.array.ordinal);
			}
			value (length.slice);
			return graph.absent ();
		}
		if (source is CheckedLoadExpression) {
			return read (place (((CheckedLoadExpression) source).source));
		}
		if (source is CheckedStructProjectionValue) {
			var projected = (CheckedStructProjectionValue) source;
			return graph.project (producer (projected.source), field_path (projected.path));
		}
		if (source is CheckedBinaryExpression) {
			value (((CheckedBinaryExpression) source).left);
			value (((CheckedBinaryExpression) source).right);
			return graph.absent ();
		}
		if (source is CheckedShortCircuitExpression) {
			var expression = (CheckedShortCircuitExpression) source;
			value (expression.left);
			var entry = flow.state.snapshot ();
			value (expression.right);
			flow.merge (entry, entry, flow.state);
			return graph.absent ();
		}
		if (source is CheckedPrefixExpression) {
			value (((CheckedPrefixExpression) source).operand);
			return graph.absent ();
		}
		if (source is CheckedComparisonChain) {
			var operands = ((CheckedComparisonChain) source).operands;
			for (int i = 0; i < operands.length; i++) {
				var entry = flow.state.snapshot ();
				value (operands[i]);
				if (i >= 2) {
					flow.merge (entry, entry, flow.state);
				}
			}
			return graph.absent ();
		}
		if (source is CheckedIntegerConversionExpression) {
			value (((CheckedIntegerConversionExpression) source).operand);
			return graph.absent ();
		}
		if (source is CheckedFloatConversionExpression) {
			value (((CheckedFloatConversionExpression) source).operand);
			return graph.absent ();
		}
		if (source is CheckedNumericConversionExpression) {
			value (((CheckedNumericConversionExpression) source).operand);
			return graph.absent ();
		}
		if (source is CheckedIntegerExpression || source is CheckedBooleanExpression || source is CheckedFloatExpression || source is CheckedTextExpression || source is CheckedNullPointerExpression || source is CheckedConstantReference) {
			return graph.absent ();
		}
		unsupported_node ("expression requires its exact lifetime operation: " + source.get_type ().name ());
		return graph.absent ();
	}
	private void exit() throws RuntimeLifetimeError {
		if (!flow.state.reachable) {
			return;
		}
		exit_count++;
		foreach (int binding in exits.get_keys ()) {
			graph.alternative (exits.lookup (binding), flow.read (binding));
		}
	}
	private void exception(int value, ClassType type) throws RuntimeLifetimeError {
		int site = (int) exception_types.size ();
		exception_types.insert (site, type);
		flow.exception (value, site);
	}
	private void guarded(CheckedTry source) throws RuntimeLifetimeError {
		var entry = flow.state.snapshot ();
		flow.begin_try ();
		statement (source.body);
		var normal = flow.state.snapshot ();
		var pending = flow.end_try ();
		int pending_count = (int) pending.length;
		if (pending_count < 0) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("source exception event count exceeds the supported array extent");
		}
		bool[] handled = new bool[pending_count];
		foreach (var caught in source.catches) {
			flow.state = entry.snapshot ();
			flow.state.reachable = false;
			int failure = graph.join ();
			bool reachable = false;
			var bound = (ClassType) caught.binding.semantic_type;
			for (int e = 0; e < pending.length; e++) {
				if (handled[e]) {
					continue;
				}
				var event = pending[e];
				var type = exception_types.lookup (event.site);
				if (type == null) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("exception lost its exact source effect type");
				}
				if (!type.derives_from (bound) && !bound.derives_from (type)) {
					continue;
				}
				var incoming = event.state.snapshot ();
				foreach (var local in definition.locals) {
					if (!local.lexical_region.outlives (caught.body.region)) {
						incoming.bindings.insert (local.ordinal, graph.absent ());
					}
				}
				flow.merge (entry, flow.state, incoming);
				graph.alternative (failure, event.value);
				reachable = true;
				if (type.derives_from (bound)) {
					handled[e] = true;
				}
			}
			if (reachable) {
				write (new SemanticRuntimeStorage (caught.binding.ordinal), failure, source.span);
				statement (caught.body);
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
	private void statement(CheckedStatement source) throws RuntimeLifetimeError {
		if (!flow.state.reachable) {
			return;
		}
		current_span = source.span;
		if (source is CheckedBlockStatement) {
			var block = (CheckedBlockStatement) source;
			foreach (var child in block.statements) {
				statement (child);
			}
			foreach (var local in definition.locals) {
				if (local.lexical_region == block.region && local.incoming_parameter == null) {
					flow.write (local.ordinal, graph.absent ());
				}
			}
		} else if (source is CheckedTry) {
			guarded ((CheckedTry) source);
		} else if (source is CheckedAsyncDelay) {
			var delay = (CheckedAsyncDelay) source;
			value (delay.ticks);
			exception (graph.absent (), delay.body.runtime.error_type);
		} else if (source is CheckedTaskAwaitStatement) {
			task_await (((CheckedTaskAwaitStatement) source).operation);
		} else if (source is CheckedAsyncOperationStatement) {
			async_operation (((CheckedAsyncOperationStatement) source).operation);
		} else if (source is CheckedEnumStore) {
			var store = (CheckedEnumStore) source;
			write (new SemanticRuntimeStorage (store.destination.ordinal), enum_value (store.producer), source.span);
		} else if (source is CheckedEnumMatch) {
			var match = (CheckedEnumMatch) source;
			enum_value (match.scrutinee);
			var entry = flow.state.snapshot ();
			RuntimeLifetimeState? joined = null;
			foreach (var arm in match.arms) {
				if (arm.bindings.length != 0) {
					unsupported_node ("enum matching requires exact payload lifetime bindings");
				}
				flow.state = entry.snapshot ();
				statement (arm.body);
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
		} else if (source is CheckedThrow) {
			var thrown = (CheckedThrow) source;
			if (thrown.construction != null) {
				statement (thrown.construction);
			}
			int failure = flow.read (thrown.owner.ordinal);
			flow.write (thrown.owner.ordinal, graph.absent ());
			exception (failure, (ClassType) thrown.owner.semantic_type);
			flow.state.reachable = false;
		} else if (source is CheckedIf) {
			var branch = (CheckedIf) source;
			value (branch.condition);
			var entry = flow.state.snapshot ();
			statement (branch.then_body);
			var left = flow.state;
			flow.state = entry.snapshot ();
			if (branch.else_body != null) {
				statement (branch.else_body);
			}
			flow.merge (entry, left, flow.state);
		} else if (source is CheckedWhile) {
			var loop = (CheckedWhile) source;
			if (loop.has_iteration || loop.has_sequence) {
				unsupported_node ("iteration requires element and owner lifetime effects");
			}
			flow.begin_loop ();
			value (loop.condition);
			statement (loop.body);
			flow.begin_step ();
			if (loop.step != null) {
				statement (loop.step);
			}
			flow.end_loop ();
		} else if (source is CheckedBreak || source is CheckedContinue) {
			flow.jump (source is CheckedBreak);
		} else if (source is CheckedConstructorObjectInitialization) {
			var construction = (CheckedConstructorObjectInitialization) source;
			objects.insert (construction.storage, construction.local);
			RuntimeLifetimeState? refused = construction.storage.fallible ? flow.state.snapshot () : null;
			int root = construction.storage.heap_allocated ? allocation (construction.storage.object_class, construction.allocation_context) : empty_product (construction.storage.semantic_type);
			write (new SemanticRuntimeStorage (construction.local.ordinal), invoke (construction.constructor, construction.arguments, null, source.span, root), source.span);
			if (refused != null) {
				flow.merge (refused, refused, flow.state);
			}
		} else if (source is CheckedObjectConstruction) {
			var construction = (CheckedObjectConstruction) source;
			objects.insert (construction.storage, construction.local);
			write (new SemanticRuntimeStorage (construction.local.ordinal), initializer (construction.local.semantic_type, construction.initializers), source.span);
		} else if (source is CheckedLocalDeclaration) {
			var declaration = (CheckedLocalDeclaration) source;
			if (declaration.local.semantic_type is ClassType && !declaration.local.is_owned) {
				unsupported_node ("persistent borrowed Class locals require alias-sensitive storage effects");
			}
			write (new SemanticRuntimeStorage (declaration.local.ordinal), value (declaration.initializer), source.span);
		} else if (source is CheckedStructLocalDeclaration) {
			var declaration = (CheckedStructLocalDeclaration) source;
			write (new SemanticRuntimeStorage (declaration.local.ordinal), initializer (declaration.local.semantic_type, declaration.initializers), source.span);
		} else if (source is CheckedStructResultStore) {
			var store = (CheckedStructResultStore) source;
			write (place (store.destination), producer (store.producer), source.span);
		} else if (source is CheckedStructMove) {
			var move = (CheckedStructMove) source;
			int incoming = flow.read (move.source.ordinal);
			flow.write (move.source.ordinal, graph.absent ());
			write (new SemanticRuntimeStorage (move.destination.ordinal), incoming, source.span);
		} else if (source is CheckedRecordTake) {
			var take = (CheckedRecordTake) source;
			var storage = place (take.field);
			int incoming = read (storage);
			write (storage, graph.absent (), source.span);
			write (new SemanticRuntimeStorage (take.destination.ordinal), incoming, source.span);
		} else if (source is CheckedRecordReplace) {
			var replace = (CheckedRecordReplace) source;
			write (place (replace.field), value (replace.incoming), source.span);
		} else if (source is CheckedStructCopy) {
			var copy = (CheckedStructCopy) source;
			write (place (copy.destination), read (place (copy.source)), source.span);
		} else if (source is CheckedFieldInitialize) {
			var field = (CheckedFieldInitialize) source;
			write (place (field.target), value (field.value), source.span);
		} else if (source is CheckedOwnedFieldTransfer) {
			var field = (CheckedOwnedFieldTransfer) source;
			write (place (field.destination), value (field.incoming), source.span);
		} else if (source is CheckedStore) {
			var store = (CheckedStore) source;
			write (place (store.target), value (store.value), source.span);
		} else if (source is CheckedAssignment) {
			var assignment = (CheckedAssignment) source;
			write (new SemanticRuntimeStorage (assignment.target.ordinal), value (assignment.expression), source.span);
		} else if (source is CheckedFieldAssignment) {
			var assignment = (CheckedFieldAssignment) source;
			write (field_storage (new SemanticRuntimeStorage (assignment.local.ordinal), assignment.field), value (assignment.expression), source.span);
		} else if (source is CheckedOwnershipRearmAssignment) {
			var assignment = (CheckedOwnershipRearmAssignment) source;
			write (new SemanticRuntimeStorage (assignment.owner.ordinal), value (assignment.incoming), source.span);
		} else if (source is CheckedOwnedBufferReplace) {
			var assignment = (CheckedOwnedBufferReplace) source;
			write (new SemanticRuntimeStorage (assignment.owner.ordinal), value (assignment.incoming), source.span);
		} else if (source is CheckedOwnedBufferExchange) {
			var exchange = (CheckedOwnedBufferExchange) source;
			var left = place (exchange.left.place);
			var right = place (exchange.right.place);
			int old_left = read (left);
			int old_right = read (right);
			write (left, old_right, source.span);
			write (right, old_left, source.span);
		} else if (source is CheckedOwnershipRelease) {
			flow.write (((CheckedOwnershipRelease) source).owner.ordinal, graph.absent ());
		} else if (source is CheckedCallStatement) {
			var call = (CheckedCallStatement) source;
			invoke (call.target, call.arguments, call.receiver, source.span);
		} else if (source is CheckedValueStatement) {
			value (((CheckedValueStatement) source).value);
		} else if (source is CheckedOwnershipReturn) {
			var result = (CheckedOwnershipReturn) source;
			graph.alternative (returned, value ((CheckedExpression?) result.transfer ?? result.producer));
			exit ();
			flow.state.reachable = false;
		} else if (source is CheckedStructReturn) {
			graph.alternative (returned, producer (((CheckedStructReturn) source).producer));
			exit ();
			flow.state.reachable = false;
		} else if (source is CheckedReturnStatement) {
			int result = value (((CheckedReturnStatement) source).expression);
			graph.alternative (returned, graph_input (definition.symbol.return_type) ? result : graph.absent ());
			exit ();
			flow.state.reachable = false;
		} else {
			unsupported_node ("statement requires its exact lifetime operation: " + source.get_type ().name ());
		}
	}
	internal RuntimeLifetimeSummary incomplete(string reason) {
		graph.seal ();
		return new RuntimeLifetimeSummary (graph, graph.absent (), new HashTable<int, int> (direct_hash, direct_equal), new GenericArray<RuntimeLifetimeStore> (), reason);
	}
	internal RuntimeLifetimeSummary analyze() throws RuntimeLifetimeError {
		region_id (definition.body.region);
		returned = graph.join ();
		exceptional_result = graph.join ();
		flow.begin_try ();
		foreach (var parameter in definition.symbol.parameters) {
			bool owning = parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER || parameter.struct_value_contract != null && parameter.struct_value_contract.mode == StructValueMode.MOVE_VALUE;
			bool allocator = parameter.semantic_type.is_scoped_allocator ();
			if (allocator || graph_input (parameter.semantic_type) || owning) {
				regions.input (parameter.ordinal, allocator);
			}
			int incoming = allocator || !graph_input (parameter.semantic_type) && !owning ? graph.absent() : graph.input (parameter.ordinal);
			int binding = parameter_binding (parameter.ordinal);
			flow.declare (binding, incoming);
			if (graph_input (parameter.semantic_type) && !owning) {
				initial_inputs.insert (binding, incoming);
				exits.insert (binding, graph.join ());
			}
		}
		if (definition.symbol.implicit_receiver != null) {
			regions.input (-1);
			int incoming = graph.input (-1);
			flow.declare (-1, incoming);
			initial_inputs.insert (-1, incoming);
			exits.insert (-1, graph.join ());
		}
		foreach (var local in definition.locals) {
			int region = region_id (local.lexical_region);
			regions.owner (local.ordinal, region);
			if (local.scoped_backing != null) {
				regions.context (local.ordinal, region);
			}
			flow.declare (local.ordinal, local.incoming_parameter == null ? graph.absent () : flow.read (parameter_binding (local.incoming_parameter.ordinal)));
		}
		regions.seal ();
		statement (definition.body);
		if (flow.state.reachable) {
			graph.alternative (returned, graph.absent ());
			exit ();
		}
		int normal_exits = exit_count;
		var normal = flow.state.snapshot ();
		var escaped = flow.end_try ();
		if (escaped.length != 0 && definition.symbol.throws_type == null && definition.symbol.async_body == null) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("exception lifetime escapes a nonthrowing source function");
		}
		foreach (var failure in escaped) {
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
		if (definition.symbol.async_body != null) {
			var captures = new HashTable<string, int> (str_hash, str_equal);
			foreach (var parameter in definition.symbol.parameters) {
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
			current_span = obligation.span;
			regions.validate (graph, obligation.value, obligation.destination);
		}
		foreach (var origin in graph.requirements (returned)) {
			if (origin.kind == RuntimeScopeOriginKind.LOCAL_CONTEXT) {
				throw new RuntimeLifetimeError.LOCAL_ESCAPE ("runtime lifetime: result retains a scoped local allocation");
			}
		}
		foreach (var origin in graph.requirements (exceptional_result)) {
			if (origin.kind == RuntimeScopeOriginKind.LOCAL_CONTEXT) {
				throw new RuntimeLifetimeError.LOCAL_ESCAPE ("runtime lifetime: exception retains a scoped local allocation");
			}
		}
		var updates = new HashTable<int, int> (direct_hash, direct_equal);
		int borrowed_inputs = 0;
		foreach (int binding in exits.get_keys ()) {
			borrowed_inputs++;
			int update = exits.lookup (binding);
			bool changed = false;
			var original = graph.requirements (initial_inputs.lookup (binding));
			var result = graph.requirements (update);
			if (original.length != result.length) {
				changed = true;
			} else {
				for (int i = 0; i < original.length; i++) {
					if (original[i].identity () != result[i].identity ()) {
						changed = true;
					}
				}
			} if (changed || stores.length != 0) {
				updates.insert (binding == -1 ? -1 : -binding - 2, update);
			}
			foreach (var origin in result) {
				if (origin.kind == RuntimeScopeOriginKind.LOCAL_CONTEXT) {
					throw new RuntimeLifetimeError.LOCAL_ESCAPE ("runtime lifetime: input storage retains a scoped local allocation");
				}
			}
		}
		if (borrowed_inputs > 1 && stores.length != 0) {
			unsupported_node ("mutating potentially aliased borrowed inputs requires alias-sensitive effects");
		}
		if (definition.symbol.async_body != null) {
			if (updates.size () != 0 || stores.length != 0) {
				unsupported_node ("async factory needs deferred borrowed-storage effects");
			}
			return new RuntimeLifetimeSummary (graph, factory_result, new HashTable<int, int> (direct_hash, direct_equal), new GenericArray<RuntimeLifetimeStore> (), unsupported);
		}
		return new RuntimeLifetimeSummary (graph, returned, updates, stores, unsupported, definition.symbol.throws_type == null ? -1 : exceptional_result);
	}
}
}
