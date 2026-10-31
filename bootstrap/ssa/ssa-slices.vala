// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Ssa {
// Exactly one SliceType result; no source-visible pointer/count components.
public class SsaSliceConstructInstruction : SsaInstruction {
	public SsaAddressableLocal storage { get; private set; }
	public ArrayType array_type { get; private set; }
	public SsaValue? start { get; private set; }
	public SsaValue? count { get; private set; }
	public DataPointerProvenance provenance { get; private set; }
	public bool traps_on_invalid { get { return start != null; } }

	internal SsaSliceConstructInstruction (SourceSpan span, SliceType type, SsaAddressableLocal storage, ArrayType array_type, SsaValue? start, SsaValue? count, DataPointerProvenance provenance, int ordinal) {
		base (span, type, ordinal);
		this.storage = storage;
		this.array_type = array_type;
		this.start = start;
		this.count = count;
		this.provenance = provenance;
	}
}

public class SsaSliceLengthInstruction : SsaInstruction {
	public SsaValue slice { get; private set; }

	internal SsaSliceLengthInstruction (SourceSpan span, SemanticType type, SsaValue slice, int ordinal) {
		base (span, type, ordinal);
		this.slice = slice;
	}
}

public class SsaSliceElementPlace : SsaMemoryPlace {
	public SsaValue slice { get; private set; }
	public SliceType slice_type { get; private set; }
	public SsaValue index { get; private set; }
	public DataPointerProvenance provenance { get; private set; }
	public bool traps_on_invalid { get { return true; } }

	internal SsaSliceElementPlace (SourceSpan span, SsaValue slice, SliceType slice_type, SsaValue index, DataPointerProvenance provenance) {
		base (span, slice_type.element_type);
		this.slice = slice;
		this.slice_type = slice_type;
		this.index = index;
		this.provenance = provenance;
	}
}

public class SsaSliceBoundsCheck : SsaInstruction {
	public SsaValue slice { get; private set; }
	public SsaValue index { get; private set; }

	internal SsaSliceBoundsCheck (SourceSpan span, SsaValue slice, SsaValue index, int ordinal) {
		base (span, index.semantic_type, ordinal);
		this.slice = slice;
		this.index = index;
	}
}
}
