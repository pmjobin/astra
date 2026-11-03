// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Foreign;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.TextIoSsa {
private SsaProgram sample(int variant) throws SsaError {
	var span = SourceSpan (new SourceFile.from_text ("independent-c-text", "x"), 0, 1);
	var types = new BuiltinTypes ();
	var parameters = new GenericArray<SsaFunctionParameter> ();
	var parameter_types = new GenericArray<SemanticType> ();
	SemanticType type = variant == 5 ? (SemanticType) types.int_type : types.string_type;
	var contract = variant == 3 || variant == 5 ? PointerParameterContract.UNMANAGED : variant == 6 ? PointerParameterContract.OWNED_TRANSFER : PointerParameterContract.BORROWED_NOESCAPE;
	parameters.add (new SsaFunctionParameter (span, span, "text", type, 0, contract));
	parameter_types.add (variant == 7 ? (SemanticType) types.int_type : type);
	var metadata = new CForeignMetadata ("unfamiliar_reader", null, null, null, variant == 1 ? CTextAbi.NONE : variant == 2 ? CTextAbi.INVALID : CTextAbi.UTF8_I32);
	SsaCFunction? imported = new SsaCFunction (span, span, "reader", metadata, ForeignAbi.C, variant == 4 ? (SemanticType) types.string_type : types.int_type, parameter_types, 0, null, parameters);
	var imports = new GenericArray<SsaCFunction> ();
	if (variant != 8) {
		imports.add (imported);
	}
	var functions = new GenericArray<SsaFunction> ();
	var arguments = new GenericArray<SsaValue> ();
	if (variant != 9) {
		arguments.add (variant == 10 ? (SsaValue) new SsaIntegerConstant (span, types.int_type, AstraIntValue.from_int64 (0)) : new SsaTextConstant (span, type, new Astra.Text.TextBytes ({65})));
	}
	var call = new SsaCCallInstruction (span, types.int_type, 0, imported, arguments);
	imported = null;
	var block = new SsaBlock (span, 0, 0);
	block.instructions.add (call);
	block.complete (new SsaReturn (span, call.result));
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (block);
	functions.add (new SsaFunction (span, span, "entry", types.int_type, 0, new GenericArray<SsaFunctionParameter> (), blocks, block));
	var program = new SsaProgram (span, functions, imports);
	foreach (var argument in arguments) {
		if (argument is SsaTextConstant) {
			program.text_literals.add (((SsaTextConstant) argument).payload);
		}
	}
	return program;
}

private void independent() {
	for (int variant = 0; variant <= 10; variant++) {
		try {
			var program = sample (variant);
			SsaVerifier.verify (program);
			assert (variant == 0);
		} catch (SsaError error) {
			if (variant == 0) {
				GLib.error ("%s", error.message);
			}
		}
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/text-io/ssa/independent-contracts", independent);
	return Test.run ();
}

}
