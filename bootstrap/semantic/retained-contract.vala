// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
namespace Astra.Semantic {
public enum RetainedAction {
	REGISTER, DISPATCH, REVOKE, OBSERVE, THREAD_START, THREAD_JOIN, THREAD_CANCEL, SIGNAL_REGISTER, SIGNAL_REVOKE, SIGNAL_OBSERVE
}

public class RetainedContracts : Object {
	public static bool threaded(RetainedAction action) {
		return action >= RetainedAction.THREAD_START && action <= RetainedAction.THREAD_CANCEL;
	}

	public static bool reserved_symbol(string name) {
		return name.has_prefix ("astra_gobject16_signal_") || name.has_prefix ("astra.retained.signal.") || name.has_prefix ("astra.actor.") || name.has_prefix ("astra_actor_") && name != "astra_actor_cancelled" || name.has_prefix ("astra_singleton_") || name.has_prefix ("astra_monitor_") || name.has_prefix ("astra_concurrency_") || name.has_prefix ("astra_thread_") || name.has_prefix ("astra.thread.") || name == "astra_retained_register" || name == "astra_retained_dispatch" || name == "astra_retained_revoke" || name == "astra_retained_observe" || name == "astra_retained_retire" || name == "astra.retained.i32.thunk" || name == "astra.retained.retire";
	}

	public static bool signature(SemanticType type) {
		var closure = type as ClosureHandleType;
		return closure != null && !closure.actor && closure.throws_type == null && closure.supported () && closure.result_type.kind == TypeKind.INT && closure.parameter_types.length == 1 && closure.parameter_types[0].kind == TypeKind.INT;
	}

	public static bool signal(RetainedAction action) {
		return action >= RetainedAction.SIGNAL_REGISTER && action <= RetainedAction.SIGNAL_OBSERVE;
	}

	public static bool signal_signature(SemanticType type) {
		var closure = type as ClosureHandleType;
		if (closure == null || closure.actor || closure.threaded || closure.throws_type != null || !closure.supported () || closure.result_type.kind != TypeKind.VOID) {
			return false;
		}
		foreach (var parameter in closure.parameter_types) {
			var scalar = ForeignApiTypes.copied (parameter);
			if (scalar == null || !scalar.scalar ()) {
				return false;
			}
		}
		return true;
	}

	public static bool accepts(RetainedAction action, SemanticType type) {
		if (signal (action)) {
			return signal_signature (type);
		}
		return signature (type) && ((ClosureHandleType) type).threaded == threaded (action);
	}

	public static int arity(RetainedAction action) {
		return action == RetainedAction.REGISTER || action == RetainedAction.DISPATCH || action == RetainedAction.THREAD_START || action == RetainedAction.SIGNAL_REGISTER ? 1 : 0;
	}

	public static bool valid_action(RetainedAction action) {
		return action >= RetainedAction.REGISTER && action <= RetainedAction.SIGNAL_OBSERVE;
	}

}
}
