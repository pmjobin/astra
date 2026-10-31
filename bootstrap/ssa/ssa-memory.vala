// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Ssa {
// Stage-owned access inventory contains declaration ranks only, no IR graph.
public class SsaPrivateFieldAccess : Object {
	public int class_ordinal { get; private set; }
	public int field_ordinal { get; private set; }
	public int function_ordinal { get; private set; }
	internal SsaPrivateFieldAccess (int owner, int field, int function) {
		class_ordinal = owner;
		field_ordinal = field;
		function_ordinal = function;
	}
}

// SSA owns descriptors only for retained typed pointers/addressable storage.
// Declaration ordinals identify fields; no physical size, offset or layout.
public abstract class SsaNativeInstance : SsaNode {
	public int ordinal { get; private set; }
	public GenericArray<SsaProperty> properties { get; private set; default = new GenericArray<SsaProperty> (); }
	public GenericArray<SsaMethod> methods { get; private set; default = new GenericArray<SsaMethod> (); }
	private string identifier;
	public string name { get { return identifier; } }
	public SourceSpan name_span { get; private set; }
	public SemanticType semantic_type { get; private set; }
	public GenericArray<SsaStructField> fields { get; private set; }

	protected SsaNativeInstance (SourceSpan span, SourceSpan name_span, string name, SemanticType semantic_type, int ordinal) {
		base (span);
		this.name_span = name_span;
		this.identifier = name;
		this.semantic_type = semantic_type;
		this.ordinal = ordinal;
		this.fields = new GenericArray<SsaStructField> ();
	}
}

public class SsaStruct : SsaNativeInstance {
	public GenericArray<SemanticType> owning_arguments { get; private set; default = new GenericArray<SemanticType> (); }
	public PodRepresentation? representation { get; internal set; }
	internal SsaStruct (SourceSpan span, SourceSpan name_span, string name, SemanticType semantic_type, int ordinal = 0) {
		base (span, name_span, name, semantic_type, ordinal);
	}
}

public class SsaClass : SsaNativeInstance {
	public ForeignClassPolicy? foreign_export { get; internal set; }
	public ConcurrencyPolicy? concurrency_policy { get; internal set; }
	public AllocationPolicy? allocation_policy { get; internal set; }
	public ExactClassGenericInstance? generic_instance { get; internal set; }
	public SsaClass? parent_class { get; internal set; }
	public bool polymorphic { get; internal set; default = false; }
	public bool exception_root { get; internal set; default = false; }
	public GenericArray<SsaFunction> virtual_entries { get; private set; default = new GenericArray<SsaFunction> (); }
	public SsaConstructor? constructor { get; internal set; }
	public SsaDestructor? destructor { get; internal set; }
	public int lifecycle_count { get { return (constructor == null ? 0 : 1) + (destructor == null ? 0 : 1); } }
	internal SsaClass (SourceSpan span, SourceSpan name_span, string name, ClassType semantic_type, int ordinal = 0) {
		base (span, name_span, name, semantic_type, ordinal);
	}
}

// Shared native field descriptor; the historical name remains compatible.
public class SsaStructField : SsaNode {
	private WeakRef record_identity;
	public SsaStruct? record_owner {
		owned get { return (SsaStruct?) record_identity.get (); }
		internal set { record_identity = WeakRef (value); }
	}
	public bool requires_nonnull { get; private set; default = false; }
	internal void mark_nonnull() {
		requires_nonnull = true;
	}
	public SsaCleanupContract? owned_cleanup { get; internal set; }
	public bool is_private { get; private set; }
	public bool text_snapshot { get; internal set; default = false; }
	public SsaCleanupContract? slots_cleanup { get; internal set; }
	private WeakRef owner;
	public SsaNativeInstance? containing_type { owned get { return (SsaNativeInstance?) owner.get (); } }
	public SsaStruct? containing_struct { owned get { return containing_type as SsaStruct; } }
	private string identifier;
	public string name { get { return identifier; } }
	public SourceSpan name_span { get; private set; }
	public SemanticType semantic_type { get; private set; }
	public int ordinal { get; private set; }

