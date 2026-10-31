// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Core {
// One registry for the compilation. Identity tables are lookup-only; source
// traversal and a growing FIFO worklist own all discovery/emission ordering.
public class CoreGenericMonomorphizer : Object {
	private GenericArray<EnumDefinition> concrete_enums = new GenericArray<EnumDefinition> ();
	private HashTable<EnumType, bool> active_enums = new HashTable<EnumType, bool> (direct_hash, direct_equal);
	private HashTable<EnumType, EnumDefinition> enum_definitions = new HashTable<EnumType, EnumDefinition> (direct_hash, direct_equal);
	private CoreProgram program;
	private GenericArray<CoreFunction> instances = new GenericArray<CoreFunction> ();
	private GenericArray<CoreGenericFunction> origins = new GenericArray<CoreGenericFunction> ();
	private HashTable<GenericRequestKey, CoreFunction> registry = new HashTable<GenericRequestKey, CoreFunction> (GenericRequestKey.hash, GenericRequestKey.equal);
	public GenericArray<CoreStruct> struct_instances { get; private set; default = new GenericArray<CoreStruct> (); }
	private HashTable<CoreGenericStructIdentity, GenericArray<CoreStruct>> struct_registry = new HashTable<CoreGenericStructIdentity, GenericArray<CoreStruct>> (direct_hash, direct_equal);
	private GenericArray<GenericStructInstance> materializing = new GenericArray<GenericStructInstance> ();
	private GenericArray<FunctionValueType> concrete_functions = new GenericArray<FunctionValueType> ();
	private GenericArray<ClosureHandleType> concrete_closures = new GenericArray<ClosureHandleType> ();
	private HashTable<SemanticType, SemanticType> callable_types = new HashTable<SemanticType, SemanticType> (direct_hash, direct_equal);
	private HashTable<SemanticType, SemanticType> collection_types = new HashTable<SemanticType, SemanticType> (direct_hash, direct_equal);
	private HashTable<SemanticType, SliceType> concrete_slices = new HashTable<SemanticType, SliceType> (direct_hash, direct_equal);
	private HashTable<SemanticType, TypedPointerType> struct_pointers = new HashTable<SemanticType, TypedPointerType> (direct_hash, direct_equal);
	private HashTable<Object, bool> counted_instances = new HashTable<Object, bool> (direct_hash, direct_equal);
	private void require_type_depth(SemanticType type, string context) throws CoreError {
		if (!GenericResourceLimits.admits_type (type)) {
			throw new CoreError.INVALID_IR ("generic materialization limit exceeded: type-expression depth %d while requesting %s", GenericResourceLimits.TYPE_DEPTH, context);
		}
	}
	private void reserve_instance(Object identity, string context) throws CoreError {
		if (counted_instances.contains (identity)) {
			return;
		}
		if (counted_instances.size () >= GenericResourceLimits.CLOSED_INSTANCES) {
			throw new CoreError.INVALID_IR ("generic materialization limit exceeded: at most %u closed instances; requesting %s", GenericResourceLimits.CLOSED_INSTANCES, context);
		}
		counted_instances.insert (identity, true);
	}

	private GenericArray<SemanticType>? copy_fields(SemanticType type) {
		if (type is EnumType) {
			var definition = enum_definitions.lookup ((EnumType) type);
			if (definition == null) {
				foreach (var candidate in program.enums) {
					if (candidate.semantic_type == type) {
						definition = candidate;
						break;
					}
				}
			}
			return definition == null ? null : definition.value_fields ();
		}
		var fields = new GenericArray<SemanticType> ();
		var application = type as CoreGenericStructApplicationType;
		if (application != null && application.definition != null) {
			foreach (var field in application.definition.fields) {
				fields.add (application.field_type (field));
			}
			return fields;
		}
		foreach (var structure in program.structs) {
			if (structure.semantic_type == type) {
				foreach (var field in structure.fields) {
					fields.add (field.semantic_type);
				}
				return fields;
			}
		}
		foreach (var structure in struct_instances) {
			if (structure.semantic_type == type && structure.generic_instance.state == GenericStructInstanceState.COMPLETE) {
				foreach (var field in structure.fields) {
					fields.add (field.semantic_type);
				}
				return fields;
			}
		}
		return null;
	}

	private GenericArray<CoreCleanupContract> concrete_cleanups = new GenericArray<CoreCleanupContract> ();
	private HashTable<CoreGenericFunction, GenericResultOrigins> result_origins;
	private CoreResultOriginProjection result_projection;
	internal HashTable<CoreOwnedLocal, GenericResultOrigins> local_origins(CoreGenericFunction function, GenericArray<SemanticType> arguments, TypeSubstitution substitution) throws CoreError {
		result_projection.project (function, arguments);
		return CoreGenericResultOrigins.projected_locals (function, result_projection, substitution);
	}
	internal CoreGenericMonomorphizer (CoreProgram program) throws CoreError {
		this.program = program;
		result_origins = CoreGenericResultOrigins.derive (program);
		result_projection = new CoreResultOriginProjection (program);
		foreach (var owner in program.classes) {
			if (owner.generic_instance != null) {
				require_type_depth (owner.semantic_type, owner.name);
				reserve_instance (owner.generic_instance, owner.name);
			}
		}
		foreach (var structure in program.structs) {
			if (structure.generic_instance != null) {
				reserve_instance (structure.generic_instance, structure.name);
			}
		}
		foreach (var function in program.functions) {
			if (function.generic_instance != null) {
				reserve_instance (function.generic_instance, function.name);
			}
			var method = function as CoreMethod;
			if (method != null && method.generic_method_instance != null) {
				reserve_instance (method.generic_method_instance, method.name);
			}
		}
		foreach (var definition in program.enums) {
			if (!definition.semantic_type.is_parameterized () && definition.semantic_type.argument_count != 0) {
				reserve_instance (definition.semantic_type, definition.semantic_type.display_name ());
			}
		}
		// Filtering responsibility descriptors preserves identity and relative order.
		// Stage-owned inventories remain dense even for independently authored Core.
		foreach (var cleanup in program.cleanups) {
			bool symbolic_class = cleanup.is_symbolic_object;
			bool symbolic_closure = cleanup.closure_type != null && cleanup.closure_type.is_parameterized ();
			if (cleanup.type_parameter == null && !cleanup.is_symbolic_buffer && !symbolic_class && !symbolic_closure) {
				cleanup.ordinal = (int) concrete_cleanups.length;
				concrete_cleanups.add (cleanup);
			}
		}
	}

	internal CoreCleanupContract? concrete_contract(CoreCleanupContract? contract, TypeSubstitution substitution, bool heap = false) throws CoreError {
		if (contract != null && contract.closure_type != null && contract.closure_type.is_parameterized ()) {
			var type = concrete_type (contract.closure_type, substitution, contract);
			foreach (var handle in program.handles) {
				if (handle.semantic_type == type || callable_types.lookup (handle.semantic_type) == type) {
					return handle.cleanup;
				}
			}
			throw new CoreError.INVALID_IR ("closure specialization lost exact concrete carrier cleanup");
		}
		if (contract != null && contract.is_symbolic_buffer) {
			var slice = (SliceType) concrete_type (contract.buffer_type, substitution, contract);
			var shape = new BufferValueShape (slice, contract.buffer_shape.base_type, contract.buffer_shape.length_type);
			if (!shape.is_valid (copy_fields)) {
				throw new CoreError.INVALID_IR ("buffer specialization requires complete concrete storage, copy, zero and destruction proofs");
			}
			foreach (var cleanup in concrete_cleanups) {
				if (cleanup.is_buffer && cleanup.buffer_type == slice) {
					return cleanup;
				}
			}
			var result = new CoreCleanupContract.for_buffer (shape, contract.symbol_span, concrete_cleanups.length);
			concrete_cleanups.add (result);
			return result;
		}
		bool object_contract = contract != null && contract.is_object;
		if (contract == null || contract.type_parameter == null && !object_contract) {
			return contract;
		}
		if (object_contract) {
			heap |= contract.is_heap_object;
			if (!contract.is_symbolic_object && heap == contract.is_heap_object) {
				return contract;
			}
		}
		var type = object_contract ? concrete_type (contract.object_class.semantic_type, substitution, contract) : substitution.apply (contract.type_parameter);
		if (type is TypeParameterType || !GenericCapabilityAuthority.satisfies (type, GenericCapabilityIdentity.OWNABLE)) {
			throw new CoreError.INVALID_IR ("ownership specialization requires a concrete Ownable identity");
		}
		foreach (var handle in program.handles) {
			if (handle.semantic_type == type) {
				return handle.cleanup;
			}
		}
		foreach (var cleanup in concrete_cleanups) {
			if (cleanup.is_object && cleanup.is_heap_object == heap && cleanup.object_class.semantic_type == type) {
				return cleanup;
			}
		}
		foreach (var object_class in program.classes) {
			if (object_class.semantic_type != type) {
				continue;
			}
			var cleanup = new CoreCleanupContract.for_object (object_class, concrete_cleanups.length, heap);
			concrete_cleanups.add (cleanup);
			return cleanup;
		}
		throw new CoreError.INVALID_IR ("ownership specialization lost exact Resource/Class contract authority");
	}

	// Consumes ordinary bodies in place, preserving their exact global targets.
	// The returned program owns all concrete functions and no generic body graph.
	public static CoreProgram build(CoreProgram program) throws CoreError {
		CoreVerifier.verify (program);
		var pass = new CoreGenericMonomorphizer (program);
		if (program.generic_functions.length == 0 && program.generic_structs.length == 0 && !has_generic_enums (program)) {
			CoreVerifier.verify_concrete (program);
			return program;
		}
		foreach (var definition in program.enums) {
			if (!definition.semantic_type.is_parameterized ()) {
				pass.enum_definition (definition);
			}
		}
		foreach (var cleanup in program.cleanups) {
			if (!cleanup.is_buffer || cleanup.is_symbolic_buffer) {
				continue;
			}
			var shape = cleanup.buffer_shape;
			cleanup.buffer_shape = new BufferValueShape ((SliceType) pass.concrete_type (shape.slice_type, new TypeSubstitution (), cleanup), shape.base_type, shape.length_type);
		}
		var class_arguments = new GenericArray<ClassTypeArgument> ();
		foreach (var argument in program.class_type_arguments) {
			CoreClass? owner = null;
			foreach (var candidate in program.classes) {
				if (candidate.semantic_type == argument.owner_type) {
					owner = candidate;
				}
			}
			var type = pass.concrete_type (argument.semantic_type, new TypeSubstitution (), owner);
			class_arguments.add (new ClassTypeArgument (argument.owner_type, argument.ordinal, type));
		}
		var handles = new GenericArray<CoreHandle> ();
		foreach (var handle in program.handles) {
			if (handle.semantic_type.is_parameterized ()) {
				continue;
			}
			var type = (HandleType) pass.concrete_type (handle.semantic_type, new TypeSubstitution (), handle);
			if (handle.cleanup.closure_type != null) {
				handle.cleanup.closure_type = (ClosureHandleType) type;
			}
			var mapped = new CoreHandle (handle.span, handle.name_span, type, handle.cleanup, handle.header, handles.length, handle.context_mode);
			mapped.com_import = handle.com_import == null ? null : handle.com_import.copy ();
			mapped.c_import = handle.c_import;
			handles.add (mapped);
		}
		foreach (var owner in program.native_instances ()) {
			var record = owner as CoreStruct;
			if (record != null) {
				for (int a = 0; a < record.owning_arguments.length; a++) {
					record.owning_arguments[a] = pass.concrete_type (record.owning_arguments[a], new TypeSubstitution (), record);
				}
			}
			foreach (var field in owner.fields) {
				field.semantic_type = pass.concrete_type (field.semantic_type, new TypeSubstitution (), owner);
			}
			foreach (var property in owner.properties) {
				property.semantic_type = pass.concrete_type (property.semantic_type, new TypeSubstitution (), owner);
			}
		}
		foreach (var root in program.functions) {
			var method = root as CoreMethod;
			if (method != null && method.generic_method_instance != null) {
				var arguments = new GenericArray<SemanticType> ();
				foreach (var argument in method.generic_method_instance.arguments.copy_values ()) {
					arguments.add (pass.concrete_type (argument, new TypeSubstitution (), root));
				}
				method.generic_method_instance = method.generic_method_instance.copy (new TypeArgumentVector (arguments));
			}
			root.return_type = pass.concrete_type (root.return_type, new TypeSubstitution (), root);
			if (root.struct_result_contract != null) {
				root.struct_result_contract = new StructValueContract (root.return_type, root.struct_result_contract.mode);
			}
			foreach (var parameter in root.parameters) {
				parameter.semantic_type = pass.concrete_type (parameter.semantic_type, new TypeSubstitution (), root);
				if (parameter.struct_value_contract != null) {
					parameter.struct_value_contract = new StructValueContract (parameter.semantic_type, parameter.struct_value_contract.mode);
				}
			}
		}
		foreach (var root in program.functions) {
			new CoreInstanceCloner (pass, root, root, new TypeSubstitution ()).build ();
		}
		for (int i = 0; i < pass.instances.length; i++) {
			var function = pass.instances[i];
			var origin = pass.origins[i];
			new CoreInstanceCloner (pass, origin, function, origin.substitution (function.generic_instance.type_arguments)).build ();
			function.generic_instance.state = GenericInstanceState.COMPLETE;
		}
		var functions = new GenericArray<CoreFunction> ();
		foreach (var root in program.functions) {
			functions.add (root);
		}
		foreach (var instance in pass.instances) {
			functions.add (instance);
		}
		var structures = new GenericArray<CoreStruct> ();
		foreach (var structure in program.structs) {
			structures.add (structure);
		}
		foreach (var structure in pass.struct_instances) {
			structures.add (structure);
		}
		var result = new CoreProgram (program.span, functions, program.c_functions, program.c_exports, structures, pass.concrete_cleanups, handles);
		foreach (var argument in class_arguments) {
			result.class_type_arguments.add (argument);
		}
		result.exception_bool_type = program.exception_bool_type;
		foreach (var definition in pass.concrete_enums) {
			result.enums.add (definition);
		}
		foreach (var payload in program.text_literals) {
			result.text_literals.add (payload);
		}
		foreach (var object_class in program.classes) {
			result.classes.add (object_class);
		}
		foreach (var definition in program.generic_classes) {
			result.generic_classes.add (definition);
		}
		CoreVerifier.verify_concrete (result);
		return result;
	}

