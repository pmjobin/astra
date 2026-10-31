// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;

namespace Astra.Cfg {
// Exact monotone CFG lattice; diagnostics are issued only after convergence.
// This snapshot contains no upstream semantic/body objects or runtime state.
public class CfgConstructorInitialization : Object {
	private HashTable<CfgBlock, FieldInitializationState> entries = new HashTable<CfgBlock, FieldInitializationState> (direct_hash, direct_equal);
	private int count;
	internal static CfgIndirectFieldPlace? record_root(CfgPlace place, out string part) {
		part = "";
		while (place is CfgFieldPlace) {
			var field = (CfgFieldPlace) place;
			part = field.field.ordinal.to_string () + (part == "" ? "" : "." + part);
			place = field.aggregate;
		}
		return part == "" || !(place is CfgIndirectFieldPlace) || !(place.semantic_type is StructType) ? null : (CfgIndirectFieldPlace) place;
	}
	public FieldInitializationState at_entry(CfgBlock block) {
		var state = entries.lookup (block);
		if (state != null) {
			return state.copy ();
		}
		var unreachable = new FieldInitializationState (count);
		unreachable.reachable = false;
		return unreachable;
	}
	internal static GenericArray<CfgBlock> successors(CfgBlock block) {
		var conditional = block.terminator as CfgConditionalBranch;
		var literal = conditional == null ? null : conditional.condition as CfgBooleanValue;
		if (literal != null) {
			var result = new GenericArray<CfgBlock> ();
			result.add (literal.literal == BooleanLiteral.TRUE ? conditional.true_target : conditional.false_target);
			return result;
		}
		return block.terminator.successors ();
	}
	public CfgConstructorInitialization (CfgConstructor function, CopyabilityFields fields) throws CfgError {
		count = (int) function.declaring_class.fields.length + (function.declaring_class.parent_class == null ? 0 : 1);
		entries.insert (function.entry, new FieldInitializationState (count));
		var pending = new GenericArray<CfgBlock> ();
		pending.add (function.entry);
		for (int b = 0; b < pending.length; b++) {
			var block = pending[b];
			var state = at_entry (block);
			foreach (var instruction in block.instructions) {
				var record_commit = instruction as CfgRecordFieldCommit;
				if (record_commit != null && record_commit.initializes) {
					var receiver = record_commit.destination.pointer as CfgReceiverValue;
					var field = record_commit.destination.field;
					if (receiver == null || receiver.receiver != function.implicit_receiver || field.ordinal < 0 || field.ordinal >= function.declaring_class.fields.length || function.declaring_class.fields[field.ordinal] != field) {
						throw new CfgError.INVALID_CFG ("record initialization requires exact constructor receiver and field");
					}
					state.initialize (field.ordinal);
				}
				if (instruction is CfgBaseLifecycleCall && ((CfgBaseLifecycleCall) instruction).target is CfgConstructor && function.declaring_class.parent_class != null) {
					state.initialize ((int) function.declaring_class.fields.length);
				}
				var initialization = instruction as CfgInitialize;
				var slot = instruction as CfgSlotsInitialize;
				var field = slot != null ? slot.store : initialization == null ? null : initialization.target as CfgIndirectFieldPlace;
				string part = "";
				var aggregate = initialization == null ? null : record_root (initialization.target, out part);
				if (aggregate != null && aggregate.pointer is CfgReceiverValue && ((CfgReceiverValue) aggregate.pointer).receiver == function.implicit_receiver) {
					try {
						if (!state.initialize_record_part (aggregate.field.ordinal, part, StructLeafOrder.path_names (aggregate.semantic_type, fields))) {
							throw new CfgError.INVALID_CFG ("constructor record leaf lacks declared path");
						}
					} catch (StructLeafError error) {
						throw new CfgError.INVALID_CFG ("%s", error.message);
					}
				}
				if (field != null && field.pointer is CfgReceiverValue && ((CfgReceiverValue) field.pointer).receiver == function.implicit_receiver) {
					if (field.field.ordinal < 0 || field.field.ordinal >= function.declaring_class.fields.length || function.declaring_class.fields[field.field.ordinal] != field.field) {
						throw new CfgError.INVALID_CFG ("constructor field requires exact class identity");
					}
					state.initialize (field.field.ordinal);
				}
			}
			foreach (var next in successors (block)) {
				if (next == null || next.ordinal < 0 || next.ordinal >= function.blocks.length || function.blocks[next.ordinal] != next) {
					throw new CfgError.INVALID_CFG ("constructor initialization edge requires an exact live block in its function");
				}
				var prior = entries.lookup (next);
				var joined = prior == null ? state.copy() : FieldInitializationState.join (prior, state);
				if (prior == null || !joined.same_as (prior)) {
					entries.insert (next, joined);
					pending.add (next);
				}
			}
		}
	}
}
}
