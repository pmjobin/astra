// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.With {
private CheckedProgram sample() {
	var parsed = Parser.parse (new SourceFile.from_text ("with-contract.astra",
		"class C {int value; init(){this.value=7;}} int f(){var c=new C();int answer=0;with(c){answer=c.value;}return answer;}"));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	return checked.program;
}
private CheckedFunction checked_function(CheckedProgram program) {
	foreach (var function in program.functions) {
		if (function.symbol.name == "f") {
			return function;
		}
	}
	assert_not_reached ();
}
private CoreFunction core_function(CoreProgram program) {
	foreach (var function in program.functions) {
		if (function.name == "f") {
			return function;
		}
	}
	assert_not_reached ();
}
private void checked_capture() {
	try {
		var program = sample ();
		var function = checked_function (program);
		var scoped = (CheckedWithScope) ((CheckedBlockStatement) function.body.statements[2]).statements[0];
		var field = (CheckedLoadExpression) ((CheckedAssignment) scoped.statements[0]).expression;
		var reference = (CheckedWithReference) ((CheckedObjectFieldPlace) field.source).reference;
		var contract = reference.contract;
		reference.contract = new CheckedWithContract (reference.span, contract.source);
		bool rejected = false;
		try {
			CoreBuilder.build (program);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		reference.contract = contract;
		CoreVerifier.verify (CoreBuilder.build (program));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void core_capture() {
	try {
		var program = CoreBuilder.build (sample ());
		CoreVerifier.verify (program);
		var function = core_function (program);
		var scoped = (CoreWithScope) ((CoreScope) function.body.statements[2]).body.statements[0];
		var field = (CoreLoadValue) ((CoreStore) scoped.body.statements[0]).value;
		var reference = (CoreWithReference) ((CoreIndirectFieldPlace) field.source).pointer;
		var contract = reference.contract;
		reference.contract = new CoreWithContract (reference.span, contract.source, contract.receiver_type);
		bool rejected = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		reference.contract = contract;
		CoreVerifier.verify (program);
		var observation = scoped.body.statements[0];
		function.body.statements.insert (3, observation);
		rejected = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		function.body.statements.remove_index (3);
		CoreVerifier.verify (program);
		CoreOwnedLocal? owner = null;
		foreach (var candidate in function.owned_locals) {
			if (candidate.place == scoped.source) {
				owner = candidate;
			}
		}
		assert (owner != null);
		scoped.body.statements.insert (0, new CoreOwnershipRelease (scoped.span, owner, owner.cleanup));
		rejected = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		scoped.body.statements.remove_index (0);
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void cfg_capture() {
	try {
		var program = CfgBuilder.build (CoreBuilder.build (sample ()));
		CfgVerifier.verify (program);
		foreach (var function in program.functions) {
			if (function.name != "f") {
				continue;
			}
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var evaluation = block.instructions[i] as CfgEvaluateInstruction;
					var load = evaluation == null ? null : evaluation.value as CfgLoadValue;
					if (load == null || !(load.semantic_type is ClassType)) {
						continue;
					}
					block.instructions.remove_index (i);
					bool rejected = false;
					try {
						CfgVerifier.verify (program);
					} catch (CfgError error) {
						rejected = true;
					}
					assert (rejected);
					block.instructions.insert (i, evaluation);
					CfgVerifier.verify (program);
					return;
				}
			}
		}
		assert_not_reached ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void ssa_capture() {
	try {
		var graph = CfgBuilder.build (CoreBuilder.build (sample ()));
		assert (CfgFlowChecker.check (graph).diagnostic == null);
		var program = SsaBuilder.build (graph);
		SsaVerifier.verify (program);
		foreach (var function in program.functions) {
			if (function.name != "f") {
				continue;
			}
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var instruction = block.instructions[i];
					if (instruction.result == null || !(instruction.result.semantic_type is ClassType)) {
						continue;
					}
					block.instructions.remove_index (i);
					bool rejected = false;
					try {
						SsaVerifier.verify (program);
					} catch (SsaError error) {
						rejected = true;
					}
					assert (rejected);
					block.instructions.insert (i, instruction);
					SsaVerifier.verify (program);
					return;
				}
			}
		}
		assert_not_reached ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/with/checked-receiver-origin", checked_capture);
	Test.add_func ("/with/core-origin-escape-consumption", core_capture);
	Test.add_func ("/with/cfg-capture-definition", cfg_capture);
	Test.add_func ("/with/ssa-capture-definition", ssa_capture);
	return Test.run ();
}
}
