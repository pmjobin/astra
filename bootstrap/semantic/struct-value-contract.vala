// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
public enum StructValueMode {
	COPY_VALUE, MOVE_VALUE, BORROW_VALUE;
	public string spelling() {
		return this == COPY_VALUE ? "COPY_VALUE" : this == MOVE_VALUE ? "MOVE_VALUE" : "BORROW_VALUE";
	}
}

// Stage-independent nominal boundary contract, never a pointer or SSA value.
// Each verifier rechecks CopyabilityAuthority against its own field graph.
public class StructValueContract : Object {
	public SemanticType semantic_type { get; private set; }
	public StructValueMode mode { get; private set; default = StructValueMode.COPY_VALUE; }
	internal StructValueContract (SemanticType semantic_type, StructValueMode mode = StructValueMode.COPY_VALUE) {
		this.semantic_type = semantic_type;
		this.mode = mode;
	}
}

public errordomain StructLeafError {
	INVALID_FIELDS
}

public class StructLeafPath : Object {
	private int[] ordinals;
	public int depth { get { return ordinals.length; } }
	public int field_ordinal(int index) {
		return ordinals[index];
	}
	public SemanticType semantic_type { get; private set; }
	public bool same_path(StructLeafPath other) {
		if (semantic_type != other.semantic_type || depth != other.depth) {
			return false;
		}
		for (int i = 0; i < depth; i++) {
			if (ordinals[i] != other.ordinals[i]) {
				return false;
			}
		}
		return true;
	}
	internal StructLeafPath (int[] ordinals, SemanticType semantic_type) {
		this.ordinals = new int[ordinals.length];
		for (int i = 0; i < ordinals.length; i++) {
			this.ordinals[i] = ordinals[i];
		}
		this.semantic_type = semantic_type;
	}
	public virtual StructLeafPath storage_path() {
		return this;
	}
	public virtual string spelling() {
		var result = new StringBuilder ();
		foreach (int ordinal in ordinals) {
			if (result.len != 0) {
				result.append (".");
			}
			result.append_printf ("%d", ordinal);
		}
		return result.str;
	}
}

// A physical component retains its complete logical buffer field identity.
public class StructBufferLeafPath : StructLeafPath {
	private StructLeafPath original;
	public BufferValueShape buffer_shape { get; private set; }
	public int component { get; private set; }
	internal StructBufferLeafPath (StructLeafPath original, BufferValueShape shape, int component) {
		int[] ordinals = new int[original.depth];
		for (int i = 0; i < original.depth; i++) {
			ordinals[i] = original.field_ordinal (i);
		}
		base (ordinals, component == 0 ? (SemanticType) shape.base_type : shape.length_type);
		this.original = original;
		this.buffer_shape = shape;
		this.component = component;
	}
	public override StructLeafPath storage_path() {
		return original;
	}
	public override string spelling() {
		return original.spelling () + (component == 0 ? "@base" : "@length");
	}
}

public delegate BufferValueShape? StructBufferShapes(SliceType type);

// The one recursive declaration-order walk used by copy and native boundaries.
// Ordinals identify fields within the exact nominal graph; padding is absent.
public class StructLeafOrder : Object {
	public static string[] path_names(SemanticType type, CopyabilityFields fields) throws StructLeafError {
		string[] paths = {};
		foreach (var leaf in enumerate_storage (type, fields)) {
			paths += leaf.spelling ();
		}
		return paths;
	}

	public static GenericArray<StructLeafPath> enumerate(SemanticType type, CopyabilityFields fields) throws StructLeafError {
		if (!type.is_struct_storage () || type.is_parameterized () || CopyabilityAuthority.of (type, fields) != Copyability.COPYABLE) {
			throw new StructLeafError.INVALID_FIELDS ("leaf order requires a concrete copyable struct");
		}
		return enumerate_storage (type, fields);
	}

	// Storage identity is independent of copy/move and cleanup authority.
	// Callers must still prove the operation permitted on each exact leaf.
	public static GenericArray<StructLeafPath> enumerate_storage(SemanticType type, CopyabilityFields fields) throws StructLeafError {
		if (!type.is_struct_storage () || type.is_parameterized ()) {
			throw new StructLeafError.INVALID_FIELDS ("storage paths require a concrete record");
		}
		var result = new GenericArray<StructLeafPath> ();
		walk (type, fields, null, result, new HashTable<SemanticType, bool> (direct_hash, direct_equal), 0);
		if (result.length == 0) {
			throw new StructLeafError.INVALID_FIELDS ("empty struct boundaries are unsupported");
		}
		return result;
	}

