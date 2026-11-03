// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Source;

namespace Astra.Core {
public class CoreBuilder : Object {
	private HashTable<EnumType, EnumDefinition> enum_definitions = new HashTable<EnumType, EnumDefinition> (direct_hash, direct_equal);
	private GenericArray<Astra.Text.TextBytes> text_literals = new GenericArray<Astra.Text.TextBytes> ();
	private HashTable<GenericStructSymbol, CoreGenericStruct> generic_structs = new HashTable<GenericStructSymbol, CoreGenericStruct> (direct_hash, direct_equal);
	private HashTable<GenericStructFieldSymbol, CoreGenericStructField> generic_fields = new HashTable<GenericStructFieldSymbol, CoreGenericStructField> (direct_hash, direct_equal);
	private HashTable<CorePlace, HashTable<CoreGenericStructField, CoreGenericStructFieldPlace>> generic_projections = new HashTable<CorePlace, HashTable<CoreGenericStructField, CoreGenericStructFieldPlace>> (direct_hash, direct_equal);
	private HashTable<SemanticType, SemanticType> callable_types = new HashTable<SemanticType, SemanticType> (direct_hash, direct_equal);
	private HashTable<SemanticType, SemanticType> class_types = new HashTable<SemanticType, SemanticType> (direct_hash, direct_equal);
	private HashTable<SemanticType, SemanticType> collection_types = new HashTable<SemanticType, SemanticType> (direct_hash, direct_equal);
	private HashTable<SemanticType, TypedPointerType> application_pointers = new HashTable<SemanticType, TypedPointerType> (direct_hash, direct_equal);
	private HashTable<LexicalRegion, Astra.Text.TextLoanExtent> text_extents = new HashTable<LexicalRegion, Astra.Text.TextLoanExtent> (direct_hash, direct_equal);
	private Astra.Text.TextLoanExtent text_extent(LexicalRegion region) {
		var result = text_extents.lookup (region);
		if (result == null) {
			result = new Astra.Text.TextLoanExtent (region.parent == null ? null : text_extent (region.parent), region.ordinal);
			text_extents.insert (region, result);
		}
		return result;
	}

	private HashTable<ResultObjectStorageSymbol, CoreResultObjectStorage> result_storages = new HashTable<ResultObjectStorageSymbol, CoreResultObjectStorage> (direct_hash, direct_equal);
	private HashTable<HandleSymbol, CoreHandle> handles = new HashTable<HandleSymbol, CoreHandle> (direct_hash, direct_equal);
	private HashTable<SemanticType, CoreCleanupContract> buffer_cleanups = new HashTable<SemanticType, CoreCleanupContract> (direct_hash, direct_equal);
	private HashTable<SemanticType, CoreCleanupContract> heap_cleanups = new HashTable<SemanticType, CoreCleanupContract> (direct_hash, direct_equal);
	private HashTable<SemanticType, CoreCleanupContract> object_cleanups = new HashTable<SemanticType, CoreCleanupContract> (direct_hash, direct_equal);
	private HashTable<LocalSymbol, CoreOwnedLocal> owned_locals = new HashTable<LocalSymbol, CoreOwnedLocal> (direct_hash, direct_equal);
	private HashTable<Astra.Foreign.CForeignCleanupContract, CoreCleanupContract> cleanups = new HashTable<Astra.Foreign.CForeignCleanupContract, CoreCleanupContract> (direct_hash, direct_equal);
	private HashTable<LexicalRegion, CoreBlock> scopes = new HashTable<LexicalRegion, CoreBlock> (direct_hash, direct_equal);
	private HashTable<CFunctionSymbol, CoreCFunction> c_functions = new HashTable<CFunctionSymbol, CoreCFunction> (direct_hash, direct_equal);
	private HashTable<FunctionSymbol, CoreFunction> functions = new HashTable<FunctionSymbol, CoreFunction> (direct_hash, direct_equal);
	private HashTable<PropertySymbol, CoreProperty> properties = new HashTable<PropertySymbol, CoreProperty> (direct_hash, direct_equal);
	private HashTable<ReceiverSymbol, CoreReceiver> receivers = new HashTable<ReceiverSymbol, CoreReceiver> (direct_hash, direct_equal);
	private HashTable<ParameterSymbol, CoreParameter> parameters = new HashTable<ParameterSymbol, CoreParameter> (direct_hash, direct_equal);
	private HashTable<LocalSymbol, CoreLocalPlace> locals = new HashTable<LocalSymbol, CoreLocalPlace> (direct_hash, direct_equal);
	private HashTable<CheckedLoopTarget, CoreLoopTarget> loop_targets = new HashTable<CheckedLoopTarget, CoreLoopTarget> (direct_hash, direct_equal);
	private HashTable<CheckedWithContract, CoreWithContract> with_contracts = new HashTable<CheckedWithContract, CoreWithContract> (direct_hash, direct_equal);
	private HashTable<CheckedIterationContract, CoreIterationContract> iterations = new HashTable<CheckedIterationContract, CoreIterationContract> (direct_hash, direct_equal);
	private HashTable<CheckedLoopTarget, CoreFunction> loop_owners = new HashTable<CheckedLoopTarget, CoreFunction> (direct_hash, direct_equal);

	private HashTable<SemanticType, CoreNativeInstance> structs = new HashTable<SemanticType, CoreNativeInstance> (direct_hash, direct_equal);
	private HashTable<StructFieldSymbol, CoreStructField> fields = new HashTable<StructFieldSymbol, CoreStructField> (direct_hash, direct_equal);
	private HashTable<CorePlace, HashTable<CoreStructField, CoreFieldPlace>> projections = new HashTable<CorePlace, HashTable<CoreStructField, CoreFieldPlace>> (direct_hash, direct_equal);

	private GenericArray<CoreCleanupContract> cleanup_contracts = new GenericArray<CoreCleanupContract> ();
	private GenericArray<CoreCleanupContract> generic_contracts = new GenericArray<CoreCleanupContract> ();
	private HashTable<TypeParameterType, CoreCleanupContract> generic_cleanups = new HashTable<TypeParameterType, CoreCleanupContract> (direct_hash, direct_equal);
	private HashTable<SemanticType, CoreCleanupContract> record_cleanups = new HashTable<SemanticType, CoreCleanupContract> (direct_hash, direct_equal);

	// Open Class members carry exact signatures into generic bodies. Their
	// executable bodies belong only to demanded closed Class declarations.
	private CoreFunction build_application_header(FunctionSymbol symbol, CoreClass owner) throws CoreError {
		var inputs = new GenericArray<CoreParameter> ();
		foreach (var parameter in symbol.parameters) {
			var input = new CoreParameter (parameter.span, parameter.name_span, parameter.name, build_type (parameter.semantic_type), parameter.ordinal, parameter.pointer_contract);
			if (parameter.struct_value_contract != null) {
				input.struct_value_contract = new StructValueContract (input.semantic_type, parameter.struct_value_contract.mode);
			}
			input.heap_object = parameter.heap_object;
			if (parameter.requires_nonnull) {
				input.mark_nonnull ();
			}
			inputs.add (input);
			parameters.insert (parameter, input);
		}
		var locals = new GenericArray<CoreLocalPlace> ();
		var body = new CoreBlock (symbol.span, new GenericArray<CoreStatement> ());
		var result = build_type (symbol.return_type);
		CoreFunction header;
		if (symbol is MethodSymbol) {
			var method = (MethodSymbol) symbol;
			var receiver = new CoreReceiver (method.receiver.span, (ReceiverType) build_type (method.receiver.semantic_type));
			header = new CoreMethod (symbol.span, symbol.name_span, symbol.name, owner, receiver, method.ordinal, method.member_ordinal, result, inputs, locals, body,
				symbol.result_contract == ResultOwnershipContract.OWNED_TRANSFER ? ownership_contract (result, symbol.owned_cleanup, symbol.heap_result) : null);
			if (method.generic_method_instance != null) {
				var values = new GenericArray<SemanticType> ();
				foreach (var argument in method.generic_method_instance.arguments.copy_values ()) {
					values.add (build_type (argument));
				}
				((CoreMethod) header).generic_method_instance = new ClassMethodInstance.application (owner.generic_instance, method.generic_method_instance.member, new TypeArgumentVector (values));
			}
		} else if (symbol is PropertyAccessorSymbol) {
			var accessor = (PropertyAccessorSymbol) symbol;
			var property = properties.lookup (accessor.property_symbol);
			var receiver = new CoreReceiver (accessor.receiver.span, (ReceiverType) build_type (accessor.receiver.semantic_type));
			header = (symbol is PropertyGetterSymbol)
			        ? (CoreFunction) new CorePropertyGetter (symbol.span, symbol.name_span, symbol.name, property, receiver, result, inputs, locals, body, symbol.result_contract == ResultOwnershipContract.OWNED_TRANSFER ? ownership_contract (result, symbol.owned_cleanup, symbol.heap_result) : null)
			        : new CorePropertySetter (symbol.span, symbol.name_span, symbol.name, property, receiver, result, inputs, locals, body);
		} else if (symbol is LifecycleSymbol) {
			var lifecycle = (LifecycleSymbol) symbol;
			var receiver = new CoreReceiver (lifecycle.receiver.span, (ReceiverType) build_type (lifecycle.receiver.semantic_type));
			header = (symbol is ConstructorSymbol)
			        ? (CoreFunction) new CoreConstructor (symbol.span, symbol.name_span, owner, receiver, lifecycle.member_ordinal, result, inputs, locals, body)
			        : new CoreDestructor (symbol.span, symbol.name_span, owner, receiver, lifecycle.member_ordinal, result, inputs, locals, body);
		} else {
			throw new CoreError.INVALID_CHECKED_MODEL ("open Class header requires a declared member identity");
		}
		header.throws_type = symbol.throws_type;
		header.dispatch_kind = symbol.dispatch_kind;
		header.virtual_slot = symbol.virtual_slot;
		header.heap_result = symbol.heap_result;
		if (symbol.struct_result_contract != null) {
			header.struct_result_contract = new StructValueContract (result, symbol.struct_result_contract.mode);
		}
		if (symbol.nonnull_result) {
			header.mark_nonnull_result ();
		}
		functions.insert (symbol, header);
		return header;
	}

	private CoreCleanupContract? ownership_contract(SemanticType type, Astra.Foreign.CForeignCleanupContract? resource = null, bool heap = false) throws CoreError {
		type = build_type (type);
		if (type is StructType) {
			var contract = record_cleanups.lookup (type);
			if (contract == null) {
				contract = new CoreCleanupContract.for_record ((CoreStruct) structs.lookup (type), cleanup_contracts.length);
				record_cleanups.insert (type, contract);
				cleanup_contracts.add (contract);
			}
			return contract;
		}
		if (type is SliceType) {
			var contract = buffer_cleanups.lookup (type);
			if (contract == null) {
				contract = new CoreCleanupContract.for_buffer (new BufferValueShape ((SliceType) type, buffer_base_type, buffer_length_type), ownership_span, cleanup_contracts.length);
				buffer_cleanups.insert (type, contract);
				cleanup_contracts.add (contract);
			}
			return contract;
		}
		var parameter = type as TypeParameterType;
		if (parameter != null) {
			var contract = generic_cleanups.lookup (parameter);
			if (contract == null) {
				contract = new CoreCleanupContract.for_parameter (parameter, ownership_span, -1);
				generic_cleanups.insert (parameter, contract);
				generic_contracts.add (contract);
			}
			return contract;
		}
		if (type is ClassType) {
			var authority = heap ? heap_cleanups : object_cleanups;
			var contract = authority.lookup (type);
			if (contract == null) {
				contract = new CoreCleanupContract.for_object ((CoreClass) structs.lookup (type), cleanup_contracts.length, heap);
				authority.insert (type, contract);
				cleanup_contracts.add (contract);
			}
			return contract;
		}
		return cleanups.lookup (resource);
	}

	private Astra.Source.SourceSpan ownership_span;
	private RawPointerType buffer_base_type;
	private IntegerType buffer_length_type;

	private CoreBuilder () {
	}

	public static CoreProgram build(CheckedProgram program) throws CoreError {
		foreach (var function in program.functions) {
			if (!function.symbol.floating_policy_valid ()) {
				throw new CoreError.INVALID_CHECKED_MODEL ("floating policy differs from its admitted declaration");
			}
		}
		foreach (var function in program.generic_functions) {
			if (!function.symbol.floating_policy_valid ()) {
				throw new CoreError.INVALID_CHECKED_MODEL ("generic floating policy differs from its admitted declaration");
			}
		}
		var utf8_error = Utf8FactoryContracts.validate_program (program);
		if (utf8_error != null) {
			throw new CoreError.INVALID_CHECKED_MODEL ("invalid checked UTF-8 factory contract: %s", utf8_error.message);
		}
		var caller_error = CallerInformation.validate_program (program);
		if (caller_error != null) {
			throw new CoreError.INVALID_CHECKED_MODEL ("invalid checked caller-information contract: %s", caller_error.message);
		}
		var builder = new CoreBuilder ();
		return builder.build_program (program);
	}

	private SemanticType build_type(SemanticType type) throws CoreError {
		if (type is ExactGenericClassType) {
			var prior = class_types.lookup (type);
			if (prior != null) {
				return prior;
			}
			var application = (ExactGenericClassType) type;
			var arguments = new GenericArray<SemanticType> ();
			foreach (var argument in application.arguments.copy_values ()) {
				arguments.add (build_type (argument));
			}
			SemanticType mapped = type;
			if (!application.arguments.matches_array (arguments)) {
				mapped = new ExactGenericClassType.application (application.definition, new TypeArgumentVector (arguments));
				mapped.bind_logical_identity (type.logical_identity);
			}
			class_types.insert (type, mapped);
			class_types.insert (mapped, mapped);
			return mapped;
		}
		if (type is ReceiverType) {
			var prior = class_types.lookup (type);
			if (prior != null) {
				return prior;
			}
			var receiver = (ReceiverType) type;
			var instance = build_type (receiver.instance_type);
			SemanticType mapped = instance == receiver.instance_type ? type : new ReceiverType (instance, receiver.mode);
			class_types.insert (type, mapped);
			return mapped;
		}
		if (type is CallableSignature) {
			var prior = callable_types.lookup (type);
			if (prior != null) {
				return prior;
			}
			var parameters = new GenericArray<SemanticType> ();
			foreach (var parameter in ((CallableSignature) type).parameter_types) {
				parameters.add (build_type (parameter));
			}
			var closure = type as ClosureHandleType;
			var environment = closure == null ? null : (ClassType) build_type (closure.environment_type);
			var mapped = CallableTypes.with_parameters (type, parameters, build_type (CallableTypes.result_type (type)), environment);
			callable_types.insert (type, mapped);
			return mapped;
		}
		if (type is EnumType && ((EnumType) type).argument_count != 0) {
			var enumeration = (EnumType) type;
			var arguments = new GenericArray<SemanticType> ();
			for (uint i = 0; i < enumeration.argument_count; i++) {
				arguments.add (build_type (enumeration.argument (i)));
			}
			return enumeration.application (arguments);
		}
		if (type is ArrayType || type is SliceType) {
			var prior = collection_types.lookup (type);
			if (prior != null) {
				return prior;
			}
			var element = (type is ArrayType) ? ((ArrayType) type).element_type : ((SliceType) type).element_type;
			var mapped = build_type (element);
			SemanticType result = mapped == element ? type : (type is ArrayType) ? (SemanticType) new ArrayType (mapped, ((ArrayType) type).length) : new SliceType (mapped);
			collection_types.insert (type, result);
			return result;
		}
		var application = type as GenericStructApplicationType;
		if (application != null) {
			var definition = application.definition == null ? null : generic_structs.lookup (application.definition);
			if (definition == null || application.logical_identity != definition.identity.nominal_identity.application (application.type_arguments)) {
				throw new CoreError.INVALID_CHECKED_MODEL ("generic application requires its exact checked definition and nominal argument identity");
			}
			var arguments = new GenericArray<SemanticType> ();
			foreach (var argument in application.type_arguments) {
				arguments.add (build_type (argument));
			}
			return definition.application (arguments);
		}
		var pointer = type as TypedPointerType;
		if (pointer != null && pointer.pointee is GenericStructApplicationType) {
			if (pointer.pointee.is_parameterized ()) {
				throw new CoreError.INVALID_CHECKED_MODEL ("parameterized generic Struct* is deferred");
			}
			var pointee = build_type (pointer.pointee);
			var result = application_pointers.lookup (pointee);
			if (result == null) {
				result = new TypedPointerType (pointee);
				application_pointers.insert (pointee, result);
			}
			return result;
		}
		return type;
	}

