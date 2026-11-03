// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Driver;

namespace Astra.Tests.BaseLink {
private string recorder;
private string record_path;
private void grammar() {
	foreach (string name in new string[] {"m", "a_b-1.2", "stdc++", "", "-m", "/tmp/m", "../m", ".hidden", "a/b", "a\\b", "a b", "a\nm", "a\tm", "-Wl,anything", ":libm.so", "m;true", "$(true)", "é"}) {
		assert (LinkInput.valid_library_name (name) == (name == "m" || name == "a_b-1.2"));
	}
}

private void order() {
	try {
		LinkInput[] inputs = {
			new LinkInput.object_file ("first ; $(false).o"), new LinkInput.named_library ("m"), new LinkInput.object_file ("second.o"), new LinkInput.named_library ("m"), new LinkInput.named_library ("c"), new LinkInput.object_file ("second.o")
		};
		try {
			HostLinker.link ("generated.o", "output", {recorder, record_path}, null, inputs);
			assert_not_reached ();
		} catch (ExecutionError.LINK error) {
			assert (error.message.contains ("exit status 37"));
		}
		string actual;
		FileUtils.get_contents (record_path, out actual);
		string directory = Environment.get_current_dir ();
		string expected = directory + "/generated.o\n" + directory + "/first ; $(false).o\n-lm\n" + directory + "/second.o\n-lm\n-lc\n" + directory + "/second.o\n-o\n" + directory + "/output";
		assert (actual == expected);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	recorder = args[1];
	record_path = args[2];
	Test.init (ref args);
	Test.add_func ("/baselib/link-library/grammar", grammar);
	Test.add_func ("/baselib/link-library/interleaved-order-repetitions-shell-free", order);
	return Test.run ();
}

}
