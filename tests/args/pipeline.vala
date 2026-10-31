// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
#if ARGS_LLVM
using Astra.Backend.LLVM;
#endif

namespace Astra.Tests.ArgsPipeline {
private SsaProgram build(string text) throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("args.astra", text));
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.format ());
	}
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	return SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (checked.program))));
}
private void lifetimes() {
	try {
		SourceFile? file = new SourceFile.from_text ("args.astra", "const LABEL=\"ok\"; int f(string[] a){var copy=a;var t=copy[0];if(t==LABEL){return t.byte_length;}return len(copy);} int main(string[] a){return f(a);}");
		var source = WeakRef (file);
		ParseResult? parsed = Parser.parse (file);
		file = null;
		var syntax = WeakRef (parsed.unit);
		SemanticResult? checked = SemanticAnalyzer.analyze (parsed.unit);
		parsed = null;
		assert (checked.diagnostic == null && syntax.get () == null);
		var checked_ref = WeakRef (checked.program);
		var checked_function = WeakRef (checked.program.functions[0]);
		var constants = WeakRef (checked.program.constants[0]);
		var universe = WeakRef (checked.program.types);
		CoreProgram? core = CoreBuilder.build (checked.program);
		checked = null;
		assert (checked_ref.get () == null && checked_function.get () == null && constants.get () == null && universe.get () == null);
		CoreVerifier.verify (core);
		core = CoreGenericMonomorphizer.build (core);
		var prior_core = WeakRef (core);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (prior_core.get () == null);
		CfgVerifier.verify (cfg);
		assert (CfgFlowChecker.check (cfg).diagnostic == null);
		var prior_cfg = WeakRef (cfg);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (prior_cfg.get () == null);
		SsaVerifier.verify (ssa);
		NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
		CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
		NativeProgramEntryPlan? plan = NativeEntryBuilder.build (ssa, nabi, ssa.functions[1]);
#if ARGS_LLVM
		var artifact = LlvmLowering.lower (ssa, nabi, cabi, ssa.functions[1], plan);
		assert (artifact.requires_text_slices);
		foreach (string target in new string[] {"aarch64-unknown-linux-gnu", "x86_64-pc-windows-msvc", "i686-unknown-linux-gnu"}) {
			bool rejected = false;
			try {
				LlvmArguments.qualify (target);
			} catch (LlvmError error) {
				rejected = true;
			}
			assert (rejected);
		}
		artifact.configure_executable (new LlvmTargetMachineArtifact ());
		assert (artifact.text_slice_layout.qualified ());
		var layout = artifact.text_slice_layout;
		Test.message ("LLVM target layout: pointer=%u offsets=%s/%s stride=%s alignment=%u", layout.pointer_bytes, layout.data_offset.to_string (), layout.length_offset.to_string (), layout.stride.to_string (), layout.alignment);
		string ir = artifact.dump ();
		assert (ir.contains ("define i32 @main(i32") && ir.contains ("@astra_host_args_prepare_v0") && ir.contains ("args.valid") && ir.contains ("@astra_host_args_dispose_v0"));
#endif
		var prior_ssa = WeakRef (ssa);
		var prior_function = WeakRef (ssa.functions[1]);
		ssa = null;
		assert (prior_ssa.get () == null && prior_function.get () == null);
		NativeAbiVerifier.verify (nabi);
		CAbiVerifier.verify (cabi);
		var prior_nabi = WeakRef (nabi);
		nabi = null;
		cabi = null;
		assert (prior_nabi.get () == null);
		plan.verify ();
		plan = null;
		assert (source.get () == null);
#if ARGS_LLVM
		artifact.verify ();
#endif
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void correspondence() {
	try {
		var source = build ("int f(string[] a){return len(a);}");
		var wrong = build ("int f(int[] a){return len(a);}");
		var wrong_plan = NativeAbiBuilder.build (wrong);
		NativeAbiVerifier.verify (wrong_plan);
		var mapping = new HashTable<SsaFunction, NativeFunction> (direct_hash, direct_equal);
		mapping.insert (source.functions[0], wrong_plan.functions[0]);
		bool rejected = false;
		try {
			NativeAbiValidator.validate_ssa_calls (source, wrong_plan, mapping);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		var entries = build ("int helper(){return 0;} int main(string[] a){return helper()+len(a);}");
		var native = NativeAbiBuilder.build (entries);
		assert (native.functions[0].signature.abi_version == NativeAbiVersion.SCALAR_V0 && native.functions[1].signature.abi_version == NativeAbiVersion.TEXT_SLICE_V10);
		var other_entry = NativeEntryBuilder.build (entries, native, entries.functions[0]);
		other_entry.verify ();
		rejected = false;
		try {
			NativeEntryBuilder.validate (other_entry, entries, native, entries.functions[1]);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
#if ARGS_LLVM
		rejected = false;
		try {
			LlvmLowering.lower (entries, native, CAbiBuilder.build (entries, native), entries.functions[1], other_entry);
		} catch (LlvmError error) {
			rejected = true;
		}
		assert (rejected);
#endif
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
#if ARGS_LLVM
private int emit(string[] args) throws GLib.Error {
	var files = new GenericArray<SourceFile> ();
	var declarations = new GenericArray<ForeignDeclarationInput> ();
	var handles = new GenericArray<ForeignHandleInput> ();
	for (int i = 3; i < args.length; i++) {
		bool vapi = args[i] == "--vapi";
		if (vapi) {
			i++;
		}
		string text;
		FileUtils.get_contents (args[i], out text);
		var source = new SourceFile.from_text (args[i], text);
		if (vapi) {
			var parsed = Astra.Vapi.VapiParser.parse (source);
			assert (parsed.diagnostic == null);
			foreach (var item in Astra.Vapi.VapiNormalizer.normalize (parsed.file)) {
				declarations.add (item);
			}
			foreach (var item in Astra.Vapi.VapiNormalizer.normalize_handles (parsed.file)) {
				handles.add (item);
			}
		} else {
			files.add (source);
		}
	}
	var parsed = SyntaxProgram.parse (new SourceSet (files));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze_program (parsed.program, declarations, handles);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	var cfg = CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (checked.program)));
	assert (CfgFlowChecker.check (cfg).diagnostic == null);
	var ssa = SsaBuilder.build (cfg);
	var nabi = NativeAbiBuilder.build (ssa);
	var artifact = LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi), Astra.Driver.ProgramEntry.resolve (ssa));
	artifact.configure_executable (new LlvmTargetMachineArtifact ());
	FileUtils.set_contents (args[2], artifact.dump ());
	return 0;
}
#endif
int main(string[] args) {
#if ARGS_LLVM
	if (args.length >= 4 && args[1] == "--emit") {
		try {
			return emit (args);
		} catch (GLib.Error error) {
			stderr.printf ("%s\n", error.message);
			return 1;
		}
	}
#endif
	Test.init (ref args);
	Test.add_func ("/args/pipeline/independent-stage-lifetimes", lifetimes);
	Test.add_func ("/args/pipeline/exact-correspondence", correspondence);
	return Test.run ();
}
}
