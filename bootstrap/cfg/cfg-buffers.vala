// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Cfg {
public class CfgScopedAllocator : CfgValue {
	public ScopedBackingLoan loan { get; private set; }
	public CfgLocalPlace backing { get; private set; }
	public CfgValue kind { get; private set; }
	public CfgValue slots { get; private set; }
	public CfgCleanupContract cleanup { get; private set; }
	internal CfgScopedAllocator (SourceSpan span, HandleType type, ScopedBackingLoan loan, CfgLocalPlace backing, CfgValue kind, CfgValue slots, CfgCleanupContract cleanup) {
		base (span, type);
		this.loan = loan;
		this.backing = backing;
		this.kind = kind;
		this.slots = slots;
		this.cleanup = cleanup;
	}
}
public class CfgSlotsRecordTransfer : CfgInstruction {
	public CfgStructBoundaryMove? record_move { get; internal set; }
	public CfgIndirectFieldPlace store { get; private set; }
	public CfgValue? index { get; private set; }
	public StructValueShape shape { get; private set; }
	public GenericArray<CfgValue> leaves { get; private set; }
	internal CfgSlotsRecordTransfer (SourceSpan span, CfgIndirectFieldPlace store, CfgValue? index, StructValueShape shape, GenericArray<CfgValue> leaves) {
		base (span);
		this.store = store;
		this.index = index;
		this.shape = shape;
		this.leaves = leaves;
	}
}
public class CfgSlotsRecordRead : CfgInstruction {
	public CfgIndirectFieldPlace store { get; private set; }
	public CfgValue index { get; private set; }
	public bool remove { get; private set; }
	public CfgStructCallResults results { get; private set; }
	internal CfgSlotsRecordRead (SourceSpan span, CfgIndirectFieldPlace store, CfgValue index, bool remove, CfgStructCallResults results) {
		base (span);
		this.store = store;
		this.index = index;
		this.remove = remove;
		this.results = results;
	}
}
// A checked destination, not a payload borrow or an extra owner. Each capture
// belongs to exactly one exchange and protects storage until that exchange.
public class CfgBufferSlotCapture : CfgInstruction {
	public CfgPlace place { get; private set; }
	public CfgCleanupContract cleanup { get; private set; }
	internal CfgBufferSlotCapture (SourceSpan span, CfgPlace place, CfgCleanupContract cleanup) {
		base (span);
		this.place = place;
		this.cleanup = cleanup;
	}
}

// Both destinations precede this indivisible language effect. Complete
// descriptor snapshots are internal to it and never acquire cleanup duties.
public class CfgBufferExchange : CfgInstruction {
	public CfgBufferSlotCapture left_capture { get; private set; }
	public CfgBufferSlotCapture right_capture { get; private set; }
	public CfgPlace left { get { return left_capture.place; } }
	public CfgPlace right { get { return right_capture.place; } }
	public CfgCleanupContract cleanup { get { return left_capture.cleanup; } }
	internal CfgBufferExchange (SourceSpan span, CfgBufferSlotCapture left, CfgBufferSlotCapture right) {
		base (span);
		this.left_capture = left;
		this.right_capture = right;
	}
}

