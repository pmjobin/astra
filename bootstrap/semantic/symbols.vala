// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Foreign;

namespace Astra.Semantic {
public abstract class Symbol : Object {
	public string name { get { return identifier; } }
	private string identifier;
	public SourceSpan span { get; private set; }
	public SourceSpan name_span { get; private set; }

	protected Symbol (SourceSpan span, SourceSpan name_span, string? name = null) {
		this.span = span;
		this.name_span = name_span;
		this.identifier = name ?? name_span.text ();
	}

}

public class HandleSymbol : Symbol {
	private string context_contract = "";
	public string context_mode { get { return context_contract; } }
	public ForeignImportContract? c_import { get; internal set; }
	public ComImportContract? com_import { get; internal set; }
	public HandleType semantic_type { get; private set; }
	public CForeignCleanupContract cleanup { get; private set; }
	public CForeignHeader? header { get; private set; }
	public int ordinal { get; private set; }

	internal HandleSymbol (SourceSpan span, SourceSpan name_span, CForeignCleanupContract cleanup, CForeignHeader? header, int ordinal, string foreign_identity = "", string context_mode = "") {
		base (span, name_span);
		this.context_contract = context_mode;
		this.semantic_type = new HandleType (name, foreign_identity, context_mode, context_mode == "" ? "" : cleanup.external_symbol);
		this.cleanup = cleanup;
		this.header = header;
		this.ordinal = ordinal;
	}

	internal HandleSymbol.closure (SourceSpan span, ClosureHandleType type, CForeignCleanupContract cleanup, int ordinal) {
		base (span, span, type.name);
		this.semantic_type = type;
		this.cleanup = cleanup;
		this.ordinal = ordinal;
	}
	internal HandleSymbol.shared (SourceSpan span, SharedHandleType type, CForeignCleanupContract cleanup, int ordinal) {
		base (span, span, type.name);
		this.semantic_type = type;
		this.cleanup = cleanup;
		this.ordinal = ordinal;
	}
}

public abstract class NativeInstanceSymbol : Symbol {
	public int ordinal { get; private set; }
	public ReceiverType receiver_type { get; private set; }
	public GenericArray<PropertySymbol> properties { get; private set; default = new GenericArray<PropertySymbol> (); }
	public GenericArray<MethodSymbol> methods { get; private set; default = new GenericArray<MethodSymbol> (); }
	public SemanticType semantic_type { get; private set; }
	public GenericArray<StructFieldSymbol> fields { get; private set; }

	protected NativeInstanceSymbol (SourceSpan span, SourceSpan name_span, SemanticType semantic_type, int ordinal, string? name = null) {
		base (span, name_span, name);
		this.semantic_type = semantic_type;
		this.ordinal = ordinal;
		this.receiver_type = new ReceiverType (semantic_type);
		this.fields = new GenericArray<StructFieldSymbol> ();
	}

	internal Symbol? find_declared_member(string name) {
		foreach (var field in fields) {
			if (field.name == name) {
				return field;
			}
		}
		foreach (var method in methods) {
			if (method.name == name) {
				return method;
			}
		}
		foreach (var property in properties) {
			if (property.name == name) {
				return property;
			}
		}
		var object_class = this as ClassSymbol;
		if (object_class != null && name == "init") {
			return object_class.constructor;
		}
		if (object_class != null && name == "deinit") {
			return object_class.destructor;
		}
		return null;
	}

	internal Symbol? find_member(string name) {
		var member = find_declared_member (name);
		return member != null ? member : (this is ClassSymbol && ((ClassSymbol) this).parent_class != null) ? ((ClassSymbol) this).parent_class.find_member (name) : null;
	}

	internal StructFieldSymbol? find_field(string name) {
		return find_member (name) as StructFieldSymbol;
	}

	internal MethodSymbol? find_method(string name) {
		return find_member (name) as MethodSymbol;
	}

