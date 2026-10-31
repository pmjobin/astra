// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
int main(string[] args) {
	assert(args.length >= 2);
	string family = args[1];
	// GLib removes parsed options from argv. Borrow the original process strings
	// so removing an option cannot strand an owned copy.
	unowned string[] selected = args[1 : args.length];
	if (family == "gen-copy") {
		return Astra.Tests.GenericCopySemantic.run_semantic(selected);
	}
	if (family == "gen-slice") {
		return Astra.Tests.GenericSliceSemantic.run_semantic(selected);
	}
	if (family == "struct-elements") {
		return Astra.Tests.StructElementsSemantic.run_semantic(selected);
	}
	stderr.printf("unknown test family: %s\n", family);
	return 2;
}
