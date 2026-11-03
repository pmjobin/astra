// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.DotCore {
private CoreProgram sample(VectorDotKind kind, int variant = 0) throws CoreError {
	var types = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("synthetic", "dot"), 0, 3);
	SemanticType source = types.vector_of (kind.is_integer () ? (SemanticType) types.i8_type : types.f32_type, 4);
	SemanticType result = kind.is_integer () ? (SemanticType) types.u16_type : types.f32_type;
	SemanticType other = source;
	SemanticType declared = source;
	SemanticType acc_type = result;
	bool present = kind.is_mac ();
	if (variant == 1) {
		declared = types.vector_of (types.u8_type, 4);
	}
	if (variant == 2) {
		other = types.vector_of (types.i16_type, 4);
	}
	if (variant == 3) {
		result = types.bool_type;
		acc_type = result;
	}
	if (variant == 4) {
		acc_type = types.i32_type;
		if (!present) {
			present = true;
		}
	}
	if (variant == 5) {
		source = new VectorType (types.i32_type, 16);
		declared = source;
		other = source;
	}
	if (variant == 6) {
		result = source;
		acc_type = result;
	}
	if (variant == 7) {
		kind = (VectorDotKind) 99;
	}
	if (variant == 8) {
		source = types.vector_of (types.bool_type, 4);
		declared = source;
		other = source;
	}
	if (variant == 9) {
		source = types.vector_of (kind.is_integer () ? types.f32_type : (SemanticType) types.i32_type, 4);
		declared = source;
		other = source;
	}
	if (variant == 10) {
		source = types.vector_of (types.i32_type, 4);
		declared = source;
		other = source;
		result = types.i8_type;
		acc_type = result;
	}
	if (variant == 11) {
		source = types.i32_type;
		declared = source;
		other = source;
	}
	if (variant == 12) {
		present = !present;
	}
	var parameters = new GenericArray<CoreParameter> ();
	parameters.add (new CoreParameter (span, span, "c", acc_type, 0));
	parameters.add (new CoreParameter (span, span, "a", source, 1));
	parameters.add (new CoreParameter (span, span, "b", other, 2));
	CoreValue? accumulator = present ? new CoreParameterValue (span, parameters[0]) : null;
	CoreValue first = new CoreParameterValue (span, parameters[1]);
	CoreValue second = new CoreParameterValue (span, parameters[2]);
	var node = new CoreVectorDotValue (span, kind, declared, result, accumulator, first, second);
	var statements = new GenericArray<CoreStatement> ();
	statements.add (new CoreReturn (span, node));
	var functions = new GenericArray<CoreFunction> ();
	functions.add (new CoreFunction (span, span, "f", result, parameters, new GenericArray<CoreLocalPlace> (), new CoreBlock (span, statements)));
	return new CoreProgram (span, functions);
}

private void modes() {
	try {
		for (int k = 0; k < 4; k++) {
			var kind = (VectorDotKind) k;
			CoreProgram? program = sample (kind);
			var witness = WeakRef (program.functions[0]);
			CoreVerifier.verify (program);
			assert (CoreDump.format (program).contains (kind.spelling ()) && CoreDump.format (program).contains (kind.order ()));
			program = null;
			assert (witness.get () == null);
			for (int variant = 1; variant <= 12; variant++) {
				bool rejected = false;
				try {
					CoreVerifier.verify (sample (kind, variant));
				} catch (CoreError error) {
					rejected = true;
				}
				if (!rejected) {
					GLib.error ("Accepted malformed Core dot %d variant %d", k, variant);
				}
			}
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/dot/core/four-modes-and-malformed-verifier", modes);
	return Test.run ();
}

}