	private static bool has_generic_enums(CoreProgram program) {
		foreach (var definition in program.enums) {
			if (definition.semantic_type.is_parameterized ()) {
				return true;
			}
		}
		return false;
	}

	internal EnumDefinition enum_definition(EnumDefinition source, TypeSubstitution? substitution = null) throws CoreError {
		var type = (EnumType) (substitution == null ? source.semantic_type : substitution.apply (source.semantic_type));
		require_type_depth (type, source.semantic_type.display_name ());
		var cached = enum_definitions.lookup (type);
		if (cached != null) {
			return cached;
		}
		if (type.is_parameterized () || active_enums.contains (type) || active_enums.size () >= 256) {
			throw new CoreError.INVALID_IR ("enum materialization requires exact concrete arguments and an acyclic bounded expansion");
		}
		if (type.argument_count != 0) {
			reserve_instance (type, type.display_name ());
		}
		active_enums.insert (type, true);
		var variants = new GenericArray<EnumVariant> ();
		for (uint v = 0; v < source.variant_count; v++) {
			var variant = source.variant (v);
			var identity = type == source.semantic_type ? variant.identity : new EnumVariantIdentity (type.identity, variant.identity.name, variant.identity.ordinal);
			var fields = new GenericArray<EnumField> ();
			for (uint f = 0; f < variant.field_count; f++) {
				var field = variant.field (f);
				fields.add (new EnumField (identity == variant.identity ? field.identity : new EnumFieldIdentity (identity, field.identity.name, field.identity.ordinal), concrete_type (field.semantic_type, substitution ?? new TypeSubstitution (), source), field.span, field.owns_buffer, field.owned_cleanup, field.owns_child, field.owns_record));
			}
			variants.add (new EnumVariant (identity, variant.span, fields));
		}
		var result = new EnumDefinition (type, source.span, variants, source.tag_type);
		enum_definitions.insert (type, result);
		concrete_enums.add (result);
		active_enums.remove (type);
		return result;
	}

	internal EnumDefinition enum_definition_for_type(EnumType type) throws CoreError {
		var definition = enum_definitions.lookup (type);
		if (definition == null) {
			throw new CoreError.INVALID_IR ("missing completed enum specialization");
		}
		return definition;
	}

	internal GenericArray<CoreNativeInstance> native_instances() {
		return program.native_instances ();
	}

	internal CoreClass concrete_class(CoreClass original, TypeSubstitution substitution) throws CoreError {
		var type = concrete_type (original.semantic_type, substitution, original);
		foreach (var owner in program.classes) {
			if (owner.semantic_type == type) {
				return owner;
			}
		}
		throw new CoreError.INVALID_IR ("Class specialization lost its exact physical declaration");
	}

	internal CoreStruct concrete_struct(SemanticType type) throws CoreError {
		foreach (var structure in program.structs) {
			if (structure.semantic_type == type) {
				return structure;
			}
		}
		foreach (var structure in struct_instances) {
			if (structure.semantic_type == type && structure.generic_instance.state == GenericStructInstanceState.COMPLETE) {
				return structure;
			}
		}
		throw new CoreError.INVALID_IR ("missing completed concrete struct identity");
	}

	internal SemanticType concrete_type(SemanticType original, TypeSubstitution substitution, Object requester) throws CoreError {
		var type = substitution.apply (original);
		if (type is ReceiverType && ((ReceiverType) type).instance_type.is_parameterized ()) {
			var receiver = (ReceiverType) type;
			var instance = concrete_type (receiver.instance_type, substitution, requester);
			foreach (var function in program.all_definitions ()) {
				if (function.implicit_receiver != null && function.implicit_receiver.contract.instance_type == instance && function.implicit_receiver.contract.mode == receiver.mode) {
					return function.implicit_receiver.contract;
				}
			}
			throw new CoreError.INVALID_IR ("Class specialization lost its declared receiver contract");
		}
		if (type is ExactGenericClassType) {
			var application = (ExactGenericClassType) type;
			if (application.is_parameterized ()) {
				throw new CoreError.INVALID_IR ("Class specialization requires closed arguments");
			}
			foreach (var owner in program.native_instances ()) {
				var actual = owner.semantic_type as ExactGenericClassType;
				if (actual != null && actual.definition == application.definition && actual.arguments.matches_identities (application.arguments)) {
					return actual;
				}
			}
			throw new CoreError.INVALID_IR ("Class specialization requires its exact materialized declaration");
		}
		if (type is CallableSignature) {
			var prior = callable_types.lookup (type);
			if (prior != null) {
				return prior;
			}
			var parameters = new GenericArray<SemanticType> ();
			foreach (var parameter in ((CallableSignature) type).parameter_types) {
				parameters.add (concrete_type (parameter, substitution, requester));
			}
			var closure = type as ClosureHandleType;
			var environment = closure == null ? null : (ClassType) concrete_type (closure.environment_type, substitution, requester);
			var mapped = CallableTypes.with_parameters (type, parameters, concrete_type (CallableTypes.result_type (type), substitution, requester), environment);
			if (mapped is FunctionValueType) {
				var function = (FunctionValueType) mapped;
				bool present = false;
				foreach (var candidate in concrete_functions) {
					if (candidate.result_type != function.result_type || candidate.result_contract != function.result_contract || candidate.parameter_types.length != function.parameter_types.length) {
						continue;
					}
					bool same = true;
					for (int p = 0; p < function.parameter_types.length; p++) {
						same &= candidate.parameter_types[p] == function.parameter_types[p] && candidate.parameter_contract (p) == function.parameter_contract (p);
					}
					if (same) {
						mapped = candidate;
						present = true;
						break;
					}
				}
				if (!present) {
					concrete_functions.add (function);
				}
			} else {
				// Closure carriers are nominal handles with one declaration-owned
				// destructor. Reuse that exact closed signature after substitution.
				bool present = false;
				var exact = new TypeSubstitution ();
				foreach (var candidate in concrete_closures) {
					if (!exact.matches (mapped, candidate)) {
						continue;
					}
					mapped = candidate;
					present = true;
					break;
				}
				if (!present) {
					bool declared = false;
					foreach (var handle in program.handles) {
						declared |= handle.semantic_type == type && !type.is_parameterized ();
					}
					if (!declared) {
						throw new CoreError.INVALID_IR ("closure specialization requires its exact concrete carrier declaration");
					}
					concrete_closures.add ((ClosureHandleType) mapped);
				}
			}
			try {
				if (mapped is FunctionValueType) {
					((FunctionValueType) mapped).complete_records (copy_fields);
				} else {
					((ClosureHandleType) mapped).complete_records (copy_fields);
				}
			} catch (StructLeafError error) {
				throw new CoreError.INVALID_IR (error.message);
			}
			callable_types.insert (type, mapped);
			return mapped;
		}
		if (type is EnumType) {
			foreach (var definition in program.enums) {
				if (definition.semantic_type == original) {
					return enum_definition (definition, substitution).semantic_type;
				}
			}
			foreach (var definition in concrete_enums) {
				if (definition.semantic_type == type) {
					return type;
				}
			}
			throw new CoreError.INVALID_IR ("enum specialization lost its exact source definition");
		}
		if (type is SliceType) {
			var cached = collection_types.lookup (type);
			if (cached != null) {
				return cached;
			}
			var element = concrete_type (((SliceType) type).element_type, substitution, requester);
			// Context-backed owners and ordinary views have different cleanup
			// authority even when their element types are identical.
			var slice = element == ((SliceType) type).element_type ? (SliceType) type : new SliceType (element);
			var key = slice.canonical_key ();
			var prior = concrete_slices.lookup (key);
			if (prior == null) {
				prior = slice;
				concrete_slices.insert (key, prior);
			}
			collection_types.insert (type, prior);
			return prior;
		}
		if (type is ArrayType) {
			var prior = collection_types.lookup (type);
			if (prior != null) {
				return prior;
			}
			var element = ((ArrayType) type).element_type;
			var mapped = concrete_type (element, substitution, requester);
			SemanticType result = mapped == element ? type : new ArrayType (mapped, ((ArrayType) type).length);
			collection_types.insert (type, result);
			return result;
		}
		if (type is TypeParameterType) {
			throw new CoreError.INVALID_IR ("incomplete exact type substitution");
		}
		if (type is CoreGenericStructApplicationType) {
			return request_struct ((CoreGenericStructApplicationType) type, requester).semantic_type;
		}
		var pointer = type as TypedPointerType;
		if (pointer != null && pointer.pointee is CoreGenericStructApplicationType) {
			if (pointer.pointee.is_parameterized ()) {
				throw new CoreError.INVALID_IR ("parameterized generic Struct* is deferred");
			}
			var pointee = request_struct ((CoreGenericStructApplicationType) pointer.pointee, requester).semantic_type;
			var result = struct_pointers.lookup (pointee);
			if (result == null) {
				result = new TypedPointerType (pointee);
				struct_pointers.insert (pointee, result);
			}
			return result;
		}
		return type;
	}

	private string requester_label(Object requester) {
		if (requester is CoreClass) {
			return "class#%d:%s".printf (((CoreClass) requester).ordinal, ((CoreClass) requester).name);
		}
		if (requester is GenericStructInstance) {
			return "struct#%d:%s".printf (((GenericStructInstance) requester).ordinal, ((GenericStructInstance) requester).display_name ());
		}
		if (requester is GenericFunctionInstance) {
			return "function#%d:%s".printf (((GenericFunctionInstance) requester).ordinal, ((GenericFunctionInstance) requester).symbol_name ());
		}
		for (int i = 0; i < program.functions.length; i++) {
			if (program.functions[i] == requester) {
				return "root#%d:%s".printf (i, program.functions[i].name);
			}
		}
		return "<unregistered requester>";
	}

