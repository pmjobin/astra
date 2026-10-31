// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.NativeAbi;

namespace Astra.Tests.StructElementsNabi {
private NativeAbiProgram sample(int variant = 0) throws NativeAbiError {
	var s = SourceSpan (new SourceFile.from_text ("native-record", "x"), 0, 1);
	var fields = new GenericArray<NativeRecordField> ();
	fields.add (new NativeRecordField (0, "flag", new NativeScalarAbiType (NativeScalarType.B1)));
	fields.add (new NativeRecordField (variant == 1 ? 0 : 1, "mask", new NativeVectorType (NativeScalarType.B1, 4)));
	fields.add (new NativeRecordField (2, "weight", variant == 2 ? (NativeAbiType) new NativeSliceType () : new NativeScalarAbiType (NativeScalarType.F64)));
	var leaf = new NativeRecordElement (0, "Leaf", fields, variant != 3);
	var outer_fields = new GenericArray<NativeRecordField> ();
	outer_fields.add (new NativeRecordField (0, "left", null, leaf));
	outer_fields.add (new NativeRecordField (1, "right", null, leaf));
	var outer = new NativeRecordElement (1, "Outer", outer_fields);
	var parameters = new GenericArray<NativeParameter> ();
	parameters.add (new NativeParameter.typed (s, s, "view", 0, new NativeRecordSliceType (variant == 4 ? new NativeRecordElement (1, "Outer", outer_fields) : outer, NativeSliceAccess.READ_WRITE, variant != 5)));
	parameters.add (new NativeParameter.typed (s, s, "base", 1, new NativeScalarAbiType (NativeScalarType.PTR)));
	parameters.add (new NativeParameter.typed (s, s, "count", 2, new NativeScalarAbiType (NativeScalarType.I32)));
	var profile = variant == 6 ? NativeAbiVersion.TEXT_SLICE_V10 : NativeAbiVersion.STRUCT_ELEMENTS_V11;
	var signature = new NativeSignature (profile, parameters, null);
	var plan = new NativeBufferValuePlan.for_record (outer);
	signature.buffer_result = plan;
	signature.buffer_parameters.add (new NativeBufferParameterPlan (1, variant == 7 ? 2 : 1, plan));
	signature.bind_buffer_transport ();
	var functions = new GenericArray<NativeFunction> ();
	functions.add (new NativeFunction (s, s, "relay", 0, signature, NativeLinkage.NATIVE_INTERNAL));
	var program = new NativeAbiProgram (s, profile, functions);
	if (variant != 8) {
		program.record_elements.add (leaf);
	}
	program.record_elements.add (outer);
	if (variant == 9) {
		fields.add (new NativeRecordField (3, "missing", null));
	}
	return program;
}
private void qualify() {
	try {
		NativeAbiProgram? program = sample ();
		NativeAbiVerifier.verify (program);
		var layout = NativeRecordLayout.x86_64 (program.record_elements[0]);
		layout.verify_x86_64 ();
		assert (layout.stride == 16 && layout.alignment == 8 && layout.fields[0].offset == 0 && layout.fields[1].offset == 1 && layout.fields[1].size == 1 && layout.fields[2].offset == 8);
		var outer = NativeRecordLayout.x86_64 (program.record_elements[1]);
		assert (outer.stride == 32 && outer.fields[1].offset == 16);
		assert (outer.fits_count (NativeRecordLayout.MAX_EXTENT / 32) && !outer.fits_count (NativeRecordLayout.MAX_EXTENT / 32 + 1));
		for (int variant = 0; variant < 6; variant++) {
			var fields = new GenericArray<NativeRecordFieldLayout> ();
			foreach (var field in layout.fields) {
				fields.add (field);
			}
			if (variant >= 2) {
				var f = fields[1];
				fields[1] = new NativeRecordFieldLayout (variant == 2 ? fields[0].field : f.field, variant == 3 ? 2 : f.offset, variant == 4 ? 2 : f.size, variant == 5 ? 2 : f.alignment);
			}
			var forged = new NativeRecordLayout (layout.element, variant == 0 ? 9 : layout.stride, variant == 1 ? 4 : layout.alignment, fields);
			bool rejected = false;
			try {
				forged.verify_x86_64 ();
			} catch (NativeAbiError error) {
				rejected = true;
			}
			assert (rejected);
		}
		var function = WeakRef (program.functions[0]);
		program = null;
		assert (function.get () == null);
		outer.verify_x86_64 ();
	} catch (NativeAbiError error) {
		GLib.error ("%s", error.message);
	}
	for (int variant = 1; variant <= 9; variant++) {
		bool rejected = false;
		try {
			NativeAbiVerifier.verify (sample (variant));
		} catch (NativeAbiError error) {
			Test.message ("variant %d: %s", variant, error.message);
			rejected = true;
		}
		assert (rejected);
	}
	var cyclic_fields = new GenericArray<NativeRecordField> ();
	var cyclic = new NativeRecordElement (0, "Cycle", cyclic_fields);
	cyclic_fields.add (new NativeRecordField (0, "cycle", null, cyclic));
	bool rejected = false;
	try {
		NativeRecordLayout.x86_64 (cyclic);
	} catch (NativeAbiError error) {
		rejected = true;
	}
	cyclic_fields.remove_index (0);
	assert (rejected);
	var leaf_fields = new GenericArray<NativeRecordField> ();
	leaf_fields.add (new NativeRecordField (0, "value", new NativeScalarAbiType (NativeScalarType.F64)));
	var huge = new NativeRecordElement (0, "Leaf", leaf_fields);
	for (int i = 1; i < 64; i++) {
		var fields = new GenericArray<NativeRecordField> ();
		fields.add (new NativeRecordField (0, "left", null, huge));
		fields.add (new NativeRecordField (1, "right", null, huge));
		huge = new NativeRecordElement (i, "Shared%d".printf (i), fields);
	}
	rejected = false;
	try {
		NativeRecordLayout.x86_64 (huge);
	} catch (NativeAbiError error) {
		rejected = true;
	}
	assert (rejected);
	try {
		assert (NativeRecordLayout.x86_64 (new NativeRecordElement (0, "Leaf", leaf_fields)).stride == 8);
	} catch (NativeAbiError error) {
		GLib.error ("%s", error.message);
	}
}
public int run_nabi(string[] args) {
	Test.init (ref args);
	Test.add_func ("/struct-elements/nabi/independent-plans-physical-layout-and-malformed-models", qualify);
	return Test.run ();
}
}
