// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.OwnedChildren {
private const string SOURCE = "class Child{int value;init(){this.value=42;}}class Holder{owned Child child;init(owned Child child){this.child=move child;}void replace(Child view,owned Child incoming){this.child=move incoming;}}int main(){var a=new Child();var b=new Child();var c=new Child();var h=new Holder(move a);h.replace(c,move b);return 42;}";
private CoreProgram core() throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("owned-child-contract", SOURCE));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked.diagnostic == null);
	return CoreBuilder.build (checked.program);
}

private void wrong_cleanup() {
	try {
		var program = core ();
		CoreVerifier.verify (program);
		var body = program.classes[1].methods[0].body;
		int position = -1;
		for (int i = 0; i < body.statements.length; i++) {
			if (body.statements[i] is CoreOwnedFieldTransfer) {
				position = i;
			}
		}
		assert (position >= 0);
		var transfer = (CoreOwnedFieldTransfer) body.statements[position];
		CoreCleanupContract? wrong = null;
		foreach (var cleanup in program.cleanups) {
			if (cleanup.is_object && !cleanup.is_heap_object && cleanup.object_class == program.classes[0]) {
				wrong = cleanup;
			}
		}
		assert (wrong != null);
		body.statements[position] = new CoreOwnedFieldTransfer (transfer.span, transfer.destination, wrong, transfer.source, null, false);
		bool rejected = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			rejected = error.message.contains ("exact field/release identity");
		}
		assert (rejected);
		body.statements[position] = transfer;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void missing_retirement() {
	try {
		var program = CfgBuilder.build (core ());
		CfgVerifier.verify (program);
		var function = program.classes[1].methods[0];
		CfgBlock? found = null;
		int position = -1;
		foreach (var block in function.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var cleanup = block.instructions[i] as CfgCleanupInstruction;
				if (cleanup != null && cleanup.value is CfgLoadValue && ((CfgLoadValue) cleanup.value).source is CfgIndirectFieldPlace) {
					found = block;
					position = i;
				}
			}
		}
		assert (found != null && position >= 0);
		var saved = found.instructions[position];
		found.instructions.remove_index (position);
		bool rejected = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			rejected = error.message.contains ("cleanup-then-store replacement");
		}
		assert (rejected);
		found.instructions.insert (position, saved);
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void borrowed_store() {
	try {
		var program = SsaBuilder.build (CfgBuilder.build (core ()));
		SsaVerifier.verify (program);
		var function = program.classes[1].methods[0];
		SsaBlock? found = null;
		int position = -1;
		foreach (var block in function.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				if (block.instructions[i] is SsaStoreInstruction) {
					found = block;
					position = i;
				}
			}
		}
		assert (found != null && position >= 0);
		var saved = (SsaStoreInstruction) found.instructions[position];
		found.instructions[position] = new SsaStoreInstruction (saved.span, saved.target, function.parameters[0]);
		bool rejected = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			rejected = error.message.contains ("store requires independently proved heap ownership");
		}
		assert (rejected);
		found.instructions[position] = saved;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void transfer_during_text_loan(bool producer) {
	try {
		string source = "class Label{readonly string text;init(string text){this.text=text;}}owned Label pass(owned Label c){return move c;}class Holder{owned Label child;init(){var c=new Label(\"x\");{var view=c.text;}this.child=" + (producer ? "pass(move c)" : "move c") + ";}}int main(){return 42;}";
		var parsed = Parser.parse (new SourceFile.from_text ("child-loan-control", source));
		assert (parsed.diagnostic == null);
		var checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.diagnostic == null);
		var program = CoreBuilder.build (checked.program);
		CoreVerifier.verify (program);
		var root = program.classes[1].constructor.body;
		CoreBlock? scope = null;
		int position = -1;
		for (int i = 0; i < root.statements.length; i++) {
			if (root.statements[i] is CoreScope) {
				scope = ((CoreScope) root.statements[i]).body;
			}
			if (root.statements[i] is CoreOwnedFieldTransfer) {
				position = i;
			}
		}
		assert (scope != null && position >= 0);
		var transfer = root.statements[position];
		root.statements.remove_index (position);
		scope.statements.add (transfer);
		bool rejected = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			rejected = error.message.contains ("receiver invalidation overlaps a surviving stored text loan");
		}
		assert (rejected);
		scope.statements.remove_index (scope.statements.length - 1);
		root.statements.insert (position, transfer);
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void missing_ssa_retirement() {
	try {
		var program = SsaBuilder.build (CfgBuilder.build (core ()));
		SsaVerifier.verify (program);
		SsaBlock? found = null;
		int position = -1;
		foreach (var block in program.classes[1].methods[0].blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var cleanup = block.instructions[i] as SsaCleanupInstruction;
				if (cleanup == null) {
					continue;
				}
				foreach (var candidate in block.instructions) {
					var load = candidate as SsaLoadInstruction;
					if (load != null && load.source is SsaIndirectFieldPlace && load.result == cleanup.value) {
						found = block;
						position = i;
					}
				}
			}
		}
		assert (found != null && position >= 0);
		var saved = found.instructions[position];
		var event = found.instructions[position + 1] as SsaHeapOwnerEvent;
		assert (event != null && event.owner == null && event.effect == saved);
		found.instructions.remove_index (position + 1);
		found.instructions.remove_index (position);
		bool rejected = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			rejected = error.message.contains ("replacement requires exact old field cleanup-then-store");
		}
		assert (rejected);
		found.instructions.insert (position, saved);
		found.instructions.insert (position + 1, event);
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private CoreProgram loan_core() throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("child-stage-loan-control", "class Label{readonly string text;init(string text){this.text=text;}}class Holder{owned Label child;init(){var c=new Label(\"x\");{var view=c.text;}this.child=move c;}}int main(){return 42;}"));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked.diagnostic == null);
	return CoreBuilder.build (checked.program);
}

