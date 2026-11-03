// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Core;
namespace Astra.Tests.GenericSliceCore {
private void qualify() {
	try {
		CoreProgram? parameterized = sample ();
		var definition = WeakRef (parameterized.generic_functions[0]);
		var obligation = WeakRef (parameterized.generic_functions[0].element_obligations);
		var symbolic = WeakRef (parameterized.generic_functions[0].parameters[1].semantic_type);
		CoreVerifier.verify (parameterized);
		CoreProgram? concrete = CoreGenericMonomorphizer.build (parameterized);
		parameterized = null;
		assert (definition.get () == null && obligation.get () == null && symbolic.get () == null);
		CoreVerifier.verify_concrete (concrete);
		assert (concrete.functions.length == 2 && concrete.functions[1].parameters[0].struct_value_contract != null && concrete.functions[1].parameters[1].semantic_type == concrete.functions[0].parameters[0].semantic_type);
		assert (concrete.functions[1].body.statements[0] is CoreAcquireStructParameter && concrete.functions[1].body.statements[2] is CoreStructCopy && concrete.functions[1].body.statements[3] is CoreStructCopy);
	} catch (CoreError error) {
		GLib.error ("%s", error.message);
	}
	for (int variant = 0; variant < 11; variant++) {
		var program = sample ();
		var generic = program.generic_functions[0];
		var root = program.functions[0];
		var call = (CoreStructCallResult) ((CoreStructResultStore) root.body.statements[1]).producer;
		if (variant == 0) {
			generic.element_obligations.require (new TypeParameterType ("T"));
		}
		if (variant == 1) {
			generic.parameters[1].semantic_type = new SliceType (new TypeParameterType ("T"));
		}
		if (variant == 2) {
			generic.locals[0].semantic_type = new SliceType (new TypeParameterType ("T", new GenericCapabilitySet ({GenericCapabilityIdentity.OWNABLE})));
		}
		if (variant == 3) {
			call.arguments.remove_index (1);
		}
		if (variant == 4) {
			call.type_arguments[0] = new StructType ("Record");
		}
		if (variant == 5) {
			program.structs[0].fields.remove_index (0);
		}
		if (variant == 6) {
			generic.body.statements.remove_index (0);
		}
		if (variant == 7) {
			generic.parameters[1] = new CoreParameter (generic.span, generic.span, "view", generic.parameters[1].semantic_type, 1);
		}
		if (variant == 8) {
			root.parameters[0].semantic_type = new SliceType (new BuiltinTypes ().string_type);
		}
		if (variant == 9) {
			var load = (CoreLoadValue) ((CoreInitialize) generic.body.statements[1]).value;
			var place = (CoreSliceElementPlace) load.source;
			generic.body.statements[1] = new CoreInitialize (generic.span, generic.locals[1], new CoreLoadValue (generic.span, new CoreSliceElementPlace (generic.span, place.slice, place.slice_type, place.index, new DataPointerProvenance (DataPointerOrigin.PARAMETER, 1, 0, true))));
		}
		if (variant == 10) {
			program.generic_functions[0] = new CoreGenericFunction (generic.span, generic.name_span, generic.name, generic.return_type, generic.parameters, generic.locals, generic.body, null, generic.type_parameters, 0);
		}
		bool rejected = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			Test.message ("parameterized variant %d: %s", variant, error.message);
			rejected = true;
		}
		assert (rejected);
	}
	for (int variant = 0; variant < 4; variant++) {
		try {
			var concrete = CoreGenericMonomorphizer.build (sample ());
			var function = concrete.functions[1];
			if (variant == 0) {
				function.generic_instance.type_arguments[0] = concrete.structs[0].fields[0].semantic_type;
			}
			if (variant == 1) {
				function.generic_instance.type_arguments[0] = new StructType ("Record");
			}
			if (variant == 2) {
				function.generic_instance.type_arguments.add (concrete.structs[0].semantic_type);
			}
			if (variant == 3) {
				function.parameters[1].semantic_type = new SliceType (new StructType ("Record"));
			}
			bool rejected = false;
			try {
				CoreVerifier.verify_concrete (concrete);
			} catch (CoreError error) {
				Test.message ("concrete variant %d: %s", variant, error.message);
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
	Test.add_func ("/gen-slice/core/independent-obligations-places-materialization-and-key-lifetimes", qualify);
	return Test.run ();
}

}
