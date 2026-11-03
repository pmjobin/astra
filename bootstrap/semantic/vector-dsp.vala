// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
// Bounded semantic identities shared by checking and LLVM-free verifiers.
// Numerical authority remains AstraIntegerValue, never a target intrinsic.
public enum DspPrimitiveKind {
	SAT_ADD,
	SAT_SUB,
	WIDEN_LOW,
	WIDEN_HIGH,
	PACK_WRAP,
	PACK_SAT,
	INTERLEAVE_LOW,
	INTERLEAVE_HIGH;

	public bool is_saturation() {
		return this == SAT_ADD || this == SAT_SUB;
	}

	public bool is_widen() {
		return this == WIDEN_LOW || this == WIDEN_HIGH;
	}

	public bool is_pack() {
		return this == PACK_WRAP || this == PACK_SAT;
	}

	public string spelling() {
		switch (this) {
		case SAT_ADD:
			return "sat-add";
		case SAT_SUB:
			return "sat-sub";
		case WIDEN_LOW:
			return "vector-widen-low";
		case WIDEN_HIGH:
			return "vector-widen-high";
		case PACK_WRAP:
			return "vector-pack-wrap";
		case PACK_SAT:
			return "vector-pack-sat";
		case INTERLEAVE_LOW:
			return "vector-interleave-low";
		case INTERLEAVE_HIGH:
			return "vector-interleave-high";
		default:
			return "invalid-dsp";
		}
	}

	public string? type_error(SemanticType first, SemanticType? second, SemanticType result, IntegerType? destination = null) {
		if (!is_saturation () && !is_widen () && !is_pack () && this != INTERLEAVE_LOW && this != INTERLEAVE_HIGH) {
			return "invalid DSP primitive kind";
		}
		var source = first as VectorType;
		var output = result as VectorType;
		if (source != null && !VectorType.supports (source.element_type, source.lane_count)) {
			return "DSP source requires a supported VectorType";
		}
		if (output != null && !VectorType.supports (output.element_type, output.lane_count)) {
			return "DSP result requires a supported VectorType";
		}
		if (is_widen () ? second != null : second != first) {
			return "DSP operands must have exact matching types and primitive arity";
		}
		if (is_saturation ()) {
			if (IntegerConversion.element_type (first) == null || result != first || destination != null) {
				return "saturation requires exact same integer scalar/vector operands and result";
			}
			return null;
		}
		if (is_widen () || is_pack ()) {
			if (source == null || !(source.element_type is IntegerType)) {
				return "widen/pack source must be an integer VectorType";
			}
			if (destination == null || output == null || output.element_type != destination) {
				return "widen/pack result requires its exact destination IntegerType element";
			}
			var element = (IntegerType) source.element_type;
			if (is_widen ()) {
				if (source.lane_count < 4 || output.lane_count != source.lane_count / 2) {
					return "widen requires at least four source lanes and half as many result lanes";
				}
				if (destination.bit_width <= element.bit_width) {
					return "widen destination element must be strictly wider than the source";
				}
			} else {
				if (output.lane_count != source.lane_count * 2) {
					return "pack requires twice as many result lanes";
				}
				if (destination.bit_width >= element.bit_width) {
					return "pack destination element must be strictly narrower than the source";
				}
			}
			return null;
		}
		if (source == null || source.lane_count % 2 != 0 || result != first || destination != null) {
			return "interleave requires exact same VectorType operands and result with even lane count";
		}
		return null;
	}

}

}
