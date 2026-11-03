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
namespace DeclaredWindowsContracts {
private delegate void Check() throws GLib.Error;
private void refused(string label, owned Check action) throws GLib.Error {
	bool rejected = false;
	try {
		action ();
	} catch (GLib.Error failure) {
		rejected = true;
		Test.message ("%s: %s", label, failure.message);
	}
	assert (rejected);
}

private const string SOURCE = "struct Packet{i64 code;f64 weight;bool enabled;}"
    + "[CExport(name=\"winproof16\",profile=\"declarations-v1\",bool_abi=\"c99\")]class Service{[Foreign]init(){}"
    + "[Foreign]Packet relay(Packet input){return input;}[Foreign]f32 half(f32 input){return input*0.5;}"
    + "[Foreign]bool choose(borrowed Callback<bool,bool> code){return code(true);}[Foreign]int count(borrowed u8[] input){return len(input);}}";
private LlvmModuleArtifact artifact(string source, string target, bool checked_gate = true) throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("windows-declarations-proof.astra", source));
	assert (parsed.diagnostic == null);
	SemanticResult? checked = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked.diagnostic == null);
	if (checked_gate) {
		Astra.Driver.RuntimeProfileAdmission.windows (checked.program);
	}
	CoreProgram? core = CoreBuilder.build (checked.program);
	checked = null;
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	SsaProgram? ssa = SsaBuilder.build (cfg);
	cfg = null;
	var prior = WeakRef (ssa.functions[0]);
	var native = NativeAbiBuilder.build (ssa);
	var cabi = CAbiBuilder.build (ssa, native);
	var result = LlvmLowering.lower (ssa, native, cabi, null, null, false, false, null, target);
	ssa = null;
	assert (prior.get () == null);
	return result;
}

private void target_and_layout() {
	try {
		var windows = new LlvmTargetMachineArtifact (0, LlvmTargetMachineArtifact.WINDOWS_INTEROP);
		var linux = new LlvmTargetMachineArtifact ();
		var host = artifact (SOURCE, "host");
		refused ("host declaration object relabeled Windows", () => windows.configure (host));
		var module = artifact (SOURCE, LlvmTargetMachineArtifact.WINDOWS_INTEROP);
		assert (module.windows_declarations && module.windows_interop_validated);
		windows.configure (module);
		module.verify ();
		assert (module.foreign_records.length != 0 && module.callback_c_bool.length != 0 && module.requires_binary32 && module.requires_c_bool && windows.pointer_bytes == 8);
		assert (CApi.get_target (module.module) == LlvmTargetMachineArtifact.WINDOWS_INTEROP);
		refused ("Windows declaration artifact relabeled host", () => linux.configure (module));
		module.selected_target = "host";
		refused ("Windows declaration lost original admission", () => windows.configure (module));
		module.selected_target = LlvmTargetMachineArtifact.WINDOWS_INTEROP;
		windows.configure (module);
		uint mutations = 0;
		for (var function = CApi.first_function (module.module); (void*) function != null; function = CApi.next_function (function)) {
			size_t length;
			string name = CApi.value_name (function, out length);
			if (!name.has_prefix ("astra.callback.from.c.")) {
				continue;
			}
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
						continue;
					}
					CApi.set_instruction_call_conv (instruction, LlvmLowering.CALL_CONVENTION);
					char* message;
					assert (CApi.verify_module (module.module, CApi.VerifierFailureAction.RETURN_STATUS, out message) == 0);
					if (message != null) {
						CApi.dispose_message (message);
					}
					refused ("ordinary-valid Windows callback crossed the wrong calling convention", () => module.verify ());
					CApi.set_instruction_call_conv (instruction, CApi.CallConv.C);
					module.verify ();
					mutations++;
				}
			}
		}
		assert (mutations == 1);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void native_descriptor_visibility() {
	try {
		foreach (bool imported in new bool[] { false, true }) {
			var parsed = Parser.parse (new SourceFile.from_text ("windows-native-descriptor.astra", SOURCE + "[ExceptionRoot]class Fault{readonly string text;init(){this.text=\"failure\";}virtual property string message{get{return this.text;}}}"));
			assert (parsed.diagnostic == null);
			var checked = SemanticAnalyzer.analyze (parsed.unit);
			assert (checked.diagnostic == null);
			var core = CoreBuilder.build (checked.program);
			var cfg = CfgBuilder.build (core);
			var ssa = SsaBuilder.build (cfg);
			var native = NativeAbiBuilder.build (ssa);
			var cabi = CAbiBuilder.build (ssa, native);
			var plan = new LlvmNativeModulePlan ();
			foreach (var owner in ssa.classes) {
				if (owner.name == "Fault") {
					plan.bind_descriptor (owner, native, "astra_mod_windows_descriptor_test", imported);
				}
			}
			var module = LlvmLowering.lower (ssa, native, cabi, null, null, false, false, plan, LlvmTargetMachineArtifact.WINDOWS_INTEROP);
			module.verify ();
			var descriptor = CApi.named_global (module.module, "astra_mod_windows_descriptor_test");
			assert ((void*) descriptor != null && CApi.get_visibility (descriptor) == CApi.Visibility.HIDDEN);
			CApi.set_visibility (descriptor, CApi.Visibility.DEFAULT);
			char* message;
			assert (CApi.verify_module (module.module, CApi.VerifierFailureAction.RETURN_STATUS, out message) == 0);
			if (message != null) {
				CApi.dispose_message (message);
			}
			refused ("ordinary-valid Windows native descriptor lost its image-local visibility", () => module.verify ());
			CApi.set_visibility (descriptor, CApi.Visibility.HIDDEN);
			module.verify ();
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void legacy_remains_bounded() {
	try {
		string plain = "f64 half(f64 input){return input*0.5;}";
		refused ("legacy checked profile retains wide/floating refusal", () => { artifact (plain, LlvmTargetMachineArtifact.WINDOWS_INTEROP);
		});
		refused ("detached legacy SSA retains wide/floating refusal", () => { artifact (plain, LlvmTargetMachineArtifact.WINDOWS_INTEROP, false);
		});
		string monitored = "[CExport(name=\"winmonitor16\",profile=\"declarations-v1\")][Shared][Monitor]class Service{[Foreign]init(){}[Foreign]int read(){return 1;}}";
		refused ("new Windows profile excludes unprovided Monitor runtime", () => { artifact (monitored, LlvmTargetMachineArtifact.WINDOWS_INTEROP);
		});
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

public static int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/declared-windows/native-unit-descriptor-image-visibility", native_descriptor_visibility);
	Test.add_func ("/declared-windows/target-layout-callback-and-detached-artifact", target_and_layout);
	Test.add_func ("/declared-windows/explicit-profile-preserves-legacy-refusals", legacy_remains_bounded);
	return Test.run ();
}

}
