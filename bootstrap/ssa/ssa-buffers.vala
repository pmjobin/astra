// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Ssa {
public class SsaScopedAllocator : SsaInstruction {
	public ScopedBackingLoan loan { get; private set; }
	public SsaBufferStorage backing { get; private set; }
	public SsaBufferPair pair { get; private set; }
	public SsaHeapOwner owner { get; private set; }
	public SsaValue kind { get; private set; }
	public SsaValue slots { get; private set; }
	internal SsaScopedAllocator (SourceSpan span, HandleType type, ScopedBackingLoan loan, SsaBufferStorage backing, SsaBufferPair pair, SsaHeapOwner owner, SsaValue kind, SsaValue slots, int ordinal) {
		base (span, type, ordinal);
		this.loan = loan;
		this.backing = backing;
		this.pair = pair;
		this.owner = owner;
		this.kind = kind;
		this.slots = slots;
	}

}
public class SsaSlotsRecordTransfer : SsaInstruction {
	public SsaStructBoundaryMove? record_move { get; internal set; }
	public SsaIndirectFieldPlace store { get; private set; }
	public SsaValue? index { get; private set; }
	public StructValueShape shape { get; private set; }
	public GenericArray<SsaValue> leaves { get; private set; }
	internal SsaSlotsRecordTransfer (SourceSpan span, SsaIndirectFieldPlace store, SsaValue? index, StructValueShape shape, GenericArray<SsaValue> leaves) {
		base (span, null, -1);
		this.store = store;
		this.index = index;
		this.shape = shape;
		this.leaves = leaves;
	}

}
public class SsaSlotsRecordRead : SsaInstruction {
	public SsaIndirectFieldPlace store { get; private set; }
	public SsaValue index { get; private set; }
	public bool remove { get; private set; }
	public SsaStructCallResults results { get; private set; }
	internal SsaSlotsRecordRead (SourceSpan span, SsaIndirectFieldPlace store, SsaValue index, bool remove, SsaStructCallResults results) {
		base (span, null, -1);
		this.store = store;
		this.index = index;
		this.remove = remove;
		this.results = results;
	}

}
public class SsaBufferSlotCaptureInstruction : SsaInstruction {
	public SsaBufferPlace place { get; private set; }
	internal SsaBufferSlotCaptureInstruction (SourceSpan span, SsaBufferPlace place) {
		base (span, null, -1);
		this.place = place;
	}

}

// Indivisible language effect, not hardware atomicity. Internal snapshots
// cannot escape, acquire cleanup responsibility, or leave a field hole.
public class SsaBufferExchangeInstruction : SsaInstruction {
	public SsaBufferSlotCaptureInstruction left_capture { get; private set; }
	public SsaBufferSlotCaptureInstruction right_capture { get; private set; }
	public SsaBufferPlace left { get { return left_capture.place; } }
	public SsaBufferPlace right { get { return right_capture.place; } }
	internal SsaBufferExchangeInstruction (SourceSpan span, SsaBufferSlotCaptureInstruction left, SsaBufferSlotCaptureInstruction right) {
		base (span, null, -1);
		this.left_capture = left;
		this.right_capture = right;
	}

}

// Bounded grouping metadata, never an Astra SSA Value. The two leaves have
// ordinary PTR/I32 types and must originate together from one definition.
public class SsaBufferPair : SsaNode {
	public BufferValueShape shape { get; private set; }
	public SsaValue base_value { get; private set; }
	public SsaValue length_value { get; private set; }
	internal SsaBufferPair (SourceSpan span, BufferValueShape shape, SsaValue base_value, SsaValue length_value) {
		base (span);
		this.shape = shape;
		this.base_value = base_value;
		this.length_value = length_value;
	}

