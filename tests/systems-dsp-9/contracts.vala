// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;
using Astra.Vapi;

namespace Astra.Tests.SystemsDsp {
private const string PROGRAM = "void write(u32* p,u32 value){volatile_store(*p,value);}u32 read(u32* p){return volatile_load(*p);}f64<2> fp(f64<2> a,f64<2> b){return a*b+a;}i64<2> saturate(i64<2> a,i64<2> b){return sat_add(a,b);}";

private CheckedProgram check(string source = PROGRAM) {
	var syntax = Parser.parse (new SourceFile.from_text ("systems-dsp-contract", source));
	assert (syntax.diagnostic == null);
	var result = SemanticAnalyzer.analyze (syntax.unit);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}
private void core_reject(CoreProgram program) {
	bool rejected = false;
	try {
		CoreVerifier.verify (program);
	} catch (CoreError error) {
		rejected = true;
		Test.message ("%s", error.message);
	}
	assert (rejected);
}
private void cfg_reject(CfgProgram program) {
	bool rejected = false;
	try {
		CfgVerifier.verify (program);
	} catch (CfgError error) {
		rejected = true;
		Test.message ("%s", error.message);
	}
	assert (rejected);
}
private void ssa_reject(SsaProgram program) {
	bool rejected = false;
	try {
		SsaVerifier.verify (program);
	} catch (SsaError error) {
		rejected = true;
		Test.message ("%s", error.message);
	}
	assert (rejected);
}
private void llvm_reject(LlvmModuleArtifact artifact) {
	bool rejected = false;
	try {
		artifact.verify ();
	} catch (LlvmError error) {
		rejected = true;
		Test.message ("%s", error.message);
	}
	assert (rejected);
}
private LlvmModuleArtifact fresh_artifact() throws GLib.Error {
	var source = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (check ())));
	var native = NativeAbiBuilder.build (source);
	return LlvmLowering.lower (source, native, CAbiBuilder.build (source, native));
}

