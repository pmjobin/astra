// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

int main(string[] args) {
	assert (args.length == 4 && args[2] == "-o");
	try {
		FileUtils.set_contents (args[3], "partial link output");
	} catch (FileError error) {
		GLib.error ("cannot create failure fixture: %s", error.message);
	}
	stdout.printf ("linker fixture stdout\n");
	stderr.printf ("linker fixture stderr\n");
	return 37;
}
