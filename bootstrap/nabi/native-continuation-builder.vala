// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Ssa;
using Astra.Semantic;
using Astra.Continuations;

namespace Astra.NativeAbi {
public class NativeContinuationBuilder : Object {
	private static NativeRecordElement record(SsaProgram source, SemanticType type) throws NativeAbiError {
		for (int i = 0; i < source.structs.length; i++) {
			var structure = source.structs[i];
			if (structure.semantic_type != type) {
				continue;
			}
			var fields = new GenericArray<NativeRecordField> ();
			foreach (var field in structure.fields) {
				var child = (field.semantic_type is StructType) ? record (source, field.semantic_type) : null;
				fields.add (new NativeRecordField (field.ordinal, field.name, child == null ? NativeTypeMapper.map_type (field.semantic_type) : null, child));
			}
			return new NativeRecordElement (i, structure.name, fields);
		}
		throw new NativeAbiError.INVALID_SSA ("continuation requires exact state record membership");
	}
	public static NativeContinuationRegionPlan build(SsaProgram source, NativeAbiProgram native, int function, int block, int position) throws NativeAbiError {
		if (function < 0 || function >= source.functions.length || block < 0 || block >= source.functions[function].blocks.length || position < 0 || position >= source.functions[function].blocks[block].instructions.length) {
			throw new NativeAbiError.INVALID_SSA ("continuation region has stale executable membership");
		}
		var region = source.functions[function].blocks[block].instructions[position] as SsaContinuationRegion;
		if (region == null) {
			throw new NativeAbiError.INVALID_SSA ("continuation plan requires an exact generated region");
		}
		try {
			SsaContinuationVerifier.verify (region, source.functions, source.structs, source.cleanups);
		} catch (SsaError error) {
			throw new NativeAbiError.INVALID_SSA ("%s", error.message);
		}
		var operands = new GenericArray<NativeAbiType> ();
		foreach (var operand in region.operands) {
			operands.add (NativeTypeMapper.map_type (operand.semantic_type));
		}
		var families = new GenericArray<NativeContinuationFamily> ();
		foreach (var family in region.families) {
			NativeContinuationEnvironment? env = null;
			var source_env = family.environment;
			if (source_env != null) {
				var state = source_env.record_shape == null ? null : record (source, source_env.state_type);
				var fields = new GenericArray<NativeRecordField> ();
				fields.add (new NativeRecordField (0, "state", state == null ? NativeTypeMapper.map_type (source_env.state_type) : null, state));
				NativeBufferValuePlan? buffer = null;
				if (source_env.buffer_cleanup != null) {
					buffer = new NativeBufferValuePlan (NativeTypeMapper.map_type (source_env.buffer_cleanup.buffer_type.element_type));
					fields.add (new NativeRecordField (1, "buffer", new NativeScalarAbiType (NativeScalarType.PTR)));
					fields.add (new NativeRecordField (2, "count", new NativeScalarAbiType (NativeScalarType.I32)));
				}
				var leaves = new GenericArray<NativeStructLeafChannel> ();
				for (int i = 0; i < source_env.leaf_count; i++) {
					leaves.add (new NativeStructLeafChannel (state == null ? "0" : "0." + source_env.record_shape.leaves[i].spelling (), NativeTypeMapper.map_type (source_env.leaf_type (i))));
				}
				env = new NativeContinuationEnvironment (source_env.identity, new NativeRecordElement (-1, "generated environment", fields), state, leaves, buffer, source_env.stable);
			}
			var entries = new GenericArray<NativeContinuationEntry> ();
			foreach (var entry in family.entries) {
				var target = entry.target;
				entries.add (new NativeContinuationEntry (entry.identity, entry.role, env == null ? null : env.identity, target.ordinal, native.functions[target.ordinal].signature));
			}
			var destroy = new NativeContinuationEntry (family.destroy.identity, ContinuationRole.DESTROY, env == null ? null : env.identity, -1, null);
			families.add (new NativeContinuationFamily (family.identity, env, entries, destroy, family.repeat_step));
		}
		var actions = new GenericArray<ContinuationAction> ();
		foreach (var action in region.actions) {
			actions.add (action.copy ());
		}
		var plan = new NativeContinuationRegionPlan (region.identity, function, block, position, operands, families, actions);
		plan.verify ();
		return plan;
	}
	private static bool same_record(NativeRecordElement a, NativeRecordElement b) {
		if (a.struct_ordinal != b.struct_ordinal || a.fields.length != b.fields.length || a.natural_layout != b.natural_layout || a.structural_zero != b.structural_zero || a.trivial_destruction != b.trivial_destruction) {
			return false;
		}
		for (int i = 0; i < a.fields.length; i++) {
			var x = a.fields[i];
			var y = b.fields[i];
			if (x.ordinal != y.ordinal || (x.record == null) != (y.record == null) || (x.record != null ? !same_record (x.record, y.record) : !x.leaf.same_type (y.leaf))) {
				return false;
			}
		}
		return true;
	}
	public static void validate(NativeContinuationRegionPlan plan, SsaProgram source, NativeAbiProgram native, int function, int block, int position) throws NativeAbiError {
		plan.verify ();
		var expected = build (source, native, function, block, position);
		bool same = plan.identity == expected.identity && plan.function_ordinal == function && plan.block_ordinal == block && plan.position == position && plan.operands.length == expected.operands.length && plan.families.length == expected.families.length && plan.actions.length == expected.actions.length;
		if (same) {
			for (int i = 0; i < plan.operands.length; i++) {
				same &= plan.operands[i].same_type (expected.operands[i]);
			}
			for (int i = 0; i < plan.actions.length; i++) {
				same &= plan.actions[i].same_action (expected.actions[i]);
			}
		}
		if (same) {
			for (int i = 0; i < plan.families.length; i++) {
				var a = plan.families[i];
				var b = expected.families[i];
				same &= a.identity == b.identity && a.repeat_step == b.repeat_step && a.destroy.identity == b.destroy.identity && (a.environment == null) == (b.environment == null) && a.entries.length == b.entries.length;
				if (a.environment != null && b.environment != null) {
					same &= a.environment.identity == b.environment.identity && same_record (a.environment.storage, b.environment.storage);
				}
				if (a.entries.length == b.entries.length) {
					for (int e = 0; e < a.entries.length; e++) {
						same &= a.entries[e].identity == b.entries[e].identity && a.entries[e].role == b.entries[e].role && a.entries[e].target_ordinal == b.entries[e].target_ordinal && a.entries[e].body_signature == b.entries[e].body_signature;
					}
				}
			}
		}
		if (!same) {
			throw new NativeAbiError.INCOMPATIBLE_CALL ("continuation plan belongs to a different code/environment/operation region");
		}
	}
}
}
