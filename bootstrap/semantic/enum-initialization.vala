// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
internal class EnumOrdinals : Object {
	private int[] items = new int[8];
	internal int length;
	internal int at(int index) {
		return items[index];
	}

	internal void add(int value) {
		if (length == items.length) {
			items.resize (items.length * 2);
		}
		items[length++] = value;
	}

}
// A verifier builds these events from its own ordered instructions. No producer
// supplies initialization facts; the fixed point derives them from actual edges.
internal class EnumFlowStep : Object {
	internal EnumOrdinals reads = new EnumOrdinals ();
	internal EnumOrdinals writes = new EnumOrdinals ();
	internal EnumOrdinals kills = new EnumOrdinals ();
	internal EnumOrdinals destroys = new EnumOrdinals ();
	internal EnumOrdinals begins = new EnumOrdinals ();
	internal EnumOrdinals ends = new EnumOrdinals ();
	internal EnumOrdinals acquires = new EnumOrdinals ();
	internal EnumOrdinals transfers = new EnumOrdinals ();
}

public class EnumFlowBlock : Object {
	internal EnumOrdinals successors = new EnumOrdinals ();
	internal bool normal_exit;
	internal GenericArray<EnumFlowStep> steps = new GenericArray<EnumFlowStep> ();
}

internal class EnumFlowFacts : Object {
	internal bool[] initialized;
	internal EnumFlowFacts (int count, bool initial) {
		initialized = new bool[count];
		for (int i = 0; i < count; i++) {
			initialized[i] = initial;
		}
	}

}

public class EnumInitializationProof : Object {
	public static void verify(int slots, int entry, GenericArray<EnumFlowBlock> blocks, bool[]? owners = null, int[]? inspection_roots = null, int[]? inspection_loans = null) throws EnumContractError {
		if (slots < 0 || entry < 0 || entry >= blocks.length) {
			throw new EnumContractError.INVALID_GRAPH ("enum initialization has invalid slot/entry bounds");
		}
		foreach (var block in blocks) {
			for (int s = 0; s < block.successors.length; s++) {
				if (block.successors.at (s) < 0 || block.successors.at (s) >= blocks.length) {
					throw new EnumContractError.INVALID_GRAPH ("enum initialization edge is outside the function");
				}
			}
			foreach (var step in block.steps) {
				for (int r = 0; r < step.reads.length; r++) {
					if (step.reads.at (r) < 0 || step.reads.at (r) >= slots) {
						throw new EnumContractError.INVALID_GRAPH ("enum initialization read is outside the slot plan");
					}
				}
				for (int w = 0; w < step.writes.length; w++) {
					if (step.writes.at (w) < 0 || step.writes.at (w) >= slots) {
						throw new EnumContractError.INVALID_GRAPH ("enum initialization write is outside the slot plan");
					}
				}
			}
		}
		var reachable = new bool[blocks.length];
		var pending = new EnumOrdinals ();
		pending.add (entry);
		reachable[entry] = true;
		for (int i = 0; i < pending.length; i++) {
			var successors = blocks[pending.at (i)].successors;
			for (int s = 0; s < successors.length; s++) {
				int successor = successors.at (s);
				if (!reachable[successor]) {
					reachable[successor] = true;
					pending.add (successor);
				}
			}
		}
		var inputs = new GenericArray<EnumFlowFacts> ();
		var outputs = new GenericArray<EnumFlowFacts> ();
		for (int b = 0; b < blocks.length; b++) {
			inputs.add (new EnumFlowFacts (slots, b != entry));
			outputs.add (new EnumFlowFacts (slots, b != entry));
		}
		bool changed = true;
		while (changed) {
			changed = false;
			for (int b = 0; b < blocks.length; b++) {
				if (!reachable[b]) {
					continue;
				}
				var incoming = new EnumFlowFacts (slots, b != entry);
				if (b != entry) {
					for (int predecessor = 0; predecessor < blocks.length; predecessor++) {
						if (!reachable[predecessor]) {
							continue;
						}
						var successors = blocks[predecessor].successors;
						for (int e = 0; e < successors.length; e++) {
							if (successors.at (e) == b) {
								for (int s = 0; s < slots; s++) {
									incoming.initialized[s] &= outputs[predecessor].initialized[s];
								}
							}
						}
					}
				}
				inputs[b] = incoming;
				var outgoing = new EnumFlowFacts (slots, false);
				for (int s = 0; s < slots; s++) {
					outgoing.initialized[s] = incoming.initialized[s];
				}
				foreach (var step in blocks[b].steps) {
					for (int w = 0; w < step.writes.length; w++) {
						outgoing.initialized[step.writes.at (w)] = true;
					}
					for (int k = 0; k < step.kills.length; k++) {
						outgoing.initialized[step.kills.at (k)] = false;
					}
				}
				for (int s = 0; s < slots; s++) {
					if (outputs[b].initialized[s] != outgoing.initialized[s]) {
						changed = true;
					}
				}
				outputs[b] = outgoing;
			}
		}
		if (owners != null) {
			verify_lifetimes (slots, entry, blocks, owners, reachable);
			verify_transfers (slots, entry, blocks, reachable);
			verify_disposals (slots, entry, blocks, reachable);
			if (inspection_roots != null) {
				verify_inspections (slots, entry, blocks, inspection_roots, inspection_loans, reachable);
			}
		}
		for (int b = 0; b < blocks.length; b++) {
			if (!reachable[b]) {
				continue;
			}
			var facts = inputs[b];
			foreach (var step in blocks[b].steps) {
				for (int r = 0; r < step.reads.length; r++) {
					int source = step.reads.at (r);
					if (!facts.initialized[source]) {
						throw new EnumContractError.INVALID_GRAPH ("enum slot #%d is not initialized on every incoming path to block #%d", source, b);
					}
				}
				for (int w = 0; w < step.writes.length; w++) {
					facts.initialized[step.writes.at (w)] = true;
				}
				for (int k = 0; k < step.kills.length; k++) {
					facts.initialized[step.kills.at (k)] = false;
				}
			}
		}
	}

