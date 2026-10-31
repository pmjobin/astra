// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.Core {
private void register_branch_operator_tests() {
	string[] expressions = {
		"true", "false", "!true", "!(1 == 2)", "1 < 2", "1 <= 2", "1 > 2", "1 >= 2", "1 == 2", "1 != 2", "true == false", "true != false"
	};
	for (int i = 0; i < expressions.length; i++) {
		string expression = expressions[i];
		add_case ("/core/branch/value/" + expression, () => {
				var program = build_ok ("bool f(){return " + expression + ";}");
				var value = returned_value (program.functions[0]);
				assert (value.semantic_type == program.functions[0].return_type && value.semantic_type.kind == TypeKind.BOOL);
				if (expression == "true" || expression == "false") {
					assert (((CoreBooleanValue) value).literal.spelling () == expression);
				} else {
					assert (value is CorePrefixValue || value is CoreBinaryValue);
				}
				assert (dump_ok (program) == dump_ok (build_ok ("bool f(){return " + expression + ";}")));
			});
	}
	for (int i = 0; i < 14; i++) {
		int invalid = i;
		add_case ("/core/branch/verifier/value-%d".printf (invalid), () => {
				var program = build_ok ("bool f(){return true;}int g(){return 1;}void h(){}");
				var bool_type = program.functions[0].return_type;
				var int_type = program.functions[1].return_type;
				var span = program.span;
				var boolean = new CoreBooleanValue (span, bool_type, BooleanLiteral.TRUE);
				var integer = new CoreIntegerValue (span, int_type, AstraIntValue.from_int64 (7));
				CoreValue bad;
				string message;
				string suffix = "";
				switch (invalid) {
					case 0:
						bad = new CoreBooleanValue (span, int_type, BooleanLiteral.TRUE);
						message = "boolean literal must have type 'bool'";
						break;
					case 1:
						bad = new CoreIntegerValue (span, bool_type, AstraIntValue.from_int64 (7));
						message = "integer literal must have type 'int'";
						break;
					case 2:
						bad = new CoreBooleanValue (span, bool_type, (BooleanLiteral) 99);
						message = "unsupported boolean literal";
						break;
					case 3:
						bad = new CorePrefixValue (span, bool_type, PrefixOperator.NOT, integer);
						message = "invalid operand or result type for semantic prefix operator";
						break;
					case 4:
						bad = new CorePrefixValue (span, bool_type, PrefixOperator.NEGATIVE, boolean);
						message = "invalid operand or result type for semantic prefix operator";
						break;
					case 5:
						bad = new CoreBinaryValue (span, bool_type, BinaryOperator.ADD, boolean, boolean);
						message = "invalid operands or result type for semantic binary operator";
						break;
					case 6:
						bad = new CoreBinaryValue (span, bool_type, BinaryOperator.LESS, boolean, boolean);
						message = "invalid operands or result type for semantic binary operator";
						break;
					case 7:
						bad = new CoreBinaryValue (span, int_type, BinaryOperator.LESS, integer, integer);
						message = "invalid operands or result type for semantic binary operator";
						break;
					case 8:
						bad = new CoreBinaryValue (span, bool_type, BinaryOperator.EQUAL, boolean, integer);
						message = "invalid operands or result type for semantic binary operator";
						break;
					case 9:
						bad = new CoreBinaryValue (span, int_type, BinaryOperator.NOT_EQUAL, integer, integer);
						message = "invalid operands or result type for semantic binary operator";
						break;
					case 10:
						bad = new CorePrefixValue (span, int_type, PrefixOperator.NOT, boolean);
						message = "invalid operand or result type for semantic prefix operator";
						break;
					case 11:
						bad = new CorePrefixValue (span, int_type, PrefixOperator.POSITIVE, boolean);
						message = "invalid operand or result type for semantic prefix operator";
						break;
					case 12:
						bad = new CoreBinaryValue (span, bool_type, BinaryOperator.EQUAL, new CoreBooleanValue (span, program.functions[2].return_type, BooleanLiteral.TRUE), boolean);
						message = "value or parameter type must be 'int', 'bool' or 'void*', found 'void'";
						suffix = "/left";
						break;
					default:
						bad = new CoreBooleanValue (span, new SemanticType (TypeKind.BOOL), BooleanLiteral.TRUE);
						message = "inconsistent 'bool' semantic type identity";
						break;
				}
				program.functions[0].body.statements[0] = new CoreReturn (span, bad);
				expect_invalid (program, "function #0/statement #0/value" + suffix, message);
			});
	}
}
}
