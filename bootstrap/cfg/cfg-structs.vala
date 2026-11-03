// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Cfg {
// Stage-owned descriptor. The shared StructType has no upstream backlinks.
public abstract class CfgNativeInstance : CfgNode {
	public int ordinal { get; private set; }
	public GenericArray<CfgProperty> properties { get; private set; default = new GenericArray<CfgProperty> (); }
	public GenericArray<CfgMethod> methods { get; private set; default = new GenericArray<CfgMethod> (); }
	private string identifier;
	public string name { get { return identifier; } }
	public SourceSpan name_span { get; private set; }
	public SemanticType semantic_type { get; private set; }
	public GenericArray<CfgStructField> fields { get; private set; }

	protected CfgNativeInstance (SourceSpan span, SourceSpan name_span, string name, SemanticType semantic_type, int ordinal) {
		base (span);
		this.name_span = name_span;
		this.identifier = name;
		this.semantic_type = semantic_type;
		this.ordinal = ordinal;
		this.fields = new GenericArray<CfgStructField> ();
	}

}

public class CfgStruct : CfgNativeInstance {
	public GenericArray<SemanticType> owning_arguments { get; private set; default = new GenericArray<SemanticType> (); }
	public PodRepresentation? representation { get; internal set; }
	internal CfgStruct (SourceSpan span, SourceSpan name_span, string name, SemanticType semantic_type, int ordinal = 0) {
		base (span, name_span, name, semantic_type, ordinal);
	}

}

public class CfgClass : CfgNativeInstance {
	public ForeignClassPolicy? foreign_export { get; internal set; }
	public ConcurrencyPolicy? concurrency_policy { get; internal set; }
	public AllocationPolicy? allocation_policy { get; internal set; }
	public ExactClassGenericInstance? generic_instance { get; internal set; }
	public CfgClass? parent_class { get; internal set; }
	public bool polymorphic { get; internal set; default = false; }
	public bool exception_root { get; internal set; default = false; }
	public GenericArray<CfgFunction> virtual_entries { get; private set; default = new GenericArray<CfgFunction> (); }
	public CfgConstructor? constructor { get; internal set; }
	public CfgDestructor? destructor { get; internal set; }
	public int lifecycle_count { get { return (constructor == null ? 0 : 1) + (destructor == null ? 0 : 1); } }
	internal CfgClass (SourceSpan span, SourceSpan name_span, string name, ClassType semantic_type, int ordinal = 0) {
		base (span, name_span, name, semantic_type, ordinal);
	}

}

// Shared native field descriptor; the historical name remains compatible.
public class CfgStructField : CfgNode {
	public bool requires_nonnull { get; private set; default = false; }
	internal void mark_nonnull() {
		requires_nonnull = true;
	}

	public CfgCleanupContract? owned_cleanup { get; internal set; }
	public bool is_private { get; private set; }
	public bool text_snapshot { get; internal set; default = false; }
	public CfgCleanupContract? slots_cleanup { get; internal set; }
	private WeakRef owner;
	public CfgNativeInstance? containing_type { owned get { return (CfgNativeInstance?) owner.get (); } }
	public CfgStruct? containing_struct { owned get { return containing_type as CfgStruct; } }
	private string identifier;
	public string name { get { return identifier; } }
	public SourceSpan name_span { get; private set; }
	public SemanticType semantic_type { get; private set; }
	public int ordinal { get; private set; }

	internal CfgStructField (SourceSpan span, SourceSpan name_span, string name, CfgNativeInstance containing_type, SemanticType semantic_type, int ordinal, bool is_private = false) {
		base (span);
		this.is_private = is_private;
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
public class CfgFieldPlace : CfgPlace {
	public CfgPlace aggregate { get; private set; }
	public CfgStructField field { get; private set; }
	public StructLeafPath storage_path() {
		return new StructLeafPath (path_ordinals (), semantic_type);
	}

	private int[] path_ordinals() {
		var parent = aggregate as CfgFieldPlace;
		int[]? prefix = parent == null ? null : parent.path_ordinals ();
		int depth = prefix == null ? 0 : prefix.length;
		var result = new int[depth + 1];
		for (int i = 0; i < depth; i++) {
			result[i] = prefix[i];
		}
		result[depth] = field.ordinal;
		return result;
	}

	public CfgLocalPlace? root_local() {
		CfgPlace root = aggregate;
		while (root is CfgFieldPlace) {
			root = ((CfgFieldPlace) root).aggregate;
		}
		return root as CfgLocalPlace;
	}

	internal CfgFieldPlace (SourceSpan span, CfgPlace aggregate, CfgStructField field) {
		base (span, field.semantic_type);
		this.aggregate = aggregate;
		this.field = field;
	}

}

// Unlike a direct field projection, this place follows a pointer VALUE.
public class CfgIndirectFieldPlace : CfgPlace {
	public CfgValue pointer { get; private set; }
	public CfgStructField field { get; private set; }

	internal CfgIndirectFieldPlace (SourceSpan span, CfgValue pointer, CfgStructField field) {
		base (span, field.semantic_type);
		this.pointer = pointer;
		this.field = field;
	}

}

// A storage Place following one pointer value. Null must trap before access.
public class CfgDereferencePlace : CfgPlace {
	public CfgValue pointer { get; private set; }
	public DataPointerProvenance provenance { get; private set; }
	public bool traps_on_null { get { return true; } }

	internal CfgDereferencePlace (SourceSpan span, CfgValue pointer, SemanticType pointee, DataPointerProvenance provenance) {
		base (span, pointee);
		this.pointer = pointer;
		this.provenance = provenance;
	}

}

public class CfgAddressOfValue : CfgValue {
	public CfgPlace? receiver_place { get; private set; }
	internal CfgAddressOfValue.projection (SourceSpan span, ReceiverType type, CfgPlace place) {
		base (span, type);
		this.receiver_place = place;
	}
	public CfgLocalPlace? target { get; private set; }
	public DataPointerProvenance? provenance { get; private set; }

	internal CfgAddressOfValue (SourceSpan span, SemanticType semantic_type, CfgLocalPlace target, DataPointerProvenance? provenance = null) {
		base (span, semantic_type);
		this.target = target;
		this.provenance = provenance;
	}

}
}
