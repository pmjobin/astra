// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Foreign;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.StructMove {
private SourceSpan span(string text) {
	var file = new SourceFile.from_text ("record-contract", text);
	return SourceSpan (file, 0, file.length);
}

private CoreProgram core(bool incoming = false, bool borrowed = false) throws GLib.Error {
	var inputs = new GenericArray<ForeignHandleInput> ();
	inputs.add (new ForeignHandleInput (span ("R"), span ("R"), new CForeignCleanupContract ("release_r")));
	inputs.add (new ForeignHandleInput (span ("Other"), span ("Other"), new CForeignCleanupContract ("release_other")));
	var parsed = Parser.parse (new SourceFile.from_text ("record-contract", "struct Bag{int tag;owned R r;}owned R empty(){return null;}" + (borrowed ? "int f(borrowed R view){" : "int main(){") + (incoming ? "owned R input=empty();" : "") + "Bag bag={tag=42,r=" + (incoming ? "move input" : "empty()") + "};var moved=move bag;return moved.tag;}" + (borrowed ? "int main(){return 42;}" : "")));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit, null, inputs);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	CopyabilityFields fields = (type) => {
		foreach (var record in checked.program.structs) {
			if (record.semantic_type == type) {
				var result = new GenericArray<SemanticType> ();
				foreach (var field in record.fields) {
					result.add (field.semantic_type);
				}
				return result;
			}
		}
		return null;
	};
	assert (CopyabilityAuthority.of (checked.program.structs[0].semantic_type, fields) != Copyability.COPYABLE);
	var program = CoreBuilder.build (checked.program);
	CoreVerifier.verify (program);
	return program;
}

