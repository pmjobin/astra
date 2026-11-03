// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;

namespace Astra.Tests.ObjectResultOwnership {
private CfgProgram cfg(string text) throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("flow", text));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	return CfgBuilder.build (CoreBuilder.build (checked.program));
}

private void nullable() {
	try {
		var p = cfg ("class C{init(){}}owned C make(){return null;}void sink(owned C c){}void f(){owned C c=make();bool absent=c==null;sink(move c);}");
		assert (CfgFlowChecker.check (p).diagnostic == null);
		assert (OwnershipState.OWNED.definitely_owned () && !OwnershipState.MOVED.definitely_owned ());
		foreach (var use in new string[] { "bool b=c==null;", "sink(move c);" }) {
			var invalid = cfg ("class C{init(){}}owned C make(){return null;}void sink(owned C c){}void f(){owned C c=make();sink(move c);" + use + "}");
			assert (CfgFlowChecker.check (invalid).diagnostic.message.contains ("moved owned value 'c'"));
		}
		var branch = cfg ("class C{init(){}}owned C make(){return null;}void sink(owned C c){}void f(bool b){owned C c=make();if(b){sink(move c);}bool absent=c==null;}");
		assert (CfgFlowChecker.check (branch).diagnostic.message.contains ("may have been moved"));
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}

private void transfer() {
	try {
		var p = cfg ("class C{init(){}deinit(){}}owned C identity(owned C c){return move c;}");
		assert (CfgFlowChecker.check (p).diagnostic == null);
		var f = p.functions[0];
		assert (f.entry.instructions[0] is CfgAcquireParameter && f.entry.instructions[1] is CfgOwnershipReturnInstruction && f.entry.instructions[2] is CfgCleanupInstruction);
		assert (((CfgOwnershipReturnInstruction) f.entry.instructions[1]).result.source == f.locals[0]);
		assert (f.object_storage.length == 0 && f.result_storage != null);
		var invalid = cfg ("class C{}void sink(owned C c){}owned C f(owned C c){sink(move c);return move c;}");
		assert (CfgFlowChecker.check (invalid).diagnostic.message.contains ("moved owned value 'c'"));
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-ret/ownership/owned-null-versus-moved-and-branch-join", nullable);
	Test.add_func ("/obj-ret/ownership/parameter-disarm-before-root-cleanup", transfer);
	return Test.run ();
}

}
