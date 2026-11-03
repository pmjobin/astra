// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Semantic {
internal enum GenericOwnershipEventKind {
	SEQUENCE, MOVE, READ, RELEASE, ACQUIRE, CHOICE, LOOP, RETURN, BREAK, CONTINUE, TRY, EFFECT, THROW, LOCAL_TRANSFER, LOCAL_ACQUIRE, RETIRE
}

// A temporary structured proof, rebuilt independently from Checked and Core.
// It contains no CFG, destructor, ABI, storage plan or runtime state.
internal class GenericOwnershipEvent : Object {
	internal GenericOwnershipEventKind kind;
	internal SourceSpan span;
	internal int owner = -1;
	internal string name = "";
	internal int truth = -1;
	internal int parameter = -1;
	internal bool returned;
	internal Object? target;
	internal ClassType? effect;
	internal GenericArray<ClassType> bounds = new GenericArray<ClassType> ();
	internal GenericArray<GenericOwnershipEvent> children = new GenericArray<GenericOwnershipEvent> ();
	internal GenericOwnershipEvent (GenericOwnershipEventKind kind, SourceSpan span) {
		this.kind = kind;
		this.span = span;
	}

}

// One structural outgoing ownership edge, or a retaining terminal.
// Stage-owned targets never survive specialization or become runtime data.
internal class GenericOwnerTransferScope : Object {
	internal bool valid = true;
	internal bool returned;
	internal Object? local;
	internal Object? target;
	internal int parameter = -1;
}

// Reachable ownership edges derived by this stage's liveness proof. Unlike
// the legacy single-site eligibility summary, this inventory retains every
// branch, loop and local transfer without imposing a body shape.
internal class GenericOwnerTransferEdge : Object {
	internal Object? target { get; private set; }
	internal int parameter { get; private set; }
	internal bool returned { get; private set; }
	internal bool local { get; private set; }
	internal SourceSpan span { get; private set; }
	internal GenericOwnerTransferEdge (GenericOwnershipEvent event) {
		target = event.target;
		parameter = event.parameter;
		returned = event.returned;
		local = event.kind == GenericOwnershipEventKind.LOCAL_TRANSFER;
		span = event.span;
	}

}

// Allocation requirements flow backwards along reachable ownership edges.
// Nodes are exact stage-owned formal/local identities; Source and Core each
// construct their own graph after their independent liveness verification.
internal class GenericStorageRequirements : Object {
	internal const uint CALLER = 1;
	internal const uint HEAP = 2;
	internal const uint EITHER = CALLER | HEAP;
	private HashTable<Object, uint> domains = new HashTable<Object, uint> (direct_hash, direct_equal);
	private HashTable<Object, Object> caller_blockers = new HashTable<Object, Object> (direct_hash, direct_equal);
	private HashTable<Object, Object> heap_blockers = new HashTable<Object, Object> (direct_hash, direct_equal);
	private HashTable<Object, GenericArray<Object>> edges = new HashTable<Object, GenericArray<Object>> (direct_hash, direct_equal);
	internal uint allowed(Object owner) {
		return domains.contains (owner) ? domains.lookup (owner) : EITHER;
	}

	internal Object? reason(Object owner, bool heap) {
		return (heap ? heap_blockers : caller_blockers).lookup (owner);
	}

	internal void constrain(Object owner, uint permitted, Object? boundary = null) {
		uint removed = allowed (owner) & ~permitted;
		if ((removed & CALLER) != 0) {
			caller_blockers.insert (owner, boundary ?? owner);
		}
		if ((removed & HEAP) != 0) {
			heap_blockers.insert (owner, boundary ?? owner);
		}
		domains.insert (owner, allowed (owner) & permitted);
	}

	internal void link(Object source, Object destination) {
		var outgoing = edges.lookup (source);
		if (outgoing == null) {
			outgoing = new GenericArray<Object> ();
			edges.insert (source, outgoing);
		}
		if (!outgoing.find (destination)) {
			outgoing.add (destination);
		}
	}

	internal void solve() {
		bool changed = false;
		do {
			changed = false;
			foreach (var source in edges.get_keys ()) {
				uint before = allowed (source);
				foreach (var destination in edges.lookup (source)) {
					if ((allowed (destination) & CALLER) == 0) {
						constrain (source, HEAP, reason (destination, false));
					}
					if ((allowed (destination) & HEAP) == 0) {
						constrain (source, CALLER, reason (destination, true));
					}
				}
				changed |= before != allowed (source);
			}
		} while (changed);
	}

