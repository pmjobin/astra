// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;

namespace Astra.Semantic {
// Resource bounds are independent of declaration shape and shared by the
// source, materialization and native dependency authorities.
public class GenericResourceLimits : Object {
	public const uint CLOSED_INSTANCES = 16384;
	public const int NATIVE_UNITS = 256;
	public const int NATIVE_DEPTH = 64;
	public const int NATIVE_CALLABLES = 4096;
	public const int NATIVE_TYPES = 1024;
	public const int TYPE_DEPTH = 128;
	// Follow type constructors, never nominal storage fields: a recursive
	// reference graph is distinct from an expanding type-argument expression.
	public static bool admits_type(SemanticType type, int remaining = TYPE_DEPTH) {
		var arguments = type.generic_arguments ();
		if (arguments != null && arguments.length != 0) {
			if (remaining == 0) {
				return false;
			}
			foreach (var argument in arguments.copy_values ()) {
				if (!admits_type (argument, remaining - 1)) {
					return false;
				}
			}
		}
		if (type is EnumType && ((EnumType) type).argument_count != 0) {
			if (remaining == 0) {
				return false;
			}
			var enumeration = (EnumType) type;
			for (uint a = 0; a < enumeration.argument_count; a++) {
				if (!admits_type (enumeration.argument (a), remaining - 1)) {
					return false;
				}
			}
		}
		if (type is ClosureHandleType) {
			if (remaining == 0) {
				return false;
			}
			var closure = (ClosureHandleType) type;
			if (!admits_type (closure.environment_type, remaining - 1) || !admits_type (closure.result_type, remaining - 1)) {
				return false;
			}
			foreach (var parameter in closure.parameter_types) {
				if (!admits_type (parameter, remaining - 1)) {
					return false;
				}
			}
		}
		SemanticType? element = null;
		if (type is SliceType) {
			element = ((SliceType) type).element_type;
		} else if (type is ArrayType) {
			element = ((ArrayType) type).element_type;
		} else if (type is TypedPointerType) {
			element = ((TypedPointerType) type).pointee;
		} else if (type is RawPointerType) {
			element = ((RawPointerType) type).pointee;
		} else if (type is OwnerSlotsType) {
			element = ((OwnerSlotsType) type).element;
		} else if (type is TaskType) {
			element = ((TaskType) type).success_type;
		}
		return element == null || remaining > 0 && admits_type (element, remaining - 1);
	}
}

public enum BooleanLiteral {
	FALSE,
	TRUE;

	public string spelling() {
		return this == TRUE ? "true" : "false";
	}
}

public enum TypeKind {
	INT,
	BOOL,
	VOID,
	RAW_POINTER,
	STRUCT,
	HANDLE,
	I8,
	U8,
	I16,
	U16,
	U32,
	I64,
	U64,
	ISIZE,
	USIZE,
	F32,
	F64,
	VECTOR,
	TYPED_POINTER,
	ARRAY,
	SLICE,
	RECEIVER,
	CLASS,
	TYPE_PARAMETER,
	GENERIC_STRUCT_APPLICATION,
	STRING,
	ENUM,
	TASK, EXECUTOR, OWNER_SLOTS, FUNCTION_VALUE, CALLBACK
}

// Language identity. IntegerType owns numeric semantics; physical ABI and
// storage remain downstream decisions. TypeKind.INT is the canonical i32 tag.
public class SemanticType : Object {
	private Object nominal_token = new Object ();
	private bool nominal_bound;
	public Object logical_identity { get { return nominal_token; } }
	internal void bind_logical_identity(Object token) {
		assert (!nominal_bound || nominal_token == token);
		nominal_token = token;
		nominal_bound = true;
	}
	private TypeKind type_kind;
	public TypeKind kind { get { return type_kind; } }

	internal SemanticType (TypeKind kind) {
		this.type_kind = kind;
	}

	public bool is_struct_pointer() {
		return this is TypedPointerType && ((TypedPointerType) this).pointee.is_struct_storage ();
	}

	public bool is_struct_storage() {
		return this is StructType || kind == TypeKind.GENERIC_STRUCT_APPLICATION;
	}
	public virtual bool is_parameterized() {
		return this is TypeParameterType;
	}
	internal virtual SemanticType substitute(TypeSubstitution substitution) {
		return this;
	}
	public virtual string? generic_definition_name() {
		return null;
	}
	public virtual TypeArgumentVector? generic_arguments() {
		return null;
	}
	// Materialized records have private storage symbols. Public nominal
	// contracts retain the definition and recursively ordered arguments.
	public string nominal_name() {
		if (this is FunctionValueType) {
			return ((FunctionValueType) this).signature_name (true);
		}
		string? definition = generic_definition_name ();
		var arguments = generic_arguments ();
		if (definition == null || arguments == null || (!(this is StructType) && !(this is ClassType))) {
			return display_name ();
		}
		var result = new StringBuilder (definition + "<");
		for (int a = 0; a < arguments.length; a++) {
			result.append ((a == 0 ? "" : ",") + arguments.at (a).nominal_name ());
		}
		return result.str + ">";
	}

	public bool is_typed_pointer() {
		return this is TypedPointerType;
	}

	public bool is_text_slice() {
		return this is SliceType && ((SliceType) this).element_type is StringType;
	}
	public bool is_text_view() {
		return this is StringType || is_text_slice ();
	}

	public bool is_lexically_borrowed_value() {
		return this is TypedPointerType || this is SliceType || this is ClassType;
	}

	// Value capability is deliberately narrower than typed pointee capability.
	public bool is_directly_dereferenceable_value_type() {
		return this is IntegerType || this is FloatingType || (this is VectorType && !((VectorType) this).is_mask && VectorType.supports (((VectorType) this).element_type, ((VectorType) this).lane_count));
	}

	public bool is_typed_data_pointee() {
		return is_directly_dereferenceable_value_type () || (is_struct_storage () && !is_parameterized ());
	}

	public bool is_void_pointer() {
		return this is RawPointerType && ((RawPointerType) this).pointee.kind == TypeKind.VOID;
	}

	public bool is_ownable_handle_type() {
		return is_void_pointer () || this is HandleType;
	}

	public bool is_scoped_allocator() {
		return this is HandleType && ((HandleType) this).context_mode == "scoped-affine";
	}

	public bool is_nullable_pointer_value() {
		return this is RawPointerType || this is TypedPointerType || this is HandleType || this is ClassType || this is CallbackType;
	}

