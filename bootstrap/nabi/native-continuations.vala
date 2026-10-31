// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Continuations;

namespace Astra.NativeAbi {
public enum NativeContinuationConvention {
	GENERATED_FAST, FOREIGN_C
}

public class NativeContinuationEnvironment : Object {
	public ContinuationIdentity identity { get; private set; }
	public NativeRecordElement storage { get; private set; }
	public NativeRecordElement? state_record { get; private set; }
	public GenericArray<NativeStructLeafChannel> leaves { get; private set; }
	public NativeBufferValuePlan? buffer { get; private set; }
	public bool stable { get; private set; }
	internal NativeContinuationEnvironment (ContinuationIdentity identity, NativeRecordElement storage, NativeRecordElement? state_record, GenericArray<NativeStructLeafChannel> leaves, NativeBufferValuePlan? buffer, bool stable) {
		this.identity = identity;
		this.storage = storage;
		this.state_record = state_record;
		this.leaves = leaves;
		this.buffer = buffer;
		this.stable = stable;
	}
}

public class NativeContinuationEntry : Object {
	public ContinuationIdentity identity { get; private set; }
	public ContinuationRole role { get; private set; }
	public ContinuationIdentity? environment { get; private set; }
	public int target_ordinal { get; private set; }
	public NativeSignature? body_signature { get; private set; }
	public NativeContinuationConvention convention { get; private set; }
	internal NativeContinuationEntry (ContinuationIdentity identity, ContinuationRole role, ContinuationIdentity? environment, int target_ordinal, NativeSignature? signature, NativeContinuationConvention convention = NativeContinuationConvention.GENERATED_FAST) {
		this.identity = identity;
		this.role = role;
		this.environment = environment;
		this.target_ordinal = target_ordinal;
		this.body_signature = signature;
		this.convention = convention;
	}
}

public class NativeContinuationFamily : Object {
	public ContinuationIdentity identity { get; private set; }
	public NativeContinuationEnvironment? environment { get; private set; }
	public GenericArray<NativeContinuationEntry> entries { get; private set; }
	public NativeContinuationEntry? destroy { get; private set; }
	public bool repeat_step { get; private set; }
	internal NativeContinuationFamily (ContinuationIdentity identity, NativeContinuationEnvironment? environment, GenericArray<NativeContinuationEntry> entries, NativeContinuationEntry? destroy, bool repeat_step) {
		this.identity = identity;
		this.environment = environment;
		this.entries = entries;
		this.destroy = destroy;
		this.repeat_step = repeat_step;
	}
}

private class NativeContinuationUse : Object {
	internal int family;
	internal int instance;
	internal int phase;
	internal int active = -1;
	internal int retention;
	internal bool called;
	internal int calls;
	internal NativeContinuationUse (int family, int instance, int phase) {
		this.family = family;
		this.instance = instance;
		this.phase = phase;
	}
}

// Complete independently retained region plan. No SSA/function/body graph.
public class NativeContinuationRegionPlan : Object {
	public NativeRecordElement descriptor_storage { get; private set; }
	public ContinuationIdentity identity { get; private set; }
	public int function_ordinal { get; private set; }
	public int block_ordinal { get; private set; }
	public int position { get; private set; }
	public GenericArray<NativeAbiType> operands { get; private set; }
	public GenericArray<NativeContinuationFamily> families { get; private set; }
	public GenericArray<ContinuationAction> actions { get; private set; }
	internal NativeContinuationRegionPlan (ContinuationIdentity identity, int function_ordinal, int block_ordinal, int position, GenericArray<NativeAbiType> operands, GenericArray<NativeContinuationFamily> families, GenericArray<ContinuationAction> actions) {
		this.identity = identity;
		this.function_ordinal = function_ordinal;
		this.block_ordinal = block_ordinal;
		this.position = position;
		this.operands = operands;
		this.families = families;
		this.actions = actions;
		var fields = new GenericArray<NativeRecordField> ();
		string[] roles = {
			"step", "cancel-drain", "destroy", "environment"
		};
		for (int i = 0; i < roles.length; i++) {
			fields.add (new NativeRecordField (i, roles[i], new NativeScalarAbiType (NativeScalarType.PTR)));
		}
		descriptor_storage = new NativeRecordElement (-1, "generated continuation descriptor", fields);
	}
	private static void check(bool condition, string reason) throws NativeAbiError {
		if (!condition) {
			throw new NativeAbiError.INVALID_ABI ("internal continuation plan: %s", reason);
		}
	}
	private bool operand_is(int index, NativeScalarType type) {
		return index >= 0 && index < operands.length && operands[index].same_type (new NativeScalarAbiType (type));
	}
	private static void walk(NativeRecordElement record, string prefix, GenericArray<NativeStructLeafChannel> leaves) {
		foreach (var field in record.fields) {
			string path = prefix + "." + field.ordinal.to_string ();
			if (field.record != null) {
				walk (field.record, path, leaves);
			} else {
				leaves.add (new NativeStructLeafChannel (path, field.leaf));
			}
		}
	}
	private static void verify_environment(NativeContinuationEnvironment env) throws NativeAbiError {
		check (env.stable && env.storage.fields.length == (env.buffer == null ? 1 : 3), "stable concrete environment layout required");
		NativeRecordLayout.x86_64 (env.storage).verify_x86_64 ();
		var fields = env.storage.fields;
		check (fields[0].record == env.state_record, "wrong memory state association");
		var expected = new GenericArray<NativeStructLeafChannel> ();
		if (env.state_record == null) {
			check (fields[0].leaf != null && fields[0].leaf.same_type (new NativeScalarAbiType (NativeScalarType.I32)), "scalar environment state signature mismatch");
			expected.add (new NativeStructLeafChannel ("0", fields[0].leaf));
		} else {
			walk (env.state_record, "0", expected);
		}
		check (env.leaves.length == expected.length && env.leaves.length > 0 && env.leaves[0].abi_type.same_type (new NativeScalarAbiType (NativeScalarType.I32)), "state leaf signature mismatch");
		for (int i = 0; i < expected.length; i++) {
			check (env.leaves[i].field_path == expected[i].field_path && env.leaves[i].abi_type.same_type (expected[i].abi_type), "memory/channel state correspondence mismatch");
		}
		if (env.buffer != null) {
			check (env.buffer.transfers_ownership && env.buffer.record_element == null && env.buffer.element_type != null && env.buffer.element_type.same_type (new NativeScalarAbiType (NativeScalarType.I32)) && fields[1].leaf != null && fields[2].leaf != null && fields[1].leaf.same_type (new NativeScalarAbiType (NativeScalarType.PTR)) && fields[2].leaf.same_type (new NativeScalarAbiType (NativeScalarType.I32)), "missing concrete buffer destruction authority");
		}
	}
	private static void verify_entry(NativeContinuationEntry entry, NativeContinuationEnvironment? env, bool destroy) throws NativeAbiError {
		check (entry.convention == NativeContinuationConvention.GENERATED_FAST, "calling convention mismatch");
		check (entry.environment == (env == null ? null : env.identity), "wrong operation environment association");
		if (destroy) {
			check (entry.role == ContinuationRole.DESTROY && entry.target_ordinal == -1 && entry.body_signature == null, "missing exact generated destruction authority");
			return;
		}
		check ((entry.role == ContinuationRole.STEP || entry.role == ContinuationRole.CANCEL_DRAIN) && entry.target_ordinal >= 0 && entry.body_signature != null, "wrong generated operation role or code");
		var signature = entry.body_signature;
		NativeAbiVerifier.verify_detached_signature (signature, "continuation/signature");
		int leaves = env == null ? 0 : (int) env.leaves.length;
		bool buffer = env != null && env.buffer != null;
		check (signature.receiver == null && signature.object_result == null && signature.buffer_result == null && signature.buffer_parameters.length == 0 && signature.parameters.length == leaves + 1 + (buffer ? 1 : 0), "body signature or ownership mismatch");
		for (int i = 0; i < leaves; i++) {
			check (signature.parameters[i].abi_type.same_type (env.leaves[i].abi_type), "snapshot parameter signature mismatch");
		}
		check (signature.parameters[leaves].abi_type.same_type (new NativeScalarAbiType (NativeScalarType.I32)), "argument signature mismatch");
		if (buffer) {
			check (signature.parameters[leaves + 1].abi_type is NativeSliceType && !(signature.parameters[leaves + 1].abi_type is NativeTextSliceType) && !(signature.parameters[leaves + 1].abi_type is NativeRecordSliceType), "bounded buffer signature mismatch");
		}
		if (env == null || env.state_record == null) {
			check (signature.struct_result == null && signature.result != null && signature.result.abi_type.same_type (new NativeScalarAbiType (NativeScalarType.I32)), "scalar result signature mismatch");
		} else {
			check (signature.result == null && signature.struct_result != null && signature.struct_parameters.length == 1 && signature.struct_result.struct_ordinal == env.state_record.struct_ordinal && signature.struct_parameters[0].first_leaf == 0 && signature.struct_parameters[0].value_plan == signature.struct_result && signature.struct_result.leaves.length == leaves, "record result signature mismatch");
			for (int i = 0; i < leaves; i++) {
				check ("0." + signature.struct_result.leaves[i].field_path == env.leaves[i].field_path && signature.struct_result.leaves[i].abi_type.same_type (env.leaves[i].abi_type), "record result memory correspondence mismatch");
			}
		}
	}
	public void verify() throws NativeAbiError {
		check (descriptor_storage.fields.length == 4 && descriptor_storage.natural_layout && descriptor_storage.trivial_destruction && descriptor_storage.structural_zero, "invalid descriptor storage contract");
		string[] roles = {
			"step", "cancel-drain", "destroy", "environment"
		};
		for (int i = 0; i < roles.length; i++) {
			var field = descriptor_storage.fields[i];
			check (field.ordinal == i && field.name == roles[i] && field.record == null && field.leaf != null && field.leaf.same_type (new NativeScalarAbiType (NativeScalarType.PTR)), "descriptor code/environment role or layout mismatch");
		}
		var descriptor_layout = NativeRecordLayout.x86_64 (descriptor_storage);
		check (descriptor_layout.stride == 32 && descriptor_layout.alignment == 8, "unqualified descriptor pointer layout");
		check (function_ordinal >= 0 && block_ordinal >= 0 && position >= 0 && families.length > 0, "invalid region identity/location");
		var identities = new HashTable<ContinuationIdentity, bool> (direct_hash, direct_equal);
		foreach (var family in families) {
			check (!identities.contains (family.identity), "duplicate family authority");
			identities.insert (family.identity, true);
			if (family.environment != null) {
				verify_environment (family.environment);
			}
			check (family.destroy != null, "missing destruction authority");
			verify_entry (family.destroy, family.environment, true);
			check (!identities.contains (family.destroy.identity), "duplicate destruction authority");
			identities.insert (family.destroy.identity, true);
			bool step = false;
			bool cancel = false;
			foreach (var entry in family.entries) {
				verify_entry (entry, family.environment, false);
				check (!identities.contains (entry.identity), "duplicate operation identity");
				identities.insert (entry.identity, true);
				step |= entry.role == ContinuationRole.STEP;
				cancel |= entry.role == ContinuationRole.CANCEL_DRAIN;
			}
			check (step && cancel, "missing step/cancel operation family");
		}
		// Independent physical-plan flow checker: phases 0 building, 1 initialized,
		// 2 published, 3 consumed. No caller-supplied safe-to-free premise.
		var slots = new HashTable<int, NativeContinuationUse> (direct_hash, direct_equal);
		var instances = new HashTable<int, bool> (direct_hash, direct_equal);
		var obligations = new HashTable<int, NativeContinuationUse> (direct_hash, direct_equal);
		var history = new HashTable<int, bool> (direct_hash, direct_equal);
		bool result = false;
		foreach (var action in actions) {
			if (action.kind == ContinuationActionKind.CREATE) {
				check (action.owner >= 0 && !slots.contains (action.owner), "duplicate owning descriptor");
				check (action.family >= 0 && action.family < families.length, "wrong operation family");
				check (action.instance >= 0 && !instances.contains (action.instance), "duplicate environment authority");
				instances.insert (action.instance, true);
				slots.insert (action.owner, new NativeContinuationUse (action.family, action.instance, families[action.family].environment == null ? 1 : 0));
				continue;
			}
			var slot = slots.lookup (action.owner);
			check (slot != null && slot.phase < 3, "use after authority consumption");
			var family = families[slot.family];
			var env = family.environment;
			switch (action.kind) {
			case ContinuationActionKind.INITIALIZE:
				check (slot.phase == 0 && env != null && action.capture_count == env.leaves.length, "missing or duplicate initialization");
				for (int i = 0; i < action.capture_count; i++) {
					int operand = action.capture (i);
					check (operand >= 0 && operand < operands.length && operands[operand].same_type (env.leaves[i].abi_type), "capture signature mismatch");
				}
				if (env.buffer != null) {
					check (operand_is (action.operand, NativeScalarType.I32), "buffer initialization signature mismatch");
				}
				slot.phase = 1;
				break;
			case ContinuationActionKind.PUBLISH:
				check (slot.phase == 1, "publication before initialization");
				check (action.first_entry >= 0 && action.second_entry >= 0 && action.first_entry < family.entries.length && action.second_entry < family.entries.length && family.entries[action.first_entry].role == ContinuationRole.STEP && family.entries[action.second_entry].role == ContinuationRole.STEP, "wrong selected operation role/family");
				check (operand_is (action.operand, NativeScalarType.B1), "selection signature mismatch");
				slot.phase = 2;
				break;
			case ContinuationActionKind.MOVE:
				check (slot.phase == 2 && slot.active < 0 && slot.retention == 0, "move overlaps invocation/retention");
				check (action.destination >= 0 && !slots.contains (action.destination), "duplicated move authority");
				var moved = new NativeContinuationUse (slot.family, slot.instance, 2);
				moved.calls = slot.calls;
				slots.insert (action.destination, moved);
				slot.phase = 3;
				break;
			case ContinuationActionKind.RETAIN: case ContinuationActionKind.BEGIN:
				check (slot.phase == 2 && action.witness >= 0 && !history.contains (action.witness), "invalid retention/invocation witness");
				if (action.kind == ContinuationActionKind.BEGIN) {
					check (slot.active < 0, "overlapping/reentrant invocation");
					slot.active = action.witness;
					slot.called = false;
				} else {
					slot.retention++;
				}
				obligations.insert (action.witness, slot);
				history.insert (action.witness, true);
				break;
			case ContinuationActionKind.CALL:
				check (slot.phase == 2 && slot.active == action.witness && !slot.called && obligations.lookup (action.witness) == slot, "missing active invocation authority");
				check (action.role == ContinuationRole.STEP || action.role == ContinuationRole.CANCEL_DRAIN, "wrong invocation role");
				check (operand_is (action.operand, NativeScalarType.I32), "invocation signature mismatch");
				check (slot.calls == 0 || family.repeat_step || action.role != ContinuationRole.STEP, "repeat permission mismatch");
				slot.called = true;
				if (action.role == ContinuationRole.STEP) {
					slot.calls++;
				}
				result = true;
				break;
			case ContinuationActionKind.END: case ContinuationActionKind.RELEASE:
				check (obligations.lookup (action.witness) == slot, "wrong environment retention association");
				if (action.kind == ContinuationActionKind.END) {
					check (slot.active == action.witness && slot.called, "incomplete invocation retirement");
					slot.active = -1;
				} else {
					check (slot.active != action.witness && slot.retention > 0, "wrong retention role");
					slot.retention--;
				} obligations.remove (action.witness);
				break;
			case ContinuationActionKind.DESTROY:
				check (slot.phase == 2 && slot.active < 0 && slot.retention == 0, "unretired destruction context");
				slot.phase = 3;
				break;
			default:
				check (false, "unknown schedule operation");
				break;
			}
		}
		foreach (var slot in slots.get_values ()) {
			check (slot.phase == 3, "missing cleanup authority consumer");
		}
		check (result && obligations.size () == 0, "unretired region/result");
	}
}
}
