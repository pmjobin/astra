// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
public enum PrefixOperator {
	POSITIVE,
	NEGATIVE,
	NOT,
	BIT_NOT;

	public bool accepts(SemanticType operand, SemanticType result) {
		if (operand is VectorType) {
			var vector = (VectorType) operand;
			return result == operand && accepts (vector.element_type, vector.element_type);
		}
		switch (this) {
		case NEGATIVE:
			return (operand is FloatingType || (operand is IntegerType && ((IntegerType) operand).is_signed)) && result == operand;
		case POSITIVE:
			return (operand is IntegerType || operand is FloatingType) && result == operand;
		case BIT_NOT:
			return operand is IntegerType && result == operand;
		case NOT:
			return operand.kind == TypeKind.BOOL && result == operand;
		default:
			return false;
		}
	}

	public string spelling() {
		switch (this) {
		case POSITIVE:
			return "+";
		case NEGATIVE:
			return "-";
		case NOT:
			return "!";
		case BIT_NOT:
			return "~";
		default:
			assert_not_reached ();
		}
	}
}

// Control-flow semantics, deliberately separate from eager binary operators.
public enum ShortCircuitOperator {
	AND,
	OR;

	public bool accepts(SemanticType left, SemanticType right, SemanticType result) {
		return (this == AND || this == OR) && left.kind == TypeKind.BOOL && left == right && result == left;
	}

	public string spelling() {
		switch (this) {
		case AND:
			return "&&";
		case OR:
			return "||";
		default:
			assert_not_reached ();
		}
	}
}

public enum VectorReductionOperator {
	ALL,
	ANY;

	public bool accepts(SemanticType operand, SemanticType result) {
		var mask = operand as VectorType;
		return (this == ALL || this == ANY) && mask != null && mask.is_mask && result == mask.element_type;
	}

	public string spelling() {
		switch (this) {
		case ALL:
			return "all";
		case ANY:
			return "any";
		default:
			assert_not_reached ();
		}
	}
}

// A separate ordinal/count domain, never a same-type binary operation.
// Every instance traps for mathematical counts outside [0, element width).
public enum IntegerShiftKind {
	LEFT,
	RIGHT;

	public static IntegerType? element_type(SemanticType type) {
		return ((type is VectorType) ? ((VectorType) type).element_type : type) as IntegerType;
	}

	public bool accepts(SemanticType value, SemanticType count, SemanticType result) {
		var vector = value as VectorType;
		return (this == LEFT || this == RIGHT) && result == value && element_type (value) != null && count is IntegerType && (vector == null || VectorType.supports (vector.element_type, vector.lane_count));
	}

	public string operation_name(SemanticType value_type) {
		return this == LEFT ? "shift-left" : element_type (value_type).is_signed ? "shift-right-arithmetic" : "shift-right-logical";
	}
}

public enum BinaryOperator {
	ADD,
	SUBTRACT,
	MULTIPLY,
	DIVIDE,
	REMAINDER,
	LESS,
	LESS_EQUAL,
	GREATER,
	GREATER_EQUAL,
	EQUAL,
	NOT_EQUAL,
	BIT_AND,
	BIT_OR,
	BIT_XOR;

	public bool is_bitwise() {
		return this == BIT_AND || this == BIT_OR || this == BIT_XOR;
	}

	public bool is_arithmetic() {
		return this == ADD || this == SUBTRACT || this == MULTIPLY || this == DIVIDE || this == REMAINDER;
	}

	public bool is_relational() {
		return this == LESS || this == LESS_EQUAL || this == GREATER || this == GREATER_EQUAL;
	}

	public bool is_equality() {
		return this == EQUAL || this == NOT_EQUAL;
	}

	public bool accepts(SemanticType left, SemanticType right, SemanticType result) {
		if (left != right) {
			return false;
		}
		if (left is VectorType) {
			var vector = (VectorType) left;
			if (is_arithmetic () || is_bitwise ()) {
				if (vector.element_type is IntegerType && (this == DIVIDE || this == REMAINDER)) {
					return false;
				}
				return result == left && accepts (vector.element_type, vector.element_type, vector.element_type);
			}
			var mask = result as VectorType;
			return mask != null && mask.lane_count == vector.lane_count && mask.is_mask && accepts (vector.element_type, vector.element_type, mask.element_type);
		}
		if (is_bitwise ()) {
			return (left is IntegerType || left.kind == TypeKind.BOOL) && result == left;
		}
		if (is_arithmetic ()) {
			return (left is IntegerType || (left is FloatingType && this != REMAINDER)) && result == left;
		}
		if (is_relational ()) {
			return (left is IntegerType || left is FloatingType) && result.kind == TypeKind.BOOL;
		}
		return is_equality () && (left is StringType || left is IntegerType || left is FloatingType || left.kind == TypeKind.BOOL || left.is_nullable_pointer_value ()) && result.kind == TypeKind.BOOL;
	}

