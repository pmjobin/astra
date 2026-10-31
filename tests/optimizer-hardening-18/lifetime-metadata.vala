// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;

namespace Astra.Tests.Metadata18 {
private void reject(string text) {
	bool refused = false;
	try {
		RuntimeLifetimeSummary.decode (text);
	} catch (RuntimeLifetimeError failure) {
		refused = true;
		Test.message ("%s", failure.message);
	}
	assert (refused);
}
private void malformed() {
	string prefix = "runtime-lifetime-summary/1\nr|0\n--\n";
	reject (prefix + "runtime-lifetime-equations/1\na");
	reject (prefix + "runtime-lifetime-equations/1\na\nj|99\n");
	reject (prefix + "runtime-lifetime-equations/1\na\nq|0|f00\n");
	reject (prefix + "runtime-lifetime-equations/1\na\np|-1||\n");
	reject ("runtime-lifetime-summary/1\nr|-1\n--\nruntime-lifetime-equations/1\na\n");
	reject ("runtime-lifetime-logical/1\nruntime-lifetime-summary/1:incomplete");
	reject ("runtime-lifetime-logical/1\nruntime-lifetime-logical/1\n" + prefix);
	reject ("runtime-lifetime-summary/2\nr|0\ne|99\n--\nruntime-lifetime-equations/1\na\n");
}
private void oversized() {
	var text = new StringBuilder ();
	string chunk = string.nfill (1024, 'x');
	for (int i = 0; i < 8192; i++) {
		text.append (chunk);
	}
	text.append_c ('x');
	reject (text.str);
}
private void maximum_inventory() {
	try {
		var graph = new RuntimeLifetimeEquations ();
		int root = graph.absent ();
		for (int i = 1; i < 65536; i++) {
			var fields = new HashTable<string, int> (str_hash, str_equal);
			fields.insert ("f0", root);
			root = graph.product (new GenericArray<RuntimeScopeOrigin> (), fields);
		}
		graph.seal ();
		var summary = new RuntimeLifetimeSummary (graph, root,
			new HashTable<int, int> (direct_hash, direct_equal), new GenericArray<RuntimeLifetimeStore> (), "");
		string encoded = summary.logical_archive ().encode ();
		var decoded = RuntimeLifetimeSummary.decode (encoded);
		assert (decoded.logical_coordinates && decoded.complete && decoded.equations.count == 65536);
		assert (decoded.encode () == encoded);
		assert (decoded.equations.requirements (decoded.result).length == 0);
	} catch (RuntimeLifetimeError failure) {
		error ("%s", failure.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/metadata18/malformed", malformed);
	Test.add_func ("/metadata18/oversized", oversized);
	Test.add_func ("/metadata18/maximum-inventory-and-depth", maximum_inventory);
	return Test.run ();
}
}