private void checked_contract() {
	try {
		var program = check ();
		var store = (CheckedStore) program.functions[0].body.statements[0];
		assert (store.volatile_access != null && store.volatile_enabled);
		store.volatile_enabled = false;
		bool rejected = false;
		try {
			CoreBuilder.build (program);
		} catch (CoreError error) {
			rejected = true;
			Test.message ("%s", error.message);
		}
		assert (rejected);
		store.volatile_enabled = true;
		CoreVerifier.verify (CoreBuilder.build (program));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void core_contract() {
	try {
		var program = CoreBuilder.build (check ());
		var store = (CoreStore) program.functions[0].body.statements[0];
		store.volatile_enabled = false;
		core_reject (program);
		store.volatile_enabled = true;
		CoreVerifier.verify (program);
		var load = (CoreLoadValue) ((CoreReturn) program.functions[1].body.statements[0]).value;
		load.volatile_enabled = false;
		core_reject (program);
		load.volatile_enabled = true;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void cfg_contract() {
	try {
		var program = CfgBuilder.build (CoreBuilder.build (check ()));
		int tested = 0;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var store = instruction as CfgStore;
					if (store != null && store.volatile_access != null) {
						store.volatile_enabled = false;
						cfg_reject (program);
						store.volatile_enabled = true;
						CfgVerifier.verify (program);
						tested++;
					}
					var evaluation = instruction as CfgEvaluateInstruction;
					var load = evaluation == null ? null : evaluation.value as CfgLoadValue;
					if (load != null && load.volatile_access != null) {
						load.volatile_enabled = false;
						cfg_reject (program);
						load.volatile_enabled = true;
						CfgVerifier.verify (program);
						tested++;
					}
				}
			}
		}
		assert (tested == 2);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void ssa_contract() {
	try {
		var program = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (check ())));
		int tested = 0;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var instruction = block.instructions[i];
					var store = instruction as SsaStoreInstruction;
					if (store != null && store.volatile_access != null) {
						store.volatile_enabled = false;
						ssa_reject (program);
						store.volatile_enabled = true;
						SsaVerifier.verify (program);
						tested++;
						block.instructions.remove_index (i);
						ssa_reject (program);
						block.instructions.insert (i, instruction);
						SsaVerifier.verify (program);
						tested++;
					}
				}
			}
		}
		assert (tested == 2);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void native_contract() {
	try {
		var program = NativeAbiBuilder.build (SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (check ()))));
		var signature = program.functions[2].signature;
		var original = signature.parameters[0];
		signature.parameters[0] = new NativeParameter.typed (original.span, original.name_span, original.name, 0, new NativeVectorType (NativeScalarType.F64, 4));
		bool rejected = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			rejected = true;
			Test.message ("%s", error.message);
		}
		assert (rejected);
		signature.parameters[0] = original;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void physical_contract() {
	try {
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (check ())));
		var upstream = WeakRef (source.functions[0]);
		var native = NativeAbiBuilder.build (source);
		var artifact = LlvmLowering.lower (source, native, CAbiBuilder.build (source, native));
		source = null;
		assert (upstream.get () == null && artifact.volatile_accesses.length == 2 && artifact.saturations.length == 1);
		foreach (var access in artifact.volatile_accesses) {
			var operation = access.operation;
			CApi.set_volatile (operation, 0);
			llvm_reject (artifact);
			CApi.set_volatile (operation, 1);
			artifact.verify ();
			uint alignment = CApi.get_alignment (operation);
			CApi.set_alignment (operation, 1);
			llvm_reject (artifact);
			CApi.set_alignment (operation, alignment);
			artifact.verify ();
			uint index = CApi.opcode (operation) == CApi.Opcode.STORE ? 1 : 0;
			var pointer = CApi.operand (operation, index);
			CApi.set_operand (operation, index, CApi.const_null (CApi.type_of (pointer)));
			llvm_reject (artifact);
			CApi.set_operand (operation, index, pointer);
			artifact.verify ();
		}
		var call = artifact.saturations[0].call;
		var argument = CApi.operand (call, 0);
		CApi.set_operand (call, 0, CApi.const_null (CApi.type_of (argument)));
		llvm_reject (artifact);
		CApi.set_operand (call, 0, argument);
		artifact.verify ();
		var signed_callee = CApi.called_value (call);
		string unsigned_name = "llvm.uadd.sat";
		uint unsigned_id = CApi.lookup_intrinsic_id (unsigned_name, unsigned_name.length);
		CApi.TypeRef[] overloads = {
			CApi.type_of (argument)
		};
		var unsigned_callee = CApi.get_intrinsic_declaration (artifact.module, unsigned_id, overloads, 1);
		CApi.set_operand (call, 2, unsigned_callee);
		llvm_reject (artifact);
		CApi.set_operand (call, 2, signed_callee);
		artifact.verify ();
		var following = CApi.next_instruction (call);
		CApi.remove_instruction (call);
		llvm_reject (artifact);
		var restoration = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_before (restoration, following);
		CApi.insert_instruction (restoration, call);
		CApi.dispose_builder (restoration);
		artifact.verify ();
		int floating = 0;
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.can_use_fast_math_flags (instruction) == 0) {
						continue;
					}
					// LLVM's setter adds flags. Mutate a fresh artifact and retain
					// the independently rebuilt strict positive after rejection.
					var candidate = fresh_artifact ();
					int index = 0;
					bool changed = false;
					for (var cf = CApi.first_function (candidate.module); (void*) cf != null; cf = CApi.next_function (cf)) {
						for (var cb = CApi.first_block (cf); (void*) cb != null; cb = CApi.next_block (cb)) {
							for (var ci = CApi.first_instruction (cb); (void*) ci != null; ci = CApi.next_instruction (ci)) {
								if (CApi.can_use_fast_math_flags (ci) != 0 && index++ == floating) {
									CApi.set_fast_math_flags (ci, 1);
									changed = true;
								}
							}
						}
					}
					assert (changed);
					llvm_reject (candidate);
					artifact.verify ();
					floating++;
				}
			}
		}
		assert (floating == 2);
		var profile = new LlvmRuntimeProfile (new LlvmTargetMachineArtifact ().triple);
		artifact.runtime_profile = profile;
		artifact.verify ();
		var type = CApi.function_type (CApi.void_type_in_context (artifact.context), null, 0, 0);
		var provider = CApi.add_function (artifact.module, "hidden_host_provider", type);
		llvm_reject (artifact);
		CApi.delete_function (provider);
		artifact.verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private CheckedProgram arena_checked() throws GLib.Error {
	var text = new StringBuilder ();
	foreach (string path in new string[] { "lib/astra/base/errors.astra", "lib/astra/memory/byte-arena.astra", "lib/astra/memory/packet-arena.astra" }) {
		string source;
		FileUtils.get_contents (path, out source);
		text.append (source + "\n");
	}
	text.append ("int main(){return 0;}");
	string api;
	FileUtils.get_contents ("lib/astra/memory/packet-resource.vapi", out api);
	var syntax = Parser.parse (new SourceFile.from_text ("live-packet-arena", text.str));
	var vapi = VapiParser.parse (new SourceFile.from_text ("packet-resource.vapi", api));
	assert (syntax.diagnostic == null && vapi.diagnostic == null);
	var result = SemanticAnalyzer.analyze (syntax.unit, VapiNormalizer.normalize (vapi.file), VapiNormalizer.normalize_handles (vapi.file));
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}
private void arena_contract() {
	try {
		var core = CoreBuilder.build (arena_checked ());
		int tested = 0;
		foreach (var owner in core.classes) {
			if (owner.name != "PacketArena") {
				continue;
			}
			var body = owner.constructor.body;
			for (int i = 0; i < body.statements.length; i++) {
				var transfer = body.statements[i] as CoreOwnedFieldTransfer;
				if (transfer == null) {
					continue;
				}
				body.statements.remove_index (i);
				core_reject (core);
				body.statements.insert (i, transfer);
				CoreVerifier.verify (core);
				tested++;
			}
		}
		assert (tested == 3);
		var cfg = CfgBuilder.build (core);
		tested = 0;
		foreach (var function in cfg.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var cleanup = block.instructions[i] as CfgCleanupInstruction;
					var load = cleanup == null ? null : cleanup.value as CfgLoadValue;
					if (load == null || !(load.source is CfgIndirectFieldPlace) || load.semantic_type.display_name () != "PacketResource") {
						continue;
					}
					block.instructions.remove_index (i);
					cfg_reject (cfg);
					block.instructions.insert (i, cleanup);
					CfgVerifier.verify (cfg);
					tested++;
				}
			}
		}
		assert (tested >= 2);
		var ssa = SsaBuilder.build (cfg);
		tested = 0;
		foreach (var function in ssa.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var cleanup = block.instructions[i] as SsaCleanupInstruction;
					if (cleanup == null || cleanup.value.semantic_type.display_name () != "PacketResource") {
						continue;
					}
					block.instructions.remove_index (i);
					ssa_reject (ssa);
					block.instructions.insert (i, cleanup);
					SsaVerifier.verify (ssa);
					tested++;
					block.instructions.insert (i + 1, cleanup);
					ssa_reject (ssa);
					block.instructions.remove_index (i + 1);
					SsaVerifier.verify (ssa);
				}
			}
		}
		assert (tested >= 2);
		var native = NativeAbiBuilder.build (ssa);
		foreach (var owner in native.classes) {
			if (owner.name != "PacketArena") {
				continue;
			}
			var field = owner.fields[1];
			owner.fields.remove_index (1);
			bool rejected = false;
			try {
				NativeAbiVerifier.verify (native);
			} catch (NativeAbiError error) {
				rejected = true;
				Test.message ("%s", error.message);
			}
			assert (rejected);
			owner.fields.insert (1, field);
			NativeAbiVerifier.verify (native);
		}
		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		tested = 0;
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) != CApi.Opcode.CALL || CApi.argument_count (instruction) != 1) {
						continue;
					}
					size_t length;
					if (CApi.value_name (CApi.called_value (instruction), out length) != "astra_packet_resource_close") {
						continue;
					}
					var pointer = CApi.operand (instruction, 0);
					CApi.set_operand (instruction, 0, CApi.const_null (CApi.type_of (pointer)));
					llvm_reject (artifact);
					CApi.set_operand (instruction, 0, pointer);
					artifact.verify ();
					tested++;
				}
			}
		}
		assert (tested >= 2);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/systems-dsp/checked-volatile-contract", checked_contract);
	Test.add_func ("/systems-dsp/core-volatile-contract", core_contract);
	Test.add_func ("/systems-dsp/cfg-volatile-contract", cfg_contract);
	Test.add_func ("/systems-dsp/ssa-volatile-effect", ssa_contract);
	Test.add_func ("/systems-dsp/native-vector-shape", native_contract);
	Test.add_func ("/systems-dsp/physical-numeric-memory-runtime", physical_contract);
	Test.add_func ("/systems-dsp/live-arena-ownership", arena_contract);
	return Test.run ();
}
}
