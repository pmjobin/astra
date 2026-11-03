// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Ssa {
internal class SsaLifetimeSnapshot : Object {
	private int[] states;
	internal SsaLifetimeSnapshot (int[] incoming) {
		states = new int[incoming.length];
		for (int i = 0; i < incoming.length; i++) {
			states[i] = incoming[i];
		}
	}

	internal SsaLifetimeSnapshot.buffers (OwnershipState[] incoming) {
		states = new int[incoming.length];
		for (int i = 0; i < incoming.length; i++) {
			states[i] = (incoming[i].may_own () ? 2 : 0) | ((incoming[i] & OwnershipState.MOVED) != 0 ? 4 : 0);
		}
	}
	internal int state(int ordinal) {
		return states[ordinal];
	}

}

// Ordering consumes snapshots of the existing lifetime authorities. It does
// not introduce another owner state machine or runtime responsibility.
internal class SsaLifetimeFacts : Object {
	internal HashTable<SsaInstruction, SsaLifetimeSnapshot> before = new HashTable<SsaInstruction, SsaLifetimeSnapshot> (direct_hash, direct_equal);
	internal bool enabled;
	internal SsaLifetimeFacts (SsaFunction function, bool all = false) {
		enabled = all;
		foreach (var storage in function.buffer_storage) {
			if (storage.record_type != null) {
				enabled = true;
				break;
			}
		}
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				if (instruction is SsaScopedAllocator) {
					enabled = true;
				}
			}
		}
	}

	internal void capture(SsaInstruction instruction, int[] state) {
		if (enabled) {
			before.insert (instruction, new SsaLifetimeSnapshot (state));
		}
	}

	internal void capture_buffers(SsaInstruction instruction, OwnershipState[] state) {
		if (enabled) {
			before.insert (instruction, new SsaLifetimeSnapshot.buffers (state));
		}
	}

}

