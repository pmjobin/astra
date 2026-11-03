// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.NativeAbi {
public errordomain NativeAbiError {
	INVALID_SSA,
	INVALID_TYPE,
	INVALID_ABI,
	INCOMPATIBLE_CALL
}

// Internal artifact identity, not a cross-version compatibility promise.
public enum NativeAbiVersion {
	SCALAR_V0,
	SCALAR_PTR_V1,
	SCALAR_INT_V2,
	SCALAR_FP_V3,
	VECTOR_V4,
	SLICE_V5,
	FP64_V6,
	AGGREGATE_V7,
	BUFFER_V8,
	TEXT_V9,
	TEXT_SLICE_V10,
	STRUCT_ELEMENTS_V11,
	SUM_VALUES_V12,
	OWNED_SUMS_V13,
	NATIVE_EXCEPTIONS_V14,
	OWNER_SLOTS_V15;

	public string spelling() {
		switch (this) {
		case OWNER_SLOTS_V15:
			return "owner-slots-v15";
		case NATIVE_EXCEPTIONS_V14:
			return "native-exceptions-v14";
		case OWNED_SUMS_V13:
			return "owned-sums-v13";
		case SUM_VALUES_V12:
			return "sum-values-v12";
		case STRUCT_ELEMENTS_V11:
			return "struct-elements-v11";
		case TEXT_SLICE_V10:
			return "text-slice-v10";
		case TEXT_V9:
			return "text-v9";
		case BUFFER_V8:
			return "buffer-v8";
		case AGGREGATE_V7:
			return "aggregate-v7";
		case FP64_V6:
			return "fp64-v6";
		case SLICE_V5:
			return "slice-v5";
		case VECTOR_V4:
			return "vector-v4";
		case SCALAR_V0:
			return "scalar-v0";
		case SCALAR_FP_V3:
			return "scalar-fp-v3";
		case SCALAR_INT_V2:
			return "scalar-int-v2";
		case SCALAR_PTR_V1:
			return "scalar-ptr-v1";
		default:
			assert_not_reached ();
		}
	}

}

// Physical call channels only. B1 does not specify addressable bool storage.
// PTR has target-dependent width and conveys no ownership or addressability.
// Void is the absence of a result, never a scalar representation.
public enum NativeScalarType {
	I32,
	B1,
	PTR,
	I8,
	U8,
	I16,
	U16,
	U32,
	I64,
	U64,
	F32,
	F64;

	public string spelling() {
		switch (this) {
		case I8:
			return "I8";
		case U8:
			return "U8";
		case I16:
			return "I16";
		case U16:
			return "U16";
		case U32:
			return "U32";
		case I64:
			return "I64";
		case U64:
			return "U64";
		case F32:
			return "F32";
		case F64:
			return "F64";
		case I32:
			return "I32";
		case B1:
			return "B1";
		case PTR:
			return "PTR";
		default:
			assert_not_reached ();
		}
	}

}

// Compiler-owned channel types, independent of semantic/LLVM objects.
public abstract class NativeAbiType : Object {
	public abstract string spelling();
	public abstract bool same_type(NativeAbiType other);
}

public class NativeScalarAbiType : NativeAbiType {
	public NativeScalarType scalar_type { get; private set; }

	internal NativeScalarAbiType (NativeScalarType scalar_type) {
		this.scalar_type = scalar_type;
	}

	public override string spelling() {
		return scalar_type.spelling ();
	}

	public override bool same_type(NativeAbiType other) {
		return other is NativeScalarAbiType && !(other is NativeFunctionPointerType) && !(other is NativeSharedHandleType) && !(other is NativeClosureHandleType) && !(other is NativeContextHandleType) && ((NativeScalarAbiType) other).scalar_type == scalar_type;
	}

}

public class NativeContextHandleType : NativeScalarAbiType {
	private string nominal_name;
	private string lifetime_threading;
	private string release_symbol;
	public string name { get { return nominal_name; } }
	public string mode { get { return lifetime_threading; } }
	public string cleanup { get { return release_symbol; } }
	internal NativeContextHandleType (string name, string mode, string cleanup) {
		base (NativeScalarType.PTR);
		nominal_name = name;
		lifetime_threading = mode;
		release_symbol = cleanup;
	}

	public bool valid() {
		return scalar_type == NativeScalarType.PTR && Astra.Source.AllocationPolicy.identifier (name, true) && Astra.Source.AllocationPolicy.valid_context_mode (mode) && Astra.Source.AllocationPolicy.identifier (cleanup);
	}

	public override string spelling() {
		return "CONTEXT(runtime-contexts/1;%s;%s;%s)".printf (name, mode, cleanup);
	}

	public override bool same_type(NativeAbiType other) {
		var context = other as NativeContextHandleType;
		return context != null && valid () && context.valid () && context.name == name && context.mode == mode && context.cleanup == cleanup;
	}

}

public class NativeVectorType : NativeAbiType {
	public NativeScalarType element { get; private set; }
	public int lanes { get; private set; }

	internal NativeVectorType (NativeScalarType element, int lanes) {
		this.element = element;
		this.lanes = lanes;
	}

	public override string spelling() {
		return "VECTOR(%s,%d)".printf (element.spelling (), lanes);
	}

	public override bool same_type(NativeAbiType other) {
		return other is NativeVectorType && ((NativeVectorType) other).element == element && ((NativeVectorType) other).lanes == lanes;
	}

}
public class NativeVectorMemoryPlan : Object {
	public NativeVectorType vector_type { get; private set; }
	public uint alignment { get; internal set; }
	public bool store { get; private set; }
	private uint origin_alignment;
	public NativeVectorMemoryPlan (NativeVectorType vector_type, uint alignment, bool store = false) {
		this.vector_type = vector_type;
		this.alignment = alignment;
		origin_alignment = alignment;
		this.store = store;
	}

	public NativeVectorMemoryPlan copy() {
		var result = new NativeVectorMemoryPlan (vector_type, origin_alignment, store);
		result.alignment = alignment;
		return result;
	}

	public bool valid() {
		return alignment == origin_alignment && alignment > 0 && alignment <= 16 && (alignment & (alignment - 1)) == 0;
	}

}

// One parameter group. These components have no element or lifetime metadata.
public class NativeSliceType : NativeAbiType {
	public NativeScalarType base_type { get; private set; }
	public NativeScalarType length_type { get; private set; }
	// A physical PTR/I32 pair alone cannot prove a declared byte view. Keep
	// the mapped scalar element and borrow fact when available at admission.
	public NativeScalarAbiType? borrowed_element { get; private set; }
	internal NativeSliceType.borrowed (NativeScalarAbiType element) {
		base_type = NativeScalarType.PTR;
		length_type = NativeScalarType.I32;
		borrowed_element = element;
	}

	internal NativeSliceType (NativeScalarType base_type = NativeScalarType.PTR, NativeScalarType length_type = NativeScalarType.I32) {
		this.base_type = base_type;
		this.length_type = length_type;
	}

	public override string spelling() {
		return "SLICE(%s,%s)".printf (base_type.spelling (), length_type.spelling ());
	}

	public override bool same_type(NativeAbiType other) {
		return other is NativeSliceType && !(other is NativeTextSliceType) && !(other is NativeRecordSliceType) && !(other is NativeContextSliceType) && ((NativeSliceType) other).base_type == base_type && ((NativeSliceType) other).length_type == length_type;
	}

}
public class NativeContextSliceType : NativeSliceType {
	public NativeContextHandleType allocator { get; private set; }
	public string name { owned get { return "ContextBytes<" + allocator.name + ">"; } }
	internal NativeContextSliceType (NativeContextHandleType allocator) {
		base ();
		this.allocator = new NativeContextHandleType (allocator.name, allocator.mode, allocator.cleanup);
	}

	public bool valid() {
		return allocator.valid () && allocator.mode != "scoped-affine" && base_type == NativeScalarType.PTR && length_type == NativeScalarType.I32;
	}

	public override string spelling() {
		return "CONTEXT-BYTES(runtime-contexts/1;%s;release=astra_context17_release_origin_checked;role=buffer;PTR,I32)".printf (allocator.spelling ());
	}

	public override bool same_type(NativeAbiType other) {
		var bytes = other as NativeContextSliceType;
		return bytes != null && valid () && bytes.valid () && allocator.same_type (bytes.allocator);
	}

}

public enum NativeLinkage {
	NATIVE_INTERNAL
}

public class NativeObjectOriginPlan : Object {
	public int class_ordinal { get; private set; }
	private string identifier;
	public string class_name { get { return identifier; } }
	public bool heap { get; private set; }
	internal NativeObjectOriginPlan (int class_ordinal, string class_name, bool heap) {
		this.class_ordinal = class_ordinal;
		this.identifier = class_name;
		this.heap = heap;
	}

}
public class NativeParameter : Object {
	public ForeignComInterface? com_unknown_borrow { get; private set; }
	internal void bind_com_unknown(ForeignComInterface protocol) throws NativeAbiError {
		if (com_unknown_borrow != null || !protocol.valid () || abi_type.get_type () != typeof (NativeScalarAbiType) || scalar_type != NativeScalarType.PTR || resource != null || scalar_pointee != null || object_origin != null || borrowed_class_ordinal != -1) {
			throw new NativeAbiError.INVALID_ABI ("IUnknown acquisition requires its exact call-only raw pointer and queried interface declaration");
		}
		com_unknown_borrow = protocol;
	}

	public NativeScalarAbiType? scalar_pointee { get; private set; }
	public bool requires_nonnull { get; private set; }
	public int generic_owner_class { get; private set; default = -1; }
	public bool generic_owner_heap { get; private set; }
	public ExactClassDefinitionIdentity? generic_owner_origin { get; private set; }
	internal void bind_generic_owner(int owner, ExactClassDefinitionIdentity definition) throws NativeAbiError {
		if (generic_owner_origin != null || owner < 0 || !definition.general_bodies) {
			throw new NativeAbiError.INVALID_ABI ("generic Class owned parameter binds one exact original instance");
		}
		if (object_origin == null) {
			throw new NativeAbiError.INVALID_ABI ("generic Class owned parameter requires its declared storage origin");
		}
		generic_owner_class = owner;
		generic_owner_origin = definition;
		generic_owner_heap = object_origin.heap;
	}

	public NativeScalarOwner? resource { get; private set; }
	public bool owns_resource { get; private set; }
	internal void bind_resource(NativeScalarOwner resource, bool owned) throws NativeAbiError {
		if (this.resource != null || resource.class_ordinal != -1 || resource.type_name == "" || resource.cleanup_symbol == "") {
			throw new NativeAbiError.INVALID_ABI ("Resource parameter binds one exact nominal destructor declaration");
		}
		this.resource = resource;
		owns_resource = owned;
	}