	internal SsaBufferPair.results (SourceSpan span, BufferValueShape shape, int first_ordinal) {
		this(span, shape, new SsaInstructionResult (span, shape.base_type, first_ordinal), new SsaInstructionResult (span, shape.length_type, first_ordinal + 1));
	}
	internal SsaBufferPair.empty (SourceSpan span, BufferValueShape shape) {
		this(span, shape, new SsaNullPointerConstant (span, shape.base_type), new SsaIntegerConstant.typed (span, shape.length_type, AstraIntegerValue.from_int64 (shape.length_type, 0)));
	}
	public bool is_empty { get { return base_value is SsaNullPointerConstant && length_value is SsaIntegerConstant && ((SsaIntegerConstant) length_value).value.bits == 0; } }
}
public class SsaBufferStorage : SsaNode {
	public Astra.Text.TextLoanExtent? text_extent { get; internal set; }
	public int cleanup_position { get; private set; }
	public SsaStruct? record_type { get; internal set; }
	public StructLeafPath? record_path { get; internal set; }
	public int record_rank { get; internal set; default = -1; }
	public int record_source_ordinal { get; internal set; default = -1; }
	public SsaCleanupContract cleanup { get; private set; }
	public int ordinal { get; private set; }
	public int owner_ordinal { get; private set; }
	internal SsaBufferStorage (SourceSpan span, SsaCleanupContract cleanup, int ordinal, int owner_ordinal, int cleanup_position = -1) {
		base (span);
		this.cleanup_position = cleanup_position < 0 ? span.start : cleanup_position;
		this.cleanup = cleanup;
		this.ordinal = ordinal;
		this.owner_ordinal = owner_ordinal;
	}

}
public class SsaBufferPlace : SsaNode {
	public StructLeafPath? record_path { get; private set; }
	public int record_rank { get; private set; default = -1; }
	public SsaCleanupContract cleanup { get; private set; }
	public SsaBufferStorage? storage { get; private set; }
	public SsaIndirectFieldPlace? field { get; private set; }
	public SsaFieldPlace? record_projection { get; private set; }
	internal SsaBufferPlace (SourceSpan span, SsaCleanupContract cleanup, SsaBufferStorage? storage = null, SsaIndirectFieldPlace? field = null) {
		base (span);
		this.cleanup = cleanup;
		this.storage = storage;
		this.field = field;
		this.record_path = storage == null ? null : storage.record_path;
		this.record_rank = storage == null ? -1 : storage.record_rank;
	}

