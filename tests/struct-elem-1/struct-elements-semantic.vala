// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;

namespace Astra.Tests.StructElementsSemantic {
private void qualify() {
	var t = new BuiltinTypes ();
	var leaves = new GenericArray<SemanticType> ();
	foreach (string name in new string[] {"bool", "i8", "u8", "i16", "u16", "int", "u32", "f32", "f64", "void*"}) {
		leaves.add (t.resolve (name));
	}
	string[] bases = {
		"i8", "u8", "i16", "u16", "int", "u32", "f32", "bool"
	};
	int[] counts = {
		4, 4, 3, 3, 2, 2, 2, 4
	};
	for (int b = 0; b < bases.length; b++) {
		for (int n = 0; n < counts[b]; n++) {
			leaves.add (t.vector_of (t.resolve (bases[b]), 2 << n));
		}
	}
	assert (leaves.length == 34);
	var leaf = new StructType ("Leaf");
	var records = new GenericArray<SemanticType> ();
	var edges = new HashTable<SemanticType, GenericArray<SemanticType>> (direct_hash, direct_equal);
	edges.insert (leaf, leaves);
	records.add (leaf);
	for (int i = 0; i < 64; i++) {
		var node = new StructType ("N%d".printf (i));
		var children = new GenericArray<SemanticType> ();
		children.add (records[i]);
		children.add (records[i]);
		edges.insert (node, children);
		records.add (node);
	}
	int visits = 0;
	CopyabilityFields graph = (type) => {
		visits++;
		return edges.lookup (type);
	};
	assert (BufferElementTypes.supports (records[64], graph));
	assert (visits == 4 * 65);
	assert (BufferElementTypes.fixed_storage (leaf, graph) && BufferElementTypes.defined_zero (leaf, graph) && BufferElementTypes.trivial_destruction (leaf, graph));
	assert (t.array_of (leaf, 4) == t.array_of (leaf, 4) && t.slice_of (leaf) == t.slice_of (leaf));
	assert (t.slice_of (leaf) != t.slice_of (new StructType ("Leaf")));
	leaves.add (t.vector_of (t.f64_type, 2));
	assert (BufferElementTypes.supports (records[1], graph));
	leaves.remove_index (34);
	var invalid = new GenericArray<SemanticType> ();
	foreach (var bad in new SemanticType[] {t.void_type, t.string_type, t.pointer_to (t.int_type), new HandleType ("R"), new ClassType ("C"), t.slice_of (t.int_type), t.array_of (t.int_type, 1), new TypeParameterType ("T"), new VectorType (t.f64_type, 4), new StructType ("Incomplete")}) {
		invalid.add (bad);
	}
	foreach (var bad in invalid) {
		leaves.add (bad);
		assert (!BufferElementTypes.supports (records[1], graph));
		assert (BufferElementTypes.invalid_field (records[1], graph) == "0.34");
		leaves.remove_index (34);
		assert (BufferElementTypes.supports (records[1], graph));
	}
	leaves.add (records[64]);
	assert (!BufferElementTypes.supports (leaf, graph));
	leaves.remove_index (34);
	assert (BufferElementTypes.supports (leaf, graph));
	var empty = new StructType ("Empty");
	edges.insert (empty, new GenericArray<SemanticType> ());
	assert (CopyabilityAuthority.of (empty, graph) == Copyability.COPYABLE && !BufferElementTypes.defined_zero (empty, graph));
}

public int run_semantic(string[] args) {
	Test.init (ref args);
	Test.add_func ("/struct-elements/semantic/independent-domain-shared-depth64-distinct-zero-and-recovery", qualify);
	return Test.run ();
}

}
