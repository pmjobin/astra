// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Cfg {
// One view value, retaining exact storage, range and lexical proof authority.
public class CfgSliceFromArrayValue : CfgValue {
	public CfgLocalPlace storage { get; private set; }
	public ArrayType array_type { get; private set; }
	public CfgValue? start { get; private set; }
	public CfgValue? count { get; private set; }
	public DataPointerProvenance provenance { get; private set; }
	public bool traps_on_invalid { get { return start != null; } }

	internal CfgSliceFromArrayValue (SourceSpan span, SliceType type, CfgLocalPlace storage, ArrayType array_type, CfgValue? start, CfgValue? count, DataPointerProvenance provenance) {
		base (span, type);
		this.storage = storage;
		this.array_type = array_type;
		this.start = start;
		this.count = count;
		this.provenance = provenance;
	}

}

public class CfgSliceLengthValue : CfgValue {
	public CfgValue slice { get; private set; }

	internal CfgSliceLengthValue (SourceSpan span, SemanticType type, CfgValue slice) {
		base (span, type);
		this.slice = slice;
	}

}

public class CfgSliceElementPlace : CfgPlace {
	public CfgValue slice { get; private set; }
	public SliceType slice_type { get; private set; }
	public CfgValue index { get; private set; }
	public DataPointerProvenance provenance { get; private set; }
	public bool traps_on_invalid { get { return true; } }

	internal CfgSliceElementPlace (SourceSpan span, CfgValue slice, SliceType slice_type, CfgValue index, DataPointerProvenance provenance) {
		base (span, slice_type.element_type);
		this.slice = slice;
		this.slice_type = slice_type;
		this.index = index;
		this.provenance = provenance;
	}

}

// The result is validated for this exact captured view, including its length.
public class CfgSliceBoundsCheck : CfgEvaluateInstruction {
	public CfgValue slice { get; private set; }

	internal CfgSliceBoundsCheck (SourceSpan span, CfgValue slice, CfgValue index, CfgEvaluatedValue result) {
		base (span, index, result);
		this.slice = slice;
	}

}
}
