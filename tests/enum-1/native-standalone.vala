// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.NativeAbi;

namespace Astra.Tests.EnumNative {
private NativeSignature signature(int mutation) {
	var span = SourceSpan (new SourceFile.from_text ("sum-native-independent", "x"), 0, 1);
	var identity = new EnumIdentity ("Pair");
	var parameters = new GenericArray<NativeParameter> ();
	parameters.add (new NativeParameter.typed (span, span, "value", 0, new NativeSumType (identity, mutation == 1 ? NativeSumRole.RESULT_CALLER_STORAGE : NativeSumRole.SNAPSHOT_READONLY, mutation == 2 ? NativeScalarType.I32 : NativeScalarType.PTR)));
	var signature = new NativeSignature (mutation == 3 ? NativeAbiVersion.STRUCT_ELEMENTS_V11 : NativeAbiVersion.SUM_VALUES_V12, parameters, mutation == 4 ? new NativeResult (NativeScalarType.I32) : mutation == 5 ? new NativeResult.typed (new NativeSumType (identity)) : null);
	if (mutation != 5) {
		signature.sum_result = new NativeSumType (identity, mutation == 6 ? NativeSumRole.SNAPSHOT_READONLY : NativeSumRole.RESULT_CALLER_STORAGE, mutation == 7 ? NativeScalarType.I32 : NativeScalarType.PTR);
	}
	return signature;
}

private void positive() {
	try {
		var plan = signature (0);
		NativeAbiVerifier.verify_detached_signature (plan, "independent sum signature");
		assert (plan.physical_parameter_count == 2);
	} catch (NativeAbiError error) {
		GLib.error ("%s", error.message);
	}
}

private void malformed() {
	for (int mutation = 1; mutation <= 7; mutation++) {
		try {
			NativeAbiVerifier.verify_detached_signature (signature (mutation), "independent sum signature");
		} catch (NativeAbiError error) {
			Test.message ("mutation %d: %s", mutation, error.message);
			continue;
		}
		GLib.error ("accepted malformed detached sum signature %d", mutation);
	}
}

private void graph() {
	try {
		var span = SourceSpan (new SourceFile.from_text ("sum-native-graph", "x"), 0, 1);
		var identity = new EnumIdentity ("Independent");
		var variant = new EnumVariantIdentity (identity, "Data", 0);
		var field = new EnumFieldIdentity (variant, "value", 0);
		var fields = new GenericArray<NativeSumField> ();
		var scalar = new NativeSumField (field, new NativeScalarAbiType (NativeScalarType.I32), null, null);
		fields.add (scalar);
		var variants = new GenericArray<NativeSumVariant> ();
		var original_variant = new NativeSumVariant (variant, fields);
		variants.add (original_variant);
		var plan = new NativeSumPlan (identity, variants);
		var program = new NativeAbiProgram (span, NativeAbiVersion.SUM_VALUES_V12, new GenericArray<NativeFunction> ());
		program.sum_values.add (plan);
		NativeAbiVerifier.verify (program);
		for (int mutation = 0; mutation < 6; mutation++) {
			if (mutation == 0) {
				variants.remove_index (0);
			}
			if (mutation == 1) {
				fields[0] = new NativeSumField (new EnumFieldIdentity (variant, "value", 1), scalar.leaf, null, null);
			}
			if (mutation == 2) {
				fields[0] = new NativeSumField (field, scalar.leaf, null, plan);
			}
			if (mutation == 3) {
				fields[0] = new NativeSumField (field, null, null, plan);
			}
			if (mutation == 4) {
				fields[0] = new NativeSumField (field, new NativeSumType (identity), null, null);
			}
			if (mutation == 5) {
				program.sum_values.add (plan);
			}
			bool rejected = false;
			try {
				NativeAbiVerifier.verify (program);
			} catch (NativeAbiError error) {
				Test.message ("graph mutation %d: %s", mutation, error.message);
				rejected = true;
			}
			assert (rejected);
			if (variants.length == 0) {
				variants.add (original_variant);
			}
			fields[0] = scalar;
			if (program.sum_values.length > 1) {
				program.sum_values.remove_index (1);
			}
			NativeAbiVerifier.verify (program);
			Test.message ("restored native graph %d", mutation);
		}
	} catch (NativeAbiError error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/enum/native/detached-signature", positive);
	Test.add_func ("/enum/native/independent-graph-restoration", graph);
	Test.add_func ("/enum/native/detached-capability-channel-profile", malformed);
	return Test.run ();
}

}
