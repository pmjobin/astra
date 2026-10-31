// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.NativeAbi {
public enum NativeSumRole {
	SNAPSHOT_READONLY, RESULT_CALLER_STORAGE, OWNED_TRANSFER, OWNED_RESULT_STORAGE
}
// Nominal identity survives pointer erasure. The completed plan retains no
// semantic definition, SSA producer, function body, or backend object.
public class NativeSumType : NativeAbiType {
	public EnumIdentity identity { get; private set; }
	public NativeSumRole role { get; private set; }
	public NativeScalarType channel { get; private set; }
	internal NativeSumType (EnumIdentity identity, NativeSumRole role = NativeSumRole.SNAPSHOT_READONLY, NativeScalarType channel = NativeScalarType.PTR) {
		this.identity = identity;
		this.role = role;
		this.channel = channel;
	}
	public override string spelling() {
		return "SUM(%s,%s,%s)".printf (identity.name, channel.spelling (), role == NativeSumRole.SNAPSHOT_READONLY ? "snapshot" : role == NativeSumRole.OWNED_TRANSFER ? "owned-transfer" : role == NativeSumRole.OWNED_RESULT_STORAGE ? "owned-result" : "caller-result");
	}
	public override bool same_type(NativeAbiType other) {
		return other is NativeSumType && ((NativeSumType) other).identity == identity && ((NativeSumType) other).role == role && ((NativeSumType) other).channel == channel;
	}
}

// Exact scalar ownership survives erasure to PTR without retaining semantic
// types, cleanup contracts, or upstream function graphs.
public class NativeScalarOwner : Object {
	private string type_identifier;
	private string destructor_symbol;
	public string type_name { get { return type_identifier; } }
	public string cleanup_symbol { get { return destructor_symbol; } }
	public int class_ordinal { get; private set; }
	internal NativeScalarOwner (string type_name, string cleanup_symbol, int class_ordinal = -1) {
		this.type_identifier = type_name;
		this.destructor_symbol = cleanup_symbol;
		this.class_ordinal = class_ordinal;
	}
	public bool same_owner(NativeScalarOwner? other) {
		return other != null && type_name == other.type_name && cleanup_symbol == other.cleanup_symbol && class_ordinal == other.class_ordinal;
	}
}

public class NativeSumField : Object {
	public NativeStructValuePlan? record_value { get; private set; }
	public NativeScalarOwner? scalar_owner { get; private set; }
	public EnumFieldIdentity identity { get; private set; }
	public NativeBufferValuePlan? buffer { get; private set; }
	public NativeAbiType? leaf { get; private set; }
	public NativeRecordElement? record { get; private set; }
	public NativeSumPlan? sum { get; private set; }
	internal NativeSumField (EnumFieldIdentity identity, NativeAbiType? leaf, NativeRecordElement? record, NativeSumPlan? sum, NativeBufferValuePlan? buffer = null, NativeScalarOwner? scalar_owner = null, NativeStructValuePlan? record_value = null) {
		this.identity = identity;
		this.leaf = leaf;
		this.record = record;
		this.sum = sum;
		this.buffer = buffer;
		this.scalar_owner = scalar_owner;
		this.record_value = record_value;
	}
}

public class NativeSumVariant : Object {
	private GenericArray<NativeSumField> original_fields = new GenericArray<NativeSumField> ();
	public EnumVariantIdentity identity { get; private set; }
	public GenericArray<NativeSumField> fields { get; private set; }
	internal NativeSumVariant (EnumVariantIdentity identity, GenericArray<NativeSumField> fields) {
		this.identity = identity;
		this.fields = fields;
		foreach (var field in fields) {
			original_fields.add (field);
		}
	}
	internal bool matches_fields() {
		if (fields.length != original_fields.length) {
			return false;
		}
		for (int i = 0; i < fields.length; i++) {
			var original = original_fields[i];
			var actual = fields[i];
			if (original.record_value != actual.record_value) {
				return false;
			}
			if ((original.scalar_owner == null) != (actual.scalar_owner == null)) {
				return false;
			}
			if (original.scalar_owner == null) {
				continue;
			}
			var expected = original.scalar_owner;
			var supplied = actual.scalar_owner;
			if (actual.identity != original.identity || expected.type_name != supplied.type_name || expected.cleanup_symbol != supplied.cleanup_symbol || expected.class_ordinal != supplied.class_ordinal || actual.leaf == null || !actual.leaf.same_type (original.leaf)) {
				return false;
			}
		}
		return true;
	}
}

