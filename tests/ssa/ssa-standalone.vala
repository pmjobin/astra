// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.SsaStandalone {
// Construction fixture uses the normal internal node API. Production
// completion remains write-once; malformed tests choose bad inputs before
// completing blocks, or edit the existing array-based model's contents.
private class Sample : Object {
	public BuiltinTypes types = new BuiltinTypes ();
	public SourceSpan span;
	public GenericArray<SsaFunctionParameter> parameters = new GenericArray<SsaFunctionParameter> ();
	public GenericArray<SsaBlock> blocks = new GenericArray<SsaBlock> ();
	public GenericArray<SsaTerminator> ends = new GenericArray<SsaTerminator> ();
	public GenericArray<SsaFunction> others = new GenericArray<SsaFunction> ();
	public SsaBlock entry;
	public SsaBlock foreign;
	public SemanticType return_type;
	public int incomplete = -1;

	public Sample () {
		var file = new SourceFile.from_text ("ssa-standalone.astra", "007");
		span = SourceSpan (file, 0, file.length);
		return_type = types.int_type;
		parameters.add (new SsaFunctionParameter (span, span, "c", types.bool_type, 0));
		parameters.add (new SsaFunctionParameter (span, span, "a", types.int_type, 1));
		parameters.add (new SsaFunctionParameter (span, span, "b", types.int_type, 2));
		for (int i = 0; i < 4; i++) {
			blocks.add (new SsaBlock (span, i, i));
		}
		entry = blocks[0];
		foreign = new SsaBlock (span, 0, 0);
		blocks[3].parameters.add (new SsaBlockParameter (span, span, "x", types.int_type, 3, 0));
		blocks[1].instructions.add (new SsaPrefixInstruction (span, types.int_type, 4, PrefixOperator.POSITIVE, parameters[1]));
		ends.add (new SsaConditionalBranch (span, parameters[0], edge (blocks[1], {}), edge (blocks[2], {})));
		ends.add (new SsaBranch (span, edge (blocks[3], {blocks[1].instructions[0].result})));
		ends.add (new SsaBranch (span, edge (blocks[3], {parameters[2]})));
		ends.add (new SsaReturn (span, blocks[3].parameters[0]));
	}

	public SsaEdge edge(SsaBlock target, SsaValue[] values) {
		var arguments = new GenericArray<SsaValue> ();
		foreach (var value in values) {
			arguments.add (value);
		}
		return new SsaEdge (target, arguments);
	}

	public SsaProgram finish() throws SsaError {
		for (int i = 0; i < blocks.length; i++) {
			if (i != incomplete) {
				blocks[i].complete (ends[i]);
			}
		}
		var functions = new GenericArray<SsaFunction> ();
		functions.add (new SsaFunction (span, span, "f", return_type, 0, parameters, blocks, entry));
		for (int i = 0; i < others.length; i++) {
			functions.add (others[i]);
		}
		return new SsaProgram (span, functions);
	}
}

private delegate void Corrupt(Sample sample);

private class InvalidCase : Object {
	private Corrupt corrupt;
	private string expected;

	public InvalidCase (owned Corrupt corrupt, string path, string message) {
		this.corrupt = (owned) corrupt;
		expected = "internal SSA verification error at " + path + ": " + message;
	}

	public void run() {
		var sample = new Sample ();
		corrupt (sample);
		try {
			var program = sample.finish ();
			for (int i = 0; i < 3; i++) {
				try {
					if (i == 1) {
						SsaDump.format (program);
					} else {
						SsaVerifier.verify (program);
					}
				} catch (SsaError error) {
					if (!(error is SsaError.INVALID_SSA) || error.message != expected) {
						GLib.error ("Expected: %s\nActual: %s", expected, error.message);
					}
					continue;
				}
				GLib.error ("Malformed SSA passed verification: %s", expected);
			}
		} catch (SsaError error) {
			GLib.error ("Test failed before verification: %s", error.message);
		}
	}
}

private HashTable<string, InvalidCase> cases;

private void invalid(string name, string path, string message, owned Corrupt corrupt) {
	string test_path = "/ssa-standalone/verifier/" + name;
	cases.insert (test_path, new InvalidCase ((owned) corrupt, path, message));
	Test.add_func (test_path, run_invalid);
}

private void run_invalid() {
	cases.lookup (Test.get_path ()).run ();
}

