// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.NativeAbi {
// Detached physical loan contract. It contains only primitive identities;
// no semantic, CFG or SSA node remains reachable from the native program.
public class NativeScopedBackingPlan : Object {
	public int block_ordinal { get; internal set; }
	public int position { get; internal set; }
	public int result_ordinal { get; internal set; }
	public int context_ordinal { get; internal set; }
	public int owner_ordinal { get; internal set; }
	public int backing_ordinal { get; internal set; }
	public int storage_ordinal { get; internal set; }
	public int base_ordinal { get; internal set; }
	public int length_ordinal { get; internal set; }
	public int region_ordinal { get; internal set; }
	private string handle_name_value;
	public string handle_name { get { return handle_name_value; } internal set { handle_name_value = value; } }
	private string kind_identity_value;
	public string kind_identity { get { return kind_identity_value; } internal set { kind_identity_value = value; } }
	private string slots_identity_value;
	public string slots_identity { get { return slots_identity_value; } internal set { slots_identity_value = value; } }
	public GenericArray<int> retirements { get; private set; default = new GenericArray<int> (); }
	private string origin;
	internal string identity() {
		var text = new StringBuilder ("scoped-backing/1;%d/%d/%d/%d/%d/%d/%d/%d/%d/%d;%s;%s;%s;scoped-affine;astra_context17_destroy;u8/PTR/I32;exclusive-until-context-drop".printf (block_ordinal, position, result_ordinal, context_ordinal, owner_ordinal, backing_ordinal, storage_ordinal, base_ordinal, length_ordinal, region_ordinal, handle_name, kind_identity, slots_identity));
		for (int i = 0; i < retirements.length; i++) {
			text.append_printf ("/%d", retirements[i]);
		}
		return text.str;
	}

	internal NativeScopedBackingPlan (int block, int position, int result, int context, int owner, int backing, int storage, int pointer, int length, int region, string name, string kind, string slots, GenericArray<int> retirements) {
		block_ordinal = block;
		this.position = position;
		result_ordinal = result;
		context_ordinal = context;
		owner_ordinal = owner;
		backing_ordinal = backing;
		storage_ordinal = storage;
		base_ordinal = pointer;
		length_ordinal = length;
		region_ordinal = region;
		handle_name = name;
		kind_identity = kind;
		slots_identity = slots;
		for (int i = 0; i < retirements.length; i++) {
			this.retirements.add (retirements[i]);
		}
		origin = identity ();
	}

	public bool valid() {
		if (origin != identity () || block_ordinal < 0 || position < 1 || result_ordinal < 0 || backing_ordinal < 0 || context_ordinal <= backing_ordinal || owner_ordinal < 0 || storage_ordinal < 0 || base_ordinal < 0 || length_ordinal != base_ordinal + 1 || region_ordinal < 0 || !Astra.Source.AllocationPolicy.identifier (handle_name, true) || kind_identity == "invalid" || slots_identity == "invalid" || retirements.length == 0 || retirements.length % 2 != 0) {
			return false;
		}
		for (int i = 0; i < retirements.length; i++) {
			if (retirements[i] < 0) {
				return false;
			}
		}
		return true;
	}

}
// Physical boundary metadata only. Unlike NativeSliceType, this complete
// pair transfers unique responsibility for static buffer deallocation.
public class NativeBufferValuePlan : Object {
	public NativeContextSliceType? context_origin { get; private set; }
	public NativeAbiType? element_type { get; private set; }
	public NativeRecordElement? record_element { get; private set; }
	public string element_spelling() {
		return (record_element == null ? element_type.spelling () : record_element.spelling ()) + (context_origin == null ? "" : ";origin=" + context_origin.spelling ());
	}

	internal NativeBufferValuePlan.for_record (NativeRecordElement element) {
		this.record_element = element;
	}
	public NativeScalarType base_type { get; private set; default = NativeScalarType.PTR; }
	public NativeScalarType length_type { get; private set; default = NativeScalarType.I32; }
	public bool transfers_ownership { get; private set; default = true; }
	internal NativeBufferValuePlan (NativeAbiType element_type, NativeContextSliceType? context_origin = null) {
		this.element_type = element_type;
		this.context_origin = context_origin;
	}

}
public class NativeBufferParameterPlan : Object {
	public int source_ordinal { get; private set; }
	public int first_leaf { get; private set; }
	public NativeBufferValuePlan value_plan { get; private set; }
	internal NativeBufferParameterPlan (int source_ordinal, int first_leaf, NativeBufferValuePlan value_plan) {
		this.source_ordinal = source_ordinal;
		this.first_leaf = first_leaf;
		this.value_plan = value_plan;
	}

}
}