	internal bool permits(Object owner, bool heap) {
		return (allowed (owner) & (heap ? HEAP : CALLER)) != 0;
	}

}

internal class GenericOwnerFacts : Object {
	internal bool reachable = true;
	internal OwnershipState[] states;
	internal GenericOwnerFacts (int count, bool reachable = true) {
		this.reachable = reachable;
		states = new OwnershipState[count];
		for (int i = 0; i < count; i++) {
			states[i] = OwnershipState.OWNED;
		}
	}

	internal GenericOwnerFacts copy() {
		var result = new GenericOwnerFacts (states.length, reachable);
		result.states = states.copy ();
		return result;
	}

	internal void merge(GenericOwnerFacts other) {
		if (!other.reachable) {
			return;
		}
		if (!reachable) {
			states = other.states.copy ();
			reachable = true;
			return;
		}
		for (int i = 0; i < states.length; i++) {
			states[i] = OwnershipState.join (states[i], other.states[i]);
		}
	}

	internal bool same(GenericOwnerFacts other) {
		if (reachable != other.reachable) {
			return false;
		}
		for (int i = 0; i < states.length; i++) {
			if (states[i] != other.states[i]) {
				return false;
			}
		}
		return true;
	}

}

internal class GenericOwnerExits : Object {
	internal GenericOwnerFacts next;
	internal HashTable<Object, GenericOwnerFacts> breaks = new HashTable<Object, GenericOwnerFacts> (direct_hash, direct_equal);
	internal HashTable<Object, GenericOwnerFacts> continues = new HashTable<Object, GenericOwnerFacts> (direct_hash, direct_equal);
	internal HashTable<Object, GenericOwnerFacts> exceptions = new HashTable<Object, GenericOwnerFacts> (direct_hash, direct_equal);
	internal GenericOwnerExits (GenericOwnerFacts entry) {
		next = entry.copy ();
	}

	internal static void merge_target(HashTable<Object, GenericOwnerFacts> exits, Object target, GenericOwnerFacts facts) {
		var previous = exits.lookup (target);
		if (previous == null) {
			exits.insert (target, facts.copy ());
		} else {
			previous.merge (facts);
		}
	}

	internal void merge_exits(GenericOwnerExits other, Object? consumed = null) {
		var iterator = HashTableIter<Object, GenericOwnerFacts> (other.breaks);
		Object target;
		GenericOwnerFacts facts;
		while (iterator.next (out target, out facts)) {
			if (target != consumed) {
				merge_target (breaks, target, facts);
			}
		}
		iterator = HashTableIter<Object, GenericOwnerFacts> (other.continues);
		while (iterator.next (out target, out facts)) {
			if (target != consumed) {
				merge_target (continues, target, facts);
			}
		}
		iterator = HashTableIter<Object, GenericOwnerFacts> (other.exceptions);
		while (iterator.next (out target, out facts)) {
			merge_target (exceptions, target, facts);
		}
	}

}

internal class GenericOwnershipFlow : Object {
	private string checking_context;
	protected GenericOwnershipEvent root;
	protected GenericOwnershipEvent current;
	protected GenericArray<GenericOwnershipEvent> parents = new GenericArray<GenericOwnershipEvent> ();
	private GenericArray<GenericOwnershipEvent> controls = new GenericArray<GenericOwnershipEvent> ();
	protected HashTable<Object, int> owners = new HashTable<Object, int> (direct_hash, direct_equal);
	private HashTable<GenericOwnershipEvent, bool> reached_transfers = new HashTable<GenericOwnershipEvent, bool> (direct_hash, direct_equal);
	internal Diagnostic? diagnostic { get; private set; }
	internal HashTable<Object, bool> retained_owners { get; private set; default = new HashTable<Object, bool> (direct_hash, direct_equal); }
	internal HashTable<Object, GenericOwnerTransferScope> transfer_scopes { get; private set; default = new HashTable<Object, GenericOwnerTransferScope> (direct_hash, direct_equal); }
	internal GenericOwnershipFlow (SourceSpan span, string checking_context = "generic definition checking") {
		root = new GenericOwnershipEvent (GenericOwnershipEventKind.SEQUENCE, span);
		current = root;
		this.checking_context = checking_context;
	}