private void model() {
	try {
		var sample = new Sample ();
		assert (sample.types.resolve ("int") == sample.types.int_type && sample.types.resolve ("bool") == sample.types.bool_type && sample.types.resolve ("void") == sample.types.void_type);
		var program = sample.finish ();
		SsaVerifier.verify (program);
		string dump = SsaDump.format (program);
		assert (dump == SsaDump.format (program));
		assert (dump.contains ("(%3 \"x\" : int)") && dump.contains ("(branch #3 (%4))") && dump.contains ("(return %3)"));
		var successors = sample.blocks[0].terminator.successors ();
		assert (successors.length == 2 && successors[0] == sample.blocks[1] && successors[1] == sample.blocks[2]);
		successors.remove_index (0);
		assert (sample.blocks[0].terminator.successors ().length == 2);
		try {
			sample.blocks[0].complete (new SsaReturn (sample.span, null));
		} catch (SsaError error) {
			assert (error.message == "internal SSA construction error: block #0 already has a terminator");
			return;
		}
		GLib.error ("SSA block accepted a second terminator");
	} catch (SsaError error) {
		GLib.error ("Standalone SSA failed: %s", error.message);
	}
}

private void constants_and_function_end() {
	try {
		var sample = new Sample ();
		sample.ends[0] = new SsaConditionalBranch (sample.span, new SsaBooleanConstant (sample.span, sample.types.bool_type, BooleanLiteral.TRUE), sample.edge (sample.blocks[1], {}), sample.edge (sample.blocks[2], {}));
		sample.blocks[1].instructions[0] = new SsaPrefixInstruction (sample.span, sample.types.int_type, 4, PrefixOperator.NEGATIVE, new SsaIntegerConstant (sample.span, sample.types.int_type, AstraIntValue.from_int64 (7)));
		sample.ends[1] = new SsaBranch (sample.span, sample.edge (sample.blocks[3], {sample.blocks[1].instructions[0].result}));
		sample.ends[3] = new SsaFunctionEnd (sample.span);
		sample.return_type = sample.types.void_type;
		string dump = SsaDump.format (sample.finish ());
		assert (dump.contains ("(integer 7 : int)") && dump.contains ("(bool true : bool)") && dump.contains ("(function-end)"));
	} catch (SsaError error) {
		GLib.error ("Standalone constants failed: %s", error.message);
	}
}

