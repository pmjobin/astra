// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
namespace Astra.Cfg {
// Direct and code-value invocations share the same capture/commit/abort
// lifetime boundary. Only these exact evaluation nodes can consume a move.
public class CfgInvocationContracts : Object {
	private static CfgValue? value(CfgInstruction instruction) {
		var record = instruction as CfgStructInvoke;
		if (record != null) {
			return record.checked_call == null ? record.call : null;
		}
		var evaluation = instruction as CfgEvaluateInstruction;
		return evaluation == null ? null : evaluation.value;
	}
	internal static GenericArray<CfgStructBoundaryMove>? record_moves(CfgInstruction instruction) {
		var direct = instruction as CfgCallInstruction;
		if (direct != null) {
			return direct.record_moves;
		}
		var invocation = value (instruction);
		var function = invocation as CfgFunctionValueCall;
		if (function != null) {
			return function.record_moves;
		}
		var closure = invocation as CfgClosureCall;
		return closure == null ? null : closure.record_moves;
	}
	internal static GenericArray<CfgValue>? arguments(CfgInstruction instruction) {
		var direct = instruction as CfgCallInstruction;
		if (direct != null) {
			return direct.arguments;
		}
		var invocation = value (instruction);
		var function = invocation as CfgFunctionValueCall;
		if (function != null) {
			return function.arguments;
		}
		var closure = invocation as CfgClosureCall;
		return closure == null ? null : closure.arguments;
	}
}
public class CfgCallbackParameterView : CfgValue {
	public CfgParameter source { get; private set; }
	public CfgParameter parameter { get; private set; }
	internal CfgCallbackParameterView (SourceSpan span, CallbackType type, CfgParameter source, CfgParameter parameter) {
		base (span, type);
		this.source = source;
		this.parameter = parameter;
	}
}
public class CfgClosureBind : CfgValue {
	public ActorBindingSpec? actor_binding { get; private set; }
	public CfgValue environment { get; private set; }
	private WeakRef code;
	public CfgFunction? target { owned get { return (CfgFunction?) code.get (); } }
	public CfgCleanupContract cleanup { get; private set; }
	internal CfgClosureBind (SourceSpan span, ClosureHandleType type, CfgValue environment, CfgFunction target, CfgCleanupContract cleanup, ActorBindingSpec? actor_binding = null) {
		base (span, type);
		this.environment = environment;
		code = WeakRef (target);
		this.cleanup = cleanup;
		this.actor_binding = actor_binding == null ? null : actor_binding.copy ();
	}
}
public class CfgClosureCall : CfgValue, CfgInvocation {
	public CfgCleanupContract? owned_cleanup { get; private set; }
	public CfgCleanupContract? result_cleanup() {
		return owned_cleanup;
	}
	public GenericArray<CfgStructBoundaryMove> record_moves { get; private set; default = new GenericArray<CfgStructBoundaryMove> (); }
	public GenericArray<StructBoundaryGroup> struct_arguments { get; private set; default = new GenericArray<StructBoundaryGroup> (); }
	public GenericArray<CfgParameter> channel_parameters { get; private set; default = new GenericArray<CfgParameter> (); }
	public CfgValue callee { get; private set; }
	public GenericArray<CfgValue> arguments { get; private set; }
	internal CfgClosureCall (SourceSpan span, ClosureHandleType type, CfgValue callee, GenericArray<CfgValue> arguments, CfgCleanupContract? owned_cleanup = null) {
		base (span, type.result_type);
		this.callee = callee;
		this.arguments = arguments;
		this.owned_cleanup = owned_cleanup;
	}
}
// A checked indirect call produces only the rooted native exception channel.
// The scalar result remains private until a verified null-error successor.
public class CfgCheckedClosureInvoke : CfgEvaluateInstruction {
	public CfgClosureCall call { get; private set; }
	internal CfgCheckedClosureInvoke (SourceSpan span, CfgClosureCall call, ClassType root) {
		base (span, call, new CfgEvaluatedValue (span, root));
		this.call = call;
	}
}
public class CfgClosureCallSuccess : CfgEvaluateInstruction {
	public CfgCheckedClosureInvoke invocation { get; private set; }
	internal CfgClosureCallSuccess (SourceSpan span, CfgCheckedClosureInvoke invocation) {
		base (span, invocation.call, new CfgEvaluatedValue (span, invocation.call.semantic_type));
		this.invocation = invocation;
	}
}

}
namespace Astra.Cfg {
public class CfgActorSend : CfgEvaluateInstruction {
	public ActorAction action { get; private set; }
	public CfgValue sender { get { return value; } }
	public CfgValue? message { get; private set; }
	public ClassType error_type { get; private set; }
	internal CfgActorSend (SourceSpan span, ActorAction action, CfgValue sender, CfgValue? message, ClassType error_type) {
		base (span, sender, new CfgEvaluatedValue (span, error_type));
		this.action = action;
		this.message = message;
		this.error_type = error_type;
	}
}
}
