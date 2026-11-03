// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Core {
public class CoreClassUpcast : CoreValue {
	public CoreValue reference { get; private set; }
	private WeakRef source_identity;
	public CoreClass? source_class { owned get { return (CoreClass?) source_identity.get (); } }
	private WeakRef target_identity;
	public CoreClass? target_class { owned get { return (CoreClass?) target_identity.get (); } }
	internal CoreClassUpcast (SourceSpan span, CoreValue reference, CoreClass source_class, CoreClass target_class, SemanticType result_type) {
		base (span, result_type);
		this.reference = reference;
		this.source_identity = WeakRef (source_class);
		this.target_identity = WeakRef (target_class);
	}

}

public class CoreObjectStorage : CoreNode {
	public bool fallible { get; private set; }
	public bool heap_allocated { get; internal set; default = false; }
	public bool result_candidate { get; internal set; default = false; }
	// Compile-time responsibility mode; no object header or runtime state.
	public bool transferable { get; internal set; default = false; }
	public CoreDestructor? destructor { owned get { return object_class == null ? null : object_class.destructor; } }
	public int cleanup_rank { get; internal set; default = -1; }
	private WeakRef class_identity;
	public CoreClass? object_class { owned get { return (CoreClass?) class_identity.get (); } }
	public ClassType semantic_type { get; private set; }
	public int ordinal { get; private set; }
	public int region_ordinal { get; private set; }
	private WeakRef lexical_scope;
	public CoreBlock? scope { owned get { return (CoreBlock?) lexical_scope.get (); } }

	internal CoreObjectStorage (SourceSpan span, CoreClass object_class, int ordinal, int region_ordinal, CoreBlock scope, bool fallible = false) {
		base (span);
		this.fallible = fallible;
		this.class_identity = WeakRef (object_class);
		this.semantic_type = (ClassType) object_class.semantic_type;
		this.ordinal = ordinal;
		this.region_ordinal = region_ordinal;
		this.lexical_scope = WeakRef (scope);
	}

}

public class CoreObjectFieldInitializer : CoreNode {
	public CoreStructField field { get; private set; }
	public CoreValue value { get; private set; }
	internal CoreObjectFieldInitializer (SourceSpan span, CoreStructField field, CoreValue value) {
		base (span);
		this.field = field;
		this.value = value;
	}

}

public class CoreObjectConstruction : CoreStatement {
	public CoreOwnedLocal? acquisition { get; internal set; }
	public CoreObjectStorage storage { get; private set; }
	public CoreLocalPlace target { get; private set; }
	public GenericArray<CoreObjectFieldInitializer> initializers { get; private set; }
	internal CoreObjectConstruction (SourceSpan span, CoreObjectStorage storage, CoreLocalPlace target, GenericArray<CoreObjectFieldInitializer> initializers) {
		base (span);
		this.storage = storage;
		this.target = target;
		this.initializers = initializers;
	}

}

public class CoreObjectReceiverValue : CoreValue {
	public CoreValue reference { get; private set; }
	public bool traps_on_null { get { return true; } }
	internal CoreObjectReceiverValue (SourceSpan span, CoreValue reference, ReceiverType contract) {
		base (span, contract);
		this.reference = reference;
	}

}
}