	public virtual string display_name() {
		if (this is FunctionValueType) {
			return ((FunctionValueType) this).signature_name ();
		}
		switch (kind) {
		case TypeKind.OWNER_SLOTS: return ((OwnerSlotsType) this).element.display_name () + "[slots]";
		case TypeKind.EXECUTOR:
			return ((ExecutorType) this).executor_display_name ();
		case TypeKind.TASK:
			return ((TaskType) this).task_display_name ();
		case TypeKind.TYPE_PARAMETER:
			return ((TypeParameterType) this).name;
		case TypeKind.RECEIVER:
			return "Receiver<%s>".printf (((ReceiverType) this).instance_type.display_name ());
		case TypeKind.SLICE:
			return ((SliceType) this).element_type.display_name () + "[]";
		case TypeKind.ARRAY:
			var array = (ArrayType) this;
			return "%s[%d]".printf (array.element_type.display_name (), array.length);
		case TypeKind.VECTOR:
			var vector = (VectorType) this;
			return "%s<%d>".printf (vector.element_type.display_name (), vector.lane_count);
		case TypeKind.HANDLE:
			return ((HandleType) this).name;
		case TypeKind.CLASS:
			return ((ClassType) this).name;
		case TypeKind.STRUCT:
			return ((StructType) this).name;
		case TypeKind.STRING:
			return "string";
		case TypeKind.INT:
			return "int";
		case TypeKind.I8:
			return "i8";
		case TypeKind.U8:
			return "u8";
		case TypeKind.I16:
			return "i16";
		case TypeKind.U16:
			return "u16";
		case TypeKind.U32:
			return "u32";
		case TypeKind.I64:
			return "i64";
		case TypeKind.U64:
			return "u64";
		case TypeKind.ISIZE:
			return "isize";
		case TypeKind.USIZE:
			return "usize";
		case TypeKind.F32:
			return "f32";
		case TypeKind.F64:
			return "f64";
		case TypeKind.BOOL:
			return "bool";
		case TypeKind.VOID:
			return "void";
		case TypeKind.RAW_POINTER:
			return ((RawPointerType) this).pointee.display_name () + "*";
		case TypeKind.TYPED_POINTER:
			return ((TypedPointerType) this).pointee.display_name () + "*";
		default:
			assert_not_reached ();
		}
	}
}

// Immutable lexical identity token, owned one-to-one by its declaring symbol.
// Like StructType, it has no symbol/body/stage backlink and may outlive semantics.
// A copied native code address with exact nonthrowing value/ownership channels.
// This is independent of Class.invoke and cannot be cast from a data pointer.
public interface CallableSignature : Object {
	public abstract ResultOwnershipContract result_contract { get; }
	public abstract StructValueShape? record_result { get; }
	public abstract GenericArray<SemanticType> parameter_types { get; }
	public abstract PointerParameterContract parameter_contract(int ordinal);
	public abstract bool has_owner_channels();
	public abstract GenericArray<PointerParameterContract> physical_contracts();
}
// Logical callable parameters share one nominal record boundary authority.
// A closure's bound environment is outside this signature; its code target
// supplies that leading parameter through the explicit offsets below.
// A declaration and its ordered application tokens carry nominal identity
// across stages without retaining any symbol, field graph or executable body.
public class RecordDefinitionIdentity : Object {
	private string identifier;
	public string name { get { return identifier; } }
	private GenericArray<RecordApplicationIdentity> applications = new GenericArray<RecordApplicationIdentity> ();
	private bool native_closed;
	private GenericArray<string> native_applications = new GenericArray<string> ();
	internal RecordDefinitionIdentity (string name, GenericArray<string>? imported_applications = null) {
		identifier = name;
		native_closed = imported_applications != null;
		if (imported_applications != null) {
			foreach (string application in imported_applications) {
				if (application.has_prefix (name + "<")) {
					native_applications.add (application);
				}
			}
		}
	}
	public string application_name(GenericArray<SemanticType> arguments) {
		var result = new StringBuilder (name + "<");
		for (int a = 0; a < arguments.length; a++) {
			result.append ((a == 0 ? "" : ",") + arguments[a].nominal_name ());
		}
		return result.str + ">";
	}
	public bool admits(GenericArray<SemanticType> arguments) {
		if (!native_closed) {
			return true;
		}
		// Symbolic declarations remain templates; every demanded concrete
		// application is checked again by Core after substitution.
		foreach (var argument in arguments) {
			if (argument.is_parameterized ()) {
				return true;
			}
		}
		string requested = application_name (arguments);
		foreach (string application in native_applications) {
			if (application == requested) {
				return true;
			}
		}
		return false;
	}
	public RecordApplicationIdentity application(GenericArray<SemanticType> arguments) {
		foreach (var prior in applications) {
			if (prior.matches (arguments)) {
				return prior;
			}
		}
		var result = new RecordApplicationIdentity (arguments);
		applications.add (result);
		return result;
	}
}
public class RecordApplicationIdentity : Object {
	private GenericArray<Object> arguments = new GenericArray<Object> ();
	internal RecordApplicationIdentity (GenericArray<SemanticType> types) {
		foreach (var type in types) {
			arguments.add (type.logical_identity);
		}
	}
	public bool matches(GenericArray<SemanticType> types) {
		if (types.length != arguments.length) {
			return false;
		}
		for (int p = 0; p < types.length; p++) {
			if (types[p].logical_identity != arguments[p]) {
				return false;
			}
		}
		return true;
	}
}
// Immutable nominal-only use. This carries no value, cleanup or stage graph.
public class ClassTypeArgument : Object {
	public ClassType owner_type { get; private set; }
	public int ordinal { get; private set; }
	public SemanticType semantic_type { get; private set; }
	internal ClassTypeArgument (ClassType owner, int ordinal, SemanticType type) {
		owner_type = owner;
		this.ordinal = ordinal;
		semantic_type = type;
	}
	public ClassTypeArgument copy() {
		return new ClassTypeArgument (owner_type, ordinal, semantic_type);
	}
	public bool matches(ExactClassGenericInstance key, ClassType owner, int ordinal) {
		return owner_type == owner && this.ordinal == ordinal && key.instance_type == owner && ordinal >= 0 && ordinal < key.arguments.length && semantic_type.logical_identity == key.arguments.at (ordinal).logical_identity;
	}
}
public class CallableTypes : Object {
	public static bool consumes(Object? target, int ordinal, SemanticType type) {
		var signature = target as FunctionValueType;
		return signature != null && ordinal >= 0 && ordinal < signature.parameter_types.length &&
		       signature.parameter_contract (ordinal) == PointerParameterContract.OWNED_TRANSFER &&
		       signature.parameter_types[ordinal] == type;
	}
	public static SemanticType result_type(SemanticType signature) {
		if (signature is FunctionValueType) {
			return ((FunctionValueType) signature).result_type;
		}
		return ((ClosureHandleType) signature).result_type;
	}
	public static SemanticType with_parameters(SemanticType original, GenericArray<SemanticType> parameters, SemanticType? mapped_result = null, ClassType? mapped_environment = null) {
		var signature = (CallableSignature) original;
		var function = original as FunctionValueType;
		var old_result = function == null ? ((ClosureHandleType) original).result_type : function.result_type;
		var actual_result = mapped_result ?? old_result;
		bool changed = actual_result != old_result;
		var old_environment = function == null ? ((ClosureHandleType) original).environment_type : null;
		var environment = mapped_environment ?? old_environment;
		changed |= environment != old_environment;
		var contracts = new GenericArray<PointerParameterContract> ();
		for (int p = 0; p < parameters.length; p++) {
			changed |= parameters[p] != signature.parameter_types[p];
			contracts.add (signature.parameter_contract (p));
		}
		if (!changed) {
			return original;
		}
		SemanticType result;
		if (function != null) {
			result = (function is CallbackType) ? (SemanticType) new CallbackType (actual_result, parameters) : new FunctionValueType (actual_result, parameters, contracts, function.result_contract);
		} else {
			var closure = (ClosureHandleType) original;
			result = new ClosureHandleType (environment, actual_result, parameters, closure.throws_type, closure.threaded, closure.actor, contracts, closure.result_contract);
		}
		bool same = actual_result.logical_identity == old_result.logical_identity;
		if (old_environment != null) {
			same &= environment.logical_identity == old_environment.logical_identity;
		}
		for (int p = 0; p < parameters.length; p++) {
			same &= parameters[p].logical_identity == signature.parameter_types[p].logical_identity;
		}
		if (same) {
			result.bind_logical_identity (original.logical_identity);
		}
		return result;
	}
}
public class CallableRecordGroups : Object {
	public static StructValueShape? complete_result(SemanticType type, CopyabilityFields fields) throws StructLeafError {
		if (!type.is_struct_storage ()) {
			return null;
		}
		bool copied = CopyabilityAuthority.of (type, fields) == Copyability.COPYABLE;
		var leaves = copied ? StructLeafOrder.enumerate (type, fields) : StructLeafOrder.enumerate_storage (type, fields);
		if (!(type is StructType)) {
			return null;
		}
		return new StructValueShape ((StructType) type, leaves, copied ? StructValueMode.COPY_VALUE : StructValueMode.MOVE_VALUE);
	}
	public static void verify_result(SemanticType type, StructValueShape? shape, CopyabilityFields fields) throws StructLeafError {
		var expected = complete_result (type, fields);
		if (expected == null ? shape != null : shape == null || shape.semantic_type != expected.semantic_type || shape.mode != expected.mode || shape.physical_buffers) {
			throw new StructLeafError.INVALID_FIELDS ("callable record result lost its exact nominal mode and logical shape");
		}
		if (shape != null) {
			shape.verify (fields);
		}
	}

