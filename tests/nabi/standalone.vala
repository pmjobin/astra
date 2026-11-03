// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.NativeAbi;

namespace Astra.Tests.NativeStandalone {
private class Sample : Object {
	public SourceSpan span;
	public NativeAbiVersion version = NativeAbiVersion.SCALAR_V0;
	public NativeAbiVersion signature_version = NativeAbiVersion.SCALAR_V0;
	public NativeLinkage linkage = NativeLinkage.NATIVE_INTERNAL;
	public int ordinal = 0;
	public GenericArray<NativeParameter> parameters = new GenericArray<NativeParameter> ();
	public NativeResult? result = new NativeResult (NativeScalarType.I32);
	public GenericArray<NativeFunction> others = new GenericArray<NativeFunction> ();

	public Sample () {
		var file = new SourceFile.from_text ("native-standalone.astra", "choose");
		span = SourceSpan (file, 0, file.length);
		parameters.add (parameter (0, NativeScalarType.B1));
		parameters.add (parameter (1, NativeScalarType.I32));
		parameters.add (parameter (2, NativeScalarType.I32));
	}

	public NativeParameter parameter(int ordinal, NativeScalarType scalar_type) {
		return new NativeParameter (span, span, "p%d".printf (ordinal), ordinal, scalar_type);
	}

	public NativeFunction function(int ordinal) {
		return new NativeFunction (span, span, "choose", ordinal, new NativeSignature (signature_version, parameters, result), linkage);
	}

	public NativeAbiProgram finish() throws NativeAbiError {
		var functions = new GenericArray<NativeFunction> ();
		functions.add (function (ordinal));
		for (int i = 0; i < others.length; i++) {
			functions.add (others[i]);
		}
		return new NativeAbiProgram (span, version, functions);
	}

}

private void reject(NativeAbiProgram program, string path, string message) {
	string expected = "internal native ABI verification error at " + path + ": " + message;
	for (int i = 0; i < 3; i++) {
		try {
			if (i == 1) {
				NativeAbiDump.format (program);
			} else {
				NativeAbiVerifier.verify (program);
			}
		} catch (NativeAbiError error) {
			if (!(error is NativeAbiError.INVALID_ABI) || error.message != expected) {
				GLib.error ("Expected: %s\nActual: %s", expected, error.message);
			}
			continue;
		}
		GLib.error ("Malformed native ABI was accepted: %s", expected);
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
		} catch (NativeAbiError error) {
			GLib.error ("Test failed before verification: %s", error.message);
		}
	}

}

private HashTable<string, InvalidCase> cases;

private void invalid(string name, string path, string message, owned Corrupt corrupt) {
	string test_path = "/nabi-standalone/verifier/" + name;
	cases.insert (test_path, new InvalidCase ((owned) corrupt, path, message));
	Test.add_func (test_path, () => cases.lookup (Test.get_path ()).run ());
}

private void model() {
	try {
		var sample = new Sample ();
		NativeAbiProgram? program = sample.finish ();
		NativeAbiVerifier.verify (program);
		assert (program.abi_version == NativeAbiVersion.SCALAR_V0);
		assert (program.functions[0].owner == program && program.functions[0].linkage == NativeLinkage.NATIVE_INTERNAL);
		assert (program.functions[0].name == "choose" && program.functions[0].name_span.text () == "choose");
		string expected = "(native-abi scalar-v0\n\t(function #0 \"choose\"\n\t\t(linkage native-internal)\n\t\t(signature\n\t\t\t(parameters\n\t\t\t\t(parameter #0 B1)\n\t\t\t\t(parameter #1 I32)\n\t\t\t\t(parameter #2 I32)\n\t\t\t)\n\t\t\t(result I32)\n\t\t)\n\t)\n)\n";
		assert (NativeAbiDump.format (program) == expected && NativeAbiDump.format (program) == expected);
		var program_ref = WeakRef (program);
		var function_ref = WeakRef (program.functions[0]);
		var signature_ref = WeakRef (program.functions[0].signature);
		program = null;
		assert (program_ref.get () == null && function_ref.get () == null && signature_ref.get () == null);
	} catch (NativeAbiError error) {
		GLib.error ("Standalone model failed: %s", error.message);
	}
}