// One exact pair of concrete memory components. Every owner operation takes
// this whole group, so neither component can be independently reassigned.
public class CfgBufferOwnerGroup : CfgNode {
	public BufferValueShape shape { get; private set; }
	public CfgBufferComponentPlace base_place { get; private set; }
	public CfgBufferComponentPlace length_place { get; private set; }
	internal CfgBufferOwnerGroup (SourceSpan span, BufferValueShape shape) {
		base (span);
		this.shape = shape;
		this.base_place = new CfgBufferComponentPlace (span, shape.base_type, 0);
		this.length_place = new CfgBufferComponentPlace (span, shape.length_type, 1);
	}
}
public class CfgBufferComponentPlace : CfgPlace {
	public int component { get; private set; }
	internal CfgBufferComponentPlace (SourceSpan span, SemanticType type, int component) {
		base (span, type);
		this.component = component;
	}
}
// Bounded producer token plus PTR/I32 definitions. The token is consumed by
// one ownership action and never becomes an aggregate SSA value.
public class CfgBufferResults : CfgNode {
	public BufferValueShape shape { get; private set; }
	public CfgCallResultValue owner { get; private set; }
	public CfgCallResultValue base_value { get; private set; }
	public CfgCallResultValue length_value { get; private set; }
	internal CfgBufferResults (SourceSpan span, BufferValueShape shape, CfgCallResultValue owner) {
		base (span);
		this.shape = shape;
		this.owner = owner;
		this.base_value = new CfgCallResultValue (span, shape.base_type);
		this.length_value = new CfgCallResultValue (span, shape.length_type);
	}
}
// The region names one ordinary call and its enforced fatal continuation.
// Targets are weak stage-local identities; no upstream model is retained.
public class CfgAllocationFailure : CfgNode {
	private WeakRef native_callee;
	private WeakRef foreign_callee;
	public CfgFunction? target { owned get { return (CfgFunction?) native_callee.get (); } }
	public CfgCFunction? c_target { owned get { return (CfgCFunction?) foreign_callee.get (); } }
	public CfgInstruction? action { get; internal set; }
	public CfgValue? captured_receiver { get; internal set; }
	internal CfgAllocationFailure (SourceSpan span, CfgFunction? target, CfgCFunction? c_target) {
		base (span);
		native_callee = WeakRef (target);
		foreign_callee = WeakRef (c_target);
	}
}
public class CfgAllocationFailureTrap : CfgTerminator {
	public CfgAllocationFailure failure { get; private set; }
	internal CfgAllocationFailureTrap (SourceSpan span, CfgAllocationFailure failure) {
		base (span);
		this.failure = failure;
	}
	public override GenericArray<CfgBlock> successors() {
		return new GenericArray<CfgBlock> ();
	}
}
public class CfgBufferAllocationBranch : CfgTerminator {
	public CfgBufferAllocate allocation { get; private set; }
	private WeakRef success;
	private WeakRef failure;
	public CfgBlock? success_target { owned get { return (CfgBlock?) success.get (); } }
	public CfgBlock? failure_target { owned get { return (CfgBlock?) failure.get (); } }
	internal CfgBufferAllocationBranch (SourceSpan span, CfgBufferAllocate allocation, CfgBlock success, CfgBlock failure) {
		base (span);
		this.allocation = allocation;
		this.success = WeakRef (success);
		this.failure = WeakRef (failure);
	}
	public override GenericArray<CfgBlock> successors() {
		var result = new GenericArray<CfgBlock> ();
		if (success_target != null) {
			result.add (success_target);
		}
		if (failure_target != null) {
			result.add (failure_target);
		}
		return result;
	}
}
public class CfgBufferAllocate : CfgInstruction {
	public CfgValue? allocation_context { get; private set; }
	public CfgAllocationFailure? failure { get; private set; }
	public CfgValue count { get; private set; }
	public CfgCleanupContract cleanup { get; private set; }
	public CfgBufferResults results { get; private set; }
	internal CfgBufferAllocate (SourceSpan span, CfgValue count, CfgCleanupContract cleanup, CfgAllocationFailure? failure = null, CfgValue? allocation_context = null) {
		base (span);
		this.failure = failure;
		this.count = count;
		this.cleanup = cleanup;
		this.allocation_context = allocation_context;
		this.results = new CfgBufferResults (span, cleanup.buffer_shape, new CfgCallResultValue (span, cleanup.buffer_type));
	}
}
public class CfgBufferBorrowValue : CfgOwnedBorrowValue {
	internal CfgBufferBorrowValue (SourceSpan span, CfgLocalPlace source, CfgParameter? parameter) {
		base (span, source, parameter);
	}
}

