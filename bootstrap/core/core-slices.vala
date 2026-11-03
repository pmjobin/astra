// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Core {
// One view value, retaining exact storage, range and lexical proof authority.
public class CoreSliceFromArrayValue : CoreValue {
	public CoreLocalPlace storage { get; private set; }
	public ArrayType array_type { get; private set; }
	public CoreValue? start { get; private set; }
	public CoreValue? count { get; private set; }
	public DataPointerProvenance provenance { get; private set; }
	public bool traps_on_invalid { get { return start != null; } }

	internal CoreSliceFromArrayValue (SourceSpan span, SliceType type, CoreLocalPlace storage, ArrayType array_type, CoreValue? start, CoreValue? count, DataPointerProvenance provenance) {
		base (span, type);
		this.storage = storage;
		this.array_type = array_type;
		this.start = start;
		this.count = count;
		this.provenance = provenance;
	}

}

public class CoreSliceLengthValue : CoreValue {
	public CoreValue slice { get; private set; }

	internal CoreSliceLengthValue (SourceSpan span, SemanticType type, CoreValue slice) {
		base (span, type);
		this.slice = slice;
	}

}

public class CoreSliceElementPlace : CorePlace {
	public CoreValue slice { get; private set; }
	public SliceType slice_type { get; private set; }
	public CoreValue index { get; private set; }
	public DataPointerProvenance provenance { get; private set; }
	public bool traps_on_invalid { get { return true; } }

	internal CoreSliceElementPlace (SourceSpan span, CoreValue slice, SliceType slice_type, CoreValue index, DataPointerProvenance provenance) {
		base (span, slice_type.element_type);
		this.slice = slice;
		this.slice_type = slice_type;
		this.index = index;
		this.provenance = provenance;
	}

}
}
