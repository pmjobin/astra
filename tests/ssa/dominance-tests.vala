// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.Ssa {
private void ordinals(GenericArray<CfgBlock> blocks, int[] expected) {
	assert (blocks.length == expected.length);
	for (int i = 0; i < expected.length; i++) {
		assert (blocks[i].ordinal == expected[i]);
	}
}

private void single() {
	var function = cfg_ok ("void f(){}").functions[0];
	var predecessors = CfgPredecessors.analyze (function);
	ordinals (predecessors.blocks (), {0});
	assert (predecessors.predecessors (function.entry).length == 0);
	var dom = CfgDominance.analyze (function);
	ordinals (dom.dominators (function.entry), {0});
	assert (dom.immediate_dominator (function.entry) == null);
	assert (dom.children (function.entry).length == 0);
	assert (dom.dominance_frontier (function.entry).length == 0);
}

private void diamond() {
	var function = cfg_ok ("void f(bool c){if(c){}else{}return;}").functions[0];
	var b = function.blocks;
	var pred = CfgPredecessors.analyze (function);
	ordinals (pred.predecessors (b[3]), {1, 2});
	ordinals (pred.predecessors (b[1]), {0});
	ordinals (pred.predecessors (b[2]), {0});
	var dom = CfgDominance.analyze (function);
	for (int i = 1; i < 4; i++) {
		assert (dom.dominates (b[0], b[i]) && dom.dominates (b[i], b[i]));
		assert (dom.immediate_dominator (b[i]) == b[0]);
		ordinals (dom.dominators (b[i]), {0, i});
	}
	assert (!dom.dominates (b[1], b[2]) && !dom.dominates (b[2], b[1]));
	ordinals (dom.children (b[0]), {1, 2, 3});
	assert (dom.dominance_frontier (b[0]).length == 0);
	ordinals (dom.dominance_frontier (b[1]), {3});
	ordinals (dom.dominance_frontier (b[2]), {3});
	assert (dom.dominance_frontier (b[3]).length == 0);
	// Query arrays cannot mutate the snapshot or graph authority.
	pred.predecessors (b[3]).remove_index (0);
	pred.blocks ().remove_index (0);
	dom.dominance_frontier (b[1]).remove_index (0);
	ordinals (pred.predecessors (b[3]), {1, 2});
	ordinals (pred.blocks (), {0, 1, 2, 3});
	ordinals (dom.dominance_frontier (b[1]), {3});
}

private void no_else() {
	var function = cfg_ok ("void f(bool c){if(c){}return;}").functions[0];
	var b = function.blocks;
	ordinals (CfgPredecessors.analyze (function).predecessors (b[2]), {0, 1});
	var dom = CfgDominance.analyze (function);
	assert (dom.immediate_dominator (b[1]) == b[0] && dom.immediate_dominator (b[2]) == b[0]);
	ordinals (dom.dominance_frontier (b[1]), {2});
	assert (dom.dominance_frontier (b[0]).length == 0);
}

private void parallel_edges() {
	var cfg = cfg_ok ("void f(bool c){if(c){}else{}return;}");
	var original = cfg.functions[0];
	var join = original.blocks[3];
	var entry = new CfgBlock (original.span, 0, original.entry.instructions, new CfgConditionalBranch (original.span, new CfgParameterValue (original.span, original.parameters[0]), join, join));
	original.blocks[0] = entry;
	var function = new CfgFunction (original.span, original.name_span, original.name, original.return_type, 0, original.parameters, original.locals, original.blocks, entry);
	cfg.functions[0] = function;
	try {
		assert (CfgFlowChecker.check (cfg).diagnostic == null);
	} catch (CfgError error) {
		GLib.error ("Parallel-edge CFG is invalid: %s", error.message);
	}
	var pred = CfgPredecessors.analyze (function);
	ordinals (pred.blocks (), {0, 3});
	ordinals (pred.predecessors (join), {0, 0});
	var dom = CfgDominance.analyze (function);
	ordinals (dom.dominators (join), {0, 3});
	assert (dom.immediate_dominator (join) == entry && dom.dominance_frontier (entry).length == 0);
}

private void nested() {
	var function = cfg_ok ("void f(bool a,bool b){if(a){if(b){}else{}}else{}return;}").functions[0];
	var b = function.blocks;
	var pred = CfgPredecessors.analyze (function);
	ordinals (pred.predecessors (b[3]), {2, 6});
	ordinals (pred.predecessors (b[6]), {4, 5});
	var dom = CfgDominance.analyze (function);
	ordinals (dom.children (b[0]), {1, 2, 3});
	ordinals (dom.children (b[1]), {4, 5, 6});
	ordinals (dom.dominators (b[6]), {0, 1, 6});
	ordinals (dom.dominance_frontier (b[4]), {6});
	ordinals (dom.dominance_frontier (b[5]), {6});
	ordinals (dom.dominance_frontier (b[6]), {3});
	ordinals (dom.dominance_frontier (b[1]), {3});
	assert (dom.immediate_dominator (b[6]) == b[1] && dom.immediate_dominator (b[3]) == b[0]);
}

private void multiple_joins() {
	var function = cfg_ok ("void f(bool a,bool b){if(a){}else{}if(b){}else{}return;}").functions[0];
	var b = function.blocks;
	var dom = CfgDominance.analyze (function);
	ordinals (dom.children (b[3]), {4, 5, 6});
	ordinals (dom.dominance_frontier (b[1]), {3});
	ordinals (dom.dominance_frontier (b[4]), {6});
	ordinals (dom.dominators (b[6]), {0, 3, 6});
}