	internal CoreStruct request_struct(CoreGenericStructApplicationType application, Object requester) throws CoreError {
		var origin = application.definition;
		bool present = false;
		foreach (var definition in program.generic_structs) {
			if (definition == origin) {
				present = true;
			}
		}
		if (!present || origin == null || application.origin != origin.identity || application.type_arguments.length != origin.type_parameters.length) {
			throw new CoreError.INVALID_IR ("generic struct request requires exact program-owned definition and arity");
		}
		require_type_depth (application, origin.name);
		var arguments = new GenericArray<SemanticType> ();
		foreach (var argument in application.type_arguments) {
			arguments.add (concrete_type (argument, new TypeSubstitution (), requester));
		}
		foreach (var argument in arguments) {
			if (!GenericArgumentTypes.supports (argument, copy_fields)) {
				throw new CoreError.INVALID_IR ("struct instance key requires complete concrete GEN1_PLAIN_COPY identities (maximum type-application depth 256)");
			}
		}
		if (!origin.identity.nominal_identity.admits (arguments)) {
			throw new CoreError.INVALID_IR ("native module: closed record application is not exported: " + origin.identity.nominal_identity.application_name (arguments));
		}
		var bucket = struct_registry.lookup (origin.identity);
		if (bucket == null) {
			bucket = new GenericArray<CoreStruct> ();
			struct_registry.insert (origin.identity, bucket);
		}
		CoreStruct? structure = null;
		foreach (var candidate in bucket) {
			if (candidate.generic_instance.matches (origin.identity, arguments)) {
				structure = candidate;
				break;
			}
		}
		if (structure == null) {
			if (materializing.length >= 256) {
				throw new CoreError.INVALID_IR ("generic materialization limit exceeded: at most 256 active struct dependencies while requesting %s", application.display_name ());
			}
			var instance = new GenericStructInstance (origin, arguments, struct_instances.length);
			reserve_instance (instance, origin.name + new TypeArgumentVector (arguments).display_suffix (true));
			var type = new StructType (instance.symbol_name ());
			type.bind_generic_application (origin.identity.nominal_identity, arguments);
			structure = new CoreStruct (origin.span, origin.name_span, instance.symbol_name (), type, (int) program.structs.length + (int) struct_instances.length);
			structure.generic_instance = instance;
			instance.attach (structure);
			// Register BEFORE following any by-value field dependencies.
			bucket.add (structure);
			struct_instances.add (structure);
		}
		var instance = structure.generic_instance;
		instance.requests++;
		bool known = false;
		foreach (var prior in instance.requesters) {
			if (prior.identity == requester) {
				known = true;
			}
		}
		if (!known) {
			instance.requesters.add (new GenericStructRequester (requester, requester_label (requester)));
		}
		if (instance.state == GenericStructInstanceState.COMPLETE) {
			return structure;
		}
		if (instance.state == GenericStructInstanceState.MATERIALIZING) {
			var path = new StringBuilder ();
			foreach (var active in materializing) {
				path.append (active.display_name () + " → ");
			}
			throw new CoreError.INVALID_IR ("recursive generic struct layout: " + path.str + instance.display_name ());
		}
		instance.state = GenericStructInstanceState.MATERIALIZING;
		materializing.add (instance);
		var substitution = origin.substitution (arguments);
		foreach (var field in origin.fields) {
			var type = concrete_type (field.semantic_type, substitution, instance);
			if (!NativeFieldTypes.supports (type, true)) {
				throw new CoreError.INVALID_IR ("unsupported concrete generic struct field type");
			}
			var concrete = new CoreStructField (field.span, field.name_span, field.name, structure, type, field.ordinal, field.identity);
			structure.fields.add (concrete);
			instance.map_field (field, concrete);
		}
		materializing.remove_index (materializing.length - 1);
		instance.state = GenericStructInstanceState.COMPLETE;
		return structure;
	}

	internal CoreFunction request(CoreGenericFunction origin, GenericArray<SemanticType> arguments, CoreFunction caller, int heap_owned_parameter = -1, GenericStorageVector? storage = null) throws CoreError {
		bool present = false;
		foreach (var definition in program.generic_functions) {
			if (origin == definition) {
				present = true;
			}
		}
		if (!present) {
			throw new CoreError.INVALID_IR ("generic request requires the exact program-owned definition");
		}
		foreach (var type in arguments) {
			require_type_depth (type, origin.name);
			if (type.is_parameterized ()) {
				throw new CoreError.INVALID_IR ("instance key requires concrete semantic types");
			}
		}
		var canonical = new GenericArray<SemanticType> (arguments.length);
		foreach (var argument in arguments) {
			canonical.add (concrete_type (argument, new TypeSubstitution (), caller));
		}
		arguments = canonical;
		origin.verify_capability_arguments (arguments, copy_fields);
		var substitution = origin.substitution (arguments);
		var allocation = storage ?? new GenericStorageVector.single (heap_owned_parameter);
		if (!allocation.valid ((int) origin.parameters.length)) {
			throw new CoreError.INVALID_IR ("generic storage vector requires exact parameter positions");
		}
		for (int p = 0; p < allocation.count; p++) {
			var parameter = origin.parameters[allocation.parameter (p)];
			var actual = substitution.apply (parameter.semantic_type);
			if (!(parameter.semantic_type is TypeParameterType || parameter.semantic_type is ClassType) || parameter.pointer_contract != PointerParameterContract.OWNED_TRANSFER || !(actual is ClassType)) {
				throw new CoreError.INVALID_IR ("generic heap storage position requires an owned Class specialization");
			}
		}
		var key = new GenericRequestKey (origin.identity, new TypeArgumentVector (arguments), -1, allocation);
		var function = registry.lookup (key);
		if (function != null && !function.generic_instance.matches (origin.identity, arguments, -1, allocation)) {
			throw new CoreError.INVALID_IR ("generic cache lost its exact canonical instance key");
		}
		if (function == null) {
			var result_type = concrete_type (origin.return_type, substitution, origin);
			bool heap_result = origin.heap_result;
			if (origin.owned_cleanup != null && (origin.return_type is TypeParameterType || origin.return_type is ClassType) && result_type is ClassType) {
				var heaps = new bool[origin.parameters.length];
				foreach (var parameter in origin.parameters) {
					heaps[parameter.ordinal] = parameter.heap_object || allocation.is_heap (parameter.ordinal);
				}
				var equation = result_origins.lookup (origin);
				if ((equation.domains & GenericResultOrigins.UNKNOWN) != 0) {
					equation = result_projection.project (origin, arguments);
				}
				uint domains = equation.evaluate (heaps);
				if ((domains & GenericResultOrigins.UNKNOWN) != 0) {
					throw new CoreError.INVALID_IR ("generic Class result still requires concrete producer-origin projection");
				}
				if (domains == (GenericResultOrigins.CALLER | GenericResultOrigins.HEAP)) {
					throw new CoreError.INVALID_IR ("generic Class result joins incompatible heap and caller-backed storage origins");
				}
				heap_result = domains == GenericResultOrigins.HEAP;
			}
			var identity = new GenericFunctionInstance (origin, arguments, instances.length, -1, heap_result, allocation);
			reserve_instance (identity, origin.name + new TypeArgumentVector (arguments).display_suffix (true) + " from " + caller.name);
			var parameters = new GenericArray<CoreParameter> ();
			foreach (var parameter in origin.parameters) {
				var cloned = new CoreParameter (parameter.span, parameter.name_span, parameter.name, concrete_type (parameter.semantic_type, substitution, identity), parameter.ordinal, parameter.pointer_contract);
				cloned.heap_object = parameter.heap_object || allocation.is_heap (parameter.ordinal);
				if (parameter.requires_nonnull) {
					cloned.mark_nonnull ();
				}
				parameters.add (cloned);
			}
			function = new CoreFunction (origin.span, origin.name_span, identity.symbol_name (), result_type, parameters, new GenericArray<CoreLocalPlace> (), new CoreBlock (origin.body.span, new GenericArray<CoreStatement> ()), concrete_contract (origin.owned_cleanup, substitution, heap_result));
			function.generic_instance = identity;
			function.bind_floating_policy (origin.floating_policy);
			function.throws_type = origin.throws_type;
			function.heap_result = heap_result;
			if (origin.nonnull_result) {
				function.mark_nonnull_result ();
			}
			if (function.owned_cleanup != null && function.owned_cleanup.is_object && !function.heap_result) {
				function.result_storage = new CoreResultObjectStorage (origin.span, function.owned_cleanup.object_class);
			}
			// Register the complete concrete signature BEFORE any body traversal.
			registry.insert (key, function);
			instances.add (function);
			origins.add (origin);
		}
		function.generic_instance.requests++;
		bool known_caller = false;
		foreach (var site in function.generic_instance.callers) {
			if (site.function == caller) {
				known_caller = true;
			}
		}
		if (!known_caller) {
			string label = caller.name;
			for (int i = 0; i < program.functions.length; i++) {
				if (program.functions[i] == caller) {
					label = "root#%d:%s".printf (i, caller.name);
					break;
				}
			}
			function.generic_instance.callers.add (new GenericInstanceCaller (caller, label));
		}
		return function;
	}
}

// Exhaustive semantic Core cloning. Every instance-local identity is mapped;
// immutable global callable/member/type/cleanup authorities are retained.
private class CoreInstanceCloner : Object {
	private CoreGenericMonomorphizer pass;
	private CoreFunction source;
	private CoreFunction target;
	private TypeSubstitution substitution;
	private bool in_place;
	private HashTable<CoreParameter, CoreParameter> parameters = new HashTable<CoreParameter, CoreParameter> (direct_hash, direct_equal);
	private HashTable<CoreParameter, CoreLocalPlace> parameter_storage = new HashTable<CoreParameter, CoreLocalPlace> (direct_hash, direct_equal);
	private HashTable<CorePlace, CorePlace> places = new HashTable<CorePlace, CorePlace> (direct_hash, direct_equal);
	private HashTable<CoreBlock, CoreBlock> blocks = new HashTable<CoreBlock, CoreBlock> (direct_hash, direct_equal);
	private HashTable<CoreObjectStorage, CoreObjectStorage> storages = new HashTable<CoreObjectStorage, CoreObjectStorage> (direct_hash, direct_equal);
	private HashTable<CoreOwnedLocal, CoreOwnedLocal> owners = new HashTable<CoreOwnedLocal, CoreOwnedLocal> (direct_hash, direct_equal);
	private HashTable<CoreLoopTarget, CoreLoopTarget> loops = new HashTable<CoreLoopTarget, CoreLoopTarget> (direct_hash, direct_equal);
	private HashTable<CoreWithContract, CoreWithContract> with_contracts = new HashTable<CoreWithContract, CoreWithContract> (direct_hash, direct_equal);
	private CoreWithContract with_contract(CoreWithContract source) throws CoreError {
		var result = with_contracts.lookup (source);
		if (result == null) {
			result = new CoreWithContract (source.span, (CoreLocalPlace) place (source.source), source.receiver_type);
			with_contracts.insert (source, result);
		}
		return result;
	}
	private HashTable<CoreIterationContract, CoreIterationContract> iterations = new HashTable<CoreIterationContract, CoreIterationContract> (direct_hash, direct_equal);
	private CoreIterationContract? iteration(CoreIterationContract? source) throws CoreError {
		if (source == null) {
			return null;
		}
		var result = iterations.lookup (source);
		if (result == null) {
			result = new CoreIterationContract (source.span, loops.lookup (source.target), (CoreIndirectFieldPlace) place (source.store), (CoreLocalPlace) place (source.index), source.binding == null ? null : (CoreLocalPlace) place (source.binding));
			iterations.insert (source, result);
		}
		return result;
	}
	private HashTable<CorePlace, HashTable<CoreStructField, CoreFieldPlace>> projections = new HashTable<CorePlace, HashTable<CoreStructField, CoreFieldPlace>> (direct_hash, direct_equal);

	internal CoreInstanceCloner (CoreGenericMonomorphizer pass, CoreFunction source, CoreFunction target, TypeSubstitution substitution) {
		this.pass = pass;
		this.source = source;
		this.target = target;
		this.substitution = substitution;
		this.in_place = source == target;
	}

