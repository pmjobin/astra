// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Source;
using Astra.Code;

namespace Astra.Core {
public class CoreVerifier : Object {
	private void verify_application_header(CoreClass owner, CoreFunction header, GenericMemberPattern? declared) throws CoreError {
		string path = "Class application/member";
		var receiver = header.implicit_receiver;
		bool initializing = header is CoreConstructor;
		var method = header as CoreMethod;
		var request = method == null ? null : method.generic_method_instance;
		bool binding = declared != null && (declared.type_parameter_count == 0 ? request == null : request != null && request.valid_application (owner.generic_instance) && header.name == request.name);
		if (!binding || header.body.statements.length != 0 || header.locals.length != 0 || header.native_declaration != null || receiver == null || receiver.contract.instance_type != owner.semantic_type || receiver.contract.mode != (initializing ? ReceiverMode.INITIALIZING : ReceiverMode.LIVE) || functions.contains (header) || receiver_owners.contains (receiver)) {
			fail (path, "requires an exact bodyless declared signature and receiver");
		}
		var types = new GenericArray<SemanticType> ();
		var contracts = new GenericArray<PointerParameterContract> ();
		for (int p = 0; p < header.parameters.length; p++) {
			var parameter = header.parameters[p];
			if (parameter.ordinal != p) {
				fail (path, "parameter requires its declared ordinal");
			}
			types.add (parameter.semantic_type);
			contracts.add (parameter.pointer_contract);
		}
		if (!GenericClassDeclaredShape.signature (declared, owner.generic_instance, header.return_type, types, contracts, header.throws_type, header.async_body != null, copy_fields, request == null ? null : request.arguments) || (int) header.dispatch_kind != declared.dispatch) {
			fail (path, "signature differs from its immutable declared type patterns");
		}
		bool owned_result = GenericClassDeclaredShape.owns_value (declared.result_mode, header.return_type);
		var cleanup = header.owned_cleanup;
		if (owned_result != (cleanup != null) || cleanup != null && (!cleanups.contains (cleanup) || !(cleanup.is_object ? cleanup.object_class != null && cleanup.object_class.semantic_type == header.return_type : matches_cleanup (header.return_type, cleanup)))) {
			fail (path, "owned result requires its exact declared responsibility");
		}
		functions.insert (header, header);
		receiver_owners.insert (receiver, header);
		if (initializing) {
			initializing_types.insert (owner.semantic_type, receiver.contract);
		}
	}

	private void verify_native_declaration(CoreFunction function, string path) throws CoreError {
		if (!function.native_declaration_valid ()) {
			fail (path, "native declaration lost its original signature facts");
		}
		var declaration = function.native_declaration;
		if (declaration == null) {
			if (function.name_span.file.native_interface) {
				fail (path, "native declaration lost its original signature facts");
			}
			return;
		}
		if (!function.name_span.file.native_interface) {
			fail (path, "native declaration requires its exact imported source origin");
		}
		if (!declaration.matches_async (function.async_body)) {
			fail (path, "native declaration differs from its original async result/runtime contract");
		}
		var types = new GenericArray<SemanticType> ();
		var contracts = new GenericArray<PointerParameterContract> ();
		var heaps = new bool[function.parameters.length];
		var nonnull = new bool[function.parameters.length];
		var records = new int[function.parameters.length];
		for (int p = 0; p < function.parameters.length; p++) {
			var parameter = function.parameters[p];
			types.add (parameter.semantic_type);
			contracts.add (parameter.pointer_contract);
			heaps[p] = parameter.heap_object;
			nonnull[p] = parameter.requires_nonnull;
			records[p] = parameter.struct_value_contract == null ? -1 : (int) parameter.struct_value_contract.mode;
		}
		var receiver = function.implicit_receiver;
		string member = function.name_span.text ();
		if (function is CoreConstructor) {
			member = "init";
		} else if (function is CoreDestructor) {
			member = "deinit";
		} else if (function is CorePropertyGetter) {
			member = "get:" + ((CorePropertyGetter) function).property_member.name;
		} else if (function is CorePropertySetter) {
			member = "set:" + ((CorePropertySetter) function).property_member.name;
		}
		var method = function as CoreMethod;
		if (method != null && method.generic_method_instance != null) {
			member += method.generic_method_instance.arguments.display_suffix (true);
		}
		string key = receiver == null ? "F:" + function.name : "C:" + receiver.contract.instance_type.display_name () + "::" + member;
		if (key != declaration.identity.key || !declaration.matches_logical_records (records, function.struct_result_contract == null ? -1 : (int) function.struct_result_contract.mode) || !declaration.matches (function.return_type, function.result_contract,
			function.heap_result, function.nonnull_result, receiver == null ? null : receiver.contract.instance_type,
			function.throws_type, types, contracts, heaps, nonnull)) {
			fail (path, "native declaration differs from its original exact signature");
		}
	}

	private bool thread_capture_type(SemanticType type, HashTable<SemanticType, bool> seen, bool mailbox_graph = false, bool affinity_only = false) {
		if (type is ClassType && ((ClassType) type).thread_bound) {
			return false;
		}
		if (affinity_only && type is ClosureHandleType) {
			if (seen.contains (type)) {
				return true;
			}
			seen.insert (type, true);
			return thread_capture_type (((ClosureHandleType) type).environment_type, seen, mailbox_graph, true);
		}
		var shared = type as SharedHandleType;
		if (shared != null && affinity_only) {
			return thread_capture_type (shared.payload_type, seen, mailbox_graph, true);
		}
		if (shared != null) {
			var payload = structs.lookup (shared.payload_type) as CoreClass;
			return payload != null && shared.payload_type.monitored && !shared.payload_type.thread_bound && (payload.allocation_policy == null || payload.allocation_policy.kind == AllocationKind.CONTEXT && payload.allocation_policy.context_mode == "owned-concurrent") && thread_capture_type (shared.payload_type, seen, mailbox_graph, affinity_only);
		}

		if (type is ClosureHandleType && ((ClosureHandleType) type).actor) {
			return !mailbox_graph && ((ClosureHandleType) type).supported ();
		}
		if (type is HandleType) {
			var context = ((HandleType) type).context_mode;
			return context != "" ? context == "owned-concurrent" : affinity_only;
		}
		if (type is RawPointerType || type is TypedPointerType) {
			return false;
		}
		if (type is StringType || FunctionValueType.scalar (type) || type is VectorType) {
			return true;
		}
		if (seen.contains (type)) {
			return true;
		}
		seen.insert (type, true);
		if (type is ContextBytesType && ((ContextBytesType) type).context_mode != "owned-concurrent") {
			return false;
		}
		if (type is SliceType) {
			return thread_capture_type (((SliceType) type).element_type, seen, mailbox_graph, affinity_only);
		}
		if (type is OwnerSlotsType) {
			return thread_capture_type (((OwnerSlotsType) type).element, seen, mailbox_graph, affinity_only);
		}
		var owner = structs.lookup (type);
		if (owner == null) {
			return false;
		}
		var object_class = owner as CoreClass;
		if (object_class != null && object_class.allocation_policy != null) {
			var policy = object_class.allocation_policy;
			if (policy.kind == AllocationKind.CONTEXT ? policy.context_mode != "owned-concurrent" : !affinity_only) {
				return false;
			}
		}
		if (!affinity_only && object_class != null && ((ClassType) type).intrinsically_shared && !((ClassType) type).monitored) {
			return false;
		}
		if (object_class != null && object_class.polymorphic) {
			foreach (var instance in structs.get_values ()) {
				var derived = instance as CoreClass;
				if (derived == null || derived == object_class) {
					continue;
				}
				for (var parent = derived.parent_class; parent != null; parent = parent.parent_class) {
					if (parent == object_class) {
						if (!thread_capture_type (derived.semantic_type, seen, mailbox_graph, affinity_only)) {
							return false;
						}
						break;
					}
				}
			}
		}
		foreach (var field in owner.fields) {
			if (!thread_capture_type (field.semantic_type, seen, mailbox_graph, affinity_only)) {
				return false;
			}
		}
		return object_class == null || object_class.parent_class == null || thread_capture_type (object_class.parent_class.semantic_type, seen, mailbox_graph, affinity_only);
	}

	private GenericArray<CoreFunction> nonnull_definitions = new GenericArray<CoreFunction> ();
	private HashTable<CoreSlotsTake, CoreOwnedLocal> slots_takes = new HashTable<CoreSlotsTake, CoreOwnedLocal> (direct_hash, direct_equal);
	private HashTable<CoreUtf8FactoryValue, CoreFunction> utf8_values;
	private HashTable<CoreOwnedArgumentValue, CoreFunction> heap_generic_requests = new HashTable<CoreOwnedArgumentValue, CoreFunction> (direct_hash, direct_equal);
	private GenericArray<CoreOwnedArgumentValue> heap_generic_order = new GenericArray<CoreOwnedArgumentValue> ();
	private HashTable<CoreFunction, int> heap_consumer_parameters = new HashTable<CoreFunction, int> (direct_hash, direct_equal);
	private HashTable<CoreFunction, GenericOwnerTransferScope> heap_consumer_scopes = new HashTable<CoreFunction, GenericOwnerTransferScope> (direct_hash, direct_equal);
	private HashTable<CoreFunction, GenericOwnershipFlow> storage_flows = new HashTable<CoreFunction, GenericOwnershipFlow> (direct_hash, direct_equal);
	private HashTable<CoreCallValue, CoreOwnedLocal> heap_result_receivers = new HashTable<CoreCallValue, CoreOwnedLocal> (direct_hash, direct_equal);
	private HashTable<CoreGenericFunction, GenericResultOrigins> generic_result_origins;
	private CoreResultOriginProjection generic_result_projection;
	private HashTable<CoreFunction, GenericResultOrigins> concrete_result_origins;
	private HashTable<CoreFunction, HashTable<CoreOwnedLocal, GenericResultOrigins>> concrete_local_origins = new HashTable<CoreFunction, HashTable<CoreOwnedLocal, GenericResultOrigins>> (direct_hash, direct_equal);
	private CoreFunction? ownership_function;
	private bool deferred_class_result(CoreFunction function) {
		var generic = function as CoreGenericFunction;
		var equation = generic == null ? null : generic_result_origins.lookup (generic);
		return generic != null && generic.return_type is ClassType && generic.owned_cleanup != null
		       && equation != null && (equation.domains & GenericResultOrigins.UNKNOWN) != 0;
	}

	private CoreCleanupContract? class_result_cleanup(SemanticType type, bool heap) {
		foreach (var cleanup in cleanups.get_keys ()) {
			if (cleanup.is_object && cleanup.is_heap_object == heap && cleanup.object_class.semantic_type == type) {
				return cleanup;
			}
		}
		return null;
	}

	private bool tracked_owner(CoreOwnedLocal owner) {
		if (ownership_function is CoreGenericFunction && owner.place.incoming_parameter != null && owner.place.semantic_type is ClassType) {
			return true;
		}
		if (ownable_parameter (owner.place.semantic_type) || owner.cleanup.is_buffer || (owner.place.incoming_parameter != null && owner.cleanup.is_heap_object) || generic_local_owner (owner)) {
			return true;
		}
		foreach (var transfer in generic_local_transfers.get_values ()) {
			if (transfer.source == owner) {
				return true;
			}
		}
		return ownership_function != null && ownership_function.generic_instance != null && owner.place.incoming_parameter != null && ownership_function.generic_instance.owns_parameter (owner.place.incoming_parameter.ordinal);
	}

	private HashTable<CoreOwnedLocal, CoreOwnershipTransfer> generic_local_transfers = new HashTable<CoreOwnedLocal, CoreOwnershipTransfer> (direct_hash, direct_equal);
	private HashTable<CoreOwnedLocal, bool> generic_local_acquisitions = new HashTable<CoreOwnedLocal, bool> (direct_hash, direct_equal);
	private bool generic_local_owner(CoreOwnedLocal owner) {
		return generic_local_transfers.contains (owner) || generic_local_acquisitions.contains (owner);
	}

	private ObjectResultProvenance returned_object_origin(CoreFunction function, CoreOwnedLocal owner) throws CoreError {
		if (owner.cleanup.is_heap_object) {
			return ObjectResultProvenance.HEAP_OBJECT;
		}
		var seen = new HashTable<CoreOwnedLocal, bool> (direct_hash, direct_equal);
		var root = owner;
		while (generic_local_transfers.contains (root)) {
			if (seen.contains (root)) {
				return ObjectResultProvenance.CALLEE_LOCAL_STORAGE;
			}
			seen.insert (root, true);
			root = generic_local_transfers.lookup (root).source;
		}
		if (root.place.incoming_parameter != null) {
			return ObjectResultProvenance.OWNED_PARAMETER_STORAGE;
		}
		var locals = concrete_local_origins.lookup (function);
		if (locals == null) {
			locals = CoreGenericResultOrigins.concrete_locals (function, concrete_result_origins);
			concrete_local_origins.insert (function, locals);
		}
		var equation = locals.lookup (owner);
		if (equation == null || equation.domains != 0) {
			return ObjectResultProvenance.CALLEE_LOCAL_STORAGE;
		}
		if (equation.input_count == 0) {
			return ObjectResultProvenance.NULL;
		}
		for (int i = 0; i < equation.input_count; i++) {
			int ordinal = equation.input (i);
			if (ordinal < 0 || ordinal >= function.parameters.length) {
				return ObjectResultProvenance.CALLEE_LOCAL_STORAGE;
			}
			var parameter = function.parameters[ordinal];
			if (parameter.pointer_contract != PointerParameterContract.OWNED_TRANSFER || parameter.semantic_type != owner.place.semantic_type || parameter.heap_object) {
				return ObjectResultProvenance.CALLEE_LOCAL_STORAGE;
			}
		}
		return ObjectResultProvenance.OWNED_PARAMETER_STORAGE;
	}

	private static bool generic_local_transfer(CoreFunction function, CoreOwnedLocal source, CoreOwnedLocal destination) {
		if (!(function is CoreGenericFunction) && function.generic_instance == null) {
			return false;
		}
		if (function is CoreGenericFunction && !ownable_parameter (source.place.semantic_type)) {
			return false;
		}
		return source.place.semantic_type == destination.place.semantic_type && source.cleanup == destination.cleanup
		       && destination.place.incoming_parameter == null && source.object_storage == null && destination.object_storage == null;
	}

	private int heap_consumer_parameter(CoreFunction function, GenericOwnershipFlow flow) {
		bool returning = function.owned_cleanup != null;
		if (function.async_body != null || function.throws_type != null) {
			return -1;
		}
		if (returning) {
			if (!(ownable_parameter (function.return_type) || (function.generic_instance != null && function.heap_result))) {
				return -1;
			}
		} else if (function.return_type.kind != TypeKind.VOID && !GenericBorrowTypes.scalar (function.return_type)) {
			return -1;
		}
		int ordinal = -1;
		foreach (var parameter in function.parameters) {
			bool incoming = ownable_parameter (parameter.semantic_type) || (function.generic_instance != null && function.generic_instance.owns_parameter (parameter.ordinal));
			if (incoming && parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER) {
				if (ordinal != -1) {
					return -1;
				}
				ordinal = parameter.ordinal;
			} else if (!GenericClassTypes.borrowed_context (parameter.semantic_type, parameter.pointer_contract) && (parameter.pointer_contract != PointerParameterContract.UNMANAGED || !(GenericBorrowTypes.scalar (parameter.semantic_type) || parameter.semantic_type is FunctionValueType))) {
				return -1;
			}
		}
		if (ordinal == -1 || (returning && function.return_type != function.parameters[ordinal].semantic_type)) {
			return -1;
		}
		if (returning) {
			if (function.object_storage.length != 0) {
				return -1;
			}
			foreach (var owner in function.owned_locals) {
				if (owner.place.incoming_parameter == null) {
					return -1;
				}
			}
		}
		foreach (var owner in function.owned_locals) {
			if (owner.place.incoming_parameter == function.parameters[ordinal]) {
				var scope = flow.transfer_scopes.lookup (owner) ?? new GenericOwnerTransferScope ();
				if (!scope.valid || scope.returned != returning || (returning && (scope.target != null || owner.cleanup != function.owned_cleanup))) {
					return -1;
				}
				heap_consumer_scopes.insert (function, scope);
				return ordinal;
			}
		}
		return -1;
	}

	private bool consuming_class_member(Object? target, int ordinal, SemanticType type) {
		var method = target as CoreMethod;
		if (method == null || !functions.contains (method) || !GenericClassTypes.general (method.declaring_type.semantic_type) || method.async_body != null || method.throws_type != null || method.owned_cleanup != null || ordinal < 0 || ordinal >= method.parameters.length) {
			return false;
		}
		var parameter = method.parameters[ordinal];
		return parameter.semantic_type == type && parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER && (ownable_parameter (type) || type is ClassType && parameter.heap_object);
	}

	private static bool heap_transfer(SemanticType source, CoreCleanupContract from, SemanticType target, CoreCleanupContract to) {
		return from.is_heap_object && to.is_heap_object && source is ClassType && target is ClassType && ((ClassType) source).derives_from ((ClassType) target) && (source == target || to.object_class.polymorphic);
	}

	private GenericArray<CoreExceptionHandlerScope> exception_handlers = new GenericArray<CoreExceptionHandlerScope> ();
	private GenericArray<CoreLocalPlace> caught_exceptions = new GenericArray<CoreLocalPlace> ();
	private HashTable<CoreLocalPlace, GenericArray<ClassType>> caught_effects = new HashTable<CoreLocalPlace, GenericArray<ClassType>> (direct_hash, direct_equal);
	private void verify_class_hierarchy(CoreProgram program) throws CoreError {
		var classes = new HashTable<CoreClass, bool> (direct_hash, direct_equal);
		foreach (var owner in program.classes) {
			classes.insert (owner, true);
		}
		CoreClass? nominated = null;
		foreach (var owner in program.structs) {
			var policy = owner.representation;
			var type = (StructType) owner.semantic_type;
			string[] names = {};
			string[] types = {};
			foreach (var field in owner.fields) {
				names += field.name;
				types += field.semantic_type.display_name ();
			}
			if (policy == null ? type.representation_identity != "" : !policy.matches (type.representation_identity, owner.name, names, types) || owner.methods.length != 0 || owner.properties.length != 0) {
				fail ("POD representation", "record lost its admitted natural C field order, scalar types or alignment");
			}
		}
		var allocation_domains = new Astra.Source.AllocationDomains ();
		foreach (var owner in program.classes) {
			if (!allocation_domains.admit (owner.allocation_policy)) {
				fail ("allocation domain", "conflicting or altered named policy");
			}
			if (!Astra.Source.ForeignClassPolicy.matches (owner.foreign_export, ((ClassType) owner.semantic_type).foreign_policy_identity, owner.name) || (owner.parent_class != null && owner.parent_class.foreign_export != null)) {
				fail ("foreign Class policy", "lost its admitted native root or independent declaration");
			}
			if (owner.foreign_export != null) {
				var policy = owner.foreign_export;
				if (policy.declared_api != null) {
					if (!CoreForeignApi.valid (owner, program)) {
						fail ("foreign declared API", "lost exact native member binding, type, ownership or effect authority");
					}
				} else {
					if (owner.parent_class != null || owner.polymorphic || owner.exception_root || owner.generic_instance != null || owner.allocation_policy != null || owner.concurrency_policy == null || (owner.concurrency_policy.identity != 1 && owner.concurrency_policy.identity != 3) || owner.constructor == null || owner.constructor.throws_type != null || owner.constructor.parameters.length != 1 || owner.constructor.parameters[0].semantic_type.kind != TypeKind.INT || policy.property_ordinal >= owner.properties.length) {
						fail ("foreign Class policy", "requires its selected Shared heap root and exact int constructor");
					}
					var property = owner.properties[policy.property_ordinal];
					if (property.name != policy.property_name || property.ordinal != policy.property_ordinal || property.semantic_type.kind != TypeKind.INT || property.is_lazy || property.is_borrowed || property.getter == null || property.setter == null || property.getter.throws_type != null || property.setter.throws_type != null) {
						fail ("foreign Class policy", "lost its selected nonthrowing read/write int property");
					}
					foreach (var field in owner.fields) {
						if (field.semantic_type.kind != TypeKind.INT) {
							fail ("foreign Class policy", "requires copied int payload fields");
						}
					}
				}
			}
			if (owner.exception_root && owner.concurrency_policy != null) {
				fail ("exception policy", "native exception roots retain their unique lifetime contract");
			}
			if (owner.parent_class != null && ((ClassType) owner.parent_class.semantic_type).concurrency_policy_identity != ((ClassType) owner.semantic_type).concurrency_policy_identity) {
				fail ("Class concurrency policy", "inheritance lost one root policy authority");
			}
			if (owner.concurrency_policy != null && (owner.concurrency_policy.monitor || owner.concurrency_policy.thread_bound || owner.concurrency_policy.actor)) {
				foreach (var field in owner.fields) {
					if (!field.is_private) {
						fail ("protected state", "Monitor/ThreadBound fields require private compiler-mediated access");
					}
				}
			}
			if (owner.concurrency_policy != null && owner.concurrency_policy.actor && (owner.concurrency_policy.identity != 16 || owner.parent_class != null || owner.polymorphic || owner.allocation_policy != null)) {
				fail ("Actor policy", "requires an exact hosted receiver with transferable state and no sender cycles");
			}
			if (owner.concurrency_policy != null && owner.concurrency_policy.monitor) {
				foreach (var method in owner.methods) {
					if (method.async_body != null || !(FunctionValueType.scalar (method.return_type) || method.return_type.kind == TypeKind.VOID || method.result_contract == ResultOwnershipContract.OWNED_TRANSFER)) {
						fail ("Monitor signature", "requires synchronous copied scalar/void or an owning snapshot");
					}
				}
				foreach (var property in owner.properties) {
					if (property.is_borrowed || !FunctionValueType.scalar (property.semantic_type)) {
						fail ("Monitor signature", "protected property borrow cannot escape its guard");
					}
				}
			}
			if (owner.concurrency_policy != null && owner.concurrency_policy.singleton) {
				if (owner.concurrency_policy.identity != 7 || owner.constructor == null || owner.parent_class != null || owner.polymorphic || owner.allocation_policy != null) {
					fail ("Singleton policy", "requires an exact hosted Shared Monitor root with an explicit constructor");
				}
				foreach (var field in owner.fields) {
					if (!(field.semantic_type is IntegerType || field.semantic_type is FloatingType || field.semantic_type.kind == TypeKind.BOOL)) {
						fail ("Singleton fields", "bounded initialization requires copied numeric state");
					}
				}
				foreach (var parameter in owner.constructor.parameters) {
					if (parameter.pointer_contract != PointerParameterContract.UNMANAGED || !(parameter.semantic_type is IntegerType || parameter.semantic_type is FloatingType || parameter.semantic_type.kind == TypeKind.BOOL)) {
						fail ("Singleton constructor", "requires copied numeric inputs");
					}
				}
			}
			if (owner.constructor != null) {
				var constructor = owner.constructor;
				bool declared = ConstructorContracts.admitted (owner.foreign_export, owner.allocation_policy, constructor.member_ordinal, constructor.throws_type);
				if (constructor.throws_type != null && !declared && (owner.concurrency_policy == null || !owner.concurrency_policy.singleton)) {
					fail ("checked constructor", "requires the bounded Singleton failure and retry protocol");
				}
				int field_cursor = 0, lazy_cursor = 0;
				if (declared) {
					for (int f = owner.fields.length - 1; f >= 0; f--) {
						var field = owner.fields[f];
						if (field.owned_cleanup == null && !field.text_snapshot && !(field.semantic_type is OwnerSlotsType)) {
							continue;
						}
						var cleanup = (field.semantic_type is OwnerSlotsType) ? field.slots_cleanup : field.owned_cleanup;
						if (field_cursor >= constructor.unwind_fields.length || constructor.unwind_fields[field_cursor].field != field || constructor.unwind_fields[field_cursor].cleanup != cleanup) {
							fail ("constructor unwind", "lost its exact declared field retirement recipe");
						}
						field_cursor++;
					}
					for (int p = owner.properties.length - 1; p >= 0; p--) {
						var property = owner.properties[p];
						if (!property.is_owned_lazy) {
							continue;
						}
						if (lazy_cursor >= constructor.unwind_lazy.length || constructor.unwind_lazy[lazy_cursor] != property) {
							fail ("constructor unwind", "lost its exact lazy-cache retirement recipe");
						}
						lazy_cursor++;
					}
				}
				if (field_cursor != constructor.unwind_fields.length || lazy_cursor != constructor.unwind_lazy.length || field_cursor > 4096) {
					fail ("constructor unwind", "requires its complete bounded field and cache retirement inventory");
				}
			}
			if (!Astra.Source.ConcurrencyPolicy.matches (owner.concurrency_policy, ((ClassType) owner.semantic_type).concurrency_policy_identity)) {
				fail ("Class concurrency policy", "lost its exact admitted declaration identity");
			}
			if (!Astra.Source.AllocationPolicy.matches (owner.allocation_policy, ((ClassType) owner.semantic_type).allocation_policy_identity) || owner.allocation_policy != null && (owner.polymorphic || owner.parent_class != null || owner.exception_root || ((ClassType) owner.semantic_type).is_interface)) {
				fail ("Class allocation policy", "requires its exact admitted nonpolymorphic declaration");
			}
			if (((ClassType) owner.semantic_type).is_interface && (owner.parent_class != null || owner.fields.length != 0 || owner.properties.length != 0 || owner.destructor != null || owner.methods.length == 0 || !owner.polymorphic)) {
				fail ("interface contract", "requires a fieldless nonconstructible exact root and typed operation slots");
			}
			if (((ClassType) owner.semantic_type).is_interface) {
				foreach (var method in owner.methods) {
					if (method.return_type.kind != TypeKind.INT || method.throws_type != null || method.result_contract != ResultOwnershipContract.UNMANAGED || method.dispatch_kind != ClassDispatchKind.VIRTUAL) {
						fail ("interface operation", "requires copied nonthrowing int result and exact virtual declaration");
					}
					foreach (var parameter in method.parameters) {
						if (parameter.semantic_type.kind != TypeKind.INT || parameter.pointer_contract != PointerParameterContract.UNMANAGED) {
							fail ("interface operation", "requires copied int parameter channels");
						}
					}
				}
			}
			if (((ClassType) owner.semantic_type).parent_type != (owner.parent_class == null ? null : owner.parent_class.semantic_type)) {
				fail ("class parent", "requires the exact nominal parent identity");
			}
			if (owner.exception_root) {
				if (nominated != null || owner.parent_class != null) {
					fail ("ExceptionRoot", "requires one unique root class");
				}
				nominated = owner;
			}
			var seen = new HashTable<CoreClass, bool> (direct_hash, direct_equal);
			int depth = 0;
			for (CoreClass? current = owner; current != null; current = current.parent_class) {
				if (!classes.contains (current) || seen.contains (current) || ++depth > 256) {
					fail ("class parent", "requires a bounded acyclic exact program-owned chain");
				}
				seen.insert (current, true);
			}
		}
		var complete = new HashTable<CoreClass, bool> (direct_hash, direct_equal);
		while (complete.size () != classes.size ()) {
			foreach (var owner in program.classes) {
				if (complete.contains (owner) || (owner.parent_class != null && !complete.contains (owner.parent_class))) {
					continue;
				}
				var expected = new GenericArray<CoreFunction> ();
				if (owner.parent_class != null) {
					foreach (var entry in owner.parent_class.virtual_entries) {
						expected.add (entry);
					}
				}
				var members = new GenericArray<CoreFunction> ();
				foreach (var member in owner.methods) {
					members.add (member);
				}
				foreach (var property in owner.properties) {
					members.add (property.getter);
				}
				foreach (var member in members) {
					var getter = member as CorePropertyGetter;
					string name = getter == null ? member.name : getter.property_member.name;
					CoreFunction? prior = null;
					bool inherited_name = false;
					for (var ancestor = owner.parent_class; ancestor != null; ancestor = ancestor.parent_class) {
						foreach (var field in ancestor.fields) {
							if (field.name == name) {
								inherited_name = true;
							}
						}
						foreach (var candidate in ancestor.methods) {
							if (candidate.name == name && !inherited_name) {
								prior = candidate;
								inherited_name = true;
							}
						}
						foreach (var property in ancestor.properties) {
							if (property.name == name && !inherited_name) {
								prior = property.getter;
								inherited_name = true;
							}
						}
					}
					if (member.dispatch_kind == ClassDispatchKind.DIRECT) {
						if (member.virtual_slot != -1 || inherited_name) {
							fail ("virtual slot", "direct member cannot carry a virtual slot or shadow an inherited member");
						}
						continue;
					}
					if (!owner.polymorphic || member.owned_cleanup != null || member.return_type is EnumType || member.return_type.is_struct_storage () || (getter != null && getter.property_member.setter != null)) {
						fail ("virtual slot", "bounded virtual member requires nonowning result and get-only property");
					}
					foreach (var parameter in member.parameters) {
						if (parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER || parameter.semantic_type is EnumType || parameter.semantic_type.is_struct_storage ()) {
							fail ("virtual slot", "bounded virtual parameter requires a nonowning plain value or borrow");
						}
					}
					if (member.dispatch_kind == ClassDispatchKind.VIRTUAL) {
						if (inherited_name || member.virtual_slot != expected.length) {
							fail ("virtual slot", "new virtual slot must have its exact declaration rank");
						}
						expected.add (member);
					} else if (member.dispatch_kind == ClassDispatchKind.OVERRIDE) {
						if (prior == null || prior.dispatch_kind == ClassDispatchKind.DIRECT || (getter == null) != (prior is CoreMethod) || prior.return_type != member.return_type || prior.result_contract != member.result_contract || member.parameters.length != prior.parameters.length || member.virtual_slot != prior.virtual_slot) {
							fail ("virtual override", "requires exact inherited slot kind, result and parameter grouping");
						}
						for (int p = 0; p < member.parameters.length; p++) {
							if (member.parameters[p].semantic_type != prior.parameters[p].semantic_type || member.parameters[p].pointer_contract != prior.parameters[p].pointer_contract) {
								fail ("virtual override", "requires exact parameter type and borrow contract");
							}
						}
						if (member.throws_type != null && (prior.throws_type == null || !member.throws_type.derives_from (prior.throws_type))) {
							fail ("virtual override", "cannot broaden the inherited checked bound");
						}
						expected.set (member.virtual_slot, member);
					} else {
						fail ("virtual slot", "invalid dispatch kind");
					}
				}
				foreach (var field in owner.fields) {
					for (var ancestor = owner.parent_class; ancestor != null; ancestor = ancestor.parent_class) {
						foreach (var prior in ancestor.fields) {
							if (prior.name == field.name) {
								fail ("class field", "derived field cannot shadow an inherited field");
							}
						}
						foreach (var prior in ancestor.methods) {
							if (prior.name == field.name) {
								fail ("class field", "derived field cannot shadow an inherited method");
							}
						}
						foreach (var prior in ancestor.properties) {
							if (prior.name == field.name) {
								fail ("class field", "derived field cannot shadow an inherited property");
							}
						}
					}
				}
				if (owner.virtual_entries.length != expected.length) {
					fail ("virtual slots", "requires one complete exact inherited slot table");
				}
				for (int v = 0; v < expected.length; v++) {
					if (owner.virtual_entries[v] != expected[v]) {
						fail ("virtual slots", "slot must select the exact overriding implementation");
					}
				}
				foreach (var method in owner.methods) {
					bool readonly_contract = false;
					for (var ancestor = owner.parent_class; ancestor != null; ancestor = ancestor.parent_class) {
						if (((ClassType) ancestor.semantic_type).is_interface && method.virtual_slot >= 0 && method.virtual_slot < ancestor.virtual_entries.length) {
							readonly_contract = true;
						}
					}
					if (readonly_contract && method.native_declaration != null) {
						verify_native_declaration (method, "native interface implementation");
					} else if (readonly_contract) {
						if (!interface_read_block (method.body, method)) {
							fail ("interface read-only implementation", "requires copied receiver-read returns and conditions without calls, mutation or ownership effects");
						}
					}
				}
				if (!((ClassType) owner.semantic_type).is_interface) {
					foreach (var entry in owner.virtual_entries) {
						var requirement = entry as CoreMethod;
						if (requirement != null && requirement.declaring_type.semantic_type is ClassType && ((ClassType) requirement.declaring_type.semantic_type).is_interface) {
							fail ("interface dispatch", "concrete Class must replace every abstract operation with its exact implementation");
						}
					}
				}
				bool required = owner.parent_class != null || expected.length != 0;
				foreach (var child in program.classes) {
					if (child.parent_class == owner) {
						required = true;
					}
				}
				if (required != owner.polymorphic) {
					fail ("class header", "pay-for-use header must correspond to this participating hierarchy");
				}
				complete.insert (owner, true);
			}
		}
		if (nominated != null) {
			CoreProperty? message = null;
			foreach (var property in nominated.properties) {
				if (property.name == "message") {
					message = property;
				}
			}
			if (message == null || !(message.semantic_type is StringType) || message.setter != null || message.getter.dispatch_kind != ClassDispatchKind.VIRTUAL) {
				fail ("ExceptionRoot", "requires the exact virtual get-only receiver text message slot");
			}
		}
		foreach (var function in program.all_definitions ()) {
			if (function.throws_type == null) {
				continue;
			}
			bool bound = false;
			foreach (var owner in program.classes) {
				if (owner.semantic_type == function.throws_type && nominated != null && function.throws_type.derives_from ((ClassType) nominated.semantic_type)) {
					bound = true;
				}
			}
			if (!bound || (function is CoreLifecycle && (!(function is CoreConstructor) || !ConstructorContracts.admitted (((CoreConstructor) function).declaring_class.foreign_export, ((CoreConstructor) function).declaring_class.allocation_policy, ((CoreConstructor) function).member_ordinal, function.throws_type) && (((CoreConstructor) function).declaring_class.concurrency_policy == null || !((CoreConstructor) function).declaring_class.concurrency_policy.singleton))) || (function is CorePropertyAccessor && (!(function is CorePropertyGetter) || !(((CorePropertyAccessor) function).property_member.declaring_type is CoreClass) || ((CorePropertyAccessor) function).property_member.setter != null || function.dispatch_kind != ClassDispatchKind.DIRECT || (!((CorePropertyAccessor) function).property_member.is_owned_lazy && !PropertyValueTypes.supports_cache (function.return_type))))) {
				fail ("throws declaration", "requires an exact program-owned nominated exception subtype and native callable");
			}
			foreach (var exported in program.c_exports) {
				if (exported.target == function) {
					fail ("throws declaration", "private exception channel cannot cross a C export");
				}
			}
		}
	}

	private static bool interface_read_block(CoreBlock body, CoreMethod method) {
		foreach (var statement in body.statements) {
			var returned = statement as CoreReturn;
			if (returned != null) {
				if (returned.value == null || !interface_read_value (returned.value, method)) {
					return false;
				}
				continue;
			}
			var branch = statement as CoreIf;
			if (branch != null) {
				if (!interface_read_value (branch.condition, method) || !interface_read_block (branch.then_block, method) ||
				    branch.else_block != null && !interface_read_block (branch.else_block, method)) {
					return false;
				}
				continue;
			}
			if (statement is CoreScope && !(statement is CoreWithScope) && interface_read_block (((CoreScope) statement).body, method)) {
				continue;
			}
			return false;
		}
		return true;
	}

	private static bool interface_read_value(CoreValue value, CoreMethod method) {
		if (value is CoreIntegerValue || value is CoreBooleanValue || value is CoreParameterValue) {
			return true;
		}
		if (value is CoreOwnedFieldBorrow) {
			return interface_read_field (((CoreOwnedFieldBorrow) value).source, method);
		}
		var indexed = (value is CoreLoadValue) ? ((CoreLoadValue) value).source as CoreSliceElementPlace : null;
		if (indexed != null) {
			return interface_read_value (indexed.slice, method) && interface_read_value (indexed.index, method);
		}
		if (value is CorePrefixValue) {
			return interface_read_value (((CorePrefixValue) value).operand, method);
		}
		if (value is CoreComparisonChain) {
			foreach (var operand in ((CoreComparisonChain) value).operands) {
				if (!interface_read_value (operand, method)) {
					return false;
				}
			}
			return true;
		}
		if (value is CoreBinaryValue) {
			var binary = (CoreBinaryValue) value;
			return interface_read_value (binary.left, method) && interface_read_value (binary.right, method);
		}
		if (value is CoreShortCircuitValue) {
			var binary = (CoreShortCircuitValue) value;
			return interface_read_value (binary.left, method) && interface_read_value (binary.right, method);
		}
		if (value is CoreIntegerShiftValue) {
			var shift = (CoreIntegerShiftValue) value;
			return interface_read_value (shift.operand, method) && interface_read_value (shift.count, method);
		}
		var load = value as CoreLoadValue;
		var field = load == null ? null : load.source as CoreIndirectFieldPlace;
		return field != null && interface_read_field (field, method);
	}

	private static bool interface_read_field(CoreIndirectFieldPlace field, CoreMethod method) {
		CoreValue receiver = field.pointer;
		while (receiver is CoreClassUpcast) {
			receiver = ((CoreClassUpcast) receiver).reference;
		}
		return receiver is CoreReceiverValue && ((CoreReceiverValue) receiver).receiver == method.receiver;
	}

	private void verify_borrowed_getter(CorePropertyAccessor accessor) throws CoreError {
		if (accessor.native_declaration != null) {
			verify_native_declaration (accessor, "borrowed native getter");
			return;
		}
		var returned = accessor.body.statements.length == 1 ? accessor.body.statements[0] as CoreReturn : null;
		var load = returned == null ? null : returned.value as CoreLoadValue;
		var record_return = accessor.body.statements.length == 1 ? accessor.body.statements[0] as CoreStructReturn : null;
		var observation = record_return == null ? null : record_return.producer as CoreStructBorrowSnapshot;
		var place = observation == null ? (load == null ? null : load.source as CoreIndirectFieldPlace) : observation.source as CoreIndirectFieldPlace;
		var receiver = place == null ? null : place.pointer as CoreReceiverValue;
		if (accessor.locals.length != 0 || accessor.parameters.length != 0 || accessor.result_contract != ResultOwnershipContract.RECEIVER_BORROW || accessor.dispatch_kind != ClassDispatchKind.DIRECT || place == null || receiver == null || receiver.receiver != accessor.receiver || place.field.containing_type != accessor.property_member.declaring_type || place.field.owned_cleanup == null || place.semantic_type != accessor.return_type) {
			fail ("borrowed getter", "requires one exact owned receiver-field projection without effects or result ownership");
		}
	}

	private void verify_text_getter(CorePropertyAccessor accessor) throws CoreError {
		if (accessor.native_declaration != null) {
			verify_native_declaration (accessor, "native text getter");
			return;
		}
		var returned = accessor.body.statements.length == 1 ? accessor.body.statements[0] as CoreReturn : null;
		var value = returned == null ? null : returned.value;
		var load = value as CoreLoadValue;
		var place = load == null ? null : load.source as CoreIndirectFieldPlace;
		var cast = place == null ? null : place.pointer as CoreClassUpcast;
		var receiver = place == null ? null : (cast == null ? place.pointer : cast.reference) as CoreReceiverValue;
		bool backing = place != null && (cast == null ? place.field.containing_type == accessor.property_member.declaring_type : cast.source_class == accessor.property_member.declaring_type && cast.target_class == place.field.containing_type);
		if (accessor.locals.length != 0 || accessor.parameters.length != 0 || !(value is CoreTextValue || (receiver != null && receiver.receiver == accessor.receiver && place.field.text_snapshot && backing))) {
			fail ("text getter", "requires one literal or exact readonly receiver snapshot return without effects");
		}
	}

	private SemanticType? string_type;
	private GenericArray<CoreIterationContract> active_iterations = new GenericArray<CoreIterationContract> ();
	private GenericArray<CoreSequenceIteration> active_sequences = new GenericArray<CoreSequenceIteration> ();
	private CoreSequenceIteration? sequence_step;
	private CoreIterationContract? iteration_step;
	private GenericArray<CoreWithContract> active_with = new GenericArray<CoreWithContract> ();
	private bool with_overlap(SemanticType type) {
		if (type is ReceiverType) {
			type = ((ReceiverType) type).instance_type;
		}
		foreach (var contract in active_with) {
			if (OwnedChildComposition.may_invalidate (type, contract.source.semantic_type, possible_child_edges)) {
				return true;
			}
		}
		return false;
	}

	private void with_mutation(CorePlace place, string path) throws CoreError {
		foreach (var contract in active_with) {
			if (place == contract.source) {
				fail (path, "with receiver cannot be replaced while its capture is live");
			}
		}
		var field = place as CoreIndirectFieldPlace;
		if (field != null && with_overlap (field.field.containing_type.semantic_type)) {
			fail (path, "with receiver excludes overlapping field mutation");
		}
		var element = place as CoreSliceElementPlace;
		var borrow = element == null ? null : element.slice as CoreOwnedFieldBorrow;
		if (borrow != null && with_overlap (borrow.source.field.containing_type.semantic_type)) {
			fail (path, "with receiver excludes overlapping buffer mutation");
		}
	}

	private HashTable<CoreFunction, bool> readonly_inspectors = new HashTable<CoreFunction, bool> (direct_hash, direct_equal);

	private static bool same_iteration_store(CoreIndirectFieldPlace left, CoreIndirectFieldPlace right) {
		if (left.field != right.field) {
			return false;
		}
		var a = left.pointer as CoreLoadValue;
		var b = right.pointer as CoreLoadValue;
		if (a != null && b != null) {
			return a.source == b.source;
		}
		var p = left.pointer as CoreParameterValue;
		var q = right.pointer as CoreParameterValue;
		return p != null && q != null && p.parameter == q.parameter;
	}

	private void verify_iteration_consumption(CoreOwnedLocal? owner, string path) throws CoreError {
		if (owner == null) {
			return;
		}
		foreach (var sequence in active_sequences) {
			if (sequence_local (sequence.source) == owner.place) {
				fail (path, "foreach cannot consume or release its active sequence");
			}
		}
		foreach (var contract in active_with) {
			if (owner.place == contract.source) {
				fail (path, "with receiver cannot be consumed or released while its capture is live");
			}
		}
		foreach (var iteration in active_iterations) {
			var load = iteration.store.pointer as CoreLoadValue;
			if (load != null && load.source == owner.place) {
				fail (path, "foreach cannot consume or release its active collection");
			}
		}
	}

	private static CoreLocalPlace? sequence_local(CoreValue source) {
		if (source is CoreSliceFromArrayValue) {
			return ((CoreSliceFromArrayValue) source).storage;
		}
		if (source is CoreOwnedBufferBorrow) {
			return ((CoreOwnedBufferBorrow) source).source.place;
		}
		var load = source as CoreLoadValue;
		return load == null ? null : load.source as CoreLocalPlace;
	}

	private static bool same_sequence(CoreValue left, CoreValue right) {
		if (left.semantic_type != right.semantic_type || left.get_type () != right.get_type ()) {
			return false;
		}
		if (left is CoreSliceFromArrayValue) {
			var a = (CoreSliceFromArrayValue) left;
			var b = (CoreSliceFromArrayValue) right;
			return a.storage == b.storage && a.start == null && a.count == null && b.start == null && b.count == null;
		}
		if (left is CoreLoadValue || left is CoreOwnedBufferBorrow) {
			return sequence_local (left) != null && sequence_local (left) == sequence_local (right);
		}
		var a = left as CoreParameterValue;
		var b = right as CoreParameterValue;
		return a != null && b != null && a.parameter == b.parameter;
	}

	private void verify_sequence_shape(CoreWhile loop, CoreFunction function, string path) throws CoreError {
		var sequence = loop.sequence;
		if (sequence.is_iterator) {
			verify_iterator_shape (loop, function, path);
			return;
		}
		var slice = sequence.source.semantic_type as SliceType;
		if (sequence.target != loop.target || loop.iteration != null || slice == null || sequence.index == null || sequence.index == sequence.binding
		    || sequence.index.address_taken || sequence.index.semantic_type.kind != TypeKind.INT
		    || !function.locals.find (sequence.index) || !function.locals.find (sequence.binding)
		    || sequence.binding.semantic_type != slice.element_type || CopyabilityAuthority.value_copy (slice.element_type, copy_fields) != Copyability.COPYABLE
		    || !same_sequence (sequence.source, sequence.source)) {
			fail (path, "foreach lost exact copyable sequence/index/binding authority");
		}
		verify_value (sequence.source, function, path + "/source", null, false, null, false, false, false, true);
		var condition = loop.condition as CoreBinaryValue;
		var index = condition == null ? null : condition.left as CoreLoadValue;
		var length = condition == null ? null : condition.right as CoreSliceLengthValue;
		if (condition == null || condition.operator_kind != BinaryOperator.LESS || index == null || index.source != sequence.index
		    || length == null || !same_sequence (length.slice, sequence.source)) {
			fail (path, "foreach sequence condition lost its exact length guard");
		}
		var first = loop.body.statements.length == 0 ? null : loop.body.statements[0];
		var copied = first as CoreInitialize;
		var record = first as CoreStructResultStore;
		var snapshot = record == null ? null : record.producer as CoreStructSnapshot;
		var load = copied == null ? null : copied.value as CoreLoadValue;
		var place = (load != null ? load.source : snapshot == null ? null : snapshot.source) as CoreSliceElementPlace;
		var selected = place == null ? null : place.index as CoreLoadValue;
		if (place == null || selected == null || selected.source != sequence.index || !same_sequence (place.slice, sequence.source)
		    || (copied != null ? copied.target != sequence.binding || copied.acquisition != null : record == null || record.destination != sequence.binding || !record.initializes_destination)) {
			fail (path, "foreach must copy its exact indexed element before the body");
		}
		var step = loop.step == null || loop.step.statements.length != 1 ? null : loop.step.statements[0] as CoreStore;
		var add = step == null ? null : step.value as CoreBinaryValue;
		var prior = add == null ? null : add.left as CoreLoadValue;
		var one = add == null ? null : add.right as CoreIntegerValue;
		if (step == null || step.target != sequence.index || add == null || add.operator_kind != BinaryOperator.ADD
		    || prior == null || prior.source != sequence.index || one == null || one.value.signed_value != 1) {
			fail (path, "foreach sequence must advance its hidden index by one");
		}
	}

	private static bool iterator_receiver(CoreValue? receiver, CoreSequenceIteration contract) {
		var object_receiver = receiver as CoreObjectReceiverValue;
		return object_receiver != null && same_sequence (object_receiver.reference, contract.source);
	}

	private void verify_iterator_shape(CoreWhile loop, CoreFunction function, string path) throws CoreError {
		var sequence = loop.sequence;
		var owner = structs.lookup (sequence.source.semantic_type) as CoreClass;
		var advance = sequence.advance;
		var current = sequence.current;
		if (owner == null || owner.polymorphic || owner.parent_class != null || owner.generic_instance != null
		    || sequence.target != loop.target || loop.iteration != null || sequence.index != null || loop.step != null
		    || !function.locals.find (sequence.binding) || !same_sequence (sequence.source, sequence.source)
		    || advance == null || current == null || !owner.methods.find (advance) || !owner.methods.find (current)
		    || advance.name != "advance" || current.name != "current" || advance.parameters.length != 0 || current.parameters.length != 0
		    || advance.return_type.kind != TypeKind.BOOL || advance.async_body != null || current.async_body != null
		    || advance.dispatch_kind != ClassDispatchKind.DIRECT || current.dispatch_kind != ClassDispatchKind.DIRECT
		    || current.owned_cleanup != null || current.return_type != sequence.binding.semantic_type
		    || CopyabilityAuthority.value_copy (current.return_type, copy_fields) != Copyability.COPYABLE) {
			fail (path, "foreach iterator lost its exact native method/value contract");
		}
		var condition = loop.condition as CoreCallValue;
		if (condition == null || condition.target != advance || condition.arguments.length != 0 || !iterator_receiver (condition.receiver, sequence)) {
			fail (path, "foreach iterator must call its exact advance method for each condition");
		}
		var first = loop.body.statements.length == 0 ? null : loop.body.statements[0];
		var initial = first as CoreInitialize;
		var record = first as CoreStructResultStore;
		var call = initial == null ? null : initial.value as CoreCallValue;
		var copied = record == null ? null : record.producer as CoreStructCallResult;
		if (call != null) {
			if (initial.target != sequence.binding || initial.acquisition != null || call.target != current || call.arguments.length != 0 || !iterator_receiver (call.receiver, sequence)) {
				fail (path, "foreach iterator observation lost its copied current value");
			}
		} else if (copied == null || record.destination != sequence.binding || !record.initializes_destination
		         || copied.target != current || copied.arguments.length != 0 || !iterator_receiver (copied.receiver, sequence)) {
			fail (path, "foreach iterator must copy current before its body");
		}
	}

	private void verify_iteration_shape(CoreWhile loop, CoreFunction function, string path) throws CoreError {
		var iteration = loop.iteration;
		if (iteration == null || iteration.target != loop.target || iteration.index.address_taken || iteration.index.semantic_type.kind != TypeKind.INT || !function.locals.find (iteration.index) || !(iteration.store.semantic_type is OwnerSlotsType) || !(iteration.store.field.containing_type is CoreClass) || ((CoreClass) iteration.store.field.containing_type).generic_instance == null) {
			fail (path, "foreach lost exact Bag/index/target authority");
		}
		var element = ((OwnerSlotsType) iteration.store.semantic_type).element;
		if ((iteration.binding != null) != (element is StructType)) {
			fail (path, "container iteration lost its copy-versus-loan binding");
		}
		if (iteration.binding != null) {
			var copied = loop.body.statements.length == 0 ? null : loop.body.statements[0] as CoreStructResultStore;
			var read = copied == null ? null : copied.producer as CoreSlotsRecordRead;
			var position = read == null ? null : read.index as CoreLoadValue;
			if (iteration.binding.semantic_type != element || !function.locals.find (iteration.binding) || copied == null || copied.destination != iteration.binding || !copied.initializes_destination || read == null || read.remove || position == null || position.source != iteration.index || !same_iteration_store (read.store, iteration.store)) {
				fail (path, "container iteration must snapshot its complete exact record before each body");
			}
		}
		var test = loop.condition as CoreBinaryValue;
		var index = test == null ? null : test.left as CoreLoadValue;
		var length = test == null ? null : test.right as CoreSlotsValue;
		if (test == null || test.operator_kind != BinaryOperator.LESS || index == null || index.source != iteration.index || length == null || length.action != OwnerSlotsAction.LENGTH || !same_iteration_store (length.store, iteration.store)) {
			fail (path, "foreach condition must guard its exact index against current Bag length");
		}
		var step = loop.step == null || loop.step.statements.length != 1 ? null : loop.step.statements[0] as CoreStore;
		var add = step == null ? null : step.value as CoreBinaryValue;
		var prior = add == null ? null : add.left as CoreLoadValue;
		var one = add == null ? null : add.right as CoreIntegerValue;
		if (step == null || step.target != iteration.index || add == null || add.operator_kind != BinaryOperator.ADD || prior == null || prior.source != iteration.index || one == null || one.value.signed_value != 1) {
			fail (path, "foreach step must advance its exact hidden index by one");
		}
	}

	private CodeEffectAnalysis? readonly_inference;
	private CoreFunction? readonly_scope;
	private CodeEffectSummary? readonly_result;
	public static CodeEffectAnalysis infer_effects(CoreProgram program) {
		var origins = new CoreCodeOrigins (program);
		var effects = create_effect_analysis (origins);
		foreach (var function in program.all_definitions ()) {
			var parameters = new GenericArray<Object> ();
			var formals = new GenericArray<Object> ();
			foreach (var parameter in function.parameters) {
				parameters.add (parameter);
				var signature = parameter.semantic_type as FunctionValueType;
				if (signature == null) {
					continue;
				}
				bool first_order = true;
				foreach (var type in signature.parameter_types) {
					first_order &= !(type is FunctionValueType);
				}
				if (first_order) {
					formals.add (parameter);
				}
			}
			var positions = new GenericArray<int> ();
			for (int p = 0; p < function.parameters.length; p++) {
				if (!(function.parameters[p].semantic_type is FunctionValueType)) {
					continue;
				}
				bool record_leaf = false;
				if (!record_leaf) {
					positions.add (p);
				}
			}
			var declaration = function.native_declaration;
			effects.add_function (function, parameters, formals,
				declaration == null ? null : Astra.Code.CodeInputSet.decode (declaration.identity.scoped_readonly,
					declaration.identity.readonly_inputs, (int) parameters.length, positions),
				declaration == null ? null : Astra.Code.CodeInputSet.decode (true,
					declaration.identity.callback_inputs, (int) parameters.length, positions));
		}
		origins.add_effect_calls (effects);
		var probe = new CoreVerifier ();
		probe.code_program = program;
		probe.readonly_inference = effects;
		effects.infer_readonly (probe.probe_readonly);
		effects.infer_requirements ();
		return effects;
	}

	private bool probe_readonly(Object function, CodeEffectSummary result) {
		var checker = new CoreVerifier ();
		foreach (var definition in code_program.all_definitions ()) {
			checker.functions.insert (definition, definition);
		}
		foreach (var record in code_program.structs) {
			checker.structs.insert (record.semantic_type, record);
		}
		foreach (var definition in code_program.enums) {
			checker.enum_definitions.insert (definition.semantic_type, definition);
		}
		checker.readonly_inference = readonly_inference;
		checker.readonly_scope = (CoreFunction) function;
		checker.readonly_result = result;
		try {
			checker.readonly_inspector ((CoreFunction) function, "declarative callback summary");
			return true;
		} catch (CoreError error) {
			return false;
		}
	}

	private static void verify_callback_effects(CoreProgram program) throws CoreError {
		bool needed = false;
		foreach (var function in program.functions) {
			var declaration = function.native_declaration;
			needed |= declaration != null && (declaration.identity.readonly_inputs != "" || declaration.identity.callback_inputs != "");
		}
		if (!needed) {
			return;
		}
		var effects = infer_effects (program);
		foreach (var function in program.functions) {
			var required = effects.required_summary (function);
			if (required == null || !required.eligible) {
				throw new CoreError.INVALID_IR ("native callback inputs require independently proved readonly code");
			}
		}
	}

	// Vala shares closure storage within one method. Keep this long-lived
	// frontier separate from probes that capture the analysis or its owner.
	private static CodeEffectAnalysis create_effect_analysis(CoreCodeOrigins origins) {
		return new CodeEffectAnalysis ((value, formals) => origins.effect_frontier (value, formals));
	}

	private static GenericArray<Object> effect_arguments(GenericArray<CoreValue> values) {
		var result = new GenericArray<Object> ();
		foreach (var value in values) {
			result.add (value);
		}
		return result;
	}

	private void readonly_call(CoreFunction? target, GenericArray<CoreValue> arguments, string path) throws CoreError {
		if (readonly_inference == null) {
			readonly_inspector (target, path);
		} else if (target == null || !readonly_inference.call (target, effect_arguments (arguments), readonly_scope, readonly_result)) {
			fail (path, "readonly scoped inspector unproved conditional direct call effect");
		}
	}

	private CoreProgram code_program;
	private CoreCodeOrigins? code_origins;
	private bool readonly_scalar(SemanticType type) {
		if (type is FunctionValueType || FunctionValueType.scalar (type) || type is StringType) {
			return true;
		}
		if (!type.is_struct_storage ()) {
			return false;
		}
		try {
			foreach (var leaf in StructLeafOrder.enumerate (type, copy_fields)) {
				if (!FunctionValueType.scalar (leaf.semantic_type)) {
					return false;
				}
			}
		} catch (StructLeafError error) {
			return false;
		}
		return true;
	}

	private void readonly_c_arguments(GenericArray<CoreValue> arguments, string path) throws CoreError {
		foreach (var argument in arguments) {
			if (!readonly_scalar (argument.semantic_type)) {
				fail (path, "readonly scoped inspection cannot expose mutable C pointers, handles or buffers");
			}
			readonly_value (argument, path);
		}
	}

	private void readonly_place(CorePlace place, string path) throws CoreError {
		if (place is CoreLocalPlace) {
			return;
		}
		if (place is CoreSliceElementPlace) {
			var element = (CoreSliceElementPlace) place;
			readonly_value (element.slice, path);
			readonly_value (element.index, path);
			return;
		}
		if (place is CoreStorageFieldPlace) {
			readonly_place (((CoreStorageFieldPlace) place).aggregate, path);
			return;
		}
		if (place is CoreIndirectFieldPlace) {
			readonly_value (((CoreIndirectFieldPlace) place).pointer, path);
			return;
		}
		fail (path, "readonly scoped inspector cannot read unproved indirect storage");
	}

	private void readonly_producer(CoreStructProducer source, string path) throws CoreError {
		if (source is CoreStructInvocationResult) {
			readonly_value (((CoreStructInvocationResult) source).invocation, path);
			return;
		}
		if (source.contract.mode == StructValueMode.BORROW_VALUE) {
			if (source is CoreStructBorrowSnapshot) {
				readonly_place (((CoreStructBorrowSnapshot) source).source, path);
				return;
			}
			var call = source as CoreStructCallResult;
			if (call != null && call.target is CorePropertyGetter && call.target.result_contract == ResultOwnershipContract.RECEIVER_BORROW) {
				if (call.receiver != null) {
					readonly_value (call.receiver, path);
				}
				foreach (var argument in call.arguments) {
					readonly_value (argument, path);
				}
				readonly_call (call.target, call.arguments, path);
				return;
			}
			fail (path, "readonly borrowed record requires its exact pure receiver getter");
			return;
		}
		if (source.contract.mode != StructValueMode.COPY_VALUE || !readonly_scalar (source.semantic_type)) {
			fail (path, "readonly scoped inspector record cannot transport mutable aliases");
		}
		if (source is CoreStructProjectionProducer) {
			readonly_producer (((CoreStructProjectionProducer) source).source, path);
			return;
		}
		if (source is CoreStructSnapshot) {
			readonly_place (((CoreStructSnapshot) source).source, path);
			return;
		}
		if (source is CoreStructCallResult) {
			var call = (CoreStructCallResult) source;
			if (call.receiver != null) {
				readonly_value (call.receiver, path);
			}
			foreach (var argument in call.arguments) {
				readonly_value (argument, path);
			}
			readonly_call (call.target, call.arguments, path);
			return;
		}
		fail (path, "readonly scoped inspector requires a bounded record snapshot or call");
	}

	private void readonly_value(CoreValue value, string path) throws CoreError {
		if (readonly_inference != null && value is CoreFunctionAddress) {
			return;
		}
		if (value is CoreSliceLengthValue) {
			readonly_value (((CoreSliceLengthValue) value).slice, path);
			return;
		}
		if (value is CoreStructProjectionValue) {
			readonly_producer (((CoreStructProjectionValue) value).source, path);
			return;
		}
		if (value is CoreIntegerValue || value is CoreFloatValue || value is CoreBooleanValue || value is CoreNullPointerValue || value is CoreTextValue || value is CoreParameterValue || value is CoreReceiverValue) {
			return;
		}
		if (value is CoreLoadValue) {
			readonly_place (((CoreLoadValue) value).source, path);
			return;
		}
		if (value is CoreOwnedFieldBorrow) {
			readonly_value (((CoreOwnedFieldBorrow) value).source.pointer, path);
			return;
		}
		if (value is CoreObjectReceiverValue) {
			readonly_value (((CoreObjectReceiverValue) value).reference, path);
			return;
		}
		if (value is CoreClassUpcast) {
			readonly_value (((CoreClassUpcast) value).reference, path);
			return;
		}
		if (value is CoreSlotsValue) {
			var query = (CoreSlotsValue) value;
			if (readonly_inference != null && query.action == OwnerSlotsAction.BORROW) {
				readonly_place (query.store, path);
				if (query.operand != null) {
					readonly_value (query.operand, path);
				}
				return;
			}
			if (query.action != OwnerSlotsAction.LENGTH && query.action != OwnerSlotsAction.CAPACITY || query.operand != null) {
				fail (path, "readonly scoped inspector cannot mutate or expose collection storage");
			}
			readonly_value (query.store.pointer, path);
			return;
		}
		if (value is CoreTextLengthValue) {
			readonly_value (((CoreTextLengthValue) value).receiver, path);
			return;
		}
		if (value is CorePrefixValue) {
			readonly_value (((CorePrefixValue) value).operand, path);
			return;
		}
		if (value is CoreBinaryValue) {
			readonly_value (((CoreBinaryValue) value).left, path);
			readonly_value (((CoreBinaryValue) value).right, path);
			return;
		}
		if (value is CoreShortCircuitValue) {
			readonly_value (((CoreShortCircuitValue) value).left, path);
			readonly_value (((CoreShortCircuitValue) value).right, path);
			return;
		}
		if (value is CoreComparisonChain) {
			foreach (var operand in ((CoreComparisonChain) value).operands) {
				readonly_value (operand, path);
			}
			return;
		}
		if (value is CoreIntegerConversionValue) {
			readonly_value (((CoreIntegerConversionValue) value).operand, path);
			return;
		}
		if (value is CoreFloatConversionValue) {
			readonly_value (((CoreFloatConversionValue) value).operand, path);
			return;
		}
		if (value is CoreNumericConversionValue) {
			readonly_value (((CoreNumericConversionValue) value).operand, path);
			return;
		}
		if (value is CoreStructArgument) {
			readonly_producer (((CoreStructArgument) value).producer, path);
			return;
		}
		if (value is CoreFunctionValueCall) {
			var call = (CoreFunctionValueCall) value;
			var signature = (FunctionValueType) call.callee.semantic_type;
			bool requires_target = false;
			foreach (var parameter in signature.parameter_types) {
				requires_target |= !readonly_scalar (parameter) || parameter is FunctionValueType || parameter is StringType;
			}
			if (requires_target) {
				if (readonly_inference != null) {
					if (!readonly_inference.code (call.callee, readonly_scope, readonly_result, effect_arguments (call.arguments))) {
						fail (path, "readonly scoped inspector unproved declarative callback origin or invocation context");
					}
					readonly_value (call.callee, path);
					foreach (var argument in call.arguments) {
						readonly_value (argument, path);
					}
					return;
				}
				if (code_origins == null) {
					code_origins = new CoreCodeOrigins (code_program);
				}
				var targets = code_origins.targets (call.callee);
				if (targets == null) {
					fail (path, "readonly scoped indirect call requires independently proved code targets");
				}
				foreach (var target in targets) {
					readonly_inspector (target, path);
				}
			}
			readonly_value (call.callee, path);
			foreach (var argument in call.arguments) {
				readonly_value (argument, path);
			}
			return;
		}
		if (value is CoreCallValue) {
			var call = (CoreCallValue) value;
			if (call.receiver != null) {
				readonly_value (call.receiver, path);
			}
			foreach (var argument in call.arguments) {
				readonly_value (argument, path);
			}
			readonly_call (call.target, call.arguments, path);
			return;
		}
		if (value is CoreCCallValue) {
			if (!readonly_scalar (value.semantic_type)) {
				fail (path, "readonly scoped inspector cannot acquire foreign pointer or handle results");
			}
			readonly_c_arguments (((CoreCCallValue) value).arguments, path);
			return;
		}
		fail (path, "readonly scoped inspector requires scalar/text observations and bounded native calls");
	}

	private bool readonly_writable(CorePlace place) {
		while (place is CoreStorageFieldPlace) {
			place = ((CoreStorageFieldPlace) place).aggregate;
		}
		var local = place as CoreLocalPlace;
		if (local == null || !readonly_scalar (local.semantic_type)) {
			return false;
		}
		var parameter = local.incoming_parameter;
		return parameter == null || parameter.struct_value_contract == null || parameter.struct_value_contract.mode != StructValueMode.BORROW_VALUE;
	}

	private void readonly_block(CoreBlock block, string path) throws CoreError {
		readonly_statements (block.statements, path);
	}

	private void readonly_statements(GenericArray<CoreStatement> statements, string path) throws CoreError {
		foreach (var statement in statements) {
			if (statement is CoreInitialize) {
				var initial = (CoreInitialize) statement;
				if (!readonly_writable (initial.target) || initial.acquisition != null) {
					fail (path, "readonly scoped inspector permits only copied scalar/text locals");
				}
				readonly_value (initial.value, path);
			} else if (statement is CoreStore) {
				var store = (CoreStore) statement;
				if (!readonly_writable (store.target)) {
					fail (path, "readonly scoped inspector cannot write object fields or indirect storage");
				}
				readonly_value (store.value, path);
			} else if (statement is CoreStructInitialize) {
				var initial = (CoreStructInitialize) statement;
				if (!readonly_writable (initial.target) || initial.record_owner != null) {
					fail (path, "readonly scoped inspector cannot initialize observed or owned record storage");
				}
				if (initial.producer != null) {
					readonly_producer (initial.producer, path);
				}
				readonly_statements (initial.initializers, path);
			} else if (statement is CoreStructCopy) {
				var copy = (CoreStructCopy) statement;
				if (!readonly_writable (copy.destination) || !readonly_scalar (copy.semantic_type)) {
					fail (path, "readonly scoped inspector cannot change observed record storage");
				}
				readonly_place (copy.source, path);
			} else if (statement is CoreAcquireStructParameter) {
				var parameter = (CoreAcquireStructParameter) statement;
				bool borrowed = borrowed_record_parameter (parameter.parameter) && parameter.destination.incoming_parameter == parameter.parameter && !owned_places.contains (parameter.destination);
				if (!borrowed && (!readonly_scalar (parameter.destination.semantic_type) || parameter.parameter.struct_value_contract == null || parameter.parameter.struct_value_contract.mode != StructValueMode.COPY_VALUE)) {
					fail (path, "readonly scoped inspector cannot acquire owning record parameters");
				}
			} else if (statement is CoreStructReturn) {
				readonly_producer (((CoreStructReturn) statement).producer, path);
			} else if (statement is CoreStructResultStore) {
				var stored = (CoreStructResultStore) statement;
				if (!(stored.destination is CoreLocalPlace)) {
					fail (path, "readonly scoped inspector cannot write record fields");
				}
				readonly_producer (stored.producer, path);
			} else if (statement is CoreReturn) {
				var value = ((CoreReturn) statement).value;
				if (value != null) {
					readonly_value (value, path);
				}
			} else if (statement is CoreScope) {
				readonly_block (((CoreScope) statement).body, path);
			} else if (statement is CoreIf) {
				var branch = (CoreIf) statement;
				readonly_value (branch.condition, path);
				readonly_block (branch.then_block, path);
				if (branch.else_block != null) {
					readonly_block (branch.else_block, path);
				}
			} else if (statement is CoreWhile) {
				var loop = (CoreWhile) statement;
				readonly_value (loop.condition, path);
				readonly_block (loop.body, path);
				if (loop.step != null) {
					readonly_block (loop.step, path);
				}
			} else if (statement is CoreCallStatement) {
				var call = (CoreCallStatement) statement;
				if (call.receiver != null) {
					readonly_value (call.receiver, path);
				}
				foreach (var argument in call.arguments) {
					readonly_value (argument, path);
				}
				readonly_call (call.target, call.arguments, path);
			} else if (statement is CoreCCallStatement) {
				readonly_c_arguments (((CoreCCallStatement) statement).arguments, path);
			} else if (!(statement is CoreBreak || statement is CoreContinue)) {
				fail (path, "readonly scoped inspector cannot mutate ownership or object storage: " + statement.get_type ().name ());
			}
		}
	}

	private void readonly_inspector(CoreFunction? target, string path) throws CoreError {
		if (readonly_inference != null && target is CoreLifecycle) {
			fail (path, "readonly scoped inspector cannot perform lifecycle work");
		}
		var getter = target as CorePropertyGetter;
		if (target == null || !functions.contains (target) || target.dispatch_kind != ClassDispatchKind.DIRECT || target.async_body != null || target.throws_type != null || target is CoreGenericFunction || (getter != null && (getter.property_member.is_lazy || getter.property_member.is_owned_lazy))) {
			fail (path, "readonly scoped inspector requires an exact synchronous nonthrowing direct function without lazy mutation");
		}
		if (target.result_contract == ResultOwnershipContract.OWNED_TRANSFER || target.struct_result_contract != null && target.struct_result_contract.mode == StructValueMode.MOVE_VALUE) {
			fail (path, "readonly scoped inspector cannot acquire owning results");
		}
		foreach (var parameter in target.parameters) {
			if (parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER || parameter.struct_value_contract != null && parameter.struct_value_contract.mode == StructValueMode.MOVE_VALUE) {
				fail (path, "readonly scoped inspector cannot consume an owner");
			}
		}
		if (target.name_span.file.native_interface) {
			verify_native_declaration (target, path);
			if (target.native_declaration == null || !target.native_declaration.identity.scoped_readonly) {
				fail (path, "readonly scoped inspector requires a checked implementation effect");
			}
			return;
		}
		if (readonly_inspectors.contains (target)) {
			return;
		}
		readonly_inspectors.insert (target, true);
		readonly_block (target.body, path);
	}

	private HashTable<Astra.Text.TextBytes, bool> text_literals = new HashTable<Astra.Text.TextBytes, bool> (direct_hash, direct_equal);
	private HashTable<CorePlace, CorePlace> enum_views = new HashTable<CorePlace, CorePlace> (direct_hash, direct_equal);
	private GenericArray<CorePlace> enum_inspections = new GenericArray<CorePlace> ();
	private GenericArray<CorePlace> enum_reservations = new GenericArray<CorePlace> ();
	private HashTable<EnumType, EnumDefinition> enum_definitions = new HashTable<EnumType, EnumDefinition> (direct_hash, direct_equal);
	private HashTable<CoreEnumProducer, bool> enum_producers = new HashTable<CoreEnumProducer, bool> (direct_hash, direct_equal);
	private HashTable<CoreStructProducer, bool> struct_producers = new HashTable<CoreStructProducer, bool> (direct_hash, direct_equal);
	private HashTable<CoreResultObjectStorage, CoreFunction> result_inputs = new HashTable<CoreResultObjectStorage, CoreFunction> (direct_hash, direct_equal);
	private HashTable<CoreObjectStorage, CoreFunction> object_owners = new HashTable<CoreObjectStorage, CoreFunction> (direct_hash, direct_equal);
	private HashTable<CoreObjectStorage, CoreObjectStorage> object_constructions = new HashTable<CoreObjectStorage, CoreObjectStorage> (direct_hash, direct_equal);
	private HashTable<SemanticType, ReceiverType> initializing_types = new HashTable<SemanticType, ReceiverType> (direct_hash, direct_equal);
	private HashTable<SemanticType, ReceiverType> receiver_types = new HashTable<SemanticType, ReceiverType> (direct_hash, direct_equal);
	private HashTable<CoreReceiver, CoreFunction> receiver_owners = new HashTable<CoreReceiver, CoreFunction> (direct_hash, direct_equal);
	private HashTable<CoreTaskCreate, CoreTaskAwait> direct_wait_creations = new HashTable<CoreTaskCreate, CoreTaskAwait> (direct_hash, direct_equal);
	private HashTable<CoreSliceFromArrayValue, CoreSuspensionLoan> sealed_loan_views = new HashTable<CoreSliceFromArrayValue, CoreSuspensionLoan> (direct_hash, direct_equal);
	private HashTable<CoreLocalPlace, bool> exposed_loan_roots = new HashTable<CoreLocalPlace, bool> (direct_hash, direct_equal);
	private HashTable<Astra.Source.SuspensionLoanIdentity, bool> loan_identities = new HashTable<Astra.Source.SuspensionLoanIdentity, bool> (direct_hash, direct_equal);
	private HashTable<CoreTaskAwait, bool> aggregate_awaits = new HashTable<CoreTaskAwait, bool> (direct_hash, direct_equal);
	private HashTable<CoreTaskAwait, bool> buffer_awaits = new HashTable<CoreTaskAwait, bool> (direct_hash, direct_equal);
	private HashTable<CoreOwnedBufferAllocate, bool> buffer_allocations = new HashTable<CoreOwnedBufferAllocate, bool> (direct_hash, direct_equal);
	private HashTable<CoreCallValue, bool> buffer_producers = new HashTable<CoreCallValue, bool> (direct_hash, direct_equal);
	private HashTable<SemanticType, SliceType> slices = new HashTable<SemanticType, SliceType> (direct_hash, direct_equal);
	private GenericArray<ArrayType> arrays = new GenericArray<ArrayType> ();
	private HashTable<SemanticType, CoreHandle> handles = new HashTable<SemanticType, CoreHandle> (direct_hash, direct_equal);
	private HashTable<CoreParameter, CoreParameter> contract_parameters = new HashTable<CoreParameter, CoreParameter> (direct_hash, direct_equal);
	private GenericArray<CorePlace> active_closure_owners = new GenericArray<CorePlace> ();
	private GenericArray<CorePlace> active_object_receivers = new GenericArray<CorePlace> ();
	private HashTable<CorePlace, CoreOwnedLocal> owned_places = new HashTable<CorePlace, CoreOwnedLocal> (direct_hash, direct_equal);
	private HashTable<CoreLocalPlace, CoreScopedAllocator> scoped_contexts = new HashTable<CoreLocalPlace, CoreScopedAllocator> (direct_hash, direct_equal);
	private GenericArray<CoreLocalPlace> pending_scoped_backings = new GenericArray<CoreLocalPlace> ();
	private HashTable<CoreCleanupContract, CoreCleanupContract> cleanups = new HashTable<CoreCleanupContract, CoreCleanupContract> (direct_hash, direct_equal);
	private HashTable<CoreCFunction, CoreCFunction> c_functions = new HashTable<CoreCFunction, CoreCFunction> (direct_hash, direct_equal);
	private HashTable<CoreFunction, CoreFunction> functions = new HashTable<CoreFunction, CoreFunction> (direct_hash, direct_equal);
	private HashTable<CoreParameter, CoreFunction> owners = new HashTable<CoreParameter, CoreFunction> (direct_hash, direct_equal);
	private HashTable<CorePlace, CoreFunction> local_owners = new HashTable<CorePlace, CoreFunction> (direct_hash, direct_equal);
	private HashTable<CorePlace, CorePlace> initialized = new HashTable<CorePlace, CorePlace> (direct_hash, direct_equal);
	private HashTable<CorePlace, CorePlace> available = new HashTable<CorePlace, CorePlace> (direct_hash, direct_equal);
	private HashTable<CoreBlock, CoreBlock> blocks = new HashTable<CoreBlock, CoreBlock> (direct_hash, direct_equal);
	private HashTable<CoreLoopTarget, CoreFunction> loop_owners = new HashTable<CoreLoopTarget, CoreFunction> (direct_hash, direct_equal);
	private HashTable<CoreLoopTarget, CoreLoopTarget> active_targets = new HashTable<CoreLoopTarget, CoreLoopTarget> (direct_hash, direct_equal);
	private int next_loop_ordinal = 0;
	private GenericArray<SemanticType> allocation_containers = new GenericArray<SemanticType> ();
	private GenericArray<SemanticType> pending_lazy_borrows = new GenericArray<SemanticType> ();
	private GenericArray<SemanticType> pending_field_borrows = new GenericArray<SemanticType> ();
	private GenericArray<CoreLocalPlace> pending_record_borrows = new GenericArray<CoreLocalPlace> ();
	private GenericArray<SemanticType>? child_edges(SemanticType type) {
		var result = new GenericArray<SemanticType> ();
		var record = structs.lookup (type) as CoreStruct;
		if (record != null) {
			foreach (var field in record.fields) {
				if (field.semantic_type is ClassType || field.semantic_type is StructType) {
					result.add (field.semantic_type);
				}
			}
			return result;
		}
		for (var owner = structs.lookup (type) as CoreClass; owner != null; owner = owner.parent_class) {
			foreach (var property in owner.properties) {
				if (property.is_owned_lazy) {
					result.add (property.semantic_type);
				}
			}
			foreach (var field in owner.fields) {
				if (field.semantic_type is ClassType || field.semantic_type is StructType) {
					result.add (field.semantic_type);
				} else if (field.semantic_type is OwnerSlotsType) {
					result.add (((OwnerSlotsType) field.semantic_type).element);
				}
			}
		}
		return result;
	}

	private GenericArray<SemanticType>? possible_child_edges(SemanticType type) {
		var result = child_edges (type);
		var owner = type as ClassType;
		if (owner != null) {
			foreach (var instance in structs.get_values ()) {
				var candidate = instance.semantic_type as ClassType;
				if (candidate != null && candidate != owner && candidate.derives_from (owner)) {
					foreach (var child in child_edges (candidate)) {
						result.add (child);
					}
				}
			}
		}
		return result;
	}

	private FieldInitializationState? field_state;
	private HashTable<CoreLoopTarget, CoreLoopTarget> constructor_breaks = new HashTable<CoreLoopTarget, CoreLoopTarget> (direct_hash, direct_equal);
	private HashTable<int, SemanticType> integer_types = new HashTable<int, SemanticType> (direct_hash, direct_equal);
	private SemanticType? f32_type;
	private SemanticType? f64_type;
	private SemanticType? bool_type;
	private SemanticType? void_type;
	private HashTable<SemanticType, SemanticType> pointer_types = new HashTable<SemanticType, SemanticType> (direct_hash, direct_equal);

	private HashTable<SemanticType, CoreNativeInstance> structs = new HashTable<SemanticType, CoreNativeInstance> (direct_hash, direct_equal);

	private GenericArray<VectorType> vectors = new GenericArray<VectorType> ();

	private bool concrete_only = false;
	private GenericArray<CoreFunction> scoped_constructions = new GenericArray<CoreFunction> ();
	private CoreNode? active_generic;
	private HashTable<TypeParameterType, CoreNode> type_parameters = new HashTable<TypeParameterType, CoreNode> (direct_hash, direct_equal);
	private HashTable<CoreGenericStructIdentity, CoreGenericStruct> generic_structs = new HashTable<CoreGenericStructIdentity, CoreGenericStruct> (direct_hash, direct_equal);
	private HashTable<CorePlace, HashTable<CoreNode, CoreStorageFieldPlace>> deferred_projections = new HashTable<CorePlace, HashTable<CoreNode, CoreStorageFieldPlace>> (direct_hash, direct_equal);

	private GenericOwnershipFlow? generic_owner_flow;
	private static bool ownable_parameter(SemanticType type) {
		return type is TypeParameterType && ((TypeParameterType) type).transport_mode == GenericTransportMode.OWNABLE;
	}

	private static int generic_truth(CoreValue value) {
		return (value is CoreBooleanValue) ? (((CoreBooleanValue) value).literal == BooleanLiteral.TRUE ? 1 : 0) : -1;
	}

	private CoreVerifier () {
	}

	public static void verify(CoreProgram program) throws CoreError {
		foreach (var function in program.generic_functions) {
			if (!function.floating_policy_valid ()) {
				throw new CoreError.INVALID_IR ("generic floating policy differs from its admitted declaration");
			}
		}
		foreach (var function in program.functions) {
			if (!function.floating_policy_valid ()) {
				throw new CoreError.INVALID_IR ("floating policy differs from its admitted declaration");
			}
		}
		var verifier = new CoreVerifier ();
		verifier.utf8_values = CoreUtf8FactoryAuthority.authorize (program);
		foreach (var function in program.functions) {
			verifier.verify_native_declaration (function, "native declaration");
		}
		verifier.verify_program (program);
		verify_callback_effects (program);
		var nonnull_error = CoreNonNull.check (program, verifier.nonnull_definitions);
		if (nonnull_error != null) {
			throw new CoreError.INVALID_IR (nonnull_error.format ());
		}
		CoreTextOrigins.verify (program);
		CoreRuntimeLifetimes.verify (program, verifier.scoped_constructions);
	}

	public static void verify_concrete(CoreProgram program) throws CoreError {
		foreach (var function in program.functions) {
			if (!function.floating_policy_valid ()) {
				throw new CoreError.INVALID_IR ("floating policy differs from its admitted declaration");
			}
		}
		var verifier = new CoreVerifier ();
		verifier.utf8_values = CoreUtf8FactoryAuthority.authorize (program);
		verifier.concrete_only = true;
		foreach (var function in program.functions) {
			verifier.verify_native_declaration (function, "native declaration");
		}
		if (program.generic_functions.length != 0 || program.generic_structs.length != 0) {
			verifier.fail ("CFG boundary", "generic definitions must be removed before CFG");
		}
		verifier.verify_program (program);
		verify_callback_effects (program);
		var nonnull_error = CoreNonNull.check (program, verifier.nonnull_definitions);
		if (nonnull_error != null) {
			throw new CoreError.INVALID_IR (nonnull_error.format ());
		}
		CoreTextOrigins.verify (program);
		CoreRuntimeLifetimes.verify (program, verifier.scoped_constructions);
	}

	private void fail(string path, string message) throws CoreError {
		throw new CoreError.INVALID_IR ("internal Core verification error at %s: %s", path, message);
	}

	private GenericArray<CoreStruct> element_structs;
	private CoreArrayElementPlace? initializing_array_entry;
	private GenericArray<SemanticType>? element_fields(SemanticType type) {
		if (type is CoreGenericStructApplicationType) {
			return copy_fields (type);
		}
		foreach (var structure in element_structs) {
			if (structure.semantic_type != type) {
				continue;
			}
			var result = new GenericArray<SemanticType> ();
			foreach (var field in structure.fields) {
				result.add (field.semantic_type);
			}
			return result;
		}
		return null;
	}

	private void verify_collection_element(SemanticType type, string path) throws CoreError {
		if (!type.is_struct_storage ()) {
			verify_type (type, true, path);
			return;
		}
		if (!BufferElementTypes.supports (type, element_fields)) {
			fail (path, "record collection element requires a complete copyable, zeroable, trivially destructible field graph; invalid path " + (BufferElementTypes.invalid_field (type, element_fields) ?? "<copy>"));
		}
	}

	private void verify_array_type(ArrayType array, string path) throws CoreError {
		if (!ArrayType.supports (array.element_type, array.length)) {
			fail (path, "unsupported array element or length; requires numeric storage and length 1..1024");
			return;
		}
		verify_collection_element (array.element_type, path + "/element");
		foreach (var prior in arrays) {
			if (prior.element_type == array.element_type && prior.length == array.length) {
				if (prior != array) {
					fail (path, "inconsistent array semantic type identity");
				}
				return;
			}
		}
		arrays.add (array);
	}

	private HashTable<CoreGenericStructApplicationType, bool> checking_applications = new HashTable<CoreGenericStructApplicationType, bool> (direct_hash, direct_equal);
	private void verify_application(CoreGenericStructApplicationType application, string path) throws CoreError {
		var definition = application.definition;
		if (concrete_only || definition == null || generic_structs.lookup (application.origin) != definition || application.origin != definition.identity || application.type_arguments.length != definition.type_parameters.length || application.logical_identity != application.origin.nominal_identity.application (application.type_arguments)) {
			fail (path, "generic aggregate requires its exact program-owned definition and argument arity before materialization");
			return;
		}
		if (checking_applications.contains (application) || checking_applications.size () >= 256) {
			fail (path, "cyclic or excessive constructed type-argument graph (maximum depth 256)");
		}
		checking_applications.insert (application, true);
		foreach (var argument in application.type_arguments) {
			verify_type (argument, true, path + "/argument", argument.is_struct_storage ());
			if (!GenericArgumentTypes.plain_copy (argument, copy_fields, copy_premise)) {
				fail (path, "generic struct arguments require complete GEN1_PLAIN_COPY identities and exact scoped premises");
			}
		}
		if (definition.application (application.type_arguments) != application) {
			fail (path, "generic struct application must have canonical exact semantic identity");
		}
		checking_applications.remove (application);
	}

	private int storage_field_count(SemanticType type) throws CoreError {
		var application = type as CoreGenericStructApplicationType;
		if (application != null && application.definition != null) {
			return (int) application.definition.fields.length;
		}
		var structure = structs.lookup (type);
		if (structure == null) {
			fail ("initializer", "storage requires an exact aggregate descriptor");
			return 0;
		}
		return (int) structure.fields.length;
	}

	private CoreNode projection_identity(CoreStorageFieldPlace place) throws CoreError {
		if (place is CoreFieldPlace) {
			return ((CoreFieldPlace) place).field;
		}
		if (place is CoreGenericStructFieldPlace && !concrete_only) {
			return ((CoreGenericStructFieldPlace) place).field;
		}
		fail ("projection", "unsupported or unresolved generic aggregate field Place");
		assert_not_reached ();
	}

	private static bool has_generic_base(CorePlace place) {
		CorePlace current = place;
		while (current is CoreStorageFieldPlace) {
			current = ((CoreStorageFieldPlace) current).aggregate;
			if (current.semantic_type is CoreGenericStructApplicationType) {
				return true;
			}
		}
		return false;
	}

	private void verify_deferred_projection(CoreStorageFieldPlace place, CoreFunction function, string path) throws CoreError {
		var projected = deferred_projections.lookup (place.aggregate);
		if (projected == null) {
			projected = new HashTable<CoreNode, CoreStorageFieldPlace> (direct_hash, direct_equal);
			deferred_projections.insert (place.aggregate, projected);
		}
		var identity = projection_identity (place);
		var prior = projected.lookup (identity);
		if (prior != null && prior != place) {
			fail (path, "generic storage projections require canonical exact base and field identities");
		}
		projected.insert (identity, place);
		if (place.root_local () != null) {
			local_owners.insert (place, function);
			// A fully initialized generic root also initializes projections first
			// encountered after whole-copy initialization, before materialization.
			if (available.contains (place.root_local ())) {
				initialized.insert (place, place);
				available.insert (place, place);
			}
		}
	}

	private void verify_slots_field(CoreStructField field, string path) throws CoreError {
		var type = field.semantic_type as OwnerSlotsType;
		var cleanup = field.slots_cleanup;
		if (type == null || !(field.containing_type is CoreClass) || ((CoreClass) field.containing_type).polymorphic || field.owned_cleanup != null || field.text_snapshot) {
			fail (path, "owner slots lost exact field authority");
		}
		if (field.ordinal < 0 || field.ordinal >= field.containing_type.fields.length || field.containing_type.fields[field.ordinal] != field) {
			fail (path, "owner-slot field requires its exact declared ordinal and identity");
		}
		if (type.element is StructType) {
			if (cleanup != null || copy_fields (type.element) == null) {
				fail (path, "record slots require an exact complete value layout without scalar cleanup");
			}
			try {
				StructLeafOrder.enumerate_storage (type.element, copy_fields);
			} catch (StructLeafError error) {
				fail (path, "record slots require a complete supported layout: " + error.message);
			}
			return;
		}
		if (cleanup == null || !cleanups.contains (cleanup)) {
			fail (path, "owner slots lost exact scalar cleanup authority");
		}
		if (type.element.get_type () == typeof (HandleType)) {
			if (cleanup.is_object || cleanup.is_buffer || cleanup.shared_type != null || cleanup.closure_type != null || !matches_cleanup (type.element, cleanup)) {
				fail (path, "owner slots lost the exact Resource declaration destructor");
			}
			return;
		}
		if (!cleanup.is_heap_object || cleanup.object_class == null || cleanup.object_class.semantic_type != type.element || structs.lookup (type.element) != cleanup.object_class || cleanup.object_class.polymorphic || cleanup.object_class.parent_class != null) {
			fail (path, "owner slots lost exact bounded heap Class cleanup");
		}
	}

	private void verify_slots_place(CoreIndirectFieldPlace store, CoreFunction function, bool read, string path) throws CoreError {
		if (function.async_body != null || function is CoreGenericFunction || function.generic_instance != null) {
			fail (path, "owner slots require synchronous concrete code");
		}
		verify_place (store, function, false, path);
		verify_slots_field (store.field, path);
		var receiver = store.pointer as CoreReceiverValue;
		if (read && receiver != null && receiver.receiver.contract.mode == ReceiverMode.INITIALIZING && (field_state == null || !field_state.is_definite (store.field.ordinal))) {
			fail (path, "owner-slot store read before definite initialization");
		}
	}

	private void verify_slots_mutation(CoreIndirectFieldPlace store, string path) throws CoreError {
		if (active_with.length != 0) {
			fail (path, "with receiver scope excludes structural slot mutation");
		}
		foreach (var pending in pending_field_borrows) {
			if (OwnedChildComposition.may_invalidate (store.field.containing_type.semantic_type, pending, possible_child_edges)) {
				fail (path, "owner-slot mutation overlaps an active loan");
			}
		}
	}

	private void verify_invocation_result(CoreInvocation call, CallableSignature? signature, CoreCleanupContract? acquisition, string path) throws CoreError {
		if (signature == null || !FunctionValueType.supported_result (((CoreValue) call).semantic_type, signature.result_contract)) {
			fail (path, "indirect result requires its exact supported ownership contract");
		}
		var cleanup = call.result_cleanup ();
		if (cleanup != acquisition || (signature.result_contract == ResultOwnershipContract.OWNED_TRANSFER
		        ? cleanup == null || !cleanups.contains (cleanup) || !matches_cleanup (((CoreValue) call).semantic_type, cleanup) || ((CoreValue) call).semantic_type is ClassType && !cleanup.is_heap_object
		        : cleanup != null)) {
			fail (path, "indirect owned result requires its exact acquisition and declared cleanup");
		}
	}

	private void verify_type(SemanticType? semantic_type, bool requires_value, string path, bool aggregate_storage = false) throws CoreError {
		if (semantic_type is ClosureHandleType && !((ClosureHandleType) semantic_type).actor) {
			var signature = (ClosureHandleType) semantic_type;
			try {
				signature.verify_records (signature.record_parameters, copy_fields);
				foreach (var parameter in signature.parameter_types) {
					verify_type (parameter, true, path + "/channel", parameter.is_struct_storage ());
				}
			} catch (StructLeafError error) {
				fail (path, error.message);
			}
		}
		if (semantic_type is FunctionValueType) {
			var signature = (FunctionValueType) semantic_type;
			if ((signature is CallbackType) ? !((CallbackType) signature).supported () : !FunctionValueType.supported_result (signature.result_type, signature.result_contract) || signature.parameter_types.length > 4) {
				fail (path, "function value requires a bounded copied scalar signature");
			}
			verify_type (signature.result_type, signature.result_type.kind != TypeKind.VOID, path + "/result", signature.result_type.is_struct_storage ());
			try {
				signature.verify_records (signature.record_parameters, copy_fields);
				foreach (var parameter in signature.parameter_types) {
					verify_type (parameter, true, path + "/channel", parameter.is_struct_storage ());
				}
			} catch (StructLeafError error) {
				fail (path, error.message);
			}
			return;
		}
		if (semantic_type is ExecutorType || semantic_type is TaskType) {
			return;
		}
		if (semantic_type == null) {
			fail (path, "missing semantic type");
			return;
		}
		if (semantic_type is EnumType) {
			if (!enum_definitions.contains ((EnumType) semantic_type)) {
				fail (path, "enum type requires its exact program definition");
			}
			return;
		}
		if (semantic_type.kind == TypeKind.GENERIC_STRUCT_APPLICATION) {
			var application = semantic_type as CoreGenericStructApplicationType;
			if (concrete_only || application == null) {
				fail (path, "unresolved generic aggregate; concrete stages require materialization");
				return;
			}
			verify_application (application, path);
			if (!aggregate_storage) {
				fail (path, "generic struct application is storage only; whole aggregate values and ABI are unsupported");
			}
			return;
		}
		if (aggregate_storage && semantic_type is StructType) {
			if (!structs.contains (semantic_type)) {
				fail (path, "aggregate requires exact program-owned struct descriptor");
			}
			return;
		}
		var open_class = semantic_type as ExactGenericClassType;
		if (open_class != null && open_class.is_parameterized ()) {
			if (concrete_only || active_generic == null || !open_class.definition.valid ()) {
				fail (path, "unresolved Class application requires its exact lexical generic scope");
			}
			foreach (var argument in open_class.arguments.copy_values ()) {
				verify_type (argument, true, path + "/class-argument", argument.is_struct_storage ());
			}
			return;
		}
		if (semantic_type is TypeParameterType) {
			if (concrete_only || active_generic == null || type_parameters.lookup ((TypeParameterType) semantic_type) != active_generic) {
				fail (path, "unresolved or nonlexical type parameter; concrete stages require monomorphization");
			}
			return;
		}
		if (semantic_type.kind == TypeKind.STRING) {
			if (!(semantic_type is StringType) || (string_type != null && string_type != semantic_type)) {
				fail (path, "text requires canonical StringType identity");
			}
			string_type = semantic_type;
			return;
		}
		if (semantic_type.kind == TypeKind.RECEIVER) {
			var receiver = semantic_type as ReceiverType;
			if (receiver == null || (receiver.mode == ReceiverMode.INITIALIZING ? initializing_types : receiver_types).lookup (receiver.instance_type) != receiver) {
				fail (path, "receiver requires exact declared instance type and compiler-owned contract");
			}
			return;
		}
		if (semantic_type.kind == TypeKind.SLICE) {
			var slice = semantic_type as SliceType;
			if (slice == null || (!SliceType.supports (slice.element_type) && !(slice.element_type is TypeParameterType && element_premise ((TypeParameterType) slice.element_type)))) {
				fail (path, "unsupported slice element; requires exact supported storage or text descriptor type");
				return;
			}
			if (slice.element_type is TypeParameterType) {
				verify_type (slice.element_type, true, path + "/element");
			} else {
				verify_collection_element (slice.element_type, path + "/element");
			}
			if (slice is ContextBytesType) {
				var bytes = (ContextBytesType) slice;
				if (!bytes.valid ()) {
					fail (path, "context byte pair lost its exact owned allocator contract");
				}
				verify_type (bytes.allocator_type, true, path + "/allocator");
			}
			var prior = slices.lookup (slice.canonical_key ());
			if (prior != null && prior != slice) {
				fail (path, "inconsistent slice semantic type identity");
			}
			slices.insert (slice.canonical_key (), slice);
			return;
		}
		if (semantic_type.kind == TypeKind.VECTOR) {
			var vector = semantic_type as VectorType;
			if (vector == null || !VectorType.supports (vector.element_type, vector.lane_count)) {
				fail (path, "unsupported vector element or lane shape");
				return;
			}
			verify_type (vector.element_type, true, path + "/element");
			foreach (var prior in vectors) {
				if (prior.element_type == vector.element_type && prior.lane_count == vector.lane_count) {
					if (prior != vector) {
						fail (path, "inconsistent vector semantic type identity");
					}
					return;
				}
			}
			vectors.add (vector);
			return;
		}
		switch (semantic_type.kind) {
		case TypeKind.INT:
		case TypeKind.I8:
		case TypeKind.U8:
		case TypeKind.I16:
		case TypeKind.U16:
		case TypeKind.U32:
		case TypeKind.I64:
		case TypeKind.U64:
		case TypeKind.ISIZE:
		case TypeKind.USIZE:
			var prior_integer = integer_types.lookup ((int) semantic_type.kind);
			if (prior_integer != null && prior_integer != semantic_type) {
				fail (path, "inconsistent '%s' semantic type identity".printf (semantic_type.display_name ()));
			}
			if (!(semantic_type is IntegerType)) {
				fail (path, "integer type requires immutable IntegerType authority");
			}
			integer_types.insert ((int) semantic_type.kind, semantic_type);
			break;
		case TypeKind.F32:
			if (!(semantic_type is F32Type)) {
				fail (path, "f32 type requires immutable F32Type authority");
			}
			if (f32_type != null && f32_type != semantic_type) {
				fail (path, "inconsistent 'f32' semantic type identity");
			}
			f32_type = semantic_type;
			break;
		case TypeKind.F64:
			if (!(semantic_type is F64Type)) {
				fail (path, "f64 type requires immutable F64Type authority");
			}
			if (f64_type != null && f64_type != semantic_type) {
				fail (path, "inconsistent 'f64' semantic type identity");
			}
			f64_type = semantic_type;
			break;
		case TypeKind.BOOL:
			if (bool_type != null && bool_type != semantic_type) {
				fail (path, "inconsistent 'bool' semantic type identity");
			}
			bool_type = semantic_type;
			break;
		case TypeKind.CLASS:
			if (!(semantic_type is ClassType) || !(structs.lookup (semantic_type) is CoreClass)) {
				fail (path, "class reference requires exact program-owned nominal identity");
			}
			break;
		case TypeKind.HANDLE:
			if (!(semantic_type is HandleType) || !handles.contains (semantic_type)) {
				fail (path, "handle value requires exact declared nominal type identity");
			}
			break;
		case TypeKind.TYPED_POINTER:
			var typed = semantic_type as TypedPointerType;
			if (typed == null || !typed.pointee.is_typed_data_pointee ()) {
				fail (path, "unsupported typed data pointer pointee");
				return;
			}
			if (typed.pointee is StructType) {
				if (!structs.contains (typed.pointee)) {
					fail (path, "typed pointer requires exact program-owned struct identity");
				}
				if (record_field (typed.pointee) != null) {
					fail (path, "owning record pointers are deferred");
				}
			} else {
				verify_type (typed.pointee, true, path + "/pointee", true);
			}
			var prior_pointer = pointer_types.lookup (typed.pointee);
			if (prior_pointer != null && prior_pointer != typed) {
				fail (path, "inconsistent typed pointer semantic type identity");
			}
			pointer_types.insert (typed.pointee, typed);
			break;
		case TypeKind.RAW_POINTER:
			var pointer = semantic_type as RawPointerType;
			if (pointer == null || pointer.pointee.kind != TypeKind.VOID) {
				fail (path, "raw pointer must point to void");
				return;
			}
			if (pointer.pointee.kind == TypeKind.VOID) {
				verify_type (pointer.pointee, false, path + "/pointee");
			}
			var previous = pointer_types.lookup (pointer.pointee);
			if (previous != null && previous != pointer) {
				fail (path, "inconsistent '%s' semantic type identity".printf (pointer.display_name ()));
			}
			pointer_types.insert (pointer.pointee, pointer);
			break;
		case TypeKind.VOID:
			if (requires_value) {
				fail (path, "value or parameter type must be 'int', 'bool' or 'void*', found 'void'");
			}
			if (void_type != null && void_type != semantic_type) {
				fail (path, "inconsistent 'void' semantic type identity");
			}
			void_type = semantic_type;
			break;
			default:
			fail (path, "unsupported semantic type");
			break;
		}
	}

	private CoreStructField? record_field(SemanticType type) {
		if (!(structs.lookup (type) is CoreStruct)) {
			return null;
		}
		CoreStructField? found = null;
		try {
			foreach (var path in StructLeafOrder.enumerate_storage (type, copy_fields)) {
				var field = record_leaf (type, path);
				if (field == null) {
					if (copied_generic_record_leaf (type, path)) {
						continue;
					}
					return null;
				}
				if (field.owned_cleanup != null) {
					if (!(field.semantic_type is HandleType) && !(field.semantic_type is ClassType) && !(field.semantic_type is SliceType)) {
						return null;
					}
					if (found == null) {
						found = field;
					}
				} else if (!NativeFieldTypes.supports (field.semantic_type, false)) {
					return null;
				}
			}
		} catch (StructLeafError error) {
			return null;
		}
		return found;
	}

	private bool copied_generic_record_leaf(SemanticType type, StructLeafPath path) {
		bool generic = false;
		SemanticType current = type;
		for (int d = 0; d < path.depth; d++) {
			int ordinal = path.field_ordinal (d);
			var application = current as CoreGenericStructApplicationType;
			if (application != null) {
				var definition = application.definition;
				if (concrete_only || definition == null || generic_structs.lookup (application.origin) != definition || ordinal < 0 || ordinal >= definition.fields.length || !GenericArgumentTypes.plain_copy (application, copy_fields, copy_premise)) {
					return false;
				}
				current = application.field_type (definition.fields[ordinal]);
				generic = true;
			} else {
				var owner = structs.lookup (current) as CoreStruct;
				if (owner == null || ordinal < 0 || ordinal >= owner.fields.length) {
					return false;
				}
				current = owner.fields[ordinal].semantic_type;
			}
		}
		return generic && current == path.semantic_type && NativeFieldTypes.supports (current, false);
	}

	private CoreStructField? record_leaf(SemanticType type, StructLeafPath path) {
		CoreStructField? field = null;
		for (int d = 0; d < path.depth; d++) {
			var owner = structs.lookup (type) as CoreStruct;
			int ordinal = path.field_ordinal (d);
			if (owner == null || ordinal < 0 || ordinal >= owner.fields.length) {
				return null;
			}
			field = owner.fields[ordinal];
			type = field.semantic_type;
		}
		return field != null && field.semantic_type == path.semantic_type ? field : null;
	}

	private CoreFieldPlace? record_projection(CorePlace aggregate, CoreStructField field, CoreFunction function) {
		foreach (var place in function.field_places) {
			if (place is CoreFieldPlace && ((CoreFieldPlace) place).aggregate == aggregate && ((CoreFieldPlace) place).field == field) {
				return (CoreFieldPlace) place;
			}
		}
		return null;
	}

	private bool closure_capture_type(SemanticType type, HashTable<SemanticType, bool> seen) {
		if (type is RawPointerType || type is TypedPointerType) {
			return false;
		}
		if (type is HandleType || type is StringType || FunctionValueType.scalar (type) || type is VectorType) {
			return true;
		}
		if (seen.contains (type)) {
			return true;
		}
		seen.insert (type, true);
		if (type is SliceType) {
			return closure_capture_type (((SliceType) type).element_type, seen);
		}
		if (type is OwnerSlotsType) {
			return closure_capture_type (((OwnerSlotsType) type).element, seen);
		}
		var owner = structs.lookup (type);
		if (owner == null) {
			var fields = copy_fields (type);
			if (fields == null) {
				return false;
			}
			foreach (var field in fields) {
				if (!closure_capture_type (field, seen)) {
					return false;
				}
			}
			return true;
		}
		foreach (var field in owner.fields) {
			if (!closure_capture_type (field.semantic_type, seen)) {
				return false;
			}
		}
		var object_class = owner as CoreClass;
		return object_class == null || object_class.parent_class == null || closure_capture_type (object_class.parent_class.semantic_type, seen);
	}

	private bool matches_cleanup(SemanticType type, CoreCleanupContract cleanup) {
		if (cleanup.record_type != null) {
			return type == cleanup.record_type.semantic_type && structs.lookup (type) == cleanup.record_type && record_field (type) != null;
		}
		if (cleanup.closure_type != null) {
			return type == cleanup.closure_type && cleanup.closure_environment != null && cleanup.closure_environment.semantic_type == cleanup.closure_type.environment_type && !cleanup.closure_environment.polymorphic;
		}
		if (cleanup.shared_type != null) {
			return type == cleanup.shared_type && cleanup.shared_payload != null && cleanup.shared_payload.semantic_type == cleanup.shared_type.payload_type;
		}
		if (cleanup.is_buffer) {
			return type == cleanup.buffer_type && (cleanup.is_symbolic_buffer ? cleanup.buffer_type.element_type is TypeParameterType && element_premise ((TypeParameterType) cleanup.buffer_type.element_type) : cleanup.buffer_shape.is_valid (element_fields));
		}
		if (cleanup.type_parameter != null) {
			return !concrete_only && type == cleanup.type_parameter && ownable_parameter (type);
		}
		if (cleanup.is_object) {
			return type is ClassType && cleanup.object_class != null && structs.lookup (type) == cleanup.object_class;
		}
		var record = record_field (type);
		if (record != null) {
			return record.owned_cleanup == cleanup;
		}
		var handle = handles.lookup (type);
		return type.is_void_pointer () || (type is HandleType && handle != null && handle.cleanup == cleanup);
	}

	private static bool borrowed_record_parameter(CoreParameter parameter) {
		return parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && parameter.struct_value_contract != null && parameter.struct_value_contract.mode == StructValueMode.BORROW_VALUE && parameter.struct_value_contract.semantic_type == parameter.semantic_type;
	}

	private void verify_parameter_contract(CoreParameter parameter, string path) throws CoreError {
		if (ownable_parameter (parameter.semantic_type) && parameter.heap_object) {
			fail (path, "symbolic ownership parameter must remain allocation-neutral");
		}
		if (parameter.semantic_type is ReceiverType) {
			fail (path, "receiver is not an explicit parameter");
		}
		if (parameter.semantic_type is CallbackType && parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
			fail (path, "Callback requires exact borrowed-noescape parameter transport");
		}
		if (contract_parameters.contains (parameter) || !parameter.pointer_contract.is_valid () || (parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER && !(parameter.semantic_type is HandleType) && !(parameter.semantic_type is ClassType) && !(parameter.semantic_type is SliceType) && !ownable_parameter (parameter.semantic_type)) || (parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && !(parameter.semantic_type is CallbackType) && !parameter.semantic_type.is_ownable_handle_type () && !(parameter.semantic_type is TypedPointerType && (CPlainRecordTypes.pointer (parameter.semantic_type, copy_fields) || (CPlainRecordTypes.i32_pointer (parameter.semantic_type) || ForeignApiTypes.scalar_pointee (parameter.semantic_type) != null))) && !(parameter.semantic_type is StringType) && !(parameter.semantic_type is SliceType) && !(parameter.semantic_type is ClassType) && !ownable_parameter (parameter.semantic_type) && !borrowed_record_parameter (parameter)) || ((parameter.semantic_type is SliceType && parameter.pointer_contract == PointerParameterContract.UNMANAGED) || (parameter.semantic_type is ClassType && parameter.pointer_contract == PointerParameterContract.UNMANAGED))) {
			fail (path, "parameter requires unique identity and a valid ownership or borrowed-noescape contract");
		}
		if (ownable_parameter (parameter.semantic_type) && parameter.pointer_contract == PointerParameterContract.UNMANAGED) {
			fail (path, "plain Ownable T parameter transport is unavailable");
		}
		if (parameter.semantic_type.is_text_slice () && parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
			fail (path, "text slice requires deep borrowed-noescape contract");
		}
		if (parameter.semantic_type is StringType && parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
			fail (path, "string parameter requires borrowed-noescape");
		}
		contract_parameters.insert (parameter, parameter);
	}

	private void verify_program(CoreProgram program) throws CoreError {
		foreach (var function in program.functions) {
			if (function.return_type.is_scoped_allocator ()) {
				fail ("scoped context", "cannot escape through a callable result");
			}
			foreach (var parameter in function.parameters) {
				if (parameter.semantic_type.is_scoped_allocator () && (parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || function.async_body != null)) {
					fail ("scoped context", "requires a synchronous nonescaping borrowed parameter");
				}
			}
		}
		foreach (var function in program.c_functions) {
			if (function.return_type.is_scoped_allocator ()) {
				fail ("scoped context", "cannot be acquired from a foreign factory");
			}
		}
		foreach (var record in program.structs) {
			foreach (var field in record.fields) {
				if (field.semantic_type.is_scoped_allocator ()) {
					fail ("scoped context", "cannot be stored in a field");
				}
			}
		}
		foreach (var record in program.classes) {
			foreach (var field in record.fields) {
				if (field.semantic_type.is_scoped_allocator ()) {
					fail ("scoped context", "cannot be stored in a Class field");
				}
			}
		}
		code_program = program;
		// Accessor links are weak. Reject a retired/missing property before
		// any derived result contract or hierarchy check dereferences it.
		foreach (var function in program.functions) {
			var accessor = function as CorePropertyAccessor;
			if (accessor != null && accessor.property_member == null) {
				fail ("property accessor", "requires its live exact property declaration");
			}
		}
		CoreExactClassAuthority.verify (program);
		verify_class_hierarchy (program);
		element_structs = program.structs;
		foreach (var definition in program.enums) {
			if (enum_definitions.contains (definition.semantic_type)) {
				fail ("enum", "duplicate exact enum definition");
			}
			enum_definitions.insert (definition.semantic_type, definition);
		}
		foreach (var payload in program.text_literals) {
			if (!payload.valid ()) {
				fail ("text literal", "invalid UTF-8 payload or signed-I32 byte length");
			}
			text_literals.insert (payload, true);
		}
		var definitions = program.all_definitions ();
		generic_result_origins = CoreGenericResultOrigins.derive (program);
		generic_result_projection = new CoreResultOriginProjection (program);
		concrete_result_origins = CoreGenericResultOrigins.concrete_results (program);
		for (int g = 0; g < program.generic_structs.length; g++) {
			var generic = program.generic_structs[g];
			if (generic.identity.ordinal != g || generic_structs.contains (generic.identity) || generic.type_parameters.length == 0 || generic.fields.length == 0) {
				fail ("generic struct", "definition requires unique exact identity, ordered nonempty parameters and fields");
			}
			generic_structs.insert (generic.identity, generic);
			var parameter_names = new HashTable<string, string> (str_hash, str_equal);
			for (int t = 0; t < generic.type_parameters.length; t++) {
				var parameter = generic.type_parameters[t];
				var type = parameter.semantic_type;
				if (parameter.ordinal != t || type_parameters.contains (type) || type.capability != GenericCapability.GEN1_PLAIN_COPY || type.explicit_capabilities.length != 0 || parameter.capability_requirements.length != 0 || type.name == "" || parameter_names.contains (type.name) || BuiltinTypes.is_builtin_name (type.name)) {
					fail ("generic struct", "parameters require exact lexical GEN1_PLAIN_COPY identity without struct where clauses");
				}
				type_parameters.insert (type, generic);
				parameter_names.insert (type.name, type.name);
			}
		}
		for (int g = 0; g < program.generic_functions.length; g++) {
			var generic = program.generic_functions[g];
			if (generic.identity.ordinal != g || generic.type_parameters.length == 0 || generic.implicit_receiver != null || generic.name == "main") {
				fail ("generic", "invalid top-level generic definition identity");
			}
			for (int t = 0; t < generic.type_parameters.length; t++) {
				var parameter = generic.type_parameters[t];
				bool required = false;
				foreach (var formal in generic.parameters) {
					var slice = formal.semantic_type as SliceType;
					if (slice != null && slice.element_type == parameter.semantic_type) {
						if ((formal.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE && formal.pointer_contract != PointerParameterContract.OWNED_TRANSFER) || parameter.transport_mode != GenericTransportMode.PLAIN_COPY) {
							fail ("generic", "symbolic slices require plain-copy elements and an exact borrow or transfer contract");
						}
						required = true;
					}
				}
				foreach (var formal in generic.parameters) {
					var enumeration = formal.semantic_type as EnumType;
					if (enumeration != null && enumeration.declares_element (parameter.semantic_type)) {
						required = true;
					}
				}
				var result_enum = generic.return_type as EnumType;
				if (result_enum != null && result_enum.declares_element (parameter.semantic_type)) {
					required = true;
				}
				var result_slice = generic.return_type as SliceType;
				if (result_slice != null && result_slice.element_type == parameter.semantic_type && generic.owned_cleanup != null) {
					required = true;
				}
				if (required != generic.element_obligations.contains (parameter.semantic_type)) {
					fail ("generic", "element obligation must derive from an exact direct T[] boundary or known applied enum signature");
				}
				if (required && (parameter.transport_mode != GenericTransportMode.PLAIN_COPY || generic.element_obligations.requirements (parameter.semantic_type) != GenericElementRequirements.BUFFER)) {
					fail ("generic", "buffer element contract requires separate copy, storage, structural zero and trivial destruction premises");
				}
				if (parameter.ordinal != t || type_parameters.contains (parameter.semantic_type)) {
					fail ("generic", "type parameters require unique exact lexical identities and GEN1_PLAIN_COPY");
				}
				type_parameters.insert (parameter.semantic_type, generic);
				var authority = parameter.semantic_type.explicit_capabilities;
				if (parameter.transport_mode == GenericTransportMode.OWNABLE && authority.length != 1) {
					fail ("generic", "Ownable cannot combine with value capabilities");
				}
				if (authority.length != parameter.capability_requirements.length) {
					fail ("generic", "capability requirement order/set mismatch");
				}
				uint membership = 0;
				for (int r = 0; r < parameter.capability_requirements.length; r++) {
					var requirement = parameter.capability_requirements[r];
					if (requirement.type_parameter != parameter || !requirement.capability.valid () || authority.at (r) != requirement.capability || (membership & requirement.capability.bit ()) != 0) {
						fail ("generic", "invalid, duplicate or nonlexical capability requirement");
					}
					membership |= requirement.capability.bit ();
				}
			}
		}
		foreach (var generic in program.generic_functions) {
			uint exact_elements = 0;
			foreach (var parameter in generic.type_parameters) {
				if (generic.element_obligations.contains (parameter.semantic_type)) {
					exact_elements++;
				}
			}
			if (exact_elements != generic.element_obligations.length) {
				fail ("generic", "element obligation references a foreign type parameter");
			}
			var counts = new int[generic.type_parameters.length];
			int last_parameter = -1;
			int last_source_offset = generic.span.start;
			foreach (var requirement in generic.capability_requirements) {
				if (requirement.span.file != generic.span.file || requirement.span.start < last_source_offset || requirement.span.end > generic.span.end) {
					fail ("generic", "capability requirement provenance is not in source order");
				}
				last_source_offset = requirement.span.start;
				var parameter = requirement.type_parameter;
				if (parameter == null || parameter.ordinal < 0 || parameter.ordinal >= counts.length || generic.type_parameters[parameter.ordinal] != parameter) {
					fail ("generic", "requirement references a foreign type parameter");
				}
				int index = parameter.ordinal;
				if (counts[index] >= parameter.capability_requirements.length || parameter.capability_requirements[counts[index]] != requirement || (last_parameter != index && counts[index] != 0)) {
					fail ("generic", "capability source ordering or canonical membership mismatch");
				}
				counts[index]++;
				last_parameter = index;
			}
			foreach (var parameter in generic.type_parameters) {
				if (counts[parameter.ordinal] != parameter.capability_requirements.length) {
					fail ("generic", "missing function capability requirement");
				}
			}
		}
		foreach (var function in program.functions) {
			if (function is CoreGenericFunction) {
				fail ("generic", "generic definition cannot occupy a concrete function slot");
			}
		}
		var cleanup_symbols = new HashTable<string, string> (str_hash, str_equal);
		var object_cleanups = new HashTable<CoreClass, CoreCleanupContract> (direct_hash, direct_equal);
		var heap_cleanups = new HashTable<CoreClass, CoreCleanupContract> (direct_hash, direct_equal);
		var buffer_cleanups = new HashTable<SliceType, bool> (direct_hash, direct_equal);
		var generic_cleanups = new HashTable<TypeParameterType, CoreCleanupContract> (direct_hash, direct_equal);
		var record_cleanups = new HashTable<CoreStruct, bool> (direct_hash, direct_equal);
		for (int c = 0; c < program.cleanups.length; c++) {
			var cleanup = program.cleanups[c];
			if (cleanup.record_type != null) {
				var record = cleanup.record_type;
				if (cleanup.ordinal != c || cleanups.contains (cleanup) || !program.structs.find (record) || record_cleanups.contains (record) || cleanup.is_object || cleanup.is_buffer || cleanup.closure_type != null || cleanup.shared_type != null || cleanup.external_symbol != "") {
					fail ("record responsibility", "requires one program-owned exact root record without scalar cleanup authority");
				}
				record_cleanups.insert (record, true);
				cleanups.insert (cleanup, cleanup);
				continue;
			}
			if (cleanup.closure_type != null) {
				if (cleanup.ordinal != c || cleanups.contains (cleanup) || cleanup.is_object || cleanup.is_buffer || cleanup.shared_type != null || !cleanup.closure_type.supported () || cleanup.closure_environment == null || cleanup.closure_environment.semantic_type != cleanup.closure_type.environment_type || cleanup.closure_environment.polymorphic || !program.classes.find (cleanup.closure_environment)) {
					fail ("closure cleanup", "requires exact closure signature and nonpolymorphic program-owned environment destructor authority");
				}
				cleanups.insert (cleanup, cleanup);
				continue;
			}
			if (cleanup.shared_type != null) {
				if (cleanup.ordinal != c || cleanups.contains (cleanup) || cleanup.is_object || cleanup.is_buffer || cleanup.shared_payload == null || cleanup.shared_payload.semantic_type != cleanup.shared_type.payload_type || !program.classes.find (cleanup.shared_payload) || cleanup.shared_type.payload_type.is_interface && !cleanup.shared_type.payload_type.intrinsically_shared || cleanup.shared_type.payload_type.intrinsically_shared && !cleanup.shared_type.is_weak) {
					fail ("shared cleanup", "requires exact strong/weak type and program-owned concrete payload destructor authority");
				}
				cleanups.insert (cleanup, cleanup);
				continue;
			}
			if (cleanup.is_buffer) {
				bool eligible = cleanup.buffer_shape.is_valid (element_fields);
				if (cleanup.is_symbolic_buffer) {
					var element = cleanup.buffer_type.element_type as TypeParameterType;
					var definition = element == null ? null : type_parameters.lookup (element) as CoreGenericFunction;
					eligible = !concrete_only && definition != null && definition.element_obligations.establishes (element, GenericElementRequirements.BUFFER) && cleanup.buffer_shape.base_type.is_void_pointer () && cleanup.buffer_shape.length_type.kind == TypeKind.INT;
				}
				if (cleanup.ordinal != c || cleanups.contains (cleanup) || buffer_cleanups.contains (cleanup.buffer_type) || cleanup.is_object || cleanup.type_parameter != null || cleanup.external_symbol != "" || !eligible) {
					fail ("buffer cleanup", "requires unique exact eligible SliceType and static native buffer deallocation");
				}
				buffer_cleanups.insert (cleanup.buffer_type, true);
				cleanups.insert (cleanup, cleanup);
				verify_type (cleanup.buffer_shape.base_type, true, "buffer base");
				verify_type (cleanup.buffer_shape.length_type, true, "buffer length");
				continue;
			}
			if (cleanup.type_parameter != null) {
				if (concrete_only || cleanup.ordinal != c || !ownable_parameter (cleanup.type_parameter) || !type_parameters.contains (cleanup.type_parameter) || generic_cleanups.contains (cleanup.type_parameter) || cleanup.is_object || cleanup.external_symbol != "") {
					fail ("ownership contract", "unresolved or invalid exact Ownable responsibility; must disappear before CFG");
				}
				generic_cleanups.insert (cleanup.type_parameter, cleanup);
				cleanups.insert (cleanup, cleanup);
				continue;
			}
			if (cleanup.is_object) {
				var object_class = cleanup.object_class;
				var authority = cleanup.is_heap_object ? heap_cleanups : object_cleanups;
				bool symbolic = !concrete_only && object_class != null && object_class.semantic_type.is_parameterized () && program.class_applications.find (object_class);
				bool declared = object_class != null && object_class.ordinal >= 0 && object_class.ordinal < program.classes.length && program.classes[object_class.ordinal] == object_class;
				if (cleanup.ordinal != c || cleanups.contains (cleanup) || (!symbolic && !declared) || authority.contains (object_class) || cleanup.external_symbol != "") {
					fail ("cleanup", "object responsibility requires unique exact program-owned class and native destructor authority");
				}
				authority.insert (object_class, cleanup);
				cleanups.insert (cleanup, cleanup);
				continue;
			}
			if (cleanup.ordinal != c || cleanups.contains (cleanup) || cleanup.external_symbol == "" || cleanup_symbols.contains (cleanup.external_symbol)) {
				fail ("cleanup", "cleanup identity, symbol and ordinal must be unique, nonempty and in declaration order");
			}
			cleanups.insert (cleanup, cleanup);
			cleanup_symbols.insert (cleanup.external_symbol, cleanup.external_symbol);
		}
		var names = new HashTable<string, string> (str_hash, str_equal);
		var foreign_roots = new GenericArray<Astra.Source.ForeignImportContract> ();
		foreach (var handle in program.handles) {
			if (handle.c_import != null) {
				foreign_roots.add (handle.c_import);
			}
		}
		if (!Astra.Source.ForeignImportContract.distinct (foreign_roots)) {
			fail ("foreign imports", "requires distinct nominal roots, prefixes and COM IIDs with exact declared parents");
		}
		for (int h = 0; h < program.handles.length; h++) {
			var handle = program.handles[h];
			if (handle.context_mode != "" && handle.semantic_type.context_cleanup != handle.cleanup.external_symbol) {
				fail ("allocator context", "context handle lost its exact backing-release contract");
			}
			if (handle.context_mode != handle.semantic_type.context_mode || handle.context_mode != "" && !AllocationPolicy.valid_context_mode (handle.context_mode)) {
				fail ("allocator context", "nominal handle lost its independently retained context lifetime/thread contract");
			}
			if (handle.c_import != null) {
				var root = handle.c_import;
				for (uint m = 0; m < root.api.member_count; m++) {
					int matches = 0;
					foreach (var candidate in program.functions) {
						if (candidate.name != root.api.native_origin + "." + root.native_name (m)) {
							continue;
						}
						var imported = candidate.body.statements.length > 0 ? candidate.body.statements[candidate.body.statements.length - 1] as CoreForeignReturn : null;
						if (imported == null || imported.binding.member_index != m || !imported.binding.root.equal (root)) {
							fail ("CImport", "declared member lost its exact typed adapter operation");
						}
						matches++;
					}
					if (matches != 1) {
						fail ("CImport", "requires exactly one adapter for each declared member");
					}
				}
			}

			if (!(handle.c_import == null ? Astra.Source.ComImportContract.matches (handle.com_import, handle.semantic_type.foreign_policy_identity, handle.name, handle.cleanup.external_symbol) : Astra.Source.ForeignImportContract.matches (handle.c_import, handle.semantic_type.foreign_policy_identity, handle.name, handle.cleanup.external_symbol))) {
				fail ("COMImport", "lost exact imported interface IID/lifetime/context identity");
			}
			if (handle.ordinal != h || handles.contains (handle.semantic_type) || names.contains (handle.name) || handle.name == "" || BuiltinTypes.is_builtin_name (handle.name) || !cleanups.contains (handle.cleanup)) {
				fail ("handle", "handle requires exact unique nominal identity, type name, declaration ordinal and program-owned cleanup");
			}
			handles.insert (handle.semantic_type, handle);
			names.insert (handle.name, handle.name);
		}
		foreach (var application in program.class_applications) {
			var type = application.semantic_type as ExactGenericClassType;
			var receiver = application.application_receiver;
			if (concrete_only || type == null || !type.is_parameterized () || receiver == null || receiver.instance_type != type || receiver.mode != ReceiverMode.LIVE || structs.contains (type)) {
				fail ("Class application", "requires its exact symbolic declaration and live receiver");
			}
			if (!AllocationPolicy.matches (application.allocation_policy, type.allocation_policy_identity) || !ConcurrencyPolicy.matches (application.concurrency_policy, type.concurrency_policy_identity)) {
				fail ("Class application policy", "lost its exact admitted declaration authority");
			}
			var key = application.generic_instance;
			if (key == null || key.definition != type.definition || key.instance_type != type || !key.arguments.matches (type.arguments) || type.definition.structure == null || application.fields.length != type.definition.structure.field_count) {
				fail ("Class application", "requires its exact nominal argument vector and complete declared fields");
			}
			structs.insert (type, application);
			receiver_types.insert (type, receiver);
			for (int f = 0; f < application.fields.length; f++) {
				var field = application.fields[f];
				if (field.containing_type != application || field.ordinal != f || type.definition.structure == null || f >= type.definition.structure.field_count) {
					fail ("Class application", "field requires its exact declared position");
				}
				var declared = type.definition.structure.field (f);
				if (field.name != declared.name || field.is_private != declared.private_field || !GenericClassDeclaredShape.type (declared.value_type, field.semantic_type, application.generic_instance, null, copy_fields)) {
					fail ("Class application", "field requires its exact declared type pattern");
				}
			}
		}
		foreach (var application in program.class_applications) {
			var shape = application.generic_instance.definition.structure;
			var member_names = new HashTable<string, string> (str_hash, str_equal);
			for (int m = 0; m < application.methods.length; m++) {
				var method = application.methods[m];
				var declared = shape.find_member (method.name);
				if (method.declaring_type != application || method.method_ordinal != m || member_names.contains (method.name) || declared == null || declared.kind != GenericMemberPatternKind.METHOD) {
					fail ("Class application", "method requires its exact declared member identity");
				}
				member_names.insert (method.name, method.name);
				verify_application_header (application, method, declared);
			}
			if (application.properties.length != shape.property_count) {
				fail ("Class application", "requires every declared property signature");
			}
			for (int p = 0; p < application.properties.length; p++) {
				var property = application.properties[p];
				var declared = shape.property (p);
				if (property.declaring_type != application || property.ordinal != p || property.name != declared.name || property.is_lazy != declared.lazy_property || property.getter == null || property.getter.property_member != property || (property.setter == null) != (declared.setter == null)) {
					fail ("Class application", "property requires its exact declared accessor signatures");
				}
				if (property.getter.return_type != property.semantic_type || !GenericClassDeclaredShape.type (declared.getter.result, property.semantic_type, application.generic_instance, null, copy_fields)) {
					fail ("Class application", "property requires its exact declared type and getter result");
				}
				verify_application_header (application, property.getter, declared.getter);
				if (property.setter != null) {
					if (property.setter.property_member != property) {
						fail ("Class application", "setter requires its exact property identity");
					}
					verify_application_header (application, property.setter, declared.setter);
				}
			}
			if (application.constructor != null) {
				verify_application_header (application, application.constructor, shape.find_member ("init"));
			}
			if (application.destructor != null) {
				verify_application_header (application, application.destructor, shape.find_member ("deinit"));
			}
		}
		var instances = program.native_instances ();
		foreach (var structure in instances) {
			string path = "native type " + structure.name;
			if (structure is CoreClass && (structure.ordinal < 0 || structure.ordinal >= program.classes.length || program.classes[structure.ordinal] != structure)) {
				fail (path, "class requires its exact declaration ordinal even without methods");
			}
			if ((structure is CoreStruct && !(structure.semantic_type is StructType)) || (structure is CoreClass && !(structure.semantic_type is ClassType))) {
				fail (path, "native declaration category must match its exact semantic type");
			}
			if (structs.contains (structure.semantic_type) || names.contains (structure.name) || structure.name == "" || structure.name != structure.semantic_type.display_name ()) {
				fail (path, "struct descriptor must have unique declared type identity and name");
			}
			if (BuiltinTypes.is_builtin_name (structure.name)) {
				fail (path, "struct descriptor conflicts with builtin type");
			}
			structs.insert (structure.semantic_type, structure);
			names.insert (structure.name, structure.name);
			if (structure is CoreStruct && structure.fields.length == 0) {
				fail (path, "struct must have at least one scalar field");
			}
		}
		int class_argument = 0;
		foreach (var owner in program.classes) {
			var key = owner.generic_instance;
			if (key == null) {
				continue;
			}
			for (int a = 0; a < key.arguments.length; a++) {
				if (class_argument >= program.class_type_arguments.length) {
					fail ("Class type arguments", "missing original nominal argument demand");
				}
				var argument = program.class_type_arguments[class_argument++];
				if (!argument.matches (key, (ClassType) owner.semantic_type, a)) {
					fail ("Class type arguments", "nominal argument differs from its original exact Class key");
				}
				verify_type (argument.semantic_type, true, "Class type argument", argument.semantic_type.is_struct_storage ());
			}
		}
		if (class_argument != program.class_type_arguments.length) {
			fail ("Class type arguments", "unexpected nominal argument demand");
		}
		// Structural transfer checks require the complete registered type graph.
		foreach (var owner in program.classes) {
			if (owner.concurrency_policy != null && owner.concurrency_policy.actor && !thread_capture_type (owner.semantic_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal), true)) {
				fail ("Actor policy", "receiver state must be transferable and contain no sender cycles");
			}
		}
		foreach (var function in program.all_definitions ()) {
			if (function.async_body != null) {
				foreach (var parameter in function.parameters) {
					if (!AsyncClosureCaptures.valid (parameter.semantic_type, parameter.pointer_contract, function.async_body.runtime.threaded)) {
						fail ("async frame", "Closure capture requires one owned non-actor handle and a single-threaded executor");
					}
					if (parameter.semantic_type is ClassType && (parameter.pointer_contract != PointerParameterContract.OWNED_TRANSFER || !parameter.heap_object)) {
						fail ("async frame", "Class capture requires one exact independently heap-owned parameter");
					}
					if (parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && !(parameter.semantic_type is SliceType)) {
						fail ("async frame", "borrowed captures require an exact sealed array suspension loan");
					}
				}
			}
			if (function.async_body != null && function.async_body.runtime.threaded) {
				foreach (var parameter in function.parameters) {
					if ((parameter.semantic_type is ClassType && (parameter.pointer_contract != PointerParameterContract.OWNED_TRANSFER || !parameter.heap_object)) || !thread_capture_type (parameter.semantic_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal))) {
						fail ("threaded frame", "parameter lost exact heap ownership or structural Send authority");
					}
				}
				if (function.return_type.kind != TypeKind.VOID && !thread_capture_type (function.return_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal))) {
					fail ("threaded frame", "result lost structural Send authority");
				}
			}
		}

		foreach (var structure in instances) {
			string path = "native type " + structure.name;
			var field_names = new HashTable<string, string> (str_hash, str_equal);
			for (int f = 0; f < structure.fields.length; f++) {
				var field = structure.fields[f];
				if (field.semantic_type is CallbackType) {
					fail (path, "call-scoped Callback cannot be stored in a field");
				}
				if (field.is_private && (!(structure is CoreClass) || ((CoreClass) structure).generic_instance != null && ((CoreClass) structure).generic_instance.definition.structure == null)) {
					fail (path, "private fields require an ordinary nongeneric native Class");
				}
				if (field.containing_type != structure || field.ordinal != f || field.name == "" || field_names.contains (field.name)) {
					fail (path, "field must have exact struct owner, unique name and declaration ordinal");
				}
				field_names.insert (field.name, field.name);
				if (field.semantic_type is VectorType && structure is CoreClass) {
					fail (path, "vector struct fields are unsupported");
				}
				if (field.semantic_type.is_typed_pointer () || (field.semantic_type is HandleType && field.owned_cleanup == null)) {
					fail (path, "typed-pointer struct fields are unsupported");
				}
				if (field.semantic_type is SliceType && field.owned_cleanup == null) {
					fail (path, "borrowed slice fields are unsupported");
				}
				if (field.semantic_type is ReceiverType) {
					fail (path, "receiver cannot be a field");
				}
				if (field.semantic_type is OwnerSlotsType) {
					verify_slots_field (field, path);
				} else if (!(field.semantic_type is StructType)) {
					verify_type (field.semantic_type, true, path + "/field " + field.name, field.semantic_type.is_struct_storage ());
				}
				if (field.owned_cleanup != null && (!(structure is CoreClass || structure is CoreStruct) || (!(field.semantic_type is StructType) && !(field.semantic_type is HandleType) && !(field.semantic_type is SliceType) && !(field.semantic_type is ClassType)) || !cleanups.contains (field.owned_cleanup) || !matches_cleanup (field.semantic_type, field.owned_cleanup))) {
					fail (path, "owned field requires an exact nominal Resource, native class and release contract");
				}
				if (field.semantic_type is ClassType && (field.owned_cleanup == null || !field.owned_cleanup.is_heap_object || field.owned_cleanup.object_class.polymorphic)) {
					fail (path, "owned child field requires exact nonpolymorphic heap cleanup authority");
				}
				if (field.text_snapshot && (!(structure is CoreClass) || !(field.semantic_type is StringType) || field.owned_cleanup != null)) {
					fail (path, "snapshot requires an exact readonly text class field without Resource cleanup");
				}
				if (field.owned_cleanup == null && !(field.semantic_type is OwnerSlotsType) && !field.text_snapshot && !NativeFieldTypes.supports (field.semantic_type, true)) {
					fail (path, "unsupported native field type");
				}
			}
		}
		foreach (var record in program.structs) {
			foreach (var field in record.fields) {
				if (!(field.semantic_type is ClassType)) {
					continue;
				}
				var child = structs.lookup (field.semantic_type) as CoreClass;
				if (child == null || child.polymorphic || field.owned_cleanup == null || !field.owned_cleanup.is_heap_object || field.owned_cleanup.object_class != child) {
					fail ("record Class field", "requires exact nonpolymorphic heap cleanup authority");
				}
			}
		}
		foreach (var owner in program.structs) {
			bool owns = record_field (owner.semantic_type) != null;
			if (owns && (owner.methods.length != 0 || owner.properties.length != 0)) {
				fail ("record ownership", "owning record members require their own value ownership contract");
			}
		}
		foreach (var owner in program.classes) {
			if (!OwnedChildComposition.acyclic (owner.semantic_type, child_edges)) {
				fail ("owned fields", "cyclic owned child composition");
			}
			int expected = 0;
			for (int f = owner.fields.length - 1; f >= 0; f--) {
				var field = owner.fields[f];
				if (field.owned_cleanup == null && !(field.semantic_type is OwnerSlotsType) && !field.text_snapshot) {
					continue;
				}
				if (owner.constructor == null || owner.destructor == null || expected >= owner.destructor.field_cleanups.length) {
					fail ("owned fields", "owned fields require a constructor and complete automatic destructor epilogue");
				}
				var action = owner.destructor.field_cleanups[expected++];
				if (action.field != field || action.cleanup != (field.slots_cleanup ?? field.owned_cleanup)) {
					fail ("owned fields", "automatic cleanup must retain exact field/release identity in reverse declaration order");
				}
			}
			int lazy_expected = 0;
			for (int p = owner.properties.length - 1; p >= 0; p--) {
				var property = owner.properties[p];
				if (!property.is_owned_lazy) {
					continue;
				}
				if (owner.destructor == null || lazy_expected >= owner.destructor.lazy_cleanups.length || owner.destructor.lazy_cleanups[lazy_expected++] != property) {
					fail ("owned lazy", "destructor lost exact reverse-order cache retirement plan");
				}
			}
			if (owner.destructor != null && owner.destructor.lazy_cleanups.length != lazy_expected) {
				fail ("owned lazy", "duplicate or unrelated cache retirement obligation");
			}
			if (owner.destructor != null && owner.destructor.field_cleanups.length != expected) {
				fail ("owned fields", "unexpected or duplicate automatic field cleanup");
			}
		}
		// All symbolic and physical owners are registered before resolving a
		// field's exact cleanup authority; declaration order is immaterial.
		foreach (var application in program.class_applications) {
			var shape = application.generic_instance.definition.structure;
			foreach (var field in application.fields) {
				var declared = shape.field (field.ordinal);
				bool owns = GenericClassDeclaredShape.owns_field (declared.owned_field, field.semantic_type, copy_fields) && !(field.semantic_type is OwnerSlotsType);
				if (owns != (field.owned_cleanup != null) || owns && (!cleanups.contains (field.owned_cleanup) || !matches_cleanup (field.semantic_type, field.owned_cleanup))) {
					fail ("Class application/" + field.name, "field requires its exact declared ownership responsibility");
				}
			}
		}
		foreach (var application in program.method_applications) {
			var owner = application.declaring_type as CoreClass;
			var request = application.generic_method_instance;
			if (concrete_only || owner == null || structs.lookup (owner.semantic_type) != owner || request == null || !request.valid_application (owner.generic_instance) || !owner.semantic_type.is_parameterized () && request.arguments.closed () || owner.methods.find (application)) {
				fail ("method application", "requires a nonphysical exact declared generic member binding");
			}
			CoreGenericFunction? scope = null;
			foreach (var generic in program.generic_functions) {
				if (generic.identity == application.application_scope) {
					scope = generic;
				}
			}
			if (scope == null) {
				fail ("method application", "requires its exact enclosing generic scope");
			}
			var saved_scope = active_generic;
			active_generic = scope;
			foreach (var argument in owner.generic_instance.arguments.copy_values ()) {
				verify_type (argument, true, "method application/owner argument", argument.is_struct_storage ());
			}
			foreach (var argument in request.arguments.copy_values ()) {
				verify_type (argument, true, "method application/method argument", argument.is_struct_storage ());
			}
			verify_type (application.return_type, application.return_type.kind != TypeKind.VOID, "method application/result", application.return_type.is_struct_storage ());
			foreach (var parameter in application.parameters) {
				verify_type (parameter.semantic_type, true, "method application/parameter", parameter.semantic_type.is_struct_storage ());
			}
			active_generic = saved_scope;
			var declared = owner.generic_instance.definition.structure.find_member (owner.generic_instance.definition.generic_method_name (request.member));
			verify_application_header (owner, application, declared);
		}
		var complete_layouts = new HashTable<CoreNativeInstance, CoreNativeInstance> (direct_hash, direct_equal);
		var active_layouts = new GenericArray<CoreNativeInstance> ();
		foreach (var structure in instances) {
			verify_layout (structure, complete_layouts, active_layouts);
		}
		foreach (var generic in program.generic_structs) {
			if (generic.name == "" || names.contains (generic.name) || BuiltinTypes.is_builtin_name (generic.name)) {
				fail ("generic struct", "definition conflicts in the nominal type namespace");
			}
			names.insert (generic.name, generic.name);
			active_generic = generic;
			var field_names = new HashTable<string, string> (str_hash, str_equal);
			for (int f = 0; f < generic.fields.length; f++) {
				var field = generic.fields[f];
				if (field.definition != generic || field.identity.definition != generic.identity || field.ordinal != f || field.name == "" || field_names.contains (field.name)) {
					fail ("generic struct", "field requires exact origin, unique name and declaration ordinal");
				}
				field_names.insert (field.name, field.name);
				verify_type (field.semantic_type, true, "generic struct " + generic.name + "/" + field.name, true);
				if (!(field.semantic_type is TypeParameterType) && !(field.semantic_type is CoreGenericStructApplicationType) && !NativeFieldTypes.supports (field.semantic_type, true)) {
					fail ("generic struct", "unsupported parameterized native field type");
				}
			}
		}
		active_generic = null;
		var struct_instance_identities = new GenericArray<GenericStructInstance> ();
		foreach (var structure in program.structs) {
			var record_type = structure.semantic_type as StructType;
			var owning_record = record_type == null ? null : record_type.owning_application;
			if (owning_record != null) {
				if (!(structure is CoreStruct) || !owning_record.valid (record_type, ((CoreStruct) structure).owning_arguments, copy_fields) || structure.fields.length != owning_record.definition.field_count) {
					fail ("owning record", "lost exact closed declared storage and argument authority");
				}
				foreach (var field in structure.fields) {
					if (!owning_record.field (field.ordinal, field.name, field.semantic_type, field.owned_cleanup != null, field.is_private, copy_fields)) {
						fail ("owning record field", "lost declared type, ownership or visibility");
					}
				}
			} else if (structure.owning_arguments.length != 0) {
				fail ("owning record", "argument demands require an exact owning declaration");
			}
			var instance = structure.generic_instance;
			if (instance == null) {
				continue;
			}
			if (!instance.has_canonical_key () || instance.state != GenericStructInstanceState.COMPLETE || instance.concrete_struct != structure || instance.ordinal != struct_instance_identities.length || structure.name != instance.symbol_name () || instance.requests == 0 || instance.requesters.length == 0 || instance.type_arguments.length == 0) {
				fail ("generic struct instance", "materialized struct requires complete exact identity, deterministic order and request provenance");
			}
			foreach (var argument in instance.type_arguments) {
				verify_type (argument, true, "generic struct instance/argument", argument.is_struct_storage ());
				if (!GenericArgumentTypes.supports (argument, copy_fields)) {
					fail ("generic struct instance", "instance key requires concrete GEN1_PLAIN_COPY identity");
				}
			}
			foreach (var prior in struct_instance_identities) {
				if (instance.matches (prior.origin, prior.type_arguments)) {
					fail ("generic struct instance", "duplicate exact instance key");
				}
				if (instance.origin.ordinal == prior.origin.ordinal && instance.origin != prior.origin) {
					fail ("generic struct instance", "origin ordinal must retain exact definition identity");
				}
			}
			foreach (var field in structure.fields) {
				if (field.generic_origin == null || field.generic_origin.definition != instance.origin || field.generic_origin.ordinal != field.ordinal || field.generic_origin.name != field.name) {
					fail ("generic struct instance", "concrete field lost immutable exact generic origin");
				}
			}
			struct_instance_identities.add (instance);
		}
		for (int st = 0; st < instances.length; st++) {
			var structure = instances[st];
			var member_names = new HashTable<string, string> (str_hash, str_equal);
			foreach (var field in structure.fields) {
				member_names.insert (field.name, field.name);
			}
			int previous_member = -1;
			for (int m = 0; m < structure.methods.length; m++) {
				var method = structure.methods[m];
				bool present = false;
				foreach (var function in program.functions) {
					if (function == method) {
						present = true;
					}
				}
				if (!present || structure.ordinal != ((structure is CoreClass) ? st - (int) program.structs.length : st) || method.declaring_type != structure || method.method_ordinal != m || method.member_ordinal <= previous_member || method.member_ordinal >= structure.fields.length + structure.methods.length + structure.properties.length + ((structure is CoreClass) ? ((CoreClass) structure).lifecycle_count : 0) || method.name == "" || member_names.contains (method.name) || receiver_owners.contains (method.receiver) || method.receiver.contract.mode != ReceiverMode.LIVE || method.receiver.contract.instance_type != structure.semantic_type) {
					fail ("methods", "method requires exact declaring struct, unique member name/ordinal and one implicit receiver");
				}
				var prior = receiver_types.lookup (structure.semantic_type);
				if (prior != null && prior != method.receiver.contract) {
					fail ("methods", "methods of one struct require the same exact receiver type contract");
				}
				receiver_types.insert (structure.semantic_type, method.receiver.contract);
				receiver_owners.insert (method.receiver, method);
				member_names.insert (method.name, method.name);
				previous_member = method.member_ordinal;
			}
			int previous_property_member = -1;
			for (int p = 0; p < structure.properties.length; p++) {
				var property = structure.properties[p];
				if (property.declaring_type != structure || property.ordinal != p || property.name == "" || member_names.contains (property.name) || property.member_ordinal <= previous_property_member || property.member_ordinal >= structure.fields.length + structure.methods.length + structure.properties.length + ((structure is CoreClass) ? ((CoreClass) structure).lifecycle_count : 0) || !(property.is_borrowed ? structure is CoreClass && (property.semantic_type is ClassType || property.semantic_type is HandleType || property.semantic_type.is_struct_storage () && record_field (property.semantic_type) != null) && (!property.is_lazy || property.is_owned_lazy) : PropertyValueTypes.supports (property.semantic_type, copy_fields) || property.getter != null && property.getter.result_contract == ResultOwnershipContract.OWNED_TRANSFER && structure is CoreClass && ForeignApiTypes.owned_property (((CoreClass) structure).foreign_export, property.member_ordinal)) || property.getter == null) {
					fail ("properties", "property requires exact owner, legal value type, unique member name/ordinal and getter");
				}
				if (property.is_owned_lazy) {
					var factory = property.factory;
					var returned = property.getter.body.statements.length == 1 ? property.getter.body.statements[0] as CoreReturn : null;
					var observe = returned == null ? null : returned.value as CoreLazyObserve;
					if (observe == null || observe.property_member != property || property.getter.locals.length != 0) {
						fail ("owned lazy", "public getter must contain only its exact receiver-bounded cache observation");
					}
					if (!property.is_lazy || !property.is_borrowed || !(property.semantic_type is ClassType) || property.setter != null || factory == null || !definitions.find (factory) || factory.declaring_type != structure || factory.return_type != property.semantic_type || factory.result_contract != ResultOwnershipContract.OWNED_TRANSFER || !factory.heap_result || factory.owned_cleanup == null || !factory.owned_cleanup.is_heap_object || factory.owned_cleanup.object_class.polymorphic || property.semantic_type is ExactGenericClassType && !GenericClassTypes.general (property.semantic_type) || factory.parameters.length != 0 || factory.throws_type != property.getter.throws_type || factory.dispatch_kind != ClassDispatchKind.DIRECT || property.getter.dispatch_kind != ClassDispatchKind.DIRECT) {
						fail ("owned lazy", "requires distinct exact owned factory and receiver-borrow observation channels");
					}
				} else if (property.factory != null) {
					fail ("owned lazy", "ordinary property cannot acquire an owned factory");
				}
				if (structure is CoreClass && (property.name == "init" || property.name == "deinit")) {
					fail ("properties", "class lifecycle names are reserved");
				}
				foreach (var method in structure.methods) {
					if (method.member_ordinal == property.member_ordinal) {
						fail ("properties", "property/member ordinals must be distinct");
					}
				}
				verify_type (property.semantic_type, true, "property/value-type", property.semantic_type.is_struct_storage ());
				member_names.insert (property.name, property.name);
				previous_property_member = property.member_ordinal;
				if (property.semantic_type is StringType && (!(structure is CoreClass) || property.setter != null)) {
					fail ("property", "receiver text requires a get-only native class property");
				}
				if (property.is_lazy && (!(structure is CoreClass) || property.setter != null || property.getter.dispatch_kind != ClassDispatchKind.DIRECT || (!property.is_owned_lazy && !PropertyValueTypes.supports_cache (property.semantic_type)))) {
					fail ("lazy property", "requires an exact nonvirtual get-only copied-value class property");
				}
				var accessors = new GenericArray<CorePropertyAccessor> ();
				accessors.add (property.getter);
				if (property.setter != null) {
					accessors.add (property.setter);
				}
				foreach (var accessor in accessors) {
					bool present = false;
					foreach (var function in program.functions) {
						if (function == accessor) {
							present = true;
						}
					}
					bool getter = accessor is CorePropertyGetter;
					if (getter && accessor.return_type is StringType) {
						verify_text_getter (accessor);
					}
					if (getter && property.is_borrowed && !property.is_owned_lazy) {
						verify_borrowed_getter (accessor);
					}
					if ((accessor.result_contract == ResultOwnershipContract.RECEIVER_BORROW) != (getter && property.is_borrowed)) {
						fail ("borrowed property", "receiver-borrow result requires its exact declared projection getter");
					}
					if (!present || accessor.property_member != property || (getter ? property.getter != accessor : property.setter != accessor) || receiver_owners.contains (accessor.receiver) || accessor.receiver.contract.mode != ReceiverMode.LIVE || accessor.receiver.contract.instance_type != structure.semantic_type || (accessor.owned_cleanup != null && !(getter && structure is CoreClass && ForeignApiTypes.owned_property (((CoreClass) structure).foreign_export, property.member_ordinal) && accessor.result_contract == ResultOwnershipContract.OWNED_TRANSFER)) || accessor.result_storage != null || accessor.parameters.length != (getter ? 0 : 1) || (getter ? accessor.return_type != property.semantic_type : accessor.return_type.kind != TypeKind.VOID)) {
						fail ("accessors", "accessor requires exact property identity, live receiver and plain getter/setter signature");
					}
					if (!getter && (accessor.parameters[0].semantic_type != property.semantic_type || accessor.parameters[0].pointer_contract != (property.is_borrowed ? PointerParameterContract.OWNED_TRANSFER : PointerParameterContract.UNMANAGED))) {
						fail ("accessors", "setter requires one exact plain property-value parameter");
					}
					var prior = receiver_types.lookup (structure.semantic_type);
					if (prior != null && prior != accessor.receiver.contract) {
						fail ("accessors", "accessor must share the exact native member receiver contract");
					}
					receiver_types.insert (structure.semantic_type, accessor.receiver.contract);
					receiver_owners.insert (accessor.receiver, accessor);
				}
			}
		}

		// Physical external-symbol uniqueness is validated by CABI.
		foreach (var owner in program.classes) {
			var lifecycle_members = new GenericArray<CoreLifecycle> ();
			if (owner.constructor != null) {
				lifecycle_members.add (owner.constructor);
			}
			if (owner.destructor != null) {
				lifecycle_members.add (owner.destructor);
			}
			foreach (var lifecycle in lifecycle_members) {
				bool present = false;
				foreach (var function in program.functions) {
					if (function == lifecycle) {
						present = true;
					}
				}
				bool initializing = lifecycle is CoreConstructor;
				if (!present || lifecycle.declaring_class != owner || lifecycle.receiver.contract.instance_type != owner.semantic_type || lifecycle.receiver.contract.mode != (initializing ? ReceiverMode.INITIALIZING : ReceiverMode.LIVE) || lifecycle.return_type.kind != TypeKind.VOID || lifecycle.owned_cleanup != null || (!initializing && lifecycle.parameters.length != 0) || lifecycle.name != (initializing ? "init" : "deinit") || lifecycle.member_ordinal < 0 || lifecycle.member_ordinal >= owner.fields.length + owner.methods.length + owner.properties.length + owner.lifecycle_count || receiver_owners.contains (lifecycle.receiver)) {
					fail ("lifecycle", "lifecycle requires exact class identity, receiver mode, member ordinal and void callable contract");
				}
				foreach (var method in owner.methods) {
					if (method.name == "init" || method.name == "deinit" || method.member_ordinal == lifecycle.member_ordinal) {
						fail ("lifecycle", "lifecycle names and member ordinals cannot collide with methods");
					}
				}
				foreach (var property in owner.properties) {
					if (property.member_ordinal == lifecycle.member_ordinal) {
						fail ("properties", "property and lifecycle member ordinals must be distinct");
					}
				}
				foreach (var field in owner.fields) {
					if (field.name == "init" || field.name == "deinit") {
						fail ("lifecycle", "lifecycle names cannot collide with fields");
					}
				}
				if (owner.constructor != null && owner.destructor != null && owner.constructor.member_ordinal == owner.destructor.member_ordinal) {
					fail ("lifecycle", "lifecycle member ordinals must be distinct");
				}
				var contracts = initializing ? initializing_types : receiver_types;
				var prior = contracts.lookup (owner.semantic_type);
				if (prior != null && prior != lifecycle.receiver.contract) {
					fail ("lifecycle", "receiver contract must have exact class and mode identity");
				}
				contracts.insert (owner.semantic_type, lifecycle.receiver.contract);
				receiver_owners.insert (lifecycle.receiver, lifecycle);
			}
		}
		for (int c = 0; c < program.c_functions.length; c++) {
			var imported = program.c_functions[c];
			string path = "C import #%d".printf (c);
			if (imported.return_type is ClosureHandleType || imported.return_type is SharedHandleType) {
				fail (path, "native lifetime carriers cannot be exposed as raw C results");
			}
			foreach (var carrier_type in imported.parameter_types) {
				if (carrier_type is ClosureHandleType || carrier_type is SharedHandleType) {
					fail (path, "native lifetime carriers cannot be exposed as raw C parameters");
				}
			}

			if (c_functions.contains (imported) || imported.ordinal != c) {
				fail (path, "C function identity/ordinal must be unique and in declaration order");
			}
			if (imported.abi != ForeignAbi.C || imported.external_symbol == "") {
				fail (path, "C import must have ABI C and a nonempty external symbol");
			}
			if (imported.metadata.owned_result != null || (imported.owned_cleanup != null && (!cleanups.contains (imported.owned_cleanup) || !imported.return_type.is_ownable_handle_type () || !matches_cleanup (imported.return_type, imported.owned_cleanup)))) {
				fail (path, "owned-result requires an exact program-owned cleanup and void* result; semantic ownership metadata must be normalized");
			}
			bool device_parameters = true;
			foreach (var type in imported.parameter_types) {
				device_parameters &= type.kind == TypeKind.INT;
			}
			if (!imported.metadata.device_signature (imported.return_type.kind == TypeKind.INT, imported.parameter_types.length, device_parameters)) {
				fail (path, "PC device policy lost its admitted operation or exact i32 signature");
			}
			if (!imported.metadata.text_abi.is_valid ()) {
				fail (path, "invalid C text ABI mode");
			}
			if (!imported.metadata.bool_policy_valid ()) {
				fail (path, "lost admitted C99 boolean policy");
			}
			if (!imported.metadata.import_policy_valid ()) {
				fail (path, "lost admitted foreign policy or GObject bridge/header identity");
			}
			if (!imported.metadata.record_abi.is_valid ()) {
				fail (path, "invalid C record ABI mode");
			}
			if (!imported.metadata.buffer_abi.is_valid ()) {
				fail (path, "invalid C buffer ABI mode");
			}
			if (imported.metadata.buffer_abi != Astra.Foreign.CBufferAbi.NONE && imported.return_type.is_nullable_pointer_value ()) {
				fail (path, "C byte buffer imports cannot return pointer-like values");
			}
			if (imported.metadata.record_abi != Astra.Foreign.CRecordAbi.NONE && imported.return_type.is_nullable_pointer_value ()) {
				fail (path, "C record imports cannot return pointer-like values or derived owners");
			}
			bool has_text = false;
			bool has_buffer = false;
			bool has_record = false;
			bool has_pointer = false;
			SemanticType[] com_types = null;
			PointerParameterContract[] com_contracts = null;
			foreach (var parameter in imported.parameters) {
				com_types += parameter.semantic_type;
				com_contracts += parameter.pointer_contract;
			}
			if (!ComImportTypes.valid (imported.metadata, imported.return_type, com_types, com_contracts, imported.owned_cleanup == null ? "" : imported.owned_cleanup.external_symbol)) {
				fail (path, "COMImport lost its nominal IID, signature, ownership or context contract");
			}
			if (!imported.metadata.pointer_abi.is_valid () || imported.metadata.pointer_abi != Astra.Foreign.CPointerAbi.NONE && (imported.metadata.record_abi != Astra.Foreign.CRecordAbi.NONE || imported.metadata.text_abi != Astra.Foreign.CTextAbi.NONE || imported.metadata.buffer_abi != Astra.Foreign.CBufferAbi.NONE || imported.metadata.callback != null || !imported.metadata.com_owner_result && (imported.owned_cleanup != null || imported.return_type.is_nullable_pointer_value ()))) {
				fail (path, "invalid i32-noescape C pointer transport");
			}
			bool value_record = imported.metadata.record_abi == Astra.Foreign.CRecordAbi.VALUE_LP64;
			if (value_record && (imported.parameters.length > 2 || imported.metadata.callback != null || imported.metadata.text_abi != Astra.Foreign.CTextAbi.NONE || imported.metadata.buffer_abi != Astra.Foreign.CBufferAbi.NONE)) {
				fail (path, "value-lp64 requires at most two parameters and no alternate transport groups");
			}
			if (value_record && imported.return_type.is_struct_storage ()) {
				if (!CPlainRecordTypes.value (imported.return_type, copy_fields)) {
					fail (path, "unsupported C value record result");
				}
				has_record = true;
			}
			c_functions.insert (imported, imported);
			if (imported.return_type is StringType || imported.return_type is SliceType) {
				fail (path, "C slice results are unsupported");
			}
			verify_type (imported.return_type, false, path + "/result", value_record && imported.return_type.is_struct_storage ());
			if (!(value_record && imported.return_type.is_struct_storage ()) && !(imported.metadata.bool_abi == Astra.Foreign.CBoolAbi.C99 && imported.return_type.kind == TypeKind.BOOL) && imported.return_type.kind != TypeKind.INT && imported.return_type.kind != TypeKind.I64 && imported.return_type.kind != TypeKind.U64 && imported.return_type.kind != TypeKind.ISIZE && imported.return_type.kind != TypeKind.USIZE && !(imported.return_type is F64Type) && !(imported.return_type is F32Type) && imported.return_type.kind != TypeKind.VOID && !imported.return_type.is_ownable_handle_type ()) {
				fail (path, "C result must be int, void* or void; foreign bool is unsupported");
			}
			if (imported.parameters.length != imported.parameter_types.length) {
				fail (path, "C parameter metadata count must match semantic types");
			}
			for (int p = 0; p < imported.parameters.length; p++) {
				var parameter = imported.parameters[p];
				if (parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER) {
					fail (path, "C ownership parameter boundaries are unsupported");
				}
				verify_parameter_contract (parameter, path);
				if (value_record && parameter.semantic_type.is_struct_storage ()) {
					if (parameter.pointer_contract != PointerParameterContract.UNMANAGED || !CPlainRecordTypes.value (parameter.semantic_type, copy_fields)) {
						fail (path, "unsupported C value record parameter");
					}
					has_record = true;
				}
				if (CPlainRecordTypes.i32_pointer (parameter.semantic_type)) {
					if (imported.metadata.pointer_abi != Astra.Foreign.CPointerAbi.I32_NOESCAPE || parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
						fail (path, "C int pointer requires explicit i32-noescape borrowed int*");
					}
					has_pointer = true;
				} else if (parameter.semantic_type is TypedPointerType) {
					if (imported.metadata.record_abi != Astra.Foreign.CRecordAbi.NATURAL_LP64 || parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || !(CPlainRecordTypes.pointer (parameter.semantic_type, copy_fields) || CPlainRecordTypes.i32_pointer (parameter.semantic_type))) {
						fail (path, "C record parameter requires explicit natural-lp64 borrowed scalar POD Struct*");
					}
					has_record = true;
				}
				if (parameter.semantic_type is SliceType) {
					var slice = (SliceType) parameter.semantic_type;
					if (!(slice.element_type is IntegerType) || slice.element_type.kind != TypeKind.U8 || parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || imported.metadata.buffer_abi != Astra.Foreign.CBufferAbi.U8_I32) {
						fail (path, "C buffer parameter requires exact borrowed u8[] and explicit u8-i32 metadata");
					}
				}
				if (parameter.ordinal != p || parameter.semantic_type != imported.parameter_types[p]) {
					fail (path, "C parameter identity/order/type metadata mismatch");
				}
			}
			foreach (var parameter_type in imported.parameter_types) {
				if (parameter_type is StringType) {
					has_text = true;
					if (imported.metadata.text_abi != Astra.Foreign.CTextAbi.UTF8_I32) {
						fail (path, "C string parameter requires explicit utf8-i32 metadata");
					}
				} else if (parameter_type is SliceType) {
					has_buffer = true;
				}
				verify_type (parameter_type, true, path + "/parameter", value_record && parameter_type.is_struct_storage ());
				if (!(value_record && parameter_type.is_struct_storage ()) && !(imported.metadata.bool_abi == Astra.Foreign.CBoolAbi.C99 && parameter_type.kind == TypeKind.BOOL) && parameter_type.kind != TypeKind.INT && parameter_type.kind != TypeKind.I64 && parameter_type.kind != TypeKind.U64 && parameter_type.kind != TypeKind.ISIZE && parameter_type.kind != TypeKind.USIZE && !(parameter_type is F64Type) && !(parameter_type is F32Type) && !(parameter_type is StringType) && !(parameter_type is SliceType) && !parameter_type.is_ownable_handle_type () && !(parameter_type is TypedPointerType && (CPlainRecordTypes.pointer (parameter_type, copy_fields) || CPlainRecordTypes.i32_pointer (parameter_type)))) {
					fail (path, "C parameters must be int or void*; foreign bool is unsupported");
				}
			}
			bool has_bool = imported.return_type.kind == TypeKind.BOOL;
			foreach (var type in imported.parameter_types) {
				has_bool |= type.kind == TypeKind.BOOL;
			}
			if (!imported.metadata.bool_signature_valid (has_bool) || imported.metadata.bool_abi == Astra.Foreign.CBoolAbi.C99 && imported.owned_cleanup != null) {
				fail (path, "C99 boolean profile requires copied bool channels without alternate transports");
			}
			if (has_text != (imported.metadata.text_abi == Astra.Foreign.CTextAbi.UTF8_I32)) {
				fail (path, "C text ABI mode requires string parameters");
			}
			if (has_buffer != (imported.metadata.buffer_abi == Astra.Foreign.CBufferAbi.U8_I32)) {
				fail (path, "C buffer ABI mode requires borrowed u8[] parameters");
			}
			if (has_pointer != (imported.metadata.pointer_abi == Astra.Foreign.CPointerAbi.I32_NOESCAPE)) {
				fail (path, "C pointer ABI mode requires borrowed int* parameters");
			}
			if (has_record != (imported.metadata.record_abi != Astra.Foreign.CRecordAbi.NONE)) {
				fail (path, "C record ABI mode requires borrowed scalar POD Struct* parameters");
			}
			if (!imported.metadata.callback_abi.is_valid () || (imported.metadata.callback != null) != (imported.metadata.callback_abi == Astra.Foreign.CCallbackAbi.I32_CONTEXT_I32_SYNC)) {
				fail (path, "C callback requires exact synchronous nonretaining mode and target name");
			}
			if (imported.metadata.callback != null) {
				CoreFunction? callback = null;
				foreach (var candidate in program.functions) {
					if (candidate.name == imported.metadata.callback) {
						if (callback != null) {
							fail (path, "C callback target identity is ambiguous");
						}
						callback = candidate;
					}
				}
				if (!has_record || imported.parameters.length != 2 || imported.return_type.kind != TypeKind.INT || !imported.parameters[0].semantic_type.is_struct_pointer () || imported.parameters[1].semantic_type.kind != TypeKind.INT || imported.parameters[1].pointer_contract != PointerParameterContract.UNMANAGED || callback == null || callback is CoreGenericFunction || callback.implicit_receiver != null || callback.throws_type != null || callback.async_body != null || callback.return_type.kind != TypeKind.INT || callback.parameters.length != 2 || callback.parameters[0].semantic_type != imported.parameters[0].semantic_type || callback.parameters[0].pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || callback.parameters[1].semantic_type.kind != TypeKind.INT || callback.parameters[1].pointer_contract != PointerParameterContract.UNMANAGED) {
					fail (path, "C callback requires exact nonthrowing native I32(borrowed POD*, I32) target");
				}
			}
		}
		var instance_identities = new GenericArray<GenericFunctionInstance> ();
		foreach (var function in program.functions) {
			var instance = function.generic_instance;
			if (instance == null) {
				continue;
			}
			if (!instance.has_canonical_key () || instance.state != GenericInstanceState.COMPLETE || instance.ordinal != instance_identities.length || function.name != instance.symbol_name () || instance.requests == 0 || instance.callers.length == 0 || instance.type_arguments.length == 0) {
				fail ("generic instance", "concrete instance requires completed canonical identity, deterministic ordinal and request provenance");
			}
			if (!instance.has_storage_domain (function)) {
				fail ("generic instance", "canonical consuming storage domain must match the exact specialized parameters");
			}
			foreach (var type in instance.type_arguments) {
				verify_type (type, true, "generic instance/type-argument", type.is_struct_storage ());
				if (!GenericArgumentTypes.supports (type, copy_fields) && !GenericCapabilityAuthority.satisfies (type, GenericCapabilityIdentity.OWNABLE)) {
					fail ("generic instance", "instance arguments must be concrete plain-copy or Ownable identities");
				}
			}
			foreach (var prior in instance_identities) {
				if (instance.matches (prior.origin, prior.type_arguments, -1, prior.storage)) {
					fail ("generic instance", "duplicate canonical instance key");
				}
				if (instance.origin.ordinal == prior.origin.ordinal && instance.origin != prior.origin) {
					fail ("generic instance", "definition ordinal must retain exact origin identity");
				}
			}
			instance_identities.add (instance);
		}
		foreach (var definition in program.enums) {
			try {
				if (concrete_only) {
					EnumValueAuthority.verify (definition, (type) => enum_definitions.lookup (type), copy_fields, null, null, valid_enum_scalar_owner);
				} else {
					EnumValueAuthority.verify (definition, (type) => enum_definitions.lookup (type), copy_fields, definition.semantic_type.declares_copy, definition.semantic_type.declares_element, valid_enum_scalar_owner);
				}
			} catch (EnumContractError error) {
				fail ("enum", error.message);
			}
		}
		// Validate all declarations first, including ownership across functions.
		for (int i = 0; i < definitions.length; i++) {
			var function = definitions[i];
			active_generic = function as CoreGenericFunction;
			string path = "function #%d".printf (i);
			verify_native_declaration (function, path);
			int generic_borrows = 0;
			foreach (var parameter in function.parameters) {
				if (parameter.semantic_type is TypeParameterType && parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE) {
					generic_borrows++;
				}
			}
			if (generic_borrows != 0) {
				if (generic_borrows != 1 || active_generic == null || function.async_body != null || function.throws_type != null || function.owned_cleanup != null || (function.return_type.kind != TypeKind.VOID && !GenericBorrowTypes.scalar (function.return_type))) {
					fail (path, "generic borrowing requires one borrowed T, synchronous nonthrowing native helpers and a copied scalar or void result");
				}
				foreach (var parameter in function.parameters) {
					if (parameter.semantic_type is TypeParameterType && parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE) {
						continue;
					}
					if (parameter.pointer_contract != PointerParameterContract.UNMANAGED || !(GenericBorrowTypes.scalar (parameter.semantic_type) || parameter.semantic_type is FunctionValueType)) {
						fail (path, "generic borrow helpers permit only copied scalar adjacent parameters");
					}
				}
			}
			if (functions.contains (function)) {
				fail (path, "function identity occurs more than once");
			}
			functions.insert (function, function);
			if (function.implicit_receiver != null && receiver_owners.lookup (function.implicit_receiver) != function) {
				fail (path, "method is absent from its exact declaring struct member namespace");
			}
			if (function.heap_result) {
				if (!(function.return_type is ClassType) || function.owned_cleanup == null || !function.owned_cleanup.is_heap_object || function.result_storage != null) {
					fail (path, "heap-origin result requires exact heap cleanup and no lexical result storage");
				}
			} else if (function.return_type is ClassType && function.result_contract != ResultOwnershipContract.RECEIVER_BORROW) {
				var input = function.result_storage;
				if (function.owned_cleanup == null || input == null || input.semantic_type != function.return_type || input.object_class == null || structs.lookup (input.semantic_type) != input.object_class || result_inputs.contains (input)) {
					fail (path, "owned ClassType result requires exact unique caller-provided result storage and cleanup contract");
				}
				result_inputs.insert (input, function);
			} else if (function.result_storage != null) {
				fail (path, "only owned ClassType results have result storage");
			}
			if (function.result_contract == ResultOwnershipContract.RECEIVER_BORROW && (!(function is CorePropertyGetter) || !((CorePropertyGetter) function).property_member.is_borrowed || function.owned_cleanup != null || function.result_storage != null || function.heap_result)) {
				fail (path, "receiver borrow requires the exact nonowning property getter");
			}
			if (function.return_type is ReceiverType) {
				fail (path, "receiver cannot be a function result");
			}
			if (ownable_parameter (function.return_type) && function.owned_cleanup == null) {
				fail (path, "plain Ownable T result transport is unavailable");
			}
			if (function.owned_cleanup != null && (!(function.return_type is HandleType || function.return_type is ClassType || function.return_type is SliceType || ownable_parameter (function.return_type)) || !cleanups.contains (function.owned_cleanup) || !matches_cleanup (function.return_type, function.owned_cleanup))) {
				fail (path, "owned native result requires exact nominal handle type and its cleanup contract");
			}
			if (function.return_type is SliceType && (function.owned_cleanup == null || !function.owned_cleanup.is_buffer)) {
				fail (path, "native slice results require unsupported lifetime relationships");
			}
			verify_struct_contract (function.return_type, function.struct_result_contract, path + "/return-type", function.result_contract == ResultOwnershipContract.RECEIVER_BORROW);
			if (function.return_type is CallbackType) {
				fail ("callback result", "call-scoped Callback cannot be returned");
			}
			verify_type (function.return_type, false, path + "/return-type", function.struct_result_contract != null);
			if (function.return_type.is_typed_pointer ()) {
				fail (path, "typed-pointer function results are unsupported in TPTR-1");
			}
			for (int j = 0; j < function.parameters.length; j++) {
				var parameter = function.parameters[j];
				string parameter_path = path + "/parameter #%d".printf (j);
				if (owners.contains (parameter)) {
					fail (parameter_path, "parameter identity occurs in more than one declaration slot");
				}
				if (parameter.ordinal != j) {
					fail (parameter_path, "expected ordinal %d, found %d".printf (j, parameter.ordinal));
				}
				verify_struct_contract (parameter.semantic_type, parameter.struct_value_contract, parameter_path, borrowed_record_parameter (parameter));
				verify_type (parameter.semantic_type, true, parameter_path, parameter.struct_value_contract != null);
				verify_parameter_contract (parameter, parameter_path);
				owners.insert (parameter, function);
			}
			for (int j = 0; j < function.locals.length; j++) {
				var local = function.locals[j];
				if (local.semantic_type is CallbackType) {
					fail ("callback storage", "call-scoped Callback cannot be stored in a local");
				}
				if (ownable_parameter (local.semantic_type)) {
					bool owns_slot = false;
					foreach (var owner in function.owned_locals) {
						owns_slot |= owner.place == local;
					}
					if (!owns_slot || (local.incoming_parameter != null && local.incoming_parameter.pointer_contract != PointerParameterContract.OWNED_TRANSFER)) {
						fail (path, "generic T local requires an explicit owned slot and exact acquisition");
					}
				}
				if (local.semantic_type is ReceiverType) {
					fail (path, "receiver cannot be a mutable local");
				}
				string local_path = path + "/local #%d".printf (j);
				if (local_owners.contains (local)) {
					fail (local_path, "local identity occurs in more than one declaration slot");
				}
				if (local.ordinal != j) {
					fail (local_path, "expected ordinal %d, found %d".printf (j, local.ordinal));
				}
				if (local.address_taken && !local.semantic_type.is_typed_data_pointee ()) {
					fail (local_path, "only supported scalar or aggregate locals may be address-taken");
				}
				if (local.semantic_type.kind == TypeKind.STRUCT) {
					if (!structs.contains (local.semantic_type)) {
						fail (local_path, "aggregate local must have a program-owned struct descriptor");
					}
				} else {
					if (local.semantic_type is ArrayType) {
						verify_array_type ((ArrayType) local.semantic_type, local_path);
					} else {
						verify_type (local.semantic_type, true, local_path, true);
					}
				}
				if (local.incoming_parameter != null && local.incoming_parameter.struct_value_contract != null && (owners.lookup (local.incoming_parameter) != function || local.semantic_type != local.incoming_parameter.semantic_type || local.address_taken)) {
					fail (local_path, "struct parameter requires exact read-only local storage without an address");
				}
				local_owners.insert (local, function);
			}
			for (int o = 0; o < function.object_storage.length; o++) {
				var storage = function.object_storage[o];
				if (storage.ordinal != o || storage.region_ordinal < 0 || (!storage.result_candidate && storage.destructor != null && storage.cleanup_rank < 0) || object_owners.contains (storage) || storage.object_class == null || structs.lookup (storage.semantic_type) != storage.object_class || storage.scope == null) {
					fail (path, "object storage requires exact class, lexical scope and unique function identity");
				}
				if (storage.fallible) {
					var owner = storage.object_class;
					if (!storage.heap_allocated || storage.result_candidate || owner.allocation_policy == null || owner.constructor == null || function.async_body != null) {
						fail (path, "fallible construction requires fresh synchronous policy-owned storage and exact constructor");
					}
					foreach (var parameter in owner.constructor.parameters) {
						bool scalar = (parameter.semantic_type is IntegerType || parameter.semantic_type is FloatingType || parameter.semantic_type.kind == TypeKind.BOOL) && parameter.pointer_contract == PointerParameterContract.UNMANAGED;
						bool input = (parameter.semantic_type is ClassType || parameter.semantic_type is HandleType || parameter.semantic_type is SliceType) && parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER;
						bool record = parameter.struct_value_contract != null && parameter.struct_value_contract.mode != StructValueMode.BORROW_VALUE;
						if (!scalar && !input && !record) {
							fail (path, "fallible construction requires copied values or exact owning input contracts");
						}
					}
				}
				object_owners.insert (storage, function);
			}
			int projection_index = 0;
			foreach (var local in function.locals) {
				if (local.semantic_type.kind != TypeKind.STRUCT) {
					continue;
				}
				verify_projections (local, function, ref projection_index, path);
			}
			if (projection_index != function.field_places.length) {
				fail (path, "unexpected or duplicate field projection");
			}
		}
		for (int e = 0; e < program.c_exports.length; e++) {
			var exported = program.c_exports[e];
			string path = "C export #%d".printf (e);
			var target = exported.target;
			if (target != null && target.implicit_receiver != null) {
				fail (path, "methods are internal native members and cannot be C exports");
			}
			if (target == null || !functions.contains (target)) {
				fail (path, "C export target must be a live native function owned by this program");
			}
			if (exported.ordinal != e || exported.abi != ForeignAbi.C) {
				fail (path, "C export must have ABI C and an ordinal in declaration order");
			}
			if ((exported.record_abi != Astra.Foreign.CRecordAbi.NONE && exported.record_abi != Astra.Foreign.CRecordAbi.VALUE_LP64) || (exported.record_abi == Astra.Foreign.CRecordAbi.VALUE_LP64 && target.parameters.length > 2)) {
				fail (path, "invalid explicit C value record export authority");
			}
			bool has_bool = target.return_type.kind == TypeKind.BOOL;
			foreach (var parameter in target.parameters) {
				has_bool |= parameter.semantic_type.kind == TypeKind.BOOL;
			}
			if (!exported.bool_policy_valid () || has_bool != (exported.bool_abi == Astra.Foreign.CBoolAbi.C99) || exported.bool_abi == Astra.Foreign.CBoolAbi.C99 && exported.record_abi != Astra.Foreign.CRecordAbi.NONE) {
				fail (path, "C export lost its admitted C99 bool channels");
			}
			bool has_value_record = target.return_type.is_struct_storage ();
			foreach (var parameter in target.parameters) {
				if (parameter.semantic_type.is_struct_storage ()) {
					has_value_record = true;
				}
			}
			if (has_value_record != (exported.record_abi == Astra.Foreign.CRecordAbi.VALUE_LP64)) {
				fail (path, "C export record groups require exact explicit value-lp64 authority");
			}
			if (exported.external_symbol == "") {
				fail (path, "external C symbols must be nonempty");
			}
			if (!(exported.record_abi == Astra.Foreign.CRecordAbi.VALUE_LP64 && CPlainRecordTypes.value (target.return_type, copy_fields)) && !(exported.bool_abi == Astra.Foreign.CBoolAbi.C99 && target.return_type.kind == TypeKind.BOOL) && target.return_type.kind != TypeKind.INT && target.return_type.kind != TypeKind.I64 && target.return_type.kind != TypeKind.U64 && target.return_type.kind != TypeKind.ISIZE && target.return_type.kind != TypeKind.USIZE && !(target.return_type is F64Type) && !(target.return_type is F32Type) && target.return_type.kind != TypeKind.VOID && !target.return_type.is_void_pointer ()) {
				fail (path, "C export result must be int, void* or void; foreign bool is unsupported");
			}
			foreach (var parameter in target.parameters) {
				if (parameter.pointer_contract != PointerParameterContract.UNMANAGED) {
					fail (path, "C export borrowed parameters are unsupported");
				}
				if (!(exported.record_abi == Astra.Foreign.CRecordAbi.VALUE_LP64 && CPlainRecordTypes.value (parameter.semantic_type, copy_fields)) && !(exported.bool_abi == Astra.Foreign.CBoolAbi.C99 && parameter.semantic_type.kind == TypeKind.BOOL) && parameter.semantic_type.kind != TypeKind.INT && parameter.semantic_type.kind != TypeKind.I64 && parameter.semantic_type.kind != TypeKind.U64 && parameter.semantic_type.kind != TypeKind.ISIZE && parameter.semantic_type.kind != TypeKind.USIZE && !(parameter.semantic_type is F64Type) && !(parameter.semantic_type is F32Type) && !parameter.semantic_type.is_void_pointer ()) {
					fail (path, "C export parameters must be int or void*; foreign bool is unsupported");
				}
			}
		}
		for (int i = 0; i < definitions.length; i++) {
			var function = definitions[i];
			active_generic = function as CoreGenericFunction;
			if (function.native_declaration != null) {
				if (function.body.statements.length != 0 || function.locals.length != 0 || function.owned_locals.length != 0 || function.object_storage.length != 0 || function.field_places.length != 0) {
					fail ("native declaration", "imported callable cannot retain executable statements or local storage");
				}
				continue;
			}
			foreach (var owner in function.owned_locals) {
				if (owned_places.contains (owner.place) || local_owners.lookup (owner.place) != function || (!owner.place.semantic_type.is_ownable_handle_type () && !(owner.place.semantic_type is ClassType) && !(owner.place.semantic_type is SliceType) && !ownable_parameter (owner.place.semantic_type) && record_field (owner.place.semantic_type) == null) || (!owner.place.is_promotable () && !(record_field (owner.place.semantic_type) != null && !owner.place.address_taken)) || !cleanups.contains (owner.cleanup) || !matches_cleanup (owner.place.semantic_type, owner.cleanup) || owner.scope == null) {
					fail ("owned-local", "owner requires unique scalar void* local, exact cleanup and lexical scope");
				}
				if (owner.cleanup.is_object && (owner.place.incoming_parameter == null ? owner.object_storage != null && (!owner.object_storage.transferable || owner.object_storage.result_candidate || owner.object_storage.semantic_type != owner.place.semantic_type) : owner.object_storage != null)) {
					fail ("owned-local", "object owner requires fresh exact storage or an incoming owned parameter");
				}
				owned_places.insert (owner.place, owner);
			}

			foreach (var owner in function.owned_locals) {
				if (record_field (owner.place.semantic_type) == null) {
					if (owner.record_fields.length != 0) {
						fail ("record ownership", "nonrecord cannot carry field obligations");
					}
					continue;
				}
				var seen = new HashTable<string, bool> (str_hash, str_equal);
				int count = 0;
				try {
					foreach (var path in StructLeafOrder.enumerate_storage (owner.place.semantic_type, copy_fields)) {
						var leaf = record_leaf (owner.place.semantic_type, path);
						if (leaf != null && leaf.owned_cleanup != null) {
							count++;
						}
					}
				} catch (StructLeafError error) {
					fail ("record ownership", error.message);
				}
				foreach (var field in owner.record_fields) {
					var path = field.storage_path ();
					if (field.root_local () != owner.place || field.field.owned_cleanup == null || record_leaf (owner.place.semantic_type, path) != field.field
					    || !function.field_places.find (field) || seen.contains (path.spelling ())) {
						fail ("record ownership", "field obligation requires exact unique owning projection path");
					}
					seen.insert (path.spelling (), true);
				}
				if (count != owner.record_fields.length) {
					fail ("record ownership", "record plan must cover every owned field exactly once");
				}
			}
			foreach (var local in function.locals) {
				bool borrowed_parameter = local.incoming_parameter != null && borrowed_record_parameter (local.incoming_parameter);
				if (record_field (local.semantic_type) != null && (borrowed_parameter && function.async_body != null || (borrowed_parameter ? owned_places.contains (local) : !owned_places.contains (local) || local.incoming_parameter != null && (local.incoming_parameter.struct_value_contract == null || local.incoming_parameter.struct_value_contract.mode != StructValueMode.MOVE_VALUE)))) {
					fail ("record ownership", "record local requires exact ownership or synchronous borrowed parameter authority");
				}
			}
			int parameter_rank = 0;
			foreach (var parameter in function.parameters) {
				if (parameter.pointer_contract != PointerParameterContract.OWNED_TRANSFER) {
					continue;
				}
				if (parameter_rank >= function.owned_locals.length || parameter_rank >= function.body.statements.length) {
					fail ("owned-parameter", "missing root parameter slot");
				}
				var owner = function.owned_locals[parameter_rank];
				var acquire = function.body.statements[parameter_rank] as CoreAcquireParameter;
				if (owner.place.incoming_parameter != parameter || owner.scope != function.body || acquire == null || acquire.acquisition != owner) {
					fail ("owned-parameter", "parameter slots must initialize at entry in declaration order before root locals");
				}
				parameter_rank++;
			}
			for (int rank = parameter_rank; rank < function.owned_locals.length; rank++) {
				var parameter = function.owned_locals[rank].place.incoming_parameter;
				if (parameter != null && (parameter.struct_value_contract == null || parameter.struct_value_contract.mode != StructValueMode.MOVE_VALUE)) {
					fail ("owned-parameter", "duplicate parameter slot or invalid cleanup rank");
				}
			}
			int struct_rank = parameter_rank;
			foreach (var parameter in function.parameters) {
				if (parameter.struct_value_contract == null) {
					continue;
				}
				if (struct_rank >= function.body.statements.length) {
					fail ("struct-parameter", "missing entry acquisition");
				}
				var acquisition = function.body.statements[struct_rank++] as CoreAcquireStructParameter;
				if (acquisition == null || acquisition.parameter != parameter || acquisition.destination.incoming_parameter != parameter) {
					fail ("struct-parameter", "struct parameters must acquire all leaves before body execution in declaration order");
				}
				int slots = 0;
				foreach (var local in function.locals) {
					if (local.incoming_parameter == parameter) {
						slots++;
					}
				}
				if (slots != 1) {
					fail ("struct-parameter", "each struct parameter requires exactly one independent local");
				}
			}
			initialized.remove_all ();
			next_loop_ordinal = 0;
			field_state = (function is CoreConstructor) ? new FieldInitializationState ((int) ((CoreConstructor) function).declaring_class.fields.length + (((CoreConstructor) function).declaring_class.parent_class == null ? 0 : 1)) : null;
			bool owning_enums = false;
			foreach (var definition in program.enums) {
				if (EnumValueAuthority.owns (definition, (type) => enum_definitions.lookup (type))) {
					owning_enums = true;
				}
			}
			bool owning_records = false;
			foreach (var owner in function.owned_locals) {
				owning_records |= owner.record_fields.length != 0;
			}
			generic_local_transfers.remove_all ();
			generic_local_acquisitions.remove_all ();
			ownership_function = function;
			generic_owner_flow = active_generic != null || owning_enums || function.generic_instance != null || owning_records ? new GenericOwnershipFlow (function.span, owning_records ? "record field ownership checking" : "generic ownership checking") : contains_buffer_exchange (function.body) ? new GenericOwnershipFlow (function.span, "owned buffer exchange checking") : null;
			verify_block (function.body, function, "function #%d".printf (i));
			foreach (var owner in function.owned_locals) {
				if ((ownable_parameter (owner.place.semantic_type) || function.generic_instance != null) && owner.object_storage == null && !initialized.contains (owner.place)) {
					fail ("generic local", "owner requires one exact entry or local acquisition");
				}
				if (ownable_parameter (owner.place.semantic_type) && owner.place.incoming_parameter == null && !generic_local_owner (owner)) {
					fail ("generic local", "requires its exact local transfer or owning acquisition");
				}
			}
			if (function.generic_instance != null && function.generic_instance.local_owned_parameter >= 0) {
				if (generic_local_transfers.size () != 1) {
					fail ("generic local", "specialized local requires its independently reconstructed incoming transfer");
				}
				foreach (var transfer in generic_local_transfers.get_values ()) {
					if (transfer.source.place.incoming_parameter.ordinal != function.generic_instance.local_owned_parameter) {
						fail ("generic local", "specialized local changed its exact incoming formal");
					}
				}
			}
			foreach (var loan in sealed_loan_views.get_values ()) {
				if (local_owners.lookup (loan.storage) == function && exposed_loan_roots.contains (loan.storage)) {
					fail ("suspension loan", "parent-local backing has a stored or uncontrolled alias");
				}
			}
			if (generic_owner_flow != null && !generic_owner_flow.verify (function.owned_cleanup != null)) {
				fail (active_generic == null ? "buffer exchange ownership flow" : "generic ownership flow", generic_owner_flow.diagnostic.message);
			}
			if (active_generic != null || function.generic_instance != null) {
				storage_flows.insert (function, generic_owner_flow);
				int ordinal = heap_consumer_parameter (function, generic_owner_flow);
				heap_consumer_parameters.insert (function, ordinal);
			}
			generic_owner_flow = null;
			ownership_function = null;
			if (field_state != null) {
				if (((CoreConstructor) function).declaring_class.parent_class != null && !field_state.is_definite ((int) ((CoreConstructor) function).declaring_class.fields.length)) {
					fail ("base init", "every successful constructor completion requires exact base initialization");
				}
				foreach (var field in ((CoreConstructor) function).declaring_class.fields) {
					if (!field_state.is_definite (field.ordinal)) {
						fail ("constructor/" + field.name, "field is not definitely initialized on every successful completion");
					}
				}
			}
			field_state = null;
			foreach (var storage in function.object_storage) {
				if (function.async_body != null && function.async_body.runtime.threaded && !thread_capture_type (storage.semantic_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal))) {
					fail ("threaded frame", "object storage lost its structural Send authority");
				}
				if (((ClassType) storage.semantic_type).intrinsically_shared && !storage.heap_allocated) {
					fail ("shared allocation", "intrinsic weak anchors require independently allocated retained backing");
				}
				if (!object_constructions.contains (storage)) {
					fail ("object storage", "every lexical storage identity requires its exact construction site");
				}
			}
			foreach (var place in function.field_places) {
				if (!initialized.contains (place)) {
					fail ("field " + place.field.name, "field must have exactly one initialization");
				}
			}
			for (int j = 0; j < function.locals.length; j++) {
				if (function.locals[j].semantic_type.kind != TypeKind.STRUCT && !initialized.contains (function.locals[j])) {
					fail ("function #%d/local #%d".printf (i, j), "local must have exactly one initialization");
				}
			}
		}
		// Rebuild finite transfer qualification solely from this verified Core
		// graph, for both abstract definitions and concrete heap instances.
		var heap_qualified = new HashTable<CoreFunction, bool> (direct_hash, direct_equal);
		bool heap_changed = false;
		do {
			heap_changed = false;
			foreach (var function in definitions) {
				if (!heap_consumer_parameters.contains (function) || heap_consumer_parameters.lookup (function) < 0 || heap_qualified.contains (function)) {
					continue;
				}
				var scope = heap_consumer_scopes.lookup (function);
				if (scope == null) {
					continue;
				}
				var target = scope.target as CoreFunction;
				if (scope.target == null || consuming_class_member (scope.target, scope.parameter, function.parameters[heap_consumer_parameters.lookup (function)].semantic_type) || CallableTypes.consumes (scope.target, scope.parameter, function.parameters[heap_consumer_parameters.lookup (function)].semantic_type) || (target != null && target.owned_cleanup == null && heap_qualified.contains (target) && heap_consumer_parameters.lookup (target) == scope.parameter)) {
					heap_qualified.insert (function, true);
					heap_changed = true;
				}
			}
		} while (heap_changed);
		var storage_requirements = new GenericStorageRequirements ();
		foreach (var function in definitions) {
			var flow = storage_flows.lookup (function);
			if (flow == null) {
				continue;
			}
			foreach (var owner in function.owned_locals) {
				if (owner.place.incoming_parameter != null) {
					storage_requirements.link (owner.place.incoming_parameter, owner);
				}
				foreach (var edge in flow.transfers_for (owner)) {
					if (edge.local && edge.target != null) {
						storage_requirements.link (owner, edge.target);
						continue;
					}
					var target = edge.target as CoreFunction;
					if (target != null && edge.parameter >= 0 && edge.parameter < target.parameters.length) {
						var parameter = target.parameters[edge.parameter];
						if (target is CoreGenericFunction || target.generic_instance != null) {
							storage_requirements.link (owner, parameter);
						} else if (parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER && (ownable_parameter (parameter.semantic_type) || parameter.semantic_type is ClassType)) {
							storage_requirements.constrain (owner, ownable_parameter (parameter.semantic_type) || parameter.heap_object ? GenericStorageRequirements.HEAP : GenericStorageRequirements.CALLER);
						}
					} else if (CallableTypes.consumes (edge.target, edge.parameter, owner.place.semantic_type)) {
						storage_requirements.constrain (owner, GenericStorageRequirements.HEAP);
					}
				}
			}
			if (function.generic_instance != null) {
				foreach (var parameter in function.parameters) {
					if (parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER && parameter.semantic_type is ClassType) {
						storage_requirements.constrain (parameter, parameter.heap_object ? GenericStorageRequirements.HEAP : GenericStorageRequirements.CALLER);
					}
				}
			}
		}
		storage_requirements.solve ();
		foreach (var argument in heap_generic_order) {
			if (!storage_requirements.permits (argument.parameter, argument.cleanup.is_heap_object)) {
				fail ("generic storage requirements", "consuming boundary is incompatible with the argument's heap or caller-backed storage");
			}
		}

	}

	private void verify_layout(CoreNativeInstance structure, HashTable<CoreNativeInstance, CoreNativeInstance> complete, GenericArray<CoreNativeInstance> active) throws CoreError {
		if (complete.contains (structure)) {
			return;
		}
		for (int i = 0; i < active.length; i++) {
			if (active[i] != structure) {
				continue;
			}
			var path = new StringBuilder ();
			for (int j = i; j < active.length; j++) {
				path.append (active[j].name + " → ");
			}
			fail ("struct layout", "recursive by-value struct layout: " + path.str + structure.name);
		}
		active.add (structure);
		foreach (var field in structure.fields) {
			if (!(field.semantic_type is StructType)) {
				continue;
			}
			var dependency = structs.lookup (field.semantic_type);
			if (!(dependency is CoreStruct)) {
				fail ("struct layout", "embedded struct requires its exact program-owned descriptor");
			}
			verify_layout (dependency, complete, active);
		}
		active.remove_index (active.length - 1);
		complete.insert (structure, structure);
	}

	private void verify_projections(CorePlace aggregate, CoreFunction function, ref int index, string path) throws CoreError {
		foreach (var field in structs.lookup (aggregate.semantic_type).fields) {
			if (index >= function.field_places.length) {
				fail (path, "missing canonical field projection");
			}
			var place = function.field_places[index++];
			if (place.aggregate != aggregate || place.field != field || place.semantic_type != field.semantic_type || local_owners.contains (place)) {
				fail (path, "field projection must be canonical, function-owned and match its exact aggregate base and declared field");
			}
			local_owners.insert (place, function);
			if (field.semantic_type is StructType) {
				verify_projections (place, function, ref index, path);
			}
		}
	}

	private void collect_initialized_places(CoreStructInitialize initializer, GenericArray<CorePlace> places) {
		places.add (initializer.target);
		foreach (var child in initializer.initializers) {
			if (child is CoreStructInitialize) {
				collect_initialized_places ((CoreStructInitialize) child, places);
			} else if (child is CoreInitialize) {
				places.add (((CoreInitialize) child).target);
			} else if (child is CoreStructAcquire) {
				places.add (((CoreStructAcquire) child).field);
			}
		}
	}

	private bool element_premise(TypeParameterType parameter) {
		return copy_premise (parameter) && active_generic is CoreGenericFunction && ((CoreGenericFunction) active_generic).element_obligations.establishes (parameter, GenericElementRequirements.BUFFER);
	}

	private bool copy_premise(TypeParameterType parameter) {
		return !concrete_only && active_generic != null && type_parameters.lookup (parameter) == active_generic && parameter.transport_mode == GenericTransportMode.PLAIN_COPY;
	}

	private static bool contains_place(CorePlace ancestor, CorePlace place) {
		while (place != ancestor && place is CoreStorageFieldPlace) {
			place = ((CoreStorageFieldPlace) place).aggregate;
		}
		return place == ancestor;
	}

	private GenericArray<SemanticType>? copy_fields(SemanticType type) {
		if (type is EnumType) {
			var definition = enum_definitions.lookup ((EnumType) type);
			return definition == null ? null : definition.value_fields ();
		}
		var result = new GenericArray<SemanticType> ();
		var application = type as CoreGenericStructApplicationType;
		if (application != null && application.definition != null && !concrete_only) {
			foreach (var field in application.definition.fields) {
				result.add (application.field_type (field));
			}
		} else {
			var structure = structs.lookup (type) as CoreStruct;
			if (structure == null) {
				return null;
			}
			foreach (var field in structure.fields) {
				result.add (field.semantic_type);
			}
		}
		return result;
	}

	private void verify_copy_place(CorePlace place, CoreFunction function, bool requires_initialization, string path) throws CoreError {
		verify_place (place, function, false, path);
		CorePlace root = place;
		while (root is CoreStorageFieldPlace) {
			root = ((CoreStorageFieldPlace) root).aggregate;
		}
		var receiver_field = root as CoreIndirectFieldPlace;
		if (requires_initialization && field_state != null && receiver_field != null && receiver_field.pointer is CoreReceiverValue && !field_state.is_definite (receiver_field.field.ordinal)) {
			fail (path, "constructor record field read before complete initialization");
		}
		if (place is CoreLocalPlace && place.semantic_type is StructType) {
			foreach (var field in function.field_places) {
				if (field.root_local () != place) {
					continue;
				}
				if (requires_initialization ? !available.contains (field) : initialized.contains (field)) {
					fail (path, requires_initialization ? "struct copy requires complete initialized visible storage" : "struct copy initialization requires fresh storage exactly once");
				}
			}
		} else if (requires_initialization) {
			verify_place (place, function, true, path);
		}
	}

	private void verify_struct_contract(SemanticType type, StructValueContract? contract, string path, bool borrowed = false) throws CoreError {
		if (type.is_struct_storage () != (contract != null)) {
			fail (path, "struct boundary requires an explicit COPY_VALUE contract");
		}
		if (contract == null) {
			return;
		}
		if (contract.mode == StructValueMode.BORROW_VALUE) {
			if (!borrowed || type.is_parameterized () || record_field (type) == null || contract.semantic_type != type) {
				fail (path, "borrowed record requires an exact concrete owning graph and bounded observation");
			}
			verify_type (type, false, path, true);
			try {
				StructLeafOrder.enumerate_storage (type, copy_fields);
			} catch (StructLeafError error) {
				fail (path, error.message);
			}
			return;
		}
		if (type.is_parameterized ()) {
			verify_type (type, false, path, true);
			if (concrete_only || contract.semantic_type != type || contract.mode != StructValueMode.COPY_VALUE || !GenericArgumentTypes.plain_copy (type, copy_fields, copy_premise)) {
				fail (path, "symbolic record boundary requires its exact scoped copy proof");
			}
			return;
		}
		bool moving = record_field (type) != null;
		if (contract.semantic_type != type || contract.mode != (moving ? StructValueMode.MOVE_VALUE : StructValueMode.COPY_VALUE) || type.is_parameterized () || (concrete_only && !(type is StructType))) {
			fail (path, "struct boundary requires exact concrete nominal identity and derived copy/move mode");
		}
		verify_type (type, false, path, true);
		try {
			if (moving) {
				StructLeafOrder.enumerate_storage (type, copy_fields);
			} else {
				StructLeafOrder.enumerate (type, copy_fields);
			}
		} catch (StructLeafError error) {
			fail (path, error.message);
		}
	}

	private void require_mutable_struct_place(CorePlace place, string path) throws CoreError {
		if (enum_view_place (place)) {
			fail (path, "enum inspection array view is read-only");
		}
		while (place is CoreStorageFieldPlace) {
			place = ((CoreStorageFieldPlace) place).aggregate;
		}
		var local = place as CoreLocalPlace;
		if (local != null && pending_record_borrows.find (local)) {
			fail (path, "record mutation overlaps an active borrowed record argument");
		}
		if (local != null && local.incoming_parameter != null && local.incoming_parameter.struct_value_contract != null) {
			fail (path, "by-value struct parameter storage is read-only");
		}
	}

	private bool fresh_struct_destination(CorePlace place, CoreFunction function) {
		if (place is CoreLocalPlace) {
			return !initialized.contains (place);
		}
		var field = place as CoreIndirectFieldPlace;
		var receiver = field == null ? null : field.pointer as CoreReceiverValue;
		return function is CoreConstructor && field_state != null && receiver != null && receiver.receiver == function.implicit_receiver && field.field.containing_type == ((CoreConstructor) function).declaring_class && !field_state.is_possible (field.field.ordinal);
	}

	private void initialize_struct_place(CorePlace place, CoreFunction function) {
		initialized.insert (place, place);
		available.insert (place, place);
		foreach (var field in function.field_places) {
			if (contains_place (place, field)) {
				initialized.insert (field, field);
				available.insert (field, field);
			}
		}
		var receiver_field = place as CoreIndirectFieldPlace;
		if (receiver_field != null && field_state != null && receiver_field.pointer is CoreReceiverValue) {
			field_state.initialize (receiver_field.field.ordinal);
		}
	}

	private void verify_struct_projection(CoreStructProducer source, StructLeafPath selection, SemanticType expected, CoreFunction function, string path) throws CoreError {
		if ((source.contract.mode != StructValueMode.COPY_VALUE && source.contract.mode != StructValueMode.BORROW_VALUE) || selection.depth == 0 || selection.semantic_type != expected) {
			fail (path, "record projection requires a copied producer and exact nonempty field path");
		}
		verify_struct_producer (source, source.semantic_type, function, path + "/producer", false, true);
		SemanticType selected = source.semantic_type;
		for (int i = 0; i < selection.depth; i++) {
			var fields = copy_fields (selected);
			int ordinal = selection.field_ordinal (i);
			if (fields == null || ordinal < 0 || ordinal >= fields.length) {
				fail (path, "record projection lost its exact nominal field path");
			}
			selected = fields[ordinal];
		}
		if (selected != expected) {
			fail (path, "record projection changed the selected field type");
		}
	}

	private void verify_struct_producer(CoreStructProducer producer, SemanticType expected, CoreFunction function, string path, bool argument = false, bool observation = false) throws CoreError {
		if (producer.semantic_type != expected || struct_producers.contains (producer)) {
			fail (path, "struct producer requires exact nominal compatibility and one bounded consumer");
		}
		struct_producers.insert (producer, true);
		if (producer.contract.mode == StructValueMode.BORROW_VALUE && !observation) {
			fail (path, "borrowed record cannot initialize, assign, move or escape its bounded observation");
		}
		if (expected.is_parameterized ()) {
			verify_type (expected, false, path, true);
			if (concrete_only || producer.contract.semantic_type != expected || producer.contract.mode != StructValueMode.COPY_VALUE || !GenericArgumentTypes.plain_copy (expected, copy_fields, copy_premise)) {
				fail (path, "symbolic struct producer requires its exact scoped copy proof");
			}
		} else {
			var observed = producer as CoreStructCallResult;
			bool borrowed = (producer is CoreStructBorrowSnapshot) ? observation : observed != null && observed.target != null && observed.target.result_contract == ResultOwnershipContract.RECEIVER_BORROW;
			verify_struct_contract (expected, producer.contract, path, borrowed);
		}
		if (argument && producer.contract.mode == StructValueMode.MOVE_VALUE && !(producer is CoreStructMoveProducer)) {
			fail (path, "MOVE_VALUE argument requires an exact named owning record move producer");
		}
		if (producer is CoreStructInvocationResult) {
			var invocation = ((CoreStructInvocationResult) producer).invocation;
			if (!(invocation is CoreFunctionValueCall || invocation is CoreClosureCall) || invocation.semantic_type != producer.semantic_type || producer.contract.mode == StructValueMode.BORROW_VALUE) {
				fail (path, "indirect record producer requires its exact owned/copy result contract");
			}
			verify_value (invocation, function, path + "/invocation", null, false, null, false, false, false, false, null, true);
			return;
		}
		if (producer is CoreStructProjectionProducer) {
			var projection = (CoreStructProjectionProducer) producer;
			verify_struct_projection (projection.source, projection.path, expected, function, path);
			return;
		}
		if (producer is CoreSlotsRecordRead) {
			var read = (CoreSlotsRecordRead) producer;
			verify_slots_place (read.store, function, true, path);
			if ((producer.contract.mode == StructValueMode.MOVE_VALUE && !read.remove) || ((OwnerSlotsType) read.store.semantic_type).element != expected || read.index.semantic_type.kind != TypeKind.INT) {
				fail (path, "record slot read lost exact copy layout or index");
			}
			if (read.remove) {
				verify_slots_mutation (read.store, path);
			}
			verify_value (read.index, function, path);
			return;
		}
		if (producer is CoreStructMoveProducer) {
			var source = ((CoreStructMoveProducer) producer).source;
			if (source == null || owned_places.lookup (source.place) != source || source.cleanup.record_type == null || source.cleanup.record_type.semantic_type != expected || source.record_fields.length == 0 || producer.contract.mode != StructValueMode.MOVE_VALUE) {
				fail (path, "MOVE_VALUE producer requires its exact live owning record root");
			}
			verify_copy_place (source.place, function, true, path);
			if (!argument) {
				record_boundary_events (GenericOwnershipEventKind.MOVE, source, producer.span);
			}
			return;
		}
		if (producer is CoreStructAwait) {
			var operation = ((CoreStructAwait) producer).operation;
			if (operation.semantic_type != expected || aggregate_awaits.contains (operation)) {
				fail (path, "record await lost its exact bounded result consumer");
			}
			aggregate_awaits.insert (operation, true);
			verify_value (operation, function, path + "/await");
			return;
		}
		if (producer is CoreStructBorrowSnapshot) {
			var local = ((CoreStructBorrowSnapshot) producer).source as CoreLocalPlace;
			if (local != null) {
				var owner = owned_places.lookup (local);
				bool incoming = local.incoming_parameter != null && borrowed_record_parameter (local.incoming_parameter) && owners.lookup (local.incoming_parameter) == function;
				if (local.semantic_type != expected || (owner == null && !incoming) || owner != null && owner.cleanup.record_type == null) {
					fail (path, "record loan requires its exact named owner or borrowed parameter");
				}
				verify_copy_place (local, function, true, path);
				if (owner != null) {
					record_boundary_events (GenericOwnershipEventKind.READ, owner, producer.span);
				}
				return;
			}
			var source = ((CoreStructBorrowSnapshot) producer).source as CoreIndirectFieldPlace;
			var receiver = source == null ? null : source.pointer as CoreReceiverValue;
			if (!(function is CorePropertyGetter) || receiver == null || receiver.receiver != function.implicit_receiver || source.field.owned_cleanup == null || source.field.owned_cleanup.record_type == null || source.semantic_type != expected || producer.contract.mode != StructValueMode.BORROW_VALUE) {
				fail (path, "record borrow snapshot requires its exact complete owning receiver field");
			}
			verify_place (source, function, true, path);
			return;
		}
		var snapshot = producer as CoreStructSnapshot;
		if (snapshot != null) {
			if (snapshot.source.semantic_type != expected || owned_places.contains (snapshot.source)) {
				fail (path, "struct snapshot requires exact copyable source storage");
			}
			verify_copy_place (snapshot.source, function, true, path + "/source");
			return;
		}
		var foreign_call = producer as CoreCStructCallResult;
		if (foreign_call != null) {
			if (foreign_call.target == null || foreign_call.target.metadata.record_abi != Astra.Foreign.CRecordAbi.VALUE_LP64 || foreign_call.target.return_type != expected) {
				fail (path, "C struct producer lost its exact value-lp64 result");
			}
			verify_c_call (foreign_call.target, foreign_call.arguments, function, path);
			return;
		}
		var call = producer as CoreStructCallResult;
		if (call == null || call.target == null || call.target.owned_cleanup != null) {
			fail (path, "struct call producer requires its exact native COPY_VALUE result");
		}
		var substitution = verify_generic_arguments (call.target, call.type_arguments, path);
		if ((substitution == null && call.target.struct_result_contract == null) || (substitution == null ? call.target.return_type : substitution.apply (call.target.return_type)) != expected) {
			fail (path, "struct call producer lost its exact substituted result identity");
		}
		verify_call (call.target, call.arguments, function, path, call.receiver, false, call.type_arguments);
	}

	private void record_boundary_events(GenericOwnershipEventKind kind, CoreOwnedLocal owner, Astra.Source.SourceSpan span) throws CoreError {
		if (kind != GenericOwnershipEventKind.READ && pending_record_borrows.find (owner.place)) {
			fail ("record boundary", "ownership mutation overlaps an active borrowed record argument");
		}
		if (generic_owner_flow == null) {
			return;
		}
		generic_owner_flow.owner_event (kind, owner, owner.place.name, span);
		foreach (var field in owner.record_fields) {
			generic_owner_flow.owner_event (kind, field, owner.place.name + "." + field.storage_path ().spelling (), span);
		}
	}

	private void read_buffer_place(CorePlace place) {
		if (generic_owner_flow == null) {
			return;
		}
		if (place is CoreStorageFieldPlace) {
			read_buffer_place (((CoreStorageFieldPlace) place).aggregate);
		}
		var slice = place as CoreSliceElementPlace;
		var borrow = slice == null ? null : slice.slice as CoreOwnedBufferBorrow;
		if (borrow != null) {
			generic_owner_flow.owner_event (GenericOwnershipEventKind.READ, borrow.source, borrow.source.place.name, place.span);
		}
	}

	private CoreOwnedFieldBorrow? place_field_borrow(CorePlace place) {
		if (place is CoreStorageFieldPlace) {
			return place_field_borrow (((CoreStorageFieldPlace) place).aggregate);
		}
		return (place is CoreSliceElementPlace) ? ((CoreSliceElementPlace) place).slice as CoreOwnedFieldBorrow : null;
	}

	private void verify_struct_copy(CoreStructCopy copy, CoreFunction function, string path) throws CoreError {
		var type = copy.semantic_type;
		require_mutable_struct_place (copy.destination, path);
		if (!type.is_struct_storage () || copy.destination.semantic_type != type || copy.source.semantic_type != type || (concrete_only && !(type is StructType))) {
			fail (path, "struct copy requires the exact same nominal StructType on both Places");
		}
		verify_type (type, false, path + "/type", true);
		if (!GenericArgumentTypes.plain_copy (type, copy_fields, copy_premise)) {
			fail (path, "struct copy field graph is not recursively copyable under exact scoped premises");
		}
		if (copy.initializes_destination && !fresh_struct_destination (copy.destination, function)) {
			fail (path, "struct copy initialization requires one fresh local or exact constructor field");
		}
		if (owned_places.contains (copy.destination) || owned_places.contains (copy.source)) {
			fail (path, "struct copy excludes ownership-bearing storage");
		}
		verify_copy_place (copy.destination, function, !copy.initializes_destination, path + "/destination");
		var borrow = place_field_borrow (copy.destination);
		if (borrow != null) {
			pending_field_borrows.add (borrow.source.field.containing_type.semantic_type);
		}
		verify_copy_place (copy.source, function, true, path + "/source");
		if (borrow != null) {
			pending_field_borrows.remove_index (pending_field_borrows.length - 1);
		}
		if (copy.initializes_destination) {
			initialize_struct_place (copy.destination, function);
		}
	}

	private void verify_array_fields(CoreArrayElementPlace root, CorePlace target, GenericArray<CoreStatement> children, CoreFunction function, string path) throws CoreError {
		if (children.length != storage_field_count (target.semantic_type)) {
			fail (path, "record entry requires every field exactly once");
		}
		var seen = new HashTable<CoreNode, bool> (direct_hash, direct_equal);
		foreach (var child in children) {
			var nested = child as CoreStructInitialize;
			var leaf = child as CoreInitialize;
			var field = nested != null ? nested.target : leaf == null ? null : leaf.target as CoreStorageFieldPlace;
			if (field == null || field.aggregate != target || seen.contains (projection_identity (field)) || (leaf != null && leaf.acquisition != null)) {
				fail (path, "record entry requires distinct exact field projections");
			}
			seen.insert (projection_identity (field), true);
			initializing_array_entry = root;
			verify_place (field, function, false, path);
			initializing_array_entry = null;
			if (nested != null && nested.producer != null) {
				if (nested.initializers.length != 0) {
					fail (path, "record field entry requires exactly one producer or nested initializer");
				}
				verify_struct_producer (nested.producer, field.semantic_type, function, path);
			} else if (nested != null) {
				verify_array_fields (root, field, nested.initializers, function, path);
			} else {
				verify_value (leaf.value, function, path + "/value");
				if (leaf.value.semantic_type != field.semantic_type) {
					fail (path, "record field initializer requires exact leaf type");
				}
			}
		}
	}

	private void verify_struct_initializer(CoreStructInitialize initializer, CoreFunction function, CoreBlock scope, string path) throws CoreError {
		var target = initializer.target;
		verify_place (target, function, false, path);
		if (initializer.producer != null) {
			if (target.root_local () == null || initialized.contains (target) || initializer.initializers.length != 0) {
				fail (path, "field producer requires fresh exact subobject storage and a single source");
			}
			var owner = initializer.record_owner;
			if (initializer.producer.contract.mode == StructValueMode.MOVE_VALUE) {
				if (owner == null || owned_places.lookup (target.root_local ()) != owner || owner.scope != scope) {
					fail (path, "owning subobject producer requires its exact lexical root responsibility");
				}
				bool reached = false;
				foreach (var field in owner.record_fields) {
					if (contains_place (target, field)) {
						reached = true;
						if (initialized.contains (field)) {
							fail (path, "owning subobject cannot reacquire an initialized field");
						}
					} else if (!reached && !initialized.contains (field)) {
						fail (path, "owning subobject acquisition lost written initialized prefix");
					}
				}
				if (!reached) {
					fail (path, "owning subobject omitted its destination leaf obligations");
				}
			} else if (owner != null) {
				fail (path, "copied subobject cannot acquire record responsibility");
			}
			verify_struct_producer (initializer.producer, target.semantic_type, function, path);
			initialize_struct_place (target, function);
			return;
		}
		if (!target.semantic_type.is_struct_storage () || target.root_local () == null || initialized.contains (target) || initializer.initializers.length != storage_field_count (target.semantic_type)) {
			fail (path, "nested initializer requires complete unique direct struct subobject storage");
		}
		var seen = new HashTable<CoreNode, CoreNode> (direct_hash, direct_equal);
		foreach (var child in initializer.initializers) {
			var nested = child as CoreStructInitialize;
			var leaf = child as CoreInitialize;
			var acquire = child as CoreStructAcquire;
			var field = nested != null ? nested.target : acquire != null ? acquire.field : leaf == null ? null : leaf.target as CoreStorageFieldPlace;
			if (field == null || field.aggregate != target || seen.contains (projection_identity (field)) || (leaf != null && leaf.acquisition != null)) {
				fail (path, "nested initializer children require distinct exact target field identities");
			}
			var identity = projection_identity (field);
			seen.insert (identity, identity);
			verify_statement (child, function, scope, path + "/field");
		}
		initialized.insert (target, target);
		available.insert (target, target);
	}

	private void verify_block(CoreBlock block, CoreFunction function, string path) throws CoreError {
		if (blocks.contains (block)) {
			fail (path, "block identity occurs more than once in structured Core");
		}
		blocks.insert (block, block);
		var declarations = new GenericArray<CorePlace> ();
		CorePlace? pending_aggregate = null;
		int pending_fields = 0;
		for (int i = 0; i < block.statements.length; i++) {
			var statement = block.statements[i];
			var sequence_loop = statement as CoreWhile;
			if (sequence_loop != null && sequence_loop.sequence != null && !sequence_loop.sequence.is_iterator) {
				var initial = i == 0 ? null : block.statements[i - 1] as CoreInitialize;
				var zero = initial == null ? null : initial.value as CoreIntegerValue;
				if (initial == null || initial.target != sequence_loop.sequence.index || zero == null || zero.value.signed_value != 0) {
					fail (path, "foreach sequence requires an immediately preceding fresh zero index");
				}
			}
			if (statement is CoreWhile && ((CoreWhile) statement).iteration != null) {
				var iteration = ((CoreWhile) statement).iteration;
				var initial = i == 0 ? null : block.statements[i - 1] as CoreInitialize;
				var zero = initial == null ? null : initial.value as CoreIntegerValue;
				if (initial == null || initial.target != iteration.index || zero == null || zero.value.signed_value != 0) {
					fail (path, "foreach requires an immediately preceding fresh zero index");
				}
			}
			var initialization = statement as CoreInitialize;
			var nested = statement as CoreStructInitialize;
			var acquire = statement as CoreStructAcquire;
			CoreStorageFieldPlace? field = acquire != null ? acquire.field : nested != null ? nested.target : initialization == null ? null : initialization.target as CoreStorageFieldPlace;
			if (pending_aggregate != null && (field == null || field.aggregate != pending_aggregate)) {
				fail (path, "struct declaration must initialize every field in one contiguous sequence");
			}
			verify_statement (statement, function, block, path + "/statement #%d".printf (i));
			if (field != null) {
				pending_aggregate = field.aggregate;
				pending_fields++;
				if (pending_fields == storage_field_count (field.aggregate.semantic_type)) {
					initialized.insert (field.aggregate, field.aggregate);
					available.insert (field.aggregate, field.aggregate);
					declarations.add (field.aggregate);
					pending_aggregate = null;
					pending_fields = 0;
				}
			}
			if (statement is CoreStructMove) {
				var destination = ((CoreStructMove) statement).destination.place;
				declarations.add (destination);
				foreach (var projection in function.field_places) {
					if (projection.root_local () == destination) {
						declarations.add (projection);
					}
				}
			}
			if (statement is CoreRecordTake) {
				declarations.add (((CoreRecordTake) statement).destination.place);
			}
			if (statement is CoreStructResultStore && ((CoreStructResultStore) statement).initializes_destination) {
				var destination = ((CoreStructResultStore) statement).destination;
				declarations.add (destination);
				foreach (var projection in function.field_places) {
					if (projection.root_local () == destination) {
						declarations.add (projection);
					}
				}
			}
			if (statement is CoreEnumStore && ((CoreEnumStore) statement).initializes_destination) {
				declarations.add (((CoreEnumStore) statement).destination);
			}
			if (statement is CoreAcquireEnumParameter) {
				declarations.add (((CoreAcquireEnumParameter) statement).destination);
			}
			var copy = statement as CoreStructCopy;
			if (copy != null && copy.initializes_destination) {
				declarations.add (copy.destination);
				foreach (var projection in function.field_places) {
					if (projection.root_local () == copy.destination) {
						declarations.add (projection);
					}
				}
			}
			if (nested != null) {
				collect_initialized_places (nested, declarations);
				foreach (var projection in function.field_places) {
					if (contains_place (nested.target, projection)) {
						declarations.add (projection);
					}
				}
			}
			if (statement is CoreObjectConstruction) {
				declarations.add (((CoreObjectConstruction) statement).target);
			}
			if (statement is CoreArrayInitialize) {
				declarations.add (((CoreArrayInitialize) statement).storage);
			}
			if (statement is CoreInitialize) {
				declarations.add (((CoreInitialize) statement).target);
			} else if (statement is CoreOwnershipTransfer) {
				declarations.add (((CoreOwnershipTransfer) statement).destination.place);
			}
		}
		if (pending_aggregate != null) {
			fail (path, "incomplete struct field initialization in declaration block");
		}
		for (int i = 0; i < declarations.length; i++) {
			var owner = owned_places.lookup (declarations[i]);
			if (generic_owner_flow != null && owner != null && generic_local_owner (owner)) {
				generic_owner_flow.owner_event (GenericOwnershipEventKind.RETIRE, owner, owner.place.name, block.span);
			}
			available.remove (declarations[i]);
		}
	}

	private void verify_statement(CoreStatement statement, CoreFunction function, CoreBlock scope, string path) throws CoreError {
		if (statement is CoreActorSend) {
			var send = (CoreActorSend) statement;
			var type = send.sender.semantic_type as ClosureHandleType;
			var error = structs.lookup (send.error_type) as CoreClass;
			if (type == null || !type.actor || !type.supported () || send.action < Astra.Source.ActorAction.SEND || send.action > Astra.Source.ActorAction.CANCEL || function.async_body != null || error == null || !error.exception_root || error.parent_class != null || error.constructor == null || error.constructor.throws_type != null || error.constructor.parameters.length != 1 || !(error.constructor.parameters[0].semantic_type is StringType)) {
				fail (path, "Actor operation lost exact sender, finite action or ordinary nominated Error constructor");
			}
			verify_exception_effect (send.error_type, function, path);
			var load = send.sender as CoreLoadValue;
			var parameter = send.sender as CoreParameterValue;
			if (load == null ? parameter == null || parameter.parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE : !(load.source is CoreLocalPlace) || !owned_places.contains (load.source)) {
				fail (path, "Actor operation requires immediate live sender loan");
			}
			verify_value (send.sender, function, path + "/sender", null, true, null, true);
			if (send.action == Astra.Source.ActorAction.SEND) {
				if (type.actor_message is ClassType) {
					if (send.scalar != null || send.message == null || owned_places.lookup (send.message.place) != send.message || !send.message.cleanup.is_heap_object || send.message.cleanup.object_class.polymorphic || send.message.place.semantic_type != type.actor_message) {
						fail (path, "Actor send requires sole exact heap message move on every outcome");
					}
					verify_iteration_consumption (send.message, path);
					verify_place (send.message.place, function, true, path + "/message");
				} else {
					if (send.message != null || send.scalar == null || send.scalar.semantic_type != type.actor_message || !FunctionValueType.scalar (send.scalar.semantic_type)) {
						fail (path, "Actor scalar send requires one exact copied numeric/bool scalar");
					}
					verify_value (send.scalar, function, path + "/scalar");
				}
			} else if (send.scalar != null || send.message != null) {
				fail (path, "Actor lifecycle operation cannot carry a message");
			}
			return;
		}
		if (statement is CoreValueStatement) {
			var value = ((CoreValueStatement) statement).value;
			if (!(value is CoreFunctionValueCall || value is CoreClosureCall) || value.semantic_type.kind != TypeKind.VOID && !FunctionValueType.scalar (value.semantic_type)) {
				fail (path, "indirect call statement requires its exact scalar or void result");
			}
			verify_value (value, function, path, null, false, null, false, false, false, false, null, false, true);
			return;
		}
		if (statement is CoreAsyncOperationStatement) {
			verify_value (((CoreAsyncOperationStatement) statement).operation, function, path);
			return;
		}
		if (statement is CoreTaskAwaitStatement) {
			verify_value (((CoreTaskAwaitStatement) statement).operation, function, path);
			return;
		}
		if (statement is CoreAsyncDelay) {
			var delay = (CoreAsyncDelay) statement;
			if (delay.body != function.async_body) {
				fail (path, "suspension lost exact async body identity");
			}
			if (delay.payload) {
				var load = delay.ticks as CoreLoadValue;
				var owner = load == null ? null : owned_places.lookup (load.source);
				if (!delay.body.runtime.linux || owner == null || !AsyncPayloadTypes.matches (load.semantic_type, owner.cleanup.external_symbol)) {
					fail (path, "payload suspension requires exact unique LinuxPayload owner and cleanup");
				}
				verify_value (delay.ticks, function, path + "/payload", null, true, null, true);
			} else {
				verify_value (delay.ticks, function, path + "/ticks");
				if (delay.ticks.semantic_type.kind != TypeKind.U32 && delay.ticks.semantic_type.kind != TypeKind.INT) {
					fail (path, "virtual suspension requires integral ticks");
				}
			}
			return;
		}
		verify_statement_body (statement, function, scope, path);
		if (generic_owner_flow != null) {
			var subobject = statement as CoreStructInitialize;
			if (subobject != null && subobject.record_owner != null) {
				var owner = subobject.record_owner;
				generic_owner_flow.owner_event (GenericOwnershipEventKind.ACQUIRE, owner, owner.place.name, statement.span);
				foreach (var field in owner.record_fields) {
					if (contains_place (subobject.target, field)) {
						generic_owner_flow.owner_event (GenericOwnershipEventKind.ACQUIRE, field, owner.place.name + "." + field.storage_path ().spelling (), statement.span);
					}
				}
			}
			if (statement is CoreAcquireStructParameter) {
				var owner = owned_places.lookup (((CoreAcquireStructParameter) statement).destination);
				if (owner != null && owner.record_fields.length != 0) {
					record_boundary_events (GenericOwnershipEventKind.ACQUIRE, owner, statement.span);
				}
			}
			if (statement is CoreStructResultStore && ((CoreStructResultStore) statement).producer.contract.mode == StructValueMode.MOVE_VALUE) {
				var destination = ((CoreStructResultStore) statement).destination;
				var owner = owned_places.lookup (destination);
				if (owner != null) {
					record_boundary_events (GenericOwnershipEventKind.ACQUIRE, owner, statement.span);
				} else if (!(destination is CoreIndirectFieldPlace)) {
					fail (path, "record acquisition lost its exact local or owning Class field");
				}
			}
			if (statement is CoreStructAcquire) {
				var acquire = (CoreStructAcquire) statement;
				var field = acquire.field;
				generic_owner_flow.owner_event (GenericOwnershipEventKind.ACQUIRE, acquire.owner, acquire.owner.place.name, statement.span);
				generic_owner_flow.owner_event (GenericOwnershipEventKind.ACQUIRE, field, field.root_local ().name + "." + field.storage_path ().spelling (), statement.span);
			}
			if (statement is CoreStructMove) {
				var move = (CoreStructMove) statement;
				generic_owner_flow.move (move.source, move.source.place.name, statement.span);
				generic_owner_flow.owner_event (GenericOwnershipEventKind.ACQUIRE, move.destination, move.destination.place.name, statement.span);
				foreach (var field in move.source.record_fields) {
					generic_owner_flow.move (field, move.source.place.name + "." + field.storage_path ().spelling (), statement.span);
				}
				foreach (var field in move.destination.record_fields) {
					generic_owner_flow.owner_event (GenericOwnershipEventKind.ACQUIRE, field, move.destination.place.name + "." + field.storage_path ().spelling (), statement.span);
				}
			}
			if (statement is CoreRecordTake) {
				var take = (CoreRecordTake) statement;
				generic_owner_flow.owner_event (GenericOwnershipEventKind.READ, take.source, take.source.place.name, statement.span);
				generic_owner_flow.move (take.field, take.source.place.name + "." + take.field.storage_path ().spelling (), statement.span);
				if (tracked_owner (take.destination)) {
					generic_owner_flow.owner_event (GenericOwnershipEventKind.ACQUIRE, take.destination, take.destination.place.name, statement.span);
				}
			}
			if (statement is CoreRecordReplace) {
				var replace = (CoreRecordReplace) statement;
				generic_owner_flow.owner_event (GenericOwnershipEventKind.READ, replace.owner, replace.owner.place.name, statement.span);
				if (replace.source != null && tracked_owner (replace.source)) {
					generic_owner_flow.move (replace.source, replace.source.place.name, statement.span);
				}
				generic_owner_flow.owner_event (GenericOwnershipEventKind.ACQUIRE, replace.field, replace.owner.place.name + "." + replace.field.storage_path ().spelling (), statement.span);
			}
			if (statement is CoreStore) {
				read_buffer_place (((CoreStore) statement).target);
			}
			if (statement is CoreStructCopy) {
				read_buffer_place (((CoreStructCopy) statement).destination);
			}
			if (statement is CoreStructResultStore) {
				read_buffer_place (((CoreStructResultStore) statement).destination);
			}
			var field_transfer = statement as CoreOwnedFieldTransfer;
			if (field_transfer != null && field_transfer.source != null && field_transfer.cleanup.is_buffer) {
				generic_owner_flow.move (field_transfer.source, field_transfer.source.place.name, statement.span);
			}
			var initialized_owner = (statement is CoreInitialize) ? ((CoreInitialize) statement).acquisition : null;
			if (initialized_owner != null && generic_local_acquisitions.contains (initialized_owner)) {
				generic_owner_flow.owner_event (GenericOwnershipEventKind.LOCAL_ACQUIRE, initialized_owner, initialized_owner.place.name, statement.span);
			}
			if (initialized_owner != null && initialized_owner.cleanup.is_buffer) {
				generic_owner_flow.owner_event (GenericOwnershipEventKind.ACQUIRE, initialized_owner, initialized_owner.place.name, statement.span);
			}
			var transfer = statement as CoreOwnershipTransfer;
			if (transfer != null && tracked_owner (transfer.source)) {
				if (generic_local_transfers.contains (transfer.destination)) {
					generic_owner_flow.move (transfer.source, transfer.source.place.name, statement.span, transfer.destination, -1, false, true);
				} else {
					generic_owner_flow.move (transfer.source, transfer.source.place.name, statement.span);
					generic_owner_flow.owner_event (GenericOwnershipEventKind.ACQUIRE, transfer.destination, transfer.destination.place.name, statement.span);
				}
			}
			var release = statement as CoreOwnershipRelease;
			if (release != null && tracked_owner (release.owner)) {
				generic_owner_flow.owner_event (GenericOwnershipEventKind.RELEASE, release.owner, release.owner.place.name, statement.span);
			}
			var rearm = statement as CoreOwnershipRearm;
			if (rearm != null && rearm.cleanup.is_buffer) {
				if (rearm.source != null) {
					generic_owner_flow.move (rearm.source, rearm.source.place.name, statement.span);
				}
				generic_owner_flow.owner_event (GenericOwnershipEventKind.ACQUIRE, rearm.owner, rearm.owner.place.name, statement.span);
			}
			if (statement is CoreReturn || statement is CoreStructReturn || statement is CoreOwnershipReturn) {
				foreach (var owner in function.owned_locals) {
					if (generic_local_owner (owner) && available.contains (owner.place)) {
						generic_owner_flow.owner_event (GenericOwnershipEventKind.RETIRE, owner, owner.place.name, statement.span);
					}
				}
				generic_owner_flow.jump (GenericOwnershipEventKind.RETURN, statement.span);
			}
			if (statement is CoreBreak || statement is CoreContinue) {
				generic_owner_flow.jump ((statement is CoreBreak) ? GenericOwnershipEventKind.BREAK : GenericOwnershipEventKind.CONTINUE, statement.span, (statement is CoreBreak) ? ((CoreBreak) statement).target : ((CoreContinue) statement).target);
			}
		}
	}

	private static bool contains_buffer_exchange(CoreBlock root) {
		var pending = new GenericArray<CoreBlock> ();
		var seen = new HashTable<CoreBlock, bool> (direct_hash, direct_equal);
		pending.add (root);
		for (int i = 0; i < pending.length; i++) {
			var block = pending[i];
			if (seen.contains (block)) {
				continue;
			}
			seen.insert (block, true);
			foreach (var statement in block.statements) {
				if (statement is CoreOwnedBufferExchange) {
					return true;
				}
				if (statement is CoreScope) {
					pending.add (((CoreScope) statement).body);
				}
				if (statement is CoreWhile) {
					pending.add (((CoreWhile) statement).body);
					if (((CoreWhile) statement).step != null) {
						pending.add (((CoreWhile) statement).step);
					}
				}
				if (statement is CoreIf) {
					var branch = (CoreIf) statement;
					pending.add (branch.then_block);
					if (branch.else_block != null) {
						pending.add (branch.else_block);
					}
				}
			}
		}
		return false;
	}

	private void verify_buffer_owner_slot(CoreBufferOwnerSlot slot, CoreFunction function, string path) throws CoreError {
		if (!(slot.place.semantic_type is SliceType) || !cleanups.contains (slot.cleanup) || !slot.cleanup.is_buffer || !matches_cleanup (slot.place.semantic_type, slot.cleanup)) {
			fail (path, "buffer exchange slot requires exact buffer type and cleanup authority");
		}
		var field = slot.place as CoreIndirectFieldPlace;
		if (slot.owner != null) {
			if (owned_places.lookup (slot.place) != slot.owner || slot.owner.place != slot.place || slot.owner.cleanup != slot.cleanup) {
				fail (path, "buffer exchange local slot/owner/cleanup identity mismatch");
			}
			if (generic_owner_flow != null) {
				generic_owner_flow.owner_event (GenericOwnershipEventKind.READ, slot.owner, slot.owner.place.name, slot.span);
			}
		} else {
			if (field == null || !(field.field.containing_type is CoreClass) || field.field.owned_cleanup != slot.cleanup) {
				fail (path, "buffer exchange field requires native class owner storage");
			}
			foreach (var container in pending_field_borrows) {
				if (container == field.field.containing_type.semantic_type) {
					fail (path, "buffer exchange overlaps a pending containing-object field borrow");
				}
			}
		}
		verify_place (slot.place, function, true, path);
	}

	private bool enum_view_place(CorePlace place) {
		if (place is CoreStorageFieldPlace) {
			return enum_view_place (((CoreStorageFieldPlace) place).aggregate);
		}
		var slice = place as CoreSliceElementPlace;
		var load = slice == null ? null : slice.slice as CoreLoadValue;
		return enum_views.contains (place) || (load != null && enum_views.contains (load.source));
	}

	private bool valid_enum_scalar_owner(EnumField field) {
		if (field.owns_child) {
			var owner = structs.lookup (field.semantic_type) as CoreClass;
			return owner != null && !owner.polymorphic && !((ClassType) owner.semantic_type).is_interface;
		}
		var handle = handles.lookup (field.semantic_type);
		return handle != null && field.owned_cleanup != null && handle.cleanup.external_symbol == field.owned_cleanup.external_symbol;
	}

	private void verify_enum_producer(CoreEnumProducer producer, EnumType expected, CoreFunction function, string path, bool reserve = false, bool inspection = false) throws CoreError {
		if (producer.semantic_type != expected || enum_definitions.lookup (expected) != producer.definition || enum_producers.contains (producer)) {
			fail (path, "enum producer requires one exact nominal definition and bounded consumer");
		}
		enum_producers.insert (producer, true);
		if (producer is CoreEnumAwait) {
			var operation = ((CoreEnumAwait) producer).operation;
			if (operation.semantic_type != expected || aggregate_awaits.contains (operation)) {
				fail (path, "enum await lost its exact bounded result consumer");
			}
			aggregate_awaits.insert (operation, true);
			verify_value (operation, function, path + "/await");
			return;
		}
		if (producer is CoreAsyncRun) {
			var operation = ((CoreAsyncRun) producer).operation;
			if (expected != operation.contract.runtime.status_type || operation.contract.kind != AsyncOperationKind.RUN) {
				fail (path, "void root status requires its exact nominated ordinary enum");
			}
			verify_value (operation, function, path + "/run");
			return;
		}
		var snapshot = producer as CoreEnumSnapshot;
		if (snapshot != null) {
			bool owning = EnumValueAuthority.owns (snapshot.definition, (type) => enum_definitions.lookup (type));
			if (snapshot.source.semantic_type != expected || (owning ? snapshot.mode == EnumUse.COPY || (snapshot.mode == EnumUse.INSPECT && !inspection) : snapshot.mode != EnumUse.COPY)) {
				fail (path, "enum snapshot requires exact nominal identity and derived copy/move/inspection authority");
			}
			if (snapshot.mode == EnumUse.MOVE && (enum_reservations.find (snapshot.source) || enum_views.contains (snapshot.source) || enum_inspections.find (snapshot.source))) {
				fail (path, "enum owner is reserved by an unfinished consumer");
			}
			verify_place (snapshot.source, function, true, path);
			if (owning && generic_owner_flow != null) {
				if (snapshot.mode == EnumUse.MOVE && reserve) {
					enum_reservations.add (snapshot.source);
					generic_owner_flow.owner_event (GenericOwnershipEventKind.READ, snapshot.source, snapshot.source.name, snapshot.span);
				} else {
					generic_owner_flow.owner_event (snapshot.mode == EnumUse.MOVE ? GenericOwnershipEventKind.MOVE : GenericOwnershipEventKind.READ, snapshot.source, snapshot.source.name, snapshot.span);
				}
			}
			return;
		}
		var construction = producer as CoreEnumConstruct;
		if (construction != null && !construction.matches_inputs ()) {
			fail (path, "enum constructor lost intended field/operand correspondence");
		}
		if (construction != null) {
			uint reservation_depth = enum_reservations.length;
			var variant = construction.variant;
			if (variant.identity.ordinal < 0 || variant.identity.ordinal >= producer.definition.variant_count || producer.definition.variant (variant.identity.ordinal) != variant || construction.fields.length != variant.field_count) {
				fail (path, "enum construction requires its exact variant and complete active fields");
			}
			for (uint f = 0; f < variant.field_count; f++) {
				var input = construction.fields[f];
				var field = variant.field (f);
				int channels = (input.scalar == null ? 0 : 1) + (input.record == null ? 0 : 1) + (input.sum == null ? 0 : 1);
				if (input.field != field || channels != 1) {
					fail (path, "enum construction field/value correspondence mismatch");
				}
				if (field.semantic_type is EnumType) {
					if (input.sum == null) {
						fail (path, "nested enum field requires an exact sum producer");
					}
					verify_enum_producer (input.sum, (EnumType) field.semantic_type, function, path, true);
				} else if (field.semantic_type.is_struct_storage ()) {
					if (input.record == null) {
						fail (path, "record payload requires its exact copied or moving producer");
					}
					verify_struct_producer (input.record, field.semantic_type, function, path, field.owns_record);
					if (field.owns_record) {
						var owner = ((CoreStructMoveProducer) input.record).source;
						if (enum_reservations.find (owner.place)) {
							fail (path, "record owner is reserved by an unfinished enum constructor");
						}
						record_boundary_events (GenericOwnershipEventKind.READ, owner, input.span);
						enum_reservations.add (owner.place);
					}
				} else if (field.owns_scalar) {
					var scalar = input.scalar as CoreEnumScalarValue;
					if (scalar == null || scalar.semantic_type != field.semantic_type || owned_places.lookup (scalar.source.place) != scalar.source || !cleanups.contains (scalar.cleanup) || !matches_cleanup (field.semantic_type, scalar.cleanup) || scalar.cleanup.is_heap_object != field.owns_child || (field.owned_cleanup != null && scalar.cleanup.external_symbol != field.owned_cleanup.external_symbol)) {
						fail (path, "owned enum scalar field requires its exact named owner and Resource or heap Class cleanup");
					}
					verify_place (scalar.source.place, function, true, path);
					if (enum_reservations.find (scalar.source.place)) {
						fail (path, "enum scalar owner is reserved by another unfinished consumer");
					}
					enum_reservations.add (scalar.source.place);
					if (generic_owner_flow != null) {
						generic_owner_flow.owner_event (GenericOwnershipEventKind.READ, scalar.source, scalar.source.place.name, scalar.span);
					}
				} else if (field.owns_buffer) {
					var buffer = input.scalar as CoreEnumBufferValue;
					if (buffer == null || buffer.semantic_type != field.semantic_type || !cleanups.contains (buffer.cleanup) || !matches_cleanup (field.semantic_type, buffer.cleanup) || (buffer.source == null) == (buffer.producer == null)) {
						fail (path, "owned enum payload requires one exact buffer transfer and cleanup authority");
					}
					if (buffer.source != null) {
						if (owned_places.lookup (buffer.source.place) != buffer.source || buffer.source.cleanup != buffer.cleanup) {
							fail (path, "owned enum payload source lost ownership identity");
						}
						verify_place (buffer.source.place, function, true, path);
						if (enum_reservations.find (buffer.source.place)) {
							fail (path, "buffer owner is reserved by another unfinished enum consumer");
						}
						enum_reservations.add (buffer.source.place);
						if (generic_owner_flow != null) {
							generic_owner_flow.owner_event (GenericOwnershipEventKind.READ, buffer.source, buffer.source.place.name, buffer.span);
						}
					} else {
						verify_value (buffer.producer, function, path, buffer.cleanup);
					}
				} else {
					if (input.scalar == null || input.scalar.semantic_type != field.semantic_type || input.scalar is CoreEnumBufferValue) {
						fail (path, "enum scalar payload has the wrong exact type");
					}
					verify_value (input.scalar, function, path);
				}
			}
			while (enum_reservations.length > reservation_depth) {
				var place = enum_reservations[reservation_depth];
				var owner = owned_places.lookup (place);
				if (owner != null && owner.cleanup.record_type != null) {
					record_boundary_events (GenericOwnershipEventKind.MOVE, owner, construction.span);
				} else if (generic_owner_flow != null) {
					generic_owner_flow.move ((Object?) owner ?? (Object) place, ((CoreLocalPlace) place).name, construction.span);
				}
				enum_reservations.remove_index (reservation_depth);
			}
			return;
		}
		var call = producer as CoreEnumCallResult;
		if (call == null || call.target == null || (call.type_arguments == null ? call.target.return_type != expected : !((CoreGenericFunction) call.target).substitution (call.type_arguments).matches (call.target.return_type, expected))) {
			fail (path, "enum call producer requires its exact concrete native target and result");
		}
		verify_call (call.target, call.arguments, function, path, call.receiver, false, call.type_arguments);
	}

	private bool verify_enum_statement(CoreStatement statement, CoreFunction function, CoreBlock scope, string path) throws CoreError {
		var acquisition = statement as CoreAcquireEnumParameter;
		if (acquisition != null) {
			if (scope != function.body || !(acquisition.parameter.semantic_type is EnumType) || owners.lookup (acquisition.parameter) != function || acquisition.destination.incoming_parameter != acquisition.parameter || acquisition.destination.semantic_type != acquisition.parameter.semantic_type || initialized.contains (acquisition.destination)) {
				fail (path, "enum parameter acquisition requires its exact fresh read-only entry local");
			}
			verify_place (acquisition.destination, function, false, path);
			initialized.insert (acquisition.destination, acquisition.destination);
			available.insert (acquisition.destination, acquisition.destination);
			return true;
		}
		var store = statement as CoreEnumStore;
		if (store != null) {
			if (!(store.destination.semantic_type is EnumType) || (store.destination.incoming_parameter != null && !EnumValueAuthority.owns (enum_definitions.lookup ((EnumType) store.destination.semantic_type), (type) => enum_definitions.lookup (type))) || (store.initializes_destination && initialized.contains (store.destination))) {
				fail (path, "enum store requires exact mutable local storage and explicit initialization");
			}
			if (enum_views.contains (store.destination) || enum_inspections.find (store.destination) || enum_reservations.find (store.destination)) {
				fail (path, "enum replacement invalidates an inspection or reserved source");
			}
			verify_place (store.destination, function, !store.initializes_destination, path);
			verify_enum_producer (store.producer, (EnumType) store.destination.semantic_type, function, path);
			if (store.initializes_destination) {
				initialized.insert (store.destination, store.destination);
				available.insert (store.destination, store.destination);
			}
			if (generic_owner_flow != null && EnumValueAuthority.owns (store.producer.definition, (type) => enum_definitions.lookup (type))) {
				generic_owner_flow.owner_event (GenericOwnershipEventKind.ACQUIRE, store.destination, store.destination.name, store.span);
			}
			return true;
		}
		var returned = statement as CoreEnumReturn;
		if (returned != null) {
			if (!(function.return_type is EnumType)) {
				fail (path, "enum return requires an exact enum result signature");
			}
			verify_enum_producer (returned.producer, (EnumType) function.return_type, function, path);
			return true;
		}
		var match = statement as CoreEnumMatch;
		if (match == null) {
			return false;
		}
		verify_enum_producer (match.scrutinee, match.scrutinee.semantic_type, function, path, false, true);
		var definition = match.scrutinee.definition;
		var inspected = match.scrutinee as CoreEnumSnapshot;
		CorePlace? inspection_root = inspected != null && inspected.mode == EnumUse.INSPECT ? enum_views.lookup (inspected.source) ?? inspected.source : null;
		var selected = new HashTable<EnumVariant, bool> (direct_hash, direct_equal);
		bool fallback = false;
		var incoming_fields = field_state == null ? null : field_state.copy ();
		FieldInitializationState? joined_fields = null;
		for (uint a = 0; a < match.arms.length; a++) {
			var arm = match.arms[a];
			if (fallback) {
				fail (path, "enum match fallback must be last");
			}
			if (arm.variant == null) {
				if (selected.size () == definition.variant_count || arm.bindings.length != 0) {
					fail (path, "unreachable or payload-binding fallback");
				}
				fallback = true;
			} else {
				var variant = arm.variant;
				if (variant.identity.ordinal < 0 || variant.identity.ordinal >= definition.variant_count || definition.variant (variant.identity.ordinal) != variant || selected.contains (variant)) {
					fail (path, "enum match requires exact unique declared variants");
				}
				selected.insert (variant, true);
				int previous = -1;
				if (!arm.matches_bindings ()) {
					fail (path, "enum match lost intended selected-field/destination correspondence");
				}
				foreach (var binding in arm.bindings) {
					var field = binding.field;
					if (inspection_root != null && (field.owns_scalar || field.owns_record)) {
						fail (path, "owned enum scalar binding requires a consuming match; scalar inspection loans need separate authority");
					}
					bool owned_field = field.owns_buffer || field.owns_scalar || field.owns_record || (field.semantic_type is EnumType && EnumValueAuthority.owns (enum_definitions.lookup ((EnumType) field.semantic_type), (type) => enum_definitions.lookup (type)));
					if (inspection_root != null && owned_field) {
						if (binding.acquisition != null) {
							fail (path, "inspection cannot acquire an owning field");
						}
						enum_views.insert (binding.destination, inspection_root);
					}
					if (inspection_root == null && (field.owns_buffer || field.owns_scalar || field.owns_record) && binding.acquisition == null) {
						fail (path, "consuming buffer binding requires its exact lexical owner");
					}
					if (binding.contract.instance != match.scrutinee.instance || field.identity.ordinal <= previous || field.identity.ordinal >= variant.field_count || variant.field (field.identity.ordinal) != field || binding.destination.semantic_type != field.semantic_type || initialized.contains (binding.destination)) {
						fail (path, "selected enum field/binding correspondence mismatch");
					}
					previous = field.identity.ordinal;
					if (binding.acquisition != null) {
						if ((!field.owns_buffer && !field.owns_scalar && !field.owns_record) || owned_places.lookup (binding.destination) != binding.acquisition || binding.acquisition.scope != arm.body || !matches_cleanup (field.semantic_type, binding.acquisition.cleanup)) {
							fail (path, "owning enum binding requires exact field cleanup and arm lifetime");
						}
						if (field.owns_record) {
							record_boundary_events (GenericOwnershipEventKind.ACQUIRE, binding.acquisition, binding.span);
						} else if (generic_owner_flow != null) {
							generic_owner_flow.owner_event (GenericOwnershipEventKind.ACQUIRE, binding.acquisition, binding.destination.name, binding.span);
						}
					}
					if (field.owns_scalar && binding.acquisition != null && (binding.acquisition.cleanup.is_heap_object != field.owns_child || (field.owned_cleanup != null && binding.acquisition.cleanup.external_symbol != field.owned_cleanup.external_symbol))) {
						fail (path, "enum scalar binding changed its original Resource or heap Class cleanup");
					}
					verify_place (binding.destination, function, false, path);
					if (field.semantic_type.is_struct_storage ()) {
						initialize_struct_place (binding.destination, function);
					} else {
						initialized.insert (binding.destination, binding.destination);
						available.insert (binding.destination, binding.destination);
					}
				}
			}
			if (incoming_fields != null) {
				field_state = incoming_fields.copy ();
			}
			if (generic_owner_flow != null && a + 1 < match.arms.length) {
				generic_owner_flow.begin (GenericOwnershipEventKind.CHOICE, match.span, -1);
			}
			if (inspection_root != null) {
				enum_inspections.add (inspection_root);
			}
			verify_block (arm.body, function, path + "/arm");
			if (inspection_root != null) {
				enum_inspections.remove_index (enum_inspections.length - 1);
			}
			foreach (var binding in arm.bindings) {
				enum_views.remove (binding.destination);
			}
			if (generic_owner_flow != null && a + 1 < match.arms.length) {
				generic_owner_flow.arm (1);
			}
			if (field_state != null) {
				joined_fields = joined_fields == null ? field_state : FieldInitializationState.join (joined_fields, field_state);
			}
			foreach (var binding in arm.bindings) {
				available.remove (binding.destination);
				foreach (var projection in function.field_places) {
					if (projection.root_local () == binding.destination) {
						available.remove (projection);
					}
				}
			}
		}
		if (generic_owner_flow != null) {
			for (uint a = 1; a < match.arms.length; a++) {
				generic_owner_flow.end ();
			}
		}
		if (match.arms.length == 0 || (!fallback && selected.size () != definition.variant_count)) {
			fail (path, "enum match is not exhaustive");
		}
		if (incoming_fields != null) {
			field_state = joined_fields;
		}
		return true;
	}

	private bool is_catch_binding(CoreLocalPlace? place) {
		foreach (var binding in caught_exceptions) {
			if (binding == place) {
				return true;
			}
		}
		return false;
	}

	private void verify_exception_effect(ClassType bound, CoreFunction function, string path) throws CoreError {
		for (int i = (int) exception_handlers.length - 1; i >= 0; i--) {
			var scope = exception_handlers[i];
			scope.effects.add (bound);
			foreach (var caught in scope.bounds) {
				if (bound.derives_from (caught)) {
					return;
				}
			}
		}
		if (function.throws_type != null && bound.derives_from (function.throws_type)) {
			return;
		}
		fail (path, "checked exception bound lacks an ancestor catch or compatible throws declaration");
	}

	private void verify_exception_cleanup(CoreCleanupContract cleanup, string path) throws CoreError {
		if (!cleanups.contains (cleanup) || !cleanup.is_heap_object || cleanup.object_class == null || !cleanup.object_class.exception_root) {
			fail (path, "exception channel requires the exact nominated root heap cleanup");
		}
	}

	// Compound verification recurses without retaining the large scalar verifier frame.
	private void verify_statement_body(CoreStatement statement, CoreFunction function, CoreBlock scope, string path) throws CoreError {
		if (statement is CoreForeignSignalReturn) {
			var binding = ((CoreForeignSignalReturn) statement).binding;
			var method = function as CoreMethod;
			var owner = method == null ? null : method.declaring_type as CoreClass;
			if (!binding.valid () || owner == null || owner.foreign_export == null || owner.foreign_export.identity () != binding.root.identity () || CoreForeignApi.target (owner, binding.member) != function || !CoreForeignApi.valid (owner, code_program) || function.body != scope || function.body.statements[function.body.statements.length - 1] != statement) {
				fail (path, "native signal lost its exact shared receiver, signature, member or intrinsic body authority");
			}
			for (int n = 0; n + 1 < function.body.statements.length; n++) {
				if (!(function.body.statements[n] is CoreAcquireStructParameter)) {
					fail (path, "native signal permits only its exact copied parameter prologue");
				}
			}
			return;
		}
		if (statement is CoreForeignReturn) {
			var imported = (CoreForeignReturn) statement;
			var types = new GenericArray<SemanticType> ();
			var contracts = new GenericArray<PointerParameterContract> ();
			foreach (var parameter in function.parameters) {
				if (parameter.semantic_type.is_struct_storage () && (parameter.struct_value_contract == null || parameter.struct_value_contract.mode != StructValueMode.COPY_VALUE)) {
					fail (path, "CImport POD requires an exact copied native parameter");
				}
			}
			if (function.return_type.is_struct_storage () && (function.struct_result_contract == null || function.struct_result_contract.mode != StructValueMode.COPY_VALUE)) {
				fail (path, "CImport POD requires an exact copied native result");
			}
			foreach (var p in function.parameters) {
				types.add (p.semantic_type);
				contracts.add (p.pointer_contract);
			}
			if (!ForeignImportTypes.signature (imported.binding, function.name, function.return_type, function.result_contract, function.owned_cleanup == null ? "" : function.owned_cleanup.external_symbol, function.throws_type, types, contracts, (type) => CoreForeignApi.record (code_program, type), null, (type) => { var handle = handles.lookup (type); return handle == null ? null : handle.c_import; }) || !ForeignApiTypes.errors (imported.binding.member, function.throws_type, (name) => { foreach (var type in structs.get_keys ()) {
																																																																																																																												if (type is ClassType && type.nominal_name () == name) {
																																																																																																																													return (ClassType) type;
																																																																																																																												}
																																																																																																																											}
				                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            return null; })) {
				fail (path, "CImport lost its exact nominal member/signature/ownership/throws authority");
			}
			types.remove_range (0, types.length);
			contracts.remove_range (0, contracts.length);
			var factory = imported.factory;
			foreach (var p in factory.parameters) {
				types.add (p.semantic_type);
				contracts.add (p.pointer_contract);
			}
			if (!functions.contains (factory) || !ForeignImportTypes.factory (imported.binding, factory.name, factory.return_type, function.throws_type, factory.result_contract == ResultOwnershipContract.OWNED_TRANSFER, factory.heap_result, factory.throws_type, types, contracts)) {
				fail (path, "CImport lost its exact owned heap exception factory");
			}
			int prologue = 0, transfers = 0;
			foreach (var parameter in function.parameters) {
				if (parameter.struct_value_contract != null) {
					prologue++;
				}
				if (parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER) {
					prologue++;
					if (transfers >= imported.consumed.length || transfers >= function.owned_locals.length || imported.consumed[transfers] != function.owned_locals[transfers] || imported.consumed[transfers].place.incoming_parameter != parameter) {
						fail (path, "CImport lost exact ordered owned-parameter consumption");
					}
					transfers++;
				}
			}
			if (transfers != imported.consumed.length || transfers != function.owned_locals.length) {
				fail (path, "CImport consumed inventory differs from owned parameters");
			}
			if (function.body.statements.length != prologue + 1 || function.body.statements[prologue] != statement || function.locals.length != prologue) {
				fail (path, "CImport adapter requires exact copied-parameter acquisitions followed by one typed return");
			}
			return;
		}

		if (statement is CoreTry) {
			verify_compound_try (statement, function, scope, path);
			return;
		}
		if (statement is CoreWithScope) {
			verify_compound_with (statement, function, scope, path);
			return;
		}
		if (statement is CoreWhile) {
			verify_compound_loop (statement, function, scope, path);
			return;
		}
		if (statement is CoreIf) {
			verify_compound_if (statement, function, scope, path);
			return;
		}
		if (statement is CoreScope) {
			verify_block (((CoreScope) statement).body, function, path + "/scope");
			return;
		}
		if (verify_enum_statement (statement, function, scope, path)) {
			return;
		}
		verify_simple_statement (statement, function, scope, path);
	}

	private void verify_compound_try(CoreStatement statement, CoreFunction function, CoreBlock scope, string path) throws CoreError {
		if (statement is CoreTry) {
			if (!((CoreTry) statement).matches_catches ()) {
				fail (path, "protected group lost exact source-ordered handler and binding association");
			}
			var guarded = (CoreTry) statement;
			verify_exception_cleanup (guarded.cleanup, path);
			var handler = new CoreExceptionHandlerScope ();
			var bounds = handler.bounds;
			foreach (var caught in guarded.catches) {
				var type = caught.binding.semantic_type as ClassType;
				if (type == null || !type.derives_from ((ClassType) guarded.cleanup.object_class.semantic_type) || initialized.contains (caught.binding) || owned_places.contains (caught.binding)) {
					fail (path, "catch requires a fresh borrowed binding with exact exception subtype");
				}
				foreach (var prior in bounds) {
					if (type.derives_from (prior)) {
						fail (path, "unreachable ordered subtype catch");
					}
				}
				bounds.add (type);
			}
			if (generic_owner_flow != null) {
				generic_owner_flow.begin_try (guarded.span, bounds);
			}
			exception_handlers.add (handler);
			verify_block (guarded.body, function, path + "/protected");
			exception_handlers.remove_index (exception_handlers.length - 1);
			int catch_index = 0;
			foreach (var caught in guarded.catches) {
				if (generic_owner_flow != null) {
					generic_owner_flow.arm (catch_index + 1);
				}
				caught_effects.insert (caught.binding, handler.incoming (catch_index++));
				verify_place (caught.binding, function, false, path + "/binding");
				initialized.insert (caught.binding, caught.binding);
				available.insert (caught.binding, caught.binding);
				caught_exceptions.add (caught.binding);
				verify_block (caught.body, function, path + "/catch");
				caught_exceptions.remove_index (caught_exceptions.length - 1);
				available.remove (caught.binding);
			}
			if (generic_owner_flow != null) {
				generic_owner_flow.end ();
			}
			return;
		}
	}

	private void verify_compound_with(CoreStatement statement, CoreFunction function, CoreBlock scope, string path) throws CoreError {
		if (statement is CoreWithScope) {
			var scoped = (CoreWithScope) statement;
			var contract = scoped.contract;
			if (function.async_body != null || function is CoreGenericFunction || contract == null || contract.receiver_type.mode != ReceiverMode.LIVE || contract.receiver_type.instance_type != scoped.source.semantic_type) {
				fail (path, "with scope requires an exact live receiver contract");
			}
			if (!receiver_types.contains (scoped.source.semantic_type)) {
				receiver_types.insert (scoped.source.semantic_type, contract.receiver_type);
			}
			if (contract == null || contract.source != scoped.source || !(scoped.source.semantic_type is ClassType) || local_owners.lookup (scoped.source) != function || !owned_places.contains (scoped.source) || contract.receiver_type != receiver_types.lookup (scoped.source.semantic_type) || active_with.find (contract)) {
				fail (path, "with scope lost its exact owned receiver/capture authority");
			}
			verify_value (new CoreLoadValue (scoped.span, scoped.source), function, path + "/capture", null, false, null, false, true);
			active_with.add (contract);
			verify_block (scoped.body, function, path + "/with");
			active_with.remove_index (active_with.length - 1);
			return;
		}
	}

	private void verify_compound_loop(CoreStatement statement, CoreFunction function, CoreBlock scope, string path) throws CoreError {
		var loop = statement as CoreWhile;
		if (loop != null) {
			if (loop.has_sequence != (loop.sequence != null)) {
				fail (path, "foreach lost its sequence authority");
			}
			if (loop.sequence != null) {
				verify_sequence_shape (loop, function, path);
			}
			if (loop.has_iteration != (loop.iteration != null)) {
				fail (path, "foreach lost its iteration authority");
			}
			if (loop.iteration != null) {
				verify_iteration_shape (loop, function, path);
			}
			if (loop.has_step != (loop.step != null)) {
				fail (path, "loop lost its required step block");
			}
			if (loop.target == null || loop_owners.contains (loop.target)) {
				fail (path, "missing or repeated loop-target identity");
			}
			if (loop.target.ordinal != next_loop_ordinal++) {
				fail (path, "loop-target ordinal must follow function-local source traversal order");
			}
			loop_owners.insert (loop.target, function);
			if (generic_owner_flow != null) {
				generic_owner_flow.begin (GenericOwnershipEventKind.LOOP, loop.span, -1, loop.target);
			}
			verify_value (loop.condition, function, path + "/condition");
			if (loop.condition.semantic_type.kind != TypeKind.BOOL) {
				fail (path + "/condition", "while condition must have type 'bool'");
			}
			// Validate an already resolved identity's region; never select a
			// target from nesting or replace the transfer's supplied target.
			active_targets.insert (loop.target, loop.target);
			var before_loop = field_state == null ? null : field_state.copy ();
			if (field_state != null && loop.condition is CoreBooleanValue && ((CoreBooleanValue) loop.condition).literal == BooleanLiteral.FALSE) {
				field_state.reachable = false;
			}
			if (generic_owner_flow != null) {
				generic_owner_flow.arm (1, generic_truth (loop.condition));
			}
			if (loop.iteration != null) {
				active_iterations.add (loop.iteration);
				pending_field_borrows.add (loop.iteration.store.field.containing_type.semantic_type);
			}
			if (loop.sequence != null) {
				active_sequences.add (loop.sequence);
			}
			verify_block (loop.body, function, path + "/body");
			if (loop.step != null) {
				if (loop.step.statements.length != 1 || !(loop.step.statements[0] is CoreStore || loop.step.statements[0] is CoreCallStatement || loop.step.statements[0] is CoreCCallStatement || loop.step.statements[0] is CoreOwnershipRearm || loop.step.statements[0] is CoreStructCopy || loop.step.statements[0] is CoreEnumStore || loop.step.statements[0] is CoreSlotsReplace || loop.step.statements[0] is CoreSlotsAppend)) {
					fail (path + "/step", "for step requires exactly one assignment or call");
				}
				if (generic_owner_flow != null) {
					generic_owner_flow.arm (2);
				}
				var prior_step = iteration_step;
				iteration_step = loop.iteration;
				var prior_sequence_step = sequence_step;
				sequence_step = loop.sequence;
				verify_block (loop.step, function, path + "/step");
				iteration_step = prior_step;
				sequence_step = prior_sequence_step;
			}
			if (generic_owner_flow != null) {
				generic_owner_flow.end ();
			}
			if (loop.iteration != null) {
				pending_field_borrows.remove_index (pending_field_borrows.length - 1);
				active_iterations.remove_index (active_iterations.length - 1);
			}
			if (loop.sequence != null) {
				active_sequences.remove_index (active_sequences.length - 1);
			}
			active_targets.remove (loop.target);
			if (before_loop != null) {
				field_state = before_loop;
				if (loop.condition is CoreBooleanValue && ((CoreBooleanValue) loop.condition).literal == BooleanLiteral.TRUE && !constructor_breaks.contains (loop.target)) {
					field_state.reachable = false;
				}
			}
			return;
		}
	}

	private void verify_compound_if(CoreStatement statement, CoreFunction function, CoreBlock scope, string path) throws CoreError {
		var conditional = statement as CoreIf;
		if (conditional != null) {
			verify_value (conditional.condition, function, path + "/condition");
			if (conditional.condition.semantic_type.kind != TypeKind.BOOL) {
				fail (path + "/condition", "if condition must have type 'bool'");
			}
			var incoming_fields = field_state == null ? null : field_state.copy ();
			if (field_state != null && conditional.condition is CoreBooleanValue && ((CoreBooleanValue) conditional.condition).literal == BooleanLiteral.FALSE) {
				field_state.reachable = false;
			}
			if (generic_owner_flow != null) {
				generic_owner_flow.begin (GenericOwnershipEventKind.CHOICE, conditional.span, generic_truth (conditional.condition));
			}
			verify_block (conditional.then_block, function, path + "/then");
			if (generic_owner_flow != null) {
				generic_owner_flow.arm (1);
			}
			var then_fields = field_state;
			field_state = incoming_fields;
			if (field_state != null && conditional.condition is CoreBooleanValue && ((CoreBooleanValue) conditional.condition).literal == BooleanLiteral.TRUE) {
				field_state.reachable = false;
			}
			if (conditional.else_block != null) {
				verify_block (conditional.else_block, function, path + "/else");
			}
			if (generic_owner_flow != null) {
				generic_owner_flow.end ();
			}
			if (field_state != null) {
				field_state = FieldInitializationState.join (then_fields, field_state);
			}
			return;
		}
	}

	private void verify_simple_statement(CoreStatement statement, CoreFunction function, CoreBlock scope, string path) throws CoreError {
		if (statement is CoreStore) {
			with_mutation (((CoreStore) statement).target, path);
		}
		if (statement is CoreOwnedFieldTransfer) {
			with_mutation (((CoreOwnedFieldTransfer) statement).destination, path);
			verify_iteration_consumption (((CoreOwnedFieldTransfer) statement).source, path);
		}
		if (statement is CoreOwnershipRearm) {
			with_mutation (((CoreOwnershipRearm) statement).owner.place, path);
			verify_iteration_consumption (((CoreOwnershipRearm) statement).source, path);
			verify_iteration_consumption (((CoreOwnershipRearm) statement).owner, path);
		}
		if (statement is CoreOwnedBufferExchange && active_with.length != 0) {
			fail (path, "with receiver scope excludes buffer exchange");
		}
		if (statement is CoreOwnershipRelease) {
			verify_iteration_consumption (((CoreOwnershipRelease) statement).owner, path);
		}
		if (statement is CoreOwnershipTransfer) {
			verify_iteration_consumption (((CoreOwnershipTransfer) statement).source, path);
		}
		if (statement is CoreOwnershipReturn) {
			verify_iteration_consumption (((CoreOwnershipReturn) statement).source, path);
		}
		if (statement is CoreVectorMemoryStatement) {
			verify_value (((CoreVectorMemoryStatement) statement).operation, function, path + "/vector-store");
			return;
		}
		if (statement is CoreThrow) {
			var thrown = (CoreThrow) statement;
			verify_exception_cleanup (thrown.cleanup, path);
			var type = thrown.source.semantic_type as ClassType;
			if (type == null || !type.derives_from ((ClassType) thrown.cleanup.object_class.semantic_type)) {
				fail (path, "throw requires an exact exception subtype");
			}
			verify_place (thrown.source, function, true, path);
			if (thrown.rethrows) {
				if (caught_exceptions.length == 0 || caught_exceptions[caught_exceptions.length - 1] != thrown.source) {
					fail (path, "bare throw requires exact nearest catch identity");
				}
			} else if (thrown.owner.place != thrown.source || owned_places.lookup (thrown.source) != thrown.owner || !thrown.owner.cleanup.is_heap_object) {
				fail (path, "throw move requires an exact unique heap owner");
			}
			if (thrown.rethrows) {
				foreach (var effect in caught_effects.lookup (thrown.source)) {
					verify_exception_effect (effect, function, path);
					if (generic_owner_flow != null) {
						generic_owner_flow.effect (effect, thrown.span, true);
					}
				}
			} else {
				verify_exception_effect (type, function, path);
				if (generic_owner_flow != null) {
					generic_owner_flow.effect (type, thrown.span, true);
				}
			} return;
		}
		var exchange = statement as CoreOwnedBufferExchange;
		if (exchange != null) {
			verify_iteration_consumption (exchange.left.owner, path);
			verify_iteration_consumption (exchange.right.owner, path);
			verify_buffer_owner_slot (exchange.left, function, path + "/left");
			verify_buffer_owner_slot (exchange.right, function, path + "/right");
			if (exchange.left.place.semantic_type != exchange.right.place.semantic_type || exchange.left.cleanup != exchange.right.cleanup) {
				fail (path, "buffer exchange requires identical element and cleanup contracts");
			}
			return;
		}
		if (statement is CoreAcquireStructParameter) {
			var acquisition = (CoreAcquireStructParameter) statement;
			var parameter = acquisition.parameter;
			if (scope != function.body || owners.lookup (parameter) != function || parameter.struct_value_contract == null || acquisition.destination.incoming_parameter != parameter || acquisition.destination.semantic_type != parameter.semantic_type || initialized.contains (acquisition.destination)) {
				fail (path, "struct parameter acquisition requires its exact fresh entry local and COPY_VALUE contract");
			}
			if (parameter.struct_value_contract.mode == StructValueMode.MOVE_VALUE) {
				var owner = owned_places.lookup (acquisition.destination);
				if (owner == null || owner.scope != scope || owner.record_fields.length == 0) {
					fail (path, "MOVE_VALUE parameter requires its exact root and leaf cleanup responsibility");
				}
			}
			verify_copy_place (acquisition.destination, function, false, path);
			initialize_struct_place (acquisition.destination, function);
			return;
		}
		if (statement is CoreStructReturn) {
			if (function.struct_result_contract == null || function is CoreConstructor || function is CoreDestructor) {
				fail (path, "struct return requires an exact COPY_VALUE result contract");
			}
			verify_struct_producer (((CoreStructReturn) statement).producer, function.return_type, function, path, false, function.result_contract == ResultOwnershipContract.RECEIVER_BORROW);
			return;
		}
		if (statement is CoreStructResultStore) {
			var store = (CoreStructResultStore) statement;
			if (store.producer.contract.mode == StructValueMode.MOVE_VALUE) {
				var owner = owned_places.lookup (store.destination);
				var field = store.destination as CoreIndirectFieldPlace;
				bool record_field = field != null && field.field.containing_type is CoreClass && field.field.owned_cleanup != null && field.field.owned_cleanup.record_type != null && field.field.owned_cleanup.record_type.semantic_type == field.semantic_type;
				if (!record_field && (!store.initializes_destination || owner == null || owner.scope != scope || owner.record_fields.length == 0)) {
					fail (path, "MOVE_VALUE result requires a fresh local or exact owning Class field with complete root/leaf responsibility");
				}
			}
			require_mutable_struct_place (store.destination, path);
			if (store.initializes_destination && !fresh_struct_destination (store.destination, function)) {
				fail (path, "struct result initialization requires a fresh local or exact constructor field");
			}
			verify_copy_place (store.destination, function, !store.initializes_destination, path + "/destination");
			var borrow = place_field_borrow (store.destination);
			if (borrow != null) {
				pending_field_borrows.add (borrow.source.field.containing_type.semantic_type);
			}
			verify_struct_producer (store.producer, store.destination.semantic_type, function, path + "/producer");
			if (borrow != null) {
				pending_field_borrows.remove_index (pending_field_borrows.length - 1);
			}
			if (store.initializes_destination) {
				initialize_struct_place (store.destination, function);
			}
			return;
		}
		if (statement is CoreStructAcquire) {
			var acquire = (CoreStructAcquire) statement;
			var owner = acquire.owner;
			var field = acquire.field.field;
			bool ordered = false;
			foreach (var obligation in owner.record_fields) {
				if (obligation == acquire.field) {
					ordered = true;
					break;
				}
				if (!initialized.contains (obligation)) {
					fail (path, "record acquisition lost written initialized prefix");
				}
			}
			if (!ordered) {
				fail (path, "record acquisition missing from field obligation plan");
			}
			if (record_field (owner.place.semantic_type) == null || field.owned_cleanup == null || acquire.field != record_projection (acquire.field.aggregate, field, function) || acquire.field.root_local () != owner.place || owned_places.lookup (owner.place) != owner || owner.scope != scope || initialized.contains (acquire.field) || ((acquire.source == null) == (acquire.producer == null))) {
				fail (path, "record acquire requires exact fresh Resource field obligation and lexical owner");
			}
			if (acquire.source != null) {
				verify_place (acquire.source.place, function, true, path);
				if (owned_places.lookup (acquire.source.place) != acquire.source || acquire.source.place.semantic_type != field.semantic_type || acquire.source.cleanup != field.owned_cleanup) {
					fail (path, "record incoming move requires exact scalar Resource owner");
				}
			} else {
				if (!(acquire.producer is CoreCallValue || acquire.producer is CoreCCallValue || acquire.producer is CoreInvocation || (field.owned_cleanup.is_buffer && acquire.producer is CoreOwnedBufferAllocate)) || acquire.producer.semantic_type != field.semantic_type) {
					fail (path, "record incoming producer requires exact owned Resource result");
				}
				verify_value (acquire.producer, function, path, field.owned_cleanup);
			}
			initialized.insert (acquire.field, acquire.field);
			available.insert (acquire.field, acquire.field);
			return;
		}
		if (statement is CoreStructMove) {
			var move = (CoreStructMove) statement;
			var field = record_field (move.source.place.semantic_type);
			if (field == null || move.source == move.destination || move.source.place.semantic_type != move.destination.place.semantic_type || !matches_cleanup (move.source.place.semantic_type, move.source.cleanup) || move.destination.cleanup != move.source.cleanup || owned_places.lookup (move.source.place) != move.source || owned_places.lookup (move.destination.place) != move.destination || move.destination.scope != scope || initialized.contains (move.destination.place)) {
				fail (path, "record move requires exact distinct owners and fresh complete destination");
			}
			if (move.source.record_fields.length != move.destination.record_fields.length) {
				fail (path, "record move lost field obligation order");
			}
			for (int i = 0; i < move.source.record_fields.length; i++) {
				if (!move.source.record_fields[i].storage_path ().same_path (move.destination.record_fields[i].storage_path ())) {
					fail (path, "record move must preserve written acquisition/retirement paths and order");
				}
			}
			verify_place (move.source.place, function, true, path);
			foreach (var place in function.field_places) {
				if (place.root_local () == move.destination.place) {
					initialized.insert (place, place);
					available.insert (place, place);
				}
			}
			initialized.insert (move.destination.place, move.destination.place);
			available.insert (move.destination.place, move.destination.place);
			return;
		}
		if (statement is CoreRecordTake) {
			var take = (CoreRecordTake) statement;
			var field = take.field;
			if (pending_record_borrows.find (take.source.place)) {
				fail (path, "record field extraction overlaps an active borrowed record argument");
			}
			if (owned_places.lookup (take.source.place) != take.source || take.source.record_fields.length == 0 || !take.source.record_fields.find (field) || field.root_local () != take.source.place || field.field.owned_cleanup == null || record_projection (field.aggregate, field.field, function) != field || owned_places.lookup (take.destination.place) != take.destination || take.destination.scope != scope || take.destination.cleanup != field.field.owned_cleanup || take.destination.place.semantic_type != field.semantic_type || initialized.contains (take.destination.place)) {
				fail (path, "record field take requires exact source projection, cleanup and fresh destination ownership");
			}
			verify_place (field, function, true, path + "/field");
			initialized.insert (take.destination.place, take.destination.place);
			available.insert (take.destination.place, take.destination.place);
			return;
		}
		if (statement is CoreRecordReplace) {
			var replace = (CoreRecordReplace) statement;
			var field = replace.field;
			if (pending_record_borrows.find (replace.owner.place)) {
				fail (path, "record field replacement overlaps an active borrowed record argument");
			}
			if (owned_places.lookup (replace.owner.place) != replace.owner || !replace.owner.record_fields.find (field) || field.root_local () != replace.owner.place || field.field.owned_cleanup == null || record_projection (field.aggregate, field.field, function) != field || ((replace.source == null) == (replace.producer == null))) {
				fail (path, "record replacement requires exact live root, field path and one incoming owner");
			}
			verify_place (field, function, true, path + "/field");
			if (replace.source != null) {
				if (owned_places.lookup (replace.source.place) != replace.source || replace.source.cleanup != field.field.owned_cleanup || replace.source.place.semantic_type != field.semantic_type) {
					fail (path, "record replacement requires the original exact incoming owner and allocation kind");
				}
				verify_place (replace.source.place, function, true, path + "/incoming");
			} else {
				if (replace.producer.semantic_type != field.semantic_type || !(replace.producer is CoreCallValue || replace.producer is CoreCCallValue || replace.producer is CoreInvocation || (field.field.owned_cleanup.is_buffer && replace.producer is CoreOwnedBufferAllocate))) {
					fail (path, "record replacement requires an exact owned factory result or buffer allocation");
				}
				verify_value (replace.producer, function, path + "/incoming", field.field.owned_cleanup);
			}
			return;
		}
		if (statement is CoreStructCopy) {
			verify_struct_copy ((CoreStructCopy) statement, function, path);
			return;
		}
		if (statement is CoreSlotsRecordTransfer) {
			var transfer = (CoreSlotsRecordTransfer) statement;
			verify_slots_place (transfer.store, function, true, path);
			verify_slots_mutation (transfer.store, path);
			if (transfer.index != null) {
				verify_value (transfer.index, function, path);
				if (transfer.index.semantic_type.kind != TypeKind.INT) {
					fail (path, "record slot replacement requires exact I32 index");
				}
			}
			if (transfer.value.contract.mode == StructValueMode.MOVE_VALUE && !(transfer.value is CoreStructMoveProducer)) {
				fail (path, "owning record slot insertion requires an exact named move");
			}
			verify_struct_producer (transfer.value, ((OwnerSlotsType) transfer.store.semantic_type).element, function, path);
			return;
		}
		if (statement is CoreSlotsInitialize) {
			var store = ((CoreSlotsInitialize) statement).store;
			verify_slots_place (store, function, false, path);
			var receiver = store.pointer as CoreReceiverValue;
			if (field_state == null || !(function is CoreConstructor) || receiver == null || receiver.receiver != function.implicit_receiver || receiver.receiver.contract.mode != ReceiverMode.INITIALIZING || store.field.containing_type != ((CoreConstructor) function).declaring_class || active_targets.size () != 0 || field_state.is_possible (store.field.ordinal)) {
				fail (path, "owner-slot empty initialization lost exact constructor/field authority");
			}
			field_state.initialize (store.field.ordinal);
			return;
		}
		if (statement is CoreSlotsReplace) {
			var replace = (CoreSlotsReplace) statement;
			verify_slots_place (replace.store, function, true, path);
			verify_slots_mutation (replace.store, path);
			pending_field_borrows.add (replace.store.field.containing_type.semantic_type);
			verify_value (replace.index, function, path + "/index");
			pending_field_borrows.remove_index (pending_field_borrows.length - 1);
			var owner = replace.incoming;
			if (replace.index.semantic_type.kind != TypeKind.INT || owner == null || owned_places.lookup (owner.place) != owner || owner.cleanup != replace.store.field.slots_cleanup || !matches_cleanup (owner.place.semantic_type, owner.cleanup) || owner.place.semantic_type != ((OwnerSlotsType) replace.store.semantic_type).element) {
				fail (path, "owner-slot replace lost exact index/unique heap owner");
			}
			verify_place (owner.place, function, true, path);
			return;
		}
		if (statement is CoreSlotsAppend) {
			var append = (CoreSlotsAppend) statement;
			verify_slots_place (append.store, function, true, path);
			verify_slots_mutation (append.store, path);
			var owner = append.incoming;
			if (owner == null || owned_places.lookup (owner.place) != owner || owner.cleanup != append.store.field.slots_cleanup || !matches_cleanup (owner.place.semantic_type, owner.cleanup) || owner.place.semantic_type != ((OwnerSlotsType) append.store.semantic_type).element) {
				fail (path, "owner-slot append lost unique exact heap input");
			}
			verify_place (owner.place, function, true, path);
			return;
		}
		if (statement is CoreOwnedFieldTransfer) {
			var transfer = (CoreOwnedFieldTransfer) statement;
			var target = transfer.destination;
			if (target.field.requires_nonnull && !nonnull_definitions.find (function)) {
				nonnull_definitions.add (function);
			}
			var receiver = target.pointer as CoreReceiverValue;
			verify_place (target, function, false, path + "/destination");
			if (!(target.field.containing_type is CoreClass) || (!(target.semantic_type is HandleType) && !(target.semantic_type is SliceType) && !(target.semantic_type is ClassType)) || transfer.cleanup != target.field.owned_cleanup || !cleanups.contains (transfer.cleanup) || !matches_cleanup (target.semantic_type, transfer.cleanup) || ((transfer.source == null) == (transfer.producer == null))) {
				fail (path, "owned field transfer requires exact field/release identity and one incoming owner");
			}
			bool initializing = receiver != null && receiver.receiver.contract.mode == ReceiverMode.INITIALIZING;
			if (transfer.initializes != initializing) {
				fail (path, "owned field initialization and live replacement cannot be interchanged");
			}
			if (transfer.source != null) {
				var source = transfer.source;
				verify_place (source.place, function, true, path + "/source");
				if (owned_places.lookup (source.place) != source || source.cleanup != transfer.cleanup || source.place.semantic_type != target.semantic_type) {
					fail (path, "incoming named owner requires exact Resource type and cleanup identity");
				}
			} else {
				if (!(transfer.producer is CoreCallValue || transfer.producer is CoreCCallValue || (transfer.cleanup.is_buffer && (transfer.producer is CoreOwnedBufferAllocate || transfer.producer is CoreTaskAwait))) || transfer.producer.semantic_type != target.semantic_type) {
					fail (path, "incoming owner must be a direct exact owned Resource result");
				}
				allocation_containers.add (target.field.containing_type.semantic_type);
				if (transfer.cleanup.is_heap_object) {
					pending_field_borrows.add (target.field.containing_type.semantic_type);
				}
				verify_value (transfer.producer, function, path + "/incoming", transfer.cleanup);
				if (transfer.cleanup.is_heap_object) {
					pending_field_borrows.remove_index (pending_field_borrows.length - 1);
				}
				allocation_containers.remove_index (allocation_containers.length - 1);
			}
			if (initializing) {
				if (field_state == null || !(function is CoreConstructor) || receiver.receiver != function.implicit_receiver || target.field.containing_type != ((CoreConstructor) function).declaring_class || active_targets.size () != 0) {
					fail (path, "owned field initialization requires the exact constructor receiver outside loops");
				}
				if (field_state.is_possible (target.field.ordinal)) {
					fail (path, "owned field possibly initialized twice: " + target.field.name);
				}
				field_state.initialize (target.field.ordinal);
			}
			return;
		}
		if (statement is CoreFieldInitialize) {
			if (function is CoreConstructor && ((CoreConstructor) function).declaring_class.parent_class != null && !field_state.is_definite ((int) ((CoreConstructor) function).declaring_class.fields.length)) {
				fail (path, "derived fields require completed base initialization");
			}
			var initialization = (CoreFieldInitialize) statement;
			var target = initialization.target as CoreIndirectFieldPlace;
			var receiver = target == null ? null : target.pointer as CoreReceiverValue;
			if (target != null && target.field.owned_cleanup != null) {
				fail (path, "owned field initialization requires explicit ownership transfer");
			}
			if (field_state == null || receiver == null || receiver.receiver != function.implicit_receiver || target.field.containing_type != ((CoreConstructor) function).declaring_class || initialization.acquisition != null) {
				fail (path, "Field Initialize requires the exact initializing receiver and field");
				return;
			}
			if (active_targets.size () > 0) {
				fail (path, "constructor field initialization inside loop is unsupported");
			}
			verify_place (target, function, false, path + "/field");
			verify_value (initialization.value, function, path + "/value");
			if (initialization.value.semantic_type != target.semantic_type || field_state.is_possible (target.field.ordinal)) {
				fail (path, "constructor field type mismatch or possible double initialization: " + target.field.name);
			}
			field_state.initialize (target.field.ordinal);
			return;
		}
		var construction = statement as CoreObjectConstruction;
		if (construction != null) {
			var storage = construction.storage;
			if (((ClassType) storage.semantic_type).is_interface) {
				fail (path, "interface contract is nonconstructible");
			}
			var acquisition = construction.acquisition;
			if ((storage.heap_allocated && (acquisition == null || !(construction is CoreConstructorObjectInitialization))) || (acquisition != null && acquisition.cleanup.is_heap_object != storage.heap_allocated) || storage.result_candidate || storage.transferable != (acquisition != null) || owned_places.lookup (construction.target) != acquisition || (acquisition != null && (acquisition.object_storage != storage || acquisition.scope != scope || acquisition.cleanup.object_class != storage.object_class || acquisition.place != construction.target))) {
				fail (path, "transferable construction requires its exact fresh ObjectStorage, owner and cleanup contract");
			}
			if (object_owners.lookup (storage) != function || storage.scope != scope || object_constructions.contains (storage) || construction.target.semantic_type != storage.semantic_type || (!(construction is CoreConstructorObjectInitialization) && (storage.object_class.constructor != null || storage.object_class.polymorphic || construction.initializers.length != storage.object_class.fields.length)) || initialized.contains (construction.target)) {
				fail (path, "object construction requires one exact storage identity, fresh reference local and complete initialization");
			}
			var invocation = construction as CoreConstructorObjectInitialization;
			var context = invocation == null ? null : invocation.allocation_context;
			var policy = storage.object_class.allocation_policy;
			if ((policy != null && policy.kind == AllocationKind.CONTEXT) != (context != null)) {
				fail (path, "context construction lost its explicit instance selection");
			}
			if (context != null) {
				var context_type = context.semantic_type as HandleType;
				var load = context as CoreLoadValue;
				if (!(context is CoreParameterValue) && (load == null || !(load.source is CoreLocalPlace))) {
					fail (path, "context construction requires its exact named local or parameter origin");
				}
				if (!storage.heap_allocated || context_type == null || !handles.contains (context_type) || handles.lookup (context_type).context_mode != policy.context_mode || context_type.context_mode != policy.context_mode) {
					fail (path, "context allocation requires exact nominal lifetime/thread authority and heap responsibility");
				}
				if (policy.context_mode == "scoped-affine") {
					if (function.async_body != null) {
						fail (path, "scoped construction requires a synchronous backing lifetime");
					}
					if (!scoped_constructions.find (function)) {
						scoped_constructions.add (function);
					}
				}
				verify_value (context, function, path + "/context", null, true, null, true);
			}
			if (invocation != null) {
				if (invocation.constructor == null || invocation.constructor != storage.object_class.constructor || invocation.initializers.length != 0) {
					fail (path, "construction requires the exact explicit class constructor");
				}
				verify_call (invocation.constructor, invocation.arguments, function, path, new CoreStorageReceiverValue (statement.span, storage, invocation.constructor.receiver.contract), true);
			}
			verify_place (construction.target, function, false, path + "/target");
			var fields = new HashTable<CoreStructField, CoreStructField> (direct_hash, direct_equal);
			foreach (var initializer in construction.initializers) {
				verify_field_visibility (initializer.field, function, path);
				var field = initializer.field;
				if (field.containing_type != storage.object_class || field.ordinal < 0 || field.ordinal >= storage.object_class.fields.length || storage.object_class.fields[field.ordinal] != field || fields.contains (field) || initializer.value.semantic_type != field.semantic_type) {
					fail (path, "object initializer requires each exact field once with its exact type");
				}
				verify_value (initializer.value, function, path + "/field");
				fields.insert (field, field);
			}
			object_constructions.insert (storage, storage);
			initialized.insert (construction.target, construction.target);
			available.insert (construction.target, construction.target);
			return;
		}
		var array = statement as CoreArrayInitialize;
		if (array != null) {
			var type = array.storage.semantic_type as ArrayType;
			if (type == null || local_owners.lookup (array.storage) != function || initialized.contains (array.storage)) {
				fail (path, "array initialization requires unique exact local array storage");
				return;
			}
			verify_array_type (type, path);
			if (type.element_type.is_struct_storage ()) {
				if (array.elements.length != 0 || array.records.length != type.length) {
					fail (path, "record array requires exactly N complete storage entries");
				}
				for (int i = 0; i < array.records.length; i++) {
					var entry = array.records[i];
					var index = entry.target.index as CoreIntegerValue;
					if (entry.target.storage != array.storage || entry.target.array_type != type || index == null || !index.value.fits_nonnegative (i) || index.value.bits != i) {
						fail (path, "record array entries require exact ordered destination storage");
					}
					initializing_array_entry = entry.target;
					verify_place (entry.target, function, false, path + "/entry");
					initializing_array_entry = null;
					if (entry.producer != null) {
						if (entry.initializers.length != 0) {
							fail (path, "record entry has more than one initialization producer");
						}
						verify_struct_producer (entry.producer, type.element_type, function, path + "/producer");
					} else {
						verify_array_fields (entry.target, entry.target, entry.initializers, function, path + "/fields");
					}
				}
				initialized.insert (array.storage, array.storage);
				available.insert (array.storage, array.storage);
				return;
			}
			if (array.records.length != 0) {
				fail (path, "scalar array cannot carry record entries");
			}
			if (array.elements.length != type.length) {
				fail (path, "array initialization requires exactly N elements");
			}
			foreach (var element in array.elements) {
				verify_value (element, function, path + "/element");
				if (element.semantic_type != type.element_type) {
					fail (path, "array initializer element requires exact type");
				}
			}
			initialized.insert (array.storage, array.storage);
			available.insert (array.storage, array.storage);
			return;
		}
		var parameter_acquire = statement as CoreAcquireParameter;
		if (parameter_acquire != null) {
			var owner = parameter_acquire.acquisition;
			var incoming = parameter_acquire.value as CoreParameterValue;
			if (owner == null || incoming == null || owner.cleanup.is_heap_object != incoming.parameter.heap_object || owner.scope != function.body || scope != function.body || owned_places.lookup (owner.place) != owner || parameter_acquire.target != owner.place || owner.place.incoming_parameter != incoming.parameter || owners.lookup (incoming.parameter) != function || incoming.parameter.pointer_contract != PointerParameterContract.OWNED_TRANSFER || incoming.semantic_type != owner.place.semantic_type || initialized.contains (owner.place)) {
				fail (path, "owned parameter acquisition requires its exact root slot and incoming native parameter");
			}
			initialized.insert (owner.place, owner.place);
			available.insert (owner.place, owner.place);
			return;
		}
		var owned_return = statement as CoreOwnershipReturn;
		if (owned_return != null && owned_return.semantic_type.is_scoped_allocator ()) {
			fail (path, "scoped context cannot escape its lexical backing loan through a result");
		}
		if (owned_return != null) {
			if (function.owned_cleanup == null || owned_return.cleanup != function.owned_cleanup || owned_return.semantic_type != function.return_type) {
				fail (path, "owned return requires the exact function result ownership contract");
			}
			if (function.return_type is ClassType) {
				bool deferred_result = deferred_class_result (function);
				ObjectResultProvenance expected = owned_return.source != null ? returned_object_origin(function, owned_return.source)
				        : (owned_return.producer is CoreOwnedObjectResultConstruction) ? ObjectResultProvenance.RESULT_STORAGE
				        : (owned_return.producer is CoreCallValue || owned_return.producer is CoreInvocation) ? ObjectResultProvenance.FORWARDED_OWNED_RESULT : ObjectResultProvenance.NULL;
				if ((owned_return.source != null && !deferred_result && owned_return.source.cleanup.is_heap_object != function.heap_result) || !expected.is_returnable () || owned_return.provenance != expected || (owned_return.source != null && owned_return.producer != null)) {
					fail (path, "owned object return has illegal or mismatched storage provenance; callee-local storage cannot escape (expected %s, received %s)".printf (expected.label (), owned_return.provenance.label ()));
				}
				var result_construction = owned_return.producer as CoreOwnedObjectResultConstruction;
				if (result_construction != null) {
					if (result_construction.storage != function.result_storage || result_construction.semantic_type != function.return_type || result_construction.constructor == null || result_construction.constructor != function.result_storage.object_class.constructor) {
						fail (path, "result result_construction requires exact result storage and constructor class");
					}
					verify_call (result_construction.constructor, result_construction.arguments, function, path + "/result-construction", new CoreResultStorageReceiverValue (result_construction.span, result_construction.storage, result_construction.constructor.receiver.contract), true);
				} else if (owned_return.producer is CoreInvocation) {
					var invocation = (CoreInvocation) owned_return.producer;
					var acquisition = invocation.result_cleanup ();
					if (owned_return.producer.semantic_type != function.return_type || acquisition == null
					    || !acquisition.is_heap_object || !matches_cleanup (function.return_type, acquisition)
					    || !deferred_result && (!function.heap_result || function.result_storage != null || acquisition != function.owned_cleanup)) {
						fail (path, "indirect Class forwarding requires the exact heap result and cleanup contract");
					}
					verify_value (owned_return.producer, function, path + "/forwarded-result", acquisition);
				} else if (owned_return.producer != null) {
					var call = owned_return.producer as CoreCallValue;
					bool heap = call != null && call.target.heap_result;
					if (call is CoreGenericCall && (call.target.return_type is TypeParameterType || call.target.return_type is ClassType)) {
						var origin = generic_result_origins.lookup ((CoreGenericFunction) call.target);
						if (origin != null && (origin.domains & GenericResultOrigins.UNKNOWN) != 0) {
							origin = generic_result_projection.project ((CoreGenericFunction) call.target, ((CoreGenericCall) call).type_arguments);
						}
						uint domains = origin == null ? GenericResultOrigins.UNKNOWN : origin.evaluate (CoreGenericResultOrigins.heap_arguments (call.arguments));
						// An abstract call can use either provisional transport.
						// Its concrete instance must establish the actual domain.
						heap = deferred_result && (domains & GenericResultOrigins.UNKNOWN) != 0
						        ? call.result_storage == null : domains == GenericResultOrigins.HEAP;
					}
					if (call == null || !deferred_result && heap != function.heap_result
					    || call.result_storage != (heap ? null : function.result_storage) || call.semantic_type != function.return_type) {
						fail (path, "forwarded result requires same caller result storage and exact ClassType");
					}
					foreach (var argument in call.arguments) {
						var transfer = argument as CoreOwnedArgumentValue;
						if (transfer != null && transfer.semantic_type == function.return_type && transfer.source != null && transfer.source.place.incoming_parameter == null && !transfer.source.cleanup.is_heap_object) {
							fail (path, "callee-local ObjectStorage cannot escape through forwarded result argument");
						}
					}
					var acquisition = deferred_result && heap ? class_result_cleanup(call.semantic_type, true) : function.owned_cleanup;
					verify_value (call, function, path + "/forwarded-result", acquisition, false, null, false, false, true);
				}
			} else {
				if (function.owned_cleanup.is_buffer && owned_return.source == null && owned_return.producer == null) {
					fail (path, "owned buffer result requires a complete owning producer; null is not an array owner");
				}
				if (owned_return.provenance != ObjectResultProvenance.NONE || (owned_return.source != null && owned_return.producer != null)) {
					fail (path, "non-object ownership return has invalid provenance or duplicate producers");
				}
				if (ownable_parameter (function.return_type) && ((owned_return.source == null && owned_return.producer == null))) {
					fail (path, "owned T return requires incoming owner provenance or direct generic owned-result forwarding");
				}
				if (owned_return.producer != null) {
					if (!(owned_return.producer is CoreCallValue || owned_return.producer is CoreInvocation || (function.owned_cleanup.is_buffer && (owned_return.producer is CoreOwnedBufferAllocate || owned_return.producer is CoreTaskAwait))) || owned_return.producer.semantic_type != function.return_type) {
						fail (path, "owned forwarding requires exact invocation result type");
					}
					verify_value (owned_return.producer, function, path + "/forwarded-result", function.owned_cleanup);
				}
			}
			if (owned_return.source != null) {
				var source = owned_return.source;
				if (generic_owner_flow != null && tracked_owner (source)) {
					generic_owner_flow.move (source, source.place.name, owned_return.span, null, -1, true);
				}
				verify_place (source.place, function, true, path + "/source");
				bool deferred_same_type = deferred_class_result (function) && source.place.semantic_type == owned_return.semantic_type
				    && source.cleanup.is_object && source.cleanup.object_class.semantic_type == owned_return.semantic_type;
				if (owned_places.lookup (source.place) != source || (!deferred_same_type && (source.cleanup != owned_return.cleanup || source.place.semantic_type != owned_return.semantic_type) && !heap_transfer (source.place.semantic_type, source.cleanup, owned_return.semantic_type, owned_return.cleanup))) {
					fail (path, "owned return source must have the exact nominal result type and cleanup");
				}
			}
			return;
		}
		var rearm = statement as CoreOwnershipRearm;
		if (rearm != null) {
			if (rearm.owner.place.semantic_type.is_scoped_allocator ()) {
				fail (path, "scoped context cannot be rearmed");
			}
			if (generic_local_transfers.size () != 0 || (function.generic_instance != null && function.generic_instance.local_owned_parameter >= 0)) {
				fail (path, "generic local rearm remains deferred; its incoming transfer is the sole acquisition");
			}
			verify_place (rearm.owner.place, function, true, path + "/owner");
			if (owned_places.lookup (rearm.owner.place) != rearm.owner || (!rearm.owner.place.semantic_type.is_ownable_handle_type () && !rearm.cleanup.is_buffer) || !cleanups.contains (rearm.cleanup) || rearm.owner.cleanup != rearm.cleanup) {
				fail (path, "ownership rearm requires exact owned void* local and its stable cleanup contract");
			}
			if (rearm.source != null) {
				var source = rearm.source;
				verify_place (source.place, function, true, path + "/source");
				if (rearm.producer != null || source == rearm.owner || (!(source.place.semantic_type is HandleType) && !rearm.cleanup.is_buffer) || source.place.semantic_type != rearm.owner.place.semantic_type || source.cleanup != rearm.cleanup || owned_places.lookup (source.place) != source) {
					fail (path, "replacement move requires distinct exact concrete owners and one incoming responsibility");
				}
				return;
			}
			if (!(rearm.producer is CoreCallValue || rearm.producer is CoreCCallValue || rearm.producer is CoreInvocation || rearm.producer is CoreOwnedBufferAllocate || rearm.producer is CoreTaskAwait) || rearm.producer.semantic_type != rearm.owner.place.semantic_type) {
				fail (path, "rearm requires a direct owned producer of the exact owner type");
			}
			verify_value (rearm.producer, function, path + "/producer", rearm.cleanup);
			return;
		}
		var release = statement as CoreOwnershipRelease;
		if (release != null) {
			if (release.owner.place.semantic_type.is_scoped_allocator ()) {
				fail (path, "scoped context retires at its lexical scope exit");
			}
			verify_place (release.owner.place, function, true, path + "/owner");
			if (owned_places.lookup (release.owner.place) != release.owner || (!release.owner.place.semantic_type.is_ownable_handle_type () && !release.cleanup.is_buffer && !release.cleanup.is_heap_object) || !cleanups.contains (release.cleanup) || release.owner.cleanup != release.cleanup) {
				fail (path, "ownership release requires exact owned void* local and its cleanup contract");
			}
			return;
		}
		var transfer = statement as CoreOwnershipTransfer;
		if (transfer != null) {
			if (transfer.source.place.semantic_type.is_scoped_allocator ()) {
				fail (path, "scoped context cannot leave its lexical backing loan");
			}
			var source = transfer.source;
			var destination = transfer.destination;
			verify_place (source.place, function, true, path + "/source");
			verify_place (destination.place, function, false, path + "/destination");
			bool generic_local = ownable_parameter (source.place.semantic_type) || (function.generic_instance != null && (generic_local_owner (source) || source.place.incoming_parameter != null && function.generic_instance.owns_parameter (source.place.incoming_parameter.ordinal)));
			if (generic_local) {
				if (!generic_local_transfer (function, source, destination)) {
					fail (path, "generic local transfer requires exact owner identities, type and cleanup");
				}
				generic_local_transfers.insert (destination, transfer);
			}
			if ((source.place.semantic_type is ClassType && !transfer.cleanup.is_heap_object && !generic_local) || source == destination || source.place == destination.place || source.place.semantic_type != destination.place.semantic_type || owned_places.lookup (source.place) != source || owned_places.lookup (destination.place) != destination || source.cleanup != transfer.cleanup || destination.cleanup != transfer.cleanup || destination.scope != scope || initialized.contains (destination.place)) {
				fail (path, "ownership transfer requires distinct exact owners, identical cleanup contracts and a fresh destination in its lexical scope");
			}
			initialized.insert (destination.place, destination.place);
			available.insert (destination.place, destination.place);
			return;
		}
		if (statement is CoreBreak || statement is CoreContinue) {
			if (field_state != null) {
				if (field_state.reachable && statement is CoreBreak) {
					var loop = ((CoreBreak) statement).target;
					constructor_breaks.insert (loop, loop);
				}
				field_state.reachable = false;
			}
			var target = (statement is CoreBreak) ? ((CoreBreak) statement).target : ((CoreContinue) statement).target;
			if (target == null) {
				fail (path, "loop-control target is expired");
			} else if (loop_owners.lookup (target) != function) {
				fail (path, "loop-control target is not owned by the containing function");
			} else if (!active_targets.contains (target)) {
				fail (path, "loop-control target does not enclose the transfer");
			}
			return;
		}
		var c_call = statement as CoreCCallStatement;
		if (c_call != null) {
			verify_c_call (c_call.target, c_call.arguments, function, path);
			if (c_call.target.owned_cleanup != null) {
				fail (path, "owned-result call cannot be discarded");
			}
			return;
		}
		if (statement is CoreBaseLifecycleCall) {
			var call = (CoreBaseLifecycleCall) statement;
			var constructor = function as CoreConstructor;
			var cast = call.receiver as CoreClassUpcast;
			var self = cast == null ? null : cast.reference as CoreReceiverValue;
			if (constructor == null || constructor.declaring_class.parent_class == null || call.target != constructor.declaring_class.parent_class.constructor || cast == null || cast.source_class != constructor.declaring_class || cast.target_class != constructor.declaring_class.parent_class || self == null || self.receiver != constructor.receiver || field_state == null || field_state.is_possible ((int) constructor.declaring_class.fields.length) || active_targets.size () != 0) {
				fail (path, "base init requires the exact constructor receiver and one parent init outside loops");
			}
			verify_call (call.target, call.arguments, function, path, call.receiver, true);
			field_state.initialize ((int) constructor.declaring_class.fields.length);
			return;
		}
		var call = statement as CoreCallStatement;
		if (call != null) {
			if (call.target != null && call.target.struct_result_contract != null) {
				fail (path, "struct call result requires a bounded consumer");
			}
			if (call.target != null && call.target.owned_cleanup != null && !(call is CoreDiscardOwnedSuccess)) {
				fail (path, "owned-result call cannot be discarded");
			}
			if (call is CoreDiscardOwnedSuccess && (((CoreDiscardOwnedSuccess) call).cleanup != call.target.owned_cleanup || !call.target.owned_cleanup.is_buffer || call.target.throws_type == null)) {
				fail (path, "ignored success requires exact checked buffer result cleanup");
			}
			if (call is CoreGenericCallStatement) {
				verify_retained_requirements (call.target, ((CoreGenericCallStatement) call).target_requirements, path);
			}
			verify_call (call.target, call.arguments, function, path, call.receiver, false, (call is CoreGenericCallStatement) ? ((CoreGenericCallStatement) call).type_arguments : null);
			return;
		}
		if (statement is CoreStructInitialize) {
			verify_struct_initializer ((CoreStructInitialize) statement, function, scope, path);
			return;
		}
		var direct_target = (statement is CoreInitialize) ? ((CoreInitialize) statement).target : (statement is CoreStore) ? ((CoreStore) statement).target : null;
		var record_target = direct_target as CoreFieldPlace;
		if (record_target != null && record_target.field.owned_cleanup != null) {
			fail (path, "record Resource field write requires exact whole-record acquisition");
		}
		var initialization = statement as CoreInitialize;
		if (initialization != null) {
			if ((initialization.target is CoreFieldPlace && ((CoreFieldPlace) initialization.target).root_local () == null) || initialization.target is CoreIndirectFieldPlace || initialization.target is CoreDereferencePlace || initialization.target is CoreSliceElementPlace) {
				fail (path, "indirect storage cannot be initialized; use Store");
			}
			verify_type (initialization.target.semantic_type, true, path + "/target");
			verify_place (initialization.target, function, false, path + "/target");
			if (initialized.contains (initialization.target)) {
				fail (path, "local must have exactly one initialization");
			}
			reject_stored_owner (initialization.value, path);
			var owner = initialization.acquisition;
			if (owner != owned_places.lookup (initialization.target) || (owner != null && (owner.place != initialization.target || owner.scope != scope || !(initialization.value is CoreCCallValue || initialization.value is CoreCallValue || initialization.value is CoreInvocation || initialization.value is CoreSlotsTake || initialization.value is CoreOwnedBufferAllocate || initialization.value is CoreTaskAwait || initialization.value is CoreSharedOperation || initialization.value is CoreClosureBind || initialization.value is CoreScopedAllocator)))) {
				fail (path, "owned initialization requires exact binding, lexical scope and direct producer call");
			}
			if (initialization.value is CoreSlotsTake) {
				var take = (CoreSlotsTake) initialization.value;
				if (owner == null || slots_takes.contains (take)) {
					fail (path, "owner-slot take requires one fresh local acquisition");
				}
				slots_takes.insert (take, owner);
			}
			if (owner != null && owner.place.incoming_parameter == null && (ownable_parameter (owner.place.semantic_type) || function.generic_instance != null)) {
				generic_local_acquisitions.insert (owner, true);
			}
			var result_call = initialization.value as CoreCallValue;
			if (result_call != null && owner != null && owner.cleanup.is_heap_object && ((result_call is CoreGenericCall && (ownable_parameter (result_call.target.return_type) || result_call.target.return_type is ClassType)) || (result_call.target.generic_instance != null && result_call.target.generic_instance.storage.count > 0))) {
				if (heap_result_receivers.contains (result_call)) {
					fail (path, "heap generic result requires one fresh named concrete acquisition");
				}
				heap_result_receivers.insert (result_call, owner);
			}
			var scoped = initialization.value as CoreScopedAllocator;
			var scoped_type = initialization.target.semantic_type as HandleType;
			if (scoped_type != null && scoped_type.context_mode == "scoped-affine") {
				if (scoped == null || !(initialization.target is CoreLocalPlace) || owner == null || owner.scope != scope || !scoped.loan.valid () || scoped.loan.context_ordinal != owner.place.ordinal || scoped.loan.backing_ordinal != scoped.backing.ordinal || owner.place.text_extent == null || owner.place.text_extent.ordinal != scoped.loan.region_ordinal || scoped.backing.text_extent == null || !scoped.backing.text_extent.outlives (owner.place.text_extent) || scoped_contexts.contains (owner.place)) {
					fail (path, "scoped context requires one exact lexical backing-loan acquisition");
				}
			}
			verify_value (initialization.value, function, path + "/value", owner == null ? null : owner.cleanup);
			if (scoped != null) {
				scoped_contexts.insert (owner.place, scoped);
			}
			if (initialization.value.semantic_type != initialization.target.semantic_type) {
				fail (path, "initializer value type does not match target place type");
			}
			// Checking the value first also rejects loads in its own initializer.
			initialized.insert (initialization.target, initialization.target);
			available.insert (initialization.target, initialization.target);
			return;
		}
		var store = statement as CoreStore;
		if (store != null) {
			foreach (var sequence in active_sequences) {
				if (store.target == sequence_local (sequence.source) || (store.target == sequence.index && sequence_step != sequence)) {
					fail (path, "foreach cannot rebind its source or mutate its hidden index");
				}
			}
		}
		if (store != null && (!VolatileAccessContract.valid (store.volatile_access, store.volatile_enabled, store.target.semantic_type) || (store.volatile_enabled && !(store.target is CoreDereferencePlace || store.target is CoreArrayElementPlace || store.target is CoreSliceElementPlace)))) {
			fail (path, "volatile store requires its exact typed memory provenance and flag");
		}
		if (store != null) {
			foreach (var iteration in active_iterations) {
				if (store.target == iteration.index && iteration_step != iteration) {
					fail (path, "foreach body cannot mutate its hidden index");
				}
			}
		}
		if (store != null && (is_catch_binding (store.target as CoreLocalPlace) || (store.value is CoreLoadValue && is_catch_binding (((CoreLoadValue) store.value).source as CoreLocalPlace)))) {
			fail (path, "catch binding cannot be rebound or escape its borrowed scope");
		}
		if (store != null && store.target is CoreIndirectFieldPlace && ((CoreIndirectFieldPlace) store.target).field.text_snapshot) {
			fail (path, "readonly snapshot cannot be rebound");
		}
		if (store != null && enum_view_place (store.target)) {
			fail (path, "enum inspection array view is read-only");
		}
		if (store != null && store.target is CoreSliceElementPlace && ((CoreSliceElementPlace) store.target).slice_type.element_access != SliceElementAccess.READ_WRITE) {
			fail (path, "text slice descriptor elements are read-only");
		}
		if (store != null && store.target is CoreIndirectFieldPlace && ((CoreIndirectFieldPlace) store.target).field.owned_cleanup != null) {
			fail (path, "owned field replacement requires explicit ownership transfer and cleanup");
		}
		if (store != null && store.target is CoreIndirectFieldPlace && ((CoreIndirectFieldPlace) store.target).pointer.semantic_type is ReceiverType && ((ReceiverType) ((CoreIndirectFieldPlace) store.target).pointer.semantic_type).mode == ReceiverMode.INITIALIZING) {
			fail (path, "initializing receiver field writes must remain Field Initialize");
		}
		if (store != null) {
			require_mutable_struct_place (store.target, path);
			if (owned_places.contains (store.target)) {
				fail (path, "owned local reassignment/transfer is unsupported in OWN-1");
			}
			verify_type (store.target.semantic_type, true, path + "/target");
			verify_place (store.target, function, true, path + "/target");
			reject_stored_owner (store.value, path);
			var buffer_field = place_field_borrow (store.target);
			if (buffer_field != null) {
				pending_field_borrows.add (buffer_field.source.field.containing_type.semantic_type);
			}
			verify_value (store.value, function, path + "/value");
			if (buffer_field != null) {
				pending_field_borrows.remove_index (pending_field_borrows.length - 1);
			}
			if (store.value.semantic_type != store.target.semantic_type) {
				fail (path, "stored value type does not match target place type");
			}
			return;
		}
		if (function.owned_cleanup != null) {
			fail (path, "owned function requires an explicit ownership return");
		}
		if (statement is CoreReturn && function is CoreConstructor) {
			fail (path, "constructor cannot contain explicit return");
		}
		var returned = statement as CoreReturn;
		if (returned == null) {
			fail (path, "unsupported Core statement");
			return;
		}
		if (function.return_type.kind == TypeKind.VOID) {
			if (returned.value != null) {
				fail (path, "void function return must not carry a value");
			}
			return;
		}
		if (returned.value == null) {
			fail (path, "non-void function return must carry a value");
			return;
		}
		verify_value (returned.value, function, path + "/value");
		if (returned.value.semantic_type != function.return_type) {
			fail (path, "return value type does not match function return type");
		}
	}

	private void reject_stored_owner(CoreValue value, string path) throws CoreError {
		var load = value as CoreLoadValue;
		if (load != null && load.semantic_type is ClassType && owned_places.contains (load.source)) {
			fail (path, "persistent alias from transferable object owner is unsupported");
		}
	}

	private void verify_field_visibility(CoreStructField field, CoreFunction function, string path) throws CoreError {
		if (!field.is_private) {
			return;
		}
		var owner = field.containing_type as CoreClass;
		var receiver = function.implicit_receiver;
		if (owner == null || receiver == null || receiver.contract.instance_type != owner.semantic_type) {
			fail (path, "private field access requires its exact lexical declaring Class");
		}
	}

	private void verify_place(CorePlace place, CoreFunction function, bool requires_initialization, string path) throws CoreError {
		if (place is CoreLocalPlace) {
			var local = (CoreLocalPlace) place;
			if (pending_scoped_backings.find (local)) {
				fail (path, "scoped backing cannot be used during context argument evaluation");
			}
			foreach (var context in scoped_contexts.get_keys ()) {
				if (available.contains (context) && scoped_contexts.lookup (context).backing == local) {
					fail (path, "scoped backing is exclusively borrowed through context scope exit");
				}
			}
		}
		if (place.semantic_type is CallbackType) {
			fail (path, "call-scoped Callback cannot occupy storage");
		}
		var generic = place as CoreGenericStructFieldPlace;
		if (generic != null) {
			if (concrete_only) {
				fail (path, "generic field Place must be materialized before CFG");
			}
			verify_application (generic.application, path);
			var owner = generic.application.definition;
			if (generic.aggregate.semantic_type != generic.application || generic.field.definition != owner || generic.field.ordinal < 0 || generic.field.ordinal >= owner.fields.length || owner.fields[generic.field.ordinal] != generic.field || generic.semantic_type != generic.application.field_type (generic.field)) {
				fail (path, "generic projection lost its exact application, origin or substituted field type");
			}
			verify_place (generic.aggregate, function, false, path + "/base");
			verify_deferred_projection (generic, function, path);
			if (generic.root_local () == null) {
				return;
			}
		}
		var slice = place as CoreSliceElementPlace;
		if (slice != null) {
			verify_value (slice.slice, function, path + "/operand", null, false, null, false, false, false, true);
			uint loan_depth = pending_field_borrows.length;
			if (slice.slice is CoreOwnedFieldBorrow || slice.slice is CoreStructProjectionValue) {
				reserve_receiver_loans (slice.slice);
			}
			verify_value (slice.index, function, path + "/operand");
			read_buffer_place (slice);
			while (pending_field_borrows.length > loan_depth) {
				pending_field_borrows.remove_index (pending_field_borrows.length - 1);
			}
			if (slice.provenance.deep_text != slice.slice_type.deep_borrow) {
				fail (path, "text slice element requires the complete table and payload backing-origin contract");
			}
			if (slice.slice.semantic_type != slice.slice_type || place.semantic_type != slice.slice_type.element_type || !(slice.index.semantic_type is IntegerType) || !slice.provenance.is_valid () || slice.provenance.origin == DataPointerOrigin.NULL) {
				fail (path, "slice element requires exact SliceType, integer index and non-null lexical provenance");
			}
			return;
		}
		var array = place as CoreArrayElementPlace;
		if (array != null) {
			verify_array_type (array.array_type, path);
			if (array.storage.semantic_type != array.array_type || local_owners.lookup (array.storage) != function || (!available.contains (array.storage) && array != initializing_array_entry) || array.storage.is_promotable ()) {
				fail (path, "array element requires exact initialized local array storage");
			}
			verify_value (array.index, function, path + "/index");
			if (!(array.index.semantic_type is IntegerType) || place.semantic_type != array.array_type.element_type || !array.provenance.is_valid () || array.provenance.origin != DataPointerOrigin.LOCAL || array.provenance.origin_ordinal != array.storage.ordinal) {
				fail (path, "array element requires integer index, exact element type and storage provenance");
			}
			var constant = array.index as CoreIntegerValue;
			if (constant != null && (!constant.value.fits_nonnegative ((uint64) array.array_type.length - 1))) {
				fail (path, "constant array index outside bounds");
			}
			return;
		}
		var dereference = place as CoreDereferencePlace;
		if (dereference != null) {
			verify_value (dereference.pointer, function, path + "/pointer", null, false, null, false, true);
			if (!(place.semantic_type is StructType)) {
				verify_type (place.semantic_type, true, path, true);
			}
			var pointer = dereference.pointer.semantic_type as TypedPointerType;
			if (pointer == null || !pointer.pointee.is_typed_data_pointee () || pointer.pointee != place.semantic_type || !dereference.provenance.is_valid ()) {
				fail (path, "dereference place requires the exact directly dereferenceable pointee and lexical provenance");
			}
			return;
		}
		var indirect = place as CoreIndirectFieldPlace;
		if (indirect != null) {
			verify_field_visibility (indirect.field, function, path);
			var structure = indirect.field.containing_type;
			if (indirect.pointer.semantic_type is ReceiverType && !(indirect.pointer is CoreReceiverValue || indirect.pointer is CoreClassUpcast)) {
				fail (path, "receiver field access requires this identity or its exact verified ancestor upcast");
			}
			verify_value (indirect.pointer, function, path + "/pointer", null, false, null, false, true);
			if (structure == null || structs.lookup (structure.semantic_type) != structure || indirect.field.ordinal < 0 || indirect.field.ordinal >= structure.fields.length || structure.fields[indirect.field.ordinal] != indirect.field) {
				fail (path, "indirect field must have exact program-owned struct/field identity");
			}
			if (((indirect.pointer.semantic_type is ReceiverType) ? ((ReceiverType) indirect.pointer.semantic_type).instance_type != structure.semantic_type : (indirect.pointer.semantic_type is ClassType) ? indirect.pointer.semantic_type != structure.semantic_type : (!indirect.pointer.semantic_type.is_struct_pointer () || ((TypedPointerType) indirect.pointer.semantic_type).pointee != structure.semantic_type)) || place.semantic_type != indirect.field.semantic_type) {
				fail (path, "indirect field pointer pointee and scalar type must match the exact field");
			}
			return;
		}
		var recursive = place as CoreFieldPlace;
		if (recursive != null) {
			var owner = recursive.field.containing_struct;
			if (owner == null || structs.lookup (recursive.aggregate.semantic_type) != owner || recursive.field.ordinal < 0 || recursive.field.ordinal >= owner.fields.length || owner.fields[recursive.field.ordinal] != recursive.field || place.semantic_type != recursive.field.semantic_type) {
				fail (path, "field projection requires exact StructType base, field owner and result type");
			}
			verify_place (recursive.aggregate, function, false, path + "/base");
			if (recursive.root_local () == null) {
				return;
			}
			if (has_generic_base (recursive)) {
				verify_deferred_projection (recursive, function, path);
			}
		}
		if (!(place is CoreLocalPlace) && !(place is CoreStorageFieldPlace)) {
			fail (path, "unsupported Core place");
			return;
		}
		if (local_owners.lookup (place) != function) {
			fail (path, "local place is not owned by the containing function");
		}
		if (!(place.semantic_type is StructType)) {
			verify_type (place.semantic_type, true, path, true);
		}
		if (requires_initialization && place is CoreStorageFieldPlace && has_generic_base (place) && !available.contains (((CoreStorageFieldPlace) place).root_local ())) {
			fail (path, "generic struct local is unavailable until its complete field initializer finishes");
		}
		var projection = place as CoreFieldPlace;
		if (requires_initialization && projection != null) {
			var owner = owned_places.lookup (projection.root_local ());
			if (generic_owner_flow != null && owner != null && owner.record_fields.length != 0) {
				generic_owner_flow.owner_event (GenericOwnershipEventKind.READ, owner, owner.place.name, place.span);
			}
			foreach (var sibling in function.field_places) {
				if (sibling.root_local () == projection.root_local () && !available.contains (sibling)) {
					fail (path, "struct local is unavailable until its complete field initializer finishes");
				}
			}
		}
		if (requires_initialization && !available.contains (place)) {
			fail (path, "local place is used before initialization in structured statement order");
		}
	}

	private void verify_retained_requirements(CoreFunction? target, GenericArray<CoreGenericCapabilityRequirement> retained, string path) throws CoreError {
		var generic = target as CoreGenericFunction;
		if (generic == null || retained.length != generic.capability_requirements.length) {
			fail (path, "generic call lost target capability requirements");
		}
		for (int i = 0; i < retained.length; i++) {
			if (retained[i] != generic.capability_requirements[i]) {
				fail (path, "generic call requires exact ordered target capability requirements");
			}
		}
	}

	private TypeSubstitution? verify_generic_arguments(CoreFunction target, GenericArray<SemanticType>? arguments, string path) throws CoreError {
		var generic = target as CoreGenericFunction;
		if ((generic == null) != (arguments == null)) {
			fail (path, "generic call requires its exact definition and explicit type arguments");
		}
		if (generic == null) {
			return null;
		}
		if (concrete_only) {
			fail (path, "unresolved generic call must disappear before CFG");
		}
		foreach (var type in arguments) {
			verify_type (type, true, path + "/type-argument", type.is_struct_storage ());
		}
		generic.verify_capability_arguments (arguments, copy_fields, copy_premise, element_premise);
		return generic.substitution (arguments);
	}

	private void verify_field_borrow_overlap(GenericArray<CoreValue> arguments, CoreValue? receiver, string path, bool stable_observation = false, bool scoped_inspection = false) throws CoreError {
		foreach (var value in arguments) {
			var captured = value as CoreOwnedBorrowValue;
			if (captured == null || !(captured.semantic_type is CallbackType)) {
				continue;
			}
			foreach (var incoming in arguments) {
				var transfer = incoming as CoreOwnedArgumentValue;
				if (transfer != null && transfer.source == captured.source) {
					fail (path, "captured callback view overlaps transfer of its backing Closure");
				}
			}
		}

		foreach (var owner_type in pending_lazy_borrows) {
			var contract = receiver == null ? null : receiver.semantic_type as ReceiverType;
			if (!stable_observation && contract != null && OwnedChildComposition.may_invalidate (contract.instance_type, owner_type, possible_child_edges)) {
				fail (path, "lazy cache loan overlaps a containing-owner call");
			}
			foreach (var argument in arguments) {
				if (OwnedChildComposition.may_invalidate (argument.semantic_type, owner_type, possible_child_edges)) {
					fail (path, "lazy cache loan overlaps containing-owner transfer or argument");
				}
			}
		}
		foreach (var owner_type in pending_field_borrows) {
			var contract = receiver == null ? null : receiver.semantic_type as ReceiverType;
			if (!scoped_inspection && contract != null && contract.mode == ReceiverMode.LIVE && OwnedChildComposition.may_invalidate (contract.instance_type, owner_type, possible_child_edges)) {
				fail (path, "temporary field borrow overlaps a possibly aliasing live receiver");
			}
			foreach (var argument in arguments) {
				if (OwnedChildComposition.may_invalidate (argument.semantic_type, owner_type, possible_child_edges)) {
					fail (path, "temporary field borrow overlaps a possibly aliasing containing-object argument");
				}
			}
		}
	}

	private void reserve_receiver_loans(CoreValue? receiver) {
		if (receiver is CoreStructArgument) {
			var argument = (CoreStructArgument) receiver;
			var observed = argument.producer as CoreStructCallResult;
			var getter = observed == null ? null : observed.target as CorePropertyGetter;
			if (argument.producer.contract.mode == StructValueMode.BORROW_VALUE && getter != null && getter.result_contract == ResultOwnershipContract.RECEIVER_BORROW) {
				pending_field_borrows.add (getter.property_member.declaring_type.semantic_type);
				reserve_receiver_loans (observed.receiver);
			}
		} else if (receiver is CoreStructProjectionValue) {
			var projection = (CoreStructProjectionValue) receiver;
			if (projection.source.contract.mode != StructValueMode.BORROW_VALUE || !(projection.semantic_type is ClassType || projection.semantic_type is HandleType || projection.semantic_type is SliceType)) {
				return;
			}
			CoreStructProducer source = projection.source;
			while (source is CoreStructProjectionProducer) {
				source = ((CoreStructProjectionProducer) source).source;
			}
			var observed = source as CoreStructCallResult;
			var getter = observed == null ? null : observed.target as CorePropertyGetter;
			if (getter != null) {
				pending_field_borrows.add (getter.property_member.declaring_type.semantic_type);
				reserve_receiver_loans (observed.receiver);
			}
		} else if (receiver is CoreClassUpcast) {
			reserve_receiver_loans (((CoreClassUpcast) receiver).reference);
		} else if (receiver is CoreObjectReceiverValue) {
			reserve_receiver_loans (((CoreObjectReceiverValue) receiver).reference);
		} else if (receiver is CoreCallValue) {
			var observed = (CoreCallValue) receiver;
			if (observed.target.result_contract != ResultOwnershipContract.RECEIVER_BORROW) {
				return;
			}
			var property = ((CorePropertyGetter) observed.target).property_member;
			(property.is_owned_lazy ? pending_lazy_borrows : pending_field_borrows).add (property.declaring_type.semantic_type);
			reserve_receiver_loans (observed.receiver);
		} else if (receiver is CoreOwnedFieldBorrow) {
			var observed = (CoreOwnedFieldBorrow) receiver;
			pending_field_borrows.add (observed.source.field.containing_type.semantic_type);
			reserve_receiver_loans (observed.source.pointer);
		}
	}

	private void verify_call(CoreFunction? target, GenericArray<CoreValue> arguments, CoreFunction function, string path, CoreValue? receiver = null, bool construction = false, GenericArray<SemanticType>? type_arguments = null, bool task_creation = false) throws CoreError {
		if (target != null) {
			foreach (var statement in target.body.statements) {
				var imported = statement as CoreForeignReturn;
				if (imported != null && imported.binding.root.api.active_personalities == 0) {
					fail (path, "call requires unselected foreign import");
				}
			}
		}
		if (target != null) {
			foreach (var statement in target.body.statements) {
				if (!(statement is CoreForeignSignalReturn)) {
					continue;
				}
				var self = receiver as CoreReceiverValue;
				if (self == null || function.implicit_receiver == null || self.receiver != function.implicit_receiver || target.implicit_receiver.contract.instance_type != function.implicit_receiver.contract.instance_type) {
					fail (path, "signal emission requires the exact defining Class self receiver");
				}
			}
		}
		var caller_policy = function.implicit_receiver == null ? null : function.implicit_receiver.contract.instance_type as ClassType;
		var callee_policy = target == null || target.implicit_receiver == null ? null : target.implicit_receiver.contract.instance_type as ClassType;
		if (caller_policy != null && caller_policy.monitored && !(function is CoreLifecycle) && callee_policy != null && callee_policy.monitored && !(target is CoreLifecycle)) {
			var self = receiver as CoreReceiverValue;
			if (self == null || self.receiver != function.implicit_receiver) {
				fail (path, "cross-object monitor nesting requires a qualified ordered-lock operation");
			}
		}

		if (target != null) {
			foreach (var parameter in target.parameters) {
				if (parameter.requires_nonnull && !nonnull_definitions.find (function)) {
					nonnull_definitions.add (function);
				}
			}
		}
		if (target != null && (target.async_body != null) != task_creation) {
			fail (path, "ordinary call and deferred task creation require separate exact body channels");
		}
		if (target == null || !functions.contains (target)) {
			fail (path, "call target is not owned by the containing program");
			return;
		}
		bool with_alias = !construction && receiver != null && with_overlap (receiver.semantic_type);
		foreach (var argument in arguments) {
			if (with_overlap (argument.semantic_type)) {
				with_alias = true;
			}
		}
		if (with_alias) {
			readonly_inspector (target, path);
		}
		var factory_method = target as CoreMethod;
		if (factory_method != null) {
			foreach (var property in factory_method.declaring_type.properties) {
				if (property.factory == factory_method) {
					fail (path, "owning lazy factory is reserved for its exact compiler cache gate");
				}
			}
		}
		if (target.throws_type != null && !task_creation) {
			verify_exception_effect (target.throws_type, function, path);
		}
		uint reservation_depth = enum_reservations.length;
		var substitution = verify_generic_arguments (target, type_arguments, path);
		if ((target is CoreLifecycle) != construction || (construction && !(target is CoreConstructor))) {
			fail (path, "lifecycle cannot be a source call target");
		}
		var receiver_contract = target.implicit_receiver;
		if ((receiver_contract == null) != (receiver == null)) {
			fail (path, "method call requires exactly one implicit receiver; free calls have none");
		}
		if (receiver != null) {
			if (receiver.semantic_type != receiver_contract.contract || !(receiver is CoreReceiverValue || receiver is CoreAddressOfValue || receiver is CoreObjectReceiverValue || receiver is CoreClassUpcast || (construction && (receiver is CoreStorageReceiverValue || receiver is CoreResultStorageReceiverValue)))) {
				fail (path, "method call requires exact declaring receiver type and supported storage form");
			}
			verify_value (receiver, function, path + "/receiver", null, false, null, false, true);
		}
		if (arguments.length != target.parameters.length) {
			fail (path, "call argument count does not match target parameters");
		}
		var receiver_origin = receiver;
		while (receiver_origin is CoreClassUpcast) {
			receiver_origin = ((CoreClassUpcast) receiver_origin).reference;
		}
		var object_receiver = receiver_origin as CoreObjectReceiverValue;
		var receiver_load = object_receiver == null ? null : object_receiver.reference as CoreLoadValue;
		bool owned_receiver = receiver_load != null && owned_places.contains (receiver_load.source);
		if (owned_receiver) {
			active_object_receivers.add (receiver_load.source);
		}
		uint borrow_depth = pending_field_borrows.length;
		uint lazy_depth = pending_lazy_borrows.length;
		uint record_borrow_depth = pending_record_borrows.length;
		var address_receiver = receiver as CoreAddressOfValue;
		var receiver_borrow = address_receiver == null || address_receiver.receiver_place == null ? null : place_field_borrow (address_receiver.receiver_place);
		if (receiver_borrow != null) {
			pending_field_borrows.add (receiver_borrow.source.field.containing_type.semantic_type);
		}
		reserve_receiver_loans (receiver);
		// Nested argument evaluation inherits the enclosing receiver loans.
		// Reject invalidating owners before processing their transfer contracts.
		verify_field_borrow_overlap (arguments, null, path);
		for (int i = 0; i < arguments.length; i++) {
			string argument_path = path + "/argument #%d".printf (i);
			var expected = substitution == null ? target.parameters[i].semantic_type : substitution.apply (target.parameters[i].semantic_type);
			if (target.parameters[i].semantic_type is TypeParameterType && target.parameters[i].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE) {
				if (function.async_body != null) {
					fail (argument_path, "generic borrowing requires a synchronous caller; async loans and coroutine frames are deferred");
				}
				var forwarded = arguments[i] as CoreParameterValue;
				if (!GenericBorrowTypes.accepts (expected) || !(arguments[i] is CoreOwnedBorrowValue || (forwarded != null && GenericBorrowTypes.accepts (forwarded.parameter.semantic_type) && forwarded.parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE) || (arguments[i] is CoreNullPointerValue && !expected.is_parameterized ()))) {
					fail (argument_path, "generic borrowed argument requires an exact owner, borrowed T forwarding or contextual null");
				}
			}
			if (expected is EnumType) {
				var argument = arguments[i] as CoreEnumArgument;
				if (argument == null || argument.parameter != target.parameters[i]) {
					fail (argument_path, "enum argument requires its exact value parameter");
				}
				verify_enum_producer (argument.producer, (EnumType) expected, function, argument_path, true);
			} else if (expected.is_struct_storage ()) {
				var argument = arguments[i] as CoreStructArgument;
				if (argument == null || argument.parameter != target.parameters[i]) {
					fail (argument_path, "struct argument requires its exact COPY_VALUE parameter");
				}
				bool borrowing = borrowed_record_parameter (target.parameters[i]);
				if (borrowing != (argument.producer.contract.mode == StructValueMode.BORROW_VALUE)) {
					fail (argument_path, "record argument must preserve its declared copy, move or noescape borrow mode");
				}
				verify_struct_producer (argument.producer, expected, function, argument_path, true, borrowing);
				var snapshot = argument.producer as CoreStructBorrowSnapshot;
				var root = snapshot == null ? null : snapshot.source as CoreLocalPlace;
				if (borrowing && root != null) {
					pending_record_borrows.add (root);
				}
			} else if (target.parameters[i].pointer_contract == PointerParameterContract.OWNED_TRANSFER) {
				var argument = arguments[i] as CoreOwnedArgumentValue;
				bool symbolic_class = target is CoreGenericFunction && target.parameters[i].semantic_type is ClassType;
				bool generic_storage = ownable_parameter (target.parameters[i].semantic_type) || symbolic_class;
				bool heap_generic = argument != null && argument.cleanup.is_heap_object && generic_storage && !target.parameters[i].heap_object;
				if (argument != null && generic_storage && argument.semantic_type is ClassType) {
					if (!heap_generic_requests.contains (argument)) {
						heap_generic_order.add (argument);
					}
					heap_generic_requests.insert (argument, target);
				}
				if (heap_generic) {
					bool adapted_class = symbolic_class && argument.source != null && heap_transfer (argument.source.place.semantic_type, argument.source.cleanup, argument.semantic_type, argument.cleanup);
					if (function.async_body != null || argument.source == null || argument.producer != null || (!adapted_class && (argument.source.cleanup != argument.cleanup || argument.source.place.semantic_type != argument.semantic_type)) || !(argument.semantic_type is ClassType)) {
						fail (argument_path, "heap generic argument requires an exact concrete named owner and synchronous caller");
					}
					if (!heap_generic_requests.contains (argument)) {
						heap_generic_order.add (argument);
					}
					heap_generic_requests.insert (argument, target);
				}
				if (argument != null && argument.cleanup.is_buffer && argument.source == null && argument.producer == null) {
					fail (argument_path, "owned buffer argument requires a complete named owner transfer");
				}
				if (argument == null || argument.parameter != target.parameters[i] || (!heap_generic && argument.cleanup.is_heap_object != target.parameters[i].heap_object) || !cleanups.contains (argument.cleanup) || !matches_cleanup (argument.semantic_type, argument.cleanup)) {
					fail (argument_path, "owned argument requires its exact target parameter and nominal cleanup contract");
				}
				if (ownable_parameter (argument.semantic_type) && argument.source == null) {
					fail (argument_path, "generic owned argument cannot manufacture null");
				}
				if (argument.producer != null) {
					if (!task_creation || argument.source != null || argument.producer.semantic_type != expected || !(argument.producer is CoreCallValue || argument.producer is CoreCCallValue || (argument.cleanup.is_buffer && (argument.producer is CoreOwnedBufferAllocate || argument.producer is CoreTaskAwait)))) {
						fail (argument_path, "fresh capture requires one exact task creation ownership consumer");
					}
					verify_value (argument.producer, function, argument_path + "/fresh", argument.cleanup);
				}
				if (argument.source != null) {
					var selected = receiver as CoreStorageReceiverValue;
					if (selected != null && selected.storage.fallible && (argument.source.place.semantic_type != argument.semantic_type || argument.source.place.requires_nonnull || argument.source.place.incoming_parameter != null && argument.source.place.incoming_parameter.requires_nonnull)) {
						fail (argument_path, "fallible input requires an exact nullable caller slot");
					}
					if (enum_reservations.find (argument.source.place)) {
						fail (argument_path, "buffer source is reserved by an unfinished enum consumer");
					}
					if (generic_owner_flow != null && tracked_owner (argument.source)) {
						generic_owner_flow.owner_event (GenericOwnershipEventKind.READ, argument.source, argument.source.place.name, argument.span);
					}
					if (active_closure_owners.find (argument.source.place)) {
						fail (argument_path, "closure invocation cannot consume its borrowed backing owner during argument evaluation");
					}
					foreach (var active_receiver in active_object_receivers) {
						if (active_receiver == argument.source.place) {
							fail (argument_path, "method receiver cannot consume the same object owner");
						}
					}
					verify_place (argument.source.place, function, true, argument_path);
					if (target.generic_instance != null && target.generic_instance.requires_exact_source (i) && target.generic_instance.storage.is_heap (i) && argument.source.place.semantic_type != argument.semantic_type) {
						fail (argument_path, "generic owned argument requires its exact nominal source; subtype adaptation is deferred");
					}
					if (owned_places.lookup (argument.source.place) != argument.source || ((argument.source.cleanup != argument.cleanup || argument.source.place.semantic_type != argument.semantic_type) && !heap_transfer (argument.source.place.semantic_type, argument.source.cleanup, argument.semantic_type, argument.cleanup))) {
						fail (argument_path, "owned argument source must match the exact owner type and contract");
					}
				}
			} else {
				verify_value (arguments[i], function, argument_path, null, false, target.parameters[i].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE ? target.parameters[i] : null, false, false, false, false, substitution);
			}
			if (arguments[i] is CoreOwnedFieldBorrow || arguments[i] is CoreStructProjectionValue || arguments[i] is CoreStructArgument) {
				reserve_receiver_loans (arguments[i]);
			}
			if (arguments[i] is CoreCallValue && ((CoreCallValue) arguments[i]).target.result_contract == ResultOwnershipContract.RECEIVER_BORROW) {
				var property = ((CorePropertyGetter) ((CoreCallValue) arguments[i]).target).property_member;
				(property.is_owned_lazy ? pending_lazy_borrows : pending_field_borrows).add (property.declaring_type.semantic_type);
			}
			if (arguments[i] is CoreSlotsValue) {
				var slot = (CoreSlotsValue) arguments[i];
				if (slot.action == OwnerSlotsAction.BORROW) {
					if (slot.iteration != null || active_iterations.length != 0 || target.kind == CallableKind.METHOD) {
						readonly_inspector (target, path);
					}
					if ((target.kind != CallableKind.FUNCTION && target.kind != CallableKind.METHOD) || target is CoreGenericFunction || target.generic_instance != null || target.async_body != null || target.throws_type != null || !(FunctionValueType.scalar (target.return_type) || target.return_type.kind == TypeKind.VOID || target.return_type.is_struct_storage () && readonly_scalar (target.return_type))) {
						fail (path, "owner-slot inspection lost concrete synchronous copied result call authority");
					}
					pending_field_borrows.add (slot.store.field.containing_type.semantic_type);
				}
			}
			if ((substitution == null ? arguments[i].semantic_type != target.parameters[i].semantic_type : !substitution.matches (target.parameters[i].semantic_type, arguments[i].semantic_type))) {
				fail (argument_path, "call argument type does not match target parameter");
			}
		}
		if (owned_receiver) {
			active_object_receivers.remove_index (active_object_receivers.length - 1);
		}
		foreach (var value in arguments) {
			var borrow = value as CoreOwnedBufferBorrow;
			if (generic_owner_flow != null && borrow != null) {
				generic_owner_flow.owner_event (GenericOwnershipEventKind.READ, borrow.source, borrow.source.place.name, value.span);
			}
			var owner_borrow = value as CoreOwnedBorrowValue;
			if (generic_owner_flow != null && owner_borrow != null && tracked_owner (owner_borrow.source)) {
				generic_owner_flow.owner_event (GenericOwnershipEventKind.READ, owner_borrow.source, owner_borrow.source.place.name, value.span);
			}
		}
		bool scoped_indexed_receiver = false;
		if (target.kind == CallableKind.METHOD) {
			foreach (var argument in arguments) {
				var slot = argument as CoreSlotsValue;
				if (slot != null && slot.action == OwnerSlotsAction.BORROW) {
					scoped_indexed_receiver = true;
				}
			}
		}
		verify_field_borrow_overlap (arguments, receiver, path, target is CorePropertyGetter && ((CorePropertyGetter) target).property_member.is_owned_lazy, scoped_indexed_receiver || target is CorePropertyGetter && target.struct_result_contract != null && target.struct_result_contract.mode == StructValueMode.BORROW_VALUE);
		while (enum_reservations.length > reservation_depth) {
			var place = enum_reservations[reservation_depth];
			if (generic_owner_flow != null) {
				generic_owner_flow.move (place, ((CoreLocalPlace) place).name, function.span);
			}
			enum_reservations.remove_index (reservation_depth);
		}
		if (generic_owner_flow != null) {
			foreach (var value in arguments) {
				var record = value as CoreStructArgument;
				var moved = record == null ? null : record.producer as CoreStructMoveProducer;
				if (moved != null) {
					record_boundary_events (GenericOwnershipEventKind.MOVE, moved.source, moved.span);
					var selected = receiver as CoreStorageReceiverValue;
					if (selected != null && selected.storage.fallible) {
						record_boundary_events (GenericOwnershipEventKind.ACQUIRE, moved.source, moved.span);
					}
				}
				var owned = value as CoreOwnedArgumentValue;
				if (owned != null && owned.source != null && tracked_owner (owned.source)) {
					generic_owner_flow.move (owned.source, owned.source.place.name, owned.span, target, owned.parameter.ordinal);
					var selected = receiver as CoreStorageReceiverValue;
					if (selected != null && selected.storage.fallible) {
						generic_owner_flow.owner_event (GenericOwnershipEventKind.ACQUIRE, owned.source, owned.source.place.name, owned.span);
					}
				}
			}
			if (target.throws_type != null && !task_creation) {
				generic_owner_flow.effect (target.throws_type, target.span);
			}
		}
		while (pending_field_borrows.length > borrow_depth) {
			pending_field_borrows.remove_index (pending_field_borrows.length - 1);
		}
		while (pending_lazy_borrows.length > lazy_depth) {
			pending_lazy_borrows.remove_index (pending_lazy_borrows.length - 1);
		}
		while (pending_record_borrows.length > record_borrow_depth) {
			pending_record_borrows.remove_index (pending_record_borrows.length - 1);
		}
	}

	private void verify_c_call(CoreCFunction? target, GenericArray<CoreValue> arguments, CoreFunction function, string path) throws CoreError {
		if (target == null || !c_functions.contains (target)) {
			fail (path, "call target is not owned by the containing program");
			return;
		}
		if (arguments.length != target.parameter_types.length) {
			fail (path, "call argument count does not match target parameters");
		}
		uint borrow_depth = pending_field_borrows.length;
		uint lazy_depth = pending_lazy_borrows.length;
		for (int i = 0; i < arguments.length; i++) {
			string argument_path = path + "/argument #%d".printf (i);
			if (target.parameter_types[i].is_struct_storage ()) {
				var argument = arguments[i] as CoreStructArgument;
				if (argument == null || argument.parameter != target.parameters[i]) {
					fail (argument_path, "C value record requires exact parameter and producer identity");
				}
				verify_struct_producer (argument.producer, target.parameter_types[i], function, argument_path);
			} else {
				verify_value (arguments[i], function, argument_path, null, false, target.parameters[i].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE ? target.parameters[i] : null);
			}
			if (arguments[i] is CoreOwnedFieldBorrow || arguments[i] is CoreStructProjectionValue) {
				reserve_receiver_loans (arguments[i]);
			}
			if (arguments[i] is CoreCallValue && ((CoreCallValue) arguments[i]).target.result_contract == ResultOwnershipContract.RECEIVER_BORROW) {
				var property = ((CorePropertyGetter) ((CoreCallValue) arguments[i]).target).property_member;
				(property.is_owned_lazy ? pending_lazy_borrows : pending_field_borrows).add (property.declaring_type.semantic_type);
			}
			if (arguments[i].semantic_type != target.parameter_types[i]) {
				fail (argument_path, "call argument type does not match target parameter");
			}
		}
		verify_field_borrow_overlap (arguments, null, path);
		while (pending_field_borrows.length > borrow_depth) {
			pending_field_borrows.remove_index (pending_field_borrows.length - 1);
		}
		while (pending_lazy_borrows.length > lazy_depth) {
			pending_lazy_borrows.remove_index (pending_lazy_borrows.length - 1);
		}
	}

	private void verify_indirect_owned_argument(CoreValue value, CoreParameter parameter, CoreFunction function, string path) throws CoreError {
		var argument = value as CoreOwnedArgumentValue;
		if (argument == null || argument.parameter != parameter || parameter.pointer_contract != PointerParameterContract.OWNED_TRANSFER || argument.semantic_type != parameter.semantic_type || argument.producer != null || argument.cleanup.is_heap_object != parameter.heap_object || !cleanups.contains (argument.cleanup) || !matches_cleanup (argument.semantic_type, argument.cleanup)) {
			fail (path, "indirect owned argument requires its exact channel and nominal cleanup");
		}
		if (argument.source != null) {
			if (active_closure_owners.find (argument.source.place)) {
				fail (path, "indirect invocation cannot consume an active borrowed owner");
			}
			foreach (var receiver in active_object_receivers) {
				if (receiver == argument.source.place) {
					fail (path, "indirect invocation cannot consume its active receiver owner");
				}
			}
			verify_place (argument.source.place, function, true, path);
			if (owned_places.lookup (argument.source.place) != argument.source || argument.source.cleanup != argument.cleanup || argument.source.place.semantic_type != argument.semantic_type) {
				fail (path, "indirect owned argument source lost its exact type or cleanup");
			}
		}
	}

	private void commit_indirect_owned_arguments(GenericArray<CoreValue> arguments, CallableSignature signature, string path) throws CoreError {
		for (int p = 0; p < arguments.length; p++) {
			var owned = arguments[p] as CoreOwnedArgumentValue;
			if (owned == null || owned.source == null) {
				continue;
			}
			if (active_closure_owners.find (owned.source.place)) {
				fail (path, "indirect invocation cannot consume an active borrowed owner");
			}
			foreach (var receiver in active_object_receivers) {
				if (receiver == owned.source.place) {
					fail (path, "indirect invocation cannot consume its active receiver owner");
				}
			}
			if (generic_owner_flow != null && tracked_owner (owned.source)) {
				generic_owner_flow.move (owned.source, owned.source.place.name, owned.span, signature as Object, p);
			}
		}
	}

	private void verify_value(CoreValue value, CoreFunction function, string path, CoreCleanupContract? acquisition = null, bool owner_null_test = false, CoreParameter? borrowed_parameter = null, bool pointer_comparison = false, bool receiver_use = false, bool result_use = false, bool buffer_view_use = false, TypeSubstitution? borrow_substitution = null, bool record_result = false, bool effect_only = false) throws CoreError {
		if (value.semantic_type.is_scoped_allocator () && (value is CoreOwnedArgumentValue || acquisition != null && !(value is CoreScopedAllocator))) {
			fail (path, "scoped context requires one exact lexical intrinsic acquisition");
		}
		if (value is CoreScopedAllocator) {
			var scoped = (CoreScopedAllocator) value;
			var type = value.semantic_type as HandleType;
			var backing = scoped.backing.semantic_type as SliceType;
			if (type == null || type.context_mode != "scoped-affine" || type.context_cleanup != "astra_context17_destroy" || !handles.contains (type) || acquisition != scoped.cleanup || scoped.cleanup.is_object || scoped.cleanup.external_symbol != type.context_cleanup || function.async_body != null || !scoped.loan.valid () || scoped.loan.backing_ordinal != scoped.backing.ordinal || backing == null || backing.element_type.kind != TypeKind.U8 || !owned_places.contains (scoped.backing) || !owned_places.lookup (scoped.backing).cleanup.is_buffer || local_owners.lookup (scoped.backing) != function) {
				fail (path, "scoped context lost complete owned byte backing and checked release authority");
			}
			verify_place (scoped.backing, function, true, path + "/backing");
			pending_scoped_backings.add (scoped.backing);
			verify_value (scoped.kind, function, path + "/kind");
			verify_value (scoped.slots, function, path + "/slots");
			pending_scoped_backings.remove_index (pending_scoped_backings.length - 1);
			if (scoped.kind.semantic_type.kind != TypeKind.INT || scoped.slots.semantic_type.kind != TypeKind.INT) {
				fail (path, "scoped context kind and slots require int channels");
			}
			return;
		}
		if (value.semantic_type.kind == TypeKind.VOID && (value is CoreFunctionValueCall || value is CoreClosureCall) && !effect_only) {
			fail (path, "void invocation cannot define or supply a value");
		}
		if (value.semantic_type.is_struct_storage () && (value is CoreFunctionValueCall || value is CoreClosureCall) && !record_result) {
			fail (path, "indirect record result requires one exact bounded producer consumer");
		}
		// Keep recursive dispatch small on the supported normal host stack.
		if (verify_callable_value (value, function, path, acquisition, owner_null_test, borrowed_parameter, pointer_comparison, receiver_use, result_use, buffer_view_use, borrow_substitution, record_result)) {
			return;
		}
		if (verify_storage_value (value, function, path, acquisition, owner_null_test, borrowed_parameter, pointer_comparison, receiver_use, result_use, buffer_view_use, borrow_substitution, record_result)) {
			return;
		}
		if (verify_composed_value (value, function, path, acquisition, owner_null_test, borrowed_parameter, pointer_comparison, receiver_use, result_use, buffer_view_use, borrow_substitution, record_result)) {
			return;
		}
		fail (path, "unsupported Core value");
	}

	private bool verify_callable_value(CoreValue value, CoreFunction function, string path, CoreCleanupContract? acquisition, bool owner_null_test, CoreParameter? borrowed_parameter, bool pointer_comparison, bool receiver_use, bool result_use, bool buffer_view_use, TypeSubstitution? borrow_substitution, bool record_result) throws CoreError {
		if (value is CoreStructProjectionValue) {
			var projection = (CoreStructProjectionValue) value;
			if (value.semantic_type.is_struct_storage ()) {
				fail (path, "record subprojection requires a bounded producer consumer");
			}
			if (projection.source.contract.mode == StructValueMode.BORROW_VALUE && (value.semantic_type is ClassType || value.semantic_type is HandleType || value.semantic_type is SliceType) && (acquisition != null || (borrowed_parameter == null ? !owner_null_test && !receiver_use && !buffer_view_use : borrowed_parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || borrowed_parameter.semantic_type != value.semantic_type))) {
				fail (path, "owning record leaf observation requires an exact bounded borrowed use");
			}
			verify_struct_projection (projection.source, projection.path, value.semantic_type, function, path);
			return true;
		}
		if (value is CoreRetainedOperation) {
			var operation = (CoreRetainedOperation) value;
			if (!RetainedContracts.valid_action (operation.action) || !RetainedContracts.accepts (operation.action, operation.callee.semantic_type) || value.semantic_type.kind != TypeKind.INT || operation.arguments.length != RetainedContracts.arity (operation.action) || acquisition != null) {
				fail (path, "retained callback requires exact finite action and native carrier signature");
			}
			if (!thread_capture_type (((ClosureHandleType) operation.callee.semantic_type).environment_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal), false, true)) {
				fail (path, "retained callback cannot capture thread-bound state");
			}
			var load = operation.callee as CoreLoadValue;
			var parameter = operation.callee as CoreParameterValue;
			if (load == null ? parameter == null || parameter.parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE : !(load.source is CoreLocalPlace) || !owned_places.contains (load.source)) {
				fail (path, "retained callback requires a live owned local or exact borrowed carrier");
			}
			verify_value (operation.callee, function, path + "/retained", null, true, null, true);
			if (load != null) {
				active_closure_owners.add (load.source);
			}
			foreach (var argument in operation.arguments) {
				verify_value (argument, function, path + "/argument");
				if (argument.semantic_type != value.semantic_type) {
					fail (path, "retained callback int argument mismatch");
				}
			}
			if (load != null) {
				active_closure_owners.remove_index (active_closure_owners.length - 1);
			}
			return true;
		}
		if (value is CoreClosureBind) {
			var closure = (CoreClosureBind) value;
			var type = value.semantic_type as ClosureHandleType;
			var target = closure.target;
			if (type == null || !type.supported () || (type.actor ? closure.actor_binding == null || !closure.actor_binding.valid () || !thread_capture_type (type.environment_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal), true) || !thread_capture_type (type.actor_message, new HashTable<SemanticType, bool> (direct_hash, direct_equal), true) : closure.actor_binding != null || type.environment_type.concurrency_policy_identity == 16) || !closure_capture_type (type.environment_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal)) || (type.threaded && !thread_capture_type (type.environment_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal))) || acquisition != closure.cleanup || !cleanups.contains (closure.cleanup) || !matches_cleanup (type, closure.cleanup) || closure.source == null || owned_places.lookup (closure.source.place) != closure.source || !closure.source.cleanup.is_heap_object || closure.source.place.semantic_type != type.environment_type || closure.source.cleanup.object_class != closure.cleanup.closure_environment || target == null || target is CoreGenericFunction || target.generic_instance != null || target.kind != CallableKind.FUNCTION || !functions.contains (target) || target.implicit_receiver != null || target.async_body != null || target.throws_type != type.throws_type || target.result_contract != type.result_contract || target.return_type != type.result_type || (type.result_contract == ResultOwnershipContract.OWNED_TRANSFER && type.result_type is ClassType && !target.heap_result) || target.parameters.length != type.parameter_types.length + 1 || target.parameters[0].semantic_type != type.environment_type || target.parameters[0].pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
				fail (path, "closure binding requires one exact heap environment move, native code signature and environment destruction authority");
			}
			for (int p = 0; p < type.parameter_types.length; p++) {
				if (target.parameters[p + 1].semantic_type != type.parameter_types[p] || ((type.actor && type.parameter_types[p] is ClassType) ? target.parameters[p + 1].pointer_contract != PointerParameterContract.OWNED_TRANSFER || !target.parameters[p + 1].heap_object : target.parameters[p + 1].pointer_contract != type.parameter_contract (p) || CallableRecordGroups.heap_parameter (type, p) && !target.parameters[p + 1].heap_object)) {
					fail (path, "closure code scalar signature mismatch");
				}
			}
			verify_place (closure.source.place, function, true, path + "/environment");
			return true;
		}
		if (value is CoreClosureCall) {
			var call = (CoreClosureCall) value;
			var type = call.callee.semantic_type as ClosureHandleType;
			verify_invocation_result (call, type, acquisition, path);
			try {
				if (type != null) {
					type.verify_records (type.record_parameters, copy_fields);
				}
			} catch (StructLeafError error) {
				fail (path, error.message);
			}
			if (type != null && type.throws_type != null) {
				verify_exception_effect (type.throws_type, function, path);
			}
			if (type == null || type.threaded || type.actor || value.semantic_type != type.result_type || call.arguments.length != type.parameter_types.length) {
				fail (path, "closure invocation requires exact borrowed carrier and scalar signature");
			}
			var load = call.callee as CoreLoadValue;
			var parameter = call.callee as CoreParameterValue;
			if (load == null ? parameter == null || parameter.parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE : !(load.source is CoreLocalPlace) || !owned_places.contains (load.source)) {
				fail (path, "closure invocation requires an immediate live owned local or borrowed parameter");
			}
			if (call.channel_parameters.length != (type.has_owner_channels () ? type.parameter_types.length : 0)) {
				fail (path, "closure invocation lost its call-owned channel declarations");
			}
			for (int p = 0; p < call.channel_parameters.length; p++) {
				var channel = call.channel_parameters[p];
				if (channel.ordinal != p || channel.semantic_type != type.parameter_types[p] || channel.pointer_contract != type.parameter_contract (p) || channel.heap_object != CallableRecordGroups.heap_parameter (type, p) || channel.requires_nonnull) {
					fail (path, "closure channel differs from its exact signature");
				}
				verify_parameter_contract (channel, path);
			}
			uint record_depth = pending_record_borrows.length;
			uint borrow_depth = pending_field_borrows.length;
			uint lazy_depth = pending_lazy_borrows.length;
			uint named_depth = active_closure_owners.length;
			verify_value (call.callee, function, path + "/closure", null, true, null, true);
			if (load != null) {
				active_closure_owners.add (load.source);
			}
			for (int p = 0; p < call.arguments.length; p++) {
				if (type.parameter_types[p].is_struct_storage ()) {
					var record = call.arguments[p] as CoreStructArgument;
					if (record == null || record.parameter != null || record.producer.contract.mode != (type.parameter_contract (p) == PointerParameterContract.BORROWED_NOESCAPE ? StructValueMode.BORROW_VALUE : CopyabilityAuthority.of (type.parameter_types[p], copy_fields) == Copyability.COPYABLE ? StructValueMode.COPY_VALUE : StructValueMode.MOVE_VALUE)) {
						fail (path, "indirect record argument requires its exact copy/move signature boundary");
					}
					bool borrowing = type.parameter_contract (p) == PointerParameterContract.BORROWED_NOESCAPE;
					verify_struct_producer (record.producer, type.parameter_types[p], function, path + "/record-argument", true, borrowing);
					var snapshot = record.producer as CoreStructBorrowSnapshot;
					var root = snapshot == null ? null : snapshot.source as CoreLocalPlace;
					if (borrowing && root != null) {
						pending_record_borrows.add (root);
					}
				} else if (type.parameter_contract (p) == PointerParameterContract.OWNED_TRANSFER) {
					verify_indirect_owned_argument (call.arguments[p], call.channel_parameters[p], function, path + "/owned-argument");
				} else {
					verify_value (call.arguments[p], function, path + "/argument", null, false, type.parameter_contract (p) == PointerParameterContract.BORROWED_NOESCAPE ? call.channel_parameters[p] : null);
				}
				if (call.arguments[p] is CoreOwnedBorrowValue) {
					active_closure_owners.add (((CoreOwnedBorrowValue) call.arguments[p]).source.place);
				}
				if (call.arguments[p] is CoreOwnedFieldBorrow || call.arguments[p] is CoreStructProjectionValue || call.arguments[p] is CoreStructArgument) {
					reserve_receiver_loans (call.arguments[p]);
				}
				if (call.arguments[p] is CoreCallValue && ((CoreCallValue) call.arguments[p]).target.result_contract == ResultOwnershipContract.RECEIVER_BORROW) {
					var property = ((CorePropertyGetter) ((CoreCallValue) call.arguments[p]).target).property_member;
					(property.is_owned_lazy ? pending_lazy_borrows : pending_field_borrows).add (property.declaring_type.semantic_type);
				}
				if (call.arguments[p].semantic_type != type.parameter_types[p]) {
					fail (path, "closure invocation scalar signature mismatch");
				}
			}
			foreach (var owner_type in pending_field_borrows) {
				if (OwnedChildComposition.may_invalidate (type.environment_type, owner_type, possible_child_edges)) {
					fail (path, "borrowed argument overlaps a possibly aliasing closure environment");
				}
			}
			foreach (var owner_type in pending_lazy_borrows) {
				if (OwnedChildComposition.may_invalidate (type.environment_type, owner_type, possible_child_edges)) {
					fail (path, "lazy loan overlaps a possibly aliasing closure environment");
				}
			}
			verify_field_borrow_overlap (call.arguments, null, path);
			commit_indirect_owned_arguments (call.arguments, type, path);
			while (pending_record_borrows.length > record_depth) {
				pending_record_borrows.remove_index (pending_record_borrows.length - 1);
			}
			while (active_closure_owners.length > named_depth) {
				active_closure_owners.remove_index (active_closure_owners.length - 1);
			}
			while (pending_field_borrows.length > borrow_depth) {
				pending_field_borrows.remove_index (pending_field_borrows.length - 1);
			}
			while (pending_lazy_borrows.length > lazy_depth) {
				pending_lazy_borrows.remove_index (pending_lazy_borrows.length - 1);
			}
			return true;
		}
		if (value is CoreSharedOperation) {
			var operation = (CoreSharedOperation) value;
			if (!SharedContracts.matches (operation.action, operation.operand.semantic_type, value.semantic_type)) {
				fail (path, "shared operation lost exact payload and strong/weak capability");
			}
			if (operation.action == SharedAction.BORROW) {
				if (operation.operand is CoreLoadValue && operation.source == null) {
					fail (path, "shared field payload projection requires a named strong clone owner");
				}
				if (acquisition != null || borrowed_parameter == null || operation.borrower != borrowed_parameter || borrowed_parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || borrowed_parameter.semantic_type != value.semantic_type) {
					fail (path, "shared payload loan requires exact call-scoped borrowed parameter");
				}
			} else if (acquisition == null || operation.cleanup != acquisition || !matches_cleanup (value.semantic_type, acquisition)) {
				fail (path, "shared producer requires exact single owned acquisition");
			}
			if (operation.action == SharedAction.ACQUIRE) {
				var source = operation.source;
				var load = operation.operand as CoreLoadValue;
				if (source == null || owned_places.lookup (source.place) != source || !source.cleanup.is_heap_object || source.cleanup.object_class.semantic_type != operation.operand.semantic_type || load == null || load.source != source.place) {
					fail (path, "shared acquisition requires sole exact native heap owner and its move identity");
				}
			}
			var field_load = operation.operand as CoreLoadValue;
			var field = field_load == null ? null : field_load.source as CoreIndirectFieldPlace;
			if (field != null) {
				if (field.field.owned_cleanup == null || (field.semantic_type is ClassType && ((ClassType) field.semantic_type).intrinsically_shared ? !field.field.owned_cleanup.is_heap_object || field.field.owned_cleanup.object_class.semantic_type != field.semantic_type : field.semantic_type is ClosureHandleType && ((ClosureHandleType) field.semantic_type).actor ? field.field.owned_cleanup.closure_type != field.semantic_type : !(field.semantic_type is SharedHandleType) || field.field.owned_cleanup.shared_type != field.semantic_type) || operation.action == SharedAction.BORROW) {
					fail (path, "shared field operand requires exact owned handle and immediate native clone/upgrade operation");
				}
				verify_place (field, function, true, path + "/field");
				return true;
			}
			verify_value (operation.operand, function, path + "/operand", null, true, null, true);
			return true;
		}
		if (value is CoreFunctionValueCall) {
			var call = (CoreFunctionValueCall) value;
			var signature = call.callee.semantic_type as FunctionValueType;
			verify_invocation_result (call, signature, acquisition, path);
			if (signature == null || value.semantic_type != signature.result_type || call.arguments.length != signature.parameter_types.length) {
				fail (path, "function invocation requires exact code signature and arity");
			}
			try {
				signature.verify_records (signature.record_parameters, copy_fields);
			} catch (StructLeafError error) {
				fail (path, error.message);
			}
			if (call.channel_parameters.length != (signature.has_owner_channels () ? signature.parameter_types.length : 0)) {
				fail (path, "function invocation lost its exact call-owned channel declarations");
			}
			for (int p = 0; p < call.channel_parameters.length; p++) {
				var channel = call.channel_parameters[p];
				if (channel.ordinal != p || channel.semantic_type != signature.parameter_types[p] || channel.pointer_contract != signature.parameter_contract (p) || channel.heap_object != CallableRecordGroups.heap_parameter (signature, p) || channel.requires_nonnull) {
					fail (path, "function invocation channel declaration differs from carried signature");
				}
				verify_parameter_contract (channel, path + "/channel");
			}
			uint record_depth = pending_record_borrows.length;
			uint borrow_depth = pending_field_borrows.length;
			uint lazy_depth = pending_lazy_borrows.length;
			uint named_depth = active_closure_owners.length;
			verify_value (call.callee, function, path + "/callee", null, false, null, signature is CallbackType);
			for (int i = 0; i < call.arguments.length; i++) {
				if (signature.parameter_types[i].is_struct_storage ()) {
					var record = call.arguments[i] as CoreStructArgument;
					if (record == null || record.parameter != null || record.producer.contract.mode != (signature.parameter_contract (i) == PointerParameterContract.BORROWED_NOESCAPE ? StructValueMode.BORROW_VALUE : CopyabilityAuthority.of (signature.parameter_types[i], copy_fields) == Copyability.COPYABLE ? StructValueMode.COPY_VALUE : StructValueMode.MOVE_VALUE)) {
						fail (path, "indirect record argument requires its exact copy/move signature boundary");
					}
					bool borrowing = signature.parameter_contract (i) == PointerParameterContract.BORROWED_NOESCAPE;
					verify_struct_producer (record.producer, signature.parameter_types[i], function, path + "/record-argument", true, borrowing);
					var snapshot = record.producer as CoreStructBorrowSnapshot;
					var root = snapshot == null ? null : snapshot.source as CoreLocalPlace;
					if (borrowing && root != null) {
						pending_record_borrows.add (root);
					}
				} else if (signature.parameter_contract (i) == PointerParameterContract.OWNED_TRANSFER) {
					verify_indirect_owned_argument (call.arguments[i], call.channel_parameters[i], function, path + "/owned-argument");
				} else {
					verify_value (call.arguments[i], function, path + "/argument", null, false, signature.parameter_contract (i) == PointerParameterContract.BORROWED_NOESCAPE ? call.channel_parameters[i] : null);
				}
				if (call.arguments[i] is CoreOwnedBorrowValue) {
					active_closure_owners.add (((CoreOwnedBorrowValue) call.arguments[i]).source.place);
				}
				if (call.arguments[i] is CoreOwnedFieldBorrow || call.arguments[i] is CoreStructProjectionValue || call.arguments[i] is CoreStructArgument) {
					reserve_receiver_loans (call.arguments[i]);
				}
				if (call.arguments[i] is CoreCallValue && ((CoreCallValue) call.arguments[i]).target.result_contract == ResultOwnershipContract.RECEIVER_BORROW) {
					var property = ((CorePropertyGetter) ((CoreCallValue) call.arguments[i]).target).property_member;
					(property.is_owned_lazy ? pending_lazy_borrows : pending_field_borrows).add (property.declaring_type.semantic_type);
				}
				if (call.arguments[i].semantic_type != signature.parameter_types[i]) {
					fail (path, "function invocation argument signature mismatch");
				}
			}
			verify_field_borrow_overlap (call.arguments, null, path);
			commit_indirect_owned_arguments (call.arguments, signature, path);
			while (pending_record_borrows.length > record_depth) {
				pending_record_borrows.remove_index (pending_record_borrows.length - 1);
			}
			while (active_closure_owners.length > named_depth) {
				active_closure_owners.remove_index (active_closure_owners.length - 1);
			}
			while (pending_field_borrows.length > borrow_depth) {
				pending_field_borrows.remove_index (pending_field_borrows.length - 1);
			}
			while (pending_lazy_borrows.length > lazy_depth) {
				pending_lazy_borrows.remove_index (pending_lazy_borrows.length - 1);
			}
			return true;
		}
		if (value is CoreCallbackParameterView) {
			var view = (CoreCallbackParameterView) value;
			var callback = value.semantic_type as CallbackType;
			if (acquisition != null || borrowed_parameter == null || view.parameter != borrowed_parameter || borrowed_parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || value.semantic_type != borrowed_parameter.semantic_type || !function.parameters.find (view.source) || view.source.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || callback == null || !callback.matches_closure (view.source.semantic_type)) {
				fail (path, "captured callback parameter lost exact source and noescape boundary");
			}
			return true;
		}
		if (value is CoreFunctionAddress) {
			var address = (CoreFunctionAddress) value;
			var signature = value.semantic_type as FunctionValueType;
			var target = address.target;
			if (signature == null || target == null || !functions.contains (target) || target.implicit_receiver != null || target.async_body != null || target.throws_type != null || target.result_contract != signature.result_contract || target.return_type != signature.result_type || (signature.result_contract == ResultOwnershipContract.OWNED_TRANSFER && signature.result_type is ClassType && !target.heap_result) || target.parameters.length != signature.parameter_types.length) {
				fail (path, "function address requires exact program-owned nonthrowing native signature");
			}
			try {
				signature.verify_records (signature.record_parameters, copy_fields);
			} catch (StructLeafError error) {
				fail (path, error.message);
			}
			for (int i = 0; i < target.parameters.length; i++) {
				if (target.parameters[i].semantic_type != signature.parameter_types[i] || target.parameters[i].pointer_contract != signature.parameter_contract (i) || CallableRecordGroups.heap_parameter (signature, i) && !target.parameters[i].heap_object) {
					fail (path, "function address parameter identity mismatch");
				}
			}
			return true;
		}
		if (value is CoreSlotsTake) {
			var take = (CoreSlotsTake) value;
			verify_slots_place (take.store, function, true, path);
			verify_slots_mutation (take.store, path);
			if (slots_takes.lookup (take) == null || acquisition == null || acquisition != slots_takes.lookup (take).cleanup || acquisition != take.store.field.slots_cleanup || !matches_cleanup (value.semantic_type, acquisition) || value.semantic_type != ((OwnerSlotsType) take.store.semantic_type).element) {
				fail (path, "owner-slot take lost exact fresh heap acquisition");
			}
			pending_field_borrows.add (take.store.field.containing_type.semantic_type);
			verify_value (take.index, function, path + "/index");
			pending_field_borrows.remove_index (pending_field_borrows.length - 1);
			if (take.index.semantic_type.kind != TypeKind.INT) {
				fail (path, "owner-slot take requires I32 index");
			}
			return true;
		}
		if (value is CoreOwnedArgumentValue) {
			verify_iteration_consumption (((CoreOwnedArgumentValue) value).source, path);
		}
		if (value is CoreSharedOperation) {
			verify_iteration_consumption (((CoreSharedOperation) value).source, path);
		}
		if (value is CoreClosureBind) {
			verify_iteration_consumption (((CoreClosureBind) value).source, path);
		}
		return false;
	}

	private bool verify_storage_value(CoreValue value, CoreFunction function, string path, CoreCleanupContract? acquisition, bool owner_null_test, CoreParameter? borrowed_parameter, bool pointer_comparison, bool receiver_use, bool result_use, bool buffer_view_use, TypeSubstitution? borrow_substitution, bool record_result) throws CoreError {
		if (value is CoreWithReference) {
			var reference = (CoreWithReference) value;
			if (!active_with.find (reference.contract) || reference.semantic_type != reference.contract.source.semantic_type || acquisition != null || result_use) {
				fail (path, "with reference lost its active exact receiver capture or attempted escape");
			}
			verify_value (new CoreLoadValue (value.span, reference.contract.source), function, path, null, false, null, false, true);
			return true;
		}
		if (value is CoreSlotsValue) {
			var v = (CoreSlotsValue) value;
			if (v.has_iteration != (v.iteration != null)) {
				fail (path, "foreach element lost its iteration authority");
			}
			if (v.iteration != null) {
				var index = v.operand as CoreLoadValue;
				if (!active_iterations.find (v.iteration) || v.action != OwnerSlotsAction.BORROW || index == null || index.source != v.iteration.index || !same_iteration_store (v.store, v.iteration.store)) {
					fail (path, "foreach element lost its active backing/index identity");
				}
			}
			verify_slots_place (v.store, function, true, path);
			if (v.operand != null) {
				pending_field_borrows.add (v.store.field.containing_type.semantic_type);
				verify_value (v.operand, function, path + "/operand");
				pending_field_borrows.remove_index (pending_field_borrows.length - 1);
				if (v.operand.semantic_type.kind != TypeKind.INT) {
					fail (path, "owner-slot operand requires exact I32");
				}
			}
			if (v.action == OwnerSlotsAction.BORROW) {
				if (borrowed_parameter == null || v.borrower != borrowed_parameter || borrowed_parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || borrowed_parameter.semantic_type != ((OwnerSlotsType) v.store.semantic_type).element || v.semantic_type != borrowed_parameter.semantic_type || v.operand == null || acquisition != null) {
					fail (path, "owner-slot loan lost exact call parameter and occupied index");
				}
			} else {
				if (v.borrower != null || ((v.action == OwnerSlotsAction.RESERVE) != (v.operand != null)) || v.semantic_type.kind != (v.action == OwnerSlotsAction.RESERVE ? TypeKind.BOOL : TypeKind.INT)) {
					fail (path, "owner-slot query/reserve lost exact action and operand/result shape");
				}
				if (v.action == OwnerSlotsAction.RESERVE) {
					verify_slots_mutation (v.store, path);
				}
			} return true;
		}
		if (value is CoreTaskBorrow) {
			var borrow = (CoreTaskBorrow) value;
			verify_place (borrow.source, function, true, path);
			if (!(borrow.semantic_type is TaskType)) {
				fail (path, "task borrow lost unique task place authority");
			}
			return true;
		}
		if (value is CoreExecutorBorrow) {
			var borrow = (CoreExecutorBorrow) value;
			verify_place (borrow.source, function, true, path);
			if (!(borrow.semantic_type is ExecutorType)) {
				fail (path, "executor borrow lost unique executor place authority");
			}
			return true;
		}
		if (value is CoreAsyncOperation) {
			var operation = (CoreAsyncOperation) value;
			if (!operation.contract.valid_shape (operation.executor == null ? null : operation.executor.semantic_type, operation.task == null ? null : operation.task.semantic_type, operation.argument == null ? null : operation.argument.semantic_type, function.async_body)) {
				fail (path, "virtual operation lost exact registered operand/result/effect/context contract");
			}
			if (operation.semantic_type != operation.contract.result) {
				fail (path, "executor operation lost exact logical result contract");
			}
			if (operation.executor != null) {
				verify_value (operation.executor, function, path + "/executor");
				if (operation.executor.semantic_type != operation.contract.runtime.executor_type) {
					fail (path, "operation requires exact nominated executor");
				}
			}
			if (operation.task != null) {
				verify_value (operation.task, function, path + "/task");
				if (!(operation.task.semantic_type is TaskType) || ((TaskType) operation.task.semantic_type).runtime != operation.contract.runtime) {
					fail (path, "operation requires exact nominated task");
				}
			}
			if (operation.argument != null) {
				verify_value (operation.argument, function, path + "/argument");
			}
			return true;
		}
		if (value is CoreLazyObserve) {
			var observe = (CoreLazyObserve) value;
			var getter = function as CorePropertyGetter;
			if (getter == null || getter.property_member != observe.property_member || !observe.property_member.is_owned_lazy || observe.semantic_type != getter.return_type || acquisition != null) {
				fail (path, "lazy observation requires its exact borrowed property getter");
			}
			return true;
		}
		if (value is CoreTaskAwait) {
			var wait = (CoreTaskAwait) value;
			if ((wait.semantic_type.is_struct_storage () || wait.semantic_type is EnumType) && !aggregate_awaits.contains (wait)) {
				fail (path, "aggregate await requires one bounded record/enum producer");
			}
			if (wait.buffer_cleanup != null) {
				if (acquisition != wait.buffer_cleanup || !cleanups.contains (acquisition) || !matches_cleanup (value.semantic_type, acquisition) || buffer_awaits.contains (wait)) {
					fail (path, "owned await requires one exact buffer ownership consumer");
				}
				buffer_awaits.insert (wait, true);
			}
			if (wait.child is CoreTaskCreate) {
				direct_wait_creations.insert ((CoreTaskCreate) wait.child, wait);
			}
			var bridge = wait.bridge_executor;
			CoreLoadValue? bridge_load = null;
			if (bridge != null) {
				var handle = bridge.semantic_type as HandleType;
				bridge_load = bridge as CoreLoadValue;
				if (handle == null || !handles.contains (handle) || !AsyncBridgeTypes.matches (handle, handles.lookup (handle).cleanup.external_symbol) || bridge_load == null || !(bridge_load.source is CoreLocalPlace)) {
					fail (path, "worker bridge requires its exact named live pool owner");
				}
				verify_value (bridge, function, path + "/bridge", null, true, null, true);
				active_closure_owners.add (bridge_load.source);
			}
			verify_value (wait.child, function, path + "/child");
			if (bridge_load != null) {
				active_closure_owners.remove_index (active_closure_owners.length - 1);
			}
			var task = wait.child.semantic_type as TaskType;
			if (wait.body != function.async_body || task == null || (bridge == null ? !task.runtime.compatible (wait.body.runtime) : !AsyncBridgeTypes.compatible (wait.body.runtime, task.runtime)) || (wait.discard ? wait.semantic_type.kind != TypeKind.VOID : wait.semantic_type.logical_identity != task.success_type.logical_identity)) {
				fail (path, "await lost exact task/result/body identity");
			}
			return true;
		}
		if (value is CoreTaskCreate) {
			var creation = (CoreTaskCreate) value;
			if (!creation.matches_captures () || creation.target == null || creation.target.async_body == null || creation.semantic_type != creation.target.async_body.task_type || acquisition != null) {
				fail (path, "task creation requires exact logical contract and generated body identity");
			}
			if (creation.checked_admission) {
				if (creation.allocation_context == null) {
					fail (path, "checked frame admission requires explicit backing authority");
				}
				verify_exception_effect (creation.target.async_body.runtime.error_type, function, path);
				foreach (var input in creation.arguments) {
					var argument = input as CoreOwnedArgumentValue;
					var record = input as CoreStructArgument;
					var enumeration = input as CoreEnumArgument;
					if (record != null && record.producer.contract.mode == StructValueMode.MOVE_VALUE && !(record.producer is CoreStructMoveProducer) || enumeration != null && EnumValueAuthority.owns (enumeration.producer.definition, (type) => enum_definitions.lookup (type)) || argument != null && !(argument.semantic_type is ClassType || argument.semantic_type is HandleType || argument.semantic_type is SliceType)) {
						fail (path, "checked frame capture lacks an exact conditional input restoration contract");
					}
					if (argument != null && argument.source != null && (argument.source.place.semantic_type != argument.semantic_type || argument.source.place.requires_nonnull || argument.source.place.incoming_parameter != null && argument.source.place.incoming_parameter.requires_nonnull)) {
						fail (path, "checked frame input requires an exact nullable caller slot");
					}
				}
			}
			var frame_context = creation.allocation_context;
			CoreLoadValue? frame_load = null;
			if (frame_context != null) {
				var type = frame_context.semantic_type as HandleType;
				frame_load = frame_context as CoreLoadValue;
				if (type == null || !handles.contains (type) || type.context_mode == "" || handles.lookup (type).context_mode != type.context_mode || creation.target.async_body.runtime.threaded && type.context_mode != "owned-concurrent" || creation.loans.length != 0 || frame_load == null && !(frame_context is CoreParameterValue) || frame_load != null && !(frame_load.source is CoreLocalPlace)) {
					fail (path, "task frame requires exact named backing lifetime/thread authority");
				}
				verify_value (frame_context, function, path + "/frame-context", null, true, null, true);
				if (frame_load != null) {
					active_closure_owners.add (frame_load.source);
				}
			}
			int borrowed = 0;
			for (int p = 0; p < creation.target.parameters.length; p++) {
				var parameter = creation.target.parameters[p];
				if (parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
					continue;
				}
				if (borrowed >= creation.loans.length) {
					fail (path, "borrowed task capture has no sealed direct suspension loan");
				}
				var loan = creation.loans[borrowed++];
				if (function.async_body == null || !direct_wait_creations.contains (creation) || loan.parameter_ordinal != p || loan.view != creation.arguments[p] || loan.view.storage != loan.storage || local_owners.lookup (loan.storage) != function || loan.storage.incoming_parameter != null || !(parameter.semantic_type is SliceType) || sealed_loan_views.contains (loan.view) || loan_identities.contains (loan.identity)) {
					fail (path, "suspension loan lost exact direct waiter/view/parent storage/parameter authority");
				}
				sealed_loan_views.insert (loan.view, loan);
				loan_identities.insert (loan.identity, true);
			}
			if (borrowed != creation.loans.length) {
				fail (path, "task has an unrelated suspension loan");
			}
			verify_call (creation.target, creation.arguments, function, path, null, false, null, true);
			if (creation.checked_admission && generic_owner_flow != null) {
				foreach (var input in creation.arguments) {
					var record = input as CoreStructArgument;
					var moved = record == null ? null : record.producer as CoreStructMoveProducer;
					if (moved != null) {
						record_boundary_events (GenericOwnershipEventKind.ACQUIRE, moved.source, input.span);
					}
				}
				foreach (var input in creation.arguments) {
					var owned = input as CoreOwnedArgumentValue;
					if (owned != null && owned.source != null && tracked_owner (owned.source)) {
						generic_owner_flow.owner_event (GenericOwnershipEventKind.ACQUIRE, owned.source, owned.source.place.name, owned.span);
					}
				}
				generic_owner_flow.effect (creation.target.async_body.runtime.error_type, creation.span);
			}
			if (frame_load != null) {
				active_closure_owners.remove_index (active_closure_owners.length - 1);
			}
			return true;
		}
		if (value is CoreTaskMove) {
			var move = (CoreTaskMove) value;
			verify_place (move.source, function, false, path + "/source");
			if (!(move.semantic_type is TaskType) || move.semantic_type != move.source.semantic_type) {
				fail (path, "task move requires exact unique local contract");
			}
			return true;
		}
		if (value is CoreClassUpcast) {
			var cast = (CoreClassUpcast) value;
			var incoming = cast.reference.semantic_type as ReceiverType;
			var outgoing = value.semantic_type as ReceiverType;
			if (structs.lookup (cast.source_class.semantic_type) != cast.source_class || structs.lookup (cast.target_class.semantic_type) != cast.target_class || cast.source_class == cast.target_class || !((ClassType) cast.source_class.semantic_type).derives_from ((ClassType) cast.target_class.semantic_type) || (incoming == null ? cast.reference.semantic_type != cast.source_class.semantic_type : incoming.instance_type != cast.source_class.semantic_type) || (outgoing == null ? value.semantic_type != cast.target_class.semantic_type : outgoing.instance_type != cast.target_class.semantic_type) || (incoming == null) != (outgoing == null) || (incoming != null && (incoming.mode != outgoing.mode || !receiver_use))) {
				fail (path, "upcast requires exact descendant/ancestor identities and the same borrowed receiver mode");
			}
			verify_value (cast.reference, function, path + "/source", null, false, borrowed_parameter, true, incoming != null);
			return true;
		}

		if (value is CoreEnumEquality) {
			var equality = (CoreEnumEquality) value;
			if (value.semantic_type.kind != TypeKind.BOOL || !equality.left.definition.payload_free) {
				fail (path, "enum equality requires a payload-free enum and bool result");
			}
			verify_enum_producer (equality.left, equality.left.semantic_type, function, path);
			verify_enum_producer (equality.right, equality.left.semantic_type, function, path);
			return true;
		}
		if (value.semantic_type is EnumType) {
			fail (path, "enum producers are bounded and cannot enter ordinary Core values");
		}
		if (value is CoreOwnedBufferAllocate) {
			var allocation = (CoreOwnedBufferAllocate) value;
			var bytes = value.semantic_type as ContextBytesType;
			var context = allocation.allocation_context;
			var context_load = context as CoreLoadValue;
			if ((bytes != null) != (context != null)) {
				fail (path, "byte allocation lost its exact context selection");
			}
			if (context != null) {
				if (context.semantic_type != bytes.allocator_type || context_load == null && !(context is CoreParameterValue) || context_load != null && !(context_load.source is CoreLocalPlace)) {
					fail (path, "byte allocation requires its named exact context owner or borrowed parameter");
				}
				verify_value (context, function, path + "/context", null, true, null, true);
				if (context_load != null) {
					active_closure_owners.add (context_load.source);
				}
			}
			verify_type (value.semantic_type, true, path);
			if (!(value.semantic_type is SliceType) || acquisition == null || allocation.cleanup != acquisition || !cleanups.contains (acquisition) || !matches_cleanup (value.semantic_type, acquisition) || buffer_allocations.contains (allocation)) {
				fail (path, "buffer allocation requires one exact ownership consumer and static deallocation authority");
			}
			if (allocation.count.semantic_type != allocation.cleanup.buffer_shape.length_type || !(allocation.count.semantic_type is IntegerType) || (allocation.count is CoreIntegerValue && ((CoreIntegerValue) allocation.count).value.mathematical_value < 0)) {
				fail (path, "buffer allocation requires a non-negative int/i32 count");
			}
			verify_value (allocation.count, function, path + "/count");
			if (allocation.failure_call != null) {
				uint pending_depth = pending_field_borrows.length;
				foreach (var container in allocation_containers) {
					pending_field_borrows.add (container);
				}
				var call = allocation.failure_call as CoreCallStatement;
				var c_call = allocation.failure_call as CoreCCallStatement;
				if (call == null && c_call == null) {
					fail (path, "allocation failure action requires a typed direct call");
				}
				if (generic_owner_flow != null) {
					generic_owner_flow.begin (GenericOwnershipEventKind.CHOICE, allocation.failure_call.span);
				}
				if (call != null) {
					if (call is CoreGenericCallStatement) {
						verify_retained_requirements (call.target, ((CoreGenericCallStatement) call).target_requirements, path);
					}
					verify_call (call.target, call.arguments, function, path + "/failure", call.receiver, false, (call is CoreGenericCallStatement) ? ((CoreGenericCallStatement) call).type_arguments : null);
				} else {
					verify_c_call (c_call.target, c_call.arguments, function, path + "/failure");
				}
				if ((call != null ? call.target.return_type : c_call.target.return_type).kind != TypeKind.VOID) {
					fail (path, "allocation failure action must return exact void");
				}
				if (generic_owner_flow != null) {
					generic_owner_flow.jump (GenericOwnershipEventKind.RETURN, allocation.failure_call.span);
					generic_owner_flow.end ();
				}
				while (pending_field_borrows.length > pending_depth) {
					pending_field_borrows.remove_index (pending_field_borrows.length - 1);
				}
			}
			if (context_load != null) {
				active_closure_owners.remove_index (active_closure_owners.length - 1);
			}
			buffer_allocations.insert (allocation, true);
			return true;
		}
		if (value is CoreOwnedBufferBorrow) {
			var borrow = (CoreOwnedBufferBorrow) value;
			if (generic_owner_flow != null) {
				generic_owner_flow.owner_event (GenericOwnershipEventKind.READ, borrow.source, borrow.source.place.name, value.span);
			}
			bool projected = borrow.parameter != null && ContextBytesType.permits_view (borrow.source.place.semantic_type, value.semantic_type);
			if (acquisition != null || owned_places.lookup (borrow.source.place) != borrow.source || value.semantic_type != borrow.source.place.semantic_type && !projected || !borrow.source.cleanup.is_buffer || (borrow.parameter == null ? !buffer_view_use : borrow.parameter != borrowed_parameter || borrowed_parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || (borrow_substitution == null ? borrowed_parameter.semantic_type != value.semantic_type : !borrow_substitution.matches (borrowed_parameter.semantic_type, value.semantic_type)))) {
				fail (path, "buffer borrow requires an exact owner and bounded non-owning use");
			}
			verify_place (borrow.source.place, function, true, path + "/owner");
			return true;
		}
		if (value.semantic_type is ReceiverType && !receiver_use) {
			fail (path, "receiver is only valid as an implicit method input or receiver field base");
		}
		if (value is CoreOwnedFieldBorrow) {
			var borrow = (CoreOwnedFieldBorrow) value;
			var field = borrow.source.field;
			bool direct_use = field.owned_cleanup != null && (field.owned_cleanup.is_buffer ? buffer_view_use : owner_null_test || receiver_use && field.owned_cleanup.is_heap_object);
			bool parameter_use = borrow.parameter != null && borrow.parameter == borrowed_parameter && borrowed_parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE;
			if (field.owned_cleanup == null || !(field.containing_type is CoreClass) || (!(field.semantic_type is HandleType) && !field.owned_cleanup.is_buffer && !field.owned_cleanup.is_heap_object) || value.semantic_type != field.semantic_type || acquisition != null || (borrow.parameter == null ? !direct_use : !parameter_use)) {
				fail (path, "owned field borrow requires exact field identity and temporary borrowed argument, receiver or null-test use");
			}
			verify_place (borrow.source, function, true, path + "/field");
			if (field_state != null && borrow.source.pointer is CoreReceiverValue && !field_state.is_definite (field.ordinal)) {
				fail (path, "owned field borrowed before definite initialization: " + field.name);
			}
			return true;
		}
		var result_receiver = value as CoreResultStorageReceiverValue;
		if (result_receiver != null) {
			if (!receiver_use || result_receiver.storage != function.result_storage || ((ReceiverType) value.semantic_type).instance_type != function.return_type || ((ReceiverType) value.semantic_type).mode != ReceiverMode.INITIALIZING) {
				fail (path, "result receiver requires exact initializing result storage");
			}
			return true;
		}
		var storage_receiver = value as CoreStorageReceiverValue;
		if (storage_receiver != null) {
			if (object_owners.lookup (storage_receiver.storage) != function || ((ReceiverType) value.semantic_type).instance_type != storage_receiver.storage.semantic_type) {
				fail (path, "storage receiver requires exact caller-owned object storage");
			}
			verify_type (value.semantic_type, true, path);
			return true;
		}
		var object_receiver = value as CoreObjectReceiverValue;
		if (object_receiver != null) {
			var contract = value.semantic_type as ReceiverType;
			if (!receiver_use || contract == null || contract.mode != ReceiverMode.LIVE || !(contract.instance_type is ClassType) || contract.instance_type != object_receiver.reference.semantic_type) {
				fail (path, "object receiver requires exact class reference and nonnull receiver contract");
			}
			verify_type (value.semantic_type, true, path);
			verify_value (object_receiver.reference, function, path + "/reference", null, false, null, false, true);
			return true;
		}
		var self = value as CoreReceiverValue;
		if (self != null) {
			if (receiver_owners.lookup (self.receiver) != function) {
				fail (path, "this must reference the exact containing method receiver");
			}
			verify_type (value.semantic_type, true, path);
			return true;
		}

		var borrow = value as CoreOwnedBorrowValue;
		if (borrow != null) {
			bool projected_callback = value.semantic_type is CallbackType && ((CallbackType) value.semantic_type).matches_closure (borrow.source.place.semantic_type);
			bool matches = borrowed_parameter != null && (borrow_substitution == null ? value.semantic_type == borrowed_parameter.semantic_type || (value.semantic_type is ClassType && borrowed_parameter.semantic_type is ClassType && ((ClassType) value.semantic_type).derives_from ((ClassType) borrowed_parameter.semantic_type)) : borrow_substitution.matches (borrowed_parameter.semantic_type, value.semantic_type));
			if (acquisition != null || borrowed_parameter == null || borrowed_parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || borrow.parameter != borrowed_parameter || (!value.semantic_type.is_ownable_handle_type () && !(value.semantic_type is ClassType) && !ownable_parameter (value.semantic_type) && !projected_callback) || !matches || value.semantic_type != borrow.source.place.semantic_type && !projected_callback || owned_places.lookup (borrow.source.place) != borrow.source) {
				fail (path, "owner borrow requires exact owned local and borrowed/noescape argument boundary");
			}
			if (generic_owner_flow != null && tracked_owner (borrow.source)) {
				generic_owner_flow.owner_event (GenericOwnershipEventKind.READ, borrow.source, borrow.source.place.name, value.span);
			}
			verify_place (borrow.source.place, function, true, path + "/owner");
			return true;
		}
		var address = value as CoreAddressOfValue;
		if (address != null && address.receiver_place != null) {
			var receiver = value.semantic_type as ReceiverType;
			if (receiver == null || receiver.mode != ReceiverMode.LIVE || address.target != null || address.provenance != null || receiver.instance_type != address.receiver_place.semantic_type || !(address.receiver_place.semantic_type is StructType)) {
				fail (path, "projected receiver requires an exact live struct storage contract");
			}
			require_mutable_struct_place (address.receiver_place, path);
			verify_copy_place (address.receiver_place, function, true, path + "/receiver-place");
			return true;
		}
		if (address != null) {
			require_mutable_struct_place (address.target, path);
		}
		if (address != null) {
			verify_type (value.semantic_type, true, path);
			if (local_owners.lookup (address.target) != function || !address.target.address_taken || !address.target.semantic_type.is_typed_data_pointee () || ((value.semantic_type is ReceiverType) ? ((ReceiverType) value.semantic_type).instance_type != address.target.semantic_type : (!value.semantic_type.is_typed_pointer () || ((TypedPointerType) value.semantic_type).pointee != address.target.semantic_type))) {
				fail (path, "address-of must match exact addressable local storage and pointer type");
			}
			if (address.target.semantic_type.is_directly_dereferenceable_value_type ()) {
				verify_place (address.target, function, true, path + "/target");
			}
			foreach (var field in function.field_places) {
				if (field.root_local () == address.target && !available.contains (field)) {
					fail (path, "address borrow requires complete initialized and visible aggregate storage");
				}
			}
			return true;
		}
		verify_type (value.semantic_type, true, path);
		var slice = value as CoreSliceFromArrayValue;
		if (slice != null) {
			if (!sealed_loan_views.contains (slice)) {
				exposed_loan_roots.insert (slice.storage, true);
			}
			verify_array_type (slice.array_type, path);
			if (local_owners.lookup (slice.storage) != function || !available.contains (slice.storage) || slice.storage.is_promotable ()) {
				fail (path, "slice construction requires initialized visible array storage");
			}
			var type = value.semantic_type as SliceType;
			if (type == null || slice.storage.semantic_type != slice.array_type || type.element_type != slice.array_type.element_type || !slice.provenance.is_valid () || slice.provenance.origin != DataPointerOrigin.LOCAL || slice.provenance.origin_ordinal != slice.storage.ordinal) {
				fail (path, "slice construction requires exact array element, result type and storage provenance");
			}
			if ((slice.start == null) != (slice.count == null)) {
				fail (path, "slice range requires paired start and count");
			}
			if (slice.start != null && slice.count != null) {
				verify_value (slice.start, function, path + "/operand");
				verify_value (slice.count, function, path + "/operand");
				if (!(slice.start.semantic_type is IntegerType) || !(slice.count.semantic_type is IntegerType)) {
					fail (path, "slice start and count require scalar IntegerTypes");
				}
				var start = slice.start as CoreIntegerValue;
				var count = slice.count as CoreIntegerValue;
				if (start != null && (!start.value.fits_nonnegative (slice.array_type.length))) {
					fail (path, "constant slice start outside array extent");
				}
				if (count != null && (!count.value.fits_nonnegative (slice.array_type.length) || (start != null && (!start.value.fits_nonnegative (slice.array_type.length) || count.value.bits > (uint64) slice.array_type.length - start.value.bits)))) {
					fail (path, "constant slice count outside remaining extent");
				}
			}
			return true;
		}
		return false;
	}

	private bool verify_composed_value(CoreValue value, CoreFunction function, string path, CoreCleanupContract? acquisition, bool owner_null_test, CoreParameter? borrowed_parameter, bool pointer_comparison, bool receiver_use, bool result_use, bool buffer_view_use, TypeSubstitution? borrow_substitution, bool record_result) throws CoreError {
		if (value is CoreUtf8FactoryValue) {
			if (utf8_values.lookup ((CoreUtf8FactoryValue) value) != function) {
				fail (path, "unassociated UTF-8 validation/copy boundary");
			}
			return true;
		}
		if (value is CoreTextValue) {
			var payload = ((CoreTextValue) value).payload;
			if (!(value.semantic_type is StringType) || !payload.valid () || !text_literals.contains (payload)) {
				fail (path, "text literal requires member immutable UTF-8 payload and exact byte length");
			}
			return true;
		}
		if (value is CoreTextLengthValue) {
			var receiver = ((CoreTextLengthValue) value).receiver;
			verify_value (receiver, function, path + "/text");
			if (!(receiver.semantic_type is StringType) || !(value.semantic_type is IntegerType) || value.semantic_type.kind != TypeKind.INT) {
				fail (path, "text byte length requires StringType input and int result");
			}
			return true;
		}
		var length = value as CoreSliceLengthValue;
		if (length != null) {
			verify_value (length.slice, function, path + "/operand", null, false, null, false, false, false, true);
			if (!(length.slice.semantic_type is SliceType) || !(value.semantic_type is IntegerType) || value.semantic_type.kind != TypeKind.INT) {
				fail (path, "slice length requires SliceType input and exact int result");
			}
			return true;
		}
		var c_call = value as CoreCCallValue;
		if (c_call != null) {
			verify_c_call (c_call.target, c_call.arguments, function, path);
			if (c_call.target.owned_cleanup != acquisition) {
				fail (path, "owned-result call requires its exact acquisition contract");
			}
			if (c_call.target.return_type.kind == TypeKind.VOID || value.semantic_type != c_call.target.return_type) {
				fail (path, "C call value must match a non-void target return type");
			}
			return true;
		}
		var loan_parameter = value as CoreParameterValue;
		bool forwarding_loan = loan_parameter != null && loan_parameter.parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && borrowed_parameter != null && borrowed_parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && acquisition == null;
		var call = value as CoreCallValue;
		bool owned_call = call != null && call.target != null && acquisition != null && call.target.owned_cleanup == acquisition;
		if (ownable_parameter (value.semantic_type) && !(value is CoreGenericCall) && !forwarding_loan && !owned_call) {
			fail (path, "plain Ownable T values cannot be copied, loaded, compared or constructed");
		}
		if (call != null) {
			if (call.target != null && call.target.result_contract == ResultOwnershipContract.RECEIVER_BORROW && (acquisition != null || (!receiver_use && !owner_null_test && (borrowed_parameter == null || borrowed_parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || borrowed_parameter.semantic_type != call.semantic_type)))) {
				fail (path, "borrowed property result requires a direct borrowed argument, temporary receiver or null test");
			}
			if (call.target != null && call.target.owned_cleanup != null && call.target.owned_cleanup.is_buffer) {
				if (buffer_producers.contains (call)) {
					fail (path, "owned buffer call producer requires exactly one consuming position");
				}
				buffer_producers.insert (call, true);
			}
			if (call is CoreGenericCall) {
				verify_retained_requirements (call.target, ((CoreGenericCall) call).target_requirements, path);
			}
			verify_call (call.target, call.arguments, function, path, call.receiver, false, (call is CoreGenericCall) ? ((CoreGenericCall) call).type_arguments : null);
			bool heap_result = call.target.heap_result;
			if (call is CoreGenericCall && (call.target.return_type is TypeParameterType || call.target.return_type is ClassType) && call.semantic_type is ClassType && call.target.owned_cleanup != null) {
				var origin = generic_result_origins.lookup ((CoreGenericFunction) call.target);
				if (origin != null && (origin.domains & GenericResultOrigins.UNKNOWN) != 0) {
					origin = generic_result_projection.project ((CoreGenericFunction) call.target, ((CoreGenericCall) call).type_arguments);
				}
				uint domains = origin == null ? GenericResultOrigins.UNKNOWN : origin.evaluate (CoreGenericResultOrigins.heap_arguments (call.arguments));
				// Only an unresolved application in an abstract generic body can
				// defer; concrete verification must resolve every producer.
				bool open_arguments = false;
				foreach (var argument in ((CoreGenericCall) call).type_arguments) {
					open_arguments |= argument.is_parameterized ();
				}
				bool deferred = (domains & GenericResultOrigins.UNKNOWN) != 0 && function is CoreGenericFunction
				    && open_arguments && acquisition != null && acquisition.is_object;
				if ((domains & GenericResultOrigins.UNKNOWN) != 0 && !deferred) {
					fail (path, "generic Class result requires concrete producer-origin projection");
				}
				if (domains == (GenericResultOrigins.CALLER | GenericResultOrigins.HEAP)) {
					fail (path, "generic Class result has incompatible independently derived storage origins");
				}
				heap_result = deferred ? acquisition.is_heap_object : domains == GenericResultOrigins.HEAP;
				if (!deferred && (acquisition == null || !acquisition.is_object || acquisition.is_heap_object != heap_result)) {
					fail (path, "generic Class result requires exact independently derived acquisition domain");
				}
			}
			if (heap_result && ((call is CoreGenericCall && (ownable_parameter (call.target.return_type) || call.target.return_type is ClassType)) || (call.target.generic_instance != null && call.target.generic_instance.storage.count > 0))) {
				var receiver = heap_result_receivers.lookup (call);
				if (result_use) {
					if ((!deferred_class_result (function) && (!function.heap_result || acquisition != function.owned_cleanup))
					    || acquisition == null || !acquisition.is_heap_object || !matches_cleanup (call.semantic_type, acquisition)
					    || call.candidate_storage != null || call.result_storage != null) {
						fail (path, "heap generic result forwarding requires the exact function result contract");
					}
				} else if (receiver == null || receiver.cleanup != acquisition || receiver.place.semantic_type != call.semantic_type || receiver.place.incoming_parameter != null) {
					fail (path, "heap generic result requires one fresh named concrete acquisition");
				}
			}
			if (call.semantic_type is ClassType && call.target.owned_cleanup != null && !heap_result) {
				if ((call.candidate_storage == null) == (call.result_storage == null)) {
					fail (path, "owned object call requires exactly one candidate or forwarded result storage");
				}
				if (call.result_storage != null && (!result_use || call.result_storage != function.result_storage || call.result_storage.semantic_type != call.semantic_type)) {
					fail (path, "forwarded call requires exact result storage");
				}
				if (call.candidate_storage != null) {
					var storage = call.candidate_storage;
					if (!storage.result_candidate || storage.transferable || object_owners.lookup (storage) != function || storage.semantic_type != call.semantic_type || object_constructions.contains (storage)) {
						fail (path, "candidate requires exact unused caller storage");
					}
					object_constructions.insert (storage, storage);
				}
			} else if (call.candidate_storage != null || call.result_storage != null) {
				fail (path, "unmanaged call cannot carry result storage");
			}
			if (call.target.owned_cleanup != null && (call.target.owned_cleanup.type_parameter != null || call.target.owned_cleanup.is_symbolic_buffer || call.target.owned_cleanup.is_symbolic_object || call is CoreGenericCall && call.target.return_type is ClassType) ? acquisition == null || !cleanups.contains (acquisition) || !matches_cleanup (call.semantic_type, acquisition) : call.target.owned_cleanup != acquisition) {
				fail (path, "owned-result call requires its exact substituted acquisition contract");
			}
			var substitution = (call is CoreGenericCall) ? ((CoreGenericFunction) call.target).substitution (((CoreGenericCall) call).type_arguments) : null;
			if (call.target.return_type.kind == TypeKind.VOID || (substitution == null ? value.semantic_type != call.target.return_type : !substitution.matches (call.target.return_type, value.semantic_type))) {
				fail (path, "call value must match a non-void target return type");
			}
			return true;
		}
		if (value is CoreNullPointerValue) {
			if (!value.semantic_type.is_nullable_pointer_value ()) {
				fail (path, "null pointer must have type 'void*'");
			}
			return true;
		}
		var boolean = value as CoreBooleanValue;
		if (boolean != null) {
			if (value.semantic_type.kind != TypeKind.BOOL) {
				fail (path, "boolean literal must have type 'bool'");
			}
			if (boolean.literal != BooleanLiteral.TRUE && boolean.literal != BooleanLiteral.FALSE) {
				fail (path, "unsupported boolean literal");
			}
			return true;
		}
		var dot = value as CoreVectorDotValue;
		if (dot != null) {
			if (dot.accumulator != null) {
				verify_value (dot.accumulator, function, path + "/accumulator");
			}
			verify_value (dot.first, function, path + "/first");
			verify_value (dot.second, function, path + "/second");
			string? error = dot.dot_kind.type_error (dot.source_type, dot.first.semantic_type, dot.second.semantic_type, dot.destination_type, dot.accumulator == null ? null : dot.accumulator.semantic_type);
			if (error != null) {
				fail (path, error);
			}
			return true;
		}
		var dsp = value as CoreDspValue;
		if (dsp != null) {
			verify_value (dsp.first, function, path + "/first");
			if (dsp.second != null) {
				verify_value (dsp.second, function, path + "/second");
			}
			if (dsp.source_type != dsp.first.semantic_type) {
				fail (path, "DSP source type must exactly match its first operand");
			}
			string? error = dsp.primitive_kind.type_error (dsp.source_type, dsp.second == null ? null : dsp.second.semantic_type, dsp.destination_type, dsp.destination_element);
			if (error != null) {
				fail (path, error);
			}
			return true;
		}
		var shift = value as CoreIntegerShiftValue;
		if (shift != null) {
			verify_value (shift.operand, function, path + "/value");
			verify_value (shift.count, function, path + "/count");
			if (!shift.shift_kind.accepts (shift.operand.semantic_type, shift.count.semantic_type, value.semantic_type)) {
				fail (path, "shift requires exact integer scalar/vector result and scalar integer count; invalid counts trap");
			}
			return true;
		}
		var numeric_conversion = value as CoreNumericConversionValue;
		if (numeric_conversion != null) {
			verify_value (numeric_conversion.operand, function, path + "/operand");
			if (numeric_conversion.source_type != numeric_conversion.operand.semantic_type || !numeric_conversion.conversion_kind.accepts (numeric_conversion.source_type, numeric_conversion.destination_type, numeric_conversion.policy)) {
				fail (path, "numeric conversion requires exact scalar types, signedness, kind and rounding/trap policy");
			}
			return true;
		}
		var floating_conversion = value as CoreFloatConversionValue;
		if (floating_conversion != null) {
			verify_value (floating_conversion.operand, function, path + "/operand");
			if (floating_conversion.source_type != floating_conversion.operand.semantic_type || !floating_conversion.conversion_kind.accepts (floating_conversion.source_type, floating_conversion.destination_type)) {
				fail (path, "float conversion requires exact source type and f32/f64 widen or narrow kind");
			}
			return true;
		}
		var conversion = value as CoreIntegerConversionValue;
		if (conversion != null) {
			verify_value (conversion.operand, function, path + "/operand");
			if (conversion.source_type != conversion.operand.semantic_type || !IntegerConversion.accepts (conversion.source_type, conversion.destination_type)) {
				fail (path, "integer conversion requires exact source type and integer scalar types or supported integer vectors with equal lane counts");
			}
			return true;
		}
		var splat = value as CoreVectorSplatValue;
		if (splat != null) {
			verify_value (splat.operand, function, path + "/operand");
			var type = value.semantic_type as VectorType;
			if (type == null || type.element_type != splat.operand.semantic_type || type.lane_count != splat.lane_count || !VectorType.supports (splat.operand.semantic_type, splat.lane_count)) {
				fail (path, "vector splat requires exact scalar element, supported shape and matching lane count");
				return true;
			}
			return true;
		}
		var extract = value as CoreVectorExtractValue;
		if (extract != null) {
			verify_value (extract.vector, function, path + "/vector");
			var type = extract.vector.semantic_type as VectorType;
			if (type == null) {
				fail (path, "vector extract requires a vector source");
				return true;
			}
			if (value.semantic_type != type.element_type) {
				fail (path, "vector extract result requires exact element type");
				return true;
			}
			if (!extract.index.in_range (type)) {
				fail (path, "vector extract index is out of range");
				return true;
			}
			return true;
		}
		var insert = value as CoreVectorInsertValue;
		if (insert != null) {
			verify_value (insert.vector, function, path + "/vector");
			verify_value (insert.replacement, function, path + "/replacement");
			var type = insert.vector.semantic_type as VectorType;
			if (type == null) {
				fail (path, "vector insert requires a vector source");
				return true;
			}
			if (value.semantic_type != type) {
				fail (path, "vector insert result requires exact source VectorType");
				return true;
			}
			if (insert.replacement.semantic_type != type.element_type) {
				fail (path, "vector insert replacement requires exact element type");
				return true;
			}
			if (!insert.index.in_range (type)) {
				fail (path, "vector insert index is out of range");
				return true;
			}
			return true;
		}
		var shuffle = value as CoreVectorShuffleValue;
		if (shuffle != null) {
			verify_value (shuffle.vector, function, path + "/vector");
			var type = shuffle.vector.semantic_type as VectorType;
			if (type == null) {
				fail (path, "vector shuffle requires a vector source");
				return true;
			}
			if (value.semantic_type != type) {
				fail (path, "vector shuffle result requires exact source VectorType");
				return true;
			}
			if (shuffle.selectors.length != type.lane_count) {
				fail (path, "vector shuffle requires exactly one selector per lane");
				return true;
			}
			for (int i = 0; i < shuffle.selectors.length; i++) {
				if (!shuffle.selectors.at (i).in_range (type)) {
					fail (path, "vector shuffle selector is out of range");
				}
			}
			return true;
		}
		if (value is CoreVectorMemoryValue) {
			var memory = (CoreVectorMemoryValue) value;
			verify_value (memory.view, function, path + "/view");
			verify_value (memory.offset, function, path + "/offset");
			if (memory.stored != null) {
				verify_value (memory.stored, function, path + "/stored");
			}
			var error = memory.contract.type_error (memory.view.semantic_type, memory.offset.semantic_type, memory.stored == null ? null : memory.stored.semantic_type, value.semantic_type);
			if (error != null) {
				fail (path, error);
			}
			return true;
		}
		var select = value as CoreVectorSelectValue;
		if (select != null) {
			verify_value (select.mask, function, path + "/mask");
			verify_value (select.true_value, function, path + "/true_value");
			verify_value (select.false_value, function, path + "/false_value");
			var type = select.true_value.semantic_type as VectorType;
			var mask_type = select.mask.semantic_type as VectorType;
			if (type == null || select.false_value.semantic_type != type || value.semantic_type != type) {
				fail (path, "vector select requires exact matching data and result VectorTypes");
				return true;
			}
			if (mask_type == null || !mask_type.is_mask || mask_type.lane_count != type.lane_count) {
				fail (path, "vector select requires bool<N> mask with matching data lane count");
				return true;
			}
			return true;
		}
		var vector = value as CoreVectorConstructValue;
		if (vector != null) {
			var type = value.semantic_type as VectorType;
			if (type == null || vector.lanes.length != type.lane_count) {
				fail (path, "vector construct requires exact vector type and lane count");
				return true;
			}
			foreach (var lane in vector.lanes) {
				verify_value (lane, function, path + "/lane");
				if (lane.semantic_type != type.element_type) {
					fail (path, "vector construct lane requires exact element type");
				}
			}
			return true;
		}
		var reduction = value as CoreVectorReductionValue;
		if (reduction != null) {
			verify_value (reduction.operand, function, path + "/operand");
			if (!reduction.operator_kind.accepts (reduction.operand.semantic_type, value.semantic_type)) {
				fail (path, "vector reduction requires bool<N> operand and scalar bool result");
			}
			return true;
		}
		if (value is CoreFloatValue) {
			if (!(value.semantic_type is FloatingType) || ((FloatingType) value.semantic_type).format != ((CoreFloatValue) value).value.format) {
				fail (path, "floating constant requires exact canonical type and matching binary format");
			}
			return true;
		}
		// Numeric validity is guaranteed by immutable AstraIntegerValue construction.
		if (value is CoreIntegerValue) {
			if (!(value.semantic_type is IntegerType)) {
				fail (path, "integer literal must have type 'int'");
			}
			if (((CoreIntegerValue) value).value.integer_type != value.semantic_type) {
				fail (path, "integer value must retain its exact semantic type identity");
			}
			return true;
		}
		var load = value as CoreLoadValue;
		if (load != null) {
			if (!VolatileAccessContract.valid (load.volatile_access, load.volatile_enabled, load.source.semantic_type) || (load.volatile_enabled && !(load.source is CoreDereferencePlace || load.source is CoreArrayElementPlace || load.source is CoreSliceElementPlace))) {
				fail (path, "volatile load requires its exact typed memory provenance and flag");
			}
			if (enum_views.contains (load.source) && (!buffer_view_use || !enum_inspections.find (enum_views.lookup (load.source)))) {
				fail (path, "enum inspection view requires a live root and read-only nonescaping use");
			}
			if (load.source is CoreIndirectFieldPlace && ((CoreIndirectFieldPlace) load.source).field.owned_cleanup != null && !(function is CorePropertyGetter && ((CorePropertyGetter) function).property_member.is_borrowed)) {
				fail (path, "owned field reads require an explicit temporary borrow");
			}
			if (owned_places.contains (load.source) && !(load.semantic_type is ClassType) && !owner_null_test) {
				fail (path, "owned local may only be read for null comparison in OWN-1");
			}
			verify_place (load.source, function, true, path + "/source");
			if (field_state != null && load.source is CoreIndirectFieldPlace) {
				var target = (CoreIndirectFieldPlace) load.source;
				if (target.pointer is CoreReceiverValue && !field_state.is_definite (target.field.ordinal)) {
					fail (path, "constructor field read before definite initialization: " + target.field.name);
				}
			}
			if (load.semantic_type != load.source.semantic_type) {
				fail (path, "load result type does not match source place type");
			}
			return true;
		}
		// Slices and object references permit local copies; signature/storage guards enforce noescape.
		var reference = value as CoreParameterValue;
		if (reference != null) {
			if (reference.parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER) {
				fail (path, "owned parameter value may only initialize its owner slot");
			}
			if (reference.parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && !(reference.parameter.semantic_type is StringType) && !(reference.parameter.semantic_type is SliceType) && !(reference.parameter.semantic_type is ClassType) && borrowed_parameter == null && !pointer_comparison && !(receiver_use && (CPlainRecordTypes.pointer (reference.parameter.semantic_type, copy_fields) || ForeignApiTypes.scalar_pointee (reference.parameter.semantic_type) != null))) {
				fail (path, "borrowed parameter cannot escape; only equality or direct borrowed forwarding is permitted");
			}
			if (owners.lookup (reference.parameter) != function) {
				fail (path, "parameter reference is not owned by the containing function");
			}
			if (value.semantic_type != reference.parameter.semantic_type) {
				fail (path, "parameter reference type does not match its declaration");
			}
			return true;
		}
		var capability = value as CoreGenericCapabilityOperation;
		if (capability != null) {
			var parameter = capability.type_parameter;
			var generic_function = active_generic as CoreGenericFunction;
			if (concrete_only || generic_function == null || parameter.ordinal < 0 || parameter.ordinal >= generic_function.type_parameters.length || generic_function.type_parameters[parameter.ordinal] != parameter) {
				fail (path, "unresolved or nonlexical generic capability operation; must disappear before CFG");
			}
			if (!capability.operator_kind.valid () || !capability.capability.valid () || capability.operator_kind.capability () != capability.capability || !capability.operator_kind.accepts (parameter.semantic_type, capability.left.semantic_type, capability.right == null ? null : capability.right.semantic_type, capability.semantic_type)) {
				fail (path, "unauthorized generic capability operation or incorrect exact operand/result shape");
			}
			verify_value (capability.left, function, path + "/left");
			if (capability.right != null) {
				verify_value (capability.right, function, path + "/right");
			}
			return true;
		}
		var prefix = value as CorePrefixValue;
		if (prefix != null) {
			switch (prefix.operator_kind) {
			case PrefixOperator.POSITIVE:
			case PrefixOperator.NEGATIVE:
			case PrefixOperator.BIT_NOT:
			case PrefixOperator.NOT:
				break;
				default:
				fail (path, "unsupported semantic prefix operator");
				break;
			}
			verify_value (prefix.operand, function, path + "/operand");
			if (!prefix.operator_kind.accepts (prefix.operand.semantic_type, value.semantic_type)) {
				fail (path, "invalid operand or result type for semantic prefix operator");
			}
			return true;
		}
		if (value is CoreComparisonChain) {
			var chain = (CoreComparisonChain) value;
			if (chain.operand_count != chain.operands.length || chain.operands.length < 3 || chain.operators.length + 1 != chain.operands.length || value.semantic_type.kind != TypeKind.BOOL) {
				fail (path, "comparison chain lost its scalar bool result or operand/operator arity");
			}
			var seen = new HashTable<CoreValue, bool> (direct_hash, direct_equal);
			var before_tail = field_state == null ? null : field_state.copy ();
			for (int i = 0; i < chain.operands.length; i++) {
				var operand = chain.operands[i];
				if (seen.contains (operand)) {
					fail (path, "comparison chain repeated an operand occurrence");
				}
				seen.insert (operand, true);
				if (i >= 2) {
					if (i == 2 && field_state != null) {
						before_tail = field_state.copy ();
					}
					if (generic_owner_flow != null) {
						generic_owner_flow.begin (GenericOwnershipEventKind.CHOICE, operand.span);
					}
				}
				verify_value (operand, function, path + "/operand%d".printf (i));
				if (!(operand.semantic_type is IntegerType || operand.semantic_type is FloatingType) || operand.semantic_type != chain.operands[0].semantic_type) {
					fail (path, "comparison chain requires one exact scalar numeric type");
				}
				if (i > 0 && (!chain.operators[i - 1].is_relational () || !chain.operators[i - 1].accepts (chain.operands[i - 1].semantic_type, operand.semantic_type, value.semantic_type))) {
					fail (path, "comparison chain requires qualified scalar ordered comparisons");
				}
			}
			for (int i = 2; i < chain.operands.length; i++) {
				if (generic_owner_flow != null) {
					generic_owner_flow.end ();
				}
			}
			if (before_tail != null) {
				field_state = before_tail;
			}
			return true;
		}
		var short_circuit = value as CoreShortCircuitValue;
		if (short_circuit != null) {
			verify_value (short_circuit.left, function, path + "/left");
			bool incoming_reachable = field_state != null && field_state.reachable;
			var constant_left = short_circuit.left as CoreBooleanValue;
			if (field_state != null && constant_left != null && ((short_circuit.operator_kind == ShortCircuitOperator.AND && constant_left.literal == BooleanLiteral.FALSE) || (short_circuit.operator_kind == ShortCircuitOperator.OR && constant_left.literal == BooleanLiteral.TRUE))) {
				field_state.reachable = false;
			}
			int truth = generic_truth (short_circuit.left);
			if (truth != -1 && short_circuit.operator_kind == ShortCircuitOperator.OR) {
				truth = 1 - truth;
			}
			if (generic_owner_flow != null) {
				generic_owner_flow.begin (GenericOwnershipEventKind.CHOICE, value.span, truth);
			}
			verify_value (short_circuit.right, function, path + "/right");
			if (generic_owner_flow != null) {
				generic_owner_flow.end ();
			}
			if (field_state != null) {
				field_state.reachable = incoming_reachable;
			}
			if (!short_circuit.operator_kind.accepts (short_circuit.left.semantic_type, short_circuit.right.semantic_type, value.semantic_type)) {
				fail (path, "invalid operator, operands or result type for short-circuit value");
			}
			return true;
		}
		var binary = value as CoreBinaryValue;
		if (binary != null) {
			if (!binary.operator_kind.is_bitwise () && !binary.operator_kind.is_arithmetic () && !binary.operator_kind.is_relational () && !binary.operator_kind.is_equality ()) {
				fail (path, "unsupported semantic binary operator");
			}
			verify_value (binary.left, function, path + "/left", null, binary.operator_kind.is_equality () && binary.right is CoreNullPointerValue, null, binary.operator_kind.is_equality ());
			verify_value (binary.right, function, path + "/right", null, binary.operator_kind.is_equality () && binary.left is CoreNullPointerValue, null, binary.operator_kind.is_equality ());
			if (!binary.operator_kind.accepts (binary.left.semantic_type, binary.right.semantic_type, value.semantic_type)) {
				fail (path, "invalid operands or result type for semantic binary operator");
			}
			return true;
		}
		return false;
	}

}
}
