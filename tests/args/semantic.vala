// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Text;

namespace Astra.Tests.ArgsSemantic {
private void contracts() {
	var t = new BuiltinTypes ();
	var slice = t.slice_of (t.string_type);
	assert (slice != null && slice == t.slice_of (t.string_type) && slice.element_type == t.string_type && slice.deep_borrow && slice.element_access == SliceElementAccess.READ);
	assert (t.slice_of (t.int_type).element_access == SliceElementAccess.READ_WRITE);
	assert (!BufferElementTypes.supports (t.string_type) && !GenericArgumentTypes.supports (slice) && !ArrayType.supports (t.string_type, 1));
	var flow = new TextOriginFlow ();
	var parameter = new Object ();
	var binding = new Object ();
	var saved = new Object ();
	var replacement = new Object ();
	var element = new Object ();
	flow.origins.borrowed (parameter);
	flow.write (binding, parameter);
	flow.read (binding, saved);
	flow.origins.literal (replacement);
	flow.write (binding, replacement);
	flow.origins.copy (element, saved);
	assert (flow.origins.is_bounded (saved) && flow.origins.is_bounded (element) && !flow.origins.is_static (element));
	var current = new Object ();
	flow.read (binding, current);
	assert (flow.origins.is_static (current));
	var ungrounded = new Object ();
	flow.origins.copy (ungrounded, ungrounded);
	assert (!flow.origins.is_bounded (ungrounded));
	var mixed = new Object ();
	flow.origins.copy (mixed, current);
	flow.origins.copy (mixed, element);
	assert (!flow.origins.is_static (mixed) && flow.origins.is_bounded (mixed));
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/args/semantic/identity-access-deep-snapshots", contracts);
	return Test.run ();
}

}
