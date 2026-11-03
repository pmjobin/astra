// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Ssa {
public class SsaArrayInitialize : SsaInstruction {
	public SsaAddressableLocal storage { get; private set; }
	public GenericArray<SsaValue> elements { get; private set; }
	public SsaArrayElementPlace? record_root { get; private set; }
	public GenericArray<SsaMemoryPlace> record_fields { get; private set; default = new GenericArray<SsaMemoryPlace> (); }
	public int record_ordinal {
		get {
			var value = record_root == null ? null : record_root.index as SsaIntegerConstant;
			return record_root == null ? -1 : value == null || !value.value.fits_nonnegative (int.MAX) ? -2 : (int) value.value.bits;
		}
	}
	public bool completes_array { get { return record_root == null || (storage.semantic_type is ArrayType && record_ordinal == ((ArrayType) storage.semantic_type).length - 1); } }
	internal SsaArrayInitialize.record (SourceSpan span, SsaArrayElementPlace root, GenericArray<SsaMemoryPlace> fields, GenericArray<SsaValue> values) {
		this(span, root.storage, values);
		this.record_root = root;
		this.record_fields = fields;
	}

	internal SsaArrayInitialize (SourceSpan span, SsaAddressableLocal storage, GenericArray<SsaValue> elements) {
		base (span, null, -1);
		this.storage = storage;
		this.elements = elements;
	}

}

public class SsaArrayElementPlace : SsaMemoryPlace {
	public SsaAddressableLocal storage { get; private set; }
	public ArrayType array_type { get; private set; }
	public SsaValue index { get; private set; }
	public DataPointerProvenance provenance { get; private set; }
	public bool traps_on_invalid { get { return true; } }

	internal SsaArrayElementPlace (SourceSpan span, SsaAddressableLocal storage, ArrayType array_type, SsaValue index, DataPointerProvenance provenance) {
		base (span, array_type.element_type);
		this.storage = storage;
		this.array_type = array_type;
		this.index = index;
		this.provenance = provenance;
	}

}

public class SsaArrayBoundsCheck : SsaInstruction {
	public SsaAddressableLocal storage { get; private set; }
	public SsaValue index { get; private set; }

	internal SsaArrayBoundsCheck (SourceSpan span, SsaAddressableLocal storage, SsaValue index, int ordinal) {
		base (span, index.semantic_type, ordinal);
		this.storage = storage;
		this.index = index;
	}

}
}
