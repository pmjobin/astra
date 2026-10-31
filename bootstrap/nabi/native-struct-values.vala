// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.NativeAbi {
public class NativeStructLeafChannel : Object {
	private string path_identifier;
	public string field_path { get { return path_identifier; } }
	public NativeAbiType abi_type { get; private set; }
	private string storage_identifier;
	public string storage_path { get { return storage_identifier; } }
	public int buffer_component { get; private set; }
	internal NativeStructLeafChannel (string field_path, NativeAbiType abi_type, string? storage_path = null, int buffer_component = -1) {
		this.path_identifier = field_path;
		this.abi_type = abi_type;
		this.storage_identifier = storage_path ?? field_path;
		this.buffer_component = buffer_component;
	}
}

public enum NativeStructResultCarrier {
	SINGLE_LEAF, LEAF_AGGREGATE
}
public enum NativeStructValueMode {
	COPY_VALUE, MOVE_VALUE, BORROW_VALUE;
	internal bool matches_storage(NativeStructValuePlan plan) {
		return this == plan.mode || this == BORROW_VALUE && plan.mode == MOVE_VALUE;
	}
}

// Physical plan with a copied exact source declaration identity. It is neither
// a NativeAbiType channel nor an Astra semantic type. No upstream graph lives here.
public class NativeStructValuePlan : Object {
	public Astra.Source.ForeignValueType? foreign_record { get; private set; }
	private bool foreign_record_bound;
	internal void bind_foreign_record(Astra.Source.ForeignValueType? record) throws NativeAbiError {
		if (foreign_record_bound) {
			throw new NativeAbiError.INVALID_ABI ("native foreign record fields bind exactly once");
		}
		foreign_record = record;
		foreign_record_bound = true;
	}
	public NativeRecordDeclarationPlan? declaration { get; internal set; }
	public NativeStructValueMode mode { get; private set; }
	public GenericArray<NativeRecordResource> ownership { get; private set; }
	public uint ownership_field_count { get; private set; }
	public int struct_ordinal { get; private set; }
	private string identifier;
	public string struct_name { get { return identifier; } }
	public GenericArray<NativeStructLeafChannel> leaves { get; private set; }
	public uint leaf_count { get; private set; }
	public NativeStructResultCarrier result_carrier { get; private set; }
	internal NativeStructValuePlan (int struct_ordinal, string struct_name, GenericArray<NativeStructLeafChannel> leaves, NativeStructResultCarrier result_carrier, NativeStructValueMode mode = NativeStructValueMode.COPY_VALUE, GenericArray<NativeRecordResource>? ownership = null) {
		this.struct_ordinal = struct_ordinal;
		this.identifier = struct_name;
		this.leaves = leaves;
		this.result_carrier = result_carrier;
		this.leaf_count = leaves.length;
		this.mode = mode;
		this.ownership = ownership ?? new GenericArray<NativeRecordResource> ();
		this.ownership_field_count = this.ownership.length;
	}
}

public class NativeStructParameterPlan : Object {
	public int source_ordinal { get; private set; }
	public int first_leaf { get; private set; }
	public NativeStructValuePlan value_plan { get; private set; }
	public NativeStructValueMode mode { get; private set; }
	internal NativeStructParameterPlan (int source_ordinal, int first_leaf, NativeStructValuePlan value_plan, NativeStructValueMode? mode = null) {
		this.source_ordinal = source_ordinal;
		this.first_leaf = first_leaf;
		this.value_plan = value_plan;
		this.mode = mode ?? value_plan.mode;
	}
}

// Copied declaration facts survive independently of the SSA getter body.
public class NativeRecordObservation : Object {
	public int class_ordinal { get; private set; }
	public int field_ordinal { get; private set; }
	public NativeStructValuePlan value_plan { get; private set; }
	internal NativeRecordObservation (int owner, int field, NativeStructValuePlan value_plan) {
		class_ordinal = owner;
		field_ordinal = field;
		this.value_plan = value_plan;
	}
}
}