	// A captured carrier has physical bytes before commitment, but obtains
	// ownership only from the commit's acquisition event. Derive definite
	// authority on every incoming edge, separately from byte initialization.
	private static void verify_transfers(int slots, int entry, GenericArray<EnumFlowBlock> blocks, bool[] reachable) throws EnumContractError {
		var inputs = new GenericArray<EnumFlowFacts> ();
		var outputs = new GenericArray<EnumFlowFacts> ();
		for (int b = 0; b < blocks.length; b++) {
			inputs.add (new EnumFlowFacts (slots, b != entry));
			outputs.add (new EnumFlowFacts (slots, b != entry));
		}
		bool changed = true;
		while (changed) {
			changed = false;
			for (int b = 0; b < blocks.length; b++) {
				if (!reachable[b]) {
					continue;
				}
				var state = new EnumFlowFacts (slots, b != entry);
				if (b != entry) {
					for (int p = 0; p < blocks.length; p++) {
						if (!reachable[p]) {
							continue;
						}
						for (int e = 0; e < blocks[p].successors.length; e++) {
							if (blocks[p].successors.at (e) == b) {
								for (int s = 0; s < slots; s++) {
									state.initialized[s] &= outputs[p].initialized[s];
								}
							}
						}
					}
				}
				for (int s = 0; s < slots; s++) {
					inputs[b].initialized[s] = state.initialized[s];
				}
				foreach (var step in blocks[b].steps) {
					for (int a = 0; a < step.acquires.length; a++) {
						state.initialized[step.acquires.at (a)] = true;
					}
					for (int k = 0; k < step.kills.length; k++) {
						state.initialized[step.kills.at (k)] = false;
					}
				}
				for (int s = 0; s < slots; s++) {
					if (outputs[b].initialized[s] != state.initialized[s]) {
						changed = true;
					}
				}
				outputs[b] = state;
			}
		}
		for (int b = 0; b < blocks.length; b++) {
			if (!reachable[b]) {
				continue;
			}
			var state = inputs[b];
			foreach (var step in blocks[b].steps) {
				for (int t = 0; t < step.transfers.length; t++) {
					int source = step.transfers.at (t);
					if (!state.initialized[source]) {
						throw new EnumContractError.INVALID_GRAPH ("enum transfer #%d requires committed live ownership on every incoming path", source);
					}
				}
				for (int a = 0; a < step.acquires.length; a++) {
					state.initialized[step.acquires.at (a)] = true;
				}
				for (int k = 0; k < step.kills.length; k++) {
					state.initialized[step.kills.at (k)] = false;
				}
			}
		}
	}

