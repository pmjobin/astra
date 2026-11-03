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
namespace Astra.Tests.OwningLlvm {
private LlvmModuleArtifact artifact() throws GLib.Error {
	ParseResult? parsed = Parser.parse (new SourceFile.from_text ("owning-stage-lifetimes.astra", "enum Owner{Ready(owned int[] first,owned int[] second),Empty} Owner forward(Owner input){return move input;} int main(){var owner=Owner.Ready(new int[2],new int[3]);owner=forward(move owner);match(owner){case Owner.Ready(a,b):{if(len(a)+len(b)!=5){return 1;}}else:{return 2;}}match(move owner){case Owner.Ready(a,_):{return len(a)-2;}else:{return 3;}}}"));
	assert (parsed.diagnostic == null);
	var syntax = WeakRef (parsed.unit);
	SemanticResult? checked = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked.diagnostic == null);
	parsed = null;
	assert (syntax.get () == null);
	var checked_function = WeakRef (checked.program.functions[0]);
	CoreProgram? core = CoreBuilder.build (checked.program);
	checked = null;
	assert (checked_function.get () == null);
	CoreVerifier.verify (core);
	var core_function = WeakRef (core.functions[0]);
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	assert (core_function.get () == null);
	CfgVerifier.verify (cfg);
	var cfg_function = WeakRef (cfg.functions[0]);
	SsaProgram? ssa = SsaBuilder.build (cfg);
	cfg = null;
	assert (cfg_function.get () == null);
	SsaVerifier.verify (ssa);
	var ssa_function = WeakRef (ssa.functions[0]);
	NativeAbiProgram? native = NativeAbiBuilder.build (ssa);
	CAbiProgram? foreign = CAbiBuilder.build (ssa, native);
	var native_function = WeakRef (native.functions[0]);
	var result = LlvmLowering.lower (ssa, native, foreign);
	ssa = null;
	native = null;
	foreign = null;
	assert (ssa_function.get () == null && native_function.get () == null);
	var target = new LlvmTargetMachineArtifact ();
	target.configure (result);
	result.verify ();
	return result;
}

private void ordinary(LlvmModuleArtifact artifact) {
	char* message;
	int failed = CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message);
	string text = message == null ? "" : (string) message;
	if (message != null) {
		CApi.dispose_message (message);
	}
	if (failed != 0) {
		GLib.error ("ordinary LLVM fixture failure: %s", text);
	}
}

private void physical() {
	for (int mutation = 0; mutation < 5; mutation++) {
		try {
			var module = artifact ();
			ordinary (module);
			CApi.ValueRef changed = (CApi.ValueRef) null;
			CApi.ValueRef original = (CApi.ValueRef) null;
			CApi.ValueRef next = (CApi.ValueRef) null;
			uint operand = 0;
			uint convention = 0;
			CApi.ValueRef callee = (CApi.ValueRef) null;
			for (var function = CApi.first_function (module.module); (void*) function != null && (void*) changed == null; function = CApi.next_function (function)) {
				for (var block = CApi.first_block (function); (void*) block != null && (void*) changed == null; block = CApi.next_block (block)) {
					for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
						size_t length;
						if (mutation == 0 && CApi.opcode (instruction) == CApi.Opcode.STORE && CApi.value_name (CApi.operand (instruction, 1), out length).has_prefix ("sum.live")) {
							changed = instruction;
							break;
						}
						if (mutation == 1 && CApi.opcode (instruction) == CApi.Opcode.BR && CApi.operand_count (instruction) == 3) {
							changed = instruction;
							break;
						}
						if (mutation >= 2 && CApi.opcode (instruction) == CApi.Opcode.CALL && CApi.value_name (CApi.called_value (instruction), out length) == "free") {
							changed = instruction;
							break;
						}
					}
				}
			}
			assert ((void*) changed != null);
			if (mutation <= 2) {
				original = CApi.operand (changed, operand);
				CApi.set_operand (changed, operand, mutation == 2 ? CApi.const_null (CApi.type_of (original)) : CApi.const_int (CApi.type_of (original), mutation == 0 ? 1 - CApi.const_int_zext (original) : 0, 0));
			}
			if (mutation == 3) {
				convention = CApi.instruction_call_conv (changed);
				CApi.set_instruction_call_conv (changed, CApi.CallConv.FAST);
			}
			if (mutation == 4) {
				next = CApi.next_instruction (changed);
				assert ((void*) next != null);
				original = CApi.operand (changed, 0);
				callee = CApi.called_value (changed);
				CApi.set_operand (changed, 0, CApi.const_null (CApi.type_of (original)));
				CApi.set_operand (changed, (uint) CApi.operand_count (changed) - 1, CApi.const_null (CApi.type_of (callee)));
				CApi.remove_instruction (changed);
			}
			ordinary (module);
			bool rejected = false;
			try {
				module.verify ();
			} catch (LlvmError error) {
				rejected = true;
				Test.message ("LLVM-valid owning mutation %d: %s", mutation, error.message);
			}
			assert (rejected);
			if (mutation <= 2) {
				CApi.set_operand (changed, operand, original);
			}
			if (mutation == 3) {
				CApi.set_instruction_call_conv (changed, convention);
			}
			if (mutation == 4) {
				var builder = CApi.create_builder_in_context (module.context);
				CApi.position_builder_before (builder, next);
				CApi.insert_instruction (builder, changed);
				CApi.dispose_builder (builder);
				CApi.set_operand (changed, 0, original);
				CApi.set_operand (changed, (uint) CApi.operand_count (changed) - 1, callee);
			}
			ordinary (module);
			module.verify ();
		} catch (GLib.Error error) {
			GLib.error ("%s", error.message);
		}
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/enum-own/llvm/stage-release-ordinary-valid-mutations-restoration", physical);
	Astra.Tests.OwningVerification.register ();
	return Test.run ();
}

}