	internal SsaStructField (SourceSpan span, SourceSpan name_span, string name, SsaNativeInstance containing_type, SemanticType semantic_type, int ordinal, bool is_private = false) {
		base (span);
		this.is_private = is_private;
		this.name_span = name_span;
		this.identifier = name;
		this.owner = WeakRef (containing_type);
		this.semantic_type = semantic_type;
		this.ordinal = ordinal;
	}
}

// Storage object, never an SSA value. Function owns storage; storage owns its
// type descriptor. Neither owns instructions, Places, or results.
public class SsaAddressableLocal : SsaNode {
	public SemanticType semantic_type { get; private set; }
	public SsaStruct? structure { get; private set; }
	public int ordinal { get; private set; }
	public int source_local_ordinal { get; private set; }
	private string identifier;
	public string name { get { return identifier; } }
	public SourceSpan name_span { get; private set; }

	internal SsaAddressableLocal (SourceSpan span, SourceSpan name_span, string name, SemanticType semantic_type, int ordinal, int source_local_ordinal, SsaStruct? structure = null) {
		base (span);
		this.name_span = name_span;
		this.identifier = name;
		this.structure = structure;
		this.semantic_type = semantic_type;
		this.ordinal = ordinal;
		this.source_local_ordinal = source_local_ordinal;
	}
}

public abstract class SsaMemoryPlace : SsaNode {
	public SemanticType semantic_type { get; private set; }

	public SsaAddressableLocal? root_storage() {
		var local = this as SsaLocalMemoryPlace;
		if (local != null) {
			return local.storage;
		}
		var direct = this as SsaDirectFieldPlace;
		if (direct != null) {
			return direct.storage;
		}
		var field = this as SsaFieldPlace;
		return field == null || field.aggregate == null ? null : field.aggregate.root_storage ();
	}

	// Exact storage projection equivalence, never a textual field path.
	private static Object identity_base(Object object) {
		if (object is SsaLocalMemoryPlace) {
			return ((SsaLocalMemoryPlace) object).storage;
		}
		return object;
	}

	private static Object? field_base(SsaFieldPlace field) {
		return field.aggregate != null ? (Object) field.aggregate : (field is SsaDirectFieldPlace) ? ((SsaDirectFieldPlace) field).storage : null;
	}

	public static uint storage_hash(Object object) {
		var normalized = identity_base (object);
		var field = normalized as SsaFieldPlace;
		var aggregate = field == null ? null : field_base (field);
		return aggregate == null ? direct_hash(normalized) : storage_hash (aggregate) * 33 + direct_hash (field.field);
	}

	public static bool storage_equal(Object left, Object right) {
		var a = identity_base (left);
		var b = identity_base (right);
		if (a == b) {
			return true;
		}
		var af = a as SsaFieldPlace;
		var bf = b as SsaFieldPlace;
		if (af == null || bf == null || af.field != bf.field) {
			return false;
		}
		var ap = field_base (af);
		var bp = field_base (bf);
		return ap != null && bp != null && storage_equal (ap, bp);
	}

	protected SsaMemoryPlace (SourceSpan span, SemanticType semantic_type) {
		base (span);
		this.semantic_type = semantic_type;
	}
}

public class SsaLocalMemoryPlace : SsaMemoryPlace {
	public SsaAddressableLocal storage { get; private set; }

	internal SsaLocalMemoryPlace (SourceSpan span, SsaAddressableLocal storage) {
		base (span, storage.semantic_type);
		this.storage = storage;
	}
}

public class SsaDereferencePlace : SsaMemoryPlace {
	public SsaValue pointer { get; private set; }
	public DataPointerProvenance provenance { get; private set; }
	public bool traps_on_null { get { return true; } }

