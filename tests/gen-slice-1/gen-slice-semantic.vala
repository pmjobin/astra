// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
namespace Astra.Tests.GenericSliceSemantic {
private class Application : SemanticType {
	public Application () {
		base (TypeKind.GENERIC_STRUCT_APPLICATION);
	}

	public override bool is_parameterized() {
		return true;
	}

}
private void proof() {
	var types = new BuiltinTypes ();
	var fields = new GenericArray<SemanticType> ();
	foreach (string name in new string[] {"bool", "i8", "u8", "i16", "u16", "int", "u32", "f32", "f64", "void*"}) {
		fields.add (types.resolve (name));
	}
	foreach (string name in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32", "bool"}) {
		foreach (int lanes in new int[] {2, 4, 8, 16}) {
			var vector = types.vector_of (types.resolve (name), lanes);
			if (vector != null) {
				fields.add (vector);
			}
		}
	}
	assert (fields.length == 34);
	assert (GenericArgumentTypes.supports (types.vector_of (types.f64_type, 2)));
	assert (GenericSliceObligations.accepts (types.vector_of (types.f64_type, 2)));
	foreach (var type in fields) {
		assert (GenericSliceObligations.accepts (type));
	}
	var record = new StructType ("Record");
	var graph = new HashTable<SemanticType, GenericArray<SemanticType>> (direct_hash, direct_equal);
	graph.insert (record, fields);
	CopyabilityFields resolve = (type) => graph.lookup (type);
	foreach (var type in fields) {
		assert (GenericArgumentTypes.supports (type));
	}
	assert (GenericArgumentTypes.supports (record, resolve) && !GenericArgumentTypes.supports (record));
	assert (GenericSliceObligations.accepts (record, resolve) && !GenericSliceObligations.accepts (record));
	var t = new TypeParameterType ("T");
	var foreign = new TypeParameterType ("T");
	var application = new Application ();
	var symbolic = new GenericArray<SemanticType> ();
	symbolic.add (t);
	symbolic.add (record);
	graph.insert (application, symbolic);
	CopyabilityPremise scoped = (parameter) => parameter == t;
	var obligations = new GenericSliceObligations ();
	obligations.require (t);
	CopyabilityPremise element = (parameter) => parameter == t && obligations.contains (parameter);
	assert (GenericSliceObligations.accepts (t, resolve, element) && !GenericSliceObligations.accepts (foreign, resolve, element));
	assert (!GenericSliceObligations.accepts (t, resolve) && !GenericSliceObligations.accepts (types.slice_of (types.int_type)));
	assert (GenericArgumentTypes.plain_copy (t, resolve, scoped));
	assert (!GenericArgumentTypes.plain_copy (foreign, resolve, scoped) && !GenericArgumentTypes.plain_copy (t, resolve));
	assert (GenericArgumentTypes.plain_copy (application, resolve, scoped) && !GenericArgumentTypes.supports (application, resolve));
	assert (CopyabilityAuthority.of (application, resolve) == Copyability.NOT_COPYABLE && !BufferElementTypes.supports (application, resolve));
	var capabilities = new GenericCapabilitySet ({GenericCapabilityIdentity.OWNABLE});
	var owned = new TypeParameterType ("T", capabilities);
	assert (!GenericArgumentTypes.plain_copy (owned, resolve, (parameter) => true));
	foreach (var bad in new SemanticType[] {types.void_type, types.string_type, types.pointer_to (types.int_type), types.slice_of (types.int_type), types.array_of (types.int_type, 2), new HandleType ("R"), new ClassType ("C"), new StructType ("Missing"), new VectorType (types.f64_type, 4), foreign, owned}) {
		assert (!GenericSliceObligations.accepts (bad, resolve, element));
		fields.add (bad);
		assert (!GenericArgumentTypes.plain_copy (application, resolve, scoped));
		fields.remove_index (34);
		assert (GenericArgumentTypes.plain_copy (application, resolve, scoped));
	}
	var empty = new StructType ("Empty");
	graph.insert (empty, new GenericArray<SemanticType> ());
	assert (!GenericArgumentTypes.supports (empty, resolve));
	var nodes = new GenericArray<SemanticType> ();
	nodes.add (record);
	for (int i = 0; i < 64; i++) {
		var node = new StructType ("Depth%d".printf (i));
		var children = new GenericArray<SemanticType> ();
		children.add (nodes[i]);
		children.add (nodes[i]);
		graph.insert (node, children);
		nodes.add (node);
	}
	assert (GenericArgumentTypes.supports (nodes[64], resolve));
	fields.add (nodes[64]);
	assert (!GenericArgumentTypes.supports (record, resolve));
	fields.remove_index (34);
	assert (GenericArgumentTypes.supports (nodes[64], resolve));
	SemanticType deep = record;
	for (int i = 0; i < 300; i++) {
		var node = new StructType ("ConcreteDepth%d".printf (i));
		var children = new GenericArray<SemanticType> ();
		children.add (deep);
		graph.insert (node, children);
		deep = node;
	}
	assert (GenericArgumentTypes.supports (deep, resolve));
	SemanticType expanded = t;
	for (int i = 0; i < 256; i++) {
		var node = new Application ();
		var children = new GenericArray<SemanticType> ();
		children.add (expanded);
		graph.insert (node, children);
		expanded = node;
	}
	assert (GenericArgumentTypes.plain_copy (expanded, resolve, scoped));
	var excessive = new Application ();
	var children = new GenericArray<SemanticType> ();
	children.add (expanded);
	graph.insert (excessive, children);
	assert (!GenericArgumentTypes.plain_copy (excessive, resolve, scoped));
	assert (GenericArgumentTypes.plain_copy (expanded, resolve, scoped));
	foreach (var capability in new GenericCapabilityIdentity[] {GenericCapabilityIdentity.EQ, GenericCapabilityIdentity.ORDERED, GenericCapabilityIdentity.NUMERIC, GenericCapabilityIdentity.BITWISE, GenericCapabilityIdentity.SHIFT, GenericCapabilityIdentity.OWNABLE}) {
		assert (!GenericCapabilityAuthority.satisfies (record, capability));
	}
}

public int run_semantic(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-slice/semantic/shared-exact-concrete-symbolic-proof-and-exclusions", proof);
	return Test.run ();
}

}
