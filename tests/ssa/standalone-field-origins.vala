// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.SsaStandalone {
private SsaProgram field_origin_program(int variant = -1) throws SsaError {
	var file = new SourceFile.from_text ("scalar-origins", "p.x p.y");
	var span = SourceSpan (file, 0, file.length);
	var types = new BuiltinTypes ();
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (new SsaBlock (span, 0, 0));
	blocks.add (new SsaBlock (span, 1, 1));
	blocks[1].parameters.add (new SsaBlockParameter.field (span, span, "p.x", types.int_type, 0, 0, variant == 0 ? -1 : 0));
	blocks[1].parameters.add (new SsaBlockParameter.field (span, span, "p.y", types.int_type, 1, 0, variant == 1 ? 0 : 1));
	var arguments = new GenericArray<SsaValue> ();
	arguments.add (new SsaIntegerConstant (span, types.int_type, AstraIntValue.from_int64 (20)));
	arguments.add (new SsaIntegerConstant (span, types.int_type, AstraIntValue.from_int64 (22)));
	blocks[0].complete (new SsaBranch (span, new SsaEdge (blocks[1], arguments)));
	blocks[1].instructions.add (new SsaBinaryInstruction (span, types.int_type, 2, BinaryOperator.ADD, blocks[1].parameters[0], blocks[1].parameters[1]));
	blocks[1].complete (new SsaReturn (span, blocks[1].instructions[0].result));
	var functions = new GenericArray<SsaFunction> ();
	functions.add (new SsaFunction (span, span, "f", types.int_type, 0, new GenericArray<SsaFunctionParameter> (), blocks, blocks[0]));
	return new SsaProgram (span, functions);
}

private void field_origins() {
	try {
		SsaProgram? program = field_origin_program ();
		SsaVerifier.verify (program);
		string dump = SsaDump.format (program);
		assert (dump.contains ("\"p.y\" (local #0 field #1) : int"));
		assert (!dump.contains ("struct") && !dump.contains ("place"));
		var parameter_ref = WeakRef (program.functions[0].blocks[1].parameters[0]);
		program = null;
		assert (parameter_ref.get () == null);
		for (int i = 0; i < 2; i++) {
			try {
				SsaVerifier.verify (field_origin_program (i));
			} catch (SsaError error) {
				assert (error.message.contains (i == 0 ? "invalid scalar field promotion provenance" : "block parameters must follow"));
				continue;
			}
			GLib.error ("invalid scalar debug origin accepted");
		}
	} catch (SsaError error) {
		GLib.error ("%s", error.message);
	}
}

private void register_field_origin_tests() {
	Test.add_func ("/ssa-standalone/scalar-field-debug-origins", field_origins);
}
}
