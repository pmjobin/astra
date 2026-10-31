// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.NativeAbi;
namespace Astra.Tests.StructAbiNabi {
private NativeAbiProgram sample(bool single = false, NativeAbiVersion version = NativeAbiVersion.AGGREGATE_V7) throws NativeAbiError {
	var s = SourceSpan (new SourceFile.from_text ("nabi-boundary", "x"), 0, 1);
	var leaves = new GenericArray<NativeStructLeafChannel> ();
	leaves.add (new NativeStructLeafChannel (single ? "0" : "0.0", new NativeScalarAbiType (single ? NativeScalarType.F64 : NativeScalarType.I32)));
	if (!single) {
		leaves.add (new NativeStructLeafChannel ("0.1", new NativeScalarAbiType (NativeScalarType.F64)));
		leaves.add (new NativeStructLeafChannel ("1", new NativeVectorType (NativeScalarType.I16, 8)));
		leaves.add (new NativeStructLeafChannel ("2", new NativeScalarAbiType (NativeScalarType.PTR)));
	}
	var plan = new NativeStructValuePlan (0, single ? "One" : "Outer", leaves, single ? NativeStructResultCarrier.SINGLE_LEAF : NativeStructResultCarrier.LEAF_AGGREGATE);
	var parameters = new GenericArray<NativeParameter> ();
	foreach (var leaf in leaves) {
		parameters.add (new NativeParameter.typed (s, s, "p%u".printf (parameters.length), parameters.length, leaf.abi_type));
	}
	var signature = new NativeSignature (version, parameters, null);
	signature.struct_parameters.add (new NativeStructParameterPlan (0, 0, plan));
	signature.struct_result = plan;
	var functions = new GenericArray<NativeFunction> ();
	functions.add (new NativeFunction (s, s, "identity", 0, signature, NativeLinkage.NATIVE_INTERNAL));
	var program = new NativeAbiProgram (s, version, functions);
	program.struct_values.add (plan);
	return program;
}
private void positive() {
	try {
		foreach (bool single in new bool[] {false, true}) {
			var p = sample (single);
			NativeAbiVerifier.verify (p);
			assert (p.functions[0].signature.physical_parameter_count == (single ? 1 : 4));
			assert (NativeAbiDump.format (p) == NativeAbiDump.format (sample (single)));
			assert (p.struct_values[0].result_carrier == (single ? NativeStructResultCarrier.SINGLE_LEAF : NativeStructResultCarrier.LEAF_AGGREGATE));
			assert (NativeAbiDump.format (p).contains ("aggregate-v7"));
		}
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
private void vector_matrix() {
	try {
		int count = 0;
		foreach (NativeScalarType element in new NativeScalarType[] {NativeScalarType.I8, NativeScalarType.U8, NativeScalarType.I16, NativeScalarType.U16, NativeScalarType.I32, NativeScalarType.U32, NativeScalarType.F32, NativeScalarType.B1}) {
			foreach (int lanes in new int[] {2, 4, 8, 16}) {
				int width = (element == NativeScalarType.I8 || element == NativeScalarType.U8) ? 8 : (element == NativeScalarType.I16 || element == NativeScalarType.U16) ? 16 : 32;
				if (element != NativeScalarType.B1 && width * lanes > 128) {
					continue;
				}
				var p = sample ();
				var plan = p.struct_values[0];
				plan.leaves[2] = new NativeStructLeafChannel ("1", new NativeVectorType (element, lanes));
				var f = p.functions[0];
				var old = f.signature.parameters[2];
				f.signature.parameters[2] = new NativeParameter.typed (old.span, old.name_span, old.name, 2, plan.leaves[2].abi_type);
				NativeAbiVerifier.verify (p);
				count++;
			}
		}
		assert (count == 24);
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
private void invalid() {
	try {
		for (int scenario = 0; scenario < 12; scenario++) {
			var p = sample (false, scenario == 0 ? NativeAbiVersion.FP64_V6 : NativeAbiVersion.AGGREGATE_V7);
			var plan = p.struct_values[0];
			var f = p.functions[0];
			var s = p.span;
			if (scenario == 1) {
				f.signature.parameters.remove_index (3);
			}
			if (scenario == 2) {
				plan.leaves[1] = new NativeStructLeafChannel ("0.0", plan.leaves[1].abi_type);
			}
			if (scenario == 3) {
				plan.leaves[0] = new NativeStructLeafChannel ("1.0", plan.leaves[0].abi_type);
			}
			if (scenario == 4) {
				plan.leaves[1] = new NativeStructLeafChannel ("0.2", plan.leaves[1].abi_type);
			}
			if (scenario == 5) {
				plan.leaves[1] = new NativeStructLeafChannel ("0.1", new NativeScalarAbiType (NativeScalarType.F32));
			}
			if (scenario == 6) {
				f.signature.struct_parameters[0] = new NativeStructParameterPlan (1, 0, plan);
			}
			if (scenario == 7) {
				f.signature.struct_parameters[0] = new NativeStructParameterPlan (0, 1, plan);
			}
			if (scenario == 8) {
				f.signature.struct_result = new NativeStructValuePlan (0, "Other", plan.leaves, plan.result_carrier);
			}
			if (scenario == 9) {
				p.struct_values.add (plan);
			}
			if (scenario == 10) {
				f.signature.parameters[0] = new NativeParameter.typed (s, s, "p0", 0, new NativeScalarAbiType (NativeScalarType.PTR));
			}
			if (scenario == 11) {
				var forged = new NativeStructValuePlan (0, "Outer", plan.leaves, NativeStructResultCarrier.SINGLE_LEAF);
				p.struct_values[0] = forged;
				f.signature.struct_result = forged;
				f.signature.struct_parameters[0] = new NativeStructParameterPlan (0, 0, forged);
			}
			bool rejected = false;
			try {
				NativeAbiVerifier.verify (p);
			} catch (NativeAbiError e) {
				rejected = true;
			}
			if (!rejected) {
				GLib.error ("accepted forged physical boundary %d", scenario);
			}
		}
	} catch (NativeAbiError e) {
		GLib.error ("%s", e.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/struct-abi/nabi/physical-only-nested-single-multi-deterministic-plans", positive);
	Test.add_func ("/struct-abi/nabi/v7-all-24-vector-mask-channels", vector_matrix);
	Test.add_func ("/struct-abi/nabi/profile-count-order-channel-nominal-carrier-firewalls", invalid);
	return Test.run ();
}
}
