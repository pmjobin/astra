// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
namespace Astra.Semantic {
// Exact opt-in lifetime domain. Handle transport is linear; payload identity
// is never the handle/control-block identity and no Class layout is changed.
public class SharedHandleType : HandleType {
	public ClassType payload_type { get; private set; }
	public bool is_weak { get; private set; }
	internal SharedHandleType (ClassType payload_type, bool is_weak) {
		base ((is_weak ? "Weak<" : "Shared<") + payload_type.display_name () + ">");
		this.payload_type = payload_type;
		this.is_weak = is_weak;
	}

}
public enum SharedAction {
	ACQUIRE, CLONE, DOWNGRADE, WEAK_CLONE, UPGRADE, BORROW, SINGLETON_SHUTDOWN
}

public class SharedContracts : Object {
	public static bool matches(SharedAction action, SemanticType input, SemanticType output) {
		if (input is ClosureHandleType && ((ClosureHandleType) input).actor) {
			return action == SharedAction.CLONE && output == input && ((ClosureHandleType) input).supported ();
		}
		var from = input as SharedHandleType;
		var to = output as SharedHandleType;
		var intrinsic = input as ClassType;
		if (intrinsic != null && intrinsic.intrinsically_shared) {
			if (action == SharedAction.SINGLETON_SHUTDOWN) {
				return intrinsic.concurrency_policy_identity == 7 && output == input;
			}
			return action == SharedAction.CLONE && output == input || action == SharedAction.DOWNGRADE && to != null && to.is_weak && to.payload_type == input;
		}
		if (from != null && from.is_weak && from.payload_type.intrinsically_shared && action == SharedAction.UPGRADE) {
			return output == from.payload_type;
		}

		if (action == SharedAction.ACQUIRE) {
			return input is ClassType && ((ClassType) input).concurrency_policy_identity != 16 && to != null && !to.is_weak && to.payload_type == input;
		}
		if (from == null) {
			return false;
		}
		if (action == SharedAction.BORROW) {
			return !from.is_weak && output == from.payload_type;
		}
		if (to == null || to.payload_type != from.payload_type) {
			return false;
		}
		switch (action) {
		case SharedAction.CLONE:
			return !from.is_weak && !to.is_weak;
		case SharedAction.DOWNGRADE:
			return !from.is_weak && to.is_weak;
		case SharedAction.WEAK_CLONE:
			return from.is_weak && to.is_weak;
		case SharedAction.UPGRADE:
			return from.is_weak && !to.is_weak;
		default:
			return false;
		}
	}

}
}
