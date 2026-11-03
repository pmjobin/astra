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
namespace Astra.Tests.OwningClosures {
private CheckedProgram source() {
	string text = "class Env{int bias;init(int bias){this.bias=bias;}deinit(){}}class Other{init(){}}"
	    + "int apply(borrowed Env env,int x){return env.bias+x;}int wrong(borrowed Env env,bool x){return env.bias;}"
	    + "int invoke(borrowed Closure<Env,int,int> f){return closure_invoke(f,1);}"
	    + "int main(){var env=new Env(10);var f=closure_bind(move env,apply);return closure_invoke(f,7)-17;}";
	var parsed = Parser.parse (new SourceFile.from_text ("closure-mutation", text));
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.message);
	}
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.message);
	}
	return checked.program;
}

private CheckedFunction checked_named(CheckedProgram program, string name) {
	foreach (var function in program.functions) {
		if (function.symbol.name == name) {
			return function;
		}
	}
	assert_not_reached ();
}

private CoreFunction core_named(CoreProgram program, string name) {
	foreach (var function in program.functions) {
		if (function.name == name) {
			return function;
		}
	}
	assert_not_reached ();
}

private SsaFunction ssa_named(SsaProgram program, string name) {
	foreach (var function in program.functions) {
		if (function.name == name) {
			return function;
		}
	}
	assert_not_reached ();
}

private bool core_rejects(CoreProgram program) {
	try {
		CoreVerifier.verify (program);
	} catch (CoreError error) {
		Test.message ("rejected: %s", error.message);
		return true;
	}
	return false;
}

private bool cfg_rejects(CfgProgram program) {
	try {
		CfgVerifier.verify (program);
	} catch (CfgError error) {
		Test.message ("rejected: %s", error.message);
		return true;
	}
	return false;
}

private bool ssa_rejects(SsaProgram program) {
	try {
		SsaVerifier.verify (program);
	} catch (SsaError error) {
		Test.message ("rejected: %s", error.message);
		return true;
	}
	return false;
}

