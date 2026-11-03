// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.NativeAbi;
using Astra.Semantic;

namespace Astra.Backend.LLVM {
internal class LlvmScalarLowering : Object {
	private LlvmModuleArtifact artifact;
	private LlvmTypeMapper types;
	private CApi.BuilderRef builder;
	private CApi.ValueRef function;
	internal uint floating_policy;

	internal LlvmScalarLowering (LlvmModuleArtifact artifact, LlvmTypeMapper types, CApi.BuilderRef builder, CApi.ValueRef function) {
		this.artifact = artifact;
		this.types = types;
		this.builder = builder;
		this.function = function;
	}

	internal CApi.ValueRef integer(AstraIntegerValue value) {
		return CApi.const_int (types.integer_type (value.integer_type), value.bits, 0);
	}

	internal CApi.ValueRef floating(BinaryFloatValue value) throws LlvmError {
		// Exact integer bits -> constant bitcast. No numeric conversion,
		// decimal parser, or host floating value enters the LLVM boundary.
		return CApi.const_bit_cast (CApi.const_int (types.float_bits_type (value.format), value.exact_bits, 0), types.scalar (value.format == BinaryFloatFormat.BINARY32 ? NativeScalarType.F32 : NativeScalarType.F64));
	}

	internal CApi.ValueRef prefix(PrefixOperator op, SemanticType operand_type, CApi.ValueRef operand, string name) throws LlvmError {
		switch (op) {
		case PrefixOperator.POSITIVE:
			return operand;
		case PrefixOperator.NEGATIVE:
			if (operand_type is FloatingType || (operand_type is VectorType && ((VectorType) operand_type).element_type is FloatingType)) {
				return CApi.build_fneg (builder, operand, name);
			}
			return CApi.build_sub (builder, CApi.const_null (CApi.type_of (operand)), operand, name);
		case PrefixOperator.BIT_NOT:
		case PrefixOperator.NOT:
			return CApi.build_xor (builder, operand, CApi.const_all_ones (CApi.type_of (operand)), name);
		default:
			throw new LlvmError.LOWERING ("internal LLVM lowering error: unsupported prefix operator");
		}
	}

	internal CApi.ValueRef binary(BinaryOperator op, SemanticType operand_type, CApi.ValueRef left, CApi.ValueRef right, string name, LlvmBlockState state) throws LlvmError {
		// The same operator dispatch realizes scalar and vector lane semantics;
		// signedness survives until this final predicate selection.
		var lane_type = (operand_type is VectorType) ? ((VectorType) operand_type).element_type : operand_type;
		if (lane_type is FloatingType) {
			LlvmFloatingDomain? domain = null;
			if ((floating_policy & (FloatingPointPolicy.NO_NAN | FloatingPointPolicy.NO_INFINITY)) != 0) {
				domain = checked_floating_domain (op, operand_type, left, right, name, state);
			}
			var result = floating_binary (op, left, right, name);
			if (floating_policy != 0 && (void*) CApi.is_instruction (result) != null && CApi.can_use_fast_math_flags (result) != 0) {
				CApi.set_fast_math_flags (result, floating_policy);
				artifact.floating_permissions |= floating_policy;
				artifact.floating_instructions.add (new LlvmFloatingPermission (result, floating_policy, domain));
			}
			return result;
		}
		var integer_type = lane_type as IntegerType;
		bool signed = integer_type != null && integer_type.is_signed;
		switch (op) {
		case BinaryOperator.BIT_AND: return CApi.build_and (builder, left, right, name);
		case BinaryOperator.BIT_OR:
			return CApi.build_or (builder, left, right, name);
		case BinaryOperator.BIT_XOR:
			return CApi.build_xor (builder, left, right, name);
		case BinaryOperator.ADD:
			return CApi.build_add (builder, left, right, name);
		case BinaryOperator.SUBTRACT:
			return CApi.build_sub (builder, left, right, name);
		case BinaryOperator.MULTIPLY:
			return CApi.build_mul (builder, left, right, name);
		case BinaryOperator.DIVIDE:
		case BinaryOperator.REMAINDER:
			return division (op, integer_type, left, right, name, state);
		case BinaryOperator.LESS:
			return CApi.build_icmp (builder, (signed ? CApi.IntPredicate.SLT : CApi.IntPredicate.ULT), left, right, name);
		case BinaryOperator.LESS_EQUAL:
			return CApi.build_icmp (builder, (signed ? CApi.IntPredicate.SLE : CApi.IntPredicate.ULE), left, right, name);
		case BinaryOperator.GREATER:
			return CApi.build_icmp (builder, (signed ? CApi.IntPredicate.SGT : CApi.IntPredicate.UGT), left, right, name);
		case BinaryOperator.GREATER_EQUAL:
			return CApi.build_icmp (builder, (signed ? CApi.IntPredicate.SGE : CApi.IntPredicate.UGE), left, right, name);
		case BinaryOperator.EQUAL:
			return CApi.build_icmp (builder, CApi.IntPredicate.EQ, left, right, name);
		case BinaryOperator.NOT_EQUAL:
			return CApi.build_icmp (builder, CApi.IntPredicate.NE, left, right, name);
		default:
			throw new LlvmError.LOWERING ("internal LLVM lowering error: unsupported binary operator");
		}
	}

