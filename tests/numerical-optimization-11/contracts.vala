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

namespace Astra.Tests.NumericalOptimization {
private const string PROGRAM = "[FloatingPoint(contract=\"on\",finite=\"on\")] f64 selected(f64 a,f64 b){return a*b+a;} f64 strict(f64 a,f64 b){return a*b+a;}";
private CheckedProgram check() {
	var syntax = Parser.parse (new SourceFile.from_text ("numerical-policy-contract", PROGRAM));
	assert (syntax.diagnostic == null);
	var result = SemanticAnalyzer.analyze (syntax.unit);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}

private void checked_contract() {
	try {
		var program = check ();
		var function = program.functions[0].symbol;
		assert (function.floating_policy == 38);
		function.floating_policy = 0;
		bool rejected = false;
		try {
			CoreBuilder.build (program);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		function.floating_policy = 38;
		CoreVerifier.verify (CoreBuilder.build (program));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void core_contract() {
	try {
		CheckedProgram? source = check ();
		var program = CoreBuilder.build (source);
		var upstream = WeakRef (source);
		source = null;
		assert (upstream.get () == null);
		program.functions[0].floating_policy = 0;
		bool rejected = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		program.functions[0].floating_policy = 38;
		CoreVerifier.verify (program);
		program.functions[1].floating_policy = 32;
		rejected = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		program.functions[1].floating_policy = 0;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void cfg_contract() {
	try {
		CoreProgram? source = CoreBuilder.build (check ());
		var program = CfgBuilder.build (source);
		var upstream = WeakRef (source);
		source = null;
		assert (upstream.get () == null);
		program.functions[0].floating_policy = 63;
		bool rejected = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			rejected = true;
		}
		assert (rejected);
		program.functions[0].floating_policy = 38;
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void ssa_contract() {
	try {
		CfgProgram? source = CfgBuilder.build (CoreBuilder.build (check ()));
		var program = SsaBuilder.build (source);
		var upstream = WeakRef (source);
		source = null;
		assert (upstream.get () == null);
		program.functions[0].floating_policy = 127;
		bool rejected = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			rejected = true;
		}
		assert (rejected);
		program.functions[0].floating_policy = 38;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_contract() {
	try {
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (check ())));
		var program = NativeAbiBuilder.build (source);
		var upstream = WeakRef (source);
		source = null;
		assert (upstream.get () == null);
		program.functions[0].floating_policy = 0;
		bool rejected = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		program.functions[0].floating_policy = 38;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void llvm_reject(LlvmModuleArtifact artifact, string reason) {
	bool rejected = false;
	try {
		artifact.verify ();
	} catch (LlvmError error) {
		rejected = true;
		Test.message ("%s", error.message);
	}
	if (!rejected) {
		GLib.error ("accepted invalid LLVM mutation: %s", reason);
	}
}

private void llvm_contract() {
	try {
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (check ())));
		var native = NativeAbiBuilder.build (source);
		var artifact = LlvmLowering.lower (source, native, CAbiBuilder.build (source, native));
		var upstream = WeakRef (source);
		source = null;
		assert (upstream.get () == null);
		assert (artifact.floating_instructions.length == 2);
		var permission = artifact.floating_instructions[0];
		var operation = permission.instruction;
		assert (CApi.get_fast_math_flags (operation) == 38);
		var domain = permission.domain;
		assert (domain != null && domain.steps.length > 3);
		permission.domain = null;
		llvm_reject (artifact, "domain-erasure");
		permission.domain = domain;
		artifact.verify ();
		foreach (var step in domain.steps) {
			if (CApi.opcode (step.instruction) != CApi.Opcode.FCMP) {
				continue;
			}
			var bound = CApi.operand (step.instruction, 1);
			CApi.set_operand (step.instruction, 1, CApi.const_null (CApi.type_of (bound)));
			llvm_reject (artifact, "bound-replacement");
			CApi.set_operand (step.instruction, 1, bound);
			artifact.verify ();
			break;
		}
		foreach (var step in domain.steps) {
			if (CApi.opcode (step.instruction) != CApi.Opcode.BR) {
				continue;
			}
			var condition = CApi.operand (step.instruction, 0);
			CApi.set_operand (step.instruction, 0, CApi.const_null (CApi.type_of (condition)));
			llvm_reject (artifact, "trap-condition");
			CApi.set_operand (step.instruction, 0, condition);
			artifact.verify ();
			break;
		}
		// LLVMSetFastMathFlags adds bits; it cannot clear them. A forged flag
		// therefore uses its own artifact rather than pretending to restore it.
		CApi.set_fast_math_flags (operation, 64);
		llvm_reject (artifact, "permission-addition");
		var second = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (check ())));
		var second_native = NativeAbiBuilder.build (second);
		artifact = LlvmLowering.lower (second, second_native, CAbiBuilder.build (second, second_native));
		bool strict_tested = false;
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (strict_tested || CApi.opcode (instruction) != CApi.Opcode.FMUL || CApi.get_fast_math_flags (instruction) != 0) {
						continue;
					}
					CApi.set_fast_math_flags (instruction, 32);
					llvm_reject (artifact, "strict-leakage");
					strict_tested = true;
				}
			}
		}
		assert (strict_tested);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

public static int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/floating/checked", checked_contract);
	Test.add_func ("/floating/core-detached", core_contract);
	Test.add_func ("/floating/cfg-detached", cfg_contract);
	Test.add_func ("/floating/ssa-detached", ssa_contract);
	Test.add_func ("/floating/native-detached", native_contract);
	Test.add_func ("/floating/llvm-detached", llvm_contract);
	return Test.run ();
}

}
