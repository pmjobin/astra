// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
#if DIAG_LLVM
using Astra.Backend.LLVM;
#endif

namespace Astra.Tests.DiagPipeline {
private const string SOURCE = "const VALUE=7; int check(int value,[CallerFilePath] string file,[CallerLineNumber] int line,[CallerArgumentExpression(\"value\")] string expression){return value;} T id<T>(T x,[CallerArgumentExpression(\"x\")] string expression){check(VALUE);return x;} int main(){return id(check(VALUE))+id<int>(1);}";
private CheckedProgram check() {
	var parsed = Parser.parse (new SourceFile.from_text ("diag.astra", SOURCE));
	assert (parsed.diagnostic == null);
	var result = SemanticAnalyzer.analyze (parsed.unit);
	assert (result.diagnostic == null);
	return result.program;
}

private void lifetimes() {
	try {
		SourceFile? file = new SourceFile.from_text ("diag.astra", SOURCE);
		var source = WeakRef (file);
		ParseResult? parsed = Parser.parse (file);
		file = null;
		var syntax = WeakRef (parsed.unit);
		SemanticResult? checked = SemanticAnalyzer.analyze (parsed.unit);
		parsed = null;
		assert (checked.diagnostic == null && syntax.get () == null);
		var call = (CheckedCallStatement) checked.program.generic_functions[0].body.statements[0];
		Astra.Text.TextBytes? leaf = ((CheckedTextExpression) call.arguments[3]).payload;
		var leaf_ref = WeakRef (leaf);
		var arguments = WeakRef (call.arguments[3]);
		call = null;
		var checked_ref = WeakRef (checked.program);
		var checked_function = WeakRef (checked.program.functions[0]);
		var constants = WeakRef (checked.program.constants[0]);
		var universe = WeakRef (checked.program.types);
		var generic = WeakRef (checked.program.generic_functions[0].definition.type_parameters[0]);
		var contract = WeakRef (checked.program.functions[0].symbol.parameters[1].caller_information);
		CoreProgram? core = CoreBuilder.build (checked.program);
		checked = null;
		assert (checked_ref.get () == null && checked_function.get () == null && constants.get () == null && universe.get () == null && generic.get () == null && contract.get () == null && arguments.get () == null);
		CoreVerifier.verify (core);
		var definition = WeakRef (core);
		core = CoreGenericMonomorphizer.build (core);
		assert (definition.get () == null);
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
#if DIAG_LLVM
		var artifact = LlvmLowering.lower (ssa, nabi, cabi);
		artifact.verify ();
		assert (!artifact.dump ().contains ("Caller") && !artifact.dump ().contains ("astra_diag_assert_fail"));
#endif
		var prior_ssa = WeakRef (ssa);
		ssa = null;
		assert (prior_ssa.get () == null);
		NativeAbiVerifier.verify (nabi);
		CAbiVerifier.verify (cabi);
		nabi = null;
		cabi = null;
		assert (source.get () == null && leaf.valid () && leaf.hex () == "56414c5545");
		leaf = null;
		assert (leaf_ref.get () == null);
#if DIAG_LLVM
		artifact.verify ();
#endif
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void forged_checked() {
	for (int defect = 0; defect < 4; defect++) {
		var checked = check ();
		var parameter = checked.functions[0].symbol.parameters[3];
		var original = parameter.caller_information;
		if (defect == 0) {
			parameter.caller_information = new CallerInformationContract (CallerInformationKind.ARGUMENT_EXPRESSION, original.span, 999);
		}
		if (defect == 1) {
			parameter.caller_information = new CallerInformationContract (CallerInformationKind.LINE_NUMBER, original.span);
		}
		if (defect == 2) {
			parameter.caller_information = new CallerInformationContract (CallerInformationKind.ARGUMENT_EXPRESSION, SourceSpan (original.span.file, 0, 0), 0);
		}
		if (defect == 3) {
			((CheckedCallStatement) checked.generic_functions[0].body.statements[0]).arguments.remove_index (3);
		}
		bool rejected = false;
		try {
			CoreBuilder.build (checked);
		} catch (CoreError error) {
			rejected = true;
			assert (error.message.contains (defect == 3 ? "argument count" : "caller-information"));
		}
		assert (rejected);
	}
}

private void repeated() {
	for (int i = 0; i < 96; i++) {
		try {
			var parsed = Parser.parse (new SourceFile.from_text ("repeated.astra", SOURCE.replace ("check(VALUE)", "check(VALUE /* capture %d */)".printf (i))));
			assert (parsed.diagnostic == null);
			var result = SemanticAnalyzer.analyze (parsed.unit);
			assert (result.diagnostic == null);
			var core = CoreGenericMonomorphizer.build (CoreBuilder.build (result.program));
			var ssa = SsaBuilder.build (CfgBuilder.build (core));
			SsaVerifier.verify (ssa);
			parsed = Parser.parse (new SourceFile.from_text ("failed.astra", SOURCE.replace ("check(VALUE)", "check()")));
			assert (parsed.diagnostic == null);
			result = SemanticAnalyzer.analyze (parsed.unit);
			assert (result.program == null && result.diagnostic.message.contains ("expects 1 through 4"));
		} catch (GLib.Error error) {
			GLib.error ("%s", error.message);
		}
	}
}

#if DIAG_LLVM
private int emit(string[] args) throws GLib.Error {
	var files = new GenericArray<SourceFile> ();
	var foreign = new GenericArray<ForeignDeclarationInput> ();
	var handles = new GenericArray<ForeignHandleInput> ();
	for (int i = 3; i < args.length; i++) {
		bool vapi = args[i] == "--vapi";
		if (vapi) {
			i++;
		}
		string bytes;
		FileUtils.get_contents (args[i], out bytes);
		var source = new SourceFile.from_text (args[i], bytes);
		if (vapi) {
			var parsed = Astra.Vapi.VapiParser.parse (source);
			assert (parsed.diagnostic == null);
			foreach (var item in Astra.Vapi.VapiNormalizer.normalize (parsed.file)) {
				foreign.add (item);
			}
			foreach (var item in Astra.Vapi.VapiNormalizer.normalize_handles (parsed.file)) {
				handles.add (item);
			}
		} else {
			files.add (source);
		}
	}
	var syntax = SyntaxProgram.parse (new SourceSet (files));
	if (syntax.diagnostic != null) {
		GLib.error ("%s", syntax.diagnostic.format ());
	}
	var checked = SemanticAnalyzer.analyze_program (syntax.program, foreign, handles);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	var cfg = CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (checked.program)));
	var flow = CfgFlowChecker.check (cfg);
	if (flow.diagnostic != null) {
		GLib.error ("%s", flow.diagnostic.format ());
	}
	var ssa = SsaBuilder.build (cfg);
	var nabi = NativeAbiBuilder.build (ssa);
	var artifact = LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi), Astra.Driver.ProgramEntry.resolve (ssa));
	artifact.configure_executable (new LlvmTargetMachineArtifact ());
	FileUtils.set_contents (args[2], artifact.dump ());
	return 0;
}

#endif
int main(string[] args) {
#if DIAG_LLVM
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
	Test.add_func ("/diag/pipeline/independent-stage-lifetimes", lifetimes);
	Test.add_func ("/diag/pipeline/forged-checked-model", forged_checked);
	Test.add_func ("/diag/pipeline/repeated-capture-reclamation", repeated);
	return Test.run ();
}

}