	public static bool heap_parameter(CallableSignature signature, int ordinal) {
		return signature.parameter_types[ordinal] is ClassType && signature.parameter_contract (ordinal) == PointerParameterContract.OWNED_TRANSFER;
	}
	private static StructValueMode parameter_mode(CallableSignature signature, int ordinal, CopyabilityFields fields) {
		if (CopyabilityAuthority.of (signature.parameter_types[ordinal], fields) == Copyability.COPYABLE) {
			return StructValueMode.COPY_VALUE;
		}
		return signature.parameter_contract (ordinal) == PointerParameterContract.BORROWED_NOESCAPE ? StructValueMode.BORROW_VALUE : StructValueMode.MOVE_VALUE;
	}
	public static void complete(CallableSignature signature, GenericArray<StructBoundaryGroup> groups, CopyabilityFields fields) throws StructLeafError {
		if (groups.length != 0) {
			verify (signature, groups, fields);
			return;
		}
		int first = 0;
		for (int p = 0; p < signature.parameter_types.length; p++) {
			var type = signature.parameter_types[p];
			if (type.is_struct_storage ()) {
				bool copyable = CopyabilityAuthority.of (type, fields) == Copyability.COPYABLE;
				var leaves = copyable ? StructLeafOrder.enumerate (type, fields) : StructLeafOrder.enumerate_storage (type, fields);
				if (type is StructType) {
					groups.add (new StructBoundaryGroup (p, first, new StructValueShape ((StructType) type, leaves, parameter_mode (signature, p, fields))));
				}
				first += (int) leaves.length;
			} else {
				first++;
			}
		}
		verify (signature, groups, fields);
	}
	public static void verify(CallableSignature signature, GenericArray<StructBoundaryGroup> groups, CopyabilityFields fields, int source_offset = 0, int physical_offset = 0) throws StructLeafError {
		int first = physical_offset;
		int group = 0;
		for (int p = 0; p < signature.parameter_types.length; p++) {
			var type = signature.parameter_types[p];
			var contract = signature.parameter_contract (p);
			if (type.is_struct_storage () && !(type is StructType)) {
				if (contract != PointerParameterContract.UNMANAGED && !(contract == PointerParameterContract.BORROWED_NOESCAPE && parameter_mode (signature, p, fields) == StructValueMode.BORROW_VALUE)) {
					throw new StructLeafError.INVALID_FIELDS ("record application requires its exact copied callable channel");
				}
				// Closed applications are checked against this stage's field graph.
				// Their concrete nominal group is derived after materialization.
				first += (int) (CopyabilityAuthority.of (type, fields) == Copyability.COPYABLE ? StructLeafOrder.enumerate (type, fields) : StructLeafOrder.enumerate_storage (type, fields)).length;
			} else if (type is StructType) {
				if ((contract != PointerParameterContract.UNMANAGED && !(contract == PointerParameterContract.BORROWED_NOESCAPE && parameter_mode (signature, p, fields) == StructValueMode.BORROW_VALUE)) || group >= groups.length || groups[group].source_ordinal != p + source_offset || groups[group].first_leaf != first || groups[group].shape.semantic_type != type || groups[group].shape.mode != parameter_mode (signature, p, fields)) {
					throw new StructLeafError.INVALID_FIELDS ("callable record parameter lost its exact nominal ordered group");
				}
				groups[group].shape.verify (fields);
				first += (int) groups[group++].shape.leaves.length;
			} else {
				if (!((FunctionValueType.scalar (type) || FunctionValueType.symbolic_copy (type)) && contract == PointerParameterContract.UNMANAGED) && !(contract == PointerParameterContract.BORROWED_NOESCAPE && (type is ClassType || type.get_type () == typeof (HandleType) || GenericBorrowTypes.symbolic (type))) && !(contract == PointerParameterContract.OWNED_TRANSFER && (type is ClassType || type.get_type () == typeof (HandleType) || GenericBorrowTypes.symbolic (type)))) {
					throw new StructLeafError.INVALID_FIELDS ("callable parameter is outside its exact copied or borrowed signature");
				}
				first++;
			}
		}
		if (group != groups.length) {
			throw new StructLeafError.INVALID_FIELDS ("callable signature contains an extra record group");
		}
	}
	public static GenericArray<SemanticType> physical_parameters(CallableSignature signature, GenericArray<StructBoundaryGroup> groups) {
		var result = new GenericArray<SemanticType> ();
		int group = 0;
		for (int p = 0; p < signature.parameter_types.length; p++) {
			if (signature.parameter_types[p].is_struct_storage () && !(signature.parameter_types[p] is StructType)) {
				return result;
			}
			if (signature.parameter_types[p] is StructType) {
				if (group >= groups.length) {
					return result;
				}
				foreach (var leaf in groups[group++].shape.leaves) {
					result.add (leaf.semantic_type);
				}
			} else {
				result.add (signature.parameter_types[p]);
			}
		}
		return result;
	}
	public static bool borrowed_record_leaf(GenericArray<StructBoundaryGroup> groups, int ordinal) {
		foreach (var group in groups) {
			if (group.shape.mode == StructValueMode.BORROW_VALUE && ordinal >= group.first_leaf && ordinal < group.first_leaf + group.shape.leaves.length) {
				return true;
			}
		}
		return false;
	}
	public static GenericArray<PointerParameterContract> physical_contracts(CallableSignature signature, GenericArray<StructBoundaryGroup> groups) {
		var result = new GenericArray<PointerParameterContract> ();
		int group = 0;
		for (int p = 0; p < signature.parameter_types.length; p++) {
			if (signature.parameter_types[p].is_struct_storage () && !(signature.parameter_types[p] is StructType)) {
				return result;
			}
			if (signature.parameter_types[p] is StructType) {
				if (group >= groups.length) {
					return result;
				}
				var shape = groups[group++].shape;
				foreach (var leaf in shape.leaves) {
					bool borrowed = shape.mode == StructValueMode.BORROW_VALUE && (leaf.semantic_type is ClassType || leaf.semantic_type is HandleType || leaf.semantic_type is SliceType);
					result.add (borrowed ? PointerParameterContract.BORROWED_NOESCAPE : PointerParameterContract.UNMANAGED);
				}
			} else {
				result.add (signature.parameter_contract (p));
			}
		}
		return result;
	}
}
public class FunctionValueType : SemanticType, CallableSignature {
	private ResultOwnershipContract result_ownership;
	public ResultOwnershipContract result_contract { get { return result_ownership; } }
	public SemanticType result_type { get; private set; }
	private StructValueShape? result_shape;
	public StructValueShape? record_result { get { return result_shape; } }
	private GenericArray<SemanticType> declared_parameters;
	public GenericArray<SemanticType> parameter_types { get { return declared_parameters; } }
	private GenericArray<PointerParameterContract> parameter_contracts = new GenericArray<PointerParameterContract> ();
	public PointerParameterContract parameter_contract(int ordinal) {
		return parameter_contracts[ordinal];
	}
	public GenericArray<StructBoundaryGroup> record_parameters { get; private set; default = new GenericArray<StructBoundaryGroup> (); }
	internal FunctionValueType (SemanticType result, GenericArray<SemanticType> parameters, GenericArray<PointerParameterContract>? contracts = null, ResultOwnershipContract result_contract = ResultOwnershipContract.UNMANAGED, TypeKind kind = TypeKind.FUNCTION_VALUE) {
		base (kind);
		result_ownership = result_contract;
		result_type = result;
		declared_parameters = parameters;
		for (int p = 0; p < parameters.length; p++) {
			parameter_contracts.add (contracts == null ? PointerParameterContract.UNMANAGED : contracts[p]);
		}
	}
	public static bool supported_result(SemanticType type, ResultOwnershipContract contract) {
		return contract == ResultOwnershipContract.UNMANAGED && (type.kind == TypeKind.VOID || scalar (type) || symbolic_copy (type) || type.is_struct_storage ()) || contract == ResultOwnershipContract.OWNED_TRANSFER && (GenericBorrowTypes.symbolic (type) || type.get_type () == typeof (HandleType) || type is ClassType && !((ClassType) type).is_interface && (!(type is ExactGenericClassType) || GenericClassTypes.general (type)));
	}
	public static bool symbolic_copy(SemanticType type) {
		return type is TypeParameterType && ((TypeParameterType) type).transport_mode == GenericTransportMode.PLAIN_COPY;
	}
	public static bool scalar(SemanticType type) {
		return type is IntegerType || type is FloatingType || type.kind == TypeKind.BOOL;
	}
	public override bool is_parameterized() {
		if (result_type.is_parameterized ()) {
			return true;
		}
		foreach (var parameter in parameter_types) {
			if (parameter.is_parameterized ()) {
				return true;
			}
		}
		return false;
	}
	internal override SemanticType substitute(TypeSubstitution substitution) {
		return substitution.function (this);
	}
	public override string? generic_definition_name() {
		return (this is CallbackType) ? "Callback" : "Fn";
	}
	public override TypeArgumentVector? generic_arguments() {
		var values = new GenericArray<SemanticType> ();
		values.add (result_type);
		foreach (var parameter in parameter_types) {
			values.add (parameter);
		}
		return new TypeArgumentVector (values);
	}
	internal void complete_records(CopyabilityFields fields) throws StructLeafError {
		if (parameter_contracts.length != parameter_types.length) {
			throw new StructLeafError.INVALID_FIELDS ("function signature lost its complete parameter channel contracts");
		}
		CallableRecordGroups.complete (this, record_parameters, fields);
		result_shape = CallableRecordGroups.complete_result (result_type, fields);
	}
	public void verify_records(GenericArray<StructBoundaryGroup> groups, CopyabilityFields fields) throws StructLeafError {
		if (parameter_contracts.length != parameter_types.length) {
			throw new StructLeafError.INVALID_FIELDS ("function signature lost its complete parameter channel contracts");
		}
		CallableRecordGroups.verify (this, groups, fields);
		CallableRecordGroups.verify_result (result_type, result_shape, fields);
	}
	public bool has_owner_channels() {
		for (int p = 0; p < parameter_contracts.length; p++) {
			if (parameter_contracts[p] != PointerParameterContract.UNMANAGED) {
				return true;
			}
		}
		return false;
	}
	public GenericArray<PointerParameterContract> physical_contracts() {
		return CallableRecordGroups.physical_contracts (this, record_parameters);
	}
	public GenericArray<SemanticType> physical_parameters() {
		return CallableRecordGroups.physical_parameters (this, record_parameters);
	}
	public string signature_name(bool nominal = false) {
		string name = ((this is CallbackType) ? "Callback<" : "Fn<") + (result_contract == ResultOwnershipContract.OWNED_TRANSFER ? "owned " : "") + (nominal ? result_type.nominal_name () : result_type.display_name ());
		for (int p = 0; p < parameter_types.length; p++) {
			name += "," + (parameter_contract (p) == PointerParameterContract.BORROWED_NOESCAPE ? "borrowed " : parameter_contract (p) == PointerParameterContract.OWNED_TRANSFER ? "owned " : "") + (nominal ? parameter_types[p].nominal_name () : parameter_types[p].display_name ());
		}
		return name + ">";
	}
}

// A borrowed code/context view. It never owns an environment and cannot be
// stored, returned or captured. Fn remains a distinct copied native code PTR.
public class CallbackType : FunctionValueType {
	internal CallbackType (SemanticType result, GenericArray<SemanticType> parameters) {
		base (result, parameters, null, ResultOwnershipContract.UNMANAGED, TypeKind.CALLBACK);
	}
	public bool matches_closure(SemanticType source) {
		var closure = source as ClosureHandleType;
		if (closure == null || !supported () || closure.threaded || closure.actor || closure.throws_type != null || closure.result_contract != ResultOwnershipContract.UNMANAGED || closure.result_type != result_type || closure.parameter_types.length != parameter_types.length) {
			return false;
		}
		for (int p = 0; p < parameter_types.length; p++) {
			if (closure.parameter_types[p] != parameter_types[p] || closure.parameter_contract (p) != PointerParameterContract.UNMANAGED) {
				return false;
			}
		}
		return true;
	}
	public static SemanticType borrowed_type(SemanticType source, SemanticType? target) {
		return (source is ClosureHandleType && target is CallbackType) ? target : source;
	}
	public static bool copied(SemanticType type) {
		return type.kind == TypeKind.INT || type.kind == TypeKind.U32 || type.kind == TypeKind.I64 || type.kind == TypeKind.U64 || type.kind == TypeKind.F32 || type.kind == TypeKind.F64 || type.kind == TypeKind.BOOL || FunctionValueType.symbolic_copy (type);
	}
	public bool supported() {
		if (result_contract != ResultOwnershipContract.UNMANAGED || result_type.kind != TypeKind.VOID && !copied (result_type) || parameter_types.length > 256) {
			return false;
		}
		for (int p = 0; p < parameter_types.length; p++) {
			if (!copied (parameter_types[p]) || parameter_contract (p) != PointerParameterContract.UNMANAGED) {
				return false;
			}
		}
		return true;
	}
}

public enum GenericCapability {
	GEN1_PLAIN_COPY, OWNABLE
}
public enum GenericTransportMode {
	PLAIN_COPY, OWNABLE
}

public class TypeParameterType : SemanticType {
	private string identifier;
	public string name { get { return identifier; } }
	public GenericTransportMode transport_mode { get { return explicit_capabilities.contains (GenericCapabilityIdentity.OWNABLE) ? GenericTransportMode.OWNABLE : GenericTransportMode.PLAIN_COPY; } }
	public GenericCapability capability { get { return transport_mode == GenericTransportMode.PLAIN_COPY ? GenericCapability.GEN1_PLAIN_COPY : GenericCapability.OWNABLE; } }
	public GenericCapabilitySet explicit_capabilities { get; private set; }
	internal TypeParameterType (string name, GenericCapabilitySet? capabilities = null) {
		base (TypeKind.TYPE_PARAMETER);
		this.identifier = name;
		this.explicit_capabilities = capabilities ?? new GenericCapabilitySet ();
	}
}

public class GenericArgumentTypes : Object {
	public static bool plain_copy(SemanticType type, CopyabilityFields? fields = null, CopyabilityPremise? premise = null) {
		return (fields == null ? CopyabilityAuthority.value_copy (type, (aggregate) => null, premise) : CopyabilityAuthority.value_copy (type, fields, premise)) == Copyability.COPYABLE;
	}
	public static bool accepts(TypeParameterType parameter, SemanticType type, CopyabilityFields? fields = null, CopyabilityPremise? premise = null) {
		return parameter.transport_mode == GenericTransportMode.OWNABLE ? GenericCapabilityAuthority.satisfies (type, GenericCapabilityIdentity.OWNABLE) : plain_copy (type, fields, premise);
	}
	public static bool supports(SemanticType type, CopyabilityFields? fields = null) {
		return !type.is_parameterized () && plain_copy (type, fields);
	}
}

// One exact substitution authority shared by checking and Core. Only generic
// aggregate applications, callable signatures and direct slices participate.
// T* and T[N] remain unsupported. Stages retain their own canonical interning.
public delegate SliceType SliceSubstitution(SemanticType element);
public delegate FunctionValueType FunctionSubstitution(FunctionValueType original, GenericArray<SemanticType> parameters, SemanticType result);
public delegate ClosureHandleType ClosureSubstitution(ClosureHandleType original, ClassType environment, GenericArray<SemanticType> parameters, SemanticType result);
public delegate ExactGenericClassType ClassSubstitution(ExactGenericClassType original, TypeArgumentVector arguments);
// A specialization records storage by parameter position, including when
// several parameters have the same nominal type. Trailing caller-backed
// positions do not distinguish keys for the same declared function.
public class GenericStorageVector : Object {
	private int[] heap_inputs;
	public int count { get { return heap_inputs.length; } }
	public int parameter(int position) {
		return heap_inputs[position];
	}
	public GenericStorageVector (bool[] heap_parameters) {
		for (int p = 0; p < heap_parameters.length; p++) {
			if (heap_parameters[p]) {
				heap_inputs += p;
			}
		}
	}
	public GenericStorageVector.single (int parameter = -1) {
		if (parameter != -1) {
			heap_inputs += parameter;
		}
	}
	public bool is_heap(int parameter) {
		foreach (int input in heap_inputs) {
			if (input == parameter) {
				return true;
			}
		}
		return false;
	}
	public bool valid(int parameters) {
		foreach (int input in heap_inputs) {
			if (input < 0 || input >= parameters) {
				return false;
			}
		}
		return parameters >= 0;
	}
	public bool same(GenericStorageVector other) {
		if (heap_inputs.length != other.heap_inputs.length) {
			return false;
		}
		for (int p = 0; p < heap_inputs.length; p++) {
			if (heap_inputs[p] != other.heap_inputs[p]) {
				return false;
			}
		}
		return true;
	}
	public uint identity_hash() {
		uint result = 5381;
		foreach (int input in heap_inputs) {
			result = result * 33 + (uint) input;
		}
		return result;
	}
}

// Hashes accelerate canonical lookup only. Exact ordered identities and the
// ownership storage variant still decide equality, including on collisions.
public class GenericRequestKey : Object {
	private Object definition;
	private TypeArgumentVector arguments;
	private GenericStorageVector storage;
	public GenericRequestKey (Object definition, TypeArgumentVector arguments, int storage_variant = -1, GenericStorageVector? storage = null) {
		this.definition = definition;
		this.arguments = arguments;
		this.storage = storage ?? new GenericStorageVector.single (storage_variant);
	}
	public static uint hash(GenericRequestKey key) {
		return (direct_hash (key.definition) * 33 + key.arguments.identity_hash ()) * 33 + key.storage.identity_hash ();
	}
	public static bool equal(GenericRequestKey left, GenericRequestKey right) {
		return left.definition == right.definition && left.storage.same (right.storage) && left.arguments.matches (right.arguments);
	}
}

// Ordered canonical type identities, never display-name keys. The private
// copy cannot be mutated through a caller's argument worklist.
public class TypeArgumentVector : Object {
	private GenericArray<SemanticType> values = new GenericArray<SemanticType> ();
	public uint length { get { return values.length; } }

