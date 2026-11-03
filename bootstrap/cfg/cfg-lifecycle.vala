// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Cfg {
public class CfgBaseLifecycleCall : CfgCallInstruction {
	internal CfgBaseLifecycleCall (SourceSpan span, CfgLifecycle target, GenericArray<CfgValue> arguments, CfgValue receiver) {
		base (span, target, arguments, null, receiver);
	}

}

// Exact stage-owned lifecycle identity, independent of upstream symbols.
public abstract class CfgLifecycle : CfgFunction {
	private WeakRef owner;
	public CfgClass? declaring_class { owned get { return (CfgClass?) owner.get (); } }
	public CfgReceiver receiver { get; private set; }
	public int member_ordinal { get; private set; }
	protected CfgLifecycle (SourceSpan span, SourceSpan name_span, string name, CfgClass owner, CfgReceiver receiver, int member_ordinal, SemanticType void_type, int ordinal, GenericArray<CfgParameter> parameters, GenericArray<CfgLocalPlace> locals, GenericArray<CfgBlock> blocks, CfgBlock entry) {
		base (span, name_span, name, void_type, ordinal, parameters, locals, blocks, entry);
		this.owner = WeakRef (owner);
		this.receiver = receiver;
		this.member_ordinal = member_ordinal;
	}

}

public class CfgConstructor : CfgLifecycle {
	internal CfgConstructor (SourceSpan span, SourceSpan name_span, CfgClass owner, CfgReceiver receiver, int member_ordinal, SemanticType void_type, int ordinal, GenericArray<CfgParameter> parameters, GenericArray<CfgLocalPlace> locals, GenericArray<CfgBlock> blocks, CfgBlock entry) {
		base (span, name_span, "init", owner, receiver, member_ordinal, void_type, ordinal, parameters, locals, blocks, entry);
	}

}

public class CfgDestructor : CfgLifecycle {
	internal CfgDestructor (SourceSpan span, SourceSpan name_span, CfgClass owner, CfgReceiver receiver, int member_ordinal, SemanticType void_type, int ordinal, GenericArray<CfgParameter> parameters, GenericArray<CfgLocalPlace> locals, GenericArray<CfgBlock> blocks, CfgBlock entry) {
		base (span, name_span, "deinit", owner, receiver, member_ordinal, void_type, ordinal, parameters, locals, blocks, entry);
	}

}

public class CfgStorageReceiverValue : CfgValue {
	public CfgValue? allocation_context { get; private set; }
	public CfgObjectStorage storage { get; private set; }
	internal CfgStorageReceiverValue (SourceSpan span, CfgObjectStorage storage, ReceiverType contract, CfgValue? allocation_context = null) {
		base (span, contract);
		this.storage = storage;
		this.allocation_context = allocation_context;
	}

}

// Normal return from a constructor call is the successful construction
// authority. A deinit call consumes that storage's lexical responsibility.
public class CfgLifecycleCallInstruction : CfgCallInstruction {
	public CfgObjectStorage storage { get; private set; }
	public bool constructs { get { return target is CfgConstructor; } }
	internal CfgLifecycleCallInstruction (SourceSpan span, CfgLifecycle target, CfgObjectStorage storage, GenericArray<CfgValue> arguments, CfgValue? allocation_context = null) {
		base (span, target, arguments, null, new CfgStorageReceiverValue (span, storage, target.receiver.contract, allocation_context));
		this.storage = storage;
	}

}
}
