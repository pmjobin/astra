// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Foreign;
namespace Astra.Semantic {
public class CheckedCallbackParameterView : CheckedExpression {
	public ParameterSymbol source { get; private set; }
	public ParameterSymbol parameter { get; private set; }
	internal CheckedCallbackParameterView (SourceSpan span, CallbackType type, ParameterSymbol source, ParameterSymbol parameter) {
		base (span, type);
		this.source = source;
		this.parameter = parameter;
	}

}
public class CheckedClosureBind : CheckedExpression {
	public ActorBindingSpec? actor_binding { get; private set; }
	public LocalSymbol source { get; private set; }
	private WeakRef code;
	public FunctionSymbol? target { owned get { return (FunctionSymbol?) code.get (); } }
	public CForeignCleanupContract cleanup { get; private set; }
	internal CheckedClosureBind (SourceSpan span, ClosureHandleType type, LocalSymbol source, FunctionSymbol target, CForeignCleanupContract cleanup, ActorBindingSpec? actor_binding = null) {
		base (span, type);
		this.source = source;
		code = WeakRef (target);
		this.cleanup = cleanup;
		this.actor_binding = actor_binding == null ? null : actor_binding.copy ();
	}

}
public class CheckedClosureCall : CheckedExpression, CheckedInvocation {
	public OwnedValueProducer? owned_producer { get; internal set; }
	public OwnedValueProducer? result_producer() {
		return owned_producer;
	}

	public GenericArray<ParameterSymbol> channel_parameters { get; private set; default = new GenericArray<ParameterSymbol> (); }
	public CheckedExpression callee { get; private set; }
	public GenericArray<CheckedExpression> arguments { get; private set; }
	internal CheckedClosureCall (SourceSpan span, ClosureHandleType type, CheckedExpression callee, GenericArray<CheckedExpression> arguments) {
		base (span, type.result_type);
		this.callee = callee;
		this.arguments = arguments;
	}

}
}
namespace Astra.Semantic {
public class CheckedActorSend : CheckedStatement {
	public ActorAction action { get; private set; }
	public CheckedExpression sender { get; private set; }
	public CheckedExpression? scalar { get; private set; }
	public LocalSymbol? message { get; private set; }
	public ClassType error_type { get; private set; }
	internal CheckedActorSend (SourceSpan span, ActorAction action, CheckedExpression sender, CheckedExpression? scalar, LocalSymbol? message, ClassType error_type) {
		base (span);
		this.action = action;
		this.sender = sender;
		this.scalar = scalar;
		this.message = message;
		this.error_type = error_type;
	}

}
}
