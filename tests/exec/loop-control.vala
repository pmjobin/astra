// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;

namespace Astra.Tests.Exec {
private string control_source(string name) throws FileError {
	return read ("tests/loopctrl/fixtures/" + name + ".astra");
}

private void control_recurrence() throws GLib.Error {
	var source = new StringBuilder ("""
int recurrence(int seed, int n, int multiplier, int increment) {
	int x = seed;
	int i = 0;
	while (i < n) {
		i = i + 1;
		if (i % 3 == 0) {
			x = x + increment;
			continue;
		}
		x = x * multiplier + increment;
		if (i % 5 == 0) {
			continue;
		}
		x = x - seed;
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
				var initial = AstraIntValue.from_int64 (seed);
				var expected = initial;
				var factor = AstraIntValue.from_int64 (multiplier);
				for (int i = 1; i <= n; i++) {
					if (i % 3 == 0) {
						expected = expected.add_wrap (increment);
						continue;
					}
					expected = expected.mul_wrap (factor).add_wrap (increment);
					if (i % 5 != 0) {
						expected = expected.sub_wrap (initial);
					}
				}
				source.append_printf ("\tif (recurrence(%s, %d, %s, %s) != %s) { return %d; }\n", initial.to_string (), n, factor.to_string (), increment.to_string (), expected.to_string (), ++checks);
			}
		}
	}
	source.append ("\treturn 0;\n}\n");
	assert (checks == 144);
	Test.message ("144 machine results match AstraIntValue: two continue sites, alternate wrapping updates, 6 seeds x 6 counts x 4 factors");
	execute (source.str);
}

private void register_loop_control() {
	add ("/exec/loopctrl/simple-break", () => execute (control_source ("break-basic") + "int main(){if(run() != 7){return 1;}return 0;}"));
	add ("/exec/loopctrl/simple-continue", () => execute (control_source ("continue-basic") + """
int main() {
	if (sum_odds(0) != 0) { return 1; }
	if (sum_odds(1) != 1) { return 2; }
	if (sum_odds(2) != 1) { return 3; }
	if (sum_odds(7) != 16) { return 4; }
	if (sum_odds(1000) != 250000) { return 5; }
	return 0;
}
"""));
	add ("/exec/loopctrl/multiple-continue", () => execute (control_source ("multiple-sites") + """
int main() {
	if (multiple_continue(0) != 0) { return 1; }
	if (multiple_continue(1) != 100) { return 2; }
	if (multiple_continue(2) != 101) { return 3; }
	if (multiple_continue(3) != 111) { return 4; }
	if (multiple_continue(30) != 1110) { return 5; }
	return 0;
}
"""));
	add ("/exec/loopctrl/multiple-break", () => execute (control_source ("multiple-sites") + """
int main() {
	if (multiple_break(0) != 5) { return 1; }
	if (multiple_break(1) != 6) { return 2; }
	if (multiple_break(2) != 10) { return 3; }
	if (multiple_break(3) != 20) { return 4; }
	if (multiple_break(1000) != 20) { return 5; }
	return 0;
}
"""));
	add ("/exec/loopctrl/break-state-zero-and-entered", () => execute (control_source ("break-merge") + control_source ("edge-state") + """
int main() {
	if (break_merge(false) != 0) { return 1; }
	if (break_merge(true) != 1) { return 2; }
	if (zero_break(false) != 5) { return 3; }
	if (zero_break(true) != 10) { return 4; }
	if (break_after(false) != 5) { return 5; }
	if (break_after(true) != 6) { return 6; }
	return 0;
}
"""));
	add ("/exec/loopctrl/continue-state-before-and-after", () => execute (control_source ("continue-merge") + control_source ("edge-state") + """
int main() {
	if (continue_merge(0) != 0) { return 1; }
	if (continue_merge(1) != 20) { return 2; }
	if (continue_merge(2) != 10) { return 3; }
	if (continue_merge(3) != 20) { return 4; }
	if (continue_before(0) != 1) { return 5; }
	if (continue_before(2) != 2) { return 6; }
	if (continue_before(1000) != 1000) { return 7; }
	if (continue_after(0) != 1) { return 8; }
	if (continue_after(2) != 3) { return 9; }
	if (continue_after(1000) != 1001) { return 10; }
	return 0;
}
"""));
	add ("/exec/loopctrl/nested-break", () => execute ("""
int nested_break(int outer_n, int inner_n) {
	int outer = 0;
	int total = 0;
	while (outer < outer_n) {
		int inner = 0;
		while (inner < inner_n) {
			if (inner == 2) { break; }
			total = total + 1;
			inner = inner + 1;
		}
		outer = outer + 1;
	}
	return total;
}
int main() {
	if (nested_break(0, 10) != 0) { return 1; }
	if (nested_break(10, 0) != 0) { return 2; }
	if (nested_break(10, 1) != 10) { return 3; }
	if (nested_break(3, 10) != 6) { return 4; }
	if (nested_break(100, 100) != 200) { return 5; }
	return 0;
}
"""));
	add ("/exec/loopctrl/nested-continue", () => execute ("""
int nested_continue(int outer_n, int inner_n) {
	int outer = 0;
	int total = 0;
	while (outer < outer_n) {
		int inner = 0;
		while (inner < inner_n) {
			inner = inner + 1;
			if (inner % 2 == 0) { continue; }
			total = total + 1;
		}
		outer = outer + 1;
	}
	return total;
}
int main() {
	if (nested_continue(0, 5) != 0) { return 1; }
	if (nested_continue(5, 0) != 0) { return 2; }
	if (nested_continue(3, 5) != 9) { return 3; }
	if (nested_continue(3, 4) != 6) { return 4; }
	if (nested_continue(100, 100) != 5000) { return 5; }
	return 0;
}
"""));
	add ("/exec/loopctrl/nested-both", () => execute (control_source ("nested-loop-control") + "int main(){if(nested_control(0,10) != 0){return 1;}if(nested_control(10,0) != 0){return 2;}if(nested_control(3,10) != 6){return 3;}if(nested_control(10,10) != 8){return 4;}return 0;}"));
	add ("/exec/loopctrl/body-local-availability", () => execute (control_source ("edge-state") + "int main(){if(body_local(0) != 0){return 1;}if(body_local(2) != 11){return 2;}if(body_local(3) != 24){return 3;}if(body_local(100) != 24){return 4;}return 0;}"));
	add ("/exec/loopctrl/calls-and-unreachable-tails", () => execute (control_source ("unreachable") + """
int main() {
	if (break_tail(false) != 0) { return 1; }
	if (break_tail(true) != 1) { return 2; }
	if (continue_tail(0) != 0) { return 3; }
	if (continue_tail(4) != 4) { return 4; }
	if (distinct(true, true, false) != 1) { return 5; }
	if (distinct(true, false, true) != 2) { return 6; }
	if (distinct(false, true, true) != 2) { return 7; }
	return 0;
}
"""));
	add ("/exec/loopctrl/condition-call-reevaluated", () => execute ("bool less(int i,int n){return i < n;}int f(){int i = 0;while(less(i,10)){i = i + 1;continue;}return i;}int main(){if(f() != 10){return 1;}return 0;}"));
	add ("/exec/loopctrl/trap-splits", () => execute (control_source ("trap-control") + """
int main() {
	if (trap_continue(0, 0) != 64) { return 1; }
	if (trap_continue(1, 0) != 63) { return 2; }
	if (trap_continue(2, 2) != 31) { return 3; }
	if (trap_continue(3, 2) != 30) { return 4; }
	if (trap_break(0, 0) != 64) { return 5; }
	if (trap_break(2, 2) != 32) { return 6; }
	if (trap_break(10, 7) != 6) { return 7; }
	return 0;
}
"""));
	add ("/exec/loopctrl/trap-before-continue", () => execute (control_source ("trap-control") + "int main(){return trap_continue(2,0);}", 0, true));
	add ("/exec/loopctrl/trap-before-break", () => execute (control_source ("trap-control") + "int main(){return trap_break(2,0);}", 0, true));
	add ("/exec/loopctrl/repeated-header-trap", () => execute ("int main(){int d = 2;while(8 / d > 0){d = d - 1;continue;}return 99;}", 0, true));
	add ("/exec/loopctrl/wrapping-differential", control_recurrence);
	add ("/exec/loopctrl/native-artifact-lifetime", () => lifetime (control_source ("nested-loop-control") + "int main(){if(nested_control(3,10) != 6){return 1;}return 0;}"));
}
}
