// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
namespace Astra.Cfg {
public class TaskFlow : Object {
	public static Diagnostic? check(CfgFunction function) {
		int owners = function.locals.length;
		bool any = false;
		foreach (var local in function.locals) {
			any = any || local.semantic_type is TaskType;
		}
		if (!any) {
			return null;
		}
		int[,] entries = new int[function.blocks.length, owners];
		bool[] reachable = new bool[function.blocks.length];
		reachable[function.entry.ordinal] = true;
		for (int o = 0; o < owners; o++) {
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
					int[] state = new int[owners];
					for (int o = 0; o < owners; o++) {
						state[o] = entries[block.ordinal, o];
					}
					foreach (var instruction in block.instructions) {
						var move = instruction as CfgTaskMove;
						var end = instruction as CfgTaskEnd;
						var initialize = instruction as CfgInitialize;
						var borrow = instruction as CfgTaskBorrow;
						var started = instruction as CfgTaskStarted;
						var owner = borrow != null ? borrow.source : started != null ? started.source : move != null ? move.source : end != null ? end.source : initialize == null || !(initialize.target.semantic_type is TaskType) ? null : initialize.target as CfgLocalPlace;
						if (owner == null) {
							continue;
						}
						int allowed = borrow != null || started != null || move != null ? 6 : end != null ? 10 : 1;
						if (pass == 1 && (state[owner.ordinal] == 0 || (state[owner.ordinal] & ~allowed) != 0)) {
							return new Diagnostic (instruction.span, "unique task '%s' is moved, uninitialized, or still has an unjoined started obligation on a scope exit".printf (owner.name));
						}
						state[owner.ordinal] = borrow != null ? state[owner.ordinal] : started != null ? 4 : move != null ? 8 : end != null ? 1 : 2;
					}
					if (pass == 1 && block.terminator.successors ().length == 0 && !(block.terminator is CfgExceptionUnreachable)) {
						for (int o = 0; o < owners; o++) {
							if (function.locals[o].semantic_type is TaskType && (state[o] & 6) != 0) {
								return new Diagnostic (block.terminator.span, "unique task owner exits without its exact consuming scope disposition");
							}
						}
					}
					if (pass == 0) {
						foreach (var next in block.terminator.successors ()) {
							if (!reachable[next.ordinal]) {
								reachable[next.ordinal] = true;
								changed = true;
							}
							for (int o = 0; o < owners; o++) {
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
		return null;
	}
}
}