	private int borrowed_class_identity = -1;
	public int borrowed_class_ordinal { get { return borrowed_class_identity; } }
	// Exact generic Class borrow identity is compile-time metadata only.
	public int generic_borrow_class { get; internal set; default = -1; }
	public Astra.Source.ExactClassDefinitionIdentity? generic_borrow_origin { get; private set; }
	private int declared_generic_borrow_class = -1;
	internal void bind_generic_borrow(int ordinal, Astra.Source.ExactClassDefinitionIdentity origin) throws NativeAbiError {
		if (generic_borrow_origin != null || ordinal < 0) {
			throw new NativeAbiError.INVALID_ABI ("generic Class borrow origin binds exactly once");
		}
		declared_generic_borrow_class = ordinal;
		generic_borrow_class = ordinal;
		generic_borrow_origin = origin;
	}

	internal bool generic_borrow_matches() {
		return generic_borrow_class == declared_generic_borrow_class;
	}

	public NativeObjectOriginPlan? object_origin { get; internal set; }
	public int ordinal { get; private set; }
	public NativeAbiType abi_type { get; private set; }
	public NativeScalarType scalar_type {
		get {
			assert (abi_type is NativeScalarAbiType);
			return ((NativeScalarAbiType) abi_type).scalar_type;
		}
	}
	private string identifier;
	public string name { get { return identifier; } }
	public SourceSpan span { get; private set; }
	public SourceSpan name_span { get; private set; }

	internal NativeParameter (SourceSpan span, SourceSpan name_span, string name, int ordinal, NativeScalarType scalar_type) {
		this.span = span;
		this.name_span = name_span;
		this.identifier = name;
		this.ordinal = ordinal;
		this.abi_type = new NativeScalarAbiType (scalar_type);
	}

	internal NativeParameter.typed (SourceSpan span, SourceSpan name_span, string name, int ordinal, NativeAbiType abi_type, int borrowed_class = -1, bool requires_nonnull = false, NativeScalarAbiType? scalar_pointee = null) {
		this.span = span;
		this.name_span = name_span;
		this.identifier = name;
		this.ordinal = ordinal;
		this.abi_type = abi_type;
		this.borrowed_class_identity = borrowed_class;
		this.requires_nonnull = requires_nonnull;
		this.scalar_pointee = scalar_pointee;
	}
}

public class NativeResult : Object {
	public NativeAbiType abi_type { get; private set; }
	public NativeScalarType scalar_type {
		get {
			assert (abi_type is NativeScalarAbiType);
			return ((NativeScalarAbiType) abi_type).scalar_type;
		}
	}

	internal NativeResult (NativeScalarType scalar_type) {
		this.abi_type = new NativeScalarAbiType (scalar_type);
	}

	internal NativeResult.typed (NativeAbiType abi_type) {
		this.abi_type = abi_type;
	}
}

// One group per semantic parameter and at most one direct result.
// Only slice groups expand to two components; no semantic type objects.
public class NativeOwnedObjectResultPlan : Object {
	public NativeScalarAbiType candidate_storage { get; private set; default = new NativeScalarAbiType (NativeScalarType.PTR); }
	public NativeScalarAbiType owner_result { get; private set; default = new NativeScalarAbiType (NativeScalarType.PTR); }
	public NativeObjectOriginPlan? object_origin { get; private set; }
	public NativeOwnedObjectResultPlan () {
	}

	internal NativeOwnedObjectResultPlan.typed (NativeObjectOriginPlan origin) {
		object_origin = origin;
	}
}

public class NativeExceptionPlan : Object {
	public int bound_ordinal { get; private set; }
	private string bound_identifier;
	public string bound_name { get { return bound_identifier; } }
	public int root_ordinal { get; private set; }
	private string root_identifier;
	public string root_name { get { return root_identifier; } }
	internal NativeExceptionPlan (int bound_ordinal, string bound_name, int root_ordinal, string root_name) {
		this.bound_ordinal = bound_ordinal;
		this.bound_identifier = bound_name;
		this.root_ordinal = root_ordinal;
		this.root_identifier = root_name;
	}

}
public class NativeSignature : Object {
	public bool nonnull_result { get; private set; }
	private GenericArray<NativeParameter> declared_resource_channels = new GenericArray<NativeParameter> ();
	private GenericArray<NativeAbiType> declared_resource_types = new GenericArray<NativeAbiType> ();
	internal bool matches_resource_parameters() {
		uint count = uint.max (parameters.length, declared_resource_channels.length);
		for (int p = 0; p < count; p++) {
			var original = p < declared_resource_channels.length ? declared_resource_channels[p] : null;
			var actual = p < parameters.length ? parameters[p] : null;
			if ((original == null || original.resource == null) && (actual == null || actual.resource == null)) {
				continue;
			}
			if (original == null || actual == null || original.resource == null || actual.resource == null || !original.resource.same_owner (actual.resource) || original.owns_resource != actual.owns_resource || p >= declared_resource_types.length || !declared_resource_types[p].same_type (actual.abi_type)) {
				return false;
			}
		}
		return true;
	}

	public int generic_owner_result_class { get; private set; default = -1; }
	public ExactClassDefinitionIdentity? generic_owner_result_origin { get; private set; }
	public bool generic_owner_result_heap { get; private set; }
	internal void bind_generic_owner_result(int owner, ExactClassDefinitionIdentity definition, bool heap = true) throws NativeAbiError {
		if (generic_owner_result_origin != null || owner < 0 || !definition.general_bodies) {
			throw new NativeAbiError.INVALID_ABI ("generic Class owned result binds one exact original instance");
		}
		generic_owner_result_class = owner;
		generic_owner_result_origin = definition;
		generic_owner_result_heap = heap;
	}

	public NativeScalarOwner? resource_result { get; private set; }
	internal void bind_resource_result(NativeScalarOwner resource) throws NativeAbiError {
		if (resource_result != null || resource.class_ordinal != -1 || resource.type_name == "" || resource.cleanup_symbol == "") {
			throw new NativeAbiError.INVALID_ABI ("Resource result binds one exact nominal destructor declaration");
		}
		resource_result = resource;
	}

	private bool struct_transport_bound;
	private NativeStructValuePlan? declared_struct_result;
	private NativeStructValueMode declared_struct_result_mode;
	private GenericArray<NativeStructParameterPlan> declared_struct_parameters = new GenericArray<NativeStructParameterPlan> ();
	public bool has_struct_transport_declaration { get { return struct_transport_bound; } }
	internal void bind_struct_transport(uint parameter_groups, NativeStructValuePlan? result) throws NativeAbiError {
		if (struct_transport_bound || struct_parameters.length != parameter_groups || struct_result != result) {
			throw new NativeAbiError.INVALID_ABI ("struct transport declaration must bind the complete original signature once");
		}
		struct_transport_bound = true;
		declared_struct_result = result;
		declared_struct_result_mode = struct_result_mode;
		foreach (var parameter in struct_parameters) {
			declared_struct_parameters.add (parameter);
		}
	}

	internal bool matches_struct_transport() {
		if (!struct_transport_bound || struct_result != declared_struct_result || struct_result_mode != declared_struct_result_mode || struct_parameters.length != declared_struct_parameters.length) {
			return false;
		}
		for (int i = 0; i < struct_parameters.length; i++) {
			if (struct_parameters[i] != declared_struct_parameters[i]) {
				return false;
			}
		}
		return true;
	}

	public NativeObjectOriginPlan? heap_result { get; internal set; }
	public NativeExceptionPlan? exception_plan { get; internal set; }
	public NativeSumType? sum_result { get; internal set; }
	public GenericArray<NativeBufferParameterPlan> buffer_parameters { get; private set; default = new GenericArray<NativeBufferParameterPlan> (); }
	public NativeBufferValuePlan? buffer_result { get; internal set; }
	private bool buffer_transport_bound;
	private NativeBufferValuePlan? declared_buffer_result;
	private GenericArray<NativeBufferParameterPlan> declared_buffer_parameters = new GenericArray<NativeBufferParameterPlan> ();
	internal void bind_buffer_transport() {
		assert (!buffer_transport_bound);
		buffer_transport_bound = true;
		declared_buffer_result = buffer_result;
		foreach (var parameter in buffer_parameters) {
			declared_buffer_parameters.add (parameter);
		}
	}

	internal bool matches_buffer_transport() {
		if (!buffer_transport_bound) {
			return buffer_result == null && buffer_parameters.length == 0;
		}
		if (buffer_result != declared_buffer_result || buffer_parameters.length != declared_buffer_parameters.length) {
			return false;
		}
		for (int p = 0; p < buffer_parameters.length; p++) {
			if (buffer_parameters[p] != declared_buffer_parameters[p]) {
				return false;
			}
		}
		return true;
	}

	public GenericArray<NativeStructParameterPlan> struct_parameters { get; private set; default = new GenericArray<NativeStructParameterPlan> (); }
	public NativeStructValuePlan? struct_result { get; internal set; }
	public NativeStructValueMode struct_result_mode { get; internal set; default = NativeStructValueMode.COPY_VALUE; }
	public NativeOwnedObjectResultPlan? object_result { get; private set; }
	// Separate implicit channel; explicit parameters keep their original ordinals.
	public NativeScalarAbiType? receiver { get; private set; }
	public NativeAbiVersion abi_version { get; private set; }
	public GenericArray<NativeParameter> parameters { get; private set; }
	public NativeResult? result { get; private set; }
	public bool has_exception_success_slot { get { return exception_plan != null && sum_result == null && (result != null || buffer_result != null || struct_result != null); } }
	public int physical_parameter_count {
		get {
			int count = (has_exception_success_slot ? 1 : 0) + (sum_result == null ? 0 : 1) + (object_result == null ? 0 : 1) + (receiver == null ? 0 : 1);
			foreach (var parameter in parameters) {
				count += (parameter.abi_type is NativeSliceType || parameter.abi_type is NativeTextType) ? 2 : 1;
			}
			return count;
		}
	}

	internal NativeSignature (NativeAbiVersion abi_version, GenericArray<NativeParameter> parameters, NativeResult? result, NativeScalarAbiType? receiver = null, NativeOwnedObjectResultPlan? object_result = null, bool nonnull_result = false) {
		this.nonnull_result = nonnull_result;
		this.object_result = object_result;
		this.abi_version = abi_version;
		this.receiver = receiver;
		this.parameters = parameters;
		foreach (var parameter in parameters) {
			declared_resource_channels.add (parameter);
			declared_resource_types.add (parameter.abi_type);
		}
		this.result = result;
	}

}

