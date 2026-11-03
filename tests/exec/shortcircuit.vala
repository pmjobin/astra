// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Tests.Exec {
private const string LOGICAL_HELPERS = "bool false_value(){return false;}bool true_value(){return true;}bool trap_value(){return (1 / 0) == 0;}";
private void logical_case(string name, string expression, bool expected, bool trap = false) {
	add ("/exec/shortcircuit/" + name, () => execute (LOGICAL_HELPERS + "int main(){if((" + expression + ") != " + (expected ? "true" : "false") + "){return 1;}return 0;}", 0, trap));
}

private void logical_truth_table(bool is_and) throws GLib.Error {
	string source = "bool f(bool a,bool b){return a " + (is_and ? "&&" : "||") + " b;}int main(){";
	for (int a = 0; a < 2; a++) {
		for (int b = 0; b < 2; b++) {
			bool expected = is_and ? a != 0 && b != 0 : a != 0 || b != 0;
			source += "if(f(%s,%s) != %s){return %d;}".printf (a != 0 ? "true" : "false", b != 0 ? "true" : "false", expected ? "true" : "false", a * 2 + b + 1);
		}
	}
	execute (source + "return 0;}");
}

private void logical_loops() throws GLib.Error {
	execute (read ("tests/shortcircuit/fixtures/loop-short.astra") + """
int main() {
	if (count(0) != 0 || count(3) != 3 || count(10) != 5) { return 1; }
	if (continue_count(0) != 0 || continue_count(3) != 3 || continue_count(10) != 5) { return 2; }
	if (break_count(0) != 0 || break_count(2) != 2 || break_count(10) != 8) { return 3; }
	return 0;
}
""");
}

private void logical_arguments() throws GLib.Error {
	execute (LOGICAL_HELPERS + """
bool consume(bool a, bool b) { return a == b; }
bool value(bool a) { return a; }
int main() {
	bool x = false_value() && trap_value();
	if (x) { return 1; }
	x = true_value() || trap_value();
	if (!x) { return 2; }
	if (!consume(false_value() && trap_value(), true_value() && false_value())) { return 3; }
	if (!consume(true_value() || trap_value(), false_value() || true_value())) { return 4; }
	if (!consume(value(true), false || value(true))) { return 5; }
	if (!consume((8 / 2) > 0, true && value(true))) { return 6; }
	consume(false && trap_value(), true || trap_value());
	return 0;
}
""");
}

private void register_shortcircuit() {
	add ("/exec/shortcircuit/and-truth-table", () => logical_truth_table (true));
	add ("/exec/shortcircuit/or-truth-table", () => logical_truth_table (false));
	logical_case ("false-and-skips-trap", "false && ((1 / 0) == 0)", false);
	logical_case ("true-or-skips-trap", "true || ((1 / 0) == 0)", true);
	logical_case ("true-and-requires-trap", "true && ((1 / 0) == 0)", false, true);
	logical_case ("false-or-requires-trap", "false || ((1 / 0) == 0)", false, true);
	logical_case ("left-and-always-traps", "((1 / 0) == 0) && false", false, true);
	logical_case ("left-or-always-traps", "((1 / 0) == 0) || true", false, true);
	logical_case ("call-false-and-skips", "false_value() && trap_value()", false);
	logical_case ("call-true-or-skips", "true_value() || trap_value()", true);
	logical_case ("call-true-and-traps", "true_value() && trap_value()", false, true);
	logical_case ("call-false-or-traps", "false_value() || trap_value()", false, true);
	logical_case ("call-left-and-traps", "trap_value() && false", false, true);
	logical_case ("call-left-or-traps", "trap_value() || true", false, true);
	logical_case ("nested-and-or", "true && (false || true)", true);
	logical_case ("nested-or-and", "false || (true && false)", false);
	logical_case ("nested-or-suppresses", "true || (trap_value() && false)", true);
	logical_case ("nested-and-suppresses", "false && (trap_value() || true)", false);
	logical_case ("chain-and-suppresses", "false && trap_value() && trap_value()", false);
	logical_case ("chain-or-suppresses", "true || trap_value() || trap_value()", true);
	add ("/exec/shortcircuit/loops-continue-break", logical_loops);
	add ("/exec/shortcircuit/initializer-assignment-call-arguments", logical_arguments);
	add ("/exec/shortcircuit/continue-fresh-left-skips-final-rhs", () => execute ("int main(){int i = 0;while(i < 3 && 8 / (3 - i) > 0){i = i + 1;continue;}return i;}", 3));
	add ("/exec/shortcircuit/continue-fresh-rhs-traps", () => execute ("int main(){int i = 0;while(i < 4 && 8 / (3 - i) > 0){i = i + 1;continue;}return 9;}", 0, true));
	add ("/exec/shortcircuit/native-artifact-lifetime", () => lifetime (read ("tests/shortcircuit/fixtures/loop-short.astra") + "int main(){return continue_count(10) - 5;}"));
}

}