	// Ordinary LLVM operations: nearest/ties-even, IEEE denormals, no
	// fast-math flags. Source operations remain separately rounded.
	private CApi.ValueRef floating_binary(BinaryOperator op, CApi.ValueRef left, CApi.ValueRef right, string name) throws LlvmError {
		switch (op) {
		case BinaryOperator.ADD:
			return CApi.build_fadd (builder, left, right, name);
		case BinaryOperator.SUBTRACT:
			return CApi.build_fsub (builder, left, right, name);
		case BinaryOperator.MULTIPLY:
			return CApi.build_fmul (builder, left, right, name);
		case BinaryOperator.DIVIDE:
			return CApi.build_fdiv (builder, left, right, name);
		case BinaryOperator.EQUAL:
			return CApi.build_fcmp (builder, CApi.RealPredicate.OEQ, left, right, name);
		case BinaryOperator.NOT_EQUAL:
			return CApi.build_fcmp (builder, CApi.RealPredicate.UNE, left, right, name);
		case BinaryOperator.LESS:
			return CApi.build_fcmp (builder, CApi.RealPredicate.OLT, left, right, name);
		case BinaryOperator.LESS_EQUAL:
			return CApi.build_fcmp (builder, CApi.RealPredicate.OLE, left, right, name);
		case BinaryOperator.GREATER:
			return CApi.build_fcmp (builder, CApi.RealPredicate.OGT, left, right, name);
		case BinaryOperator.GREATER_EQUAL:
			return CApi.build_fcmp (builder, CApi.RealPredicate.OGE, left, right, name);
		default:
			throw new LlvmError.LOWERING ("internal LLVM lowering error: unsupported floating operator");
		}
	}

	private CApi.BasicBlockRef block(string name) {
		return CApi.append_basic_block_in_context (artifact.context, function, name);
	}