private void unreachable_join() {
	var function = cfg_ok ("int f(bool c){if(c){return 1;}else{return 2;}}").functions[0];
	var b = function.blocks;
	var pred = CfgPredecessors.analyze (function);
	ordinals (pred.blocks (), {0, 1, 2});
	assert (pred.predecessors (b[3]).length == 0);
	var dom = CfgDominance.analyze (function);
	assert (!dom.dominates (b[0], b[3]) && !dom.dominates (b[3], b[3]));
	assert (dom.immediate_dominator (b[3]) == null);
	assert (dom.dominators (b[3]).length == 0);
	assert (dom.dominance_frontier (b[1]).length == 0);
	ordinals (dom.children (b[0]), {1, 2});
}

// Analysis-only graph fixture. Models the existing zero/one/two-successor
// shapes using weak references so synthetic cyclic graphs can be released.
// It is never a production CFG operation or input to the SSA builder.
private class GraphEdges : CfgTerminator {
	private weak CfgBlock? first;
	private weak CfgBlock? second;

	public GraphEdges (SourceSpan span, CfgBlock? first, CfgBlock? second) {
		base (span);
		this.first = first;
		this.second = second;
	}

	public override GenericArray<CfgBlock> successors() {
		var result = new GenericArray<CfgBlock> ();
		if (first != null) {
			result.add (first);
		}
		if (second != null) {
			result.add (second);
		}
		return result;
	}

}

private bool[] paths(CfgFunction function, int omitted) {
	var reached = new bool[function.blocks.length];
	if (function.entry.ordinal == omitted) {
		return reached;
	}
	reached[function.entry.ordinal] = true;
	bool changed = true;
	while (changed) {
		changed = false;
		for (int i = 0; i < reached.length; i++) {
			if (!reached[i]) {
				continue;
			}
			var successors = function.blocks[i].terminator.successors ();
			for (int j = 0; j < successors.length; j++) {
				int target = successors[j].ordinal;
				if (target != omitted && !reached[target]) {
					changed = true;
					reached[target] = true;
				}
			}
		}
	}
	return reached;
}

private void finite_graphs() {
	var file = new SourceFile.from_text ("graphs.astra", "");
	var span = SourceSpan (file, 0, 0);
	var types = new BuiltinTypes ();
	// All three-node directed graphs (all subsets of successors fit the
	// current terminator model except three simultaneous successors).
	int[,] targets = {{
						  -1, -1
					  }, {
						  0, -1
					  }, {
						  1, -1
					  }, {
						  2, -1
					  }, {
						  0, 1
					  }, {
						  0, 2
					  }, {
						  1, 2
					  }, {
						  1, 1
					  }};
	for (int graph = 0; graph < 512; graph++) {
		var blocks = new GenericArray<CfgBlock> ();
		for (int i = 0; i < 3; i++) {
			blocks.add (new CfgBlock.reserve (span, i));
		}
		int code = graph;
		for (int i = 0; i < 3; i++) {
			int shape = code % 8;
			code /= 8;
			try {
				blocks[i].complete (span, new GraphEdges (span, targets[shape, 0] < 0 ? null : blocks[targets[shape, 0]], targets[shape, 1] < 0 ? null : blocks[targets[shape, 1]]));
			} catch (CfgError error) {
				GLib.error ("Graph construction failed: %s", error.message);
			}
		}
		var function = new CfgFunction (span, span, "graph", types.void_type, 0, new GenericArray<CfgParameter> (), new GenericArray<CfgLocalPlace> (), blocks, blocks[graph % 3]);
		var pred = CfgPredecessors.analyze (function);
		var dom = CfgDominance.analyze (function);
		var reachable = paths (function, -1);
		for (int d = 0; d < 3; d++) {
			var without = paths (function, d);
			for (int b = 0; b < 3; b++) {
				assert (dom.dominates (blocks[d], blocks[b]) == (reachable[d] && reachable[b] && !without[b]));
			}
			var incoming = pred.predecessors (blocks[d]);
			for (int i = 1; i < incoming.length; i++) {
				assert (incoming[i - 1].ordinal <= incoming[i].ordinal);
			}
			var parent = dom.immediate_dominator (blocks[d]);
			if (reachable[d] && blocks[d] != function.entry) {
				assert (parent != null && parent != blocks[d] && dom.dominates (parent, blocks[d]));
				for (int other = 0; other < 3; other++) {
					assert (other == d || !dom.dominates (blocks[other], blocks[d]) || dom.dominates (blocks[other], parent));
				}
			} else {
				assert (parent == null);
			}
			var frontier = dom.dominance_frontier (blocks[d]);
			int next = 0;
			for (int b = 0; b < 3; b++) {
				bool expected = false;
				var predecessors = pred.predecessors (blocks[b]);
				for (int p = 0; p < predecessors.length; p++) {
					expected = expected || (dom.dominates (blocks[d], predecessors[p]) && (d == b || !dom.dominates (blocks[d], blocks[b])));
				}
				if (expected) {
					assert (next < frontier.length && frontier[next++].ordinal == b);
				}
			}
			assert (next == frontier.length);
		}
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/dominance/single", single);
	Test.add_func ("/dominance/diamond", diamond);
	Test.add_func ("/dominance/no-else", no_else);
	Test.add_func ("/dominance/parallel-edges", parallel_edges);
	Test.add_func ("/dominance/nested", nested);
	Test.add_func ("/dominance/multiple-joins", multiple_joins);
	Test.add_func ("/dominance/unreachable-join", unreachable_join);
	Test.add_func ("/dominance/finite-graphs", finite_graphs);
	return Test.run ();
}

}
