// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;

namespace Astra.Tests.Exec {
private void loop_recurrence() throws GLib.Error {
	var source = new StringBuilder ("""
int recurrence(int seed, int n, int multiplier, int increment) {
	int x = seed;
	int i = 0;
	while (i < n) {
		x = x * multiplier + increment;
		i = i + 1;
	}
	return x;
}
int main() {
""");
	int64[] seeds = {
		0, 1, -1, AstraIntValue.MIN, AstraIntValue.MAX, 305419896
	};
	int[] counts = {
		0, 1, 2, 7, 31, 1000
	};
	int64[] multipliers = {
		-1, 3, 1664525, AstraIntValue.MAX
	};
	var increment = AstraIntValue.from_int64 (1013904223);
	int checks = 0;
	foreach (int64 seed in seeds) {
		foreach (int n in counts) {
			foreach (int64 multiplier in multipliers) {
				var expected = AstraIntValue.from_int64 (seed);
				var factor = AstraIntValue.from_int64 (multiplier);
				for (int i = 0; i < n; i++) {
					expected = expected.mul_wrap (factor).add_wrap (increment);
				}
				source.append_printf ("\tif (recurrence(%s, %d, %s, %s) != %s) { return %d; }\n", seed.to_string (), n, factor.to_string (), increment.to_string (), expected.to_string (), ++checks);
			}
		}
	}
	source.append ("\treturn 0;\n}\n");
	assert (checks == 144 && checks < 256);
	Test.message ("144 iterative machine results match AstraIntValue wrapping; 6 seeds x 6 counts x 4 multipliers");
	execute (source.str);
}

private void register_loops() {
	add ("/exec/loop/count-zero-one-ten-many", () => execute (read ("tests/loop/fixtures/runtime-count.astra")));
	add ("/exec/loop/accumulate", () => execute (read ("tests/loop/fixtures/accumulate.astra") + """
int main() {
	if (accumulate(0) != 0) { return 1; }
	if (accumulate(1) != 0) { return 2; }
	if (accumulate(2) != 1) { return 3; }
	if (accumulate(10) != 45) { return 4; }
	if (accumulate(1000) != 499500) { return 5; }
	return 0;
}
"""));
	add ("/exec/loop/body-local-reinitialized", () => execute (read ("tests/loop/fixtures/body-local.astra") + "int main(){if(body_local(0) != 0){return 1;}if(body_local(1000) != 1000){return 2;}return 0;}"));
	add ("/exec/loop/bool-even-odd", () => execute (read ("tests/loop/fixtures/bool-carried.astra") + """
int main() {
	if (flip_count(0) != 0) { return 1; }
	if (flip_count(1) != 1) { return 2; }
	if (flip_count(10) != 0) { return 3; }
	if (flip_count(11) != 1) { return 4; }
	if (flip_count(1000) != 0) { return 5; }
	return 0;
}
"""));
	add ("/exec/loop/call-condition-and-body", () => execute (read ("tests/loop/fixtures/call-loop.astra") + "int main(){if(call_loop() != 4){return 1;}return 0;}"));
	add ("/exec/loop/call-body-many", () => execute ("int step(int x){return x + 1;}int run(int n){int x = 0;while(x < n){x = step(x);}return x;}int main(){if(run(0) != 0){return 1;}if(run(1000) != 1000){return 2;}return 0;}"));
	add ("/exec/loop/nested", () => execute (read ("tests/loop/fixtures/nested-loop.astra") + """
int main() {
	if (nested_count(0, 5) != 0) { return 1; }
	if (nested_count(5, 0) != 0) { return 2; }
	if (nested_count(1, 1) != 1) { return 3; }
	if (nested_count(3, 4) != 12) { return 4; }
	if (nested_count(10, 10) != 100) { return 5; }
	return 0;
}
"""));
	add ("/exec/loop/early-return-and-normal-exit", () => execute (read ("tests/loop/fixtures/return-loop.astra") + """
int main() {
	if (find_limit(0) != 0) { return 1; }
	if (find_limit(2) != 2) { return 2; }
	if (find_limit(3) != 3) { return 3; }
	if (find_limit(10) != 3) { return 4; }
	return 0;
}
"""));
	add ("/exec/loop/unreachable", () => execute (read ("tests/loop/fixtures/post-return.astra") + read ("tests/loop/fixtures/body-return-tail.astra") + """
int main() {
	if (post_return(true) != 1) { return 1; }
	if (unreachable_cycle(true) != 3) { return 2; }
	if (body_return_tail(true) != 0) { return 3; }
	if (body_return_tail(false) != 0) { return 4; }
	if (both_return(true, true) != 0) { return 5; }
	if (both_return(true, false) != 2) { return 6; }
	return 0;
}
"""));
	add ("/exec/loop/trap-splits", () => execute (read ("tests/loop/fixtures/trap-loop.astra") + """
int main() {
	if (divide_loop(0, 0) != 64) { return 1; }
	if (divide_loop(3, 2) != 8) { return 2; }
	if (remainder_loop(0, 0) != 64) { return 3; }
	if (remainder_loop(3, 7) != 1) { return 4; }
	if (condition_divide(10, 2) != 1) { return 5; }
	return 0;
}
"""));
	add ("/exec/loop/repeated-condition-trap", () => execute ("int f(){int divisor = 2;while(8 / divisor > 0){divisor = divisor - 1;}return 99;}int main(){return f();}", 0, true));
	add ("/exec/loop/body-trap", () => execute (read ("tests/loop/fixtures/trap-loop.astra") + "int main(){return divide_loop(1, 0);}", 0, true));
	add ("/exec/loop/condition-call-trap-order", () => execute (read ("tests/loop/fixtures/condition-order.astra") + "int main(){if(condition_order(10, 2) != 0){return 1;}return 0;}"));
	add ("/exec/loop/wrapping-differential", loop_recurrence);
	add ("/exec/loop/native-artifact-lifetime", () => lifetime (read ("tests/loop/fixtures/nested-loop.astra") + "int main(){if(nested_count(3, 4) != 12){return 1;}return 0;}"));
}

}