private void cyclic_lifetime() {
	try {
		SsaProgram? program;
		WeakRef block_ref;
		WeakRef parameter_ref;
		{
			var sample = new Sample ();
			// A synthetic back edge exercises graph/value ownership, without
			// adding source loops or loop-specific construction machinery.
			sample.ends[3] = new SsaConditionalBranch (sample.span, sample.parameters[0], sample.edge (sample.blocks[1], {}), sample.edge (sample.blocks[2], {}));
			block_ref = WeakRef (sample.blocks[3]);
			parameter_ref = WeakRef (sample.blocks[3].parameters[0]);
			program = sample.finish ();
		}
		SsaVerifier.verify (program);
		assert (SsaDump.format (program).contains ("(arguments"));
		program = null;
		assert (block_ref.get () == null && parameter_ref.get () == null);
	} catch (SsaError error) {
		GLib.error ("Standalone cyclic lifetime failed: %s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	register_owned_tests ();
	cases = new HashTable<string, InvalidCase> (str_hash, str_equal);
	register_call_tests ();
	register_shortcircuit_tests ();
	register_field_origin_tests ();
	register_memory_tests ();
	register_loop_tests ();
	Test.add_func ("/ssa-standalone/model", model);
	Test.add_func ("/ssa-standalone/constants-and-function-end", constants_and_function_end);
	Test.add_func ("/ssa-standalone/cyclic-lifetime", cyclic_lifetime);
	invalid ("missing-edge-argument", "function #0/block #1/terminator/edge", "edge argument count does not match target block parameters", (s) => {
			((SsaBranch) s.ends[1]).edge.arguments.remove_index (0);
		});
	invalid ("extra-edge-argument", "function #0/block #1/terminator/edge", "edge argument count does not match target block parameters", (s) => {
			((SsaBranch) s.ends[1]).edge.arguments.add (s.parameters[1]);
		});
	invalid ("wrong-edge-type", "function #0/block #1/terminator/edge/argument #0", "edge argument type does not match target block parameter", (s) => {
			((SsaBranch) s.ends[1]).edge.arguments[0] = s.parameters[0];
		});
	invalid ("conditional-true-missing", "function #0/block #0/terminator/true", "edge argument count does not match target block parameters", (s) => {
			s.blocks[1].parameters.add (new SsaBlockParameter (s.span, s.span, "y", s.types.int_type, 5, 1));
		});
	invalid ("conditional-false-extra", "function #0/block #0/terminator/false", "edge argument count does not match target block parameters", (s) => {
			((SsaConditionalBranch) s.ends[0]).false_edge.arguments.add (s.parameters[1]);
		});
	invalid ("conditional-true-type", "function #0/block #0/terminator/true/argument #0", "edge argument type does not match target block parameter", (s) => {
			s.blocks[1].parameters.add (new SsaBlockParameter (s.span, s.span, "y", s.types.int_type, 5, 1));
			((SsaConditionalBranch) s.ends[0]).true_edge.arguments.add (s.parameters[0]);
		});
	invalid ("conditional-false-type", "function #0/block #0/terminator/false/argument #0", "edge argument type does not match target block parameter", (s) => {
			s.blocks[2].parameters.add (new SsaBlockParameter (s.span, s.span, "y", s.types.bool_type, 5, 1));
			((SsaConditionalBranch) s.ends[0]).false_edge.arguments.add (s.parameters[1]);
		});
	invalid ("foreign-block", "function #0/block #1/terminator/edge", "successor block is not owned by the containing function", (s) => {
			s.ends[1] = new SsaBranch (s.span, s.edge (s.foreign, {}));
		});
	invalid ("expired-target", "function #0/block #1/terminator/edge", "successor block is not owned by the containing function", (s) => {
			var expired = new SsaBlock (s.span, 0, 0);
			s.ends[1] = new SsaBranch (s.span, s.edge (expired, {}));
		});
	invalid ("non-bool-condition", "function #0/block #0/terminator/condition", "conditional branch condition must have type 'bool'", (s) => {
			var old = (SsaConditionalBranch) s.ends[0];
			s.ends[0] = new SsaConditionalBranch (s.span, s.parameters[1], old.true_edge, old.false_edge);
		});
	invalid ("duplicate-value-ordinal", "function #0/parameter #1", "SSA value ordinal must be nonnegative and unique within the function", (s) => {
			s.parameters[1] = new SsaFunctionParameter (s.span, s.span, "a", s.types.int_type, 0);
		});
	invalid ("duplicate-definition", "function #0/block #1/instruction #1/result", "SSA definition occurs in more than one definition slot", (s) => {
			s.blocks[1].instructions.add (s.blocks[1].instructions[0]);
		});
	invalid ("use-before-definition", "function #0/block #1/instruction #0/operand", "instruction result is used before its definition", (s) => {
			var later = new SsaPrefixInstruction (s.span, s.types.int_type, 5, PrefixOperator.POSITIVE, s.parameters[1]);
			s.blocks[1].instructions[0] = new SsaPrefixInstruction (s.span, s.types.int_type, 4, PrefixOperator.NEGATIVE, later.result);
			s.blocks[1].instructions.add (later);
		});
	invalid ("non-dominating-instruction", "function #0/block #2/instruction #0/operand", "value definition does not dominate its use", (s) => {
			s.blocks[2].instructions.add (new SsaPrefixInstruction (s.span, s.types.int_type, 5, PrefixOperator.NEGATIVE, s.blocks[1].instructions[0].result));
		});
	invalid ("non-dominating-edge-value", "function #0/block #2/terminator/edge/argument #0", "value definition does not dominate its use", (s) => {
			((SsaBranch) s.ends[2]).edge.arguments[0] = s.blocks[1].instructions[0].result;
		});
	invalid ("non-dominating-block-parameter", "function #0/block #1/instruction #0/operand", "value definition does not dominate its use", (s) => {
			s.blocks[1].instructions[0] = new SsaPrefixInstruction (s.span, s.types.int_type, 4, PrefixOperator.POSITIVE, s.blocks[3].parameters[0]);
		});
	invalid ("foreign-function-parameter", "function #0/block #1/instruction #0/operand", "value definition is not owned by the containing function", (s) => {
			var parameters = new GenericArray<SsaFunctionParameter> ();
			parameters.add (new SsaFunctionParameter (s.span, s.span, "foreign", s.types.int_type, 0));
			var blocks = new GenericArray<SsaBlock> ();
			blocks.add (s.foreign);
			s.others.add (new SsaFunction (s.span, s.span, "other", s.types.int_type, 1, parameters, blocks, s.foreign));
			try {
				s.foreign.complete (new SsaReturn (s.span, parameters[0]));
			} catch (SsaError error) {
				GLib.error ("Foreign fixture failed: %s", error.message);
			}
			s.blocks[1].instructions[0] = new SsaPrefixInstruction (s.span, s.types.int_type, 4, PrefixOperator.POSITIVE, parameters[0]);
		});
	invalid ("undefined-result", "function #0/block #1/instruction #0/operand", "value definition is not owned by the containing function", (s) => {
			s.blocks[1].instructions[0] = new SsaPrefixInstruction (s.span, s.types.int_type, 4, PrefixOperator.POSITIVE, new SsaInstructionResult (s.span, s.types.int_type, 99));
		});
	invalid ("void-block-parameter", "function #0/block #3/argument #0", "void is not an SSA value type", (s) => {
			s.blocks[3].parameters[0] = new SsaBlockParameter (s.span, s.span, "x", s.types.void_type, 3, 0);
		});
	invalid ("void-instruction-result", "function #0/block #1/instruction #0/result", "void is not an SSA value type", (s) => {
			s.blocks[1].instructions[0] = new SsaPrefixInstruction (s.span, s.types.void_type, 4, PrefixOperator.POSITIVE, s.parameters[1]);
		});
	invalid ("void-constant", "function #0/block #1/instruction #0/operand", "void is not an SSA value type", (s) => {
			s.blocks[1].instructions[0] = new SsaPrefixInstruction (s.span, s.types.int_type, 4, PrefixOperator.POSITIVE, new SsaIntegerConstant (s.span, s.types.void_type, AstraIntValue.from_int64 (7)));
		});
	invalid ("return-type", "function #0/block #3/terminator", "return value type does not match function return type", (s) => {
			s.ends[3] = new SsaReturn (s.span, s.parameters[0]);
		});
	invalid ("return-missing-value", "function #0/block #3/terminator", "non-void function return must carry a value", (s) => {
			s.ends[3] = new SsaReturn (s.span, null);
		});
	invalid ("void-return-value", "function #0/block #3/terminator", "return value type does not match function return type", (s) => {
			s.return_type = s.types.void_type;
		});
	invalid ("non-void-function-end", "function #0/block #3/terminator", "non-void function must not reach function-end", (s) => {
			s.ends[3] = new SsaFunctionEnd (s.span);
		});
	invalid ("block-parameter-order", "function #0/block #3/argument #1", "block parameters must follow ascending source local ordinals, then temporary ordinals", (s) => {
			s.blocks[3].parameters.add (new SsaBlockParameter (s.span, s.span, "y", s.types.int_type, 5, 0));
		});
	invalid ("bad-prefix", "function #0/block #1/instruction #0", "invalid semantic prefix operator or operand/result type", (s) => {
			s.blocks[1].instructions[0] = new SsaPrefixInstruction (s.span, s.types.int_type, 4, PrefixOperator.NOT, s.parameters[1]);
		});
	invalid ("bad-binary", "function #0/block #1/instruction #0", "invalid semantic binary operator or operand/result type", (s) => {
			s.blocks[1].instructions[0] = new SsaBinaryInstruction (s.span, s.types.int_type, 4, BinaryOperator.ADD, s.parameters[0], s.parameters[1]);
		});
	invalid ("foreign-entry", "function #0/entry", "entry block is not owned by the containing function", (s) => {
			s.entry = s.foreign;
		});
	invalid ("entry-parameters", "function #0/entry", "entry block must not require edge arguments", (s) => {
			s.entry.parameters.add (new SsaBlockParameter (s.span, s.span, "y", s.types.int_type, 5, 1));
		});
	invalid ("missing-terminator", "function #0/block #3", "block has no terminator", (s) => {
			s.incomplete = 3;
		});
	invalid ("bad-block-ordinal", "function #0/block #2", "block identity/ordinal must be unique and in array order", (s) => {
			s.blocks[2] = new SsaBlock (s.span, 8, 2);
		});
	invalid ("unreachable-block", "function #0/block #4", "SSA block is unreachable", (s) => {
			s.blocks.add (new SsaBlock (s.span, 4, 4));
			s.ends.add (new SsaReturn (s.span, s.parameters[1]));
		});
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