public class NativeSumPlan : Object {
	private GenericArray<NativeSumVariant> original_variants = new GenericArray<NativeSumVariant> ();
	public bool owning {
		get {
			foreach (var variant in variants) {
				foreach (var field in variant.fields) {
					if (field.record_value != null || field.scalar_owner != null || field.buffer != null || (field.sum != null && field.sum.owning)) {
						return true;
					}
				}
			}
			return false;
		}
	}
	public EnumIdentity identity { get; private set; }
	public GenericArray<NativeSumVariant> variants { get; private set; }
	internal NativeSumPlan (EnumIdentity identity, GenericArray<NativeSumVariant> variants) {
		this.identity = identity;
		this.variants = variants;
		foreach (var variant in variants) {
			original_variants.add (variant);
		}
	}
	internal bool matches_variants() {
		if (variants.length != original_variants.length) {
			return false;
		}
		for (int i = 0; i < variants.length; i++) {
			if (variants[i] != original_variants[i]) {
				return false;
			}
		}
		return true;
	}
}

internal class NativeSumVerifier : Object {
	private static void visit(NativeSumPlan plan, HashTable<EnumIdentity, NativeSumPlan> plans, HashTable<NativeSumPlan, int> state, NativeAbiProgram program) throws NativeAbiError {
		if (state.lookup (plan) == 2) {
			return;
		}
		if (state.lookup (plan) == 1 || plan.variants.length == 0 || !plan.matches_variants ()) {
			throw new NativeAbiError.INVALID_ABI ("sum storage requires an acyclic complete original nominal graph");
		}
		state.insert (plan, 1);
		var names = new HashTable<string, bool> (str_hash, str_equal);
		for (int v = 0; v < plan.variants.length; v++) {
			var variant = plan.variants[v];
			if (!variant.matches_fields () || variant.identity.enumeration != plan.identity || variant.identity.ordinal != v || variant.identity.name == "" || names.contains (variant.identity.name)) {
				throw new NativeAbiError.INVALID_ABI ("sum variant identity/order or original field responsibility mismatch");
			}
			names.insert (variant.identity.name, true);
			var fields = new HashTable<string, bool> (str_hash, str_equal);
			for (int f = 0; f < variant.fields.length; f++) {
				var field = variant.fields[f];
				if (field.identity.variant != variant.identity || field.identity.ordinal != f || field.identity.name == "" || fields.contains (field.identity.name) || (field.leaf == null ? 0 : 1) + (field.record == null ? 0 : 1) + (field.sum == null ? 0 : 1) + (field.buffer == null ? 0 : 1) + (field.record_value == null ? 0 : 1) != 1) {
					throw new NativeAbiError.INVALID_ABI ("sum field identity or complete channel mismatch");
				}
				fields.insert (field.identity.name, true);
				if (field.record_value != null && (field.record_value.mode != NativeStructValueMode.MOVE_VALUE || !program.struct_values.find (field.record_value))) {
					throw new NativeAbiError.INVALID_ABI ("owning enum record requires its exact program-owned complete value and cleanup plan");
				}
				if (field.scalar_owner != null) {
					var owner = field.scalar_owner;
					var leaf = field.leaf as NativeScalarAbiType;
					if (owner.type_name == "" || leaf == null || leaf.scalar_type != NativeScalarType.PTR || field.buffer != null || field.sum != null || field.record != null || owner.class_ordinal < -1) {
						throw new NativeAbiError.INVALID_ABI ("owned scalar sum field requires its exact nominal PTR authority");
					}
					if (owner.class_ordinal == -1) {
						if (owner.cleanup_symbol == "") {
							throw new NativeAbiError.INVALID_ABI ("owned Resource sum field lost its original foreign destructor");
						}
					} else if (owner.class_ordinal >= program.classes.length || program.classes[owner.class_ordinal].name != owner.type_name || program.classes[owner.class_ordinal].polymorphic || program.classes[owner.class_ordinal].is_interface || owner.cleanup_symbol != "") {
						throw new NativeAbiError.INVALID_ABI ("owned Class sum field lost its exact concrete heap authority");
					}
				}
				if (field.buffer != null) {
					NativeAbiVerifier.verify_buffer_plan (field.buffer, NativeAbiVersion.OWNED_SUMS_V13, "owned sum payload");
					if (field.buffer.record_element != null) {
						bool present = false;
						foreach (var record in program.record_elements) {
							if (record == field.buffer.record_element) {
								present = true;
							}
						}
						if (!present) {
							throw new NativeAbiError.INVALID_ABI ("owned sum record buffer requires its exact retained record");
						}
					}
				}
				if (field.sum != null) {
					if (plans.lookup (field.sum.identity) != field.sum) {
						throw new NativeAbiError.INVALID_ABI ("nested sum plan lost nominal association");
					}
					visit (field.sum, plans, state, program);
				}
				if (field.record != null) {
					bool present = false;
					foreach (var record in program.record_elements) {
						if (record == field.record) {
							present = true;
						}
					}
					if (!present) {
						throw new NativeAbiError.INVALID_ABI ("sum record field requires a retained exact storage plan");
					}
				}
				if (field.leaf != null) {
					if (!(field.leaf is NativeScalarAbiType || field.leaf is NativeVectorType)) {
						throw new NativeAbiError.INVALID_ABI ("sum field requires concrete scalar/vector or nominal storage");
					}
					NativeAbiVerifier.verify_detached_signature (new NativeSignature (NativeAbiVersion.SUM_VALUES_V12, new GenericArray<NativeParameter> (), new NativeResult.typed (field.leaf)), "sum payload");
				}
			}
		}
		state.insert (plan, 2);
	}

