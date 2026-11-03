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
namespace Astra.Tests.WidePhysical {
private void reject(LlvmModuleArtifact artifact) {
	bool rejected = false;
	try {
		artifact.verify ();
	} catch (LlvmError error) {
		rejected = true;
	}
	assert (rejected);
}

private void physical() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("wide-physical.astra", "i64 widen_i(int x){return x as i64;}u64 widen_u(u32 x){return x as u64;}int narrow(i64 x){return x as int;}"));
		assert (parsed.unit != null);
		var checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.program != null);
		var ssa = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (checked.program)));
		var nabi = NativeAbiBuilder.build (ssa);
		var artifact = LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
		artifact.verify ();
		int casts = 0;
		foreach (var binding in artifact.class_values) {
			var instruction = binding.instruction;
			var operation = CApi.opcode (instruction);
			if (operation != CApi.Opcode.SEXT && operation != CApi.Opcode.ZEXT && operation != CApi.Opcode.TRUNC) {
				continue;
			}
			var operand = CApi.operand (instruction, 0);
			CApi.set_operand (instruction, 0, CApi.const_int (CApi.type_of (operand), 1, 0));
			reject (artifact);
			CApi.set_operand (instruction, 0, operand);
			artifact.verify ();
			CApi.set_operand (instruction, 0, CApi.const_int (CApi.int_type_in_context (artifact.context, 16), 1, 0));
			reject (artifact);
			CApi.set_operand (instruction, 0, operand);
			artifact.verify ();
			var builder = CApi.create_builder_in_context (artifact.context);
			CApi.position_builder_before (builder, instruction);
			// All forged instructions are well formed by themselves. The
			// independent intent binding must reject their wrong signedness
			// or destination width before any native execution is possible.
			var forged = operation == CApi.Opcode.SEXT ? CApi.build_zext (builder, operand, CApi.type_of (instruction), "forged.unsigned") : operation == CApi.Opcode.ZEXT ? CApi.build_sext (builder, operand, CApi.type_of (instruction), "forged.signed") : CApi.build_trunc (builder, operand, CApi.int_type_in_context (artifact.context, 16), "forged.width");
			CApi.dispose_builder (builder);
			binding.instruction = forged;
			reject (artifact);
			binding.instruction = instruction;
			artifact.verify ();
			casts++;
		}
		assert (casts == 3);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/wide/llvm/extension-truncation-physical-mutations", physical);
	return Test.run ();
}

}