	internal PropertySymbol? find_property(string name) {
		return find_member (name) as PropertySymbol;
	}

}

public class StructSymbol : NativeInstanceSymbol {
	public OwnedRecordInstantiation? owning_instantiation { get; internal set; }
	public PodRepresentation? representation { get; internal set; }
	internal StructSymbol (SourceSpan span, SourceSpan name_span, int ordinal = 0, string? name = null) {
		base (span, name_span, new StructType (name ?? name_span.text ()), ordinal, name);
	}

}

public class ClassSymbol : NativeInstanceSymbol {
	public NativeDeclarationIdentity? native_destructor_declaration { get; internal set; }
	public ForeignClassPolicy? foreign_export { get; internal set; }
	public ConcurrencyPolicy? concurrency_policy { get; internal set; }
	public AllocationPolicy? allocation_policy { get; internal set; }
	public ExactClassGenericInstance? generic_instance { get; internal set; }
	public ClassSymbol? parent_class { get; internal set; }
	public bool polymorphic { get; internal set; default = false; }
	public bool exception_root { get; internal set; default = false; }
	public GenericArray<FunctionSymbol> virtual_entries { get; private set; default = new GenericArray<FunctionSymbol> (); }
	public ConstructorSymbol? constructor { get; internal set; }
	public DestructorSymbol? destructor { get; internal set; }
	internal ClassSymbol (SourceSpan span, SourceSpan name_span, int ordinal = 0, string? name = null) {
		base (span, name_span, new ClassType (name ?? name_span.text ()), ordinal, name);
	}

	internal ClassSymbol.specialized (SourceSpan span, SourceSpan name_span, ExactGenericClassType type, int ordinal) {
		base (span, name_span, type, ordinal, type.name);
	}
}

// Common declaration metadata lets direct-storage initializers retain exact
// ordinary or generic field origins without a second initializer hierarchy.
public abstract class FieldSymbol : Symbol {
	public bool text_snapshot { get; internal set; default = false; }
	public bool owns_buffer { get; internal set; default = false; }
	public bool owns_child { get; internal set; default = false; }
	public bool owns_record { get; internal set; default = false; }
	public bool owns_parameter { get; internal set; default = false; }
	public bool is_owned_field { get { return owned_cleanup != null || owns_buffer || owns_child || owns_record || owns_parameter || semantic_type is OwnerSlotsType; } }
	public CForeignCleanupContract? owned_cleanup { get; internal set; }
	public OwnershipKind ownership_kind { get { return is_owned_field ? OwnershipKind.OWNED_FIELD : OwnershipKind.UNMANAGED; } }
	public SemanticType semantic_type { get; private set; }
	public int ordinal { get; private set; }
	protected FieldSymbol (SourceSpan span, SourceSpan name_span, SemanticType type, int ordinal) {
		base (span, name_span);
		this.semantic_type = type;
		this.ordinal = ordinal;
	}

}

// Historical name retained for the shared concrete native field descriptor.
public class StructFieldSymbol : FieldSymbol {
	public bool requires_nonnull { get; private set; default = false; }
	internal void mark_nonnull() {
		requires_nonnull = true;
	}

	public bool is_private { get; private set; }
	private WeakRef owner;
	public NativeInstanceSymbol? containing_type { owned get { return (NativeInstanceSymbol?) owner.get (); } }
	public StructSymbol? containing_struct { owned get { return containing_type as StructSymbol; } }

	internal StructFieldSymbol (SourceSpan span, SourceSpan name_span, NativeInstanceSymbol containing_type, SemanticType semantic_type, int ordinal, bool is_private = false) {
		base (span, name_span, semantic_type, ordinal);
		this.is_private = is_private;
		this.owner = WeakRef (containing_type);
	}

}

public enum CallableDomain {
	NATIVE,
	METHOD,
	CONSTRUCTOR,
	DESTRUCTOR,
	PROPERTY_GETTER,
	PROPERTY_SETTER,
	C
}

public abstract class DirectCallableSymbol : Symbol {
	public CallableDomain domain { get; private set; }
	public SemanticType return_type { get; private set; }
	public GenericArray<ParameterSymbol> parameters { get; private set; }

	protected DirectCallableSymbol (SourceSpan span, SourceSpan name_span, SemanticType return_type, GenericArray<ParameterSymbol> parameters, CallableDomain domain, string? name = null) {
		base (span, name_span, name);
		this.domain = domain;
		this.return_type = return_type;
		this.parameters = parameters;
	}

}

public class FunctionSymbol : DirectCallableSymbol {
	public ForeignImportBinding? foreign_import { get; internal set; }
	public FunctionSymbol? foreign_error_factory { get; internal set; }
	public bool foreign_heap_boundary { get; private set; }
	internal void bind_foreign_heap_boundary() {
		foreign_heap_boundary = true;
	}

