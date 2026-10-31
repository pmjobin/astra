// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;

// A direct source-built decoder witness, also usable under an external RSS/CPU cap.
int main(string[] args) {
	int prefixes = args.length == 2 ? int.parse (args[1]) : 0;
	var text = new StringBuilder ();
	for (int i = 0; i < prefixes; i++) {
		text.append ("runtime-lifetime-logical/1\n");
	}
	text.append ("runtime-lifetime-summary/1\nr|0\n--\nruntime-lifetime-equations/1\na\n");
	try {
		var summary = RuntimeLifetimeSummary.decode (text.str);
		assert (summary.complete && summary.logical_coordinates == (prefixes == 1));
		stdout.printf ("accepted %d prefixes\n", prefixes);
		return 0;
	} catch (RuntimeLifetimeError failure) {
		stderr.printf ("rejected %d prefixes: %s\n", prefixes, failure.message);
		return 1;
	}
}
