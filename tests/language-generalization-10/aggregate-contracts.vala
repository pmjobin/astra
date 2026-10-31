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

namespace Astra.Tests.RecursiveOwnership {
private CheckedProgram sample(bool mixed = false, bool buffers = false, bool partial = false, bool transport = false, bool buffer_transport = false) throws GLib.Error {
	string api;
	FileUtils.get_contents ("tests/own-field/fixtures/resources.vapi", out api);
	string source = "struct Pair{owned R first;owned Other second;int tag;}struct Branch{Pair payload;}struct Document{Branch left;Branch right;}int main(){Document document={right={payload={second=make_other(2),first=make(1),tag=3}},left={payload={first=make(4),second=make_other(5),tag=6}}};var moved=move document;return moved.left.payload.tag;}";
	if (mixed || buffers || transport || buffer_transport) {
		FileUtils.get_contents (buffer_transport ? "tests/language-generalization-10/transport-buffer.astra" : transport ? "tests/language-generalization-10/transport.astra" : buffers ? "tests/language-generalization-10/aggregate-buffer.astra" : "tests/language-generalization-10/aggregate-class.astra", out source);
		string errors;
		FileUtils.get_contents ("lib/astra/base/errors.astra", out errors);
		source += errors;
	}
	if (partial) {
		source = "struct Pair{owned R first;owned Other second;owned int[] values;int tag;}struct Box{Pair fields;}int main(){Box box={fields={first=make(1),second=make_other(2),values=new int[3],tag=7}};var first=move box.fields.first;release first;var values=move box.fields.values;release values;box.fields.first=make(3);box.fields.values=new int[2];box.fields.second=make_other(4);var whole=move box;return whole.fields.tag;}";
	}
	var syntax = Parser.parse (new SourceFile.from_text ("recursive-record.astra", source));
	var vapi = VapiParser.parse (new SourceFile.from_text ("resources.vapi", api));
	assert (syntax.diagnostic == null && vapi.diagnostic == null);
	var result = SemanticAnalyzer.analyze (syntax.unit, VapiNormalizer.normalize (vapi.file), VapiNormalizer.normalize_handles (vapi.file));
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}
private void reject_core(CoreProgram program) {
	bool rejected = false;
	try {
		CoreVerifier.verify (program);
	} catch (CoreError error) {
		rejected = true;
		Test.message ("%s", error.message);
	}
	assert (rejected);
}
private void reject_cfg(CfgProgram program) {
	bool rejected = false;
	try {
		CfgVerifier.verify (program);
	} catch (CfgError error) {
		rejected = true;
		Test.message ("%s", error.message);
	}
	assert (rejected);
}
private void reject_ssa(SsaProgram program) {
	bool rejected = false;
	try {
		SsaVerifier.verify (program);
	} catch (SsaError error) {
		rejected = true;
		Test.message ("%s", error.message);
	}
	assert (rejected);
}
private void reject_native(NativeAbiProgram program) {
	bool rejected = false;
	try {
		NativeAbiVerifier.verify (program);
	} catch (NativeAbiError error) {
		rejected = true;
		Test.message ("%s", error.message);
	}
	assert (rejected);
}
private void checked_core() {
	try {
		var checked = sample ();
		var declaration = (CheckedStructLocalDeclaration) checked.functions[0].body.statements[0];
		var leaf = declaration.initializers[0].initializer.fields[0].initializer.fields;
		var original = leaf[1];
		leaf.remove_index (1);
		bool rejected = false;
		try {
			CoreVerifier.verify (CoreBuilder.build (checked));
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		leaf.insert (1, original);
		var program = CoreBuilder.build (checked);
		var owner = program.functions[0].owned_locals[0];
		assert (owner.record_fields.length == 4);
		assert (owner.record_fields[0].storage_path ().spelling () == "1.0.1");
		assert (owner.record_fields[2].storage_path ().spelling () == "0.0.0");
		var field = owner.record_fields[1];
		owner.record_fields[1] = owner.record_fields[2];
		reject_core (program);
		owner.record_fields[1] = field;
		CoreVerifier.verify (program);
		owner.record_fields.remove_index (3);
		reject_core (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void cfg_paths() {
	try {
		var program = CfgBuilder.build (CoreBuilder.build (sample ()));
		var function = program.functions[0];
		var local = function.locals[0];
		assert (local.record_order.length == 4);
		var path = local.record_order[0];
		local.record_order[0] = local.record_order[3];
		reject_cfg (program);
		local.record_order[0] = path;
		CfgVerifier.verify (program);
		int tested = 0;
		foreach (var block in function.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var cleanup = block.instructions[i] as CfgCleanupInstruction;
				if (cleanup == null || cleanup.record_owner == null) {
					continue;
				}
				var load = (CfgLoadValue) cleanup.value;
				foreach (var field in function.field_places) {
					if (field.root_local () != cleanup.record_owner || field == load.source || field.field.owned_cleanup != cleanup.cleanup) {
						continue;
					}
					var wrong = new CfgCleanupInstruction (cleanup.span, new CfgLoadValue (cleanup.span, field), cleanup.cleanup);
					wrong.record_owner = cleanup.record_owner;
					wrong.record_final = cleanup.record_final;
					block.instructions[i] = wrong;
					reject_cfg (program);
					block.instructions[i] = cleanup;
					CfgVerifier.verify (program);
					tested++;
					break;
				}
			}
		}
		assert (tested == 8);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void ssa_paths() {
	try {
		var program = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (sample ())));
		var function = program.functions[0];
		int tested = 0;
		foreach (var owner in function.heap_owners) {
			if (owner.record_type == null) {
				continue;
			}
			foreach (var other in function.heap_owners) {
				if (other == owner || other.source_ordinal != owner.source_ordinal || other.record_field != owner.record_field) {
					continue;
				}
				var path = owner.record_path;
				owner.record_path = other.record_path;
				reject_ssa (program);
				owner.record_path = path;
				SsaVerifier.verify (program);
				tested++;
				break;
			}
		}
		assert (tested == 8);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void native_paths() {
	try {
		var native = NativeAbiBuilder.build (SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (sample ()))));
		int tested = 0;
		foreach (var plan in native.functions[0].record_owners) {
			assert (plan.fields.length == 4 && plan.obligations.length == 4);
			var field = plan.obligations[0];
			assert (field.depth == 3);
			plan.obligations[0] = new NativeRecordResource (field.field_ordinal, field.type_name, field.cleanup_symbol, field.acquisition_rank);
			reject_native (native);
			plan.obligations[0] = field;
			NativeAbiVerifier.verify (native);
			tested++;
			plan.obligations[0] = plan.obligations[3];
			reject_native (native);
			plan.obligations[0] = field;
			NativeAbiVerifier.verify (native);
			tested++;
		}
		assert (tested == 4);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void independent_llvm() {
	try {
		CheckedProgram? checked = sample ();
		var prior = WeakRef (checked.functions[0]);
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		assert (prior.get () == null);
		prior = WeakRef (core.functions[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (prior.get () == null);
		prior = WeakRef (cfg.functions[0]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (prior.get () == null);
		var native = NativeAbiBuilder.build (ssa);
		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		prior = WeakRef (ssa.functions[0]);
		ssa = null;
		assert (prior.get () == null);
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
					}
					assert (rejected);
					CApi.set_operand (instruction, 0, original);
					artifact.verify ();
					tested++;
				}
			}
		}
		assert (tested == 4);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void class_paths() {
	try {
		CheckedProgram? checked = sample (true);
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		CoreVerifier.verify (core);
		int roots = 0;
		foreach (var function in core.functions) {
			foreach (var owner in function.owned_locals) {
				if (owner.record_fields.length == 0) {
					continue;
				}
				assert (owner.cleanup.record_type != null && !owner.cleanup.is_object && !owner.cleanup.is_buffer);
				roots++;
			}
		}
		assert (roots == 4);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		int tested = 0;
		foreach (var function in native.functions) {
			foreach (var owner in function.record_owners) {
				for (int i = 0; i < owner.obligations.length; i++) {
					var field = owner.obligations[i];
					if (field.cleanup_class_ordinal < 0) {
						continue;
					}
					owner.obligations[i] = new NativeRecordResource (field.field_ordinal, field.type_name, "of_release", field.acquisition_rank);
					reject_native (native);
					owner.obligations[i] = field;
					NativeAbiVerifier.verify (native);
					tested++;
				}
			}
		}
		assert (tested == 6);
		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		var prior = WeakRef (ssa.functions[0]);
		ssa = null;
		assert (prior.get () == null);
		NativeAbiVerifier.verify (native);
		artifact.verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private SsaProgram buffer_model() throws GLib.Error {
	return SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (sample (false, true))));
}
private void buffer_paths() {
	try {
		var program = buffer_model ();
		int tested = 0;
		foreach (var function in program.functions) {
			foreach (var slot in function.buffer_storage) {
				if (slot.record_type == null) {
					continue;
				}
				foreach (var other in function.buffer_storage) {
					if (other == slot || other.record_type != slot.record_type || other.record_source_ordinal != slot.record_source_ordinal) {
						continue;
					}
					var path = slot.record_path;
					slot.record_path = other.record_path;
					reject_ssa (program);
					slot.record_path = path;
					SsaVerifier.verify (program);
					int rank = slot.record_rank;
					slot.record_rank = other.record_rank;
					other.record_rank = rank;
					reject_ssa (program);
					other.record_rank = slot.record_rank;
					slot.record_rank = rank;
					SsaVerifier.verify (program);
					tested++;
					break;
				}
			}
		}
		assert (tested == 12);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void buffer_pairs_and_exits() {
	try {
		var program = buffer_model ();
		int moves = 0;
		int exits = 0;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var write = block.instructions[i] as SsaBufferWriteInstruction;
					if (write != null && write.record_move_source != null) {
						var original = write.record_move_source;
						write.record_move_source = null;
						reject_ssa (program);
						write.record_move_source = original;
						SsaVerifier.verify (program);
						var pair = new SsaBufferPair (write.span, write.pair.shape, write.pair.base_value,
							new SsaIntegerConstant.typed (write.span, write.pair.shape.length_type, AstraIntegerValue.from_int64 (write.pair.shape.length_type, 1)));
						var wrong = new SsaBufferWriteInstruction (write.span, write.place, pair);
						wrong.initializes = true;
						wrong.record_move_source = original;
						block.instructions[i] = wrong;
						reject_ssa (program);
						block.instructions[i] = write;
						SsaVerifier.verify (program);
						moves++;
					}
					var cleanup = block.instructions[i] as SsaBufferDeallocateInstruction;
					var read = i == 0 ? null : block.instructions[i - 1] as SsaBufferReadInstruction;
					if (cleanup == null || read == null || read.place.storage == null || read.place.storage.record_type == null) {
						continue;
					}
					bool live_destination = false;
					foreach (var candidate_block in function.blocks) {
						foreach (var candidate in candidate_block.instructions) {
							var installed = candidate as SsaBufferWriteInstruction;
							if (installed != null && installed.record_move_source != null && installed.place.storage == read.place.storage) {
								live_destination = true;
							}
						}
					}
					if (!live_destination) {
						continue;
					}
					block.instructions.remove_index (i);
					reject_ssa (program);
					block.instructions.insert (i, cleanup);
					SsaVerifier.verify (program);
					exits++;
				}
			}
		}
		assert (moves == 6 && exits >= 6);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void buffer_native_llvm() {
	try {
		SsaProgram? ssa = buffer_model ();
		var native = NativeAbiBuilder.build (ssa);
		int tested = 0;
		foreach (var function in native.functions) {
			foreach (var owner in function.record_owners) {
				for (int i = 0; i < owner.obligations.length; i++) {
					var field = owner.obligations[i];
					if (field.buffer_cleanup == null) {
						continue;
					}
					owner.obligations[i] = new NativeRecordResource (field.field_ordinal, field.type_name, "of_release", field.acquisition_rank);
					reject_native (native);
					owner.obligations[i] = field;
					NativeAbiVerifier.verify (native);
					tested++;
				}
			}
		}
		assert (tested == 12);
		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		var prior = WeakRef (ssa.functions[0]);
		ssa = null;
		assert (prior.get () == null);
		NativeAbiVerifier.verify (native);
		artifact.verify ();
		int retired = 0;
		for (var f = CApi.first_function (artifact.module); (void*) f != null; f = CApi.next_function (f)) {
			for (var b = CApi.first_block (f); (void*) b != null; b = CApi.next_block (b)) {
				if (!CApi.block_name (b).has_prefix ("buffer.free")) {
					continue;
				}
				for (var instruction = CApi.first_instruction (b); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) != CApi.Opcode.CALL || CApi.argument_count (instruction) != 1) {
						continue;
					}
					size_t length;
					if (CApi.value_name (CApi.called_value (instruction), out length) != "free") {
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
					}
					assert (rejected);
					CApi.set_operand (instruction, 0, original);
					artifact.verify ();
					retired++;
				}
			}
		}
		assert (retired >= 12);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void partial_core() {
	try {
		var checked = sample (false, false, true);
		var statements = checked.functions[0].body.statements;
		int take_index = -1;
		for (int i = 0; i < statements.length; i++) {
			if (statements[i] is CheckedRecordTake) {
				take_index = i;
				break;
			}
		}
		assert (take_index >= 0);
		var original = (CheckedRecordTake) statements[take_index];
		var declaration = (CheckedStructLocalDeclaration) statements[0];
		var aggregate = original.field.aggregate;
		var other = declaration.initializers[0].initializer.fields[1].field;
		statements[take_index] = new CheckedRecordTake (original.span, original.source, new CheckedFieldPlace (original.span, aggregate, (StructFieldSymbol) other), original.destination);
		bool rejected = false;
		try {
			CoreVerifier.verify (CoreBuilder.build (checked));
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		statements[take_index] = original;
		var program = CoreBuilder.build (checked);
		var body = program.functions[0].body.statements;
		int tested = 0;
		for (int i = 0; i < body.length; i++) {
			var replace = body[i] as CoreRecordReplace;
			if (replace == null || replace.field.field.name != "first") {
				continue;
			}
			body.remove_index (i);
			reject_core (program);
			body.insert (i, replace);
			CoreVerifier.verify (program);
			tested++;
		}
		assert (tested == 1);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void partial_cfg() {
	try {
		var program = CfgBuilder.build (CoreBuilder.build (sample (false, false, true)));
		int takes = 0;
		int refills = 0;
		foreach (var block in program.functions[0].blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var instruction = block.instructions[i];
				var take = instruction as CfgRecordTake;
				if (take != null) {
					block.instructions.remove_index (i);
					reject_cfg (program);
					block.instructions.insert (i, instruction);
					CfgVerifier.verify (program);
					takes++;
				}
				var replace = instruction as CfgRecordReplace;
				if (replace != null && replace.field.field.name == "first") {
					block.instructions.remove_index (i);
					reject_cfg (program);
					block.instructions.insert (i, instruction);
					CfgVerifier.verify (program);
					refills++;
				}
			}
		}
		assert (takes == 2 && refills == 1);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void partial_ssa() {
	try {
		var program = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (sample (false, false, true))));
		int takes = 0;
		int retirements = 0;
		int pairs = 0;
		foreach (var block in program.functions[0].blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var instruction = block.instructions[i];
				var take = instruction as SsaRecordTake;
				if (take != null) {
					block.instructions.remove_index (i);
					reject_ssa (program);
					block.instructions.insert (i, instruction);
					SsaVerifier.verify (program);
					takes++;
				}
				var cleanup = instruction as SsaCleanupInstruction;
				if (cleanup != null && cleanup.record_replacement != null) {
					block.instructions.remove_index (i);
					reject_ssa (program);
					block.instructions.insert (i, instruction);
					SsaVerifier.verify (program);
					retirements++;
				}
				var write = instruction as SsaBufferWriteInstruction;
				if (write != null && write.record_take_source != null) {
					var original = write.record_take_source;
					write.record_take_source = null;
					reject_ssa (program);
					write.record_take_source = original;
					SsaVerifier.verify (program);
					pairs++;
				}
				if (write != null && write.record_retirement != null) {
					var original = write.record_retirement;
					write.record_retirement = null;
					reject_ssa (program);
					write.record_retirement = original;
					SsaVerifier.verify (program);
					pairs++;
				}
			}
		}
		assert (takes == 1 && retirements == 2 && pairs == 2);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void partial_native_llvm() {
	try {
		CheckedProgram? checked = sample (false, false, true);
		var prior = WeakRef (checked.functions[0]);
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		assert (prior.get () == null);
		prior = WeakRef (core.functions[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (prior.get () == null);
		prior = WeakRef (cfg.functions[0]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (prior.get () == null);
		var native = NativeAbiBuilder.build (ssa);
		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		prior = WeakRef (ssa.functions[0]);
		ssa = null;
		assert (prior.get () == null);
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
					string callee = CApi.value_name (CApi.called_value (instruction), out length);
					if (callee != "of_release" && callee != "of_release_other" && callee != "free") {
						continue;
					}
					var original = CApi.operand (instruction, 0);
					var empty = CApi.const_null (CApi.type_of (original));
					if ((void*) original == (void*) empty) {
						continue;
					}
					CApi.set_operand (instruction, 0, empty);
					bool rejected = false;
					try {
						artifact.verify ();
					} catch (LlvmError error) {
						rejected = true;
					}
					assert (rejected);
					CApi.set_operand (instruction, 0, original);
					artifact.verify ();
					tested++;
				}
			}
		}
		assert (tested >= 5);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void transport_core_cfg() {
	try {
		var core = CoreBuilder.build (sample (false, false, false, true));
		int parameters = 0;
		foreach (var function in core.functions) {
			if (function.name != "relay") {
				continue;
			}
			var original = function.body.statements[0];
			assert (original is CoreAcquireStructParameter);
			function.body.statements.remove_index (0);
			reject_core (core);
			function.body.statements.insert (0, original);
			CoreVerifier.verify (core);
			var contract = function.parameters[0].struct_value_contract;
			function.parameters[0].struct_value_contract = new StructValueContract (contract.semantic_type);
			reject_core (core);
			function.parameters[0].struct_value_contract = contract;
			CoreVerifier.verify (core);
			parameters++;
		}
		assert (parameters == 1);
		var cfg = CfgBuilder.build (core);
		int acquisitions = 0;
		int moves = 0;
		foreach (var function in cfg.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var instruction = block.instructions[i];
					if (!(instruction is CfgStructBoundaryAcquire || instruction is CfgStructBoundaryMove)) {
						continue;
					}
					block.instructions.remove_index (i);
					reject_cfg (cfg);
					block.instructions.insert (i, instruction);
					CfgVerifier.verify (cfg);
					if (instruction is CfgStructBoundaryAcquire) {
						acquisitions++;
					} else {
						moves++;
					}
				}
			}
		}
		assert (acquisitions >= 8 && moves >= 7);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void transport_ssa() {
	try {
		var ssa = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (sample (false, false, false, true))));
		int tested = 0;
		foreach (var function in ssa.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var boundary = block.instructions[i] as SsaStructBoundary;
					if (boundary == null) {
						continue;
					}
					var removed = new GenericArray<SsaInstruction> ();
					for (int n = 0; n <= boundary.owners.length; n++) {
						removed.add (block.instructions[i]);
						block.instructions.remove_index (i);
					}
					reject_ssa (ssa);
					for (int n = 0; n < removed.length; n++) {
						block.instructions.insert (i + n, removed[n]);
					}
					SsaVerifier.verify (ssa);
					tested++;
				}
			}
		}
		assert (tested >= 15);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void transport_commit_order() {
	try {
		var cfg = CfgBuilder.build (CoreBuilder.build (sample (false, false, false, true)));
		int tested = 0;
		foreach (var function in cfg.functions) {
			if (function.name != "ordered") {
				continue;
			}
			foreach (var block in function.blocks) {
				int effect = -1;
				int commit = -1;
				for (int i = 0; i < block.instructions.length; i++) {
					if (block.instructions[i] is CfgCCallInstruction) {
						effect = i;
					}
					if (block.instructions[i] is CfgStructBoundaryMove) {
						commit = i;
					}
				}
				if (commit < 0) {
					continue;
				}
				assert (effect >= 0 && effect < commit);
				var move = block.instructions[commit];
				block.instructions.remove_index (commit);
				block.instructions.insert (effect, move);
				bool rejected = false;
				try {
					CfgVerifier.verify (cfg);
				} catch (CfgError error) {
					rejected = error.message.contains ("cannot commit before another argument effect");
				}
				assert (rejected);
				block.instructions.remove_index (effect);
				block.instructions.insert (commit, move);
				CfgVerifier.verify (cfg);
				tested++;
			}
		}
		assert (tested == 1);
		var ssa = SsaBuilder.build (cfg);
		tested = 0;
		foreach (var function in ssa.functions) {
			if (function.name != "ordered") {
				continue;
			}
			foreach (var block in function.blocks) {
				int effect = -1;
				int commit = -1;
				for (int i = 0; i < block.instructions.length; i++) {
					if (block.instructions[i] is SsaCCallInstruction) {
						effect = i;
					}
					if (block.instructions[i] is SsaStructBoundaryMove) {
						commit = i;
					}
				}
				if (commit < 0) {
					continue;
				}
				assert (effect >= 0 && effect < commit);
				var marker = (SsaStructBoundaryMove) block.instructions[commit];
				var moved = new GenericArray<SsaInstruction> ();
				for (int i = 0; i <= marker.owners.length; i++) {
					moved.add (block.instructions[commit]);
					block.instructions.remove_index (commit);
				}
				for (int i = 0; i < moved.length; i++) {
					block.instructions.insert (effect + i, moved[i]);
				}
				bool rejected = false;
				try {
					SsaVerifier.verify (ssa);
				} catch (SsaError error) {
					rejected = error.message.contains ("cannot commit before another argument effect");
				}
				assert (rejected);
				for (int i = 0; i < moved.length; i++) {
					block.instructions.remove_index (effect);
				}
				for (int i = 0; i < moved.length; i++) {
					block.instructions.insert (commit + i, moved[i]);
				}
				SsaVerifier.verify (ssa);
				tested++;
			}
		}
		assert (tested == 1);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void transport_parameter_order() {
	try {
		var cfg = CfgBuilder.build (CoreBuilder.build (sample (false, false, false, true)));
		int tested = 0;
		foreach (var function in cfg.functions) {
			if (function.name != "adjacent") {
				continue;
			}
			foreach (var block in function.blocks) {
				int scalar = -1;
				int record = -1;
				for (int i = 0; i < block.instructions.length; i++) {
					var cleanup = block.instructions[i] as CfgCleanupInstruction;
					if (cleanup == null) {
						continue;
					}
					if (cleanup.record_owner == null) {
						scalar = i;
					} else if (record < 0) {
						record = i;
					}
				}
				if (record < 0) {
					continue;
				}
				assert (scalar >= 0 && scalar < record);
				var first = block.instructions[scalar];
				block.instructions[scalar] = block.instructions[record];
				block.instructions[record] = first;
				bool rejected = false;
				try {
					CfgVerifier.verify (cfg);
				} catch (CfgError error) {
					rejected = error.message.contains ("reverse parameter declaration order");
				}
				assert (rejected);
				block.instructions[record] = block.instructions[scalar];
				block.instructions[scalar] = first;
				CfgVerifier.verify (cfg);
				tested++;
			}
		}
		assert (tested == 1);
		var ssa = SsaBuilder.build (cfg);
		tested = 0;
		foreach (var function in ssa.functions) {
			if (function.name != "adjacent") {
				continue;
			}
			foreach (var block in function.blocks) {
				int scalar = -1;
				int record = -1;
				for (int i = 0; i + 1 < block.instructions.length; i++) {
					var cleanup = block.instructions[i] as SsaCleanupInstruction;
					var event = block.instructions[i + 1] as SsaHeapOwnerEvent;
					if (cleanup == null || event == null || event.owner == null || event.action != SsaHeapOwnerAction.END || event.effect != cleanup) {
						continue;
					}
					if (event.owner.record_type == null) {
						scalar = i;
					} else if (record < 0) {
						record = i;
					}
				}
				if (record < 0) {
					continue;
				}
				assert (scalar >= 0 && record == scalar + 2);
				var first = block.instructions[scalar];
				var event = block.instructions[scalar + 1];
				block.instructions[scalar] = block.instructions[record];
				block.instructions[scalar + 1] = block.instructions[record + 1];
				block.instructions[record] = first;
				block.instructions[record + 1] = event;
				bool rejected = false;
				try {
					SsaVerifier.verify (ssa);
				} catch (SsaError error) {
					rejected = error.message.contains ("reverse parameter declaration order");
				}
				assert (rejected);
				block.instructions[record] = block.instructions[scalar];
				block.instructions[record + 1] = block.instructions[scalar + 1];
				block.instructions[scalar] = first;
				block.instructions[scalar + 1] = event;
				SsaVerifier.verify (ssa);
				tested++;
			}
		}
		assert (tested == 1);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void transport_native_llvm() {
	try {
		CheckedProgram? checked = sample (false, false, false, true);
		var prior = WeakRef (checked.functions[0]);
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		assert (prior.get () == null);
		prior = WeakRef (core.functions[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (prior.get () == null);
		prior = WeakRef (cfg.functions[0]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (prior.get () == null);
		var native = NativeAbiBuilder.build (ssa);
		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		prior = WeakRef (ssa.functions[0]);
		ssa = null;
		assert (prior.get () == null);
		NativeAbiVerifier.verify (native);
		artifact.verify ();
		int tested = 0;
		foreach (var plan in native.struct_values) {
			if (plan.mode != NativeStructValueMode.MOVE_VALUE) {
				continue;
			}
			assert (plan.declaration != null && plan.ownership.length == 3);
			var original = plan.ownership[0];
			int[] ordinals = new int[original.depth];
			for (int i = 0; i < original.depth; i++) {
				ordinals[i] = original.path_ordinal (i);
			}
			plan.ownership[0] = new NativeRecordResource.projected (ordinals, original.type_name, "of_release_other", original.acquisition_rank);
			reject_native (native);
			plan.ownership[0] = original;
			NativeAbiVerifier.verify (native);
			tested++;
			plan.ownership.remove_index (0);
			reject_native (native);
			plan.ownership.insert (0, original);
			NativeAbiVerifier.verify (native);
			tested++;
			var declaration = plan.declaration;
			plan.declaration = null;
			reject_native (native);
			plan.declaration = declaration;
			NativeAbiVerifier.verify (native);
			tested++;
			var last = plan.leaves[plan.leaves.length - 1];
			plan.leaves.remove_index (plan.leaves.length - 1);
			reject_native (native);
			plan.leaves.add (last);
			NativeAbiVerifier.verify (native);
			tested++;
		}
		assert (tested == 4);
		int signatures = 0;
		foreach (var function in native.functions) {
			var signature = function.signature;
			if (function.name == "consume") {
				var original = signature.struct_parameters[0];
				signature.struct_parameters.remove_index (0);
				reject_native (native);
				signature.struct_parameters.insert (0, original);
				NativeAbiVerifier.verify (native);
				signatures++;
			}
			if (function.name == "create") {
				var original = signature.struct_result;
				signature.struct_result = null;
				reject_native (native);
				signature.struct_result = original;
				NativeAbiVerifier.verify (native);
				signatures++;
			}
		}
		assert (signatures == 2);
		int physical = 0;
		for (var f = CApi.first_function (artifact.module); (void*) f != null; f = CApi.next_function (f)) {
			for (var b = CApi.first_block (f); (void*) b != null; b = CApi.next_block (b)) {
				for (var instruction = CApi.first_instruction (b); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) != CApi.Opcode.CALL || CApi.argument_count (instruction) != 1) {
						continue;
					}
					size_t length;
					string callee = CApi.value_name (CApi.called_value (instruction), out length);
					if (callee != "of_release" && callee != "of_release_other" && callee != "free") {
						continue;
					}
					var original = CApi.operand (instruction, 0);
					var empty = CApi.const_null (CApi.type_of (original));
					if ((void*) original == (void*) empty) {
						continue;
					}
					CApi.set_operand (instruction, 0, empty);
					bool rejected = false;
					try {
						artifact.verify ();
					} catch (LlvmError error) {
						rejected = true;
					}
					assert (rejected);
					CApi.set_operand (instruction, 0, original);
					artifact.verify ();
					physical++;
				}
			}
		}
		assert (physical >= 15);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void transport_buffer_pairs() {
	try {
		var checked = sample (false, false, false, false, true);
		var cfg = CfgBuilder.build (CoreBuilder.build (checked));
		int acquisitions = 0;
		int captures = 0;
		foreach (var function in cfg.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var captured = block.instructions[i] as CfgRecordBufferCapture;
					if (captured != null) {
						block.instructions[i] = new CfgEvaluateInstruction (captured.span, captured.value, captured.result);
						reject_cfg (cfg);
						block.instructions[i] = captured;
						CfgVerifier.verify (cfg);
						captures++;
					}
					var acquire = block.instructions[i] as CfgStructBoundaryAcquire;
					if (acquire == null) {
						continue;
					}
					block.instructions.remove_index (i);
					reject_cfg (cfg);
					block.instructions.insert (i, acquire);
					CfgVerifier.verify (cfg);
					acquisitions++;
				}
			}
		}
		assert (acquisitions >= 6 && captures >= 12);

		var ssa = SsaBuilder.build (cfg);
		int writes = 0;
		int pairs = 0;
		foreach (var function in ssa.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var boundary = block.instructions[i] as SsaStructBoundary;
					if (boundary == null) {
						continue;
					}
					assert (boundary.buffers.length == 2 && boundary.shape.physical_buffers);
					var original = boundary.buffer_pairs[0];
					boundary.buffer_pairs[0] = new SsaBufferPair (boundary.span, original.shape, original.base_value, boundary.buffer_pairs[1].length_value);
					reject_ssa (ssa);
					boundary.buffer_pairs[0] = original;
					SsaVerifier.verify (ssa);
					pairs++;
					int index = i + (int) boundary.owners.length + 1;
					var write = (SsaBufferWriteInstruction) block.instructions[index];
					block.instructions.remove_index (index);
					reject_ssa (ssa);
					block.instructions.insert (index, write);
					SsaVerifier.verify (ssa);
					writes++;
					write.record_boundary = null;
					reject_ssa (ssa);
					write.record_boundary = boundary;
					SsaVerifier.verify (ssa);
					writes++;
					var leaf = boundary.shape.leaves[1];
					boundary.shape.leaves[1] = boundary.shape.leaves[0];
					reject_ssa (ssa);
					boundary.shape.leaves[1] = leaf;
					SsaVerifier.verify (ssa);
					pairs++;
				}
			}
		}
		assert (writes >= 20 && pairs >= 20);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void transport_buffer_retirement() {
	try {
		var ssa = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (sample (false, false, false, false, true))));
		int tested = 0;
		foreach (var function in ssa.functions) {
			if (function.name != "retirement") {
				continue;
			}
			foreach (var block in function.blocks) {
				int scalar = -1;
				int buffer = -1;
				int record = -1;
				for (int i = 1; i < block.instructions.length; i++) {
					var event = block.instructions[i] as SsaHeapOwnerEvent;
					if (event != null && event.action == SsaHeapOwnerAction.END && event.owner.record_type == null && event.owner.source_ordinal == 1) {
						scalar = i - 1;
					}
					if (event != null && event.action == SsaHeapOwnerAction.END && event.owner.record_type != null && event.owner.record_rank == 2) {
						record = i - 1;
					}
					var deallocation = block.instructions[i] as SsaBufferDeallocateInstruction;
					var read = block.instructions[i - 1] as SsaBufferReadInstruction;
					if (deallocation != null && read != null && deallocation.pair == read.pair && read.place.storage != null && read.place.storage.record_path != null && read.place.storage.record_path.spelling () == "1") {
						buffer = i - 1;
					}
				}
				if (scalar < 0 || buffer < 0) {
					continue;
				}
				var first = block.instructions[scalar];
				var second = block.instructions[scalar + 1];
				block.instructions[scalar] = block.instructions[buffer];
				block.instructions[scalar + 1] = block.instructions[buffer + 1];
				block.instructions[buffer] = first;
				block.instructions[buffer + 1] = second;
				bool rejected = false;
				try {
					SsaVerifier.verify (ssa);
				} catch (SsaError error) {
					rejected = error.message.contains ("reverse parameter declaration order");
				}
				assert (rejected);
				block.instructions[buffer] = block.instructions[scalar];
				block.instructions[buffer + 1] = block.instructions[scalar + 1];
				block.instructions[scalar] = first;
				block.instructions[scalar + 1] = second;
				SsaVerifier.verify (ssa);
				tested++;
				assert (record >= 0);
				first = block.instructions[record];
				second = block.instructions[record + 1];
				block.instructions[record] = block.instructions[buffer];
				block.instructions[record + 1] = block.instructions[buffer + 1];
				block.instructions[buffer] = first;
				block.instructions[buffer + 1] = second;
				rejected = false;
				try {
					SsaVerifier.verify (ssa);
				} catch (SsaError error) {
					rejected = error.message.contains ("reverse written field order");
				}
				assert (rejected);
				block.instructions[buffer] = block.instructions[record];
				block.instructions[buffer + 1] = block.instructions[record + 1];
				block.instructions[record] = first;
				block.instructions[record + 1] = second;
				SsaVerifier.verify (ssa);
				tested++;
			}
		}
		assert (tested == 2);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void transport_buffer_native_llvm() {
	try {
		CheckedProgram? checked = sample (false, false, false, false, true);
		var prior = WeakRef (checked.functions[0]);
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		assert (prior.get () == null);
		prior = WeakRef (core.functions[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (prior.get () == null);
		prior = WeakRef (cfg.functions[0]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (prior.get () == null);
		var native = NativeAbiBuilder.build (ssa);
		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		prior = WeakRef (ssa.functions[0]);
		ssa = null;
		assert (prior.get () == null);
		NativeAbiVerifier.verify (native);
		artifact.verify ();
		int pairs = 0;
		int cleanups = 0;
		foreach (var plan in native.struct_values) {
			for (int i = 0; i < plan.leaves.length; i++) {
				var leaf = plan.leaves[i];
				if (leaf.buffer_component != 1) {
					continue;
				}
				plan.leaves[i] = new NativeStructLeafChannel (leaf.field_path, new NativeScalarAbiType (NativeScalarType.PTR), leaf.storage_path, 1);
				reject_native (native);
				plan.leaves[i] = leaf;
				NativeAbiVerifier.verify (native);
				pairs++;
				plan.leaves.remove_index (i);
				reject_native (native);
				plan.leaves.insert (i, leaf);
				NativeAbiVerifier.verify (native);
				pairs++;
			}
			for (int i = 0; i < plan.ownership.length; i++) {
				var owner = plan.ownership[i];
				if (owner.buffer_cleanup == null) {
					continue;
				}
				int[] ordinals = new int[owner.depth];
				for (int p = 0; p < owner.depth; p++) {
					ordinals[p] = owner.path_ordinal (p);
				}
				plan.ownership[i] = new NativeRecordResource.projected (ordinals, owner.type_name, "of_release", owner.acquisition_rank);
				reject_native (native);
				plan.ownership[i] = owner;
				NativeAbiVerifier.verify (native);
				cleanups++;
			}
		}
		assert (pairs == 8 && cleanups == 4);

		int physical = 0;
		for (var f = CApi.first_function (artifact.module); (void*) f != null; f = CApi.next_function (f)) {
			for (var b = CApi.first_block (f); (void*) b != null; b = CApi.next_block (b)) {
				for (var instruction = CApi.first_instruction (b); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) != CApi.Opcode.CALL || CApi.argument_count (instruction) != 1) {
						continue;
					}
					size_t length;
					string callee = CApi.value_name (CApi.called_value (instruction), out length);
					if (callee != "free") {
						continue;
					}
					var original = CApi.operand (instruction, 0);
					var empty = CApi.const_null (CApi.type_of (original));
					if ((void*) original == (void*) empty) {
						continue;
					}
					CApi.set_operand (instruction, 0, empty);
					bool rejected = false;
					try {
						artifact.verify ();
					} catch (LlvmError error) {
						rejected = true;
					}
					assert (rejected);
					CApi.set_operand (instruction, 0, original);
					artifact.verify ();
					physical++;
				}
			}
		}
		assert (physical >= 12);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
public int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/recursive-ownership/checked-core-paths", checked_core);
	Test.add_func ("/recursive-ownership/cfg-cleanup-paths", cfg_paths);
	Test.add_func ("/recursive-ownership/ssa-owner-paths", ssa_paths);
	Test.add_func ("/recursive-ownership/native-copied-paths", native_paths);
	Test.add_func ("/recursive-ownership/independent-llvm", independent_llvm);
	Test.add_func ("/recursive-ownership/mixed-class-authority", class_paths);
	Test.add_func ("/recursive-ownership/buffer-paths-and-ranks", buffer_paths);
	Test.add_func ("/recursive-ownership/buffer-pairs-and-exits", buffer_pairs_and_exits);
	Test.add_func ("/recursive-ownership/buffer-native-independent-llvm", buffer_native_llvm);
	Test.add_func ("/recursive-ownership/partial-core", partial_core);
	Test.add_func ("/recursive-ownership/partial-cfg", partial_cfg);
	Test.add_func ("/recursive-ownership/partial-ssa", partial_ssa);
	Test.add_func ("/recursive-ownership/partial-native-independent-llvm", partial_native_llvm);
	Test.add_func ("/recursive-ownership/transport-core-cfg", transport_core_cfg);
	Test.add_func ("/recursive-ownership/transport-ssa", transport_ssa);
	Test.add_func ("/recursive-ownership/transport-native-independent-llvm", transport_native_llvm);
	Test.add_func ("/recursive-ownership/transport-commit-order", transport_commit_order);
	Test.add_func ("/recursive-ownership/transport-parameter-order", transport_parameter_order);
	Test.add_func ("/recursive-ownership/transport-buffer-pairs", transport_buffer_pairs);
	Test.add_func ("/recursive-ownership/transport-buffer-native-independent-llvm", transport_buffer_native_llvm);
	Test.add_func ("/recursive-ownership/transport-buffer-retirement", transport_buffer_retirement);
	return Test.run ();
}
}