	public uint floating_policy { get; internal set; default = 0; }
	private uint floating_policy_origin;
	private bool floating_policy_bound;
	internal void bind_floating_policy(uint permissions) {
		floating_policy = permissions;
		if (!floating_policy_bound) {
			floating_policy_origin = permissions;
			floating_policy_bound = true;
		}
	}

	public bool floating_policy_valid() {
		return floating_policy == floating_policy_origin && Astra.Semantic.FloatingPointPolicy.valid (floating_policy);
	}

	public bool nonnull_result { get; private set; default = false; }
	internal void mark_nonnull_result() {
		nonnull_result = true;
	}

	public bool utf8_factory { get; internal set; default = false; }
	public AsyncBodyContract? async_body { get; internal set; }
	public bool heap_result { get; internal set; default = false; }
	private WeakRef result_class_identity = WeakRef (null);
	public ClassSymbol? result_class { owned get { return (ClassSymbol?) result_class_identity.get (); } internal set { result_class_identity = WeakRef (value); } }
	public ClassType? throws_type { get; internal set; }
	public ClassDispatchKind dispatch_kind { get; internal set; default = ClassDispatchKind.DIRECT; }
	public int virtual_slot { get; internal set; default = -1; }
	public StructValueContract? struct_result_contract { get; internal set; }
	public ResultObjectStorageSymbol? result_storage { get; internal set; }
	public CallableKind kind { get { return (this is PropertyGetterSymbol) ? CallableKind.PROPERTY_GETTER : (this is PropertySetterSymbol) ? CallableKind.PROPERTY_SETTER : (this is ConstructorSymbol) ? CallableKind.CONSTRUCTOR : (this is DestructorSymbol) ? CallableKind.DESTRUCTOR : (this is MethodSymbol) ? CallableKind.METHOD : CallableKind.FUNCTION; } }
	public ReceiverSymbol? implicit_receiver { get { return (this is PropertyAccessorSymbol) ? ((PropertyAccessorSymbol) this).receiver : (this is MethodSymbol) ? ((MethodSymbol) this).receiver : (this is LifecycleSymbol) ? ((LifecycleSymbol) this).receiver : null; } }
	public ResultOwnershipContract result_contract { get; private set; }
	public CForeignCleanupContract? owned_cleanup { get; private set; }

	internal FunctionSymbol (SourceSpan span, SourceSpan name_span, SemanticType return_type, GenericArray<ParameterSymbol> parameters, ResultOwnershipContract result_contract = ResultOwnershipContract.UNMANAGED, CForeignCleanupContract? owned_cleanup = null, CallableDomain domain = CallableDomain.NATIVE, string? name = null) {
		base (span, name_span, return_type, parameters, domain, name);
		this.result_contract = result_contract;
		this.owned_cleanup = owned_cleanup;
	}

}

public class CFunctionSymbol : DirectCallableSymbol {
	public DeclarationPolicyId declaration_policy { get { return metadata.com_import == null ? metadata.import_policy : DeclarationPolicyId.COM_IMPORT; } }
	public ForeignAbi abi { get; private set; }
	public CForeignMetadata metadata { get; private set; }
	public string external_symbol { get { return metadata.external_symbol; } }

	internal CFunctionSymbol (SourceSpan span, SourceSpan name_span, SemanticType return_type, GenericArray<ParameterSymbol> parameters, CForeignMetadata? metadata = null, string? name = null) {
		base (span, name_span, return_type, parameters, CallableDomain.C, name);
		this.abi = ForeignAbi.C;
		this.metadata = metadata ?? new CForeignMetadata (name_span.text ());
	}

}

public enum OwnershipKind {
	UNMANAGED,
	OWNED,
	TRANSFERABLE_OBJECT_OWNER,
	OWNED_FIELD
}

internal class IterationElementSymbol : Symbol {
	internal CheckedIterationContract iteration;
	internal IterationElementSymbol (SourceSpan span, CheckedIterationContract iteration) {
		base (span, span);
		this.iteration = iteration;
	}

}

public class LocalSymbol : Symbol {
	public ScopedBackingLoan? scoped_backing { get; internal set; }
	public bool requires_nonnull { get; private set; default = false; }
	internal void mark_nonnull() {
		requires_nonnull = true;
	}

