// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;

namespace Astra.Tests.VectorOracle {
private string initializer(GenericArray<AstraIntegerValue> values) {
	var text = new StringBuilder ("{");
	for (int i = 0; i < values.length; i++) {
		if (i > 0) {
			text.append (", ");
		}
		text.append (values[i].to_string ());
	}
	text.append ("}");
	return text.str;
}

int main() {
	var types = new BuiltinTypes ();
	var calls = new GenericArray<string> ();
	int shapes = 0;
	int lane_checks = 0;
	uint64 state = 0xA57A;
	foreach (var element in new IntegerType[] {types.i8_type, types.u8_type, types.i16_type, types.u16_type, types.i32_type, types.u32_type}) {
		foreach (int lanes in new int[] {2, 4, 8, 16}) {
			var vector = types.vector_of (element, lanes);
			if (vector == null) {
				continue;
			}
			string type = vector.display_name ();
			string id = "v%d".printf (shapes++);
			string[] ops = {
				"+", "-", "*", "==", "!=", "<", "<=", ">", ">="
			};
			for (int op = 0; op < ops.length; op++) {
				stdout.printf ("%s %s_op%d(%s a,%s b){return a%s b;}\n", op < 3 ? type : "bool<%d>".printf (lanes), id, op, type, type, ops[op]);
			}
			stdout.printf ("%s %s_plus(%s a){return +a;}\n", type, id, type);
			if (element.is_signed) {
				stdout.printf ("%s %s_neg(%s a){return -a;}\n", type, id, type);
			}
			for (int trial = 0; trial < 24; trial++) {
				var left = new GenericArray<AstraIntegerValue> ();
				var right = new GenericArray<AstraIntegerValue> ();
				uint64[] boundary = {
					(uint64) element.maximum, element.modulus / 2, element.mask, 0, 1, element.mask - 1, 3, 7
				};
				for (int lane = 0; lane < lanes; lane++) {
					state = (state * 1664525 + 1013904223) % 4294967296UL;
					left.add (AstraIntegerValue.from_bits (element, trial < 4 ? boundary[(trial * lanes + lane) % boundary.length] : state & element.mask));
					state = (state * 1664525 + 1013904223) % 4294967296UL;
					right.add (AstraIntegerValue.from_bits (element, trial == 0 ? 1 : trial < 4 ? boundary[(trial + lane + 2) % boundary.length] : state & element.mask));
				}
				string name = "%s_check%d".printf (id, trial);
				calls.add (name);
				stdout.printf ("bool %s(){\n\t%s a=%s;\n\t%s b=%s;\n", name, type, initializer (left), type, initializer (right));
				for (int op = 0; op < ops.length; op++) {
					var expected = new GenericArray<AstraIntegerValue> ();
					var mask = new StringBuilder ("{");
					for (int lane = 0; lane < lanes; lane++) {
						var a = left[lane];
						var b = right[lane];
						// This is the existing scalar authority applied once per
						// lane, with no vector arithmetic implementation.
						if (op < 3) {
							expected.add (op == 0 ? a.add_wrap (b) : op == 1 ? a.sub_wrap (b) : a.mul_wrap (b));
						}
						int cmp = a.compare (b);
						bool value = op == 3 ? a.equal_value (b) : op == 4 ? !a.equal_value (b) : op == 5 ? cmp < 0 : op == 6 ? cmp <= 0 : op == 7 ? cmp > 0 : cmp >= 0;
						if (lane > 0) {
							mask.append (", ");
						}
						mask.append (value ? "true" : "false");
						lane_checks++;
					}
					mask.append ("}");
					stdout.printf ("\t%s e%d=%s;\n\tif(!all(%s_op%d(a,b)==e%d)){return false;}\n", op < 3 ? type : "bool<%d>".printf (lanes), op, op < 3 ? initializer (expected) : mask.str, id, op, op);
				}
				stdout.printf ("\tif(!all(%s_plus(a)==a)){return false;}\n", id);
				lane_checks += lanes;
				if (element.is_signed) {
					var negated = new GenericArray<AstraIntegerValue> ();
					foreach (var value in left) {
						negated.add (value.neg_wrap ());
					}
					stdout.printf ("\t%s n=%s;\n\tif(!all(%s_neg(a)==n)){return false;}\n", type, initializer (negated), id);
					lane_checks += lanes;
				}
				stdout.printf ("\treturn true;\n}\n");
			}
		}
	}
	stdout.printf ("int main(){\n");
	foreach (var name in calls) {
		stdout.printf ("\tif(!%s()){return 1;}\n", name);
	}
	stdout.printf ("\treturn 0;\n}\n// oracle shapes=%d vectors=%u lane_checks=%d\n", shapes, calls.length, lane_checks);
	return 0;
}

}