// Independent closed-region proof: only allocator-null enters this DAG,
// and every normal argument/call return reaches the actual fallback trap.
internal class CfgAllocationFailureVerifier : Object {
	private static void require(bool condition, string message) throws CfgError {
		if (!condition) {
			throw new CfgError.INVALID_CFG ("allocation failure region: %s", message);
		}
	}
	// Exception edges use the ordinary checked exception channel. Only the
	// exact null result continues toward the fallback trap; the nonnull edge
	// leaves this allocation's normal failure-action region.
	private static CfgBlock? normal_success(CfgBlock block) {
		if (block.instructions.length == 0) {
			return null;
		}
		var call = block.instructions[block.instructions.length - 1] as CfgCallInstruction;
		var branch = block.terminator as CfgConditionalBranch;
		var condition = branch == null ? null : branch.condition as CfgBinaryValue;
		if (call == null || call.target == null || call.target.throws_type == null || call.exception_result == null || condition == null || condition.operator_kind != BinaryOperator.EQUAL || condition.left != call.exception_result || !(condition.right is CfgNullPointerValue) || branch.true_target == branch.false_target) {
			return null;
		}
		return branch.true_target;
	}
	internal static void verify(CfgFunction function) throws CfgError {
		bool present = false;
		foreach (var block in function.blocks) {
			if (block.terminator is CfgBufferAllocationBranch || block.terminator is CfgAllocationFailureTrap) {
				present = true;
			}
			foreach (var instruction in block.instructions) {
				var allocation = instruction as CfgBufferAllocate;
				if (allocation != null && allocation.failure != null) {
					present = true;
				}
			}
		}
		if (!present) {
			return;
		}
		var blocks = new HashTable<CfgBlock, bool> (direct_hash, direct_equal);
		var sites = new HashTable<CfgInstruction, CfgBlock> (direct_hash, direct_equal);
		var publications = new HashTable<CfgBufferAllocate, bool> (direct_hash, direct_equal);
		var regions = new HashTable<CfgAllocationFailure, bool> (direct_hash, direct_equal);
		var traps = new HashTable<CfgAllocationFailureTrap, bool> (direct_hash, direct_equal);
		foreach (var block in function.blocks) {
			blocks.insert (block, true);
			foreach (var instruction in block.instructions) {
				require (!sites.contains (instruction), "repeated instruction identity");
				sites.insert (instruction, block);
			}
		}
		foreach (var origin in function.blocks) {
			var request = origin.terminator as CfgBufferAllocationBranch;
			if (request == null) {
				continue;
			}
			var allocation = request.allocation;
			var failure = allocation.failure;
			var success = request.success_target;
			var failed = request.failure_target;
			require (failure != null && !publications.contains (allocation) && !regions.contains (failure), "request needs one unique action and publication");
			publications.insert (allocation, true);
			regions.insert (failure, true);
			require (success != null && failed != null && success != failed && success != origin && failed != origin && blocks.contains (success) && blocks.contains (failed), "request needs distinct live success/failure successors");
			require (success != function.entry && failed != function.entry && success.instructions.length > 0 && success.instructions[0] == allocation && sites.lookup (allocation) == success, "owner publication must begin the exclusive success successor");
			CfgValue? expected_receiver = null;
			CfgResourceCapture? capture = null;
			foreach (var instruction in success.instructions) {
				if (instruction is CfgResourceCapture && ((CfgResourceCapture) instruction).value == allocation.results.owner) {
					capture = (CfgResourceCapture) instruction;
				}
				var initialized = instruction as CfgInitialize;
				var store = instruction as CfgStore;
				var place = initialized != null ? initialized.target : store == null ? null : store.target;
				var incoming = initialized != null ? initialized.value : store == null ? null : store.value;
				if (capture != null && incoming == capture.result && place is CfgIndirectFieldPlace) {
					expected_receiver = ((CfgIndirectFieldPlace) place).pointer;
				}
			}
			require (failure.captured_receiver == expected_receiver, "failure must preserve the destination's captured receiver");
			var call = failure.action as CfgCallInstruction;
			var c_call = failure.action as CfgCCallInstruction;
			require ((failure.target != null) != (failure.c_target != null), "action needs exactly one live typed callee");
			require (failure.target != null ? call != null && call.target == failure.target && call.result == null && failure.target.return_type.kind == TypeKind.VOID : c_call != null && c_call.target == failure.c_target && c_call.result == null && failure.c_target.return_type.kind == TypeKind.VOID, "action call/callee/result correspondence mismatch");
			var region = new HashTable<CfgBlock, bool> (direct_hash, direct_equal);
			var terminal = new HashTable<CfgBlock, bool> (direct_hash, direct_equal);
			var pending = new GenericArray<CfgBlock> ();
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
						var invocation = instruction as CfgCallInstruction;
						if (invocation != null) {
							require (invocation.target == null || invocation.target.implicit_receiver == null || invocation.target.implicit_receiver.contract.instance_type != type, "captured field receiver overlaps a containing-object method call");
							foreach (var argument in invocation.arguments) {
								require (!(argument is CfgPendingOwnedArgument) || argument.semantic_type != type, "captured field receiver overlaps an ownership transfer");
							}
						}
					}
					require (!(instruction is CfgCleanupInstruction || instruction is CfgOwnershipReleaseInstruction || instruction is CfgBufferAllocate || instruction is CfgOwnershipRearmInstruction), "failure path cannot acquire a buffer or synthesize caller cleanup");
				}
				var trap = block.terminator as CfgAllocationFailureTrap;
				if (trap != null) {
					var action_site = sites.lookup (failure.action);
					bool direct = (call == null || call.exception_result == null) && block.instructions.length > 0 && block.instructions[block.instructions.length - 1] == failure.action;
					bool returned = block.instructions.length == 0 && action_site != null && normal_success (action_site) == block && action_site.instructions[action_site.instructions.length - 1] == failure.action;
					require (trap.failure == failure && (direct || returned), "failure action must be immediately followed by its enforced trap");
					traps.insert (trap, true);
					terminal.insert (block, true);
					trap_count++;
					continue;
				}
				require (block.terminator is CfgBranch || block.terminator is CfgConditionalBranch, "failure region must end in a trap");
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
						successors = new GenericArray<CfgBlock> ();
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
				var allocation = instruction as CfgBufferAllocate;
				if (allocation != null && allocation.failure != null) {
					require (publications.contains (allocation), "annotated publication has no allocation request");
				}
			}
			var trap = block.terminator as CfgAllocationFailureTrap;
			if (trap != null) {
				require (traps.contains (trap), "orphan failure trap");
			}
		}
	}
}
}

