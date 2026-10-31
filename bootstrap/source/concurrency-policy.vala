// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
namespace Astra.Source {
// Per-binding mailbox metadata. Later stages copy the original admission
// identity, rather than making a new contract from a mutated name/capacity.
public class ActorBindingSpec : Object {
	public int capacity { get; internal set; }
	private string label;
	public string name { get { return label; } }
	public void alter_name(string value) {
		label = value;
	}
	private int admitted_capacity;
	private string admitted_name;
	public ActorBindingSpec (int capacity, string name) {
		this.capacity = admitted_capacity = capacity;
		this.label = admitted_name = name;
	}
	public bool valid() {
		if (capacity != admitted_capacity || name != admitted_name || capacity < 1 || capacity > 1024 || name.length < 1 || name.length > 15) {
			return false;
		}
		for (int i = 0; i < name.length; i++) {
			if (name[i] < 32 || name[i] > 126) {
				return false;
			}
		}
		return true;
	}
	public string dump() {
		return "fifo=%d executor=\"%s\"".printf (capacity, name.escape ());
	}
	public ActorBindingSpec copy() {
		var result = new ActorBindingSpec (admitted_capacity, admitted_name);
		result.capacity = capacity;
		result.label = label;
		return result;
	}
}

public enum ActorAction {
	SEND, SHUTDOWN, CANCEL
}

[Flags]
public enum ConcurrencyKind {
	NONE = 0, SHARED = 1, MONITOR = 2, SINGLETON = 4, THREAD_BOUND = 8, ACTOR = 16;

	public static ConcurrencyKind parse(string name) {
		switch (DeclarationPolicyRegistry.lookup (name)) {
		case DeclarationPolicyId.SHARED:
			return SHARED;
		case DeclarationPolicyId.MONITOR:
			return MONITOR;
		case DeclarationPolicyId.SINGLETON:
			return SINGLETON;
		case DeclarationPolicyId.THREAD_BOUND:
			return THREAD_BOUND;
		case DeclarationPolicyId.ACTOR:
			return ACTOR;
		default:
			return NONE;
		}
	}
}

// Primitive, stage-neutral declaration evidence, independent of AST/symbols.
// Copying an altered policy cannot admit a new identity at a later stage.
public class ConcurrencyPolicy : Object {
	public ConcurrencyKind kinds { get; internal set; }
	private ConcurrencyKind admitted;
	public uint identity { get { return (uint) admitted; } }
	public bool shared { get { return (kinds & ConcurrencyKind.SHARED) != 0; } }
	public bool monitor { get { return (kinds & ConcurrencyKind.MONITOR) != 0; } }
	public bool singleton { get { return (kinds & ConcurrencyKind.SINGLETON) != 0; } }
	public bool thread_bound { get { return (kinds & ConcurrencyKind.THREAD_BOUND) != 0; } }
	public bool actor { get { return (kinds & ConcurrencyKind.ACTOR) != 0; } }

	public ConcurrencyPolicy (ConcurrencyKind kinds) {
		this.kinds = kinds;
		admitted = kinds;
	}
	public bool valid() {
		return kinds == admitted && kinds != ConcurrencyKind.NONE && ((uint) kinds & ~31u) == 0 && !(actor && monitor);
	}
	public ConcurrencyPolicy copy() {
		var result = new ConcurrencyPolicy (admitted);
		result.kinds = kinds;
		return result;
	}
	public static bool matches(ConcurrencyPolicy? policy, uint identity) {
		return policy == null ? identity == 0 : policy.valid () && policy.identity == identity;
	}
	public string dump() {
		return "(concurrency-policy identity=%u shared=%s monitor=%s singleton=%s thread-bound=%s actor=%s)".printf (identity, shared.to_string (), monitor.to_string (), singleton.to_string (), thread_bound.to_string (), actor.to_string ());
	}
}
}
