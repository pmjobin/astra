// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Tests {
// Reuse accepted effect workloads with different source-call spellings.
internal string alias_source(string source) {
	string[] physical = {
		"astra_test_add", "astra_test_identity", "astra_test_reset", "astra_test_record", "astra_test_state", "c_call_astra_roundtrip", "c_call_astra_order"
	};
	string[] local = {
		"add", "echo", "reset", "record", "state", "roundtrip", "order"
	};
	string result = source;
	for (int i = 0; i < physical.length; i++) {
		result = result.replace (physical[i] + "(", local[i] + "(");
	}
	return result;
}

}
