// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.TextSnapshots {
private string source() {
	return "class Label{readonly string text;init(string input){this.text=input;}property string label{get{return this.text;}}}int main(){var first=new Label(\"a\\0é\");var second=new Label(first.label);release first;if(second.label==\"a\\0é\"){return 42;}return 1;}";
}
private CheckedProgram check(string text) {
	var parsed = Parser.parse (new SourceFile.from_text ("snapshot", text));
	assert (parsed.diagnostic == null);
	var result = SemanticAnalyzer.analyze (parsed.unit);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.message);
	}
	return result.program;
}
private void retained() {
	try {
		CheckedProgram? checked = check (source ());
		var predecessor = WeakRef (checked.classes[0].fields[0]);
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		assert (predecessor.get () == null);
		CoreVerifier.verify (core);
		assert (core.classes[0].fields[0].text_snapshot);
		assert (CoreDump.format (core).contains ("owned-field-cleanup"));
		predecessor = WeakRef (core.classes[0].fields[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (predecessor.get () == null);
		CfgVerifier.verify (cfg);
		assert (CfgDump.format (cfg).contains ("snapshot-destroy"));
		predecessor = WeakRef (cfg.classes[0].fields[0]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (predecessor.get () == null);
		SsaVerifier.verify (ssa);
		assert (SsaDump.format (ssa).contains ("snapshot-destroy"));
		var nabi = NativeAbiBuilder.build (ssa);
		assert (nabi.abi_version == NativeAbiVersion.NATIVE_EXCEPTIONS_V14);
		var getter = ssa.classes[0].properties[0].getter;
		assert (getter.result_contract == ResultOwnershipContract.RECEIVER_TEXT);
		assert (((NativeTextType) nabi.functions[getter.ordinal].signature.result.abi_type).contract == NativeTextContract.RECEIVER_TEXT);
		var cabi = CAbiBuilder.build (ssa, nabi);
		predecessor = WeakRef (ssa.classes[0]);
		ssa = null;
		assert (predecessor.get () == null);
		NativeAbiVerifier.verify (nabi);
		CAbiVerifier.verify (cabi);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void field_contract() {
	try {
		var core = CoreBuilder.build (check (source ()));
		core.classes[0].fields[0].text_snapshot = false;
		bool rejected = false;
		try {
			CoreVerifier.verify (core);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		core.classes[0].fields[0].text_snapshot = true;
		CoreVerifier.verify (core);
		var cfg = CfgBuilder.build (core);
		cfg.classes[0].fields[0].text_snapshot = false;
		rejected = false;
		try {
			CfgVerifier.verify (cfg);
		} catch (CfgError error) {
			rejected = true;
		}
		assert (rejected);
		cfg.classes[0].fields[0].text_snapshot = true;
		CfgVerifier.verify (cfg);
		var ssa = SsaBuilder.build (cfg);
		ssa.classes[0].fields[0].text_snapshot = false;
		rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			rejected = true;
		}
		assert (rejected);
		ssa.classes[0].fields[0].text_snapshot = true;
		SsaVerifier.verify (ssa);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void cleanup_contract() {
	try {
		var ssa = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (check (source ()))));
		var block = ssa.classes[0].destructor.entry;
		var cleanup = block.instructions[block.instructions.length - 1];
		block.instructions.remove_index (block.instructions.length - 1);
		bool rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			rejected = error.message.contains ("snapshot cleanup");
		}
		assert (rejected);
		block.instructions.add (cleanup);
		SsaVerifier.verify (ssa);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void negatives() {
	foreach (string text in new string[] {
			"class C{readonly string s;init(){this.s=\"x\";this.s=\"y\";}}",
			"class C{readonly string s;init(){this.s=\"x\";}void change(){this.s=\"y\";}}",
			"class C{readonly int n;}",
			"class C{string s;}",
			"class C{property string s{get{return \"x\";}set(string value){}}}",
			"class C{property string s{get{return helper();}}}string helper(){return \"x\";}",
			"class C{readonly string s;init(string x){this.s=x;}property string text{get{return this.s;}}}string bad(C c){return c.text;}",
			"class C{readonly string s;init(string x){this.s=x;}property string text{get{return this.s;}}}int main(){var c=new C(\"x\");var text=c.text;release c;return text.byte_length;}",
			"class C{readonly string s;init(string x){this.s=x;}property string text{get{return this.s;}}}int main(){var c=new C(\"x\");var text=c.text;var copy=text;release c;return copy.byte_length;}",
			"class C{readonly string s;init(string x){this.s=x;}property string text{get{return this.s;}}}int consume(owned C c){return 42;}int main(){var c=new C(\"x\");var text=c.text;return consume(move c);}",
			"class C{readonly string s;init(string x){this.s=x;}property string text{get{return this.s;}}}string bad(C c){var text=c.text;var copy=text;return copy;}",
			"class C{readonly string s;init(string x){this.s=x;}property string text{get{return this.s;}}}int main(){var text=\"x\";{var c=new C(\"x\");text=c.text;}return text.byte_length;}"
		}) {
		var parsed = Parser.parse (new SourceFile.from_text ("invalid", text));
		assert (parsed.diagnostic == null);
		var result = SemanticAnalyzer.analyze (parsed.unit);
		assert (result.diagnostic != null);
		Test.message ("%s", result.diagnostic.message);
	}
}
private string loans() {
	return "class Label{readonly string text;init(string input){this.text=input;}property string label{get{return this.text;}}}int main(){var first=new Label(\"a\");var second=new Label(\"b\");var outer=second.label;{var view=first.label;var copy=view;int length=copy.byte_length;}release first;return outer.byte_length+41;}";
}
private void loan_authority() {
	try {
		CheckedProgram? checked = check (loans ());
		var predecessor = WeakRef (checked.functions[0].locals[0]);
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		assert (predecessor.get () == null);
		CoreVerifier.verify (core);
		var scope = ((CoreScope) core.functions[0].body.statements[3]).body;
		var init = (CoreInitialize) scope.statements[0];
		var saved = init.value;
		var call = (CoreCallValue) saved;
		var wrong = new CoreCallValue (call.span, call.semantic_type, call.target, call.arguments, call.receiver);
		wrong.text_loan_intent = new Astra.Text.TextLoanIntent (new GenericArray<Object> ());
		scope.statements[0] = new CoreInitialize (init.span, init.target, wrong);
		bool rejected = false;
		try {
			CoreVerifier.verify (core);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("receiver association");
		}
		assert (rejected);
		scope.statements[0] = init;
		CoreVerifier.verify (core);
		var local = (CoreLocalPlace) init.target;
		local.text_loan = false;
		rejected = false;
		try {
			CoreVerifier.verify (core);
		} catch (CoreError error) {
			rejected = error.message.contains ("loan extent");
		}
		assert (rejected);
		local.text_loan = true;
		CoreVerifier.verify (core);
		predecessor = WeakRef (core.functions[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (predecessor.get () == null);
		CfgVerifier.verify (cfg);
		CfgBlock? ending = null;
		CfgTextLoanEnd? end = null;
		int position = -1;
		foreach (var block in cfg.functions[0].blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var candidate = block.instructions[i] as CfgTextLoanEnd;
				if (candidate != null && candidate.local.name == "view") {
					ending = block;
					end = candidate;
					position = i;
				}
			}
		}
		assert (ending != null && end != null);
		ending.instructions.remove_index (position);
		rejected = false;
		try {
			CfgVerifier.verify (cfg);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("surviving");
		}
		assert (rejected);
		ending.instructions.insert (position, end);
		CfgVerifier.verify (cfg);
		predecessor = WeakRef (cfg.functions[0]);
		var ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (predecessor.get () == null);
		SsaVerifier.verify (ssa);
		SsaBlock? binding_block = null;
		SsaTextLoanBind? binding = null;
		position = -1;
		foreach (var block in ssa.functions[0].blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				if (block.instructions[i] is SsaTextLoanBind) {
					binding_block = block;
					binding = (SsaTextLoanBind) block.instructions[i];
					position = i;
				}
			}
		}
		assert (binding != null);
		binding_block.instructions[position] = new SsaTextLoanBind (binding.span, binding.loan, binding.value, new Astra.Text.TextLoanIntent (new GenericArray<Object> ()));
		rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("receiver association");
		}
		assert (rejected);
		binding_block.instructions[position] = binding;
		SsaVerifier.verify (ssa);
		var saved_loans = new GenericArray<SsaTextLoan> ();
		foreach (var loan in ssa.functions[0].text_loans) {
			saved_loans.add (loan);
		}
		while (ssa.functions[0].text_loans.length != 0) {
			ssa.functions[0].text_loans.remove_index (ssa.functions[0].text_loans.length - 1);
		}
		rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("exact function loan") || error.message.contains ("function-owned extent");
		}
		assert (rejected);
		foreach (var loan in saved_loans) {
			ssa.functions[0].text_loans.add (loan);
		}
		SsaVerifier.verify (ssa);
		SsaBlock? exit_block = null;
		SsaTextLoanEnd? exit = null;
		position = -1;
		foreach (var block in ssa.functions[0].blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var candidate = block.instructions[i] as SsaTextLoanEnd;
				if (candidate != null && candidate.loan == binding.loan) {
					exit_block = block;
					exit = candidate;
					position = i;
				}
			}
		}
		assert (exit != null);
		exit_block.instructions.remove_index (position);
		rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("surviving") || error.message.contains ("active stored");
		}
		assert (rejected);
		exit_block.instructions.insert (position, exit);
		SsaVerifier.verify (ssa);
		exit_block.instructions.insert (position + 1, new SsaTextLoanEnd (exit.span, exit.loan, exit.exit_authority));
		rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("duplicate end");
		}
		assert (rejected);
		exit_block.instructions.remove_index (position + 1);
		SsaVerifier.verify (ssa);
		var outer = ssa.functions[0].text_loans[0];
		assert (outer != exit.loan);
		exit_block.instructions[position] = new SsaTextLoanEnd (exit.span, outer, exit.exit_authority);
		rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("surviving outer extent");
		}
		assert (rejected);
		exit_block.instructions[position] = exit;
		SsaVerifier.verify (ssa);
		int read_position = -1;
		for (int i = 0; i < position; i++) {
			var use = exit_block.instructions[i] as SsaTextLoanUse;
			if (use != null && use.loan == exit.loan) {
				read_position = i;
				break;
			}
		}
		assert (read_position >= 0);
		exit_block.instructions.remove_index (position);
		exit_block.instructions.insert (read_position, exit);
		rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("prematurely ended");
		}
		assert (rejected);
		exit_block.instructions.remove_index (read_position);
		exit_block.instructions.insert (position, exit);
		SsaVerifier.verify (ssa);

	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/error-1/snapshot/retained-fields-getter-contract-and-profiles", retained);
	Test.add_func ("/error-1/snapshot/false-field-contract-rejected-and-restored", field_contract);
	Test.add_func ("/error-1/snapshot/missing-cleanup-rejected-and-restored", cleanup_contract);
	Test.add_func ("/error-1/snapshot/mutable-effectful-static-escape-and-unproved-loans", negatives);
	Test.add_func ("/error-1/snapshot/predecessor-dead-exact-loan-authority-and-exits", loan_authority);
	return Test.run ();
}
}
