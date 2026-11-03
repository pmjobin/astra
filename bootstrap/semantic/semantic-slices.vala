// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Semantic {
public class CheckedSliceFromArrayExpression : CheckedExpression {
	public LocalSymbol local { get; private set; }
	public ArrayType array_type { get; private set; }
	public CheckedExpression? start { get; private set; }
	public CheckedExpression? count { get; private set; }
	public DataPointerProvenance provenance { get; private set; }

	internal CheckedSliceFromArrayExpression (SourceSpan span, LocalSymbol local, SliceType type, CheckedExpression? start = null, CheckedExpression? count = null) {
		base (span, type);
		this.local = local;
		this.array_type = (ArrayType) local.semantic_type;
		this.start = start;
		this.count = count;
		this.provenance = new DataPointerProvenance (DataPointerOrigin.LOCAL, local.ordinal, local.lexical_region.ordinal);
	}

}

public class CheckedLengthExpression : CheckedExpression {
	public LocalSymbol? array { get; private set; }
	public CheckedExpression? slice { get; private set; }

	internal CheckedLengthExpression (SourceSpan span, IntegerType type, LocalSymbol? array, CheckedExpression? slice) {
		base (span, type);
		this.array = array;
		this.slice = slice;
	}

}

public class CheckedSliceElementPlace : CheckedPlace {
	public CheckedExpression slice { get; private set; }
	public SliceType slice_type { get; private set; }
	public CheckedExpression index { get; private set; }
	public BorrowProvenance provenance { get; private set; }
	public bool traps_on_invalid { get { return true; } }

	internal CheckedSliceElementPlace (SourceSpan span, CheckedExpression slice, CheckedExpression index) {
		base (span, ((SliceType) slice.semantic_type).element_type);
		this.slice = slice;
		this.slice_type = (SliceType) slice.semantic_type;
		this.index = index;
		this.provenance = BorrowProvenance.for_expression (slice);
	}

}
}
