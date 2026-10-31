// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
namespace Astra.Ssa {
public class SsaSuspensionLoan : Object {
	public SuspensionLoanIdentity identity { get; private set; }
	public int parameter_ordinal { get; private set; }
	public SsaAddressableLocal storage { get; private set; }
	public SsaValue view { get; private set; }
	internal SsaSuspensionLoan (SuspensionLoanIdentity identity, int parameter_ordinal, SsaAddressableLocal storage, SsaValue view) {
		this.identity = identity;
		this.parameter_ordinal = parameter_ordinal;
		this.storage = storage;
		this.view = view;
	}
}

public class SsaTaskOwner : Object {
	private SsaTaskAcquire? original_acquisition;
	internal void retain_acquisition(SsaTaskAcquire acquisition) {
		assert (original_acquisition == null);
		original_acquisition = acquisition;
	}
	internal bool matches_acquisition(SsaTaskAcquire acquisition) {
		return original_acquisition == acquisition && acquisition.owner_ordinal == source_ordinal && acquisition.source.semantic_type == contract;
	}
	public int source_ordinal { get; private set; }
	public TaskType contract { get; private set; }
	public Astra.Text.TextLoanExtent? text_extent { get; private set; }
	internal SsaTaskOwner (int source_ordinal, TaskType contract, SsaTaskAcquire? acquisition = null, Astra.Text.TextLoanExtent? text_extent = null) {
		this.text_extent = text_extent;
		this.source_ordinal = source_ordinal;
		this.contract = contract;
		if (acquisition != null) {
			retain_acquisition (acquisition);
		}
	}
}
public class SsaTaskAcquire : SsaInstruction {
	public SsaValue source { get; private set; }
	public int owner_ordinal { get; private set; }
	internal SsaTaskAcquire (SourceSpan span, SsaValue source, int owner_ordinal) {
		base (span, null, -1);
		this.source = source;
		this.owner_ordinal = owner_ordinal;
	}
}
private class TaskPointerFacts : Object {
	internal bool absent = true;
	internal GenericArray<SsaValue> values = new GenericArray<SsaValue> ();
	internal TaskPointerFacts copy() {
		var result = new TaskPointerFacts ();
		result.absent = absent;
		foreach (var value in values) {
			result.values.add (value);
		}
		return result;
	}
	internal bool include(TaskPointerFacts incoming) {
		bool changed = false;
		if (incoming.absent && !absent) {
			absent = true;
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
internal class SsaTaskFlow : Object {
	private static bool exact_pointer(SsaValue value, TaskPointerFacts expected, SsaFunction function, int owner, TaskPointerFacts[,] exits, HashTable<SsaValue, bool> active) {
		if (expected.absent && expected.values.length == 0 && value is SsaTaskAbsent) {
			return true;
		}
		if (!expected.absent && expected.values.length == 1 && expected.values[0] == value) {
			return true;
		}
		var parameter = value as SsaBlockParameter;
		if (parameter == null) {
			return false;
		}
		// Loops still require an original acquisition in the independent
		// disposition proof. Check every reachable predecessor of this phi.
		if (active.contains (value)) {
			return true;
		}
		active.insert (value, true);
		bool found = false;
		bool valid = true;
		foreach (var block in function.blocks) {
			foreach (var edge in SsaHeapOwnerFlow.pointer_edges (block)) {
				for (int p = 0; p < edge.target.parameters.length; p++) {
					if (edge.target.parameters[p] != parameter) {
						continue;
					}
					var incoming = exits[block.ordinal, owner];
					if (incoming == null) {
						continue;
					}
					found = true;
					if ((incoming.absent && !expected.absent) || !exact_pointer (edge.arguments[p], incoming, function, owner, exits, active)) {
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
	private static void verify_pointers(SsaFunction function) throws SsaError {
		int count = function.task_owners.length;
		TaskPointerFacts[,] entries = new TaskPointerFacts[function.blocks.length, count];
		TaskPointerFacts[,] exits = new TaskPointerFacts[function.blocks.length, count];
		for (int o = 0; o < count; o++) {
			entries[function.entry.ordinal, o] = new TaskPointerFacts ();
		}
		for (int pass = 0; pass < 2; pass++) {
			bool changed = false;
			do {
				changed = false;
				foreach (var block in function.blocks) {
					if (entries[block.ordinal, 0] == null) {
						continue;
					}
					var state = new TaskPointerFacts[count];
					for (int o = 0; o < count; o++) {
						state[o] = entries[block.ordinal, o].copy ();
					}
					foreach (var instruction in block.instructions) {
						var acquire = instruction as SsaTaskAcquire;
						var move = instruction as SsaTaskMove;
						var end = instruction as SsaTaskEnd;
						var borrow = instruction as SsaTaskBorrow;
						if (acquire == null && move == null && end == null && borrow == null) {
							continue;
						}
						int ordinal = acquire != null ? acquire.owner_ordinal : move != null ? move.owner_ordinal : end != null ? end.owner_ordinal : borrow.owner_ordinal;
						int o = 0;
						while (function.task_owners[o].source_ordinal != ordinal) {
							o++;
						}
						SsaValue pointer = acquire != null ? acquire.source : move != null ? move.source : end != null ? end.source : borrow.source;
						if (acquire != null) {
							state[o] = new TaskPointerFacts ();
							state[o].absent = false;
							state[o].values.add (pointer);
						} else {
							if (pass == 1 && !exact_pointer (pointer, state[o], function, o, exits, new HashTable<SsaValue, bool> (direct_hash, direct_equal))) {
								throw new SsaError.INVALID_SSA ("task disposition lost its current exact live/absent pointer on a control edge");
							}
							if (borrow == null) {
								state[o] = new TaskPointerFacts ();
							}
						}
					}
					for (int o = 0; o < count; o++) {
						exits[block.ordinal, o] = state[o];
					}
					if (pass == 0) {
						foreach (var edge in SsaHeapOwnerFlow.pointer_edges (block)) {
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
	internal static void verify(SsaFunction function) throws SsaError {
		int count = function.task_owners.length;
		var producers = new HashTable<SsaValue, SsaInstruction> (direct_hash, direct_equal);
		var consumers = new HashTable<SsaValue, int> (direct_hash, direct_equal);
		var acquisitions = new HashTable<SsaTaskOwner, bool> (direct_hash, direct_equal);
		foreach (var parameter in function.parameters) {
			if (parameter.semantic_type is TaskType || parameter.semantic_type is ExecutorType) {
				throw new SsaError.INVALID_SSA ("unique tasks and executors cannot cross an ordinary parameter boundary");
			}
		}
		if (function.return_type is TaskType || function.return_type is ExecutorType) {
			throw new SsaError.INVALID_SSA ("unique tasks and executors cannot cross an ordinary result boundary");
		}
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				if (instruction is SsaTaskCreate || instruction is SsaTaskMove || instruction is SsaTaskBorrow) {
					producers.insert (instruction.result, instruction);
				}
			}
		}
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				SsaValue? consumed = (instruction is SsaTaskAcquire) ? ((SsaTaskAcquire) instruction).source : (instruction is SsaTaskWait) ? ((SsaTaskWait) instruction).child : ((instruction is SsaAsyncOperation) && ((SsaAsyncOperation) instruction).contract.kind == AsyncOperationKind.RUN) ? ((SsaAsyncOperation) instruction).task : null;
				if (consumed != null) {
					var producer = producers.lookup (consumed);
					if (!(producer is SsaTaskCreate || producer is SsaTaskMove)) {
						throw new SsaError.INVALID_SSA ("task consumption requires its exact fresh or moved unique producer");
					}
					consumers.insert (consumed, consumers.lookup (consumed) + 1);
				}
				var operation = instruction as SsaAsyncOperation;
				if (operation != null && operation.task != null && operation.contract.kind != AsyncOperationKind.RUN) {
					var borrow = producers.lookup (operation.task) as SsaTaskBorrow;
					if (borrow == null || borrow.owner_ordinal != operation.task_owner) {
						throw new SsaError.INVALID_SSA ("nonconsuming task operation requires its exact original local borrow");
					}
				}
			}
		}
		foreach (var value in producers.get_keys ()) {
			if (!(producers.lookup (value) is SsaTaskBorrow) && consumers.lookup (value) != 1) {
				throw new SsaError.INVALID_SSA ("fresh or moved task requires exactly one original consuming responsibility");
			}
		}
		var ordinals = new HashTable<int, SsaTaskOwner> (direct_hash, direct_equal);
		foreach (var owner in function.task_owners) {
			if (owner.source_ordinal < 0 || ordinals.contains (owner.source_ordinal)) {
				throw new SsaError.INVALID_SSA ("task owner has duplicate original local authority");
			}
			ordinals.insert (owner.source_ordinal, owner);
		}
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var acquire = instruction as SsaTaskAcquire;
				var move = instruction as SsaTaskMove;
				var end = instruction as SsaTaskEnd;
				var borrow = instruction as SsaTaskBorrow;
				var started = instruction as SsaTaskStarted;
				if (acquire == null && move == null && end == null && borrow == null && started == null) {
					continue;
				}
				int source_ordinal = borrow != null ? borrow.owner_ordinal : started != null ? started.owner_ordinal : acquire != null ? acquire.owner_ordinal : move != null ? move.owner_ordinal : end.owner_ordinal;
				var owner = ordinals.lookup (source_ordinal);
				var value = borrow != null ? borrow.source : started != null ? started.operation.task : acquire != null ? acquire.source : move != null ? move.source : end.source;
				if (owner == null || owner.contract != value.semantic_type) {
					throw new SsaError.INVALID_SSA ("task effect lost exact original local/nominal task owner authority");
				}
				if (acquire != null) {
					if (!owner.matches_acquisition (acquire) || acquisitions.contains (owner)) {
						throw new SsaError.INVALID_SSA ("task owner lost its exact original acquisition association");
					}
					acquisitions.insert (owner, true);
				}
				if (acquire != null) {
					bool producer = false;
					foreach (var candidate in function.blocks) {
						foreach (var prior in candidate.instructions) {
							if (prior.result == value && (prior is SsaTaskCreate || prior is SsaTaskMove)) {
								producer = true;
							}
						}
					}
					if (!producer) {
						throw new SsaError.INVALID_SSA ("task acquisition requires exact unique creation or move producer");
					}
				}
			}
		}
		foreach (var owner in function.task_owners) {
			if (!acquisitions.contains (owner)) {
				throw new SsaError.INVALID_SSA ("task owner lost its original acquisition responsibility");
			}
		}
		if (count == 0) {
			return;
		}
		int[,] entries = new int[function.blocks.length, count];
		bool[] reachable = new bool[function.blocks.length];
		reachable[function.entry.ordinal] = true;
		for (int o = 0; o < count; o++) {
			entries[function.entry.ordinal, o] = 1;
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
					for (int o = 0; o < count; o++) {
						state[o] = entries[block.ordinal, o];
					}
					foreach (var instruction in block.instructions) {
						var acquire = instruction as SsaTaskAcquire;
						var move = instruction as SsaTaskMove;
						var end = instruction as SsaTaskEnd;
						var borrow = instruction as SsaTaskBorrow;
						var started = instruction as SsaTaskStarted;
						if (acquire == null && move == null && end == null && borrow == null && started == null) {
							continue;
						}
						int source_ordinal = borrow != null ? borrow.owner_ordinal : started != null ? started.owner_ordinal : acquire != null ? acquire.owner_ordinal : move != null ? move.owner_ordinal : end.owner_ordinal;
						int o = 0;
						while (function.task_owners[o].source_ordinal != source_ordinal) {
							o++;
						}
						int allowed = acquire != null ? 1 : move != null || borrow != null || started != null ? 6 : 10;
						if (pass == 1 && (state[o] == 0 || (state[o] & ~allowed) != 0)) {
							throw new SsaError.INVALID_SSA ("task owner #%d lost unique live/moved disposition on a control edge", source_ordinal);
						}
						state[o] = borrow != null ? state[o] : started != null ? 4 : acquire != null ? 2 : move != null ? 8 : 1;
					}
					if (pass == 1 && block.terminator.successors ().length == 0 && !(block.terminator is SsaExceptionUnreachable)) {
						for (int o = 0; o < count; o++) {
							if ((state[o] & 6) != 0) {
								throw new SsaError.INVALID_SSA ("task owner exits without exact consuming cleanup disposition");
							}
						}
					}
					if (pass == 0) {
						foreach (var next in block.terminator.successors ()) {
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
		verify_pointers (function);
	}
}
public class SsaTaskCreate : SsaCallInstruction {
	public bool checked_admission { get; private set; }
	public GenericArray<SsaFrameInputRestore> input_restores { get; private set; default = new GenericArray<SsaFrameInputRestore> (); }
	public GenericArray<SsaFrameBufferRestore> buffer_restores { get; private set; default = new GenericArray<SsaFrameBufferRestore> (); }
	public GenericArray<SsaFrameRecordRestore> record_restores { get; private set; default = new GenericArray<SsaFrameRecordRestore> (); }
	public SsaValue? allocation_context { get; private set; }
	public SsaHeapOwner? context_owner { get; private set; }
	public GenericArray<SsaSuspensionLoan> loans { get; private set; default = new GenericArray<SsaSuspensionLoan> (); }
	private GenericArray<SsaValue> captures = new GenericArray<SsaValue> ();
	internal bool matches_captures() {
		if (arguments.length != captures.length) {
			return false;
		}
		for (int i = 0; i < captures.length; i++) {
			if (arguments[i] != captures[i]) {
				return false;
			}
		}
		return true;
	}
	internal int direct_wait_position(SsaBlock block, int position) {
		for (int i = position + 1; i < block.instructions.length; i++) {
			var wait = block.instructions[i] as SsaTaskWait;
			if (wait != null) {
				return wait.child == result ? i : -1;
			}
			var cleanup = block.instructions[i] as SsaCleanupInstruction;
			if (cleanup != null && cleanup.value is SsaNullPointerConstant && i + 1 < block.instructions.length) {
				var ended = block.instructions[i + 1] as SsaHeapOwnerEvent;
				bool captured = false;
				if (ended != null && ended.action == SsaHeapOwnerAction.END && ended.effect == cleanup && ended.owner != null) {
					foreach (var argument in owned_arguments) {
						if (argument.source_ordinal == ended.owner.source_ordinal && argument.cleanup == cleanup.cleanup && argument.source_after_commit == cleanup.value) {
							captured = true;
						}
					}
				}
				if (!captured) {
					return -1;
				}
				i++;
				continue;
			}
			var read = block.instructions[i] as SsaBufferReadInstruction;
			if (read != null && i + 1 < block.instructions.length) {
				var ended = block.instructions[i + 1] as SsaBufferDeallocateInstruction;
				bool captured = false;
				if (ended != null && ended.pair == read.pair && ended.cleanup == read.place.cleanup) {
					foreach (var argument in buffer_arguments) {
						if (argument.disarm.place.storage == read.place.storage && read.place.storage != null && argument.disarm.pair.is_empty) {
							captured = true;
						}
					}
				}
				if (!captured) {
					return -1;
				}
				i++;
				continue;
			}
			return -1;
		}
		return -1;
	}
	internal SsaTaskCreate (SourceSpan span, TaskType type, int ordinal, SsaFunction target, GenericArray<SsaValue> arguments, SsaValue? allocation_context = null, SsaHeapOwner? context_owner = null, bool checked_admission = false) {
		base (span, type, ordinal, target, arguments);
		this.checked_admission = checked_admission;
		this.allocation_context = allocation_context;
		this.context_owner = context_owner;
		foreach (var argument in arguments) {
			captures.add (argument);
		}
	}
}
public class SsaFrameInputRestore : SsaInstruction {
	private WeakRef invocation;
	public SsaTaskCreate? creation { owned get { return (SsaTaskCreate?) invocation.get (); } }
	public SsaOwnedArgument argument { get; private set; }
	public SsaHeapOwner owner { get; private set; }
	internal SsaFrameInputRestore (SourceSpan span, SsaTaskCreate creation, SsaOwnedArgument argument, SsaHeapOwner owner, int ordinal) {
		base (span, argument.value.semantic_type, ordinal);
		invocation = WeakRef (creation);
		this.argument = argument;
		this.owner = owner;
	}
}
public class SsaFrameBufferRestore : SsaInstruction {
	private WeakRef invocation;
	public SsaTaskCreate? creation { owned get { return (SsaTaskCreate?) invocation.get (); } }
	public SsaBufferArgument argument { get; private set; }
	public SsaBufferPair pair { get; private set; }
	internal SsaFrameBufferRestore (SourceSpan span, SsaTaskCreate creation, SsaBufferArgument argument, int ordinal) {
		base (span, null, -1);
		invocation = WeakRef (creation);
		this.argument = argument;
		pair = new SsaBufferPair.results (span, argument.pair.shape, ordinal);
	}
}
public abstract class SsaRecordAdmissionRestore : SsaInstruction {
	public SsaStructBoundaryMove original { get; private set; }
	public SsaStructCallResults results { get; private set; }
	private WeakRef restored_acquisition = WeakRef (null);
	public SsaStructBoundaryAcquire? acquisition { owned get { return (SsaStructBoundaryAcquire?) restored_acquisition.get (); } internal set { restored_acquisition.set (value); } }
	internal bool owning_leaf(int leaf) {
		if (original.shape.leaves[leaf] is StructBufferLeafPath) {
			return true;
		}
		foreach (var owner in original.owners) {
			if (owner.record_path.same_path (original.shape.leaves[leaf])) {
				return true;
			}
		}
		return false;
	}
	public abstract SsaValue admission_value();
	protected SsaRecordAdmissionRestore (SourceSpan span, SsaStructBoundaryMove original, SsaStructCallResults results) {
		base (span, null, -1);
		this.original = original;
		this.results = results;
	}
}
public class SsaFrameRecordRestore : SsaRecordAdmissionRestore {
	private WeakRef invocation;
	public SsaTaskCreate? creation { owned get { return (SsaTaskCreate?) invocation.get (); } }
	public override SsaValue admission_value() {
		return creation.result;
	}
	internal SsaFrameRecordRestore (SourceSpan span, SsaTaskCreate creation, SsaStructBoundaryMove original, SsaStructCallResults results) {
		base (span, original, results);
		invocation = WeakRef (creation);
	}
}
public class SsaTaskMove : SsaInstruction {
	public SsaValue source { get; private set; }
	public int owner_ordinal { get; private set; }
	internal SsaTaskMove (SourceSpan span, SsaValue source, int owner_ordinal, int ordinal) {
		base (span, source.semantic_type, ordinal);
		this.source = source;
		this.owner_ordinal = owner_ordinal;
	}
}
public class SsaTaskAbsent : SsaValue {
	internal SsaTaskAbsent (SourceSpan span, TaskType type) {
		base (span, type);
	}
}
public class SsaTaskEnd : SsaInstruction {
	public SsaValue source { get; private set; }
	public int owner_ordinal { get; private set; }
	internal SsaTaskEnd (SourceSpan span, SsaValue source, int owner_ordinal) {
		base (span, null, -1);
		this.source = source;
		this.owner_ordinal = owner_ordinal;
	}
}
public class SsaAsyncDelay : SsaInstruction {
	public bool payload { get; private set; }
	public SsaHeapOwner? source_owner { get; private set; }
	public AsyncBodyContract body { get; private set; }
	public SsaValue ticks { get; private set; }
	internal SsaAsyncDelay (SourceSpan span, AsyncBodyContract body, SsaValue ticks, ClassType error_root, int ordinal, bool payload = false, SsaHeapOwner? source_owner = null) {
		base (span, error_root, ordinal);
		this.body = body;
		this.ticks = ticks;
		this.payload = payload;
		this.source_owner = source_owner;
	}
}
public class SsaTaskWait : SsaInstruction {
	public SsaValue? bridge_executor { get; private set; }
	public SsaHeapOwner? bridge_owner { get; private set; }
	public AsyncBodyContract body { get; private set; }
	public SsaValue child { get; private set; }
	public bool discard { get; private set; }
	private WeakRef continuation = WeakRef (null);
	public SsaTaskSuccess? success { owned get { return (SsaTaskSuccess?) continuation.get (); } internal set { continuation.set (value); } }
	internal SsaTaskWait (SourceSpan span, AsyncBodyContract body, SsaValue child, ClassType error_root, bool discard, int ordinal, SsaValue? bridge_executor = null, SsaHeapOwner? bridge_owner = null) {
		base (span, error_root, ordinal);
		this.bridge_executor = bridge_executor;
		this.bridge_owner = bridge_owner;
		this.body = body;
		this.child = child;
		this.discard = discard;
	}
}
public class SsaTaskSuccess : SsaInstruction {
	public SsaBufferPair? buffer_result { get; private set; }
	public SsaCleanupContract? buffer_cleanup { get; private set; }
	public SsaStructCallResults? struct_result { get; private set; }
	public SsaEnumSlot? enum_result { get; private set; }
	public SemanticType success_type { get; private set; }
	public SsaTaskWait operation { get; private set; }
	internal SsaTaskSuccess (SourceSpan span, SsaTaskWait operation, SemanticType result, int ordinal) {
		base (span, result, ordinal);
		this.operation = operation;
		success_type = result;
	}
	internal SsaTaskSuccess.for_buffer (SourceSpan span, SsaTaskWait operation, SsaCleanupContract cleanup, int ordinal) {
		base (span, null, -1);
		this.operation = operation;
		buffer_cleanup = cleanup;
		buffer_result = new SsaBufferPair.results (span, cleanup.buffer_shape, ordinal);
		success_type = cleanup.buffer_type;
	}
	internal SsaTaskSuccess.for_record (SourceSpan span, SsaTaskWait operation, SsaStructCallResults results) {
		base (span, null, -1);
		this.operation = operation;
		struct_result = results;
		success_type = results.shape.semantic_type;
	}
	internal SsaTaskSuccess.for_enum (SourceSpan span, SsaTaskWait operation, SsaEnumSlot destination) {
		base (span, null, -1);
		this.operation = operation;
		enum_result = destination;
		success_type = destination.definition.semantic_type;
	}
}

private class SsaFrameCatchIdentity : Object {
	private WeakRef identity;
	internal SsaFrameCatchIdentity (SsaFrameCatchEvent event) {
		identity = WeakRef (event);
	}
	internal SsaFrameCatchEvent? event {
		owned get {
			return (SsaFrameCatchEvent?) identity.get ();
		}
	}
}
public class SsaFrameCatchOwner : Object {
	private GenericArray<SsaFrameCatchIdentity> original_events = new GenericArray<SsaFrameCatchIdentity> ();
	public void retain_event(SsaFrameCatchEvent event) {
		assert (event.owner == this && !matches_event (event));
		original_events.add (new SsaFrameCatchIdentity (event));
	}
	internal bool matches_event(SsaFrameCatchEvent event) {
		foreach (var original in original_events) {
			if (original.event == event) {
				return true;
			}
		}
		return false;
	}
	internal void verify_events(SsaFunction function) throws SsaError {
		foreach (var original in original_events) {
			var expected = original.event;
			int count = 0;
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					if (instruction == expected) {
						count++;
					}
				}
			}
			if (count != 1) {
				throw new SsaError.INVALID_SSA ("suspended catch owner lost original acquisition/cleanup responsibility");
			}
		}
	}
	public int cleanup_position { get; private set; }
	public int ordinal { get; private set; }
	public int source_ordinal { get; private set; }
	public ClassType semantic_type { get; private set; }
	internal SsaFrameCatchOwner (int ordinal, int source_ordinal, ClassType type, int cleanup_position = -1) {
		this.cleanup_position = cleanup_position;
		this.ordinal = ordinal;
		this.source_ordinal = source_ordinal;
		semantic_type = type;
	}
}
public class SsaFrameCatchEvent : SsaInstruction {
	public SsaFrameCatchOwner owner { get; private set; }
	public SsaValue source { get; private set; }
	internal SsaFrameCatchEvent (SourceSpan span, SsaFrameCatchOwner owner, SsaValue source) {
		base (span, null, -1);
		this.owner = owner;
		this.source = source;
	}
}

public class SsaTaskBorrow : SsaInstruction {
	public SsaValue source { get; private set; }
	public int owner_ordinal { get; private set; }
	internal SsaTaskBorrow (SourceSpan span, SsaValue source, int owner_ordinal, int ordinal) {
		base (span, source.semantic_type, ordinal);
		this.source = source;
		this.owner_ordinal = owner_ordinal;
	}
}
public class SsaAsyncOperation : SsaInstruction {
	public AsyncOperationContract contract { get; private set; }
	public SsaValue? executor { get; private set; }
	public SsaValue? task { get; private set; }
	public SsaValue? argument { get; private set; }
	public int task_owner { get; private set; }
	public int executor_owner { get; private set; }
	public SsaInstructionResult? exception { get; private set; }
	internal SsaAsyncOperation (SourceSpan span, AsyncOperationContract contract, SsaValue? executor, SsaValue? task, SsaValue? argument, ClassType? error_root, int task_owner, int executor_owner, int result_ordinal, int exception_ordinal) {
		base (span, contract.result.kind == TypeKind.VOID ? null : contract.result, result_ordinal);
		this.contract = contract;
		this.executor = executor;
		this.task = task;
		this.argument = argument;
		this.task_owner = task_owner;
		this.executor_owner = executor_owner;
		if (contract.raises) {
			exception = new SsaInstructionResult (span, error_root, exception_ordinal);
		}
	}
}
public class SsaTaskStarted : SsaInstruction {
	public int owner_ordinal { get; private set; }
	public SsaAsyncOperation operation { get; private set; }
	internal SsaTaskStarted (SourceSpan span, int owner_ordinal, SsaAsyncOperation operation) {
		base (span, null, -1);
		this.owner_ordinal = owner_ordinal;
		this.operation = operation;
	}
}

public class SsaExecutorEnd : SsaInstruction {
	public SsaValue source { get; private set; }
	internal SsaExecutorEnd (SourceSpan span, SsaValue source) {
		base (span, null, -1);
		this.source = source;
	}
}

public class SsaAsyncRunStatus : SsaInstruction {
	public SsaAsyncOperation operation { get; private set; }
	public SsaEnumSlot destination { get; private set; }
	internal SsaAsyncRunStatus (SourceSpan span, SsaAsyncOperation operation, SsaEnumSlot destination) {
		base (span, null, -1);
		this.operation = operation;
		this.destination = destination;
	}
}

}
