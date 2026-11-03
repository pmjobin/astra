// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
// Conditional facts contain no nested flow state. They describe the two
// possible outcomes of a captured Boolean, including lowered short circuits.
private class NonNullOutcome : Object {
	internal bool possible;
	internal HashTable<Object, bool> facts = new HashTable<Object, bool> (direct_hash, direct_equal);
	internal NonNullOutcome (bool possible) {
		this.possible = possible;
	}

	internal NonNullOutcome copy() {
		var result = new NonNullOutcome (possible);
		foreach (var key in facts.get_keys ()) {
			result.facts.insert (key, true);
		}
		return result;
	}

	internal static NonNullOutcome meet(NonNullOutcome a, NonNullOutcome b) {
		if (!a.possible) {
			return b.copy ();
		}
		if (!b.possible) {
			return a.copy ();
		}
		var result = new NonNullOutcome (true);
		foreach (var key in a.facts.get_keys ()) {
			if (b.facts.contains (key)) {
				result.facts.insert (key, true);
			}
		}
		return result;
	}

	internal bool same(NonNullOutcome other) {
		if (possible != other.possible || facts.size () != other.facts.size ()) {
			return false;
		}
		foreach (var key in facts.get_keys ()) {
			if (!other.facts.contains (key)) {
				return false;
			}
		}
		return true;
	}

}
private class NonNullPredicate : Object {
	internal NonNullOutcome yes;
	internal NonNullOutcome no;
	internal NonNullPredicate (NonNullOutcome yes, NonNullOutcome no) {
		this.yes = yes;
		this.no = no;
	}

	internal NonNullPredicate copy() {
		return new NonNullPredicate (yes.copy (), no.copy ());
	}

}
// Canonical keys belong to one stage's proof run. A projection is a pure
// borrowed property of one exact receiver; effects erase all such facts.
public class NonNullProjections : Object {
	private HashTable<Object, HashTable<Object, Object>> receivers = new HashTable<Object, HashTable<Object, Object>> (direct_hash, direct_equal);
	public Object? key(Object? receiver, Object member) {
		if (receiver == null) {
			return null;
		}
		var members = receivers.lookup (receiver);
		if (members == null) {
			members = new HashTable<Object, Object> (direct_hash, direct_equal);
			receivers.insert (receiver, members);
		}
		var value = members.lookup (member);
		if (value == null) {
			value = new Object ();
			members.insert (member, value);
		}
		return value;
	}

	public void invalidate(NonNullFacts state) {
		foreach (var members in receivers.get_values ()) {
			foreach (var value in members.get_values ()) {
				state.assign (value, false);
			}
		}
	}

}
// Mechanical must-fact storage shared by independent stage adapters. Keys are
// stage-owned slots/values; this class never interprets a predecessor model.
public class NonNullFacts : Object {
	public bool reachable { get; set; default = true; }
	private HashTable<Object, bool> facts = new HashTable<Object, bool> (direct_hash, direct_equal);
	private HashTable<Object, Object> aliases = new HashTable<Object, Object> (direct_hash, direct_equal);
	private HashTable<Object, NonNullPredicate> predicates = new HashTable<Object, NonNullPredicate> (direct_hash, direct_equal);
	private NonNullOutcome outcome() {
		var result = new NonNullOutcome (reachable);
		foreach (var key in facts.get_keys ()) {
			result.facts.insert (key, true);
		}
		return result;
	}

	public void boolean(Object value, NonNullFacts yes, NonNullFacts no) {
		predicates.insert (value, new NonNullPredicate (yes.outcome (), no.outcome ()));
	}

	public void assume(Object value, bool truth) {
		var predicate = predicates.lookup (value);
		if (predicate == null) {
			return;
		}
		var outcome = truth ? predicate.yes : predicate.no;
		if (!outcome.possible) {
			reachable = false;
			return;
		}
		foreach (var key in outcome.facts.get_keys ()) {
			refine (key);
		}
	}

	private void invalidate(Object key) {
		predicates.remove (key);
		foreach (var predicate in predicates.get_values ()) {
			predicate.yes.facts.remove (key);
			predicate.no.facts.remove (key);
		}
	}

	public bool knows(Object key) {
		return facts.contains (key);
	}

	public Object? backing(Object value) {
		return aliases.lookup (value);
	}

	private void set_fact(Object key, bool proven) {
		if (proven) {
			facts.insert (key, true);
		} else {
			facts.remove (key);
		}
	}

	public void capture(Object value, bool proven, Object? backing = null) {
		invalidate (value);
		set_fact (value, proven);
		aliases.remove (value);
		if (backing != null) {
			aliases.insert (value, backing);
		}
	}

	public void assign(Object slot, bool proven) {
		invalidate (slot);
		foreach (var value in aliases.get_keys ()) {
			if (aliases.lookup (value) == slot) {
				aliases.remove (value);
			}
		}
		set_fact (slot, proven);
	}

	public void refine(Object value) {
		set_fact (value, true);
		var slot = aliases.lookup (value);
		if (slot != null) {
			set_fact (slot, true);
		}
	}

	public NonNullFacts copy() {
		var result = new NonNullFacts ();
		result.reachable = reachable;
		foreach (var key in facts.get_keys ()) {
			result.facts.insert (key, true);
		}
		foreach (var key in aliases.get_keys ()) {
			result.aliases.insert (key, aliases.lookup (key));
		}
		foreach (var key in predicates.get_keys ()) {
			result.predicates.insert (key, predicates.lookup (key).copy ());
		}
		return result;
	}

	public static NonNullFacts join(NonNullFacts left, NonNullFacts right) {
		if (!left.reachable) {
			return right.copy ();
		}
		if (!right.reachable) {
			return left.copy ();
		}
		var result = new NonNullFacts ();
		foreach (var key in left.facts.get_keys ()) {
			if (right.facts.contains (key)) {
				result.facts.insert (key, true);
			}
		}
		foreach (var key in left.aliases.get_keys ()) {
			if (right.aliases.lookup (key) == left.aliases.lookup (key)) {
				result.aliases.insert (key, left.aliases.lookup (key));
			}
		}
		var keys = new HashTable<Object, bool> (direct_hash, direct_equal);
		foreach (var key in left.predicates.get_keys ()) {
			keys.insert (key, true);
		}
		foreach (var key in right.predicates.get_keys ()) {
			keys.insert (key, true);
		}
		foreach (var key in keys.get_keys ()) {
			var a = left.predicates.lookup (key);
			var b = right.predicates.lookup (key);
			result.predicates.insert (key, new NonNullPredicate (NonNullOutcome.meet (a == null ? left.outcome () : a.yes, b == null ? right.outcome () : b.yes), NonNullOutcome.meet (a == null ? left.outcome () : a.no, b == null ? right.outcome () : b.no)));
		}
		return result;
	}

	public bool same(NonNullFacts other) {
		if (reachable != other.reachable || facts.size () != other.facts.size () || aliases.size () != other.aliases.size () || predicates.size () != other.predicates.size ()) {
			return false;
		}
		foreach (var key in facts.get_keys ()) {
			if (!other.facts.contains (key)) {
				return false;
			}
		}
		foreach (var key in aliases.get_keys ()) {
			if (aliases.lookup (key) != other.aliases.lookup (key)) {
				return false;
			}
		}
		foreach (var key in predicates.get_keys ()) {
			var a = predicates.lookup (key);
			var b = other.predicates.lookup (key);
			if (b == null || !a.yes.same (b.yes) || !a.no.same (b.no)) {
				return false;
			}
		}
		return true;
	}

}
}
