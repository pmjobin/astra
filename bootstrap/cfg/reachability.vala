// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Cfg {
// Snapshot for a verified function; recompute after any graph edits.
public class CfgReachabilityResult : Object {
	private HashTable<CfgBlock, CfgBlock> reachable = new HashTable<CfgBlock, CfgBlock> (direct_hash, direct_equal);

	internal CfgReachabilityResult () {
	}

	internal bool visit(CfgBlock block) {
		return reachable.insert (block, block);
	}

	public bool is_reachable(CfgBlock block) {
		return reachable.contains (block);
	}

}

public class CfgReachability : Object {
	public static CfgReachabilityResult analyze(CfgFunction function) {
		var result = new CfgReachabilityResult ();
		var pending = new GenericArray<CfgBlock> ();
		result.visit (function.entry);
		pending.add (function.entry);
		for (int i = 0; i < pending.length; i++) {
			var successors = pending[i].terminator.successors ();
			for (int j = 0; j < successors.length; j++) {
				if (result.visit (successors[j])) {
					pending.add (successors[j]);
				}
			}
		}
		return result;
	}

}
}
