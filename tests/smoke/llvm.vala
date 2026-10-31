// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Tests {
int main(string[] args) {
	bool invalid = args.length == 2 && args[1] == "--invalid";
	if (args.length != 1 && !invalid) {
		stderr.printf ("Usage: astra-llvm-smoke [--invalid]\n");
		return 2;
	}

	string? diagnostic;
	bool verified = Backend.LLVM.verify_smoke_module (!invalid, out diagnostic);
	if (invalid) {
		if (verified || diagnostic == null || diagnostic == "") {
			stderr.printf ("LLVM verifier must reject an unterminated block and return a diagnostic.\n");
			return 1;
		}
		stdout.printf ("LLVM verifier rejected the unterminated smoke module: %s", diagnostic);
		return 0;
	}

	if (!verified) {
		stderr.printf ("LLVM smoke module verification failed: %s\n", diagnostic ?? "no diagnostic");
		return 1;
	}
	stdout.printf ("LLVM smoke module constructed and verified: astra_smoke returns i32 0.\n");
	return 0;
}
}
