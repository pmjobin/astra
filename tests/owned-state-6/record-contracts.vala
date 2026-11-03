// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Vapi;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;
namespace Astra.Tests.OwnedState {
private CheckedProgram record_checked(bool checked_factory = false) throws GLib.Error {
	string api, errors;
	FileUtils.get_contents ("tests/own-field/fixtures/resources.vapi", out api);
	FileUtils.get_contents ("lib/astra/base/errors.astra", out errors);
	string source = "struct Packet{owned R first;int tag;owned Other second;}";
	if (checked_factory) {
		source += "owned Other produce(bool failing) throws Error{owned Other item=make_other(2);if(failing){throw new Error(\"fail\");}return move item;}int main(){try{Packet p={first=make(1),second=produce(true),tag=7};var next=move p;return next.tag;}catch(Error error){return 0;}}";
	} else {
		source += "int main(){Packet p={first=make(1),tag=7,second=make_other(2)};var next=move p;return next.tag;}";
	}
	var syntax = Parser.parse (new SourceFile.from_text ("record-obligations", source + errors));
	var vapi = VapiParser.parse (new SourceFile.from_text ("resources.vapi", api));
	assert (syntax.diagnostic == null && vapi.diagnostic == null);
	var result = SemanticAnalyzer.analyze (syntax.unit, VapiNormalizer.normalize (vapi.file), VapiNormalizer.normalize_handles (vapi.file));
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}

private void record_core() {
	try {
		var checked = record_checked ();
		var declaration = checked.functions[0].body.statements[0] as CheckedStructLocalDeclaration;
		assert (declaration != null);
		var field = declaration.initializers[2];
		declaration.initializers.remove_index (2);
		bool rejected = false;
		try {
			CoreVerifier.verify (CoreBuilder.build (checked));
		} catch (CoreError error) {
			rejected = true;
			Test.message ("%s", error.message);
		}
		assert (rejected);
		declaration.initializers.add (field);
		CoreBuilder.build (checked);
		var core = CoreBuilder.build (checked);
		var f = core.functions[0];
		var owner = f.owned_locals[0];
		assert (owner.record_fields.length == 2);
		var first = owner.record_fields[0];
		var second = owner.record_fields[1];
		owner.record_fields[0] = second;
		owner.record_fields[1] = first;
		core_reject (core);
		owner.record_fields[0] = first;
		owner.record_fields[1] = second;
		CoreVerifier.verify (core);
		var obligation = owner.record_fields[1];
		owner.record_fields.remove_index (1);
		core_reject (core);
		owner.record_fields.add (obligation);
		CoreVerifier.verify (core);
		for (int i = 0; i < f.body.statements.length; i++) {
			var acquire = f.body.statements[i] as CoreStructAcquire;
			if (acquire == null) {
				continue;
			}
			f.body.statements.insert (i + 1, acquire);
			core_reject (core);
			f.body.statements.remove_index (i + 1);
			CoreVerifier.verify (core);
			break;
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void record_cfg() {
	try {
		var graph = CfgBuilder.build (CoreBuilder.build (record_checked (true)));
		CfgVerifier.verify (graph);
		int tested = 0;
		foreach (var function in graph.functions) {
			foreach (var local in function.locals) {
				if (local.record_order.length != 2) {
					continue;
				}
				var first = local.record_order[0];
				var second = local.record_order[1];
				local.record_order[0] = second;
				local.record_order[1] = first;
				cfg_reject (graph);
				local.record_order[0] = first;
				local.record_order[1] = second;
				CfgVerifier.verify (graph);
			}
		}
		foreach (var f in graph.functions) {
			foreach (var block in f.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var cleanup = block.instructions[i] as CfgCleanupInstruction;
					if (cleanup == null || cleanup.record_owner == null) {
						continue;
					}
					block.instructions.remove_index (i);
					cfg_reject (graph);
					block.instructions.insert (i, cleanup);
					CfgVerifier.verify (graph);
					tested++;
					block.instructions.insert (i + 1, cleanup);
					cfg_reject (graph);
					block.instructions.remove_index (i + 1);
					CfgVerifier.verify (graph);
					tested++;
					var load = (CfgLoadValue) cleanup.value;
					foreach (var field in f.field_places) {
						if (field.aggregate != cleanup.record_owner || field == load.source || field.field.owned_cleanup == null) {
							continue;
						}
						var wrong = new CfgCleanupInstruction (cleanup.span, new CfgLoadValue (cleanup.span, field), field.field.owned_cleanup);
						wrong.record_owner = cleanup.record_owner;
						wrong.record_final = cleanup.record_final;
						block.instructions[i] = wrong;
						cfg_reject (graph);
						block.instructions[i] = cleanup;
						CfgVerifier.verify (graph);
						tested++;
						break;
					}
				}
			}
		}
		assert (tested >= 9);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void record_ssa() {
	try {
		var model = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (record_checked (true))));
		SsaVerifier.verify (model);
		int tested = 0;
		foreach (var f in model.functions) {
			foreach (var block in f.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var event = block.instructions[i] as SsaHeapOwnerEvent;
					if (event == null || event.owner == null || event.owner.record_type == null) {
						continue;
					}
					block.instructions.remove_index (i);
					ssa_reject (model);
					block.instructions.insert (i, event);
					SsaVerifier.verify (model);
					tested++;
					int rank = event.owner.record_rank;
					event.owner.record_rank = -1;
					ssa_reject (model);
					event.owner.record_rank = rank;
					SsaVerifier.verify (model);
					tested++;
					var field = event.owner.record_field;
					event.owner.record_field = null;
					ssa_reject (model);
					event.owner.record_field = field;
					SsaVerifier.verify (model);
					tested++;
				}
			}
		}
		assert (tested >= 12);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void record_llvm() {
	try {
		CheckedProgram? checked = record_checked (true);
		var old = WeakRef (checked.functions[0]);
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		assert (old.get () == null);
		old = WeakRef (core.functions[0]);
		CfgProgram? graph = CfgBuilder.build (core);
		core = null;
		assert (old.get () == null);
		old = WeakRef (graph.functions[0]);
		SsaProgram? model = SsaBuilder.build (graph);
		graph = null;
		assert (old.get () == null);
		var native = NativeAbiBuilder.build (model);
		var artifact = LlvmLowering.lower (model, native, CAbiBuilder.build (model, native));
		old = WeakRef (model.functions[0]);
		model = null;
		assert (old.get () == null);
		NativeAbiVerifier.verify (native);
		artifact.verify ();
		int tested = 0;
		for (var f = CApi.first_function (artifact.module); (void*) f != null; f = CApi.next_function (f)) {
			for (var b = CApi.first_block (f); (void*) b != null; b = CApi.next_block (b)) {
				for (var instruction = CApi.first_instruction (b); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) != CApi.Opcode.CALL || CApi.argument_count (instruction) != 1) {
						continue;
					}
					size_t length;
					string name = CApi.value_name (CApi.called_value (instruction), out length);
					if (name != "of_release" && name != "of_release_other") {
						continue;
					}
					var original = CApi.operand (instruction, 0);
					if ((void*) original == (void*) CApi.const_null (CApi.type_of (original))) {
						continue;
					}
					CApi.set_operand (instruction, 0, CApi.const_null (CApi.type_of (original)));
					bool rejected = false;
					try {
						artifact.verify ();
					} catch (LlvmError error) {
						rejected = true;
						Test.message ("%s", error.message);
					}
					assert (rejected);
					CApi.set_operand (instruction, 0, original);
					artifact.verify ();
					tested++;
				}
			}
		}
		assert (tested >= 3);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void record_native() {
	try {
		var native = NativeAbiBuilder.build (SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (record_checked (true)))));
		int tested = 0;
		foreach (var f in native.functions) {
			foreach (var owner in f.record_owners) {
				assert (owner.obligations.length == 2);
				var field = owner.obligations[1];
				owner.obligations.remove_index (1);
				native_reject (native);
				owner.obligations.add (field);
				NativeAbiVerifier.verify (native);
				tested++;
				owner.obligations[1] = owner.obligations[0];
				native_reject (native);
				owner.obligations[1] = field;
				NativeAbiVerifier.verify (native);
				tested++;
				owner.obligations[1] = new NativeRecordResource (field.field_ordinal, field.type_name, field.cleanup_symbol, owner.obligations[0].acquisition_rank);
				native_reject (native);
				owner.obligations[1] = field;
				NativeAbiVerifier.verify (native);
				tested++;
			}
		}
		assert (tested == 6);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

internal void register_records() {
	Test.add_func ("/owned-state-completion/record-native-field-obligations", record_native);
	Test.add_func ("/owned-state-completion/record-checked-core-prefix", record_core);
	Test.add_func ("/owned-state-completion/record-cfg-field-obligations", record_cfg);
	Test.add_func ("/owned-state-completion/record-ssa-fields-and-moves", record_ssa);
	Test.add_func ("/owned-state-completion/record-independent-llvm-cleanup", record_llvm);
}

}
