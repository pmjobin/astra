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

namespace Astra.Tests.ConcurrencyContracts {
private CheckedProgram source() {
	var parsed = Parser.parse (new SourceFile.from_text ("concurrency-contract",
		"[Shared,Monitor]class Ledger{private int value;init(){this.value=0;}int constant(){return 7;}int add(int n){this.value=this.value+n;return this.value;}}"
		+ "[ThreadBound]class Local{private int value;init(){this.value=3;}int read(){return this.value;}}"
		+ "class Env{int value;init(){this.value=7;}}int worker(borrowed Env env,int n){return env.value+n;}"
		+ "int main(){var ledger=new Ledger();var copy=ledger.clone();var local=new Local();var env=new Env();var t=thread_bind(move env,worker);if(thread_start(t,2)!=0){return 81;}int joined=thread_join(t);return copy.add(local.read())+joined;}"));
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.message);
	}
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.message);
	}
	return checked.program;
}

private void authority() {
	try {
		var checked = source ();
		var declared = checked.classes[0].concurrency_policy;
		checked.classes[0].concurrency_policy = null;
		bool rejected = false;
		try {
			CoreBuilder.build (checked);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		checked.classes[0].concurrency_policy = declared;
		var core = CoreBuilder.build (checked);
		CoreVerifier.verify (core);
		var core_policy = core.classes[0].concurrency_policy;
		core.classes[0].concurrency_policy = null;
		rejected = false;
		try {
			CoreVerifier.verify (core);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		core.classes[0].concurrency_policy = core_policy;
		CoreVerifier.verify (core);
		var cfg = CfgBuilder.build (core);
		CfgVerifier.verify (cfg);
		var cfg_policy = cfg.classes[0].concurrency_policy;
		cfg.classes[0].concurrency_policy = null;
		rejected = false;
		try {
			CfgVerifier.verify (cfg);
		} catch (CfgError error) {
			rejected = true;
		}
		assert (rejected);
		cfg.classes[0].concurrency_policy = cfg_policy;
		CfgVerifier.verify (cfg);
		var ssa = SsaBuilder.build (cfg);
		SsaVerifier.verify (ssa);
		var ssa_policy = ssa.classes[0].concurrency_policy;
		ssa.classes[0].concurrency_policy = null;
		rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			rejected = true;
		}
		assert (rejected);
		ssa.classes[0].concurrency_policy = ssa_policy;
		SsaVerifier.verify (ssa);
		bool protected_effect = false;
		foreach (var function in ssa.functions) {
			if (function.name != "constant") {
				continue;
			}
			assert (function.effect_facts != null && function.effect_facts.flags == 0);
			var effects = function.effect_facts;
			function.effect_facts = new FunctionEffectFacts (FunctionEffectFacts.NO_EXTERNAL_MEMORY);
			rejected = false;
			try {
				SsaVerifier.verify (ssa);
			} catch (SsaError error) {
				rejected = true;
			}
			assert (rejected);
			function.effect_facts = effects;
			SsaVerifier.verify (ssa);
			protected_effect = true;
		}
		assert (protected_effect);
		var native = NativeAbiBuilder.build (ssa);
		NativeAbiVerifier.verify (native);
		var native_policy = native.classes[0].concurrency_policy;
		native.classes[0].concurrency_policy = null;
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		native.classes[0].concurrency_policy = native_policy;
		NativeAbiVerifier.verify (native);
		var field = native.classes[0].fields[0];
		native.classes[0].fields[0] = new NativeClassField (field.span, field.name, field.type_name, field.ordinal, field.text_snapshot, field.storage_type, field.record_ordinal, false, field.owned_class_ordinal, field.owns_buffer);
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		native.classes[0].fields[0] = field;
		NativeAbiVerifier.verify (native);
		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		artifact.verify ();
		int locks = 0;
		int unlocks = 0;
		int affinity = 0;
		var mutation = CApi.create_builder_in_context (artifact.context);
		foreach (var binding in artifact.class_calls) {
			var call = binding.instruction;
			size_t length;
			string name = CApi.value_name (CApi.called_value (call), out length);
			if (name != "astra_monitor_enter" && name != "astra_monitor_leave" && name != "astra_concurrency_thread_check") {
				continue;
			}
			var argument = CApi.operand (call, 0);
			CApi.set_operand (call, 0, CApi.const_null (CApi.type_of (argument)));
			rejected = false;
			try {
				artifact.verify ();
			} catch (LlvmError error) {
				rejected = true;
			}
			assert (rejected);
			CApi.set_operand (call, 0, argument);
			artifact.verify ();
			if (name == "astra_monitor_enter") {
				locks++;
			} else if (name == "astra_concurrency_thread_check") {
				affinity++;
			} else {
				var next = CApi.next_instruction (call);
				assert ((void*) next != null);
				CApi.remove_instruction (call);
				rejected = false;
				try {
					artifact.verify ();
				} catch (LlvmError error) {
					rejected = true;
				}
				assert (rejected);
				CApi.position_builder_before (mutation, next);
				CApi.insert_instruction (mutation, call);
				artifact.verify ();
				unlocks++;
			}
		}
		CApi.dispose_builder (mutation);
		assert (locks > 0 && unlocks > 0 && affinity > 0);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private CheckedProgram actor_source() {
	string text = "[ExceptionRoot]class Error{readonly string text;init(string message){this.text=message;}virtual property string message{get{return this.text;}}}"
	    + "[Actor]class Inbox{private int count;init(){this.count=0;}int add(int n){this.count=this.count+n;return this.count;}}"
	    + "int handle(borrowed Inbox inbox,int n){return inbox.add(n);}"
	    + "int observe(Error error){return 0;}"
	    + "int scenario() throws Error{var inbox=new Inbox();var sender=actor_bind(move inbox,handle,8,\"actor-proof\");var peer=sender.clone();if(peer==null){return 1;}actor_send(peer,7);actor_cancel(sender);actor_shutdown(sender);return 0;}"
	    + "int main(){try{return scenario();}catch(Error error){return 1;}}";
	var parsed = Parser.parse (new SourceFile.from_text ("actor-contract", text));
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.message);
	}
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.message);
	}
	return checked.program;
}