	private static void walk(SemanticType type, CopyabilityFields fields, int[]? path, GenericArray<StructLeafPath> result, HashTable<SemanticType, bool> active, int application_depth) throws StructLeafError {
		if (active.contains (type)) {
			throw new StructLeafError.INVALID_FIELDS ("recursive by-value record storage cycle");
		}
		if (type.kind == TypeKind.GENERIC_STRUCT_APPLICATION && ++application_depth > 256) {
			throw new StructLeafError.INVALID_FIELDS ("record type application depth exceeds 256");
		}
		var children = fields (type);
		if (children == null || children.length == 0) {
			throw new StructLeafError.INVALID_FIELDS ("missing or empty exact struct field graph");
		}
		active.insert (type, true);
		for (int i = 0; i < children.length; i++) {
			if (children[i].is_parameterized () || children[i].kind == TypeKind.VOID) {
				throw new StructLeafError.INVALID_FIELDS ("record storage leaf requires an exact concrete nonvoid type");
			}
			int depth = path == null ? 0 : path.length;
			var next = new int[depth + 1];
			for (int d = 0; d < depth; d++) {
				next[d] = path[d];
			}
			next[depth] = i;
			if (children[i].is_struct_storage ()) {
				walk (children[i], fields, next, result, active, application_depth);
			} else {
				result.add (new StructLeafPath (next, children[i]));
			}
		}
		active.remove (type);
	}
}

// Concrete boundary shape may outlive all stage graphs. It groups leaf
// channels, and is not an aggregate semantic type, storage, or value.
public class StructValueShape : Object {
	public StructType semantic_type { get; private set; }
	public GenericArray<StructLeafPath> leaves { get; private set; }
	public StructValueMode mode { get; private set; }
	public bool physical_buffers { get; private set; }
	internal StructValueShape (StructType semantic_type, GenericArray<StructLeafPath> leaves, StructValueMode mode = StructValueMode.COPY_VALUE, bool physical_buffers = false) {
		this.semantic_type = semantic_type;
		this.leaves = leaves;
		this.mode = mode;
		this.physical_buffers = physical_buffers;
	}
	public StructValueShape flatten_buffers(StructBufferShapes shapes) throws StructLeafError {
		if (physical_buffers) {
			return this;
		}
		var result = new GenericArray<StructLeafPath> ();
		bool changed = false;
		foreach (var leaf in leaves) {
			if (!(leaf.semantic_type is SliceType)) {
				result.add (leaf);
				continue;
			}
			var shape = shapes ((SliceType) leaf.semantic_type);
			if ((mode != StructValueMode.MOVE_VALUE && mode != StructValueMode.BORROW_VALUE) || shape == null || shape.slice_type != leaf.semantic_type) {
				throw new StructLeafError.INVALID_FIELDS ("record buffer boundary requires its exact complete owned pair contract");
			}
			result.add (new StructBufferLeafPath (leaf, shape, 0));
			result.add (new StructBufferLeafPath (leaf, shape, 1));
			changed = true;
		}
		return changed ? new StructValueShape (semantic_type, result, mode, true) : this;
	}
	public void verify(CopyabilityFields fields) throws StructLeafError {
		bool copyable = CopyabilityAuthority.of (semantic_type, fields) == Copyability.COPYABLE;
		if (mode == StructValueMode.BORROW_VALUE ? copyable : mode != (copyable ? StructValueMode.COPY_VALUE : StructValueMode.MOVE_VALUE)) {
			throw new StructLeafError.INVALID_FIELDS ("struct transport mode must follow its recursive copyability or an explicit owning-record observation");
		}
		var expected = mode == StructValueMode.COPY_VALUE ? StructLeafOrder.enumerate (semantic_type, fields) : StructLeafOrder.enumerate_storage (semantic_type, fields);
		int physical = 0;
		foreach (var field in expected) {
			if (physical_buffers && field.semantic_type is SliceType) {
				var first = physical < leaves.length ? leaves[physical++] as StructBufferLeafPath : null;
				var second = physical < leaves.length ? leaves[physical++] as StructBufferLeafPath : null;
				if (first == null || second == null || first.component != 0 || second.component != 1 || first.buffer_shape != second.buffer_shape || first.buffer_shape.slice_type != field.semantic_type || !first.buffer_shape.is_valid (fields) || !first.storage_path ().same_path (field) || !second.storage_path ().same_path (field) || first.semantic_type != first.buffer_shape.base_type || second.semantic_type != first.buffer_shape.length_type) {
					throw new StructLeafError.INVALID_FIELDS ("record buffer channels must retain one complete exact ordered PTR/I32 field pair");
				}
			} else {
				if (physical >= leaves.length || leaves[physical] is StructBufferLeafPath || !leaves[physical++].same_path (field)) {
					throw new StructLeafError.INVALID_FIELDS ("struct boundary leaf order or exact type mismatch");
				}
			}
		}
		if (physical != leaves.length) {
			throw new StructLeafError.INVALID_FIELDS ("struct boundary leaf count mismatch");
		}
	}
}

// Source argument/parameter grouping over a contiguous range of concrete leaves.
public class StructBoundaryGroup : Object {
	public int source_ordinal { get; private set; }
	public int first_leaf { get; private set; }
	public StructValueShape shape { get; private set; }
	internal StructBoundaryGroup (int source_ordinal, int first_leaf, StructValueShape shape) {
		this.source_ordinal = source_ordinal;
		this.first_leaf = first_leaf;
		this.shape = shape;
	}
}

public enum StructResultUseKind {
	INITIALIZE, ASSIGN, ARGUMENT, RETURN, ENUM_PAYLOAD, CONTAINER_ELEMENT, OBSERVE
}
}