private void empty() {
	try {
		var sample = new Sample ();
		var program = new NativeAbiProgram (sample.span, NativeAbiVersion.SCALAR_V0, new GenericArray<NativeFunction> ());
		assert (NativeAbiDump.format (program) == "(native-abi scalar-v0)\n");
	} catch (NativeAbiError error) {
		GLib.error ("Empty sidecar failed: %s", error.message);
	}
}

private void zero_arguments() {
	try {
		for (int i = 0; i < 3; i++) {
			var sample = new Sample ();
			sample.parameters = new GenericArray<NativeParameter> ();
			sample.result = i == 0 ? null : new NativeResult (i == 1 ? NativeScalarType.I32 : NativeScalarType.B1);
			var program = sample.finish ();
			string dump = NativeAbiDump.format (program);
			assert (program.functions[0].signature.parameters.length == 0 && dump.contains ("(parameters)"));
			assert (dump.contains ("(result " + (i == 0 ? "void" : i == 1 ? "I32" : "B1") + ")"));
		}
	} catch (NativeAbiError error) {
		GLib.error ("Zero-argument signatures failed: %s", error.message);
	}
}

private void unique_owner() {
	try {
		var sample = new Sample ();
		NativeAbiProgram? first = sample.finish ();
		var function = first.functions[0];
		var second_functions = new GenericArray<NativeFunction> ();
		second_functions.add (function);
		bool rejected = false;
		try {
			new NativeAbiProgram (sample.span, sample.version, second_functions);
		} catch (NativeAbiError error) {
			assert (error is NativeAbiError.INVALID_ABI && error.message == "internal native ABI construction error: function #0 already belongs to a program");
			rejected = true;
		}
		assert (rejected && function.owner == first);
		NativeAbiVerifier.verify (first);
		var first_ref = WeakRef (first);
		first = null;
		assert (first_ref.get () == null && function.owner == null);
	} catch (NativeAbiError error) {
		GLib.error ("Unique ownership failed: %s", error.message);
	}
}

private void foreign_owner() {
	try {
		var sample = new Sample ();
		var first = sample.finish ();
		NativeAbiProgram? second = sample.finish ();
		first.functions[0] = second.functions[0];
		reject (first, "function #0", "function is not owned by the containing program");
		second = null;
		assert (first.functions[0].owner == null);
		reject (first, "function #0", "function is not owned by the containing program");
	} catch (NativeAbiError error) {
		GLib.error ("Foreign/expired ownership failed: %s", error.message);
	}
}

private void duplicate_identity() {
	try {
		var sample = new Sample ();
		var program = sample.finish ();
		program.functions.add (program.functions[0]);
		reject (program, "function #1", "function identity/ordinal must be unique and in source order");
	} catch (NativeAbiError error) {
		GLib.error ("Duplicate identity test failed: %s", error.message);
	}
}

private void pointers() {
	try {
		var sample = new Sample ();
		sample.version = NativeAbiVersion.SCALAR_PTR_V1;
		sample.signature_version = NativeAbiVersion.SCALAR_PTR_V1;
		sample.parameters[2] = sample.parameter (2, NativeScalarType.PTR);
		sample.result = new NativeResult (NativeScalarType.PTR);
		var program = sample.finish ();
		NativeAbiVerifier.verify (program);
		string dump = NativeAbiDump.format (program);
		assert (dump.contains ("scalar-ptr-v1") && dump.contains ("(parameter #2 PTR)") && dump.contains ("(result PTR)"));
		assert (dump.contains ("(parameter #1 I32)") && dump == NativeAbiDump.format (program));
	} catch (NativeAbiError error) {
		GLib.error ("Standalone pointer channels failed: %s", error.message);
	}
}