private void actor_authority() {
	try {
		var checked = actor_source ();
		CheckedClosureBind? checked_bind = null;
		foreach (var function in checked.functions) {
			foreach (var statement in function.body.statements) {
				var local = statement as CheckedOwnedLocalDeclaration;
				if (local != null && local.initializer is CheckedClosureBind) {
					checked_bind = (CheckedClosureBind) local.initializer;
				}
			}
		}
		assert (checked_bind != null && checked_bind.actor_binding != null);
		checked_bind.actor_binding.capacity = 9;
		assert (!checked_bind.actor_binding.copy ().valid ());
		bool rejected = false;
		try {
			CoreVerifier.verify (CoreBuilder.build (checked));
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		checked_bind.actor_binding.capacity = 8;

		var core = CoreBuilder.build (checked);
		CoreVerifier.verify (core);
		CoreClosureBind? core_bind = null;
		foreach (var function in core.functions) {
			foreach (var statement in function.body.statements) {
				var initial = statement as CoreInitialize;
				if (initial != null && initial.value is CoreClosureBind) {
					core_bind = (CoreClosureBind) initial.value;
				}
			}
		}
		assert (core_bind != null && core_bind.actor_binding != null);
		core_bind.actor_binding.alter_name ("forged");
		rejected = false;
		try {
			CoreVerifier.verify (core);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		core_bind.actor_binding.alter_name ("actor-proof");
		CoreVerifier.verify (core);
		var core_receiver = core_bind.cleanup.closure_environment;
		var core_field = core_receiver.fields[0];
		core_receiver.fields[0] = new CoreStructField (core_field.span, core_field.name_span, core_field.name, core_receiver, new BuiltinTypes ().raw_pointer_type, 0, null, true);
		rejected = false;
		try {
			CoreVerifier.verify (core);
		} catch (CoreError error) {
			rejected = error.message.contains ("receiver state must be transferable");
		}
		assert (rejected);
		core_receiver.fields[0] = core_field;
		CoreVerifier.verify (core);

		var cfg = CfgBuilder.build (core);
		CfgVerifier.verify (cfg);
		CfgClosureBind? cfg_bind = null;
		foreach (var function in cfg.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var evaluation = instruction as CfgEvaluateInstruction;
					if (evaluation != null && evaluation.value is CfgClosureBind) {
						cfg_bind = (CfgClosureBind) evaluation.value;
					}
				}
			}
		}
		assert (cfg_bind != null && cfg_bind.actor_binding != null);
		cfg_bind.actor_binding.capacity = 9;
		rejected = false;
		try {
			CfgVerifier.verify (cfg);
		} catch (CfgError error) {
			rejected = true;
		}
		assert (rejected);
		cfg_bind.actor_binding.capacity = 8;
		CfgVerifier.verify (cfg);
		var cfg_receiver = cfg_bind.cleanup.closure_environment;
		var cfg_field = cfg_receiver.fields[0];
		cfg_receiver.fields[0] = new CfgStructField (cfg_field.span, cfg_field.name_span, cfg_field.name, cfg_receiver, new BuiltinTypes ().raw_pointer_type, 0, true);
		rejected = false;
		try {
			CfgVerifier.verify (cfg);
		} catch (CfgError error) {
			rejected = error.message.contains ("receiver state must be transferable");
		}
		assert (rejected);
		cfg_receiver.fields[0] = cfg_field;
		CfgVerifier.verify (cfg);
		CfgFunction? observe = null;
		foreach (var function in cfg.functions) {
			if (function.name == "observe") {
				observe = function;
			}
		}
		assert (observe != null);
		observe.parameters[0].mark_nonnull ();
		bool cfg_nullable = false;
		foreach (var function in cfg.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var send = block.instructions[i] as CfgActorSend;
					if (send == null || send.action != ActorAction.SEND) {
						continue;
					}
					var arguments = new GenericArray<CfgValue> ();
					arguments.add (send.result);
					block.instructions.insert (i + 1, new CfgCallInstruction (send.span, observe, arguments, new CfgCallResultValue (send.span, observe.return_type)));
					rejected = false;
					try {
						CfgNonNull.verify (cfg);
					} catch (CfgError error) {
						rejected = error.message.contains ("nonnull contract requires");
					}
					assert (rejected);
					block.instructions.remove_index (i + 1);
					CfgVerifier.verify (cfg);
					cfg_nullable = true;
				}
			}
		}
		assert (cfg_nullable);

		var ssa = SsaBuilder.build (cfg);
		SsaVerifier.verify (ssa);
		SsaClosureBind? ssa_bind = null;
		foreach (var function in ssa.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					if (instruction is SsaClosureBind) {
						ssa_bind = (SsaClosureBind) instruction;
					}
				}
			}
		}
		assert (ssa_bind != null && ssa_bind.actor_binding != null);
		ssa_bind.actor_binding.alter_name ("forged");
		rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			rejected = true;
		}
		assert (rejected);
		ssa_bind.actor_binding.alter_name ("actor-proof");
		SsaVerifier.verify (ssa);
		var ssa_receiver = ssa_bind.cleanup.closure_environment;
		var ssa_field = ssa_receiver.fields[0];
		ssa_receiver.fields[0] = new SsaStructField (ssa_field.span, ssa_field.name_span, ssa_field.name, ssa_receiver, new BuiltinTypes ().raw_pointer_type, 0, true);
		rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			rejected = error.message.contains ("receiver state must be transferable");
		}
		assert (rejected);
		ssa_receiver.fields[0] = ssa_field;
		SsaVerifier.verify (ssa);
		bool ssa_nullable = false;
		foreach (var function in ssa.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var send = block.instructions[i] as SsaActorSend;
					if (send == null || send.action != ActorAction.SEND) {
						continue;
					}
					block.instructions.insert (i + 1, new SsaNonNullUse (send.span, send.result, 0, block, i + 1));
					rejected = false;
					try {
						SsaVerifier.verify (ssa);
					} catch (SsaError error) {
						rejected = error.message.contains ("nonnull contract requires");
					}
					assert (rejected);
					block.instructions.remove_index (i + 1);
					SsaVerifier.verify (ssa);
					ssa_nullable = true;
				}
			}
		}
		assert (ssa_nullable);

		var native = NativeAbiBuilder.build (ssa);
		NativeAbiVerifier.verify (native);
		NativeClosurePlan? native_bind = null;
		foreach (var plan in native.closures) {
			if (plan.binding && plan.handle.actor) {
				native_bind = plan;
			}
		}
		assert (native_bind != null && native_bind.actor_binding != null);
		native_bind.actor_binding.capacity = 9;
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		native_bind.actor_binding.capacity = 8;
		NativeAbiVerifier.verify (native);
		var operations = native.actor_operations.length;
		assert (operations == 3);
		var first = native.actor_operations[0];
		native.actor_operations.add (first);
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		native.actor_operations.remove_index (operations);
		NativeAbiVerifier.verify (native);
		// A mailbox pointer is not the five-word callback carrier, even when
		// its copied message/result scalars happen to match that C thunk.
		native.retained_operations.add (new NativeRetainedPlan (first.caller, first.block, first.instruction, 0, native_bind.handle));
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		native.retained_operations.remove_index (native.retained_operations.length - 1);
		NativeAbiVerifier.verify (native);

		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		artifact.verify ();
		int calls = 0;
		foreach (var binding in artifact.class_calls) {
			var call = binding.instruction;
			size_t length;
			string name = CApi.value_name (CApi.called_value (call), out length);
			if (!name.has_prefix ("astra_actor_")) {
				continue;
			}
			var original = CApi.operand (call, 0);
			CApi.set_operand (call, 0, CApi.const_null (CApi.type_of (original)));
			rejected = false;
			try {
				artifact.verify ();
			} catch (LlvmError error) {
				rejected = true;
			}
			assert (rejected);
			CApi.set_operand (call, 0, original);
			artifact.verify ();
			calls++;
		}
		assert (calls >= 6);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

public int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/concurrency/checked-core-cfg-ssa-native-llvm-authority-and-restore", authority);
	Test.add_func ("/concurrency/actor-binding-transfer-abi-and-llvm-authority-and-restore", actor_authority);
	return Test.run ();
}

}
