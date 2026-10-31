// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;

int main(string[] args) {
	if (args.length != 3) {
		return 2;
	}
	int count = int.parse (args[2]);
	try {
		if (args[1] == "wide") {
			var graph = new RuntimeLifetimeEquations ();
			var fields = new HashTable<string, int> (str_hash, str_equal);
			for (int i = 0; i < count; i++) {
				fields.insert ("f%d".printf (i), graph.absent ());
			}
			int root = graph.product (new GenericArray<RuntimeScopeOrigin> (), fields);
			graph.seal ();
			var summary = new RuntimeLifetimeSummary (graph, root, new HashTable<int, int> (direct_hash, direct_equal), new GenericArray<RuntimeLifetimeStore> (), "");
			string encoded = summary.encode ();
			var decoded = RuntimeLifetimeSummary.decode (encoded);
			assert (decoded.encode () == encoded);
			stdout.printf ("wide=%d bytes=%d nodes=%u\n", count, encoded.length, decoded.equations.count);
		} else if (args[1] == "deep") {
			var path = new StringBuilder ();
			for (int i = 0; i < count; i++) {
				if (i != 0) {
					path.append_c ('.');
				}
				path.append ("f0");
			}
			var logical = new GenericArray<int> ();
			logical.add (0);
			var paths = new GenericArray<string> ();
			paths.add (path.str);
			var lengths = new GenericArray<bool> ();
			lengths.add (false);
			var layout = new RuntimeLifetimeLayout (logical, paths, lengths, 1);
			var graph = new RuntimeLifetimeEquations ();
			int root = graph.input (0);
			graph.seal ();
			var summary = new RuntimeLifetimeSummary (graph, root, new HashTable<int, int> (direct_hash, direct_equal), new GenericArray<RuntimeLifetimeStore> (), "");
			var physical = layout.to_physical (summary.logical_archive (), false, new bool[] { true }, new bool[] { false }, new bool[] { false });
			assert (physical.valid () && physical.complete && physical.equations.count <= 65536);
			stdout.printf ("depth=%d nodes=%u\n", count, physical.equations.count);
		} else {
			return 2;
		}
		return 0;
	} catch (RuntimeLifetimeError failure) {
		stderr.printf ("%s\n", failure.message);
		return 1;
	}
}