	public TypeArgumentVector (GenericArray<SemanticType> arguments) {
		values = new GenericArray<SemanticType> (arguments.length);
		foreach (var argument in arguments) {
			values.add (argument);
		}
	}

	public TypeArgumentVector.single (SemanticType argument) {
		values.add (argument);
	}

	public unowned SemanticType at(int ordinal) {
		return values[ordinal];
	}

	public bool matches(TypeArgumentVector other) {
		return same_values (values, other.values);
	}
	public uint identity_hash() {
		uint result = length;
		foreach (var type in values) {
			result = result * 33 + direct_hash (type);
		}
		return result;
	}

	// A symbolic aggregate application and its physical record share the
	// same nominal token after materialization, while their stage types differ.
	public bool matches_identities(TypeArgumentVector other) {
		if (length != other.length) {
			return false;
		}
		for (int a = 0; a < length; a++) {
			if (at (a).logical_identity != other.at (a).logical_identity) {
				return false;
			}
		}
		return true;
	}

	public bool matches_array(GenericArray<SemanticType> other) {
		return same_values (values, other);
	}

	public static bool same_values(GenericArray<SemanticType> left, GenericArray<SemanticType> right) {
		if (left.length != right.length) {
			return false;
		}
		for (int i = 0; i < left.length; i++) {
			if (left[i] != right[i]) {
				return false;
			}
		}
		return true;
	}

