// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;

// Streaming access to the bounded typed evaluator. No LLVM or host floats.
namespace Astra.Tests.ConstantOperations {
private CheckedExpression atom(BuiltinTypes types, SourceSpan span, string name, string bits) {
	var type = types.resolve (name);
	uint64 pattern = uint64.parse (bits, 16);
	if (type is IntegerType) {
		return new CheckedIntegerExpression.typed (span, type, AstraIntegerValue.from_bits ((IntegerType) type, pattern));
	}
	if (type is FloatingType) {
		return new CheckedFloatExpression (span, type, new BinaryFloatValue.from_bits (((FloatingType) type).format, pattern));
	}
	return new CheckedBooleanExpression (span, type, pattern == 0 ? BooleanLiteral.FALSE : BooleanLiteral.TRUE);
}
int main() {
	var types = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("oracle", "x"), 0, 1);
	string? line;
	while ((line = stdin.read_line ()) != null) {
		var fields = line.split (" ");
		var left = atom (types, span, fields[0], fields[2]);
		CheckedExpression expression;
		string operation = fields[1];
		if (operation == "as") {
			var destination = types.resolve (fields[3]);
			var numeric = NumericConversionKind.select (left.semantic_type, destination);
			if (numeric != NumericConversionKind.INVALID) {
				expression = new CheckedNumericConversionExpression (span, left.semantic_type, destination, numeric, left, numeric.policy ());
			} else if (left.semantic_type is IntegerType) {
				expression = new CheckedIntegerConversionExpression (span, left.semantic_type, destination, left);
			} else {
				expression = new CheckedFloatConversionExpression (span, left.semantic_type, destination, (left.semantic_type is F32Type) ? FloatConversionKind.FLOAT_WIDEN : FloatConversionKind.FLOAT_NARROW, left);
			}
		} else if (fields.length == 3) {
			var kind = operation == "+" ? PrefixOperator.POSITIVE : operation == "-" ? PrefixOperator.NEGATIVE : operation == "~" ? PrefixOperator.BIT_NOT : PrefixOperator.NOT;
			assert (kind.accepts (left.semantic_type, left.semantic_type));
			expression = new CheckedPrefixExpression (span, left.semantic_type, kind, left);
		} else {
			var right = atom (types, span, fields[3], fields[4]);
			if (operation == "<<" || operation == ">>") {
				expression = new CheckedIntegerShiftExpression (span, left.semantic_type, operation == "<<" ? IntegerShiftKind.LEFT : IntegerShiftKind.RIGHT, left, right);
			} else {
				BinaryOperator kind = BinaryOperator.ADD;
				bool found = false;
				for (int i = (int) BinaryOperator.ADD; i <= (int) BinaryOperator.BIT_XOR; i++) {
					if (((BinaryOperator) i).spelling () == operation) {
						kind = (BinaryOperator) i;
						found = true;
						break;
					}
				}
				assert (found);
				SemanticType result = kind.is_equality () || kind.is_relational () ? types.bool_type : left.semantic_type;
				assert (kind.accepts (left.semantic_type, right.semantic_type, result));
				expression = new CheckedBinaryExpression (span, result, kind, left, right);
			}
		}
		var evaluator = new ConstantEvaluator ("oracle");
		var value = evaluator.evaluate (expression);
		stdout.printf ("%s\n", value == null ? "trap" : value.integer != null ? value.integer.to_string () : value.floating != null ? value.floating.to_string () : value.boolean ? "true" : "false");
	}
	return 0;
}
}
