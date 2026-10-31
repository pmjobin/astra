// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
namespace Astra.Cfg {
public class CfgSharedOperation : CfgValue {
	public SharedAction action { get; private set; }
	public CfgValue operand { get; private set; }
	public CfgCleanupContract? cleanup { get; private set; }
	public CfgParameter? borrower { get; private set; }
	internal CfgSharedOperation (SourceSpan span, SemanticType type, SharedAction action, CfgValue operand, CfgCleanupContract? cleanup, CfgParameter? borrower) {
		base (span, type);
		this.action = action;
		this.operand = operand;
		this.cleanup = cleanup;
		this.borrower = borrower;
	}
}
}
