// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Cfg {
public class CfgClassUpcast : CfgValue {
	public CfgValue reference { get; private set; }
	private WeakRef source_identity;
	public CfgClass? source_class { owned get { return (CfgClass?) source_identity.get (); } }
	private WeakRef target_identity;
	public CfgClass? target_class { owned get { return (CfgClass?) target_identity.get (); } }
	internal CfgClassUpcast (SourceSpan span, CfgValue reference, CfgClass source_class, CfgClass target_class, SemanticType result_type) {
		base (span, result_type);
		this.reference = reference;
		this.source_identity = WeakRef (source_class);
		this.target_identity = WeakRef (target_class);
	}

}

public class CfgObjectStorage : CfgNode {
	public bool fallible { get; private set; }
	public bool heap_allocated { get; internal set; default = false; }
	public bool result_candidate { get; internal set; default = false; }
	// Compile-time responsibility mode; no object header or runtime state.
	public bool transferable { get; internal set; default = false; }
	public CfgDestructor? destructor { owned get { return object_class == null ? null : object_class.destructor; } }
	public int cleanup_rank { get; internal set; default = -1; }
	private WeakRef class_identity;
	public CfgClass? object_class { owned get { return (CfgClass?) class_identity.get (); } }
	public ClassType semantic_type { get; private set; }
	public int ordinal { get; private set; }
	public int region_ordinal { get; private set; }
	internal CfgObjectStorage (SourceSpan span, CfgClass object_class, int ordinal, int region_ordinal, bool fallible = false) {
		base (span);
		this.fallible = fallible;
		this.class_identity = WeakRef (object_class);
		this.semantic_type = (ClassType) object_class.semantic_type;
		this.ordinal = ordinal;
		this.region_ordinal = region_ordinal;
	}

}

// Only complete construction publishes a reference; storage initialization
// uses exact direct field Places without making a partial object observable.
public class CfgObjectReferenceValue : CfgValue {
	public CfgObjectStorage storage { get; private set; }
	internal CfgObjectReferenceValue (SourceSpan span, CfgObjectStorage storage) {
		base (span, storage.semantic_type);
		this.storage = storage;
	}

}

public class CfgObjectFieldPlace : CfgPlace {
	public CfgObjectStorage storage { get; private set; }
	public CfgStructField field { get; private set; }
	internal CfgObjectFieldPlace (SourceSpan span, CfgObjectStorage storage, CfgStructField field) {
		base (span, field.semantic_type);
		this.storage = storage;
		this.field = field;
	}

}

public class CfgObjectValidateValue : CfgValue {
	public CfgValue reference { get; private set; }
	public bool traps_on_null { get { return true; } }
	internal CfgObjectValidateValue (SourceSpan span, CfgValue reference, SemanticType result_type) {
		base (span, result_type);
		this.reference = reference;
	}

}
}
