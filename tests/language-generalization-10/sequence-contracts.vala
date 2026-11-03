// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.SequenceIteration {
private class StorageGraph : Object {
	internal HashTable<SemanticType, GenericArray<SemanticType>> fields = new HashTable<SemanticType, GenericArray<SemanticType>> (direct_hash, direct_equal);
	internal GenericArray<SemanticType>? lookup(SemanticType type) {
		return fields.lookup (type);
	}

}
private CheckedProgram sample(bool buffer = false) {
	string source = buffer ? "var values=new int[3];" : "int[3] values={2,4,6};";
	var parsed = Parser.parse (new SourceFile.from_text ("sequence.astra",
		"int main(){" + source + "int total=0;foreach(var value in values){total=total+value;}return total;}"));
	assert (parsed.diagnostic == null);
	var result = SemanticAnalyzer.analyze (parsed.unit);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}

private CoreWhile core_loop(CoreProgram program) {
	return (CoreWhile) ((CoreScope) program.functions[0].body.statements[2]).body.statements[1];
}

private void reject(CoreProgram program) {
	bool rejected = false;
	try {
		CoreVerifier.verify (program);
	} catch (CoreError error) {
		rejected = true;
		Test.message ("%s", error.message);
	}
	assert (rejected);
}

private void checked_authority() {
	try {
		var program = sample ();
		var loop = (CheckedWhile) ((CheckedBlockStatement) program.functions[0].body.statements[2]).statements[1];
		var authority = loop.sequence;
		loop.sequence = null;
		bool rejected = false;
		try {
			CoreBuilder.build (program);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		loop.sequence = authority;
		CoreVerifier.verify (CoreBuilder.build (program));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void core_authority() {
	try {
		var program = CoreBuilder.build (sample ());
		var loop = core_loop (program);
		var authority = loop.sequence;
		loop.sequence = null;
		reject (program);
		loop.sequence = authority;
		CoreVerifier.verify (program);

		var scope = ((CoreScope) program.functions[0].body.statements[2]).body;
		var initial = (CoreInitialize) scope.statements[0];
		scope.statements[0] = new CoreInitialize (initial.span, initial.target,
			new CoreIntegerValue (initial.span, initial.value.semantic_type, AstraIntValue.from_int64 (1)));
		reject (program);
		scope.statements[0] = initial;
		CoreVerifier.verify (program);

		var element = loop.body.statements[0];
		loop.body.statements.remove_index (0);
		reject (program);
		loop.body.statements.insert (0, element);
		CoreVerifier.verify (program);
		var copy = (CoreInitialize) element;
		loop.body.statements[0] = new CoreInitialize (copy.span, copy.target,
			new CoreIntegerValue (copy.span, copy.target.semantic_type, AstraIntValue.from_int64 (0)));
		reject (program);
		loop.body.statements[0] = element;
		CoreVerifier.verify (program);

		var step = loop.step.statements[0];
		loop.body.statements.add (step);
		reject (program);
		loop.body.statements.remove_index (loop.body.statements.length - 1);
		CoreVerifier.verify (program);
		loop.step.statements[0] = new CoreStore (step.span, authority.index,
			new CoreIntegerValue (step.span, authority.index.semantic_type, AstraIntValue.from_int64 (0)));
		reject (program);
		loop.step.statements[0] = step;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void buffer_liveness() {
	try {
		var program = CoreBuilder.build (sample (true));
		var loop = core_loop (program);
		var owner = program.functions[0].owned_locals[0];
		loop.body.statements.add (new CoreOwnershipRelease (loop.span, owner, owner.cleanup));
		reject (program);
		loop.body.statements.remove_index (loop.body.statements.length - 1);
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void cfg_initialization() {
	try {
		var program = CfgBuilder.build (CoreBuilder.build (sample ()));
		CfgVerifier.verify (program);
		foreach (var block in program.functions[0].blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				if (!(block.instructions[i] is CfgArrayInitialize)) {
					continue;
				}
				var initial = block.instructions[i];
				block.instructions.remove_index (i);
				bool rejected = false;
				try {
					CfgVerifier.verify (program);
				} catch (CfgError error) {
					rejected = true;
					Test.message ("%s", error.message);
				}
				assert (rejected);
				block.instructions.insert (i, initial);
				CfgVerifier.verify (program);
				return;
			}
		}
		assert_not_reached ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void ssa_bounds() {
	try {
		var program = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (sample ())));
		SsaVerifier.verify (program);
		foreach (var block in program.functions[0].blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				if (!(block.instructions[i] is SsaSliceBoundsCheck)) {
					continue;
				}
				var bounds = block.instructions[i];
				block.instructions.remove_index (i);
				bool rejected = false;
				try {
					SsaVerifier.verify (program);
				} catch (SsaError error) {
					rejected = true;
					Test.message ("%s", error.message);
				}
				assert (rejected);
				block.instructions.insert (i, bounds);
				SsaVerifier.verify (program);
				return;
			}
		}
		assert_not_reached ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void iterator_methods() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("iterator.astra",
			"class Sequence{int index;init(){this.index=0;}bool advance(){this.index=this.index+1;return this.index<4;}int current(){return this.index;}} int main(){var sequence=new Sequence();int total=0;foreach(var value in sequence){total=total+value;}return total;}"));
		assert (parsed.diagnostic == null);
		var checked = SemanticAnalyzer.analyze (parsed.unit);
		if (checked.diagnostic != null) {
			GLib.error ("%s", checked.diagnostic.format ());
		}
		var program = CoreBuilder.build (checked.program);
		var scope = ((CoreScope) program.functions[0].body.statements[2]).body;
		var loop = (CoreWhile) scope.statements[0];
		CoreVerifier.verify (program);
		scope.statements[0] = new CoreWhile (loop.span, loop.target,
			new CoreBooleanValue (loop.span, loop.condition.semantic_type, BooleanLiteral.TRUE), loop.body, null, null, loop.sequence);
		reject (program);
		scope.statements[0] = loop;
		CoreVerifier.verify (program);
		var observation = loop.body.statements[0];
		loop.body.statements.remove_index (0);
		reject (program);
		loop.body.statements.insert (0, observation);
		CoreVerifier.verify (program);
		var authority = loop.sequence;
		loop.sequence = new CoreSequenceIteration.iterator (authority.span, loop.target, authority.source,
			authority.binding, authority.current, authority.advance);
		reject (program);
		loop.sequence = authority;
		CoreVerifier.verify (program);
		var owner = program.functions[0].owned_locals[0];
		loop.body.statements.add (new CoreOwnershipRelease (loop.span, owner, owner.cleanup));
		reject (program);
		loop.body.statements.remove_index (loop.body.statements.length - 1);
		CoreVerifier.verify (program);
		SsaVerifier.verify (SsaBuilder.build (CfgBuilder.build (program)));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void aggregate_storage_paths() {
	try {
		var types = new BuiltinTypes ();
		var resource = new HandleType ("R");
		var identity = new ClassType ("Node");
		var leaf = new StructType ("Leaf");
		var middle = new StructType ("Middle");
		var root = new StructType ("Root");
		var graph = new StorageGraph ();
		var leaf_fields = new GenericArray<SemanticType> ();
		leaf_fields.add (resource);
		leaf_fields.add (identity);
		leaf_fields.add (types.slice_of (types.u8_type));
		graph.fields.insert (leaf, leaf_fields);
		var middle_fields = new GenericArray<SemanticType> ();
		middle_fields.add (types.int_type);
		middle_fields.add (leaf);
		graph.fields.insert (middle, middle_fields);
		var root_fields = new GenericArray<SemanticType> ();
		root_fields.add (middle);
		root_fields.add (middle);
		graph.fields.insert (root, root_fields);
		CopyabilityFields fields = graph.lookup;
		var paths = StructLeafOrder.enumerate_storage (root, fields);
		assert (paths.length == 8);
		assert (paths[1].spelling () == "0.1.0" && paths[5].spelling () == "1.1.0");
		assert (paths[1].semantic_type == resource && paths[2].semantic_type == identity);
		assert (paths[3].semantic_type == types.slice_of (types.u8_type));
		assert (CopyabilityAuthority.of (root, fields) == Copyability.NOT_COPYABLE);
		bool rejected = false;
		try {
			StructLeafOrder.enumerate (root, fields);
		} catch (StructLeafError error) {
			rejected = true;
		}
		assert (rejected);
		int[] original = {
			0, 1, 0
		};
		var frozen = new StructLeafPath (original, resource);
		original[0] = 9;
		assert (frozen.spelling () == "0.1.0");
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void malformed_storage_paths() {
	var types = new BuiltinTypes ();
	for (int variant = 0; variant < 4; variant++) {
		var root = new StructType ("Root");
		var children = new GenericArray<SemanticType> ();
		if (variant == 0) {
			children.add (root);
		}
		if (variant == 1) {
			children.add (new StructType ("Missing"));
		}
		if (variant == 2) {
			children.add (types.void_type);
		}
		var graph = new StorageGraph ();
		graph.fields.insert (root, children);
		bool rejected = false;
		try {
			StructLeafOrder.enumerate_storage (root, graph.lookup);
		} catch (StructLeafError error) {
			rejected = true;
			Test.message ("%s", error.message);
		}
		assert (rejected);
	}
}

private void container_snapshot() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("container-snapshot.astra",
			"class Values<T>{owned T[slots] entries;init(){this.entries=new T[slots];}} struct Point{int x;int y;} int main(){var values=new Values<Point>();int total=0;foreach(var value in values){total=total+value.x;}return total;}"));
		assert (parsed.diagnostic == null);
		var checked = SemanticAnalyzer.analyze (parsed.unit);
		if (checked.diagnostic != null) {
			GLib.error ("%s", checked.diagnostic.format ());
		}
		var checked_loop = (CheckedWhile) ((CheckedBlockStatement) checked.program.functions[0].body.statements[2]).statements[1];
		var checked_contract = checked_loop.iteration;
		assert (checked_contract.binding != null);
		checked_loop.iteration = new CheckedIterationContract (checked_contract.span, checked_contract.target, checked_contract.store, checked_contract.index);
		bool rejected = false;
		try {
			CoreBuilder.build (checked.program);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		checked_loop.iteration = checked_contract;
		var core = CoreBuilder.build (checked.program);
		CoreVerifier.verify (core);
		var loop = core_loop (core);
		var snapshot = loop.body.statements[0] as CoreStructResultStore;
		assert (loop.iteration.binding != null && snapshot != null && snapshot.producer is CoreSlotsRecordRead);
		loop.body.statements.remove_index (0);
		reject (core);
		loop.body.statements.insert (0, snapshot);
		CoreVerifier.verify (core);
		var read = (CoreSlotsRecordRead) snapshot.producer;
		loop.body.statements[0] = new CoreStructResultStore (snapshot.span, snapshot.destination,
			new CoreSlotsRecordRead (read.span, read.store, new CoreIntegerValue (read.span, read.index.semantic_type, AstraIntValue.from_int64 (0)), false), true);
		reject (core);
		loop.body.statements[0] = snapshot;
		CoreVerifier.verify (core);
		var contract = loop.iteration;
		loop.iteration = new CoreIterationContract (contract.span, contract.target, contract.store, contract.index);
		reject (core);
		loop.iteration = contract;
		CoreVerifier.verify (core);

		var cfg = CfgBuilder.build (core);
		CfgSlotsRecordRead? cfg_read = null;
		foreach (var function in cfg.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					if (instruction is CfgSlotsRecordRead) {
						cfg_read = (CfgSlotsRecordRead) instruction;
					}
				}
			}
		}
		assert (cfg_read != null && cfg_read.results.leaves.length == 2);
		var cfg_leaf = cfg_read.results.leaves[1];
		cfg_read.results.leaves.remove_index (1);
		rejected = false;
		try {
			CfgVerifier.verify (cfg);
		} catch (CfgError error) {
			rejected = true;
		}
		assert (rejected);
		cfg_read.results.leaves.add (cfg_leaf);
		CfgVerifier.verify (cfg);
		var ssa = SsaBuilder.build (cfg);
		int reads = 0;
		foreach (var function in ssa.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var ssa_read = block.instructions[i] as SsaSlotsRecordRead;
					if (ssa_read == null) {
						continue;
					}
					assert (block.instructions[i + 1] is SsaStructResultConsume);
					var consumption = block.instructions[i + 1];
					block.instructions.remove_index (i + 1);
					rejected = false;
					try {
						SsaVerifier.verify (ssa);
					} catch (SsaError error) {
						rejected = true;
					}
					assert (rejected);
					block.instructions.insert (i + 1, consumption);
					SsaVerifier.verify (ssa);
					reads++;
				}
			}
		}
		assert (reads == 1);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/sequence/container-complete-snapshot-authority-restored", container_snapshot);
	Test.add_func ("/sequence/checked-authority", checked_authority);
	Test.add_func ("/sequence/core-shape-and-copy", core_authority);
	Test.add_func ("/sequence/core-buffer-liveness", buffer_liveness);
	Test.add_func ("/sequence/cfg-initialization", cfg_initialization);
	Test.add_func ("/sequence/ssa-bounds", ssa_bounds);
	Test.add_func ("/sequence/iterator-method-authority", iterator_methods);
	Test.add_func ("/aggregate/storage-paths-preserve-owner-kinds", aggregate_storage_paths);
	Test.add_func ("/aggregate/storage-paths-reject-malformed-graphs", malformed_storage_paths);
	return Test.run ();
}

}
