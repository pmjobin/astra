// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.CfgStandalone {
private CfgProgram short_program(bool is_and = true) throws CfgError {
	var file = new SourceFile.from_text ("cfg-short", "a && b");
	var span = SourceSpan (file, 0, file.length);
	var types = new BuiltinTypes ();
	var parameters = new GenericArray<CfgParameter> ();
	parameters.add (new CfgParameter (span, span, "a", types.bool_type, 0));
	parameters.add (new CfgParameter (span, span, "b", types.bool_type, 1));
	var blocks = new GenericArray<CfgBlock> ();
	for (int i = 0; i < 4; i++) {
		blocks.add (new CfgBlock.reserve (span, i));
	}
	var f = new CfgFunction (span, span, "f", types.bool_type, 0, parameters, new GenericArray<CfgLocalPlace> (), blocks, blocks[0]);
	var t = new CfgTemporaryPlace (span, types.bool_type, 0);
	f.temporaries.add (t);
	blocks[0].complete (span, new CfgBranch (span, blocks[1]));
	blocks[1].instructions.add (new CfgInitialize (span, t, new CfgBooleanValue (span, types.bool_type, is_and ? BooleanLiteral.FALSE : BooleanLiteral.TRUE)));
	blocks[1].complete (span, new CfgConditionalBranch (span, new CfgParameterValue (span, parameters[0]), blocks[is_and ? 2 : 3], blocks[is_and ? 3 : 2]));
	blocks[2].instructions.add (new CfgStore (span, t, new CfgParameterValue (span, parameters[1])));
	blocks[2].complete (span, new CfgBranch (span, blocks[3]));
	blocks[3].complete (span, new CfgReturn (span, new CfgLoadValue (span, t)));
	var functions = new GenericArray<CfgFunction> ();
	functions.add (f);
	return new CfgProgram (span, functions);
}

private void short_model() {
	try {
		foreach (bool is_and in new bool[] {true, false}) {
			CfgProgram? program = short_program (is_and);
			CfgVerifier.verify (program);
			assert (CfgFlowChecker.check (program).diagnostic == null);
			string dump = CfgDump.format (program);
			assert (dump.contains ("temporary-place #0 : bool") && !dump.contains ("local-place"));
			assert (dump.contains ("(initialize") && dump.contains ("(store") && dump.contains ("(load"));
			var place_ref = WeakRef (program.functions[0].temporaries[0]);
			var block_ref = WeakRef (program.functions[0].blocks[3]);
			var branch = (CfgBranch) program.functions[0].blocks[2].terminator;
			program = null;
			assert (place_ref.get () == null && block_ref.get () == null && branch.target == null);
		}
	} catch (CfgError error) {
		GLib.error ("%s", error.message);
	}
}

private void short_invalid() {
	try {
		for (int variant = 0; variant < 9; variant++) {
			var program = short_program ();
			var f = program.functions[0];
			var t = f.temporaries[0];
			var span = t.span;
			string expected;
			switch (variant) {
			case 0:
				f.temporaries.remove_index (0);
				expected = "temporary place is not owned";
				break;
			case 1:
				f.temporaries.add (t);
				expected = "temporary identity/ordinal";
				break;
			case 2:
				f.temporaries[0] = new CfgTemporaryPlace (span, t.semantic_type, 2);
				expected = "temporary identity/ordinal";
				break;
			case 3:
				f.temporaries[0] = new CfgTemporaryPlace (span, new IntegerType (TypeKind.INT), 0);
				expected = "generated temporary must have type 'bool'";
				break;
			case 4:
				f.blocks[1].instructions.remove_index (0);
				expected = "temporary must have exactly one initialization";
				break;
			case 5:
				f.blocks[2].instructions.add (f.blocks[1].instructions[0]);
				expected = "temporary must have exactly one initialization";
				break;
			case 6:
				f.blocks[2].instructions[0] = new CfgStore (span, new CfgTemporaryPlace (span, t.semantic_type, 0), new CfgBooleanValue (span, t.semantic_type, BooleanLiteral.TRUE));
				expected = "temporary place is not owned";
				break;
			case 7:
				f.blocks[1].instructions[0] = new CfgInitialize (span, t, new CfgIntegerValue (span, new IntegerType (TypeKind.INT), AstraIntValue.from_int64 (0)));
				expected = "initializer value type does not match";
				break;
			default:
				f.blocks[2].instructions[0] = new CfgStore (span, t, new CfgIntegerValue (span, new IntegerType (TypeKind.INT), AstraIntValue.from_int64 (0)));
				expected = "stored value type does not match";
				break;
			}
			try {
				CfgVerifier.verify (program);
			} catch (CfgError error) {
				assert (error.message.contains (expected));
				continue;
			}
			GLib.error ("Invalid temporary accepted: %d", variant);
		}
	} catch (CfgError error) {
		GLib.error ("%s", error.message);
	}
}

