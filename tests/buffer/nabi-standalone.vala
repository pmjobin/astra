// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.NativeAbi;

namespace Astra.Tests.BufferNabi {
private NativeAbiProgram sample(int variant = 0) throws NativeAbiError {
	var span = SourceSpan(new SourceFile.from_text("buffer-nabi", "x"), 0, 1);
	var profile = variant == 1 ? NativeAbiVersion.AGGREGATE_V7 : variant == 2 ? NativeAbiVersion.SLICE_V5 : NativeAbiVersion.BUFFER_V8;
	var parameters = new GenericArray<NativeParameter>();
	NativeAbiType[] types = {
		new NativeScalarAbiType(NativeScalarType.I32), new NativeScalarAbiType(variant == 3 ? NativeScalarType.I32 : NativeScalarType.PTR), new NativeScalarAbiType(NativeScalarType.I32), new NativeSliceType(), new NativeScalarAbiType(NativeScalarType.PTR), new NativeScalarAbiType(NativeScalarType.I32)
	};
	for (int i = 0; i < types.length; i++) {
		parameters.add(new NativeParameter.typed(span, span, "p" + i.to_string(), i, types[i]));
	}
	var signature = new NativeSignature(profile, parameters, variant == 4 ? new NativeResult(NativeScalarType.PTR) : null);
	var plan = new NativeBufferValuePlan(variant == 5 ? (NativeAbiType) new NativeSliceType() : new NativeScalarAbiType(NativeScalarType.F64));
	signature.buffer_result = plan;
	signature.buffer_parameters.add(new NativeBufferParameterPlan(1, variant == 6 ? 2 : 1, plan));
	signature.buffer_parameters.add(new NativeBufferParameterPlan(3, variant == 7 ? 3 : 4, plan));
	signature.bind_buffer_transport();
	var function = new NativeFunction(span, span, "transfer", 0, signature, NativeLinkage.NATIVE_INTERNAL);
	var functions = new GenericArray<NativeFunction>();
	functions.add(function);
	return new NativeAbiProgram(span, profile, functions);
}

private void positive() {
	try {
		var program = sample();
		NativeAbiVerifier.verify(program);
		string dump = NativeAbiDump.format(program);
		assert(dump.contains("buffer-v8") && dump.contains("owned-transfer") && program.functions[0].signature.physical_parameter_count == 7);
	} catch (NativeAbiError error) {
		GLib.error("%s", error.message);
	}
}

private void negative() {
	for (int variant = 1; variant <= 7; variant++) {
		try {
			NativeAbiVerifier.verify(sample(variant));
		} catch (NativeAbiError error) {
			Test.message("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error("accepted malformed NABI buffer %d", variant);
	}
}

int main(string[] args) {
	Test.init(ref args);
	Test.add_func("/buffer/nabi/independent-owned-pairs-mixed-with-slice-and-scalar", positive);
	Test.add_func("/buffer/nabi/reject-old-profiles-partial-groups-and-result-collapse", negative);
	return Test.run();
}

}
