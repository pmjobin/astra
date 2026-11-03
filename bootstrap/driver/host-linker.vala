// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Driver {
// One explicit input stream preserves object/library order and repetitions.
public class LinkInput : Object {
	private string value;
	private bool library;
	public LinkInput.object_file (string path) {
		value = path;
		library = false;
	}
	public LinkInput.named_library (string name) {
		assert (valid_library_name (name));
		value = name;
		library = true;
	}
	public static bool valid_library_name(string name) {
		if (name.length == 0 || !name[0].isalnum ()) {
			return false;
		}
		for (int index = 0; index < name.length; index++) {
			char c = name[index];
			if (!c.isalnum () && c != '_' && c != '-' && c != '.') {
				return false;
			}
		}
		return true;
	}

	public string argument(string directory) {
		return library ? "-l" + value : Path.is_absolute (value) ? value : Path.build_filename (directory, value);
	}

}

public class HostLinker : Object {
	// The optional argv is an internal test seam, not compiler CLI/configuration.
	public static void link(string object_path, string executable_path, string[]? driver = null, string[]? link_objects = null, LinkInput[]? link_inputs = null) throws ExecutionError {
		string[] argv = driver == null ? Config.host_linker_argv() : driver;
		string directory = Environment.get_current_dir ();
		argv += Path.is_absolute (object_path) ? object_path : Path.build_filename (directory, object_path);
		if (link_objects != null) {
			foreach (string path in link_objects) {
				argv += Path.is_absolute (path) ? path : Path.build_filename (directory, path);
			}
		}
		if (link_inputs != null) {
			foreach (var input in link_inputs) {
				argv += input.argument (directory);
			}
		}
		argv += "-o";
		argv += Path.is_absolute (executable_path) ? executable_path : Path.build_filename (directory, executable_path);
		string output;
		string errors;
		int status;
		try {
			Process.spawn_sync (null, argv, null, (SpawnFlags) 0, null, out output, out errors, out status);
		} catch (SpawnError error) {
			throw new ExecutionError.LINK ("astrac: error: cannot start host linker '%s': %s", argv[0], error.message);
		}
		if (!Process.if_exited (status) || Process.exit_status (status) != 0) {
			string termination = Process.if_exited (status) ? "exit status %d".printf (Process.exit_status (status)) : "abnormal termination (wait status %d)".printf (status);
			string detail = errors.strip ();
			if (output.strip () != "") {
				detail += (detail == "" ? "" : "\n") + output.strip ();
			}
			throw new ExecutionError.LINK ("astrac: error: host linker '%s' failed (%s)%s%s", argv[0], termination, detail == "" ? "" : ":\n", detail);
		}
	}

}
}
