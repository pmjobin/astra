// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
namespace Astra.Semantic {
public class CheckedRetainedOperation : CheckedExpression {
	public RetainedAction action { get; private set; }
	public CheckedExpression callee { get; private set; }
	public GenericArray<CheckedExpression> arguments { get; private set; }
	internal CheckedRetainedOperation (SourceSpan span, RetainedAction action, CheckedExpression callee, GenericArray<CheckedExpression> arguments, SemanticType? status_type = null) {
		base (span, status_type ?? ((ClosureHandleType) callee.semantic_type).result_type);
		this.action = action;
		this.callee = callee;
		this.arguments = arguments;
	}

}
}
