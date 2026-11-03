// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;

namespace Astra.Tests.NonNullCfg {
private CfgProgram sample(string body) throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("nonnull-cfg.astra",
		"class C {int value;init(){this.value=7;}} int use(C input){return input.value;} int f(C input){" + body + "}"));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	var program = CfgBuilder.build (CoreBuilder.build (checked.program));
	CfgVerifier.verify (program);
	return program;
}

private CfgFunction function(CfgProgram program, string name) {
	foreach (var definition in program.functions) {
		if (definition.name == name) {
			return definition;
		}
	}
	assert_not_reached ();
}

private void rejected(CfgProgram program) {
	bool failed = false;
	try {
		CfgVerifier.verify (program);
	} catch (CfgError error) {
		Test.message ("%s", error.message);
		failed = error.message.contains ("CFG nonnull contract requires a current non-null proof");
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
			CfgVerifier.verify (program);
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
		CfgVerifier.verify (program);
		foreach (var block in function (program, "f").blocks) {
			foreach (var node in block.instructions) {
				var call = node as CfgCallInstruction;
				if (call == null || call.target.name != "use") {
					continue;
				}
				var argument = call.arguments[0];
				call.arguments[0] = new CfgNullPointerValue (argument.span, argument.semantic_type);
				rejected (program);
				call.arguments[0] = argument;
				CfgVerifier.verify (program);
				return;
			}
		}
		assert_not_reached ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void branch_restore() {
	try {
		var program = sample ("if(input!=null){return use(input);}return 0;");
		function (program, "use").parameters[0].mark_nonnull ();
		CfgVerifier.verify (program);
		var original = function (program, "f");
		var branch = (CfgConditionalBranch) original.entry.terminator;
		var entry = new CfgBlock (original.entry.span, original.entry.ordinal, original.entry.instructions,
			new CfgConditionalBranch (branch.span, branch.condition, branch.false_target, branch.true_target));
		var blocks = new GenericArray<CfgBlock> ();
		foreach (var block in original.blocks) {
			blocks.add (block == original.entry ? entry : block);
		}
		var altered = new CfgFunction (original.span, original.name_span, original.name, original.return_type, original.ordinal, original.parameters, original.locals, blocks, entry);
		int index = -1;
		for (int i = 0; i < program.functions.length; i++) {
			if (program.functions[i] == original) {
				index = i;
			}
		}
		assert (index >= 0);
		program.functions[index] = altered;
		rejected (program);
		program.functions[index] = original;
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void promised_result() {
	try {
		var program = sample ("var input_owner=new C();return use(input_owner);");
		function (program, "use").parameters[0].mark_nonnull ();
		CfgVerifier.verify (program);
		// A scalar result cannot manufacture a reference contract by metadata.
		function (program, "f").mark_nonnull_result ();
		bool failed = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			failed = error.message.contains ("nonnull result lost exact");
		}
		assert (failed);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/nonnull-cfg/branch-short-circuit-loop", branch_refinement);
	Test.add_func ("/nonnull-cfg/unproven-join-stale-backedge", reject_unproven);
	Test.add_func ("/nonnull-cfg/argument-reject-restore", argument_restore);
	Test.add_func ("/nonnull-cfg/branch-reject-restore", branch_restore);
	Test.add_func ("/nonnull-cfg/result-contract-shape", promised_result);
	return Test.run ();
}

}