	public bool text_loan { get; internal set; default = false; }
	public bool catch_borrow { get; internal set; default = false; }
	public LocalSymbol? enum_inspection_root { get; internal set; }
	public bool is_enum_parameter { get { return incoming_parameter != null && semantic_type is EnumType; } }
	public bool is_struct_parameter { get { return incoming_parameter != null && incoming_parameter.struct_value_contract != null; } }
	public LocalSymbol? generic_owner_source { get; internal set; }
	internal bool generic_owned_local;
	public bool is_generic_owner { get { return semantic_type is TypeParameterType && ((TypeParameterType) semantic_type).transport_mode == GenericTransportMode.OWNABLE && ((incoming_parameter != null && incoming_parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER) || generic_owner_source != null || generic_owned_local); } }
	public ObjectResultProvenance object_provenance { get { return object_owner == null ? ObjectResultProvenance.BORROWED_STORAGE : heap_object ? ObjectResultProvenance.HEAP_OBJECT : incoming_parameter == null ? ObjectResultProvenance.CALLEE_LOCAL_STORAGE : ObjectResultProvenance.OWNED_PARAMETER_STORAGE; } }
	public bool heap_object { get; internal set; default = false; }
	public ClassSymbol? object_owner { get; private set; }
	public LexicalObjectStorageSymbol? object_storage { get; internal set; }
	public bool is_buffer_owner { get; private set; }
	public bool is_owned { get { return cleanup != null || object_owner != null || is_generic_owner || is_buffer_owner || is_record_owner; } }
	// Only owned parameters have a mutable lexical slot. The incoming identity
	// remains a value in the signature; it has no backlink to this slot.
	public ParameterSymbol? incoming_parameter { get; private set; }
	// Nominal move-only discriminator; destruction is derived from every field.
	public FieldSymbol? record_owner { get; internal set; }
	public bool is_record_owner { get { return record_owner != null; } }
	private CForeignCleanupContract? cleanup_contract;
	public CForeignCleanupContract? cleanup { get { return cleanup_contract; } }
	public OwnershipKind ownership_kind { get { return object_owner != null ? OwnershipKind.TRANSFERABLE_OBJECT_OWNER : is_owned ? OwnershipKind.OWNED : OwnershipKind.UNMANAGED; } }
	public LexicalRegion lexical_region { get; private set; }
	public bool address_taken { get; internal set; default = false; }
	public SemanticType semantic_type { get; private set; }
	public int ordinal { get; private set; }

	internal LocalSymbol (SourceSpan span, SourceSpan name_span, SemanticType semantic_type, int ordinal, LexicalRegion lexical_region, CForeignCleanupContract? cleanup = null, ParameterSymbol? incoming_parameter = null, ClassSymbol? object_owner = null, bool buffer_owner = false) {
		base (span, name_span);
		this.is_buffer_owner = buffer_owner;
		assert (!buffer_owner || (semantic_type is SliceType && (BufferElementTypes.candidate (((SliceType) semantic_type).element_type) || ((SliceType) semantic_type).element_type is TypeParameterType)));
		this.semantic_type = semantic_type;
		this.ordinal = ordinal;
		this.incoming_parameter = incoming_parameter;
		this.object_owner = object_owner;
		assert (object_owner == null || (cleanup == null && semantic_type == object_owner.semantic_type));
		this.lexical_region = lexical_region;
		this.cleanup_contract = cleanup;
		assert (cleanup == null || semantic_type.is_ownable_handle_type ());
	}

}

public class ParameterSymbol : Symbol {
	public bool substituted_copy { get; internal set; default = false; }
	public bool requires_nonnull { get; private set; default = false; }
	internal void mark_nonnull() {
		requires_nonnull = true;
	}

	public bool heap_object { get; internal set; default = false; }
	public CallerInformationContract? caller_information { get; internal set; }
	public StructValueContract? struct_value_contract { get; internal set; }
	public PointerParameterContract pointer_contract { get; private set; }
	// Native parameters receive the checked function body region; C has none.
	public LexicalRegion? lexical_region { get; internal set; }
	public SemanticType semantic_type { get; private set; }
	public int ordinal { get; private set; }

	internal ParameterSymbol (SourceSpan span, SourceSpan name_span, SemanticType semantic_type, int ordinal, PointerParameterContract pointer_contract = PointerParameterContract.UNMANAGED, string? name = null) {
		base (span, name_span, name);
		this.pointer_contract = pointer_contract;
		this.semantic_type = semantic_type;
		this.ordinal = ordinal;
	}

}
}
