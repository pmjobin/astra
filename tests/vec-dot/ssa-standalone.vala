// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.DotSsa {
private SsaProgram sample(VectorDotKind kind, int variant = 0) throws SsaError {
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
	var parameters = new GenericArray<SsaFunctionParameter> ();
	parameters.add (new SsaFunctionParameter (span, span, "c", acc_type, 0));
	parameters.add (new SsaFunctionParameter (span, span, "a", source, 1));
	parameters.add (new SsaFunctionParameter (span, span, "b", other, 2));
	SsaValue? accumulator = present ? parameters[0] : null;
	SsaValue first = parameters[1];
	SsaValue second = parameters[2];
	var node = new SsaVectorDotInstruction (span, kind, declared, result, 3, accumulator, first, second);
	var block = new SsaBlock (span, 0, 0);
	block.instructions.add (node);
	block.complete (new SsaReturn (span, node.result));
	if (variant == 13) {
		block.instructions.remove_index (0);
	}
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (block);
	var functions = new GenericArray<SsaFunction> ();
	functions.add (new SsaFunction (span, span, "f", result, 0, parameters, blocks, block));
	return new SsaProgram (span, functions);
}

private void modes() {
	try {
		for (int k = 0; k < 4; k++) {
			var kind = (VectorDotKind) k;
			SsaProgram? program = sample (kind);
			var witness = WeakRef (program.functions[0]);
			SsaVerifier.verify (program);
			assert (SsaDump.format (program).contains (kind.spelling ()) && SsaDump.format (program).contains (kind.order ()));
			assert (program.functions[0].entry.instructions.length == 1 && program.functions[0].blocks.length == 1);
			assert (program.functions[0].storage.length == 0);
			program = null;
			assert (witness.get () == null);
			for (int variant = 1; variant <= 13; variant++) {
				bool rejected = false;
				try {
					SsaVerifier.verify (sample (kind, variant));
				} catch (SsaError error) {
					rejected = true;
				}
				if (!rejected) {
					GLib.error ("Accepted malformed Ssa dot %d variant %d", k, variant);
				}
			}
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/dot/ssa/four-modes-and-malformed-verifier", modes);
	return Test.run ();
}

}
