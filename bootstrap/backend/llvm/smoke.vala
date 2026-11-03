// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Backend.LLVM {
// Internal fixture only. Omitting the terminator exercises verifier failure.
internal bool verify_smoke_module(bool add_return, out string? diagnostic) {
	var context = CApi.context_create ();
	var module = CApi.module_create_with_name_in_context ("astra-smoke", context);
	var builder = CApi.create_builder_in_context (context);
	char* message = null;
	diagnostic = null;

	var i32 = CApi.int32_type_in_context (context);
	var signature = CApi.function_type (i32, null, 0, 0);
	var function = CApi.add_function (module, "astra_smoke", signature);
	var block = CApi.append_basic_block_in_context (context, function, "entry");
	CApi.position_builder_at_end (builder, block);
	if (add_return) {
		CApi.build_ret (builder, CApi.const_int (i32, 0, 0));
	}

	int failed = CApi.verify_module (module, CApi.VerifierFailureAction.RETURN_STATUS, out message);
	if (message != null) {
		// Copy before freeing the message with LLVM's allocator.
		diagnostic = (string) message;
		CApi.dispose_message (message);
	}
	// One exit path releases borrowed storage's owners in dependency order.
	CApi.dispose_builder (builder);
	CApi.dispose_module (module);
	CApi.context_dispose (context);
	return failed == 0;
}

}
