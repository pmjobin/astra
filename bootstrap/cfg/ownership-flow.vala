// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Cfg {

// An absent map entry means outside the dynamic lexical lifetime. The extra
// bit detects malformed joins/duplicate cleanup; it is not a source state.
private class OwnershipEnvironment : Object {
	internal const uint OUT_OF_SCOPE = 8;
	private HashTable<CfgLocalPlace, CfgPendingOwnedArgument> pending = new HashTable<CfgLocalPlace, CfgPendingOwnedArgument> (direct_hash, direct_equal);
	internal CfgPendingOwnedArgument? reservation(CfgLocalPlace owner) {
		return pending.lookup (owner);
	}

	internal void reserve(CfgLocalPlace owner, CfgPendingOwnedArgument? transfer) {
		if (transfer == null) {
			pending.remove (owner);
		} else {
			pending.insert (owner, transfer);
		}
	}

	private HashTable<CfgLocalPlace, uint> facts = new HashTable<CfgLocalPlace, uint> (direct_hash, direct_equal);

	internal uint get_fact(CfgLocalPlace owner) {
		return facts.contains (owner) ? facts.lookup (owner) : OUT_OF_SCOPE;
	}

	internal void set_fact(CfgLocalPlace owner, uint fact) {
		if (fact == OUT_OF_SCOPE) {
			facts.remove (owner);
		} else {
			facts.insert (owner, fact);
		}
	}

	internal OwnershipEnvironment copy(GenericArray<CfgLocalPlace> owners) {
		var result = new OwnershipEnvironment ();
		foreach (var owner in owners) {
			result.set_fact (owner, get_fact (owner));
			result.reserve (owner, reservation (owner));
		}
		return result;
	}

	internal void merge(OwnershipEnvironment other, GenericArray<CfgLocalPlace> owners) {
		foreach (var owner in owners) {
			set_fact (owner, get_fact (owner) | other.get_fact (owner));
			if (reservation (owner) != other.reservation (owner)) {
				reserve (owner, null);
			}
		}
	}

	internal bool equal_to(OwnershipEnvironment other, GenericArray<CfgLocalPlace> owners) {
		foreach (var owner in owners) {
			if (get_fact (owner) != other.get_fact (owner) || reservation (owner) != other.reservation (owner)) {
				return false;
			}
		}
		return true;
	}

}

// A derived snapshot. No graph node points back here, and SSA retains none
// of this storage. Exact Place/block objects are keys; ordinals only print.
public class OwnershipFlowResult : Object {
	public Diagnostic? diagnostic { get; internal set; }
	public int iterations { get; internal set; }
	public HashTable<CfgOwnershipRearmInstruction, OwnershipState> rearm_states { get; private set; default = new HashTable<CfgOwnershipRearmInstruction, OwnershipState> (direct_hash, direct_equal); }
	internal bool receiver_is_fresh;
	internal HashTable<CfgEvaluatedValue, CfgValue> evaluated_sources = new HashTable<CfgEvaluatedValue, CfgValue> (direct_hash, direct_equal);
	internal HashTable<CfgLocalPlace, bool> input_borrows = new HashTable<CfgLocalPlace, bool> (direct_hash, direct_equal);
	internal HashTable<CfgValue, CfgLocalPlace> temporary_owners = new HashTable<CfgValue, CfgLocalPlace> (direct_hash, direct_equal);
	internal GenericArray<CfgLocalPlace> owners = new GenericArray<CfgLocalPlace> ();
	internal HashTable<CfgLocalPlace, CfgLocalPlace> scoped_backings = new HashTable<CfgLocalPlace, CfgLocalPlace> (direct_hash, direct_equal);
	private HashTable<CfgInstruction, HashTable<CfgLocalPlace, uint>> scoped_states_before = new HashTable<CfgInstruction, HashTable<CfgLocalPlace, uint>> (direct_hash, direct_equal);
	internal void snapshot_scoped(CfgInstruction instruction, OwnershipEnvironment state) {
		if (scoped_backings.size () == 0) {
			return;
		}
		var snapshot = new HashTable<CfgLocalPlace, uint> (direct_hash, direct_equal);
		foreach (var context in scoped_backings.get_keys ()) {
			snapshot.insert (context, state.get_fact (context));
		}
		scoped_states_before.insert (instruction, snapshot);
	}

	// Exact instruction position after convergence. Null includes absent or
	// inconsistent lexical lifetime; it never supplies a live-context proof.
	public OwnershipState? scoped_state_before(CfgInstruction instruction, CfgLocalPlace context) {
		var snapshot = scoped_states_before.lookup (instruction);
		if (snapshot == null || !snapshot.contains (context)) {
			return null;
		}
		uint fact = snapshot.lookup (context);
		return (fact & OwnershipEnvironment.OUT_OF_SCOPE) != 0 ? null : (OwnershipState?) fact;
	}

	internal HashTable<CfgLocalPlace, int> parameter_ordinals = new HashTable<CfgLocalPlace, int> (direct_hash, direct_equal);
	internal GenericArray<CfgBlock> blocks;
	internal HashTable<CfgBlock, OwnershipEnvironment> entries = new HashTable<CfgBlock, OwnershipEnvironment> (direct_hash, direct_equal);
	internal HashTable<CfgBlock, OwnershipEnvironment> exits = new HashTable<CfgBlock, OwnershipEnvironment> (direct_hash, direct_equal);

	internal OwnershipFlowResult (GenericArray<CfgBlock> blocks) {
		this.blocks = blocks;
	}

	public OwnershipState? entry_state(CfgBlock block, CfgLocalPlace owner) {
		var entry = entries.lookup (block);
		if (entry == null || entry.get_fact (owner) == OwnershipEnvironment.OUT_OF_SCOPE) {
			return null;
		}
		return (OwnershipState) entry.get_fact (owner);
	}

