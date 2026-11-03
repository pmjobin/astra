// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Foreign;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.TextIoCore {
private CoreProgram sample(int variant) throws CoreError {
	var span = SourceSpan (new SourceFile.from_text ("independent-c-text", "x"), 0, 1);
	var types = new BuiltinTypes ();
	var parameters = new GenericArray<CoreParameter> ();
	var parameter_types = new GenericArray<SemanticType> ();
	SemanticType type = variant == 5 ? (SemanticType) types.int_type : types.string_type;
	var contract = variant == 3 || variant == 5 ? PointerParameterContract.UNMANAGED : variant == 6 ? PointerParameterContract.OWNED_TRANSFER : PointerParameterContract.BORROWED_NOESCAPE;
	parameters.add (new CoreParameter (span, span, "text", type, 0, contract));
	parameter_types.add (variant == 7 ? (SemanticType) types.int_type : type);
	var metadata = new CForeignMetadata ("unfamiliar_reader", null, null, null, variant == 1 ? CTextAbi.NONE : variant == 2 ? CTextAbi.INVALID : CTextAbi.UTF8_I32);
	CoreCFunction? imported = new CoreCFunction (span, span, "reader", metadata, ForeignAbi.C, variant == 4 ? (SemanticType) types.string_type : types.int_type, parameter_types, 0, null, parameters);
	var imports = new GenericArray<CoreCFunction> ();
	if (variant != 8) {
		imports.add (imported);
	}
	var functions = new GenericArray<CoreFunction> ();
	var arguments = new GenericArray<CoreValue> ();
	if (variant != 9) {
		arguments.add (variant == 10 ? (CoreValue) new CoreIntegerValue (span, types.int_type, AstraIntValue.from_int64 (0)) : new CoreTextValue (span, type, new Astra.Text.TextBytes ({65})));
	}
	var call = new CoreCCallValue (span, types.int_type, imported, arguments);
	imported = null;
	var body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	body.statements.add (new CoreReturn (span, call));
	functions.add (new CoreFunction (span, span, "entry", types.int_type, new GenericArray<CoreParameter> (), new GenericArray<CoreLocalPlace> (), body));
	var program = new CoreProgram (span, functions, imports);
	foreach (var argument in arguments) {
		if (argument is CoreTextValue) {
			program.text_literals.add (((CoreTextValue) argument).payload);
		}
	}
	return program;
}

private void independent() {
	for (int variant = 0; variant <= 10; variant++) {
		try {
			var program = sample (variant);
			CoreVerifier.verify (program);
			assert (variant == 0);
		} catch (CoreError error) {
			if (variant == 0) {
				GLib.error ("%s", error.message);
			}
		}
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/text-io/core/independent-contracts", independent);
	return Test.run ();
}

}
