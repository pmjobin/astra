// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
#if TEXT_IO_LLVM
using Astra.Backend.LLVM;
#endif

namespace Astra.Tests.TextIoPipeline {
private SourceFile source_file(CheckedProgram program) {
	return program.span.file;
}

private void lifetime() {
	try {
		var files = new GenericArray<SourceFile> ();
		foreach (string path in new string[] {"tests/text-io/fixtures/pipeline.astra"}) {
			string text;
			FileUtils.get_contents (path, out text);
			files.add (new SourceFile.from_text (path, text));
		}
		SourceSet? source_set = new SourceSet (files);
		files = null;
		SyntaxProgramResult? parsed = SyntaxProgram.parse (source_set);
		source_set = null;
		assert (parsed.diagnostic == null);
		var syntax = WeakRef (parsed.program.units[0]);
		SemanticResult? result = SemanticAnalyzer.analyze_program (parsed.program);
		parsed = null;
		assert (result.diagnostic == null && syntax.get () == null);
		var metadata = WeakRef (result.program.c_functions[0].metadata);
		var callee = WeakRef (result.program.c_functions[0]);
		var checked = WeakRef (result.program);
		var constant = WeakRef (result.program.constants[0]);
		var declaration = WeakRef (result.program.constants[0].declaration);
		var universe = WeakRef (result.program.types);
		var function = WeakRef (result.program.functions[0]);
		SourceFile? file = source_file (result.program);
		var source = WeakRef (file);
		file = null;
		CoreProgram? core = CoreBuilder.build (result.program);
		result = null;
		assert (universe.get () == null && function.get () == null && callee.get () == null && metadata.get () == null);
		assert (checked.get () == null && constant.get () == null && declaration.get () == null);
		CoreVerifier.verify (core);
		core = CoreGenericMonomorphizer.build (core);
		var core_reference = WeakRef (core);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (core_reference.get () == null);
		CfgVerifier.verify (cfg);
		assert (CfgFlowChecker.check (cfg).diagnostic == null);
		var cfg_reference = WeakRef (cfg);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (cfg_reference.get () == null);
		SsaVerifier.verify (ssa);
		NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
		CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
#if TEXT_IO_LLVM
		var artifact = LlvmLowering.lower (ssa, nabi, cabi);
		assert (artifact.requires_c_text && artifact.requires_c_floating);
		foreach (string target in new string[] {"aarch64-unknown-linux-gnu", "x86_64-pc-windows-msvc", "i686-unknown-linux-gnu"}) {
			bool rejected = false;
			try {
				LlvmTargetMachineArtifact.qualify_c_text (target);
			} catch (LlvmError error) {
				rejected = error.message.contains ("C utf8-i32 text views");
			}
			assert (rejected);
		}
		LlvmTargetMachineArtifact.qualify_c_text ("x86_64-unknown-linux-gnu");
#endif
		var ssa_reference = WeakRef (ssa);
		ssa = null;
		assert (ssa_reference.get () == null);
		NativeAbiVerifier.verify (nabi);
		CAbiVerifier.verify (cabi);
		nabi = null;
		cabi = null;
		assert (source.get () == null);
#if TEXT_IO_LLVM
		artifact.verify ();
#endif
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private SsaProgram declared(string text) throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("correspondence.astra", text));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked.diagnostic == null);
	return SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (checked.program)));
}

private void correspondence() {
	try {
		string prefix = "[CCode(text_abi=\"utf8-i32\")] extern(C) ";
		var source = declared (prefix + "int observe(borrowed string first, int second);");
		foreach (string declaration in new string[] {prefix + "int observe(int first, borrowed string second);", "extern(C) int observe(void* first, int second);", prefix + "f64 observe(borrowed string first, int second);"}) {
			var other = declared (declaration);
			var cabi = CAbiBuilder.build (other, NativeAbiBuilder.build (other));
			CAbiVerifier.verify (cabi);
			var map = new HashTable<SsaCFunction, CAbiFunction> (direct_hash, direct_equal);
			map.insert (source.c_functions[0], cabi.functions[0]);
			bool rejected = false;
			try {
				CAbiValidator.validate_ssa_calls (source, cabi, map);
			} catch (CAbiError error) {
				rejected = error is CAbiError.INCOMPATIBLE_CALL;
			}
			assert (rejected);
#if TEXT_IO_LLVM
			rejected = false;
			try {
				LlvmLowering.lower (source, NativeAbiBuilder.build (source), cabi);
			} catch (LlvmError error) {
				rejected = true;
			}
			assert (rejected);
#endif
		}
		var good = CAbiBuilder.build (source, NativeAbiBuilder.build (source));
		var foreign = declared (prefix + "int observe(borrowed string first, int second);");
		var map = new HashTable<SsaCFunction, CAbiFunction> (direct_hash, direct_equal);
		map.insert (foreign.c_functions[0], good.functions[0]);
		bool rejected = false;
		try {
			CAbiValidator.validate_ssa_calls (source, good, map);
		} catch (CAbiError error) {
			rejected = true;
		}
		assert (rejected);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/text-io/stage-lifetime-firewall", lifetime);
	Test.add_func ("/text-io/exact-source-plan-correspondence", correspondence);
	return Test.run ();
}

}