// Independent physical identity with copied debug names and provenance.
// No body or call edges; only the program strongly owns its functions.
public enum NativeCallableKind {
	FUNCTION, METHOD, CONSTRUCTOR, DESTRUCTOR, PROPERTY_GETTER, PROPERTY_SETTER
}

// Source-free local record obligations. These add no aggregate ABI transport.
public class NativeRecordResource : Object {
	public int acquisition_rank { get; private set; }
	public int cleanup_class_ordinal { get; private set; default = -1; }
	public NativeBufferValuePlan? buffer_cleanup { get; private set; }
	public int field_ordinal { get; private set; }
	private int[] ordinals;
	public int depth { get { return ordinals.length; } }
	public int path_ordinal(int index) {
		return ordinals[index];
	}

	public string field_path {
		owned get {
			var text = new StringBuilder ();
			foreach (int ordinal in ordinals) {
				if (text.len != 0) {
					text.append (".");
				}
				text.append_printf ("%d", ordinal);
			}
			return text.str;
		}
	}
	public int compare_path(NativeRecordResource other) {
		for (int i = 0; i < int.min (depth, other.depth); i++) {
			if (ordinals[i] != other.ordinals[i]) {
				return ordinals[i] < other.ordinals[i] ? -1 : 1;
			}
		}
		return depth == other.depth ? 0 : depth < other.depth ? -1 : 1;
	}

	public bool same_cleanup(NativeRecordResource other) {
		if (cleanup_symbol != other.cleanup_symbol || cleanup_class_ordinal != other.cleanup_class_ordinal || (buffer_cleanup == null) != (other.buffer_cleanup == null)) {
			return false;
		}
		if (buffer_cleanup == null) {
			return true;
		}
		if ((buffer_cleanup.context_origin == null) != (other.buffer_cleanup.context_origin == null) || buffer_cleanup.context_origin != null && !buffer_cleanup.context_origin.same_type (other.buffer_cleanup.context_origin)) {
			return false;
		}
		if (buffer_cleanup.record_element != null || other.buffer_cleanup.record_element != null) {
			return buffer_cleanup.record_element != null && buffer_cleanup.record_element == other.buffer_cleanup.record_element;
		}
		return buffer_cleanup.element_type != null && other.buffer_cleanup.element_type != null && buffer_cleanup.element_type.same_type (other.buffer_cleanup.element_type);
	}

	private string type_identifier;
	private string cleanup_identifier;
	public string type_name { get { return type_identifier; } }
	public string cleanup_symbol { get { return cleanup_identifier; } }
	internal NativeRecordResource (int field_ordinal, string type_name, string cleanup_symbol, int acquisition_rank = -1) {
		this.ordinals = {
			field_ordinal
		};
		this.acquisition_rank = acquisition_rank;
		this.field_ordinal = field_ordinal;
		this.type_identifier = type_name;
		this.cleanup_identifier = cleanup_symbol;
	}

	internal NativeRecordResource.projected (int[] path, string type_name, string cleanup_symbol, int acquisition_rank = -1, int cleanup_class_ordinal = -1, NativeBufferValuePlan? buffer_cleanup = null) {
		this.buffer_cleanup = buffer_cleanup;
		this.cleanup_class_ordinal = cleanup_class_ordinal;
		this.ordinals = new int[path.length];
		for (int i = 0; i < path.length; i++) {
			ordinals[i] = path[i];
		}
		this.field_ordinal = path.length == 0 ? -1 : path[path.length - 1];
		this.acquisition_rank = acquisition_rank;
		this.type_identifier = type_name;
		this.cleanup_identifier = cleanup_symbol;
	}
}
public class NativeRecordDeclarationPlan : Object {
	public int struct_ordinal { get; private set; }
	private string identifier;
	public string name { get { return identifier; } }
	public GenericArray<NativeRecordResource> fields { get; private set; }
	public uint field_count { get; private set; }
	internal NativeRecordDeclarationPlan (int struct_ordinal, string name, GenericArray<NativeRecordResource> fields) {
		this.struct_ordinal = struct_ordinal;
		this.identifier = name;
		this.fields = new GenericArray<NativeRecordResource> ();
		foreach (var field in fields) {
			this.fields.add (field);
		}
		this.field_count = this.fields.length;
	}

}
public class NativeRecordOwnerPlan : Object {
	public NativeRecordDeclarationPlan? declaration { get; internal set; }
	public int source_ordinal { get; private set; }
	private string record_identifier;
	public string record_name { get { return record_identifier; } }
	public GenericArray<NativeRecordResource> fields { get; private set; default = new GenericArray<NativeRecordResource> (); }
	public GenericArray<NativeRecordResource> obligations { get; private set; default = new GenericArray<NativeRecordResource> (); }
	internal NativeRecordOwnerPlan (int source_ordinal, string record_name) {
		this.source_ordinal = source_ordinal;
		this.record_identifier = record_name;
	}

}
public class NativeAllocationInput : Object {
	public int parameter_ordinal { get; internal set; }
	public int source_ordinal { get; internal set; }
	public int class_ordinal { get; internal set; }
	public bool heap { get; internal set; }
	private string resource_name_value;
	public string resource_name { get { return resource_name_value; } internal set { resource_name_value = value; } }
	private string cleanup_symbol_value;
	public string cleanup_symbol { get { return cleanup_symbol_value; } internal set { cleanup_symbol_value = value; } }
	private string origin;
	internal string identity() {
		return "%d/%d/%d/%d/%d:%s/%d:%s".printf (parameter_ordinal, source_ordinal, class_ordinal, heap ? 1 : 0, resource_name.length, resource_name, cleanup_symbol.length, cleanup_symbol);
	}

	internal NativeAllocationInput (int parameter, int source, int owner, bool heap, string resource, string cleanup) {
		parameter_ordinal = parameter;
		source_ordinal = source;
		class_ordinal = owner;
		this.heap = heap;
		resource_name = resource;
		cleanup_symbol = cleanup;
		origin = identity ();
	}

	public bool valid() {
		return origin == identity () && parameter_ordinal >= 0 && source_ordinal >= -1 && (class_ordinal >= 0 ? resource_name == "" && cleanup_symbol == "" : class_ordinal == -1 && !heap && resource_name != "" && cleanup_symbol != "");
	}

}
public class NativeAllocationSite : Object {
	public int storage_ordinal { get; internal set; }
	public int class_ordinal { get; internal set; }
	public int constructor_ordinal { get; internal set; }
	public bool heap { get; internal set; }
	public bool fallible { get; internal set; }
	public GenericArray<NativeAllocationInput> inputs { get; private set; default = new GenericArray<NativeAllocationInput> (); }
	public GenericArray<NativeFrameBufferInput> buffers { get; private set; default = new GenericArray<NativeFrameBufferInput> (); }
	public GenericArray<NativeFrameRecordInput> records { get; private set; default = new GenericArray<NativeFrameRecordInput> (); }
	private string origin;
	private string identity() {
		var text = new StringBuilder ("%d/%d/%d/%d/%d".printf (storage_ordinal, class_ordinal, constructor_ordinal, heap ? 1 : 0, fallible ? 1 : 0));
		foreach (var input in inputs) {
			text.append ("/" + input.identity ());
		}
		foreach (var buffer in buffers) {
			text.append ("/buffer=" + buffer.identity ());
		}
		foreach (var record in records) {
			text.append ("/record=" + record.identity ());
		}
		return text.str;
	}

	internal NativeAllocationSite (int storage, int owner, int constructor, bool heap, bool fallible, GenericArray<NativeAllocationInput>? inputs = null, GenericArray<NativeFrameBufferInput>? buffers = null, GenericArray<NativeFrameRecordInput>? records = null) {
		storage_ordinal = storage;
		class_ordinal = owner;
		constructor_ordinal = constructor;
		this.heap = heap;
		this.fallible = fallible;
		if (inputs != null) {
			foreach (var input in inputs) {
				this.inputs.add (input);
			}
		}
		if (buffers != null) {
			foreach (var buffer in buffers) {
				this.buffers.add (buffer);
			}
		}
		if (records != null) {
			foreach (var record in records) {
				this.records.add (record);
			}
		}
		origin = identity ();
	}

	public bool valid() {
		foreach (var input in inputs) {
			if (!input.valid ()) {
				return false;
			}
		}
		foreach (var buffer in buffers) {
			if (!buffer.valid ()) {
				return false;
			}
		}
		foreach (var record in records) {
			if (!record.valid ()) {
				return false;
			}
		}
		return origin == identity () && storage_ordinal >= 0 && class_ordinal >= 0 && constructor_ordinal >= 0;
	}

}
public class NativeFrameBufferInput : Object {
	public int first_leaf { get; internal set; }
	public int source_ordinal { get; internal set; }
	public NativeBufferValuePlan value_plan { get; private set; }
	private string origin;
	internal string identity() {
		return "%d/%d/%s".printf (first_leaf, source_ordinal, value_plan.element_spelling ());
	}

	internal NativeFrameBufferInput (int first, int source, NativeBufferValuePlan plan) {
		first_leaf = first;
		source_ordinal = source;
		value_plan = plan;
		origin = identity ();
	}

	public bool valid() {
		return origin == identity () && first_leaf >= 0 && source_ordinal >= 0 && value_plan.transfers_ownership && value_plan.base_type == NativeScalarType.PTR && value_plan.length_type == NativeScalarType.I32;
	}

}
public class NativeFrameRecordInput : Object {
	public int first_leaf { get; internal set; }
	public int source_ordinal { get; internal set; }
	public NativeStructValuePlan value_plan { get; private set; }
	private string origin;
	internal string identity() {
		return "%d/%d/%s".printf (first_leaf, source_ordinal, NativeAsyncFramePlan.record_identity (value_plan));
	}

	internal NativeFrameRecordInput (int first, int source, NativeStructValuePlan plan) {
		first_leaf = first;
		source_ordinal = source;
		value_plan = plan;
		origin = identity ();
	}

