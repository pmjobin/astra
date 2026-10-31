// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Semantic {
public class CheckedClassUpcast : CheckedExpression {
	public CheckedExpression reference { get; private set; }
	private WeakRef source_identity;
	public ClassSymbol? source_class { owned get { return (ClassSymbol?) source_identity.get (); } }
	private WeakRef target_identity;
	public ClassSymbol? target_class { owned get { return (ClassSymbol?) target_identity.get (); } }
	internal CheckedClassUpcast (SourceSpan span, CheckedExpression reference, ClassSymbol source_class, ClassSymbol target_class, SemanticType result_type) {
		base (span, result_type);
		this.reference = reference;
		this.source_identity = WeakRef (source_class);
		this.target_identity = WeakRef (target_class);
	}
}

public class LexicalObjectStorageSymbol : Symbol {
	public bool fallible { get; private set; }
	public bool heap_allocated { get; internal set; default = false; }
	public bool result_candidate { get; internal set; default = false; }
	public DestructorSymbol? destructor { get { return object_class.destructor; } }
	public ClassSymbol object_class { get; private set; }
	public ClassType semantic_type { get { return (ClassType) object_class.semantic_type; } }
	public int ordinal { get; private set; }
	public int cleanup_rank { get; internal set; default = -1; }
	public LexicalRegion lexical_region { get; private set; }

	internal LexicalObjectStorageSymbol (SourceSpan span, SourceSpan name_span, ClassSymbol object_class, int ordinal, LexicalRegion region, bool fallible = false) {
		base (span, name_span);
		this.fallible = fallible;
		this.object_class = object_class;
		this.ordinal = ordinal;
		this.lexical_region = region;
	}
}

public class CheckedObjectConstruction : CheckedStatement {
	public LexicalObjectStorageSymbol storage { get; private set; }
	public LocalSymbol local { get; private set; }
	public GenericArray<CheckedFieldInitializer> initializers { get; private set; }
	public CheckedObjectReferenceExpression reference { get; private set; }

	internal CheckedObjectConstruction (SourceSpan span, LexicalObjectStorageSymbol storage, LocalSymbol local, GenericArray<CheckedFieldInitializer> initializers) {
		base (span);
		this.storage = storage;
		this.local = local;
		this.initializers = initializers;
		this.reference = new CheckedObjectReferenceExpression (span, storage);
	}
}

public class CheckedObjectReferenceExpression : CheckedExpression {
	public LexicalObjectStorageSymbol storage { get; private set; }
	internal CheckedObjectReferenceExpression (SourceSpan span, LexicalObjectStorageSymbol storage) {
		base (span, storage.semantic_type);
		this.storage = storage;
	}
}

public class CheckedObjectFieldPlace : CheckedPlace {
	public CheckedExpression reference { get; private set; }
	public StructFieldSymbol field { get; private set; }
	public bool traps_on_null { get { return true; } }
	internal CheckedObjectFieldPlace (SourceSpan span, CheckedExpression reference, StructFieldSymbol field) {
		base (span, field.semantic_type);
		this.reference = reference;
		this.field = field;
	}
}

// Validating a nullable reference forms the existing nonnull receiver contract.
public class CheckedObjectReceiverExpression : CheckedExpression {
	public CheckedExpression reference { get; private set; }
	public bool traps_on_null { get { return true; } }
	internal CheckedObjectReceiverExpression (SourceSpan span, CheckedExpression reference, ReceiverType contract) {
		base (span, contract);
		this.reference = reference;
	}
}
}