	internal void build() throws CoreError {
		for (int p = 0; p < source.parameters.length; p++) {
			parameters.insert (source.parameters[p], target.parameters[p]);
		}
		if (!in_place) {
			foreach (var parameter in source.parameters) {
				var concrete = parameters.lookup (parameter);
				if (parameter.struct_value_contract != null || parameter.semantic_type is EnumType || (concrete.struct_value_contract == null && !(concrete.semantic_type is EnumType))) {
					continue;
				}
				var local = new CoreLocalPlace (parameter.span, parameter.name_span, parameter.name, concrete.semantic_type, target.locals.length, false, concrete);
				parameter_storage.insert (parameter, local);
				target.locals.add (local);
			}
		}
		foreach (var local in source.locals) {
			if (in_place) {
				local.semantic_type = type (local.semantic_type);
			}
			var result = in_place ? local : new CoreLocalPlace (local.span, local.name_span, local.name, type (local.semantic_type), target.locals.length, local.address_taken, local.incoming_parameter == null ? null : parameters.lookup (local.incoming_parameter));
			if (local.requires_nonnull) {
				result.mark_nonnull ();
			}
			result.text_extent = local.text_extent;
			result.text_loan = local.text_loan;
			places.insert (local, result);
			if (!in_place) {
				target.locals.add (result);
			}
		}
		prepare_blocks (source.body, target.body);
		foreach (var storage in source.object_storage) {
			var result = in_place ? storage : new CoreObjectStorage (storage.span, pass.concrete_class (storage.object_class, substitution), storage.ordinal, storage.region_ordinal, blocks.lookup (storage.scope), storage.fallible);
			result.heap_allocated = storage.heap_allocated;
			result.cleanup_rank = storage.cleanup_rank + (in_place ? 0 : (int) parameter_storage.size ());
			result.transferable = storage.transferable;
			result.result_candidate = storage.result_candidate;
			storages.insert (storage, result);
			if (!in_place) {
				target.object_storage.add (result);
			}
		}
		foreach (var owner in source.owned_locals) {
			var result = in_place ? owner : new CoreOwnedLocal (owner.span, (CoreLocalPlace) place (owner.place), owner_contract (owner), blocks.lookup (owner.scope), owner.object_storage == null ? null : storages.lookup (owner.object_storage));
			owners.insert (owner, result);
			if (!in_place) {
				target.owned_locals.add (result);
			}
		}
		foreach (var field in source.field_places) {
			if (in_place) {
				field.semantic_type = type (field.semantic_type);
			}
			var mapped = in_place ? field : (CoreFieldPlace) place (field);
			places.insert (field, mapped);
			var projected = projections.lookup (mapped.aggregate);
			if (projected == null) {
				projected = new HashTable<CoreStructField, CoreFieldPlace> (direct_hash, direct_equal);
				projections.insert (mapped.aggregate, projected);
			}
			projected.insert (mapped.field, mapped);
		}
		target.field_places.remove_range (0, target.field_places.length);
		foreach (var local in target.locals) {
			if (local.semantic_type is StructType) {
				declare_projections (local);
			}
		}
		fill_block (source.body);
	}

	private SemanticType type(SemanticType original) throws CoreError {
		return pass.concrete_type (original, substitution, target.generic_instance == null ? (Object) target : target.generic_instance);
	}
	private CoreCleanupContract? contract(CoreCleanupContract? original) throws CoreError {
		return pass.concrete_contract (original, substitution);
	}
	private HashTable<CoreOwnedLocal, GenericResultOrigins>? local_origins;
	private CoreCleanupContract? owner_contract(CoreOwnedLocal owner) throws CoreError {
		var incoming = owner.place.incoming_parameter;
		if (incoming != null) {
			var parameter = parameters.lookup (incoming);
			if (parameter == null) {
				throw new CoreError.INVALID_IR ("owned local lost its exact incoming parameter during specialization");
			}
			return pass.concrete_contract (owner.cleanup, substitution, parameter.heap_object);
		}
		var instance = target.generic_instance;
		if (owner.cleanup.type_parameter != null && instance != null && type (owner.place.semantic_type) is ClassType) {
			if (local_origins == null) {
				local_origins = pass.local_origins ((CoreGenericFunction) source, instance.type_arguments, substitution);
			}
			var equation = local_origins.lookup (owner);
			var heaps = new bool[target.parameters.length];
			foreach (var parameter in target.parameters) {
				heaps[parameter.ordinal] = parameter.heap_object;
			}
			uint domains = equation == null ? GenericResultOrigins.UNKNOWN : equation.evaluate (heaps);
			if ((domains & GenericResultOrigins.UNKNOWN) != 0 || domains == (GenericResultOrigins.CALLER | GenericResultOrigins.HEAP)) {
				throw new CoreError.INVALID_IR ("generic local Class owner requires one independently derived storage origin");
			}
			return pass.concrete_contract (owner.cleanup, substitution, domains == GenericResultOrigins.HEAP);
		}
		return contract (owner.cleanup);
	}

	private DataPointerProvenance provenance(DataPointerProvenance original) throws CoreError {
		if (in_place || original.origin != DataPointerOrigin.LOCAL) {
			return original;
		}
		if (original.origin_ordinal < 0 || original.origin_ordinal >= source.locals.length) {
			throw new CoreError.INVALID_IR ("local provenance requires its exact source local before specialization");
		}
		var local = places.lookup (source.locals[original.origin_ordinal]) as CoreLocalPlace;
		if (local == null) {
			throw new CoreError.INVALID_IR ("specialization lost local provenance identity");
		}
		return new DataPointerProvenance (original.origin, local.ordinal, original.region_ordinal, original.deep_text);
	}

	private CoreFieldPlace project_field(CorePlace aggregate, CoreStructField field, SourceSpan span) {
		var projected = projections.lookup (aggregate);
		if (projected == null) {
			projected = new HashTable<CoreStructField, CoreFieldPlace> (direct_hash, direct_equal);
			projections.insert (aggregate, projected);
		}
		var result = projected.lookup (field);
		if (result == null) {
			result = new CoreFieldPlace (span, aggregate, field);
			projected.insert (field, result);
		}
		return result;
	}

	private void declare_projections(CorePlace aggregate) throws CoreError {
		foreach (var field in pass.concrete_struct (aggregate.semantic_type).fields) {
			var place = project_field (aggregate, field, aggregate.span);
			target.field_places.add (place);
			if (field.semantic_type is StructType) {
				declare_projections (place);
			}
		}
	}

	private void prepare_blocks(CoreBlock block, CoreBlock? existing = null) {
		blocks.insert (block, in_place ? block : existing ?? new CoreBlock (block.span, new GenericArray<CoreStatement> ()));
		blocks.lookup (block).text_extent = block.text_extent;
		foreach (var statement in block.statements) {
			if (statement is CoreTry) {
				prepare_blocks (((CoreTry) statement).body);
				foreach (var caught in ((CoreTry) statement).catches) {
					prepare_blocks (caught.body);
				}
			}
			if (statement is CoreEnumMatch) {
				foreach (var arm in ((CoreEnumMatch) statement).arms) {
					prepare_blocks (arm.body);
				}
			}
			if (statement is CoreScope) {
				prepare_blocks (((CoreScope) statement).body);
			}
			if (statement is CoreIf) {
				var branch = (CoreIf) statement;
				prepare_blocks (branch.then_block);
				if (branch.else_block != null) {
					prepare_blocks (branch.else_block);
				}
			}
			if (statement is CoreWhile) {
				var loop = (CoreWhile) statement;
				loops.insert (loop.target, in_place ? loop.target : new CoreLoopTarget (loop.target.span, loop.target.ordinal));
				prepare_blocks (loop.body);
				if (loop.step != null) {
					prepare_blocks (loop.step);
				}
			}
		}
	}

	private CoreBlock fill_block(CoreBlock source_block) throws CoreError {
		var result = blocks.lookup (source_block);
		var statements = new GenericArray<CoreStatement> ();
		foreach (var statement in source_block.statements) {
			statements.add (clone_statement (statement));
		}
		if (source_block == source.body) {
			int rank = 0;
			foreach (var parameter in target.parameters) {
				if (parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER) {
					rank++;
				}
			}
			foreach (var parameter in source.parameters) {
				var concrete = parameters.lookup (parameter);
				if (concrete.struct_value_contract == null && !(concrete.semantic_type is EnumType)) {
					continue;
				}
				var storage = parameter_storage.lookup (parameter);
				if (storage != null) {
					statements.insert (rank, (concrete.semantic_type is EnumType) ? (CoreStatement) new CoreAcquireEnumParameter (parameter.span, storage, concrete) : new CoreAcquireStructParameter (parameter.span, storage, concrete));
				}
				rank++;
			}
		}
		result.statements.remove_range (0, result.statements.length);
		foreach (var statement in statements) {
			result.statements.add (statement);
		}
		return result;
	}

	private CorePlace place(CorePlace original) throws CoreError {
		var mapped = places.lookup (original);
		if (mapped != null) {
			return mapped;
		}
		if (original is CoreGenericStructFieldPlace) {
			var p = (CoreGenericStructFieldPlace) original;
			var aggregate = place (p.aggregate);
			var instance = pass.concrete_struct (aggregate.semantic_type).generic_instance;
			var field = instance == null ? null : instance.field_for (p.field);
			var arguments = new GenericArray<SemanticType> ();
			foreach (var argument in p.application.type_arguments) {
				arguments.add (type (argument));
			}
			if (field == null || !instance.matches (p.application.origin, arguments)) {
				throw new CoreError.INVALID_IR ("generic projection requires exact origin-to-concrete-field mapping");
			}
			mapped = project_field (aggregate, field, p.span);
		} else if (original is CoreFieldPlace) {
			var p = (CoreFieldPlace) original;
			mapped = project_field (place (p.aggregate), p.field, p.span);
		} else if (original is CoreIndirectFieldPlace) {
			var p = (CoreIndirectFieldPlace) original;
			var field = p.field;
			if (field.containing_type.semantic_type.is_parameterized ()) {
				var instance = type (field.containing_type.semantic_type);
				CoreNativeInstance? owner = null;
				foreach (var candidate in pass.native_instances ()) {
					if (candidate.semantic_type == instance) {
						owner = candidate;
					}
				}
				if (owner == null || field.ordinal < 0 || field.ordinal >= owner.fields.length || owner.fields[field.ordinal].name != field.name) {
					throw new CoreError.INVALID_IR ("Class field specialization lost its exact declaration");
				}
				field = owner.fields[field.ordinal];
			}
			mapped = new CoreIndirectFieldPlace (p.span, value (p.pointer), field);
		} else if (original is CoreDereferencePlace) {
			var p = (CoreDereferencePlace) original;
			mapped = new CoreDereferencePlace (p.span, value (p.pointer), type (p.semantic_type), provenance (p.provenance));
		} else if (original is CoreArrayElementPlace) {
			var p = (CoreArrayElementPlace) original;
			mapped = new CoreArrayElementPlace (p.span, (CoreLocalPlace) place (p.storage), (ArrayType) type (p.array_type), value (p.index), provenance (p.provenance));
		} else if (original is CoreSliceElementPlace) {
			var p = (CoreSliceElementPlace) original;
			mapped = new CoreSliceElementPlace (p.span, value (p.slice), (SliceType) type (p.slice_type), value (p.index), provenance (p.provenance));
		} else {
			throw new CoreError.INVALID_IR ("unmapped instance-local Core Place");
		}
		places.insert (original, mapped);
		return mapped;
	}