	// Ordered scalar checks are strict, including every lane of vectors.
	// No flagged arithmetic occurs until its complete finite domain holds.
	private LlvmFloatingDomain checked_floating_domain(BinaryOperator op, SemanticType type, CApi.ValueRef left, CApi.ValueRef right, string name, LlvmBlockState state) throws LlvmError {
		var original_block = CApi.insert_block (builder);
		var preceding = CApi.last_instruction (original_block);
		var vector = type as VectorType;
		var element = vector == null ? type : vector.element_type;
		bool single = element.kind == TypeKind.F32;
		var format = single ? BinaryFloatFormat.BINARY32 : BinaryFloatFormat.BINARY64;
		var bound_value = new BinaryFloatValue.from_bits (format, single ? ((uint64) 187 << 23) : ((uint64) 1523 << 52));
		var minimum_value = new BinaryFloatValue.from_bits (format, single ? ((uint64) 67 << 23) : ((uint64) 523 << 52));
		var upper = floating (bound_value);
		var lower = floating (bound_value.negated ());
		var minimum = floating (minimum_value);
		var negative_minimum = floating (minimum_value.negated ());
		var valid = CApi.const_int (CApi.int1_type_in_context (artifact.context), 1, 0);
		for (int lane = 0; lane < (vector == null ? 1 : vector.lane_count); lane++) {
			var index = CApi.const_int (types.scalar (NativeScalarType.I32), lane, 0);
			var a = vector == null ? left : CApi.build_extract_element (builder, left, index, name + ".domain.left");
			var b = vector == null ? right : CApi.build_extract_element (builder, right, index, name + ".domain.right");
			var a_valid = CApi.build_and (builder, CApi.build_fcmp (builder, CApi.RealPredicate.OGE, a, lower, name + ".left.lower"), CApi.build_fcmp (builder, CApi.RealPredicate.OLE, a, upper, name + ".left.upper"), name + ".left.finite");
			var b_valid = CApi.build_and (builder, CApi.build_fcmp (builder, CApi.RealPredicate.OGE, b, lower, name + ".right.lower"), CApi.build_fcmp (builder, CApi.RealPredicate.OLE, b, upper, name + ".right.upper"), name + ".right.finite");
			if (op == BinaryOperator.DIVIDE) {
				b_valid = CApi.build_and (builder, b_valid, CApi.build_or (builder, CApi.build_fcmp (builder, CApi.RealPredicate.OGE, b, minimum, name + ".divisor.positive"), CApi.build_fcmp (builder, CApi.RealPredicate.OLE, b, negative_minimum, name + ".divisor.negative"), name + ".divisor.nonzero"), name + ".division.domain");
			}
			valid = CApi.build_and (builder, valid, CApi.build_and (builder, a_valid, b_valid, name + ".lane.domain"), name + ".domain");
		}
		guard_slice_condition (CApi.build_xor (builder, valid, CApi.const_int (CApi.int1_type_in_context (artifact.context), 1, 0), name + ".invalid.fp.domain"), name + ".fp.policy", state);
		var domain = new LlvmFloatingDomain ();
		for (var step = (void*) preceding == null ? CApi.first_instruction (original_block) : CApi.next_instruction (preceding); (void*) step != null; step = CApi.next_instruction (step)) {
			domain.steps.add (new LlvmFloatingStep (step));
		}
		var trap = CApi.successor (CApi.last_instruction (original_block), 0);
		for (var step = CApi.first_instruction (trap); (void*) step != null; step = CApi.next_instruction (step)) {
			domain.steps.add (new LlvmFloatingStep (step));
		}
		return domain;
	}

	private bool constant_true(CApi.ValueRef value) {
		return (void*) CApi.is_constant_int (value) != null && CApi.constant_signed (value) != 0;
	}

	// Shares the physical continuation authority used by arithmetic traps.
	internal void guard_nonnull(CApi.ValueRef pointer, string name, LlvmBlockState state, bool class_guard = false) throws LlvmError {
		var trap = block (name + ".trap");
		var continuation = block (name + ".nonnull");
		var is_null = CApi.build_icmp (builder, CApi.IntPredicate.EQ, pointer, CApi.const_pointer_null (types.scalar (NativeScalarType.PTR)), name + ".null");
		var guarded = CApi.build_cond_br (builder, is_null, trap, continuation);
		if (class_guard) {
			if ((void*) CApi.is_instruction (is_null) != null) {
				artifact.class_values.add (new LlvmClassValueBinding (is_null, CApi.Opcode.ICMP, types.scalar (NativeScalarType.B1), new CApi.ValueRef[] { pointer, CApi.const_pointer_null (types.scalar (NativeScalarType.PTR)) }, "heap throw nonnull guard", -1, (int) CApi.IntPredicate.EQ));
			}
			artifact.class_branches.add (new LlvmClassBranchBinding (guarded, is_null, trap, continuation));
		}
		CApi.position_builder_at_end (builder, trap);
		emit_trap ();
		CApi.position_builder_at_end (builder, continuation);
		state.end = continuation;
	}

