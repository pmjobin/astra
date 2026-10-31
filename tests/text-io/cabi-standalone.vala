// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Foreign;
using Astra.Semantic;
using Astra.CAbi;

namespace Astra.Tests.TextIoCAbi {
private CAbiProgram sample(int variant) throws CAbiError {
	var span = SourceSpan (new SourceFile.from_text ("independent-c-text", "x"), 0, 1);
	var parameters = new GenericArray<CAbiParameter> ();
	parameters.add (new CAbiParameter (span, span, "tag", 0, CAbiScalarType.I32));
	var channels = new GenericArray<CAbiTextComponent> ();
	channels.add (new CAbiTextComponent (variant == 1 ? CAbiTextComponentRole.BYTE_LENGTH : CAbiTextComponentRole.DATA, CAbiScalarType.PTR, 1, 1));
	channels.add (new CAbiTextComponent (CAbiTextComponentRole.BYTE_LENGTH, variant == 2 ? CAbiScalarType.F64 : CAbiScalarType.I32, variant == 3 ? 3 : 2, variant == 4 ? 0 : 1));
	if (variant == 5) {
		channels.remove_index (1);
	}
	var text = new CAbiTextParameterPlan (variant == 6 ? CTextAbi.NONE : CTextAbi.UTF8_I32, variant == 7 ? (CAbiTextRole) 91 : CAbiTextRole.IMPORT_PARAMETER, variant == 8 ? PointerParameterContract.UNMANAGED : PointerParameterContract.BORROWED_NOESCAPE, channels);
	parameters.add (new CAbiParameter.text_view (span, span, "text", 1, 1, text, variant == 9 ? PointerParameterContract.OWNED_TRANSFER : PointerParameterContract.BORROWED_NOESCAPE));
	parameters.add (new CAbiParameter (span, span, "scale", 2, CAbiScalarType.F32, PointerParameterContract.UNMANAGED, variant == 10 ? 2 : 3));
	var result = new CAbiResult (variant == 11 ? (CAbiScalarType) 91 : CAbiScalarType.F64);
	var signature = new CAbiSignature (variant == 12 ? CAbiProfile.SCALAR_FP_V2 : CAbiProfile.TEXT_VIEW_V3, parameters, result);
	var functions = new GenericArray<CAbiFunction> ();
	var exports = new GenericArray<CAbiExport> ();
	var metadata = new CForeignMetadata ("unfamiliar_reader", null, null, null, variant == 13 ? CTextAbi.INVALID : variant == 14 ? CTextAbi.NONE : CTextAbi.UTF8_I32);
	if (variant == 15) {
		exports.add (new CAbiExport (span, span, "unfamiliar_reader", 0, signature, 0));
	} else {
		functions.add (new CAbiFunction (span, span, "reader", 0, signature, metadata));
	}
	if (variant == 16) {
		functions.add (new CAbiFunction (span, span, "different", 1, new CAbiSignature (CAbiProfile.SCALAR_FP_V2, new GenericArray<CAbiParameter> (), result), metadata));
	}
	return new CAbiProgram (span, CAbiProfile.TEXT_VIEW_V3, functions, exports);
}
private void independent() {
	for (int variant = 0; variant <= 16; variant++) {
		try {
			var program = sample (variant);
			CAbiVerifier.verify (program);
			assert (variant == 0);
			assert (program.functions[0].signature.physical_parameter_count == 4);
			assert (CAbiDump.format (program).contains ("(component #2 byte-length I32)"));
		} catch (CAbiError error) {
			if (variant == 0) {
				GLib.error ("%s", error.message);
			}
		}
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/text-io/cabi/independent-groups", independent);
	return Test.run ();
}
}
