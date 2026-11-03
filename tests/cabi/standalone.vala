// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Foreign;
using Astra.CAbi;

namespace Astra.Tests.CAbiStandalone {
private class Sample : Object {
	public SourceSpan span;
	public CAbiProfile profile = CAbiProfile.SCALAR_V0;
	public CAbiProfile signature_profile = CAbiProfile.SCALAR_V0;
	public string external_symbol = "choose";
	public int ordinal = 0;
	public GenericArray<CAbiParameter> parameters = new GenericArray<CAbiParameter> ();
	public CAbiResult? result = new CAbiResult (CAbiScalarType.I32);
	public GenericArray<CAbiFunction> others = new GenericArray<CAbiFunction> ();

	public Sample () {
		var file = new SourceFile.from_text ("cabi-standalone.astra", "choose");
		span = SourceSpan (file, 0, file.length);
		parameters.add (parameter (0, CAbiScalarType.I32));
		parameters.add (parameter (1, CAbiScalarType.I32));
		parameters.add (parameter (2, CAbiScalarType.I32));
	}

	public CAbiParameter parameter(int ordinal, CAbiScalarType scalar_type) {
		return new CAbiParameter (span, span, "p%d".printf (ordinal), ordinal, scalar_type);
	}

	public CAbiFunction function(int ordinal) {
		return new CAbiFunction (span, span, "choose", ordinal, new CAbiSignature (signature_profile, parameters, result), new CForeignMetadata (external_symbol));
	}

	public CAbiProgram finish() throws CAbiError {
		var functions = new GenericArray<CAbiFunction> ();
		functions.add (function (ordinal));
		for (int i = 0; i < others.length; i++) {
			functions.add (others[i]);
		}
		return new CAbiProgram (span, profile, functions);
	}

}

private void reject(CAbiProgram program, string path, string message) {
	bool collision = message.has_prefix ("C external symbol");
	string expected = collision ? new Diagnostic (program.span, message).format () : "internal C ABI verification error at " + path + ": " + message;
	for (int i = 0; i < 3; i++) {
		try {
			if (i == 1) {
				CAbiDump.format (program);
			} else {
				CAbiVerifier.verify (program);
			}
		} catch (CAbiError error) {
			if ((collision && !(error is CAbiError.DUPLICATE_SYMBOL)) || (!collision && !(error is CAbiError.INVALID_ABI)) || error.message != expected) {
				GLib.error ("Expected: %s\nActual: %s", expected, error.message);
			}
			continue;
		}
		GLib.error ("Malformed C ABI was accepted: %s", expected);
	}
}

private delegate void Corrupt(Sample sample);

private class InvalidCase : Object {
	private Corrupt corrupt;
	private string path;
	private string message;

	public InvalidCase (owned Corrupt corrupt, string path, string message) {
		this.corrupt = (owned) corrupt;
		this.path = path;
		this.message = message;
	}

