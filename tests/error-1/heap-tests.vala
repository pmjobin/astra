// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.HeapObjects {
private CheckedProgram check(string text) {
	var parsed = Parser.parse (new SourceFile.from_text ("heap", text));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.message);
	}
	return checked.program;
}

private string source() {
	return "class Box{int value;init(int value){this.value=value;}property int item{get{return this.value;}}}int read(Box b){return b.item;}int main(){var first=new Box(42);owned Box second=move first;return read(second);}";
}

private void origins() {
	try {
		var checked = check (source ());
		var local = checked.functions[1].locals[0];
		assert (local.heap_object && local.object_storage.heap_allocated && local.is_owned);
		var core = CoreBuilder.build (checked);
		assert (core.functions[1].object_storage[0].heap_allocated);
		assert (core.functions[1].owned_locals[0].cleanup.is_heap_object);
		assert (core.functions[1].owned_locals[1].cleanup == core.functions[1].owned_locals[0].cleanup);
		var cfg = CfgBuilder.build (core);
		assert (cfg.functions[1].object_storage[0].heap_allocated);
		var ssa = SsaBuilder.build (cfg);
		assert (ssa.functions[1].object_storage[0].heap_allocated);
		SsaVerifier.verify (ssa);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void legacy() {
	try {
		var checked = check ("class Box{int value;init(int value){this.value=value;}}int main(){owned Box b=Box.init(42);return b.value;}");
		assert (!checked.functions[0].locals[0].heap_object);
		var core = CoreBuilder.build (checked);
		assert (!core.functions[0].object_storage[0].heap_allocated);
		assert (!core.functions[0].owned_locals[0].cleanup.is_heap_object);
		SsaVerifier.verify (SsaBuilder.build (CfgBuilder.build (core)));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void wrong_storage() {
	try {
		var core = CoreBuilder.build (check (source ()));
		CoreVerifier.verify (core);
		core.functions[1].object_storage[0].heap_allocated = false;
		bool rejected = false;
		try {
			CoreVerifier.verify (core);
		} catch (CoreError error) {
			rejected = error.message.contains ("exact fresh ObjectStorage");
		}
		assert (rejected);
		core.functions[1].object_storage[0].heap_allocated = true;
		CoreVerifier.verify (core);
		var cfg = CfgBuilder.build (core);
		CfgVerifier.verify (cfg);
		cfg.functions[1].object_storage[0].heap_allocated = false;
		rejected = false;
		try {
			CfgVerifier.verify (cfg);
		} catch (CfgError error) {
			rejected = error.message.contains ("exact fresh published ObjectStorage");
		}
		assert (rejected);
		cfg.functions[1].object_storage[0].heap_allocated = true;
		CfgVerifier.verify (cfg);
		var ssa = SsaBuilder.build (cfg);
		SsaVerifier.verify (ssa);
		ssa.functions[1].object_storage[0].heap_allocated = false;
		rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			rejected = error.message.contains ("allocation domain");
		}
		assert (rejected);
		ssa.functions[1].object_storage[0].heap_allocated = true;
		SsaVerifier.verify (ssa);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void unsupported_escapes() {
	foreach (string body in new string[] {"Box b=new Box(1);", "var b=new Box(1);Box copy=b;", "var b=new Box(1);consume(move b);return b.value;", "var b=new Box(1);var c=move b;return b.value;", "var b=new Box(1);owned Box b=move b;"}) {
		var parsed = Parser.parse (new SourceFile.from_text ("invalid", "class Box{int value;init(int n){this.value=n;}}void consume(owned Box b){}int main(){" + body + "return 0;}"));
		assert (parsed.diagnostic == null);
		var checked = SemanticAnalyzer.analyze (parsed.unit);
		if (checked.diagnostic != null) {
			continue;
		}
		bool rejected = false;
		try {
			SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (checked.program)));
		} catch (GLib.Error error) {
			rejected = true;
		}
		assert (rejected);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/error-1/heap/exact-storage-owner-move-and-borrow", origins);
	Test.add_func ("/error-1/heap/legacy-lexical-init-preserved", legacy);
	Test.add_func ("/error-1/heap/wrong-domain-rejected-and-restored", wrong_storage);
	Test.add_func ("/error-1/heap/unsupported-alias-consumer-and-double-use", unsupported_escapes);
	return Test.run ();
}

}
