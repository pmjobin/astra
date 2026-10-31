// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Semantic {
// Compiler-owned exact syntax metadata, with no runtime value or storage identity.
public class VectorLaneIndex : Object {
	public int ordinal { get; private set; }
	public SourceSpan span { get; private set; }

	internal VectorLaneIndex (SourceSpan span, int ordinal) {
		this.span = span;
		this.ordinal = ordinal;
	}

	public VectorLaneIndex copy() {
		return new VectorLaneIndex (span, ordinal);
	}
	public bool in_range(VectorType type) {
		return ordinal >= 0 && ordinal < type.lane_count;
	}
}

// Each stage owns a snapshot. Neither the array nor mutable list access escapes.
public class VectorLaneSelectors : Object {
	private VectorLaneIndex[] indices;
	public int length { get { return indices.length; } }

	internal VectorLaneSelectors (GenericArray<VectorLaneIndex> indices) {
		this.indices = new VectorLaneIndex[indices.length];
		for (int i = 0; i < indices.length; i++) {
			this.indices[i] = indices[i].copy ();
		}
	}

	public VectorLaneIndex at(int position) {
		return indices[position];
	}
	public VectorLaneSelectors copy() {
		var snapshot = new GenericArray<VectorLaneIndex> ();
		foreach (var index in indices) {
			snapshot.add (index);
		}
		return new VectorLaneSelectors (snapshot);
	}

	public string spelling() {
		var text = new StringBuilder ();
		for (int i = 0; i < indices.length; i++) {
			if (i > 0) {
				text.append (" ");
			}
			text.append_printf ("%d", indices[i].ordinal);
		}
		return text.str;
	}
}
}
