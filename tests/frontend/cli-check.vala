// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Tests.Frontend {
private string expected_text(string path) throws FileError {
	if (path == "-") {
		return "";
	}
	string text;
	FileUtils.get_contents (path, out text);
	return text;
}

int main(string[] args) {
	if (args.length < 7) {
		stderr.printf ("Usage: cli-check ASTRAC MODE INPUT STDOUT_FILE STDERR_FILE STATUS [OPTIONS...]\n");
		return 2;
	}
	try {
		string output;
		string errors;
		int status;
		string[] command = {
			args[1], args[2], args[3]
		};
		for (int i = 7; i < args.length; i++) {
			command += args[i];
		}
		Process.spawn_sync (null, command, null, (SpawnFlags) 0, null, out output, out errors, out status);
		if (!Process.if_exited (status) || Process.exit_status (status) != int.parse (args[6])) {
			stderr.printf ("Unexpected process status %d; expected exit %s.\n%s", status, args[6], errors);
			return 1;
		}
		string expected_output = expected_text (args[4]);
		string expected_errors = expected_text (args[5]);
		if (output != expected_output || errors != expected_errors) {
			stderr.printf ("stdout expected:\n%sstdout actual:\n%sstderr expected:\n%sstderr actual:\n%s", expected_output, output, expected_errors, errors);
			return 1;
		}
		return 0;
	} catch (GLib.Error error) {
		stderr.printf ("CLI test failed: %s\n", error.message);
		return 1;
	}
}
}
