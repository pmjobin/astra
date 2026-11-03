// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.CfgStandalone {
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
	functions.add (call_function (span, types.int_type, types.int_type, "f", 0));
	functions.add (call_function (span, types.int_type, types.int_type, "g", 1));
	functions.add (call_function (span, types.void_type, null, "ping", 2));
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

private void calls_model_and_lifetime() {
	try {
		CfgProgram? program = call_program ();
		var first = WeakRef (program.functions[0]);
		var second = WeakRef (program.functions[1]);
		var ping = WeakRef (program.functions[2]);
		var block = WeakRef (program.functions[0].entry);
		var call = WeakRef (program.functions[0].entry.instructions[0]);
		var result = WeakRef (((CfgCallInstruction) program.functions[0].entry.instructions[0]).result);
		CfgVerifier.verify (program);
		assert (((CfgCallInstruction) program.functions[0].entry.instructions[0]).target == program.functions[1]);
		assert (((CfgCallInstruction) program.functions[0].entry.instructions[1]).target == program.functions[0]);
		assert (((CfgCallInstruction) program.functions[1].entry.instructions[0]).target == program.functions[0]);
		assert (program.functions[0].entry.terminator.successors ().length == 0);
		assert (CfgReachability.analyze (program.functions[0]).is_reachable (program.functions[0].entry));
		string dump = CfgDump.format (program);
		assert (dump == CfgDump.format (program) && dump.contains ("(call-result %0 : int)") && dump.contains ("(call #2 \"ping\" -> void"));
		program = null;
		assert (first.get () == null && second.get () == null && ping.get () == null);
		assert (block.get () == null && call.get () == null && result.get () == null);
	} catch (CfgError error) {
		GLib.error ("Standalone CFG calls failed: %s", error.message);
	}
}

private void invalid_calls() {
	string[] messages = {
		"call target is not owned by the containing program",
		"call target is not owned by the containing program",
		"call argument count does not match target parameters",
		"call argument count does not match target parameters",
		"call argument type does not match target parameter",
		"void call must not define a result",
		"non-void call must define a result matching the target return type",
		"non-void call must define a result matching the target return type",
		"call result identity occurs in more than one definition slot",
		"call result must be defined earlier in the same block or on every incoming path",
		"call result must be defined earlier in the same block or on every incoming path",
		"call result must be defined earlier in the same block or on every incoming path",
		"call result must be defined earlier in the same block or on every incoming path",
		"call result must be defined earlier in the same block or on every incoming path",
		"call instruction identity occurs in more than one instruction slot",
		"parameter reference is not owned by the containing function"
	};
	try {
		for (int mode = 0; mode < messages.length; mode++) {
			var program = call_program ();
			var function = program.functions[0];
			var old = (CfgCallInstruction) function.entry.instructions[0];
			var next = (CfgCallInstruction) function.entry.instructions[1];
			var target = old.target;
			var arguments = old.arguments;
			var result = old.result;
			CfgFunction? foreign = null;
			var types = new BuiltinTypes ();
			switch (mode) {
			case 0:
			case 1:
				foreign = call_function (function.span, function.return_type, function.return_type, target.name, target.ordinal);
				target = foreign;
				break;
			case 2:
				arguments.remove_index (0);
				break;
			case 3:
				arguments.add (arguments[0]);
				break;
			case 4:
				arguments[0] = new CfgBooleanValue (function.span, types.bool_type, BooleanLiteral.TRUE);
				break;
			case 5:
				target = program.functions[2];
				arguments.remove_index (0);
				break;
			case 6:
				result = null;
				break;
			case 7:
				result = new CfgCallResultValue (function.span, types.bool_type);
				break;
			case 8:
				function.entry.instructions[1] = new CfgCallInstruction (next.span, next.target, next.arguments, result);
				break;
			case 9:
				arguments[0] = next.result;
				break;
			case 10:
				arguments[0] = result;
				break;
			case 11:
				arguments[0] = new CfgCallResultValue (function.span, function.return_type);
				break;
			case 12:
				function.blocks.add (new CfgBlock (function.span, 1, new GenericArray<CfgInstruction> (), new CfgReturn (function.span, result)));
				break;
			case 13:
				arguments[0] = ((CfgCallInstruction) program.functions[1].entry.instructions[0]).result;
				break;
			case 15:
				arguments[0] = new CfgParameterValue (function.span, target.parameters[0]);
				break;
			}
			function.entry.instructions[0] = new CfgCallInstruction (old.span, target, arguments, result);
			if (mode == 1) {
				target = null;
				foreign = null;
				assert (((CfgCallInstruction) function.entry.instructions[0]).target == null);
			}
			if (mode == 14) {
				function.entry.instructions.add (function.entry.instructions[0]);
			}
			for (int attempt = 0; attempt < 2; attempt++) {
				try {
					if (attempt == 0) {
						CfgVerifier.verify (program);
					} else {
						CfgDump.format (program);
					}
				} catch (CfgError error) {
					if (!(error is CfgError.INVALID_CFG) || !error.message.has_suffix (": " + messages[mode])) {
						GLib.error ("CFG call case %d expected %s; got %s", mode, messages[mode], error.message);
					}
					continue;
				}
				GLib.error ("Invalid CFG call case %d passed", mode);
			}
		}
	} catch (CfgError error) {
		GLib.error ("Malformed CFG call setup failed: %s", error.message);
	}
}

private void register_call_tests() {
	Test.add_func ("/cfg-standalone/calls/model-and-recursive-lifetime", calls_model_and_lifetime);
	Test.add_func ("/cfg-standalone/calls/invalid-models", invalid_calls);
}

}