private void conservative_effects() {
	try {
		var sample = new Sample ();
		var program = sample.finish ();
		var function = program.functions[0];
		NativeAbiVerifier.verify (program);
		assert (!function.scoped_readonly && !function.callback_contract_supported);

		function.scoped_readonly = true;
		reject (program, "readonly native effect", "lost its original checked definition contract");
		function.scoped_readonly = false;
		function.callback_contract_supported = true;
		reject (program, "readonly native effect", "lost its original checked definition contract");
		function.callback_contract_supported = false;
		function.callback_inputs = "0";
		reject (program, "readonly native effect", "lost its original checked definition contract");
		function.callback_inputs = "";
		NativeAbiVerifier.verify (program);

		function.bind_scoped_readonly (true);
		NativeAbiVerifier.verify (program);
		function.scoped_readonly = false;
		reject (program, "readonly native effect", "lost its original checked definition contract");
		function.scoped_readonly = true;
		bool refused = false;
		try {
			function.bind_scoped_readonly (false);
		} catch (NativeAbiError error) {
			refused = error.message == "readonly effect binds once to its original checked definition";
		}
		assert (refused);
		NativeAbiVerifier.verify (program);
	} catch (NativeAbiError error) {
		GLib.error ("Conservative native effect contract failed: %s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, InvalidCase> (str_hash, str_equal);
	Test.add_func ("/nabi-standalone/model", model);
	Test.add_func ("/nabi-standalone/conservative-effect-contract", conservative_effects);
	Test.add_func ("/nabi-standalone/pointer-mixed-v1", pointers);
	invalid ("pointer-parameter-v0", "function #0/parameter #0", "PTR requires scalar-ptr-v1", s => s.parameters[0] = s.parameter (0, NativeScalarType.PTR));
	invalid ("pointer-result-v0", "function #0/result", "PTR requires scalar-ptr-v1", s => s.result = new NativeResult (NativeScalarType.PTR));
	Test.add_func ("/nabi-standalone/empty", empty);
	Test.add_func ("/nabi-standalone/zero-arguments", zero_arguments);
	Test.add_func ("/nabi-standalone/unique-owner", unique_owner);
	Test.add_func ("/nabi-standalone/verifier/foreign-and-expired-owner", foreign_owner);
	Test.add_func ("/nabi-standalone/verifier/duplicate-function-identity", duplicate_identity);
	invalid ("duplicate-parameter", "function #0/parameter #1", "parameter ordinals must be unique and in source order", s => s.parameters[1] = s.parameter (0, NativeScalarType.I32));
	invalid ("parameter-order", "function #0/parameter #0", "parameter ordinals must be unique and in source order", s => s.parameters[0] = s.parameter (1, NativeScalarType.B1));
	invalid ("negative-parameter", "function #0/parameter #0", "parameter ordinals must be unique and in source order", s => s.parameters[0] = s.parameter (-1, NativeScalarType.B1));
	invalid ("unsupported-parameter", "function #0/parameter #0", "unsupported native scalar type", s => s.parameters[0] = s.parameter (0, (NativeScalarType) 99));
	invalid ("unsupported-result", "function #0/result", "unsupported native scalar type", s => s.result = new NativeResult ((NativeScalarType) 99));
	invalid ("unknown-version", "program", "unsupported native ABI version", s => s.version = (NativeAbiVersion) 99);
	invalid ("signature-version", "function #0/signature", "signature ABI version must match the program", s => s.signature_version = (NativeAbiVersion) 99);
	invalid ("duplicate-function-ordinal", "function #1", "function identity/ordinal must be unique and in source order", s => s.others.add (s.function (0)));
	invalid ("function-order", "function #0", "function identity/ordinal must be unique and in source order", s => s.ordinal = 1);
	invalid ("negative-function", "function #0", "function identity/ordinal must be unique and in source order", s => s.ordinal = -1);
	invalid ("invalid-linkage", "function #0", "unsupported native linkage", s => s.linkage = (NativeLinkage) 99);
	int status = Test.run ();
	cases = null;
	return status;
}

}