	private CoreFunction call_target(CoreFunction original, GenericArray<SemanticType>? arguments, GenericArray<CoreValue>? actuals = null) throws CoreError {
		var receiver = original.implicit_receiver;
		var method_application = original as CoreMethod;
		bool open_method = method_application != null && method_application.generic_method_instance != null && !method_application.generic_method_instance.arguments.closed ();
		if (receiver != null && (receiver.contract.instance_type.is_parameterized () || open_method)) {
			var owner_type = type (receiver.contract.instance_type);
			foreach (var owner in pass.native_instances ()) {
				if (owner.semantic_type != owner_type) {
					continue;
				}
				if (original is CoreMethod) {
					var method = (CoreMethod) original;
					var binding = method.generic_method_instance;
					TypeArgumentVector? method_arguments = null;
					if (binding != null) {
						var values = new GenericArray<SemanticType> ();
						foreach (var argument in binding.arguments.copy_values ()) {
							values.add (type (argument));
						}
						method_arguments = new TypeArgumentVector (values);
					}
					foreach (var candidate in owner.methods) {
						if (binding != null) {
							var key = candidate.generic_method_instance;
							if (key != null && key.member == binding.member && key.arguments.matches_identities (method_arguments)) {
								return candidate;
							}
						} else if (candidate.member_ordinal == method.member_ordinal && candidate.name == method.name) {
							return candidate;
						}
					}
				} else if (original is CorePropertyAccessor) {
					var property = ((CorePropertyAccessor) original).property_member;
					foreach (var candidate in owner.properties) {
						if (candidate.ordinal == property.ordinal && candidate.name == property.name) {
							return (original is CorePropertyGetter) ? (CoreFunction) candidate.getter : candidate.setter;
						}
					}
				} else if (owner is CoreClass) {
					var object_class = (CoreClass) owner;
					if (original is CoreConstructor && object_class.constructor != null) {
						return object_class.constructor;
					}
					if (original is CoreDestructor && object_class.destructor != null) {
						return object_class.destructor;
					}
				}
			}
			throw new CoreError.INVALID_IR ("symbolic Class member has no exact closed declaration");
		}
		if (arguments == null) {
			if (original is CoreGenericFunction) {
				throw new CoreError.INVALID_IR ("generic call missing exact arguments");
			}
			return original;
		}
		var concrete = new GenericArray<SemanticType> (arguments.length);
		foreach (var argument in arguments) {
			concrete.add (type (argument));
		}
		var heaps = new bool[original.parameters.length];
		if (actuals != null) {
			for (int i = 0; i < actuals.length; i++) {
				var owned = actuals[i] as CoreOwnedArgumentValue;
				if (owned == null || !(original.parameters[i].semantic_type is TypeParameterType || original.parameters[i].semantic_type is ClassType) || owned.source == null) {
					continue;
				}
				var owner = owners.lookup (owned.source);
				if (owner == null) {
					throw new CoreError.INVALID_IR ("generic argument lost its exact caller owner during specialization");
				}
				heaps[i] = owner.cleanup.is_heap_object;
			}
		}
		return pass.request ((CoreGenericFunction) original, concrete, target, -1, new GenericStorageVector (heaps));
	}

	private GenericArray<CoreValue> values(GenericArray<CoreValue> originals, GenericArray<CoreParameter>? boundaries = null) throws CoreError {
		var result = new GenericArray<CoreValue> ();
		for (int i = 0; i < originals.length; i++) {
			result.add (value (originals[i], boundaries == null ? null : boundaries[i]));
		}
		return result;
	}

	private CoreStatement clone_statement(CoreStatement original) throws CoreError {
		var span = original.span;
		if (original is CoreForeignSignalReturn) {
			return new CoreForeignSignalReturn (span, ((CoreForeignSignalReturn) original).binding);
		}
		if (original is CoreForeignReturn) {
			var imported = (CoreForeignReturn) original;
			var consumed = new GenericArray<CoreOwnedLocal> ();
			foreach (var owner in imported.consumed) {
				consumed.add (owners.lookup (owner));
			}
			return new CoreForeignReturn (span, imported.binding, imported.factory, consumed);
		}
		if (original is CoreAsyncDelay) {
			var delay = (CoreAsyncDelay) original;
			return new CoreAsyncDelay (span, delay.body, value (delay.ticks), delay.payload);
		}
		if (original is CoreTaskAwaitStatement) {
			return new CoreTaskAwaitStatement (span, (CoreTaskAwait) value (((CoreTaskAwaitStatement) original).operation));
		}
		if (original is CoreValueStatement) {
			return new CoreValueStatement (span, value (((CoreValueStatement) original).value));
		}
		if (original is CoreAsyncOperationStatement) {
			return new CoreAsyncOperationStatement (span, (CoreAsyncOperation) value (((CoreAsyncOperationStatement) original).operation));
		}
		if (original is CoreTry) {
			var guarded = (CoreTry) original;
			var body = fill_block (guarded.body);
			var catches = new GenericArray<CoreCatch> ();
			foreach (var caught in guarded.catches) {
				catches.add (new CoreCatch ((CoreLocalPlace) place (caught.binding), fill_block (caught.body)));
			}
			return new CoreTry (span, body, catches, guarded.cleanup);
		}
		if (original is CoreVectorMemoryStatement) {
			return new CoreVectorMemoryStatement (original.span, (CoreVectorMemoryValue) value (((CoreVectorMemoryStatement) original).operation));
		}
		if (original is CoreThrow) {
			var thrown = (CoreThrow) original;
			return new CoreThrow (span, (CoreLocalPlace) place (thrown.source), thrown.owner == null ? null : owners.lookup (thrown.owner), thrown.cleanup);
		}
		if (original is CoreBaseLifecycleCall) {
			var call = (CoreBaseLifecycleCall) original;
			return new CoreBaseLifecycleCall (span, (CoreLifecycle) call.target, values (call.arguments, call.target.parameters), value (call.receiver));
		}
		if (original is CoreAcquireEnumParameter) {
			var s = (CoreAcquireEnumParameter) original;
			return new CoreAcquireEnumParameter (span, (CoreLocalPlace) place (s.destination), parameters.lookup (s.parameter));
		}
		if (original is CoreEnumStore) {
			var s = (CoreEnumStore) original;
			return new CoreEnumStore (span, (CoreLocalPlace) place (s.destination), enum_producer (s.producer), s.initializes_destination);
		}
		if (original is CoreEnumReturn) {
			return new CoreEnumReturn (span, enum_producer (((CoreEnumReturn) original).producer));
		}
		if (original is CoreEnumMatch) {
			var s = (CoreEnumMatch) original;
			var producer = enum_producer (s.scrutinee);
			var arms = new GenericArray<CoreEnumArm> ();
			foreach (var arm in s.arms) {
				var variant = arm.variant == null ? null : producer.definition.variant (arm.variant.identity.ordinal);
				var bindings = new GenericArray<CoreEnumBinding> ();
				foreach (var binding in arm.bindings) {
					bindings.add (new CoreEnumBinding (binding.span, variant.field (binding.field.identity.ordinal), (CoreLocalPlace) place (binding.destination), new EnumBindingIdentity (variant.field (binding.field.identity.ordinal).identity, ((CoreLocalPlace) place (binding.destination)).ordinal, producer.instance), binding.acquisition == null ? null : owners.lookup (binding.acquisition)));
				}
				arms.add (new CoreEnumArm (arm.span, variant, bindings, fill_block (arm.body)));
			}
			return new CoreEnumMatch (span, producer, arms);
		}
		if (original is CoreAcquireStructParameter) {
			var s = (CoreAcquireStructParameter) original;
			return new CoreAcquireStructParameter (span, (CoreLocalPlace) place (s.destination), parameters.lookup (s.parameter));
		}
		if (original is CoreStructReturn) {
			return new CoreStructReturn (span, struct_producer (((CoreStructReturn) original).producer));
		}
		if (original is CoreStructResultStore) {
			var s = (CoreStructResultStore) original;
			return new CoreStructResultStore (span, place (s.destination), struct_producer (s.producer), s.initializes_destination);
		}
		if (original is CoreWithScope) {
			var scoped = (CoreWithScope) original;
			var contract = with_contract (scoped.contract);
			return new CoreWithScope (span, contract, fill_block (scoped.body));
		}
		if (original is CoreScope) {
			return new CoreScope (span, fill_block (((CoreScope) original).body));
		}
		if (original is CoreIf) {
			var s = (CoreIf) original;
			var condition = value (s.condition);
			var then_block = fill_block (s.then_block);
			var else_block = s.else_block == null ? null : fill_block (s.else_block);
			return new CoreIf (span, condition, then_block, else_block);
		}
		if (original is CoreWhile) {
			var s = (CoreWhile) original;
			if (s.has_sequence != (s.sequence != null)) {
				throw new CoreError.INVALID_CHECKED_MODEL ("foreach lost sequence authority before specialization");
			}
			var condition = value (s.condition);
			CoreSequenceIteration? sequence = null;
			if (s.sequence != null) {
				if (s.sequence.is_iterator) {
					sequence = new CoreSequenceIteration.iterator (s.sequence.span, loops.lookup (s.target), value (s.sequence.source),
						(CoreLocalPlace) place (s.sequence.binding), s.sequence.advance, s.sequence.current);
				} else {
					sequence = new CoreSequenceIteration (s.sequence.span, loops.lookup (s.target), value (s.sequence.source),
						(CoreLocalPlace) place (s.sequence.index), (CoreLocalPlace) place (s.sequence.binding));
				}
			}
			return new CoreWhile (span, loops.lookup (s.target), condition, fill_block (s.body), s.step == null ? null : fill_block (s.step), iteration (s.iteration), sequence);
		}
		if (original is CoreBreak) {
			return new CoreBreak (span, loops.lookup (((CoreBreak) original).target));
		}
		if (original is CoreContinue) {
			return new CoreContinue (span, loops.lookup (((CoreContinue) original).target));
		}
		if (original is CoreReturn) {
			var s = (CoreReturn) original;
			if (s.value != null && type (s.value.semantic_type) is EnumType) {
				return new CoreEnumReturn (span, sum_source (s.value));
			}
			if (s.value != null && type (s.value.semantic_type) is StructType) {
				return new CoreStructReturn (span, copy_source (s.value));
			}
			return new CoreReturn (span, s.value == null ? null : value (s.value));
		}
		if (original is CoreDiscardOwnedSuccess) {
			var discarded = (CoreDiscardOwnedSuccess) original;
			return new CoreDiscardOwnedSuccess (span, discarded.target, values (discarded.arguments, discarded.target.parameters), discarded.receiver == null ? null : value (discarded.receiver), discarded.cleanup);
		}
		if (original is CoreCallStatement) {
			var s = (CoreCallStatement) original;
			var callee = call_target (s.target, (s is CoreGenericCallStatement) ? ((CoreGenericCallStatement) s).type_arguments : null, s.arguments);
			var receiver = s.receiver == null ? null : value (s.receiver);
			if (callee.struct_result_contract != null) {
				var result = new CoreLocalPlace (span, span, "$copy_result_%u".printf (target.locals.length), callee.return_type, target.locals.length);
				target.locals.add (result);
				declare_projections (result);
				return new CoreStructResultStore (span, result, new CoreStructCallResult (span, callee.return_type, callee, values (s.arguments, callee.parameters), receiver), true);
			}
			return new CoreCallStatement (span, callee, values (s.arguments, callee.parameters), receiver);
		}
		if (original is CoreCCallStatement) {
			var s = (CoreCCallStatement) original;
			return new CoreCCallStatement (span, s.target, values (s.arguments, s.target.parameters));
		}
		if (original is CoreAcquireParameter) {
			var s = (CoreAcquireParameter) original;
			return new CoreAcquireParameter (span, owners.lookup (s.acquisition), parameters.lookup (((CoreParameterValue) s.value).parameter));
		}
		if (original is CoreOwnedBufferExchange) {
			var s = (CoreOwnedBufferExchange) original;
			var left_owner = s.left.owner == null ? null : owners.lookup (s.left.owner);
			var right_owner = s.right.owner == null ? null : owners.lookup (s.right.owner);
			var left = new CoreBufferOwnerSlot (s.left.span, place (s.left.place), left_owner, left_owner == null ? contract (s.left.cleanup) : left_owner.cleanup);
			var right = new CoreBufferOwnerSlot (s.right.span, place (s.right.place), right_owner, right_owner == null ? contract (s.right.cleanup) : right_owner.cleanup);
			return new CoreOwnedBufferExchange (span, left, right);
		}
		if (original is CoreStructAcquire) {
			var s = (CoreStructAcquire) original;
			return new CoreStructAcquire (span, owners.lookup (s.owner), (CoreFieldPlace) place (s.field), s.source == null ? null : owners.lookup (s.source), s.producer == null ? null : value (s.producer));
		}
		if (original is CoreStructMove) {
			var s = (CoreStructMove) original;
			return new CoreStructMove (span, owners.lookup (s.source), owners.lookup (s.destination));
		}
		if (original is CoreRecordTake) {
			var s = (CoreRecordTake) original;
			return new CoreRecordTake (span, owners.lookup (s.source), (CoreFieldPlace) place (s.field), owners.lookup (s.destination));
		}
		if (original is CoreRecordReplace) {
			var s = (CoreRecordReplace) original;
			return new CoreRecordReplace (span, owners.lookup (s.owner), (CoreFieldPlace) place (s.field), s.source == null ? null : owners.lookup (s.source), s.producer == null ? null : value (s.producer));
		}
		if (original is CoreSlotsRecordTransfer) {
			var transfer = (CoreSlotsRecordTransfer) original;
			return new CoreSlotsRecordTransfer (span, (CoreIndirectFieldPlace) place (transfer.store), transfer.index == null ? null : value (transfer.index), struct_producer (transfer.value));
		}
		if (original is CoreSlotsInitialize) {
			return new CoreSlotsInitialize (span, (CoreIndirectFieldPlace) place (((CoreSlotsInitialize) original).store));
		}
		if (original is CoreSlotsAppend) {
			var s = (CoreSlotsAppend) original;
			return new CoreSlotsAppend (span, (CoreIndirectFieldPlace) place (s.store), owners.lookup (s.incoming));
		}
		if (original is CoreSlotsReplace) {
			var s = (CoreSlotsReplace) original;
			return new CoreSlotsReplace (span, (CoreIndirectFieldPlace) place (s.store), value (s.index), owners.lookup (s.incoming));
		}
		if (original is CoreOwnedFieldTransfer) {
			var s = (CoreOwnedFieldTransfer) original;
			return new CoreOwnedFieldTransfer (span, (CoreIndirectFieldPlace) place (s.destination), s.cleanup, s.source == null ? null : owners.lookup (s.source), s.producer == null ? null : value (s.producer), s.initializes);
		}
		if (original is CoreFieldInitialize) {
			var s = (CoreFieldInitialize) original;
			return new CoreFieldInitialize (span, (CoreIndirectFieldPlace) place (s.target), value (s.value));
		}
		if (original is CoreStructCopy) {
			var s = (CoreStructCopy) original;
			return new CoreStructCopy (span, place (s.destination), place (s.source), type (s.semantic_type), s.initializes_destination);
		}
		if (original is CoreStructInitialize) {
			var s = (CoreStructInitialize) original;
			if (s.producer != null) {
				return new CoreStructInitialize.from_producer (span, (CoreStorageFieldPlace) place (s.target), struct_producer (s.producer), s.record_owner == null ? null : owners.lookup (s.record_owner));
			}
			var children = new GenericArray<CoreStatement> ();
			foreach (var child in s.initializers) {
				children.add (clone_statement (child));
			}
			return new CoreStructInitialize (span, (CoreFieldPlace) place (s.target), children);
		}
		if (original is CoreInitialize) {
			var s = (CoreInitialize) original;
			var destination = place (s.target);
			if (destination.semantic_type is EnumType) {
				return new CoreEnumStore (span, (CoreLocalPlace) destination, sum_source (s.value), true);
			}
			if (destination.semantic_type is StructType) {
				return copy_store (span, destination, copy_source (s.value), true);
			}
			var producer = value (s.value);
			var acquisition = s.acquisition == null ? null : owners.lookup (s.acquisition);
			var call = producer as CoreCallValue;
			if (acquisition != null && acquisition.cleanup.is_object && !acquisition.cleanup.is_heap_object && call != null
			    && call.target.owned_cleanup != null && !call.target.heap_result && call.candidate_storage == null && call.result_storage == null) {
				var extent = acquisition.scope.text_extent;
				if (extent == null) {
					throw new CoreError.INVALID_IR ("caller-result local requires its exact lexical acquisition extent");
				}
				var storage = new CoreObjectStorage (span, acquisition.cleanup.object_class, target.object_storage.length, extent.ordinal, acquisition.scope);
				storage.result_candidate = true;
				target.object_storage.add (storage);
				call.candidate_storage = storage;
			}
			return new CoreInitialize (span, destination, producer, acquisition);
		}
		if (original is CoreStore) {
			var s = (CoreStore) original;
			var destination = place (s.target);
			if (destination.semantic_type is EnumType) {
				return new CoreEnumStore (span, (CoreLocalPlace) destination, sum_source (s.value), false);
			}
			if (destination.semantic_type is StructType) {
				return copy_store (span, destination, copy_source (s.value), false);
			}
			return new CoreStore (span, destination, value (s.value), s.volatile_access == null ? null : s.volatile_access.copy ());
		}
		if (original is CoreArrayInitialize) {
			var s = (CoreArrayInitialize) original;
			if (s.records.length == 0) {
				return new CoreArrayInitialize (span, (CoreLocalPlace) place (s.storage), values (s.elements));
			}
			var records = new GenericArray<CoreArrayRecordEntry> ();
			foreach (var entry in s.records) {
				var initializers = new GenericArray<CoreStatement> ();
				foreach (var initializer in entry.initializers) {
					initializers.add (clone_statement (initializer));
				}
				records.add (new CoreArrayRecordEntry (entry.span, (CoreArrayElementPlace) place (entry.target), initializers, entry.producer == null ? null : struct_producer (entry.producer)));
			}
			return new CoreArrayInitialize.record_entries (span, (CoreLocalPlace) place (s.storage), records);
		}
		if (original is CoreOwnershipTransfer) {
			var s = (CoreOwnershipTransfer) original;
			var owner = owners.lookup (s.source);
			return new CoreOwnershipTransfer (span, owner, owners.lookup (s.destination), pass.concrete_contract (s.cleanup, substitution, owner.cleanup.is_heap_object));
		}
		if (original is CoreOwnershipRelease) {
			var s = (CoreOwnershipRelease) original;
			var owner = owners.lookup (s.owner);
			return new CoreOwnershipRelease (span, owner, owner.cleanup);
		}
		if (original is CoreOwnershipRearm) {
			var s = (CoreOwnershipRearm) original;
			var owner = owners.lookup (s.owner);
			return s.source == null ? new CoreOwnershipRearm (span, owner, value (s.producer), owner.cleanup) : new CoreOwnershipRearm.from_owner (span, owner, owners.lookup (s.source), owner.cleanup);
		}
		if (original is CoreOwnershipReturn) {
			var s = (CoreOwnershipReturn) original;
			var concrete = type (s.semantic_type);
			var producer = s.producer == null ? null : value (s.producer);
			var provenance = s.provenance;
			CoreCleanupContract? cleanup;
			if ((s.cleanup.type_parameter != null || target.generic_instance != null) && concrete is ClassType) {
				cleanup = target.owned_cleanup;
			} else {
				cleanup = contract (s.cleanup);
			}
			if ((s.cleanup.type_parameter != null || target.generic_instance != null) && concrete is ClassType) {
				cleanup = target.owned_cleanup;
				if (s.source != null) {
					var equation = local_origins == null ? null : local_origins.lookup (s.source);
					provenance = owners.lookup (s.source).cleanup.is_heap_object ? ObjectResultProvenance.HEAP_OBJECT
					        : equation != null && equation.domains == 0 && equation.input_count == 0 ? ObjectResultProvenance.NULL
					        : ObjectResultProvenance.OWNED_PARAMETER_STORAGE;
				} else if (producer is CoreOwnedObjectResultConstruction) {
					provenance = ObjectResultProvenance.RESULT_STORAGE;
				} else if (producer == null || producer is CoreNullPointerValue) {
					provenance = ObjectResultProvenance.NULL;
				} else {
					provenance = ObjectResultProvenance.FORWARDED_OWNED_RESULT;
				}
				if (producer is CoreCallValue) {
					((CoreCallValue) producer).result_storage = target.result_storage;
				}
			}
			return new CoreOwnershipReturn (span, concrete, cleanup, s.source == null ? null : owners.lookup (s.source), producer, provenance);
		}
		if (original is CoreObjectConstruction) {
			var s = (CoreObjectConstruction) original;
			CoreObjectConstruction result;
			if (s is CoreConstructorObjectInitialization) {
				var c = (CoreConstructorObjectInitialization) s;
				var constructor = (CoreConstructor) call_target (c.constructor, null, c.arguments);
				result = new CoreConstructorObjectInitialization (span, storages.lookup (s.storage), (CoreLocalPlace) place (s.target), constructor, values (c.arguments, constructor.parameters), c.allocation_context == null ? null : value (c.allocation_context));
			} else {
				var initializers = new GenericArray<CoreObjectFieldInitializer> ();
				foreach (var field in s.initializers) {
					initializers.add (new CoreObjectFieldInitializer (field.span, field.field, value (field.value)));
				}
				result = new CoreObjectConstruction (span, storages.lookup (s.storage), (CoreLocalPlace) place (s.target), initializers);
			}
			result.acquisition = s.acquisition == null ? null : owners.lookup (s.acquisition);
			return result;
		}
		throw new CoreError.INVALID_IR ("unsupported statement in Core monomorphization");
	}