	internal CApi.ValueRef guard_numeric(CApi.ValueRef operand, IntegerType destination, string name, LlvmBlockState state) throws LlvmError {
		// All current bounds (MIN-1, MAX+1) and every f32 are exact in
		// binary64. These open intervals implement truncation BEFORE range:
		// e.g. -128.9 -> i8 and -0.5 -> u32 are valid. Ordered comparisons
		// reject every NaN and both infinities without a physical conversion.
		var wide_type = types.scalar (NativeScalarType.F64);
		var wide = (void*) CApi.type_of (operand) == (void*) wide_type ? operand : CApi.build_fpext (builder, operand, wide_type, name + ".wide");
		// Near 2^63/2^64 the floating spacing exceeds one. MIN is an
		// inclusive exact boundary; MAX+1 is an exclusive power of two.
		var lower = BinaryFloatValue.from_decimal (BinaryFloatFormat.BINARY64, destination.bit_width == 64 && destination.is_signed ? "9223372036854775808.0" : (-(destination.minimum - 1)).to_string () + ".0").negated ();
		var upper = BinaryFloatValue.from_decimal (BinaryFloatFormat.BINARY64, destination.bit_width == 64 ? (destination.is_signed ? "9223372036854775808.0" : "18446744073709551616.0") : (destination.maximum + 1).to_string () + ".0");
		var above = CApi.build_fcmp (builder, destination.bit_width == 64 && destination.is_signed ? CApi.RealPredicate.OGE : CApi.RealPredicate.OGT, wide, floating (lower), name + ".above");
		var below = CApi.build_fcmp (builder, CApi.RealPredicate.OLT, wide, floating (upper), name + ".below");
		var valid = CApi.build_and (builder, above, below, name + ".in.range");
		// Sanitizing before the branch also makes speculative uses defined.
		// The original invalid source still takes the non-unwinding trap.
		var safe = CApi.build_select (builder, valid, operand, CApi.const_null (CApi.type_of (operand)), name + ".safe");
		var invalid = CApi.build_xor (builder, valid, CApi.const_int (CApi.int1_type_in_context (artifact.context), 1, 0), name + ".invalid");
		guard_slice_condition (invalid, name, state);
		return safe;
	}

	internal void guard_array_index(CApi.ValueRef index, IntegerType type, int length, string name, LlvmBlockState state) throws LlvmError {
		var physical = types.integer_type (type);
		// Compare in the original exact integer domain. A bound outside its
		// positive domain cannot be encoded in that width and needs no test.
		var invalid = CApi.const_int (CApi.int1_type_in_context (artifact.context), 0, 0);
		if (length <= type.maximum) {
			invalid = CApi.build_icmp (builder, type.is_signed ? CApi.IntPredicate.SGE : CApi.IntPredicate.UGE, index, CApi.const_int (physical, length, 0), name + ".oversized");
		}
		if (type.is_signed) {
			var negative = CApi.build_icmp (builder, CApi.IntPredicate.SLT, index, CApi.const_null (physical), name + ".negative");
			invalid = CApi.build_or (builder, invalid, negative, name + ".invalid");
		}
		var trap = block (name + ".trap");
		var valid = block (name + ".valid");
		CApi.build_cond_br (builder, invalid, trap, valid);
		CApi.position_builder_at_end (builder, trap);
		emit_trap ();
		CApi.position_builder_at_end (builder, valid);
		state.end = valid;
	}

	// One extra sign bit makes even u64.MAX a positive mathematical
	// ordinal. Old narrow paths keep their existing i64 physical proof.
	internal CApi.ValueRef mathematical_integer(CApi.ValueRef value, IntegerType type, string name, bool wide_ordinal = false) {
		var wide = CApi.int_type_in_context (artifact.context, type.bit_width == 64 || wide_ordinal ? 128 : 64);
		return type.is_signed ? CApi.build_sext (builder, value, wide, name) : CApi.build_zext (builder, value, wide, name);
	}

	internal void guard_slice_condition(CApi.ValueRef invalid, string name, LlvmBlockState state) throws LlvmError {
		var trap = block (name + ".trap");
		var valid = block (name + ".valid");
		CApi.build_cond_br (builder, invalid, trap, valid);
		CApi.position_builder_at_end (builder, trap);
		emit_trap ();
		CApi.position_builder_at_end (builder, valid);
		state.end = valid;
	}

