// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Semantic {
// Responsibility belongs to the exact field, independently of its HandleType.
public class CheckedOwnedFieldTransfer : CheckedStatement {
	public CheckedPlace destination { get; private set; }
	public StructFieldSymbol field { get; private set; }
	public CheckedExpression incoming { get; private set; }
	public bool initializes { get; private set; }
	internal CheckedOwnedFieldTransfer (SourceSpan span, CheckedPlace destination, StructFieldSymbol field, CheckedExpression incoming, bool initializes) {
		base (span);
		this.destination = destination;
		this.field = field;
		this.incoming = incoming;
		this.initializes = initializes;
	}
}

// One temporary use of the live slot, never an independently owned handle.
public class CheckedOwnedFieldBorrow : CheckedExpression {
	public CheckedPlace source { get; private set; }
	public StructFieldSymbol field { get; private set; }
	public ParameterSymbol? parameter { get; private set; }
	public LexicalRegion? borrow_region { get; internal set; }
	internal CheckedOwnedFieldBorrow (SourceSpan span, CheckedPlace source, StructFieldSymbol field, ParameterSymbol? parameter) {
		base (span, field.semantic_type);
		this.source = source;
		this.field = field;
		this.parameter = parameter;
	}
}
}
