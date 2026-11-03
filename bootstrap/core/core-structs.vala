// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Core {
// Stage-owned descriptor. Shared nominal types have no upstream backlinks.
public abstract class CoreNativeInstance : CoreNode {
	public int ordinal { get; private set; }
	public GenericArray<CoreProperty> properties { get; private set; default = new GenericArray<CoreProperty> (); }
	public GenericArray<CoreMethod> methods { get; private set; default = new GenericArray<CoreMethod> (); }
	private string identifier;
	public string name { get { return identifier; } }
	public SourceSpan name_span { get; private set; }
	public SemanticType semantic_type { get; private set; }
	public GenericArray<CoreStructField> fields { get; private set; }

	protected CoreNativeInstance (SourceSpan span, SourceSpan name_span, string name, SemanticType semantic_type, int ordinal) {
		base (span);
		this.name_span = name_span;
		this.identifier = name;
		this.semantic_type = semantic_type;
		this.ordinal = ordinal;
		this.fields = new GenericArray<CoreStructField> ();
	}

}

public class CoreStruct : CoreNativeInstance {
	public GenericArray<SemanticType> owning_arguments { get; private set; default = new GenericArray<SemanticType> (); }
	public PodRepresentation? representation { get; internal set; }
	public GenericStructInstance? generic_instance { get; internal set; }
	internal CoreStruct (SourceSpan span, SourceSpan name_span, string name, SemanticType semantic_type, int ordinal = 0) {
		base (span, name_span, name, semantic_type, ordinal);
	}

}

public class CoreClass : CoreNativeInstance {
	public ReceiverType? application_receiver { get; internal set; }
	public ForeignClassPolicy? foreign_export { get; internal set; }
	public ConcurrencyPolicy? concurrency_policy { get; internal set; }
	public AllocationPolicy? allocation_policy { get; internal set; }
	public ExactClassGenericInstance? generic_instance { get; internal set; }
	public CoreClass? parent_class { get; internal set; }
	public bool polymorphic { get; internal set; default = false; }
	public bool exception_root { get; internal set; default = false; }
	public GenericArray<CoreFunction> virtual_entries { get; private set; default = new GenericArray<CoreFunction> (); }
	public CoreConstructor? constructor { get; internal set; }
	public CoreDestructor? destructor { get; internal set; }
	public int lifecycle_count { get { return (constructor == null ? 0 : 1) + (destructor == null ? 0 : 1); } }
	internal CoreClass (SourceSpan span, SourceSpan name_span, string name, ClassType semantic_type, int ordinal = 0) {
		base (span, name_span, name, semantic_type, ordinal);
	}

}

// Shared native field descriptor; the historical name remains compatible.
public class CoreStructField : CoreNode {
	public bool requires_nonnull { get; private set; default = false; }
	internal void mark_nonnull() {
		requires_nonnull = true;
	}

	public bool is_private { get; private set; }
	public bool text_snapshot { get; internal set; default = false; }
	public CoreCleanupContract? owned_cleanup { get; internal set; }
	public CoreCleanupContract? slots_cleanup { get; internal set; }
	public CoreGenericStructFieldIdentity? generic_origin { get; private set; }
	private WeakRef owner;
	public CoreNativeInstance? containing_type { owned get { return (CoreNativeInstance?) owner.get (); } }
	public CoreStruct? containing_struct { owned get { return containing_type as CoreStruct; } }
	private string identifier;
	public string name { get { return identifier; } }
	public SourceSpan name_span { get; private set; }
	public SemanticType semantic_type { get; internal set; }
	public int ordinal { get; private set; }

	internal CoreStructField (SourceSpan span, SourceSpan name_span, string name, CoreNativeInstance containing_type, SemanticType semantic_type, int ordinal, CoreGenericStructFieldIdentity? generic_origin = null, bool is_private = false) {
		base (span);
		this.is_private = is_private;
		this.generic_origin = generic_origin;
		this.name_span = name_span;
		this.identifier = name;
		this.owner = WeakRef (containing_type);
		this.semantic_type = semantic_type;
		this.ordinal = ordinal;
	}

}

