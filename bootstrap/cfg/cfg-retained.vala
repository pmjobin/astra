// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
namespace Astra.Cfg {
public class CfgRetainedOperation : CfgValue {
	public RetainedAction action { get; private set; }
	public CfgValue callee { get; private set; }
	public GenericArray<CfgValue> arguments { get; private set; }
	internal CfgRetainedOperation (SourceSpan span, RetainedAction action, CfgValue callee, GenericArray<CfgValue> arguments, SemanticType? status_type = null) {
		base (span, status_type ?? ((ClosureHandleType) callee.semantic_type).result_type);
		this.action = action;
		this.callee = callee;
		this.arguments = arguments;
	}
}
}
