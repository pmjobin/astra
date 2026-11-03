// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;

namespace Astra.Ssa {
// Exact monotone CFG lattice; diagnostics are issued only after convergence.
// This snapshot contains no upstream semantic/body objects or runtime state.
public class SsaConstructorInitialization : Object {
	private HashTable<SsaBlock, FieldInitializationState> entries = new HashTable<SsaBlock, FieldInitializationState> (direct_hash, direct_equal);
	private int count;
	internal static SsaIndirectFieldPlace? record_root(SsaMemoryPlace place, out string part) {
		part = "";
		while (place is SsaFieldPlace && ((SsaFieldPlace) place).aggregate != null) {
			var field = (SsaFieldPlace) place;
			part = field.field.ordinal.to_string () + (part == "" ? "" : "." + part);
			place = field.aggregate;
		}
		return part == "" || !(place is SsaIndirectFieldPlace) || !(place.semantic_type is StructType) ? null : (SsaIndirectFieldPlace) place;
	}

	public FieldInitializationState at_entry(SsaBlock block) {
		var state = entries.lookup (block);
		if (state != null) {
			return state.copy ();
		}
		var unreachable = new FieldInitializationState (count);
		unreachable.reachable = false;
		return unreachable;
	}

	internal static GenericArray<SsaBlock> successors(SsaBlock block) {
		if (block.terminator is SsaBufferAllocationBranch) {
			return block.terminator.successors ();
		}
		var result = new GenericArray<SsaBlock> ();
		var branch = block.terminator as SsaBranch;
		if (branch != null) {
			result.add (branch.edge.target);
		}
		var conditional = block.terminator as SsaConditionalBranch;
		if (conditional != null) {
			var literal = conditional.condition as SsaBooleanConstant;
			if (literal == null || literal.literal == BooleanLiteral.TRUE) {
				result.add (conditional.true_edge.target);
			}
			if (literal == null || literal.literal == BooleanLiteral.FALSE) {
				result.add (conditional.false_edge.target);
			}
		}
		return result;
	}

	public SsaConstructorInitialization (SsaConstructor function, CopyabilityFields fields) throws SsaError {
		count = (int) function.declaring_class.fields.length + (function.declaring_class.parent_class == null ? 0 : 1);
		entries.insert (function.entry, new FieldInitializationState (count));
		var pending = new GenericArray<SsaBlock> ();
		pending.add (function.entry);
		for (int b = 0; b < pending.length; b++) {
			var block = pending[b];
			var state = at_entry (block);
			foreach (var instruction in block.instructions) {
				var commit = instruction as SsaRecordFieldCommit;
				if (commit != null && commit.initializes) {
					var field = commit.destination.field;
					if (commit.destination.pointer != function.implicit_receiver || field.ordinal < 0 || field.ordinal >= function.declaring_class.fields.length || function.declaring_class.fields[field.ordinal] != field) {
						throw new SsaError.INVALID_SSA ("record initialization requires exact constructor receiver and field");
					}
					state.initialize (field.ordinal);
				}
				if (instruction is SsaBaseLifecycleCall && ((SsaBaseLifecycleCall) instruction).target is SsaConstructor && function.declaring_class.parent_class != null) {
					state.initialize ((int) function.declaring_class.fields.length);
				}
				var initialization = instruction as SsaInitializeInstruction;
				string part = "";
				var aggregate = initialization == null ? null : record_root (initialization.target, out part);
				if (aggregate != null && aggregate.pointer == function.implicit_receiver) {
					try {
						if (!state.initialize_record_part (aggregate.field.ordinal, part, StructLeafOrder.path_names (aggregate.semantic_type, fields))) {
							throw new SsaError.INVALID_SSA ("constructor record leaf lacks declared path");
						}
					} catch (StructLeafError error) {
						throw new SsaError.INVALID_SSA ("%s", error.message);
					}
				}
				var buffer = instruction as SsaBufferWriteInstruction;
				var slots = instruction as SsaSlotsEffect;
				var field = slots != null && slots.action == SsaSlotsAction.INITIALIZE ? slots.store : buffer != null && buffer.initializes ? buffer.place.field : initialization == null ? null : initialization.target as SsaIndirectFieldPlace;
				if (field != null && field.pointer == function.implicit_receiver) {
					if (field.field.ordinal < 0 || field.field.ordinal >= function.declaring_class.fields.length || function.declaring_class.fields[field.field.ordinal] != field.field) {
						throw new SsaError.INVALID_SSA ("constructor field requires exact class identity");
					}
					state.initialize (field.field.ordinal);
				}
			}
			foreach (var next in successors (block)) {
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
