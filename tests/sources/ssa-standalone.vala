// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;
#if SOURCES_LLVM
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;
#endif

namespace Astra.Tests.SourcesSsa {
private SsaFunction call_function(SourceSpan span, SemanticType type, SemanticType? parameter_type, string name, int ordinal) {
	var parameters = new GenericArray<SsaFunctionParameter> ();
	if (parameter_type != null) {
		parameters.add (new SsaFunctionParameter (span, span, "x", parameter_type, 0));
	}
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (new SsaBlock (span, 0, 0));
	return new SsaFunction (span, span, name, type, ordinal, parameters, blocks, blocks[0]);
}

private GenericArray<SsaValue> call_arguments(SsaValue value) {
	var arguments = new GenericArray<SsaValue> ();
	arguments.add (value);
	return arguments;
}

private SsaProgram call_program() throws SsaError {
	var file = new SourceFile.from_text ("ssa-calls.astra", "007");
	var span = SourceSpan (file, 0, file.length);
	var types = new BuiltinTypes ();
	var functions = new GenericArray<SsaFunction> ();
	functions.add (call_function (SourceSpan (new SourceFile.from_text ("f.astra", "f"), 0, 1), types.int_type, types.int_type, "f", 0));
	functions.add (call_function (SourceSpan (new SourceFile.from_text ("g.astra", "g"), 0, 1), types.int_type, types.int_type, "g", 1));
	functions.add (call_function (SourceSpan (new SourceFile.from_text ("ping.astra", "ping"), 0, 4), types.void_type, null, "ping", 2));
	for (int i = 0; i < 2; i++) {
		var function = functions[i];
		var call = new SsaCallInstruction (span, types.int_type, 1, functions[1 - i], call_arguments (function.parameters[0]));
		function.entry.instructions.add (call);
		if (i == 0) {
			call = new SsaCallInstruction (span, types.int_type, 2, function, call_arguments (call.result));
			function.entry.instructions.add (call);
		}
		function.entry.complete (new SsaReturn (span, call.result));
	}
	functions[2].entry.instructions.add (new SsaCallInstruction (span, null, -1, functions[2], new GenericArray<SsaValue> ()));
	functions[2].entry.complete (new SsaReturn (span, null));
	return new SsaProgram (span, functions);
}

private void verify() {
	try {
		SsaProgram? program = call_program ();
		SsaVerifier.verify (program);
		assert (((SsaCallInstruction) program.functions[0].entry.instructions[0]).target == program.functions[1]);
		assert (program.functions[0].span.file.path == "f.astra" && program.functions[1].span.file.path == "g.astra");
		var f = WeakRef (program.functions[0]);
		var g = WeakRef (program.functions[1]);
		var file = WeakRef (program.functions[2].span.file);
		string dump = SsaDump.format (program);
		assert (!dump.contains (".astra"));
#if SOURCES_LLVM
		NativeAbiProgram? nabi = NativeAbiBuilder.build (program);
		CAbiProgram? cabi = CAbiBuilder.build (program, nabi);
		var artifact = LlvmLowering.lower (program, nabi, cabi);
		nabi = null;
		cabi = null;
#endif
		program = null;
		assert (f.get () == null && g.get () == null && file.get () == null);
#if SOURCES_LLVM
		artifact.verify ();
		assert (!artifact.dump ().contains (".astra"));
#endif
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/sources/ssa/independent-cross-file-exact-call-identities", verify);
	return Test.run ();
}
}