	internal CApi.ValueRef guard_slice_range(CApi.ValueRef start, IntegerType start_type, CApi.ValueRef count, IntegerType count_type, int length, string name, LlvmBlockState state, out CApi.ValueRef extent) throws LlvmError {
		bool wide_ordinal = start_type.bit_width == 64 || count_type.bit_width == 64;
		var first = mathematical_integer (start, start_type, name + ".start.math", wide_ordinal);
		var size = mathematical_integer (count, count_type, name + ".count.math", wide_ordinal);
		var wide = CApi.type_of (first);
		var bound = CApi.const_int (wide, length, 0);
		var negative = CApi.build_icmp (builder, CApi.IntPredicate.SLT, first, CApi.const_null (wide), name + ".start.negative");
		var oversized = CApi.build_icmp (builder, CApi.IntPredicate.SGT, first, bound, name + ".start.oversized");
		guard_slice_condition (CApi.build_or (builder, negative, oversized, name + ".start.invalid"), name + ".start", state);
		// Subtract only after proving 0 <= start <= N. Never add start+count.
		var remaining = CApi.build_sub (builder, bound, first, name + ".remaining");
		negative = CApi.build_icmp (builder, CApi.IntPredicate.SLT, size, CApi.const_null (wide), name + ".count.negative");
		oversized = CApi.build_icmp (builder, CApi.IntPredicate.SGT, size, remaining, name + ".count.oversized");
		guard_slice_condition (CApi.build_or (builder, negative, oversized, name + ".count.invalid"), name + ".count", state);
		extent = CApi.build_trunc (builder, size, CApi.int32_type_in_context (artifact.context), name + ".length");
		return first;
	}

	internal void guard_slice_index(CApi.ValueRef index, IntegerType type, CApi.ValueRef length, string name, LlvmBlockState state) throws LlvmError {
		var ordinal = mathematical_integer (index, type, name + ".index.math");
		var wide = CApi.type_of (ordinal);
		var extent = CApi.build_zext (builder, length, wide, name + ".length.math");
		var negative = CApi.build_icmp (builder, CApi.IntPredicate.SLT, ordinal, CApi.const_null (wide), name + ".negative");
		var oversized = CApi.build_icmp (builder, CApi.IntPredicate.SGE, ordinal, extent, name + ".oversized");
		guard_slice_condition (CApi.build_or (builder, negative, oversized, name + ".invalid"), name, state);
	}

	internal void emit_trap() throws LlvmError {
		uint trap_id = CApi.lookup_intrinsic_id ("llvm.trap", 9);
		if (trap_id == 0) {
			throw new LlvmError.LOWERING ("internal LLVM lowering error: LLVM 22 trap intrinsic is unavailable");
		}
		var trap_function = CApi.get_intrinsic_declaration (artifact.module, trap_id, null, 0);
		var trap_type = CApi.intrinsic_get_type (artifact.context, trap_id, null, 0);
		CApi.build_call (builder, trap_type, trap_function, null, 0, "");
		CApi.build_unreachable (builder);
	}

	internal CApi.ValueRef shift(IntegerShiftKind kind, SemanticType value_type, IntegerType count_type, CApi.ValueRef operand, CApi.ValueRef count, bool known_valid, string name, LlvmBlockState state) throws LlvmError, NativeAbiError {
		var element = IntegerShiftKind.element_type (value_type);
		var physical = types.integer_type (element);
		if (!known_valid) {
			var count_physical = types.integer_type (count_type);
			var oversized = CApi.build_icmp (builder, count_type.is_signed ? CApi.IntPredicate.SGE : CApi.IntPredicate.UGE, count, CApi.const_int (count_physical, element.bit_width, 0), name + ".oversized");
			var invalid = oversized;
			if (count_type.is_signed) {
				var negative = CApi.build_icmp (builder, CApi.IntPredicate.SLT, count, CApi.const_null (count_physical), name + ".negative");
				invalid = CApi.build_or (builder, negative, oversized, name + ".invalid");
			}
			var trap = block (name + ".trap");
			var valid = block (name + ".valid");
			CApi.build_cond_br (builder, invalid, trap, valid);
			CApi.position_builder_at_end (builder, trap);
			emit_trap ();
			CApi.position_builder_at_end (builder, valid);
			state.end = valid;
			// The C builder folds constants even without optimization. An
			// impossible continuation must not manufacture constant poison.
			if (constant_true (invalid)) {
				return CApi.const_null (types.value_type (value_type));
			}
		}
		// Proven nonnegative and < W: this physical normalization is
		// lossless, backend-only, and never an Astra ICONV operation.
		if (count_type.bit_width > element.bit_width) {
			count = CApi.build_trunc (builder, count, physical, name + ".count");
		} else if (count_type.bit_width < element.bit_width) {
			count = CApi.build_zext (builder, count, physical, name + ".count");
		}
		var vector = value_type as VectorType;
		if (vector != null) {
			var index_type = types.scalar (NativeScalarType.I32);
			var seed = CApi.build_insert_element (builder, CApi.const_null (types.value_type (value_type)), count, CApi.const_int (index_type, 0, 0), name + ".count.seed");
			count = CApi.build_shuffle_vector (builder, seed, seed, CApi.const_null (CApi.vector_type (index_type, vector.lane_count)), name + ".count.splat");
		}
		// Ordinary flag-free shifts: no nsw/nuw, no exact.
		return kind == IntegerShiftKind.LEFT ? CApi.build_shl (builder, operand, count, name) : element.is_signed ? CApi.build_ashr (builder, operand, count, name) : CApi.build_lshr (builder, operand, count, name);
	}

