// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
namespace Astra.Ssa {
public class SsaConstructorUnwindField : Object {
	public SsaStructField field { get; private set; }
	public SsaCleanupContract? cleanup { get; private set; }
	public StructValueShape? shape { get; private set; }
	internal SsaConstructorUnwindField (SsaStructField field, SsaCleanupContract? cleanup, StructValueShape? shape = null) {
		this.field = field;
		this.cleanup = cleanup;
		this.shape = shape;
	}

}
public class SsaConstructorAbort : SsaInstruction {
	public SsaReceiver receiver { get; private set; }
	public GenericArray<SsaConstructorUnwindField> fields { get; private set; default = new GenericArray<SsaConstructorUnwindField> (); }
	public GenericArray<SsaProperty> lazy_properties { get; private set; default = new GenericArray<SsaProperty> (); }
	internal SsaConstructorAbort (SourceSpan span, SsaReceiver receiver) {
		base (span, null, -1);
		this.receiver = receiver;
	}

}
internal class SsaExceptionDisposition : Object {
	internal SsaNode effect;
	internal SsaValue value;
	internal SsaExceptionDisposition (SsaNode effect, SsaValue value) {
		this.effect = effect;
		this.value = value;
	}

}
public class SsaExceptionHandler : Object {
	private WeakRef dispatch_identity;
	private WeakRef matched_identity;
	private WeakRef next_identity;
	public SsaBlock? dispatch { owned get { return (SsaBlock?) dispatch_identity.get (); } }
	public SsaBlock? matched { owned get { return (SsaBlock?) matched_identity.get (); } }
	public SsaBlock? next { owned get { return (SsaBlock?) next_identity.get (); } }
	public SsaExceptionMatch selection { get; private set; }
	public SsaCatchBorrow borrow { get; private set; }
	internal SsaExceptionHandler (SsaBlock dispatch, SsaBlock matched, SsaBlock next, SsaExceptionMatch selection, SsaCatchBorrow borrow) {
		dispatch_identity = WeakRef (dispatch);
		matched_identity = WeakRef (matched);
		next_identity = WeakRef (next);
		this.selection = selection;
		this.borrow = borrow;
	}

}
public enum SsaHeapOwnerAction {
	ACQUIRE, MOVE, RETURN, RELEASE, END, READ
}

public class SsaHeapOwner : Object {
	public Astra.Text.TextLoanExtent? text_extent { get; internal set; }
	public SsaStructField? record_field { get; internal set; }
	public StructLeafPath? record_path { get; internal set; }
	public int record_rank { get; internal set; default = -1; }
	public int cleanup_position { get; private set; }
	public int ordinal { get; private set; }
	public int source_ordinal { get; private set; }
	public SsaCleanupContract cleanup { get; private set; }
	private WeakRef record_identity;
	public SsaStruct? record_type { owned get { return (SsaStruct?) record_identity.get (); } }
	internal SsaHeapOwner (int ordinal, int source_ordinal, SsaCleanupContract cleanup, int cleanup_position = -1, SsaStruct? record_type = null) {
		this.record_identity = WeakRef (record_type);
		this.cleanup_position = cleanup_position;
		this.ordinal = ordinal;
		this.source_ordinal = source_ordinal;
		this.cleanup = cleanup;
	}

}
public class SsaHeapOwnerEvent : SsaInstruction {
	public SsaHeapOwner? owner { get; private set; }
	public SsaHeapOwnerAction action { get; private set; }
	public SsaValue value { get; private set; }
	public SsaNode? effect { get; private set; }
	internal SsaHeapOwnerEvent (SourceSpan span, SsaHeapOwner? owner, SsaHeapOwnerAction action, SsaValue value, SsaNode? effect = null) {
		base (span, null, -1);
		this.owner = owner;
		this.action = action;
		this.value = value;
		this.effect = effect;
	}

}
public class SsaRecordAcquire : SsaInstruction {
	public StructLeafPath? path { get; private set; }
	public int rank { get; private set; }
	public SsaHeapOwner owner { get; private set; }
	public SsaHeapOwner? source_owner { get; private set; }
	public SsaValue pointer { get; private set; }
	public GenericArray<SsaValue> fields { get; private set; }
	internal SsaRecordAcquire (SourceSpan span, SsaHeapOwner owner, SsaHeapOwner? source_owner, SsaValue pointer, GenericArray<SsaValue> fields) {
		base (span, null, -1);
		this.path = owner.record_path;
		this.rank = owner.record_rank;
		this.owner = owner;
		this.source_owner = source_owner;
		this.pointer = pointer;
		this.fields = fields;
	}

}
public class SsaRecordMove : SsaInstruction {
	public StructLeafPath? path { get; private set; }
	public int rank { get; private set; }
	public SsaHeapOwner source { get; private set; }
	public SsaHeapOwner destination { get; private set; }
	public SsaValue pointer { get; private set; }
	public GenericArray<SsaValue> fields { get; private set; }
	internal SsaRecordMove (SourceSpan span, SsaHeapOwner source, SsaHeapOwner destination, SsaValue pointer, GenericArray<SsaValue> fields) {
		base (span, null, -1);
		this.path = source.record_path;
		this.rank = source.record_rank;
		this.source = source;
		this.destination = destination;
		this.pointer = pointer;
		this.fields = fields;
	}

}
public class SsaRecordTake : SsaInstruction {
	public SsaHeapOwner source { get; private set; }
	public SsaHeapOwner destination { get; private set; }
	public SsaValue pointer { get; private set; }
	public StructLeafPath? path { get; private set; }
	public int rank { get; private set; }
	public GenericArray<SsaValue> fields { get; private set; }
	internal SsaRecordTake (SourceSpan span, SsaHeapOwner source, SsaHeapOwner destination, SsaValue pointer) {
		base (span, null, -1);
		this.source = source;
		this.destination = destination;
		this.pointer = pointer;
		this.path = source.record_path;
		this.rank = source.record_rank;
		this.fields = new GenericArray<SsaValue> ();
		fields.add (pointer);
	}

}
public class SsaRecordReplace : SsaInstruction {
	public SsaHeapOwner owner { get; private set; }
	public SsaHeapOwner? source_owner { get; private set; }
	public SsaValue incoming { get; private set; }
	public SsaValue old_value { get; private set; }
	public SsaCleanupInstruction retirement { get; private set; }
	public StructLeafPath? path { get; private set; }
	public int rank { get; private set; }
	public GenericArray<SsaValue> fields { get; private set; }
	internal SsaRecordReplace (SourceSpan span, SsaHeapOwner owner, SsaHeapOwner? source_owner, SsaValue incoming, SsaValue old_value, SsaCleanupInstruction retirement) {
		base (span, null, -1);
		this.owner = owner;
		this.source_owner = source_owner;
		this.incoming = incoming;
		this.old_value = old_value;
		this.retirement = retirement;
		this.path = owner.record_path;
		this.rank = owner.record_rank;
		this.fields = new GenericArray<SsaValue> ();
		fields.add (old_value);
		retirement.record_replacement = this;
	}

}
private class RecordPointerFacts : Object {
	internal GenericArray<SsaValue> values = new GenericArray<SsaValue> ();
	internal bool disarmed;
	internal RecordPointerFacts copy() {
		var result = new RecordPointerFacts ();
		result.disarmed = disarmed;
		foreach (var value in values) {
			result.values.add (value);
		}
		return result;
	}

