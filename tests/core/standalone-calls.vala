// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.CoreStandalone {
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
	functions.add (call_function (span, types.int_type, types.int_type, "f"));
	functions.add (call_function (span, types.int_type, types.int_type, "g"));
	functions.add (call_function (span, types.void_type, null, "ping"));
	functions[0].body.statements.add (new CoreReturn (span, new CoreCallValue (span, types.int_type, functions[1], call_arguments (functions[0]))));
	functions[1].body.statements.add (new CoreCallStatement (span, functions[0], call_arguments (functions[1])));
	functions[1].body.statements.add (new CoreReturn (span, new CoreCallValue (span, types.int_type, functions[1], call_arguments (functions[1]))));
	functions[2].body.statements.add (new CoreCallStatement (span, functions[2], new GenericArray<CoreValue> ()));
	functions[2].body.statements.add (new CoreReturn (span, null));
	return new CoreProgram (span, functions);
}

private void calls_model_and_lifetime() {
	try {
		CoreProgram? program = call_program ();
		var first = WeakRef (program.functions[0]);
		var second = WeakRef (program.functions[1]);
		var ping = WeakRef (program.functions[2]);
		var body = WeakRef (program.functions[0].body);
		CoreVerifier.verify (program);
		assert (((CoreCallValue) ((CoreReturn) program.functions[0].body.statements[0]).value).target == program.functions[1]);
		assert (((CoreCallStatement) program.functions[1].body.statements[0]).target == program.functions[0]);
		assert (((CoreCallValue) ((CoreReturn) program.functions[1].body.statements[1]).value).target == program.functions[1]);
		string dump = CoreDump.format (program);
		assert (dump == CoreDump.format (program) && dump.contains ("(call-statement \"ping\" -> void"));
		program = null;
		assert (first.get () == null && second.get () == null && ping.get () == null && body.get () == null);
	} catch (CoreError error) {
		GLib.error ("Standalone Core calls failed: %s", error.message);
	}
}

private void invalid_calls() {
	string[] messages = {
		"call target is not owned by the containing program",
		"call target is not owned by the containing program",
		"call argument count does not match target parameters",
		"call argument count does not match target parameters",
		"call argument type does not match target parameter",
		"call value must match a non-void target return type",
		"call value must match a non-void target return type",
		"call argument count does not match target parameters",
		"call argument type does not match target parameter",
		"parameter reference is not owned by the containing function"
	};
	for (int mode = 0; mode < messages.length; mode++) {
		var program = call_program ();
		var function = program.functions[0];
		var target = program.functions[1];
		var arguments = call_arguments (function);
		var types = new BuiltinTypes ();
		var result_type = function.return_type;
		CoreFunction? foreign = null;
		switch (mode) {
		case 0:
		case 1:
			foreign = call_function (function.span, result_type, result_type, target.name);
			target = foreign;
			break;
		case 2:
		case 7:
			arguments.remove_index (0);
			break;
		case 3:
			arguments.add (arguments[0]);
			break;
		case 4:
		case 8:
			arguments[0] = new CoreBooleanValue (function.span, types.bool_type, BooleanLiteral.TRUE);
			break;
		case 5:
			result_type = types.bool_type;
			break;
		case 6:
			target = program.functions[2];
			arguments.remove_index (0);
			break;
		case 9:
			arguments[0] = new CoreParameterValue (function.span, target.parameters[0]);
			break;
		}
		if (mode == 7 || mode == 8) {
			function.body.statements[0] = new CoreCallStatement (function.span, target, arguments);
		} else {
			function.body.statements[0] = new CoreReturn (function.span, new CoreCallValue (function.span, result_type, target, arguments));
		}
		if (mode == 1) {
			target = null;
			foreign = null;
			assert (((CoreCallValue) ((CoreReturn) function.body.statements[0]).value).target == null);
		}
		for (int attempt = 0; attempt < 2; attempt++) {
			try {
				if (attempt == 0) {
					CoreVerifier.verify (program);
				} else {
					CoreDump.format (program);
				}
			} catch (CoreError error) {
				assert (error is CoreError.INVALID_IR && error.message.has_suffix (": " + messages[mode]));
				continue;
			}
			GLib.error ("Invalid Core call case %d passed", mode);
		}
	}
}

private void register_call_tests() {
	Test.add_func ("/core-standalone/calls/model-and-recursive-lifetime", calls_model_and_lifetime);
	Test.add_func ("/core-standalone/calls/invalid-models", invalid_calls);
}
}
