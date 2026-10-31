// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
namespace Astra.Semantic {
// A bounded scalar view supplies provenance, extent and element identity.
// Alignment is a checked operation precondition, never a caller assertion.
public class VectorMemoryContract : Object {
	public VectorType vector_type { get; private set; }
	public uint alignment { get; internal set; }
	public bool store { get; private set; }
	private uint original_alignment;
	public VectorMemoryContract (VectorType vector_type, uint alignment, bool store = false) {
		this.store = store;
		this.vector_type = vector_type;
		this.alignment = alignment;
		original_alignment = alignment;
	}
	public VectorMemoryContract copy() {
		var result = new VectorMemoryContract (vector_type, original_alignment, store);
		result.alignment = alignment;
		return result;
	}
	public bool valid() {
		return alignment == original_alignment && alignment > 0 && alignment <= 16 && (alignment & (alignment - 1)) == 0 && !vector_type.is_mask && VectorType.supports (vector_type.element_type, vector_type.lane_count);
	}
	public string? type_error(SemanticType view, SemanticType offset, SemanticType? stored, SemanticType result) {
		var slice = view as SliceType;
		var integer = offset as IntegerType;
		if (!valid () || store != (stored != null) || slice == null || slice.element_type != vector_type.element_type || integer == null || integer.bit_width != 32 || !integer.is_signed || result != vector_type || (stored != null && stored != vector_type)) {
			return "vector memory requires an exact numeric scalar view, int offset, vector shape and checked power-of-two alignment (1..16)";
		}
		return null;
	}
}
}
