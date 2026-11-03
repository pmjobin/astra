// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.NativeAbi;
namespace Astra.Tests.GenericCopyNabi {
private NativeAbiProgram sample(int variant = -1) throws NativeAbiError {
	var span = SourceSpan (new SourceFile.from_text ("independent-specialization-plan", "x"), 0, 1);
	var leaves = new GenericArray<NativeStructLeafChannel> ();
	leaves.add (new NativeStructLeafChannel ("0.0", new NativeScalarAbiType (NativeScalarType.I32)));
	leaves.add (new NativeStructLeafChannel ("0.1", new NativeScalarAbiType (NativeScalarType.F64)));
	var plan = new NativeStructValuePlan (0, "astra.gen.struct.0.0", leaves, NativeStructResultCarrier.LEAF_AGGREGATE);
	var parameters = new GenericArray<NativeParameter> ();
	foreach (var leaf in leaves) {
		parameters.add (new NativeParameter.typed (span, span, "value", parameters.length, leaf.abi_type));
	}
	var signature = new NativeSignature (NativeAbiVersion.AGGREGATE_V7, parameters, null);
	signature.struct_parameters.add (new NativeStructParameterPlan (0, 0, plan));
	signature.struct_result = plan;
	var functions = new GenericArray<NativeFunction> ();
	functions.add (new NativeFunction (span, span, "astra.gen.0.0", 0, signature, NativeLinkage.NATIVE_INTERNAL));
	var program = new NativeAbiProgram (span, NativeAbiVersion.AGGREGATE_V7, functions);
	program.struct_values.add (plan);
	if (variant == 0) {
		leaves.remove_index (1);
	}
	if (variant == 1) {
		signature.struct_result = new NativeStructValuePlan (0, "Other", leaves, NativeStructResultCarrier.LEAF_AGGREGATE);
	}
	if (variant == 2) {
		leaves[1] = new NativeStructLeafChannel ("0.0", leaves[1].abi_type);
	}
	if (variant == 3) {
		signature.struct_parameters[0] = new NativeStructParameterPlan (1, 0, plan);
	}
	if (variant == 4) {
		parameters[1] = new NativeParameter.typed (span, span, "value", 1, new NativeScalarAbiType (NativeScalarType.PTR));
	}
	return program;
}

private void qualify() {
	try {
		NativeAbiProgram? program = sample ();
		NativeAbiVerifier.verify (program);
		var plan = program.struct_values[0];
		var function = WeakRef (program.functions[0]);
		program = null;
		assert (function.get () == null && plan.leaves.length == 2);
		for (int variant = 0; variant < 5; variant++) {
			bool rejected = false;
			try {
				NativeAbiVerifier.verify (sample (variant));
			} catch (NativeAbiError error) {
				rejected = true;
			}
			assert (rejected);
		}
		NativeAbiVerifier.verify (sample ());
	} catch (NativeAbiError error) {
		GLib.error ("%s", error.message);
	}
}

public int run_nabi(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-copy/nabi/independent-owned-physical-shapes-and-forgeries", qualify);
	return Test.run ();
}

}
