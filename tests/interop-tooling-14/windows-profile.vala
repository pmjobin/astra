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

namespace Astra.Tests.WindowsInterop {
private delegate void Check() throws GLib.Error;
private const string SOURCE = "[CImport(name=\"observe14\")]int observe(int n);"
    + "[Shared]class Cell{int value;init(){this.value=42;}int read(){return this.value;}deinit(){observe(this.value);}}"
    + "[CExport(name=\"exercise14\")]int exercise(){var root=new Cell();var weak=root.downgrade();var copy=root.clone();release root;var again=weak.upgrade();if(again==null){return 1;}release copy;int result=again.read();release again;var dead=weak.upgrade();if(dead!=null){return 2;}release weak;return result-42;}";
private void rejected(string label, owned Check check) throws GLib.Error {
	bool refused = false;
	try {
		check ();
	} catch (LlvmError error) {
		refused = true;
		Test.message ("%s: %s", label, error.message);
	}
	if (!refused) {
		Test.message ("unexpectedly accepted mutation: %s", label);
	}
	assert (refused);
}

private LlvmModuleArtifact artifact(string target) throws GLib.Error {
	ParseResult? parsed = Parser.parse (new SourceFile.from_text ("windows-native-contract.astra", SOURCE));
	assert (parsed.diagnostic == null);
	SemanticResult? checked = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked.diagnostic == null);
	Astra.Driver.RuntimeProfileAdmission.windows (checked.program);
	parsed = null;
	CoreProgram? core = CoreBuilder.build (checked.program);
	checked = null;
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	SsaProgram? ssa = SsaBuilder.build (cfg);
	cfg = null;
	var source_identity = WeakRef (ssa.functions[0]);
	NativeAbiProgram? native = NativeAbiBuilder.build (ssa);
	CAbiProgram? foreign = CAbiBuilder.build (ssa, native);
	var result = LlvmLowering.lower (ssa, native, foreign, null, null, false, false, null, target);
	ssa = null;
	native = null;
	foreign = null;
	assert (source_identity.get () == null);
	return result;
}

private void ordinary(LlvmModuleArtifact module) {
	char* message;
	int status = CApi.verify_module (module.module, CApi.VerifierFailureAction.RETURN_STATUS, out message);
	string text = message == null ? "" : (string) message;
	if (message != null) {
		CApi.dispose_message (message);
	}
	if (status != 0) {
		error ("ordinary LLVM control failed: %s", text);
	}
}

private void target_admission() {
	try {
		var windows = new LlvmTargetMachineArtifact (0, LlvmTargetMachineArtifact.WINDOWS_INTEROP);
		var linux = new LlvmTargetMachineArtifact ();
		var host_module = artifact ("host");
		rejected ("host artifact relabeled Windows", () => windows.configure (host_module));
		var module = artifact (LlvmTargetMachineArtifact.WINDOWS_INTEROP);
		windows.configure (module);
		module.verify ();
		rejected ("Windows artifact relabeled host", () => linux.configure (module));
		module.selected_target = "host";
		rejected ("lost original target admission", () => windows.configure (module));
		module.selected_target = LlvmTargetMachineArtifact.WINDOWS_INTEROP;
		windows.configure (module);
		module.verify ();
		ordinary (module);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void lifetime_and_call_mutations() {
	try {
		var module = artifact (LlvmTargetMachineArtifact.WINDOWS_INTEROP);
		new LlvmTargetMachineArtifact (0, LlvmTargetMachineArtifact.WINDOWS_INTEROP).configure (module);
		int atomics = 0, releases = 0, calls = 0;
		foreach (var binding in module.shared_atomics) {
			var instruction = binding.instruction;
			if (CApi.opcode (instruction) != CApi.Opcode.LOAD) {
				continue;
			}
			CApi.set_ordering (instruction, 2);
			ordinary (module);
			rejected ("weakened Shared acquire load", () => module.verify ());
			CApi.set_ordering (instruction, 4);
			module.verify ();
			atomics++;
		}
		foreach (var binding in module.class_calls) {
			var call = binding.instruction;
			size_t length;
			string name = CApi.value_name (CApi.called_value (call), out length);
			if (name != "free") {
				continue;
			}
			var argument = CApi.operand (call, 0);
			// Nullable cleanup also emits unreachable free(null) sites. Only a
			// changed live-root operand is a missing-retirement mutation.
			if ((void*) CApi.is_constant_pointer_null (argument) != null) {
				continue;
			}
			CApi.set_operand (call, 0, CApi.const_null (CApi.type_of (argument)));
			ordinary (module);
			rejected ("lost exact Shared root retirement", () => module.verify ());
			CApi.set_operand (call, 0, argument);
			module.verify ();
			releases++;
		}
		for (var function = CApi.first_function (module.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var call = CApi.first_instruction (block); (void*) call != null; call = CApi.next_instruction (call)) {
					if (CApi.opcode (call) != CApi.Opcode.CALL || CApi.instruction_call_conv (call) != LlvmLowering.CALL_CONVENTION) {
						continue;
					}
					CApi.set_instruction_call_conv (call, CApi.CallConv.C);
					ordinary (module);
					size_t length;
					string callee = CApi.value_name (CApi.called_value (call), out length);
					rejected ("changed exact native call convention: " + callee, () => module.verify ());
					CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
					module.verify ();
					calls++;
				}
			}
		}
		assert (atomics > 0 && releases > 0 && calls > 0);
		ordinary (module);
		module.verify ();
		Test.message ("%d atomic, %d exact retirement and %d call-convention mutations rejected and restored", atomics, releases, calls);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/windows-interop/target-admission-and-restoration", target_admission);
	Test.add_func ("/windows-interop/ordinary-LLVM-valid-lifetime-and-call-mutations", lifetime_and_call_mutations);
	return Test.run ();
}

}