	public bool valid() {
		return origin == identity () && first_leaf >= 0 && source_ordinal >= 0 && value_plan.mode == NativeStructValueMode.MOVE_VALUE && value_plan.ownership.length != 0;
	}

}
public class NativeFrameAdmissionSite : Object {
	public int block_ordinal { get; internal set; }
	public int position { get; internal set; }
	public int task_ordinal { get; internal set; }
	public int factory_ordinal { get; internal set; }
	public int exception_ordinal { get; internal set; }
	private string context_mode_value;
	public string context_mode { get { return context_mode_value; } internal set { context_mode_value = value; } }
	public GenericArray<NativeAllocationInput> inputs { get; private set; default = new GenericArray<NativeAllocationInput> (); }
	public GenericArray<NativeFrameBufferInput> buffers { get; private set; default = new GenericArray<NativeFrameBufferInput> (); }
	public GenericArray<NativeFrameRecordInput> records { get; private set; default = new GenericArray<NativeFrameRecordInput> (); }
	private string origin;
	private string identity() {
		var text = new StringBuilder ("%d/%d/%d/%d/%d/%s".printf (block_ordinal, position, task_ordinal, factory_ordinal, exception_ordinal, context_mode));
		foreach (var input in inputs) {
			text.append ("/" + input.identity ());
		}
		foreach (var buffer in buffers) {
			text.append ("/buffer=" + buffer.identity ());
		}
		foreach (var record in records) {
			text.append ("/record=" + record.identity ());
		}
		return text.str;
	}

	internal NativeFrameAdmissionSite (int block, int position, int task, int factory, int exception, string mode, GenericArray<NativeAllocationInput> inputs, GenericArray<NativeFrameBufferInput> buffers, GenericArray<NativeFrameRecordInput>? records = null) {
		block_ordinal = block;
		this.position = position;
		task_ordinal = task;
		factory_ordinal = factory;
		exception_ordinal = exception;
		context_mode = mode;
		foreach (var input in inputs) {
			this.inputs.add (input);
		}
		foreach (var buffer in buffers) {
			this.buffers.add (buffer);
		}
		if (records != null) {
			foreach (var record in records) {
				this.records.add (record);
			}
		}
		origin = identity ();
	}

	public bool valid() {
		foreach (var input in inputs) {
			if (!input.valid ()) {
				return false;
			}
		}
		foreach (var buffer in buffers) {
			if (!buffer.valid ()) {
				return false;
			}
		}
		foreach (var record in records) {
			if (!record.valid ()) {
				return false;
			}
		}
		return origin == identity () && block_ordinal >= 0 && position >= 0 && task_ordinal >= 0 && factory_ordinal >= 0 && exception_ordinal >= 0 && (context_mode == "owned-concurrent" || context_mode == "owned-affine" || context_mode == "owned-transfer" || context_mode == "scoped-affine");
	}

}
public class NativeFunction : Object {
	public NativeForeignSignalPlan? foreign_signal { get; internal set; }
	public NativeForeignImportPlan? foreign_import { get; internal set; }
	public NativeConstructorUnwindPlan? constructor_unwind { get; internal set; }
	public bool scoped_readonly { get; internal set; }
	private string readonly_input_text = "";
	private string callback_input_text = "";
	public string readonly_inputs { get { return readonly_input_text; } internal set { readonly_input_text = value; } }
	public string callback_inputs { get { return callback_input_text; } internal set { callback_input_text = value; } }
	public int callback_input_count { get; internal set; }
	public bool callback_contract_supported { get; internal set; }
	private bool original_scoped_readonly;
	private string original_readonly_inputs = "";
	private string original_callback_inputs = "";
	private int original_callback_input_count;
	private bool original_callback_contract_supported;
	private bool readonly_bound;
	internal void bind_scoped_readonly(bool value, string readonly_inputs = "", string callback_inputs = "", int input_count = 0, bool supported = true) throws NativeAbiError {
		if (readonly_bound) {
			throw new NativeAbiError.INVALID_ABI ("readonly effect binds once to its original checked definition");
		}
		readonly_bound = true;
		scoped_readonly = original_scoped_readonly = value;
		this.readonly_inputs = original_readonly_inputs = readonly_inputs;
		this.callback_inputs = original_callback_inputs = callback_inputs;
		callback_input_count = original_callback_input_count = input_count;
		callback_contract_supported = original_callback_contract_supported = supported;
	}

	internal bool scoped_readonly_valid() {
		// A newly constructed physical model promises no readonly behavior or
		// supported callback contract. A producer may bind checked facts once;
		// either state must retain its exact original facts under mutation.
		return scoped_readonly == original_scoped_readonly && readonly_inputs == original_readonly_inputs &&
		       callback_inputs == original_callback_inputs && callback_input_count == original_callback_input_count &&
		       callback_contract_supported == original_callback_contract_supported;
	}

	private string lifetime_text = "runtime-lifetime-summary/1:incomplete";
	public string runtime_lifetimes { get { return lifetime_text; } internal set { lifetime_text = value; } }
	private string lifetime_origin = "runtime-lifetime-summary/1:incomplete";
	private bool lifetime_bound;
	internal void bind_runtime_lifetimes(string descriptor) throws NativeAbiError {
		if (lifetime_bound) {
			throw new NativeAbiError.INVALID_ABI ("runtime lifetime summary binds once");
		}
		try {
			var summary = RuntimeLifetimeSummary.decode (descriptor);
			if (summary.logical_coordinates) {
				throw new NativeAbiError.INVALID_ABI ("native physical lifetime plan cannot substitute logical archive coordinates");
			}
			if (!summary.matches_exception (async_origin == null && signature.exception_plan != null)) {
				throw new NativeAbiError.INVALID_ABI ("runtime lifetime exception channel differs from its native signature");
			}
		} catch (RuntimeLifetimeError failure) {
			throw new NativeAbiError.INVALID_ABI ("invalid runtime lifetime descriptor: %s", failure.message);
		}
		runtime_lifetimes = lifetime_origin = descriptor;
		lifetime_bound = true;
	}

	internal bool runtime_lifetimes_valid() {
		if (runtime_lifetimes != lifetime_origin) {
			return false;
		}
		try {
			return async_callable_valid () && RuntimeLifetimeSummary.decode (runtime_lifetimes).matches_exception (async_origin == null && signature.exception_plan != null);
		} catch (RuntimeLifetimeError failure) {
			return false;
		}
	}

	public NativeAsyncCallablePlan? async_callable { get; internal set; }
	private NativeAsyncCallablePlan? async_origin;
	internal void bind_async_callable(NativeAsyncCallablePlan plan) throws NativeAbiError {
		if (async_origin != null) {
			throw new NativeAbiError.INVALID_ABI ("async callable binds once to its original declaration");
		}
		async_callable = async_origin = plan;
	}

	internal bool async_callable_valid() {
		return async_callable == async_origin && (async_callable == null || async_callable.matches (signature));
	}

	public GenericArray<NativeAllocationSite> allocation_sites { get; private set; default = new GenericArray<NativeAllocationSite> (); }
	public GenericArray<NativeScopedBackingPlan> scoped_backings { get; private set; default = new GenericArray<NativeScopedBackingPlan> (); }
	private GenericArray<NativeScopedBackingPlan> scoped_backing_origin = new GenericArray<NativeScopedBackingPlan> ();
	internal void bind_scoped_backing(NativeScopedBackingPlan plan) throws NativeAbiError {
		optimizer_admission ();
		if (!plan.valid ()) {
			throw new NativeAbiError.INVALID_ABI ("invalid original scoped backing loan");
		}
		scoped_backings.add (plan);
		scoped_backing_origin.add (plan);
	}

	internal bool scoped_backings_valid() {
		if (scoped_backings.length != scoped_backing_origin.length) {
			return false;
		}
		for (int i = 0; i < scoped_backings.length; i++) {
			if (scoped_backings[i] != scoped_backing_origin[i] || !scoped_backings[i].valid ()) {
				return false;
			}
		}
		return true;
	}

	private GenericArray<NativeAllocationSite> allocation_origin = new GenericArray<NativeAllocationSite> ();
	public void bind_allocation_site(NativeAllocationSite site) throws NativeAbiError {
		optimizer_admission ();
		if (!site.valid ()) {
			throw new NativeAbiError.INVALID_ABI ("invalid original allocation site");
		}
		allocation_sites.add (site);
		allocation_origin.add (site);
	}

	internal bool allocation_sites_valid() {
		if (allocation_sites.length != allocation_origin.length) {
			return false;
		}
		for (int i = 0; i < allocation_sites.length; i++) {
			if (allocation_sites[i] != allocation_origin[i] || !allocation_sites[i].valid ()) {
				return false;
			}
		}
		return true;
	}

	public GenericArray<NativeFrameAdmissionSite> frame_admissions { get; private set; default = new GenericArray<NativeFrameAdmissionSite> (); }
	private GenericArray<NativeFrameAdmissionSite> frame_admission_origin = new GenericArray<NativeFrameAdmissionSite> ();
	public void bind_frame_admission(NativeFrameAdmissionSite site) throws NativeAbiError {
		optimizer_admission ();
		if (!site.valid ()) {
			throw new NativeAbiError.INVALID_ABI ("invalid original checked frame admission");
		}
		frame_admissions.add (site);
		frame_admission_origin.add (site);
	}

	internal bool frame_admissions_valid() {
		if (frame_admissions.length != frame_admission_origin.length) {
			return false;
		}
		for (int i = 0; i < frame_admissions.length; i++) {
			if (frame_admissions[i] != frame_admission_origin[i] || !frame_admissions[i].valid ()) {
				return false;
			}
		}
		return true;
	}

	public FunctionEffectFacts? effect_facts { get; internal set; }
	private FunctionEffectFacts? effect_origin;
	private NativeOptimizerEvidence? imported_effect_evidence;
	internal bool imported_effects_valid() {
		return effect_facts == null || effect_facts.flags == 0 && no_parameter_effects () || imported_effect_evidence != null && imported_effect_evidence.permits (effect_facts);
	}

	private bool no_parameter_effects() {
		for (int p = 0; p < effect_facts.parameter_count; p++) {
			if (effect_facts.parameter (p) != 0) {
				return false;
			}
		}
		return true;
	}

	private bool optimizer_facts_sealed;
	private bool effects_bound;
	private void optimizer_admission() throws NativeAbiError {
		if (optimizer_facts_sealed) {
			throw new NativeAbiError.INVALID_ABI ("optimizer facts are sealed after native construction");
		}
	}

	public void seal_optimizer_facts() {
		optimizer_facts_sealed = true;
	}

	public GenericArray<int> stack_objects { get; private set; default = new GenericArray<int> (); }
	private GenericArray<int> stack_origin = new GenericArray<int> ();
	public GenericArray<int> exact_calls { get; private set; default = new GenericArray<int> (); }
	private GenericArray<int> exact_origin = new GenericArray<int> ();
	public GenericArray<int> shared_elisions { get; private set; default = new GenericArray<int> (); }
	private GenericArray<int> shared_origin = new GenericArray<int> ();
	public void bind_shared_elision(int ordinal) throws NativeAbiError {
		optimizer_admission ();
		shared_elisions.add (ordinal);
		shared_origin.add (ordinal);
	}