	internal void owner_event(GenericOwnershipEventKind kind, Object owner, string name, SourceSpan span) {
		if (!owners.contains (owner)) {
			owners.insert (owner, (int) owners.size ());
		}
		var event = new GenericOwnershipEvent (kind, span);
		event.owner = owners.lookup (owner);
		event.name = name;
		current.children.add (event);
	}

	internal void move(Object owner, string name, SourceSpan span, Object? target = null, int parameter = -1, bool returned = false, bool local = false) {
		if (local && target != null && !owners.contains (target)) {
			owners.insert (target, (int) owners.size ());
		}
		owner_event (local ? GenericOwnershipEventKind.LOCAL_TRANSFER : GenericOwnershipEventKind.MOVE, owner, name, span);
		var event = current.children[current.children.length - 1];
		event.target = target;
		event.parameter = parameter;
		event.returned = returned;
	}

	// Q11B eligibility is a structural scope gate over the existing proof,
	// including unreachable events; it is not another liveness analysis.
	private bool retains_event(GenericOwnershipEvent event, int owner) {
		if (event.owner == owner && event.kind != GenericOwnershipEventKind.READ) {
			return false;
		}
		foreach (var child in event.children) {
			if (!retains_event (child, owner)) {
				return false;
			}
		}
		return true;
	}

	// Q11C's finite scope is structural, including dead branches. Liveness
	// remains evaluate() below; loop forwarding and multiple sites are deferred.
	private bool transfer_event(GenericOwnershipEvent event, int owner, GenericOwnerTransferScope scope, bool loop = false) {
		if (event.owner == owner && event.kind != GenericOwnershipEventKind.READ && event.kind != GenericOwnershipEventKind.RETIRE) {
			if (event.kind == GenericOwnershipEventKind.LOCAL_TRANSFER) {
				if (scope.local != null || scope.target != null || scope.returned || loop || event.target == null || !owners.contains (event.target) || owners.lookup (event.target) == owner) {
					return false;
				}
				scope.local = event.target;
			} else {
				if (event.kind != GenericOwnershipEventKind.MOVE || scope.local != null || scope.target != null || scope.returned || loop) {
					return false;
				}
				if (event.returned) {
					if (event.target != null || event.parameter != -1) {
						return false;
					}
					scope.returned = true;
				} else {
					if (event.target == null || event.parameter < 0) {
						return false;
					}
					scope.target = event.target;
					scope.parameter = event.parameter;
				}
			}
		}
		foreach (var child in event.children) {
			if (!transfer_event (child, owner, scope, loop || event.kind == GenericOwnershipEventKind.LOOP)) {
				return false;
			}
		}
		return true;
	}

	internal void effect(ClassType bound, SourceSpan span, bool terminal = false) {
		var event = new GenericOwnershipEvent (terminal ? GenericOwnershipEventKind.THROW : GenericOwnershipEventKind.EFFECT, span);
		event.effect = bound;
		current.children.add (event);
	}

	internal void begin_try(SourceSpan span, GenericArray<ClassType> bounds) {
		var event = new GenericOwnershipEvent (GenericOwnershipEventKind.TRY, span);
		foreach (var bound in bounds) {
			event.bounds.add (bound);
		}
		for (int i = 0; i <= bounds.length; i++) {
			event.children.add (new GenericOwnershipEvent (GenericOwnershipEventKind.SEQUENCE, span));
		}
		current.children.add (event);
		parents.add (current);
		controls.add (event);
		current = event.children[0];
	}

	internal void jump(GenericOwnershipEventKind kind, SourceSpan span, Object? target = null) {
		var event = new GenericOwnershipEvent (kind, span);
		event.target = target;
		current.children.add (event);
	}

	internal void begin(GenericOwnershipEventKind kind, SourceSpan span, int truth = -1, Object? target = null) {
		var event = new GenericOwnershipEvent (kind, span);
		event.truth = truth;
		event.target = target;
		for (int i = 0; i < (kind == GenericOwnershipEventKind.LOOP ? 3 : 2); i++) {
			event.children.add (new GenericOwnershipEvent (GenericOwnershipEventKind.SEQUENCE, span));
		}
		current.children.add (event);
		parents.add (current);
		controls.add (event);
		current = event.children[0];
	}

