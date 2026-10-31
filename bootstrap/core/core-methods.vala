// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Core {
// Exact stage-owned member identity; native bodies/signatures are reused.
public class CoreMethod : CoreFunction {
	public ClassMethodInstance? generic_method_instance { get; internal set; }
	public CoreGenericIdentity? application_scope { get; internal set; }
	private WeakRef owner;
	public CoreNativeInstance? declaring_type { owned get { return (CoreNativeInstance?) owner.get (); } }
	public CoreStruct? declaring_struct { owned get { return declaring_type as CoreStruct; } }
	public CoreReceiver receiver { get; private set; }
	public int method_ordinal { get; private set; }
	public int member_ordinal { get; private set; }

	internal CoreMethod (SourceSpan span, SourceSpan name_span, string name, CoreNativeInstance declaring_type, CoreReceiver receiver, int method_ordinal, int member_ordinal, SemanticType return_type, GenericArray<CoreParameter> parameters, GenericArray<CoreLocalPlace> locals, CoreBlock body, CoreCleanupContract? owned_cleanup = null) {
		base (span, name_span, name, return_type, parameters, locals, body, owned_cleanup);
		this.owner = WeakRef (declaring_type);
		this.receiver = receiver;
		this.method_ordinal = method_ordinal;
		this.member_ordinal = member_ordinal;
	}
}

public class CoreReceiver : CoreNode {
	public ReceiverType contract { get; private set; }

	internal CoreReceiver (SourceSpan span, ReceiverType contract) {
		base (span);
		this.contract = contract;
	}
}

public class CoreReceiverValue : CoreValue {
	public CoreReceiver receiver { get; private set; }

	internal CoreReceiverValue (SourceSpan span, CoreReceiver receiver) {
		base (span, receiver.contract);
		this.receiver = receiver;
	}
}
}