	private CoreEnumProducer enum_producer(CoreEnumProducer original) throws CoreError {
		if (original is CoreEnumAwait) {
			return new CoreEnumAwait (pass.enum_definition (original.definition), (CoreTaskAwait) value (((CoreEnumAwait) original).operation), original.instance);
		}
		var definition = pass.enum_definition (original.definition, substitution);
		if (original is CoreAsyncRun) {
			return new CoreAsyncRun (original.span, definition, (CoreAsyncOperation) value (((CoreAsyncRun) original).operation), original.instance);
		}
		if (original is CoreEnumSnapshot) {
			return new CoreEnumSnapshot (original.span, definition, (CoreLocalPlace) place (((CoreEnumSnapshot) original).source), original.instance, ((CoreEnumSnapshot) original).mode);
		}
		if (original is CoreEnumConstruct) {
			var s = (CoreEnumConstruct) original;
			var variant = definition.variant (s.variant.identity.ordinal);
			var fields = new GenericArray<CoreEnumFieldValue> ();
			for (uint f = 0; f < variant.field_count; f++) {
				var input = s.fields[f];
				var field = variant.field (f);
				var sum = input.sum == null ? null : enum_producer (input.sum);
				var record = input.record == null ? null : struct_producer (input.record);
				CoreValue? scalar = null;
				if (input.scalar != null) {
					if (field.semantic_type is EnumType) {
						sum = sum_source (input.scalar);
					} else if (field.semantic_type is StructType) {
						record = copy_source (input.scalar);
					} else {
						scalar = value (input.scalar);
					}
				}
				fields.add (new CoreEnumFieldValue (input.span, field, scalar, record, sum));
			}
			return new CoreEnumConstruct (original.span, definition, variant, fields, original.instance);
		}
		var call = (CoreEnumCallResult) original;
		var callee = call_target (call.target, call.type_arguments);
		return new CoreEnumCallResult (original.span, definition, callee, values (call.arguments, callee.parameters), call.receiver == null ? null : value (call.receiver), original.instance);
	}

	private StructLeafPath projection_path(StructLeafPath path) throws CoreError {
		int[] ordinals = new int[path.depth];
		for (int i = 0; i < path.depth; i++) {
			ordinals[i] = path.field_ordinal (i);
		}
		return new StructLeafPath (ordinals, type (path.semantic_type));
	}

	private CoreStructProducer struct_producer(CoreStructProducer original) throws CoreError {
		if (original is CoreStructInvocationResult) {
			return new CoreStructInvocationResult (value (((CoreStructInvocationResult) original).invocation), original.contract.mode);
		}
		if (original is CoreStructProjectionProducer) {
			var projection = (CoreStructProjectionProducer) original;
			return new CoreStructProjectionProducer (original.span, struct_producer (projection.source), projection_path (projection.path));
		}
		if (original is CoreSlotsRecordRead) {
			var read = (CoreSlotsRecordRead) original;
			return new CoreSlotsRecordRead (original.span, (CoreIndirectFieldPlace) place (read.store), value (read.index), read.remove, read.contract.mode);
		}

		if (original is CoreStructMoveProducer) {
			return new CoreStructMoveProducer (original.span, owners.lookup (((CoreStructMoveProducer) original).source));
		}
		if (original is CoreStructAwait) {
			return new CoreStructAwait ((CoreTaskAwait) value (((CoreStructAwait) original).operation), original.contract.mode);
		}
		if (original is CoreStructBorrowSnapshot) {
			return new CoreStructBorrowSnapshot (original.span, place (((CoreStructBorrowSnapshot) original).source));
		}
		if (original is CoreStructSnapshot) {
			return new CoreStructSnapshot (original.span, place (((CoreStructSnapshot) original).source));
		}
		if (original is CoreCStructCallResult) {
			var foreign_call = (CoreCStructCallResult) original;
			return new CoreCStructCallResult (original.span, foreign_call.target, values (foreign_call.arguments, foreign_call.target.parameters));
		}
		var call = (CoreStructCallResult) original;
		var callee = call_target (call.target, call.type_arguments);
		return new CoreStructCallResult (original.span, type (original.semantic_type), callee, values (call.arguments, callee.parameters), call.receiver == null ? null : value (call.receiver));
	}

