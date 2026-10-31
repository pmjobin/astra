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

namespace Astra.Tests.VectorMemory {
private CheckedProgram check() {
	var syntax = Parser.parse(new SourceFile.from_text("memory-proof", "f32<4> read(f32[] v,int i){return load_vector(v,i,4,16);}void write(f32[] v,int i,f32<4> x){store_vector(v,i,x,16);}"));
	assert(syntax.diagnostic == null);
	var result = SemanticAnalyzer.analyze(syntax.unit);
	if (result.diagnostic != null) {
		GLib.error("%s", result.diagnostic.format());
	}
	return result.program;
}
private void checked_contract() {
	try {
		var source = check();
		var operation = ((CheckedVectorMemoryStatement)source.functions[1].body.statements[0]).operation;
		operation.contract.alignment = 1;
		bool rejected = false;
		try{
			CoreBuilder.build(source);
		} catch (CoreError error) {
			rejected = true;
		}
		assert(rejected);
		operation.contract.alignment = 16;
		CoreVerifier.verify(CoreBuilder.build(source));
	} catch (GLib.Error error) {
		GLib.error("%s", error.message);
	}
}
private void core_contract() {
	try {
		CheckedProgram? source = check();
		var program = CoreBuilder.build(source);
		var upstream = WeakRef(source);
		source = null;
		assert(upstream.get() == null);
		var operation = ((CoreVectorMemoryStatement)program.functions[1].body.statements[0]).operation;
		operation.contract.alignment = 32;
		bool rejected = false;
		try{
			CoreVerifier.verify(program);
		} catch (CoreError error) {
			rejected = true;
		}
		assert(rejected);
		operation.contract.alignment = 16;
		CoreVerifier.verify(program);
	} catch (GLib.Error error) {
		GLib.error("%s", error.message);
	}
}
private void cfg_contract() {
	try {
		CoreProgram? source = CoreBuilder.build(check());
		var program = CfgBuilder.build(source);
		var upstream = WeakRef(source);
		source = null;
		assert(upstream.get() == null);
		bool tested = false;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var evaluation = block.instructions[i] as CfgEvaluateInstruction;
					if (evaluation == null || !(evaluation.value is CfgVectorMemoryValue)) {
						continue;
					}
					var memory = (CfgVectorMemoryValue)evaluation.value;
					memory.contract.alignment = 1;
					bool rejected = false;
					try{
						CfgVerifier.verify(program);
					} catch (CfgError error) {
						rejected = true;
					}
					assert(rejected);
					memory.contract.alignment = 16;
					CfgVerifier.verify(program);
					block.instructions.remove_index(i);
					rejected = false;
					try{
						CfgVerifier.verify(program);
					} catch (CfgError error) {
						rejected = true;
					}
					assert(rejected);
					block.instructions.insert(i, evaluation);
					CfgVerifier.verify(program);
					tested = true;
				}
			}
		}
		assert(tested);
	} catch (GLib.Error error) {
		GLib.error("%s", error.message);
	}
}
private void ssa_contract() {
	try {
		CfgProgram? source = CfgBuilder.build(CoreBuilder.build(check()));
		var program = SsaBuilder.build(source);
		var upstream = WeakRef(source);
		source = null;
		assert(upstream.get() == null);
		bool tested = false;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var memory = block.instructions[i] as SsaVectorMemoryInstruction;
					if (memory == null) {
						continue;
					}
					memory.contract.alignment = 1;
					bool rejected = false;
					try{
						SsaVerifier.verify(program);
					} catch (SsaError error) {
						rejected = true;
					}
					assert(rejected);
					memory.contract.alignment = 16;
					SsaVerifier.verify(program);
					block.instructions.remove_index(i);
					rejected = false;
					try{
						SsaVerifier.verify(program);
					} catch (SsaError error) {
						rejected = true;
					}
					assert(rejected);
					block.instructions.insert(i, memory);
					SsaVerifier.verify(program);
					tested = true;
				}
			}
		}
		assert(tested);
	} catch (GLib.Error error) {
		GLib.error("%s", error.message);
	}
}
private void native_contract() {
	try {
		SsaProgram? source = SsaBuilder.build(CfgBuilder.build(CoreBuilder.build(check())));
		var program = NativeAbiBuilder.build(source);
		var upstream = WeakRef(source);
		source = null;
		assert(upstream.get() == null);
		var function = program.functions[1];
		assert(function.vector_memory.length == 1);
		var memory = function.vector_memory[0];
		function.vector_memory[0] = new NativeVectorMemoryPlan(memory.vector_type, 16, false);
		bool rejected = false;
		try{
			NativeAbiVerifier.verify(program);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert(rejected);
		function.vector_memory[0] = memory;
		NativeAbiVerifier.verify(program);
		function.vector_memory.remove_index(0);
		rejected = false;
		try{
			NativeAbiVerifier.verify(program);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert(rejected);
		function.vector_memory.add(memory);
		NativeAbiVerifier.verify(program);
	} catch (GLib.Error error) {
		GLib.error("%s", error.message);
	}
}
private void reject_llvm(LlvmModuleArtifact artifact) {
	bool rejected = false;
	try{
		artifact.verify();
	} catch (LlvmError error) {
		rejected = true;
		Test.message("%s", error.message);
	}
	assert(rejected);
}
private void llvm_contract() {
	try {
		SsaProgram? source = SsaBuilder.build(CfgBuilder.build(CoreBuilder.build(check())));
		var native = NativeAbiBuilder.build(source);
		var artifact = LlvmLowering.lower(source, native, CAbiBuilder.build(source, native));
		var upstream = WeakRef(source);
		source = null;
		assert(upstream.get() == null);
		assert(artifact.vector_memory.length == 2);
		foreach (var binding in artifact.vector_memory) {
			CApi.set_alignment(binding.operation, 1);
			reject_llvm(artifact);
			CApi.set_alignment(binding.operation, 16);
			artifact.verify();
			bool tested = false;
			foreach (var step in binding.proof) {
				if (CApi.opcode(step.instruction) != CApi.Opcode.ICMP) {
					continue;
				}
				var operand = CApi.operand(step.instruction, 0);
				CApi.set_operand(step.instruction, 0, CApi.const_null(CApi.type_of(operand)));
				reject_llvm(artifact);
				CApi.set_operand(step.instruction, 0, operand);
				artifact.verify();
				tested = true;
				break;
			}
			assert(tested);
			var following = CApi.next_instruction(binding.operation);
			assert((void*)following != null);
			CApi.remove_instruction(binding.operation);
			reject_llvm(artifact);
			var builder = CApi.create_builder_in_context(artifact.context);
			CApi.position_builder_before(builder, following);
			CApi.insert_instruction(builder, binding.operation);
			CApi.dispose_builder(builder);
			artifact.verify();
		}
	} catch (GLib.Error error) {
		GLib.error("%s", error.message);
	}
}
public static int main(string[] args) {
	Test.init(ref args);
	Test.add_func("/vector-memory/checked", checked_contract);
	Test.add_func("/vector-memory/core-detached", core_contract);
	Test.add_func("/vector-memory/cfg-detached", cfg_contract);
	Test.add_func("/vector-memory/ssa-detached", ssa_contract);
	Test.add_func("/vector-memory/native-detached", native_contract);
	Test.add_func("/vector-memory/llvm-detached", llvm_contract);
	return Test.run();
}
}
