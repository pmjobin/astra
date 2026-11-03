// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Backend.LLVM;
namespace Astra.Tests.PublicOptimizer {
private void optimizer_contract() {
	try {
		var source = new Astra.Source.SourceFile.from_text ("optimizer.astra", "export(C) int optimized_value(int value) { return value * 0 + 42; }");
		var syntax = Astra.Syntax.Parser.parse (source);
		assert (syntax.diagnostic == null);
		var checked = Astra.Semantic.SemanticAnalyzer.analyze (syntax.unit);
		assert (checked.diagnostic == null);
		var ssa = Astra.Ssa.SsaBuilder.build (Astra.Cfg.CfgBuilder.build (Astra.Core.CoreGenericMonomorphizer.build (Astra.Core.CoreBuilder.build (checked.program))));
		var native = Astra.NativeAbi.NativeAbiBuilder.build (ssa);
		var artifact = LlvmLowering.lower (ssa, native, Astra.CAbi.CAbiBuilder.build (ssa, native));
		var target = new LlvmTargetMachineArtifact (2);
		target.configure (artifact);
		string before = artifact.dump ();
		string after = target.optimized_dump (artifact);
		assert (before.contains ("mul i32") && !after.contains ("mul i32") && after.contains ("ret i32 42"));
		assert (before == artifact.dump ());
		artifact.verify ();
		var copy = CApi.clone_module (artifact.module);
		bool rejected = false;
		try {
			target.run_pipeline (copy, "astra-intentionally-invalid-pass");
		} catch (LlvmError error) {
			rejected = error is LlvmError.EMISSION && error.message.contains ("optimization failed");
		}
		CApi.dispose_module (copy);
		assert (rejected && before == artifact.dump ());
		var exported = CApi.named_function (artifact.module, "optimized_value");
		CApi.set_function_call_conv (exported, CApi.CallConv.FAST);
		rejected = false;
		try {
			target.optimized_dump (artifact);
		} catch (LlvmError error) {
			rejected = error is LlvmError.VERIFICATION;
		}
		assert (rejected); // Reject corrupted proof metadata before any optimization or execution.
		foreach (int level in new int[] {-1, 3}) {
			rejected = false;
			try {
				new LlvmTargetMachineArtifact (level);
			} catch (LlvmError error) {
				rejected = true;
			}
			assert (rejected);
		}
		foreach (string triple in new string[] {"i686-unknown-linux-gnu", "aarch64-unknown-linux-gnu", "x86_64-pc-windows-msvc", "x86_64-unknown-linux-musl", "x86_64-unknown-linux-gnux32"}) {
			rejected = false;
			try {
				LlvmTargetMachineArtifact.qualify_c_systems (triple, 8);
			} catch (LlvmError error) {
				rejected = true;
			}
			assert (rejected);
		}
		rejected = false;
		try {
			LlvmTargetMachineArtifact.qualify_c_systems ("x86_64-pc-linux-gnu", 4);
		} catch (LlvmError error) {
			rejected = true;
		}
		assert (rejected);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/compiler-systems/optimizer/proof-clone-error-target", optimizer_contract);
	return Test.run ();
}

}