	// These are the only symbolic plain-copy computations. Consumers select a
	// concrete representation; no aggregate CoreValue is ever constructed.
	private CoreEnumProducer sum_source(CoreValue source) throws CoreError {
		var definition = pass.enum_definition_for_type ((EnumType) type (source.semantic_type));
		if (source is CoreLoadValue) {
			return new CoreEnumSnapshot (source.span, definition, (CoreLocalPlace) place (((CoreLoadValue) source).source));
		}
		if (source is CoreParameterValue) {
			var storage = parameter_storage.lookup (((CoreParameterValue) source).parameter);
			if (storage == null) {
				throw new CoreError.INVALID_IR ("plain-copy enum parameter lost its independent storage");
			}
			return new CoreEnumSnapshot (source.span, definition, storage);
		}
		if (source is CoreGenericCall) {
			var call = (CoreGenericCall) source;
			var callee = call_target (call.target, call.type_arguments);
			return new CoreEnumCallResult (source.span, definition, callee, values (call.arguments, callee.parameters), null);
		}
		throw new CoreError.INVALID_IR ("enum specialization requires a bounded plain-copy source");
	}

	private CoreStructProducer copy_source(CoreValue source) throws CoreError {
		if (source is CoreFunctionValueCall) {
			return new CoreStructInvocationResult (value (source), StructValueMode.COPY_VALUE);
		}
		if (source is CoreStructProjectionValue) {
			var projection = (CoreStructProjectionValue) source;
			return new CoreStructProjectionProducer (source.span, struct_producer (projection.source), projection_path (projection.path));
		}
		if (source is CoreLoadValue) {
			return new CoreStructSnapshot (source.span, place (((CoreLoadValue) source).source));
		}
		if (source is CoreParameterValue) {
			var storage = parameter_storage.lookup (((CoreParameterValue) source).parameter);
			if (storage == null) {
				throw new CoreError.INVALID_IR ("plain-copy parameter lost its independent record storage");
			}
			return new CoreStructSnapshot (source.span, storage);
		}
		if (source is CoreCallValue) {
			var call = (CoreCallValue) source;
			var callee = call_target (call.target, (call is CoreGenericCall) ? ((CoreGenericCall) call).type_arguments : null, call.arguments);
			return new CoreStructCallResult (source.span, type (source.semantic_type), callee, values (call.arguments, callee.parameters), call.receiver == null ? null : value (call.receiver));
		}
		throw new CoreError.INVALID_IR ("record specialization requires a checked bounded plain-copy source");
	}

	private CoreStatement copy_store(SourceSpan span, CorePlace destination, CoreStructProducer producer, bool initializes) throws CoreError {
		if (destination.semantic_type != producer.semantic_type) {
			throw new CoreError.INVALID_IR ("plain-copy specialization lost exact source/destination identity");
		}
		if (initializes && destination is CoreStorageFieldPlace) {
			return new CoreStructInitialize.from_producer (span, (CoreStorageFieldPlace) destination, producer);
		}
		if (producer is CoreStructSnapshot) {
			return new CoreStructCopy (span, destination, ((CoreStructSnapshot) producer).source, producer.semantic_type, initializes);
		}
		return new CoreStructResultStore (span, destination, producer, initializes);
	}

	private GenericArray<CoreValue> callable_arguments(GenericArray<CoreValue> originals, CallableSignature signature, GenericArray<CoreParameter> channels) throws CoreError {
		var result = new GenericArray<CoreValue> ();
		for (int p = 0; p < originals.length; p++) {
			if (signature.parameter_types[p].is_struct_storage () && !(originals[p] is CoreStructArgument)) {
				result.add (new CoreStructArgument (originals[p].span, null, copy_source (originals[p])));
			} else {
				result.add (value (originals[p], channels.length == 0 ? null : channels[p]));
			}
		}
		return result;
	}

