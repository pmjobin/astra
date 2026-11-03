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

namespace Astra.Tests.EnumScalarOwnership {
private CheckedProgram sample(bool record = false, bool buffers = false) throws GLib.Error {
	string source, api, errors;
	FileUtils.get_contents (record ? "tests/language-generalization-10/enum-record.astra" : "tests/language-generalization-10/enum-scalar.astra", out source);
	if (buffers) {
		source = "enum Buffer{Ready(owned int[] data),Empty}int main(){var owner=Buffer.Ready(new int[2]);match(move owner){case Buffer.Ready(data):{return len(data)-2;}else:{return 1;}}}";
	}
	FileUtils.get_contents ("tests/own-field/fixtures/resources.vapi", out api);
	FileUtils.get_contents ("lib/astra/base/errors.astra", out errors);
	var syntax = Parser.parse (new SourceFile.from_text ("enum-scalar.astra", source + errors));
	var vapi = VapiParser.parse (new SourceFile.from_text ("resources.vapi", api));
	assert (syntax.diagnostic == null && vapi.diagnostic == null);
	var result = SemanticAnalyzer.analyze (syntax.unit, VapiNormalizer.normalize (vapi.file), VapiNormalizer.normalize_handles (vapi.file));
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}

private SsaProgram ssa_sample(bool record = false, bool buffers = false) throws GLib.Error {
	return SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (sample (record, buffers))));
}

