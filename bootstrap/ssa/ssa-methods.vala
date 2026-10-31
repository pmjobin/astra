// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Ssa {
// Exact stage-owned member identity; native bodies/signatures are reused.
public class SsaMethod : SsaFunction {
	public ClassMethodInstance? generic_method_instance { get; internal set; }
	private WeakRef owner;
	public SsaNativeInstance? declaring_type { owned get { return (SsaNativeInstance?) owner.get (); } }
	public SsaStruct? declaring_struct { owned get { return declaring_type as SsaStruct; } }
	public SsaReceiver receiver { get; private set; }
	public int method_ordinal { get; private set; }
	public int member_ordinal { get; private set; }

	internal SsaMethod (SourceSpan span, SourceSpan name_span, string name, SsaNativeInstance declaring_type, SsaReceiver receiver, int method_ordinal, int member_ordinal, SemanticType return_type, int ordinal, GenericArray<SsaFunctionParameter> parameters, GenericArray<SsaBlock> blocks, SsaBlock entry, SsaCleanupContract? owned_cleanup = null) {
		base (span, name_span, name, return_type, ordinal, parameters, blocks, entry, owned_cleanup);
		this.owner = WeakRef (declaring_type);
		this.receiver = receiver;
		this.method_ordinal = method_ordinal;
		this.member_ordinal = member_ordinal;
	}
}

// Implicit immutable input; absent from the explicit source parameter array.
public class SsaReceiver : SsaDefinition {
	public ReceiverType contract { get { return (ReceiverType) semantic_type; } }

	internal SsaReceiver (SourceSpan span, ReceiverType contract, int ordinal) {
		base (span, contract, ordinal);
	}
}
}
