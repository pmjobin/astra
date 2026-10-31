// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.IntegerConversionCore {
private CoreProgram sample(bool vector, int variant = 0) throws CoreError {
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
	var parameters = new GenericArray<CoreParameter> ();
	parameters.add (new CoreParameter (span, span, "x", source, 0));
	var operand = new CoreParameterValue (span, parameters[0]);
	var conversion = new CoreIntegerConversionValue (span, declared_source, destination, operand);
	var statements = new GenericArray<CoreStatement> ();
	statements.add (new CoreReturn (span, conversion));
	var functions = new GenericArray<CoreFunction> ();
	functions.add (new CoreFunction (span, span, "f", destination, parameters, new GenericArray<CoreLocalPlace> (), new CoreBlock (span, statements)));
	return new CoreProgram (span, functions);
}

private void values() {
	try {
		foreach (bool vector in new bool[] {false, true}) {
			CoreProgram? program = sample (vector);
			var weak_function = WeakRef (program.functions[0]);
			CoreVerifier.verify (program);
			string dump = CoreDump.format (program);
			assert (dump.contains (vector ? "integer-vector-convert (from i8<8>) (to u16<8>)" : "integer-convert (from i8) (to u16)"));
			program = null;
			assert (weak_function.get () == null);
		}
		for (int variant = 1; variant <= 15; variant++) {
			bool rejected = false;
			try {
				CoreVerifier.verify (sample (true, variant));
			} catch (CoreError error) {
				rejected = true;
			}
			if (!rejected) {
				GLib.error ("Accepted malformed Core integer conversion variant %d", variant);
			}
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/iconv/core/standalone-values-and-verifier", values);
	return Test.run ();
}
}
