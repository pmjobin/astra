// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.NonNullFields {
private CheckedProgram sample() {
	var parsed = Parser.parse (new SourceFile.from_text ("nonnull-fields.astra",
		"class C {int value;} class Box {owned nonnull C child;owned C other;init(owned nonnull C good,owned C maybe){this.child=move good;this.other=move maybe;}property borrowed nonnull C item {get{return this.child;}}}"));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	return checked.program;
}

private void source_fields() {
	var program = sample ();
	var selected = new GenericArray<FunctionSymbol> ();
	assert (SemanticNonNull.check (program, selected) == null);
	foreach (var function in program.functions) {
		if (function.symbol != program.classes[1].constructor) {
			continue;
		}
		var a = (CheckedOwnedFieldTransfer) function.body.statements[0];
		var b = (CheckedOwnedFieldTransfer) function.body.statements[1];
		function.body.statements[0] = new CheckedOwnedFieldTransfer (a.span, a.destination, a.field, b.incoming, a.initializes);
		function.body.statements[1] = new CheckedOwnedFieldTransfer (b.span, b.destination, b.field, a.incoming, b.initializes);
		var error = SemanticNonNull.check (program, selected);
		assert (error != null && error.message.contains ("current non-null proof"));
		function.body.statements[0] = a;
		function.body.statements[1] = b;
		assert (SemanticNonNull.check (program, selected) == null);
		return;
	}
	assert_not_reached ();
}

private CoreBlock transfers(CoreBlock block) {
	foreach (var node in block.statements) {
		if (node is CoreOwnedFieldTransfer) {
			return block;
		}
		if (node is CoreScope) {
			return transfers (((CoreScope) node).body);
		}
	}
	assert_not_reached ();
}

private void core_fields() {
	try {
		var program = CoreBuilder.build (sample ());
		CoreVerifier.verify (program);
		var block = transfers (program.classes[1].constructor.body);
		int first = -1;
		int second = -1;
		for (int i = 0; i < block.statements.length; i++) {
			if (block.statements[i] is CoreOwnedFieldTransfer) {
				if (first < 0) {
					first = i;
				} else {
					second = i;
				}
			}
		}
		assert (second >= 0);
		var a = (CoreOwnedFieldTransfer) block.statements[first];
		var b = (CoreOwnedFieldTransfer) block.statements[second];
		block.statements[first] = new CoreOwnedFieldTransfer (a.span, a.destination, a.cleanup, b.source, b.producer, a.initializes);
		block.statements[second] = new CoreOwnedFieldTransfer (b.span, b.destination, b.cleanup, a.source, a.producer, b.initializes);
		bool rejected = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("current non-null proof");
		}
		assert (rejected);
		block.statements[first] = a;
		block.statements[second] = b;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void cfg_fields() {
	try {
		var program = CfgBuilder.build (CoreBuilder.build (sample ()));
		CfgVerifier.verify (program);
		var block = program.classes[1].constructor.entry;
		int first = -1;
		int second = -1;
		for (int i = 0; i < block.instructions.length; i++) {
			if (block.instructions[i] is CfgResourceCapture) {
				if (first < 0) {
					first = i;
				} else {
					second = i;
				}
			}
		}
		assert (second >= 0);
		var a = (CfgResourceCapture) block.instructions[first];
		var b = (CfgResourceCapture) block.instructions[second];
		var x = (CfgInitialize) block.instructions[first + 1];
		var y = (CfgInitialize) block.instructions[second + 1];
		var changed_a = new CfgResourceCapture (a.span, b.value, b.source, a.cleanup);
		var changed_b = new CfgResourceCapture (b.span, a.value, a.source, b.cleanup);
		block.instructions[first] = changed_a;
		block.instructions[first + 1] = new CfgInitialize (x.span, x.target, changed_a.result);
		block.instructions[second] = changed_b;
		block.instructions[second + 1] = new CfgInitialize (y.span, y.target, changed_b.result);
		bool rejected = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("current non-null proof");
		}
		assert (rejected);
		block.instructions[first] = a;
		block.instructions[first + 1] = x;
		block.instructions[second] = b;
		block.instructions[second + 1] = y;
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void ssa_fields() {
	try {
		var graph = CfgBuilder.build (CoreBuilder.build (sample ()));
		var program = SsaBuilder.build (graph);
		SsaVerifier.verify (program);
		var block = program.classes[1].constructor.entry;
		int first = -1;
		int second = -1;
		for (int i = 0; i < block.instructions.length; i++) {
			if (block.instructions[i] is SsaInitializeInstruction) {
				if (first < 0) {
					first = i;
				} else {
					second = i;
				}
			}
		}
		assert (second > first && first > 0);
		var a = (SsaInitializeInstruction) block.instructions[first];
		var b = (SsaInitializeInstruction) block.instructions[second];
		var move_a = block.instructions[first - 1];
		var move_b = block.instructions[second - 1];
		assert (move_a is SsaHeapOwnerEvent && move_b is SsaHeapOwnerEvent);
		block.instructions[first - 1] = move_b;
		block.instructions[first] = new SsaInitializeInstruction (a.span, a.target, b.value);
		block.instructions[second - 1] = move_a;
		block.instructions[second] = new SsaInitializeInstruction (b.span, b.target, a.value);
		bool rejected = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("current non-null proof");
		}
		assert (rejected);
		block.instructions[first - 1] = move_a;
		block.instructions[first] = a;
		block.instructions[second - 1] = move_b;
		block.instructions[second] = b;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/nonnull-fields/source-reject-restore", source_fields);
	Test.add_func ("/nonnull-fields/core-reject-restore", core_fields);
	Test.add_func ("/nonnull-fields/cfg-reject-restore", cfg_fields);
	Test.add_func ("/nonnull-fields/ssa-reject-restore", ssa_fields);
	return Test.run ();
}

}