private void cfg_transfer_loan() {
	try {
		var program = CfgBuilder.build (loan_core ());
		CfgVerifier.verify (program);
		CfgBlock? found = null;
		int end = -1;
		int position = -1;
		foreach (var block in program.classes[1].constructor.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				if (block.instructions[i] is CfgTextLoanEnd) {
					found = block;
					end = i;
				}
				if (block.instructions[i] is CfgResourceCapture) {
					position = i;
				}
			}
		}
		assert (found != null && end >= 0 && position > end && found.instructions[position + 1] is CfgInitialize);
		var capture = found.instructions[position];
		var initialize = found.instructions[position + 1];
		found.instructions.remove_index (position + 1);
		found.instructions.remove_index (position);
		found.instructions.insert (end, capture);
		found.instructions.insert (end + 1, initialize);
		bool rejected = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			rejected = error.message.contains ("receiver invalidation overlaps a surviving stored text loan");
		}
		assert (rejected);
		found.instructions.remove_index (end + 1);
		found.instructions.remove_index (end);
		found.instructions.insert (position, capture);
		found.instructions.insert (position + 1, initialize);
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void ssa_transfer_loan() {
	try {
		var program = SsaBuilder.build (CfgBuilder.build (loan_core ()));
		SsaVerifier.verify (program);
		SsaBlock? found = null;
		int end = -1;
		int position = -1;
		foreach (var block in program.classes[1].constructor.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				if (block.instructions[i] is SsaTextLoanEnd) {
					found = block;
					end = i;
				}
				var event = block.instructions[i] as SsaHeapOwnerEvent;
				if (event != null && event.action == SsaHeapOwnerAction.MOVE) {
					position = i;
				}
			}
		}
		assert (found != null && end >= 0 && position > end);
		var transfer = found.instructions[position];
		found.instructions.remove_index (position);
		found.instructions.insert (end, transfer);
		bool rejected = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			rejected = error.message.contains ("receiver invalidation overlaps a surviving exact loan");
		}
		assert (rejected);
		found.instructions.remove_index (end);
		found.instructions.insert (position, transfer);
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-field-2/core/lexical-cleanup-cannot-own-heap-field", wrong_cleanup);
	Test.add_func ("/obj-field-2/cfg/replacement-needs-old-retirement", missing_retirement);
	Test.add_func ("/obj-field-2/ssa/borrowed-input-cannot-own-field", borrowed_store);
	Test.add_func ("/obj-field-2/ssa/replacement-needs-old-retirement", missing_ssa_retirement);
	Test.add_func ("/obj-field-2/core/child-transfer-text-loan", () => { transfer_during_text_loan (false);
	});
	Test.add_func ("/obj-field-2/core/child-producer-text-loan", () => { transfer_during_text_loan (true);
	});
	Test.add_func ("/obj-field-2/cfg/child-transfer-text-loan", cfg_transfer_loan);
	Test.add_func ("/obj-field-2/ssa/child-transfer-text-loan", ssa_transfer_loan);
	return Test.run ();
}

}