	public bool closed() {
		foreach (var argument in values) {
			if (argument.is_parameterized ()) {
				return false;
			}
		}
		return true;
	}

	public GenericArray<SemanticType> copy_values() {
		var result = new GenericArray<SemanticType> (values.length);
		foreach (var argument in values) {
			result.add (argument);
		}
		return result;
	}

	public string display_suffix(bool nominal = false) {
		var text = new StringBuilder ("<");
		for (int i = 0; i < values.length; i++) {
			if (i != 0) {
				text.append (",");
			}
			text.append (nominal ? values[i].nominal_name () : values[i].display_name ());
		}
		text.append (">");
		return text.str;
	}
}

// Declarative result-origin equation. An owned Class result may originate
// intrinsically in heap/caller storage or depend on particular owned inputs.
// No parameter, function, place or predecessor-stage object is retained.
public class GenericResultOrigins : Object {
	public const uint CALLER = 1;
	public const uint HEAP = 2;
	public const uint UNKNOWN = 4;
	public uint domains { get; private set; }
	public bool captured_caller { get; private set; }
	private int[] inputs;
	public int input_count { get { return inputs.length; } }
	public int input(int position) {
		return inputs[position];
	}

	public GenericResultOrigins (uint domains = 0, int[]? inputs = null, bool captured_caller = false) {
		this.domains = domains;
		this.captured_caller = captured_caller;
		this.inputs = inputs == null ? null : inputs.copy ();
	}
	public GenericResultOrigins captured() {
		return new GenericResultOrigins (domains, inputs, captured_caller || (domains & CALLER) != 0);
	}
	public GenericResultOrigins union(GenericResultOrigins other) {
		int[] merged = inputs.copy ();
		foreach (var ordinal in other.inputs) {
			bool present = false;
			foreach (var prior in merged) {
				present |= prior == ordinal;
			}
			if (!present) {
				merged += ordinal;
			}
		}
		return new GenericResultOrigins (domains | other.domains, merged, captured_caller || other.captured_caller);
	}
	public bool same(GenericResultOrigins other) {
		if (domains != other.domains || captured_caller != other.captured_caller || inputs.length != other.inputs.length) {
			return false;
		}
		foreach (var ordinal in inputs) {
			bool present = false;
			foreach (var candidate in other.inputs) {
				present |= candidate == ordinal;
			}
			if (!present) {
				return false;
			}
		}
		return true;
	}
	public GenericResultOrigins compose(GenericArray<GenericResultOrigins> arguments) {
		var result = new GenericResultOrigins (domains, null, captured_caller);
		foreach (var ordinal in inputs) {
			if (ordinal < 0 || ordinal >= arguments.length) {
				return new GenericResultOrigins (UNKNOWN);
			}
			result = result.union (arguments[ordinal]);
		}
		return result;
	}
	public uint evaluate(bool[] heap_arguments) {
		uint result = domains;
		foreach (var ordinal in inputs) {
			if (ordinal < 0 || ordinal >= heap_arguments.length) {
				return UNKNOWN;
			}
			result |= heap_arguments[ordinal] ? HEAP : CALLER;
		}
		return result;
	}
}

public class TypeSubstitution : Object {
	private HashTable<TypeParameterType, SemanticType> bindings = new HashTable<TypeParameterType, SemanticType> (direct_hash, direct_equal);
	private SliceSubstitution? slices;
	private FunctionSubstitution? functions;
	private ClassSubstitution? classes;
	private ClosureSubstitution? closures;
	private HashTable<ExactGenericClassType, ExactGenericClassType> class_types = new HashTable<ExactGenericClassType, ExactGenericClassType> (direct_hash, direct_equal);
	private HashTable<FunctionValueType, FunctionValueType> function_types = new HashTable<FunctionValueType, FunctionValueType> (direct_hash, direct_equal);
	private HashTable<ClosureHandleType, ClosureHandleType> closure_types = new HashTable<ClosureHandleType, ClosureHandleType> (direct_hash, direct_equal);
	public TypeSubstitution (owned SliceSubstitution? slices = null, owned FunctionSubstitution? functions = null, owned ClassSubstitution? classes = null, owned ClosureSubstitution? closures = null) {
		this.slices = (owned) slices;
		this.functions = (owned) functions;
		this.classes = (owned) classes;
		this.closures = (owned) closures;
	}
	internal ExactGenericClassType class_type(ExactGenericClassType original) {
		var prior = class_types.lookup (original);
		if (prior != null) {
			return prior;
		}
		var arguments = new TypeArgumentVector (apply_arguments (original.arguments.copy_values ()));
		if (original.arguments.matches (arguments)) {
			return original;
		}
		var mapped = classes == null ? new ExactGenericClassType.application (original.definition, arguments) : classes (original, arguments);
		class_types.insert (original, mapped);
		return mapped;
	}
	internal FunctionValueType function(FunctionValueType original) {
		var prior = function_types.lookup (original);
		if (prior != null) {
			return prior;
		}
		var parameters = apply_arguments (original.parameter_types);
		var result = apply (original.result_type);
		var mapped = functions == null ? (FunctionValueType) CallableTypes.with_parameters (original, parameters, result) : functions (original, parameters, result);
		function_types.insert (original, mapped);
		return mapped;
	}
	internal SliceType slice(SliceType original) {
		var element = apply (original.element_type);
		return element == original.element_type ? original : slices == null ? new SliceType (element) : slices (element);
	}
	internal ClosureHandleType closure(ClosureHandleType original) {
		var prior = closure_types.lookup (original);
		if (prior != null) {
			return prior;
		}
		var environment = (ClassType) apply (original.environment_type);
		var parameters = apply_arguments (original.parameter_types);
		var result = apply (original.result_type);
		var mapped = closures == null ? (ClosureHandleType) CallableTypes.with_parameters (original, parameters, result, environment) : closures (original, environment, parameters, result);
		closure_types.insert (original, mapped);
		return mapped;
	}
	public bool matches(SemanticType formal, SemanticType actual) {
		if (formal is SliceType) {
			return actual is SliceType && matches (((SliceType) formal).element_type, ((SliceType) actual).element_type);
		}
		if (formal is ExactGenericClassType) {
			var expected = (ExactGenericClassType) formal;
			var found = actual as ExactGenericClassType;
			if (found == null || expected.definition != found.definition || expected.arguments.length != found.arguments.length) {
				return false;
			}
			for (int p = 0; p < expected.arguments.length; p++) {
				if (!matches (expected.arguments.at (p), found.arguments.at (p))) {
					return false;
				}
			}
			return true;
		}
		if (formal is FunctionValueType) {
			var expected = (FunctionValueType) formal;
			var found = actual as FunctionValueType;
			if (found == null || (expected is CallbackType) != (found is CallbackType) || expected.result_contract != found.result_contract || expected.parameter_types.length != found.parameter_types.length || !matches (expected.result_type, found.result_type)) {
				return false;
			}
			for (int p = 0; p < expected.parameter_types.length; p++) {
				if (expected.parameter_contract (p) != found.parameter_contract (p) || !matches (expected.parameter_types[p], found.parameter_types[p])) {
					return false;
				}
			}
			return true;
		}
		if (formal is ClosureHandleType) {
			var expected = (ClosureHandleType) formal;
			var found = actual as ClosureHandleType;
			if (found == null || expected.threaded != found.threaded || expected.actor != found.actor
			    || expected.throws_type != found.throws_type || expected.result_contract != found.result_contract
			    || expected.parameter_types.length != found.parameter_types.length
			    || !matches (expected.environment_type, found.environment_type)
			    || !matches (expected.result_type, found.result_type)) {
				return false;
			}
			for (int p = 0; p < expected.parameter_types.length; p++) {
				if (expected.parameter_contract (p) != found.parameter_contract (p)
				    || !matches (expected.parameter_types[p], found.parameter_types[p])) {
					return false;
				}
			}
			return true;
		}
		return apply (formal) == actual;
	}
	public void bind(TypeParameterType parameter, SemanticType argument) {
		assert (!bindings.contains (parameter));
		bindings.insert (parameter, argument);
		function_types.remove_all ();
		closure_types.remove_all ();
		class_types.remove_all ();
	}
	public SemanticType apply(SemanticType type) {
		return (type is TypeParameterType) ? (bindings.lookup ((TypeParameterType) type) ?? type) : type.substitute (this);
	}
	public GenericArray<SemanticType> apply_arguments(GenericArray<SemanticType> arguments) {
		var result = new GenericArray<SemanticType> ();
		foreach (var argument in arguments) {
			result.add (apply (argument));
		}
		return result;
	}
}

// Compiler-owned receiver contract, never a source pointer or whole-struct value.
public enum CallableKind {
	FUNCTION, METHOD, CONSTRUCTOR, DESTRUCTOR, PROPERTY_GETTER, PROPERTY_SETTER
}

// The plain native parameter/result intersection, excluding deferred handle contracts.
public class PropertyValueTypes : Object {
	public static bool supports_cache(SemanticType type) {
		return !(type is StringType) && supports (type);
	}
	public static bool supports(SemanticType type, CopyabilityFields? fields = null) {
		return type is StringType || type is IntegerType || type is FloatingType || type.kind == TypeKind.BOOL || type.is_void_pointer () || (type is VectorType && VectorType.supports (((VectorType) type).element_type, ((VectorType) type).lane_count)) || type.is_struct_storage () && fields != null && GenericArgumentTypes.plain_copy (type, fields);
	}
}

public enum ReceiverMode {
	LIVE, INITIALIZING
}

public class ReceiverType : SemanticType {
	public ReceiverMode mode { get; private set; }
	public SemanticType instance_type { get; private set; }
	public bool is_nonnull { get { return true; } }
	public bool is_mutable { get { return true; } }
	public bool is_owning { get { return false; } }

