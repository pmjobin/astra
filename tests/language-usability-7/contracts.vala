// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.LanguageUsability {
private CheckedProgram sample() {
	var parsed = Parser.parse (new SourceFile.from_text ("for-contract.astra",
		"int f(int n){int total=0;for(int i=0;i<n;i=i+1){if(i==2){continue;}total=total+i;}return total;}"));
	assert (parsed.diagnostic == null);
	var checked_program = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked_program.diagnostic == null);
	return checked_program.program;
}

private void checked_step() {
	try {
		var program = sample ();
		var loop = (CheckedWhile) ((CheckedBlockStatement) program.functions[0].body.statements[1]).statements[1];
		var original = loop.step;
		loop.step = null;
		bool rejected = false;
		try {
			CoreBuilder.build (program);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		loop.step = original;
		CoreVerifier.verify (CoreBuilder.build (program));
	} catch (Error error) {
		GLib.error ("%s", error.message);
	}
}

private void core_step() {
	try {
		var program = CoreBuilder.build (sample ());
		var loop = (CoreWhile) ((CoreScope) program.functions[0].body.statements[1]).body.statements[1];
		var step = loop.step;
		loop.step = null;
		bool rejected = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		loop.step = step;
		CoreVerifier.verify (program);
		var original = step.statements[0];
		step.statements[0] = new CoreContinue (loop.span, loop.target);
		rejected = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		step.statements[0] = original;
		CoreVerifier.verify (program);
	} catch (Error error) {
		GLib.error ("%s", error.message);
	}
}

private void cfg_step() {
	try {
		var program = CfgBuilder.build (CoreBuilder.build (sample ()));
		assert (CfgFlowChecker.check (program).diagnostic == null);
		bool tested = false;
		foreach (var block in program.functions[0].blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var store = block.instructions[i] as CfgStore;
				if (store == null || store.target.span.text () != "int i=0;") {
					continue;
				}
				block.instructions[i] = new CfgStore (store.span, store.target,
					new CfgBooleanValue (store.span, new BuiltinTypes ().bool_type, BooleanLiteral.TRUE));
				bool rejected = false;
				try {
					CfgVerifier.verify (program);
				} catch (CfgError error) {
					rejected = true;
				}
				assert (rejected);
				block.instructions[i] = store;
				CfgVerifier.verify (program);
				tested = true;
			}
		}
		assert (tested);
	} catch (Error error) {
		GLib.error ("%s", error.message);
	}
}

private void ssa_step() {
	try {
		var graph = CfgBuilder.build (CoreBuilder.build (sample ()));
		assert (CfgFlowChecker.check (graph).diagnostic == null);
		var program = SsaBuilder.build (graph);
		bool tested = false;
		foreach (var block in program.functions[0].blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var binary = block.instructions[i] as SsaBinaryInstruction;
				if (binary == null || binary.span.text () != "i+1") {
					continue;
				}
				block.instructions[i] = new SsaBinaryInstruction (binary.span, binary.result.semantic_type,
					binary.result.ordinal, binary.operator_kind, binary.left,
					new SsaBooleanConstant (binary.span, new BuiltinTypes ().bool_type, BooleanLiteral.TRUE));
				bool rejected = false;
				try {
					SsaVerifier.verify (program);
				} catch (SsaError error) {
					rejected = true;
				}
				assert (rejected);
				block.instructions[i] = binary;
				SsaVerifier.verify (program);
				tested = true;
			}
		}
		assert (tested);
	} catch (Error error) {
		GLib.error ("%s", error.message);
	}
}

private CheckedProgram chain_sample() {
	var parsed = Parser.parse (new SourceFile.from_text ("chain-contract.astra", "bool f(int a,int b,int c){return a<b<c;}"));
	assert (parsed.diagnostic == null);
	var checked_program = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked_program.diagnostic == null);
	return checked_program.program;
}

private void checked_chain() {
	try {
		var program = chain_sample ();
		var chain = (CheckedComparisonChain) ((CheckedReturnStatement) program.functions[0].body.statements[0]).expression;
		var original = chain.operands[1];
		chain.operands[1] = chain.operands[0];
		bool rejected = false;
		try {
			CoreBuilder.build (program);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		chain.operands[1] = original;
		CoreVerifier.verify (CoreBuilder.build (program));
	} catch (Error error) {
		GLib.error ("%s", error.message);
	}
}

private void core_chain() {
	try {
		var program = CoreBuilder.build (chain_sample ());
		var chain = (CoreComparisonChain) ((CoreReturn) program.functions[0].body.statements[0]).value;
		var original = chain.operands[1];
		chain.operands[1] = chain.operands[0];
		bool rejected = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		chain.operands[1] = original;
		CoreVerifier.verify (program);
		var operation = chain.operators[0];
		chain.operators[0] = BinaryOperator.ADD;
		rejected = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		chain.operators[0] = operation;
		CoreVerifier.verify (program);
		var last = chain.operands[2];
		chain.operands.remove_index (2);
		rejected = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		chain.operands.add (last);
		CoreVerifier.verify (program);
	} catch (Error error) {
		GLib.error ("%s", error.message);
	}
}

private void cfg_chain() {
	try {
		var program = CfgBuilder.build (CoreBuilder.build (chain_sample ()));
		assert (CfgFlowChecker.check (program).diagnostic == null);
		bool tested = false;
		foreach (var block in program.functions[0].blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var evaluation = block.instructions[i] as CfgEvaluateInstruction;
				if (evaluation == null) {
					continue;
				}
				// Repeating an immutable operand use is legal; repeating its
				// defining evaluation event is not a valid CFG program.
				block.instructions.insert (i, evaluation);
				bool rejected = false;
				try {
					CfgVerifier.verify (program);
				} catch (CfgError error) {
					rejected = true;
				}
				assert (rejected);
				block.instructions.remove_index (i);
				CfgVerifier.verify (program);
				tested = true;
				break;
			}
			if (tested) {
				break;
			}
		}
		assert (tested);
		var values = SsaBuilder.build (program);
		SsaVerifier.verify (values);
		foreach (var block in values.functions[0].blocks) {
			if (block.instructions.length == 0) {
				continue;
			}
			var instruction = block.instructions[0];
			block.instructions.insert (0, instruction);
			bool rejected = false;
			try {
				SsaVerifier.verify (values);
			} catch (SsaError error) {
				rejected = true;
			}
			assert (rejected);
			block.instructions.remove_index (0);
			SsaVerifier.verify (values);
			return;
		}
		assert_not_reached ();
	} catch (Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/usability/for/checked-step", checked_step);
	Test.add_func ("/usability/for/core-step", core_step);
	Test.add_func ("/usability/for/cfg-step", cfg_step);
	Test.add_func ("/usability/for/ssa-step", ssa_step);
	Test.add_func ("/usability/chain/checked-once", checked_chain);
	Test.add_func ("/usability/chain/core-shape", core_chain);
	Test.add_func ("/usability/chain/cfg-ssa-evaluation", cfg_chain);
	return Test.run ();
}

}
