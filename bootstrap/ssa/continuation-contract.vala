// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Continuations {
// Immutable nominal leaves; neither names nor address layout supply identity.
public class ContinuationIdentity : Object {
}
public enum ContinuationRole {
	STEP, CANCEL_DRAIN, DESTROY
}
public enum ContinuationActionKind {
	CREATE, INITIALIZE, PUBLISH, MOVE, RETAIN, RELEASE, BEGIN, CALL, END, DESTROY
}

// Ordinals are typed by their action and checked against the complete region.
// Values index the region's already captured, dominance-checked SSA operands.
public class ContinuationAction : Object {
	public ContinuationActionKind kind { get; private set; }
	public int owner { get; private set; }
	public int destination { get; private set; }
	public int family { get; private set; }
	public int instance { get; private set; }
	public int witness { get; private set; }
	public int operand { get; private set; }
	public int first_entry { get; private set; }
	public int second_entry { get; private set; }
	public ContinuationRole role { get; private set; }
	private int[] captures;
	public int capture_count { get { return captures.length; } }
	public int capture(int index) {
		return captures[index];
	}
	internal ContinuationAction (ContinuationActionKind kind, int owner, int destination = -1, int family = -1, int instance = -1, int witness = -1, int operand = -1, int first_entry = -1, int second_entry = -1, ContinuationRole role = ContinuationRole.STEP, int[]? captures = null) {
		this.kind = kind;
		this.owner = owner;
		this.destination = destination;
		this.family = family;
		this.instance = instance;
		this.witness = witness;
		this.operand = operand;
		this.first_entry = first_entry;
		this.second_entry = second_entry;
		this.role = role;
		this.captures = captures == null ? null : captures.copy ();
	}
	public ContinuationAction copy() {
		return new ContinuationAction (kind, owner, destination, family, instance, witness, operand, first_entry, second_entry, role, captures);
	}
	public bool same_action(ContinuationAction other) {
		if (kind != other.kind || owner != other.owner || destination != other.destination || family != other.family || instance != other.instance || witness != other.witness || operand != other.operand || first_entry != other.first_entry || second_entry != other.second_entry || role != other.role || capture_count != other.capture_count) {
			return false;
		}
		for (int i = 0; i < captures.length; i++) {
			if (capture (i) != other.capture (i)) {
				return false;
			}
		}
		return true;
	}
}
}