	internal ReceiverType (SemanticType instance_type, ReceiverMode mode = ReceiverMode.LIVE) {
		base (TypeKind.RECEIVER);
		this.instance_type = instance_type;
		this.mode = mode;
	}
}

public enum SliceElementAccess {
	READ, READ_WRITE
}
// One non-null, non-owning bounded view value. Runtime extent is not type identity.
public class SliceType : SemanticType {
	public SemanticType element_type { get; private set; }
	public SliceElementAccess element_access { get { return (element_type is StringType) ? SliceElementAccess.READ : SliceElementAccess.READ_WRITE; } }
	public bool deep_borrow { get { return element_type is StringType; } }

	internal SliceType (SemanticType element_type) {
		base (TypeKind.SLICE);
		this.element_type = element_type;
	}

	public override bool is_parameterized() {
		return element_type.is_parameterized ();
	}
	internal override SemanticType substitute(TypeSubstitution substitution) {
		return substitution.slice (this);
	}
	public static bool supports(SemanticType element) {
		return element is StringType || BufferElementTypes.candidate (element);
	}
	public SemanticType canonical_key() {
		var bytes = this as ContextBytesType;
		return bytes == null ? element_type : (SemanticType) bytes.allocator_type;
	}
}
// A distinct owning byte pair keeps its original context release authority.
// Ordinary borrowed u8[] views may observe it without acquiring that authority.
public class ContextBytesType : SliceType {
	public HandleType allocator_type { get; private set; }
	public string context_mode { get { return allocator_type.context_mode; } }
	internal ContextBytesType (SemanticType element, HandleType allocator_type) {
		base (element);
		this.allocator_type = allocator_type;
	}
	public bool valid() {
		return element_type.kind == TypeKind.U8 && (context_mode == "owned-concurrent" || context_mode == "owned-affine" || context_mode == "owned-transfer");
	}
	public override string display_name() {
		return "ContextBytes<" + allocator_type.display_name () + ">";
	}
	public override string? generic_definition_name() {
		return "ContextBytes";
	}
	public override TypeArgumentVector? generic_arguments() {
		return new TypeArgumentVector.single (allocator_type);
	}
	internal override SemanticType substitute(TypeSubstitution substitution) {
		return this;
	}
	public static bool permits_view(SemanticType owner, SemanticType view) {
		return owner is ContextBytesType && ((ContextBytesType) owner).valid () && view is SliceType && !(view is ContextBytesType) && ((SliceType) view).element_type == ((ContextBytesType) owner).element_type;
	}
	public static SemanticType borrowed_type(SemanticType owner, SemanticType? requested) {
		return requested != null && permits_view (owner, requested) ? requested : owner;
	}
}

// Contiguous local storage identity; never a value, pointer, vector or ABI type.
public class ArrayType : SemanticType {
	public SemanticType element_type { get; private set; }
	public int length { get; private set; }
	public const int MAX_LENGTH = 1024;

	internal ArrayType (SemanticType element_type, int length) {
		base (TypeKind.ARRAY);
		this.element_type = element_type;
		this.length = length;
	}

	public static bool supports(SemanticType element, int length) {
		return length >= 1 && length <= MAX_LENGTH && (element.is_directly_dereferenceable_value_type () || (element.is_struct_storage () && !element.is_parameterized ()));
	}
}

// One exact value identity. Shape is a milestone capability, not storage or
// hardware width. No stage, syntax, symbol, ABI, or backend backlink.
public class VectorType : SemanticType {
	public SemanticType element_type { get; private set; }
	public int lane_count { get; private set; }
	public bool is_mask { get { return element_type.kind == TypeKind.BOOL; } }

	internal VectorType (SemanticType element_type, int lane_count) {
		base (TypeKind.VECTOR);
		this.element_type = element_type;
		this.lane_count = lane_count;
	}

