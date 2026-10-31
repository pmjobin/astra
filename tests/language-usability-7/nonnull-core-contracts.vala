// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.NonNullCore {
private CoreProgram sample(string body) throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("nonnull-core.astra",
		"class C {int value;init(){this.value=7;}} int use(C input){return input.value;} int f(C input){" + body + "}"));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	var program = CoreBuilder.build (checked.program);
	CoreVerifier.verify (program);
	return program;
}
private CoreFunction function(CoreProgram program, string name) {
	foreach (var definition in program.functions) {
		if (definition.name == name) {
			return definition;
		}
	}
	assert_not_reached ();
}
private void rejected(CoreProgram program) {
	bool failed = false;
	try {
		CoreVerifier.verify (program);
	} catch (CoreError error) {
		Test.message ("%s", error.message);
		failed = error.message.contains ("nonnull contract requires a current non-null proof");
	}
	assert (failed);
}
private void branch_refinement() {
	try {
		foreach (string body in new string[] {
				"if(input!=null){return use(input);}return 0;",
				"if(input==null){return 0;}return use(input);",
				"if(input!=null && use(input)==7){return 1;}return 0;",
				"if(input==null || use(input)==7){return 1;}return 0;",
				"while(input!=null){return use(input);}return 0;",
				"if(input!=null && true){return use(input);}return 0;",
				"if(input==null || false){return 0;}return use(input);"
			}) {
			var program = sample (body);
			function (program, "use").parameters[0].mark_nonnull ();
			CoreVerifier.verify (program);
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void reject_unproven() {
	try {
		foreach (string body in new string[] {
				"return use(input);",
				"if(input!=null){use(input);}return use(input);",
				"C local=input;bool prior=local!=null;local=null;if(prior){return use(local);}return 0;",
				"C local=input;if(local==null){return 0;}while(true){use(local);local=null;}return 1;"
			}) {
			var program = sample (body);
			function (program, "use").parameters[0].mark_nonnull ();
			rejected (program);
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void argument_restore() {
	try {
		var program = sample ("if(input!=null){return use(input);}return 0;");
		function (program, "use").parameters[0].mark_nonnull ();
		CoreVerifier.verify (program);
		var branch = (CoreIf) function (program, "f").body.statements[0];
		var call = (CoreCallValue) ((CoreReturn) branch.then_block.statements[0]).value;
		var argument = call.arguments[0];
		call.arguments[0] = new CoreNullPointerValue (argument.span, argument.semantic_type);
		rejected (program);
		call.arguments[0] = argument;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void promised_result() {
	try {
		var program = sample ("var input_owner=new C();return use(input_owner);");
		function (program, "use").parameters[0].mark_nonnull ();
		CoreVerifier.verify (program);
		// A scalar result cannot manufacture a reference contract by metadata.
		function (program, "f").mark_nonnull_result ();
		bool failed = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			failed = error.message.contains ("nonnull result requires an exact native");
		}
		assert (failed);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/nonnull-core/branch-short-circuit-loop", branch_refinement);
	Test.add_func ("/nonnull-core/unproven-join-stale-backedge", reject_unproven);
	Test.add_func ("/nonnull-core/argument-reject-restore", argument_restore);
	Test.add_func ("/nonnull-core/result-contract-shape", promised_result);
	return Test.run ();
}
}
