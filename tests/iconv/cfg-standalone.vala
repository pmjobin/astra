// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.IntegerConversionCfg {
private CfgProgram sample(bool vector, int variant = 0) throws CfgError {
	var types = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("synthetic", "x as u16<8>"), 0, 11);
	SemanticType source = vector ? (SemanticType) types.vector_of (types.i8_type, 8) : types.i8_type;
	SemanticType destination = vector ? (SemanticType) types.vector_of (types.u16_type, 8) : types.u16_type;
	SemanticType declared_source = source;
	if (variant == 1) {
		declared_source = types.u8_type;
	}
	if (variant == 2) {
		destination = types.bool_type;
	}
	if (variant == 3) {
		destination = types.f32_type;
	}
	if (variant == 4) {
		destination = types.raw_pointer_type;
	}
	if (variant == 5) {
		destination = vector ? (SemanticType) types.u8_type : types.vector_of (types.u16_type, 8);
	}
	if (variant == 6) {
		source = types.bool_type;
		declared_source = source;
	}
	if (variant == 7) {
		source = types.f32_type;
		declared_source = source;
	}
	if (variant == 8) {
		source = types.raw_pointer_type;
		declared_source = source;
	}
	if (variant == 9) {
		source = types.vector_of (types.bool_type, 8);
		declared_source = source;
	}
	if (variant == 10) {
		destination = types.vector_of (types.bool_type, 8);
	}
	if (variant == 11) {
		destination = types.vector_of (types.u16_type, 4);
	}
	if (variant == 12) {
		destination = new VectorType (types.u16_type, 16);
	}
	if (variant == 13) {
		source = new VectorType (types.i8_type, 32);
		declared_source = source;
	}
	if (variant == 14) {
		source = types.vector_of (types.f32_type, 4);
		declared_source = source;
	}
	if (variant == 15) {
		destination = types.vector_of (types.f32_type, 4);
	}
	var parameters = new GenericArray<CfgParameter> ();
	parameters.add (new CfgParameter (span, span, "x", source, 0));
	var operand = new CfgParameterValue (span, parameters[0]);
	var conversion = new CfgIntegerConversionInstruction (span, declared_source, destination, operand);
	var block = new CfgBlock.reserve (span, 0);
	block.instructions.add (conversion);
	block.complete (span, new CfgReturn (span, conversion.result));
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (block);
	var functions = new GenericArray<CfgFunction> ();
	functions.add (new CfgFunction (span, span, "f", destination, 0, parameters, new GenericArray<CfgLocalPlace> (), blocks, block));
	return new CfgProgram (span, functions);
}

private void values() {
	try {
		foreach (bool vector in new bool[] {false, true}) {
			CfgProgram? program = sample (vector);
			var weak_function = WeakRef (program.functions[0]);
			CfgVerifier.verify (program);
			string dump = CfgDump.format (program);
			assert (dump.contains (vector ? "integer-vector-convert (from i8<8>) (to u16<8>)" : "integer-convert (from i8) (to u16)"));
			assert (program.functions[0].entry.instructions.length == 1 && program.functions[0].blocks.length == 1);
			assert (program.functions[0].locals.length == 0 && program.functions[0].temporaries.length == 0 && CfgFlowChecker.check (program).diagnostic == null);
			program = null;
			assert (weak_function.get () == null);
		}
		for (int variant = 1; variant <= 15; variant++) {
			bool rejected = false;
			try {
				CfgVerifier.verify (sample (true, variant));
			} catch (CfgError error) {
				rejected = true;
			}
			if (!rejected) {
				GLib.error ("Accepted malformed Cfg integer conversion variant %d", variant);
			}
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/iconv/cfg/standalone-values-and-verifier", values);
	return Test.run ();
}

}
