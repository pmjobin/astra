// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Ssa {
// Verifies explicit lifecycle edges; this is never a cleanup inserter.
// Bit sets describe compiler paths: inactive=1, constructor-returned=2,
// live-with-destructor=4. They never become source or runtime storage.
public class SsaObjectLifecycleFlow : Object {
	public static void verify(SsaFunction function) throws SsaError {
		int count = (int) function.object_storage.length;
		if (count == 0) {
			return;
		}
		int[,] entries = new int[function.blocks.length, count];
		bool[] reachable = new bool[function.blocks.length];
		for (int o = 0; o < count; o++) {
			entries[function.entry.ordinal, o] = 1;
		}
		reachable[function.entry.ordinal] = true;
		bool changed = true;
		// First converge, then validate to avoid order-dependent diagnostics.
		for (int pass = 0; pass < 2; pass++) {
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
						var call = instruction as SsaLifecycleCallInstruction;
						var publication = instruction as SsaObjectReferenceInstruction;
						var storage = call != null ? call.storage : publication != null ? publication.storage : null;
						if (storage == null) {
							continue;
						}
						int o = storage.ordinal;
						int expected = call != null ? (call.constructs ? 1 : 4) : (storage.object_class.constructor == null ? 1 : 2);
						if (pass == 1 && state[o] != expected) {
							throw new SsaError.INVALID_SSA ("object storage #%d lifecycle action requires successful construction exactly once on every incoming path", o);
						}
						if (pass == 1 && call != null && !call.constructs) {
							foreach (var other in function.object_storage) {
								if ((state[other.ordinal] & 4) != 0 && other.cleanup_rank > storage.cleanup_rank) {
									throw new SsaError.INVALID_SSA ("object cleanup must follow reverse lexical storage rank");
								}
							}
						}
						state[o] = call != null ? (call.constructs ? 2 : 1) : (storage.transferable || storage.destructor == null ? 1 : 4);
					}
					if (pass == 1 && (block.terminator is SsaReturn || block.terminator is SsaFunctionEnd)) {
						for (int o = 0; o < count; o++) {
							if (state[o] != 1) {
								throw new SsaError.INVALID_SSA ("normal lexical exit leaves object storage #%d without its exact cleanup", o);
							}
						}
					}
					if (pass == 0) {
						foreach (var next in SsaConstructorInitialization.successors (block)) {
							int failed = -1;
							var branch = block.terminator as SsaConditionalBranch;
							foreach (var instruction in block.instructions) {
								var call = instruction as SsaLifecycleCallInstruction;
								if (call != null && call.constructs && call.exception_result != null && branch != null && branch.false_edge.target == next) {
									failed = call.storage.ordinal;
								}
							}

							if (!reachable[next.ordinal]) {
								reachable[next.ordinal] = true;
								changed = true;
							}
							for (int o = 0; o < count; o++) {
								int joined = entries[next.ordinal, o] | (o == failed ? 1 : state[o]);
								if (entries[next.ordinal, o] != joined) {
									entries[next.ordinal, o] = joined;
									changed = true;
								}
							}
						}
					}
				}
			} while (changed);
		}
	}
}
}
