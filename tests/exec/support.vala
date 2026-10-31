// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;

namespace Astra.Tests.Exec {
private delegate void TestBody() throws GLib.Error;

private class Case : Object {
	internal TestBody body;
	internal Case (owned TestBody body) {
		this.body = (owned) body;
	}
}

private HashTable<string, Case> cases;

private void add(string path, owned TestBody body) {
	cases.insert (path, new Case ((owned) body));
	Test.add_func (path, () => {
			try {
				cases.lookup (Test.get_path ()).body ();
			} catch (GLib.Error error) {
				GLib.error ("%s failed: %s", Test.get_path (), error.message);
			}
		});
}

private string read(string path) throws FileError {
	string contents;
	FileUtils.get_contents (path, out contents);
	return contents;
}

private class Run : Object {
	internal string output;
	internal string errors;
	internal int status;
	internal Run (string[] argv, string? directory = null, string[]? environment = null) throws SpawnError {
		Process.spawn_sync (directory, argv, environment, (SpawnFlags) 0, null, out output, out errors, out status);
	}
	internal void exits(int expected) {
		if (!Process.if_exited (status) || Process.exit_status (status) != expected) {
			GLib.error ("expected exit %d, wait status %d; stdout: %s; stderr: %s", expected, status, output, errors);
		}
	}
	internal void silent() {
		assert (output == "" && errors == "");
	}
}

private class Workspace : Object {
	internal string directory;
	internal string source;
	internal string executable;
	internal string temporary;

	internal Workspace () throws FileError {
		directory = DirUtils.make_tmp ("astra-exec-test spaces-XXXXXX");
		// Literal shell metacharacters must remain part of argv paths.
		source = Path.build_filename (directory, "input ; $(false) ' file.astra");
		executable = Path.build_filename (directory, "output ; $(false) ' file");
		temporary = Path.build_filename (directory, "controlled tmp");
		assert (DirUtils.create (temporary, 0700) == 0);
	}

	internal Run compile(string text, string[]? options = null) throws GLib.Error {
		FileUtils.set_contents (source, text);
		string[] argv = {
			Environment.get_variable ("ASTRA_TEST_COMPILER")
		};
		if (options == null) {
			argv += source;
			argv += "-o";
			argv += executable;
		} else {
			foreach (string argument in options) {
				argv += argument;
			}
		}
		string[] environment = Environ.set_variable (Environ.get (), "TMPDIR", temporary);
		return new Run (argv, directory, environment);
	}

	internal void clean_temporaries() throws FileError {
		var contents = Dir.open (directory);
		unowned string? name;
		while ((name = contents.read_name ()) != null) {
			assert (!name.has_prefix (".astra-exec-"));
		}
		assert (Dir.open (temporary).read_name () == null);
	}

	~Workspace () {
		FileUtils.unlink (source);
		FileUtils.unlink (executable);
		FileUtils.unlink (Path.build_filename (directory, "a.out"));
		DirUtils.remove (temporary);
		assert (DirUtils.remove (directory) == 0);
	}
}

private void execute(string text, int expected = 0, bool trap = false) throws GLib.Error {
	var workspace = new Workspace ();
	var compiled = workspace.compile (text);
	compiled.exits (0);
	compiled.silent ();
	assert (FileUtils.test (workspace.executable, FileTest.IS_EXECUTABLE));
	workspace.clean_temporaries ();
	// The compiler child and its LLVM resources have already been destroyed.
	var run = new Run ({workspace.executable}, workspace.directory);
	run.silent ();
	if (trap) {
		assert (!Process.if_exited (run.status) && Process.if_signaled (run.status));
		Test.message ("trap terminated abnormally (host signal %d); no exact signal is required", (int) Process.term_sig (run.status));
	} else {
		run.exits (expected);
	}
	workspace.clean_temporaries ();
}

int main(string[] args) {
	Test.init (ref args);
	assert (Environment.get_variable ("ASTRA_TEST_COMPILER") != null);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	register_runtime ();
	register_loops ();
	register_loop_control ();
	register_matrix ();
	register_backend ();
	register_driver ();
	register_shortcircuit ();
	register_c_imports ();
	register_c_exports ();
	register_vapi ();
	register_pointers ();
	register_structs ();
	register_typed_pointers ();
	register_borrows ();
	register_ownership ();
	return Test.run ();
}
}
