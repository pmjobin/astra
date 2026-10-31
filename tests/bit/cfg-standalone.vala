// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.BitCfg {
private CfgProgram sample(int op, int variant = 0, bool mask = false, bool scalar = false) throws CfgError {
	var t = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("synthetic", "bits"), 0, 4);
	SemanticType element = mask ? t.bool_type : (SemanticType) t.i16_type;
	SemanticType source = scalar ? element : (SemanticType) t.vector_of (element, 8);
	if (variant == 1 && op == 3) {
		source = t.bool_type;
	}
	if (variant == 3) {
		source = t.f32_type;
	}
	if (variant == 4) {
		source = t.raw_pointer_type;
	}
	if (variant == 6) {
		source = new VectorType (t.i32_type, 16);
	}
	if (variant == 8 && op == 3) {
		source = t.vector_of (t.bool_type, 8);
	}
	SemanticType other = op >= 4 ? (SemanticType) t.u32_type : source;
	if (variant == 1 && op != 3) {
		other = t.bool_type;
	}
	if (variant == 8 && op != 3) {
		other = t.vector_of (t.i16_type, 4);
	}
	SemanticType result = source;
	if (variant == 2) {
		result = t.u8_type;
	}
	if (variant == 7) {
		result = t.vector_of (t.u16_type, 8);
	}
	var parameters = new GenericArray<CfgParameter> ();
	parameters.add (new CfgParameter (span, span, "a", source, 0));
	parameters.add (new CfgParameter (span, span, "b", other, 1));
	CfgValue a = new CfgParameterValue (span, parameters[0]);
	CfgValue b = new CfgParameterValue (span, parameters[1]);
	CfgValue node;
	if (op < 3) {
		node = new CfgBinaryValue (span, result, variant == 5 ? (BinaryOperator) 99 : op == 0 ? BinaryOperator.BIT_AND : op == 1 ? BinaryOperator.BIT_OR : BinaryOperator.BIT_XOR, a, b);
	} else if (op == 3) {
		node = new CfgPrefixValue (span, result, variant == 5 ? (PrefixOperator) 99 : PrefixOperator.BIT_NOT, a);
	} else {
		node = new CfgIntegerShiftValue (span, result, variant == 5 ? (IntegerShiftKind) 99 : op == 4 ? IntegerShiftKind.LEFT : IntegerShiftKind.RIGHT, a, b);
	}
	var instruction = new CfgEvaluateInstruction (span, node, new CfgEvaluatedValue (span, result));
	var block = new CfgBlock.reserve (span, 0);
	block.instructions.add (instruction);
	block.complete (span, new CfgReturn (span, instruction.result));
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (block);
	var functions = new GenericArray<CfgFunction> ();
	functions.add (new CfgFunction (span, span, "f", result, 0, parameters, new GenericArray<CfgLocalPlace> (), blocks, block));
	return new CfgProgram (span, functions);
}

private void matrix() {
	try {
		for (int op = 0; op < 6; op++) {
			foreach (bool scalar in new bool[] {false, true}) {
				CfgProgram? p = sample (op, 0, false, scalar);
				var witness = WeakRef (p.functions[0]);
				CfgVerifier.verify (p);
				string dump = CfgDump.format (p);
				assert (!dump.contains ("vector-extract") && !dump.contains ("lane-place"));
				if (op >= 4) {
					assert (dump.contains ("invalid-count trap") && dump.contains ("valid-range 0 15"));
				}
				assert (p.functions[0].entry.instructions.length == 1 && p.functions[0].blocks.length == 1);
				p = null;
				assert (witness.get () == null);
				if (op < 3) {
					CfgVerifier.verify (sample (op, 0, true, scalar));
				}
			}
			for (int variant = 1; variant <= 8; variant++) {
				bool rejected = false;
				try {
					CfgVerifier.verify (sample (op, variant));
				} catch (CfgError error) {
					rejected = true;
				}
				if (!rejected) {
					GLib.error ("Accepted malformed Cfg op %d variant %d", op, variant);
				}
			}
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/bit/cfg/scalar-vector-mask-and-malformed", matrix);
	return Test.run ();
}
}
