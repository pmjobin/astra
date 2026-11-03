// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.F32Cfg {
private CfgProgram sample(BuiltinTypes types, uint32 bits, SemanticType? wrong = null) throws CfgError {
	var type = types.f32_type;
	var span = SourceSpan (new SourceFile.from_text ("synthetic", "not a decimal"), 0, 13);
	var parameter = new CfgParameter (span, span, "p", type, 0);
	var local = new CfgLocalPlace (span, span, "x", type, 0);
	var parameters = new GenericArray<CfgParameter> ();
	parameters.add (parameter);
	var locals = new GenericArray<CfgLocalPlace> ();
	locals.add (local);
	var instructions = new GenericArray<CfgInstruction> ();
	var constant = new CfgFloatValue (span, wrong ?? type, new AstraF32Value.from_bits (bits));
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
		foreach (uint32 bits in new uint32[] {0, 0x80000000U, 1, 0x00800000U, 0x7f7fffffU, 0x7f800000U, 0xffc00001U}) {
			var program = sample (types, bits);
			CfgVerifier.verify (program);
			assert (CfgFlowChecker.check (program).diagnostic == null);
			string dump = CfgDump.format (program);
			assert (dump.contains ("(f32 0x%08x : f32)".printf (bits)) && dump.contains ("binary !="));
		}
		foreach (var wrong in new SemanticType[] {types.i32_type, new BuiltinTypes ().f32_type, new SemanticType (TypeKind.F32)}) {
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

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/f32/cfg/standalone-constants-places-exactness", constants_places);
	return Test.run ();
}

}
