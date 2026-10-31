// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Core;
namespace Astra.Tests.GenStructCore {
private void model() {
	try {
		var program = sample ();
		CoreVerifier.verify (program);
		Object definition = program.generic_structs[0];
		assert (!(definition is CoreNativeInstance));
		var bundle = program.generic_structs[1];
		var application = (CoreGenericStructApplicationType) bundle.fields[0].semantic_type;
		assert (application.definition == program.generic_structs[0] && application.type_arguments[0] == bundle.type_parameters[0].semantic_type);
		var function = program.generic_functions[0];
		var initializer = (CoreStructInitialize) function.body.statements[0];
		var projection = (CoreGenericStructFieldPlace) ((CoreInitialize) initializer.initializers[0]).target;
		assert (projection.field == program.generic_structs[0].fields[0] && projection.semantic_type == function.return_type && projection.aggregate == initializer.target);
		assert (CoreDump.format (program).contains ("generic-field-place") && CoreDump.format (program).contains ("struct-initialize-storage"));
		bool rejected = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			rejected = error.message.contains ("before CFG");
		}
		assert (rejected);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void malformed() {
	for (int scenario = 0; scenario < 8; scenario++) {
		var program = sample ();
		var definition = program.generic_structs[0];
		if (scenario == 0) {
			program.generic_structs.remove_index (0);
		}
		if (scenario == 1) {
			definition.type_parameters[1] = definition.type_parameters[0];
		}
		if (scenario == 2) {
			definition.fields[0] = program.generic_structs[1].fields[0];
		}
		if (scenario == 3) {
			definition.fields[0] = new CoreGenericStructField (span (), span (), "first", definition, new TypeParameterType ("Foreign"), 0);
		}
		if (scenario == 4) {
			((CoreStructInitialize) program.generic_functions[0].body.statements[0]).initializers.remove_index (1);
		}
		if (scenario == 5) {
			((CoreStructInitialize) program.generic_functions[0].body.statements[0]).initializers[1] = ((CoreStructInitialize) program.generic_functions[0].body.statements[0]).initializers[0];
		}
		if (scenario == 6) {
			program.functions[0].parameters.add (new CoreParameter (span (), span (), "aggregate", program.functions[0].locals[0].semantic_type, 0));
		}
		if (scenario == 7) {
			var pointer = new TypedPointerType (program.generic_functions[0].locals[0].semantic_type);
			program.generic_functions[0].parameters.add (new CoreParameter (span (), span (), "pointer", pointer, 1));
		}
		bool rejected = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-struct/core/parameterized-model-exact-origins", model);
	Test.add_func ("/gen-struct/core/malformed-scope-origin-initializer-boundaries", malformed);
	return Test.run ();
}
}
