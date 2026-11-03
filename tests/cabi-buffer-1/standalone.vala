// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Foreign;
using Astra.Semantic;
using Astra.CAbi;

namespace Astra.Tests.CAbiBuffer {
private CAbiProgram sample(int variant) throws CAbiError {
	var span = SourceSpan (new SourceFile.from_text ("independent-c-buffer", "x"), 0, 1);
	var parameters = new GenericArray<CAbiParameter> ();
	parameters.add (new CAbiParameter (span, span, "tag", 0, CAbiScalarType.I32));
	var channels = new GenericArray<CAbiBufferComponent> ();
	channels.add (new CAbiBufferComponent (variant == 1 ? CAbiBufferComponentRole.BYTE_LENGTH : CAbiBufferComponentRole.DATA, CAbiScalarType.PTR, 1, 1));
	channels.add (new CAbiBufferComponent (CAbiBufferComponentRole.BYTE_LENGTH, variant == 2 ? CAbiScalarType.I64 : CAbiScalarType.I32, variant == 3 ? 3 : 2, variant == 4 ? 0 : 1));
	if (variant == 5) {
		channels.remove_index (1);
	}
	var buffer = new CAbiBufferParameterPlan (variant == 6 ? CBufferAbi.NONE : CBufferAbi.U8_I32, variant == 7 ? (CAbiBufferRole) 91 : CAbiBufferRole.IMPORT_PARAMETER, variant == 8 ? PointerParameterContract.UNMANAGED : PointerParameterContract.BORROWED_NOESCAPE, channels, variant == 9 ? (CAbiBufferAccess) 91 : CAbiBufferAccess.READ_WRITE, variant == 10 ? 2 : 1, variant == 11 ? 2 : 1);
	parameters.add (new CAbiParameter.buffer_view (span, span, "bytes", 1, 1, buffer, variant == 12 ? PointerParameterContract.OWNED_TRANSFER : PointerParameterContract.BORROWED_NOESCAPE));
	parameters.add (new CAbiParameter (span, span, "tail", 2, CAbiScalarType.I32, PointerParameterContract.UNMANAGED, variant == 13 ? 2 : 3));
	var signature = new CAbiSignature (variant == 14 ? CAbiProfile.TEXT_VIEW_V3 : CAbiProfile.BUFFER_VIEW_V4, parameters, new CAbiResult (variant == 18 ? CAbiScalarType.PTR : CAbiScalarType.I32));
	var metadata = new CForeignMetadata ("buffer_reader", null, null, null, CTextAbi.NONE, null, variant == 15 ? CBufferAbi.INVALID : variant == 16 ? CBufferAbi.NONE : CBufferAbi.U8_I32);
	var functions = new GenericArray<CAbiFunction> ();
	var exports = new GenericArray<CAbiExport> ();
	if (variant == 17) {
		exports.add (new CAbiExport (span, span, "buffer_reader", 0, signature, 0));
	} else {
		functions.add (new CAbiFunction (span, span, "reader", 0, signature, metadata));
	}
	return new CAbiProgram (span, CAbiProfile.BUFFER_VIEW_V4, functions, exports);
}

private void independent() {
	for (int variant = 0; variant <= 18; variant++) {
		bool rejected = false;
		try {
			var program = sample (variant);
			CAbiVerifier.verify (program);
			assert (program.functions[0].signature.physical_parameter_count == 4);
			assert (CAbiDump.format (program).contains ("(buffer-view u8-i32 alignment=1 read-write)"));
		} catch (CAbiError error) {
			rejected = true;
		}
		if (rejected != (variant != 0)) {
			GLib.error ("buffer variant %d rejection=%s", variant, rejected.to_string ());
		}
	}
}

private void wide() {
	var span = SourceSpan (new SourceFile.from_text ("independent-wide", "x"), 0, 1);
	foreach (var scalar in new CAbiScalarType[] { CAbiScalarType.I64, CAbiScalarType.U64 }) {
		foreach (var profile in new CAbiProfile[] { CAbiProfile.SCALAR_V0, CAbiProfile.BUFFER_VIEW_V4, CAbiProfile.WIDE_INT_V5 }) {
			var parameters = new GenericArray<CAbiParameter> ();
			parameters.add (new CAbiParameter (span, span, "wide", 0, scalar));
			var functions = new GenericArray<CAbiFunction> ();
			functions.add (new CAbiFunction (span, span, "wide", 0, new CAbiSignature (profile, parameters, new CAbiResult (scalar)), new CForeignMetadata ("wide")));
			bool rejected = false;
			try {
				CAbiVerifier.verify (new CAbiProgram (span, profile, functions));
			} catch (CAbiError error) {
				rejected = true;
			}
			assert (rejected == (profile != CAbiProfile.WIDE_INT_V5));
		}
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/cabi-buffer/independent-bounded-groups", independent);
	Test.add_func ("/cabi-buffer/exact-wide-scalar-profiles", wide);
	return Test.run ();
}

}
