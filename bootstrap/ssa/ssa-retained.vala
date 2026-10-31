// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
namespace Astra.Ssa {
public class SsaRetainedOperation : SsaInstruction {
	public RetainedAction action { get; private set; }
	public SsaValue callee { get; private set; }
	public GenericArray<SsaValue> arguments { get; private set; }
	public SsaHeapOwner? source_owner { get; private set; }
	internal SsaRetainedOperation (SourceSpan span, RetainedAction action, SsaValue callee, GenericArray<SsaValue> arguments, int ordinal, SsaHeapOwner? source_owner = null, SemanticType? status_type = null) {
		base (span, status_type ?? ((ClosureHandleType) callee.semantic_type).result_type, ordinal);
		this.action = action;
		this.callee = callee;
		this.arguments = arguments;
		this.source_owner = source_owner;
	}
}
}