	internal bool shared_elisions_valid() {
		if (shared_elisions.length != shared_origin.length) {
			return false;
		}
		for (int i = 0; i < shared_elisions.length; i++) {
			if (shared_elisions[i] != shared_origin[i]) {
				return false;
			}
		}
		return true;
	}

	public void bind_exact_call(int block, int instruction, int target) throws NativeAbiError {
		optimizer_admission ();
		exact_calls.add (block);
		exact_calls.add (instruction);
		exact_calls.add (target);
		exact_origin.add (block);
		exact_origin.add (instruction);
		exact_origin.add (target);
	}

	internal bool exact_calls_valid() {
		if (exact_calls.length != exact_origin.length) {
			return false;
		}
		for (int i = 0; i < exact_calls.length; i++) {
			if (exact_calls[i] != exact_origin[i]) {
				return false;
			}
		}
		return true;
	}

	public void bind_stack_object(int ordinal) throws NativeAbiError {
		optimizer_admission ();
		stack_objects.add (ordinal);
		stack_origin.add (ordinal);
	}

	internal bool stack_objects_valid() {
		if (stack_objects.length != stack_origin.length) {
			return false;
		}
		for (int i = 0; i < stack_objects.length; i++) {
			if (stack_objects[i] != stack_origin[i]) {
				return false;
			}
		}
		return true;
	}

	public void bind_effects(FunctionEffectFacts? facts, NativeOptimizerEvidence? imported = null) throws NativeAbiError {
		optimizer_admission ();
		if (effects_bound) {
			throw new NativeAbiError.INVALID_ABI ("derived effects bind once to their original verified body");
		}
		effects_bound = true;
		effect_facts = facts == null ? null : facts.copy ();
		effect_origin = facts == null ? null : facts.copy ();
		imported_effect_evidence = imported;
		if (imported != null && (facts == null || !imported.permits (facts))) {
			throw new NativeAbiError.INVALID_ABI ("imported effects differ from checked native object evidence");
		}
	}

	internal bool effects_valid() {
		return (effect_facts == null) == (effect_origin == null) && (effect_facts == null || (effect_facts.valid () && effect_facts.same (effect_origin)));
	}

	public GenericArray<NativeVectorMemoryPlan> vector_memory { get; private set; default = new GenericArray<NativeVectorMemoryPlan> (); }
	private GenericArray<NativeVectorMemoryPlan> vector_memory_origin = new GenericArray<NativeVectorMemoryPlan> ();
	public void bind_vector_memory(NativeVectorMemoryPlan contract) throws NativeAbiError {
		optimizer_admission ();
		vector_memory.add (contract.copy ());
		vector_memory_origin.add (contract.copy ());
	}

	internal bool vector_memory_valid() {
		if (vector_memory.length != vector_memory_origin.length) {
			return false;
		}
		for (int i = 0; i < vector_memory.length; i++) {
			var current = vector_memory[i];
			var original = vector_memory_origin[i];
			if (!current.valid () || !current.vector_type.same_type (original.vector_type) || current.alignment != original.alignment || current.store != original.store) {
				return false;
			}
		}
		return true;
	}

	public uint floating_policy { get; internal set; default = 0; }
	private uint floating_policy_origin;
	private bool floating_policy_bound;
	public void bind_floating_policy(uint permissions) {
		floating_policy = permissions;
		if (!floating_policy_bound) {
			floating_policy_origin = permissions;
			floating_policy_bound = true;
		}
	}

	public bool floating_policy_valid() {
		return floating_policy == floating_policy_origin && FloatingPointPermissions.valid (floating_policy);
	}

	private NativeGenericMethodInstance? generic_method_binding_origin;
	internal bool generic_method_matches() {
		return generic_method_instance == null ? generic_method_binding_origin == null : generic_method_binding_origin != null && generic_method_binding_origin.same_arguments (generic_method_instance);
	}

	public NativeGenericMethodInstance? generic_method_instance { get; internal set; }
	public ExactClassDefinitionIdentity? generic_method_origin { get; private set; }
	public int generic_method_member_origin { get; private set; default = -1; }
	internal void bind_generic_method(NativeGenericMethodInstance instance) throws NativeAbiError {
		if (generic_method_origin != null) {
			throw new NativeAbiError.INVALID_ABI ("generic method origin binds once to its original declaration");
		}
		generic_method_instance = instance;
		generic_method_origin = instance.definition;
		generic_method_member_origin = instance.member;
		generic_method_binding_origin = instance;
	}

	public GenericArray<NativeRecordOwnerPlan> record_owners { get; private set; default = new GenericArray<NativeRecordOwnerPlan> (); }
	public bool receiver_borrow { get; internal set; default = false; }
	public NativeRecordObservation? record_observation { get; internal set; }
	private NativeRecordObservation? declared_record_observation;
	internal void bind_record_observation(NativeRecordObservation observation) throws NativeAbiError {
		if (declared_record_observation != null || !receiver_borrow) {
			throw new NativeAbiError.INVALID_ABI ("record observation binds once to its original receiver declaration");
		}
		record_observation = declared_record_observation = observation;
	}

	internal bool matches_record_observation() {
		return record_observation == declared_record_observation;
	}

	public int virtual_slot { get; internal set; default = -1; }
	public bool utf8_factory { get; internal set; default = false; }
	public NativeLazyCache? lazy_cache { get; internal set; }
	public NativeCallableKind kind { get; private set; }
	public bool declaring_type_is_class { get; private set; }
	public int declaring_type_ordinal { get; private set; }
	public int declaring_struct_ordinal { get { return declaring_type_ordinal; } }
	public int property_ordinal { get; private set; }
	public int method_ordinal { get; private set; }
	public int ordinal { get; private set; }
	private string identifier;
	public string name { get { return identifier; } }
	public SourceSpan span { get; private set; }
	public SourceSpan name_span { get; private set; }
	public NativeSignature signature { get; private set; }
	public NativeLinkage linkage { get; private set; }
	private WeakRef containing_program = WeakRef (null);
	public NativeAbiProgram? owner { owned get { return (NativeAbiProgram?) containing_program.get (); } }

	internal NativeFunction (SourceSpan span, SourceSpan name_span, string name, int ordinal, NativeSignature signature, NativeLinkage linkage, int declaring_type_ordinal = -1, int method_ordinal = -1, bool declaring_type_is_class = false, NativeCallableKind kind = NativeCallableKind.FUNCTION, int property_ordinal = -1) {
		this.span = span;
		this.name_span = name_span;
		this.identifier = name;
		this.ordinal = ordinal;
		this.signature = signature;
		this.linkage = linkage;
		this.declaring_type_ordinal = declaring_type_ordinal;
		this.property_ordinal = property_ordinal;
		this.method_ordinal = method_ordinal;
		this.declaring_type_is_class = declaring_type_is_class;
		this.kind = kind == NativeCallableKind.FUNCTION && signature.receiver != null ? NativeCallableKind.METHOD : kind;
	}

	internal void claim_owner(NativeAbiProgram program) throws NativeAbiError {
		if (owner != null) {
			throw new NativeAbiError.INVALID_ABI ("internal native ABI construction error: function #%d already belongs to a program", ordinal);
		}
		containing_program.set (program);
	}

}

public class NativeAbiProgram : Object {
	public GenericArray<NativeCallbackViewPlan> callback_views { get; private set; default = new GenericArray<NativeCallbackViewPlan> (); }
	private GenericArray<NativeCallbackViewPlan> callback_view_origins = new GenericArray<NativeCallbackViewPlan> ();
	internal void bind_callback_view(NativeCallbackViewPlan plan) {
		callback_views.add (plan);
		callback_view_origins.add (plan);
	}

	internal bool callback_views_valid() {
		if (callback_views.length != callback_view_origins.length) {
			return false;
		}
		for (int p = 0; p < callback_views.length; p++) {
			if (callback_views[p] != callback_view_origins[p] || !callback_views[p].valid ()) {
				return false;
			}
		}
		return true;
	}

	public GenericArray<string> c_bool_policies { get; private set; default = new GenericArray<string> (); }
	private GenericArray<string> c_bool_origins = new GenericArray<string> ();
	internal void bind_c_bool_policy(string identity) {
		c_bool_policies.add (identity);
		c_bool_origins.add (identity);
	}

	internal bool c_bool_policies_valid() {
		if (c_bool_policies.length != c_bool_origins.length) {
			return false;
		}
		for (int i = 0; i < c_bool_policies.length; i++) {
			if (c_bool_policies[i] != c_bool_origins[i]) {
				return false;
			}
		}
		return true;
	}

	public GenericArray<string> gobject_imports { get; private set; default = new GenericArray<string> (); }
	private GenericArray<string> gobject_origins = new GenericArray<string> ();
	internal void bind_gobject_import(int ordinal, string policy_identity) {
		string identity = "%d;%s".printf (ordinal, policy_identity);
		gobject_imports.add (identity);
		gobject_origins.add (identity);
	}

	internal bool gobject_imports_valid() {
		if (gobject_imports.length != gobject_origins.length) {
			return false;
		}
		for (int i = 0; i < gobject_imports.length; i++) {
			if (gobject_imports[i] != gobject_origins[i]) {
				return false;
			}
		}
		return true;
	}

	public GenericArray<ForeignImportContract> class_imports { get; private set; default = new GenericArray<ForeignImportContract> (); }
	private GenericArray<ForeignImportContract> class_import_origins = new GenericArray<ForeignImportContract> ();
	internal void bind_class_import(ForeignImportContract contract) {
		class_imports.add (contract);
		class_import_origins.add (contract);
	}

	internal bool class_imports_valid() {
		if (class_imports.length != class_import_origins.length) {
			return false;
		}
		for (int i = 0; i < class_imports.length; i++) {
			if (class_imports[i] != class_import_origins[i] || !class_imports[i].valid ()) {
				return false;
			}
		}
		return true;
	}

	public GenericArray<ComImportContract> com_imports { get; private set; default = new GenericArray<ComImportContract> (); }
	private GenericArray<string> com_origins = new GenericArray<string> ();
	internal void bind_com_import(ComImportContract contract) {
		com_imports.add (contract.copy ());
		com_origins.add (contract.identity ());
	}

	internal bool com_imports_valid() {
		if (com_imports.length != com_origins.length) {
			return false;
		}
		for (int i = 0; i < com_imports.length; i++) {
			if (com_imports[i] == null || !com_imports[i].valid () || com_imports[i].identity () != com_origins[i]) {
				return false;
			}
		}
		return true;
	}