	internal bool include(RecordPointerFacts incoming) {
		bool changed = false;
		if (incoming.disarmed && !disarmed) {
			disarmed = true;
			changed = true;
		}
		foreach (var value in incoming.values) {
			if (!values.find (value)) {
				values.add (value);
				changed = true;
			}
		}
		return changed;
	}

}
internal class SsaHeapOwnerFlow : Object {
	private static void verify_enum_effect(SsaHeapOwnerEvent event, SsaBlock block) throws SsaError {
		var capture = event.effect as SsaEnumScalarCapture;
		var commit = event.effect as SsaEnumScalarCommit;
		var extraction = event.effect as SsaEnumReadScalar;
		bool valid = capture != null ? event.owner == capture.owner && event.action == SsaHeapOwnerAction.READ && event.value == capture.pointer : commit != null ? event.owner == commit.capture.owner && event.action == SsaHeapOwnerAction.MOVE && event.value == commit.capture.pointer : extraction != null && event.owner == extraction.owner && event.action == SsaHeapOwnerAction.ACQUIRE && event.value == extraction.result;
		if (!valid || !block.instructions.find ((SsaInstruction) event.effect)) {
			throw new SsaError.INVALID_SSA ("enum scalar responsibility lost its exact original acquisition, loan or committed source");
		}
	}