private void checked_core() {
	try {
		var checked = source ();
		var main = checked_named (checked, "main");
		int at = -1;
		for (int i = 0; i < main.body.statements.length; i++) {
			var local = main.body.statements[i] as CheckedOwnedLocalDeclaration;
			if (local != null && local.initializer is CheckedClosureBind) {
				at = i;
			}
		}
		assert (at >= 0);
		var saved = (CheckedOwnedLocalDeclaration) main.body.statements[at];
		var bound = (CheckedClosureBind) saved.initializer;
		main.body.statements[at] = new CheckedOwnedLocalDeclaration (saved.span, saved.local, new CheckedClosureBind (bound.span, (ClosureHandleType) bound.semantic_type, bound.source, checked_named (checked, "wrong").symbol, bound.cleanup));
		bool rejected = false;
		try {
			CoreVerifier.verify (CoreBuilder.build (checked));
		} catch (CoreError error) {
			rejected = true;
			Test.message ("Checked target signature: %s", error.message);
		}
		assert (rejected);
		main.body.statements[at] = saved;
		var core = CoreBuilder.build (checked);
		CoreVerifier.verify (core);
		var function = core_named (core, "main");
		at = -1;
		for (int i = 0; i < function.body.statements.length; i++) {
			var initialization = function.body.statements[i] as CoreInitialize;
			if (initialization != null && initialization.value is CoreClosureBind) {
				at = i;
			}
		}
		assert (at >= 0);
		var original = (CoreInitialize) function.body.statements[at];
		var closure = (CoreClosureBind) original.value;
		function.body.statements[at] = new CoreInitialize (original.span, original.target, new CoreClosureBind (closure.span, (ClosureHandleType) closure.semantic_type, closure.source, core_named (core, "wrong"), closure.cleanup), original.acquisition);
		assert (core_rejects (core));
		function.body.statements[at] = original;
		CoreVerifier.verify (core);
		var environment = closure.cleanup.closure_environment;
		closure.cleanup.closure_environment = null;
		assert (core_rejects (core));
		closure.cleanup.closure_environment = environment;
		CoreVerifier.verify (core);
		var raw_field = new CoreStructField (environment.span, environment.name_span, "raw_capture", environment, new BuiltinTypes ().raw_pointer_type, environment.fields.length);
		environment.fields.add (raw_field);
		assert (core_rejects (core));
		environment.fields.remove_index (environment.fields.length - 1);
		CoreVerifier.verify (core);
		var borrowed = core_named (core, "invoke");
		var returned = (CoreReturn) borrowed.body.statements[0];
		var call = (CoreClosureCall) returned.value;
		var argument = call.arguments[0];
		call.arguments[0] = call.callee;
		assert (core_rejects (core));
		call.arguments[0] = argument;
		CoreVerifier.verify (core);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void cfg_contract() {
	try {
		var cfg = CfgBuilder.build (CoreBuilder.build (source ()));
		CfgVerifier.verify (cfg);
		CfgBlock? block = null;
		int at = -1;
		foreach (var function in cfg.functions) {
			foreach (var candidate in function.blocks) {
				for (int i = 0; i < candidate.instructions.length; i++) {
					var evaluation = candidate.instructions[i] as CfgEvaluateInstruction;
					if (evaluation != null && evaluation.value is CfgClosureBind) {
						block = candidate;
						at = i;
					}
				}
			}
		}
		assert (block != null && at >= 0);
		var evaluation = (CfgEvaluateInstruction) block.instructions[at];
		var closure = (CfgClosureBind) evaluation.value;
		CfgFunction? wrong = null;
		foreach (var function in cfg.functions) {
			if (function.name == "wrong") {
				wrong = function;
			}
		}
		assert (wrong != null);
		block.instructions[at] = new CfgEvaluateInstruction (evaluation.span, new CfgClosureBind (closure.span, (ClosureHandleType) closure.semantic_type, closure.environment, wrong, closure.cleanup), evaluation.result);
		assert (cfg_rejects (cfg));
		block.instructions[at] = evaluation;
		CfgVerifier.verify (cfg);
		var capture = block.instructions[at - 1];
		assert (capture is CfgResourceCapture);
		block.instructions.remove_index (at - 1);
		assert (cfg_rejects (cfg));
		block.instructions.insert (at - 1, capture);
		CfgVerifier.verify (cfg);
		var environment = closure.cleanup.closure_environment;
		closure.cleanup.closure_environment = null;
		assert (cfg_rejects (cfg));
		closure.cleanup.closure_environment = environment;
		CfgVerifier.verify (cfg);
		var initialize = block.instructions[at + 1] as CfgInitialize;
		assert (initialize != null);
		block.instructions.insert (at + 2, initialize);
		assert (cfg_rejects (cfg));
		block.instructions.remove_index (at + 2);
		CfgVerifier.verify (cfg);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void ssa_contract() {
	try {
		var ssa = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (source ())));
		SsaVerifier.verify (ssa);
		SsaBlock? block = null;
		int at = -1;
		foreach (var function in ssa.functions) {
			foreach (var candidate in function.blocks) {
				for (int i = 0; i < candidate.instructions.length; i++) {
					if (candidate.instructions[i] is SsaClosureBind) {
						block = candidate;
						at = i;
					}
				}
			}
		}
		assert (block != null && at >= 0);
		var closure = (SsaClosureBind) block.instructions[at];
		var environment = closure.cleanup.closure_environment;
		closure.cleanup.closure_environment = null;
		assert (ssa_rejects (ssa));
		closure.cleanup.closure_environment = environment;
		SsaVerifier.verify (ssa);
		var disposition = block.instructions[at - 1];
		assert (disposition is SsaHeapOwnerEvent);
		block.instructions.remove_index (at - 1);
		assert (ssa_rejects (ssa));
		block.instructions.insert (at - 1, disposition);
		SsaVerifier.verify (ssa);
		block.instructions[at] = new SsaClosureBind (closure.span, (ClosureHandleType) closure.result.semantic_type, closure.environment, ssa_named (ssa, "wrong"), closure.cleanup, closure.result.ordinal);
		assert (ssa_rejects (ssa));
		block.instructions[at] = closure;
		SsaVerifier.verify (ssa);
		int call_at = -1;
		for (int i = 0; i < block.instructions.length; i++) {
			if (block.instructions[i] is SsaClosureCall) {
				call_at = i;
			}
		}
		assert (call_at >= 1);
		var read = block.instructions[call_at - 1];
		assert (read is SsaHeapOwnerEvent && ((SsaHeapOwnerEvent) read).action == SsaHeapOwnerAction.READ);
		block.instructions.remove_index (call_at - 1);
		assert (ssa_rejects (ssa));
		block.instructions.insert (call_at - 1, read);
		SsaVerifier.verify (ssa);
		var call = (SsaClosureCall) block.instructions[call_at];
		var argument = call.arguments[0];
		call.arguments[0] = call.callee;
		assert (ssa_rejects (ssa));
		call.arguments[0] = argument;
		SsaVerifier.verify (ssa);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_contract() {
	try {
		var ssa = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (source ())));
		var native = NativeAbiBuilder.build (ssa);
		NativeAbiVerifier.verify (native);
		var map = new HashTable<SsaFunction, NativeFunction> (direct_hash, direct_equal);
		foreach (var function in ssa.functions) {
			map.insert (function, native.functions[function.ordinal]);
		}
		NativeAbiValidator.validate_ssa_calls (ssa, native, map);
		int at = -1;
		for (int i = 0; i < native.closures.length; i++) {
			if (native.closures[i].binding) {
				at = i;
			}
		}
		assert (at >= 0);
		var plan = native.closures[at];
		var raw = new NativeScalarAbiType (NativeScalarType.PTR);
		assert (!raw.same_type (plan.handle) && !plan.handle.same_type (raw));
		native.closures.remove_index (at);
		bool rejected = false;
		try {
			NativeAbiValidator.validate_ssa_calls (ssa, native, map);
		} catch (NativeAbiError error) {
			rejected = true;
			Test.message ("missing native plan: %s", error.message);
		}
		assert (rejected);
		native.closures.insert (at, plan);
		native.closures[at] = new NativeClosurePlan (plan.caller, plan.block, plan.instruction, true, plan.handle, plan.target, -1);
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
			NativeAbiValidator.validate_ssa_calls (ssa, native, map);
		} catch (NativeAbiError error) {
			rejected = true;
			Test.message ("lost carried destruction authority: %s", error.message);
		}
		assert (rejected);
		native.closures[at] = plan;
		native.closures[at] = new NativeClosurePlan (plan.caller, plan.block, plan.instruction, true, plan.handle, ssa_named (ssa, "wrong").ordinal, plan.destructor);
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
			NativeAbiValidator.validate_ssa_calls (ssa, native, map);
		} catch (NativeAbiError error) {
			rejected = true;
			Test.message ("forged native code signature: %s", error.message);
		}
		assert (rejected);
		native.closures[at] = plan;
		NativeAbiVerifier.verify (native);
		NativeAbiValidator.validate_ssa_calls (ssa, native, map);
		native.closures.add (plan);
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = true;
			Test.message ("duplicated closure plan: %s", error.message);
		}
		assert (rejected);
		native.closures.remove_index (native.closures.length - 1);
		NativeAbiVerifier.verify (native);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void generic_valid(LlvmModuleArtifact artifact) {
	char* message = null;
	int invalid = CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message);
	if (message != null) {
		CApi.dispose_message (message);
	}
	assert (invalid == 0);
}

