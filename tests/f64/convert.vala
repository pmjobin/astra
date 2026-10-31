// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;

// Streaming test access; parsing integer bits is not floating conversion.
int main() {
	if (Intl.setlocale (LocaleCategory.ALL, "") == null) {
		return 2;
	}
	string? line;
	while ((line = stdin.read_line ()) != null) {
		string[] fields = line.split (" ");
		BinaryFloatValue? value;
		if (fields[0] == "decimal") {
			value = BinaryFloatValue.from_decimal (BinaryFloatFormat.BINARY64, fields[1]);
		} else {
			var source = fields[0] == "widen" ? BinaryFloatFormat.BINARY32 : BinaryFloatFormat.BINARY64;
			value = new BinaryFloatValue.from_bits (source, uint64.parse (fields[1], 16));
			value = value.converted (source == BinaryFloatFormat.BINARY32 ? BinaryFloatFormat.BINARY64 : BinaryFloatFormat.BINARY32);
		}
		if (value == null) {
			return 1;
		}
		stdout.printf ("%s\n", value.to_string ());
	}
	return 0;
}