	internal static void verify(NativeAbiProgram program) throws NativeAbiError {
		var plans = new HashTable<EnumIdentity, NativeSumPlan> (direct_hash, direct_equal);
		foreach (var plan in program.sum_values) {
			if ((program.abi_version != NativeAbiVersion.SUM_VALUES_V12 && program.abi_version != NativeAbiVersion.OWNED_SUMS_V13 && program.abi_version != NativeAbiVersion.NATIVE_EXCEPTIONS_V14 && program.abi_version != NativeAbiVersion.OWNER_SLOTS_V15) || plan.identity.name == "" || plans.contains (plan.identity)) {
				throw new NativeAbiError.INVALID_ABI ("sum values require unique exact nominal plans and sum-values-v12");
			}
			plans.insert (plan.identity, plan);
		}
		var state = new HashTable<NativeSumPlan, int> (direct_hash, direct_equal);
		foreach (var plan in program.sum_values) {
			visit (plan, plans, state, program);
		}
		foreach (var plan in program.sum_values) {
			if (plan.owning && program.abi_version != NativeAbiVersion.OWNED_SUMS_V13 && program.abi_version != NativeAbiVersion.NATIVE_EXCEPTIONS_V14 && program.abi_version != NativeAbiVersion.OWNER_SLOTS_V15) {
				throw new NativeAbiError.INVALID_ABI ("owning sum plans require owned-sums-v13");
			}
		}
		foreach (var function in program.functions) {
			var signature = function.signature;
			if (signature.sum_result != null && (!plans.contains (signature.sum_result.identity) || (plans.lookup (signature.sum_result.identity).owning ? signature.sum_result.role != NativeSumRole.OWNED_RESULT_STORAGE : signature.sum_result.role != NativeSumRole.RESULT_CALLER_STORAGE))) {
				throw new NativeAbiError.INVALID_ABI ("sum result lacks its nominal storage plan");
			}
			foreach (var parameter in signature.parameters) {
				var sum = parameter.abi_type as NativeSumType;
				if (sum != null && (!plans.contains (sum.identity) || (plans.lookup (sum.identity).owning ? sum.role != NativeSumRole.OWNED_TRANSFER : sum.role != NativeSumRole.SNAPSHOT_READONLY))) {
					throw new NativeAbiError.INVALID_ABI ("sum parameter lacks its nominal storage plan");
				}
			}
		}
	}
}
}