private void llvm_contract() {
	try {
		var ssa = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (source ())));
		var native = NativeAbiBuilder.build (ssa);
		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		artifact.verify ();
		int calls = 0;
		int stores = 0;
		foreach (var binding in artifact.class_calls) {
			var call = binding.instruction;
			var code = CApi.called_value (call);
			if ((void*) CApi.is_instruction (code) == null || CApi.opcode (code) != CApi.Opcode.LOAD) {
				continue;
			}
			uint count = CApi.argument_count (call);
			CApi.set_operand (call, count, CApi.const_null (CApi.type_of (code)));
			generic_valid (artifact);
			bool rejected = false;
			try {
				artifact.verify ();
			} catch (LlvmError error) {
				rejected = true;
				Test.message ("LLVM forged carried code: %s", error.message);
			}
			assert (rejected);
			CApi.set_operand (call, count, code);
			artifact.verify ();
			var environment = CApi.operand (call, 0);
			CApi.set_operand (call, 0, CApi.const_null (CApi.type_of (environment)));
			generic_valid (artifact);
			rejected = false;
			try {
				artifact.verify ();
			} catch (LlvmError error) {
				rejected = true;
				Test.message ("LLVM forged carried environment: %s", error.message);
			}
			assert (rejected);
			CApi.set_operand (call, 0, environment);
			artifact.verify ();
			CApi.set_instruction_call_conv (call, CApi.CallConv.C);
			generic_valid (artifact);
			rejected = false;
			try {
				artifact.verify ();
			} catch (LlvmError error) {
				rejected = true;
				Test.message ("LLVM foreign closure convention: %s", error.message);
			}
			assert (rejected);
			CApi.set_instruction_call_conv (call, CApi.CallConv.FAST);
			artifact.verify ();
			calls++;
		}
		foreach (var binding in artifact.class_values) {
			var store = binding.instruction;
			if (CApi.opcode (store) != CApi.Opcode.STORE) {
				continue;
			}
			var original = CApi.operand (store, 0);
			if (CApi.type_kind (CApi.type_of (original)) != CApi.TypeKind.POINTER || (void*) original == (void*) CApi.const_null (CApi.type_of (original))) {
				continue;
			}
			CApi.set_operand (store, 0, CApi.const_null (CApi.type_of (original)));
			generic_valid (artifact);
			bool rejected = false;
			try {
				artifact.verify ();
			} catch (LlvmError error) {
				rejected = true;
				Test.message ("LLVM removed code/environment/destructor publication: %s", error.message);
			}
			assert (rejected);
			CApi.set_operand (store, 0, original);
			artifact.verify ();
			stores++;
		}
		assert (calls >= 2 && stores >= 3);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

public int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/closure/checked-core-environment-code-signature", checked_core);
	Test.add_func ("/closure/cfg-sole-acquisition", cfg_contract);
	Test.add_func ("/closure/ssa-move-loan-and-destruction", ssa_contract);
	Test.add_func ("/closure/native-code-environment-destructor", native_contract);
	Test.add_func ("/closure/llvm-carried-triple-and-convention", llvm_contract);
	return Test.run ();
}

}
