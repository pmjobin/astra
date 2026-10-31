// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

// Test-only streaming access to the production converter, including a real
// process locale change. This driver adds no conversion behavior of its own.
int main() {
	if (Intl.setlocale (LocaleCategory.ALL, "") == null) {
		return 2;
	}
	string? line;
	while ((line = stdin.read_line ()) != null) {
		var value = Astra.Semantic.AstraF32Value.from_decimal (line);
		if (value == null) {
			return 1;
		}
		stdout.printf ("%08x\n", value.bits);
	}
	return 0;
}