	private void check_struct_contract(SemanticType type, StructValueContract? contract, FunctionSymbol scope, bool result = false, bool borrowed_parameter = false) throws CoreError {
		if (type.is_struct_storage () != (contract != null) || (contract != null && (contract.semantic_type != type || type.is_parameterized () && (!(scope is GenericFunctionSymbol) || contract.mode != StructValueMode.COPY_VALUE)))) {
			throw new CoreError.INVALID_CHECKED_MODEL ("checked struct boundary requires an explicit exact scoped value contract");
		}
		if (contract != null && contract.mode == StructValueMode.BORROW_VALUE && (type.is_parameterized () || !(borrowed_parameter || result && scope is PropertyGetterSymbol && scope.result_contract == ResultOwnershipContract.RECEIVER_BORROW))) {
			throw new CoreError.INVALID_CHECKED_MODEL ("borrowed record result requires its exact concrete receiver-bound property contract");
		}
	}

	private GenericArray<SemanticType>? callable_fields(SemanticType type) {
		var fields = new GenericArray<SemanticType> ();
		var application = type as CoreGenericStructApplicationType;
		if (application != null && application.definition != null) {
			foreach (var field in application.definition.fields) {
				fields.add (application.field_type (field));
			}
			return fields;
		}
		var structure = structs.lookup (type);
		if (structure == null) {
			return null;
		}
		foreach (var field in structure.fields) {
			fields.add (field.semantic_type);
		}
		return fields;
	}