	internal void arm(int index, int truth = -1) {
		var event = controls[controls.length - 1];
		if (truth != -1) {
			event.truth = truth;
		}
		current = event.children[index];
	}

	internal void end() {
		current = parents[parents.length - 1];
		parents.remove_index (parents.length - 1);
		controls.remove_index (controls.length - 1);
	}

	private void collect_transfers(GenericOwnershipEvent event, int owner, GenericArray<GenericOwnerTransferEdge> result) {
		if (event.owner == owner && reached_transfers.contains (event)) {
			result.add (new GenericOwnerTransferEdge (event));
		}
		foreach (var child in event.children) {
			collect_transfers (child, owner, result);
		}
	}

	// Query after successful verify(). Arrays are independent snapshots; the
	// descriptors contain only temporary stage-owned identities and positions.
	internal GenericArray<GenericOwnerTransferEdge> transfers_for(Object owner) {
		var result = new GenericArray<GenericOwnerTransferEdge> ();
		if (owners.contains (owner)) {
			collect_transfers (root, owners.lookup (owner), result);
		}
		return result;
	}

	private void initialize_local_destinations(GenericOwnershipEvent event, GenericOwnerFacts entry) {
		if (event.kind == GenericOwnershipEventKind.LOCAL_TRANSFER && event.target != null && owners.contains (event.target)) {
			entry.states[owners.lookup (event.target)] = OwnershipState.MOVED;
		} else if (event.kind == GenericOwnershipEventKind.LOCAL_ACQUIRE) {
			entry.states[event.owner] = OwnershipState.MOVED;
		}
		foreach (var child in event.children) {
			initialize_local_destinations (child, entry);
		}
	}

	internal bool verify(bool requires_return = false) {
		assert (parents.length == 0);
		reached_transfers.remove_all ();
		foreach (var owner in owners.get_keys ()) {
			retained_owners.insert (owner, retains_event (root, owners.lookup (owner)));
			var scope = new GenericOwnerTransferScope ();
			scope.valid = transfer_event (root, owners.lookup (owner), scope);
			transfer_scopes.insert (owner, scope);
		}
		var entry = new GenericOwnerFacts ((int) owners.size ());
		initialize_local_destinations (root, entry);
		foreach (var scope in transfer_scopes.get_values ()) {
			if (scope.local == null) {
				continue;
			}
			var local = transfer_scopes.lookup (scope.local);
			if (local == null || !local.valid || local.returned || local.local != null) {
				scope.valid = false;
			} else {
				scope.target = local.target;
				scope.parameter = local.parameter;
			}
		}
		var result = evaluate (root, entry);
		if (diagnostic == null && requires_return && result.next.reachable) {
			diagnostic = new Diagnostic (root.span, "owned generic result must transfer ownership on every normal return path");
		}
		return diagnostic == null;
	}

