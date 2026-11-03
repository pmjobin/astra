// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Foreign;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;
namespace Astra.Tests.RetainedCallbacks {
private CheckedProgram source() {
	string text = "class Env{int bias;init(int bias){this.bias=bias;}deinit(){}}int apply(borrowed Env env,int x){return env.bias+x;}"
	    + "int dispatch_borrowed(borrowed Closure<Env,int,int> f){return retained_dispatch(f,1);}"
	    + "int main(){var env=new Env(10);var f=closure_bind(move env,apply);int registered=retained_register(f,0);int dispatched=retained_dispatch(f,7);int revoked=retained_revoke(f);return retained_observe(f);}";
	var parsed = Parser.parse (new SourceFile.from_text ("retained-mutation", text));
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.message);
	}
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.message);
	}
	return checked.program;
}

private void checked_core() {
	try {
		var checked = source ();
		CheckedFunction? borrowed = null;
		foreach (var function in checked.functions) {
			if (function.symbol.name == "dispatch_borrowed") {
				borrowed = function;
			}
		}
		assert (borrowed != null);
		var returned = (CheckedReturnStatement) borrowed.body.statements[0];
		var operation = (CheckedRetainedOperation) returned.expression;
		borrowed.body.statements[0] = new CheckedReturnStatement (returned.span, new CheckedRetainedOperation (operation.span, (RetainedAction) 99, operation.callee, operation.arguments));
		bool rejected = false;
		try {
			CoreBuilder.build (checked);
		} catch (CoreError error) {
			rejected = true;
			Test.message ("Checked invalid retained action: %s", error.message);
		}
		assert (rejected);
		borrowed.body.statements[0] = returned;
		var core = CoreBuilder.build (checked);
		CoreVerifier.verify (core);
		CoreFunction? function = null;
		foreach (var candidate in core.functions) {
			if (candidate.name == "dispatch_borrowed") {
				function = candidate;
			}
		}
		assert (function != null);
		var original = (CoreReturn) function.body.statements[0];
		var call = (CoreRetainedOperation) original.value;
		var saved = call.arguments[0];
		call.arguments[0] = call.callee;
		rejected = false;
		try {
			CoreVerifier.verify (core);
		} catch (CoreError error) {
			rejected = true;
			Test.message ("Core forged retained argument: %s", error.message);
		}
		assert (rejected);
		call.arguments[0] = saved;
		CoreVerifier.verify (core);
		function.body.statements[0] = new CoreReturn (original.span, new CoreRetainedOperation (call.span, (RetainedAction) 99, call.callee, call.arguments));
		rejected = false;
		try {
			CoreVerifier.verify (core);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		function.body.statements[0] = original;
		CoreVerifier.verify (core);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void cfg_contract() {
	try {
		var cfg = CfgBuilder.build (CoreBuilder.build (source ()));
		CfgVerifier.verify (cfg);
		int count = 0;
		foreach (var function in cfg.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var evaluation = instruction as CfgEvaluateInstruction;
					var initialization = instruction as CfgInitialize;
					CfgValue? value = evaluation != null ? evaluation.value : initialization == null ? null : initialization.value;
					var operation = value as CfgRetainedOperation;
					if (operation == null || operation.arguments.length == 0) {
						continue;
					}
					var saved = operation.arguments[0];
					operation.arguments[0] = operation.callee;
					bool rejected = false;
					try {
						CfgVerifier.verify (cfg);
					} catch (CfgError error) {
						rejected = true;
						Test.message ("CFG retained identity: %s", error.message);
					}
					assert (rejected);
					operation.arguments[0] = saved;
					CfgVerifier.verify (cfg);
					count++;
				}
				var returned = block.terminator as CfgReturn;
				var operation = returned == null ? null : returned.value as CfgRetainedOperation;
				if (operation != null && operation.arguments.length > 0) {
					var saved = operation.arguments[0];
					operation.arguments[0] = operation.callee;
					bool rejected = false;
					try {
						CfgVerifier.verify (cfg);
					} catch (CfgError error) {
						rejected = true;
					}
					assert (rejected);
					operation.arguments[0] = saved;
					CfgVerifier.verify (cfg);
					count++;
				}
			}
		}
		assert (count > 0);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private SsaProgram ssa_source() throws GLib.Error {
	return SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (source ())));
}

private void ssa_contract() {
	try {
		var ssa = ssa_source ();
		SsaVerifier.verify (ssa);
		int count = 0;
		foreach (var function in ssa.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var operation = block.instructions[i] as SsaRetainedOperation;
					if (operation == null) {
						continue;
					}
					if (operation.source_owner != null) {
						var loan = block.instructions[i - 1];
						assert (loan is SsaHeapOwnerEvent);
						block.instructions.remove_index (i - 1);
						bool rejected = false;
						try {
							SsaVerifier.verify (ssa);
						} catch (SsaError error) {
							rejected = true;
							Test.message ("SSA missing retained owner loan: %s", error.message);
						}
						assert (rejected);
						block.instructions.insert (i - 1, loan);
						SsaVerifier.verify (ssa);
						count++;
					}
					if (operation.arguments.length > 0) {
						var saved = operation.arguments[0];
						operation.arguments[0] = operation.callee;
						bool rejected = false;
						try {
							SsaVerifier.verify (ssa);
						} catch (SsaError error) {
							rejected = true;
						}
						assert (rejected);
						operation.arguments[0] = saved;
						SsaVerifier.verify (ssa);
						count++;
					}
				}
			}
		}
		assert (count >= 4);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_cabi() {
	try {
		var ssa = ssa_source ();
		var native = NativeAbiBuilder.build (ssa);
		var cabi = CAbiBuilder.build (ssa, native);
		NativeAbiVerifier.verify (native);
		CAbiVerifier.verify (cabi);
		var map = new HashTable<SsaFunction, NativeFunction> (direct_hash, direct_equal);
		foreach (var function in ssa.functions) {
			map.insert (function, native.functions[function.ordinal]);
		}
		var plan = native.retained_operations[0];
		native.retained_operations.remove_index (0);
		bool rejected = false;
		try {
			NativeAbiValidator.validate_ssa_calls (ssa, native, map);
		} catch (NativeAbiError error) {
			rejected = true;
			Test.message ("native lost retained operation: %s", error.message);
		}
		assert (rejected);
		native.retained_operations.insert (0, plan);
		native.retained_operations[0] = new NativeRetainedPlan (plan.caller, plan.block, plan.instruction, 99, plan.handle);
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		native.retained_operations[0] = plan;
		var cplan = cabi.retained_operations[0];
		cabi.retained_operations[0] = new CAbiRetainedPlan (cplan.caller, cplan.block, cplan.instruction, cplan.action, cplan.environment, CAbiScalarType.PTR);
		rejected = false;
		try {
			CAbiVerifier.verify (cabi);
		} catch (CAbiError error) {
			rejected = true;
			Test.message ("CABI callback result corruption: %s", error.message);
		}
		assert (rejected);
		cabi.retained_operations[0] = cplan;
		var cmap = new HashTable<SsaCFunction, CAbiFunction> (direct_hash, direct_equal);
		cabi.retained_operations.remove_index (0);
		rejected = false;
		try {
			CAbiValidator.validate_ssa_calls (ssa, cabi, cmap);
		} catch (CAbiError error) {
			rejected = true;
		}
		assert (rejected);
		cabi.retained_operations.insert (0, cplan);
		cabi.retained_operations[0] = new CAbiRetainedPlan (cplan.caller, cplan.block, cplan.instruction, cplan.action, "WrongEnvironment");
		rejected = false;
		try {
			LlvmLowering.lower (ssa, native, cabi);
		} catch (LlvmError error) {
			rejected = true;
			Test.message ("CABI lost exact native environment: %s", error.message);
		}
		assert (rejected);
		cabi.retained_operations[0] = cplan;
		NativeAbiVerifier.verify (native);
		CAbiVerifier.verify (cabi);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void foreign_boundary() {
	try {
		var core = CoreBuilder.build (source ());
		ClosureHandleType? type = null;
		foreach (var cleanup in core.cleanups) {
			if (cleanup.closure_type != null) {
				type = cleanup.closure_type;
			}
		}
		assert (type != null);
		var metadata = new CForeignMetadata ("forged_raw_closure");
		for (int channel = 0; channel < 2; channel++) {
			var arguments = new GenericArray<SemanticType> ();
			if (channel != 0) {
				arguments.add (type);
			}
			core.c_functions.add (new CoreCFunction (core.span, core.span, "forged", metadata, ForeignAbi.C, channel == 0 ? (SemanticType) type : type.result_type, arguments, core.c_functions.length));
			bool rejected = false;
			try {
				CoreVerifier.verify (core);
			} catch (CoreError error) {
				rejected = true;
				Test.message ("Core raw lifetime carrier: %s", error.message);
			}
			assert (rejected);
			core.c_functions.remove_index (core.c_functions.length - 1);
			CoreVerifier.verify (core);
			var cfg = CfgBuilder.build (core);
			cfg.c_functions.add (new CfgCFunction (cfg.span, cfg.span, "forged", metadata, ForeignAbi.C, channel == 0 ? (SemanticType) type : type.result_type, arguments, cfg.c_functions.length));
			rejected = false;
			try {
				CfgVerifier.verify (cfg);
			} catch (CfgError error) {
				rejected = true;
			}
			assert (rejected);
			cfg.c_functions.remove_index (cfg.c_functions.length - 1);
			CfgVerifier.verify (cfg);
			var ssa = SsaBuilder.build (cfg);
			ssa.c_functions.add (new SsaCFunction (ssa.span, ssa.span, "forged", metadata, ForeignAbi.C, channel == 0 ? (SemanticType) type : type.result_type, arguments, ssa.c_functions.length));
			rejected = false;
			try {
				SsaVerifier.verify (ssa);
			} catch (SsaError error) {
				rejected = true;
			}
			assert (rejected);
			ssa.c_functions.remove_index (ssa.c_functions.length - 1);
			SsaVerifier.verify (ssa);
		}
		bool rejected = false;
		try {
			CAbiTypeMapper.map_scalar (type);
		} catch (CAbiError error) {
			rejected = true;
			Test.message ("CABI raw closure carrier: %s", error.message);
		}
		assert (rejected);
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
		var ssa = ssa_source ();
		var native = NativeAbiBuilder.build (ssa);
		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		artifact.verify ();
		int calls = 0;
		int checks = 0;
		foreach (var binding in artifact.class_calls) {
			var call = binding.instruction;
			var code = CApi.called_value (call);
			if (CApi.argument_count (call) != 3) {
				continue;
			}
			var original = CApi.operand (call, 0);
			CApi.set_operand (call, 0, CApi.const_null (CApi.type_of (original)));
			generic_valid (artifact);
			bool rejected = false;
			try {
				artifact.verify ();
			} catch (LlvmError error) {
				rejected = true;
				Test.message ("LLVM retained C callback identity: %s", error.message);
			}
			assert (rejected);
			CApi.set_operand (call, 0, original);
			artifact.verify ();
			original = CApi.operand (call, 1);
			CApi.set_operand (call, 1, CApi.const_null (CApi.type_of (original)));
			generic_valid (artifact);
			rejected = false;
			try {
				artifact.verify ();
			} catch (LlvmError error) {
				rejected = true;
			}
			assert (rejected);
			CApi.set_operand (call, 1, original);
			artifact.verify ();
			assert ((void*) code == (void*) CApi.called_value (call));
			calls++;
		}
		foreach (var binding in artifact.class_values) {
			var instruction = binding.instruction;
			if (CApi.opcode (instruction) != CApi.Opcode.ICMP) {
				continue;
			}
			var original = CApi.operand (instruction, 1);
			if (CApi.type_kind (CApi.type_of (original)) != CApi.TypeKind.INTEGER || (void*) CApi.is_constant_int (original) == null || CApi.const_int_zext (original) != 1) {
				continue;
			}
			CApi.set_operand (instruction, 1, CApi.const_null (CApi.type_of (original)));
			generic_valid (artifact);
			bool rejected = false;
			try {
				artifact.verify ();
			} catch (LlvmError error) {
				rejected = true;
				Test.message ("LLVM forged quiescence ACK: %s", error.message);
			}
			assert (rejected);
			CApi.set_operand (instruction, 1, original);
			artifact.verify ();
			checks++;
		}
		assert (calls > 0 && checks > 0);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

public int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/retained/checked-core-action-owner", checked_core);
	Test.add_func ("/retained/cfg-exact-carrier", cfg_contract);
	Test.add_func ("/retained/ssa-owner-loan", ssa_contract);
	Test.add_func ("/retained/native-cabi-correspondence", native_cabi);
	Test.add_func ("/retained/native-only-carrier-boundary", foreign_boundary);
	Test.add_func ("/retained/llvm-code-context-quiescence", llvm_contract);
	return Test.run ();
}

}