	internal SsaBufferPlace.projection (SourceSpan span, SsaCleanupContract cleanup, SsaFieldPlace field) {
		base (span);
		this.cleanup = cleanup;
		this.record_projection = field;
	}
}
public class SsaBufferParameter : SsaNode {
	public int first_leaf { get; private set; }
	public int source_ordinal { get; private set; }
	public SsaCleanupContract cleanup { get; private set; }
	public SsaBufferPair pair { get; private set; }
	internal SsaBufferParameter (SourceSpan span, int first_leaf, int source_ordinal, SsaCleanupContract cleanup, SsaBufferPair pair) {
		base (span);
		this.first_leaf = first_leaf;
		this.source_ordinal = source_ordinal;
		this.cleanup = cleanup;
		this.pair = pair;
	}

}
public class SsaBufferArgument : SsaNode {
	public SsaBufferParameter parameter { get; private set; }
	public SsaBufferPair pair { get; private set; }
	public SsaBufferWriteInstruction disarm { get; private set; }
	internal SsaBufferArgument (SourceSpan span, SsaBufferParameter parameter, SsaBufferPair pair, SsaBufferWriteInstruction disarm) {
		base (span);
		this.parameter = parameter;
		this.pair = pair;
		this.disarm = disarm;
	}

}
// The region names one ordinary call and its enforced fatal continuation.
// Targets are weak stage-local identities; no upstream model is retained.
public class SsaAllocationFailure : SsaNode {
	private WeakRef native_callee;
	private WeakRef foreign_callee;
	public SsaFunction? target { owned get { return (SsaFunction?) native_callee.get (); } }
	public SsaCFunction? c_target { owned get { return (SsaCFunction?) foreign_callee.get (); } }
	public SsaInstruction? action { get; internal set; }
	public SsaValue? captured_receiver { get; internal set; }
	internal SsaAllocationFailure (SourceSpan span, SsaFunction? target, SsaCFunction? c_target) {
		base (span);
		native_callee = WeakRef (target);
		foreign_callee = WeakRef (c_target);
	}

}
public class SsaAllocationFailureTrap : SsaTerminator {
	public SsaAllocationFailure failure { get; private set; }
	internal SsaAllocationFailureTrap (SourceSpan span, SsaAllocationFailure failure) {
		base (span);
		this.failure = failure;
	}

}
public class SsaBufferAllocationBranch : SsaTerminator {
	public SsaBufferAllocateInstruction allocation { get; private set; }
	public SsaEdge success_edge { get; private set; }
	public SsaEdge failure_edge { get; private set; }
	internal SsaBufferAllocationBranch (SourceSpan span, SsaBufferAllocateInstruction allocation, SsaEdge success, SsaEdge failure) {
		base (span);
		this.allocation = allocation;
		this.success_edge = success;
		this.failure_edge = failure;
	}

}
public class SsaBufferAllocateInstruction : SsaInstruction {
	public SsaHeapOwner? context_owner { get; private set; }
	public SsaValue? allocation_context { get; private set; }
	public SsaAllocationFailure? failure { get; private set; }
	public SsaValue count { get; private set; }
	public SsaCleanupContract cleanup { get; private set; }
	public SsaBufferPair pair { get; private set; }
	internal SsaBufferAllocateInstruction (SourceSpan span, SsaValue count, SsaCleanupContract cleanup, int first_ordinal, SsaAllocationFailure? failure = null, SsaValue? allocation_context = null, SsaHeapOwner? context_owner = null) {
		base (span, null, -1);
		this.failure = failure;
		this.count = count;
		this.cleanup = cleanup;
		this.allocation_context = allocation_context;
		this.context_owner = context_owner;
		this.pair = new SsaBufferPair.results (span, cleanup.buffer_shape, first_ordinal);
	}

}
public class SsaBufferReadInstruction : SsaInstruction {
	public SsaBufferPlace place { get; private set; }
	public SsaBufferPair pair { get; private set; }
	internal SsaBufferReadInstruction (SourceSpan span, SsaBufferPlace place, int first_ordinal) {
		base (span, null, -1);
		this.place = place;
		this.pair = new SsaBufferPair.results (span, place.cleanup.buffer_shape, first_ordinal);
	}

}
public class SsaBufferWriteInstruction : SsaInstruction {
	public SsaStructBoundary? record_boundary { get; internal set; }
	public SsaBufferStorage? record_move_source { get; internal set; }
	public SsaBufferStorage? record_take_source { get; internal set; }
	public SsaBufferDeallocateInstruction? record_retirement { get; internal set; }
	public bool initializes { get; internal set; }
	public SsaBufferPlace place { get; private set; }
	public SsaBufferPair pair { get; private set; }
	internal SsaBufferWriteInstruction (SourceSpan span, SsaBufferPlace place, SsaBufferPair pair) {
		base (span, null, -1);
		this.place = place;
		this.pair = pair;
	}

}
public class SsaBufferDeallocateInstruction : SsaInstruction {
	public SsaBufferPair pair { get; private set; }
	public SsaCleanupContract cleanup { get; private set; }
	internal SsaBufferDeallocateInstruction (SourceSpan span, SsaBufferPair pair, SsaCleanupContract cleanup) {
		base (span, null, -1);
		this.pair = pair;
		this.cleanup = cleanup;
	}

}
public class SsaBufferBorrowInstruction : SsaInstruction {
	public SsaBufferPair pair { get; private set; }
	public SsaStructCallResults? record_source { get; private set; }
	public StructBoundaryGroup? record_parameter { get; private set; }
	public StructLeafPath? record_path { get; private set; }
	internal SsaBufferBorrowInstruction (SourceSpan span, SsaBufferPair pair, int ordinal, SliceType? view_type = null) {
		base (span, view_type ?? pair.shape.slice_type, ordinal);
		this.pair = pair;
	}

	internal SsaBufferBorrowInstruction.for_record (SourceSpan span, SsaBufferPair pair, SsaStructCallResults group, int ordinal) {
		this(span, pair, ordinal);
		record_source = group;
	}
	internal SsaBufferBorrowInstruction.for_parameter (SourceSpan span, SsaBufferPair pair, StructBoundaryGroup group, StructLeafPath path, int ordinal) {
		this(span, pair, ordinal);
		record_parameter = group;
		record_path = path;
	}
}
public class SsaBufferReturn : SsaReturn {
	public SsaBufferPair pair { get; private set; }
	public SsaCleanupContract cleanup { get; private set; }
	internal SsaBufferReturn (SourceSpan span, SsaBufferPair pair, SsaCleanupContract cleanup) {
		base (span, null);
		this.pair = pair;
		this.cleanup = cleanup;
	}

}

// Independent closed-region proof: only allocator-null enters this DAG,
// and every normal argument/call return reaches the actual fallback trap.
internal class SsaAllocationFailureVerifier : Object {
	private static void require(bool condition, string message) throws SsaError {
		if (!condition) {
			throw new SsaError.INVALID_SSA ("allocation failure region: %s", message);
		}
	}

	private static SsaBlock? normal_success(SsaBlock block) {
		if (block.instructions.length < 2) {
			return null;
		}
		var call = block.instructions[block.instructions.length - 2] as SsaCallInstruction;
		var condition = block.instructions[block.instructions.length - 1] as SsaBinaryInstruction;
		var branch = block.terminator as SsaConditionalBranch;
		if (call == null || call.target == null || call.target.throws_type == null || call.exception_result == null || condition == null || condition.operator_kind != BinaryOperator.EQUAL || condition.left != call.exception_result || !(condition.right is SsaNullPointerConstant) || branch == null || branch.condition != condition.result || branch.true_edge.target == branch.false_edge.target) {
			return null;
		}
		return branch.true_edge.target;
	}

