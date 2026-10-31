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

namespace Astra.Tests.FunctionValues {
private CheckedProgram source() {
	string text = "int increment(int value){return value+1;}i64 wide(i64 value){return value+2;}"
	    + "Fn<int,int> choose(){return increment;}"
	    + "int apply(Fn<int,int> function,int value){return function(value);}"
	    + "int bound(){Fn<int,int> function=increment;return function(1);}"
	    + "int main(){Fn<int,int> function=choose();return apply(function,3)+bound();}";
	var parsed = Parser.parse (new SourceFile.from_text ("function-value-mutation", text));
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
private CfgFunction cfg_named(CfgProgram program, string name) {
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

private void checked_and_core() {
	try {
		var checked = source ();
		var choose = checked_named (checked, "choose");
		var saved = choose.body.statements[0];
		var address = (CheckedFunctionAddress) ((CheckedReturnStatement) saved).expression;
		choose.body.statements[0] = new CheckedReturnStatement (saved.span,
			new CheckedFunctionAddress (address.span, (FunctionValueType) address.semantic_type, checked_named (checked, "wide").symbol));
		bool rejected = false;
		try {
			CoreVerifier.verify (CoreBuilder.build (checked));
		} catch (CoreError error) {
			rejected = true;
			Test.message ("Checked forged signature: %s", error.message);
		}
		assert (rejected);
		choose.body.statements[0] = saved;
		var core = CoreBuilder.build (checked);
		CoreVerifier.verify (core);
		var core_choose = core_named (core, "choose");
		var returned = core_choose.body.statements[0];
		var original = (CoreFunctionAddress) ((CoreReturn) returned).value;
		core_choose.body.statements[0] = new CoreReturn (returned.span,
			new CoreFunctionAddress (original.span, (FunctionValueType) original.semantic_type, core_named (core, "wide")));
		rejected = false;
		try {
			CoreVerifier.verify (core);
		} catch (CoreError error) {
			rejected = true;
			Test.message ("Core forged address: %s", error.message);
		}
		assert (rejected);
		core_choose.body.statements[0] = returned;
		CoreVerifier.verify (core);
		var apply = core_named (core, "apply");
		var apply_return = apply.body.statements[0];
		var call = (CoreFunctionValueCall) ((CoreReturn) apply_return).value;
		var argument = call.arguments[0];
		call.arguments[0] = call.callee;
		rejected = false;
		try {
			CoreVerifier.verify (core);
		} catch (CoreError error) {
			rejected = true;
			Test.message ("Core code as scalar argument: %s", error.message);
		}
		assert (rejected);
		call.arguments[0] = argument;
		CoreVerifier.verify (core);
		apply.body.statements[0] = new CoreReturn (call.span,
			new CoreFunctionValueCall (call.span, (FunctionValueType) call.callee.semantic_type, argument, call.arguments));
		rejected = false;
		try {
			CoreVerifier.verify (core);
		} catch (CoreError error) {
			rejected = true;
			Test.message ("Core scalar as code: %s", error.message);
		}
		assert (rejected);
		apply.body.statements[0] = apply_return;
		CoreVerifier.verify (core);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void cfg_contract() {
	try {
		var cfg = CfgBuilder.build (CoreBuilder.build (source ()));
		CfgVerifier.verify (cfg);
		var bound = cfg_named (cfg, "bound");
		var initialize = (CfgInitialize) bound.entry.instructions[0];
		var address = (CfgFunctionAddress) initialize.value;
		bound.entry.instructions[0] = new CfgInitialize (initialize.span, initialize.target,
			new CfgFunctionAddress (address.span, (FunctionValueType) address.semantic_type, cfg_named (cfg, "wide")));
		bool rejected = false;
		try {
			CfgVerifier.verify (cfg);
		} catch (CfgError error) {
			rejected = true;
			Test.message ("CFG forged address: %s", error.message);
		}
		assert (rejected);
		bound.entry.instructions[0] = initialize;
		CfgVerifier.verify (cfg);
		var apply = cfg_named (cfg, "apply");
		var call = (CfgFunctionValueCall) ((CfgReturn) apply.entry.terminator).value;
		var argument = call.arguments[0];
		call.arguments[0] = call.callee;
		rejected = false;
		try {
			CfgVerifier.verify (cfg);
		} catch (CfgError error) {
			rejected = true;
			Test.message ("CFG code as scalar argument: %s", error.message);
		}
		assert (rejected);
		call.arguments[0] = argument;
		CfgVerifier.verify (cfg);
		call.arguments.remove_index (0);
		rejected = false;
		try {
			CfgVerifier.verify (cfg);
		} catch (CfgError error) {
			rejected = true;
			Test.message ("CFG missing argument: %s", error.message);
		}
		assert (rejected);
		call.arguments.add (argument);
		CfgVerifier.verify (cfg);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void ssa_contract() {
	try {
		var ssa = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (source ())));
		SsaVerifier.verify (ssa);
		var bound = ssa_named (ssa, "bound");
		int position = -1;
		for (int i = 0; i < bound.entry.instructions.length; i++) {
			if (bound.entry.instructions[i] is SsaFunctionValueCall) {
				position = i;
			}
		}
		assert (position >= 0);
		var direct = (SsaFunctionValueCall) bound.entry.instructions[position];
		var address = (SsaFunctionAddress) direct.callee;
		bound.entry.instructions[position] = new SsaFunctionValueCall (direct.span,
			(FunctionValueType) address.semantic_type,
			new SsaFunctionAddress (address.span, (FunctionValueType) address.semantic_type, ssa_named (ssa, "wide")),
			direct.arguments, direct.result.ordinal);
		bool rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			rejected = true;
			Test.message ("SSA forged address: %s", error.message);
		}
		assert (rejected);
		bound.entry.instructions[position] = direct;
		SsaVerifier.verify (ssa);
		var apply = ssa_named (ssa, "apply");
		position = -1;
		for (int i = 0; i < apply.entry.instructions.length; i++) {
			if (apply.entry.instructions[i] is SsaFunctionValueCall) {
				position = i;
			}
		}
		assert (position >= 0);
		var call = (SsaFunctionValueCall) apply.entry.instructions[position];
		var argument = call.arguments[0];
		call.arguments[0] = call.callee;
		rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			rejected = true;
			Test.message ("SSA code as scalar argument: %s", error.message);
		}
		assert (rejected);
		call.arguments[0] = argument;
		SsaVerifier.verify (ssa);
		apply.entry.instructions[position] = new SsaFunctionValueCall (call.span,
			(FunctionValueType) call.callee.semantic_type, argument, call.arguments, call.result.ordinal);
		rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			rejected = true;
			Test.message ("SSA scalar as code: %s", error.message);
		}
		assert (rejected);
		apply.entry.instructions[position] = call;
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
		var function = native.functions[ssa_named (ssa, "apply").ordinal];
		var parameter = function.signature.parameters[0];
		var typed = (NativeFunctionPointerType) parameter.abi_type;
		var data = new NativeScalarAbiType (NativeScalarType.PTR);
		assert (!data.same_type (typed) && !typed.same_type (data));
		function.signature.parameters[0] = new NativeParameter (parameter.span, parameter.name_span, parameter.name, parameter.ordinal, NativeScalarType.PTR);
		NativeAbiVerifier.verify (native); // Both physical PTRs are legal alone.
		bool rejected = false;
		try {
			NativeAbiValidator.validate_ssa_calls (ssa, native, map);
		} catch (NativeAbiError error) {
			rejected = true;
			Test.message ("Native data/code pointer correspondence: %s", error.message);
		}
		assert (rejected);
		function.signature.parameters[0] = parameter;
		NativeAbiValidator.validate_ssa_calls (ssa, native, map);
		var wrong = new NativeFunctionPointerType (NativeScalarType.I64, typed.parameter_types);
		function.signature.parameters[0] = new NativeParameter.typed (parameter.span, parameter.name_span, parameter.name, parameter.ordinal, wrong);
		NativeAbiVerifier.verify (native);
		rejected = false;
		try {
			NativeAbiValidator.validate_ssa_calls (ssa, native, map);
		} catch (NativeAbiError error) {
			rejected = true;
			Test.message ("Native code signature correspondence: %s", error.message);
		}
		assert (rejected);
		function.signature.parameters[0] = parameter;
		NativeAbiValidator.validate_ssa_calls (ssa, native, map);
		var copied = typed.parameter_types[0];
		typed.parameter_types[0] = data;
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = true;
			Test.message ("Native forbidden pointer channel: %s", error.message);
		}
		assert (rejected);
		typed.parameter_types[0] = copied;
		NativeAbiVerifier.verify (native);
		assert (native.function_values.length > 0);
		var plan = native.function_values[0];
		native.function_values.remove_index (0);
		rejected = false;
		try {
			NativeAbiValidator.validate_ssa_calls (ssa, native, map);
		} catch (NativeAbiError error) {
			rejected = true;
			Test.message ("Native missing invocation plan: %s", error.message);
		}
		assert (rejected);
		native.function_values.insert (0, plan);
		NativeAbiValidator.validate_ssa_calls (ssa, native, map);
		native.function_values.add (plan);
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = true;
			Test.message ("Native duplicate invocation site: %s", error.message);
		}
		assert (rejected);
		native.function_values.remove_index (native.function_values.length - 1);
		NativeAbiVerifier.verify (native);
		native.function_values[0] = new NativeFunctionValuePlan (plan.caller, plan.block, plan.instruction, wrong);
		NativeAbiVerifier.verify (native);
		rejected = false;
		try {
			NativeAbiValidator.validate_ssa_calls (ssa, native, map);
		} catch (NativeAbiError error) {
			rejected = true;
			Test.message ("Native invocation plan signature: %s", error.message);
		}
		assert (rejected);
		native.function_values[0] = plan;
		NativeAbiValidator.validate_ssa_calls (ssa, native, map);
		native.function_values.add (new NativeFunctionValuePlan (0, 999, 999, typed));
		NativeAbiVerifier.verify (native);
		rejected = false;
		try {
			NativeAbiValidator.validate_ssa_calls (ssa, native, map);
		} catch (NativeAbiError error) {
			rejected = true;
			Test.message ("Native invented invocation site: %s", error.message);
		}
		assert (rejected);
		native.function_values.remove_index (native.function_values.length - 1);
		NativeAbiValidator.validate_ssa_calls (ssa, native, map);
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
		int mutations = 0;
		foreach (var binding in artifact.class_calls) {
			var call = binding.instruction;
			uint count = CApi.argument_count (call);
			if (count != 1) {
				continue;
			}
			var code = CApi.operand (call, count);
			CApi.set_operand (call, count, CApi.const_null (CApi.type_of (code)));
			generic_valid (artifact);
			bool rejected = false;
			try {
				artifact.verify ();
			} catch (LlvmError error) {
				rejected = true;
				Test.message ("LLVM forged code address: %s", error.message);
			}
			assert (rejected);
			CApi.set_operand (call, count, code);
			artifact.verify ();
			mutations++;
			var argument = CApi.operand (call, 0);
			CApi.set_operand (call, 0, CApi.const_null (CApi.type_of (argument)));
			generic_valid (artifact);
			rejected = false;
			try {
				artifact.verify ();
			} catch (LlvmError error) {
				rejected = true;
				Test.message ("LLVM forged scalar input: %s", error.message);
			}
			assert (rejected);
			CApi.set_operand (call, 0, argument);
			artifact.verify ();
			mutations++;
			CApi.set_instruction_call_conv (call, CApi.CallConv.C);
			generic_valid (artifact);
			rejected = false;
			try {
				artifact.verify ();
			} catch (LlvmError error) {
				rejected = true;
				Test.message ("LLVM foreign convention: %s", error.message);
			}
			assert (rejected);
			CApi.set_instruction_call_conv (call, CApi.CallConv.FAST);
			artifact.verify ();
			mutations++;
		}
		assert (mutations >= 6);
		// LLVM opaque pointers accept this different call-site signature. The
		// independently retained native Fn contract must still reject it.
		var apply = CApi.named_function (artifact.module, "astra.fn.%d".printf (ssa_named (ssa, "apply").ordinal));
		bool changed_signature = false;
		foreach (var binding in artifact.class_calls) {
			var original = binding.instruction;
			if ((void*) CApi.block_parent (CApi.instruction_parent (original)) != (void*) apply) {
				continue;
			}
			var block = CApi.append_basic_block_in_context (artifact.context, apply, "forged.signature");
			var builder = CApi.create_builder_in_context (artifact.context);
			CApi.position_builder_at_end (builder, block);
			var parameter = CApi.int_type_in_context (artifact.context, 64);
			var signature = CApi.function_type (CApi.int32_type_in_context (artifact.context), &parameter, 1, 0);
			var argument = CApi.const_int (parameter, 7, 0);
			var call = CApi.build_call (builder, signature, CApi.called_value (original), &argument, 1, "forged.call");
			CApi.set_instruction_call_conv (call, CApi.CallConv.FAST);
			CApi.build_ret (builder, call);
			CApi.dispose_builder (builder);
			binding.instruction = call;
			generic_valid (artifact);
			bool rejected = false;
			try {
				artifact.verify ();
			} catch (LlvmError error) {
				rejected = true;
				Test.message ("LLVM mismatched opaque-pointer call signature: %s", error.message);
			}
			assert (rejected);
			binding.instruction = original;
			CApi.delete_basic_block (block);
			artifact.verify ();
			changed_signature = true;
			break;
		}
		assert (changed_signature);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
public int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/function-value/checked-core-signature-callee-arguments", checked_and_core);
	Test.add_func ("/function-value/cfg-address-and-call-arity", cfg_contract);
	Test.add_func ("/function-value/ssa-address-and-code-scalar-separation", ssa_contract);
	Test.add_func ("/function-value/native-code-pointer-signature", native_contract);
	Test.add_func ("/function-value/llvm-code-arguments-convention", llvm_contract);
	return Test.run ();
}
}
