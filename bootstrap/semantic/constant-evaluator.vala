// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Semantic {
// Only checked scalar expressions enter. References are memoized leaves;
// syntax's bounded depth also bounds this walk, independent of graph depth.
public class ConstantEvaluator : Object {
	public Diagnostic? diagnostic { get; private set; }
	private string context;
	public ConstantEvaluator (string context) {
		this.context = context;
	}
	private ConstantValue? fail(CheckedExpression expression, string message) {
		diagnostic = new Diagnostic (expression.span, message + " in " + context);
		return null;
	}

	public static bool comparison(BinaryOperator operation, int order) {
		switch (operation) {
		case BinaryOperator.EQUAL: return order == 0;
		case BinaryOperator.NOT_EQUAL: return order != 0;
		case BinaryOperator.LESS:
			return order < 0;
		case BinaryOperator.LESS_EQUAL:
			return order <= 0;
		case BinaryOperator.GREATER:
			return order > 0;
		case BinaryOperator.GREATER_EQUAL:
			return order >= 0;
		default:
			assert_not_reached ();
		}
	}

	public ConstantValue? evaluate(CheckedExpression expression) {
		if (expression is CheckedTextExpression) {
			return new ConstantValue.text_value (expression.semantic_type, ((CheckedTextExpression) expression).payload);
		}
		if (expression is CheckedTextLengthExpression) {
			var value = evaluate (((CheckedTextLengthExpression) expression).receiver);
			return value == null ? null : new ConstantValue.integer_value (AstraIntegerValue.from_int64 ((IntegerType) expression.semantic_type, value.text.byte_length));
		}
		if (expression is CheckedConstantReference) {
			return ((CheckedConstantReference) expression).constant.value;
		}
		if (expression is CheckedIntegerExpression) {
			return new ConstantValue.integer_value (((CheckedIntegerExpression) expression).value);
		}
		if (expression is CheckedFloatExpression) {
			return new ConstantValue.float_value (expression.semantic_type, ((CheckedFloatExpression) expression).value);
		}
		if (expression is CheckedBooleanExpression) {
			return new ConstantValue.bool_value (expression.semantic_type, ((CheckedBooleanExpression) expression).literal == BooleanLiteral.TRUE);
		}
		var prefix = expression as CheckedPrefixExpression;
		if (prefix != null) {
			var value = evaluate (prefix.operand);
			if (value == null) {
				return null;
			}
			if (prefix.operator_kind == PrefixOperator.POSITIVE) {
				return value;
			}
			if (prefix.operator_kind == PrefixOperator.NOT) {
				return new ConstantValue.bool_value (expression.semantic_type, !value.boolean);
			}
			if (value.floating != null) {
				return new ConstantValue.float_value (expression.semantic_type, value.floating.negated ());
			}
			return new ConstantValue.integer_value (prefix.operator_kind == PrefixOperator.NEGATIVE ? value.integer.neg_wrap () : value.integer.bit_not ());
		}
		var lazy = expression as CheckedShortCircuitExpression;
		if (lazy != null) {
			var left = evaluate (lazy.left);
			if (left == null) {
				return null;
			}
			if (left.boolean == (lazy.operator_kind == ShortCircuitOperator.OR)) {
				return left;
			}
			return evaluate (lazy.right);
		}
		var shift = expression as CheckedIntegerShiftExpression;
		if (shift != null) {
			var left = evaluate (shift.operand);
			if (left == null) {
				return null;
			}
			var count = evaluate (shift.count);
			if (count == null) {
				return null;
			}
			var value = shift.shift_kind == IntegerShiftKind.LEFT ? left.integer.shift_left (count.integer) : left.integer.shift_right (count.integer);
			return value == null ? fail(expression, "invalid evaluated shift count") : new ConstantValue.integer_value (value);
		}
		var iconv = expression as CheckedIntegerConversionExpression;
		var fconv = expression as CheckedFloatConversionExpression;
		var nconv = expression as CheckedNumericConversionExpression;
		if (iconv != null || fconv != null || nconv != null) {
			var value = evaluate (iconv != null ? iconv.operand : fconv != null ? fconv.operand : nconv.operand);
			if (value == null) {
				return null;
			}
			if (iconv != null) {
				return new ConstantValue.integer_value (value.integer.convert_to ((IntegerType) expression.semantic_type));
			}
			if (expression.semantic_type is FloatingType) {
				var format = ((FloatingType) expression.semantic_type).format;
				return new ConstantValue.float_value (expression.semantic_type, value.floating != null ? value.floating.converted (format) : ConstantFloat.from_integer (value.integer, format));
			}
			var integer = ConstantFloat.to_integer (value.floating, (IntegerType) expression.semantic_type);
			return integer == null ? fail(expression, "invalid evaluated floating-to-integer conversion: nonfinite or out-of-range input") : new ConstantValue.integer_value (integer);
		}
		if (expression is CheckedComparisonChain) {
			var chain = (CheckedComparisonChain) expression;
			var left = evaluate (chain.operands[0]);
			if (left == null) {
				return null;
			}
			for (int i = 0; i < chain.operators.length; i++) {
				var right = evaluate (chain.operands[i + 1]);
				if (right == null) {
					return null;
				}
				bool passes = left.floating != null ? ConstantFloat.compare(chain.operators[i], left.floating, right.floating) : comparison (chain.operators[i], left.integer.compare (right.integer));
				if (!passes) {
					return new ConstantValue.bool_value (expression.semantic_type, false);
				}
				left = right;
			}
			return new ConstantValue.bool_value (expression.semantic_type, true);
		}
		var binary = expression as CheckedBinaryExpression;
		if (binary != null) {
			var left = evaluate (binary.left);
			if (left == null) {
				return null;
			}
			var right = evaluate (binary.right);
			if (right == null) {
				return null;
			}
			var operation = binary.operator_kind;
			if (left.text != null) {
				return new ConstantValue.bool_value (expression.semantic_type, left.text.equal_content (right.text) == (operation == BinaryOperator.EQUAL));
			}
			if (left.floating != null) {
				if (operation.is_arithmetic ()) {
					return new ConstantValue.float_value (expression.semantic_type, ConstantFloat.arithmetic (operation, left.floating, right.floating));
				}
				return new ConstantValue.bool_value (expression.semantic_type, ConstantFloat.compare (operation, left.floating, right.floating));
			}
			if (operation.is_relational () || operation.is_equality ()) {
				int order = left.integer != null ? left.integer.compare(right.integer) : left.boolean == right.boolean ? 0 : left.boolean ? 1 : -1;
				return new ConstantValue.bool_value (expression.semantic_type, comparison (operation, order));
			}
			if (left.integer == null) {
				return new ConstantValue.bool_value (expression.semantic_type, operation == BinaryOperator.BIT_AND ? left.boolean && right.boolean : operation == BinaryOperator.BIT_OR ? left.boolean || right.boolean : left.boolean != right.boolean);
			}
			AstraIntegerValue? value = null;
			switch (operation) {
			case BinaryOperator.ADD: value = left.integer.add_wrap (right.integer);
				break;
			case BinaryOperator.SUBTRACT: value = left.integer.sub_wrap (right.integer);
				break;
			case BinaryOperator.MULTIPLY:
				value = left.integer.mul_wrap (right.integer);
				break;
			case BinaryOperator.DIVIDE:
				left.integer.div (right.integer, out value);
				break;
			case BinaryOperator.REMAINDER:
				left.integer.rem (right.integer, out value);
				break;
			case BinaryOperator.BIT_AND:
				value = left.integer.bit_and (right.integer);
				break;
			case BinaryOperator.BIT_OR:
				value = left.integer.bit_or (right.integer);
				break;
			case BinaryOperator.BIT_XOR:
				value = left.integer.bit_xor (right.integer);
				break;
			default:
				assert_not_reached ();
			}
			return value == null ? fail(expression, "invalid evaluated integer operation: division by zero") : new ConstantValue.integer_value (value);
		}
		return fail (expression, "unsupported constant expression");
	}
}
}