	private CoreProgram build_program(CheckedProgram program) throws CoreError {
		foreach (var symbol in program.classes) {
			var type = symbol.semantic_type as ExactGenericClassType;
			var key = symbol.generic_instance;
			if (type == null && key == null) {
				continue;
			}
			if (type == null || key == null || !key.valid (type) || !program.generic_classes.find (key.definition)) {
				throw new CoreError.INVALID_CHECKED_MODEL ("generic Class requires its exact checked argument vector and declared definition");
			}
		}
		var checked_definitions = program.all_definitions ();
		var generic_definitions = new GenericArray<CoreGenericFunction> ();
		var structures = new GenericArray<CoreStruct> ();
		var classes = new GenericArray<CoreClass> ();
		var generic_struct_definitions = new GenericArray<CoreGenericStruct> ();
		int source_struct_ordinal = 0;
		foreach (var checked_struct in program.generic_structs) {
			var symbol = checked_struct.definition;
			if (generic_structs.contains (symbol) || symbol.ordinal != source_struct_ordinal++) {
				throw new CoreError.INVALID_CHECKED_MODEL ("generic struct requires exact unique definition and ordinal");
			}
			// Closed owning records have already entered the ordinary record
			// ownership proof with an immutable declaration/argument contract.
			if (symbol.owning_storage) {
				if (symbol.owning_contract == null) {
					throw new CoreError.INVALID_CHECKED_MODEL ("owning record lost its declared storage contract");
				}
				continue;
			}
			var parameters = new GenericArray<CoreTypeParameter> ();
			foreach (var parameter in symbol.type_parameters) {
				parameters.add (new CoreTypeParameter (parameter.span, parameter.semantic_type, parameter.ordinal));
			}
			var definition = new CoreGenericStruct (symbol.span, symbol.name_span, symbol.name, parameters, generic_struct_definitions.length, symbol.nominal_identity);
			generic_structs.insert (symbol, definition);
			generic_struct_definitions.add (definition);
		}
		foreach (var checked_struct in program.generic_structs) {
			if (checked_struct.definition.owning_storage) {
				continue;
			}
			var definition = generic_structs.lookup (checked_struct.definition);
			foreach (var field in checked_struct.fields) {
				if (field.definition != checked_struct.definition || generic_fields.contains (field)) {
					throw new CoreError.INVALID_CHECKED_MODEL ("generic field requires its exact definition origin");
				}
				var result = new CoreGenericStructField (field.span, field.name_span, field.name, definition, build_type (field.semantic_type), field.ordinal);
				definition.fields.add (result);
				generic_fields.insert (field, result);
			}
		}
		var class_applications = new GenericArray<CoreClass> ();
		var field_instances = program.native_instances ();
		foreach (var application in program.class_applications) {
			field_instances.add (application);
		}
		foreach (var symbol in field_instances) {
			var record_type = symbol.semantic_type as StructType;
			if (record_type != null && record_type.owning_application != null && (!(symbol is StructSymbol) || ((StructSymbol) symbol).owning_instantiation == null || ((StructSymbol) symbol).owning_instantiation.origin.owning_contract != record_type.owning_application.definition || !((StructSymbol) symbol).owning_instantiation.arguments.matches (record_type.owning_application.arguments))) {
				throw new CoreError.INVALID_CHECKED_MODEL ("owning record lost its exact checked declaration and argument snapshot");
			}
			if (structs.contains (symbol.semantic_type)) {
				throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: repeated struct type identity");
			}
			CoreNativeInstance structure = (symbol is ClassSymbol) ? (CoreNativeInstance) new CoreClass (symbol.span, symbol.name_span, symbol.name, (ClassType) build_type (symbol.semantic_type), symbol.ordinal) : new CoreStruct (symbol.span, symbol.name_span, symbol.name, symbol.semantic_type, symbol.ordinal);
			if (symbol is StructSymbol) {
				var original = ((StructSymbol) symbol).representation;
				var type = (StructType) symbol.semantic_type;
				string[] names = {};
				string[] types = {};
				foreach (var field in symbol.fields) {
					names += field.name;
					types += field.semantic_type.display_name ();
				}
				if (original == null ? type.representation_identity != "" : !original.matches (type.representation_identity, symbol.name, names, types)) {
					throw new CoreError.INVALID_CHECKED_MODEL ("POD layout differs from its exact admitted checked declaration");
				}
				((CoreStruct) structure).representation = original == null ? null : original.copy ();
			}
			structs.insert (symbol.semantic_type, structure);
			structs.insert (structure.semantic_type, structure);
			if (structure is CoreClass && structure.semantic_type.is_parameterized ()) {
				var application = (CoreClass) structure;
				var type = (ExactGenericClassType) application.semantic_type;
				application.generic_instance = new ExactClassGenericInstance.application (type.definition, type.arguments, type);
				application.application_receiver = (ReceiverType) build_type (symbol.receiver_type);
				class_applications.add (application);
			} else if (structure is CoreClass) {
				classes.add ((CoreClass) structure);
			} else {
				structures.add ((CoreStruct) structure);
			}
			foreach (var property in symbol.properties) {
				if (property.declaring_type != symbol || properties.contains (property)) {
					throw new CoreError.INVALID_CHECKED_MODEL ("property requires exact declaring member owner");
				}
				var declaration = new CoreProperty (property.span, property.name_span, property.name, structure, build_type (property.semantic_type), property.ordinal, property.member_ordinal);
				declaration.is_lazy = property.is_lazy;
				declaration.is_owned_lazy = property.is_owned_lazy;
				declaration.is_borrowed = property.is_borrowed;
				structure.properties.add (declaration);
				properties.insert (property, declaration);
			}
			foreach (var field in symbol.fields) {
				if (field.containing_type != symbol || fields.contains (field)) {
					throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: inconsistent struct field ownership");
				}
				var descriptor = new CoreStructField (field.span, field.name_span, field.name, structure, build_type (field.semantic_type), field.ordinal, null, field.is_private);
				if (field.requires_nonnull) {
					descriptor.mark_nonnull ();
				}
				descriptor.text_snapshot = field.text_snapshot;
				structure.fields.add (descriptor);
				fields.insert (field, descriptor);
			}
		}
		foreach (var instance in field_instances) {
			var symbol = instance as ClassSymbol;
			if (symbol == null) {
				continue;
			}
			var owner = (CoreClass) structs.lookup (symbol.semantic_type);
			if (!ForeignClassPolicy.matches (symbol.foreign_export, ((ClassType) symbol.semantic_type).foreign_policy_identity, symbol.name)) {
				throw new CoreError.INVALID_CHECKED_MODEL ("foreign Class export differs from its admitted declaration");
			}
			owner.foreign_export = symbol.foreign_export == null ? null : symbol.foreign_export.copy ();
			if (!ConcurrencyPolicy.matches (symbol.concurrency_policy, ((ClassType) symbol.semantic_type).concurrency_policy_identity)) {
				throw new CoreError.INVALID_CHECKED_MODEL ("Class concurrency policy differs from its admitted declaration");
			}
			if (!AllocationPolicy.matches (symbol.allocation_policy, ((ClassType) symbol.semantic_type).allocation_policy_identity)) {
				throw new CoreError.INVALID_CHECKED_MODEL ("Class allocation policy differs from its admitted declaration");
			}
			owner.allocation_policy = symbol.allocation_policy == null ? null : symbol.allocation_policy.copy ();
			owner.concurrency_policy = symbol.concurrency_policy == null ? null : symbol.concurrency_policy.copy ();
			var application_type = owner.semantic_type as ExactGenericClassType;
			owner.generic_instance = symbol.generic_instance == null ? null : new ExactClassGenericInstance.application (application_type.definition, application_type.arguments, application_type);
			var key = owner.generic_instance;
			var shape = key == null ? null : key.definition.structure;
			if (shape != null) {
				if (owner.fields.length != shape.field_count) {
					throw new CoreError.INVALID_CHECKED_MODEL ("generic Class requires all checked declared fields");
				}
				for (int f = 0; f < owner.fields.length; f++) {
					var field = owner.fields[f];
					var declared = shape.field (f);
					if (field.ordinal != f || field.name != declared.name || field.is_private != declared.private_field || !GenericClassDeclaredShape.type (declared.value_type, field.semantic_type, key, null, callable_fields)) {
						throw new CoreError.INVALID_CHECKED_MODEL ("generic Class checked field requires its exact declared type pattern and position");
					}
				}
			}
			owner.parent_class = symbol.parent_class == null ? null : (CoreClass) structs.lookup (symbol.parent_class.semantic_type);
			owner.polymorphic = symbol.polymorphic;
			owner.exception_root = symbol.exception_root;
		}
		ownership_span = program.span;
		buffer_base_type = program.types.raw_pointer_type;
		buffer_length_type = program.types.i32_type;
		var handle_declarations = new GenericArray<CoreHandle> ();
		foreach (var symbol in program.handles) {
			if (!(symbol.c_import == null ? ComImportContract.matches (symbol.com_import, symbol.semantic_type.foreign_policy_identity, symbol.name, symbol.cleanup.external_symbol) : ForeignImportContract.matches (symbol.c_import, symbol.semantic_type.foreign_policy_identity, symbol.name, symbol.cleanup.external_symbol))) {
				throw new CoreError.INVALID_CHECKED_MODEL ("COMImport lost its admitted checked IID/cleanup/context authority");
			}
			if (handles.contains (symbol) || symbol.ordinal != handle_declarations.length) {
				throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: repeated or unordered handle symbol");
			}
			var cleanup = cleanups.lookup (symbol.cleanup);
			if (cleanup == null) {
				cleanup = new CoreCleanupContract (symbol.cleanup.external_symbol, symbol.cleanup.symbol_span ?? symbol.name_span, cleanup_contracts.length);
				cleanup.closure_type = build_type (symbol.semantic_type) as ClosureHandleType;
				if (cleanup.closure_type != null) {
					cleanup.closure_environment = (CoreClass) structs.lookup (cleanup.closure_type.environment_type);
				}
				cleanup.shared_type = symbol.semantic_type as SharedHandleType;
				if (cleanup.shared_type != null) {
					cleanup.shared_payload = (CoreClass) structs.lookup (cleanup.shared_type.payload_type);
				}
				cleanups.insert (symbol.cleanup, cleanup);
				cleanup_contracts.add (cleanup);
			}
			var handle = new CoreHandle (symbol.span, symbol.name_span, (HandleType) build_type (symbol.semantic_type), cleanup, symbol.header, symbol.ordinal, symbol.context_mode);
			handle.c_import = symbol.c_import;
			handle.com_import = symbol.com_import == null ? null : symbol.com_import.copy ();
			handles.insert (symbol, handle);
			handle_declarations.add (handle);
		}
		foreach (var symbol in field_instances) {
			foreach (var field in symbol.fields) {
				if (field.semantic_type is OwnerSlotsType) {
					var element = ((OwnerSlotsType) field.semantic_type).element;
					Astra.Foreign.CForeignCleanupContract? resource = null;
					foreach (var handle in program.handles) {
						if (handle.semantic_type == element) {
							resource = handle.cleanup;
						}
					}
					fields.lookup (field).slots_cleanup = (element is StructType) ? null : ownership_contract (element, resource, element is ClassType);
				}
				fields.lookup (field).owned_cleanup = field.owns_parameter || field.owns_record ? ownership_contract (field.semantic_type) : field.owns_child ? ownership_contract (field.semantic_type, null, true) : field.owns_buffer ? ownership_contract (field.semantic_type) : field.owned_cleanup == null ? null : cleanups.lookup (field.owned_cleanup);
			}
		}
		var declarations = new GenericArray<CoreFunction> ();
		var imports = new GenericArray<CoreCFunction> ();
		foreach (var symbol in program.c_functions) {
			if (!symbol.metadata.bool_policy_valid ()) {
				throw new CoreError.INVALID_CHECKED_MODEL ("foreign import lost its admitted C99 boolean policy");
			}
			if (!symbol.metadata.import_policy_valid ()) {
				throw new CoreError.INVALID_CHECKED_MODEL ("foreign import lost its admitted policy or GObject bridge/header identity");
			}
			bool device_parameters = true;
			foreach (var parameter in symbol.parameters) {
				device_parameters &= parameter.semantic_type.kind == TypeKind.INT && parameter.pointer_contract == PointerParameterContract.UNMANAGED;
			}
			if (!symbol.metadata.device_signature (symbol.return_type.kind == TypeKind.INT, symbol.parameters.length, device_parameters)) {
				throw new CoreError.INVALID_CHECKED_MODEL ("PC device lost its checked declaration operation or exact scalar ABI");
			}
			if (c_functions.contains (symbol)) {
				throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: repeated C function symbol");
			}
			var parameter_types = new GenericArray<SemanticType> ();
			var import_parameters = new GenericArray<CoreParameter> ();
			foreach (var parameter in symbol.parameters) {
				if (parameter.requires_nonnull) {
					throw new CoreError.INVALID_CHECKED_MODEL ("foreign nonnull contracts cannot be assumed");
				}
				parameter_types.add (parameter.semantic_type);
				var core_parameter = new CoreParameter (parameter.span, parameter.name_span, parameter.name, build_type (parameter.semantic_type), parameter.ordinal, parameter.pointer_contract);
				if (parameter.struct_value_contract != null) {
					core_parameter.struct_value_contract = new StructValueContract (core_parameter.semantic_type, parameter.struct_value_contract.mode);
				}
				import_parameters.add (core_parameter);
				parameters.insert (parameter, core_parameter);
			}
			CoreCleanupContract? cleanup = null;
			if (symbol.metadata.owned_result != null) {
				var source = symbol.metadata.owned_result.cleanup;
				cleanup = cleanups.lookup (source);
				if (cleanup == null) {
					cleanup = new CoreCleanupContract (source.external_symbol, source.symbol_span ?? symbol.name_span, cleanup_contracts.length);
					cleanups.insert (source, cleanup);
					cleanup_contracts.add (cleanup);
				}
			}
			var imported = new CoreCFunction (symbol.span, symbol.name_span, symbol.name, symbol.metadata.copy_with_owned_result (), symbol.abi, symbol.return_type, parameter_types, imports.length, cleanup, import_parameters);
			imports.add (imported);
			c_functions.insert (symbol, imported);
		}
		// Only classes used as owners acquire a transfer contract. Ordinary
		// fixed objects retain their original lifecycle graph and dumps.
		foreach (var checked_function in checked_definitions) {
			var declaration = checked_function.native_declaration;
			if (declaration != null && (!checked_function.symbol.name_span.file.native_interface || !declaration.same_signature (NativeDeclarationRegistry.signature (declaration.identity, checked_function.symbol)))) {
				throw new CoreError.INVALID_CHECKED_MODEL ("native declaration lost its original exact source signature");
			}
			var result_storage = checked_function.symbol.result_storage;
			if (result_storage != null && !object_cleanups.contains (result_storage.semantic_type)) {
				var cleanup = new CoreCleanupContract.for_object ((CoreClass) structs.lookup (result_storage.semantic_type), cleanup_contracts.length);
				object_cleanups.insert (result_storage.semantic_type, cleanup);
				cleanup_contracts.add (cleanup);
			}
			foreach (var local in checked_function.locals) {
				if (local.object_owner == null || object_cleanups.contains (local.semantic_type)) {
					continue;
				}
				var cleanup = new CoreCleanupContract.for_object ((CoreClass) structs.lookup (local.semantic_type), cleanup_contracts.length);
				object_cleanups.insert (local.semantic_type, cleanup);
				cleanup_contracts.add (cleanup);
			}
		}
		foreach (var definition in program.enums) {
			enum_definitions.insert (definition.semantic_type, build_enum_definition (definition));
		}
		foreach (var application in program.class_applications) {
			var owner = (CoreClass) structs.lookup (application.semantic_type);
			foreach (var method in application.methods) {
				owner.methods.add ((CoreMethod) build_application_header (method, owner));
			}
			foreach (var property in application.properties) {
				var declaration = properties.lookup (property);
				declaration.getter = (CorePropertyGetter) build_application_header (property.getter, owner);
				if (property.setter != null) {
					declaration.setter = (CorePropertySetter) build_application_header (property.setter, owner);
				}
			}
			if (application.constructor != null) {
				owner.constructor = (CoreConstructor) build_application_header (application.constructor, owner);
			}
			if (application.destructor != null) {
				owner.destructor = (CoreDestructor) build_application_header (application.destructor, owner);
			}
		}
		// Establish function, parameter, and local identities before bodies.
		var method_applications = new GenericArray<CoreMethod> ();
		foreach (var application in program.method_applications) {
			var owner = (CoreClass) structs.lookup (application.declaring_type.semantic_type);
			if (owner == null) {
				throw new CoreError.INVALID_CHECKED_MODEL ("generic method application requires its exact Class owner");
			}
			method_applications.add ((CoreMethod) build_application_header (application, owner));
		}
		// Tables are identity maps only; source arrays determine traversal order.
		for (int i = 0; i < checked_definitions.length; i++) {
			var checked_function = checked_definitions[i];
			var symbol = checked_function.symbol;
			check_struct_contract (symbol.return_type, symbol.struct_result_contract, symbol, true);
			if (functions.contains (symbol)) {
				throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: repeated function symbol at function #%d", i);
			}
			var core_parameters = new GenericArray<CoreParameter> ();
			for (int j = 0; j < symbol.parameters.length; j++) {
				var parameter = symbol.parameters[j];
				check_struct_contract (parameter.semantic_type, parameter.struct_value_contract, symbol, false, parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
				if (parameters.contains (parameter) || parameter.ordinal != j) {
					throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: inconsistent parameter declaration at function #%d/parameter #%d", i, j);
				}
				var core_parameter = new CoreParameter (parameter.span, parameter.name_span, parameter.name, build_type (parameter.semantic_type), parameter.ordinal, parameter.pointer_contract);
				if (parameter.struct_value_contract != null) {
					core_parameter.struct_value_contract = new StructValueContract (core_parameter.semantic_type, parameter.struct_value_contract.mode);
				}
				core_parameter.heap_object = parameter.heap_object;
				if (parameter.requires_nonnull) {
					core_parameter.mark_nonnull ();
				}
				core_parameters.add (core_parameter);
				parameters.insert (parameter, core_parameter);
			}
			var core_locals = new GenericArray<CoreLocalPlace> ();
			for (int j = 0; j < checked_function.locals.length; j++) {
				var local = checked_function.locals[j];
				if (locals.contains (local) || local.ordinal != j) {
					throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: inconsistent local declaration at function #%d/local #%d", i, j);
				}
				var place = new CoreLocalPlace (local.span, local.name_span, local.name, build_type (local.semantic_type), local.ordinal, local.address_taken, local.incoming_parameter == null ? null : parameters.lookup (local.incoming_parameter));
				if (local.requires_nonnull || (local.incoming_parameter != null && local.incoming_parameter.requires_nonnull)) {
					place.mark_nonnull ();
				}
				place.text_extent = text_extent (local.lexical_region);
				place.text_loan = local.text_loan;
				core_locals.add (place);
				locals.insert (local, place);
			}
			var body = new CoreBlock (checked_function.body.span, new GenericArray<CoreStatement> ());
			body.text_extent = text_extent (checked_function.body.region);
			scopes.insert (checked_function.body.region, body);
			CoreFunction function;
			var method = symbol as MethodSymbol;
			var cleanup = symbol.result_contract == ResultOwnershipContract.OWNED_TRANSFER ? ownership_contract (symbol.return_type, symbol.owned_cleanup, symbol.heap_result) : null;
			var lifecycle = symbol as LifecycleSymbol;
			if (lifecycle != null) {
				var owner = lifecycle.declaring_class;
				var object_class = structs.lookup (owner.semantic_type) as CoreClass;
				if (object_class == null || ((symbol is ConstructorSymbol) ? owner.constructor != symbol || !(checked_function is CheckedConstructor) : owner.destructor != symbol || !(checked_function is CheckedDestructor))) {
					throw new CoreError.INVALID_CHECKED_MODEL ("lifecycle requires exact declaring class and checked callable identity");
				}
				var receiver = new CoreReceiver (lifecycle.receiver.span, (ReceiverType) build_type (lifecycle.receiver.semantic_type));
				receivers.insert (lifecycle.receiver, receiver);
				if (symbol is ConstructorSymbol) {
					var constructor = new CoreConstructor (symbol.span, symbol.name_span, object_class, receiver, lifecycle.member_ordinal, build_type (symbol.return_type), core_parameters, core_locals, body);
					object_class.constructor = constructor;
					function = constructor;
				} else {
					var destructor = new CoreDestructor (symbol.span, symbol.name_span, object_class, receiver, lifecycle.member_ordinal, build_type (symbol.return_type), core_parameters, core_locals, body);
					object_class.destructor = destructor;
					function = destructor;
				}
			} else if (symbol is PropertyAccessorSymbol) {
				var accessor = (PropertyAccessorSymbol) symbol;
				var property = properties.lookup (accessor.property_symbol);
				if (!(checked_function is CheckedPropertyAccessor) || property == null || ((symbol is PropertyGetterSymbol) ? accessor.property_symbol.getter != symbol : accessor.property_symbol.setter != symbol) || accessor.receiver.semantic_type != accessor.property_symbol.declaring_type.receiver_type || receivers.contains (accessor.receiver)) {
					throw new CoreError.INVALID_CHECKED_MODEL ("accessor requires its exact property identity and receiver");
				}
				var receiver = new CoreReceiver (accessor.receiver.span, (ReceiverType) build_type (accessor.receiver.semantic_type));
				receivers.insert (accessor.receiver, receiver);
				if (symbol is PropertyGetterSymbol) {
					var getter = new CorePropertyGetter (symbol.span, symbol.name_span, symbol.name, property, receiver, build_type (symbol.return_type), core_parameters, core_locals, body, cleanup);
					property.getter = getter;
					function = getter;
				} else {
					var setter = new CorePropertySetter (symbol.span, symbol.name_span, symbol.name, property, receiver, build_type (symbol.return_type), core_parameters, core_locals, body);
					property.setter = setter;
					function = setter;
				}
			} else if (method != null) {
				var owner = method.declaring_type;
				var structure = owner == null ? null : structs.lookup (owner.semantic_type);
				if (!(checked_function is CheckedMethod) || structure == null || method.ordinal != structure.methods.length || method.ordinal >= owner.methods.length || owner.methods[method.ordinal] != method || method.receiver.semantic_type != owner.receiver_type || receivers.contains (method.receiver)) {
					throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: method requires exact declaring struct, receiver and member identity");
				}
				var receiver = new CoreReceiver (method.receiver.span, (ReceiverType) build_type (method.receiver.semantic_type));
				receivers.insert (method.receiver, receiver);
				var declaration = new CoreMethod (checked_function.span, symbol.name_span, symbol.name, structure, receiver, method.ordinal, method.member_ordinal, build_type (symbol.return_type), core_parameters, core_locals, body, cleanup);
				if (method.generic_method_instance != null) {
					var arguments = new GenericArray<SemanticType> ();
					foreach (var argument in method.generic_method_instance.arguments.copy_values ()) {
						arguments.add (build_type (argument));
					}
					declaration.generic_method_instance = new ClassMethodInstance.application (((CoreClass) structure).generic_instance, method.generic_method_instance.member, new TypeArgumentVector (arguments));
				}
				structure.methods.add (declaration);
				function = declaration;
			} else if (symbol is GenericFunctionSymbol) {
				var generic = (GenericFunctionSymbol) symbol;
				if (!(checked_function is CheckedGenericFunction)) {
					throw new CoreError.INVALID_CHECKED_MODEL ("generic definition requires its checked generic body");
				}
				var type_parameters = new GenericArray<CoreTypeParameter> ();
				foreach (var parameter in generic.type_parameters) {
					type_parameters.add (new CoreTypeParameter (parameter.span, parameter.semantic_type, parameter.ordinal));
				}
				var definition = new CoreGenericFunction (checked_function.span, symbol.name_span, symbol.name, build_type (symbol.return_type), core_parameters, core_locals, body, cleanup, type_parameters, generic_definitions.length);
				foreach (var parameter in generic.type_parameters) {
					if (generic.element_obligations.contains (parameter.semantic_type)) {
						definition.element_obligations.require (parameter.semantic_type, generic.element_obligations.requirements (parameter.semantic_type));
					}
				}
				foreach (var requirement in generic.capability_requirements) {
					var parameter = type_parameters[requirement.type_parameter.ordinal];
					var core_requirement = new CoreGenericCapabilityRequirement (requirement.span, parameter, requirement.capability.identity);
					parameter.capability_requirements.add (core_requirement);
					definition.capability_requirements.add (core_requirement);
				}
				generic_definitions.add (definition);
				function = definition;
			} else {
				function = new CoreFunction (checked_function.span, symbol.name_span, symbol.name, build_type (symbol.return_type), core_parameters, core_locals, body, cleanup);
			}
			function.heap_result = symbol.heap_result;
			if (checked_function.native_declaration != null) {
				function.bind_native_declaration (checked_function.native_declaration);
			}
			function.utf8_factory = symbol.utf8_factory;
			function.bind_floating_policy (symbol.floating_policy);
			if (symbol.nonnull_result) {
				function.mark_nonnull_result ();
			}
			if (symbol.struct_result_contract != null) {
				function.struct_result_contract = new StructValueContract (function.return_type, symbol.struct_result_contract.mode);
			}
			if (symbol.result_storage != null) {
				function.result_storage = new CoreResultObjectStorage (symbol.span, (CoreClass) structs.lookup (symbol.return_type));
				result_storages.insert (symbol.result_storage, function.result_storage);
			}
			if (!symbol.result_contract.is_valid () || (symbol.result_contract == ResultOwnershipContract.OWNED_TRANSFER) != (function.owned_cleanup != null)) {
				throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: native result contract requires exact cleanup mapping");
			}
			foreach (var local in checked_function.locals) {
				if (local.incoming_parameter == null || local.is_struct_parameter || local.is_enum_parameter) {
					continue;
				}
				var owner = new CoreOwnedLocal (local.span, locals.lookup (local), ownership_contract (local.semantic_type, local.cleanup, local.heap_object), body);
				function.owned_locals.add (owner);
				owned_locals.insert (local, owner);
				body.statements.add (new CoreAcquireParameter (local.span, owner, parameters.lookup (local.incoming_parameter)));
			}
			foreach (var local in core_locals) {
				if (local.semantic_type.kind != TypeKind.STRUCT) {
					continue;
				}
				var structure = structs.lookup (local.semantic_type);
				if (structure == null) {
					throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: struct local has no declared type mapping");
				}
				declare_projections (local, function);
			}
			foreach (var local in checked_function.locals) {
				if (!local.is_struct_parameter) {
					continue;
				}
				if (local.is_record_owner) {
					register_boundary_record (local, function, body);
				}
				body.statements.add (new CoreAcquireStructParameter (local.span, locals.lookup (local), parameters.lookup (local.incoming_parameter)));
			}
			foreach (var local in checked_function.locals) {
				if (local.is_enum_parameter) {
					body.statements.add (new CoreAcquireEnumParameter (local.span, locals.lookup (local), parameters.lookup (local.incoming_parameter)));
				}
			}
			if (!(function is CoreGenericFunction)) {
				declarations.add (function);
			}
			function.async_body = symbol.async_body;
			function.throws_type = symbol.throws_type;
			function.dispatch_kind = symbol.dispatch_kind;
			function.virtual_slot = symbol.virtual_slot;
			functions.insert (symbol, function);
		}
		for (int i = 0; i < checked_definitions.length; i++) {
			var checked_function = checked_definitions[i];
			var function = functions.lookup (checked_function.symbol);
			if (function == null) {
				throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: missing function mapping at function #%d", i);
			}
			for (int j = 0; j < checked_function.body.statements.length; j++) {
				append_statement (checked_function.body.statements[j], function, function.body);
			}
		}
		foreach (var symbol in program.native_instances ()) {
			foreach (var property in symbol.properties) {
				if (property.factory != null) {
					properties.lookup (property).factory = (CoreMethod) functions.lookup (property.factory);
				}
			}
		}
		foreach (var symbol in program.classes) {
			var owner = (CoreClass) structs.lookup (symbol.semantic_type);
			foreach (var entry in symbol.virtual_entries) {
				owner.virtual_entries.add (functions.lookup (entry));
			}
		}
		foreach (var owner in classes) {
			bool owns_fields = false;
			foreach (var property in owner.properties) {
				owns_fields |= property.is_owned_lazy;
			}
			foreach (var field in owner.fields) {
				if (field.owned_cleanup != null || field.semantic_type is OwnerSlotsType || field.text_snapshot) {
					owns_fields = true;
				}
			}
			if (!owns_fields) {
				continue;
			}
			if (owner.destructor == null) {
				var receiver = new CoreReceiver (owner.span, (ReceiverType) build_type (program.classes[owner.ordinal].receiver_type));
				var body = new CoreBlock (owner.span, new GenericArray<CoreStatement> ());
				owner.destructor = new CoreDestructor (owner.span, owner.name_span, owner, receiver, (int) (owner.fields.length + owner.methods.length + owner.properties.length + owner.lifecycle_count), program.types.void_type, new GenericArray<CoreParameter> (), new GenericArray<CoreLocalPlace> (), body);
				bind_derived_native_destructor (owner, program);
				declarations.add (owner.destructor);
			}
			for (int p = owner.properties.length - 1; p >= 0; p--) {
				if (owner.properties[p].is_owned_lazy) {
					owner.destructor.lazy_cleanups.add (owner.properties[p]);
				}
			}
			for (int f = owner.fields.length - 1; f >= 0; f--) {
				var field = owner.fields[f];
				if (field.semantic_type is OwnerSlotsType) {
					owner.destructor.field_cleanups.add (field.slots_cleanup == null ? new CoreOwnedFieldCleanup.snapshot (field.span, field) : new CoreOwnedFieldCleanup (field.span, field, field.slots_cleanup));
				} else if (field.text_snapshot) {
					owner.destructor.field_cleanups.add (new CoreOwnedFieldCleanup.snapshot (field.span, field));
				} else if (field.owned_cleanup != null) {
					owner.destructor.field_cleanups.add (new CoreOwnedFieldCleanup (field.span, field, field.owned_cleanup));
				}
			}
		}
		foreach (var owner in classes) {
			ensure_base_destructor (owner, program, declarations);
		}
		foreach (var owner in classes) {
			if (owner.constructor == null || !ConstructorContracts.admitted (owner.foreign_export, owner.allocation_policy, owner.constructor.member_ordinal, owner.constructor.throws_type) || owner.destructor == null) {
				continue;
			}
			foreach (var action in owner.destructor.field_cleanups) {
				owner.constructor.unwind_fields.add (action);
			}
			foreach (var property in owner.destructor.lazy_cleanups) {
				owner.constructor.unwind_lazy.add (property);
			}
		}
		var exports = new GenericArray<CoreCExport> ();
		foreach (var exported in program.c_exports) {
			if (!exported.bool_policy_valid ()) {
				throw new CoreError.INVALID_CHECKED_MODEL ("C export lost its admitted bool ABI policy");
			}
			var source_target = exported.target;
			var target = source_target == null ? null : functions.lookup (source_target);
			if (target == null) {
				throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: C export target is expired or has no exact native mapping");
			}
			exports.add (new CoreCExport (exported.span, exported.name_span, target, exported.external_symbol, exported.abi, exported.ordinal, exported.record_abi, exported.bool_abi));
		}
		foreach (var contract in generic_contracts) {
			contract.ordinal = (int) cleanup_contracts.length;
			cleanup_contracts.add (contract);
		}
		foreach (var application in program.method_applications) {
			var scope = functions.lookup (application.application_scope) as CoreGenericFunction;
			if (scope == null) {
				throw new CoreError.INVALID_CHECKED_MODEL ("symbolic generic method lost its exact enclosing generic scope");
			}
			((CoreMethod) functions.lookup (application)).application_scope = scope.identity;
		}
		var result = new CoreProgram (program.span, declarations, imports, exports, structures, cleanup_contracts, handle_declarations);
		foreach (var owner in classes) {
			if (owner.exception_root) {
				result.exception_bool_type = program.types.bool_type;
			}
		}
		foreach (var definition in program.enums) {
			result.enums.add (enum_definitions.lookup (definition.semantic_type));
		}
		foreach (var payload in text_literals) {
			result.text_literals.add (payload);
		}
		foreach (var object_class in classes) {
			result.classes.add (object_class);
		}
		foreach (var application in class_applications) {
			result.class_applications.add (application);
		}
		foreach (var application in method_applications) {
			result.method_applications.add (application);
		}
		foreach (var definition in generic_definitions) {
			result.generic_functions.add (definition);
		}
		foreach (var definition in generic_struct_definitions) {
			result.generic_structs.add (definition);
		}
		foreach (var definition in program.generic_classes) {
			result.generic_classes.add (definition);
		}
		foreach (var record in structures) {
			var contract = ((StructType) record.semantic_type).owning_application;
			if (contract == null) {
				continue;
			}
			foreach (var argument in contract.arguments.copy_values ()) {
				record.owning_arguments.add (build_type (argument));
			}
		}
		foreach (var owner in classes) {
			var key = owner.generic_instance;
			if (key == null) {
				continue;
			}
			for (int a = 0; a < key.arguments.length; a++) {
				result.class_type_arguments.add (new ClassTypeArgument ((ClassType) owner.semantic_type, a, build_type (key.arguments.at (a))));
			}
		}
		foreach (var signature in callable_types.get_values ()) {
			try {
				if (signature is FunctionValueType) {
					((FunctionValueType) signature).complete_records (callable_fields);
				} else {
					((ClosureHandleType) signature).complete_records (callable_fields);
				}
			} catch (StructLeafError error) {
				throw new CoreError.INVALID_CHECKED_MODEL (error.message);
			}
		}
		CoreExactClassAuthority.verify (result);
		return result;
	}

	private bool dead_return_block;

	private CoreBlock build_block(CheckedBlockStatement block, CoreFunction function) throws CoreError {
		var result = new CoreBlock (block.span, new GenericArray<CoreStatement> ());
		result.text_extent = text_extent (block.region);
		scopes.insert (block.region, result);
		for (int i = 0; i < block.statements.length; i++) {
			append_statement (block.statements[i], function, result);
		}
		return result;
	}

	private void append_statement(CheckedStatement statement, CoreFunction function, CoreBlock scope) throws CoreError {
		if (statement is CheckedConstantDeclaration) {
			return;
		}
		var statements = scope.statements;
		if (statement is CheckedSlotsInitialize) {
			statements.add (new CoreSlotsInitialize (statement.span, (CoreIndirectFieldPlace) build_place (((CheckedSlotsInitialize) statement).store, function)));
			return;
		}
		if (statement is CheckedSlotsReplace) {
			var replace = (CheckedSlotsReplace) statement;
			statements.add (new CoreSlotsReplace (replace.span, (CoreIndirectFieldPlace) build_place (replace.store, function), build_value (replace.index, function), owned_locals.lookup (replace.incoming.source)));
			return;
		}
		if (statement is CheckedSlotsRecordTransfer) {
			var transfer = (CheckedSlotsRecordTransfer) statement;
			statements.add (new CoreSlotsRecordTransfer (statement.span, (CoreIndirectFieldPlace) build_place (transfer.store, function), transfer.index == null ? null : build_value (transfer.index, function), build_struct_producer (transfer.value, function)));
			return;
		}
		if (statement is CheckedSlotsAppend) {
			var append = (CheckedSlotsAppend) statement;
			statements.add (new CoreSlotsAppend (statement.span, (CoreIndirectFieldPlace) build_place (append.store, function), owned_locals.lookup (append.incoming.source)));
			return;
		}
		if (statement is CheckedOwnedFieldTransfer) {
			var transfer = (CheckedOwnedFieldTransfer) statement;
			var move = transfer.incoming as CheckedOwnershipMove;
			statements.add (new CoreOwnedFieldTransfer (statement.span, (CoreIndirectFieldPlace) build_place (transfer.destination, function), ownership_contract (transfer.field.semantic_type, transfer.field.owned_cleanup, transfer.field.owns_child), move == null ? null : owned_locals.lookup (move.source), move == null ? build_value (transfer.incoming, function) : null, transfer.initializes));
			return;
		}
		if (statement is CheckedFieldInitialize) {
			var initialization = (CheckedFieldInitialize) statement;
			statements.add (new CoreFieldInitialize (statement.span, (CoreIndirectFieldPlace) build_place (initialization.target, function), build_value (initialization.value, function)));
			return;
		}
		var construction = statement as CheckedObjectConstruction;
		if (construction != null) {
			var source = construction.storage;
			var object_class = structs.lookup (source.semantic_type) as CoreClass;
			if (object_class == null || source.ordinal != function.object_storage.length || source.lexical_region != construction.local.lexical_region || source.semantic_type != construction.local.semantic_type || source.lexical_region.ordinal < 0) {
				throw new CoreError.INVALID_CHECKED_MODEL ("object construction requires exact class, storage, reference and lexical region");
			}
			var storage = new CoreObjectStorage (source.span, object_class, source.ordinal, source.lexical_region.ordinal, scope, source.fallible);
			storage.heap_allocated = source.heap_allocated;
			storage.cleanup_rank = source.cleanup_rank;
			storage.transferable = construction.local.object_owner != null;
			CoreOwnedLocal? acquisition = null;
			if (storage.transferable) {
				if (construction.local.object_storage != source || construction.local.object_owner != source.object_class) {
					throw new CoreError.INVALID_CHECKED_MODEL ("owned local requires exact fresh ObjectStorage responsibility");
				}
				acquisition = new CoreOwnedLocal (statement.span, find_local (construction.local, function), ownership_contract (source.semantic_type, null, source.heap_allocated), scope, storage);
				function.owned_locals.add (acquisition);
				owned_locals.insert (construction.local, acquisition);
			}
			function.object_storage.add (storage);
			var initializers = new GenericArray<CoreObjectFieldInitializer> ();
			foreach (var initializer in construction.initializers) {
				initializers.add (new CoreObjectFieldInitializer (initializer.span, fields.lookup ((StructFieldSymbol) initializer.field), build_value (initializer.expression, function)));
			}
			var invocation = construction as CheckedConstructorObjectInitialization;
			if (invocation != null) {
				var arguments = new GenericArray<CoreValue> ();
				foreach (var argument in invocation.arguments) {
					arguments.add (build_value (argument, function));
				}
				var result = new CoreConstructorObjectInitialization (statement.span, storage, find_local (construction.local, function), (CoreConstructor) functions.lookup (invocation.constructor), arguments, invocation.allocation_context == null ? null : build_value (invocation.allocation_context, function));
				result.acquisition = acquisition;
				statements.add (result);
				return;
			}
			var result = new CoreObjectConstruction (statement.span, storage, find_local (construction.local, function), initializers);
			result.acquisition = acquisition;
			statements.add (result);
			return;
		}
		var declaration = statement as CheckedStructLocalDeclaration;
		if (declaration != null) {
			if (declaration.local.is_record_owner) {
				var place = find_local (declaration.local, function);
				var owner = new CoreOwnedLocal (declaration.span, place, ownership_contract (declaration.local.semantic_type, declaration.local.cleanup), scope);
				function.owned_locals.add (owner);
				owned_locals.insert (declaration.local, owner);
				build_initializers (place, declaration.initializers, statements, function, owner);
			} else {
				build_initializers (find_local (declaration.local, function), declaration.initializers, statements, function);
			}
			return;
		}
		if (statement is CheckedStructMove) {
			var move = (CheckedStructMove) statement;
			var source = owned_locals.lookup (move.source);
			var destination = new CoreOwnedLocal (statement.span, find_local (move.destination, function), source.cleanup, scope);
			function.owned_locals.add (destination);
			owned_locals.insert (move.destination, destination);
			foreach (var field in source.record_fields) {
				destination.record_fields.add (rebase_record_field (destination.place, field));
			}
			statements.add (new CoreStructMove (statement.span, source, destination));
			return;
		}
		if (statement is CheckedRecordTake) {
			var take = (CheckedRecordTake) statement;
			var field = (CoreFieldPlace) build_place (take.field, function);
			var destination = new CoreOwnedLocal (statement.span, find_local (take.destination, function), field.field.owned_cleanup, scope);
			function.owned_locals.add (destination);
			owned_locals.insert (take.destination, destination);
			statements.add (new CoreRecordTake (statement.span, owned_locals.lookup (take.source), field, destination));
			return;
		}
		if (statement is CheckedRecordReplace) {
			var replace = (CheckedRecordReplace) statement;
			var move = replace.incoming as CheckedOwnershipMove;
			statements.add (new CoreRecordReplace (statement.span, owned_locals.lookup (replace.owner), (CoreFieldPlace) build_place (replace.field, function), move == null ? null : owned_locals.lookup (move.source), move == null ? build_value (replace.incoming, function) : null));
			return;
		}
		if (statement is CheckedStructResultStore && ((CheckedStructResultStore) statement).producer.contract.mode == StructValueMode.MOVE_VALUE) {
			var store = (CheckedStructResultStore) statement;
			var local = store.destination as CheckedLocalPlace;
			if (local != null) {
				if (!store.initializes_destination || !local.local.is_record_owner) {
					throw new CoreError.INVALID_CHECKED_MODEL ("record MOVE_VALUE result requires a fresh owning local");
				}
				register_boundary_record (local.local, function, scope);
			} else {
				var field = store.destination as CheckedReceiverFieldPlace;
				var object_field = store.destination as CheckedObjectFieldPlace;
				if (field == null ? object_field == null || !object_field.field.owns_record : !field.field.owns_record) {
					throw new CoreError.INVALID_CHECKED_MODEL ("record field commit requires its exact owning Class field");
				}
			}
		}
		if (statement is CheckedThrow && ((CheckedThrow) statement).construction != null) {
			append_statement (((CheckedThrow) statement).construction, function, scope);
		}
		var lowered = build_statement (statement, function, scope);
		// Retain checked declarations and their exact storage inventories, but
		// a definitely dead arm cannot impose a result transport convention.
		if (!dead_return_block || !(statement is CheckedOwnershipReturn)) {
			statements.add (lowered);
		}
	}

	private void declare_projections(CorePlace aggregate, CoreFunction function) throws CoreError {
		var structure = structs.lookup (aggregate.semantic_type);
		if (!(structure is CoreStruct)) {
			throw new CoreError.INVALID_CHECKED_MODEL ("struct storage requires exact declared type");
		}
		var projected = new HashTable<CoreStructField, CoreFieldPlace> (direct_hash, direct_equal);
		projections.insert (aggregate, projected);
		foreach (var field in structure.fields) {
			var place = new CoreFieldPlace (aggregate.span, aggregate, field);
			function.field_places.add (place);
			projected.insert (field, place);
			if (field.semantic_type is StructType) {
				declare_projections (place, function);
			}
		}
	}

	private CoreFieldPlace project_field(CorePlace aggregate, CoreStructField? field, Astra.Source.SourceSpan span) throws CoreError {
		if (field == null || field.containing_struct == null || field.containing_struct.semantic_type != aggregate.semantic_type || field.ordinal < 0 || field.ordinal >= field.containing_struct.fields.length || field.containing_struct.fields[field.ordinal] != field) {
			throw new CoreError.INVALID_CHECKED_MODEL ("field projection requires exact StructType base and declared field identity");
		}
		var projected = projections.lookup (aggregate);
		if (projected != null) {
			var result = projected.lookup (field);
			if (result == null) {
				result = new CoreFieldPlace (span, aggregate, field);
				projected.insert (field, result);
			}
			return result;
		}
		projected = new HashTable<CoreStructField, CoreFieldPlace> (direct_hash, direct_equal);
		projections.insert (aggregate, projected);
		var result = new CoreFieldPlace (span, aggregate, field);
		projected.insert (field, result);
		return result;
	}

	private CoreGenericStructFieldPlace project_generic_field(CorePlace aggregate, CoreGenericStructField? field, Astra.Source.SourceSpan span) throws CoreError {
		var application = aggregate.semantic_type as CoreGenericStructApplicationType;
		if (application == null || field == null || field.definition != application.definition || field.ordinal < 0 || field.ordinal >= application.definition.fields.length || application.definition.fields[field.ordinal] != field) {
			throw new CoreError.INVALID_CHECKED_MODEL ("generic projection requires its exact application and field origin");
		}
		var projected = generic_projections.lookup (aggregate);
		if (projected == null) {
			projected = new HashTable<CoreGenericStructField, CoreGenericStructFieldPlace> (direct_hash, direct_equal);
			generic_projections.insert (aggregate, projected);
		}
		var result = projected.lookup (field);
		if (result == null) {
			result = new CoreGenericStructFieldPlace (span, aggregate, field);
			projected.insert (field, result);
		}
		return result;
	}

	private CoreFieldPlace rebase_record_field(CoreLocalPlace destination, CoreFieldPlace source) throws CoreError {
		CorePlace aggregate = (source.aggregate is CoreFieldPlace) ? (CorePlace) rebase_record_field (destination, (CoreFieldPlace) source.aggregate) : destination;
		return project_field (aggregate, source.field, source.span);
	}

	private void register_boundary_record(LocalSymbol local, CoreFunction function, CoreBlock scope) throws CoreError {
		var place = find_local (local, function);
		if (owned_locals.contains (local)) {
			throw new CoreError.INVALID_CHECKED_MODEL ("record boundary local cannot acquire twice");
		}
		var owner = new CoreOwnedLocal (local.span, place, ownership_contract (local.semantic_type, null), scope);
		foreach (var projection in function.field_places) {
			if (projection.root_local () == place && projection.field.owned_cleanup != null) {
				owner.record_fields.add (projection);
			}
		}
		function.owned_locals.add (owner);
		owned_locals.insert (local, owner);
	}

	private void build_initializers(CorePlace aggregate, GenericArray<CheckedFieldInitializer> initializers, GenericArray<CoreStatement> statements, CoreFunction function, CoreOwnedLocal? owner = null) throws CoreError {
		foreach (var initializer in initializers) {
			CoreStorageFieldPlace target = (initializer.field is GenericStructFieldSymbol) ? (CoreStorageFieldPlace) project_generic_field (aggregate, generic_fields.lookup ((GenericStructFieldSymbol) initializer.field), initializer.span) : project_field (aggregate, fields.lookup ((StructFieldSymbol) initializer.field), initializer.span);
			if (initializer.producer != null) {
				if (initializer.initializer != null || initializer.expression != null || build_type (initializer.producer.semantic_type) != target.semantic_type) {
					throw new CoreError.INVALID_CHECKED_MODEL ("field producer requires one exact bounded initializer");
				}
				var producer = build_struct_producer (initializer.producer, function);
				if (producer.contract.mode == StructValueMode.MOVE_VALUE) {
					if (owner == null) {
						throw new CoreError.INVALID_CHECKED_MODEL ("owning subobject initialization lost its lexical record owner");
					}
					foreach (var field in function.field_places) {
						CorePlace ancestor = field;
						while (ancestor is CoreStorageFieldPlace && ancestor != target) {
							ancestor = ((CoreStorageFieldPlace) ancestor).aggregate;
						}
						if (ancestor == target && field.field.owned_cleanup != null) {
							owner.record_fields.add (field);
						}
					}
				}
				statements.add (new CoreStructInitialize.from_producer (initializer.span, target, producer, producer.contract.mode == StructValueMode.MOVE_VALUE ? owner : null));
				continue;
			}
			if (initializer.initializer != null) {
				if (build_type (initializer.initializer.semantic_type) != target.semantic_type) {
					throw new CoreError.INVALID_CHECKED_MODEL ("nested initializer requires exact target StructType");
				}
				var children = new GenericArray<CoreStatement> ();
				build_initializers (target, initializer.initializer.fields, children, function, owner);
				statements.add (new CoreStructInitialize (initializer.span, target, children));
			} else if (initializer.field.is_owned_field && owner != null) {
				var field = target as CoreFieldPlace;
				if (field == null) {
					throw new CoreError.INVALID_CHECKED_MODEL ("owning record initializer requires an exact field path");
				}
				owner.record_fields.add (field);
				var move = initializer.expression as CheckedOwnershipMove;
				statements.add (new CoreStructAcquire (initializer.span, owner, field, move == null ? null : owned_locals.lookup (move.source), move == null ? build_value (initializer.expression, function) : null));
			} else {
				statements.add (new CoreInitialize (initializer.span, target, build_value (initializer.expression, function)));
			}
		}
	}

	private CoreFieldPlace find_field(LocalSymbol symbol, StructFieldSymbol field, CoreFunction function) throws CoreError {
		var local = find_local (symbol, function);
		var descriptor = fields.lookup (field);
		var projected = projections.lookup (local);
		var place = descriptor == null || projected == null ? null : projected.lookup (descriptor);
		if (place == null) {
			throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: field reference has no exact projection mapping");
		}
		return place;
	}

	private CoreStatement build_statement(CheckedStatement statement, CoreFunction function, CoreBlock scope) throws CoreError {
		if (statement is CheckedActorSend) {
			var operation = (CheckedActorSend) statement;
			var message = operation.message == null ? null : owned_locals.lookup (operation.message);
			if (operation.message != null && message == null) {
				throw new CoreError.INVALID_CHECKED_MODEL ("Actor message lost exact owner mapping");
			}
			return new CoreActorSend (statement.span, operation.action, build_value (operation.sender, function), operation.scalar == null ? null : build_value (operation.scalar, function), message, operation.error_type);
		}
		if (statement is CheckedValueStatement) {
			var value = ((CheckedValueStatement) statement).value;
			if (!(value is CheckedFunctionValueCall || value is CheckedClosureCall) || value.semantic_type.kind != TypeKind.VOID && !FunctionValueType.scalar (value.semantic_type)) {
				throw new CoreError.INVALID_CHECKED_MODEL ("indirect call statement requires an exact scalar or void result");
			}
			return new CoreValueStatement (statement.span, build_value (value, function));
		}
		if (statement is CheckedAsyncOperationStatement) {
			return new CoreAsyncOperationStatement (statement.span, (CoreAsyncOperation) build_value (((CheckedAsyncOperationStatement) statement).operation, function));
		}
		if (statement is CheckedTaskAwaitStatement) {
			return new CoreTaskAwaitStatement (statement.span, (CoreTaskAwait) build_value (((CheckedTaskAwaitStatement) statement).operation, function));
		}
		if (statement is CheckedAsyncDelay) {
			var delay = (CheckedAsyncDelay) statement;
			if (delay.body != function.async_body) {
				throw new CoreError.INVALID_CHECKED_MODEL ("suspension lost exact checked body identity");
			}
			return new CoreAsyncDelay (statement.span, delay.body, build_value (delay.ticks, function), delay.payload);
		}
		if (statement is CheckedVectorMemoryStatement) {
			return new CoreVectorMemoryStatement (statement.span, (CoreVectorMemoryValue) build_value (((CheckedVectorMemoryStatement) statement).operation, function));
		}
		if (statement is CheckedThrow) {
			var thrown = (CheckedThrow) statement;
			return new CoreThrow (function.utf8_factory ? function.span : statement.span, locals.lookup (thrown.owner), thrown.rethrows ? null : owned_locals.lookup (thrown.owner), ownership_contract (thrown.root_type, null, true));
		}
		if (statement is CheckedTry) {
			var guarded = (CheckedTry) statement;
			var body = build_block (guarded.body, function);
			var catches = new GenericArray<CoreCatch> ();
			foreach (var caught in guarded.catches) {
				catches.add (new CoreCatch (locals.lookup (caught.binding), build_block (caught.body, function)));
			}
			return new CoreTry (statement.span, body, catches, ownership_contract (guarded.root_type, null, true));
		}
		if (statement is CheckedEnumReturn) {
			return new CoreEnumReturn (statement.span, build_enum_producer (((CheckedEnumReturn) statement).producer, function));
		}
		if (statement is CheckedEnumStore) {
			var store = (CheckedEnumStore) statement;
			return new CoreEnumStore (statement.span, locals.lookup (store.destination), build_enum_producer (store.producer, function), store.initializes_destination);
		}
		if (statement is CheckedEnumMatch) {
			var match = (CheckedEnumMatch) statement;
			var producer = build_enum_producer (match.scrutinee, function);
			var arms = new GenericArray<CoreEnumArm> ();
			foreach (var arm in match.arms) {
				if (!arm.matches_bindings ()) {
					throw new CoreError.INVALID_CHECKED_MODEL ("checked match lost intended field/binding correspondence");
				}
				var variant = arm.variant == null ? null : producer.definition.variant (arm.variant.identity.ordinal);
				var bindings = new GenericArray<CoreEnumBinding> ();
				var body = new CoreBlock (arm.body.span, new GenericArray<CoreStatement> ());
				scopes.insert (arm.body.region, body);
				foreach (var binding in arm.bindings) {
					CoreOwnedLocal? acquisition = null;
					if (binding.destination.is_record_owner) {
						register_boundary_record (binding.destination, function, body);
						acquisition = owned_locals.lookup (binding.destination);
					} else if (binding.destination.is_owned) {
						acquisition = new CoreOwnedLocal (binding.span, locals.lookup (binding.destination), ownership_contract (binding.field.semantic_type, binding.field.owned_cleanup, binding.field.owns_child), body);
						owned_locals.insert (binding.destination, acquisition);
						function.owned_locals.add (acquisition);
					}
					bindings.add (new CoreEnumBinding (binding.span, variant.field (binding.field.identity.ordinal), locals.lookup (binding.destination), new EnumBindingIdentity (variant.field (binding.field.identity.ordinal).identity, binding.destination.ordinal, producer.instance), acquisition));
				}
				foreach (var member in arm.body.statements) {
					append_statement (member, function, body);
				}
				arms.add (new CoreEnumArm (arm.span, variant, bindings, body));
			}
			return new CoreEnumMatch (statement.span, producer, arms);
		}
		if (statement is CheckedStructReturn) {
			return new CoreStructReturn (statement.span, build_struct_producer (((CheckedStructReturn) statement).producer, function));
		}
		if (statement is CheckedStructResultStore) {
			var store = (CheckedStructResultStore) statement;
			return new CoreStructResultStore (statement.span, build_place (store.destination, function), build_struct_producer (store.producer, function), store.initializes_destination);
		}
		var copy = statement as CheckedStructCopy;
		if (copy != null) {
			if (copy.copyability != Copyability.COPYABLE || copy.semantic_type != copy.destination.semantic_type || copy.semantic_type != copy.source.semantic_type) {
				throw new CoreError.INVALID_CHECKED_MODEL ("struct copy requires exact copyable source and destination Places");
			}
			return new CoreStructCopy (statement.span, build_place (copy.destination, function), build_place (copy.source, function), build_type (copy.semantic_type), copy.initializes_destination);
		}
		if (statement is CheckedWithScope) {
			var scoped = (CheckedWithScope) statement;
			if (scoped.contract == null || scoped.contract.source != scoped.source) {
				throw new CoreError.INVALID_CHECKED_MODEL ("with scope lost receiver identity");
			}
			var contract = new CoreWithContract (scoped.span, (CoreLocalPlace) find_local (scoped.source, function), scoped.source.object_owner.receiver_type);
			with_contracts.insert (scoped.contract, contract);
			return new CoreWithScope (scoped.span, contract, build_block (scoped, function));
		}
		if (statement is CheckedBlockStatement) {
			return new CoreScope (statement.span, build_block ((CheckedBlockStatement) statement, function));
		}
		var owned_return = statement as CheckedOwnershipReturn;
		if (owned_return != null) {
			var source = owned_return.transfer == null ? null : owned_locals.lookup (owned_return.transfer.source);
			if ((owned_return.transfer != null && source == null) || ownership_contract (owned_return.semantic_type, owned_return.cleanup, function.heap_result) != function.owned_cleanup) {
				throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: owned return requires exact source and result contract");
			}
			return new CoreOwnershipReturn (statement.span, build_type (owned_return.semantic_type), function.owned_cleanup, source, owned_return.producer == null ? null : build_value (owned_return.producer, function), owned_return.provenance);
		}
		if (statement is CheckedOwnedBufferExchange) {
			var exchange = (CheckedOwnedBufferExchange) statement;
			return new CoreOwnedBufferExchange (statement.span, build_buffer_owner_slot (exchange.left, function), build_buffer_owner_slot (exchange.right, function));
		}
		if (statement is CheckedOwnedBufferReplace) {
			var replacement = (CheckedOwnedBufferReplace) statement;
			var owner = owned_locals.lookup (replacement.owner);
			if (replacement.incoming is CheckedOwnershipMove) {
				return new CoreOwnershipRearm.from_owner (statement.span, owner, owned_locals.lookup (((CheckedOwnershipMove) replacement.incoming).source), owner.cleanup);
			}
			return new CoreOwnershipRearm (statement.span, owner, build_value (replacement.incoming, function), owner.cleanup);
		}
		var rearm = statement as CheckedOwnershipRearmAssignment;
		if (rearm != null) {
			var owner = owned_locals.lookup (rearm.owner);
			var cleanup = cleanups.lookup (rearm.cleanup);
			if (rearm.incoming is CheckedOwnershipMove) {
				var source = owned_locals.lookup (((CheckedOwnershipMove) rearm.incoming).source);
				if (owner == null || source == null || cleanup == null) {
					throw new CoreError.INVALID_CHECKED_MODEL ("owner replacement requires exact source/destination mappings");
				}
				return new CoreOwnershipRearm.from_owner (rearm.span, owner, source, cleanup);
			}
			var producer = build_value (rearm.incoming, function);
			if (owner == null || cleanup == null || producer == null || owner.cleanup != cleanup || owner.place != find_local (rearm.owner, function)) {
				throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: rearm requires exact owner, producer and cleanup mapping");
			}
			return new CoreOwnershipRearm (rearm.span, owner, producer, cleanup);
		}
		var release = statement as CheckedOwnershipRelease;
		if (release != null) {
			var owner = owned_locals.lookup (release.owner);
			var cleanup = ownership_contract (release.owner.semantic_type, release.cleanup, release.owner.heap_object);
			if (owner == null || cleanup == null || owner.cleanup != cleanup || owner.place != find_local (release.owner, function)) {
				throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: release requires exact owner and cleanup mapping");
			}
			return new CoreOwnershipRelease (release.span, owner, cleanup);
		}
		if (statement is CheckedBreak || statement is CheckedContinue) {
			var checked_target = (statement is CheckedBreak) ? ((CheckedBreak) statement).target : ((CheckedContinue) statement).target;
			var target = checked_target == null ? null : loop_targets.lookup (checked_target);
			if (target == null || loop_owners.lookup (checked_target) != function) {
				throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: loop-control target is expired or has no mapping in the containing function");
			}
			return (statement is CheckedBreak) ? (CoreStatement) new CoreBreak (statement.span, target) : new CoreContinue (statement.span, target);
		}
		var loop = statement as CheckedWhile;
		if (loop != null) {
			if (loop.has_sequence != (loop.sequence != null) || (loop.sequence != null && loop.iteration != null)) {
				throw new CoreError.INVALID_CHECKED_MODEL ("foreach lost its unique sequence authority");
			}
			if (loop.has_iteration != (loop.iteration != null)) {
				throw new CoreError.INVALID_CHECKED_MODEL ("foreach lost its iteration authority");
			}
			if (loop.has_step != (loop.step != null)) {
				throw new CoreError.INVALID_CHECKED_MODEL ("loop lost its required step block");
			}
			if (loop_targets.contains (loop.target)) {
				throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: repeated loop-target identity");
			}
			var target = new CoreLoopTarget (loop.target.span, loop.target.ordinal);
			loop_targets.insert (loop.target, target);
			loop_owners.insert (loop.target, function);
			CoreIterationContract? iteration = null;
			if (loop.iteration != null) {
				if (loop.iteration.target != loop.target) {
					throw new CoreError.INVALID_CHECKED_MODEL ("foreach target identity mismatch");
				}
				var slots = loop.iteration.store.semantic_type as OwnerSlotsType;
				var binding = loop.iteration.binding;
				if (slots == null || (binding != null) != (slots.element is StructType)) {
					throw new CoreError.INVALID_CHECKED_MODEL ("foreach lost its copy-versus-loan binding");
				}
				if (binding != null) {
					var copied = loop.body.statements.length == 0 ? null : loop.body.statements[0] as CheckedStructResultStore;
					var destination = copied == null ? null : copied.destination as CheckedLocalPlace;
					var read = copied == null ? null : copied.producer as CheckedSlotsRecordRead;
					var position = read == null ? null : read.index as CheckedLocalReferenceExpression;
					if (binding.semantic_type != slots.element || destination == null || destination.local != binding || !copied.initializes_destination || read == null || read.remove || read.store != loop.iteration.store || position == null || position.local != loop.iteration.index) {
						throw new CoreError.INVALID_CHECKED_MODEL ("foreach lost its complete exact per-iteration record snapshot");
					}
				}

				iteration = new CoreIterationContract (loop.iteration.span, target, (CoreIndirectFieldPlace) build_place (loop.iteration.store, function), (CoreLocalPlace) find_local (loop.iteration.index, function), loop.iteration.binding == null ? null : (CoreLocalPlace) find_local (loop.iteration.binding, function));
				iterations.insert (loop.iteration, iteration);
			}
			var condition = build_value (loop.condition, function);
			var constant = condition as CoreBooleanValue;
			bool saved_dead = dead_return_block;
			dead_return_block = saved_dead || constant != null && constant.literal == BooleanLiteral.FALSE;
			var body = build_block (loop.body, function);
			var step = loop.step == null ? null : build_block (loop.step, function);
			dead_return_block = saved_dead;
			CoreSequenceIteration? sequence = null;
			if (loop.sequence != null) {
				if (loop.sequence.target != loop.target) {
					throw new CoreError.INVALID_CHECKED_MODEL ("foreach sequence target identity mismatch");
				}
				var contract = loop.sequence;
				if (contract.is_iterator) {
					if (contract.index != null || contract.advance == null || contract.current == null) {
						throw new CoreError.INVALID_CHECKED_MODEL ("foreach iterator lost its exact method identities");
					}
					var advance = functions.lookup (contract.advance) as CoreMethod;
					var current = functions.lookup (contract.current) as CoreMethod;
					if (advance == null || current == null) {
						throw new CoreError.INVALID_CHECKED_MODEL ("foreach iterator methods belong to another checked program");
					}
					sequence = new CoreSequenceIteration.iterator (contract.span, target, build_value (contract.source, function), find_local (contract.binding, function),
						advance, current);
				} else {
					if (contract.index == null) {
						throw new CoreError.INVALID_CHECKED_MODEL ("foreach indexed sequence lost its index");
					}
					sequence = new CoreSequenceIteration (contract.span, target, build_value (contract.source, function), find_local (contract.index, function), find_local (contract.binding, function));
				}
			}
			return new CoreWhile (loop.span, target, condition, body, step, iteration, sequence);
		}
		if (statement is CheckedBaseLifecycleCall) {
			var base_call = (CheckedBaseLifecycleCall) statement;
			return new CoreBaseLifecycleCall (statement.span, (CoreLifecycle) functions.lookup ((FunctionSymbol) base_call.target), build_arguments (base_call.arguments, base_call.target, function), build_value (base_call.receiver, function));
		}
		var call = statement as CheckedCallStatement;
		if (call != null) {
			return build_call_statement (call, function);
		}
		var conditional = statement as CheckedIf;
		if (conditional != null) {
			var condition = build_value (conditional.condition, function);
			var constant = condition as CoreBooleanValue;
			bool saved_dead = dead_return_block;
			dead_return_block = saved_dead || constant != null && constant.literal == BooleanLiteral.FALSE;
			var then_block = build_block (conditional.then_body, function);
			dead_return_block = saved_dead || constant != null && constant.literal == BooleanLiteral.TRUE;
			var else_block = conditional.else_body == null ? null : build_block (conditional.else_body, function);
			dead_return_block = saved_dead;
			return new CoreIf (conditional.span, condition, then_block, else_block);
		}
		var array = statement as CheckedArrayLocalDeclaration;
		if (array != null) {
			if (array.records.length != 0) {
				var storage = find_local (array.local, function);
				var records = new GenericArray<CoreArrayRecordEntry> ();
				for (int i = 0; i < array.records.length; i++) {
					var entry = array.records[i];
					var index = new CoreIntegerValue.typed (entry.span, buffer_length_type, AstraIntegerValue.from_int64 (buffer_length_type, i));
					var target = new CoreArrayElementPlace (entry.span, storage, (ArrayType) storage.semantic_type, index, new DataPointerProvenance (DataPointerOrigin.LOCAL, storage.ordinal, array.local.lexical_region.ordinal));
					var initializers = new GenericArray<CoreStatement> ();
					if (entry.initializer != null) {
						build_initializers (target, entry.initializer.fields, initializers, function);
					}
					records.add (new CoreArrayRecordEntry (entry.span, target, initializers, entry.producer == null ? null : build_struct_producer (entry.producer, function)));
				}
				return new CoreArrayInitialize.record_entries (array.span, storage, records);
			}
			var elements = new GenericArray<CoreValue> ();
			foreach (var element in array.elements) {
				elements.add (build_value (element, function));
			}
			return new CoreArrayInitialize (array.span, find_local (array.local, function), elements);
		}
		var declaration = statement as CheckedLocalDeclaration;
		if (declaration != null) {
			var scoped = declaration.initializer as CheckedScopedAllocator;
			if (scoped != null && (declaration.local.scoped_backing != scoped.loan || !scoped.loan.valid () || scoped.loan.context_ordinal != declaration.local.ordinal || scoped.loan.backing_ordinal != scoped.backing.ordinal || scoped.loan.region_ordinal != declaration.local.lexical_region.ordinal || !scoped.backing.is_buffer_owner || !scoped.backing.lexical_region.outlives (declaration.local.lexical_region))) {
				throw new CoreError.INVALID_CHECKED_MODEL ("scoped context binding lost exact backing owner and lexical loan");
			}
			var target = find_local (declaration.local, function);
			CoreOwnedLocal? acquisition = null;
			var owned_declaration = declaration as CheckedOwnedLocalDeclaration;
			if (owned_declaration != null) {
				if (declaration.local.semantic_type is TypeParameterType) {
					var move = declaration.initializer as CheckedOwnershipMove;
					var source = declaration.local.generic_owner_source;
					var invocation = declaration.initializer as CheckedInvocation;
					bool incoming_move = source != null && move != null && move.source == source && source.is_generic_owner
					    && source.semantic_type == declaration.local.semantic_type && !source.heap_object && source.object_storage == null;
					bool producer = source == null && move == null && invocation != null && invocation.result_producer () != null
					    && declaration.initializer.semantic_type == declaration.local.semantic_type;
					if (!declaration.local.is_generic_owner || (!incoming_move && !producer) || declaration.local.incoming_parameter != null
					    || declaration.local.heap_object || declaration.local.object_storage != null) {
						throw new CoreError.INVALID_CHECKED_MODEL ("generic local requires an exact allocation-neutral move or owned producer");
					}
				}
				var cleanup = ownership_contract (declaration.local.semantic_type, owned_declaration.cleanup, declaration.local.heap_object);
				if (cleanup == null || scopes.lookup (owned_declaration.lexical_region) != scope) {
					throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: owner requires exact cleanup and lexical region mapping");
				}
				acquisition = new CoreOwnedLocal (declaration.span, target, cleanup, scope);
				function.owned_locals.add (acquisition);
				owned_locals.insert (declaration.local, acquisition);
				var move = declaration.initializer as CheckedOwnershipMove;
				if (move != null) {
					var source = owned_locals.lookup (move.source);
					if (source == null || source.cleanup != cleanup || source.place != find_local (move.source, function) || source == acquisition) {
						throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: transfer requires exact distinct source owner and cleanup mapping");
					}
					return new CoreOwnershipTransfer (move.span, source, acquisition, cleanup);
				}
			}
			return new CoreInitialize (declaration.span, target, build_value (declaration.initializer, function), acquisition);
		}
		var store = statement as CheckedStore;
		if (store != null) {
			if (!VolatileAccessContract.valid (store.volatile_access, store.volatile_enabled, store.target.semantic_type)) {
				throw new CoreError.INVALID_CHECKED_MODEL ("volatile store lost its exact checked access contract");
			}
			var target = build_place (store.target, function);
			return new CoreStore (store.span, target, build_value (store.value, function), store.volatile_access == null ? null : store.volatile_access.copy ());
		}
		var indirect = statement as CheckedIndirectFieldAssignment;
		if (indirect != null) {
			var value = build_value (indirect.expression, function);
			var target = build_indirect_place (indirect.span, indirect.pointer, indirect.field, function);
			return new CoreStore (statement.span, target, value);
		}
		var field_assignment = statement as CheckedFieldAssignment;
		if (field_assignment != null) {
			var target = find_field (field_assignment.local, field_assignment.field, function);
			return new CoreStore (statement.span, target, build_value (field_assignment.expression, function));
		}
		var assignment = statement as CheckedAssignment;
		if (assignment != null) {
			var target = find_local (assignment.target, function);
			return new CoreStore (assignment.span, target, build_value (assignment.expression, function));
		}
		if (statement is CheckedForeignSignalReturn) {
			return new CoreForeignSignalReturn (statement.span, ((CheckedForeignSignalReturn) statement).binding);
		}
		if (statement is CheckedForeignReturn) {
			var imported = (CheckedForeignReturn) statement;
			var consumed = new GenericArray<CoreOwnedLocal> ();
			foreach (var owner in function.owned_locals) {
				if (owner.place.incoming_parameter != null && owner.place.incoming_parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER) {
					consumed.add (owner);
				}
			}
			return new CoreForeignReturn (statement.span, imported.binding, functions.lookup (imported.factory), consumed);
		}
		var returned = statement as CheckedReturnStatement;
		if (returned != null) {
			return new CoreReturn (returned.span, returned.expression == null ? null : build_value (returned.expression, function));
		}
		throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: unsupported checked statement");
	}

	private CoreLocalPlace find_local(LocalSymbol symbol, CoreFunction function) throws CoreError {
		var local = locals.lookup (symbol);
		if (local == null || local.ordinal < 0 || local.ordinal >= function.locals.length || function.locals[local.ordinal] != local) {
			throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: local reference has no declaration in the containing function");
		}
		return local;
	}

	private CoreCFunction find_c_function(DirectCallableSymbol symbol) throws CoreError {
		var target = symbol.domain != CallableDomain.C ? null : c_functions.lookup ((CFunctionSymbol) symbol);
		if (target == null) {
			throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: C call target is not owned by the checked program");
		}
		return target;
	}

	private CoreFunction find_function(DirectCallableSymbol? symbol) throws CoreError {
		var target = !(symbol is FunctionSymbol) ? null : functions.lookup ((FunctionSymbol) symbol);
		if (target == null) {
			throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: call target is not owned by the checked program");
		}
		return target;
	}

	private GenericArray<SemanticType> copy_type_arguments(GenericArray<SemanticType> arguments) throws CoreError {
		var result = new GenericArray<SemanticType> ();
		foreach (var type in arguments) {
			result.add (build_type (type));
		}
		return result;
	}

	private GenericArray<CoreValue> build_arguments(GenericArray<CheckedExpression> expressions, DirectCallableSymbol target, CoreFunction function, TypeSubstitution? substitution = null) throws CoreError {
		if (expressions.length != target.parameters.length) {
			throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: call argument count does not match target parameters");
		}
		var arguments = new GenericArray<CoreValue> ();
		for (int i = 0; i < expressions.length; i++) {
			if ((substitution == null ? expressions[i].semantic_type != target.parameters[i].semantic_type : !substitution.matches (target.parameters[i].semantic_type, expressions[i].semantic_type))) {
				throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: call argument type does not match target parameter");
			}
			arguments.add (build_value (expressions[i], function));
		}
		return arguments;
	}

	private void bind_derived_native_destructor(CoreClass owner, CheckedProgram program) throws CoreError {
		if (!owner.name_span.file.native_interface) {
			return;
		}
		var identity = program.classes[owner.ordinal].native_destructor_declaration;
		if (identity == null || owner.destructor == null) {
			throw new CoreError.INVALID_CHECKED_MODEL ("derived native destructor lost its exact imported declaration");
		}
		int count = (int) owner.destructor.parameters.length;
		owner.destructor.bind_native_declaration (new NativeDeclarationSignature (identity, owner.destructor.return_type,
			ResultOwnershipContract.UNMANAGED, false, false, owner.semantic_type, null,
			new GenericArray<SemanticType> (), new GenericArray<PointerParameterContract> (),
			new bool[count], new bool[count], new int[count]));
	}

	private void ensure_base_destructor(CoreClass owner, CheckedProgram program, GenericArray<CoreFunction> declarations) throws CoreError {
		if (owner.parent_class == null) {
			return;
		}
		ensure_base_destructor (owner.parent_class, program, declarations);
		if (owner.destructor != null || owner.parent_class.destructor == null) {
			return;
		}
		var body = new CoreBlock (owner.span, new GenericArray<CoreStatement> ());
		owner.destructor = new CoreDestructor (owner.span, owner.name_span, owner, new CoreReceiver (owner.span, (ReceiverType) build_type (program.classes[owner.ordinal].receiver_type)), (int) (owner.fields.length + owner.methods.length + owner.properties.length + owner.lifecycle_count), owner.parent_class.destructor.return_type, new GenericArray<CoreParameter> (), new GenericArray<CoreLocalPlace> (), body);
		bind_derived_native_destructor (owner, program);
		declarations.add (owner.destructor);
	}

	private CorePlace build_place(CheckedPlace place, CoreFunction function) throws CoreError {
		var generic = place as CheckedGenericStructFieldPlace;
		if (generic != null) {
			return project_generic_field (build_place (generic.aggregate, function), generic_fields.lookup (generic.field), place.span);
		}
		var local = place as CheckedLocalPlace;
		if (local != null) {
			return find_local (local.local, function);
		}
		var projection = place as CheckedFieldPlace;
		if (projection != null) {
			return project_field (build_place (projection.aggregate, function), fields.lookup (projection.field), place.span);
		}
		var object_field = place as CheckedObjectFieldPlace;
		if (object_field != null) {
			return build_indirect_place (place.span, object_field.reference, object_field.field, function);
		}
		var receiver_field = place as CheckedReceiverFieldPlace;
		if (receiver_field != null) {
			return build_indirect_place (place.span, receiver_field.receiver, receiver_field.field, function);
		}
		var slice = place as CheckedSliceElementPlace;
		if (slice != null) {
			var view = build_value (slice.slice, function);
			var index = build_value (slice.index, function);
			return new CoreSliceElementPlace (place.span, view, (SliceType) build_type (slice.slice_type), index, slice.provenance.snapshot (slice.slice_type.deep_borrow));
		}
		var array = place as CheckedArrayElementPlace;
		if (array != null) {
			return new CoreArrayElementPlace (place.span, find_local (array.local, function), (ArrayType) build_type (array.array_type), build_value (array.index, function), array.provenance);
		}
		return build_dereference_place ((CheckedDereferencePlace) place, function);
	}

	private CoreBufferOwnerSlot build_buffer_owner_slot(CheckedBufferOwnerSlot slot, CoreFunction function) throws CoreError {
		var place = build_place (slot.place, function);
		var owner = slot.owner == null ? null : owned_locals.lookup (slot.owner);
		var field = place as CoreIndirectFieldPlace;
		if ((slot.owner == null) == (slot.field == null) || (slot.owner != null && (owner == null || owner.place != place)) || (slot.field != null && (field == null || fields.lookup (slot.field) != field.field))) {
			throw new CoreError.INVALID_CHECKED_MODEL ("buffer exchange requires exact owning slot provenance");
		}
		return new CoreBufferOwnerSlot (slot.span, place, owner, owner == null ? field.field.owned_cleanup : owner.cleanup);
	}

	private CoreDereferencePlace build_dereference_place(CheckedDereferencePlace place, CoreFunction function) throws CoreError {
		return new CoreDereferencePlace (place.span, build_value (place.pointer, function), build_type (place.semantic_type), place.provenance.snapshot ());
	}

	private CoreIndirectFieldPlace build_indirect_place(Astra.Source.SourceSpan span, CheckedExpression pointer, StructFieldSymbol field, CoreFunction function) throws CoreError {
		if (field.is_private && (function.implicit_receiver == null || function.implicit_receiver.contract.instance_type != build_type (field.containing_type.semantic_type))) {
			throw new CoreError.INVALID_CHECKED_MODEL ("private field access requires its exact lexical declaring Class");
		}
		var descriptor = fields.lookup (field);
		var property = pointer as CheckedPropertyGetExpression;
		var observation = pointer as CheckedStructProjectionValue;
		bool projected = pointer.semantic_type is ClassType && (pointer is CheckedOwnedFieldBorrow || property != null && property.property_symbol.is_borrowed || observation != null && observation.source.contract.mode == StructValueMode.BORROW_VALUE);
		if (descriptor == null || !(projected || pointer is CheckedThisExpression || pointer is CheckedWithReference || pointer is CheckedClassUpcast || pointer is CheckedParameterReferenceExpression || pointer is CheckedLocalReferenceExpression)) {
			throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: indirect field requires an exact field and pointer symbol reference");
		}
		return new CoreIndirectFieldPlace (span, build_value (pointer, function), descriptor);
	}

	private EnumDefinition build_enum_definition(EnumDefinition source) throws CoreError {
		var variants = new GenericArray<EnumVariant> ();
		for (uint v = 0; v < source.variant_count; v++) {
			var variant = source.variant (v);
			var type = (EnumType) build_type (source.semantic_type);
			var identity = type == source.semantic_type ? variant.identity : new EnumVariantIdentity (type.identity, variant.identity.name, variant.identity.ordinal);
			var fields = new GenericArray<EnumField> ();
			for (uint f = 0; f < variant.field_count; f++) {
				var field = variant.field (f);
				fields.add (new EnumField (identity == variant.identity ? field.identity : new EnumFieldIdentity (identity, field.identity.name, field.identity.ordinal), build_type (field.semantic_type), field.span, field.owns_buffer, field.owned_cleanup, field.owns_child, field.owns_record));
			}
			variants.add (new EnumVariant (identity, variant.span, fields));
		}
		return new EnumDefinition ((EnumType) build_type (source.semantic_type), source.span, variants, source.tag_type);
	}

	private CoreEnumProducer build_enum_producer(CheckedEnumProducer producer, CoreFunction function) throws CoreError {
		var definition = enum_definitions.lookup (producer.semantic_type);
		if (definition == null) {
			throw new CoreError.INVALID_CHECKED_MODEL ("enum producer has no exact definition");
		}
		if (producer is CheckedEnumAwait) {
			return new CoreEnumAwait (definition, (CoreTaskAwait) build_value (((CheckedEnumAwait) producer).operation, function), producer.instance);
		}
		if (producer is CheckedAsyncRun) {
			return new CoreAsyncRun (producer.span, definition, (CoreAsyncOperation) build_value (((CheckedAsyncRun) producer).operation, function), producer.instance);
		}
		if (producer is CheckedEnumSnapshot) {
			return new CoreEnumSnapshot (producer.span, definition, locals.lookup (((CheckedEnumSnapshot) producer).source), producer.instance, ((CheckedEnumSnapshot) producer).mode);
		}
		var construction = producer as CheckedEnumConstruct;
		if (construction != null && !construction.matches_inputs ()) {
			throw new CoreError.INVALID_IR ("checked enum constructor lost intended field/operand correspondence");
		}
		if (construction != null) {
			if (construction.variant.identity.ordinal < 0 || construction.variant.identity.ordinal >= definition.variant_count) {
				throw new CoreError.INVALID_CHECKED_MODEL ("enum constructor variant is outside its definition");
			}
			var variant = definition.variant (construction.variant.identity.ordinal);
			if (variant.identity.ordinal != construction.variant.identity.ordinal || construction.fields.length != variant.field_count) {
				throw new CoreError.INVALID_CHECKED_MODEL ("enum constructor requires exact variant and complete payload");
			}
			var fields = new GenericArray<CoreEnumFieldValue> ();
			for (uint f = 0; f < variant.field_count; f++) {
				var field = construction.fields[f];
				if (field.field.identity != construction.variant.field (f).identity) {
					throw new CoreError.INVALID_CHECKED_MODEL ("enum constructor field correspondence mismatch");
				}
				CoreValue? scalar = null;
				if (field.field.owns_buffer) {
					var move = field.scalar as CheckedOwnershipMove;
					scalar = new CoreEnumBufferValue (field.span, ownership_contract (field.field.semantic_type), move == null ? null : owned_locals.lookup (move.source), move == null ? build_value (field.scalar, function) : null);
				} else if (field.field.owns_scalar) {
					var move = field.scalar as CheckedOwnershipMove;
					var owner = move == null ? null : owned_locals.lookup (move.source);
					if (owner == null || move.semantic_type != field.field.semantic_type || ownership_contract (field.field.semantic_type, field.field.owned_cleanup, field.field.owns_child) != owner.cleanup) {
						throw new CoreError.INVALID_CHECKED_MODEL ("enum scalar field lost its exact named owner and cleanup authority");
					}
					scalar = new CoreEnumScalarValue (field.span, owner);
				} else if (field.scalar != null) {
					scalar = build_value (field.scalar, function);
				}
				fields.add (new CoreEnumFieldValue (field.span, variant.field (f), scalar, field.record == null ? null : build_struct_producer (field.record, function), field.sum == null ? null : build_enum_producer (field.sum, function)));
			}
			return new CoreEnumConstruct (producer.span, definition, variant, fields, producer.instance);
		}
		var call = producer as CheckedEnumCallResult;
		if (call == null || call.target == null || !functions.contains (call.target)) {
			throw new CoreError.INVALID_CHECKED_MODEL ("enum call requires a live exact native target");
		}
		var arguments = new GenericArray<CoreValue> ();
		foreach (var argument in call.arguments) {
			arguments.add (build_value (argument, function));
		}
		var result = new CoreEnumCallResult (producer.span, definition, functions.lookup (call.target), arguments, call.receiver == null ? null : build_value (call.receiver, function), producer.instance);
		result.type_arguments = call.type_arguments == null ? null : copy_type_arguments (call.type_arguments);
		return result;
	}

	private StructLeafPath build_projection_path(StructLeafPath path) throws CoreError {
		int[] ordinals = new int[path.depth];
		for (int i = 0; i < path.depth; i++) {
			ordinals[i] = path.field_ordinal (i);
		}
		return new StructLeafPath (ordinals, build_type (path.semantic_type));
	}

	private CoreStructProducer build_struct_producer(CheckedStructProducer producer, CoreFunction function) throws CoreError {
		if (producer is CheckedStructInvocationResult) {
			return new CoreStructInvocationResult (build_value (((CheckedStructInvocationResult) producer).invocation, function), producer.contract.mode);
		}
		if (producer is CheckedStructBorrowSnapshot) {
			return new CoreStructBorrowSnapshot (producer.span, build_place (((CheckedStructBorrowSnapshot) producer).source, function));
		}
		if (producer is CheckedStructProjectionProducer) {
			var projection = (CheckedStructProjectionProducer) producer;
			return new CoreStructProjectionProducer (producer.span, build_struct_producer (projection.source, function), build_projection_path (projection.path));
		}
		if (producer is CheckedSlotsRecordRead) {
			var read = (CheckedSlotsRecordRead) producer;
			return new CoreSlotsRecordRead (producer.span, (CoreIndirectFieldPlace) build_place (read.store, function), build_value (read.index, function), read.remove, read.contract.mode);
		}

		if (!producer.semantic_type.is_struct_storage () || (producer.contract.mode == StructValueMode.COPY_VALUE && producer.copyability != Copyability.COPYABLE) || (producer.contract.mode == StructValueMode.MOVE_VALUE && producer.copyability != Copyability.NOT_COPYABLE)) {
			throw new CoreError.INVALID_CHECKED_MODEL ("struct producer requires its exact copy/move authority");
		}
		if (producer is CheckedStructMoveProducer) {
			var local = ((CheckedStructMoveProducer) producer).source;
			var source = owned_locals.lookup (local);
			if (source == null || source.record_fields.length == 0) {
				throw new CoreError.INVALID_CHECKED_MODEL ("record move producer '%s' lost its exact root responsibility (%s)", local.name, source == null ? "missing owner" : "missing field obligations");
			}
			return new CoreStructMoveProducer (producer.span, source);
		}
		if (producer is CheckedStructAwait) {
			return new CoreStructAwait ((CoreTaskAwait) build_value (((CheckedStructAwait) producer).operation, function), producer.contract.mode);
		}
		if (producer is CheckedStructSnapshot) {
			return new CoreStructSnapshot (producer.span, build_place (((CheckedStructSnapshot) producer).source, function));
		}
		var foreign_call = producer as CheckedCStructCallResult;
		if (foreign_call != null) {
			var foreign_arguments = new GenericArray<CoreValue> ();
			foreach (var argument in foreign_call.arguments) {
				foreign_arguments.add (build_value (argument, function));
			}
			return new CoreCStructCallResult (producer.span, c_functions.lookup (foreign_call.target), foreign_arguments);
		}
		var call = producer as CheckedStructCallResult;
		var callee = call == null || call.target == null ? null : functions.lookup (call.target);
		if (callee == null || (callee.struct_result_contract == null && !(callee is CoreGenericFunction))) {
			throw new CoreError.INVALID_CHECKED_MODEL ("bounded struct producer requires an exact native callee");
		}
		var arguments = new GenericArray<CoreValue> ();
		foreach (var argument in call.arguments) {
			arguments.add (build_value (argument, function));
		}
		return new CoreStructCallResult (producer.span, build_type (producer.semantic_type), callee, arguments, call.receiver == null ? null : build_value (call.receiver, function), call.type_arguments == null ? null : copy_type_arguments (call.type_arguments));
	}

	private CoreStatement build_call_statement(CheckedCallStatement call, CoreFunction function) throws CoreError {
		if (call.target != null && call.target.domain == CallableDomain.C) {
			var target = find_c_function (call.target);
			var arguments = build_arguments (call.arguments, call.target, function);
			return new CoreCCallStatement (call.span, target, arguments);
		}
		var target = find_function (call.target);
		var generic = call as CheckedGenericCallStatement;
		if ((target is CoreGenericFunction) != (generic != null)) {
			throw new CoreError.INVALID_CHECKED_MODEL ("generic statement must retain explicit type arguments");
		}
		var substitution = generic == null ? null : ((CoreGenericFunction) target).substitution (generic.type_arguments);
		var arguments = build_arguments (call.arguments, call.target, function, substitution);
		if (generic != null) {
			return new CoreGenericCallStatement (call.span, (CoreGenericFunction) target, copy_type_arguments (generic.type_arguments), arguments);
		}
		if (call.discard_owned_success) {
			if (target.owned_cleanup == null || !target.owned_cleanup.is_buffer || target.throws_type == null) {
				throw new CoreError.INVALID_CHECKED_MODEL ("ignored checked success requires an exact owned buffer result");
			}
			return new CoreDiscardOwnedSuccess (call.span, target, arguments, call.receiver == null ? null : build_value (call.receiver, function), target.owned_cleanup);
		}
		return new CoreCallStatement (call.span, target, arguments, call.receiver == null ? null : build_value (call.receiver, function));
	}

	private CoreValue build_value(CheckedExpression expression, CoreFunction function) throws CoreError {
		if (expression is CheckedScopedAllocator) {
			var scoped = (CheckedScopedAllocator) expression;
			return new CoreScopedAllocator (expression.span, (HandleType) build_type (expression.semantic_type), scoped.loan, find_local (scoped.backing, function), build_value (scoped.kind, function), build_value (scoped.slots, function), ownership_contract (expression.semantic_type, scoped.cleanup));
		}
		if (expression is CheckedLazyObserve) {
			return new CoreLazyObserve (expression.span, properties.lookup (((CheckedLazyObserve) expression).property_symbol));
		}
		if (expression is CheckedRetainedOperation) {
			var operation = (CheckedRetainedOperation) expression;
			if (!RetainedContracts.valid_action (operation.action) || !RetainedContracts.accepts (operation.action, operation.callee.semantic_type) || operation.arguments.length != RetainedContracts.arity (operation.action) || expression.semantic_type.kind != TypeKind.INT) {
				throw new CoreError.INVALID_CHECKED_MODEL ("retained operation lost exact owner, signature or action");
			}
			var arguments = new GenericArray<CoreValue> ();
			foreach (var argument in operation.arguments) {
				if (argument.semantic_type != expression.semantic_type) {
					throw new CoreError.INVALID_CHECKED_MODEL ("retained callback argument differs from exact int signature");
				}
				arguments.add (build_value (argument, function));
			}
			return new CoreRetainedOperation (expression.span, operation.action, build_value (operation.callee, function), arguments, expression.semantic_type);
		}
		if (expression is CheckedClosureBind) {
			var closure = (CheckedClosureBind) expression;
			var source = owned_locals.lookup (closure.source);
			var target = closure.target == null ? null : find_function (closure.target);
			var cleanup = cleanups.lookup (closure.cleanup);
			if (source == null || target == null || cleanup == null || cleanup.closure_type != build_type (expression.semantic_type) || !source.cleanup.is_heap_object || source.place.semantic_type != cleanup.closure_type.environment_type) {
				throw new CoreError.INVALID_CHECKED_MODEL ("closure binding lost exact heap environment, native code or destruction identity");
			}
			return new CoreClosureBind (expression.span, (ClosureHandleType) build_type (expression.semantic_type), source, target, cleanup, closure.actor_binding);
		}
		if (expression is CheckedClosureCall) {
			var call = (CheckedClosureCall) expression;
			var channels = new GenericArray<CoreParameter> ();
			foreach (var channel in call.channel_parameters) {
				var mapped = new CoreParameter (channel.span, channel.name_span, channel.name, build_type (channel.semantic_type), channel.ordinal, channel.pointer_contract);
				mapped.heap_object = channel.heap_object;
				if (channel.struct_value_contract != null) {
					mapped.struct_value_contract = new StructValueContract (mapped.semantic_type, channel.struct_value_contract.mode);
				}
				parameters.insert (channel, mapped);
				channels.add (mapped);
			}
			var arguments = new GenericArray<CoreValue> ();
			foreach (var argument in call.arguments) {
				arguments.add (build_value (argument, function));
			}
			var invocation = new CoreClosureCall (expression.span, (ClosureHandleType) build_type (call.callee.semantic_type), build_value (call.callee, function), arguments, call.owned_producer == null ? null : ownership_contract (expression.semantic_type, call.owned_producer.cleanup, expression.semantic_type is ClassType));
			foreach (var channel in channels) {
				invocation.channel_parameters.add (channel);
			}
			return invocation;
		}
		if (expression is CheckedSharedOperation) {
			var operation = (CheckedSharedOperation) expression;
			if ((operation.action == SharedAction.ACQUIRE && (operation.source == null || !operation.source.heap_object || operation.source.object_owner == null)) || !SharedContracts.matches (operation.action, operation.operand.semantic_type, expression.semantic_type)) {
				throw new CoreError.INVALID_CHECKED_MODEL ("shared operation lost exact payload/strong/weak identity");
			}
			return new CoreSharedOperation (expression.span, expression.semantic_type, operation.action, build_value (operation.operand, function), operation.source == null ? null : owned_locals.lookup (operation.source), expression.semantic_type is ClassType && ((ClassType) expression.semantic_type).intrinsically_shared && operation.action != SharedAction.BORROW ? ownership_contract (expression.semantic_type, null, true) : operation.cleanup == null ? null : cleanups.lookup (operation.cleanup), operation.borrower == null ? null : parameters.lookup (operation.borrower));
		}
		if (expression is CheckedTaskBorrow) {
			return new CoreTaskBorrow (expression.span, locals.lookup (((CheckedTaskBorrow) expression).source));
		}
		if (expression is CheckedExecutorBorrow) {
			return new CoreExecutorBorrow (expression.span, locals.lookup (((CheckedExecutorBorrow) expression).source));
		}
		if (expression is CheckedAsyncOperation) {
			var operation = (CheckedAsyncOperation) expression;
			return new CoreAsyncOperation (expression.span, operation.contract, operation.executor == null ? null : build_value (operation.executor, function), operation.task == null ? null : build_value (operation.task, function), operation.argument == null ? null : build_value (operation.argument, function));
		}
		if (expression is CheckedTaskAwait) {
			var wait = (CheckedTaskAwait) expression;
			return new CoreTaskAwait (expression.span, build_type (expression.semantic_type), wait.body, build_value (wait.child, function), wait.discard, expression.owns_buffer ? ownership_contract (expression.semantic_type) : null, wait.bridge_executor == null ? null : build_value (wait.bridge_executor, function));
		}
		if (expression is CheckedTaskCreate) {
			var creation = (CheckedTaskCreate) expression;
			var target = find_function (creation.target);
			if (target.async_body == null || creation.semantic_type != target.async_body.task_type) {
				throw new CoreError.INVALID_CHECKED_MODEL ("task creation lost exact body/logical contract association");
			}
			var arguments = build_arguments (creation.arguments, creation.target, function, null);
			var result = new CoreTaskCreate (expression.span, (TaskType) expression.semantic_type, target, arguments, creation.allocation_context == null ? null : build_value (creation.allocation_context, function), creation.checked_admission);
			foreach (var loan in creation.loans) {
				var view = arguments[loan.parameter_ordinal] as CoreSliceFromArrayValue;
				if (view == null || creation.arguments[loan.parameter_ordinal] != loan.view || view.storage != locals.lookup (loan.storage)) {
					throw new CoreError.INVALID_CHECKED_MODEL ("suspension capture lost exact original view/root association");
				}
				result.loans.add (new CoreSuspensionLoan (loan.identity, loan.parameter_ordinal, view.storage, view));
			}
			return result;
		}
		if (expression is CheckedTaskMove) {
			return new CoreTaskMove (expression.span, locals.lookup (((CheckedTaskMove) expression).source));
		}
		var value = build_value_without_text_intent (expression, function);
		if (expression.text_loan_intent != null) {
			var owners = new GenericArray<Object> ();
			for (uint i = 0; i < expression.text_loan_intent.count; i++) {
				var owner = expression.text_loan_intent.owner (i);
				Object? mapped = null;
				if (owner is LocalSymbol) {
					mapped = locals.lookup ((LocalSymbol) owner);
				} else if (owner is ParameterSymbol) {
					mapped = parameters.lookup ((ParameterSymbol) owner);
				} else if (owner is ReceiverSymbol) {
					mapped = receivers.lookup ((ReceiverSymbol) owner);
				}
				if (mapped == null) {
					throw new CoreError.INVALID_CHECKED_MODEL ("text loan backing lacks an exact predecessor mapping");
				}
				owners.add (mapped);
			}
			value.text_loan_intent = new Astra.Text.TextLoanIntent (owners);
		}
		return value;
	}

	private CoreValue build_value_without_text_intent(CheckedExpression expression, CoreFunction function) throws CoreError {
		if (expression is CheckedStructProjectionValue) {
			var projection = (CheckedStructProjectionValue) expression;
			return new CoreStructProjectionValue (expression.span, build_struct_producer (projection.source, function), build_projection_path (projection.path));
		}
		if (expression is CheckedCallbackParameterView) {
			var view = (CheckedCallbackParameterView) expression;
			return new CoreCallbackParameterView (expression.span, (CallbackType) build_type (expression.semantic_type), parameters.lookup (view.source), parameters.lookup (view.parameter));
		}
		if (expression is CheckedFunctionAddress) {
			var address = (CheckedFunctionAddress) expression;
			return new CoreFunctionAddress (expression.span, (FunctionValueType) build_type (expression.semantic_type), find_function (address.target));
		}
		if (expression is CheckedFunctionValueCall) {
			var call = (CheckedFunctionValueCall) expression;
			var channels = new GenericArray<CoreParameter> ();
			foreach (var channel in call.channel_parameters) {
				var mapped = new CoreParameter (channel.span, channel.name_span, channel.name, build_type (channel.semantic_type), channel.ordinal, channel.pointer_contract);
				mapped.heap_object = channel.heap_object;
				if (channel.struct_value_contract != null) {
					mapped.struct_value_contract = new StructValueContract (mapped.semantic_type, channel.struct_value_contract.mode);
				}
				parameters.insert (channel, mapped);
				channels.add (mapped);
			}
			var arguments = new GenericArray<CoreValue> ();
			foreach (var argument in call.arguments) {
				arguments.add (build_value (argument, function));
			}
			var invocation = new CoreFunctionValueCall (expression.span, (FunctionValueType) build_type (call.callee.semantic_type), build_value (call.callee, function), arguments, call.owned_producer == null ? null : ownership_contract (expression.semantic_type, call.owned_producer.cleanup, expression.semantic_type is ClassType));
			foreach (var channel in channels) {
				invocation.channel_parameters.add (channel);
			}
			return invocation;
		}
		if (expression is CheckedClassUpcast) {
			var cast = (CheckedClassUpcast) expression;
			return new CoreClassUpcast (expression.span, build_value (cast.reference, function), (CoreClass) structs.lookup (cast.source_class.semantic_type), (CoreClass) structs.lookup (cast.target_class.semantic_type), expression.semantic_type);
		}
		if (expression is CheckedUtf8FactoryExpression) {
			var operation = (CheckedUtf8FactoryExpression) expression;
			return new CoreUtf8FactoryValue (expression.span, expression.semantic_type, parameters.lookup (operation.input), operation.validates);
		}
		if (expression is CheckedTextExpression) {
			var payload = ((CheckedTextExpression) expression).payload;
			text_literals.add (payload);
			return new CoreTextValue (expression.span, expression.semantic_type, payload);
		}
		if (expression is CheckedTextLengthExpression) {
			return new CoreTextLengthValue (expression.span, expression.semantic_type, build_value (((CheckedTextLengthExpression) expression).receiver, function));
		}
		if (expression is CheckedConstantReference) {
			return build_value (((CheckedConstantReference) expression).constant.value.expression (expression.span), function);
		}
		if (expression is CheckedEnumArgument) {
			var argument = (CheckedEnumArgument) expression;
			return new CoreEnumArgument (expression.span, parameters.lookup (argument.parameter), build_enum_producer (argument.producer, function));
		}
		if (expression is CheckedEnumEquality) {
			var equality = (CheckedEnumEquality) expression;
			return new CoreEnumEquality (expression.span, expression.semantic_type, build_enum_producer (equality.left, function), build_enum_producer (equality.right, function), equality.unequal);
		}
		if (expression is CheckedStructArgument) {
			var argument = (CheckedStructArgument) expression;
			return new CoreStructArgument (expression.span, argument.parameter == null ? null : parameters.lookup (argument.parameter), build_struct_producer (argument.producer, function));
		}
		var capability = expression as CheckedGenericCapabilityOperation;
		if (capability != null) {
			var generic = function as CoreGenericFunction;
			CoreTypeParameter? parameter = null;
			if (generic != null) {
				foreach (var candidate in generic.type_parameters) {
					if (candidate.semantic_type == capability.type_parameter) {
						parameter = candidate;
					}
				}
			}
			if (parameter == null) {
				throw new CoreError.INVALID_CHECKED_MODEL ("capability operation requires its exact lexical type parameter");
			}
			var left = build_value (capability.left, function);
			return new CoreGenericCapabilityOperation (capability.span, capability.semantic_type, capability.operator_kind, parameter, capability.capability.identity, left, capability.right == null ? null : build_value (capability.right, function));
		}
		if (expression is CheckedOwnedBufferAllocate) {
			var allocation = (CheckedOwnedBufferAllocate) expression;
			return new CoreOwnedBufferAllocate (expression.span, (SliceType) build_type (expression.semantic_type), build_value (allocation.count, function), ownership_contract (expression.semantic_type), allocation.failure_call == null ? null : build_call_statement (allocation.failure_call, function), allocation.allocation_context == null ? null : build_value (allocation.allocation_context, function));
		}
		if (expression is CheckedOwnedBufferBorrow) {
			var borrow = (CheckedOwnedBufferBorrow) expression;
			return new CoreOwnedBufferBorrow (expression.span, owned_locals.lookup (borrow.source), borrow.parameter == null ? null : parameters.lookup (borrow.parameter));
		}
		if (expression is CheckedWithReference) {
			var reference = (CheckedWithReference) expression;
			var contract = with_contracts.lookup (reference.contract);
			if (contract == null || reference.semantic_type != contract.source.semantic_type) {
				throw new CoreError.INVALID_CHECKED_MODEL ("with reference lost enclosing exact receiver capture");
			}
			return new CoreWithReference (expression.span, contract);
		}
		if (expression is CheckedSlotsTake) {
			var take = (CheckedSlotsTake) expression;
			if (!(take.store.semantic_type is OwnerSlotsType) || take.semantic_type != ((OwnerSlotsType) take.store.semantic_type).element) {
				throw new CoreError.INVALID_CHECKED_MODEL ("slot take lost exact checked element identity");
			}
			return new CoreSlotsTake (take.span, (CoreIndirectFieldPlace) build_place (take.store, function), build_value (take.index, function));
		}
		if (expression is CheckedSlotsValue) {
			var v = (CheckedSlotsValue) expression;
			if (v.has_iteration != (v.iteration != null)) {
				throw new CoreError.INVALID_CHECKED_MODEL ("foreach element lost its iteration authority");
			}
			if (v.iteration != null && v.store != v.iteration.store) {
				throw new CoreError.INVALID_CHECKED_MODEL ("foreach element changed its exact backing store");
			}
			var iteration = v.iteration == null ? null : iterations.lookup (v.iteration);
			if (v.iteration != null && iteration == null) {
				throw new CoreError.INVALID_CHECKED_MODEL ("foreach element has no enclosing mapped iteration");
			}
			CoreIndirectFieldPlace store;
			if (iteration == null) {
				store = (CoreIndirectFieldPlace) build_place (v.store, function);
			} else {
				store = iteration.store;
			}
			return new CoreSlotsValue (expression.span, expression.semantic_type, store, v.action, v.operand == null ? null : build_value (v.operand, function), v.borrower == null ? null : parameters.lookup (v.borrower), iteration);
		}
		if (expression is CheckedOwnedFieldBorrow) {
			var borrow = (CheckedOwnedFieldBorrow) expression;
			return new CoreOwnedFieldBorrow (expression.span, (CoreIndirectFieldPlace) build_place (borrow.source, function), borrow.parameter == null ? null : parameters.lookup (borrow.parameter));
		}
		var object_receiver = expression as CheckedObjectReceiverExpression;
		if (object_receiver != null) {
			return new CoreObjectReceiverValue (expression.span, build_value (object_receiver.reference, function), (ReceiverType) build_type (expression.semantic_type));
		}
		var self = expression as CheckedThisExpression;
		if (self != null) {
			var receiver = receivers.lookup (self.receiver);
			if (function.implicit_receiver != receiver) {
				throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: this requires the exact containing method receiver");
			}
			return new CoreReceiverValue (expression.span, receiver);
		}
		var receiver_address = expression as CheckedReceiverAddressExpression;
		if (receiver_address != null && receiver_address.receiver_place != null) {
			return new CoreAddressOfValue.projection (expression.span, (ReceiverType) expression.semantic_type, build_place (receiver_address.receiver_place, function));
		}
		if (receiver_address != null) {
			return new CoreAddressOfValue (expression.span, expression.semantic_type, find_local (receiver_address.local, function));
		}

		var slice = expression as CheckedSliceFromArrayExpression;
		if (slice != null) {
			var start = slice.start == null ? null : build_value (slice.start, function);
			var count = slice.count == null ? null : build_value (slice.count, function);
			return new CoreSliceFromArrayValue (expression.span, (SliceType) build_type (expression.semantic_type), find_local (slice.local, function), (ArrayType) build_type (slice.array_type), start, count, slice.provenance);
		}
		var length = expression as CheckedLengthExpression;
		if (length != null) {
			if (length.array != null) {
				return new CoreIntegerValue.typed (expression.span, expression.semantic_type, AstraIntegerValue.from_int64 ((IntegerType) expression.semantic_type, ((ArrayType) length.array.semantic_type).length));
			}
			return new CoreSliceLengthValue (expression.span, expression.semantic_type, build_value (length.slice, function));
		}
		var argument = expression as CheckedOwnedArgument;
		if (argument != null) {
			var parameter = parameters.lookup (argument.parameter);
			var source = argument.transfer == null ? null : owned_locals.lookup (argument.transfer.source);
			var cleanup = ownership_contract (argument.semantic_type, argument.cleanup, argument.heap_object);
			if (parameter == null || cleanup == null || (argument.transfer != null && source == null)) {
				throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: owned argument requires exact parameter, cleanup and source mapping");
			}
			return new CoreOwnedArgumentValue (argument.span, parameter, cleanup, source, build_type (argument.semantic_type), argument.producer == null ? null : build_value (argument.producer, function));
		}
		var borrow = expression as CheckedOwnedBorrowValue;
		if (borrow != null) {
			var owner = owned_locals.lookup (borrow.source);
			var parameter = parameters.lookup (borrow.parameter);
			if (owner == null || owner.place != find_local (borrow.source, function) || parameter == null || parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
				throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: borrow requires exact owner and borrowed parameter mapping");
			}
			return new CoreOwnedBorrowValue (borrow.span, owner, parameter);
		}
		var result_construction = expression as CheckedOwnedObjectResultConstruction;
		if (result_construction != null) {
			if (function.result_storage == null || result_storages.lookup (result_construction.storage) != function.result_storage || result_construction.storage.semantic_type != function.return_type) {
				throw new CoreError.INVALID_CHECKED_MODEL ("result construction requires exact function result storage");
			}
			return new CoreOwnedObjectResultConstruction (expression.span, function.result_storage, (CoreConstructor) find_function (result_construction.constructor), build_arguments (result_construction.arguments, result_construction.constructor, function));
		}
		var call = expression as CheckedCallExpression;
		if (call != null) {
			if (call.target != null && call.target.domain == CallableDomain.C) {
				var target = find_c_function (call.target);
				var arguments = build_arguments (call.arguments, call.target, function);
				if ((!(target.metadata.bool_abi == Astra.Foreign.CBoolAbi.C99 && target.return_type.kind == TypeKind.BOOL) && target.return_type.kind != TypeKind.INT && !(target.return_type is IntegerType && ((IntegerType) target.return_type).bit_width == 64) && !(target.return_type is F64Type) && !(target.return_type is F32Type) && !target.return_type.is_ownable_handle_type ()) || call.semantic_type != target.return_type) {
					throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: C call value must match an int or void* result");
				}
				return new CoreCCallValue (call.span, call.semantic_type, target, arguments);
			}
			var target = find_function (call.target);
			var generic = call as CheckedGenericCall;
			if ((target is CoreGenericFunction) != (generic != null)) {
				throw new CoreError.INVALID_CHECKED_MODEL ("generic call must retain explicit type arguments");
			}
			var substitution = generic == null ? null : ((CoreGenericFunction) target).substitution (generic.type_arguments);
			if (target.return_type.kind == TypeKind.VOID || (substitution == null ? build_type (call.semantic_type) != target.return_type : !substitution.matches (call.target.return_type, call.semantic_type))) {
				throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: call value must match a non-void target return type");
			}
			var arguments = build_arguments (call.arguments, call.target, function, substitution);
			CoreCallValue result = generic == null ? new CoreCallValue (call.span, build_type (call.semantic_type), target, arguments, call.receiver == null ? null : build_value (call.receiver, function)) : (CoreCallValue) new CoreGenericCall (call.span, build_type (call.semantic_type), (CoreGenericFunction) target, copy_type_arguments (generic.type_arguments), arguments);
			if (call.candidate_storage != null) {
				var source = call.candidate_storage;
				if (!source.result_candidate || source.ordinal != function.object_storage.length) {
					throw new CoreError.INVALID_CHECKED_MODEL ("result candidate requires exact local storage identity");
				}
				var candidate = new CoreObjectStorage (source.span, (CoreClass) structs.lookup (source.semantic_type), source.ordinal, source.lexical_region.ordinal, scopes.lookup (source.lexical_region));
				candidate.result_candidate = true;
				function.object_storage.add (candidate);
				result.candidate_storage = candidate;
			}
			if (call.result_storage != null) {
				if (result_storages.lookup (call.result_storage) != function.result_storage) {
					throw new CoreError.INVALID_CHECKED_MODEL ("forwarded call must use exact function result storage");
				}
				result.result_storage = function.result_storage;
			}
			return result;
		}
		if (expression is CheckedNullPointerExpression) {
			return new CoreNullPointerValue (expression.span, build_type (expression.semantic_type));
		}
		var boolean = expression as CheckedBooleanExpression;
		if (boolean != null) {
			return new CoreBooleanValue (boolean.span, boolean.semantic_type, boolean.literal);
		}
		var dot = expression as CheckedVectorDotExpression;
		if (dot != null) {
			var accumulator = dot.accumulator == null ? null : build_value (dot.accumulator, function);
			var first = build_value (dot.first, function);
			var second = build_value (dot.second, function);
			return new CoreVectorDotValue (expression.span, dot.dot_kind, dot.source_type, dot.destination_type, accumulator, first, second);
		}
		var dsp = expression as CheckedDspExpression;
		if (dsp != null) {
			var first = build_value (dsp.first, function);
			var second = dsp.second == null ? null : build_value (dsp.second, function);
			return new CoreDspValue (expression.span, dsp.primitive_kind, dsp.source_type, dsp.destination_type, first, second, dsp.destination_element);
		}
		var shift = expression as CheckedIntegerShiftExpression;
		if (shift != null) {
			var operand = build_value (shift.operand, function);
			var count = build_value (shift.count, function);
			return new CoreIntegerShiftValue (expression.span, expression.semantic_type, shift.shift_kind, operand, count);
		}
		var numeric_conversion = expression as CheckedNumericConversionExpression;
		if (numeric_conversion != null) {
			return new CoreNumericConversionValue (expression.span, numeric_conversion.source_type, numeric_conversion.destination_type, numeric_conversion.conversion_kind, build_value (numeric_conversion.operand, function), numeric_conversion.policy);
		}
		var floating_conversion = expression as CheckedFloatConversionExpression;
		if (floating_conversion != null) {
			return new CoreFloatConversionValue (expression.span, floating_conversion.source_type, floating_conversion.destination_type, floating_conversion.conversion_kind, build_value (floating_conversion.operand, function));
		}
		var conversion = expression as CheckedIntegerConversionExpression;
		if (conversion != null) {
			return new CoreIntegerConversionValue (expression.span, conversion.source_type, conversion.destination_type, build_value (conversion.operand, function));
		}
		if (expression is CheckedVectorMemoryExpression) {
			var memory = (CheckedVectorMemoryExpression) expression;
			if (!memory.contract.valid ()) {
				throw new CoreError.INVALID_CHECKED_MODEL ("forged vector memory contract");
			}
			var view = build_value (memory.view, function);
			var offset = build_value (memory.offset, function);
			return new CoreVectorMemoryValue (expression.span, memory.contract, view, offset, memory.stored == null ? null : build_value (memory.stored, function));
		}
		var select = expression as CheckedVectorSelectExpression;
		if (select != null) {
			return new CoreVectorSelectValue (expression.span, expression.semantic_type, build_value (select.mask, function), build_value (select.true_value, function), build_value (select.false_value, function));
		}
		var shuffle = expression as CheckedVectorShuffleExpression;
		if (shuffle != null) {
			return new CoreVectorShuffleValue (expression.span, expression.semantic_type, build_value (shuffle.vector, function), shuffle.selectors);
		}
		var insert = expression as CheckedVectorInsertExpression;
		if (insert != null) {
			return new CoreVectorInsertValue (expression.span, expression.semantic_type, build_value (insert.vector, function), insert.index, build_value (insert.replacement, function));
		}
		var extract = expression as CheckedVectorExtractExpression;
		if (extract != null) {
			return new CoreVectorExtractValue (expression.span, expression.semantic_type, build_value (extract.vector, function), extract.index);
		}
		var splat = expression as CheckedVectorSplatExpression;
		if (splat != null) {
			return new CoreVectorSplatValue (expression.span, expression.semantic_type, build_value (splat.operand, function), splat.lane_count, splat.lane_count_span);
		}
		var vector = expression as CheckedVectorConstructExpression;
		if (vector != null) {
			var lanes = new GenericArray<CoreValue> ();
			foreach (var lane in vector.lanes) {
				lanes.add (build_value (lane, function));
			}
			return new CoreVectorConstructValue (expression.span, expression.semantic_type, lanes);
		}
		var reduction = expression as CheckedVectorReductionExpression;
		if (reduction != null) {
			return new CoreVectorReductionValue (expression.span, expression.semantic_type, reduction.operator_kind, build_value (reduction.operand, function));
		}
		if (expression is CheckedFloatExpression) {
			return new CoreFloatValue (expression.span, expression.semantic_type, ((CheckedFloatExpression) expression).value);
		}
		if (expression is CheckedIntegerExpression) {
			return new CoreIntegerValue.typed (expression.span, expression.semantic_type, ((CheckedIntegerExpression) expression).value);
		}
		var reference = expression as CheckedParameterReferenceExpression;
		if (reference != null) {
			var parameter = parameters.lookup (reference.parameter);
			if (parameter == null || parameter.ordinal < 0 || parameter.ordinal >= function.parameters.length || function.parameters[parameter.ordinal] != parameter) {
				throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: parameter reference has no declaration in the containing function");
			}
			return new CoreParameterValue (reference.span, parameter);
		}
		var load = expression as CheckedLoadExpression;
		if (load != null) {
			if (!VolatileAccessContract.valid (load.volatile_access, load.volatile_enabled, load.source.semantic_type)) {
				throw new CoreError.INVALID_CHECKED_MODEL ("volatile load lost its exact checked access contract");
			}
			return new CoreLoadValue (load.span, build_place (load.source, function), load.volatile_access == null ? null : load.volatile_access.copy ());
		}
		var address = expression as CheckedAddressOfExpression;
		if (address != null) {
			return new CoreAddressOfValue (address.span, build_type (address.semantic_type), find_local (address.local, function), BorrowProvenance.for_expression (address).snapshot ());
		}
		var indirect = expression as CheckedIndirectFieldReference;
		if (indirect != null) {
			return new CoreLoadValue (expression.span, build_indirect_place (expression.span, indirect.pointer, indirect.field, function));
		}
		var field = expression as CheckedFieldReferenceExpression;
		if (field != null) {
			return new CoreLoadValue (expression.span, find_field (field.local, field.field, function));
		}
		var local = expression as CheckedLocalReferenceExpression;
		if (local != null) {
			return new CoreLoadValue (local.span, find_local (local.local, function));
		}
		var prefix = expression as CheckedPrefixExpression;
		if (prefix != null) {
			return new CorePrefixValue (prefix.span, prefix.semantic_type, prefix.operator_kind, build_value (prefix.operand, function));
		}
		if (expression is CheckedComparisonChain) {
			var chain = (CheckedComparisonChain) expression;
			if (chain.operand_count != chain.operands.length || chain.operands.length < 3 || chain.operators.length + 1 != chain.operands.length) {
				throw new CoreError.INVALID_CHECKED_MODEL ("comparison chain lost its operand/operator arity");
			}
			var operands = new GenericArray<CoreValue> ();
			var operators = new GenericArray<BinaryOperator> ();
			var seen = new HashTable<CheckedExpression, bool> (direct_hash, direct_equal);
			foreach (var operand in chain.operands) {
				if (seen.contains (operand)) {
					throw new CoreError.INVALID_CHECKED_MODEL ("comparison chain repeated an operand occurrence");
				}
				seen.insert (operand, true);
				operands.add (build_value (operand, function));
			}
			for (int i = 0; i < chain.operators.length; i++) {
				operators.add (chain.operators[i]);
			}
			return new CoreComparisonChain (expression.span, expression.semantic_type, operands, operators);
		}
		var short_circuit = expression as CheckedShortCircuitExpression;
		if (short_circuit != null) {
			var left = build_value (short_circuit.left, function);
			var right = build_value (short_circuit.right, function);
			return new CoreShortCircuitValue (short_circuit.span, short_circuit.semantic_type, short_circuit.operator_kind, left, right);
		}
		var binary = expression as CheckedBinaryExpression;
		if (binary != null) {
			var left = build_value (binary.left, function);
			var right = build_value (binary.right, function);
			return new CoreBinaryValue (binary.span, binary.semantic_type, binary.operator_kind, left, right);
		}
		throw new CoreError.INVALID_CHECKED_MODEL ("internal Core construction error: unsupported checked value");
	}

}
}