	public string dump() {
		var text = new StringBuilder ();
		foreach (var block in blocks) {
			text.append_printf ("block #%d entry:\n", block.ordinal);
			foreach (var owner in owners) {
				var state = entry_state (block, owner);
				text.append_printf ("\towner #%d %s = %s\n", owner.ordinal, owner.name, state == null ? "out-of-scope" : state.display_name ());
			}
		}
		return text.str;
	}

}

public class OwnershipFlow : Object {
	// Input must have passed CfgVerifier. Unknown predecessor outputs are
	// bottom, not out-of-scope. Process a deterministic FIFO to convergence,
	// then diagnose in block/instruction order using the final inputs.
	public static OwnershipFlowResult analyze(CfgFunction function) throws CfgError {
		var predecessors = CfgPredecessors.analyze (function);
		var result = new OwnershipFlowResult (predecessors.blocks ());
		result.receiver_is_fresh = function is CfgConstructor;
		foreach (var local in function.locals) {
			if (local.cleanup != null) {
				result.owners.add (local);
				if (local.struct_parameter != null && local.struct_parameter.shape.mode == StructValueMode.MOVE_VALUE) {
					result.parameter_ordinals.insert (local, local.struct_parameter.source_ordinal);
				} else if (local.incoming_parameter != null && local.incoming_parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER) {
					int ordinal = local.incoming_parameter.ordinal;
					foreach (var group in function.struct_parameters) {
						if (group.first_leaf < local.incoming_parameter.ordinal) {
							ordinal -= (int) group.shape.leaves.length - 1;
						}
					}
					result.parameter_ordinals.insert (local, ordinal);
				}
			}
		}
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var evaluation = instruction as CfgEvaluateInstruction;
				if (evaluation != null) {
					result.evaluated_sources.insert (evaluation.result, evaluation.value);
				}
				var scoped = evaluation == null ? null : evaluation.value as CfgScopedAllocator;
				if (scoped != null) {
					foreach (var local in function.locals) {
						if (local.ordinal == scoped.loan.context_ordinal) {
							result.scoped_backings.insert (local, scoped.backing);
						}
					}
				}
				var validation = evaluation == null ? null : evaluation.value as CfgObjectValidateValue;
				var load = validation == null ? null : validation.reference as CfgLoadValue;
				var owner = load == null ? null : load.source as CfgLocalPlace;
				if (owner != null && owner.cleanup != null) {
					result.temporary_owners.insert (evaluation.result, owner);
				}
			}
		}
		// Conservative provenance closure for existing borrowed parameter copies.
		// Fresh fixed objects and unique owners are independent of these inputs.
		bool changed = false;
		do {
			changed = false;
			foreach (var block in result.blocks) {
				foreach (var instruction in block.instructions) {
					var initialization = instruction as CfgInitialize;
					var store = instruction as CfgStore;
					var target = initialization != null ? initialization.target as CfgLocalPlace : store == null ? null : store.target as CfgLocalPlace;
					var value = initialization != null ? initialization.value : store == null ? null : store.value;
					if (target != null && target.cleanup == null && target.semantic_type is ClassType && !result.input_borrows.contains (target) && borrows_input (value, result)) {
						result.input_borrows.insert (target, true);
						changed = true;
					}
				}
			}
		} while (changed);
		var pending = new GenericArray<CfgBlock> ();
		var queued = new HashTable<CfgBlock, CfgBlock> (direct_hash, direct_equal);
		pending.add (function.entry);
		queued.insert (function.entry, function.entry);
		for (int head = 0; head < pending.length; head++) {
			var block = pending[head];
			queued.remove (block);
			result.iterations++;
			OwnershipEnvironment? entry = block == function.entry ? new OwnershipEnvironment () : null;
			foreach (var predecessor in predecessors.predecessors (block)) {
				var incoming = result.exits.lookup (predecessor);
				if (incoming == null) {
					continue;
				}
				if (entry == null) {
					entry = incoming.copy (result.owners);
				} else {
					entry.merge (incoming, result.owners);
				}
			}
			assert (entry != null);
			result.entries.insert (block, entry);
			var output = entry.copy (result.owners);
			simulate (block, output, result, false);
			var previous = result.exits.lookup (block);
			if (previous != null && previous.equal_to (output, result.owners)) {
				continue;
			}
			result.exits.insert (block, output);
			foreach (var successor in block.terminator.successors ()) {
				if (queued.insert (successor, successor)) {
					pending.add (successor);
				}
			}
		}
		foreach (var block in result.blocks) {
			var state = result.entries.lookup (block).copy (result.owners);
			foreach (var owner in result.owners) {
				uint fact = state.get_fact (owner);
				if ((fact & OwnershipEnvironment.OUT_OF_SCOPE) != 0 && fact != OwnershipEnvironment.OUT_OF_SCOPE) {
					invalid (owner, "inconsistent lexical lifetime at reachable join");
				}
			}
			simulate (block, state, result, true);
			if (result.diagnostic != null) {
				break;
			}
		}
		return result;
	}

	private static void invalid(CfgLocalPlace owner, string reason) throws CfgError {
		throw new CfgError.INVALID_CFG ("internal ownership flow error: owner #%d '%s': %s", owner.ordinal, owner.name, reason);
	}

	private static void require_owned(CfgLocalPlace owner, SourceSpan span, OwnershipEnvironment state, OwnershipFlowResult result, bool borrowing = false, bool releasing = false) throws CfgError {
		require_backing_available (owner, state, result);
		uint fact = state.get_fact (owner);
		if ((fact & OwnershipEnvironment.OUT_OF_SCOPE) != 0) {
			invalid (owner, "source operand outside its lexical lifetime");
		}
		var possibilities = (OwnershipState) fact;
		if (possibilities.definitely_owned () || result.diagnostic != null) {
			return;
		}
		string message;
		if (possibilities.definitely_moved ()) {
			message = releasing ? "cannot release moved owned value '%s'" : borrowing ? "cannot borrow moved owned value '%s'" : "use of moved owned value '%s'";
		} else if (possibilities.definitely_released ()) {
			message = releasing ? "owned value '%s' has already been released" : borrowing ? "cannot borrow released owned value '%s'" : "use of released owned value '%s'";
		} else {
			if (possibilities.definitely_disarmed ()) {
				message = "owned value '%s' no longer owns a resource on every reachable path";
			} else if (possibilities == OwnershipState.join (OwnershipState.OWNED, OwnershipState.MOVED)) {
				message = "owned value '%s' may have been moved on another control-flow path";
			} else {
				message = "owned value '%s' may no longer own its resource on another control-flow path";
			}
			if (releasing) {
				message += " and cannot be released";
			}
			if (borrowing) {
				message += " and cannot be borrowed";
			}
		}
		result.diagnostic = new Diagnostic (span, message.printf (owner.name));
	}

	private static void require_backing_available(CfgLocalPlace owner, OwnershipEnvironment state, OwnershipFlowResult result) throws CfgError {
		foreach (var context in result.scoped_backings.get_keys ()) {
			uint fact = state.get_fact (context);
			if (result.scoped_backings.lookup (context) == owner && (fact & (uint) OwnershipState.OWNED) != 0) {
				invalid (owner, "scoped backing is exclusively borrowed until its context cleanup");
			}
		}
	}

	private static void start_owner(CfgLocalPlace owner, OwnershipEnvironment state, bool validate) throws CfgError {
		if (validate && state.get_fact (owner) != OwnershipEnvironment.OUT_OF_SCOPE) {
			invalid (owner, "initialization would rearm an active lexical owner");
		}
		state.set_fact (owner, (uint) OwnershipState.OWNED);
	}

	private static bool borrows_input(CfgValue value, OwnershipFlowResult result) {
		var evaluated = value as CfgEvaluatedValue;
		if (evaluated != null) {
			var source = result.evaluated_sources.lookup (evaluated);
			return source != null && borrows_input (source, result);
		}
		var validation = value as CfgObjectValidateValue;
		if (validation != null) {
			return borrows_input (validation.reference, result);
		}
		var parameter = value as CfgParameterValue;
		if (parameter != null) {
			return parameter.parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && value.semantic_type is ClassType;
		}
		var load = value as CfgLoadValue;
		var local = load == null ? null : load.source as CfgLocalPlace;
		if (local != null) {
			return result.input_borrows.contains (local);
		}
		return value is CfgReceiverValue && !result.receiver_is_fresh;
	}

	private static void require_input_lifetime(CfgValue value, OwnershipEnvironment state, OwnershipFlowResult result) throws CfgError {
		var type = (value.semantic_type is ReceiverType) ? ((ReceiverType) value.semantic_type).instance_type : value.semantic_type;
		if (!(type is ClassType) || !borrows_input (value, result)) {
			return;
		}
		foreach (var owner in result.owners) {
			if (owner.incoming_parameter == null || owner.semantic_type != type) {
				continue;
			}
			require_owned (owner, value.span, state, result, true);
		}
	}

	private static void read_place(CfgPlace place, OwnershipEnvironment state, OwnershipFlowResult result) throws CfgError {
		if (place is CfgFieldPlace) {
			read_place (((CfgFieldPlace) place).aggregate, state, result);
		}
		var record = place as CfgLocalPlace;
		if (record != null && record.semantic_type is StructType && record.cleanup != null) {
			require_owned (record, place.span, state, result, true);
		}
		var slice = place as CfgSliceElementPlace;
		if (slice != null) {
			read_value (slice.slice, state, result);
			read_value (slice.index, state, result);
		}
		var array = place as CfgArrayElementPlace;
		if (array != null) {
			read_value (array.index, state, result);
		}
		var dereference = place as CfgDereferencePlace;
		if (dereference != null) {
			read_value (dereference.pointer, state, result);
		}
		var indirect = place as CfgIndirectFieldPlace;
		if (indirect != null) {
			var owner = result.temporary_owners.lookup (indirect.pointer);
			if (owner != null) {
				require_owned (owner, indirect.span, state, result, true);
			}
			read_value (indirect.pointer, state, result);
		}
	}

	private static void read_value(CfgValue value, OwnershipEnvironment state, OwnershipFlowResult result) throws CfgError {
		if (value is CfgScopedAllocator) {
			var scoped = (CfgScopedAllocator) value;
			require_owned (scoped.backing, value.span, state, result, true);
			read_value (scoped.kind, state, result);
			read_value (scoped.slots, state, result);
			return;
		}
		if (value is CfgRetainedOperation) {
			var operation = (CfgRetainedOperation) value;
			read_value (operation.callee, state, result);
			foreach (var argument in operation.arguments) {
				read_value (argument, state, result);
			}
			return;
		}
		if (value is CfgClosureCall) {
			var call = (CfgClosureCall) value;
			read_value (call.callee, state, result);
			foreach (var argument in call.arguments) {
				read_value (argument, state, result);
			}
			return;
		}
		if (value is CfgClosureBind) {
			read_value (((CfgClosureBind) value).environment, state, result);
			return;
		}
		if (value is CfgFunctionValueCall) {
			var call = (CfgFunctionValueCall) value;
			read_value (call.callee, state, result);
			foreach (var argument in call.arguments) {
				read_value (argument, state, result);
			}
			return;
		}
		if (value is CfgSharedOperation) {
			read_value (((CfgSharedOperation) value).operand, state, result);
			return;
		}
		require_input_lifetime (value, state, result);
		if (value is CfgSlotsValue) {
			var v = (CfgSlotsValue) value;
			read_place (v.store, state, result);
			if (v.operand != null) {
				read_value (v.operand, state, result);
			}
			return;
		}
		if (value is CfgSlotsLoan) {
			read_place (((CfgSlotsLoan) value).store, state, result);
			return;
		}
		if (value is CfgEvaluatedValue) {
			var origin = result.evaluated_sources.lookup ((CfgEvaluatedValue) value);
			if (origin is CfgBufferBorrowValue) {
				require_owned (((CfgBufferBorrowValue) origin).source, value.span, state, result, true);
			}
		}
		var receiver_address = value as CfgAddressOfValue;
		if (value is CfgEvaluatedValue) {
			receiver_address = result.evaluated_sources.lookup ((CfgEvaluatedValue) value) as CfgAddressOfValue;
		}
		if (receiver_address != null && receiver_address.receiver_place != null) {
			read_place (receiver_address.receiver_place, state, result);
		}
		var validation = value as CfgObjectValidateValue;
		if (validation != null) {
			read_value (validation.reference, state, result);
			return;
		}
		var slice = value as CfgSliceFromArrayValue;
		if (slice != null) {
			if (slice.start != null) {
				read_value (slice.start, state, result);
			}
			if (slice.count != null) {
				read_value (slice.count, state, result);
			}
			return;
		}
		if (value is CfgTextLengthValue) {
			read_value (((CfgTextLengthValue) value).receiver, state, result);
			return;
		}
		var length = value as CfgSliceLengthValue;
		if (length != null) {
			read_value (length.slice, state, result);
			return;
		}
		var dot = value as CfgVectorDotValue;
		if (dot != null) {
			if (dot.accumulator != null) {
				read_value (dot.accumulator, state, result);
			}
			read_value (dot.first, state, result);
			read_value (dot.second, state, result);
			return;
		}
		var dsp = value as CfgDspValue;
		if (dsp != null) {
			read_value (dsp.first, state, result);
			if (dsp.second != null) {
				read_value (dsp.second, state, result);
			}
			return;
		}
		var shift = value as CfgIntegerShiftValue;
		if (shift != null) {
			read_value (shift.operand, state, result);
			read_value (shift.count, state, result);
			return;
		}
		var numeric_conversion = value as CfgNumericConversionValue;
		if (numeric_conversion != null) {
			read_value (numeric_conversion.operand, state, result);
			return;
		}
		var floating_conversion = value as CfgFloatConversionValue;
		if (floating_conversion != null) {
			read_value (floating_conversion.operand, state, result);
			return;
		}
		var conversion = value as CfgIntegerConversionValue;
		if (conversion != null) {
			read_value (conversion.operand, state, result);
			return;
		}
		var splat = value as CfgVectorSplatValue;
		if (splat != null) {
			read_value (splat.operand, state, result);
		}
		var extract = value as CfgVectorExtractValue;
		if (extract != null) {
			read_value (extract.vector, state, result);
		}
		var insert = value as CfgVectorInsertValue;
		if (insert != null) {
			read_value (insert.vector, state, result);
			read_value (insert.replacement, state, result);
		}
		var shuffle = value as CfgVectorShuffleValue;
		if (shuffle != null) {
			read_value (shuffle.vector, state, result);
		}
		var select = value as CfgVectorSelectValue;
		if (select != null) {
			read_value (select.mask, state, result);
			read_value (select.true_value, state, result);
			read_value (select.false_value, state, result);
		}
		var vector = value as CfgVectorConstructValue;
		if (vector != null) {
			foreach (var lane in vector.lanes) {
				read_value (lane, state, result);
			}
		}
		var reduction = value as CfgVectorReductionValue;
		if (reduction != null) {
			read_value (reduction.operand, state, result);
		}
		var borrow = value as CfgOwnedBorrowValue;
		if (borrow != null) {
			// The owner must remain live through invocation, including when
			// another argument transfers responsibility to that same call.
			require_owned (borrow.source, borrow.span, state, result, true);
		}
		var load = value as CfgLoadValue;
		if (load != null) {
			var owner = load.source as CfgLocalPlace;
			if (owner != null && owner.cleanup != null) {
				require_owned (owner, load.span, state, result);
			}
			read_place (load.source, state, result);
		}
		var prefix = value as CfgPrefixValue;
		if (prefix != null) {
			read_value (prefix.operand, state, result);
		}
		var binary = value as CfgBinaryValue;
		if (binary != null) {
			read_value (binary.left, state, result);
			read_value (binary.right, state, result);
		}
	}

	private static void simulate(CfgBlock block, OwnershipEnvironment state, OwnershipFlowResult result, bool validate) throws CfgError {
		foreach (var instruction in block.instructions) {
			if (validate) {
				result.snapshot_scoped (instruction, state);
			}
			var conditional = instruction as CfgLifecycleCallInstruction;
			var frame = instruction as CfgTaskCreate;
			if (conditional != null && conditional.constructs && conditional.storage.fallible || frame != null && frame.checked_admission) {
				foreach (var moved in ((CfgCallInstruction) instruction).record_moves) {
					if (validate && state.get_fact (moved.source) != (uint) OwnershipState.MOVED) {
						invalid (moved.source, "checked record admission requires its exact complete transferred input");
					}
					state.set_fact (moved.source, (uint) OwnershipState.OWNED);
				}
				foreach (var input in ((CfgCallInstruction) instruction).arguments) {
					var captured = input as CfgPendingOwnedArgument;
					if (captured != null && captured.source != null) {
						if (validate && state.get_fact (captured.source) != (uint) OwnershipState.MOVED) {
							invalid (captured.source, "fallible admission requires its exact pending transferred input");
						}
						state.set_fact (captured.source, (uint) OwnershipState.OWNED);
					}
				}
			}
			if (instruction is CfgEnumExtractBuffer) {
				start_owner (((CfgEnumExtractBuffer) instruction).destination, state, validate);
				continue;
			}
			if (instruction is CfgEnumExtractRecord) {
				continue;
			}
			if (instruction is CfgEnumExtractScalar) {
				start_owner (((CfgEnumExtractScalar) instruction).destination, state, validate);
				continue;
			}
			var scalar_capture = instruction as CfgEnumScalarCapture;
			if (scalar_capture != null) {
				if (validate) {
					require_owned (scalar_capture.source, instruction.span, state, result);
				}
				continue;
			}
			var enum_capture = instruction as CfgEnumBufferCapture;
			if (enum_capture != null) {
				if (validate && enum_capture.source != null) {
					require_owned (enum_capture.source, instruction.span, state, result);
				}
				continue;
			}
			var enumeration = instruction as CfgEnumConstruct;
			if (enumeration != null) {
				foreach (var field in enumeration.fields) {
					var source = field.scalar_owner != null ? field.scalar_owner.source : field.buffer == null ? null : field.buffer.source;
					if (source != null) {
						if (validate) {
							require_owned (source, instruction.span, state, result);
						}
						state.set_fact (source, (uint) OwnershipState.MOVED);
					}
				}
				continue;
			}

			var slot_capture = instruction as CfgBufferSlotCapture;
			if (slot_capture != null) {
				if (validate) {
					var local = slot_capture.place as CfgLocalPlace;
					if (local != null) {
						require_owned (local, instruction.span, state, result);
					}
					read_place (slot_capture.place, state, result);
				}
				continue;
			}
			var exchange = instruction as CfgBufferExchange;
			if (exchange != null) {
				if (validate) {
					foreach (var slot in new CfgPlace[] { exchange.left, exchange.right }) {
						var local = slot as CfgLocalPlace;
						if (local != null) {
							require_owned (local, instruction.span, state, result);
						}
						read_place (slot, state, result);
					}
				}
				continue;
			}
			if (instruction is CfgOwnedArgumentAbort) {
				var aborted = ((CfgOwnedArgumentAbort) instruction).transfer;
				if (aborted.source != null) {
					if (validate && (state.get_fact (aborted.source) != (uint) OwnershipState.MOVED || state.reservation (aborted.source) != aborted)) {
						invalid (aborted.source, "exception abort requires the exact pending unavailable source");
					}
					state.reserve (aborted.source, null);
					state.set_fact (aborted.source, (uint) OwnershipState.OWNED);
				}
				continue;
			}
			if (instruction is CfgOwnedCallTransferCommit) {
				foreach (var transfer in ((CfgOwnedCallTransferCommit) instruction).transfers) {
					if (transfer.source != null && transfer.exceptional_abort) {
						if (validate && state.reservation (transfer.source) != transfer) {
							invalid (transfer.source, "call commit lost its exact pending reservation");
						}
						state.reserve (transfer.source, null);
					}
				}
				continue;
			}
			if (instruction is CfgExceptionTake) {
				var take = (CfgExceptionTake) instruction;
				if (validate) {
					require_owned (take.owner, take.span, state, result);
				}
				state.set_fact (take.owner, (uint) OwnershipState.MOVED);
				continue;
			}
			if (instruction is CfgSlotsRecordTransfer) {
				var transfer = (CfgSlotsRecordTransfer) instruction;
				if (validate) {
					read_place (transfer.store, state, result);
					if (transfer.index != null) {
						read_value (transfer.index, state, result);
					}
					foreach (var leaf in transfer.leaves) {
						read_value (leaf, state, result);
					}
				}
				continue;
			}
			if (instruction is CfgSlotsRecordRead) {
				var read = (CfgSlotsRecordRead) instruction;
				if (validate) {
					read_place (read.store, state, result);
					read_value (read.index, state, result);
				}
				continue;
			}
			if (instruction is CfgSlotsInitialize) {
				if (validate) {
					read_place (((CfgSlotsInitialize) instruction).store, state, result);
				}
				continue;
			}
			if (instruction is CfgSlotsDrop) {
				if (validate) {
					read_place (((CfgSlotsDrop) instruction).store, state, result);
				}
				continue;
			}
			if (instruction is CfgSlotsBorrow) {
				var loan = ((CfgSlotsBorrow) instruction).result;
				if (validate) {
					read_place (loan.store, state, result);
					read_value (loan.index, state, result);
				}
				continue;
			}
			if (instruction is CfgSlotsReplace) {
				var replace = (CfgSlotsReplace) instruction;
				if (validate) {
					read_place (replace.store, state, result);
					read_value (replace.index, state, result);
					require_owned (replace.incoming, instruction.span, state, result);
				}
				state.set_fact (replace.incoming, (uint) OwnershipState.MOVED);
				continue;
			}
			if (instruction is CfgSlotsAppend) {
				var append = (CfgSlotsAppend) instruction;
				if (validate) {
					read_place (append.store, state, result);
					require_owned (append.incoming, instruction.span, state, result);
				}
				state.set_fact (append.incoming, (uint) OwnershipState.MOVED);
				continue;
			}
			var resource_capture = instruction as CfgResourceCapture;
			if (instruction is CfgStructBoundaryAcquire) {
				var acquire = (CfgStructBoundaryAcquire) instruction;
				if (validate) {
					foreach (var leaf in acquire.leaves) {
						read_value (leaf, state, result);
					}
				}
				if (acquire.projection == null || state.get_fact (acquire.destination) == OwnershipEnvironment.OUT_OF_SCOPE) {
					start_owner (acquire.destination, state, validate);
				}
				continue;
			}
			if (instruction is CfgStructBoundaryMove) {
				var move = (CfgStructBoundaryMove) instruction;
				if (validate) {
					require_owned (move.source, move.span, state, result);
				}
				state.set_fact (move.source, (uint) OwnershipState.MOVED);
				continue;
			}
			if (instruction is CfgRecordFieldCommit) {
				var commit = (CfgRecordFieldCommit) instruction;
				if (validate) {
					read_place (commit.destination, state, result);
					foreach (var leaf in commit.leaves) {
						read_value (leaf, state, result);
					}
				}
				continue;
			}
			if (instruction is CfgRecordFieldDrop) {
				if (validate) {
					read_place (((CfgRecordFieldDrop) instruction).source, state, result);
				}
				continue;
			}
			if (instruction is CfgRecordTake) {
				var take = (CfgRecordTake) instruction;
				if (validate) {
					require_owned (take.source, take.span, state, result);
				}
				start_owner (take.destination, state, validate);
				continue;
			}
			if (instruction is CfgRecordReplace) {
				var replace = (CfgRecordReplace) instruction;
				if (validate) {
					require_owned (replace.owner, replace.span, state, result);
					if (replace.source != null) {
						require_owned (replace.source, replace.span, state, result);
					} else {
						read_value (replace.incoming, state, result);
					}
				}
				if (replace.source != null) {
					state.set_fact (replace.source, (uint) OwnershipState.MOVED);
				}
				continue;
			}
			if (resource_capture != null && resource_capture.source != null) {
				if (validate) {
					require_owned (resource_capture.source, instruction.span, state, result);
				}
				state.set_fact (resource_capture.source, (uint) OwnershipState.MOVED);
				continue;
			}
			var capture = instruction as CfgOwnedArgumentCapture;
			var returned = instruction as CfgOwnershipReturnInstruction;
			var source = capture != null ? capture.transfer.source : returned == null ? null : returned.result.source;
			if (source != null) {
				if (validate) {
					require_owned (source, instruction.span, state, result);
				}
				state.set_fact (source, (uint) OwnershipState.MOVED);
				if (capture != null && capture.transfer.exceptional_abort) {
					state.reserve (source, capture.transfer);
				}
				continue;
			}
			var rearm = instruction as CfgOwnershipRearmInstruction;
			if (rearm != null) {
				if (rearm.source != null) {
					if (validate) {
						require_owned (rearm.source, rearm.span, state, result);
					}
					state.set_fact (rearm.source, (uint) OwnershipState.MOVED);
				}
				if (validate) {
					uint fact = state.get_fact (rearm.owner);
					if ((fact & OwnershipEnvironment.OUT_OF_SCOPE) != 0) {
						invalid (rearm.owner, "rearm outside its lexical lifetime");
					}
					var possibilities = (OwnershipState) fact;
					result.rearm_states.insert (rearm, possibilities);
					if (!(rearm.owner.semantic_type is HandleType) && !rearm.cleanup.is_buffer && !possibilities.definitely_disarmed () && result.diagnostic == null) {
						string message = possibilities.definitely_owned () ? "owned value '%s' still owns a resource; release or move it before reassignment" : "owned value '%s' may still own a resource on another control-flow path";
						result.diagnostic = new Diagnostic (rearm.span, message.printf (rearm.owner.name));
					}
				}
				state.set_fact (rearm.owner, (uint) OwnershipState.OWNED);
				continue;
			}
			var release = instruction as CfgOwnershipReleaseInstruction;
			if (release != null) {
				if (validate) {
					require_owned (release.owner, release.span, state, result, false, true);
				}
				state.set_fact (release.owner, (uint) OwnershipState.RELEASED);
				continue;
			}
			var borrow = instruction as CfgOwnedBorrowInstruction;
			if (borrow != null) {
				if (validate) {
					require_owned (borrow.result.source, borrow.span, state, result, true);
				}
				continue;
			}
			var transfer = instruction as CfgOwnershipTransferInstruction;
			if (transfer != null) {
				if (validate) {
					require_owned (transfer.source, transfer.span, state, result);
				}
				state.set_fact (transfer.source, (uint) OwnershipState.MOVED);
				start_owner (transfer.destination, state, validate);
				continue;
			}
			var cleanup = instruction as CfgCleanupInstruction;
			if (cleanup != null) {
				var load = cleanup.value as CfgLoadValue;
				var owner = cleanup.record_owner ?? (load == null ? null : load.source as CfgLocalPlace);
				if (validate && owner != null) {
					require_backing_available (owner, state, result);
				}
				if (validate && owner != null && result.parameter_ordinals.contains (owner) && ((OwnershipState) state.get_fact (owner)).may_own ()) {
					int ordinal = result.parameter_ordinals.lookup (owner);
					foreach (var other in result.parameter_ordinals.get_keys ()) {
						if (result.parameter_ordinals.lookup (other) > ordinal && ((OwnershipState) state.get_fact (other)).may_own ()) {
							invalid (owner, "automatic cleanup must preserve reverse parameter declaration order");
						}
					}
				}
				if (owner != null && owner.cleanup != null && (cleanup.record_owner == null || cleanup.record_final)) {
					if (validate && (state.get_fact (owner) & OwnershipEnvironment.OUT_OF_SCOPE) != 0) {
						invalid (owner, "duplicate cleanup or cleanup outside its lexical lifetime");
					}
					state.set_fact (owner, OwnershipEnvironment.OUT_OF_SCOPE);
				} else if (validate && cleanup.record_owner == null) {
					read_value (cleanup.value, state, result);
				}
				continue;
			}
			var array = instruction as CfgArrayInitialize;
			if (array != null) {
				if (validate) {
					foreach (var element in array.elements) {
						read_value (element, state, result);
					}
				}
				continue;
			}
			var initialization = instruction as CfgInitialize;
			if (initialization != null) {
				if (validate) {
					read_value (initialization.value, state, result);
				}
				if (initialization.acquisition != null) {
					if (!(initialization.acquisition.semantic_type is StructType) || state.get_fact (initialization.acquisition) == OwnershipEnvironment.OUT_OF_SCOPE) {
						start_owner (initialization.acquisition, state, validate);
					}
				}
				continue;
			}
			if (!validate) {
				continue;
			}
			if (instruction is CfgAsyncDelay) {
				read_value (((CfgAsyncDelay) instruction).ticks, state, result);
				continue;
			}
			if (instruction is CfgBufferAllocate) {
				var allocation = (CfgBufferAllocate) instruction;
				if (allocation.allocation_context != null) {
					read_value (allocation.allocation_context, state, result);
				}
				read_value (allocation.count, state, result);
				continue;
			}
			var slice_bounds = instruction as CfgSliceBoundsCheck;
			if (slice_bounds != null) {
				read_value (slice_bounds.slice, state, result);
			}
			if (instruction is CfgStructInvoke) {
				var invocation = (CfgStructInvoke) instruction;
				if (invocation.checked_call == null) {
					read_value (invocation.call, state, result);
				}
				continue;
			}
			var evaluation = instruction as CfgEvaluateInstruction;
			if (evaluation != null) {
				read_value (evaluation.value, state, result);
			}
			var store = instruction as CfgStore;
			if (store != null) {
				read_value (store.value, state, result);
				read_place (store.target, state, result);
			}
			var call = instruction as CfgCallInstruction;
			if (call != null && call.receiver != null) {
				read_value (call.receiver, state, result);
				var receiver_owner = result.temporary_owners.lookup (call.receiver);
				if (receiver_owner != null) {
					require_owned (receiver_owner, call.span, state, result, true);
				}
			}
			var c_call = instruction as CfgCCallInstruction;
			var arguments = call != null ? call.arguments : c_call == null ? null : c_call.arguments;
			if (arguments != null) {
				foreach (var argument in arguments) {
					read_value (argument, state, result);
				}
			}
		}
		var foreign = block.terminator as CfgForeignReturn;
		if (foreign != null) {
			foreach (var owner in foreign.consumed) {
				if (validate) {
					require_owned (owner, foreign.span, state, result);
				}
				state.set_fact (owner, OwnershipEnvironment.OUT_OF_SCOPE);
			}
		}
		if (!validate) {
			return;
		}
		var allocation = block.terminator as CfgBufferAllocationBranch;
		if (allocation != null) {
			read_value (allocation.allocation.count, state, result);
		}
		var trap = block.terminator as CfgAllocationFailureTrap;
		if (trap != null && trap.failure.captured_receiver != null) {
			var receiver = trap.failure.captured_receiver;
			read_value (receiver, state, result);
			var owner = result.temporary_owners.lookup (receiver);
			if (owner != null) {
				require_owned (owner, trap.span, state, result, true);
			}
		}
		var conditional = block.terminator as CfgConditionalBranch;
		if (conditional != null) {
			read_value (conditional.condition, state, result);
		}
		var returned = block.terminator as CfgReturn;
		if (returned != null && returned.value != null) {
			read_value (returned.value, state, result);
		}
		if (block.terminator is CfgReturn || block.terminator is CfgFunctionEnd) {
			foreach (var owner in result.owners) {
				if (state.get_fact (owner) != OwnershipEnvironment.OUT_OF_SCOPE) {
					invalid (owner, "normal function exit without lexical cleanup");
				}
			}
		}
	}

}
}

