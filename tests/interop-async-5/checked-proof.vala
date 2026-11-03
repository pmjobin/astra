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
namespace Astra.Tests.CheckedClosures {
private CheckedProgram source() {
	string text = "[ExceptionRoot]class Error{init(){}virtual property string message{get{return \"checked\";}}}"
	    + "class Env{int n;init(){this.n=7;}deinit(){}}"
	    + "int code(borrowed Env env,int x)throws Error{if(x<0){throw new Error();}return env.n+x;}"
	    + "int plain(borrowed Env env,int x){return env.n+x;}"
	    + "class OtherEnv{init(){}}int wrong_env(borrowed OtherEnv env,int x)throws Error{return x;}"
	    + "int invoke(borrowed CheckedClosure<Env,Error,int,int> f)throws Error{return closure_invoke(f,1);}"
	    + "int main(){var env=new Env();var f=checked_closure_bind(move env,code);try{return closure_invoke(f,2)-9;}catch(Error e){return 1;}}";
	var parsed = Parser.parse (new SourceFile.from_text ("checked-closure-mutation", text));
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
	foreach (var f in program.functions) {
		if (f.symbol.name == name) {
			return f;
		}
	}
	assert_not_reached ();
}

private CoreFunction core_named(CoreProgram program, string name) {
	foreach (var f in program.functions) {
		if (f.name == name) {
			return f;
		}
	}
	assert_not_reached ();
}

private SsaFunction ssa_named(SsaProgram program, string name) {
	foreach (var f in program.functions) {
		if (f.name == name) {
			return f;
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
		main.body.statements[at] = new CheckedOwnedLocalDeclaration (saved.span, saved.local, new CheckedClosureBind (bound.span, (ClosureHandleType)bound.semantic_type, bound.source, checked_named(checked, "plain").symbol, bound.cleanup));
		bool rejected = false;
		try {
			CoreVerifier.verify(CoreBuilder.build(checked));
		} catch (CoreError error) {
			rejected = true;
			Test.message("Checked effect substitution: %s", error.message);
		}
		assert(rejected);
		main.body.statements[at] = saved;
		var core = CoreBuilder.build(checked);
		CoreVerifier.verify(core);
		var function = core_named(core, "main");
		at = -1;
		for (int i = 0; i < function.body.statements.length; i++) {
			var init = function.body.statements[i] as CoreInitialize;
			if (init != null && init.value is CoreClosureBind) {
				at = i;
			}
		}
		assert(at >= 0);
		var original = (CoreInitialize)function.body.statements[at];
		var closure = (CoreClosureBind)original.value;
		function.body.statements[at] = new CoreInitialize(original.span, original.target, new CoreClosureBind(closure.span, (ClosureHandleType)closure.semantic_type, closure.source, core_named(core, "plain"), closure.cleanup), original.acquisition);
		assert(core_rejects(core));
		function.body.statements[at] = original;
		CoreVerifier.verify(core);
		var callable = core_named(core, "invoke");
		var returned = (CoreReturn)callable.body.statements[0];
		var call = (CoreClosureCall)returned.value;
		var arg = call.arguments[0];
		call.arguments[0] = call.callee;
		assert(core_rejects(core));
		call.arguments[0] = arg;
		CoreVerifier.verify(core);
	} catch (GLib.Error error) {
		GLib.error("%s", error.message);
	}
}

private void cfg_contract() {
	try {
		var cfg = CfgBuilder.build(CoreBuilder.build(source()));
		CfgVerifier.verify(cfg);
		CfgBlock? block = null;
		int at = -1;
		foreach (var f in cfg.functions) {
			foreach (var b in f.blocks) {
				for (int i = 0; i < b.instructions.length; i++) {
					if (b.instructions[i] is CfgCheckedClosureInvoke) {
						block = b;
						at = i;
					}
				}
			}
		}
		assert(block != null && at >= 0);
		var invocation = (CfgCheckedClosureInvoke)block.instructions[at];
		block.instructions[at] = new CfgEvaluateInstruction(invocation.span, invocation.call, invocation.result);
		assert(cfg_rejects(cfg));
		block.instructions[at] = invocation;
		CfgVerifier.verify(cfg);
		var arg = invocation.call.arguments[0];
		invocation.call.arguments[0] = invocation.call.callee;
		assert(cfg_rejects(cfg));
		invocation.call.arguments[0] = arg;
		CfgVerifier.verify(cfg);
		// Publishing success in the originating block precedes the null-error edge.
		block.instructions.insert(at + 1, new CfgClosureCallSuccess(invocation.span, invocation));
		assert(cfg_rejects(cfg));
		block.instructions.remove_index(at + 1);
		CfgVerifier.verify(cfg);
	} catch (GLib.Error error) {
		GLib.error("%s", error.message);
	}
}

private void ssa_contract() {
	try {
		var ssa = SsaBuilder.build(CfgBuilder.build(CoreBuilder.build(source())));
		SsaVerifier.verify(ssa);
		SsaBlock? block = null;
		int at = -1;
		foreach (var f in ssa.functions) {
			foreach (var b in f.blocks) {
				for (int i = 0; i < b.instructions.length; i++) {
					if (b.instructions[i] is SsaClosureCall) {
						block = b;
						at = i;
					}
				}
			}
		}
		assert(block != null && at >= 0);
		var call = (SsaClosureCall)block.instructions[at];
		assert(((ClosureHandleType)call.callee.semantic_type).throws_type != null);
		var arg = call.arguments[0];
		call.arguments[0] = call.callee;
		assert(ssa_rejects(ssa));
		call.arguments[0] = arg;
		SsaVerifier.verify(ssa);
		// A scalar channel cannot substitute for the rooted error result.
		block.instructions[at] = new SsaClosureCall(call.span, (ClosureHandleType)call.callee.semantic_type, call.callee, call.arguments, call.result.ordinal, call.source_owner, (ClassType)((ClosureHandleType)call.callee.semantic_type).environment_type);
		assert(ssa_rejects(ssa));
		block.instructions[at] = call;
		SsaVerifier.verify(ssa);
		var saved_success = call.owned_success;
		int next = 100000;
		block.instructions.insert(at + 1, new SsaClosureCallSuccess(call.span, call, next));
		assert(ssa_rejects(ssa));
		block.instructions.remove_index(at + 1);
		call.owned_success = saved_success;
		SsaVerifier.verify(ssa);
		var read = at > 0?block.instructions[at - 1] as SsaHeapOwnerEvent:null;
		if (read != null) {
			block.instructions.remove_index(at - 1);
			assert(ssa_rejects(ssa));
			block.instructions.insert(at - 1, read);
			SsaVerifier.verify(ssa);
		}
		// Independently substitute a nonthrowing code symbol under checked identity.
		foreach (var f in ssa.functions) {
			foreach (var b in f.blocks) {
				for (int i = 0; i < b.instructions.length; i++) {
					var bind = b.instructions[i] as SsaClosureBind;
					if (bind == null) {
						continue;
					}
					b.instructions[i] = new SsaClosureBind(bind.span, (ClosureHandleType)bind.result.semantic_type, bind.environment, ssa_named(ssa, "plain"), bind.cleanup, bind.result.ordinal);
					assert(ssa_rejects(ssa));
					b.instructions[i] = bind;
					SsaVerifier.verify(ssa);
				}
			}
		}
	} catch (GLib.Error error) {
		GLib.error("%s", error.message);
	}
}

private void native_contract() {
	try {
		var ssa = SsaBuilder.build(CfgBuilder.build(CoreBuilder.build(source())));
		var native = NativeAbiBuilder.build(ssa);
		NativeAbiVerifier.verify(native);
		var map = new HashTable<SsaFunction, NativeFunction>(direct_hash, direct_equal);
		foreach (var f in ssa.functions) {
			map.insert(f, native.functions[f.ordinal]);
		}
		NativeAbiValidator.validate_ssa_calls(ssa, native, map);
		int at = -1;
		for (int i = 0; i < native.closures.length; i++) {
			if (native.closures[i].binding) {
				at = i;
			}
		}
		assert(at >= 0);
		var plan = native.closures[at];
		assert(plan.handle.checked_error == "Error");
		var unqualified = new NativeClosureHandleType(plan.handle.environment, plan.handle.signature);
		assert(!unqualified.same_type(plan.handle) && !plan.handle.same_type(unqualified));
		native.closures[at] = new NativeClosurePlan(plan.caller, plan.block, plan.instruction, true, unqualified, plan.target, plan.destructor);
		bool rejected = false;
		try{
			NativeAbiVerifier.verify(native);
			NativeAbiValidator.validate_ssa_calls(ssa, native, map);
		} catch (NativeAbiError error) {
			rejected = true;
			Test.message("native erased checked effect: %s", error.message);
		}
		assert(rejected);
		native.closures[at] = plan;
		native.closures[at] = new NativeClosurePlan(plan.caller, plan.block, plan.instruction, true, plan.handle, ssa_named(ssa, "plain").ordinal, plan.destructor);
		rejected = false;
		try{
			NativeAbiVerifier.verify(native);
			NativeAbiValidator.validate_ssa_calls(ssa, native, map);
		} catch (NativeAbiError error) {
			rejected = true;
			Test.message("native nonthrowing target: %s", error.message);
		}
		assert(rejected);
		native.closures[at] = plan;
		NativeAbiVerifier.verify(native);
		NativeAbiValidator.validate_ssa_calls(ssa, native, map);
		native.closures[at] = new NativeClosurePlan(plan.caller, plan.block, plan.instruction, true, plan.handle, ssa_named(ssa, "wrong_env").ordinal, plan.destructor);
		rejected = false;
		try{
			NativeAbiVerifier.verify(native);
		} catch (NativeAbiError error) {
			rejected = true;
			Test.message("native wrong borrowed environment identity: %s", error.message);
		}
		assert(rejected);
		native.closures[at] = plan;
		NativeAbiVerifier.verify(native);
		NativeAbiValidator.validate_ssa_calls(ssa, native, map);
	} catch (GLib.Error error) {
		GLib.error("%s", error.message);
	}
}

private void generic_valid(LlvmModuleArtifact artifact) {
	char* message = null;
	int invalid = CApi.verify_module(artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message);
	if (message != null) {
		CApi.dispose_message(message);
	}
	assert(invalid == 0);
}

private void llvm_contract() {
	try {
		var ssa = SsaBuilder.build(CfgBuilder.build(CoreBuilder.build(source())));
		var native = NativeAbiBuilder.build(ssa);
		var artifact = LlvmLowering.lower(ssa, native, CAbiBuilder.build(ssa, native));
		artifact.verify();
		int count = 0;
		foreach (var binding in artifact.class_calls) {
			var call = binding.instruction;
			var code = CApi.called_value(call);
			if ((void*)CApi.is_instruction(code) == null || CApi.opcode(code) != CApi.Opcode.LOAD || CApi.type_kind(CApi.type_of(call)) != CApi.TypeKind.POINTER) {
				continue;
			}
			uint argc = CApi.argument_count(call);
			assert(argc == 3);
			for (uint p = 0; p < 2; p++) {
				var operand = CApi.operand(call, p);
				CApi.set_operand(call, p, CApi.const_null(CApi.type_of(operand)));
				generic_valid(artifact);
				bool rejected = false;
				try{
					artifact.verify();
				} catch (LlvmError error) {
					rejected = true;
					Test.message("LLVM checked slot/env: %s", error.message);
				}
				assert(rejected);
				CApi.set_operand(call, p, operand);
				artifact.verify();
			}
			CApi.set_operand(call, argc, CApi.const_null(CApi.type_of(code)));
			generic_valid(artifact);
			bool rejected = false;
			try{
				artifact.verify();
			} catch (LlvmError error) {
				rejected = true;
				Test.message("LLVM checked code: %s", error.message);
			}
			assert(rejected);
			CApi.set_operand(call, argc, code);
			artifact.verify();
			CApi.set_instruction_call_conv(call, CApi.CallConv.C);
			generic_valid(artifact);
			rejected = false;
			try{
				artifact.verify();
			} catch (LlvmError error) {
				rejected = true;
				Test.message("LLVM checked convention: %s", error.message);
			}
			assert(rejected);
			CApi.set_instruction_call_conv(call, CApi.CallConv.FAST);
			artifact.verify();
			count++;
		}
		assert(count >= 2);
	} catch (GLib.Error error) {
		GLib.error("%s", error.message);
	}
}

public int main(string[] args) {
	Test.init(ref args);
	Test.add_func("/checked-closure/checked-core-effect-identity", checked_core);
	Test.add_func("/checked-closure/cfg-explicit-error-and-guarded-success", cfg_contract);
	Test.add_func("/checked-closure/ssa-exact-error-result-and-owner-loan", ssa_contract);
	Test.add_func("/checked-closure/native-checked-physical-signature", native_contract);
	Test.add_func("/checked-closure/llvm-slot-code-env-and-convention", llvm_contract);
	return Test.run();
}

}
