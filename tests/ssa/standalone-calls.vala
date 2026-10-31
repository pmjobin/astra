// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.SsaStandalone {
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
	functions.add (call_function (span, types.int_type, types.int_type, "f", 0));
	functions.add (call_function (span, types.int_type, types.int_type, "g", 1));
	functions.add (call_function (span, types.void_type, null, "ping", 2));
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

private void calls_model_and_lifetime() {
	try {
		SsaProgram? program = call_program ();
		var first = WeakRef (program.functions[0]);
		var second = WeakRef (program.functions[1]);
		var ping = WeakRef (program.functions[2]);
		var block = WeakRef (program.functions[0].entry);
		var call = WeakRef (program.functions[0].entry.instructions[0]);
		var result = WeakRef (program.functions[0].entry.instructions[0].result);
		SsaVerifier.verify (program);
		assert (((SsaCallInstruction) program.functions[0].entry.instructions[0]).target == program.functions[1]);
		assert (((SsaCallInstruction) program.functions[0].entry.instructions[1]).target == program.functions[0]);
		assert (((SsaCallInstruction) program.functions[1].entry.instructions[0]).target == program.functions[0]);
		assert (program.functions[0].entry.terminator.successors ().length == 0);
		string dump = SsaDump.format (program);
		assert (dump == SsaDump.format (program) && dump.contains ("(%2 : int = call #0 \"f\"") && dump.contains ("(call #2 \"ping\" -> void"));
		program = null;
		assert (first.get () == null && second.get () == null && ping.get () == null);
		assert (block.get () == null && call.get () == null && result.get () == null);
	} catch (SsaError error) {
		GLib.error ("Standalone SSA calls failed: %s", error.message);
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
		"SSA definition occurs in more than one definition slot",
		"instruction result is used before its definition",
		"instruction result is used before its definition",
		"value definition is not owned by the containing function",
		"value definition is not owned by the containing function",
		"SSA value ordinal must be nonnegative and unique within the function",
		"call instruction identity occurs in more than one instruction slot",
		"value definition is not owned by the containing function"
	};
	try {
		for (int mode = 0; mode < messages.length; mode++) {
			var program = call_program ();
			var function = program.functions[0];
			var old = (SsaCallInstruction) function.entry.instructions[0];
			var next = (SsaCallInstruction) function.entry.instructions[1];
			var target = old.target;
			var arguments = old.arguments;
			SemanticType? result_type = function.return_type;
			int ordinal = 1;
			SsaFunction? foreign = null;
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
				arguments[0] = new SsaBooleanConstant (function.span, types.bool_type, BooleanLiteral.TRUE);
				break;
			case 5:
				target = program.functions[2];
				arguments.remove_index (0);
				break;
			case 6:
				result_type = null;
				break;
			case 7:
				result_type = types.bool_type;
				break;
			case 9:
				arguments[0] = next.result;
				break;
			case 11:
				arguments[0] = new SsaInstructionResult (function.span, function.return_type, 99);
				break;
			case 12:
				arguments[0] = program.functions[1].entry.instructions[0].result;
				break;
			case 13:
				ordinal = 0;
				break;
			case 15:
				arguments[0] = target.parameters[0];
				break;
			}
			var replacement = new SsaCallInstruction (old.span, result_type, ordinal, target, arguments);
			function.entry.instructions[0] = replacement;
			// Preserve consumers unless the test deliberately violates a use.
			if (replacement.result != null) {
				next.arguments[0] = replacement.result;
			}
			if (mode == 1) {
				target = null;
				foreign = null;
				assert (replacement.target == null);
			}
			if (mode == 8) {
				function.entry.instructions.add (replacement);
			}
			if (mode == 10) {
				arguments[0] = replacement.result;
			}
			if (mode == 14) {
				var ping = program.functions[2].entry;
				ping.instructions.add (ping.instructions[0]);
			}
			for (int attempt = 0; attempt < 2; attempt++) {
				try {
					if (attempt == 0) {
						SsaVerifier.verify (program);
					} else {
						SsaDump.format (program);
					}
				} catch (SsaError error) {
					if (!(error is SsaError.INVALID_SSA) || !error.message.has_suffix (": " + messages[mode])) {
						GLib.error ("SSA call case %d expected %s; got %s", mode, messages[mode], error.message);
					}
					continue;
				}
				GLib.error ("Invalid SSA call case %d passed", mode);
			}
		}
	} catch (SsaError error) {
		GLib.error ("Malformed SSA call setup failed: %s", error.message);
	}
}

private SsaFunction call_target(Sample sample) {
	var target = call_function (sample.span, sample.types.int_type, sample.types.int_type, "callee", 1);
	try {
		target.entry.complete (new SsaReturn (sample.span, target.parameters[0]));
	} catch (SsaError error) {
		GLib.error ("Call target fixture failed: %s", error.message);
	}
	sample.others.add (target);
	return target;
}

private void register_call_tests() {
	Test.add_func ("/ssa-standalone/calls/model-and-recursive-lifetime", calls_model_and_lifetime);
	Test.add_func ("/ssa-standalone/calls/invalid-models", invalid_calls);
	invalid ("call-nondominating-argument", "function #0/block #2/instruction #0/argument #0", "value definition does not dominate its use", (s) => {
			var target = call_target (s);
			s.blocks[2].instructions.add (new SsaCallInstruction (s.span, s.types.int_type, 5, target, call_arguments (s.blocks[1].instructions[0].result)));
		});
	invalid ("call-nondominating-result", "function #0/block #2/terminator/edge/argument #0", "value definition does not dominate its use", (s) => {
			var target = call_target (s);
			var call = new SsaCallInstruction (s.span, s.types.int_type, 4, target, call_arguments (s.parameters[1]));
			s.blocks[1].instructions[0] = call;
			((SsaBranch) s.ends[1]).edge.arguments[0] = call.result;
			((SsaBranch) s.ends[2]).edge.arguments[0] = call.result;
		});
}
}
