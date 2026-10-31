// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra {
// A finite possibility set of concrete responsibilities, never pointer bits.
// Reachability/bottom and lexical lifetime remain separate from this lattice.
[Flags]
public enum OwnershipState {
	// OWNED includes legitimate null capabilities for both Resource and object results.
	// Nullability is a pointer property; MOVED remains a distinct unusable state.
	OWNED = 1,
	MOVED = 2,
	RELEASED = 4;

	public static OwnershipState join(OwnershipState left, OwnershipState right) {
		return (OwnershipState) ((int) left | (int) right);
	}

	public bool definitely_owned() {
		return this == OWNED;
	}
	public bool definitely_moved() {
		return this == MOVED;
	}
	public bool definitely_released() {
		return this == RELEASED;
	}
	public bool may_own() {
		return (this & OWNED) != 0;
	}
	public bool definitely_disarmed() {
		return !may_own ();
	}

	public string display_name() {
		if (definitely_owned ()) {
			return "OWNED";
		}
		if (definitely_moved ()) {
			return "MOVED";
		}
		if (definitely_released ()) {
			return "RELEASED";
		}
		// Preserve the established MOVE-1 dump without a combined-state enum.
		if (this == join (OWNED, MOVED)) {
			return "MAYBE_OWNED";
		}
		var names = new StringBuilder ("{");
		foreach (var state in new OwnershipState[] { OWNED, MOVED, RELEASED }) {
			if ((this & state) != 0) {
				if (names.len > 1) {
					names.append (", ");
				}
				names.append (state.display_name ());
			}
		}
		names.append ("}");
		return names.str;
	}
}

}
