// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Foreign;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.TextIoCfg {
private CfgProgram sample(int variant) throws CfgError {
	var span = SourceSpan (new SourceFile.from_text ("independent-c-text", "x"), 0, 1);
	var types = new BuiltinTypes ();
	var parameters = new GenericArray<CfgParameter> ();
	var parameter_types = new GenericArray<SemanticType> ();
	SemanticType type = variant == 5 ? (SemanticType) types.int_type : types.string_type;
	var contract = variant == 3 || variant == 5 ? PointerParameterContract.UNMANAGED : variant == 6 ? PointerParameterContract.OWNED_TRANSFER : PointerParameterContract.BORROWED_NOESCAPE;
	parameters.add (new CfgParameter (span, span, "text", type, 0, contract));
	parameter_types.add (variant == 7 ? (SemanticType) types.int_type : type);
	var metadata = new CForeignMetadata ("unfamiliar_reader", null, null, null, variant == 1 ? CTextAbi.NONE : variant == 2 ? CTextAbi.INVALID : CTextAbi.UTF8_I32);
	CfgCFunction? imported = new CfgCFunction (span, span, "reader", metadata, ForeignAbi.C, variant == 4 ? (SemanticType) types.string_type : types.int_type, parameter_types, 0, null, parameters);
	var imports = new GenericArray<CfgCFunction> ();
	if (variant != 8) {
		imports.add (imported);
	}
	var functions = new GenericArray<CfgFunction> ();
	var arguments = new GenericArray<CfgValue> ();
	if (variant != 9) {
		arguments.add (variant == 10 ? (CfgValue) new CfgIntegerValue (span, types.int_type, AstraIntValue.from_int64 (0)) : new CfgTextValue (span, type, new Astra.Text.TextBytes ({65})));
	}
	var call = new CfgCCallInstruction (span, imported, arguments, new CfgCallResultValue (span, types.int_type));
	imported = null;
	var block = new CfgBlock.reserve (span, 0);
	block.instructions.add (call);
	block.complete (span, new CfgReturn (span, call.result));
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (block);
	functions.add (new CfgFunction (span, span, "entry", types.int_type, 0, new GenericArray<CfgParameter> (), new GenericArray<CfgLocalPlace> (), blocks, block));
	var program = new CfgProgram (span, functions, imports);
	foreach (var argument in arguments) {
		if (argument is CfgTextValue) {
			program.text_literals.add (((CfgTextValue) argument).payload);
		}
	}
	return program;
}
private void independent() {
	for (int variant = 0; variant <= 10; variant++) {
		try {
			var program = sample (variant);
			CfgVerifier.verify (program);
			assert (variant == 0);
		} catch (CfgError error) {
			if (variant == 0) {
				GLib.error ("%s", error.message);
			}
		}
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/text-io/cfg/independent-contracts", independent);
	return Test.run ();
}
}
