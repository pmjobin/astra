// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.SourcesCfg {
private CfgFunction call_function(SourceSpan span, SemanticType type, SemanticType? parameter_type, string name, int ordinal) {
	var parameters = new GenericArray<CfgParameter> ();
	if (parameter_type != null) {
		parameters.add (new CfgParameter (span, span, "x", parameter_type, 0));
	}
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (new CfgBlock.reserve (span, 0));
	return new CfgFunction (span, span, name, type, ordinal, parameters, new GenericArray<CfgLocalPlace> (), blocks, blocks[0]);
}

private GenericArray<CfgValue> call_arguments(CfgValue value) {
	var arguments = new GenericArray<CfgValue> ();
	arguments.add (value);
	return arguments;
}

private CfgProgram call_program() throws CfgError {
	var file = new SourceFile.from_text ("cfg-calls.astra", "007");
	var span = SourceSpan (file, 0, file.length);
	var types = new BuiltinTypes ();
	var functions = new GenericArray<CfgFunction> ();
	functions.add (call_function (SourceSpan (new SourceFile.from_text ("f.astra", "f"), 0, 1), types.int_type, types.int_type, "f", 0));
	functions.add (call_function (SourceSpan (new SourceFile.from_text ("g.astra", "g"), 0, 1), types.int_type, types.int_type, "g", 1));
	functions.add (call_function (SourceSpan (new SourceFile.from_text ("ping.astra", "ping"), 0, 4), types.void_type, null, "ping", 2));
	for (int i = 0; i < 2; i++) {
		var function = functions[i];
		var result = new CfgCallResultValue (span, types.int_type);
		function.entry.instructions.add (new CfgCallInstruction (span, functions[1 - i], call_arguments (new CfgParameterValue (span, function.parameters[0])), result));
		if (i == 0) {
			var self_result = new CfgCallResultValue (span, types.int_type);
			function.entry.instructions.add (new CfgCallInstruction (span, function, call_arguments (result), self_result));
			result = self_result;
		}
		function.entry.complete (span, new CfgReturn (span, result));
	}
	functions[2].entry.instructions.add (new CfgCallInstruction (span, functions[2], new GenericArray<CfgValue> (), null));
	functions[2].entry.complete (span, new CfgReturn (span, null));
	return new CfgProgram (span, functions);
}

private void verify() {
	try {
		CfgProgram? program = call_program ();
		CfgVerifier.verify (program);
		assert (((CfgCallInstruction) program.functions[0].entry.instructions[0]).target == program.functions[1]);
		assert (program.functions[0].span.file.path == "f.astra" && program.functions[1].span.file.path == "g.astra");
		var f = WeakRef (program.functions[0]);
		var g = WeakRef (program.functions[1]);
		var file = WeakRef (program.functions[2].span.file);
		string dump = CfgDump.format (program);
		assert (!dump.contains (".astra"));
		program = null;
		assert (f.get () == null && g.get () == null && file.get () == null);
	} catch (CfgError error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/sources/cfg/independent-cross-file-exact-call-identities", verify);
	return Test.run ();
}

}
