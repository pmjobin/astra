// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Tests.Exec {
private void runtime_case(string name, string text) {
	add ("/exec/runtime/" + name, () => execute (text));
}

private void register_runtime() {
	add ("/exec/runtime/exit-zero", () => execute (read ("tests/exec/fixtures/exit-zero.astra")));
	add ("/exec/runtime/exit-42", () => execute (read ("tests/exec/fixtures/exit-42.astra"), 42));
	runtime_case ("wrapping", """
int add(int a, int b) { return a + b; }
int sub(int a, int b) { return a - b; }
int mul(int a, int b) { return a * b; }
int neg(int a) { return -a; }
int main() {
	if (add(2147483647, 1) != -2147483648) { return 1; }
	if (sub(-2147483648, 1) != 2147483647) { return 2; }
	if (mul(1073741824, 3) != -1073741824) { return 3; }
	if (mul(65536, 65536) != 0) { return 4; }
	if (neg(-2147483648) != -2147483648) { return 5; }
	return 0;
}
""");
	runtime_case ("signed-comparisons", """
bool less(int a, int b) { return a < b; }
bool greater(int a, int b) { return a > b; }
int main() {
	if (!less(-1, 0)) { return 1; }
	if (!less(-2147483648, 2147483647)) { return 2; }
	if (!greater(0, -1)) { return 3; }
	return 0;
}
""");
	foreach (string op in new string[] {"/", "%"}) {
		string name = op == "/" ? "division" : "remainder";
		string results = op == "/" ? "2, -2, -2, 2" : "1, -1, 1, -1";
		string[] expected = results.split (", ");
		string text = "int operation(int a, int b) { return a " + op + " b; }\nint main() {\n";
		string[] arguments = {
			"7, 3", "-7, 3", "7, -3", "-7, -3"
		};
		for (int i = 0; i < arguments.length; i++) {
			text += "\tif (operation(%s) != %s) { return %d; }\n".printf (arguments[i], expected[i], i + 1);
		}
		runtime_case (name, text + "\treturn 0;\n}\n");
		runtime_case (name + "-int-min", "int operation(int a, int b) { return a " + op + " b; } int main() { if (operation(-2147483648, -1) != " + (op == "/" ? "-2147483648" : "0") + ") { return 1; } return 0; }");
		string trapping = "int operation(int a, int b) { return a " + op + " b; } int main() { operation(7, 0); return 99; }";
		add ("/exec/runtime/" + name + "-zero-trap", () => execute (trapping, 0, true));
	}
	add ("/exec/runtime/bool", () => execute (read ("tests/llvm/fixtures/bool-phi.astra") + """
bool compare(int a, int b) { return a < b; }
bool invert(bool x) { return !x; }
int main() {
	if (!choose_bool(true, true, false)) { return 1; }
	if (choose_bool(false, true, false)) { return 2; }
	if (!choose_bool(false, false, true)) { return 3; }
	if (invert(true)) { return 4; }
	if (!invert(false)) { return 5; }
	if (!choose_bool(compare(-1, 0), true, false)) { return 6; }
	if (compare(0, -1) != false) { return 7; }
	return 0;
}
"""));
	add ("/exec/runtime/choose-ssa", () => execute (read ("tests/branch/fixtures/choose.astra") + "int main() { if (choose(true, 7, 9) != 7) { return 1; } if (choose(false, 7, 9) != 9) { return 2; } return 0; }"));
	runtime_case ("direct-call", "int sum(int a, int b) { return a + b; } int main() { if (sum(17, 25) != 42) { return 1; } return 0; }");
	add ("/exec/runtime/forward-call", () => execute (read ("tests/call/fixtures/forward-call.astra") + "int main() { if (first(41) != 42) { return 1; } return 0; }"));
	add ("/exec/runtime/self-recursion", () => execute (read ("tests/call/fixtures/recursion.astra") + "int main() { return recurse(8); }"));
	add ("/exec/runtime/mutual-recursion", () => execute (read ("tests/call/fixtures/mutual-recursion.astra") + "int main() { if (first(8) != 0) { return 1; } return second(7); }"));
	runtime_case ("main-recursion", "int main() { if (false) { return main(); } return 0; }");
	add ("/exec/runtime/choose-call", () => execute (read ("tests/call/fixtures/choose-call.astra") + "int main() { if (choose_call(true, 7, 9) != 8) { return 1; } if (choose_call(false, 7, 9) != 10) { return 2; } return 0; }"));
	add ("/exec/runtime/division-ssa", () => execute (read ("tests/llvm/fixtures/division-phi.astra") + "int main() { if (split_join(true, -7, 3) != -2) { return 1; } if (split_join(false, -7, 3) != -1) { return 2; } if (split_join(true, -2147483648, -1) != -2147483648) { return 3; } return 0; }"));
}

}