	public GenericArray<PodRepresentation> pod_layouts { get; private set; default = new GenericArray<PodRepresentation> (); }
	private GenericArray<PodRepresentation> pod_origins = new GenericArray<PodRepresentation> ();
	public void bind_pod_layout(PodRepresentation policy) {
		var copy = policy.copy ();
		pod_layouts.add (copy);
		pod_origins.add (copy);
	}

	internal bool pod_layouts_valid() {
		if (pod_layouts.length != pod_origins.length) {
			return false;
		}
		for (int i = 0; i < pod_layouts.length; i++) {
			if (pod_layouts[i] != pod_origins[i] || !pod_layouts[i].valid ()) {
				return false;
			}
		}
		return true;
	}

	public GenericArray<NativeActorPlan> actor_operations { get; private set; default = new GenericArray<NativeActorPlan> (); }
	public GenericArray<NativeRetainedPlan> retained_operations { get; private set; default = new GenericArray<NativeRetainedPlan> (); }
	private GenericArray<NativeRetainedPlan> retained_origins = new GenericArray<NativeRetainedPlan> ();
	internal void bind_retained_operation(NativeRetainedPlan plan) {
		retained_operations.add (plan);
		retained_origins.add (plan);
	}

	internal bool retained_operations_valid() {
		if (retained_operations.length != retained_origins.length) {
			return false;
		}
		for (int p = 0; p < retained_operations.length; p++) {
			if (retained_operations[p] != retained_origins[p] || !retained_operations[p].valid_signature ()) {
				return false;
			}
		}
		return true;
	}

	public GenericArray<NativeRecordApplicationPlan> record_applications { get; private set; default = new GenericArray<NativeRecordApplicationPlan> (); }
	private GenericArray<NativeRecordApplicationPlan> record_application_origins = new GenericArray<NativeRecordApplicationPlan> ();
	internal void bind_record_application(NativeRecordApplicationPlan plan) {
		record_applications.add (plan);
		record_application_origins.add (plan);
	}

	internal bool record_applications_valid() {
		if (record_applications.length != record_application_origins.length) {
			return false;
		}
		for (int a = 0; a < record_applications.length; a++) {
			if (record_applications[a] != record_application_origins[a]) {
				return false;
			}
		}
		return true;
	}

	public GenericArray<NativeClosurePlan> closures { get; private set; default = new GenericArray<NativeClosurePlan> (); }
	public GenericArray<NativeSharedOperationPlan> shared_operations { get; private set; default = new GenericArray<NativeSharedOperationPlan> (); }
	public GenericArray<NativeScalarOwner> callable_resources { get; private set; default = new GenericArray<NativeScalarOwner> (); }
	private GenericArray<NativeScalarOwner> callable_resource_origins = new GenericArray<NativeScalarOwner> ();
	internal void bind_callable_resource(NativeScalarOwner resource) {
		callable_resources.add (resource);
		callable_resource_origins.add (resource);
	}

	internal bool callable_resources_valid() {
		if (callable_resources.length != callable_resource_origins.length) {
			return false;
		}
		for (int p = 0; p < callable_resources.length; p++) {
			if (!callable_resources[p].same_owner (callable_resource_origins[p])) {
				return false;
			}
		}
		return true;
	}

	public GenericArray<NativeFunctionValuePlan> function_values { get; private set; default = new GenericArray<NativeFunctionValuePlan> (); }
	public uint interface_count { get; internal set; default = 0; }
	public GenericArray<NativePrivateFieldAccess> private_accesses { get; private set; default = new GenericArray<NativePrivateFieldAccess> (); }
	public uint private_access_count { get; private set; }
	private bool private_accesses_bound;
	internal void bind_private_accesses(GenericArray<NativePrivateFieldAccess> accesses) throws NativeAbiError {
		if (private_accesses_bound) {
			throw new NativeAbiError.INVALID_ABI ("private field access inventory is immutable once bound");
		}
		private_accesses_bound = true;
		private_accesses = accesses;
		private_access_count = accesses.length;
	}

	public GenericArray<NativeAsyncFramePlan> async_frames { get; private set; default = new GenericArray<NativeAsyncFramePlan> (); }
	public GenericArray<NativeClassPlan> classes { get; private set; default = new GenericArray<NativeClassPlan> (); }
	public GenericArray<NativeSumPlan> sum_values { get; private set; default = new GenericArray<NativeSumPlan> (); }
	public GenericArray<NativeContinuationRegionPlan> continuations { get; private set; default = new GenericArray<NativeContinuationRegionPlan> (); }
	public GenericArray<NativeRecordElement> record_elements { get; private set; default = new GenericArray<NativeRecordElement> (); }
	public GenericArray<NativeStructValuePlan> struct_values { get; private set; default = new GenericArray<NativeStructValuePlan> (); }
	public GenericArray<NativeRecordDeclarationPlan> record_declarations { get; private set; default = new GenericArray<NativeRecordDeclarationPlan> (); }
	public SourceSpan span { get; private set; }
	public NativeAbiVersion abi_version { get; private set; }
	public GenericArray<NativeFunction> functions { get; private set; }

	internal NativeAbiProgram (SourceSpan span, NativeAbiVersion abi_version, GenericArray<NativeFunction> functions) throws NativeAbiError {
		this.span = span;
		this.abi_version = abi_version;
		this.functions = functions;
		for (int i = 0; i < functions.length; i++) {
			functions[i].claim_owner (this);
		}
	}

}
}

namespace Astra.NativeAbi {
public class NativeCallableRecordParameter : Object {
	public NativeStructValueMode mode { get; private set; }
	public int source_ordinal { get; private set; }
	public int first_leaf { get; private set; }
	private string identifier;
	public string record_name { get { return identifier; } }
	public GenericArray<NativeStructLeafChannel> leaves { get; private set; }
	internal NativeCallableRecordParameter (int source_ordinal, int first_leaf, string record_name, GenericArray<NativeStructLeafChannel> leaves, NativeStructValueMode mode = NativeStructValueMode.COPY_VALUE) {
		this.mode = mode;
		this.source_ordinal = source_ordinal;
		this.first_leaf = first_leaf;
		this.identifier = record_name;
		this.leaves = leaves;
	}

	internal NativeCallableRecordParameter copy() {
		var copied = new GenericArray<NativeStructLeafChannel> ();
		foreach (var leaf in leaves) {
			copied.add (new NativeStructLeafChannel (leaf.field_path, leaf.abi_type, leaf.storage_path, leaf.buffer_component));
		}
		return new NativeCallableRecordParameter (source_ordinal, first_leaf, record_name, copied, mode);
	}

	public bool same_type(NativeCallableRecordParameter other) {
		if (source_ordinal != other.source_ordinal || first_leaf != other.first_leaf || record_name != other.record_name || mode != other.mode || leaves.length != other.leaves.length) {
			return false;
		}
		for (int i = 0; i < leaves.length; i++) {
			if (leaves[i].field_path != other.leaves[i].field_path || leaves[i].storage_path != other.leaves[i].storage_path || leaves[i].buffer_component != other.leaves[i].buffer_component || !leaves[i].abi_type.same_type (other.leaves[i].abi_type)) {
				return false;
			}
		}
		return true;
	}

}
public class NativeCallableBorrowChannel : Object {
	public int ordinal {
		get;
		private set;
	}
	private string identifier;
	public string type_name { get { return identifier; } }
	public bool is_class {
		get;
		private set;
	}
	internal NativeCallableBorrowChannel (int ordinal, string type_name, bool is_class) {
		this.ordinal = ordinal;
		this.identifier = type_name;
		this.is_class = is_class;
	}

	public bool same_channel(NativeCallableBorrowChannel other) {
		return ordinal == other.ordinal && type_name == other.type_name && is_class == other.is_class;
	}

}
public class NativeCallableOwnedChannel : Object {
	public int ordinal { get; private set; }
	private string identifier;
	public string type_name { get { return identifier; } }
	public bool is_class { get; private set; }
	internal NativeCallableOwnedChannel (int ordinal, string type_name, bool is_class = false) {
		this.ordinal = ordinal;
		identifier = type_name;
		this.is_class = is_class;
	}

	public bool same_channel(NativeCallableOwnedChannel other) {
		return ordinal == other.ordinal && type_name == other.type_name && is_class == other.is_class;
	}

}
public class NativeCallableOwnedArgument : Object {
	public int ordinal { get; private set; }
	public NativeScalarOwner resource { get; private set; }
	public int source_ordinal { get; private set; }
	public bool null_argument { get; private set; }
	public bool committed_null { get; private set; }
	internal NativeCallableOwnedArgument (int ordinal, NativeScalarOwner resource, int source_ordinal, bool null_argument, bool committed_null) {
		this.ordinal = ordinal;
		this.resource = resource;
		this.source_ordinal = source_ordinal;
		this.null_argument = null_argument;
		this.committed_null = committed_null;
	}

	public bool same_transfer(NativeCallableOwnedArgument other) {
		return ordinal == other.ordinal && resource.same_owner (other.resource) && source_ordinal == other.source_ordinal && null_argument == other.null_argument && committed_null == other.committed_null;
	}

}
public class NativeCallableRecordResult : Object {
	private string identifier;
	public string record_name { get { return identifier; } }
	public NativeStructValueMode mode { get; private set; }
	public GenericArray<NativeStructLeafChannel> leaves { get; private set; }
	internal NativeCallableRecordResult (string record_name, GenericArray<NativeStructLeafChannel> leaves, NativeStructValueMode mode) {
		identifier = record_name;
		this.leaves = leaves;
		this.mode = mode;
	}

	internal NativeCallableRecordResult copy() {
		var copied = new GenericArray<NativeStructLeafChannel> ();
		foreach (var leaf in leaves) {
			copied.add (new NativeStructLeafChannel (leaf.field_path, leaf.abi_type, leaf.storage_path, leaf.buffer_component));
		}
		return new NativeCallableRecordResult (record_name, copied, mode);
	}

	public bool matches(string name, NativeStructValueMode mode, GenericArray<NativeStructLeafChannel> other) {
		if (record_name != name || this.mode != mode || leaves.length != other.length) {
			return false;
		}
		for (int l = 0; l < leaves.length; l++) {
			if (leaves[l].field_path != other[l].field_path || leaves[l].storage_path != other[l].storage_path || leaves[l].buffer_component != other[l].buffer_component || !leaves[l].abi_type.same_type (other[l].abi_type)) {
				return false;
			}
		}
		return true;
	}