namespace Astra.Cfg {
public class CfgSlotsInitialize : CfgInstruction {
	public CfgIndirectFieldPlace store { get; private set; }
	internal CfgSlotsInitialize (SourceSpan span, CfgIndirectFieldPlace store) {
		base (span);
		this.store = store;
	}
}
public class CfgSlotsReplace : CfgInstruction {
	public CfgIndirectFieldPlace store { get; private set; }
	public CfgValue index { get; private set; }
	public CfgLocalPlace incoming { get; private set; }
	internal CfgSlotsReplace (SourceSpan span, CfgIndirectFieldPlace store, CfgValue index, CfgLocalPlace incoming) {
		base (span);
		this.store = store;
		this.index = index;
		this.incoming = incoming;
	}
}
public class CfgSlotsAppend : CfgInstruction {
	public CfgIndirectFieldPlace store { get; private set; }
	public CfgLocalPlace incoming { get; private set; }
	internal CfgSlotsAppend (SourceSpan span, CfgIndirectFieldPlace store, CfgLocalPlace incoming) {
		base (span);
		this.store = store;
		this.incoming = incoming;
	}
}
public class CfgSlotsDrop : CfgInstruction {
	public CfgIndirectFieldPlace store { get; private set; }
	internal CfgSlotsDrop (SourceSpan span, CfgIndirectFieldPlace store) {
		base (span);
		this.store = store;
	}
}
public class CfgSlotsValue : CfgValue {
	public CfgIndirectFieldPlace store { get; private set; }
	public OwnerSlotsAction action { get; private set; }
	public CfgValue? operand { get; private set; }
	internal CfgSlotsValue (SourceSpan span, SemanticType type, CfgIndirectFieldPlace store, OwnerSlotsAction action, CfgValue? operand) {
		base (span, type);
		this.store = store;
		this.action = action;
		this.operand = operand;
	}
}
public class CfgSlotsLoan : CfgEvaluatedValue {
	public bool readonly_required { get; internal set; }
	private bool original_readonly_required;
	internal bool readonly_context_valid() {
		return readonly_required == original_readonly_required;
	}
	public CfgIndirectFieldPlace store { get; private set; }
	public CfgValue index { get; private set; }
	public CfgParameter borrower { get; private set; }
	internal CfgSlotsLoan (SourceSpan span, CfgIndirectFieldPlace store, CfgValue index, CfgParameter borrower, bool readonly_required = false) {
		base (span, ((OwnerSlotsType) store.semantic_type).element);
		this.store = store;
		this.index = index;
		this.borrower = borrower;
		this.readonly_required = original_readonly_required = readonly_required;
	}
}
public class CfgSlotsBorrow : CfgInstruction {
	public CfgSlotsLoan result { get; private set; }
	internal CfgSlotsBorrow (SourceSpan span, CfgSlotsLoan result) {
		base (span);
		this.result = result;
	}
}
}