	private CApi.ValueRef division(BinaryOperator op, IntegerType type, CApi.ValueRef left, CApi.ValueRef right, string name, LlvmBlockState state) throws LlvmError {
		var physical = types.integer_type (type);
		var zero = CApi.const_int (physical, 0, 0);
		var minimum = CApi.const_int (physical, type.sign_bit, 0);
		var minus_one = CApi.const_int (physical, type.mask, 0);
		var trap = block (name + ".trap");
		var nonzero = block (name + ".nonzero");
		var is_zero = CApi.build_icmp (builder, CApi.IntPredicate.EQ, right, zero, name + ".zero");
		CApi.build_cond_br (builder, is_zero, trap, nonzero);

		CApi.position_builder_at_end (builder, trap);
		emit_trap ();

		CApi.position_builder_at_end (builder, nonzero);
		state.end = nonzero;
		if (!type.is_signed) {
			// A constant-zero RHS makes this block unreachable. Keep a
			// harmless value for downstream unreachable code, never poison.
			if (constant_true (is_zero)) {
				return zero;
			}
			return op == BinaryOperator.DIVIDE ? CApi.build_udiv (builder, left, right, name) : CApi.build_urem (builder, left, right, name);
		}
		var special = block (name + ".special");
		var normal = block (name + ".normal");
		var continuation = block (name + ".continue");
		var is_minimum = CApi.build_icmp (builder, CApi.IntPredicate.EQ, left, minimum, name + ".minimum");
		var is_minus_one = CApi.build_icmp (builder, CApi.IntPredicate.EQ, right, minus_one, name + ".minusone");
		var overflow = CApi.build_and (builder, is_minimum, is_minus_one, name + ".overflow");
		CApi.build_cond_br (builder, overflow, special, normal);

		CApi.position_builder_at_end (builder, special);
		var special_result = op == BinaryOperator.DIVIDE ? minimum : zero;
		CApi.build_br (builder, continuation);

		CApi.position_builder_at_end (builder, normal);
		// The C builder folds constant expressions even without passes.
		// If a guard is already true, this block is impossible. Do not ask
		// LLVM to fold an invalid constant division into a poison value.
		bool impossible = constant_true (is_zero) || constant_true (overflow);
		CApi.ValueRef normal_result = zero;
		if (impossible) {
			CApi.build_unreachable (builder);
		} else {
			normal_result = op == BinaryOperator.DIVIDE ? CApi.build_sdiv (builder, left, right, name + ".raw") : CApi.build_srem (builder, left, right, name + ".raw");
			CApi.build_br (builder, continuation);
		}

		CApi.position_builder_at_end (builder, continuation);
		var result = CApi.build_phi (builder, physical, name);
		CApi.add_incoming (result, &special_result, &special, 1);
		if (!impossible) {
			CApi.add_incoming (result, &normal_result, &normal, 1);
		}
		state.end = continuation;
		return result;
	}

}
}
