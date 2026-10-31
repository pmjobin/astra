// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
// Compiler-only control-flow lattice, shared by semantic checking and Core
// validation. Ordinals index exact declaring-class fields; no runtime state.
public class FieldInitializationState : Object {
	private bool[] definite;
	private bool[] possible;
	private HashTable<string, bool> definite_parts = new HashTable<string, bool> (str_hash, str_equal);
	private HashTable<string, bool> possible_parts = new HashTable<string, bool> (str_hash, str_equal);
	public bool reachable { get; set; default = true; }
	public int field_count { get { return definite.length; } }
	public FieldInitializationState (int count) {
		definite = new bool[count];
		possible = new bool[count];
	}
	public bool is_definite(int field) {
		return !reachable || definite[field];
	}
	public bool is_possible(int field) {
		return reachable && possible[field];
	}
	public void initialize(int field) {
		if (reachable) {
			definite[field] = true;
			possible[field] = true;
		}
	}
	public bool is_part_possible(int field, string part) {
		return reachable && (possible[field] || possible_parts.contains ("%d/%s".printf (field, part)));
	}

	// Lowered aggregate initialization commits one canonical declaration leaf
	// at a time. The root becomes available only after every leaf is definite.
	// Paths are copied values, reconstructed against each stage's own graph.
	public bool initialize_record_part(int field, string part, string[] leaves) {
		bool found = false;
		foreach (string leaf in leaves) {
			if (leaf == part) {
				found = true;
			}
		}
		if (!found || field < 0 || field >= field_count) {
			return false;
		}
		if (!reachable) {
			return true;
		}
		string key = "%d/%s".printf (field, part);
		definite_parts.insert (key, true);
		possible_parts.insert (key, true);
		foreach (string leaf in leaves) {
			if (!definite_parts.contains ("%d/%s".printf (field, leaf))) {
				return true;
			}
		}
		initialize (field);
		return true;
	}
	public bool same_as(FieldInitializationState other) {
		if (reachable != other.reachable || field_count != other.field_count) {
			return false;
		}
		for (int f = 0; f < field_count; f++) {
			if (definite[f] != other.definite[f] || possible[f] != other.possible[f]) {
				return false;
			}
		}
		if (definite_parts.size () != other.definite_parts.size () || possible_parts.size () != other.possible_parts.size ()) {
			return false;
		}
		foreach (var key in definite_parts.get_keys ()) {
			if (!other.definite_parts.contains (key)) {
				return false;
			}
		}
		foreach (var key in possible_parts.get_keys ()) {
			if (!other.possible_parts.contains (key)) {
				return false;
			}
		}
		return true;
	}
	public FieldInitializationState copy() {
		var result = new FieldInitializationState (field_count);
		result.reachable = reachable;
		for (int f = 0; f < field_count; f++) {
			result.definite[f] = definite[f];
			result.possible[f] = possible[f];
		}
		foreach (var key in definite_parts.get_keys ()) {
			result.definite_parts.insert (key, true);
		}
		foreach (var key in possible_parts.get_keys ()) {
			result.possible_parts.insert (key, true);
		}
		return result;
	}
	public static FieldInitializationState join(FieldInitializationState left, FieldInitializationState right) {
		if (!left.reachable) {
			return right.copy ();
		}
		if (!right.reachable) {
			return left.copy ();
		}
		var result = new FieldInitializationState (left.field_count);
		for (int f = 0; f < left.field_count; f++) {
			result.definite[f] = left.definite[f] && right.definite[f];
			result.possible[f] = left.possible[f] || right.possible[f];
		}
		foreach (var key in left.definite_parts.get_keys ()) {
			if (right.definite_parts.contains (key)) {
				result.definite_parts.insert (key, true);
			}
		}
		foreach (var key in left.possible_parts.get_keys ()) {
			result.possible_parts.insert (key, true);
		}
		foreach (var key in right.possible_parts.get_keys ()) {
			result.possible_parts.insert (key, true);
		}
		return result;
	}
}
}
