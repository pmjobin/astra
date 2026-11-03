// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Core;
namespace Astra.Tests.GenericCopyCore {
private void qualify() {
	try {
		CoreProgram? parameterized = sample ();
		var definition = WeakRef (parameterized.generic_functions[0]);
		var application = WeakRef (parameterized.generic_functions[0].locals[0].semantic_type);
		CoreVerifier.verify (parameterized);
		CoreProgram? concrete = CoreGenericMonomorphizer.build (parameterized);
		parameterized = null;
		assert (definition.get () == null && application.get () == null);
		CoreVerifier.verify_concrete (concrete);
		assert (concrete.functions.length == 2 && concrete.structs.length == 2 && concrete.functions[1].parameters[0].struct_value_contract != null);
		assert (concrete.functions[1].body.statements[0] is CoreAcquireStructParameter && concrete.functions[1].body.statements[1] is CoreStructInitialize);
		var graph = WeakRef (concrete);
		concrete = null;
		assert (graph.get () == null);
	} catch (CoreError error) {
		GLib.error ("%s", error.message);
	}
	for (int variant = 0; variant < 11; variant++) {
		var program = sample ();
		var generic = program.generic_functions[0];
		var root = program.functions[0];
		var call = (CoreStructCallResult) ((CoreStructResultStore) root.body.statements[1]).producer;
		if (variant == 0) {
			program.structs.remove_index (0);
		}
		if (variant == 1) {
			program.structs[0].fields.remove_index (0);
		}
		if (variant == 2) {
			generic.locals[2].semantic_type = new TypeParameterType ("T");
		}
		if (variant == 3) {
			call.type_arguments[0] = new StructType ("Record");
		}
		if (variant == 4) {
			call.arguments[0] = new CoreParameterValue (generic.span, generic.parameters[0]);
		}
		if (variant == 5) {
			root.body.statements.insert (2, root.body.statements[1]);
		}
		if (variant == 6) {
			generic.body.statements.remove_index (0);
		}
		if (variant == 7) {
			generic.body.statements[3] = new CoreStore (generic.span, generic.locals[0], new CoreLoadValue (generic.span, generic.locals[0]));
		}
		if (variant == 8) {
			var owner = program.generic_structs[0];
			owner.fields[0] = new CoreGenericStructField (owner.span, owner.span, "value", owner, new TypeParameterType ("B"), 0);
		}
		if (variant == 9) {
			call.arguments[0] = new CoreStructArgument (root.span, new CoreParameter (root.span, root.span, "input", generic.return_type, 0), ((CoreStructArgument) call.arguments[0]).producer);
		}
		var application = (CoreGenericStructApplicationType) generic.locals[0].semantic_type;
		var argument = application.type_arguments[0];
		if (variant == 10) {
			application.type_arguments[0] = application;
		}
		bool rejected = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			Test.message ("variant %d: %s", variant, error.message);
			rejected = true;
		}
		if (variant == 10) {
			application.type_arguments[0] = argument;
		}
		assert (rejected);
	}
	for (int variant = 0; variant < 2; variant++) {
		var parameterized = sample ();
		var application = (CoreGenericStructApplicationType) parameterized.generic_functions[0].locals[0].semantic_type;
		var argument = application.type_arguments[0];
		try {
			var concrete = CoreGenericMonomorphizer.build (parameterized);
			application.type_arguments[0] = application;
			if (variant == 0) {
				var prior = concrete.functions[1].generic_instance;
				var replacement = new GenericFunctionInstance (parameterized.generic_functions[0], arguments (application), prior.ordinal);
				replacement.state = prior.state;
				replacement.requests = prior.requests;
				foreach (var caller in prior.callers) {
					replacement.callers.add (caller);
				}
				concrete.functions[1].generic_instance = replacement;
			} else {
				var prior = concrete.structs[1].generic_instance;
				var replacement = new GenericStructInstance (parameterized.generic_structs[0], arguments (application), prior.ordinal);
				replacement.state = prior.state;
				replacement.requests = prior.requests;
				foreach (var requester in prior.requesters) {
					replacement.requesters.add (requester);
				}
				replacement.attach (concrete.structs[1]);
				concrete.structs[1].generic_instance = replacement;
			}
			bool rejected = false;
			try {
				CoreVerifier.verify_concrete (concrete);
			} catch (CoreError error) {
				Test.message ("concrete instance variant %d: %s", variant, error.message);
				rejected = true;
			}
			application.type_arguments[0] = argument;
			assert (rejected);
		} catch (CoreError error) {
			GLib.error ("%s", error.message);
		}
	}
	for (int variant = 0; variant < 4; variant++) {
		try {
			var concrete = CoreGenericMonomorphizer.build (sample ());
			var scalar = concrete.structs[0].fields[0].semantic_type;
			if (variant == 0) {
				concrete.functions[1].generic_instance.type_arguments[0] = scalar;
			}
			if (variant == 1) {
				concrete.functions[1].generic_instance.type_arguments[0] = concrete.structs[1].semantic_type;
			}
			if (variant == 2) {
				concrete.structs[1].generic_instance.type_arguments[0] = scalar;
			}
			if (variant == 3) {
				concrete.functions[1].generic_instance.type_arguments.add (scalar);
			}
			bool rejected = false;
			try {
				CoreVerifier.verify_concrete (concrete);
			} catch (CoreError error) {
				Test.message ("changed canonical key variant %d: %s", variant, error.message);
				rejected = true;
			}
			assert (rejected);
		} catch (CoreError error) {
			GLib.error ("%s", error.message);
		}
	}
}

public int run_core(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-copy/core/standalone-materialization-lifetimes-malformed-proofs-and-producers", qualify);
	return Test.run ();
}

}