	internal static void verify(SsaFunction function) throws SsaError {
		bool present = false;
		foreach (var block in function.blocks) {
			if (block.terminator is SsaBufferAllocationBranch || block.terminator is SsaAllocationFailureTrap) {
				present = true;
			}
			foreach (var instruction in block.instructions) {
				var allocation = instruction as SsaBufferAllocateInstruction;
				if (allocation != null && allocation.failure != null) {
					present = true;
				}
			}
		}
		if (!present) {
			return;
		}
		var blocks = new HashTable<SsaBlock, bool> (direct_hash, direct_equal);
		var sites = new HashTable<SsaInstruction, SsaBlock> (direct_hash, direct_equal);
		var publications = new HashTable<SsaBufferAllocateInstruction, bool> (direct_hash, direct_equal);
		var regions = new HashTable<SsaAllocationFailure, bool> (direct_hash, direct_equal);
		var traps = new HashTable<SsaAllocationFailureTrap, bool> (direct_hash, direct_equal);
		foreach (var block in function.blocks) {
			blocks.insert (block, true);
			foreach (var instruction in block.instructions) {
				require (!sites.contains (instruction), "repeated instruction identity");
				sites.insert (instruction, block);
			}
		}
		foreach (var origin in function.blocks) {
			var request = origin.terminator as SsaBufferAllocationBranch;
			if (request == null) {
				continue;
			}
			var allocation = request.allocation;
			var failure = allocation.failure;
			var success = request.success_edge.target;
			var failed = request.failure_edge.target;
			require (failure != null && !publications.contains (allocation) && !regions.contains (failure), "request needs one unique action and publication");
			publications.insert (allocation, true);
			regions.insert (failure, true);
			require (success != null && failed != null && success != failed && success != origin && failed != origin && blocks.contains (success) && blocks.contains (failed), "request needs distinct live success/failure successors");
			require (success != function.entry && failed != function.entry && success.instructions.length > 0 && success.instructions[0] == allocation && sites.lookup (allocation) == success, "owner publication must begin the exclusive success successor");
			SsaValue? expected_receiver = null;
			foreach (var instruction in success.instructions) {
				var write = instruction as SsaBufferWriteInstruction;
				if (write != null && write.pair == allocation.pair && write.place.field != null) {
					expected_receiver = write.place.field.pointer;
				}
			}
			require (failure.captured_receiver == expected_receiver, "failure must preserve the destination's captured receiver");
			var call = failure.action as SsaCallInstruction;
			var c_call = failure.action as SsaCCallInstruction;
			require ((failure.target != null) != (failure.c_target != null), "action needs exactly one live typed callee");
			require (failure.target != null ? call != null && call.target == failure.target && call.result == null && failure.target.return_type.kind == TypeKind.VOID : c_call != null && c_call.target == failure.c_target && c_call.result == null && failure.c_target.return_type.kind == TypeKind.VOID, "action call/callee/result correspondence mismatch");
			var region = new HashTable<SsaBlock, bool> (direct_hash, direct_equal);
			var terminal = new HashTable<SsaBlock, bool> (direct_hash, direct_equal);
			var pending = new GenericArray<SsaBlock> ();
			pending.add (failed);
			int trap_count = 0;
			for (int i = 0; i < pending.length; i++) {
				var block = pending[i];
				if (region.contains (block)) {
					continue;
				}
				require (blocks.contains (block) && block != success && block != origin, "failure cannot reach success or repeat the request");
				region.insert (block, true);
				foreach (var instruction in block.instructions) {
					if (failure.captured_receiver != null) {
						var type = failure.captured_receiver.semantic_type;
						if (type is ReceiverType) {
							type = ((ReceiverType) type).instance_type;
						}
						var invocation = instruction as SsaCallInstruction;
						if (invocation != null) {
							require (invocation.target == null || invocation.target.implicit_receiver == null || invocation.target.implicit_receiver.contract.instance_type != type, "captured field receiver overlaps a containing-object method call");
							foreach (var argument in invocation.owned_arguments) {
								require (argument.value.semantic_type != type, "captured field receiver overlaps an ownership transfer");
							}
						}
					}
					require (!(instruction is SsaCleanupInstruction || instruction is SsaBufferDeallocateInstruction || instruction is SsaBufferAllocateInstruction), "failure path cannot acquire a buffer or synthesize caller cleanup");
				}
				var trap = block.terminator as SsaAllocationFailureTrap;
				if (trap != null) {
					var action_site = sites.lookup (failure.action);
					bool direct = (call == null || call.exception_result == null) && block.instructions.length > 0 && block.instructions[block.instructions.length - 1] == failure.action;
					bool returned = block.instructions.length == 0 && action_site != null && normal_success (action_site) == block && action_site.instructions[action_site.instructions.length - 2] == failure.action;
					require (trap.failure == failure && (direct || returned), "failure action must be immediately followed by its enforced trap");
					traps.insert (trap, true);
					terminal.insert (block, true);
					trap_count++;
					continue;
				}
				require (block.terminator is SsaBranch || block.terminator is SsaConditionalBranch, "failure region must end in a trap");
				var normal = normal_success (block);
				if (normal != null) {
					pending.add (normal);
				} else {
					foreach (var next in block.terminator.successors ()) {
						pending.add (next);
					}
				}
			}
			require (trap_count == 1 && sites.contains (failure.action) && region.contains (sites.lookup (failure.action)), "missing or unconditional failure action");
			foreach (var block in function.blocks) {
				foreach (var next in block.terminator.successors ()) {
					if (next == success) {
						require (block == origin, "success publication has an unauthorized predecessor");
					}
					if (region.contains (next) && !region.contains (block)) {
						require (block == origin && next == failed, "only allocator-null may enter failure arguments");
					}
				}
			}
			bool changed = false;
			do {
				changed = false;
				foreach (var block in region.get_keys ()) {
					if (terminal.contains (block)) {
						continue;
					}
					bool ends = true;
					var normal = normal_success (block);
					var successors = block.terminator.successors ();
					if (normal != null) {
						successors = new GenericArray<SsaBlock> ();
						successors.add (normal);
					}
					if (successors.length == 0) {
						ends = false;
					}
					foreach (var next in successors) {
						if (!terminal.contains (next)) {
							ends = false;
						}
					}
					if (ends) {
						terminal.insert (block, true);
						changed = true;
					}
				}
			} while (changed);
			require (terminal.size () == region.size (), "failure argument region cannot cycle or escape its trap");
		}
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var allocation = instruction as SsaBufferAllocateInstruction;
				if (allocation != null && allocation.failure != null) {
					require (publications.contains (allocation), "annotated publication has no allocation request");
				}
			}
			var trap = block.terminator as SsaAllocationFailureTrap;
			if (trap != null) {
				require (traps.contains (trap), "orphan failure trap");
			}
		}
	}

}
}

