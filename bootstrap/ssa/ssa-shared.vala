// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
namespace Astra.Ssa {
public class SsaSharedOperation : SsaInstruction {
	public SsaHeapOwner? source_owner { get; private set; }
	public SharedAction action { get; private set; }
	public SsaValue operand { get; private set; }
	public SsaCleanupContract? cleanup { get; private set; }
	public SsaFunctionParameter? borrower { get; private set; }
	internal SsaSharedOperation (SourceSpan span, SemanticType type, SharedAction action, SsaValue operand, SsaCleanupContract? cleanup, SsaFunctionParameter? borrower, int ordinal, SsaHeapOwner? source_owner = null) {
		base (span, type, ordinal);
		this.action = action;
		this.operand = operand;
		this.cleanup = cleanup;
		this.borrower = borrower;
		this.source_owner = source_owner;
	}
}
}