	internal SsaDereferencePlace (SourceSpan span, SsaValue pointer, SemanticType pointee, DataPointerProvenance provenance) {
		base (span, pointee);
		this.pointer = pointer;
		this.provenance = provenance;
	}
}

public class SsaFieldPlace : SsaMemoryPlace {
	public SsaStructField field { get; private set; }

	public SsaMemoryPlace? aggregate { get; private set; }
	internal SsaFieldPlace.projection (SourceSpan span, SsaMemoryPlace aggregate, SsaStructField field) {
		base (span, field.semantic_type);
		this.aggregate = aggregate;
		this.field = field;
	}

	protected SsaFieldPlace (SourceSpan span, SsaStructField field) {
		base (span, field.semantic_type);
		this.field = field;
	}
}

public class SsaDirectFieldPlace : SsaFieldPlace {
	public SsaAddressableLocal storage { get; private set; }

	internal SsaDirectFieldPlace (SourceSpan span, SsaAddressableLocal storage, SsaStructField field) {
		base (span, field);
		this.storage = storage;
	}
}

// A result has no instruction backlink, so retaining this pointer value
// cannot create an instruction -> Place -> result -> instruction cycle.
public class SsaIndirectFieldPlace : SsaFieldPlace {
	public SsaValue pointer { get; private set; }

	internal SsaIndirectFieldPlace (SourceSpan span, SsaValue pointer, SsaStructField field) {
		base (span, field);
		this.pointer = pointer;
	}
}

public class SsaAddressOfInstruction : SsaInstruction {
	public SsaMemoryPlace? receiver_place { get; private set; }
	internal SsaAddressOfInstruction.projection (SourceSpan span, ReceiverType type, int ordinal, SsaMemoryPlace place) {
		base (span, type, ordinal);
		this.receiver_place = place;
	}
	public SsaAddressableLocal? target { get; private set; }
	public DataPointerProvenance? provenance { get; private set; }

	internal SsaAddressOfInstruction (SourceSpan span, SemanticType semantic_type, int ordinal, SsaAddressableLocal target, DataPointerProvenance? provenance = null) {
		base (span, semantic_type, ordinal);
		this.target = target;
		this.provenance = provenance;
	}
}

// Instruction array order is memory/call/trap order. No memory SSA tokens,
// whole aggregate values, caching, or implicit load forwarding.
public class SsaInitializeInstruction : SsaInstruction {
	public SsaMemoryPlace target { get; private set; }
	public SsaValue value { get; private set; }

	internal SsaInitializeInstruction (SourceSpan span, SsaMemoryPlace target, SsaValue value) {
		base (span, null, -1);
		this.target = target;
		this.value = value;
	}
}

public class SsaValidatePlaceInstruction : SsaInstruction {
	public SsaMemoryPlace place { get; private set; }
	internal SsaValidatePlaceInstruction (SourceSpan span, SsaMemoryPlace place) {
		base (span, null, -1);
		this.place = place;
	}
}

public class SsaStoreInstruction : SsaInstruction {
	public VolatileAccessContract? volatile_access { get; private set; }
	public bool volatile_enabled { get; internal set; }
	public SsaMemoryPlace target { get; private set; }
	public SsaValue value { get; private set; }

	internal SsaStoreInstruction (SourceSpan span, SsaMemoryPlace target, SsaValue value, VolatileAccessContract? access = null) {
		base (span, null, -1);
		volatile_access = access;
		volatile_enabled = access != null;
		this.target = target;
		this.value = value;
	}
}

public class SsaLoadInstruction : SsaInstruction {
	public VolatileAccessContract? volatile_access { get; private set; }
	public bool volatile_enabled { get; internal set; }
	public SsaMemoryPlace source { get; private set; }

	internal SsaLoadInstruction (SourceSpan span, SsaMemoryPlace source, int ordinal, VolatileAccessContract? access = null) {
		base (span, source.semantic_type, ordinal);
		volatile_access = access;
		volatile_enabled = access != null;
		this.source = source;
	}
}
}