	private CoreValue value(CoreValue original, CoreParameter? boundary = null) throws CoreError {
		if (original is CoreScopedAllocator) {
			var scoped = (CoreScopedAllocator) original;
			return new CoreScopedAllocator (original.span, (HandleType) type (original.semantic_type), scoped.loan, (CoreLocalPlace) place (scoped.backing), value (scoped.kind), value (scoped.slots), pass.concrete_contract (scoped.cleanup, substitution));
		}
		if (original is CoreRetainedOperation) {
			var operation = (CoreRetainedOperation) original;
			var arguments = new GenericArray<CoreValue> ();
			foreach (var argument in operation.arguments) {
				arguments.add (value (argument));
			}
			return new CoreRetainedOperation (original.span, operation.action, value (operation.callee), arguments, original.semantic_type);
		}
		if (original is CoreClosureBind) {
			var closure = (CoreClosureBind) original;
			return new CoreClosureBind (original.span, (ClosureHandleType) type (original.semantic_type),
				owners.lookup (closure.source), closure.target, pass.concrete_contract (closure.cleanup, substitution), closure.actor_binding);
		}
		if (original is CoreClosureCall) {
			var call = (CoreClosureCall) original;
			var channels = new GenericArray<CoreParameter> ();
			foreach (var channel in call.channel_parameters) {
				var mapped = new CoreParameter (channel.span, channel.name_span, channel.name, type (channel.semantic_type), channel.ordinal, channel.pointer_contract);
				mapped.heap_object = channel.heap_object;
				if (channel.struct_value_contract != null) {
					mapped.struct_value_contract = new StructValueContract (mapped.semantic_type, channel.struct_value_contract.mode);
				}
				parameters.insert (channel, mapped);
				channels.add (mapped);
			}
			var signature = (ClosureHandleType) type (call.callee.semantic_type);
			var cleanup = pass.concrete_contract (call.owned_cleanup, substitution, signature.result_type is ClassType);
			var invocation = new CoreClosureCall (original.span, signature, value (call.callee), values (call.arguments, channels.length == 0 ? null : channels), cleanup);
			foreach (var channel in channels) {
				invocation.channel_parameters.add (channel);
			}
			return invocation;
		}
		if (original is CoreSharedOperation) {
			var operation = (CoreSharedOperation) original;
			return new CoreSharedOperation (original.span, original.semantic_type, operation.action, value (operation.operand), operation.source == null ? null : owners.lookup (operation.source), operation.cleanup, operation.borrower);
		}
		var result = value_without_text_intent (original, boundary);
		if (original.text_loan_intent != null) {
			var mapped = new GenericArray<Object> ();
			for (uint i = 0; i < original.text_loan_intent.count; i++) {
				var owner = original.text_loan_intent.owner (i);
				mapped.add ((owner is CoreLocalPlace) ? (Object) place ((CoreLocalPlace) owner) : (owner is CoreParameter) ? (Object) parameters.lookup ((CoreParameter) owner) : owner);
			}
			result.text_loan_intent = new Astra.Text.TextLoanIntent (mapped);
		}
		return result;
	}
	private CoreValue value_without_text_intent(CoreValue original, CoreParameter? boundary = null) throws CoreError {
		if (original is CoreTaskCreate) {
			var creation = (CoreTaskCreate) original;
			var arguments = values (creation.arguments, creation.target.parameters);
			var result = new CoreTaskCreate (original.span, (TaskType) original.semantic_type, creation.target, arguments, creation.allocation_context == null ? null : value (creation.allocation_context), creation.checked_admission);
			foreach (var loan in creation.loans) {
				var view = (CoreSliceFromArrayValue) arguments[loan.parameter_ordinal];
				result.loans.add (new CoreSuspensionLoan (loan.identity, loan.parameter_ordinal, (CoreLocalPlace) place (loan.storage), view));
			}
			return result;
		}
		if (original is CoreTaskMove) {
			return new CoreTaskMove (original.span, (CoreLocalPlace) place (((CoreTaskMove) original).source));
		}
		if (original is CoreTaskBorrow) {
			return new CoreTaskBorrow (original.span, (CoreLocalPlace) place (((CoreTaskBorrow) original).source));
		}
		if (original is CoreExecutorBorrow) {
			return new CoreExecutorBorrow (original.span, (CoreLocalPlace) place (((CoreExecutorBorrow) original).source));
		}
		if (original is CoreTaskAwait) {
			var wait = (CoreTaskAwait) original;
			return new CoreTaskAwait (original.span, type (original.semantic_type), wait.body, value (wait.child), wait.discard, contract (wait.buffer_cleanup), wait.bridge_executor == null ? null : value (wait.bridge_executor));
		}
		if (original is CoreAsyncOperation) {
			var operation = (CoreAsyncOperation) original;
			return new CoreAsyncOperation (original.span, operation.contract, operation.executor == null ? null : value (operation.executor), operation.task == null ? null : value (operation.task), operation.argument == null ? null : value (operation.argument));
		}
		if (original is CoreEnumBufferValue) {
			var buffer = (CoreEnumBufferValue) original;
			return new CoreEnumBufferValue (original.span, contract (buffer.cleanup), buffer.source == null ? null : owners.lookup (buffer.source), buffer.producer == null ? null : value (buffer.producer));
		}
		if (original is CoreEnumScalarValue) {
			return new CoreEnumScalarValue (original.span, owners.lookup (((CoreEnumScalarValue) original).source));
		}
		if (original is CoreEnumArgument) {
			var argument = (CoreEnumArgument) original;
			return new CoreEnumArgument (original.span, boundary ?? parameters.lookup (argument.parameter), enum_producer (argument.producer));
		}
		if (original is CoreEnumEquality) {
			var equality = (CoreEnumEquality) original;
			return new CoreEnumEquality (original.span, original.semantic_type, enum_producer (equality.left), enum_producer (equality.right), equality.unequal);
		}
		if (original is CoreStructArgument) {
			var argument = (CoreStructArgument) original;
			// Indirect copied-record groups deliberately have no callee parameter.
			// A neighboring borrowed channel must not manufacture one on cloning.
			var parameter = argument.parameter == null ? null : boundary ?? parameters.lookup (argument.parameter) ?? argument.parameter;
			return new CoreStructArgument (original.span, parameter, struct_producer (argument.producer));
		}
		if (boundary != null && boundary.semantic_type is EnumType) {
			return new CoreEnumArgument (original.span, boundary, sum_source (original));
		}
		if (boundary != null && boundary.struct_value_contract != null) {
			return new CoreStructArgument (original.span, boundary, copy_source (original));
		}
		if (original is CoreStructProjectionValue) {
			var projection = (CoreStructProjectionValue) original;
			return new CoreStructProjectionValue (original.span, struct_producer (projection.source), projection_path (projection.path));
		}
		var span = original.span;
		var concrete = type (original.semantic_type);
		if (original is CoreCallbackParameterView) {
			var view = (CoreCallbackParameterView) original;
			return new CoreCallbackParameterView (span, (CallbackType) concrete, parameters.lookup (view.source), boundary ?? view.parameter);
		}
		if (original is CoreFunctionAddress) {
			var address = (CoreFunctionAddress) original;
			return new CoreFunctionAddress (span, (FunctionValueType) concrete, call_target (address.target, null));
		}
		if (original is CoreFunctionValueCall) {
			var call = (CoreFunctionValueCall) original;
			var signature = (FunctionValueType) type (call.callee.semantic_type);
			var channels = new GenericArray<CoreParameter> ();
			foreach (var channel in call.channel_parameters) {
				var mapped = new CoreParameter (channel.span, channel.name_span, channel.name, type (channel.semantic_type), channel.ordinal, channel.pointer_contract);
				mapped.heap_object = CallableRecordGroups.heap_parameter (signature, channel.ordinal);
				if (channel.struct_value_contract != null) {
					mapped.struct_value_contract = new StructValueContract (mapped.semantic_type, channel.struct_value_contract.mode);
				}
				parameters.insert (channel, mapped);
				channels.add (mapped);
			}
			var cleanup = pass.concrete_contract (call.owned_cleanup, substitution, signature.result_type is ClassType);
			var invocation = new CoreFunctionValueCall (span, signature, value (call.callee), callable_arguments (call.arguments, signature, channels), cleanup);
			foreach (var channel in channels) {
				invocation.channel_parameters.add (channel);
			}
			return invocation;
		}
		if (concrete is StructType) {
			throw new CoreError.INVALID_IR ("record transport escaped its bounded consumer during specialization");
		}
		if (original is CoreGenericCapabilityOperation) {
			var operation = (CoreGenericCapabilityOperation) original;
			var left = value (operation.left);
			return CoreGenericOperationResolver.concretize (operation, type (operation.type_parameter.semantic_type), concrete, left, operation.right == null ? null : value (operation.right));
		}
		if (original is CoreCallValue) {
			var v = (CoreCallValue) original;
			var callee = call_target (v.target, (v is CoreGenericCall) ? ((CoreGenericCall) v).type_arguments : null, v.arguments);
			var receiver = v.receiver == null ? null : value (v.receiver);
			var result = new CoreCallValue (span, concrete, callee, values (v.arguments, callee.parameters), receiver);
			result.candidate_storage = v.candidate_storage == null ? null : storages.lookup (v.candidate_storage);
			result.result_storage = v.result_storage == null ? null : target.result_storage;
			return result;
		}
		if (original is CoreCCallValue) {
			var v = (CoreCCallValue) original;
			return new CoreCCallValue (span, concrete, v.target, values (v.arguments, v.target.parameters));
		}
		if (original is CoreParameterValue) {
			var v = (CoreParameterValue) original;
			return new CoreParameterValue (span, parameters.lookup (v.parameter));
		}
		if (original is CoreLoadValue) {
			var load = (CoreLoadValue) original;
			return new CoreLoadValue (span, place (load.source), load.volatile_access == null ? null : load.volatile_access.copy ());
		}
		if (original is CoreOwnedArgumentValue) {
			var argument = (CoreOwnedArgumentValue) original;
			var parameter = boundary ?? argument.parameter;
			var owner = argument.source == null ? null : owners.lookup (argument.source);
			bool heap = owner == null ? parameter.heap_object : owner.cleanup.is_heap_object;
			var cleanup = pass.concrete_contract (argument.cleanup, substitution, heap);
			return new CoreOwnedArgumentValue (span, parameter, cleanup, owner, concrete, argument.producer == null ? null : value (argument.producer));
		}
		if (original is CoreOwnedBufferAllocate) {
			var allocation = (CoreOwnedBufferAllocate) original;
			return new CoreOwnedBufferAllocate (original.span, (SliceType) concrete, value (allocation.count), contract (allocation.cleanup), allocation.failure_call == null ? null : clone_statement (allocation.failure_call), allocation.allocation_context == null ? null : value (allocation.allocation_context));
		}
		if (original is CoreOwnedBufferBorrow) {
			var borrow = (CoreOwnedBufferBorrow) original;
			return new CoreOwnedBufferBorrow (original.span, owners.lookup (borrow.source), borrow.parameter == null ? null : (boundary ?? borrow.parameter));
		}
		if (original is CoreWithReference) {
			return new CoreWithReference (span, with_contract (((CoreWithReference) original).contract));
		}
		if (original is CoreSlotsTake) {
			var v = (CoreSlotsTake) original;
			return new CoreSlotsTake (span, (CoreIndirectFieldPlace) place (v.store), value (v.index));
		}
		if (original is CoreSlotsValue) {
			var v = (CoreSlotsValue) original;
			return new CoreSlotsValue (span, concrete, (CoreIndirectFieldPlace) place (v.store), v.action, v.operand == null ? null : value (v.operand), v.borrower == null ? null : (boundary ?? v.borrower), iteration (v.iteration));
		}
		if (original is CoreLazyObserve) {
			return new CoreLazyObserve (span, ((CoreLazyObserve) original).property_member);
		}
		if (original is CoreOwnedFieldBorrow) {
			var v = (CoreOwnedFieldBorrow) original;
			return new CoreOwnedFieldBorrow (span, (CoreIndirectFieldPlace) place (v.source), boundary ?? v.parameter);
		}
		if (original is CoreOwnedBorrowValue) {
			var v = (CoreOwnedBorrowValue) original;
			return new CoreOwnedBorrowValue (span, owners.lookup (v.source), boundary ?? v.parameter);
		}
		if (original is CoreReceiverValue) {
			return new CoreReceiverValue (span, target.implicit_receiver);
		}
		if (original is CoreClassUpcast) {
			var cast = (CoreClassUpcast) original;
			return new CoreClassUpcast (span, value (cast.reference), cast.source_class, cast.target_class, concrete);
		}
		if (original is CoreObjectReceiverValue) {
			return new CoreObjectReceiverValue (span, value (((CoreObjectReceiverValue) original).reference), (ReceiverType) concrete);
		}
		if (original is CoreAddressOfValue) {
			var v = (CoreAddressOfValue) original;
			return v.receiver_place == null ? new CoreAddressOfValue (span, concrete, (CoreLocalPlace) place (v.target), v.provenance == null ? null : provenance (v.provenance)) : new CoreAddressOfValue.projection (span, (ReceiverType) concrete, place (v.receiver_place));
		}
		if (original is CoreStorageReceiverValue) {
			return new CoreStorageReceiverValue (span, storages.lookup (((CoreStorageReceiverValue) original).storage), (ReceiverType) concrete);
		}
		if (original is CoreResultStorageReceiverValue) {
			return new CoreResultStorageReceiverValue (span, target.result_storage, (ReceiverType) concrete);
		}
		if (original is CoreOwnedObjectResultConstruction) {
			var construction = (CoreOwnedObjectResultConstruction) original;
			var constructor = (CoreConstructor) call_target (construction.constructor, null, construction.arguments);
			return new CoreOwnedObjectResultConstruction (span, target.result_storage, constructor, values (construction.arguments, constructor.parameters));
		}
		if (original is CoreNullPointerValue) {
			return new CoreNullPointerValue (span, concrete);
		}
		if (original is CoreBooleanValue) {
			return new CoreBooleanValue (span, concrete, ((CoreBooleanValue) original).literal);
		}
		if (original is CoreUtf8FactoryValue) {
			var operation = (CoreUtf8FactoryValue) original;
			return new CoreUtf8FactoryValue (span, concrete, parameters.lookup (operation.input), operation.validates);
		}
		if (original is CoreTextValue) {
			return new CoreTextValue (span, concrete, ((CoreTextValue) original).payload);
		}
		if (original is CoreTextLengthValue) {
			return new CoreTextLengthValue (span, concrete, value (((CoreTextLengthValue) original).receiver));
		}
		if (original is CoreFloatValue) {
			return new CoreFloatValue (span, concrete, ((CoreFloatValue) original).value);
		}
		if (original is CoreIntegerValue) {
			return new CoreIntegerValue.typed (span, concrete, ((CoreIntegerValue) original).value);
		}
		if (original is CorePrefixValue) {
			var v = (CorePrefixValue) original;
			return new CorePrefixValue (span, concrete, v.operator_kind, value (v.operand));
		}
		if (original is CoreComparisonChain) {
			var chain = (CoreComparisonChain) original;
			var operands = new GenericArray<CoreValue> ();
			var operators = new GenericArray<BinaryOperator> ();
			foreach (var operand in chain.operands) {
				operands.add (value (operand));
			}
			for (int i = 0; i < chain.operators.length; i++) {
				operators.add (chain.operators[i]);
			}
			return new CoreComparisonChain (span, concrete, operands, operators);
		}
		if (original is CoreBinaryValue) {
			var v = (CoreBinaryValue) original;
			var left = value (v.left);
			return new CoreBinaryValue (span, concrete, v.operator_kind, left, value (v.right));
		}
		if (original is CoreShortCircuitValue) {
			var v = (CoreShortCircuitValue) original;
			var left = value (v.left);
			return new CoreShortCircuitValue (span, concrete, v.operator_kind, left, value (v.right));
		}
		if (original is CoreIntegerShiftValue) {
			var v = (CoreIntegerShiftValue) original;
			var operand = value (v.operand);
			return new CoreIntegerShiftValue (span, concrete, v.shift_kind, operand, value (v.count));
		}
		if (original is CoreNumericConversionValue) {
			var v = (CoreNumericConversionValue) original;
			return new CoreNumericConversionValue (span, v.source_type, concrete, v.conversion_kind, value (v.operand), v.policy);
		}
		if (original is CoreFloatConversionValue) {
			var v = (CoreFloatConversionValue) original;
			return new CoreFloatConversionValue (span, v.source_type, concrete, v.conversion_kind, value (v.operand));
		}
		if (original is CoreIntegerConversionValue) {
			var v = (CoreIntegerConversionValue) original;
			return new CoreIntegerConversionValue (span, v.source_type, concrete, value (v.operand));
		}
		if (original is CoreVectorConstructValue) {
			return new CoreVectorConstructValue (span, concrete, values (((CoreVectorConstructValue) original).lanes));
		}
		if (original is CoreVectorReductionValue) {
			var v = (CoreVectorReductionValue) original;
			return new CoreVectorReductionValue (span, concrete, v.operator_kind, value (v.operand));
		}
		if (original is CoreVectorSplatValue) {
			var v = (CoreVectorSplatValue) original;
			return new CoreVectorSplatValue (span, concrete, value (v.operand), v.lane_count, v.lane_count_span);
		}
		if (original is CoreVectorExtractValue) {
			var v = (CoreVectorExtractValue) original;
			return new CoreVectorExtractValue (span, concrete, value (v.vector), v.index);
		}
		if (original is CoreVectorInsertValue) {
			var v = (CoreVectorInsertValue) original;
			var vector = value (v.vector);
			return new CoreVectorInsertValue (span, concrete, vector, v.index, value (v.replacement));
		}
		if (original is CoreVectorShuffleValue) {
			var v = (CoreVectorShuffleValue) original;
			return new CoreVectorShuffleValue (span, concrete, value (v.vector), v.selectors);
		}
		if (original is CoreVectorMemoryValue) {
			var memory = (CoreVectorMemoryValue) original;
			var view = value (memory.view);
			var offset = value (memory.offset);
			return new CoreVectorMemoryValue (span, memory.contract, view, offset, memory.stored == null ? null : value (memory.stored));
		}
		if (original is CoreVectorSelectValue) {
			var v = (CoreVectorSelectValue) original;
			var mask = value (v.mask);
			var yes = value (v.true_value);
			return new CoreVectorSelectValue (span, concrete, mask, yes, value (v.false_value));
		}
		if (original is CoreDspValue) {
			var v = (CoreDspValue) original;
			var first = value (v.first);
			return new CoreDspValue (span, v.primitive_kind, v.source_type, concrete, first, v.second == null ? null : value (v.second), v.destination_element);
		}
		if (original is CoreVectorDotValue) {
			var v = (CoreVectorDotValue) original;
			var acc = v.accumulator == null ? null : value (v.accumulator);
			var first = value (v.first);
			return new CoreVectorDotValue (span, v.dot_kind, v.source_type, concrete, acc, first, value (v.second));
		}
		if (original is CoreSliceFromArrayValue) {
			var v = (CoreSliceFromArrayValue) original;
			var start = v.start == null ? null : value (v.start);
			return new CoreSliceFromArrayValue (span, (SliceType) concrete, (CoreLocalPlace) place (v.storage), (ArrayType) type (v.array_type), start, v.count == null ? null : value (v.count), provenance (v.provenance));
		}
		if (original is CoreSliceLengthValue) {
			return new CoreSliceLengthValue (span, concrete, value (((CoreSliceLengthValue) original).slice));
		}
		throw new CoreError.INVALID_IR ("unsupported value '%s' in Core monomorphization of '%s'".printf (original.get_type ().name (), source.name));
	}
}
}
