// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
int main(string[] args) {
	assert(args.length >= 2);
	string family = args[1];
	// GLib removes parsed options from argv. Borrow the original process strings
	// so removing an option cannot strand an owned copy.
	unowned string[] selected = args[1 : args.length];
	if (family == "gen-buffer") {
		return Astra.Tests.GenericBufferCore.run_cfg(selected);
	}
	if (family == "gen-copy") {
		return Astra.Tests.GenericCopyCore.run_cfg(selected);
	}
	stderr.printf("unknown test family: %s\n", family);
	return 2;
}