	public string spelling() {
		switch (this) {
		case BIT_AND: return "&";
		case BIT_OR:
			return "|";
		case BIT_XOR:
			return "^";
		case ADD:
			return "+";
		case SUBTRACT:
			return "-";
		case MULTIPLY:
			return "*";
		case DIVIDE:
			return "/";
		case REMAINDER:
			return "%";
		case LESS:
			return "<";
		case LESS_EQUAL:
			return "<=";
		case GREATER:
			return ">";
		case GREATER_EQUAL:
			return ">=";
		case EQUAL:
			return "==";
		case NOT_EQUAL:
			return "!=";
		default:
			assert_not_reached ();
		}
	}
}

public enum GenericOperationKind {
	EQ, NE, LT, LE, GT, GE, ADD, SUB, MUL, DIV, BIT_AND, BIT_OR, BIT_XOR, BIT_NOT, SHIFT_LEFT, SHIFT_RIGHT;
	public bool valid() {
		return this >= EQ && this <= SHIFT_RIGHT;
	}
	public bool is_comparison() {
		return this >= EQ && this <= GE;
	}
	public bool is_shift() {
		return this == SHIFT_LEFT || this == SHIFT_RIGHT;
	}
	public GenericCapabilityIdentity capability() {
		if (this <= NE) {
			return GenericCapabilityIdentity.EQ;
		}
		if (this <= GE) {
			return GenericCapabilityIdentity.ORDERED;
		}
		if (this <= DIV) {
			return GenericCapabilityIdentity.NUMERIC;
		}
		if (this <= BIT_NOT) {
			return GenericCapabilityIdentity.BITWISE;
		}
		return GenericCapabilityIdentity.SHIFT;
	}
	public static GenericOperationKind? from_binary(BinaryOperator kind) {
		switch (kind) {
		case BinaryOperator.EQUAL: return EQ;
		case BinaryOperator.NOT_EQUAL:
			return NE;
		case BinaryOperator.LESS:
			return LT;
		case BinaryOperator.LESS_EQUAL:
			return LE;
		case BinaryOperator.GREATER:
			return GT;
		case BinaryOperator.GREATER_EQUAL:
			return GE;
		case BinaryOperator.ADD:
			return ADD;
		case BinaryOperator.SUBTRACT:
			return SUB;
		case BinaryOperator.MULTIPLY:
			return MUL;
		case BinaryOperator.DIVIDE:
			return DIV;
		case BinaryOperator.BIT_AND:
			return BIT_AND;
		case BinaryOperator.BIT_OR:
			return BIT_OR;
		case BinaryOperator.BIT_XOR:
			return BIT_XOR;
		default:
			return null;
		}
	}
	public BinaryOperator binary_operator() {
		switch (this) {
		case EQ:
			return BinaryOperator.EQUAL;
		case NE:
			return BinaryOperator.NOT_EQUAL;
		case LT:
			return BinaryOperator.LESS;
		case LE:
			return BinaryOperator.LESS_EQUAL;
		case GT:
			return BinaryOperator.GREATER;
		case GE:
			return BinaryOperator.GREATER_EQUAL;
		case ADD:
			return BinaryOperator.ADD;
		case SUB:
			return BinaryOperator.SUBTRACT;
		case MUL:
			return BinaryOperator.MULTIPLY;
		case DIV:
			return BinaryOperator.DIVIDE;
		case BIT_AND:
			return BinaryOperator.BIT_AND;
		case BIT_OR:
			return BinaryOperator.BIT_OR;
		case BIT_XOR:
			return BinaryOperator.BIT_XOR;
		default:
			assert_not_reached ();
		}
	}
	public string spelling() {
		return this == BIT_NOT ? "~" : this == SHIFT_LEFT ? "<<" : this == SHIFT_RIGHT ? ">>" : binary_operator ().spelling ();
	}
	public string operation_name() {
		string[] names = {
			"eq", "ne", "lt", "le", "gt", "ge", "add", "sub", "mul", "div", "bit-and", "bit-or", "bit-xor", "bit-not", "shift-left", "shift-right"
		};
		return valid () ? names[(int) this] : "invalid-operation";
	}
	public bool accepts(TypeParameterType parameter, SemanticType left, SemanticType? right, SemanticType result) {
		if (!valid () || left != parameter || !GenericCapabilityAuthority.satisfies (parameter, capability ())) {
			return false;
		}
		if (is_comparison () ? result.kind != TypeKind.BOOL : result != parameter) {
			return false;
		}
		return this == BIT_NOT ? right == null : is_shift () ? right is IntegerType : right == parameter;
	}
}
}
