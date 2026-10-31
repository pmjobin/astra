// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
// A phase populates this graph from its own declarations. Scoped call
// protection follows the same possible owner/child aliases as loan checking.
internal class ReadonlyCallContext : Object {
	private HashTable<SemanticType, GenericArray<SemanticType>> declarations = new HashTable<SemanticType, GenericArray<SemanticType>> (direct_hash, direct_equal);
	private GenericArray<SemanticType> active = new GenericArray<SemanticType> ();
	internal void add_type(SemanticType type) {
		if (!declarations.contains (type)) {
			declarations.insert (type, new GenericArray<SemanticType> ());
		}
	}
	internal void add_field(SemanticType owner, SemanticType field) {
		add_type (owner);
		if (field is OwnerSlotsType) {
			field = ((OwnerSlotsType) field).element;
		}
		if (field is ClassType || field is StructType) {
			declarations.lookup (owner).add (field);
		}
	}
	private GenericArray<SemanticType>? children(SemanticType type) {
		var result = new GenericArray<SemanticType> ();
		foreach (var declared in declarations.get_keys ()) {
			bool relevant = declared == type;
			var candidate = declared as ClassType;
			var owner = type as ClassType;
			if (candidate != null && owner != null) {
				relevant |= candidate.derives_from (owner) || owner.derives_from (candidate);
			}
			if (relevant) {
				foreach (var field in declarations.lookup (declared)) {
					result.add (field);
				}
			}
		}
		return result;
	}
	internal void enter(SemanticType type) {
		active.add (type);
	}
	internal void leave() {
		active.remove_index (active.length - 1);
	}
	internal bool overlaps(SemanticType type) {
		if (type is ReceiverType) {
			type = ((ReceiverType) type).instance_type;
		}
		foreach (var backing in active) {
			if (OwnedChildComposition.may_invalidate (type, backing, children)) {
				return true;
			}
		}
		return false;
	}
}

// The stage supplies its own exact declaration graph, without owner backlinks.
public class OwnedChildComposition : Object {
	public static bool acyclic(SemanticType type, CopyabilityFields edges) {
		return visit (type, edges, new HashTable<SemanticType, int> (direct_hash, direct_equal));
	}
	private static bool visit(SemanticType type, CopyabilityFields edges, HashTable<SemanticType, int> states) {
		if (states.contains (type)) {
			return states.lookup (type) == 2;
		}
		states.insert (type, 1);
		var children = edges (type);
		if (children == null) {
			return false;
		}
		foreach (var child in children) {
			if (!visit (child, edges, states)) {
				return false;
			}
		}
		states.insert (type, 2);
		return true;
	}
	// Possible dynamic subtypes and inherited slots belong in this callback.
	// A borrowed ancestor container can replace/destroy the exact backing slot.
	public static bool may_invalidate(SemanticType candidate, SemanticType backing, CopyabilityFields children) {
		return overlaps (candidate, backing, children, new HashTable<SemanticType, bool> (direct_hash, direct_equal));
	}
	private static bool overlaps(SemanticType candidate, SemanticType backing, CopyabilityFields children, HashTable<SemanticType, bool> seen) {
		if (candidate == backing) {
			return true;
		}
		var from = candidate as ClassType;
		var to = backing as ClassType;
		if (from != null && to != null && (from.derives_from (to) || to.derives_from (from))) {
			return true;
		}
		if (seen.contains (candidate)) {
			return false;
		}
		seen.insert (candidate, true);
		var fields = children (candidate);
		if (fields != null) {
			foreach (var field in fields) {
				if (overlaps (field, backing, children, seen)) {
					return true;
				}
			}
		}
		return false;
	}
}
}
