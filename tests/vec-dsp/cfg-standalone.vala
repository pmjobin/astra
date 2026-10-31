// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.DspCfg {
private CfgProgram sample(DspPrimitiveKind kind, int variant = 0, bool scalar = false, string category = "i8") throws CfgError {
	var types = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("synthetic", "dsp"), 0, 3);
	SemanticType source = scalar ? types.resolve (category) : types.vector_of (types.resolve (category), category == "f32" ? 4 : 8);
	if (kind.is_pack ()) {
		source = types.vector_of (types.i16_type, 4);
	}
	IntegerType? element = kind.is_widen () ? types.u16_type : kind.is_pack () ? types.u8_type : null;
	SemanticType destination = kind.is_widen () ? types.vector_of (element, 4) : kind.is_pack () ? types.vector_of (element, 8) : source;
	SemanticType declared = source;
	SemanticType other = source;
	if (variant == 1) {
		declared = types.u8_type;
	}
	if (variant == 2) {
		other = types.u32_type;
	}
	if (variant == 3) {
		destination = types.bool_type;
	}
	if (variant == 4) {
		element = types.i32_type;
	}
	if (variant == 5) {
		source = new VectorType (types.i8_type, 32);
		declared = source;
		other = source;
	}
	if (variant == 6) {
		destination = new VectorType (types.i32_type, 8);
	}
	if (variant == 7) {
		kind = (DspPrimitiveKind) 99;
	}
	if (variant == 8) {
		source = types.vector_of (types.bool_type, 8);
		declared = source;
		other = source;
		destination = source;
	}
	if (variant == 9) {
		source = types.vector_of (types.f32_type, 4);
		declared = source;
		other = source;
		destination = source;
	}
	if (variant == 10) {
		element = types.u8_type;
		destination = types.vector_of (element, 4);
	}
	if (variant == 11) {
		element = types.u16_type;
		destination = types.vector_of (element, 8);
	}
	if (variant == 12) {
		source = types.vector_of (types.i8_type, 2);
		declared = source;
		other = source;
		destination = types.vector_of (types.u16_type, 2);
	}
	var parameters = new GenericArray<CfgParameter> ();
	parameters.add (new CfgParameter (span, span, "a", source, 0));
	parameters.add (new CfgParameter (span, span, "b", other, 1));
	CfgValue first = new CfgParameterValue (span, parameters[0]);
	CfgValue? second = kind.is_widen () ? null : new CfgParameterValue (span, parameters[1]);
	if (variant == 13) {
		second = second == null ? first : null;
	}
	var node = new CfgDspInstruction (span, kind, declared, destination, first, second, element);
	var block = new CfgBlock.reserve (span, 0);
	block.instructions.add (node);
	block.complete (span, new CfgReturn (span, node.result));
	if (variant == 14) {
		block.instructions.remove_index (0);
	}
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (block);
	var functions = new GenericArray<CfgFunction> ();
	functions.add (new CfgFunction (span, span, "f", destination, 0, parameters, new GenericArray<CfgLocalPlace> (), blocks, block));
	return new CfgProgram (span, functions);
}

private void values() {
	try {
		for (int k = 0; k < 8; k++) {
			var kind = (DspPrimitiveKind) k;
			CfgProgram? program = sample (kind);
			var weak_function = WeakRef (program.functions[0]);
			CfgVerifier.verify (program);
			assert (CfgDump.format (program).contains (kind.spelling ()));
			assert (program.functions[0].entry.instructions.length == 1 && program.functions[0].blocks.length == 1);
			assert (program.functions[0].temporaries.length == 0);
			program = null;
			assert (weak_function.get () == null);
			if (kind.is_saturation ()) {
				foreach (string category in new string[] {"i8", "u8", "i16", "u16", "int", "u32"}) {
					CfgVerifier.verify (sample (kind, 0, true, category));
				}
			}
			if (k >= 6) {
				foreach (string category in new string[] {"bool", "f32"}) {
					CfgVerifier.verify (sample (kind, 0, false, category));
				}
			}
			for (int variant = 1; variant <= 14; variant++) {
				if (variant == 2 && kind.is_widen ()) {
					continue;
				}
				if ((variant == 8 || variant == 9) && k >= 6) {
					continue;
				}
				bool rejected = false;
				try {
					CfgVerifier.verify (sample (kind, variant));
				} catch (CfgError error) {
					rejected = true;
				}
				if (!rejected) {
					GLib.error ("Accepted malformed Cfg DSP %d variant %d", k, variant);
				}
			}
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/dsp/cfg/standalone-primitives-and-malformed-verifier", values);
	return Test.run ();
}
}