// Independent verification of concrete owner slots. These are compiler path
// facts using the shared ownership lattice, never runtime active flags.
public class SsaBufferMemoryFlow : Object {
	internal static SsaLifetimeFacts verify(SsaFunction function) throws SsaError {
		var facts = new SsaLifetimeFacts (function);
		int count = (int) function.buffer_storage.length;
		if (count == 0) {
			return facts;
		}
		OwnershipState[,] entries = new OwnershipState[function.blocks.length, count];
		bool[,] uninitialized = new bool[function.blocks.length, count];
		bool[] reachable = new bool[function.blocks.length];
		for (int o = 0; o < count; o++) {
			uninitialized[function.entry.ordinal, o] = true;
		}
		reachable[function.entry.ordinal] = true;
		var reads = new HashTable<SsaBufferPair, SsaBufferReadInstruction> (direct_hash, direct_equal);
		var snapshots = new HashTable<SsaBufferPair, int> (direct_hash, direct_equal);
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				if (instruction is SsaBufferReadInstruction) {
					var read = (SsaBufferReadInstruction) instruction;
					reads.insert (read.pair, read);
				}
			}
		}
		for (int pass = 0; pass < 2; pass++) {
			bool changed = false;
			do {
				changed = false;
				foreach (var block in function.blocks) {
					if (!reachable[block.ordinal]) {
						continue;
					}
					OwnershipState[] state = new OwnershipState[count];
					bool[] missing = new bool[count];
					for (int o = 0; o < count; o++) {
						state[o] = entries[block.ordinal, o];
						missing[o] = uninitialized[block.ordinal, o];
					}
					foreach (var instruction in block.instructions) {
						if (pass == 1) {
							facts.capture_buffers (instruction, state);
						}
						var slot_capture = instruction as SsaBufferSlotCaptureInstruction;
						if (pass == 1 && slot_capture != null && slot_capture.place.storage != null) {
							int o = slot_capture.place.storage.ordinal;
							if (missing[o] || !state[o].definitely_owned ()) {
								throw new SsaError.INVALID_SSA ("buffer slot capture requires initialized live owner storage #%d", o);
							}
						}
						var exchange = instruction as SsaBufferExchangeInstruction;
						if (pass == 1 && exchange != null) {
							foreach (var slot in new SsaBufferPlace[] { exchange.left, exchange.right }) {
								if (slot.storage != null) {
									int o = slot.storage.ordinal;
									if (missing[o] || !state[o].definitely_owned ()) {
										throw new SsaError.INVALID_SSA ("buffer exchange requires initialized live owner storage #%d", o);
									}
								}
							}
						}
						var read = instruction as SsaBufferReadInstruction;
						if (read != null && read.place.storage != null) {
							int o = read.place.storage.ordinal;
							if (pass == 1 && (missing[o] || (state[o] & OwnershipState.RELEASED) != 0)) {
								throw new SsaError.INVALID_SSA ("buffer storage #%d read requires initialized, unreleased physical contents", o);
							}
							snapshots.insert (read.pair, (int) state[o]);
						}
						var write = instruction as SsaBufferWriteInstruction;
						if (write != null) {
							if (pass == 1 && !write.pair.is_empty) {
								require_owned_capture (write.pair, reads, snapshots);
							}
							if (write.place.storage != null) {
								int o = write.place.storage.ordinal;
								if (pass == 1 && !write.pair.is_empty && state[o].may_own ()) {
									throw new SsaError.INVALID_SSA ("buffer replacement must clean old storage #%d before installing incoming ownership", o);
								}
								if (pass == 1 && write.pair.is_empty && missing[o]) {
									throw new SsaError.INVALID_SSA ("buffer disarm requires initialized owner storage");
								}
								state[o] = write.pair.is_empty ? OwnershipState.MOVED : OwnershipState.OWNED;
								missing[o] = false;
							}
						}
						var cleanup = instruction as SsaBufferDeallocateInstruction;
						if (cleanup != null) {
							var source = reads.lookup (cleanup.pair);
							if (source != null && source.place.storage != null) {
								int o = source.place.storage.ordinal;
								if (pass == 1 && (missing[o] || (state[o] & OwnershipState.RELEASED) != 0)) {
									throw new SsaError.INVALID_SSA ("buffer storage #%d cannot be deallocated twice", o);
								}
								state[o] = OwnershipState.RELEASED;
							}
						}
						if (pass == 1 && instruction is SsaScopedAllocator) {
							require_owned_capture (((SsaScopedAllocator) instruction).pair, reads, snapshots);
						}
						if (pass == 1 && instruction is SsaBufferBorrowInstruction) {
							require_owned_capture (((SsaBufferBorrowInstruction) instruction).pair, reads, snapshots);
						}
						if (pass == 1 && instruction is SsaCallInstruction) {
							foreach (var argument in ((SsaCallInstruction) instruction).buffer_arguments) {
								require_owned_capture (argument.pair, reads, snapshots);
							}
						}
					}
					if (pass == 1 && block.terminator is SsaBufferReturn) {
						require_owned_capture (((SsaBufferReturn) block.terminator).pair, reads, snapshots);
					}
					if (pass == 1 && (block.terminator is SsaReturn || block.terminator is SsaFunctionEnd)) {
						for (int o = 0; o < count; o++) {
							if (state[o].may_own ()) {
								throw new SsaError.INVALID_SSA ("normal exit leaves buffer storage #%d without cleanup or complete transfer", o);
							}
						}
					}
					if (pass == 0) {
						foreach (var next in SsaConstructorInitialization.successors (block)) {
							if (!reachable[next.ordinal]) {
								reachable[next.ordinal] = true;
								changed = true;
							}
							for (int o = 0; o < count; o++) {
								var joined = OwnershipState.join (entries[next.ordinal, o], state[o]);
								bool absent = uninitialized[next.ordinal, o] || missing[o];
								if (joined != entries[next.ordinal, o] || absent != uninitialized[next.ordinal, o]) {
									entries[next.ordinal, o] = joined;
									uninitialized[next.ordinal, o] = absent;
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

	private static void require_owned_capture(SsaBufferPair pair, HashTable<SsaBufferPair, SsaBufferReadInstruction> reads, HashTable<SsaBufferPair, int> snapshots) throws SsaError {
		var read = reads.lookup (pair);
		if (read != null && read.place.storage != null && snapshots.lookup (pair) != (int) OwnershipState.OWNED) {
			throw new SsaError.INVALID_SSA ("buffer borrow/transfer requires a definitely live captured owner");
		}
	}

}

// Combine the existing scalar and complete-buffer lifetime snapshots. A
// backing loan is live exactly while its lexical context owner is live.
internal class SsaScopedBackingFlow : Object {
	private static void require(bool condition, string message) throws SsaError {
		if (!condition) {
			throw new SsaError.INVALID_SSA ("scoped backing: %s", message);
		}
	}

	internal static void verify(SsaFunction function, SsaLifetimeFacts scalars, SsaLifetimeFacts buffers) throws SsaError {
		var contexts = new HashTable<SsaHeapOwner, SsaScopedAllocator> (direct_hash, direct_equal);
		var reads = new HashTable<SsaBufferPair, SsaBufferStorage> (direct_hash, direct_equal);
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var read = instruction as SsaBufferReadInstruction;
				if (read != null && read.place.storage != null) {
					reads.insert (read.pair, read.place.storage);
				}
				var scoped = instruction as SsaScopedAllocator;
				if (scoped != null) {
					require (!contexts.contains (scoped.owner), "one context owner cannot acquire competing backing loans");
					contexts.insert (scoped.owner, scoped);
				}
			}
		}
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var event = instruction as SsaHeapOwnerEvent;
				if (event != null && contexts.contains (event.owner)) {
					var scoped = contexts.lookup (event.owner);
					require (event.action == SsaHeapOwnerAction.READ || event.action == SsaHeapOwnerAction.ACQUIRE && event.effect == scoped && event.value == scoped.result || event.action == SsaHeapOwnerAction.END && event.effect is SsaCleanupInstruction && ((SsaCleanupInstruction) event.effect).value == event.value && event.value.semantic_type == scoped.result.semantic_type && ((SsaCleanupInstruction) event.effect).cleanup == scoped.owner.cleanup, "context can only acquire once, borrow, and retire at its checked lexical cleanup");
				}
				var factory = instruction as SsaScopedAllocator;
				if (factory != null) {
					var snapshot = buffers.before.lookup (factory);
					require (snapshot != null && snapshot.state (factory.backing.ordinal) == 2, "factory requires a definitely live complete backing buffer");
				}
				foreach (var scoped in contexts.get_values ()) {
					var state = scalars.before.lookup (instruction);
					if (state == null || (state.state (scoped.owner.ordinal) & 2) == 0) {
						continue;
					}
					var read = instruction as SsaBufferReadInstruction;
					var write = instruction as SsaBufferWriteInstruction;
					var capture = instruction as SsaBufferSlotCaptureInstruction;
					var exchange = instruction as SsaBufferExchangeInstruction;
					var drop = instruction as SsaBufferDeallocateInstruction;
					require ((read == null || read.place.storage != scoped.backing) && (write == null || write.place.storage != scoped.backing) && (capture == null || capture.place.storage != scoped.backing) && (exchange == null || exchange.left.storage != scoped.backing && exchange.right.storage != scoped.backing) && (drop == null || reads.lookup (drop.pair) != scoped.backing), "backing access, replacement, transfer or destruction overlaps its exclusive context loan");
				}
			}
		}
	}

}

internal class SsaRecordRetirementFlow : Object {
	private static SsaStruct? record_type(Object owner) {
		return (owner is SsaHeapOwner) ? ((SsaHeapOwner) owner).record_type : ((SsaBufferStorage) owner).record_type;
	}

	private static int root(Object owner) {
		return (owner is SsaHeapOwner) ? ((SsaHeapOwner) owner).source_ordinal : ((SsaBufferStorage) owner).record_source_ordinal;
	}

	private static int rank(Object owner) {
		return (owner is SsaHeapOwner) ? ((SsaHeapOwner) owner).record_rank : ((SsaBufferStorage) owner).record_rank;
	}

	private static int state(SsaInstruction instruction, Object owner, SsaLifetimeFacts scalars, SsaLifetimeFacts buffers) {
		var snapshot = ((owner is SsaHeapOwner) ? scalars : buffers).before.lookup (instruction);
		if (snapshot == null) {
			return 0;
		}
		return snapshot.state ((owner is SsaHeapOwner) ? ((SsaHeapOwner) owner).ordinal : ((SsaBufferStorage) owner).ordinal);
	}

	internal static void verify(SsaFunction function, SsaLifetimeFacts scalars, SsaLifetimeFacts buffers) throws SsaError {
		if (!buffers.enabled) {
			return;
		}
		var owners = new GenericArray<Object> ();
		foreach (var owner in function.heap_owners) {
			owners.add (owner);
		}
		foreach (var owner in function.buffer_storage) {
			owners.add (owner);
		}
		var parameters = new HashTable<Object, int> (direct_hash, direct_equal);
		var scalar_parameters = SsaHeapOwnerFlow.parameter_owners (function);
		foreach (var owner in scalar_parameters.get_keys ()) {
			parameters.insert (owner, scalar_parameters.lookup (owner));
		}
		foreach (var instruction in function.entry.instructions) {
			var record = instruction as SsaStructBoundaryAcquire;
			if (record != null && record.parameter != null) {
				foreach (var owner in record.buffers) {
					parameters.insert (owner, record.parameter.source_ordinal);
				}
			}
			var write = instruction as SsaBufferWriteInstruction;
			if (write == null || !write.initializes || write.place.storage == null) {
				continue;
			}
			foreach (var parameter in function.buffer_parameters) {
				if (write.pair == parameter.pair) {
					parameters.insert (write.place.storage, parameter.source_ordinal);
				}
			}
		}
		var reads = new HashTable<SsaBufferPair, SsaBufferReadInstruction> (direct_hash, direct_equal);
		var replacements = new HashTable<SsaBufferDeallocateInstruction, bool> (direct_hash, direct_equal);
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var read = instruction as SsaBufferReadInstruction;
				if (read != null) {
					reads.insert (read.pair, read);
				}
				var write = instruction as SsaBufferWriteInstruction;
				if (write != null && write.record_retirement != null) {
					replacements.insert (write.record_retirement, true);
				}
			}
		}
		foreach (var block in function.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var instruction = block.instructions[i];
				Object? owner = null;
				var event = instruction as SsaHeapOwnerEvent;
				if (event != null && event.action == SsaHeapOwnerAction.END && event.owner != null && (!(event.effect is SsaCleanupInstruction) || ((SsaCleanupInstruction) event.effect).record_replacement == null)) {
					owner = event.owner;
				}
				var cleanup = instruction as SsaBufferDeallocateInstruction;
				if (cleanup != null && !replacements.contains (cleanup)) {
					var read = reads.lookup (cleanup.pair);
					var next = i + 1 >= block.instructions.length ? null : block.instructions[i + 1] as SsaBufferWriteInstruction;
					if (read != null && read.place.storage != null && (next == null || next.place.storage != read.place.storage)) {
						owner = read.place.storage;
					}
				}
				if (owner == null) {
					continue;
				}
				foreach (var other in owners) {
					int other_state = state (instruction, other, scalars, buffers);
					if (parameters.contains (owner) && (state (instruction, owner, scalars, buffers) & 2) != 0 && parameters.contains (other) && parameters.lookup (other) > parameters.lookup (owner) && (other_state & 2) != 0) {
						throw new SsaError.INVALID_SSA ("automatic cleanup must preserve reverse parameter declaration order across scalar and buffer owners");
					}
					if (record_type (owner) != null && record_type (other) == record_type (owner) && root (other) == root (owner) && rank (other) > rank (owner) && (other_state & 6) != 0) {
						throw new SsaError.INVALID_SSA ("record retirement lost reverse written field order across scalar and buffer owners");
					}
				}
			}
		}
	}

}
}
