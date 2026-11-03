// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Ssa {
public class SsaClassUpcast : SsaInstruction {
	public SsaFunctionParameter? borrowed_parameter { get; internal set; }
	public SsaValue reference { get; private set; }
	private WeakRef source_identity;
	public SsaClass? source_class { owned get { return (SsaClass?) source_identity.get (); } }
	private WeakRef target_identity;
	public SsaClass? target_class { owned get { return (SsaClass?) target_identity.get (); } }
	internal SsaClassUpcast (SourceSpan span, SsaValue reference, SsaClass source_class, SsaClass target_class, SemanticType result_type, int ordinal) {
		base (span, result_type, ordinal);
		this.reference = reference;
		this.source_identity = WeakRef (source_class);
		this.target_identity = WeakRef (target_class);
	}

}

// Storage is not an SsaValue and has no reference-local backlink.
public class SsaObjectStorage : SsaNode {
	public Astra.Text.TextLoanExtent? text_extent { get; internal set; }
	public bool fallible { get; private set; }
	public bool heap_allocated { get; internal set; default = false; }
	public bool result_candidate { get; internal set; default = false; }
	// Compile-time responsibility mode; no object header or runtime state.
	public bool transferable { get; internal set; default = false; }
	public SsaDestructor? destructor { owned get { return object_class == null ? null : object_class.destructor; } }
	public int cleanup_rank { get; internal set; default = -1; }
	private WeakRef class_identity;
	public SsaClass? object_class { owned get { return (SsaClass?) class_identity.get (); } }
	public ClassType semantic_type { get; private set; }
	public int ordinal { get; private set; }
	public int region_ordinal { get; private set; }
	internal SsaObjectStorage (SourceSpan span, SsaClass object_class, int ordinal, int region_ordinal, bool fallible = false) {
		base (span);
		this.fallible = fallible;
		this.class_identity = WeakRef (object_class);
		this.semantic_type = (ClassType) object_class.semantic_type;
		this.ordinal = ordinal;
		this.region_ordinal = region_ordinal;
	}

}

public class SsaObjectFieldPlace : SsaFieldPlace {
	public SsaObjectStorage storage { get; private set; }
	internal SsaObjectFieldPlace (SourceSpan span, SsaObjectStorage storage, SsaStructField field) {
		base (span, field);
		this.storage = storage;
	}

}

public class SsaObjectReferenceInstruction : SsaInstruction {
	public SsaObjectStorage storage { get; private set; }
	public DataPointerProvenance provenance { get; private set; }
	internal SsaObjectReferenceInstruction (SourceSpan span, SsaObjectStorage storage, int ordinal) {
		base (span, storage.semantic_type, ordinal);
		this.storage = storage;
		this.provenance = new DataPointerProvenance (DataPointerOrigin.OBJECT_STORAGE, storage.ordinal, storage.region_ordinal);
	}

}

// The guard executes at this instruction, before subsequent argument/RHS
// instructions. A receiver result is the existing METHOD-1 contract.
public class SsaObjectValidateInstruction : SsaInstruction {
	public SsaValue reference { get; private set; }
	public bool traps_on_null { get { return true; } }
	internal SsaObjectValidateInstruction (SourceSpan span, SsaValue reference, SemanticType result_type, int ordinal) {
		base (span, result_type, ordinal);
		this.reference = reference;
	}

}
}
