// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
namespace Astra.Core {
public class CoreSharedOperation : CoreValue {
	public SharedAction action { get; private set; }
	public CoreValue operand { get; private set; }
	public CoreOwnedLocal? source { get; private set; }
	public CoreCleanupContract? cleanup { get; private set; }
	public CoreParameter? borrower { get; private set; }
	internal CoreSharedOperation (SourceSpan span, SemanticType type, SharedAction action, CoreValue operand, CoreOwnedLocal? source, CoreCleanupContract? cleanup, CoreParameter? borrower) {
		base (span, type);
		this.action = action;
		this.operand = operand;
		this.source = source;
		this.cleanup = cleanup;
		this.borrower = borrower;
	}
}
}
