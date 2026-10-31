// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.NonNullSsa {
private SsaProgram sample(string body) throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("nonnull-ssa.astra",
		"class C {int value;init(){this.value=7;}} int use(C input){return input.value;} int f(C input){" + body + "}"));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	var graph = CfgBuilder.build (CoreBuilder.build (checked.program));
	assert (CfgFlowChecker.check (graph).diagnostic == null);
	var program = SsaBuilder.build (graph);
	SsaVerifier.verify (program);
	return program;
}
private SsaFunction function(SsaProgram program, string name) {
	foreach (var definition in program.functions) {
		if (definition.name == name) {
			return definition;
		}
	}
	assert_not_reached ();
}
private void rejected(SsaProgram program) {
	bool failed = false;
	try {
		SsaVerifier.verify (program);
	} catch (SsaError error) {
		Test.message ("%s", error.message);
		failed = error.message.contains ("SSA nonnull contract requires a current non-null proof");
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
			SsaVerifier.verify (program);
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
		SsaVerifier.verify (program);
		foreach (var block in function (program, "f").blocks) {
			foreach (var node in block.instructions) {
				var call = node as SsaCallInstruction;
				if (call == null || call.target.name != "use") {
					continue;
				}
				var argument = call.arguments[0];
				call.arguments[0] = new SsaNullPointerConstant (argument.span, argument.semantic_type);
				rejected (program);
				call.arguments[0] = argument;
				SsaVerifier.verify (program);
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
		SsaVerifier.verify (program);
		var original = function (program, "f");
		var branch = (SsaConditionalBranch) original.entry.terminator;
		var entry = new SsaBlock (original.entry.span, original.entry.ordinal, original.entry.source_ordinal);
		foreach (var instruction in original.entry.instructions) {
			entry.instructions.add (instruction);
		}
		entry.complete (new SsaConditionalBranch (branch.span, branch.condition, branch.false_edge, branch.true_edge));
		var blocks = new GenericArray<SsaBlock> ();
		foreach (var block in original.blocks) {
			blocks.add (block == original.entry ? entry : block);
		}
		var altered = new SsaFunction (original.span, original.name_span, original.name, original.return_type, original.ordinal, original.parameters, blocks, entry);
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
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void retained_local_write() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("nonnull-retained.astra", "class C {int value;} int f(C p){if(p==null){return 0;}C local=p;return local.value;}"));
		var checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.diagnostic == null);
		var graph = CfgBuilder.build (CoreBuilder.build (checked.program));
		foreach (var definition in graph.functions) {
			if (definition.name == "f") {
				foreach (var local in definition.locals) {
					if (local.name == "local") {
						local.mark_nonnull ();
					}
				}
			}
		}
		var program = SsaBuilder.build (graph);
		SsaVerifier.verify (program);
		foreach (var block in function (program, "f").blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var use = block.instructions[i] as SsaNonNullUse;
				if (use == null) {
					continue;
				}
				block.instructions.remove_index (i);
				bool failed = false;
				try {
					SsaVerifier.verify (program);
				} catch (SsaError error) {
					failed = error.message.contains ("retained proof obligation");
				}
				assert (failed);
				block.instructions.insert (i, use);
				SsaVerifier.verify (program);
				block.instructions.remove_index (i);
				block.instructions.add (use);
				failed = false;
				try {
					SsaVerifier.verify (program);
				} catch (SsaError error) {
					failed = error.message.contains ("original write position");
				}
				assert (failed);
				block.instructions.remove_index (block.instructions.length - 1);
				block.instructions.insert (i, use);
				SsaVerifier.verify (program);
				return;
			}
		}
		assert_not_reached ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void promised_result() {
	try {
		var program = sample ("var input_owner=new C();return use(input_owner);");
		function (program, "use").parameters[0].mark_nonnull ();
		SsaVerifier.verify (program);
		// A scalar result cannot manufacture a reference contract by metadata.
		function (program, "f").mark_nonnull_result ();
		bool failed = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			failed = error.message.contains ("nonnull result lost exact");
		}
		assert (failed);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/nonnull-ssa/branch-short-circuit-loop", branch_refinement);
	Test.add_func ("/nonnull-ssa/unproven-join-stale-backedge", reject_unproven);
	Test.add_func ("/nonnull-ssa/argument-reject-restore", argument_restore);
	Test.add_func ("/nonnull-ssa/branch-reject-restore", branch_restore);
	Test.add_func ("/nonnull-ssa/retained-local-write", retained_local_write);
	Test.add_func ("/nonnull-ssa/result-contract-shape", promised_result);
	return Test.run ();
}
}
