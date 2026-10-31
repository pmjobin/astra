// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Core {
public class CoreBaseLifecycleCall : CoreCallStatement {
	internal CoreBaseLifecycleCall (SourceSpan span, CoreLifecycle target, GenericArray<CoreValue> arguments, CoreValue receiver) {
		base (span, target, arguments, receiver);
	}
}

// Exact stage-owned lifecycle identity, independent of upstream symbols.
public abstract class CoreLifecycle : CoreFunction {
	private WeakRef owner;
	public CoreClass? declaring_class { owned get { return (CoreClass?) owner.get (); } }
	public CoreReceiver receiver { get; private set; }
	public int member_ordinal { get; private set; }
	protected CoreLifecycle (SourceSpan span, SourceSpan name_span, string name, CoreClass owner, CoreReceiver receiver, int member_ordinal, SemanticType void_type, GenericArray<CoreParameter> parameters, GenericArray<CoreLocalPlace> locals, CoreBlock body) {
		base (span, name_span, name, void_type, parameters, locals, body);
		this.owner = WeakRef (owner);
		this.receiver = receiver;
		this.member_ordinal = member_ordinal;
	}
}

public class CoreConstructor : CoreLifecycle {
	public GenericArray<CoreOwnedFieldCleanup> unwind_fields { get; private set; default = new GenericArray<CoreOwnedFieldCleanup> (); }
	public GenericArray<CoreProperty> unwind_lazy { get; private set; default = new GenericArray<CoreProperty> (); }
	internal CoreConstructor (SourceSpan span, SourceSpan name_span, CoreClass owner, CoreReceiver receiver, int member_ordinal, SemanticType void_type, GenericArray<CoreParameter> parameters, GenericArray<CoreLocalPlace> locals, CoreBlock body) {
		base (span, name_span, "init", owner, receiver, member_ordinal, void_type, parameters, locals, body);
	}
}

public class CoreDestructor : CoreLifecycle {
	public GenericArray<CoreProperty> lazy_cleanups { get; private set; default = new GenericArray<CoreProperty> (); }
	public GenericArray<CoreOwnedFieldCleanup> field_cleanups { get; private set; default = new GenericArray<CoreOwnedFieldCleanup> (); }
	internal CoreDestructor (SourceSpan span, SourceSpan name_span, CoreClass owner, CoreReceiver receiver, int member_ordinal, SemanticType void_type, GenericArray<CoreParameter> parameters, GenericArray<CoreLocalPlace> locals, CoreBlock body) {
		base (span, name_span, "deinit", owner, receiver, member_ordinal, void_type, parameters, locals, body);
	}
}

public class CoreConstructorObjectInitialization : CoreObjectConstruction {
	public CoreValue? allocation_context { get; private set; }
	private WeakRef callee;
	public CoreConstructor? constructor { owned get { return (CoreConstructor?) callee.get (); } }
	public GenericArray<CoreValue> arguments { get; private set; }
	internal CoreConstructorObjectInitialization (SourceSpan span, CoreObjectStorage storage, CoreLocalPlace target, CoreConstructor constructor, GenericArray<CoreValue> arguments, CoreValue? allocation_context = null) {
		base (span, storage, target, new GenericArray<CoreObjectFieldInitializer> ());
		this.callee = WeakRef (constructor);
		this.arguments = arguments;
		this.allocation_context = allocation_context;
	}
}

public class CoreStorageReceiverValue : CoreValue {
	public CoreObjectStorage storage { get; private set; }
	internal CoreStorageReceiverValue (SourceSpan span, CoreObjectStorage storage, ReceiverType contract) {
		base (span, contract);
		this.storage = storage;
	}
}

public class CoreFieldInitialize : CoreInitialize {
	internal CoreFieldInitialize (SourceSpan span, CoreIndirectFieldPlace target, CoreValue value) {
		base (span, target, value);
	}
}

public enum CleanupActionKind {
	OWNED_DESTROY, OBJECT_DEINIT, ENUM_DESTROY, TASK_END, EXECUTOR_END
}

// One lexical list orders fixed ObjectStorage and transferable owner slots.
// An owner carries either native object or foreign Resource cleanup authority.
public class CoreCleanupAction : Object {
	public CoreFieldPlace? record_field { get; internal set; }
	public bool record_final { get; internal set; }
	public CoreLocalPlace? task { get; private set; }
	public CoreLocalPlace? enumeration { get; private set; }
	public CleanupActionKind kind { get; private set; }
	public CoreOwnedLocal? owner { get; private set; }
	public CoreObjectStorage? storage { get; private set; }
	internal CoreCleanupAction.for_owner (CoreOwnedLocal owner) {
		this.kind = CleanupActionKind.OWNED_DESTROY;
		this.owner = owner;
	}
	internal CoreCleanupAction.object (CoreObjectStorage storage) {
		this.kind = CleanupActionKind.OBJECT_DEINIT;
		this.storage = storage;
	}
	internal CoreCleanupAction.for_enum (CoreLocalPlace enumeration) {
		this.kind = CleanupActionKind.ENUM_DESTROY;
		this.enumeration = enumeration;
	}
	internal CoreCleanupAction.for_executor (CoreLocalPlace executor) {
		kind = CleanupActionKind.EXECUTOR_END;
		this.task = executor;
	}
	internal CoreCleanupAction.for_task (CoreLocalPlace task) {
		kind = CleanupActionKind.TASK_END;
		this.task = task;
	}
}
}
