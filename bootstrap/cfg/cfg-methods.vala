// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Cfg {
// Exact stage-owned member identity; native bodies/signatures are reused.
public class CfgMethod : CfgFunction {
	public ClassMethodInstance? generic_method_instance { get; internal set; }
	private WeakRef owner;
	public CfgNativeInstance? declaring_type { owned get { return (CfgNativeInstance?) owner.get (); } }
	public CfgStruct? declaring_struct { owned get { return declaring_type as CfgStruct; } }
	public CfgReceiver receiver { get; private set; }
	public int method_ordinal { get; private set; }
	public int member_ordinal { get; private set; }

	internal CfgMethod (SourceSpan span, SourceSpan name_span, string name, CfgNativeInstance declaring_type, CfgReceiver receiver, int method_ordinal, int member_ordinal, SemanticType return_type, int ordinal, GenericArray<CfgParameter> parameters, GenericArray<CfgLocalPlace> locals, GenericArray<CfgBlock> blocks, CfgBlock entry, CfgCleanupContract? owned_cleanup = null) {
		base (span, name_span, name, return_type, ordinal, parameters, locals, blocks, entry, owned_cleanup);
		this.owner = WeakRef (declaring_type);
		this.receiver = receiver;
		this.method_ordinal = method_ordinal;
		this.member_ordinal = member_ordinal;
	}
}

public class CfgReceiver : CfgNode {
	public ReceiverType contract { get; private set; }

	internal CfgReceiver (SourceSpan span, ReceiverType contract) {
		base (span);
		this.contract = contract;
	}
}

public class CfgReceiverValue : CfgValue {
	public CfgReceiver receiver { get; private set; }

	internal CfgReceiverValue (SourceSpan span, CfgReceiver receiver) {
		base (span, receiver.contract);
		this.receiver = receiver;
	}
}
}
