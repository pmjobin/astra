// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Text {
// The predecessor's independently established owner relation, translated to
// stage-owned identities. It never retains predecessor compiler nodes.
public class TextLoanIntent : Object {
	private GenericArray<Object> owners = new GenericArray<Object> ();
	public uint count { get { return owners.length; } }
	public Object owner(uint ordinal) {
		return owners[ordinal];
	}

	public TextLoanIntent (GenericArray<Object> owners) {
		foreach (var owner in owners) {
			this.owners.add (owner);
		}
	}

	public bool matches(GenericArray<Object> actual) {
		if (owners.length != actual.length) {
			return false;
		}
		foreach (var owner in owners) {
			if (!actual.find (owner)) {
				return false;
			}
		}
		return true;
	}

}
// Immutable lexical authority with no backlink to a compiler model.
public class TextLoanExtent : Object {
	public TextLoanExtent? parent { get; private set; }
	public int ordinal { get; private set; }
	public TextLoanExtent (TextLoanExtent? parent, int ordinal) {
		this.parent = parent;
		this.ordinal = ordinal;
	}

	public bool outlives(TextLoanExtent destination) {
		for (TextLoanExtent? current = destination; current != null; current = current.parent) {
			if (current == this) {
				return true;
			}
		}
		return false;
	}

}
private class TextOriginNode : Object {
	internal bool static_leaf;
	internal bool borrowed_leaf;
	internal bool receiver_leaf;
	internal Object? receiver_owner;
	internal GenericArray<Object> inputs = new GenericArray<Object> ();
}
// Temporary verifier authority, never retained by an IR program. Equations
// describe per-write versions and conservative control-flow joins. Cycles require grounding
// in static bytes; a single incoming borrow invalidates a static result.
public class TextOrigins : Object {
	private HashTable<Object, TextOriginNode> nodes = new HashTable<Object, TextOriginNode> (direct_hash, direct_equal);
	public void literal(Object value) {
		var node = new TextOriginNode ();
		node.static_leaf = true;
		nodes.insert (value, node);
	}

	public void borrowed(Object value) {
		var node = new TextOriginNode ();
		node.borrowed_leaf = true;
		nodes.insert (value, node);
	}

	public void receiver_borrow(Object value, Object? owner = null) {
		var node = new TextOriginNode ();
		node.borrowed_leaf = true;
		node.receiver_leaf = true;
		node.receiver_owner = owner;
		nodes.insert (value, node);
	}

	// A join retains all backing requirements. An unassociated receiver leaf
	// remains an unknown identity and can never justify a stored local loan.
	public GenericArray<Object> receiver_owners(Object root) {
		var result = new GenericArray<Object> ();
		var seen = new HashTable<Object, bool> (direct_hash, direct_equal);
		var pending = new GenericArray<Object> ();
		pending.add (root);
		for (int i = 0; i < pending.length; i++) {
			var value = pending[i];
			if (seen.contains (value)) {
				continue;
			}
			seen.insert (value, true);
			var node = nodes.lookup (value);
			if (node == null) {
				continue;
			}
			if (node.receiver_leaf) {
				var owner = node.receiver_owner ?? node;
				if (!result.find (owner)) {
					result.add (owner);
				}
			}
			foreach (var input in node.inputs) {
				pending.add (input);
			}
		}
		return result;
	}

	public bool has_receiver_borrow(Object root) {
		var seen = new HashTable<Object, bool> (direct_hash, direct_equal);
		var pending = new GenericArray<Object> ();
		pending.add (root);
		for (int i = 0; i < pending.length; i++) {
			var value = pending[i];
			if (seen.contains (value)) {
				continue;
			}
			seen.insert (value, true);
			var node = nodes.lookup (value);
			if (node == null) {
				continue;
			}
			if (node.receiver_leaf) {
				return true;
			}
			foreach (var input in node.inputs) {
				pending.add (input);
			}
		}
		return false;
	}

	public void copy(Object value, Object input) {
		var node = nodes.lookup (value);
		if (node == null) {
			node = new TextOriginNode ();
			nodes.insert (value, node);
		}
		node.inputs.add (input);
	}

	public bool is_static(Object root) {
		return prove (root, false);
	}

	public bool is_bounded(Object root) {
		return prove (root, true);
	}

	private bool prove(Object root, bool allow_borrowed) {
		var visited = new HashTable<Object, bool> (direct_hash, direct_equal);
		var pending = new GenericArray<Object> ();
		pending.add (root);
		var grounded = new HashTable<Object, bool> (direct_hash, direct_equal);
		var reverse = new HashTable<Object, GenericArray<Object>> (direct_hash, direct_equal);
		var ready = new GenericArray<Object> ();
		for (int i = 0; i < pending.length; i++) {
			var value = pending[i];
			if (visited.contains (value)) {
				continue;
			}
			visited.insert (value, true);
			var node = nodes.lookup (value);
			if (node == null) {
				return false;
			}
			if (node.static_leaf || (allow_borrowed && node.borrowed_leaf)) {
				grounded.insert (value, true);
				ready.add (value);
				continue;
			}
			if (node.inputs.length == 0) {
				return false;
			}
			foreach (var input in node.inputs) {
				pending.add (input);
				var users = reverse.lookup (input);
				if (users == null) {
					users = new GenericArray<Object> ();
					reverse.insert (input, users);
				}
				users.add (value);
			}
		}
		// Every terminal cycle must have static grounding, including when a
		// separate input of the root is already known static.
		for (int i = 0; i < ready.length; i++) {
			var users = reverse.lookup (ready[i]);
			if (users != null) {
				foreach (var user in users) {
					if (!grounded.contains (user)) {
						grounded.insert (user, true);
						ready.add (user);
					}
				}
			}
		}
		return grounded.size () == visited.size ();
	}

}