	private GenericOwnerExits evaluate(GenericOwnershipEvent event, GenericOwnerFacts entry) {
		var result = new GenericOwnerExits (entry);
		if (!entry.reachable || diagnostic != null) {
			return result;
		}
		switch (event.kind) {
		case GenericOwnershipEventKind.LOCAL_TRANSFER:
			reached_transfers.insert (event, true);
			if (!entry.states[event.owner].definitely_owned () || entry.states[owners.lookup (event.target)].may_own ()) {
				diagnostic = new Diagnostic (event.span, "generic local transfer requires a live incoming owner and an empty fresh destination");
			}
			result.next.states[event.owner] = OwnershipState.MOVED;
			result.next.states[owners.lookup (event.target)] = OwnershipState.OWNED;
			break;
		case GenericOwnershipEventKind.RETIRE: result.next.states[event.owner] = OwnershipState.RELEASED;
			break;
		case GenericOwnershipEventKind.MOVE:
		case GenericOwnershipEventKind.READ:
		case GenericOwnershipEventKind.RELEASE:
			if (event.kind == GenericOwnershipEventKind.MOVE) {
				reached_transfers.insert (event, true);
			}
			if (!entry.states[event.owner].definitely_owned ()) {
				string problem = entry.states[event.owner].may_own () ? "owned value '%s' may have been moved".printf (event.name) : "use of moved owned value '%s'".printf (event.name);
				diagnostic = new Diagnostic (event.span, "%s at %s (%s)".printf (problem, checking_context, entry.states[event.owner].display_name ()));
			}
			if (event.kind != GenericOwnershipEventKind.READ) {
				result.next.states[event.owner] = event.kind == GenericOwnershipEventKind.MOVE ? OwnershipState.MOVED : OwnershipState.RELEASED;
			}
			break;
		case GenericOwnershipEventKind.LOCAL_ACQUIRE:
		case GenericOwnershipEventKind.ACQUIRE: result.next.states[event.owner] = OwnershipState.OWNED;
			break;
		case GenericOwnershipEventKind.RETURN:
			result.next.reachable = false;
			break;
		case GenericOwnershipEventKind.EFFECT:
		case GenericOwnershipEventKind.THROW:
			GenericOwnerExits.merge_target (result.exceptions, event.effect, entry);
			if (event.kind == GenericOwnershipEventKind.THROW) {
				result.next.reachable = false;
			}
			break;
		case GenericOwnershipEventKind.TRY:
			var protected = evaluate (event.children[0], entry);
			result.next = protected.next;
			var incoming = protected.exceptions;
			protected.exceptions = new HashTable<Object, GenericOwnerFacts> (direct_hash, direct_equal);
			result.merge_exits (protected);
			for (int c = 0; c < event.bounds.length; c++) {
				var caught = new GenericOwnerFacts (entry.states.length, false);
				var removed = new GenericArray<Object> ();
				foreach (var target in incoming.get_keys ()) {
					var bound = (ClassType) target;
					if (bound.derives_from (event.bounds[c]) || event.bounds[c].derives_from (bound)) {
						caught.merge (incoming.lookup (target));
						if (bound.derives_from (event.bounds[c])) {
							removed.add (target);
						}
					}
				}
				foreach (var target in removed) {
					incoming.remove (target);
				}
				var handled = evaluate (event.children[c + 1], caught);
				result.next.merge (handled.next);
				result.merge_exits (handled);
			}
			foreach (var target in incoming.get_keys ()) {
				GenericOwnerExits.merge_target (result.exceptions, target, incoming.lookup (target));
			}
			break;
		case GenericOwnershipEventKind.BREAK:
			assert (event.target != null);
			GenericOwnerExits.merge_target (result.breaks, event.target, entry);
			result.next.reachable = false;
			break;
		case GenericOwnershipEventKind.CONTINUE:
			assert (event.target != null);
			GenericOwnerExits.merge_target (result.continues, event.target, entry);
			result.next.reachable = false;
			break;
		case GenericOwnershipEventKind.CHOICE:
			result.next.reachable = false;
			for (int i = 0; i < 2; i++) {
				if (event.truth != -1 && event.truth != 1 - i) {
					continue;
				}
				var arm = evaluate (event.children[i], entry);
				result.next.merge (arm.next);
				result.merge_exits (arm);
			}
			break;
		case GenericOwnershipEventKind.LOOP:
			assert (event.target != null);
			var header = entry.copy ();
			while (diagnostic == null) {
				var condition = evaluate (event.children[0], header);
				var body_entry = condition.next.copy ();
				if (event.truth == 0) {
					body_entry.reachable = false;
				}
				var body = evaluate (event.children[1], body_entry);
				var step_entry = body.next.copy ();
				var continued = body.continues.lookup (event.target);
				if (continued != null) {
					step_entry.merge (continued);
				}
				var step = evaluate (event.children[2], step_entry);
				var back = entry.copy ();
				back.merge (step.next);
				result.next = condition.next.copy ();
				if (event.truth == 1) {
					result.next.reachable = false;
				}
				var broken = body.breaks.lookup (event.target);
				if (broken != null) {
					result.next.merge (broken);
				}
				result.merge_exits (condition, event.target);
				result.merge_exits (body, event.target);
				result.merge_exits (step, event.target);
				if (header.same (back)) {
					break;
				}
				header = back;
			}
			break;
		case GenericOwnershipEventKind.SEQUENCE:
			foreach (var child in event.children) {
				var exits = evaluate (child, result.next);
				result.next = exits.next;
				result.merge_exits (exits);
			}
			break;
		}
		return result;
	}

}
}