namespace Astra.Cfg {
// Reconstruct field obligations from this stage's own Places and edges.
// No runtime mask, first-field sentinel, or predecessor-stage node is used.
internal class CfgRecordObligations : Object {
	private static void reject(string reason = "lost initialized prefix, exact move or once-only rollback/cleanup") throws CfgError {
		throw new CfgError.INVALID_CFG ("record field obligations: %s", reason);
	}

	internal static void verify(CfgFunction function) throws CfgError {
		var fields = new GenericArray<CfgFieldPlace> ();
		var borrowed = new HashTable<CfgLocalPlace, bool> (direct_hash, direct_equal);
		foreach (var local in function.locals) {
			if (local.struct_parameter == null || local.struct_parameter.shape.mode != StructValueMode.BORROW_VALUE) {
				continue;
			}
			int bindings = 0;
			foreach (var instruction in function.entry.instructions) {
				var binding = instruction as CfgStructParameterBorrow;
				if (binding != null && binding.destination == local && binding.parameter == local.struct_parameter) {
					bindings++;
				}
			}
			if (bindings != 1 || local.cleanup != null || local.record_order.length != 0 || !function.struct_parameters.find (local.struct_parameter)) {
				reject ("borrowed record cannot acquire local cleanup responsibility");
			}
			borrowed.insert (local, true);
		}
		foreach (var field in function.field_places) {
			if (field.root_local () != null && !borrowed.contains (field.root_local ()) && field.root_local ().semantic_type is StructType && field.field.owned_cleanup != null) {
				fields.add (field);
			}
		}
		int count = (int) fields.length;
		if (count == 0) {
			return;
		}
		foreach (var local in function.locals) {
			int expected = 0;
			foreach (var field in fields) {
				if (field.root_local () == local) {
					expected++;
				}
			}
			if (local.record_order.length != expected) {
				reject ();
			}
			var seen = new HashTable<string, bool> (str_hash, str_equal);
			foreach (var path in local.record_order) {
				bool matched = false;
				foreach (var field in fields) {
					if (field.root_local () == local && field.storage_path ().same_path (path)) {
						matched = true;
					}
				}
				if (!matched || seen.contains (path.spelling ())) {
					reject ();
				}
				seen.insert (path.spelling (), true);
			}
		}
		// 1 uninitialized, 2 live, 4 moved, 8 retired. Union at joins.
		int[,] entries = new int[function.blocks.length, count];
		bool[] reachable = new bool[function.blocks.length];
		reachable[function.entry.ordinal] = true;
		for (int f = 0; f < count; f++) {
			entries[function.entry.ordinal, f] = 1;
		}
		for (int pass = 0; pass < 2; pass++) {
			bool changed = false;
			do {
				changed = false;
				foreach (var block in function.blocks) {
					if (!reachable[block.ordinal]) {
						continue;
					}
					int[] state = new int[count];
					for (int f = 0; f < count; f++) {
						state[f] = entries[block.ordinal, f];
					}
					foreach (var instruction in block.instructions) {
						var initialize = instruction as CfgInitialize;
						var move = instruction as CfgOwnershipTransferInstruction;
						var cleanup = instruction as CfgCleanupInstruction;
						var take = instruction as CfgRecordTake;
						var replace = instruction as CfgRecordReplace;
						var boundary_acquire = instruction as CfgStructBoundaryAcquire;
						var boundary_move = instruction as CfgStructBoundaryMove;
						var evaluation = instruction as CfgEvaluateInstruction;
						var observed = evaluation == null ? null : evaluation.value as CfgLoadValue;
						var admission = instruction as CfgCallInstruction;
						var frame_admission = admission as CfgTaskCreate;
						var constructor_admission = admission as CfgLifecycleCallInstruction;
						bool conditional_admission = frame_admission != null && frame_admission.checked_admission || constructor_admission != null && constructor_admission.constructs && constructor_admission.storage.fallible;
						for (int f = 0; f < count; f++) {
							var field = fields[f];
							var local = field.root_local ();
							int rank = -1;
							for (int r = 0; r < local.record_order.length; r++) {
								if (local.record_order[r].same_path (field.storage_path ())) {
									rank = r;
								}
							}
							if (rank < 0) {
								reject ();
							}
							if (conditional_admission) {
								foreach (var original in admission.record_moves) {
									if (original.source != local) {
										continue;
									}
									if (pass == 1 && (original.consumer != admission || state[f] != 4)) {
										reject ("conditional record restoration requires every original field moved into this exact factory");
									}
									state[f] = 2;
								}
							}
							if (pass == 1 && observed != null && observed.source == field && state[f] != 2) {
								reject ("record field observation requires a definitely live original leaf");
							}
							if (boundary_acquire != null && boundary_acquire.destination == local && boundary_acquire.contains (field)) {
								if (pass == 1 && (state[f] == 0 || (state[f] & ~9) != 0)) {
									reject ("record boundary requires fresh complete field responsibility");
								}
								if (pass == 1 && boundary_acquire.projection != null) {
									for (int r = 0; r < rank; r++) {
										for (int other = 0; other < count; other++) {
											if (fields[other].root_local () == local && !boundary_acquire.contains (fields[other])
											    && fields[other].storage_path ().same_path (local.record_order[r]) && state[other] != 2) {
												reject ("record subobject acquisition lost written initialized prefix");
											}
										}
									}
								}
								state[f] = 2;
							} else if (boundary_move != null && boundary_move.source == local) {
								if (pass == 1 && state[f] != 2) {
									reject ("record MOVE_VALUE requires every field definitely live");
								}
								state[f] = 4;
							} else if (initialize != null && initialize.target == field) {
								if (pass == 1 && (state[f] == 0 || (state[f] & ~9) != 0 || initialize.acquisition != local)) {
									reject ();
								}
								if (pass == 1) {
									for (int r = 0; r < rank; r++) {
										for (int other = 0; other < count; other++) {
											if (fields[other].root_local () == local && fields[other].storage_path ().same_path (local.record_order[r]) && state[other] != 2) {
												reject ();
											}
										}
									}
								}
								state[f] = 2;
							} else if (take != null && take.field == field) {
								if (pass == 1 && state[f] != 2) {
									reject ("record field take requires a definitely live leaf; it may have been moved");
								}
								state[f] = 4;
							} else if (replace != null && replace.field == field) {
								if (pass == 1 && (state[f] == 0 || (state[f] & ~6) != 0 || replace.owner != local)) {
									reject ("record replacement requires a live or taken field in its original live root");
								}
								state[f] = 2;
							} else if (move != null && move.source == local) {
								if (pass == 1 && state[f] != 2) {
									reject ("record move requires all fields live; source may have been moved or not initialized");
								}
								if (pass == 1) {
									if (move.source.record_order.length != move.destination.record_order.length) {
										reject ();
									}
									for (int r = 0; r < move.source.record_order.length; r++) {
										if (!move.source.record_order[r].same_path (move.destination.record_order[r])) {
											reject ();
										}
									}
								}
								state[f] = 4;
							} else if (move != null && move.destination == local) {
								if (pass == 1 && (state[f] == 0 || (state[f] & ~9) != 0)) {
									reject ();
								}
								state[f] = 2;
							} else if (cleanup != null && cleanup.record_owner == local) {
								var load = cleanup.value as CfgLoadValue;
								if (load == null || load.source != field) {
									continue;
								}
								if (pass == 1 && (state[f] & 8) != 0) {
									reject ("duplicate cleanup of an owned record field");
								}
								if (pass == 1 && (state[f] == 0 || (state[f] & ~6) != 0 || cleanup.cleanup != field.field.owned_cleanup || cleanup.record_final != (rank == 0))) {
									reject ();
								}
								if (pass == 1) {
									for (int r = rank + 1; r < local.record_order.length; r++) {
										for (int other = 0; other < count; other++) {
											if (fields[other].root_local () == local && fields[other].storage_path ().same_path (local.record_order[r]) && (state[other] & 6) != 0) {
												reject ();
											}
										}
									}
								}
								state[f] = 8;
							}
						}
					}
					if (pass == 1 && (block.terminator is CfgReturn || block.terminator is CfgExceptionReturn || block.terminator is CfgFunctionEnd)) {
						for (int f = 0; f < count; f++) {
							if ((state[f] & 6) != 0) {
								reject ("normal function exit without lexical cleanup of an owned record field");
							}
						}
					}
					if (pass == 0) {
						foreach (var next in block.terminator.successors ()) {
							if (!reachable[next.ordinal]) {
								reachable[next.ordinal] = true;
								changed = true;
							}
							for (int f = 0; f < count; f++) {
								int joined = entries[next.ordinal, f] | state[f];
								if (joined != entries[next.ordinal, f]) {
									entries[next.ordinal, f] = joined;
									changed = true;
								}
							}
						}
					}
				}
			} while (changed);
		}
	}

}
}
