// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Driver {
// Own all temporary paths until a successful same-filesystem rename.
public class ExecutableOutput : Object {
	private string? directory;
	private string final_path;
	private string object_file;
	private string executable_file;
	public string object_path { get { return object_file; } }
	public string executable_path { get { return executable_file; } }

	// Borrow the mutated template, retaining its allocation even on failure.
	[CCode (cname = "g_mkdtemp", cheader_filename = "glib.h")]
	private static extern char* make_directory(char* template);

	public ExecutableOutput (string output_path) throws ExecutionError {
		// Make paths absolute without lexically collapsing symlink/.. pairs.
		final_path = Path.is_absolute (output_path) ? output_path : Path.build_filename (Environment.get_current_dir (), output_path);
		string template = Path.build_filename (Path.get_dirname (final_path), ".astra-exec-XXXXXX");
		if (make_directory ((char*) template) == null) {
			throw new ExecutionError.OUTPUT ("astrac: error: cannot create temporary output beside '%s': %s", output_path, strerror (errno));
		}
		directory = template;
		object_file = Path.build_filename (directory, "program.o");
		executable_file = Path.build_filename (directory, "program");
	}

	~ExecutableOutput () {
		if (directory != null) {
			FileUtils.unlink (object_path);
			FileUtils.unlink (executable_path);
			DirUtils.remove (directory);
		}
	}

	public void link_and_commit(string[]? driver = null, string[]? link_objects = null, LinkInput[]? link_inputs = null) throws ExecutionError {
		HostLinker.link (object_path, executable_path, driver, link_objects, link_inputs);
		if (FileUtils.rename (executable_path, final_path) != 0) {
			throw new ExecutionError.OUTPUT ("astrac: error: cannot publish executable '%s': %s", final_path, strerror (errno));
		}
	}

	public void commit_object() throws ExecutionError {
		if (FileUtils.rename (object_path, final_path) != 0) {
			throw new ExecutionError.OUTPUT ("astrac: error: cannot publish object '%s': %s", final_path, strerror (errno));
		}
	}
}
}
