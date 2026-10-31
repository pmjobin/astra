// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.NumericSsa {
private SsaProgram sample(SemanticType source, SemanticType destination, int variant) throws SsaError {
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
	var parameters = new GenericArray<SsaFunctionParameter> ();
	parameters.add (new SsaFunctionParameter (span, span, "x", source, 0));
	var blocks = new GenericArray<SsaBlock> ();
	var block = new SsaBlock (span, 0, 0);
	blocks.add (block);
	SsaValue operand = parameters[0];
	SsaNumericGuard? guard = null;
	if (NumericConversionKind.select (source, destination).traps () && variant != 4) {
		SemanticType checked_destination = variant == 5 ? malformed_types.u16_type : destination;
		guard = new SsaNumericGuard (span, checked_destination, operand, 1, variant == 6 ? NumericConversionPolicy.NEAREST_TIES_EVEN : NumericConversionPolicy.TRUNCATE_TRAP);
		if (variant != 7) {
			block.instructions.add (guard);
		}
		if (variant != 8) {
			operand = guard.result;
		}
	}
	SemanticType declared = variant == 3 ? malformed_types.bool_type : source;
	var value = new SsaNumericConversionInstruction (span, declared, destination, kind, 2, operand, policy);
	block.instructions.add (value);
	if (variant == 7) {
		block.instructions.add (guard);
	}
	if (variant == 9) {
		// The checked definition exists but lies on only one incoming path.
		var left = new SsaBlock (span, 1, 1);
		var right = new SsaBlock (span, 2, 2);
		var merge = new SsaBlock (span, 3, 3);
		blocks.add (left);
		blocks.add (right);
		blocks.add (merge);
		block.instructions.remove_index (1);
		block.instructions.remove_index (0);
		left.instructions.add (guard);
		merge.instructions.add (value);
		var types = new BuiltinTypes ();
		block.complete (new SsaConditionalBranch (span, new SsaBooleanConstant (span, types.bool_type, BooleanLiteral.TRUE), new SsaEdge (left, new GenericArray<SsaValue> ()), new SsaEdge (right, new GenericArray<SsaValue> ())));
		left.complete (new SsaBranch (span, new SsaEdge (merge, new GenericArray<SsaValue> ())));
		right.complete (new SsaBranch (span, new SsaEdge (merge, new GenericArray<SsaValue> ())));
		merge.complete (new SsaReturn (span, value.result));
	} else {
		block.complete (new SsaReturn (span, value.result));
	}
	var functions = new GenericArray<SsaFunction> ();
	functions.add (new SsaFunction (span, span, "f", destination, 0, parameters, blocks, block));
	return new SsaProgram (span, functions);
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
					SsaVerifier.verify (program);
					string dump = SsaDump.format (program);
					assert (dump.contains ("numeric-convert") && dump.contains ("policy"));
					assert (dump.contains ("numeric-guard") != to_float);
					foreach (int malformed in new int[] {10, 11}) {
						try {
							SsaVerifier.verify (sample (source, destination, malformed));
						} catch (SsaError error) {
							continue;
						}
						GLib.error ("accepted mismatched signedness/format kind %d", malformed);
					}
					for (int variant = 1; variant <= (to_float ? 3 : 9); variant++) {
						try {
							SsaVerifier.verify (sample (source, destination, variant));
						} catch (SsaError error) {
							continue;
						}
						GLib.error ("accepted malformed conversion variant %d", variant);
					}
				}
			}
		}
		foreach (var unsupported in new SemanticType[] {types.bool_type, types.raw_pointer_type, types.vector_of (types.f32_type, 4), types.vector_of (types.bool_type, 4), types.i32_type}) {
			try {
				SsaVerifier.verify (sample (unsupported, types.i32_type, 0));
			} catch (SsaError error) {
				continue;
			}
			GLib.error ("accepted unsupported scalar pairing");
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/num-conv/Ssa/independent-exact-pairs-malformed-policy-proof", matrix);
	return Test.run ();
}
}
