// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Foreign;

namespace Astra.Ssa {
// Stage-owned authority; the nominal token has no upstream backlinks.
public class SsaHandle : SsaNode {
	private string context_contract;
	public string context_mode { get { return context_contract; } }
	public ForeignImportContract? c_import { get; internal set; }
	public ComImportContract? com_import { get; internal set; }
	public SourceSpan name_span { get; private set; }
	public HandleType semantic_type { get; private set; }
	public string name { get { return semantic_type.name; } }
	public SsaCleanupContract cleanup { get; private set; }
	public CForeignHeader? header { get; private set; }
	public int ordinal { get; private set; }

	internal SsaHandle (SourceSpan span, SourceSpan name_span, HandleType semantic_type, SsaCleanupContract cleanup, CForeignHeader? header, int ordinal, string context_mode = "") {
		base (span);
		this.name_span = name_span;
		this.semantic_type = semantic_type;
		this.cleanup = cleanup;
		this.header = header == null ? null : new CForeignHeader (header.name, header.span);
		this.ordinal = ordinal;
		this.context_contract = context_mode;
	}
}
}
