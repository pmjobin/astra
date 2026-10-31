// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.IntegersCfg {
private CfgProgram sample(IntegerType type, IntegerType? wrong = null) throws CfgError {
	var span = SourceSpan (new SourceFile.from_text ("synthetic", "not a decimal"), 0, 13);
	var parameter = new CfgParameter (span, span, "p", type, 0);
	var local = new CfgLocalPlace (span, span, "x", type, 0);
	var parameters = new GenericArray<CfgParameter> ();
	parameters.add (parameter);
	var locals = new GenericArray<CfgLocalPlace> ();
	locals.add (local);
	var instructions = new GenericArray<CfgInstruction> ();
	var constant = new CfgIntegerValue.typed (span, type, AstraIntegerValue.from_bits (wrong ?? type, 255));
	instructions.add (new CfgInitialize (span, local, constant));
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
		foreach (var type in new IntegerType[] {types.i8_type, types.u8_type, types.i16_type, types.u16_type, types.i32_type, types.u32_type}) {
			var program = sample (type);
			CfgVerifier.verify (program);
			assert (CfgFlowChecker.check (program).diagnostic == null);
			assert (CfgDump.format (program).contains (" : " + type.display_name ()));
		}
		try {
			CfgVerifier.verify (sample (types.i8_type, types.u8_type));
		} catch (CfgError error) {
			assert (error.message.contains ("integer value must retain its exact semantic type identity"));
			return;
		}
		GLib.error ("Mismatched integer bits/type accepted");
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/ints/cfg/standalone-constants-places-exactness", constants_places);
	return Test.run ();
}
}