namespace Astra.Ssa {
public enum SsaSlotsAction {
	INITIALIZE, APPEND, DROP, REPLACE
}

// One exclusive field-resident descriptor group, never copyable SSA leaves.
public class SsaSlotsEffect : SsaInstruction {
	public SsaValue? index { get; internal set; }
	public SsaSlotsAction action { get; private set; }
	public SsaIndirectFieldPlace store { get; private set; }
	public SsaValue? incoming { get; private set; }
	public SsaHeapOwner? owner { get; private set; }
	internal SsaSlotsEffect (SourceSpan span, SsaSlotsAction action, SsaIndirectFieldPlace store, SsaValue? incoming = null, SsaHeapOwner? owner = null) {
		base (span, null, -1);
		this.action = action;
		this.store = store;
		this.incoming = incoming;
		this.owner = owner;
	}

}
public class SsaSlotsValueInstruction : SsaInstruction {
	public bool readonly_required { get; internal set; }
	private bool original_readonly_required;
	internal bool readonly_context_valid() {
		return readonly_required == original_readonly_required;
	}

	public SsaHeapOwner? owner { get; internal set; }
	public OwnerSlotsAction action { get; private set; }
	public SsaIndirectFieldPlace store { get; private set; }
	public SsaValue? operand { get; private set; }
	public SsaFunctionParameter? borrower { get; private set; }
	internal SsaSlotsValueInstruction (SourceSpan span, SemanticType type, int ordinal, SsaIndirectFieldPlace store, OwnerSlotsAction action, SsaValue? operand = null, SsaFunctionParameter? borrower = null, bool readonly_required = false) {
		base (span, type, ordinal);
		this.store = store;
		this.action = action;
		this.operand = operand;
		this.borrower = borrower;
		this.readonly_required = original_readonly_required = readonly_required;
	}

}
}