private void core_copy() {
	try {
		var program = core ();
		var body = program.functions[1].body;
		int position = -1;
		for (int i = 0; i < body.statements.length; i++) {
			if (body.statements[i] is CoreStructMove) {
				position = i;
			}
		}
		assert (position >= 0);
		var move = (CoreStructMove) body.statements[position];
		body.statements[position] = new CoreStructCopy (move.span, move.destination.place, move.source.place, move.source.place.semantic_type, true);
		bool rejected = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			rejected = error.message.contains ("copyable");
		}
		assert (rejected);
		body.statements[position] = move;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void core_wrong_cleanup() {
	try {
		var program = core ();
		var function = program.functions[1];
		var saved = function.owned_locals[0];
		var wrong = new CoreOwnedLocal (saved.span, saved.place, program.handles[1].cleanup, saved.scope);
		function.owned_locals[0] = wrong;
		bool rejected = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			rejected = error.message.contains ("cleanup");
		}
		assert (rejected);
		function.owned_locals[0] = saved;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void cfg_missing_cleanup() {
	try {
		var program = CfgBuilder.build (core ());
		assert (CfgFlowChecker.check (program).diagnostic == null);
		CfgBlock? found = null;
		int position = -1;
		foreach (var block in program.functions[1].blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var cleanup = block.instructions[i] as CfgCleanupInstruction;
				if (cleanup != null && cleanup.record_owner != null && cleanup.record_owner.name == "moved") {
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
			CfgFlowChecker.check (program);
		} catch (CfgError error) {
			rejected = error.message.contains ("normal function exit without lexical cleanup");
		}
		assert (rejected);
		found.instructions.insert (position, saved);
		assert (CfgFlowChecker.check (program).diagnostic == null);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void ssa_missing_cleanup() {
	try {
		var program = SsaBuilder.build (CfgBuilder.build (core ()));
		SsaVerifier.verify (program);
		SsaBlock? found = null;
		int position = -1;
		foreach (var block in program.functions[1].blocks) {
			for (int i = 0; i < block.instructions.length - 1; i++) {
				var cleanup = block.instructions[i] as SsaCleanupInstruction;
				var ended = block.instructions[i + 1] as SsaHeapOwnerEvent;
				if (cleanup != null && ended != null && ended.owner != null && ended.owner.source_ordinal == 1) {
					found = block;
					position = i;
				}
			}
		}
		assert (found != null && position >= 0);
		var saved = found.instructions[position];
		var event = found.instructions[position + 1];
		found.instructions.remove_index (position + 1);
		found.instructions.remove_index (position);
		bool rejected = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			rejected = error.message.contains ("exits without exact lexical cleanup");
		}
		assert (rejected);
		found.instructions.insert (position, saved);
		found.instructions.insert (position + 1, event);
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void ssa_missing_move() {
	try {
		var program = SsaBuilder.build (CfgBuilder.build (core ()));
		SsaVerifier.verify (program);
		SsaBlock? found = null;
		int position = -1;
		foreach (var block in program.functions[1].blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				if (block.instructions[i] is SsaRecordMove) {
					found = block;
					position = i + 1;
				}
			}
		}
		assert (found != null && position >= 0);
		var saved = found.instructions[position];
		found.instructions.remove_index (position);
		bool rejected = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			rejected = error.message.contains ("whole record move requires exact unique");
		}
		assert (rejected);
		found.instructions.insert (position, saved);
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void ssa_duplicate_owner() {
	try {
		var program = SsaBuilder.build (CfgBuilder.build (core ()));
		SsaVerifier.verify (program);
		SsaBlock? found = null;
		int position = -1;
		foreach (var block in program.functions[1].blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				if (block.instructions[i] is SsaRecordAcquire) {
					found = block;
					position = i;
				}
			}
		}
		assert (found != null && position >= 0);
		var saved = found.instructions[position];
		var event = found.instructions[position + 1];
		found.instructions.insert (position + 2, saved);
		found.instructions.insert (position + 3, event);
		bool rejected = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			rejected = error.message.contains ("duplicated ownership");
		}
		assert (rejected);
		found.instructions.remove_index (position + 3);
		found.instructions.remove_index (position + 2);
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void ssa_null_retirement() {
	try {
		var program = SsaBuilder.build (CfgBuilder.build (core ()));
		SsaVerifier.verify (program);
		SsaBlock? found = null;
		int position = -1;
		foreach (var block in program.functions[1].blocks) {
			for (int i = 0; i < block.instructions.length - 1; i++) {
				var cleanup = block.instructions[i] as SsaCleanupInstruction;
				var ended = block.instructions[i + 1] as SsaHeapOwnerEvent;
				if (cleanup != null && ended != null && ended.owner != null && ended.owner.source_ordinal == 1) {
					found = block;
					position = i;
				}
			}
		}
		assert (found != null && position >= 0);
		var saved = (SsaCleanupInstruction) found.instructions[position];
		var event = (SsaHeapOwnerEvent) found.instructions[position + 1];
		var pointer = new SsaNullPointerConstant (saved.span, saved.value.semantic_type);
		var fake = new SsaCleanupInstruction (saved.span, pointer, saved.cleanup);
		found.instructions[position] = fake;
		found.instructions[position + 1] = new SsaHeapOwnerEvent (event.span, event.owner, event.action, pointer, fake);
		bool rejected = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			rejected = error.message.contains ("current exact owner pointer");
		}
		assert (rejected);
		found.instructions[position] = saved;
		found.instructions[position + 1] = event;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void ssa_unretired_input() {
	try {
		var program = SsaBuilder.build (CfgBuilder.build (core (true)));
		SsaVerifier.verify (program);
		SsaBlock? found = null;
		int position = -1;
		foreach (var block in program.functions[1].blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				if (block.instructions[i] is SsaRecordAcquire) {
					found = block;
					position = i;
				}
			}
		}
		assert (found != null && position > 0);
		var saved = (SsaRecordAcquire) found.instructions[position];
		var event = (SsaHeapOwnerEvent) found.instructions[position + 1];
		var move = found.instructions[position - 1];
		var fake = new SsaRecordAcquire (saved.span, saved.owner, null, saved.pointer, saved.fields);
		found.instructions[position] = fake;
		found.instructions[position + 1] = new SsaHeapOwnerEvent (event.span, event.owner, event.action, event.value, fake);
		found.instructions.remove_index (position - 1);
		bool rejected = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			rejected = error.message.contains ("duplicated ownership");
		}
		assert (rejected);
		found.instructions.insert (position - 1, move);
		found.instructions[position] = saved;
		found.instructions[position + 1] = event;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void ssa_borrowed_input() {
	try {
		var program = SsaBuilder.build (CfgBuilder.build (core (true, true)));
		SsaVerifier.verify (program);
		var function = program.functions[1];
		SsaBlock? found = null;
		int position = -1;
		foreach (var block in function.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var event = block.instructions[i] as SsaHeapOwnerEvent;
				if (event != null && event.owner != null && event.owner.record_type == null && event.action == SsaHeapOwnerAction.ACQUIRE) {
					found = block;
					position = i;
				}
			}
		}
		assert (found != null && position >= 0);
		var saved = (SsaHeapOwnerEvent) found.instructions[position];
		found.instructions[position] = new SsaHeapOwnerEvent (saved.span, saved.owner, saved.action, function.parameters[0]);
		bool rejected = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			rejected = error.message.contains ("borrowed parameter cannot escape");
		}
		assert (rejected);
		found.instructions[position] = saved;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private CoreProgram checked_core() throws GLib.Error {
	var inputs = new GenericArray<ForeignHandleInput> ();
	inputs.add (new ForeignHandleInput (span ("R"), span ("R"), new CForeignCleanupContract ("release_r")));
	inputs.add (new ForeignHandleInput (span ("Other"), span ("Other"), new CForeignCleanupContract ("release_other")));
	string source = "[ExceptionRoot]class Error{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}" +
	    "struct Bag{int tag;owned R r;}owned R empty(){return null;}int fail() throws Error{throw new Error(\"failure\");}" +
	    "int work() throws Error{Bag bag={tag=42,r=empty()};var moved=move bag;fail();return moved.tag;}" +
	    "int main(){try{work();}catch(Error error){if(error.message!=\"failure\"){return 81;}}return 42;}";
	var parsed = Parser.parse (new SourceFile.from_text ("checked-record-contract", source));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit, null, inputs);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	var program = CoreBuilder.build (checked.program);
	CoreVerifier.verify (program);
	return program;
}

private void core_checked_initializer() {
	try {
		var program = checked_core ();
		CoreFunction? work = null;
		CoreFunction? failure = null;
		foreach (var function in program.functions) {
			if (function.name == "work") {
				work = function;
			}
			if (function.name == "fail") {
				failure = function;
			}
		}
		assert (work != null && failure != null);
		int position = -1;
		for (int i = 0; i < work.body.statements.length; i++) {
			var init = work.body.statements[i] as CoreInitialize;
			if (init != null && init.target is CoreFieldPlace) {
				position = i;
				break;
			}
		}
		assert (position >= 0);
		var saved = (CoreInitialize) work.body.statements[position];
		var call = new CoreCallValue (saved.span, saved.value.semantic_type, failure, new GenericArray<CoreValue> ());
		work.body.statements[position] = new CoreInitialize (saved.span, saved.target, call);
		CoreVerifier.verify (program);
		var effect = work.throws_type;
		work.throws_type = null;
		bool rejected = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("checked");
		}
		assert (rejected);
		work.throws_type = effect;
		CoreVerifier.verify (program);
		work.body.statements[position] = saved;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void cfg_checked_mutation(string mutation) {
	try {
		var program = CfgBuilder.build (checked_core ());
		assert (CfgFlowChecker.check (program).diagnostic == null);
		CfgBlock? found = null;
		int position = -1;
		foreach (var function in program.functions) {
			if (function.name != "work") {
				continue;
			}
			foreach (var block in function.blocks) {
				if (!(block.terminator is CfgExceptionReturn)) {
					continue;
				}
				for (int i = 0; i < block.instructions.length; i++) {
					var cleanup = block.instructions[i] as CfgCleanupInstruction;
					if (cleanup != null && cleanup.record_owner != null && cleanup.record_owner.name == "moved") {
						found = block;
						position = i;
					}
				}
			}
		}
		assert (found != null && position >= 0);
		var saved = (CfgCleanupInstruction) found.instructions[position];
		if (mutation == "omitted") {
			found.instructions.remove_index (position);
		} else if (mutation == "doubled") {
			found.instructions.insert (position + 1, new CfgCleanupInstruction (saved.span, saved.value, saved.cleanup));
			((CfgCleanupInstruction) found.instructions[position + 1]).record_owner = saved.record_owner;
		} else {
			var fake = new CfgCleanupInstruction (saved.span, saved.value, mutation == "wrong-cleanup" ? program.handles[1].cleanup : saved.cleanup);
			fake.record_owner = saved.record_owner;
			if (mutation == "moved-owner") {
				foreach (var function in program.functions) {
					if (function.name == "work") {
						foreach (var local in function.locals) {
							if (local.name == "bag") {
								fake.record_owner = local;
							}
						}
					}
				}
			}
			found.instructions[position] = fake;
		}
		bool rejected = false;
		try {
			CfgFlowChecker.check (program);
		} catch (CfgError error) {
			Test.message ("%s: %s", mutation, error.message);
			rejected = error.message.contains (mutation == "omitted" ? "exit without lexical cleanup" : mutation == "doubled" ? "duplicate cleanup" : mutation == "wrong-cleanup" ? "cleanup requires exact program-owned" : "record retirement requires exact original owner");
		}
		assert (rejected);
		if (mutation == "omitted") {
			found.instructions.insert (position, saved);
		} else if (mutation == "doubled") {
			found.instructions.remove_index (position + 1);
		} else {
			found.instructions[position] = saved;
		}
		assert (CfgFlowChecker.check (program).diagnostic == null);
	} catch (GLib.Error error) {
		GLib.error ("%s (%s)", error.message, mutation);
	}
}

private void ssa_checked_mutation(string mutation) {
	try {
		var program = SsaBuilder.build (CfgBuilder.build (checked_core ()));
		SsaVerifier.verify (program);
		SsaBlock? found = null;
		int position = -1;
		foreach (var function in program.functions) {
			if (function.name != "work") {
				continue;
			}
			foreach (var block in function.blocks) {
				if (!(block.terminator is SsaExceptionReturn)) {
					continue;
				}
				for (int i = 0; i < block.instructions.length - 1; i++) {
					var event = block.instructions[i + 1] as SsaHeapOwnerEvent;
					if (block.instructions[i] is SsaCleanupInstruction && event != null && event.owner != null && event.owner.record_type != null && event.owner.source_ordinal == 1) {
						found = block;
						position = i;
					}
				}
			}
		}
		assert (found != null && position >= 0);
		var saved = (SsaCleanupInstruction) found.instructions[position];
		var event = (SsaHeapOwnerEvent) found.instructions[position + 1];
		if (mutation == "omitted") {
			found.instructions.remove_index (position + 1);
			found.instructions.remove_index (position);
		} else if (mutation == "doubled") {
			var duplicate = new SsaCleanupInstruction (saved.span, saved.value, saved.cleanup);
			found.instructions.insert (position + 2, duplicate);
			found.instructions.insert (position + 3, new SsaHeapOwnerEvent (event.span, event.owner, event.action, event.value, duplicate));
		} else {
			var value = mutation == "moved-pointer" ? new SsaNullPointerConstant (saved.span, saved.value.semantic_type) : saved.value;
			var fake = new SsaCleanupInstruction (saved.span, value, mutation == "wrong-cleanup" ? program.handles[1].cleanup : saved.cleanup);
			found.instructions[position] = fake;
			found.instructions[position + 1] = new SsaHeapOwnerEvent (event.span, event.owner, event.action, value, fake);
		}
		bool rejected = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s: %s", mutation, error.message);
			rejected = error.message.contains (mutation == "omitted" ? "exits without exact lexical cleanup" : mutation == "wrong-cleanup" ? "cleanup" : "current exact owner pointer");
		}
		assert (rejected);
		if (mutation == "omitted") {
			found.instructions.insert (position, saved);
			found.instructions.insert (position + 1, event);
		} else if (mutation == "doubled") {
			found.instructions.remove_index (position + 3);
			found.instructions.remove_index (position + 2);
		} else {
			found.instructions[position] = saved;
			found.instructions[position + 1] = event;
		}
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s (%s)", error.message, mutation);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/struct-move-1/core/derived-policy-rejects-forged-copy", core_copy);
	Test.add_func ("/struct-move-1/core/wrong-nominal-cleanup", core_wrong_cleanup);
	Test.add_func ("/struct-move-1/cfg/omitted-lexical-cleanup", cfg_missing_cleanup);
	Test.add_func ("/struct-move-1/ssa/omitted-lexical-cleanup", ssa_missing_cleanup);
	Test.add_func ("/struct-move-1/ssa/omitted-move-disposition", ssa_missing_move);
	Test.add_func ("/struct-move-1/ssa/duplicate-ownership", ssa_duplicate_owner);
	Test.add_func ("/struct-move-1/ssa/null-retirement-cannot-hide-live-resource", ssa_null_retirement);
	Test.add_func ("/struct-move-1/ssa/acquire-cannot-copy-unretired-input", ssa_unretired_input);
	Test.add_func ("/struct-move-1/ssa/borrowed-input-cannot-claim-owner-authority", ssa_borrowed_input);
	Test.add_func ("/struct-move-1/core/checked-initializer-effect-rejected-and-restored", core_checked_initializer);
	Test.add_func ("/struct-move-1/cfg/exceptional-omitted-cleanup", () => cfg_checked_mutation ("omitted"));
	Test.add_func ("/struct-move-1/cfg/exceptional-doubled-cleanup", () => cfg_checked_mutation ("doubled"));
	Test.add_func ("/struct-move-1/cfg/exceptional-wrong-cleanup", () => cfg_checked_mutation ("wrong-cleanup"));
	Test.add_func ("/struct-move-1/cfg/exceptional-moved-owner", () => cfg_checked_mutation ("moved-owner"));
	Test.add_func ("/struct-move-1/ssa/exceptional-omitted-cleanup", () => ssa_checked_mutation ("omitted"));
	Test.add_func ("/struct-move-1/ssa/exceptional-doubled-cleanup", () => ssa_checked_mutation ("doubled"));
	Test.add_func ("/struct-move-1/ssa/exceptional-wrong-cleanup", () => ssa_checked_mutation ("wrong-cleanup"));
	Test.add_func ("/struct-move-1/ssa/exceptional-moved-pointer", () => ssa_checked_mutation ("moved-pointer"));
	return Test.run ();
}

}
