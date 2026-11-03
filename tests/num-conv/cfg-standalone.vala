// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.NumericCfg {
private CfgProgram sample(SemanticType source, SemanticType destination, int variant) throws CfgError {
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
	var parameters = new GenericArray<CfgParameter> ();
	parameters.add (new CfgParameter (span, span, "x", source, 0));
	var blocks = new GenericArray<CfgBlock> ();
	var block = new CfgBlock.reserve (span, 0);
	blocks.add (block);
	CfgValue operand = new CfgParameterValue (span, parameters[0]);
	CfgNumericGuard? guard = null;
	if (NumericConversionKind.select (source, destination).traps () && variant != 4) {
		SemanticType checked_destination = variant == 5 ? malformed_types.u16_type : destination;
		guard = new CfgNumericGuard (span, checked_destination, operand, variant == 6 ? NumericConversionPolicy.NEAREST_TIES_EVEN : NumericConversionPolicy.TRUNCATE_TRAP);
		if (variant != 7) {
			block.instructions.add (guard);
		}
		if (variant != 8) {
			operand = guard.result;
		}
	}
	SemanticType declared = variant == 3 ? malformed_types.bool_type : source;
	var value = new CfgNumericConversionInstruction (span, declared, destination, kind, operand, policy);
	block.instructions.add (value);
	if (variant == 7) {
		block.instructions.add (guard);
	}
	block.complete (span, new CfgReturn (span, value.result));
	var functions = new GenericArray<CfgFunction> ();
	functions.add (new CfgFunction (span, span, "f", destination, 0, parameters, new GenericArray<CfgLocalPlace> (), blocks, block));
	return new CfgProgram (span, functions);
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
					CfgVerifier.verify (program);
					string dump = CfgDump.format (program);
					assert (dump.contains ("numeric-convert") && dump.contains ("policy"));
					assert (dump.contains ("numeric-guard") != to_float);
					foreach (int malformed in new int[] {10, 11}) {
						try {
							CfgVerifier.verify (sample (source, destination, malformed));
						} catch (CfgError error) {
							continue;
						}
						GLib.error ("accepted mismatched signedness/format kind %d", malformed);
					}
					for (int variant = 1; variant <= (to_float ? 3 : 8); variant++) {
						try {
							CfgVerifier.verify (sample (source, destination, variant));
						} catch (CfgError error) {
							continue;
						}
						GLib.error ("accepted malformed conversion variant %d", variant);
					}
				}
			}
		}
		foreach (var unsupported in new SemanticType[] {types.bool_type, types.raw_pointer_type, types.vector_of (types.f32_type, 4), types.vector_of (types.bool_type, 4), types.i32_type}) {
			try {
				CfgVerifier.verify (sample (unsupported, types.i32_type, 0));
			} catch (CfgError error) {
				continue;
			}
			GLib.error ("accepted unsupported scalar pairing");
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void block_order() {
	try {
		var types = new BuiltinTypes ();
		var span = SourceSpan (new SourceFile.from_text ("independent", "no syntax or symbols"), 0, 20);
		var parameters = new GenericArray<CfgParameter> ();
		parameters.add (new CfgParameter (span, span, "x", types.f64_type, 0));
		var entry = new CfgBlock.reserve (span, 0);
		var conversion_block = new CfgBlock.reserve (span, 1);
		var guard_block = new CfgBlock.reserve (span, 2);
		var guard = new CfgNumericGuard (span, types.i32_type, new CfgParameterValue (span, parameters[0]), NumericConversionPolicy.TRUNCATE_TRAP);
		guard_block.instructions.add (guard);
		var conversion = new CfgNumericConversionInstruction (span, types.f64_type, types.i32_type, NumericConversionKind.F64_TO_SIGNED_INT, guard.result, NumericConversionPolicy.TRUNCATE_TRAP);
		conversion_block.instructions.add (conversion);
		entry.complete (span, new CfgBranch (span, guard_block));
		guard_block.complete (span, new CfgBranch (span, conversion_block));
		conversion_block.complete (span, new CfgReturn (span, conversion.result));
		var blocks = new GenericArray<CfgBlock> ();
		blocks.add (entry);
		blocks.add (conversion_block);
		blocks.add (guard_block);
		var functions = new GenericArray<CfgFunction> ();
		functions.add (new CfgFunction (span, span, "f", types.i32_type, 0, parameters, new GenericArray<CfgLocalPlace> (), blocks, entry));
		CfgVerifier.verify (new CfgProgram (span, functions));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/num-conv/Cfg/independent-exact-pairs-malformed-policy-proof", matrix);
	Test.add_func ("/num-conv/Cfg/guard-dominance-independent-of-block-layout", block_order);
	return Test.run ();
}

}
