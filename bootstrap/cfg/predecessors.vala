// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Cfg {
private class PredecessorList : Object {
	public GenericArray<CfgBlock> blocks = new GenericArray<CfgBlock> ();
}

// Derived snapshot of a verified CFG. Queries return fresh arrays; editing
// a query result cannot change either this analysis or terminator edges.
public class CfgPredecessors : Object {
	private GenericArray<CfgBlock> reachable = new GenericArray<CfgBlock> ();
	private HashTable<CfgBlock, PredecessorList> incoming = new HashTable<CfgBlock, PredecessorList> (direct_hash, direct_equal);

	private CfgPredecessors () {
	}

	public static CfgPredecessors analyze(CfgFunction function) {
		var result = new CfgPredecessors ();
		var reachability = CfgReachability.analyze (function);
		for (int i = 0; i < function.blocks.length; i++) {
			var block = function.blocks[i];
			if (reachability.is_reachable (block)) {
				result.reachable.add (block);
				result.incoming.insert (block, new PredecessorList ());
			}
		}
		// Verified CFG arrays are in ordinal order. Parallel edges remain
		// separate entries, ordered true before false for one terminator.
		for (int i = 0; i < result.reachable.length; i++) {
			var block = result.reachable[i];
			var successors = block.terminator.successors ();
			for (int j = 0; j < successors.length; j++) {
				result.incoming.lookup (successors[j]).blocks.add (block);
			}
		}
		return result;
	}

	public GenericArray<CfgBlock> blocks() {
		return copy (reachable);
	}

	public GenericArray<CfgBlock> predecessors(CfgBlock block) {
		var list = incoming.lookup (block);
		return list == null ? new GenericArray<CfgBlock> () : copy (list.blocks);
	}

	private GenericArray<CfgBlock> copy(GenericArray<CfgBlock> source) {
		var result = new GenericArray<CfgBlock> ();
		for (int i = 0; i < source.length; i++) {
			result.add (source[i]);
		}
		return result;
	}

}
}
