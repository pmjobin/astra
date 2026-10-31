// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Source;

namespace Astra.Ssa {
// A shared semantic rule, not a stored producer answer: these operations
// cannot publish a handle, observe a count or invoke an unknown observer.
internal class SsaSharedScalarWork : Object {
	private static bool scalar(SemanticType type) {
		return type.kind == TypeKind.BOOL || type is IntegerType || type is FloatingType || type is VectorType;
	}
	internal static bool permits(SsaInstruction instruction) {
		var owner = instruction as SsaHeapOwnerEvent;
		if (owner != null) {
			return owner.action == SsaHeapOwnerAction.ACQUIRE || owner.action == SsaHeapOwnerAction.READ;
		}
		var call = instruction as SsaCallInstruction;
		if (call != null) {
			if (call.receiver != null || call.target == null || call.target.effect_facts == null ||
			    (call.target.effect_facts.flags & FunctionEffectFacts.NO_EXTERNAL_MEMORY) == 0 ||
			    call.target.async_body != null || call.target.throws_type != null ||
			    call.target.dispatch_kind != ClassDispatchKind.DIRECT) {
				return false;
			}
			foreach (var argument in call.arguments) {
				if (!scalar (argument.semantic_type)) {
					return false;
				}
			}
			return call.result == null || scalar (call.result.semantic_type);
		}
		var load = instruction as SsaLoadInstruction;
		if (load != null) {
			return !load.volatile_enabled && load.source is SsaLocalMemoryPlace && scalar (load.result.semantic_type);
		}
		var store = instruction as SsaStoreInstruction;
		if (store != null) {
			return !store.volatile_enabled && store.target is SsaLocalMemoryPlace && scalar (store.value.semantic_type);
		}
		var initial = instruction as SsaInitializeInstruction;
		if (initial != null) {
			return initial.target is SsaLocalMemoryPlace && scalar (initial.value.semantic_type);
		}
		if (instruction.result != null && !scalar (instruction.result.semantic_type)) {
			return false;
		}
		var binary = instruction as SsaBinaryInstruction;
		if (binary != null && (!scalar (binary.left.semantic_type) || !scalar (binary.right.semantic_type))) {
			return false;
		}
		return instruction is SsaPrefixInstruction || instruction is SsaBinaryInstruction || instruction is SsaIntegerShiftInstruction ||
		       instruction is SsaNumericGuard || instruction is SsaNumericConversionInstruction || instruction is SsaFloatConversionInstruction ||
		       instruction is SsaIntegerConversionInstruction || instruction is SsaDspInstruction || instruction is SsaVectorDotInstruction ||
		       instruction is SsaVectorSplatInstruction || instruction is SsaVectorExtractInstruction || instruction is SsaVectorInsertInstruction ||
		       instruction is SsaVectorShuffleInstruction || instruction is SsaVectorSelectInstruction || instruction is SsaVectorConstructInstruction ||
		       instruction is SsaVectorReductionInstruction;
	}
	internal static GenericArray<SsaBlock>? successors(SsaBlock block) {
		if (block.terminator is SsaBranch) {
			foreach (var argument in ((SsaBranch) block.terminator).edge.arguments) {
				if (!scalar (argument.semantic_type)) {
					return null;
				}
			}
		} else if (block.terminator is SsaConditionalBranch) {
			var branch = (SsaConditionalBranch) block.terminator;
			foreach (var argument in branch.true_edge.arguments) {
				if (!scalar (argument.semantic_type)) {
					return null;
				}
			}
			foreach (var argument in branch.false_edge.arguments) {
				if (!scalar (argument.semantic_type)) {
					return null;
				}
			}
		} else {
			return null;
		}
		return block.terminator.successors ();
	}
}
internal class SsaSharedRegion : Object {
	internal SsaBlock block;
	internal int first;
	internal bool terminal;
	internal int unresolved;
	internal GenericArray<SsaSharedRegion> parents = new GenericArray<SsaSharedRegion> ();
	internal SsaSharedRegion (SsaBlock block, int first) {
		this.block = block;
		this.first = first;
	}
}
internal class SsaSharedBalance : Object {
	// Prove an all-path transparent region using reverse edge counts. Cycles
	// without an established terminal do not acquire a termination promise.
	private static bool reaches(SsaFunction function, SsaBlock start, int first, SsaInstruction target) {
		var regions = new HashTable<string, SsaSharedRegion> (str_hash, str_equal);
		var pending = new GenericArray<SsaSharedRegion> ();
		var complete = new GenericArray<SsaSharedRegion> ();
		var root = new SsaSharedRegion (start, first);
		regions.insert ("%d:%d".printf (start.ordinal, first), root);
		pending.add (root);
		bool valid = true;
		for (int index = 0; valid && index < pending.length; index++) {
			var region = pending[index];
			for (int position = region.first; position < region.block.instructions.length; position++) {
				var instruction = region.block.instructions[position];
				if (instruction == target) {
					region.terminal = true;
					complete.add (region);
					break;
				}
				if (!SsaSharedScalarWork.permits (instruction)) {
					valid = false;
					break;
				}
			}
			if (!valid) {
				break;
			}
			if (region.terminal) {
				continue;
			}
			var next = SsaSharedScalarWork.successors (region.block);
			if (next == null || next.length == 0) {
				valid = false;
				break;
			}
			foreach (var block in next) {
				if (!function.blocks.find (block)) {
					valid = false;
					break;
				}
				string key = "%d:0".printf (block.ordinal);
				var successor = regions.lookup (key);
				if (successor == null) {
					successor = new SsaSharedRegion (block, 0);
					regions.insert (key, successor);
					pending.add (successor);
				}
				successor.parents.add (region);
				region.unresolved++;
			}
		}
		for (int index = 0; index < complete.length; index++) {
			foreach (var parent in complete[index].parents) {
				parent.unresolved--;
				if (parent.unresolved == 0) {
					parent.terminal = true;
					complete.add (parent);
				}
			}
		}
		bool result = valid && root.terminal;
		foreach (var region in pending) {
			region.parents.remove_range (0, region.parents.length);
		}
		return result;
	}
	internal static GenericArray<SsaSharedElisionPlan> derive(SsaFunction function) {
		var result = new GenericArray<SsaSharedElisionPlan> ();
		if (function.async_body != null || function.span.file.native_interface) {
			return result;
		}
		var definitions = new HashTable<SsaValue, SsaSharedOperation> (direct_hash, direct_equal);
		var blocks = new HashTable<SsaInstruction, SsaBlock> (direct_hash, direct_equal);
		var positions = new HashTable<SsaInstruction, int> (direct_hash, direct_equal);
		foreach (var block in function.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var instruction = block.instructions[i];
				blocks.insert (instruction, block);
				positions.insert (instruction, i);
				var acquisition = instruction as SsaSharedOperation;
				if (acquisition != null && acquisition.action == SharedAction.ACQUIRE) {
					definitions.insert (acquisition.result, acquisition);
				}
			}
		}
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var copy = instruction as SsaSharedOperation;
				if (copy == null || copy.action != SharedAction.CLONE) {
					continue;
				}
				var acquisition = definitions.lookup (copy.operand);
				if (acquisition == null || !reaches (function, blocks.lookup (acquisition), positions.lookup (acquisition) + 1, copy)) {
					continue;
				}
				SsaCleanupInstruction? release = null;
				bool unique = true;
				foreach (var candidate_block in function.blocks) {
					foreach (var candidate in candidate_block.instructions) {
						var cleanup = candidate as SsaCleanupInstruction;
						if (cleanup == null || cleanup.value != copy.result) {
							continue;
						}
						if (release != null) {
							unique = false;
						}
						release = cleanup;
					}
				}
				if (unique && release != null && release.cleanup.shared_type != null && !release.cleanup.shared_type.is_weak &&
				    reaches (function, block, positions.lookup (copy) + 1, release)) {
					result.add (new SsaSharedElisionPlan (copy, release));
				}
			}
		}
		return result;
	}
}
// Independent forward state checker; it never asks the region producer to
// rederive its chosen pair and never compares a stored answer with itself.
internal class SsaSharedBalanceVerifier : Object {
	private const int ABSENT = 1;
	private const int FRESH = 2;
	private const int COPIED = 4;
	private const int BALANCED = 8;
	private static void require(bool condition, string reason) throws SsaError {
		if (!condition) {
			throw new SsaError.INVALID_SSA ("Shared balance checker: " + reason);
		}
	}
	private static void pair(SsaFunction function, SsaSharedElisionPlan plan) throws SsaError {
		require (function.async_body == null && !function.span.file.native_interface,
			"unproved function domain");
		// Checked exits outside the balanced interval keep all original cleanup.
		// Inside it, the independent state walk still rejects checked calls,
		// exceptional edges, observers and exits before the exact release.
		require (plan.acquisition.action == SharedAction.CLONE && plan.cleanup.value == plan.acquisition.result &&
			plan.cleanup.cleanup.shared_type != null && !plan.cleanup.cleanup.shared_type.is_weak, "unmatched strong clone/release");
		SsaSharedOperation? fresh = null;
		int copies = 0;
		int releases = 0;
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var operation = instruction as SsaSharedOperation;
				if (operation != null && operation.result == plan.acquisition.operand && operation.action == SharedAction.ACQUIRE) {
					fresh = operation;
				}
				if (instruction == plan.acquisition) {
					copies++;
				}
				if (instruction == plan.cleanup) {
					releases++;
				}
			}
		}
		require (fresh != null && copies == 1 && releases == 1, "lost exact fresh acquisition or pair membership");
		var states = new HashTable<SsaBlock, int> (direct_hash, direct_equal);
		var pending = new GenericArray<SsaBlock> ();
		states.insert (function.entry, ABSENT);
		pending.add (function.entry);
		for (int index = 0; index < pending.length; index++) {
			var block = pending[index];
			int state = states.lookup (block);
			foreach (var instruction in block.instructions) {
				if (instruction == fresh) {
					require ((state & ~(ABSENT | BALANCED)) == 0, "fresh acquisition overlaps an active pair");
					state = FRESH;
				} else if (instruction == plan.acquisition) {
					require (state == FRESH, "clone count is not proved one");
					state = COPIED;
				} else if (instruction == plan.cleanup) {
					require (state == COPIED, "release has no single unused clone");
					state = BALANCED;
				} else if ((state & (FRESH | COPIED)) != 0) {
					require (SsaSharedScalarWork.permits (instruction), "observer, use or unknown effect in the balance interval");
				}
			}
			var successors = block.terminator.successors ();
			if ((state & (FRESH | COPIED)) != 0) {
				require (SsaSharedScalarWork.successors (block) != null && successors.length != 0, "exit or unproved edge before balanced release");
			}
			foreach (var next in successors) {
				require (function.blocks.find (next), "foreign control-flow edge");
				int merged = states.lookup (next) | state;
				if (merged != states.lookup (next)) {
					states.insert (next, merged);
					pending.add (next);
				}
			}
		}
	}
	internal static void verify(SsaProgram program) throws SsaError {
		foreach (var function in program.functions) {
			var copies = new HashTable<SsaInstruction, bool> (direct_hash, direct_equal);
			var releases = new HashTable<SsaInstruction, bool> (direct_hash, direct_equal);
			foreach (var plan in function.shared_elisions) {
				require (!copies.contains (plan.acquisition) && !releases.contains (plan.cleanup), "duplicate elision pair");
				copies.insert (plan.acquisition, true);
				releases.insert (plan.cleanup, true);
				pair (function, plan);
			}
		}
	}
}
}
