// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Foreign;
using Astra.CAbi;
using Astra.Semantic;

namespace Astra.Tests.CAbiStandalone {
private CAbiProgram owned_program(int variant = -1) throws CAbiError {
	var file = new SourceFile.from_text ("owned-contract", "create destroy");
	var span = SourceSpan (file, 0, file.length);
	var profile = CAbiProfile.SCALAR_PTR_V1;
	var parameters = new GenericArray<CAbiParameter> ();
	if (variant != 0) {
		parameters.add (new CAbiParameter (span, span, "resource", 0, variant == 1 ? CAbiScalarType.I32 : CAbiScalarType.PTR));
	}
	var signature = new CAbiSignature (profile, parameters, variant == 2 ? new CAbiResult (CAbiScalarType.I32) : null);
	var cleanup = new CAbiCleanupFunction (variant == 3 ? "" : "destroy", span, variant == 4 ? 1 : 0, signature);
	var cleanups = new GenericArray<CAbiCleanupFunction> ();
	cleanups.add (cleanup);
	if (variant == 5) {
		cleanups.add (new CAbiCleanupFunction ("destroy", span, 1, signature));
	}
	var imports = new GenericArray<CAbiFunction> ();
	var producer = new CAbiSignature (profile, new GenericArray<CAbiParameter> (), new CAbiResult (variant == 9 ? CAbiScalarType.I32 : CAbiScalarType.PTR));
	imports.add (new CAbiFunction (span, span, "create", 0, producer, new CForeignMetadata (variant == 6 ? "destroy" : "create"), variant == 8 ? new CAbiCleanupFunction ("destroy", span, 0, signature) : cleanup));
	var exports = new GenericArray<CAbiExport> ();
	if (variant == 7) {
		exports.add (new CAbiExport (span, span, "destroy", 0, signature, 0));
	}
	return new CAbiProgram (span, profile, imports, exports, cleanups);
}

private void owned_model() {
	try {
		CAbiProgram? program = owned_program ();
		CAbiVerifier.verify (program);
		assert (program.functions[0].owned_cleanup == program.cleanups[0]);
		assert (CAbiDump.format (program).contains ("(owned-result (cleanup #0))"));
		CAbiCleanupFunction? cleanup = program.cleanups[0];
		var program_ref = WeakRef (program);
		var source_ref = WeakRef (cleanup.symbol_span.file);
		program = null;
		assert (program_ref.get () == null && cleanup.owner == null && cleanup.signature.result == null);
		cleanup = null;
		assert (source_ref.get () == null);
	} catch (CAbiError error) {
		GLib.error ("%s", error.message);
	}
}

private void owned_invalid() {
	for (int variant = 0; variant < 10; variant++) {
		try {
			CAbiVerifier.verify (owned_program (variant));
		} catch (CAbiError error) {
			Test.message ("malformed physical cleanup %d rejected: %s", variant, error.message);
			continue;
		}
		GLib.error ("malformed physical cleanup %d accepted", variant);
	}
}

private CAbiProgram oborrow_program(int variant = -1) throws CAbiError {
	var file = new SourceFile.from_text ("borrowed-contract", "borrowed void* p");
	var span = SourceSpan (file, 0, file.length);
	var profile = variant == 1 ? CAbiProfile.SCALAR_V0 : CAbiProfile.SCALAR_PTR_V1;
	var parameters = new GenericArray<CAbiParameter> ();
	parameters.add (new CAbiParameter (span, span, "p", 0, variant == 0 ? CAbiScalarType.I32 : CAbiScalarType.PTR, variant == 2 ? (PointerParameterContract) 99 : PointerParameterContract.BORROWED_NOESCAPE));
	var signature = new CAbiSignature (profile, parameters, new CAbiResult (CAbiScalarType.I32));
	var imports = new GenericArray<CAbiFunction> ();
	imports.add (new CAbiFunction (span, span, "inspect", 0, signature, new CForeignMetadata ("inspect")));
	return new CAbiProgram (span, profile, imports);
}

private void oborrow_model() {
	try {
		CAbiProgram? program = oborrow_program ();
		CAbiVerifier.verify (program);
		assert (CAbiDump.format (program).contains ("(parameter #0 PTR (contract borrowed-noescape))"));
		var reference = WeakRef (program.functions[0].signature.parameters[0]);
		program = null;
		assert (reference.get () == null);
	} catch (CAbiError error) {
		GLib.error ("%s", error.message);
	}
}

private void oborrow_invalid() {
	for (int i = 0; i < 3; i++) {
		try {
			CAbiVerifier.verify (oborrow_program (i));
		} catch (CAbiError error) {
			Test.message ("borrow %d rejected: %s", i, error.message);
			continue;
		}
		GLib.error ("malformed borrowed CABI %d accepted", i);
	}
}

private void register_owned_tests() {
	Test.add_func ("/cabi-standalone/oborrow/model-lifetime", oborrow_model);
	Test.add_func ("/cabi-standalone/oborrow/malformed", oborrow_invalid);
	Test.add_func ("/cabi-standalone/ownership/model-lifetime", owned_model);
	Test.add_func ("/cabi-standalone/ownership/malformed", owned_invalid);
}

}