	public static bool supports(SemanticType element, int lanes) {
		if (lanes != 2 && lanes != 4 && lanes != 8 && lanes != 16) {
			return false;
		}
		if (element.kind == TypeKind.BOOL) {
			return true;
		}
		if (element is F32Type) {
			return lanes <= 4;
		}
		if (element is F64Type) {
			return lanes == 2;
		}
		// Exact fixed-width two-lane 64-bit channels share the 128-bit family.
		// Pointer-sized integers remain scalar target-dependent aliases.
		return element is IntegerType && element.kind != TypeKind.ISIZE && element.kind != TypeKind.USIZE && ((IntegerType) element).bit_width * lanes <= 128;
	}
}

// Exact scalar format authority; concrete identities remain nominal.
public abstract class FloatingType : SemanticType {
	public BinaryFloatFormat format { get; private set; }
	internal FloatingType (TypeKind kind, BinaryFloatFormat format) {
		base (kind);
		this.format = format;
	}
}

public class F64Type : FloatingType {
	internal F64Type () {
		base (TypeKind.F64, BinaryFloatFormat.BINARY64);
	}
}

// Exactly one immutable binary32 identity per BuiltinTypes universe.
public class F32Type : FloatingType {
	internal F32Type () {
		base (TypeKind.F32, BinaryFloatFormat.BINARY32);
	}
}

// Exact immutable identities per BuiltinTypes universe. The legacy INT tag
// denotes I32. No host/target ABI sizes enter fixed-width source identity.
public class IntegerType : SemanticType {
	public bool is_signed { get { return kind == TypeKind.I8 || kind == TypeKind.I16 || kind == TypeKind.INT || kind == TypeKind.I64 || kind == TypeKind.ISIZE; } }
	public uint bit_width { get { return kind == TypeKind.I8 || kind == TypeKind.U8 ? 8 : kind == TypeKind.I16 || kind == TypeKind.U16 ? 16 : kind == TypeKind.I64 || kind == TypeKind.U64 || kind == TypeKind.ISIZE || kind == TypeKind.USIZE ? 64 : 32; } }
	// Legacy narrow-oracle convenience; 2^64 has no uint64 representation.
	public uint64 modulus {
		get {
			assert (bit_width < 64);
			return ((uint64) 1) << bit_width;
		}
	}
	public uint64 sign_bit { get { return ((uint64) 1) << (bit_width - 1); } }
	public uint64 mask { get { return bit_width == 64 ? uint64.MAX : (((uint64) 1) << bit_width) - 1; } }
	public int64 minimum { get { return !is_signed ? 0 : bit_width == 64 ? int64.MIN : -(int64) sign_bit; } }
	public uint64 maximum { get { return is_signed ? sign_bit - 1 : mask; } }

	internal IntegerType (TypeKind kind) {
		base (kind);
		assert (kind == TypeKind.INT || kind == TypeKind.I8 || kind == TypeKind.U8 || kind == TypeKind.I16 || kind == TypeKind.U16 || kind == TypeKind.U32 || kind == TypeKind.I64 || kind == TypeKind.U64 || kind == TypeKind.ISIZE || kind == TypeKind.USIZE);
	}
}

// Exact nominal identity, with no syntax, symbol, cleanup or stage backlink.
// The declaring symbol and each IR stage own their separate contract descriptor.
public class HandleType : SemanticType {
	private string context_contract;
	public string context_mode { get { return context_contract; } }
	private string context_release;
	public string context_cleanup { get { return context_release; } }
	private string admitted_foreign_identity = "";
	public string foreign_policy_identity { get { return admitted_foreign_identity; } }
	private string identifier;
	public string name { get { return identifier; } }

	internal HandleType (string name, string foreign_identity = "", string context_mode = "", string context_cleanup = "") {
		base (TypeKind.HANDLE);
		this.admitted_foreign_identity = foreign_identity;
		this.identifier = name;
		this.context_contract = context_mode;
		this.context_release = context_cleanup;
	}
}

// Canonical nominal reference identity. It owns no declaration or layout.
public enum ClassDispatchKind {
	DIRECT, VIRTUAL, OVERRIDE
}

public class NonNullReferenceTypes : Object {
	public static bool supports(SemanticType type) {
		return type is FunctionValueType || (type is HandleType && !(type is SharedHandleType) && !(type is ClosureHandleType)) || (type is ClassType && (!(type is ExactGenericClassType) || GenericClassTypes.general (type)) && !type.is_parameterized ());
	}
}

public class ClassType : SemanticType {
	private string foreign_identity = "";
	private bool foreign_bound;
	public string foreign_policy_identity { get { return foreign_identity; } }
	public bool bind_foreign_policy(string identity) {
		if (foreign_bound) {
			return foreign_identity == identity;
		}
		foreign_identity = identity;
		foreign_bound = true;
		return true;
	}
	private uint concurrency_identity;
	private bool concurrency_bound;
	public uint concurrency_policy_identity { get { return concurrency_identity; } }
	public bool intrinsically_shared { get { return (concurrency_identity & (uint) ConcurrencyKind.SHARED) != 0; } }
	public bool thread_bound { get { return (concurrency_identity & (uint) ConcurrencyKind.THREAD_BOUND) != 0; } }
	public bool monitored { get { return (concurrency_identity & (uint) ConcurrencyKind.MONITOR) != 0; } }
	public bool bind_concurrency_policy(uint identity) {
		if (concurrency_bound) {
			return concurrency_identity == identity;
		}
		concurrency_identity = identity;
		concurrency_bound = true;
		return true;
	}
	private string allocation_identity = "";
	private bool allocation_bound;
	public string allocation_policy_identity { get { return allocation_identity; } }
	public bool bind_allocation_policy(string identity) {
		if (allocation_bound) {
			return allocation_identity == identity;
		}
		allocation_identity = identity;
		allocation_bound = true;
		return true;
	}
	// A fieldless, nonconstructible nominal contract; its physical borrowed
	// receiver uses the existing pay-for-use native Class dispatch channel.
	public bool is_interface { get; internal set; default = false; }
	public ClassType? parent_type { get; internal set; }
	public bool derives_from(ClassType ancestor) {
		var seen = new HashTable<ClassType, bool> (direct_hash, direct_equal);
		for (ClassType? current = this; current != null; current = current.parent_type) {
			if (current == ancestor) {
				return true;
			}
			if (seen.contains (current)) {
				return false;
			}
			seen.insert (current, true);
		}
		return false;
	}
	private string identifier;
	public string name { get { return identifier; } }

	internal ClassType (string name) {
		base (TypeKind.CLASS);
		this.identifier = name;
	}
}

// The single native field authority, shared by structs and classes.
public class NativeFieldTypes : Object {
	public static bool supports(SemanticType type, bool struct_owner = false) {
		return type is IntegerType || type is FloatingType || type.kind == TypeKind.BOOL || type is FunctionValueType || type.is_void_pointer () || (struct_owner && ((type.is_struct_storage () && !type.is_parameterized ()) || type is VectorType));
	}
}

// Declared identity only. No symbol, syntax, fields, layout, or ABI backlink.
// Its declaring StructSymbol owns this canonical type; IR may retain it.
public class StructType : SemanticType {
	public OwnedRecordApplicationContract? owning_application { get; private set; }
	internal void bind_owning_application(OwnedRecordApplicationContract contract) {
		assert (owning_application == null);
		owning_application = contract;
	}
	private RecordDefinitionIdentity? generic_origin;
	private TypeArgumentVector? generic_values;
	internal void bind_generic_application(RecordDefinitionIdentity origin, GenericArray<SemanticType> arguments) {
		assert (generic_origin == null);
		generic_origin = origin;
		generic_values = new TypeArgumentVector (arguments);
		bind_logical_identity (origin.application (arguments));
	}
	public override string? generic_definition_name() {
		return generic_origin == null ? null : generic_origin.name;
	}
	public override TypeArgumentVector? generic_arguments() {
		return generic_values;
	}
	private string representation_origin = "";
	private bool representation_bound;
	public string representation_identity { get { return representation_origin; } }
	public bool bind_representation(string identity) {
		if (representation_bound) {
			return identity == representation_origin;
		}
		representation_origin = identity;
		representation_bound = true;
		return true;
	}
	private string identifier;
	public string name { get { return identifier; } }

	internal StructType (string name) {
		base (TypeKind.STRUCT);
		this.identifier = name;
	}
}

// Astra-owned nullable, unmanaged address identity. No width or host type.
// Only void* is opaque raw storage; it is not TypedPointerType(void).
public class RawPointerType : SemanticType {
	public SemanticType pointee { get; private set; }

	internal RawPointerType (SemanticType pointee) {
		base (TypeKind.RAW_POINTER);
		this.pointee = pointee;
	}
}

// One general exact typed data-pointer identity, including native structs.
// Nullable, non-owning and potentially aliasing. No layout or stage backlink.
public class TypedPointerType : SemanticType {
	public SemanticType pointee { get; private set; }