private void core_capture() {
	try {
		var program = CoreBuilder.build (sample ());
		int tested = 0;
		foreach (var function in program.functions) {
			for (int i = 0; i < function.body.statements.length; i++) {
				var store = function.body.statements[i] as CoreEnumStore;
				var construction = store == null ? null : store.producer as CoreEnumConstruct;
				if (construction == null || construction.fields.length == 0) {
					continue;
				}
				var first = construction.fields[0];
				var capture = first.scalar as CoreEnumScalarValue;
				if (capture == null) {
					continue;
				}
				var fields = new GenericArray<CoreEnumFieldValue> ();
				fields.add (new CoreEnumFieldValue (first.span, first.field, new CoreLoadValue (first.span, capture.source.place), null, null));
				for (int f = 1; f < construction.fields.length; f++) {
					fields.add (construction.fields[f]);
				}
				var wrong = new CoreEnumConstruct (construction.span, construction.definition, construction.variant, fields, construction.instance);
				function.body.statements[i] = new CoreEnumStore (store.span, store.destination, wrong, store.initializes_destination);
				bool rejected = false;
				try {
					CoreVerifier.verify (program);
				} catch (CoreError error) {
					rejected = true;
					Test.message ("%s", error.message);
				}
				assert (rejected);
				function.body.statements[i] = store;
				CoreVerifier.verify (program);
				tested++;
			}
		}
		assert (tested >= 4);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void cfg_reservations() {
	try {
		var program = CfgBuilder.build (CoreBuilder.build (sample ()));
		int captures = 0, aborts = 0, bindings = 0;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var instruction = block.instructions[i];
					if (!(instruction is CfgEnumScalarCapture || instruction is CfgEnumScalarAbort || instruction is CfgEnumExtractScalar)) {
						continue;
					}
					if (instruction is CfgEnumScalarCapture) {
						var capture = (CfgEnumScalarCapture) instruction;
						block.instructions[i] = new CfgEvaluateInstruction (capture.span, capture.value, capture.result);
						captures++;
					} else {
						block.instructions.remove_index (i);
						if (instruction is CfgEnumScalarAbort) {
							aborts++;
						} else {
							bindings++;
						}
					}
					bool rejected = false;
					try {
						CfgVerifier.verify (program);
					} catch (CfgError error) {
						rejected = true;
						Test.message ("%s", error.message);
					}
					assert (rejected);
					if (instruction is CfgEnumScalarCapture) {
						block.instructions[i] = instruction;
					} else {
						block.instructions.insert (i, instruction);
					}
					CfgVerifier.verify (program);
				}
			}
		}
		assert (captures >= 6 && aborts == 2 && bindings >= 4);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void ssa_responsibility() {
	try {
		var program = ssa_sample ();
		int captures = 0, commits = 0, aborts = 0, bindings = 0, events = 0;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var instruction = block.instructions[i];
					var event = instruction as SsaHeapOwnerEvent;
					bool associated = event != null && (event.effect is SsaEnumScalarCapture || event.effect is SsaEnumScalarCommit || event.effect is SsaEnumReadScalar);
					if (!(instruction is SsaEnumScalarCapture || instruction is SsaEnumScalarCommit || instruction is SsaEnumScalarAbort || instruction is SsaEnumReadScalar || associated)) {
						continue;
					}
					if (instruction is SsaEnumScalarCapture) {
						captures++;
					}
					if (instruction is SsaEnumScalarCommit) {
						commits++;
					}
					if (instruction is SsaEnumScalarAbort) {
						aborts++;
					}
					if (instruction is SsaEnumReadScalar) {
						bindings++;
					}
					if (associated) {
						events++;
					}
					block.instructions.remove_index (i);
					bool rejected = false;
					try {
						SsaVerifier.verify (program);
					} catch (SsaError error) {
						rejected = true;
						Test.message ("%s", error.message);
					}
					assert (rejected);
					block.instructions.insert (i, instruction);
					SsaVerifier.verify (program);
				}
			}
		}
		assert (captures >= 6 && commits == captures && aborts == 2 && bindings >= 4 && events == 2 * captures + bindings);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void independent_native() {
	try {
		SsaProgram? source = ssa_sample ();
		var predecessor = WeakRef (source.functions[0]);
		var program = NativeAbiBuilder.build (source);
		source = null;
		assert (predecessor.get () == null);
		NativeAbiVerifier.verify (program);
		int tested = 0;
		foreach (var plan in program.sum_values) {
			foreach (var variant in plan.variants) {
				for (int f = 0; f < variant.fields.length; f++) {
					var field = variant.fields[f];
					if (field.scalar_owner == null) {
						continue;
					}
					for (int mutation = 0; mutation < 4; mutation++) {
						var owner = field.scalar_owner;
						var wrong = mutation == 0 ? null : new NativeScalarOwner (owner.type_name, mutation == 1 ? "wrong_cleanup" : owner.cleanup_symbol, mutation == 2 ? program.classes.length : owner.class_ordinal);
						variant.fields[f] = new NativeSumField (field.identity, mutation == 3 ? new NativeScalarAbiType (NativeScalarType.I64) : field.leaf, null, null, null, wrong);
						bool rejected = false;
						try {
							NativeAbiVerifier.verify (program);
						} catch (NativeAbiError error) {
							rejected = true;
							Test.message ("%s", error.message);
						}
						assert (rejected);
						variant.fields[f] = field;
						NativeAbiVerifier.verify (program);
						tested++;
					}
					variant.fields.remove_index (f);
					bool rejected = false;
					try {
						NativeAbiVerifier.verify (program);
					} catch (NativeAbiError error) {
						rejected = true;
					}
					assert (rejected);
					variant.fields.insert (f, field);
					NativeAbiVerifier.verify (program);
				}
			}
		}
		assert (tested >= 20);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private LlvmModuleArtifact artifact(bool record = false) throws GLib.Error {
	SsaProgram? source = ssa_sample (record);
	var predecessor = WeakRef (source.functions[0]);
	NativeAbiProgram? native = NativeAbiBuilder.build (source);
	CAbiProgram? foreign = CAbiBuilder.build (source, native);
	var native_function = WeakRef (native.functions[0]);
	var result = LlvmLowering.lower (source, native, foreign);
	source = null;
	native = null;
	foreign = null;
	assert (predecessor.get () == null && native_function.get () == null);
	var target = new LlvmTargetMachineArtifact ();
	target.configure (result);
	result.verify ();
	return result;
}

private void ordinary(LlvmModuleArtifact module) {
	char* message;
	int failed = CApi.verify_module (module.module, CApi.VerifierFailureAction.RETURN_STATUS, out message);
	if (failed != 0) {
		GLib.error ("ordinary LLVM fixture failure: %s", (string) message);
	}
	if (message != null) {
		CApi.dispose_message (message);
	}
}

private void independent_llvm() {
	try {
		var module = artifact ();
		int resources = 0, reads = 0;
		for (var function = CApi.first_function (module.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					size_t length;
					bool resource = false, extraction = false;
					if (CApi.opcode (instruction) == CApi.Opcode.CALL) {
						resource = CApi.value_name (CApi.called_value (instruction), out length) == "of_release" || CApi.value_name (CApi.called_value (instruction), out length) == "of_release_other";
					}
					if (CApi.opcode (instruction) == CApi.Opcode.LOAD) {
						extraction = CApi.value_name (instruction, out length).has_prefix ("sum.extract.owner");
					}
					if (!resource && !extraction) {
						continue;
					}
					var original = CApi.operand (instruction, 0);
					var empty = CApi.const_null (CApi.type_of (original));
					if ((void*) original == (void*) empty) {
						continue;
					}
					CApi.set_operand (instruction, 0, empty);
					ordinary (module);
					bool rejected = false;
					try {
						module.verify ();
					} catch (LlvmError error) {
						rejected = true;
						Test.message ("%s", error.message);
					}
					assert (rejected);
					CApi.set_operand (instruction, 0, original);
					ordinary (module);
					module.verify ();
					if (resource) {
						resources++;
					} else {
						reads++;
					}
				}
			}
		}
		assert (resources >= 6 && reads >= 4);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void record_core() {
	try {
		var program = CoreBuilder.build (sample (true));
		int tested = 0;
		foreach (var function in program.functions) {
			for (int i = 0; i < function.body.statements.length; i++) {
				var store = function.body.statements[i] as CoreEnumStore;
				var construction = store == null ? null : store.producer as CoreEnumConstruct;
				if (construction == null) {
					continue;
				}
				for (int f = 0; f < construction.fields.length; f++) {
					var input = construction.fields[f];
					var move = input.record as CoreStructMoveProducer;
					if (move == null) {
						continue;
					}
					var fields = new GenericArray<CoreEnumFieldValue> ();
					foreach (var field in construction.fields) {
						fields.add (field);
					}
					fields[f] = new CoreEnumFieldValue (input.span, input.field, null, new CoreStructSnapshot (input.span, move.source.place), null);
					var copied = new CoreEnumConstruct (construction.span, construction.definition, construction.variant, fields, construction.instance);
					function.body.statements[i] = new CoreEnumStore (store.span, store.destination, copied, store.initializes_destination);
					bool rejected = false;
					try {
						CoreVerifier.verify (program);
					} catch (CoreError error) {
						rejected = true;
						Test.message ("%s", error.message);
					}
					assert (rejected);
					function.body.statements[i] = store;
					CoreVerifier.verify (program);
					tested++;
				}
			}
		}
		assert (tested >= 4);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void record_cfg() {
	try {
		var program = CfgBuilder.build (CoreBuilder.build (sample (true)));
		int commits = 0, bindings = 0;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var instruction = block.instructions[i];
					var move = instruction as CfgStructBoundaryMove;
					if (!(instruction is CfgEnumExtractRecord) && (move == null || move.use_kind != StructResultUseKind.ENUM_PAYLOAD)) {
						continue;
					}
					block.instructions.remove_index (i);
					bool rejected = false;
					try {
						CfgVerifier.verify (program);
					} catch (CfgError error) {
						rejected = true;
						Test.message ("%s", error.message);
					}
					assert (rejected);
					block.instructions.insert (i, instruction);
					CfgVerifier.verify (program);
					if (move != null) {
						commits++;
					} else {
						bindings++;
					}
				}
			}
		}
		assert (commits >= 5 && bindings >= 2);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void record_ssa() {
	try {
		var program = ssa_sample (true);
		int commits = 0, bindings = 0, pairs = 0;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var instruction = block.instructions[i];
					var move = instruction as SsaStructBoundaryMove;
					var read = instruction as SsaEnumReadRecord;
					var disarm = instruction as SsaBufferWriteInstruction;
					bool record_disarm = disarm != null && disarm.record_boundary is SsaStructBoundaryMove && ((SsaStructBoundaryMove) disarm.record_boundary).use_kind == StructResultUseKind.ENUM_PAYLOAD;
					if (read == null && !record_disarm && (move == null || move.use_kind != StructResultUseKind.ENUM_PAYLOAD)) {
						continue;
					}
					block.instructions.remove_index (i);
					bool rejected = false;
					try {
						SsaVerifier.verify (program);
					} catch (SsaError error) {
						rejected = true;
						Test.message ("%s", error.message);
					}
					assert (rejected);
					block.instructions.insert (i, instruction);
					SsaVerifier.verify (program);
					if (move != null) {
						commits++;
					}
					if (record_disarm) {
						pairs++;
					}
					if (read != null) {
						bindings++;
						var pair = read.results.buffers[0];
						read.results.buffers.remove_index (0);
						rejected = false;
						try {
							SsaVerifier.verify (program);
						} catch (SsaError error) {
							rejected = true;
							Test.message ("%s", error.message);
						}
						assert (rejected);
						read.results.buffers.insert (0, pair);
						SsaVerifier.verify (program);
					}
				}
			}
		}
		assert (commits >= 5 && bindings >= 2 && pairs == commits);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void consuming_disposition() {
	try {
		int tested = 0;
		for (int profile = 0; profile < 3; profile++) {
			var cfg = CfgBuilder.build (CoreBuilder.build (sample (profile == 1, profile == 2)));
			foreach (var function in cfg.functions) {
				foreach (var block in function.blocks) {
					for (int i = 0; i < block.instructions.length; i++) {
						var finish = block.instructions[i] as CfgEnumFinishArm;
						if (finish == null || finish.retained_count == 0) {
							continue;
						}
						block.instructions[i] = new CfgEnumDrop (finish.span, finish.source);
						bool rejected = false;
						try {
							CfgVerifier.verify (cfg);
						} catch (CfgError error) {
							rejected = true;
							Test.message ("%s", error.message);
						}
						assert (rejected);
						block.instructions[i] = finish;
						CfgVerifier.verify (cfg);
						tested++;
					}
				}
			}
			var ssa = ssa_sample (profile == 1, profile == 2);
			foreach (var function in ssa.functions) {
				foreach (var block in function.blocks) {
					for (int i = 0; i < block.instructions.length; i++) {
						var finish = block.instructions[i] as SsaEnumFinishArm;
						if (finish == null || finish.retained_count == 0) {
							continue;
						}
						block.instructions[i] = new SsaEnumDrop (finish.span, finish.source);
						bool rejected = false;
						try {
							SsaVerifier.verify (ssa);
						} catch (SsaError error) {
							rejected = true;
							Test.message ("%s", error.message);
						}
						assert (rejected);
						block.instructions[i] = finish;
						SsaVerifier.verify (ssa);
						tested++;
					}
				}
			}
		}
		assert (tested >= 16);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void record_native() {
	try {
		SsaProgram? source = ssa_sample (true);
		var predecessor = WeakRef (source.functions[0]);
		var program = NativeAbiBuilder.build (source);
		source = null;
		assert (predecessor.get () == null);
		int fields = 0;
		foreach (var enumeration in program.sum_values) {
			foreach (var variant in enumeration.variants) {
				for (int f = 0; f < variant.fields.length; f++) {
					var field = variant.fields[f];
					if (field.record_value == null) {
						continue;
					}
					fields++;
					variant.fields[f] = new NativeSumField (field.identity, new NativeScalarAbiType (NativeScalarType.PTR), null, null);
					bool rejected = false;
					try {
						NativeAbiVerifier.verify (program);
					} catch (NativeAbiError error) {
						rejected = true;
						Test.message ("%s", error.message);
					}
					assert (rejected);
					variant.fields[f] = field;
					NativeAbiVerifier.verify (program);
					var plan = field.record_value;
					var owner = plan.ownership[0];
					plan.ownership.remove_index (0);
					rejected = false;
					try {
						NativeAbiVerifier.verify (program);
					} catch (NativeAbiError error) {
						rejected = true;
						Test.message ("%s", error.message);
					}
					assert (rejected);
					plan.ownership.insert (0, owner);
					NativeAbiVerifier.verify (program);
					for (int l = 0; l < plan.leaves.length; l++) {
						var leaf = plan.leaves[l];
						if (leaf.buffer_component != 1) {
							continue;
						}
						plan.leaves[l] = new NativeStructLeafChannel (leaf.field_path, new NativeScalarAbiType (NativeScalarType.I64), leaf.storage_path, 1);
						rejected = false;
						try {
							NativeAbiVerifier.verify (program);
						} catch (NativeAbiError error) {
							rejected = true;
							Test.message ("%s", error.message);
						}
						assert (rejected);
						plan.leaves[l] = leaf;
						NativeAbiVerifier.verify (program);
					}
				}
			}
		}
		assert (fields == 3);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void record_llvm() {
	try {
		var module = artifact (true);
		int paths = 0;
		for (var function = CApi.first_function (module.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					size_t length;
					if (CApi.opcode (instruction) != CApi.Opcode.GEP || !CApi.value_name (instruction, out length).has_prefix ("sum.record.value.leaf")) {
						continue;
					}
					var original = CApi.operand (instruction, 2);
					uint ordinal = (uint) CApi.const_int_zext (original), replacement = ordinal;
					var layout = CApi.gep_source_type (instruction);
					var member_type = CApi.struct_get_type_at_index (layout, ordinal);
					for (uint member = 0; member < CApi.count_struct_element_types (layout); member++) {
						if (member != ordinal && (void*) CApi.struct_get_type_at_index (layout, member) == (void*) member_type) {
							replacement = member;
							break;
						}
					}
					if (replacement == ordinal) {
						continue;
					}
					var changed = CApi.const_int (CApi.type_of (original), replacement, 0);
					CApi.set_operand (instruction, 2, changed);
					ordinary (module);
					bool rejected = false;
					try {
						module.verify ();
					} catch (LlvmError error) {
						rejected = true;
						Test.message ("%s", error.message);
					}
					assert (rejected);
					CApi.set_operand (instruction, 2, original);
					ordinary (module);
					module.verify ();
					paths++;
				}
			}
		}
		assert (paths >= 30);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/enum-scalar/core-named-owner-authority", core_capture);
	Test.add_func ("/enum-scalar/cfg-capture-abort-binding", cfg_reservations);
	Test.add_func ("/enum-scalar/ssa-owner-loan-commit-acquisition", ssa_responsibility);
	Test.add_func ("/enum-scalar/independent-native-disposal", independent_native);
	Test.add_func ("/enum-scalar/independent-llvm-cleanup-and-read", independent_llvm);
	Test.add_func ("/enum-record/core-move-authority", record_core);
	Test.add_func ("/enum-record/cfg-commit-and-binding", record_cfg);
	Test.add_func ("/enum-record/ssa-commit-acquisition-and-pairs", record_ssa);
	Test.add_func ("/enum-record/consuming-binding-disposition", consuming_disposition);
	Test.add_func ("/enum-record/independent-native-cleanup-and-pairs", record_native);
	Test.add_func ("/enum-record/independent-llvm-record-paths", record_llvm);
	return Test.run ();
}

}
