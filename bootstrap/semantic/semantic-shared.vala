// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Foreign;
namespace Astra.Semantic {
public class CheckedSharedOperation : CheckedExpression {
	public SharedAction action { get; private set; }
	public CheckedExpression operand { get; private set; }
	public LocalSymbol? source { get; private set; }
	public CForeignCleanupContract? cleanup { get; private set; }
	public ParameterSymbol? borrower { get; private set; }
	internal CheckedSharedOperation (SourceSpan span, SemanticType type, SharedAction action, CheckedExpression operand, LocalSymbol? source, CForeignCleanupContract? cleanup, ParameterSymbol? borrower = null) {
		base (span, type);
		this.action = action;
		this.operand = operand;
		this.source = source;
		this.cleanup = cleanup;
		this.borrower = borrower;
	}
}
}
