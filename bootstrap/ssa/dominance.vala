// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Cfg {
// Astra-owned analysis, independent of SSA construction. The input must be
// verified; all answers concern graph reachability, never literal values.
public class CfgDominance : Object {
	private GenericArray<CfgBlock> blocks;
	private bool[,] relation;
	private bool[,] frontiers;
	private CfgBlock?[] parents;

	private CfgDominance (CfgFunction function) {
		var incoming = CfgPredecessors.analyze (function);
		blocks = incoming.blocks ();
		int count = blocks.length;
		relation = new bool[count, count];
		frontiers = new bool[count, count];
		parents = new CfgBlock?[count];
		for (int b = 0; b < count; b++) {
			for (int d = 0; d < count; d++) {
				relation[d, b] = blocks[b] != function.entry || d == b;
			}
		}
		// Dom(entry) = {entry}; Dom(b) = {b} union intersection Dom(pred).
		// Descending iteration from the full set also handles cyclic and
		// irreducible graphs without relying on source/block visitation order.
		bool changed = true;
		while (changed) {
			changed = false;
			for (int b = 0; b < count; b++) {
				if (blocks[b] == function.entry) {
					continue;
				}
				var predecessors = incoming.predecessors (blocks[b]);
				for (int d = 0; d < count; d++) {
					bool dominates = true;
					for (int p = 0; p < predecessors.length; p++) {
						dominates = dominates && relation[d, index (predecessors[p])];
					}
					bool next = d == b || dominates;
					changed = changed || relation[d, b] != next;
					relation[d, b] = next;
				}
			}
		}
		for (int b = 0; b < count; b++) {
			for (int d = 0; d < count; d++) {
				if (d == b || !relation[d, b]) {
					continue;
				}
				bool immediate = true;
				for (int other = 0; other < count; other++) {
					if (other != b && relation[other, b] && !relation[other, d]) {
						immediate = false;
					}
				}
				if (immediate) {
					parents[b] = blocks[d];
				}
			}
			var predecessors = incoming.predecessors (blocks[b]);
			for (int d = 0; d < count; d++) {
				if (d != b && relation[d, b]) {
					continue;
				}
				for (int p = 0; p < predecessors.length; p++) {
					// b is in DF(d) iff d dominates a predecessor of b,
					// but does not strictly dominate b (including self edges).
					frontiers[d, b] = frontiers[d, b] || relation[d, index (predecessors[p])];
				}
			}
		}
	}

	public static CfgDominance analyze(CfgFunction function) {
		return new CfgDominance (function);
	}

	private int index(CfgBlock block) {
		for (int i = 0; i < blocks.length; i++) {
			if (blocks[i] == block) {
				return i;
			}
		}
		return -1;
	}

	public bool dominates(CfgBlock dominator, CfgBlock block) {
		int d = index (dominator);
		int b = index (block);
		return d >= 0 && b >= 0 && relation[d, b];
	}

	public CfgBlock? immediate_dominator(CfgBlock block) {
		int b = index (block);
		return b < 0 ? null : parents[b];
	}

	public GenericArray<CfgBlock> dominators(CfgBlock block) {
		var result = new GenericArray<CfgBlock> ();
		for (int i = 0; i < blocks.length; i++) {
			if (dominates (blocks[i], block)) {
				result.add (blocks[i]);
			}
		}
		return result;
	}

	public GenericArray<CfgBlock> children(CfgBlock block) {
		var result = new GenericArray<CfgBlock> ();
		for (int i = 0; i < blocks.length; i++) {
			if (parents[i] == block) {
				result.add (blocks[i]);
			}
		}
		return result;
	}

	public GenericArray<CfgBlock> dominance_frontier(CfgBlock block) {
		var result = new GenericArray<CfgBlock> ();
		int d = index (block);
		for (int i = 0; d >= 0 && i < blocks.length; i++) {
			if (frontiers[d, i]) {
				result.add (blocks[i]);
			}
		}
		return result;
	}

}
}