private void crossing_values() {
	try {
		// Earlier eager results may cross a complete expression region. A
		// definition in only the RHS, a later instruction, or a disconnected
		// block cannot supply a result on every path to a later use.
		for (int variant = 0; variant < 4; variant++) {
			var program = short_program ();
			var f = program.functions[0];
			var span = f.span;
			var value = new CfgEvaluatedValue (span, f.return_type);
			var instruction = new CfgEvaluateInstruction (span, new CfgParameterValue (span, f.parameters[0]), value);
			int definition = variant == 1 ? 2 : variant == 2 ? 3 : variant == 3 ? 4 : 0;
			if (variant == 3) {
				f.blocks.add (new CfgBlock (span, 4, new GenericArray<CfgInstruction> (), new CfgReturn (span, new CfgBooleanValue (span, f.return_type, BooleanLiteral.FALSE))));
			}
			f.blocks[3].instructions.add (new CfgStore (span, f.temporaries[0], value));
			f.blocks[definition].instructions.add (instruction);
			try {
				CfgVerifier.verify (program);
			} catch (CfgError error) {
				assert (variant >= 1 && variant <= 3 && error.message.contains ("every incoming path"));
				continue;
			}
			assert (variant == 0);
		}
	} catch (CfgError error) {
		GLib.error ("%s", error.message);
	}
}

private void cyclic_availability() {
	try {
		for (int variant = 0; variant < 4; variant++) {
			var file = new SourceFile.from_text ("cyclic-values", "condition");
			var span = SourceSpan (file, 0, file.length);
			var types = new BuiltinTypes ();
			var bs = new GenericArray<CfgBlock> ();
			for (int b = 0; b < 4; b++) {
				bs.add (new CfgBlock.reserve (span, b));
			}
			var value = new CfgEvaluatedValue (span, types.bool_type);
			var source = new CfgBooleanValue (span, types.bool_type, BooleanLiteral.TRUE);
			bs[variant == 0 ? 0 : variant == 2 ? 1 : 2].instructions.add (new CfgEvaluateInstruction (span, source, value));
			bs[0].complete (span, variant == 3 ? (CfgTerminator) new CfgReturn (span, source) : new CfgBranch (span, bs[1]));
			bs[1].complete (span, new CfgConditionalBranch (span, value, bs[2], bs[3]));
			bs[2].instructions.add (new CfgEvaluateInstruction (span, value, new CfgEvaluatedValue (span, types.bool_type)));
			bs[2].complete (span, new CfgBranch (span, bs[1]));
			bs[3].complete (span, new CfgReturn (span, source));
			var fs = new GenericArray<CfgFunction> ();
			fs.add (new CfgFunction (span, span, "f", types.bool_type, 0, new GenericArray<CfgParameter> (), new GenericArray<CfgLocalPlace> (), bs, bs[0]));
			try {
				CfgVerifier.verify (new CfgProgram (span, fs));
			} catch (CfgError error) {
				assert ((variant == 1 || variant == 3) && error.message.contains ("every incoming path"));
				continue;
			}
			assert (variant == 0 || variant == 2);
		}
	} catch (CfgError error) {
		GLib.error ("%s", error.message);
	}
}

private void register_shortcircuit_tests() {
	Test.add_func ("/cfg-standalone/shortcircuit/model-lifetime", short_model);
	Test.add_func ("/cfg-standalone/shortcircuit/malformed-temporaries", short_invalid);
	Test.add_func ("/cfg-standalone/shortcircuit/cross-block-availability", crossing_values);
	Test.add_func ("/cfg-standalone/shortcircuit/cyclic-definition-availability", cyclic_availability);
}

}
