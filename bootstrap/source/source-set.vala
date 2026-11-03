// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Source {
public errordomain SourceSetError {
	DUPLICATE_INPUT
}

// Compilation-local file objects are provenance, never semantic namespaces.
public class SourceSet : Object {
	public GenericArray<SourceFile> files { get; private set; default = new GenericArray<SourceFile> (); }

	public static string[] canonical_paths(string[] paths) throws SourceSetError {
		var names = new GLib.List<string> ();
		foreach (string path in paths) {
			names.append (SourceFile.normalize_path (path));
		}
		names.sort ((a, b) => strcmp (a, b));
		string[] result = {};
		foreach (string name in names) {
			if (result.length != 0 && result[result.length - 1] == name) {
				throw new SourceSetError.DUPLICATE_INPUT ("source file '%s' was supplied more than once", name);
			}
			result += name;
		}
		return result;
	}

	public SourceSet (GenericArray<SourceFile> files) throws SourceSetError {
		assert (files.length != 0);
		var ordered = new GLib.List<SourceFile> ();
		foreach (var file in files) {
			ordered.append (file);
		}
		ordered.sort ((a, b) => strcmp (a.path, b.path));
		foreach (var file in ordered) {
			this.files.add (file);
		}
		for (int i = 1; i < this.files.length; i++) {
			if (this.files[i - 1].path == this.files[i].path) {
				throw new SourceSetError.DUPLICATE_INPUT ("source file '%s' was supplied more than once", this.files[i].path);
			}
		}
	}

}
}