	private static void verify_lifetimes(int slots, int entry, GenericArray<EnumFlowBlock> blocks, bool[] owners, bool[] reachable) throws EnumContractError {
		if (owners.length != slots) {
			throw new EnumContractError.INVALID_GRAPH ("enum owner inventory length mismatch");
		}
		var entries = new bool[blocks.length, slots];
		var outputs = new bool[blocks.length, slots];
		bool changed = true;
		while (changed) {
			changed = false;
			for (int b = 0; b < blocks.length; b++) {
				if (!reachable[b]) {
					continue;
				}
				var state = new bool[slots];
				for (int p = 0; p < blocks.length; p++) {
					if (!reachable[p] || b == entry) {
						continue;
					}
					for (int e = 0; e < blocks[p].successors.length; e++) {
						if (blocks[p].successors.at (e) == b) {
							for (int s = 0; s < slots; s++) {
								state[s] |= outputs[p, s];
							}
						}
					}
				}
				for (int s = 0; s < slots; s++) {
					entries[b, s] = state[s];
				}
				foreach (var step in blocks[b].steps) {
					for (int a = 0; a < step.acquires.length; a++) {
						state[step.acquires.at (a)] = true;
					}
					for (int k = 0; k < step.kills.length; k++) {
						state[step.kills.at (k)] = false;
					}
				}
				for (int s = 0; s < slots; s++) {
					if (outputs[b, s] != state[s]) {
						outputs[b, s] = state[s];
						changed = true;
					}
				}
			}
		}
		for (int b = 0; b < blocks.length; b++) {
			if (!reachable[b]) {
				continue;
			}
			var state = new bool[slots];
			for (int s = 0; s < slots; s++) {
				state[s] = entries[b, s];
			}
			foreach (var step in blocks[b].steps) {
				for (int a = 0; a < step.acquires.length; a++) {
					int destination = step.acquires.at (a);
					if (!owners[destination] || state[destination]) {
						throw new EnumContractError.INVALID_GRAPH ("enum owner #%d acquired twice or installed over live ownership", destination);
					}
					state[destination] = true;
				}
				for (int k = 0; k < step.kills.length; k++) {
					state[step.kills.at (k)] = false;
				}
			}
			if (blocks[b].normal_exit) {
				for (int s = 0; s < slots; s++) {
					if (owners[s] && state[s]) {
						throw new EnumContractError.INVALID_GRAPH ("normal exit leaves enum owner #%d without active cleanup or transfer", s);
					}
				}
			}
		}
	}

