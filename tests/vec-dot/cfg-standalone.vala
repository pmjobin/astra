// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.DotCfg {
private CfgProgram sample(VectorDotKind kind, int variant = 0) throws CfgError {
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
	var parameters = new GenericArray<CfgParameter> ();
	parameters.add (new CfgParameter (span, span, "c", acc_type, 0));
	parameters.add (new CfgParameter (span, span, "a", source, 1));
	parameters.add (new CfgParameter (span, span, "b", other, 2));
	CfgValue? accumulator = present ? new CfgParameterValue (span, parameters[0]) : null;
	CfgValue first = new CfgParameterValue (span, parameters[1]);
	CfgValue second = new CfgParameterValue (span, parameters[2]);
	var node = new CfgVectorDotInstruction (span, kind, declared, result, accumulator, first, second);
	var block = new CfgBlock.reserve (span, 0);
	block.instructions.add (node);
	block.complete (span, new CfgReturn (span, node.result));
	if (variant == 13) {
		block.instructions.remove_index (0);
	}
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (block);
	var functions = new GenericArray<CfgFunction> ();
	functions.add (new CfgFunction (span, span, "f", result, 0, parameters, new GenericArray<CfgLocalPlace> (), blocks, block));
	return new CfgProgram (span, functions);
}

private void modes() {
	try {
		for (int k = 0; k < 4; k++) {
			var kind = (VectorDotKind) k;
			CfgProgram? program = sample (kind);
			var witness = WeakRef (program.functions[0]);
			CfgVerifier.verify (program);
			assert (CfgDump.format (program).contains (kind.spelling ()) && CfgDump.format (program).contains (kind.order ()));
			assert (program.functions[0].entry.instructions.length == 1 && program.functions[0].blocks.length == 1);
			assert (program.functions[0].temporaries.length == 0);
			program = null;
			assert (witness.get () == null);
			for (int variant = 1; variant <= 13; variant++) {
				bool rejected = false;
				try {
					CfgVerifier.verify (sample (kind, variant));
				} catch (CfgError error) {
					rejected = true;
				}
				if (!rejected) {
					GLib.error ("Accepted malformed Cfg dot %d variant %d", k, variant);
				}
			}
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/dot/cfg/four-modes-and-malformed-verifier", modes);
	return Test.run ();
}
}
