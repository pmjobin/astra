// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
namespace Astra.Core {
public class CoreRetainedOperation : CoreValue {
	public RetainedAction action { get; private set; }
	public CoreValue callee { get; private set; }
	public GenericArray<CoreValue> arguments { get; private set; }
	internal CoreRetainedOperation (SourceSpan span, RetainedAction action, CoreValue callee, GenericArray<CoreValue> arguments, SemanticType? status_type = null) {
		base (span, status_type ?? ((ClosureHandleType) callee.semantic_type).result_type);
		this.action = action;
		this.callee = callee;
		this.arguments = arguments;
	}

}
}
