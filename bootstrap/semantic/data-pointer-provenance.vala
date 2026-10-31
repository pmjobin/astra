// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
public enum DataPointerOrigin {
	NULL, LOCAL, PARAMETER, OBJECT_STORAGE, BUFFER_FIELD, RECEIVER_RECORD
}

// Immutable record of the checked lexical proof. Ordinals are scoped to the
// containing function, never pointee or storage identity. No checked backlink.
public class DataPointerProvenance : Object {
	public DataPointerOrigin origin { get; private set; }
	public int origin_ordinal { get; private set; }
	public int region_ordinal { get; private set; }
	// Text-slice access additionally borrows every payload, not just the table.
	public bool deep_text { get; private set; }

	public DataPointerProvenance (DataPointerOrigin origin, int origin_ordinal, int region_ordinal, bool deep_text = false) {
		this.deep_text = deep_text;
		this.origin = origin;
		this.origin_ordinal = origin_ordinal;
		this.region_ordinal = region_ordinal;
	}

	public bool is_valid() {
		if (origin == DataPointerOrigin.NULL) {
			return origin_ordinal == -1 && region_ordinal == -1;
		}
		return origin_ordinal >= 0 && ((origin == DataPointerOrigin.LOCAL || origin == DataPointerOrigin.OBJECT_STORAGE || origin == DataPointerOrigin.BUFFER_FIELD || origin == DataPointerOrigin.RECEIVER_RECORD) ? region_ordinal >= 0 : origin == DataPointerOrigin.PARAMETER && region_ordinal == 0);
	}
}
}
