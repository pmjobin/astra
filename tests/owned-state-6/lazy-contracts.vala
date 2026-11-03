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
namespace Astra.Tests.OwnedState {
private CheckedProgram lazy_checked() throws GLib.Error {
	string source, errors;
	FileUtils.get_contents ("tests/owned-state-6/owning-checked-lazy.astra", out source);
	FileUtils.get_contents ("lib/astra/base/errors.astra", out errors);
	var syntax = Parser.parse (new SourceFile.from_text ("owned-lazy-proof", source + errors));
	assert (syntax.diagnostic == null);
	var result = SemanticAnalyzer.analyze (syntax.unit);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}

private void lazy_checked_core() {
	try {
		var checked = lazy_checked ();
		PropertySymbol? property = null;
		foreach (var owner in checked.classes) {
			foreach (var member in owner.properties) {
				if (member.is_owned_lazy) {
					property = member;
				}
			}
		}
		assert (property != null);
		var factory = property.factory;
		property.factory = null;
		bool rejected = false;
		try {
			CoreVerifier.verify (CoreBuilder.build (checked));
		} catch (CoreError error) {
			rejected = true;
			Test.message ("%s", error.message);
		}
		assert (rejected);
		property.factory = factory;
		CoreVerifier.verify (CoreBuilder.build (checked));
		var core = CoreBuilder.build (checked);
		CoreProperty? cache = null;
		foreach (var owner in core.classes) {
			foreach (var member in owner.properties) {
				if (member.is_owned_lazy) {
					cache = member;
				}
			}
		}
		assert (cache != null);
		var producer = cache.factory;
		cache.factory = null;
		core_reject (core);
		cache.factory = producer;
		CoreVerifier.verify (core);
		cache.is_borrowed = false;
		core_reject (core);
		cache.is_borrowed = true;
		CoreVerifier.verify (core);
		var destructor = ((CoreClass) cache.declaring_type).destructor;
		var cleanup = destructor.lazy_cleanups[0];
		destructor.lazy_cleanups.remove_index (0);
		core_reject (core);
		destructor.lazy_cleanups.add (cleanup);
		CoreVerifier.verify (core);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void lazy_cfg() {
	try {
		var graph = CfgBuilder.build (CoreBuilder.build (lazy_checked ()));
		CfgVerifier.verify (graph);
		int tested = 0;
		foreach (var f in graph.functions) {
			foreach (var block in f.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var drop = block.instructions[i] as CfgLazyDrop;
					if (drop != null) {
						block.instructions.remove_index (i);
						cfg_reject (graph);
						block.instructions.insert (i, drop);
						CfgVerifier.verify (graph);
						tested++;
						block.instructions.insert (i, drop);
						cfg_reject (graph);
						block.instructions.remove_index (i);
						CfgVerifier.verify (graph);
						tested++;
					}
					var success = block.instructions[i] as CfgCallSuccess;
					if (success != null && success.call.target.result_contract == ResultOwnershipContract.RECEIVER_BORROW) {
						block.instructions[i] = new CfgCallSuccess (success.span, success.call);
						cfg_reject (graph);
						block.instructions[i] = success;
						CfgVerifier.verify (graph);
						tested++;
					}
				}
			}
		}
		assert (tested >= 5);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void lazy_ssa() {
	try {
		var model = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (lazy_checked ())));
		SsaVerifier.verify (model);
		int tested = 0;
		foreach (var f in model.functions) {
			foreach (var block in f.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var drop = block.instructions[i] as SsaLazyDrop;
					if (drop != null) {
						block.instructions.remove_index (i);
						ssa_reject (model);
						block.instructions.insert (i, drop);
						SsaVerifier.verify (model);
						tested++;
						block.instructions.insert (i, drop);
						ssa_reject (model);
						block.instructions.remove_index (i);
						SsaVerifier.verify (model);
						tested++;
					}
					var success = block.instructions[i] as SsaCallSuccess;
					if (success != null && success.call.target.result_contract == ResultOwnershipContract.RECEIVER_BORROW) {
						var exception = success.call.exception_result;
						success.call.exception_result = null;
						ssa_reject (model);
						success.call.exception_result = exception;
						SsaVerifier.verify (model);
						tested++;
					}
				}
			}
		}
		assert (tested >= 5);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void lazy_native() {
	try {
		var model = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (lazy_checked ())));
		var native = NativeAbiBuilder.build (model);
		int tested = 0;
		foreach (var owner in native.classes) {
			foreach (var cache in owner.lazy_caches) {
				if (!cache.is_owned) {
					continue;
				}
				var getter = native.functions[cache.getter_ordinal];
				var factory = native.functions[cache.factory_ordinal];
				int ordinal = cache.factory_ordinal;
				cache.factory_ordinal = cache.getter_ordinal;
				native_reject (native);
				cache.factory_ordinal = ordinal;
				NativeAbiVerifier.verify (native);
				tested++;
				var result = factory.signature.heap_result;
				factory.signature.heap_result = null;
				native_reject (native);
				factory.signature.heap_result = result;
				NativeAbiVerifier.verify (native);
				tested++;
				getter.signature.heap_result = result;
				native_reject (native);
				getter.signature.heap_result = null;
				NativeAbiVerifier.verify (native);
				tested++;
				var bound = getter.signature.exception_plan;
				getter.signature.exception_plan = null;
				native_reject (native);
				getter.signature.exception_plan = bound;
				NativeAbiVerifier.verify (native);
				tested++;
				getter.receiver_borrow = false;
				native_reject (native);
				getter.receiver_borrow = true;
				NativeAbiVerifier.verify (native);
				tested++;
			}
		}
		assert (tested == 5);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_reject(NativeAbiProgram program) {
	bool rejected = false;
	try {
		NativeAbiVerifier.verify (program);
	} catch (NativeAbiError error) {
		rejected = true;
		Test.message ("%s", error.message);
	}
	assert (rejected);
}

private void lazy_independent_llvm() {
	try {
		CheckedProgram? checked = lazy_checked ();
		var old = WeakRef (checked.classes[1].properties[0].getter);
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		assert (old.get () == null);
		old = WeakRef (core.classes[1].properties[0].getter);
		CfgProgram? graph = CfgBuilder.build (core);
		core = null;
		assert (old.get () == null);
		old = WeakRef (graph.classes[1].properties[0].getter);
		SsaProgram? model = SsaBuilder.build (graph);
		graph = null;
		assert (old.get () == null);
		var native = NativeAbiBuilder.build (model);
		var artifact = LlvmLowering.lower (model, native, CAbiBuilder.build (model, native));
		old = WeakRef (model.classes[1].properties[0].getter);
		model = null;
		assert (old.get () == null);
		NativeAbiVerifier.verify (native);
		artifact.verify ();
		int tested = 0;
		for (var f = CApi.first_function (artifact.module); (void*) f != null; f = CApi.next_function (f)) {
			for (var block = CApi.first_block (f); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) != CApi.Opcode.STORE) {
						continue;
					}
					size_t length;
					string target = CApi.value_name (CApi.operand (instruction, 1), out length);
					if (target != "lazy.state.address" && !(target.has_prefix ("lazy.retire.") && target.has_suffix (".state.address")) && !(target.contains (".lazy.") && target.has_suffix (".state"))) {
						continue;
					}
					var value = CApi.operand (instruction, 0);
					CApi.set_operand (instruction, 0, CApi.const_int (CApi.type_of (value), 3, 0));
					bool rejected = false;
					try {
						artifact.verify ();
					} catch (LlvmError error) {
						rejected = true;
						Test.message ("%s", error.message);
					}
					assert (rejected);
					CApi.set_operand (instruction, 0, value);
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

internal void register_lazy() {
	Test.add_func ("/owned-state-completion/lazy-checked-core-channels", lazy_checked_core);
	Test.add_func ("/owned-state-completion/lazy-cfg-retirement-and-checked-success", lazy_cfg);
	Test.add_func ("/owned-state-completion/lazy-ssa-retirement-and-checked-success", lazy_ssa);
	Test.add_func ("/owned-state-completion/lazy-native-distinct-channels", lazy_native);
	Test.add_func ("/owned-state-completion/lazy-independent-llvm-states", lazy_independent_llvm);
}

}
