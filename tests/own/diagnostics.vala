// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;

namespace Astra.Tests.Ownership {
private void reject(string source, string message) {
	var result = analyze (source);
	assert (result.program == null && result.diagnostic != null);
	if (!result.diagnostic.message.contains (message)) {
		GLib.error ("expected '%s', got %s", message, result.diagnostic.format ());
	}
	assert (result.diagnostic.format () == analyze (source).diagnostic.format ());
	Test.message ("%s", result.diagnostic.format ());
}

private void register_diagnostics() {
	add ("/own/invalid/extern-owned-void-result", () => reject ("extern(C) owned void* f();", "nominal handle type"));
	foreach (string type in new string[] {"int", "bool", "Pair", "Pair*", "void"}) {
		add ("/own/invalid/type-" + type, () => reject ("struct Pair { int x; } void f() { owned " + type + " h = create(1); }", "only on local 'void*'"));
	}
	foreach (string source in new string[] {"void f(owned void* h) {}", "owned void* f() { return null; }", "struct Pair { owned void* h; }"}) {
		add ("/own/invalid/syntax/" + source, () => {
				var parsed = Parser.parse (new SourceFile.from_text ("invalid.astra", source));
				// Owning record fields now parse; raw pointers still lack a nominal cleanup contract.
				assert (parsed.unit != null);
				if (source.has_prefix ("struct")) {
					reject (source, "owned fields require an exact nominal Resource");
				} else { reject (source, "nominal handle type");
				}
			});
	}
	foreach (string source in new string[] {"void* p = create(1);", "create(1);", "use(create(1));", "use((create(1)));", "bool b = create(1) == null;", "bool b = true || create(1) == null;", "void* p = (create(1));"}) {
		add ("/own/invalid/result/" + source, () => reject ("void f() { " + source + " }", "result carries ownership responsibility"));
	}
	add ("/own/invalid/result-return", () => reject ("void* f() { return (create(1)); }", "result carries ownership responsibility"));
	foreach (string initializer in new string[] {"raw()", "null", "effect()"}) {
		add ("/own/invalid/initializer-" + initializer, () => reject ("void f() { owned void* h = " + initializer + "; }", initializer == "effect()" ? "expected initializer" : "requires a direct foreign owned-result"));
	}
	foreach (string source in new string[] {"owned void* b = h;", "void* b = h;", "use(h);", "use((h));", "return h;", "return (h);", "bool b = h == h;", "bool b = h != raw();", "bool b = h == create(1);"}) {
		add ("/own/invalid/local/" + source, () => reject ("void* f() { owned void* h = create(1); " + source + " return null; }", "cannot be copied, returned, or passed to calls"));
	}
	add ("/own/invalid/reassignment", () => reject ("void f() { owned void* h = create(1); h = null; }", "rearming requires a direct foreign owned-result call"));
	add ("/own/invalid/self-initialization", () => reject ("void f() { owned void* h = create(h); }", "unknown name 'h'"));
	add ("/own/invalid/nested-acquire-argument", () => reject ("void f() { owned void* h = create(effect() + create(1)); }", "result carries ownership responsibility"));
	foreach (string comparison in new string[] {"h == null", "h != null", "null == h", "null != h", "((h)) == (null)", "null != h && h != null", "h == null || null == h"}) {
		add ("/own/null-comparison/" + comparison, () => {
				var program = check ("bool f() { owned void* h = ((create(1))); return " + comparison + "; }");
				assert (program.functions[0].locals[0].ownership_kind == OwnershipKind.OWNED);
			});
	}
}

}
