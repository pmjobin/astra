// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.Foreach {
private CheckedProgram sample() throws GLib.Error {
	string bag;
	FileUtils.get_contents ("lib/astra/collections/bag.astra", out bag);
	var parsed = Parser.parse (new SourceFile.from_text ("foreach-contract.astra", bag +
		"class Item {int tag; init(){this.tag=1;}} int observe(Item item){return item.tag;} int scan(Bag<Item> bag){int sum=0;foreach(var item in bag){sum=sum+observe(item);}return sum;}"));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	return checked.program;
}
private CheckedFunction checked_scan(CheckedProgram program) {
	foreach (var function in program.functions) {
		if (function.symbol.name == "scan") {
			return function;
		}
	}
	assert_not_reached ();
}
private CoreFunction core_function(CoreProgram program, string name) {
	foreach (var function in program.functions) {
		if (function.name == name) {
			return function;
		}
	}
	assert_not_reached ();
}
private void core_reject(CoreProgram program) {
	bool rejected = false;
	try {
		CoreVerifier.verify (program);
	} catch (CoreError error) {
		Test.message ("%s", error.message);
		rejected = true;
	}
	assert (rejected);
}
private void checked_authority() {
	try {
		var program = sample ();
		var loop = (CheckedWhile) ((CheckedBlockStatement) checked_scan (program).body.statements[1]).statements[1];
		var authority = loop.iteration;
		loop.iteration = null;
		bool rejected = false;
		try {
			CoreBuilder.build (program);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		loop.iteration = authority;
		CoreVerifier.verify (CoreBuilder.build (program));
		var sum = (CheckedAssignment) loop.body.statements[0];
		var call = (CheckedCallExpression) ((CheckedBinaryExpression) sum.expression).right;
		var loan = (CheckedSlotsValue) call.arguments[0];
		var prior = loan.iteration;
		loan.iteration = null;
		rejected = false;
		try {
			CoreBuilder.build (program);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		loan.iteration = prior;
		CoreVerifier.verify (CoreBuilder.build (program));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void core_authority() {
	try {
		var program = CoreBuilder.build (sample ());
		CoreVerifier.verify (program);
		var scope = ((CoreScope) core_function (program, "scan").body.statements[1]).body;
		var loop = (CoreWhile) scope.statements[1];
		var authority = loop.iteration;
		loop.iteration = null;
		core_reject (program);
		loop.iteration = authority;
		CoreVerifier.verify (program);
		var initial = (CoreInitialize) scope.statements[0];
		scope.statements[0] = new CoreInitialize (initial.span, initial.target, new CoreIntegerValue (initial.span, initial.value.semantic_type, AstraIntValue.from_int64 (1)));
		core_reject (program);
		scope.statements[0] = initial;
		CoreVerifier.verify (program);
		var step = loop.step.statements[0];
		loop.step.statements[0] = new CoreStore (step.span, authority.index, new CoreIntegerValue (step.span, authority.index.semantic_type, AstraIntValue.from_int64 (0)));
		core_reject (program);
		loop.step.statements[0] = step;
		CoreVerifier.verify (program);
		loop.body.statements.insert (0, step);
		core_reject (program);
		loop.body.statements.remove_index (0);
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void readonly_body() {
	try {
		var program = CoreBuilder.build (sample ());
		CoreVerifier.verify (program);
		var observe = core_function (program, "observe");
		var returned = (CoreReturn) observe.body.statements[0];
		var field = ((CoreLoadValue) returned.value).source;
		observe.body.statements.insert (0, new CoreStore (returned.span, field, returned.value));
		core_reject (program);
		observe.body.statements.remove_index (0);
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void cfg_loan() {
	try {
		var program = CfgBuilder.build (CoreBuilder.build (sample ()));
		CfgVerifier.verify (program);
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var loan = block.instructions[i] as CfgSlotsBorrow;
					if (loan == null) {
						continue;
					}
					block.instructions.insert (i + 1, loan);
					bool rejected = false;
					try {
						CfgVerifier.verify (program);
					} catch (CfgError error) {
						rejected = true;
					}
					assert (rejected);
					block.instructions.remove_index (i + 1);
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
private void ssa_loan() {
	try {
		var graph = CfgBuilder.build (CoreBuilder.build (sample ()));
		assert (CfgFlowChecker.check (graph).diagnostic == null);
		var program = SsaBuilder.build (graph);
		SsaVerifier.verify (program);
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var loan = block.instructions[i] as SsaSlotsValueInstruction;
					if (loan == null || loan.action != OwnerSlotsAction.BORROW) {
						continue;
					}
					var parameter = loan.borrower;
					var fake = new SsaFunctionParameter (parameter.span, parameter.name_span, parameter.name, parameter.semantic_type, parameter.ordinal, parameter.pointer_contract);
					block.instructions[i] = new SsaSlotsValueInstruction (loan.span, loan.result.semantic_type, loan.result.ordinal, loan.store, loan.action, loan.operand, fake);
					bool rejected = false;
					try {
						SsaVerifier.verify (program);
					} catch (SsaError error) {
						rejected = true;
					}
					assert (rejected);
					block.instructions[i] = loan;
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
	Test.add_func ("/foreach/checked-authority", checked_authority);
	Test.add_func ("/foreach/core-authority-index", core_authority);
	Test.add_func ("/foreach/readonly-transitive-body", readonly_body);
	Test.add_func ("/foreach/cfg-loan", cfg_loan);
	Test.add_func ("/foreach/ssa-borrower", ssa_loan);
	return Test.run ();
}
}
