// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Ssa {
public class SsaBaseLifecycleCall : SsaCallInstruction {
	internal SsaBaseLifecycleCall (SourceSpan span, SsaLifecycle target, GenericArray<SsaValue> arguments, SsaValue receiver) {
		base (span, null, -1, target, arguments, receiver);
	}
}

// Exact stage-owned lifecycle identity, independent of upstream symbols.
public abstract class SsaLifecycle : SsaFunction {
	private WeakRef owner;
	public SsaClass? declaring_class { owned get { return (SsaClass?) owner.get (); } }
	public SsaReceiver receiver { get; private set; }
	public int member_ordinal { get; private set; }
	protected SsaLifecycle (SourceSpan span, SourceSpan name_span, string name, SsaClass owner, SsaReceiver receiver, int member_ordinal, SemanticType void_type, int ordinal, GenericArray<SsaFunctionParameter> parameters, GenericArray<SsaBlock> blocks, SsaBlock entry) {
		base (span, name_span, name, void_type, ordinal, parameters, blocks, entry);
		this.owner = WeakRef (owner);
		this.receiver = receiver;
		this.member_ordinal = member_ordinal;
	}
}

public class SsaConstructor : SsaLifecycle {
	internal SsaConstructor (SourceSpan span, SourceSpan name_span, SsaClass owner, SsaReceiver receiver, int member_ordinal, SemanticType void_type, int ordinal, GenericArray<SsaFunctionParameter> parameters, GenericArray<SsaBlock> blocks, SsaBlock entry) {
		base (span, name_span, "init", owner, receiver, member_ordinal, void_type, ordinal, parameters, blocks, entry);
	}
}

public class SsaDestructor : SsaLifecycle {
	internal SsaDestructor (SourceSpan span, SourceSpan name_span, SsaClass owner, SsaReceiver receiver, int member_ordinal, SemanticType void_type, int ordinal, GenericArray<SsaFunctionParameter> parameters, GenericArray<SsaBlock> blocks, SsaBlock entry) {
		base (span, name_span, "deinit", owner, receiver, member_ordinal, void_type, ordinal, parameters, blocks, entry);
	}
}

public class SsaStorageReceiverInstruction : SsaInstruction {
	public SsaValue? allocation_context { get; private set; }
	public SsaHeapOwner? context_owner { get; private set; }
	public SsaObjectStorage storage { get; private set; }
	internal SsaStorageReceiverInstruction (SourceSpan span, SsaObjectStorage storage, ReceiverType contract, int ordinal, SsaValue? allocation_context = null, SsaHeapOwner? context_owner = null) {
		base (span, contract, ordinal);
		this.storage = storage;
		this.allocation_context = allocation_context;
		this.context_owner = context_owner;
	}
}

public class SsaLifecycleCallInstruction : SsaCallInstruction {
	public GenericArray<SsaFallibleInputRestore> input_restores { get; private set; default = new GenericArray<SsaFallibleInputRestore> (); }
	public GenericArray<SsaFallibleRecordRestore> record_restores { get; private set; default = new GenericArray<SsaFallibleRecordRestore> (); }
	public GenericArray<SsaFallibleBufferRestore> buffer_restores { get; private set; default = new GenericArray<SsaFallibleBufferRestore> (); }
	public SsaObjectStorage storage { get; private set; }
	public bool constructs { get { return target is SsaConstructor; } }
	internal SsaLifecycleCallInstruction (SourceSpan span, SsaLifecycle target, SsaObjectStorage storage, GenericArray<SsaValue> arguments, SsaValue receiver) {
		base (span, null, -1, target, arguments, receiver);
		this.storage = storage;
	}
}

// A fallible constructor consumes the captured input only after admission.
// Its caller slot retains the original owner on refusal and an empty owner
// on admission, including checked initialization failure.
public class SsaFallibleInputRestore : SsaInstruction {
	private WeakRef invocation;
	public SsaLifecycleCallInstruction? call { owned get { return (SsaLifecycleCallInstruction?) invocation.get (); } }
	public SsaOwnedArgument argument { get; private set; }
	public SsaHeapOwner owner { get; private set; }
	internal SsaFallibleInputRestore (SourceSpan span, SsaLifecycleCallInstruction call, SsaOwnedArgument argument, SsaHeapOwner owner, int ordinal) {
		base (span, argument.value.semantic_type, ordinal);
		this.invocation = WeakRef (call);
		this.argument = argument;
		this.owner = owner;
	}
}
public class SsaFallibleBufferRestore : SsaInstruction {
	private WeakRef invocation;
	public SsaLifecycleCallInstruction? call { owned get { return (SsaLifecycleCallInstruction?) invocation.get (); } }
	public SsaBufferArgument argument { get; private set; }
	public SsaBufferPair pair { get; private set; }
	internal SsaFallibleBufferRestore (SourceSpan span, SsaLifecycleCallInstruction call, SsaBufferArgument argument, int ordinal) {
		base (span, null, -1);
		invocation = WeakRef (call);
		this.argument = argument;
		pair = new SsaBufferPair.results (span, argument.pair.shape, ordinal);
	}
}
public class SsaFallibleRecordRestore : SsaRecordAdmissionRestore {
	private WeakRef invocation;
	public SsaLifecycleCallInstruction? call { owned get { return (SsaLifecycleCallInstruction?) invocation.get (); } }
	public override SsaValue admission_value() {
		return call.receiver;
	}
	internal SsaFallibleRecordRestore (SourceSpan span, SsaLifecycleCallInstruction call, SsaStructBoundaryMove original, SsaStructCallResults results) {
		base (span, original, results);
		invocation = WeakRef (call);
	}
}

}
