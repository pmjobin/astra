// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
namespace Astra.Tests.GenericBufferSemantic {
private void qualify() {
	var types = new BuiltinTypes ();
	var t = new TypeParameterType ("T");
	var other = new TypeParameterType ("T");
	var proof = new GenericSliceObligations ();
	proof.require (t);
	foreach (var fact in new GenericElementRequirements[] {GenericElementRequirements.COPY, GenericElementRequirements.STORAGE, GenericElementRequirements.ZERO, GenericElementRequirements.DESTRUCTION}) {
		assert (proof.establishes (t, fact) && !proof.establishes (other, fact));
	}
	proof.require (t, GenericElementRequirements.COPY | GenericElementRequirements.STORAGE);
	assert (!proof.establishes (t, GenericElementRequirements.ZERO) && !proof.establishes (t, GenericElementRequirements.DESTRUCTION));
	assert (!GenericSliceObligations.accepts (t, null, (parameter) => proof.establishes (parameter, GenericElementRequirements.BUFFER)));
	proof.require (t);
	assert (GenericSliceObligations.accepts (t, null, (parameter) => proof.establishes (parameter, GenericElementRequirements.BUFFER)));
	var leaves = new GenericArray<SemanticType> ();
	foreach (string name in new string[] {"bool", "i8", "u8", "i16", "u16", "int", "u32", "f32", "f64", "void*"}) {
		leaves.add (types.resolve (name));
	}
	foreach (string name in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32", "bool"}) {
		foreach (int lanes in new int[] {2, 4, 8, 16}) {
			var vector = types.vector_of (types.resolve (name), lanes);
			if (vector != null) {
				leaves.add (vector);
			}
		}
	}
	assert (leaves.length == 34);
	foreach (var leaf in leaves) {
		assert (GenericSliceObligations.accepts (leaf) && BufferElementTypes.fixed_storage (leaf) && BufferElementTypes.defined_zero (leaf) && BufferElementTypes.trivial_destruction (leaf));
	}
	var graph = new HashTable<SemanticType, GenericArray<SemanticType>> (direct_hash, direct_equal);
	var record = new StructType ("Record");
	graph.insert (record, leaves);
	CopyabilityFields fields = (type) => graph.lookup (type);
	assert (GenericSliceObligations.accepts (record, fields));
	SemanticType deep = record;
	for (int i = 0; i < 64; i++) {
		var node = new StructType ("Node" + i.to_string ());
		var children = new GenericArray<SemanticType> ();
		children.add (deep);
		children.add (deep);
		graph.insert (node, children);
		deep = node;
	}
	assert (GenericSliceObligations.accepts (deep, fields));
	foreach (var bad in new SemanticType[] {types.string_type, types.slice_of (types.int_type), types.array_of (types.int_type, 2), types.pointer_to (types.int_type), new HandleType ("R"), new ClassType ("C")}) {
		assert (!GenericSliceObligations.accepts (bad, fields));
		leaves.add (bad);
		assert (!GenericSliceObligations.accepts (deep, fields));
		leaves.remove_index (34);
	}
	assert (!GenericArgumentTypes.supports (types.slice_of (types.int_type)) && !GenericCapabilityAuthority.satisfies (types.slice_of (types.int_type), GenericCapabilityIdentity.OWNABLE));
	assert (GenericCapabilityAuthority.satisfies (new HandleType ("R"), GenericCapabilityIdentity.OWNABLE) && GenericCapabilityAuthority.satisfies (new ClassType ("C"), GenericCapabilityIdentity.OWNABLE));
}
private void flow_models() {
	var span = Astra.Source.SourceSpan (new Astra.Source.SourceFile.from_text ("independent-owner-facts", "x"), 0, 1);
	var owner = new Object ();
	var loop = new Object ();
	for (int variant = 0; variant < 8; variant++) {
		var flow = new GenericOwnershipFlow (span);
		if (variant == 0 || variant == 1) {
			flow.owner_event (variant == 0 ? GenericOwnershipEventKind.MOVE : GenericOwnershipEventKind.RELEASE, owner, "values", span);
			flow.owner_event (GenericOwnershipEventKind.READ, owner, "values", span);
		}
		if (variant == 2 || variant == 3) {
			flow.begin (GenericOwnershipEventKind.CHOICE, span);
			flow.owner_event (variant == 2 ? GenericOwnershipEventKind.MOVE : GenericOwnershipEventKind.RELEASE, owner, "values", span);
			flow.arm (1);
			flow.end ();
			flow.owner_event (GenericOwnershipEventKind.READ, owner, "values", span);
		}
		if (variant == 4 || variant == 5) {
			flow.begin (GenericOwnershipEventKind.LOOP, span, -1, loop);
			flow.arm (1);
			flow.move (owner, "values", span);
			if (variant == 5) {
				flow.jump (GenericOwnershipEventKind.CONTINUE, span, loop);
			}
			flow.end ();
		}
		if (variant == 6) {
			flow.begin (GenericOwnershipEventKind.LOOP, span, -1, loop);
			flow.arm (1);
			flow.move (owner, "values", span);
			flow.jump (GenericOwnershipEventKind.BREAK, span, loop);
			flow.end ();
			flow.owner_event (GenericOwnershipEventKind.READ, owner, "values", span);
		}
		assert (!flow.verify (variant == 7) && flow.diagnostic != null);
	}
	var valid = new GenericOwnershipFlow (span);
	valid.owner_event (GenericOwnershipEventKind.RELEASE, owner, "values", span);
	valid.owner_event (GenericOwnershipEventKind.ACQUIRE, owner, "values", span);
	valid.move (owner, "values", span);
	valid.owner_event (GenericOwnershipEventKind.ACQUIRE, owner, "values", span);
	valid.owner_event (GenericOwnershipEventKind.READ, owner, "values", span);
	valid.jump (GenericOwnershipEventKind.RETURN, span);
	assert (valid.verify (true));
	var fault = new ClassType ("Fault");
	var bounds = new GenericArray<ClassType> ();
	bounds.add (fault);
	for (int variant = 0; variant < 4; variant++) {
		var flow = new GenericOwnershipFlow (span);
		flow.begin_try (span, bounds);
		if (variant == 0 || variant == 3) {
			flow.move (owner, "values", span);
		}
		flow.effect (fault, span, variant == 2);
		if (variant == 1 || variant == 2) {
			flow.move (owner, "values", span);
		}
		flow.arm (1);
		if (variant == 3) {
			flow.owner_event (GenericOwnershipEventKind.ACQUIRE, owner, "values", span);
		}
		flow.owner_event (GenericOwnershipEventKind.READ, owner, "values", span);
		flow.end ();
		if (variant == 2) {
			flow.owner_event (GenericOwnershipEventKind.READ, owner, "values", span);
		}
		assert (flow.verify () == (variant != 0));
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-buffer/semantic/separate-scoped-facts-and-unchanged-complete-domain", qualify);
	Test.add_func ("/gen-buffer/semantic/independent-owner-possibility-models", flow_models);
	return Test.run ();
}
}