	public bool same_type(NativeCallableRecordResult other) {
		return matches (other.record_name, other.mode, other.leaves);
	}

}
public class NativeFunctionPointerType : NativeScalarAbiType {
	private GenericArray<NativeCallableRecordParameter> declared_record_parameters = new GenericArray<NativeCallableRecordParameter> ();
	internal bool record_parameter_modes_valid() {
		if (record_parameters.length != declared_record_parameters.length) {
			return false;
		}
		for (int p = 0; p < record_parameters.length; p++) {
			var actual = record_parameters[p];
			var original = declared_record_parameters[p];
			if (actual.source_ordinal != original.source_ordinal || actual.first_leaf != original.first_leaf || actual.record_name != original.record_name || actual.mode != original.mode || actual.leaves.length != original.leaves.length) {
				return false;
			}
		}
		return true;
	}

	internal bool record_parameter_leaves_valid() {
		if (!record_parameter_modes_valid ()) {
			return false;
		}
		for (int p = 0; p < record_parameters.length; p++) {
			if (!record_parameters[p].same_type (declared_record_parameters[p])) {
				return false;
			}
		}
		return true;
	}

	public NativeCallableRecordResult? record_result { get; private set; }
	private NativeCallableRecordResult? declared_record_result;
	internal bool record_result_valid() {
		return record_result == null ? declared_record_result == null : declared_record_result != null && record_result.same_type (declared_record_result);
	}

	public NativeCallableOwnedChannel? owned_result { get; private set; }
	private NativeCallableOwnedChannel? declared_owned_result;
	public GenericArray<NativeCallableOwnedChannel> owned_parameters { get; private set; }
	private GenericArray<NativeCallableOwnedChannel> declared_owned_parameters = new GenericArray<NativeCallableOwnedChannel> ();
	internal bool owned_channels_valid() {
		if (owned_result == null ? declared_owned_result != null : declared_owned_result == null || !owned_result.same_channel (declared_owned_result)) {
			return false;
		}
		if (owned_parameters.length != declared_owned_parameters.length) {
			return false;
		}
		for (int p = 0; p < owned_parameters.length; p++) {
			if (!owned_parameters[p].same_channel (declared_owned_parameters[p])) {
				return false;
			}
		}
		return true;
	}

	public GenericArray<NativeCallableBorrowChannel> borrowed_parameters {
		get;
		private set;
	}
	public GenericArray<NativeCallableRecordParameter> record_parameters {
		get;
		private set;
	}
	private NativeScalarType? scalar_result;
	public bool void_result { get; private set; }
	public NativeScalarType? result_scalar() {
		return scalar_result;
	}

	public GenericArray<NativeAbiType> parameter_types {
		get;
		private set;
	}
	internal NativeFunctionPointerType (NativeScalarType? result, GenericArray<NativeAbiType> parameters, GenericArray<NativeCallableRecordParameter>? records = null, GenericArray<NativeCallableBorrowChannel>? borrows = null, GenericArray<NativeCallableOwnedChannel>? owned_channels = null, NativeCallableOwnedChannel? owned_result = null, NativeCallableRecordResult? record_result = null, bool void_result = false) {
		base (NativeScalarType.PTR);
		scalar_result = result;
		this.void_result = void_result;
		this.record_result = record_result;
		declared_record_result = record_result == null ? null : record_result.copy ();
		this.owned_result = owned_result;
		declared_owned_result = owned_result == null ? null : new NativeCallableOwnedChannel (owned_result.ordinal, owned_result.type_name, owned_result.is_class);
		parameter_types = parameters;
		record_parameters = records ?? new GenericArray<NativeCallableRecordParameter> ();
		foreach (var group in record_parameters) {
			declared_record_parameters.add (group.copy ());
		}
		borrowed_parameters = borrows ?? new GenericArray<NativeCallableBorrowChannel> ();
		owned_parameters = owned_channels ?? new GenericArray<NativeCallableOwnedChannel> ();
		foreach (var channel in owned_parameters) {
			declared_owned_parameters.add (channel);
		}
	}

	public override string spelling() {
		string name = "native-code<" + (void_result ? "void" : record_result == null ? scalar_result.spelling () : "record=" + record_result.record_name + ":" + record_result.mode.to_string ());
		if (record_result != null) {
			foreach (var leaf in record_result.leaves) {
				name += ":" + leaf.field_path + "=" + leaf.abi_type.spelling ();
			}
		}
		if (owned_result != null) {
			name += ";owned-result=" + owned_result.type_name;
		}
		foreach (var parameter in parameter_types) {
			name += "," + parameter.spelling ();
		}
		foreach (var channel in borrowed_parameters) {
			name += ";borrowed%d=%s:%s".printf (channel.ordinal, channel.is_class ? "Class" : "Resource", channel.type_name);
		}
		foreach (var channel in owned_parameters) {
			name += ";owned%d=%s:%s".printf (channel.ordinal, channel.is_class ? "Class" : "Resource", channel.type_name);
		}
		foreach (var record in record_parameters) {
			name += ";record%d@%d=%s".printf (record.source_ordinal, record.first_leaf, record.record_name);
			if (record.mode != NativeStructValueMode.COPY_VALUE) {
				name += record.mode == NativeStructValueMode.BORROW_VALUE ? ":BORROW_VALUE" : ":MOVE_VALUE";
			}
			foreach (var leaf in record.leaves) {
				name += ":" + leaf.field_path + "=" + leaf.abi_type.spelling ();
			}
		}
		return name + ">";
	}

	public override bool same_type(NativeAbiType other) {
		var signature = other as NativeFunctionPointerType;
		if (signature == null || (record_result == null ? signature.record_result != null : signature.record_result == null || !record_result.same_type (signature.record_result))) {
			return false;
		}
		if (signature == null || (signature is NativeCallbackType) != (this is NativeCallbackType) || signature.void_result != void_result || (owned_result == null ? signature.owned_result != null : signature.owned_result == null || !owned_result.same_channel (signature.owned_result)) || signature.result_scalar () != scalar_result || signature.parameter_types.length != parameter_types.length || signature.record_parameters.length != record_parameters.length || signature.borrowed_parameters.length != borrowed_parameters.length || signature.owned_parameters.length != owned_parameters.length) {
			return false;
		}
		for (int i = 0; i < parameter_types.length; i++) {
			if (!parameter_types[i].same_type (signature.parameter_types[i])) {
				return false;
			}
		}
		for (int i = 0; i < record_parameters.length; i++) {
			if (!record_parameters[i].same_type (signature.record_parameters[i])) {
				return false;
			}
		}
		for (int i = 0; i < borrowed_parameters.length; i++) {
			if (!borrowed_parameters[i].same_channel (signature.borrowed_parameters[i])) {
				return false;
			}
		}
		for (int i = 0; i < owned_parameters.length; i++) {
			if (!owned_parameters[i].same_channel (signature.owned_parameters[i])) {
				return false;
			}
		}
		return true;
	}

}
}

namespace Astra.NativeAbi {
// Call-only view of native code plus its opaque context. The logical scalar
// signature excludes that context; invocation supplies it as the first input.
public class NativeCallbackViewPlan : Object {
	public int caller { get; private set; }
	public int block { get; private set; }
	public int instruction { get; private set; }
	public int argument { get; private set; }
	public NativeClosureHandleType closure { get; private set; }
	public NativeCallbackType callback { get; private set; }
	private string original;
	internal NativeCallbackViewPlan (int caller, int block, int instruction, int argument, NativeClosureHandleType closure, NativeCallbackType callback) {
		this.caller = caller;
		this.block = block;
		this.instruction = instruction;
		this.argument = argument;
		this.closure = closure;
		this.callback = callback;
		original = identity ();
	}

	public string identity() {
		return "%d/%d/%d/%d;%s;%s".printf (caller, block, instruction, argument, closure.spelling (), callback.spelling ());
	}

	public bool valid() {
		if (caller < 0 || block < 0 || instruction < 0 || argument < 0 || identity () != original || closure.actor || closure.threaded || closure.checked_error != null || closure.environment == "" || !callback.call_scoped || callback.carrier_fields != 2 || closure.signature.void_result != callback.void_result || closure.signature.result_scalar () != callback.result_scalar () || closure.signature.parameter_types.length != callback.parameter_types.length || closure.signature.borrowed_parameters.length != 0 || closure.signature.owned_parameters.length != 0 || closure.signature.record_parameters.length != 0 || closure.signature.owned_result != null || closure.signature.record_result != null) {
			return false;
		}
		for (int p = 0; p < callback.parameter_types.length; p++) {
			if (!closure.signature.parameter_types[p].same_type (callback.parameter_types[p])) {
				return false;
			}
		}
		return true;
	}

}
public class NativeCallbackType : NativeFunctionPointerType {
	public uint carrier_fields { get { return 2; } }
	public bool call_scoped { get { return true; } }
	internal NativeCallbackType (NativeScalarType? result, GenericArray<NativeAbiType> parameters, bool void_result) {
		base (result, parameters, null, null, null, null, null, void_result);
	}

	public override string spelling() {
		return "borrowed-callback-view<code,context;" + base.spelling () + ">";
	}

}
public class NativeFunctionValuePlan : Object {
	public NativeStructValuePlan? record_result { get; private set; }
	private NativeStructValuePlan? declared_record_result;
	internal bool record_result_valid() {
		return record_result == declared_record_result;
	}

	public NativeScalarOwner? result_owner { get; private set; }
	private NativeScalarOwner? declared_result_owner;
	internal bool result_owner_valid() {
		return result_owner == null ? declared_result_owner == null : declared_result_owner != null && result_owner.same_owner (declared_result_owner);
	}

	public GenericArray<NativeCallableOwnedArgument> owned_arguments { get; private set; }
	private GenericArray<NativeCallableOwnedArgument> declared_owned_arguments = new GenericArray<NativeCallableOwnedArgument> ();
	internal bool owned_arguments_valid() {
		if (owned_arguments.length != declared_owned_arguments.length) {
			return false;
		}
		for (int p = 0; p < owned_arguments.length; p++) {
			if (!owned_arguments[p].same_transfer (declared_owned_arguments[p])) {
				return false;
			}
		}
		return true;
	}

