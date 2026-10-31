// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.F64Cfg {
private CfgProgram sample(BuiltinTypes types, uint64 bits, SemanticType? wrong = null, bool wrong_format = false) throws CfgError {
	var type = types.f64_type;
	var span = SourceSpan (new SourceFile.from_text ("synthetic", "not a decimal"), 0, 13);
	var parameter = new CfgParameter (span, span, "p", type, 0);
	var local = new CfgLocalPlace (span, span, "x", type, 0);
	var parameters = new GenericArray<CfgParameter> ();
	parameters.add (parameter);
	var locals = new GenericArray<CfgLocalPlace> ();
	locals.add (local);
	var instructions = new GenericArray<CfgInstruction> ();
	var constant = new CfgFloatValue (span, wrong ?? type, new BinaryFloatValue.from_bits (wrong_format ? BinaryFloatFormat.BINARY32 : BinaryFloatFormat.BINARY64, bits));
	instructions.add (new CfgInitialize (span, local, constant));
	var comparison = new CfgLocalPlace (span, span, "same", types.bool_type, 1);
	locals.add (comparison);
	instructions.add (new CfgInitialize (span, comparison, new CfgBinaryValue (span, types.bool_type, BinaryOperator.NOT_EQUAL, new CfgLoadValue (span, local), constant)));
	instructions.add (new CfgStore (span, local, new CfgBinaryValue (span, type, BinaryOperator.ADD, new CfgLoadValue (span, local), new CfgParameterValue (span, parameter))));
	var blocks = new GenericArray<CfgBlock> ();
	var block = new CfgBlock.reserve (span, 0);
	foreach (var instruction in instructions) {
		block.instructions.add (instruction);
	}
	block.complete (span, new CfgReturn (span, new CfgLoadValue (span, local)));
	blocks.add (block);
	var functions = new GenericArray<CfgFunction> ();
	functions.add (new CfgFunction (span, span, "f", type, 0, parameters, locals, blocks, blocks[0]));
	return new CfgProgram (span, functions);
}

private void constants_places() {
	try {
		var types = new BuiltinTypes ();
		foreach (uint64 bits in new uint64[] {0, 0x8000000000000000UL, 1, 0x0010000000000000UL, 0x7fefffffffffffffUL, 0x7ff0000000000000UL, 0xfff8000000000001UL}) {
			var program = sample (types, bits);
			CfgVerifier.verify (program);
			assert (CfgFlowChecker.check (program).diagnostic == null);
			string dump = CfgDump.format (program);
			assert (dump.contains ("(f64 %s : f64)".printf (new BinaryFloatValue.from_bits (BinaryFloatFormat.BINARY64, bits).to_string ())) && dump.contains ("binary !="));
		}
		bool bad_format = false;
		try {
			CfgVerifier.verify (sample (types, 1, null, true));
		} catch (CfgError error) {
			bad_format = error.message.contains ("matching binary format");
		}
		assert (bad_format);
		foreach (var wrong in new SemanticType[] {types.i32_type, new BuiltinTypes ().f64_type, new SemanticType (TypeKind.F64)}) {
			bool rejected = false;
			try {
				CfgVerifier.verify (sample (types, 1, wrong));
			} catch (CfgError error) {
				rejected = true;
			}
			assert (rejected);
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private CfgProgram conversion(int variant) throws CfgError {
	var types = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("conversion", "no source parsing"), 0, 17);
	SemanticType source = variant == 2 ? (SemanticType) types.int_type : types.f32_type;
	SemanticType destination = variant == 3 ? (SemanticType) types.f32_type : types.f64_type;
	var kind = variant == 1 ? FloatConversionKind.FLOAT_NARROW : FloatConversionKind.FLOAT_WIDEN;
	var parameters = new GenericArray<CfgParameter> ();
	parameters.add (new CfgParameter (span, span, "x", source, 0));
	var value = new CfgFloatConversionInstruction (span, source, destination, kind, new CfgParameterValue (span, parameters[0]));
	var blocks = new GenericArray<CfgBlock> ();
	var block = new CfgBlock.reserve (span, 0);
	block.instructions.add (value);
	block.complete (span, new CfgReturn (span, value.result));
	blocks.add (block);
	var functions = new GenericArray<CfgFunction> ();
	functions.add (new CfgFunction (span, span, "convert", destination, 0, parameters, new GenericArray<CfgLocalPlace> (), blocks, block));
	return new CfgProgram (span, functions);
}

private void conversions() {
	try {
		var program = conversion (0);
		CfgVerifier.verify (program);
		assert (CfgDump.format (program).contains ("float-convert (from f32) (to f64) (mode widen-exact)"));
		for (int variant = 1; variant <= 3; variant++) {
			bool rejected = false;
			try {
				CfgVerifier.verify (conversion (variant));
			} catch (CfgError error) {
				rejected = true;
			}
			assert (rejected);
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/f64/cfg/standalone-constants-places-exactness", constants_places);
	Test.add_func ("/f64/cfg/explicit-conversion-verifier", conversions);
	return Test.run ();
}
}