	// Reconstruct the allocation-neutral incoming scalar-owner boundary from
	// this stage's signature. Checked effects/results keep their older proof.
	internal static bool local_input(SsaFunction function) {
		if (function.implicit_receiver != null || function.async_body != null || function.throws_type != null || function.owned_cleanup != null || function.object_storage.length != 0 || (function.return_type.kind != TypeKind.VOID && !GenericBorrowTypes.scalar (function.return_type))) {
			return false;
		}
		int inputs = 0;
		foreach (var parameter in function.parameters) {
			if (parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER && (parameter.semantic_type is ClassType || parameter.semantic_type is HandleType)) {
				inputs++;
			} else if (parameter.pointer_contract != PointerParameterContract.UNMANAGED || !GenericBorrowTypes.scalar (parameter.semantic_type)) {
				return false;
			}
		}
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var call = instruction as SsaCallInstruction;
				if ((call != null && call.target.throws_type != null) || instruction is SsaExceptionTransfer) {
					return false;
				}
			}
		}
		return inputs == 1;
	}

	private static bool persistent(SsaFunction function, SsaCleanupContract cleanup) {
		foreach (var owner in function.heap_owners) {
			if (owner.cleanup == cleanup) {
				return true;
			}
		}
		return cleanup.shared_type != null || cleanup.closure_type != null || cleanup.is_heap_object || (function.async_body != null && !cleanup.is_object && !cleanup.is_buffer);
	}

	internal static GenericArray<SsaEdge> pointer_edges(SsaBlock block) {
		var result = new GenericArray<SsaEdge> ();
		if (block.terminator is SsaBranch) {
			result.add (((SsaBranch) block.terminator).edge);
		} else if (block.terminator is SsaConditionalBranch) {
			var branch = (SsaConditionalBranch) block.terminator;
			var literal = branch.condition as SsaBooleanConstant;
			if (literal == null || literal.literal == BooleanLiteral.TRUE) {
				result.add (branch.true_edge);
			}
			if (literal == null || literal.literal == BooleanLiteral.FALSE) {
				result.add (branch.false_edge);
			}
		} else if (block.terminator is SsaBufferAllocationBranch) {
			var branch = (SsaBufferAllocationBranch) block.terminator;
			result.add (branch.success_edge);
			result.add (branch.failure_edge);
		} else if (block.terminator is SsaEnumDispatch) {
			var dispatch = (SsaEnumDispatch) block.terminator;
			foreach (var branch in dispatch.cases) {
				result.add (branch.edge);
			}
			result.add (dispatch.invalid_edge);
		}
		return result;
	}

	private static GenericArray<SsaBlock> owner_successors(SsaFunction function, SsaBlock block) {
		// Enum dispatch is control flow for every owner, including contexts
		// and ordinary Classes in functions without a local owning record.
		var result = new GenericArray<SsaBlock> ();
		foreach (var edge in pointer_edges (block)) {
			result.add (edge.target);
		}
		return result;
	}

	private static bool exact_record_pointer(SsaValue value, RecordPointerFacts expected, SsaFunction function, int owner, RecordPointerFacts[,] exits, HashTable<SsaValue, bool> active) {
		if (expected.disarmed && expected.values.length == 0 && value is SsaNullPointerConstant) {
			return true;
		}
		if (!expected.disarmed && expected.values.length == 1 && expected.values[0] == value) {
			return true;
		}
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				if (instruction.result != value) {
					continue;
				}
				if (instruction is SsaClassUpcast) {
					return exact_record_pointer (((SsaClassUpcast) instruction).reference, expected, function, owner, exits, active);
				}
				if (instruction is SsaObjectValidateInstruction) {
					return exact_record_pointer (((SsaObjectValidateInstruction) instruction).reference, expected, function, owner, exits, active);
				}
			}
		}
		var parameter = value as SsaBlockParameter;
		if (parameter == null) {
			return false;
		}
		// SSA loop parameters can refer back to themselves. All reachable
		// incoming edges still need an owned/disarmed origin; the existing
		// lifetime proof rejects a cycle without an actual acquisition.
		if (active.contains (value)) {
			return true;
		}
		active.insert (value, true);
		bool found = false;
		bool valid = true;
		foreach (var block in function.blocks) {
			foreach (var edge in pointer_edges (block)) {
				for (int p = 0; p < edge.target.parameters.length; p++) {
					if (edge.target.parameters[p] != parameter) {
						continue;
					}
					var incoming = exits[block.ordinal, owner];
					if (incoming == null) {
						continue;
					}
					found = true;
					// The defining join must preserve both the pointer and its
					// owner state on each predecessor, not just a union of types.
					if ((incoming.disarmed && !expected.disarmed) || !exact_record_pointer (edge.arguments[p], incoming, function, owner, exits, active)) {
						valid = false;
					}
					foreach (var token in incoming.values) {
						if (!expected.values.find (token)) {
							valid = false;
						}
					}
				}
			}
		}
		active.remove (value);
		return found && valid;
	}

	// Pointer evidence supplements the existing owner-event authority. Exact
	// heap Class returns also retain the current pointer of their source owner.
	private static void verify_record_pointers(SsaFunction function) throws SsaError {
		var contracts = new HashTable<SsaCleanupContract, bool> (direct_hash, direct_equal);
		bool incoming_local = local_input (function);
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var invocation = instruction as SsaCallableInvocation;
				if (invocation != null) {
					foreach (var borrow in invocation.borrowed_arguments) {
						if (borrow.source_owner != null) {
							contracts.insert (borrow.source_owner.cleanup, true);
						}
					}
				}
			}
		}
		foreach (var owner in function.heap_owners) {
			if (owner.record_type != null || incoming_local || owner.cleanup.shared_type != null || owner.cleanup.closure_type != null || owner.cleanup.external_symbol == "astra_linux_payload_close") {
				contracts.insert (owner.cleanup, true);
			}
		}
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var scoped = instruction as SsaScopedAllocator;
				if (scoped != null) {
					contracts.insert (scoped.owner.cleanup, true);
				}
				var selection = instruction as SsaStorageReceiverInstruction;
				var restored = instruction as SsaFallibleInputRestore;
				if (restored != null) {
					contracts.insert (restored.owner.cleanup, true);
				}
				var frame_restore = instruction as SsaFrameInputRestore;
				if (frame_restore != null) {
					contracts.insert (frame_restore.owner.cleanup, true);
				}
				if (selection != null && selection.context_owner != null) {
					contracts.insert (selection.context_owner.cleanup, true);
				}
				var task = instruction as SsaTaskCreate;
				if (task != null && task.context_owner != null) {
					contracts.insert (task.context_owner.cleanup, true);
				}
				var buffer = instruction as SsaBufferAllocateInstruction;
				if (buffer != null && buffer.context_owner != null) {
					contracts.insert (buffer.context_owner.cleanup, true);
				}
				var bridge = instruction as SsaTaskWait;
				if (bridge != null && bridge.bridge_owner != null) {
					contracts.insert (bridge.bridge_owner.cleanup, true);
				}
			}
		}
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var append = instruction as SsaSlotsEffect;
				if (append != null && (append.action == SsaSlotsAction.APPEND || append.action == SsaSlotsAction.REPLACE) && append.owner != null) {
					contracts.insert (append.owner.cleanup, true);
				}
			}
		}
		var returned_owners = new HashTable<SsaHeapOwner, bool> (direct_hash, direct_equal);
		if (function.heap_result) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var event = instruction as SsaHeapOwnerEvent;
					if (event != null && event.action == SsaHeapOwnerAction.RETURN && event.owner != null && event.owner.cleanup.is_heap_object && event.owner.cleanup.object_class.semantic_type == function.return_type) {
						returned_owners.insert (event.owner, true);
					}
				}
			}
		}
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var take = instruction as SsaSlotsValueInstruction;
				if (take != null && take.action == OwnerSlotsAction.TAKE && take.owner != null) {
					contracts.insert (take.owner.cleanup, true);
				}
			}
		}
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var capture = instruction as SsaEnumScalarCapture;
				var read = instruction as SsaEnumReadScalar;
				if (capture != null) {
					contracts.insert (capture.owner.cleanup, true);
				}
				if (read != null) {
					contracts.insert (read.owner.cleanup, true);
				}
			}
		}
		if (contracts.size () == 0 && returned_owners.size () == 0) {
			return;
		}
		int count = function.heap_owners.length;
		RecordPointerFacts[,] entries = new RecordPointerFacts[function.blocks.length, count];
		RecordPointerFacts[,] exits = new RecordPointerFacts[function.blocks.length, count];
		for (int o = 0; o < count; o++) {
			entries[function.entry.ordinal, o] = new RecordPointerFacts ();
		}
		for (int pass = 0; pass < 2; pass++) {
			bool changed = false;
			do {
				changed = false;
				foreach (var block in function.blocks) {
					if (entries[block.ordinal, 0] == null) {
						continue;
					}
					var state = new RecordPointerFacts[count];
					for (int o = 0; o < count; o++) {
						state[o] = entries[block.ordinal, o].copy ();
					}
					foreach (var instruction in block.instructions) {
						var event = instruction as SsaHeapOwnerEvent;
						if (event == null || event.owner == null || (!contracts.contains (event.owner.cleanup) && !returned_owners.contains (event.owner))) {
							continue;
						}
						int o = event.owner.ordinal;
						if (event.action == SsaHeapOwnerAction.ACQUIRE) {
							if (pass == 1) {
								for (int other = 0; other < count; other++) {
									if (other != o && state[other].values.find (event.value)) {
										throw new SsaError.INVALID_SSA ("%s acquisition duplicates a still-live original owner pointer", event.owner.record_type == null ? "heap Class" : "record Resource");
									}
								}
							}
							state[o] = new RecordPointerFacts ();
							state[o].values.add (event.value);
						} else {
							if (pass == 1 && !exact_record_pointer (event.value, state[o], function, o, exits, new HashTable<SsaValue, bool> (direct_hash, direct_equal))) {
								throw new SsaError.INVALID_SSA ("%s disposition lost the current exact owner pointer on a control edge in %s block #%d owner #%d action %d", event.owner.record_type == null ? "heap Class" : "record Resource", function.name, block.ordinal, event.owner.ordinal, (int) event.action);
							}
							if (event.action != SsaHeapOwnerAction.READ) {
								state[o] = new RecordPointerFacts ();
								state[o].disarmed = event.action != SsaHeapOwnerAction.END;
							}
						}
					}
					for (int o = 0; o < count; o++) {
						exits[block.ordinal, o] = state[o];
					}
					if (pass == 0) {
						foreach (var edge in pointer_edges (block)) {
							for (int o = 0; o < count; o++) {
								if (entries[edge.target.ordinal, o] == null) {
									entries[edge.target.ordinal, o] = state[o].copy ();
									changed = true;
								} else {
									changed = entries[edge.target.ordinal, o].include (state[o]) || changed;
								}
							}
						}
					}
				}
			} while (changed);
		}
	}

	private static int parameter_ordinal(SsaFunction function, int physical) {
		int logical = physical;
		foreach (var group in function.struct_parameters) {
			if (group.first_leaf < physical) {
				logical -= (int) group.shape.leaves.length - 1;
			}
		}
		foreach (var group in function.buffer_parameters) {
			if (group.first_leaf < physical) {
				logical--;
			}
		}
		return logical;
	}

	internal static HashTable<SsaHeapOwner, int> parameter_owners(SsaFunction function) {
		var result = new HashTable<SsaHeapOwner, int> (direct_hash, direct_equal);
		var seen = new HashTable<SsaFunctionParameter, bool> (direct_hash, direct_equal);
		foreach (var instruction in function.entry.instructions) {
			var record = instruction as SsaStructBoundaryAcquire;
			if (record != null && record.parameter != null) {
				foreach (var owner in record.owners) {
					result.insert (owner, record.parameter.source_ordinal);
				}
			}
			var event = instruction as SsaHeapOwnerEvent;
			var parameter = event == null ? null : event.value as SsaFunctionParameter;
			if (event == null || event.action != SsaHeapOwnerAction.ACQUIRE || event.owner == null || parameter == null || parameter.pointer_contract != PointerParameterContract.OWNED_TRANSFER || seen.contains (parameter)) {
				continue;
			}
			for (int i = 0; i < function.parameters.length; i++) {
				if (function.parameters[i] == parameter) {
					result.insert (event.owner, parameter_ordinal (function, i));
					seen.insert (parameter, true);
					break;
				}
			}
		}
		return result;
	}

	private static int callable_read_count(SsaCallableInvocation invocation, SsaHeapOwner owner, SsaValue value) {
		int count = 0;
		foreach (var loan in invocation.borrowed_arguments) {
			if (loan.source_owner == owner && loan.value == value) {
				count++;
			}
		}
		var closure = invocation as SsaClosureCall;
		if (closure != null && closure.source_owner == owner && closure.callee == value) {
			count++;
		}
		return count;
	}

	internal static SsaLifetimeFacts verify(SsaFunction function, bool all_lifetimes = false) throws SsaError {
		var facts = new SsaLifetimeFacts (function, all_lifetimes);
		var parameter_cleanup_order = parameter_owners (function);
		if (function.heap_result) {
			foreach (var block in function.blocks) {
				var returned = block.terminator as SsaOwnershipReturn;
				if (returned == null) {
					continue;
				}
				int captures = 0;
				foreach (var instruction in block.instructions) {
					var event = instruction as SsaHeapOwnerEvent;
					if (event != null && event.action == SsaHeapOwnerAction.RETURN && event.value == returned.value) {
						captures++;
					}
				}
				if (captures != 1) {
					throw new SsaError.INVALID_SSA ("heap result requires one exact captured owner return event");
				}
			}
		}
		var associated = new HashTable<SsaNode, bool> (direct_hash, direct_equal);
		var boundary_owners = new HashTable<SsaStructBoundary, HashTable<SsaHeapOwner, bool>> (direct_hash, direct_equal);
		var callable_reads = new HashTable<SsaNode, GenericArray<SsaHeapOwnerEvent>> (direct_hash, direct_equal);
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var event = instruction as SsaHeapOwnerEvent;
				if (event == null) {
					continue;
				}
				if (event.owner != null && (event.owner.ordinal < 0 || event.owner.ordinal >= function.heap_owners.length || function.heap_owners[event.owner.ordinal] != event.owner)) {
					throw new SsaError.INVALID_SSA ("heap ownership event lost exact function owner authority");
				}
				if (event.effect != null) {
					var scoped = event.effect as SsaScopedAllocator;
					if (scoped != null) {
						if (associated.contains (scoped) || event.owner != scoped.owner || event.action != SsaHeapOwnerAction.ACQUIRE || event.value != scoped.result || !block.instructions.find (scoped)) {
							throw new SsaError.INVALID_SSA ("scoped context requires one exact intrinsic acquisition");
						}
						associated.insert (scoped, true);
						continue;
					}
					var callable = event.effect as SsaCallableInvocation;
					if (callable != null) {
						if (event.owner == null || event.action != SsaHeapOwnerAction.READ || !block.instructions.find ((SsaInstruction) event.effect)) {
							throw new SsaError.INVALID_SSA ("callable read requires its exact same-block owner and invocation");
						}
						int expected = callable_read_count (callable, event.owner, event.value);
						var reads = callable_reads.lookup (event.effect);
						if (reads == null) {
							reads = new GenericArray<SsaHeapOwnerEvent> ();
							callable_reads.insert (event.effect, reads);
						}
						int prior = 0;
						foreach (var read in reads) {
							if (read.owner == event.owner && read.value == event.value) {
								prior++;
							}
						}
						if (expected == 0 || prior >= expected) {
							throw new SsaError.INVALID_SSA ("callable read duplicates or invents an original borrowed operand");
						}
						reads.add (event);
						associated.insert (event.effect, true);
						continue;
					}
					if (event.effect is SsaEnumScalarCapture || event.effect is SsaEnumScalarCommit || event.effect is SsaEnumReadScalar) {
						if (associated.contains (event.effect)) {
							throw new SsaError.INVALID_SSA ("enum scalar effect has duplicate responsibility");
						}
						verify_enum_effect (event, block);
						associated.insert (event.effect, true);
						continue;
					}
					var bridge = event.effect as SsaTaskWait;
					if (bridge != null) {
						if (associated.contains (bridge) || event.owner == null || event.action != SsaHeapOwnerAction.READ || bridge.bridge_owner != event.owner || bridge.bridge_executor != event.value || !block.instructions.find (bridge)) {
							throw new SsaError.INVALID_SSA ("worker bridge lost exact original pool owner and bounded asynchronous observation loan");
						}
						associated.insert (bridge, true);
						continue;
					}
					var frame = event.effect as SsaTaskCreate;
					if (frame != null) {
						if (associated.contains (frame) || event.owner == null || event.action != SsaHeapOwnerAction.READ || frame.context_owner != event.owner || frame.allocation_context != event.value || !block.instructions.find (frame)) {
							throw new SsaError.INVALID_SSA ("task frame context read lost exact original live backing owner and allocation effect");
						}
						associated.insert (frame, true);
						continue;
					}
					var frame_restore = event.effect as SsaFrameInputRestore;
					if (frame_restore != null) {
						if (associated.contains (frame_restore) || event.owner != frame_restore.owner || event.action != SsaHeapOwnerAction.ACQUIRE || event.value != frame_restore.result || !block.instructions.find (frame_restore)) {
							throw new SsaError.INVALID_SSA ("checked frame input restore requires exact caller acquisition");
						}
						associated.insert (frame_restore, true);
						continue;
					}
					var selection = event.effect as SsaStorageReceiverInstruction;
					var restored = event.effect as SsaFallibleInputRestore;
					if (restored != null) {
						if (associated.contains (restored) || event.owner != restored.owner || event.action != SsaHeapOwnerAction.ACQUIRE || event.value != restored.result || !block.instructions.find (restored)) {
							throw new SsaError.INVALID_SSA ("fallible input restore requires its exact caller ownership acquisition");
						}
						associated.insert (restored, true);
						continue;
					}
					var buffer = event.effect as SsaBufferAllocateInstruction;
					if (buffer != null) {
						var request = block.terminator as SsaBufferAllocationBranch;
						bool local = buffer.failure == null ? block.instructions.find(buffer) : request != null && request.allocation == buffer;
						if (associated.contains (buffer) || event.owner == null || event.action != SsaHeapOwnerAction.READ || buffer.context_owner != event.owner || buffer.allocation_context != event.value || !local) {
							throw new SsaError.INVALID_SSA ("byte allocation lost exact original live context and same-block allocation effect");
						}
						associated.insert (buffer, true);
						continue;
					}
					if (selection != null) {
						if (associated.contains (selection) || event.owner == null || event.action != SsaHeapOwnerAction.READ || selection.context_owner != event.owner || selection.allocation_context != event.value || !block.instructions.find (selection)) {
							throw new SsaError.INVALID_SSA ("allocator context read lost its exact instance, live owner and same-block allocation effect");
						}
						associated.insert (selection, true);
						continue;
					}
					var bulk = event.effect as SsaStructBoundary;
					if (bulk != null) {
						var seen = boundary_owners.lookup (bulk);
						if (seen == null) {
							seen = new HashTable<SsaHeapOwner, bool> (direct_hash, direct_equal);
							boundary_owners.insert (bulk, seen);
						}
						if (event.owner == null || seen.contains (event.owner)) {
							throw new SsaError.INVALID_SSA ("record boundary effect duplicates a field responsibility");
						}
						seen.insert (event.owner, true);
					}
					if (bulk == null && associated.contains (event.effect)) {
						throw new SsaError.INVALID_SSA ("heap ownership effect has duplicate responsibility");
					}
					associated.insert (event.effect, true);
					var cleanup = event.effect as SsaCleanupInstruction;
					var argument = event.effect as SsaOwnedTransfer;
					var transfer = event.effect as SsaExceptionTransfer;
					var record_acquire = event.effect as SsaRecordAcquire;
					var record_move = event.effect as SsaRecordMove;
					var record_boundary = event.effect as SsaStructBoundary;
					var record_take = event.effect as SsaRecordTake;
					var record_replace = event.effect as SsaRecordReplace;
					var actor_read = event.effect as SsaActorSend;
					var indirect_read = event.effect as SsaCallableInvocation;
					var shared_read = event.effect as SsaSharedOperation;
					var closure_read = event.effect as SsaClosureCall;
					var retained_read = event.effect as SsaRetainedOperation;
					var payload_read = event.effect as SsaAsyncDelay;
					var slots = event.effect as SsaSlotsEffect;
					var take = event.effect as SsaSlotsValueInstruction;
					bool exact_indirect = false;
					if (indirect_read != null && event.action == SsaHeapOwnerAction.READ && event.owner != null) {
						foreach (var borrow in indirect_read.borrowed_arguments) {
							if (borrow.source_owner == event.owner && borrow.value == event.value && borrow.ordinal >= 0 && borrow.ordinal < indirect_read.arguments.length && indirect_read.arguments[borrow.ordinal] == event.value) {
								exact_indirect = true;
							}
						}
					}
					if (indirect_read != null && exact_indirect ? false : actor_read != null ? (event.action != SsaHeapOwnerAction.READ || actor_read.sender_owner != event.owner || actor_read.sender != event.value || event.owner == null) : payload_read != null ? (!payload_read.payload || event.action != SsaHeapOwnerAction.READ || payload_read.source_owner != event.owner || payload_read.ticks != event.value || event.owner == null) : shared_read != null ? (event.action != SsaHeapOwnerAction.READ || shared_read.source_owner != event.owner || shared_read.operand != event.value || event.owner == null) : retained_read != null ? (event.action != SsaHeapOwnerAction.READ || retained_read.source_owner != event.owner || retained_read.callee != event.value || event.owner == null) : closure_read != null ? (event.action != SsaHeapOwnerAction.READ || closure_read.source_owner != event.owner || closure_read.callee != event.value || event.owner == null) : take != null ? (take.action != OwnerSlotsAction.TAKE || take.owner != event.owner || take.result != event.value || event.action != SsaHeapOwnerAction.ACQUIRE || event.owner == null || take.store.field.slots_cleanup != event.owner.cleanup): slots != null ? ((slots.action != SsaSlotsAction.APPEND && slots.action != SsaSlotsAction.REPLACE) || slots.owner != event.owner || slots.incoming != event.value || event.action != SsaHeapOwnerAction.MOVE || event.owner == null || slots.store.field.slots_cleanup != event.owner.cleanup) : record_boundary != null ? (event.owner == null || !record_boundary.owns_value (event.owner, event.value) || event.action != ((record_boundary is SsaStructBoundaryAcquire) ? SsaHeapOwnerAction.ACQUIRE : SsaHeapOwnerAction.MOVE)) : record_acquire != null ? (record_acquire.owner != event.owner || record_acquire.pointer != event.value || event.action != SsaHeapOwnerAction.ACQUIRE) : record_move != null ? (record_move.source != event.owner || record_move.pointer != event.value || event.action != SsaHeapOwnerAction.MOVE) : record_take != null ? (record_take.source != event.owner || record_take.pointer != event.value || event.action != SsaHeapOwnerAction.MOVE) : record_replace != null ? (record_replace.owner != event.owner || record_replace.incoming != event.value || event.action != SsaHeapOwnerAction.ACQUIRE) : cleanup != null ? (cleanup.value != event.value || !persistent (function, cleanup.cleanup) || (event.owner != null && cleanup.cleanup != event.owner.cleanup)) : argument != null ? (argument.value != event.value || event.owner == null || argument.source_ordinal != event.owner.source_ordinal || !persistent (function, argument.cleanup)) : transfer != null ? (transfer.source != event.value || event.owner == null || transfer.owner_ordinal != event.owner.source_ordinal) : true) {
						throw new SsaError.INVALID_SSA ("heap ownership lost exact original transfer/cleanup operand");
					}
					bool present = false;
					foreach (var candidate in block.instructions) {
						if (candidate == event.effect) {
							present = true;
						}
						var call = candidate as SsaCallInstruction;
						if (call != null) {
							foreach (var owned in call.owned_arguments) {
								if (owned == event.effect) {
									present = true;
								}
							}
						}
						var indirect_callsite = candidate as SsaCallableInvocation;
						if (indirect_callsite != null) {
							foreach (var owned in indirect_callsite.owned_arguments) {
								if (owned == event.effect) {
									present = true;
								}
							}
						}
					}
					if (!present) {
						throw new SsaError.INVALID_SSA ("heap ownership effect moved outside its exact control edge");
					}
				}
				if (event.action == SsaHeapOwnerAction.RETURN) {
					var returned = block.terminator as SsaOwnershipReturn;
					if (returned == null || returned.value != event.value) {
						throw new SsaError.INVALID_SSA ("heap return lost exact original captured owner");
					}
				}
			}
		}
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var cleanup = instruction as SsaCleanupInstruction;
				var transfer = instruction as SsaExceptionTransfer;
				if (instruction is SsaEnumScalarCapture || instruction is SsaEnumScalarCommit || instruction is SsaEnumReadScalar || (instruction is SsaAsyncDelay && ((SsaAsyncDelay) instruction).payload) || (instruction is SsaSharedOperation && ((SsaSharedOperation) instruction).source_owner != null) || (instruction is SsaActorSend && ((SsaActorSend) instruction).sender_owner != null) || (instruction is SsaRetainedOperation && ((SsaRetainedOperation) instruction).source_owner != null) || (instruction is SsaClosureCall && ((SsaClosureCall) instruction).source_owner != null) || (instruction is SsaSlotsEffect && (((SsaSlotsEffect) instruction).action == SsaSlotsAction.APPEND || ((SsaSlotsEffect) instruction).action == SsaSlotsAction.REPLACE)) || (instruction is SsaSlotsValueInstruction && ((SsaSlotsValueInstruction) instruction).action == OwnerSlotsAction.TAKE) || (cleanup != null && persistent (function, cleanup.cleanup)) || transfer != null) {
					if (!associated.contains (instruction)) {
						throw new SsaError.INVALID_SSA ("heap ownership has unassociated or duplicate cleanup/transfer");
					}
				}
				var call = instruction as SsaCallInstruction;
				if (call != null) {
					foreach (var argument in call.owned_arguments) {
						if (persistent (function, argument.cleanup) && argument.source_ordinal >= 0 && !associated.contains (argument)) {
							throw new SsaError.INVALID_SSA ("heap call has unassociated original owner transfer");
						}
					}
				}
			}
		}
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var callable = instruction as SsaCallableInvocation;
				if (callable == null) {
					continue;
				}
				foreach (var argument in callable.owned_arguments) {
					if (persistent (function, argument.cleanup) && argument.source_ordinal >= 0 && !associated.contains (argument)) {
						throw new SsaError.INVALID_SSA ("indirect call has unassociated original owner transfer");
					}
				}
				int expected = 0;
				foreach (var loan in callable.borrowed_arguments) {
					if (loan.source_owner != null) {
						expected++;
					}
				}
				var closure = instruction as SsaClosureCall;
				if (closure != null && closure.source_owner != null) {
					expected++;
				}
				var reads = callable_reads.lookup (instruction);
				if ((reads == null ? 0 : (int) reads.length) != expected) {
					throw new SsaError.INVALID_SSA ("callable invocation lost a complete original owner read group");
				}
			}
		}
		verify_record_pointers (function);
		int count = function.heap_owners.length;
		if (count == 0) {
			return facts;
		}
		int[,] entries = new int[function.blocks.length, count];
		bool[] reachable = new bool[function.blocks.length];
		for (int o = 0; o < count; o++) {
			entries[function.entry.ordinal, o] = 1;
		}
		reachable[function.entry.ordinal] = true;
		for (int pass = 0; pass < 2; pass++) {
			bool changed = false;
			do {
				changed = false;
				foreach (var block in function.blocks) {
					if (!reachable[block.ordinal]) {
						continue;
					}
					int[] state = new int[count];
					for (int o = 0; o < count; o++) {
						state[o] = entries[block.ordinal, o];
					}
					foreach (var instruction in block.instructions) {
						if (pass == 1) {
							facts.capture (instruction, state);
						}
						var event = instruction as SsaHeapOwnerEvent;
						if (event == null || event.owner == null) {
							continue;
						}
						int o = event.owner.ordinal;
						if (pass == 1 && event.action == SsaHeapOwnerAction.END && parameter_cleanup_order.contains (event.owner) && (state[o] & 2) != 0 && (!(event.effect is SsaCleanupInstruction) || ((SsaCleanupInstruction) event.effect).record_replacement == null)) {
							int ordinal = parameter_cleanup_order.lookup (event.owner);
							foreach (var other in parameter_cleanup_order.get_keys ()) {
								if (parameter_cleanup_order.lookup (other) > ordinal && (state[other.ordinal] & 2) != 0) {
									throw new SsaError.INVALID_SSA ("automatic cleanup must preserve reverse parameter declaration order");
								}
							}
						}
						if (pass == 1 && event.owner.record_type != null) {
							if (event.action == SsaHeapOwnerAction.END && (!(event.effect is SsaCleanupInstruction) || ((SsaCleanupInstruction) event.effect).record_replacement == null)) {
								foreach (var other in function.heap_owners) {
									if (other.record_type == event.owner.record_type && other.source_ordinal == event.owner.source_ordinal && other.record_rank > event.owner.record_rank && (state[other.ordinal] & 6) != 0) {
										throw new SsaError.INVALID_SSA ("record retirement lost reverse written field order");
									}
								}
							}
							if (event.action == SsaHeapOwnerAction.ACQUIRE && event.effect is SsaRecordAcquire) {
								foreach (var other in function.heap_owners) {
									if (other.record_type == event.owner.record_type && other.source_ordinal == event.owner.source_ordinal && other.record_rank < event.owner.record_rank && state[other.ordinal] != 2) {
										throw new SsaError.INVALID_SSA ("record acquisition lost initialized field prefix");
									}
								}
							}
						}
						int allowed = event.action == SsaHeapOwnerAction.ACQUIRE ? (event.owner.cleanup.is_heap_object ? 9 : 13) : event.action == SsaHeapOwnerAction.END ? 6 : 2;
						if (event.action == SsaHeapOwnerAction.ACQUIRE && (event.effect is SsaFallibleInputRestore || event.effect is SsaFrameInputRestore || event.effect is SsaStructBoundaryAcquire && ((SsaStructBoundaryAcquire) event.effect).admission_restore != null)) {
							allowed = 4;
						}
						if (pass == 1 && (state[o] == 0 || (state[o] & ~allowed) != 0)) {
							throw new SsaError.INVALID_SSA ("heap owner #%d requires exact initialized/live/moved disposition on every control edge", event.owner.source_ordinal);
						}
						if (event.action != SsaHeapOwnerAction.READ) {
							state[o] = event.action == SsaHeapOwnerAction.ACQUIRE ? 2 : event.action == SsaHeapOwnerAction.END ? 8 : 4;
						}
					}
					if (pass == 1 && (block.terminator is SsaReturn || block.terminator is SsaExceptionReturn || block.terminator is SsaFunctionEnd)) {
						for (int o = 0; o < count; o++) {
							if ((state[o] & 6) != 0) {
								throw new SsaError.INVALID_SSA ("heap owner #%d exits without exact lexical cleanup or transfer disposition", function.heap_owners[o].source_ordinal);
							}
						}
					}
					if (pass == 0) {
						foreach (var next in owner_successors (function, block)) {
							if (!reachable[next.ordinal]) {
								reachable[next.ordinal] = true;
								changed = true;
							}
							for (int o = 0; o < count; o++) {
								int joined = entries[next.ordinal, o] | state[o];
								if (joined != entries[next.ordinal, o]) {
									entries[next.ordinal, o] = joined;
									changed = true;
								}
							}
						}
					}
				}
			} while (changed);
		}
		return facts;
	}

}
internal class SsaExceptionBounds : Object {
	internal GenericArray<ClassType> types = new GenericArray<ClassType> ();
	internal bool add(ClassType type) {
		foreach (var prior in types) {
			if (prior == type) {
				return false;
			}
		}
		types.add (type);
		return true;
	}

