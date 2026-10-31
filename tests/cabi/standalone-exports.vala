// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.CAbi;

namespace Astra.Tests.CAbiStandalone {
private CAbiProgram export_sample(int mode = -1, bool returns_value = false) throws CAbiError {
	var sample = new Sample ();
	var imports = new GenericArray<CAbiFunction> ();
	if (mode != -2) {
		imports.add (sample.function (0));
	}
	var exports = new GenericArray<CAbiExport> ();
	var parameters = new GenericArray<CAbiParameter> ();
	foreach (var parameter in sample.parameters) {
		parameters.add (parameter);
	}
	if (mode == 5) {
		parameters[0] = sample.parameter (1, CAbiScalarType.I32);
	}
	if (mode == 6) {
		parameters[0] = sample.parameter (0, (CAbiScalarType) 99);
	}
	var result = mode == 7 ? new CAbiResult ((CAbiScalarType) 99) : returns_value ? new CAbiResult (CAbiScalarType.I32) : null;
	var signature = new CAbiSignature (mode == 8 ? (CAbiProfile) 99 : sample.profile, parameters, result);
	exports.add (new CAbiExport (sample.span, sample.span, mode == 2 ? "" : mode == 3 ? "choose" : "exported", mode == 0 ? 1 : 0, signature, mode == 1 ? -1 : 17));
	if (mode == 4) {
		exports.add (new CAbiExport (sample.span, sample.span, "exported", 1, signature, 3));
	}
	return new CAbiProgram (sample.span, sample.profile, imports, exports);
}

private void standalone_export_model() {
	try {
		for (int result_kind = 0; result_kind < 2; result_kind++) {
			for (int mode = -2; mode < 0; mode++) {
				CAbiProgram? program = export_sample (mode, result_kind == 1);
				assert (program.exports.length == 1 && program.exports[0].owner == program && program.exports[0].native_function_ordinal == 17);
				assert (program.exports[0].span.text () == "choose" && (program.exports[0].signature.result == null) == (result_kind == 0));
				string dump = CAbiDump.format (program);
				assert (dump.contains ("(export #0\n\t\t(symbol \"exported\")\n\t\t(native-function #17)"));
				assert (dump.contains ("(result " + (result_kind == 0 ? "void" : "I32") + ")") && dump.contains ("(import #0") == (mode == -1));
				assert (dump == CAbiDump.format (program));
				var program_ref = WeakRef (program);
				var signature_ref = WeakRef (program.exports[0].signature);
				var source_ref = WeakRef (program.span.file);
				CAbiExport? retained = program.exports[0];
				program = null;
				assert (program_ref.get () == null && retained.owner == null);
				assert (retained.external_symbol == "exported" && retained.native_function_ordinal == 17);
				retained = null;
				assert (signature_ref.get () == null && source_ref.get () == null);
			}
		}
	} catch (CAbiError error) {
		GLib.error ("Standalone exports: %s", error.message);
	}
}

private void standalone_export_malformed() {
	try {
		string[] messages = {
			"export identity/ordinal must be unique and in source order", "native target ordinal must be nonnegative", "external symbols must be nonempty and unique", "C external symbol 'choose' is declared more than once", "C external symbol 'exported' is declared more than once", "parameter ordinals must be unique and in source order", "unsupported C ABI scalar type", "unsupported C ABI scalar type", "signature C ABI profile must match the program"
		};
		string[] paths = {
			"export #0", "export #0", "export #0", "export #0", "export #1", "export #0/parameter #0", "export #0/parameter #0", "export #0/result", "export #0/signature"
		};
		for (int mode = 0; mode < messages.length; mode++) {
			reject (export_sample (mode), paths[mode], messages[mode]);
		}
		var program = export_sample ();
		program.exports.add (program.exports[0]);
		reject (program, "export #1", messages[0]);
	} catch (CAbiError error) {
		GLib.error ("Malformed standalone exports: %s", error.message);
	}
}

private void standalone_export_ownership() {
	try {
		var first = export_sample ();
		CAbiProgram? second = export_sample ();
		try {
			new CAbiProgram (first.span, first.profile, new GenericArray<CAbiFunction> (), first.exports);
			assert_not_reached ();
		} catch (CAbiError.INVALID_ABI error) {
			assert (error.message.contains ("export #0 already belongs"));
		}
		assert (first.exports[0].owner == first);
		first.exports[0] = second.exports[0];
		reject (first, "export #0", "export is not owned by the containing program");
		second = null;
		assert (first.exports[0].owner == null);
		reject (first, "export #0", "export is not owned by the containing program");
	} catch (CAbiError error) {
		GLib.error ("Standalone export ownership: %s", error.message);
	}
}

private void standalone_pointer_exports() {
	try {
		for (int mode = 0; mode < 3; mode++) {
			var sample = new Sample ();
			var profile = mode == 2 ? CAbiProfile.SCALAR_PTR_V1 : CAbiProfile.SCALAR_V0;
			sample.profile = profile;
			sample.signature_profile = profile;
			var imports = new GenericArray<CAbiFunction> ();
			imports.add (sample.function (0));
			var parameters = new GenericArray<CAbiParameter> ();
			parameters.add (sample.parameter (0, mode == 1 ? CAbiScalarType.I32 : CAbiScalarType.PTR));
			var exports = new GenericArray<CAbiExport> ();
			exports.add (new CAbiExport (sample.span, sample.span, "pointer_echo", 0, new CAbiSignature (profile, parameters, new CAbiResult (CAbiScalarType.PTR)), 7));
			var program = new CAbiProgram (sample.span, profile, imports, exports);
			if (mode < 2) {
				reject (program, mode == 0 ? "export #0/parameter #0" : "export #0/result", "PTR requires scalar-ptr-v1");
			} else {
				string dump = CAbiDump.format (program);
				assert (dump.has_prefix ("(c-abi scalar-ptr-v1") && dump.contains ("(parameter #0 PTR)") && dump.contains ("(result PTR)") && dump.contains ("(result I32)"));
				assert (dump == CAbiDump.format (program));
			}
		}
	} catch (CAbiError error) {
		GLib.error ("Standalone pointer exports: %s", error.message);
	}
}

private void register_standalone_exports() {
	Test.add_func ("/cabi-standalone/exports/mixed-and-export-only-model-lifetime", standalone_export_model);
	Test.add_func ("/cabi-standalone/exports/malformed", standalone_export_malformed);
	Test.add_func ("/cabi-standalone/exports/ownership", standalone_export_ownership);
	Test.add_func ("/cabi-standalone/exports/pointer-profile", standalone_pointer_exports);
}
}