	public void run() {
		var sample = new Sample ();
		corrupt (sample);
		try {
			reject (sample.finish (), path, message);
		} catch (CAbiError error) {
			GLib.error ("Test failed before verification: %s", error.message);
		}
	}

}

private HashTable<string, InvalidCase> cases;

private void invalid(string name, string path, string message, owned Corrupt corrupt) {
	string test_path = "/cabi-standalone/verifier/" + name;
	cases.insert (test_path, new InvalidCase ((owned) corrupt, path, message));
	Test.add_func (test_path, () => cases.lookup (Test.get_path ()).run ());
}

private void model() {
	try {
		var sample = new Sample ();
		CAbiProgram? program = sample.finish ();
		CAbiVerifier.verify (program);
		assert (program.profile == CAbiProfile.SCALAR_V0);
		assert (program.functions[0].owner == program && program.functions[0].external_symbol == "choose");
		assert (program.functions[0].name == "choose" && program.functions[0].name_span.text () == "choose");
		string expected = "(c-abi scalar-v0\n\t(import #0\n\t\t(name \"choose\")\n\t\t(symbol \"choose\")\n\t\t(signature\n\t\t\t(parameters\n\t\t\t\t(parameter #0 I32)\n\t\t\t\t(parameter #1 I32)\n\t\t\t\t(parameter #2 I32)\n\t\t\t)\n\t\t\t(result I32)\n\t\t)\n\t)\n)\n";
		assert (CAbiDump.format (program) == expected && CAbiDump.format (program) == expected);
		var program_ref = WeakRef (program);
		var function_ref = WeakRef (program.functions[0]);
		var signature_ref = WeakRef (program.functions[0].signature);
		program = null;
		assert (program_ref.get () == null && function_ref.get () == null && signature_ref.get () == null);
	} catch (CAbiError error) {
		GLib.error ("Standalone model failed: %s", error.message);
	}
}

private void empty() {
	try {
		var sample = new Sample ();
		var program = new CAbiProgram (sample.span, CAbiProfile.SCALAR_V0, new GenericArray<CAbiFunction> ());
		assert (CAbiDump.format (program) == "(c-abi scalar-v0)\n");
	} catch (CAbiError error) {
		GLib.error ("Empty sidecar failed: %s", error.message);
	}
}

private void zero_arguments() {
	try {
		for (int i = 0; i < 2; i++) {
			var sample = new Sample ();
			sample.parameters = new GenericArray<CAbiParameter> ();
			sample.result = i == 0 ? null : new CAbiResult (CAbiScalarType.I32);
			var program = sample.finish ();
			string dump = CAbiDump.format (program);
			assert (program.functions[0].signature.parameters.length == 0 && dump.contains ("(parameters)"));
			assert (dump.contains ("(result " + (i == 0 ? "void" : "I32") + ")"));
		}
	} catch (CAbiError error) {
		GLib.error ("Zero-argument signatures failed: %s", error.message);
	}
}

private void unique_owner() {
	try {
		var sample = new Sample ();
		CAbiProgram? first = sample.finish ();
		var function = first.functions[0];
		var second_functions = new GenericArray<CAbiFunction> ();
		second_functions.add (function);
		bool rejected = false;
		try {
			new CAbiProgram (sample.span, sample.profile, second_functions);
		} catch (CAbiError error) {
			assert (error is CAbiError.INVALID_ABI && error.message == "internal C ABI construction error: function #0 already belongs to a program");
			rejected = true;
		}
		assert (rejected && function.owner == first);
		CAbiVerifier.verify (first);
		var first_ref = WeakRef (first);
		first = null;
		assert (first_ref.get () == null && function.owner == null);
	} catch (CAbiError error) {
		GLib.error ("Unique ownership failed: %s", error.message);
	}
}

private void foreign_owner() {
	try {
		var sample = new Sample ();
		var first = sample.finish ();
		CAbiProgram? second = sample.finish ();
		first.functions[0] = second.functions[0];
		reject (first, "function #0", "function is not owned by the containing program");
		second = null;
		assert (first.functions[0].owner == null);
		reject (first, "function #0", "function is not owned by the containing program");
	} catch (CAbiError error) {
		GLib.error ("Foreign/expired ownership failed: %s", error.message);
	}
}

private void duplicate_identity() {
	try {
		var sample = new Sample ();
		var program = sample.finish ();
		program.functions.add (program.functions[0]);
		reject (program, "function #1", "function identity/ordinal must be unique and in source order");
	} catch (CAbiError error) {
		GLib.error ("Duplicate identity test failed: %s", error.message);
	}
}

private void pointers() {
	try {
		var sample = new Sample ();
		sample.profile = CAbiProfile.SCALAR_PTR_V1;
		sample.signature_profile = CAbiProfile.SCALAR_PTR_V1;
		sample.parameters[2] = sample.parameter (2, CAbiScalarType.PTR);
		sample.result = new CAbiResult (CAbiScalarType.PTR);
		var program = sample.finish ();
		CAbiVerifier.verify (program);
		string dump = CAbiDump.format (program);
		assert (dump.contains ("scalar-ptr-v1") && dump.contains ("(parameter #2 PTR)") && dump.contains ("(result PTR)"));
		assert (dump.contains ("(parameter #1 I32)") && dump == CAbiDump.format (program));
	} catch (CAbiError error) {
		GLib.error ("Standalone pointer channels failed: %s", error.message);
	}
}

private void doubles() {
	try {
		var sample = new Sample ();
		sample.profile = CAbiProfile.SCALAR_FP_V2;
		sample.signature_profile = CAbiProfile.SCALAR_FP_V2;
		sample.parameters[0] = sample.parameter (0, CAbiScalarType.F64);
		sample.parameters[2] = sample.parameter (2, CAbiScalarType.PTR);
		sample.result = new CAbiResult (CAbiScalarType.F64);
		var program = sample.finish ();
		CAbiVerifier.verify (program);
		string dump = CAbiDump.format (program);
		assert (dump.contains ("scalar-fp-v2") && dump.contains ("(parameter #0 F64 (semantic f64) (c-type double))") && dump.contains ("(result F64 (semantic f64) (c-type double))") && dump.contains ("(parameter #2 PTR)"));
	} catch (CAbiError error) {
		GLib.error ("Standalone double channels failed: %s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	register_owned_tests ();
	cases = new HashTable<string, InvalidCase> (str_hash, str_equal);
	Test.add_func ("/cabi-standalone/model", model);
	Test.add_func ("/cabi-standalone/pointer-mixed-v1", pointers);
	Test.add_func ("/cabi-standalone/double-mixed-v2", doubles);
	invalid ("double-parameter-v0", "function #0/parameter #0", "F64 requires scalar-fp-v2", s => s.parameters[0] = s.parameter (0, CAbiScalarType.F64));
	invalid ("double-result-v0", "function #0/result", "F64 requires scalar-fp-v2", s => s.result = new CAbiResult (CAbiScalarType.F64));
	invalid ("double-parameter-v1", "function #0/parameter #0", "F64 requires scalar-fp-v2", s => { s.profile = s.signature_profile = CAbiProfile.SCALAR_PTR_V1;
		                                                                                            s.parameters[0] = s.parameter (0, CAbiScalarType.F64);
	});
	invalid ("double-result-v1", "function #0/result", "F64 requires scalar-fp-v2", s => { s.profile = s.signature_profile = CAbiProfile.SCALAR_PTR_V1;
		                                                                                   s.result = new CAbiResult (CAbiScalarType.F64);
	});
	invalid ("pointer-parameter-v0", "function #0/parameter #0", "PTR requires scalar-ptr-v1", s => s.parameters[0] = s.parameter (0, CAbiScalarType.PTR));
	invalid ("pointer-result-v0", "function #0/result", "PTR requires scalar-ptr-v1", s => s.result = new CAbiResult (CAbiScalarType.PTR));
	Test.add_func ("/cabi-standalone/empty", empty);
	Test.add_func ("/cabi-standalone/zero-arguments", zero_arguments);
	Test.add_func ("/cabi-standalone/unique-owner", unique_owner);
	Test.add_func ("/cabi-standalone/verifier/foreign-and-expired-owner", foreign_owner);
	Test.add_func ("/cabi-standalone/verifier/duplicate-function-identity", duplicate_identity);
	invalid ("duplicate-parameter", "function #0/parameter #1", "parameter ordinals must be unique and in source order", s => s.parameters[1] = s.parameter (0, CAbiScalarType.I32));
	invalid ("parameter-order", "function #0/parameter #0", "parameter ordinals must be unique and in source order", s => s.parameters[0] = s.parameter (1, CAbiScalarType.I32));
	invalid ("negative-parameter", "function #0/parameter #0", "parameter ordinals must be unique and in source order", s => s.parameters[0] = s.parameter (-1, CAbiScalarType.I32));
	invalid ("unsupported-parameter", "function #0/parameter #0", "unsupported C ABI scalar type", s => s.parameters[0] = s.parameter (0, (CAbiScalarType) 99));
	invalid ("unsupported-result", "function #0/result", "unsupported C ABI scalar type", s => s.result = new CAbiResult ((CAbiScalarType) 99));
	invalid ("unknown-profile", "program", "unsupported C ABI profile", s => s.profile = (CAbiProfile) 99);
	invalid ("signature-profile", "function #0/signature", "signature C ABI profile must match the program", s => s.signature_profile = (CAbiProfile) 99);
	invalid ("duplicate-function-ordinal", "function #1", "function identity/ordinal must be unique and in source order", s => s.others.add (s.function (0)));
	invalid ("function-order", "function #0", "function identity/ordinal must be unique and in source order", s => s.ordinal = 1);
	invalid ("negative-function", "function #0", "function identity/ordinal must be unique and in source order", s => s.ordinal = -1);
	invalid ("empty-symbol", "function #0", "external symbols must be nonempty and unique", s => s.external_symbol = "");
	invalid ("duplicate-symbol", "function #1", "C external symbol 'choose' is declared more than once", s => s.others.add (s.function (1)));
	register_standalone_exports ();
	register_standalone_metadata ();
	int status = Test.run ();
	cases = null;
	return status;
}

}
