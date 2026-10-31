// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.SourcesCore {
private CoreFunction call_function(SourceSpan span, SemanticType type, SemanticType? parameter_type, string name) {
	var parameters = new GenericArray<CoreParameter> ();
	if (parameter_type != null) {
		parameters.add (new CoreParameter (span, span, "x", parameter_type, 0));
	}
	return new CoreFunction (span, span, name, type, parameters, new GenericArray<CoreLocalPlace> (), new CoreBlock (span, new GenericArray<CoreStatement> ()));
}

private GenericArray<CoreValue> call_arguments(CoreFunction function) {
	var arguments = new GenericArray<CoreValue> ();
	arguments.add (new CoreParameterValue (function.span, function.parameters[0]));
	return arguments;
}

private CoreProgram call_program() {
	var file = new SourceFile.from_text ("core-calls.astra", "007");
	var span = SourceSpan (file, 0, file.length);
	var types = new BuiltinTypes ();
	var functions = new GenericArray<CoreFunction> ();
	functions.add (call_function (SourceSpan (new SourceFile.from_text ("f.astra", "f"), 0, 1), types.int_type, types.int_type, "f"));
	functions.add (call_function (SourceSpan (new SourceFile.from_text ("g.astra", "g"), 0, 1), types.int_type, types.int_type, "g"));
	functions.add (call_function (SourceSpan (new SourceFile.from_text ("ping.astra", "ping"), 0, 4), types.void_type, null, "ping"));
	functions[0].body.statements.add (new CoreReturn (span, new CoreCallValue (span, types.int_type, functions[1], call_arguments (functions[0]))));
	functions[1].body.statements.add (new CoreCallStatement (span, functions[0], call_arguments (functions[1])));
	functions[1].body.statements.add (new CoreReturn (span, new CoreCallValue (span, types.int_type, functions[1], call_arguments (functions[1]))));
	functions[2].body.statements.add (new CoreCallStatement (span, functions[2], new GenericArray<CoreValue> ()));
	functions[2].body.statements.add (new CoreReturn (span, null));
	return new CoreProgram (span, functions);
}

private void verify() {
	try {
		CoreProgram? program = call_program ();
		CoreVerifier.verify (program);
		assert (((CoreCallValue) ((CoreReturn) program.functions[0].body.statements[0]).value).target == program.functions[1]);
		assert (program.functions[0].span.file.path == "f.astra" && program.functions[1].span.file.path == "g.astra");
		var f = WeakRef (program.functions[0]);
		var g = WeakRef (program.functions[1]);
		var file = WeakRef (program.functions[2].span.file);
		string dump = CoreDump.format (program);
		assert (!dump.contains (".astra"));
		program = null;
		assert (f.get () == null && g.get () == null && file.get () == null);
	} catch (CoreError error) {
		GLib.error ("%s", error.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/sources/core/independent-cross-file-exact-call-identities", verify);
	return Test.run ();
}
}
