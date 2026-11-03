// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
namespace Astra.Semantic {
// Each verifier supplies its own declaration/field inventory. This helper
// retains no compiler nodes and makes no lifetime or Send claim from a type.
public delegate bool RuntimeScopeTypeExpansion(SemanticType type, GenericArray<SemanticType> following);
public class RuntimeScopeTypes : Object {
	public static bool contains(SemanticType type, RuntimeScopeTypeExpansion expand) {
		var pending = new GenericArray<SemanticType> ();
		var seen = new HashTable<SemanticType, bool> (direct_hash, direct_equal);
		pending.add (type);
		for (int at = 0; at < pending.length; at++) {
			var current = pending[at];
			if (seen.contains (current)) {
				continue;
			}
			seen.insert (current, true);
			if (current is ReceiverType) {
				pending.add (((ReceiverType) current).instance_type);
				continue;
			}
			if (current is ContextBytesType && ((ContextBytesType) current).allocator_type.context_mode == "scoped-affine") {
				return true;
			}
			if (current is SliceType) {
				pending.add (((SliceType) current).element_type);
			}
			if (current is ArrayType) {
				pending.add (((ArrayType) current).element_type);
			}
			if (current is OwnerSlotsType) {
				pending.add (((OwnerSlotsType) current).element);
			}
			if (current is SharedHandleType) {
				pending.add (((SharedHandleType) current).payload_type);
			}
			if (current is ClosureHandleType) {
				pending.add (((ClosureHandleType) current).environment_type);
			}
			if (current is TaskType) {
				var task = (TaskType) current;
				if (task.success_mode == ResultOwnershipContract.OWNED_TRANSFER || task.success_type.is_struct_storage ()) {
					pending.add (task.success_type);
				}
				if (task.exception_bound != null) {
					pending.add (task.exception_bound);
				}
			}
			if (expand (current, pending)) {
				return true;
			}
		}
		return false;
	}

}
}