// Function owns projections and bases. Projection -> base is strong and
// acyclic: the base never owns its projections. No names or byte offsets
// determine storage authority; exact base + field identities do.
public abstract class CoreStorageFieldPlace : CorePlace {
	public CorePlace aggregate { get; private set; }

	public CoreLocalPlace? root_local() {
		CorePlace root = aggregate;
		while (root is CoreStorageFieldPlace) {
			root = ((CoreStorageFieldPlace) root).aggregate;
		}
		return root as CoreLocalPlace;
	}

	protected CoreStorageFieldPlace (SourceSpan span, CorePlace aggregate, SemanticType type) {
		base (span, type);
		this.aggregate = aggregate;
	}

}

public class CoreFieldPlace : CoreStorageFieldPlace {
	public CoreStructField field { get; private set; }
	public StructLeafPath storage_path() {
		return new StructLeafPath (path_ordinals (), semantic_type);
	}

	private int[] path_ordinals() {
		var parent = aggregate as CoreFieldPlace;
		int[]? prefix = parent == null ? null : parent.path_ordinals ();
		int depth = prefix == null ? 0 : prefix.length;
		var result = new int[depth + 1];
		for (int i = 0; i < depth; i++) {
			result[i] = prefix[i];
		}
		result[depth] = field.ordinal;
		return result;
	}

	internal CoreFieldPlace (SourceSpan span, CorePlace aggregate, CoreStructField field) {
		base (span, aggregate, field.semantic_type);
		this.field = field;
	}

}

// Recursive direct-storage initialization, deliberately not a CoreValue.
public class CoreStructInitialize : CoreStatement {
	public CoreStorageFieldPlace target { get; private set; }
	public GenericArray<CoreStatement> initializers { get; private set; }
	public CoreStructProducer? producer { get; private set; }
	public CoreOwnedLocal? record_owner { get; private set; }
	internal CoreStructInitialize.from_producer (SourceSpan span, CoreStorageFieldPlace target, CoreStructProducer producer, CoreOwnedLocal? record_owner = null) {
		base (span);
		this.target = target;
		this.producer = producer;
		this.record_owner = record_owner;
		this.initializers = new GenericArray<CoreStatement> ();
	}
	internal CoreStructInitialize (SourceSpan span, CoreStorageFieldPlace target, GenericArray<CoreStatement> initializers) {
		base (span);
		this.target = target;
		this.initializers = initializers;
	}

}

// Unlike a direct field projection, this place follows a pointer VALUE.
public class CoreIndirectFieldPlace : CorePlace {
	public CoreValue pointer { get; private set; }
	public CoreStructField field { get; private set; }

	internal CoreIndirectFieldPlace (SourceSpan span, CoreValue pointer, CoreStructField field) {
		base (span, field.semantic_type);
		this.pointer = pointer;
		this.field = field;
	}

}

// A storage Place following one pointer value. Null must trap before access.
public class CoreDereferencePlace : CorePlace {
	public CoreValue pointer { get; private set; }
	public DataPointerProvenance provenance { get; private set; }
	public bool traps_on_null { get { return true; } }

	internal CoreDereferencePlace (SourceSpan span, CoreValue pointer, SemanticType pointee, DataPointerProvenance provenance) {
		base (span, pointee);
		this.pointer = pointer;
		this.provenance = provenance;
	}

}

public class CoreAddressOfValue : CoreValue {
	public CorePlace? receiver_place { get; private set; }
	internal CoreAddressOfValue.projection (SourceSpan span, ReceiverType type, CorePlace place) {
		base (span, type);
		this.receiver_place = place;
	}
	public CoreLocalPlace? target { get; private set; }
	public DataPointerProvenance? provenance { get; private set; }

	internal CoreAddressOfValue (SourceSpan span, SemanticType semantic_type, CoreLocalPlace target, DataPointerProvenance? provenance = null) {
		base (span, semantic_type);
		this.target = target;
		this.provenance = provenance;
	}

}
}
