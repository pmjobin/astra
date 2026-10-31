// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
namespace Astra.Core {
public class CoreCallbackParameterView : CoreValue {
	public CoreParameter source { get; private set; }
	public CoreParameter parameter { get; private set; }
	internal CoreCallbackParameterView (SourceSpan span, CallbackType type, CoreParameter source, CoreParameter parameter) {
		base (span, type);
		this.source = source;
		this.parameter = parameter;
	}
}
public class CoreClosureBind : CoreValue {
	public ActorBindingSpec? actor_binding { get; private set; }
	public CoreOwnedLocal source { get; private set; }
	private WeakRef code;
	public CoreFunction? target { owned get { return (CoreFunction?) code.get (); } }
	public CoreCleanupContract cleanup { get; private set; }
	internal CoreClosureBind (SourceSpan span, ClosureHandleType type, CoreOwnedLocal source, CoreFunction target, CoreCleanupContract cleanup, ActorBindingSpec? actor_binding = null) {
		base (span, type);
		this.source = source;
		code = WeakRef (target);
		this.cleanup = cleanup;
		this.actor_binding = actor_binding == null ? null : actor_binding.copy ();
	}
}
public class CoreClosureCall : CoreValue, CoreInvocation {
	public CoreCleanupContract? owned_cleanup { get; private set; }
	public CoreCleanupContract? result_cleanup() {
		return owned_cleanup;
	}
	public GenericArray<CoreParameter> channel_parameters { get; private set; default = new GenericArray<CoreParameter> (); }
	public CoreValue callee { get; private set; }
	public GenericArray<CoreValue> arguments { get; private set; }
	internal CoreClosureCall (SourceSpan span, ClosureHandleType type, CoreValue callee, GenericArray<CoreValue> arguments, CoreCleanupContract? owned_cleanup = null) {
		base (span, type.result_type);
		this.callee = callee;
		this.arguments = arguments;
		this.owned_cleanup = owned_cleanup;
	}
}
}
namespace Astra.Core {
public class CoreActorSend : CoreStatement {
	public ActorAction action { get; private set; }
	public CoreValue sender { get; private set; }
	public CoreValue? scalar { get; private set; }
	public CoreOwnedLocal? message { get; private set; }
	public ClassType error_type { get; private set; }
	internal CoreActorSend (SourceSpan span, ActorAction action, CoreValue sender, CoreValue? scalar, CoreOwnedLocal? message, ClassType error_type) {
		base (span);
		this.action = action;
		this.sender = sender;
		this.scalar = scalar;
		this.message = message;
		this.error_type = error_type;
	}
}
}
