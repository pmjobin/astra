// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.NumericCore {
private CoreProgram sample(SemanticType source, SemanticType destination, int variant) throws CoreError {
	var span = SourceSpan (new SourceFile.from_text ("independent", "no syntax or symbols"), 0, 20);
	var malformed_types = new BuiltinTypes ();
	var kind = NumericConversionKind.select (source, destination);
	var policy = variant == 1 ? (NumericConversionPolicy) 99 : kind.policy ();
	if (variant == 2) {
		kind = (NumericConversionKind) 99;
	}
	if (variant == 10) {
		kind = (NumericConversionKind) ((int) kind + ((int) kind % 2 == 1 ? 1 : -1));
	}
	if (variant == 11) {
		int ordinal = (int) kind;
		kind = (NumericConversionKind) (ordinal + ((ordinal - 1) % 4 < 2 ? 2 : -2));
	}
	var parameters = new GenericArray<CoreParameter> ();
	parameters.add (new CoreParameter (span, span, "x", source, 0));
	SemanticType declared = variant == 3 ? malformed_types.bool_type : source;
	var value = new CoreNumericConversionValue (span, declared, destination, kind, new CoreParameterValue (span, parameters[0]), policy);
	var statements = new GenericArray<CoreStatement> ();
	statements.add (new CoreReturn (span, value));
	var functions = new GenericArray<CoreFunction> ();
	functions.add (new CoreFunction (span, span, "f", destination, parameters, new GenericArray<CoreLocalPlace> (), new CoreBlock (span, statements)));
	return new CoreProgram (span, functions);
}

private void matrix() {
	try {
		var types = new BuiltinTypes ();
		foreach (var integer in new SemanticType[] {types.i8_type, types.u8_type, types.i16_type, types.u16_type, types.i32_type, types.u32_type}) {
			foreach (var floating in new SemanticType[] {types.f32_type, types.f64_type}) {
				foreach (bool to_float in new bool[] {false, true}) {
					SemanticType source = to_float ? integer : floating;
					SemanticType destination = to_float ? floating : integer;
					var program = sample (source, destination, 0);
					CoreVerifier.verify (program);
					string dump = CoreDump.format (program);
					assert (dump.contains ("numeric-convert") && dump.contains ("policy"));

					foreach (int malformed in new int[] {10, 11}) {
						try {
							CoreVerifier.verify (sample (source, destination, malformed));
						} catch (CoreError error) {
							continue;
						}
						GLib.error ("accepted mismatched signedness/format kind %d", malformed);
					}
					for (int variant = 1; variant <= 3; variant++) {
						try {
							CoreVerifier.verify (sample (source, destination, variant));
						} catch (CoreError error) {
							continue;
						}
						GLib.error ("accepted malformed conversion variant %d", variant);
					}
				}
			}
		}
		foreach (var unsupported in new SemanticType[] {types.bool_type, types.raw_pointer_type, types.vector_of (types.f32_type, 4), types.vector_of (types.bool_type, 4), types.i32_type}) {
			try {
				CoreVerifier.verify (sample (unsupported, types.i32_type, 0));
			} catch (CoreError error) {
				continue;
			}
			GLib.error ("accepted unsupported scalar pairing");
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

public int run_core(string[] args) {
	Test.init (ref args);
	Test.add_func ("/num-conv/Core/independent-exact-pairs-malformed-policy-proof", matrix);
	return Test.run ();
}

}