	internal bool include(SsaExceptionBounds? other) {
		bool changed = false;
		if (other != null) {
			foreach (var type in other.types) {
				changed = add (type) || changed;
			}
		}
		return changed;
	}

}

public class SsaOwnedArgumentReservation : SsaInstruction {
	private WeakRef invocation = WeakRef (null);
	public SsaInstruction? consumer { owned get { return (SsaInstruction?) invocation.get (); } internal set { invocation.set (value); } }
	public SsaValue? value { get; private set; }
	public SsaBufferPair? pair { get; private set; }
	public int owner_ordinal { get; private set; }
	internal SsaOwnedArgumentReservation (SourceSpan span, SsaValue? value, SsaBufferPair? pair, int owner_ordinal) {
		base (span, null, -1);
		this.value = value;
		this.pair = pair;
		this.owner_ordinal = owner_ordinal;
	}

}
public class SsaOwnedArgumentAbort : SsaInstruction {
	public SsaOwnedArgumentReservation reservation { get; private set; }
	internal SsaOwnedArgumentAbort (SourceSpan span, SsaOwnedArgumentReservation reservation) {
		base (span, null, -1);
		this.reservation = reservation;
	}

}
public class SsaExceptionTransfer : SsaInstruction {
	public SsaValue source { get; private set; }
	public SsaNullPointerConstant disarmed { get; private set; }
	public int owner_ordinal { get; private set; }
	internal SsaExceptionTransfer (SourceSpan span, SsaValue source, SsaNullPointerConstant disarmed, int owner_ordinal, int ordinal) {
		base (span, source.semantic_type, ordinal);
		this.source = source;
		this.disarmed = disarmed;
		this.owner_ordinal = owner_ordinal;
	}

}
public class SsaExceptionStamp : SsaInstruction {
	public SsaValue exception { get; private set; }
	internal SsaExceptionStamp (SourceSpan span, SsaValue exception) {
		base (span, null, -1);
		this.exception = exception;
	}

}
public class SsaExceptionMatch : SsaInstruction {
	public SsaValue exception { get; private set; }
	public ClassType match_type { get; private set; }
	internal SsaExceptionMatch (SourceSpan span, SemanticType bool_type, SsaValue exception, ClassType match_type, int ordinal) {
		base (span, bool_type, ordinal);
		this.exception = exception;
		this.match_type = match_type;
	}

}
public class SsaCatchBorrow : SsaInstruction {
	public SsaValue exception { get; private set; }
	internal SsaCatchBorrow (SourceSpan span, SsaValue exception, ClassType caught_type, int ordinal) {
		base (span, caught_type, ordinal);
		this.exception = exception;
	}

}
public class SsaExceptionReturn : SsaReturn {
	internal SsaExceptionReturn (SourceSpan span, SsaValue exception) {
		base (span, exception);
	}

}
public class SsaExceptionUnreachable : SsaTerminator {
	public SsaValue exception { get; private set; }
	internal SsaExceptionUnreachable (SourceSpan span, SsaValue exception) {
		base (span);
		this.exception = exception;
	}

}
public class SsaGroupCallSuccess : SsaInstruction {
	private WeakRef invocation;
	public SsaCallInstruction? call { owned get { return (SsaCallInstruction?) invocation.get (); } }
	internal SsaGroupCallSuccess (SourceSpan span, SsaCallInstruction call) {
		base (span, null, -1);
		invocation = WeakRef (call);
	}

}
public class SsaCallSuccess : SsaInstruction {
	public SsaCallInstruction call { get; private set; }
	internal SsaCallSuccess (SourceSpan span, SsaCallInstruction call, int ordinal) {
		base (span, call.result.semantic_type, ordinal);
		this.call = call;
	}

}
public class SsaForeignReturn : SsaFunctionEnd {
	public ForeignImportBinding binding { get; internal set; }
	public SsaFunction factory { get; internal set; }
	public GenericArray<SsaValue> consumed { get; private set; default = new GenericArray<SsaValue> (); }
	internal SsaForeignReturn (SourceSpan span, ForeignImportBinding binding, SsaFunction factory, GenericArray<SsaValue>? consumed = null) {
		base (span);
		this.binding = binding;
		this.factory = factory;
		if (consumed != null) {
			foreach (var owner in consumed) {
				this.consumed.add (owner);
			}
		}
	}

}
public class SsaForeignSignalReturn : SsaFunctionEnd {
	public ForeignSignalBinding binding { get; internal set; }
	internal SsaForeignSignalReturn (SourceSpan span, ForeignSignalBinding binding) {
		base (span);
		this.binding = binding;
	}

}

}