	internal TypedPointerType (SemanticType pointee) {
		base (TypeKind.TYPED_POINTER);
		this.pointee = pointee;
	}
}

// One canonical type universe per analysis, retained by the checked program.
public class StringType : SemanticType {
	internal StringType () {
		base (TypeKind.STRING);
	}
}

public class BuiltinTypes : Object {
	public StringType string_type { get; private set; }
	public SemanticType int_type { get; private set; }
	public IntegerType i32_type { get { return (IntegerType) int_type; } }
	public IntegerType i8_type { get; private set; }
	public IntegerType u8_type { get; private set; }
	public IntegerType i16_type { get; private set; }
	public IntegerType u16_type { get; private set; }
	public IntegerType u32_type { get; private set; }
	public IntegerType i64_type { get; private set; }
	public IntegerType u64_type { get; private set; }
	// These distinct host-scope identities require downstream pointer/layout
	// qualification; they never alias int or fixed-width source identity.
	public IntegerType isize_type { get; private set; }
	public IntegerType usize_type { get; private set; }
	public F32Type f32_type { get; private set; }
	public F64Type f64_type { get; private set; }
	public SemanticType bool_type { get; private set; }
	public SemanticType void_type { get; private set; }
	public RawPointerType raw_pointer_type { get; private set; }

	private HashTable<SemanticType, OwnerSlotsType> owner_slots = new HashTable<SemanticType, OwnerSlotsType> (direct_hash, direct_equal);
	public OwnerSlotsType slots_of(SemanticType element) {
		var result = owner_slots.lookup (element);
		if (result == null) {
			result = new OwnerSlotsType (element);
			owner_slots.insert (element, result);
		}
		return result;
	}
	private HashTable<SemanticType, SliceType> slices = new HashTable<SemanticType, SliceType> (direct_hash, direct_equal);

	private GenericArray<FunctionValueType> function_values = new GenericArray<FunctionValueType> ();
	internal void complete_function_records(CopyabilityFields fields) throws StructLeafError {
		foreach (var signature in function_values) {
			signature.complete_records (fields);
		}
	}
	public FunctionValueType substitute_function(FunctionValueType original, GenericArray<SemanticType> parameters, SemanticType result) {
		var contracts = new GenericArray<PointerParameterContract> ();
		for (int p = 0; p < parameters.length; p++) {
			contracts.add (original.parameter_contract (p));
		}
		return function_value (result, parameters, contracts, original.result_contract, original is CallbackType);
	}
	public FunctionValueType function_value(SemanticType result, GenericArray<SemanticType> parameters, GenericArray<PointerParameterContract>? contracts = null, ResultOwnershipContract result_contract = ResultOwnershipContract.UNMANAGED, bool callback = false) {
		foreach (var candidate in function_values) {
			if ((candidate is CallbackType) != callback || candidate.result_type != result || candidate.result_contract != result_contract || candidate.parameter_types.length != parameters.length) {
				continue;
			}
			bool same = true;
			for (int i = 0; i < parameters.length; i++) {
				if (candidate.parameter_types[i] != parameters[i] || candidate.parameter_contract (i) != (contracts == null ? PointerParameterContract.UNMANAGED : contracts[i])) {
					same = false;
				}
			}
			if (same) {
				return candidate;
			}
		}
		FunctionValueType type = callback ? (FunctionValueType) new CallbackType (result, parameters) : new FunctionValueType (result, parameters, contracts, result_contract);
		function_values.add (type);
		return type;
	}
	private GenericArray<ArrayType> arrays = new GenericArray<ArrayType> ();

	private GenericArray<VectorType> vectors = new GenericArray<VectorType> ();

	private HashTable<SemanticType, TypedPointerType> pointers = new HashTable<SemanticType, TypedPointerType> (direct_hash, direct_equal);

	internal BuiltinTypes () {
		string_type = new StringType ();
		int_type = new IntegerType (TypeKind.INT);
		i8_type = new IntegerType (TypeKind.I8);
		u8_type = new IntegerType (TypeKind.U8);
		i16_type = new IntegerType (TypeKind.I16);
		u16_type = new IntegerType (TypeKind.U16);
		u32_type = new IntegerType (TypeKind.U32);
		i64_type = new IntegerType (TypeKind.I64);
		u64_type = new IntegerType (TypeKind.U64);
		isize_type = new IntegerType (TypeKind.ISIZE);
		usize_type = new IntegerType (TypeKind.USIZE);
		f32_type = new F32Type ();
		f64_type = new F64Type ();
		bool_type = new SemanticType (TypeKind.BOOL);
		void_type = new SemanticType (TypeKind.VOID);
		raw_pointer_type = new RawPointerType (void_type);
	}

	public VectorType? vector_of(SemanticType element, int lanes) {
		if (!VectorType.supports (element, lanes) || resolve (element.display_name ()) != element) {
			return null;
		}
		foreach (var vector in vectors) {
			if (vector.element_type == element && vector.lane_count == lanes) {
				return vector;
			}
		}
		var vector = new VectorType (element, lanes);
		vectors.add (vector);
		return vector;
	}

	public ArrayType? array_of(SemanticType element, int length) {
		if (!ArrayType.supports (element, length)) {
			return null;
		}
		var vector = element as VectorType;
		if (!element.is_struct_storage () && (vector == null ? resolve (element.display_name ()) != element : vector_of (vector.element_type, vector.lane_count) != vector)) {
			return null;
		}
		foreach (var array in arrays) {
			if (array.element_type == element && array.length == length) {
				return array;
			}
		}
		var array = new ArrayType (element, length);
		arrays.add (array);
		return array;
	}

	public SliceType? slice_of(SemanticType element) {
		bool symbolic = element is TypeParameterType && ((TypeParameterType) element).transport_mode == GenericTransportMode.PLAIN_COPY;
		if (!symbolic && !SliceType.supports (element)) {
			return null;
		}
		var vector = element as VectorType;
		if (!symbolic && !element.is_struct_storage () && (vector == null ? resolve (element.display_name ()) != element : vector_of (vector.element_type, vector.lane_count) != vector)) {
			return null;
		}
		var slice = slices.lookup (element);
		if (slice == null) {
			slice = new SliceType (element);
			slices.insert (element, slice);
		}
		return slice;
	}
	private HashTable<HandleType, ContextBytesType> context_bytes = new HashTable<HandleType, ContextBytesType> (direct_hash, direct_equal);
	public ContextBytesType? context_bytes_of(HandleType allocator) {
		var candidate = context_bytes.lookup (allocator);
		if (candidate != null) {
			return candidate;
		}
		candidate = new ContextBytesType (u8_type, allocator);
		if (!candidate.valid ()) {
			return null;
		}
		context_bytes.insert (allocator, candidate);
		return candidate;
	}

	public TypedPointerType pointer_to(SemanticType pointee) {
		assert (pointee.is_typed_data_pointee ());
		var pointer = pointers.lookup (pointee);
		if (pointer == null) {
			pointer = new TypedPointerType (pointee);
			pointers.insert (pointee, pointer);
		}
		return pointer;
	}

	public static bool is_builtin_name(string name) {
		return name == "string" || name == "f64" || name == "f32" || name == "int" || name == "i32" || name == "i8" || name == "u8" || name == "i16" || name == "u16" || name == "u32" || name == "i64" || name == "u64" || name == "isize" || name == "usize" || name == "bool" || name == "void" || name == "void*";
	}

	public SemanticType? resolve(string name) {
		switch (name) {
		case "string": return string_type;
		case "i32":
		case "int":
			return int_type;
		case "i8": return i8_type;
		case "u8": return u8_type;
		case "i16": return i16_type;
		case "u16": return u16_type;
		case "u32": return u32_type;
		case "i64": return i64_type;
		case "u64": return u64_type;
		case "isize": return isize_type;
		case "usize": return usize_type;
		case "f32":
			return f32_type;
		case "f64":
			return f64_type;
		case "bool":
			return bool_type;
		case "void":
			return void_type;
		case "void*":
			return raw_pointer_type;
		default:
			return null;
		}
	}
}
}

namespace Astra.Semantic {
// Exact concrete storage identity; never an array, slice or copyable value.
public class OwnerSlotsType : SemanticType {
	public SemanticType element { get; private set; }
	internal OwnerSlotsType (SemanticType element) {
		base (TypeKind.OWNER_SLOTS);
		this.element = element;
	}
}
public enum OwnerSlotsAction {
	LENGTH, CAPACITY, RESERVE, BORROW, TAKE
}
}
