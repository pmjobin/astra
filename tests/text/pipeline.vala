// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
#if TEXT_LLVM
using Astra.Backend.LLVM;
#endif

namespace Astra.Tests.TextPipeline {
private SourceFile source_file(CheckedProgram program) {
	return program.span.file;
}

private void lifetime() {
	try {
		var files = new GenericArray<SourceFile> ();
		foreach (string path in new string[] {"tests/text/fixtures/basics.astra"}) {
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
		assert (universe.get () == null && function.get () == null);
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
#if TEXT_LLVM
		var artifact = LlvmLowering.lower (ssa, nabi, cabi);
#endif
		var ssa_reference = WeakRef (ssa);
		ssa = null;
		assert (ssa_reference.get () == null);
		NativeAbiVerifier.verify (nabi);
		CAbiVerifier.verify (cabi);
		nabi = null;
		cabi = null;
		assert (source.get () == null);
#if TEXT_LLVM
		artifact.verify ();
#endif
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/text/stage-lifetime-firewall", lifetime);
	return Test.run ();
}

}
