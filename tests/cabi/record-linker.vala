// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

int main(string[] args) {
	try {
		FileUtils.set_contents (args[1], string.joinv ("\n", args[2 : args.length]));
	} catch (FileError error) {
		stderr.printf ("%s\n", error.message);
		return 1;
	}
	return 37;
}