	private static void verify_inspections(int slots, int entry, GenericArray<EnumFlowBlock> blocks, int[] roots, int[]? loans, bool[] reachable) throws EnumContractError {
		var inputs = new int[blocks.length, slots];
		var outputs = new int[blocks.length, slots];
		bool changed = true;
		while (changed) {
			changed = false;
			for (int b = 0; b < blocks.length; b++) {
				if (!reachable[b]) {
					continue;
				}
				var state = new int[slots];
				for (int v = 0; v < slots; v++) {
					state[v] = 1;
				}
				if (b != entry) {
					for (int v = 0; v < slots; v++) {
						state[v] = 0;
					}
					for (int p = 0; p < blocks.length; p++) {
						if (!reachable[p]) {
							continue;
						}
						for (int e = 0; e < blocks[p].successors.length; e++) {
							if (blocks[p].successors.at (e) == b) {
								for (int v = 0; v < slots; v++) {
									state[v] |= outputs[p, v];
								}
							}
						}
					}
				}
				for (int v = 0; v < slots; v++) {
					inputs[b, v] = state[v];
				}
				foreach (var step in blocks[b].steps) {
					for (int l = 0; l < step.begins.length; l++) {
						state[step.begins.at (l)] = 2;
					}
					for (int l = 0; l < step.ends.length; l++) {
						state[step.ends.at (l)] = 1;
					}
				}
				for (int v = 0; v < slots; v++) {
					if (outputs[b, v] != state[v]) {
						outputs[b, v] = state[v];
						changed = true;
					}
				}
			}
		}
		for (int b = 0; b < blocks.length; b++) {
			if (!reachable[b]) {
				continue;
			}
			var state = new int[slots];
			for (int v = 0; v < slots; v++) {
				state[v] = inputs[b, v];
			}
			foreach (var step in blocks[b].steps) {
				for (int l = 0; l < step.begins.length; l++) {
					int view = step.begins.at (l);
					if (roots[view] < 0 || state[view] != 1) {
						throw new EnumContractError.INVALID_GRAPH ("enum inspection begins without exact fresh live-root authority");
					}
					state[view] = 2;
				}
				for (int l = 0; l < step.ends.length; l++) {
					int view = step.ends.at (l);
					if (state[view] != 2) {
						throw new EnumContractError.INVALID_GRAPH ("enum inspection ends twice or without its live loan");
					}
					state[view] = 1;
				}
				for (int r = 0; r < step.reads.length; r++) {
					int slot = step.reads.at (r);
					if (roots[slot] >= 0) {
						int loan = loans == null ? slot : loans[slot];
						if (loan < 0 || loan >= slots || state[loan] != 2) {
							throw new EnumContractError.INVALID_GRAPH ("enum view survives the end of its inspection");
						}
					}
				}
				for (int k = 0; k < step.kills.length; k++) {
					int root = step.kills.at (k);
					for (int v = 0; v < slots; v++) {
						if (roots[v] == root && (state[v] & 2) != 0) {
							throw new EnumContractError.INVALID_GRAPH ("enum owner invalidation overlaps a surviving inspection");
						}
					}
				}
			}
			if (blocks[b].normal_exit) {
				for (int v = 0; v < slots; v++) {
					if ((state[v] & 2) != 0) {
						throw new EnumContractError.INVALID_GRAPH ("normal exit leaves an enum inspection active");
					}
				}
			}
		}
	}

	private static void verify_disposals(int slots, int entry, GenericArray<EnumFlowBlock> blocks, bool[] reachable) throws EnumContractError {
		var inputs = new bool[blocks.length, slots];
		var outputs = new bool[blocks.length, slots];
		bool changed = true;
		while (changed) {
			changed = false;
			for (int b = 0; b < blocks.length; b++) {
				if (!reachable[b]) {
					continue;
				}
				var state = new bool[slots];
				if (b != entry) {
					for (int p = 0; p < blocks.length; p++) {
						if (!reachable[p]) {
							continue;
						}
						for (int e = 0; e < blocks[p].successors.length; e++) {
							if (blocks[p].successors.at (e) == b) {
								for (int s = 0; s < slots; s++) {
									state[s] |= outputs[p, s];
								}
							}
						}
					}
				}
				for (int s = 0; s < slots; s++) {
					inputs[b, s] = state[s];
				}
				foreach (var step in blocks[b].steps) {
					for (int a = 0; a < step.acquires.length; a++) {
						state[step.acquires.at (a)] = false;
					}
					for (int d = 0; d < step.destroys.length; d++) {
						state[step.destroys.at (d)] = true;
					}
				}
				for (int s = 0; s < slots; s++) {
					if (outputs[b, s] != state[s]) {
						changed = true;
						outputs[b, s] = state[s];
					}
				}
			}
		}
		for (int b = 0; b < blocks.length; b++) {
			if (!reachable[b]) {
				continue;
			}
			var state = new bool[slots];
			for (int s = 0; s < slots; s++) {
				state[s] = inputs[b, s];
			}
			foreach (var step in blocks[b].steps) {
				for (int a = 0; a < step.acquires.length; a++) {
					state[step.acquires.at (a)] = false;
				}
				for (int d = 0; d < step.destroys.length; d++) {
					int owner = step.destroys.at (d);
					if (state[owner]) {
						throw new EnumContractError.INVALID_GRAPH ("enum owner #%d disposed twice on a normal path", owner);
					}
					state[owner] = true;
				}
			}
		}
	}

}
}
