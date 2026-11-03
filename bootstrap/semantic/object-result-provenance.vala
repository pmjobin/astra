// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
// Exact storage domains, independent of ownership state and pointer nullability.
public enum ObjectResultProvenance {
	NONE,
	RESULT_STORAGE,
	OWNED_PARAMETER_STORAGE,
	FORWARDED_OWNED_RESULT,
	CALLEE_LOCAL_STORAGE,
	BORROWED_STORAGE,
	HEAP_OBJECT,
	NULL;

	public bool is_returnable() {
		return this == RESULT_STORAGE || this == OWNED_PARAMETER_STORAGE || this == FORWARDED_OWNED_RESULT || this == HEAP_OBJECT || this == NULL;
	}

	public string label() {
		switch (this) {
		case RESULT_STORAGE:
			return "result-storage";
		case OWNED_PARAMETER_STORAGE:
			return "owned-parameter-storage";
		case FORWARDED_OWNED_RESULT:
			return "forwarded-owned-result";
		case CALLEE_LOCAL_STORAGE:
			return "callee-local-storage";
		case BORROWED_STORAGE:
			return "borrowed-storage";
		case HEAP_OBJECT:
			return "heap-object";
		case NULL:
			return "null";
		default:
			return "none";
		}
	}

}

}