	public GenericArray<NativeCallableBorrowChannel> borrowed_arguments {
		get;
		private set;
	}
	public GenericArray<NativeCallableRecordParameter> record_arguments {
		get;
		private set;
	}
	public int caller {
		get;
		private set;
	}
	public int block {
		get;
		private set;
	}
	public int instruction {
		get;
		private set;
	}
	public NativeFunctionPointerType signature {
		get;
		private set;
	}
	internal NativeFunctionValuePlan (int caller, int block, int instruction, NativeFunctionPointerType signature, GenericArray<NativeCallableRecordParameter>? records = null, GenericArray<NativeCallableBorrowChannel>? borrows = null, GenericArray<NativeCallableOwnedArgument>? transfers = null, NativeScalarOwner? result_owner = null, NativeStructValuePlan? record_result = null) {
		this.record_result = declared_record_result = record_result;
		this.result_owner = result_owner;
		declared_result_owner = result_owner == null ? null : new NativeScalarOwner (result_owner.type_name, result_owner.cleanup_symbol, result_owner.class_ordinal);
		this.caller = caller;
		this.block = block;
		this.instruction = instruction;
		this.signature = signature;
		record_arguments = records ?? new GenericArray<NativeCallableRecordParameter> ();
		borrowed_arguments = borrows ?? new GenericArray<NativeCallableBorrowChannel> ();
		owned_arguments = transfers ?? new GenericArray<NativeCallableOwnedArgument> ();
		foreach (var transfer in owned_arguments) {
			declared_owned_arguments.add (transfer);
		}
	}

}
}

namespace Astra.NativeAbi {
public class NativeSharedHandleType : NativeScalarAbiType {
	public NativeClosureHandleType? actor_sender { get; private set; }
	public bool intrusive { get; private set; }
	private string payload_name;
	public string payload { get { return payload_name; } }
	public bool is_weak { get; private set; }
	internal NativeSharedHandleType (string payload, bool is_weak, bool intrusive = false, NativeClosureHandleType? actor_sender = null) {
		base (NativeScalarType.PTR);
		this.actor_sender = actor_sender;
		this.intrusive = intrusive;
		this.payload_name = payload;
		this.is_weak = is_weak;
	}

	public override string spelling() {
		return (is_weak ? "weak-control<" : "strong-control<") + payload + ">";
	}

	public override bool same_type(NativeAbiType other) {
		var handle = other as NativeSharedHandleType;
		return handle != null && (actor_sender == null ? handle.actor_sender == null : handle.actor_sender != null && handle.actor_sender.same_type (actor_sender)) && handle.intrusive == intrusive && handle.payload == payload && handle.is_weak == is_weak;
	}

}
public class NativeSharedOperationPlan : Object {
	public int caller { get; private set; }
	public int block { get; private set; }
	public int instruction { get; private set; }
	public int action { get; private set; }
	public NativeSharedHandleType handle { get; private set; }
	internal NativeSharedOperationPlan (int caller, int block, int instruction, int action, NativeSharedHandleType handle) {
		this.caller = caller;
		this.block = block;
		this.instruction = instruction;
		this.action = action;
		this.handle = handle;
	}

}
}

namespace Astra.NativeAbi {
public class NativeClosureHandleType : NativeScalarAbiType {
	public bool actor { get; private set; }
	private string? actor_message_name;
	public string? actor_message { get { return actor_message_name; } }
	public bool threaded { get; private set; }
	private string environment_name;
	public string environment { get { return environment_name; } }
	public NativeFunctionPointerType signature { get; private set; }
	private string? checked_error_identifier;
	public string? checked_error { get { return checked_error_identifier; } }
	internal NativeClosureHandleType (string environment, NativeFunctionPointerType signature, string? checked_error = null, bool threaded = false, bool actor = false, string? actor_message = null) {
		base (NativeScalarType.PTR);
		this.actor = actor;
		this.actor_message_name = actor_message;
		this.threaded = threaded;
		this.environment_name = environment;
		this.signature = signature;
		this.checked_error_identifier = checked_error;
	}

	public override string spelling() {
		if (actor) {
			return "actor-sender<" + environment + "," + (actor_message ?? signature.parameter_types[0].spelling ()) + ">";
		}
		return (checked_error == null ? (threaded ? "owned-thread<" : "owned-closure<") : "checked-owned-closure<" + checked_error + ",") + environment + "," + signature.spelling () + ">";
	}

	public override bool same_type(NativeAbiType other) {
		var closure = other as NativeClosureHandleType;
		return closure != null && closure.actor == actor && closure.actor_message == actor_message && closure.threaded == threaded && closure.environment == environment && closure.checked_error == checked_error && closure.signature.same_type (signature);
	}

}
public class NativeClosurePlan : Object {
	public NativeStructValuePlan? record_result { get; private set; }
	private NativeStructValuePlan? declared_record_result;
	internal bool record_result_valid() {
		return record_result == declared_record_result;
	}

	public NativeScalarOwner? result_owner { get; private set; }
	private NativeScalarOwner? declared_result_owner;
	internal bool result_owner_valid() {
		return result_owner == null ? declared_result_owner == null : declared_result_owner != null && result_owner.same_owner (declared_result_owner);
	}

	public GenericArray<NativeCallableOwnedArgument> owned_arguments { get; private set; }
	private GenericArray<NativeCallableOwnedArgument> declared_owned_arguments = new GenericArray<NativeCallableOwnedArgument> ();
	internal bool owned_arguments_valid() {
		if (owned_arguments.length != declared_owned_arguments.length) {
			return false;
		}
		for (int p = 0; p < owned_arguments.length; p++) {
			if (!owned_arguments[p].same_transfer (declared_owned_arguments[p])) {
				return false;
			}
		}
		return true;
	}

	public GenericArray<NativeCallableRecordParameter> record_arguments { get; private set; }
	public GenericArray<NativeCallableBorrowChannel> borrowed_arguments {
		get;
		private set;
	}
	public ActorBindingSpec? actor_binding {
		get;
		private set;
	}
	public int caller {
		get;
		private set;
	}
	public int block {
		get;
		private set;
	}
	public int instruction {
		get;
		private set;
	}
	public bool binding {
		get;
		private set;
	}
	public NativeClosureHandleType handle {
		get;
		private set;
	}
	public int target {
		get;
		private set;
	}
	public int destructor {
		get;
		private set;
	}
	internal NativeClosurePlan (int caller, int block, int instruction, bool binding, NativeClosureHandleType handle, int target = -1, int destructor = -1, ActorBindingSpec? actor_binding = null, GenericArray<NativeCallableBorrowChannel>? borrows = null, GenericArray<NativeCallableRecordParameter>? records = null, GenericArray<NativeCallableOwnedArgument>? transfers = null, NativeScalarOwner? result_owner = null, NativeStructValuePlan? record_result = null) {
		this.record_result = declared_record_result = record_result;
		this.result_owner = result_owner;
		declared_result_owner = result_owner == null ? null : new NativeScalarOwner (result_owner.type_name, result_owner.cleanup_symbol, result_owner.class_ordinal);
		record_arguments = records ?? new GenericArray<NativeCallableRecordParameter> ();
		owned_arguments = transfers ?? new GenericArray<NativeCallableOwnedArgument> ();
		foreach (var transfer in owned_arguments) {
			declared_owned_arguments.add (transfer);
		}
		borrowed_arguments = borrows ?? new GenericArray<NativeCallableBorrowChannel> ();
		this.actor_binding = actor_binding == null ? null : actor_binding.copy ();
		this.caller = caller;
		this.block = block;
		this.instruction = instruction;
		this.binding = binding;
		this.handle = handle;
		this.target = target;
		this.destructor = destructor;
	}

}
}

namespace Astra.NativeAbi {
public class NativeRetainedPlan : Object {
	public int caller { get; private set; } public int block { get; private set; } public int instruction { get; private set; } public int action { get; private set; }
	public NativeClosureHandleType handle { get; private set; }
	private string original_signature;
	public bool typed_signal { get { return action >= 7 && action <= 9; } }
	public static Astra.Source.ForeignValueType? signal_callback (NativeClosureHandleType handle) {
		var signature = handle.signature;
		if (handle.actor || handle.threaded || handle.checked_error != null || !signature.void_result || signature.owned_result != null || signature.record_result != null || signature.owned_parameters.length != 0 || signature.borrowed_parameters.length != 0 || signature.record_parameters.length != 0 || signature.parameter_types.length > 4) {
			return null;
		}
		var parameters = new GenericArray<Astra.Source.ForeignValueType> ();
		foreach (var parameter in signature.parameter_types) {
			var scalar = parameter as NativeScalarAbiType;
			if (scalar == null || scalar.get_type () != typeof (NativeScalarAbiType)) {
				return null;
			}
			Astra.Source.ForeignValueKind kind;
			switch (scalar.scalar_type) {
			case NativeScalarType.I32: kind = Astra.Source.ForeignValueKind.I32;
				break;
			case NativeScalarType.U32: kind = Astra.Source.ForeignValueKind.U32;
				break;
			case NativeScalarType.I64: kind = Astra.Source.ForeignValueKind.I64;
				break;
			case NativeScalarType.U64: kind = Astra.Source.ForeignValueKind.U64;
				break;
			case NativeScalarType.F32: kind = Astra.Source.ForeignValueKind.F32;
				break;
			case NativeScalarType.F64: kind = Astra.Source.ForeignValueKind.F64;
				break;
			case NativeScalarType.B1: kind = Astra.Source.ForeignValueKind.BOOL;
				break;
				default: return null;
			}
			parameters.add (new Astra.Source.ForeignValueType (kind));
		}
		return new Astra.Source.ForeignValueType (Astra.Source.ForeignValueKind.CALLBACK, "", null, parameters, new Astra.Source.ForeignValueType (Astra.Source.ForeignValueKind.VOID));
	}
	public bool valid_signature() {
		if (handle.spelling () != original_signature || action < 0 || action > 9 || handle.actor || handle.checked_error != null || handle.threaded != (action >= 4 && action <= 6)) {
			return false;
		}
		if (typed_signal) {
			return signal_callback (handle) != null;
		}
		return !handle.signature.void_result && handle.signature.result_scalar () == NativeScalarType.I32 && handle.signature.parameter_types.length == 1 && handle.signature.parameter_types[0].same_type (new NativeScalarAbiType (NativeScalarType.I32));
	}

	internal NativeRetainedPlan (int caller, int block, int instruction, int action, NativeClosureHandleType handle) {
		this.caller = caller;
		this.block = block;
		this.instruction = instruction;
		this.action = action;
		this.handle = handle;
		original_signature = handle.spelling ();
	}

}
}

namespace Astra.NativeAbi {
public class NativeActorPlan : Object {
	public int caller { get; private set; }
	public int block { get; private set; }
	public int instruction { get; private set; }
	public ActorAction action { get; private set; }
	public NativeClosureHandleType sender { get; private set; }
	public int error_class { get; private set; }
	internal NativeActorPlan (int caller, int block, int instruction, ActorAction action, NativeClosureHandleType sender, int error_class) {
		this.caller = caller;
		this.block = block;
		this.instruction = instruction;
		this.action = action;
		this.sender = sender;
		this.error_class = error_class;
	}

}
}
