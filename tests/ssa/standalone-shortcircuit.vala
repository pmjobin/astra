// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.SsaStandalone {
private SsaEdge bool_edge(SsaBlock block, SsaValue? value = null) {
	var arguments = new GenericArray<SsaValue> ();
	if (value != null) {
		arguments.add (value);
	}
	return new SsaEdge (block, arguments);
}

private void boolean_join() {
	try {
		var file = new SourceFile.from_text ("ssa-bool-join", "boolean join");
		var span = SourceSpan (file, 0, file.length);
		var types = new BuiltinTypes ();
		var parameters = new GenericArray<SsaFunctionParameter> ();
		parameters.add (new SsaFunctionParameter (span, span, "a", types.bool_type, 0));
		parameters.add (new SsaFunctionParameter (span, span, "b", types.bool_type, 1));
		var blocks = new GenericArray<SsaBlock> ();
		for (int i = 0; i < 4; i++) {
			blocks.add (new SsaBlock (span, i, i));
		}
		blocks[3].parameters.add (new SsaBlockParameter.temporary (span, types.bool_type, 2, 0));
		blocks[0].complete (new SsaBranch (span, bool_edge (blocks[1])));
		blocks[1].complete (new SsaConditionalBranch (span, parameters[0], bool_edge (blocks[2]), bool_edge (blocks[3], new SsaBooleanConstant (span, types.bool_type, BooleanLiteral.FALSE))));
		blocks[2].complete (new SsaBranch (span, bool_edge (blocks[3], parameters[1])));
		blocks[3].complete (new SsaReturn (span, blocks[3].parameters[0]));
		var functions = new GenericArray<SsaFunction> ();
		functions.add (new SsaFunction (span, span, "f", types.bool_type, 0, parameters, blocks, blocks[0]));
		var program = new SsaProgram (span, functions);
		SsaVerifier.verify (program);
		string dump = SsaDump.format (program);
		assert (dump.contains ("(temporary #0) : bool") && dump.contains ("(bool false : bool)"));
		assert (!dump.contains ("short-circuit") && !dump.contains ("place") && !dump.contains ("binary"));
		// Origin is metadata only; no CFG/frontend representation is linked.
		assert (blocks[3].parameters[0].source_local_ordinal == -1);
	} catch (SsaError error) {
		GLib.error ("%s", error.message);
	}
}

private void register_shortcircuit_tests() {
	Test.add_func ("/ssa-standalone/boolean-branch-join", boolean_join);
}

}