public class TextOriginState : Object {
	public bool reachable = true;
	public HashTable<Object, Object> bindings = new HashTable<Object, Object> (direct_hash, direct_equal);
	public TextOriginState snapshot() {
		var result = new TextOriginState ();
		result.reachable = reachable;
		foreach (var key in bindings.get_keys ()) {
			result.bindings.insert (key, bindings.lookup (key));
		}
		return result;
	}

}
public class TextOriginException : Object {
	public TextOriginState state;
	public Object effect;
	public TextOriginException (TextOriginState state, Object effect) {
		this.state = state;
		this.effect = effect;
	}

}
public class TextOriginLoop : Object {
	public TextOriginState header;
	public GenericArray<TextOriginState> continues = new GenericArray<TextOriginState> ();
	public GenericArray<TextOriginState> exits = new GenericArray<TextOriginState> ();
	public TextOriginLoop (TextOriginState header) {
		this.header = header;
	}

}
// Per-write versions preserve descriptor copying: a read captures the current
// origin, never the mutable binding. Structured loops form finite equations
// over header versions, backedges and explicit break/continue edges.
public class TextOriginFlow : Object {
	public TextOrigins origins = new TextOrigins ();
	public TextOriginState state = new TextOriginState ();
	private GenericArray<TextOriginLoop> loops = new GenericArray<TextOriginLoop> ();
	private GenericArray<GenericArray<TextOriginException>> protected_states = new GenericArray<GenericArray<TextOriginException>> ();
	public void begin_try() {
		protected_states.add (new GenericArray<TextOriginException> ());
	}

	public GenericArray<TextOriginException> end_try() {
		var result = protected_states[protected_states.length - 1];
		protected_states.remove_index (protected_states.length - 1);
		return result;
	}

	public void exception(Object effect, TextOriginState? incoming = null) {
		var snapshot = incoming ?? state;
		if (snapshot.reachable && protected_states.length != 0) {
			protected_states[protected_states.length - 1].add (new TextOriginException (snapshot.snapshot (), effect));
		}
	}

	public TextOriginState project(TextOriginState scope, TextOriginState incoming) {
		var result = scope.snapshot ();
		result.reachable = incoming.reachable;
		foreach (var key in scope.bindings.get_keys ()) {
			result.bindings.insert (key, incoming.bindings.lookup (key) ?? scope.bindings.lookup (key));
		}
		return result;
	}

	public void read(Object binding, Object value) {
		origins.copy (value, state.bindings.lookup (binding) ?? new Object ());
	}

	public void write(Object binding, Object value) {
		state.bindings.insert (binding, value);
	}

	public void merge(TextOriginState scope, owned TextOriginState left, owned TextOriginState right) {
		if (!left.reachable) {
			state = right.snapshot ();
			return;
		}
		if (!right.reachable) {
			state = left.snapshot ();
			return;
		}
		state = new TextOriginState ();
		foreach (var key in scope.bindings.get_keys ()) {
			var prior = scope.bindings.lookup (key);
			var a = left.bindings.lookup (key) ?? prior;
			var b = right.bindings.lookup (key) ?? prior;
			if (a == b) {
				state.bindings.insert (key, a);
			} else {
				var join = new Object ();
				origins.copy (join, a);
				origins.copy (join, b);
				state.bindings.insert (key, join);
			}
		}
	}

	public void begin_loop() {
		var header = new TextOriginState ();
		header.reachable = state.reachable;
		foreach (var key in state.bindings.get_keys ()) {
			var phi = new Object ();
			origins.copy (phi, state.bindings.lookup (key));
			header.bindings.insert (key, phi);
		}
		loops.add (new TextOriginLoop (header));
		state = header.snapshot ();
	}

	private void backedge(TextOriginLoop loop) {
		if (state.reachable) {
			foreach (var key in loop.header.bindings.get_keys ()) {
				var phi = loop.header.bindings.lookup (key);
				origins.copy (phi, state.bindings.lookup (key) ?? phi);
			}
		}
	}

	public void jump(bool is_break) {
		if (loops.length != 0 && state.reachable) {
			var loop = loops[loops.length - 1];
			if (is_break) {
				loop.exits.add (state.snapshot ());
			} else {
				loop.continues.add (state.snapshot ());
			}
		}
		state.reachable = false;
	}

	public void begin_step() {
		var loop = loops[loops.length - 1];
		foreach (var continued in loop.continues) {
			merge (loop.header, state, continued);
		}
		loop.continues = new GenericArray<TextOriginState> ();
	}

	public void end_loop() {
		begin_step ();
		var loop = loops[loops.length - 1];
		backedge (loop);
		loops.remove_index (loops.length - 1);
		state = loop.header.snapshot ();
		foreach (var exit in loop.exits) {
			merge (loop.header, state, exit);
		}
	}

}
}
