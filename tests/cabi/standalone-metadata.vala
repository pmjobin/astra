// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Foreign;
using Astra.CAbi;

namespace Astra.Tests.CAbiStandalone {
private void standalone_metadata() {
	try {
		SourceFile? source = new SourceFile.from_text ("metadata.data", "local real header");
		var source_ref = WeakRef (source);
		CForeignHeader[]? headers = {
			new CForeignHeader ("missing/é,other", SourceSpan (source, 11, 17))
		};
		CForeignMetadata? metadata = new CForeignMetadata ("real.$symbol", SourceSpan (source, 6, 10), headers);
		// Replacing the caller's collection cannot mutate normalized metadata.
		headers[0] = new CForeignHeader ("changed");
		headers = null;
		var metadata_ref = WeakRef (metadata);
		var signature = new CAbiSignature (CAbiProfile.SCALAR_V0, new GenericArray<CAbiParameter> (), new CAbiResult (CAbiScalarType.I32));
		GenericArray<CAbiFunction>? functions = new GenericArray<CAbiFunction> ();
		functions.add (new CAbiFunction (SourceSpan (source, 0, source.length), SourceSpan (source, 0, 5), "local", 0, signature, metadata));
		CAbiProgram? program = new CAbiProgram (SourceSpan (source, 0, source.length), CAbiProfile.SCALAR_V0, functions);
		metadata = null;
		source = null;
		functions = null;
		CAbiVerifier.verify (program);
		assert (program.functions[0].name == "local" && program.functions[0].external_symbol == "real.$symbol");
		assert (program.functions[0].metadata.external_symbol_span.text () == "real");
		assert (program.functions[0].metadata.header_count == 1 && program.functions[0].metadata.header_at (0).name == "missing/é,other");
		assert (program.functions[0].metadata.header_at (0).span.text () == "header");
		string dump = CAbiDump.format (program);
		assert (dump.contains ("(name \"local\")\n\t\t(symbol \"real.$symbol\")\n\t\t(headers\n"));
		assert (dump.contains ("(result I32)") && dump == CAbiDump.format (program));
		program = null;
		assert (metadata_ref.get () == null && source_ref.get () == null);
	} catch (CAbiError error) {
		GLib.error ("Standalone metadata: %s", error.message);
	}
}

private void standalone_metadata_collision() {
	try {
		var sample = new Sample ();
		var functions = new GenericArray<CAbiFunction> ();
		var signature = sample.function (0).signature;
		functions.add (new CAbiFunction (sample.span, sample.span, "alpha", 0, signature, new CForeignMetadata ("physical")));
		var later = new SourceFile.from_text ("later.data", "\n\"physical\"");
		functions.add (new CAbiFunction (sample.span, sample.span, "beta", 1, signature, new CForeignMetadata ("physical", SourceSpan (later, 1, later.length))));
		var program = new CAbiProgram (sample.span, sample.profile, functions);
		for (int attempt = 0; attempt < 2; attempt++) {
			try {
				CAbiDump.format (program);
				assert_not_reached ();
			} catch (CAbiError.DUPLICATE_SYMBOL error) {
				assert (error.message == "later.data:2:1: error: C external symbol 'physical' is declared more than once");
			}
		}
	} catch (CAbiError error) {
		GLib.error ("Standalone metadata collision: %s", error.message);
	}
}

private void standalone_empty_header() {
	try {
		var sample = new Sample ();
		var functions = new GenericArray<CAbiFunction> ();
		functions.add (new CAbiFunction (sample.span, sample.span, "choose", 0, sample.function (0).signature, new CForeignMetadata ("choose", null, {new CForeignHeader ("")})));
		reject (new CAbiProgram (sample.span, sample.profile, functions), "function #0", "C header metadata must be nonempty");
	} catch (CAbiError error) {
		GLib.error ("Standalone empty header: %s", error.message);
	}
}

private void register_standalone_metadata() {
	Test.add_func ("/cabi-standalone/metadata/model-immutability-lifetime", standalone_metadata);
	Test.add_func ("/cabi-standalone/metadata/physical-collision-provenance", standalone_metadata_collision);
	Test.add_func ("/cabi-standalone/metadata/empty-header", standalone_empty_header);
}

}
