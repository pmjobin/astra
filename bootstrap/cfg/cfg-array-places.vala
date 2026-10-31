// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Cfg {
public class CfgArrayInitialize : CfgInstruction {
	public CfgLocalPlace storage { get; private set; }
	public GenericArray<CfgValue> elements { get; private set; }
	public CfgArrayElementPlace? record_root { get; private set; }
	public GenericArray<CfgPlace> record_fields { get; private set; default = new GenericArray<CfgPlace> (); }
	public int record_ordinal {
		get {
			var value = record_root == null ? null : record_root.index as CfgIntegerValue;
			return record_root == null ? -1 : value == null || !value.value.fits_nonnegative (int.MAX) ? -2 : (int) value.value.bits;
		}
	}
	public bool completes_array { get { return record_root == null || (storage.semantic_type is ArrayType && record_ordinal == ((ArrayType) storage.semantic_type).length - 1); } }
	internal CfgArrayInitialize.record (SourceSpan span, CfgArrayElementPlace root, GenericArray<CfgPlace> fields, GenericArray<CfgValue> values) {
		this(span, root.storage, values);
		this.record_root = root;
		this.record_fields = fields;
	}

	internal CfgArrayInitialize (SourceSpan span, CfgLocalPlace storage, GenericArray<CfgValue> elements) {
		base (span);
		this.storage = storage;
		this.elements = elements;
	}
}

public class CfgArrayElementPlace : CfgPlace {
	public CfgLocalPlace storage { get; private set; }
	public ArrayType array_type { get; private set; }
	public CfgValue index { get; private set; }
	public DataPointerProvenance provenance { get; private set; }
	public bool traps_on_invalid { get { return true; } }

	internal CfgArrayElementPlace (SourceSpan span, CfgLocalPlace storage, ArrayType array_type, CfgValue index, DataPointerProvenance provenance) {
		base (span, array_type.element_type);
		this.storage = storage;
		this.array_type = array_type;
		this.index = index;
		this.provenance = provenance;
	}
}

// Ordered, potentially trapping evaluation. The result carries validated
// ordinal authority for this exact storage, independently of the RHS.
public class CfgArrayBoundsCheck : CfgEvaluateInstruction {
	public CfgLocalPlace storage { get; private set; }

	internal CfgArrayBoundsCheck (SourceSpan span, CfgLocalPlace storage, CfgValue index, CfgEvaluatedValue result) {
		base (span, index, result);
		this.storage = storage;
	}
}
}
