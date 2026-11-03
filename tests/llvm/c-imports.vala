// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.Llvm {
private void c_domains() throws GLib.Error {
	var ssa = build_ssa ("int native(int x) { if (x == 0) { return c_one(x); } return native(x - 1) + c_two(x); } extern(C) int c_one(int x); extern(C) int c_two(int x); extern(C) void c_void(); void discard() { c_one(1); c_void(); }");
	var nabi = NativeAbiBuilder.build (ssa);
	var cabi = CAbiBuilder.build (ssa, nabi);
	// Make debug names and ordinals coincide across domains. Only exact
	// source/physical identities and the foreign symbol carry authority.
	var physical = new GenericArray<CAbiFunction> ();
	foreach (var imported in cabi.functions) {
		physical.add (new CAbiFunction (imported.span, imported.name_span, "native", imported.ordinal, imported.signature, imported.metadata));
	}
	cabi = new CAbiProgram (cabi.span, cabi.profile, physical);
	var artifact = LlvmLowering.lower (ssa, nabi, cabi);
	var fs = functions (artifact);
	assert (fs.length == 5 && artifact.c_imports.length == 3);
	for (int f = 0; f < fs.length; f++) {
		size_t length;
		string name = CApi.value_name (fs[f], out length);
		if (f < 2) {
			assert (name == "astra.fn.%d".printf (f));
			assert (CApi.get_linkage (fs[f]) == CApi.Linkage.INTERNAL && CApi.function_call_conv (fs[f]) == CApi.CallConv.FAST);
			assert ((void*) CApi.first_block (fs[f]) != null);
		} else {
			assert (name == cabi.functions[f - 2].external_symbol);
			assert (CApi.get_linkage (fs[f]) == CApi.Linkage.EXTERNAL && CApi.function_call_conv (fs[f]) == CApi.CallConv.C);
			assert ((void*) CApi.first_block (fs[f]) == null);
		}
	}
	int native_calls = 0;
	int c_calls = 0;
	foreach (var f in fs) {
		foreach (var call in operations (f, CApi.Opcode.CALL)) {
			var target = CApi.called_value (call);
			if ((void*) target == (void*) fs[0]) {
				native_calls++;
				assert (CApi.instruction_call_conv (call) == CApi.CallConv.FAST);
			} else {
				c_calls++;
				assert ((void*) target == (void*) fs[2] || (void*) target == (void*) fs[3] || (void*) target == (void*) fs[4]);
				assert (CApi.instruction_call_conv (call) == CApi.CallConv.C);
			}
		}
	}
	assert (native_calls == 1 && c_calls == 4);
	assert (operations (fs[1], CApi.Opcode.CALL).length == 2);
	artifact.verify ();
}

private void c_trap_order() throws GLib.Error {
	var artifact = lower (fixture ("tests/cabi/fixtures/c-trap-order.astra"));
	var fs = functions (artifact);
	var earlier_c = operations (fs[0], CApi.Opcode.CALL)[0];
	assert ((void*) CApi.instruction_parent (earlier_c) == (void*) CApi.entry_block (fs[0]));
	var later_c = operations (fs[1], CApi.Opcode.CALL);
	// The first foreign call in before() must be beyond the division guard.
	foreach (var call in later_c) {
		if (CApi.intrinsic_id (CApi.called_value (call)) == 0) {
			assert ((void*) CApi.instruction_parent (call) != (void*) CApi.entry_block (fs[1]));
		}
	}
	string ir = artifact.dump ();
	assert (ir.index_of ("call i32 @astra_test_record(i32 1)") < ir.index_of ("call void @llvm.trap()"));
}

private void c_shortcircuit_paths() throws GLib.Error {
	var artifact = lower ("extern(C) int probe(); bool both(bool left) { return left && (probe() != 0); } bool either(bool left) { return left || (probe() != 0); }");
	var fs = functions (artifact);
	for (int f = 0; f < 2; f++) {
		var foreign_calls = operations (fs[f], CApi.Opcode.CALL);
		assert (foreign_calls.length == 1);
		var call_block = CApi.instruction_parent (foreign_calls[0]);
		bool found = false;
		foreach (var branch in operations (fs[f], CApi.Opcode.BR)) {
			if (CApi.successor_count (branch) == 2 && (void*) CApi.condition (branch) == (void*) CApi.get_param (fs[f], 0)) {
				assert ((void*) CApi.successor (branch, f == 0 ? 0 : 1) == (void*) call_block);
				assert ((void*) CApi.successor (branch, f == 0 ? 1 : 0) != (void*) call_block);
				found = true;
			}
		}
		assert (found);
	}
}

private void c_backend_rejections() throws GLib.Error {
	string source = "extern(C) int c_one(int x); int main() { return c_one(1); }";
	for (int mode = 0; mode < 6; mode++) {
		var artifact = lower (source);
		var imported = artifact.c_imports[0];
		var call = (CApi.ValueRef) imported.calls[0];
		if (mode == 0) {
			CApi.set_function_call_conv (imported.value, CApi.CallConv.FAST);
		}
		if (mode == 1) {
			CApi.set_instruction_call_conv (call, CApi.CallConv.FAST);
		}
		if (mode == 2) {
			CApi.set_linkage (imported.value, CApi.Linkage.INTERNAL);
		}
		if (mode == 3) {
			var block = CApi.append_basic_block_in_context (artifact.context, imported.value, "invalid.body");
			var builder = CApi.create_builder_in_context (artifact.context);
			CApi.position_builder_at_end (builder, block);
			CApi.build_ret (builder, CApi.get_param (imported.value, 0));
			CApi.dispose_builder (builder);
		}
		if (mode == 4) {
			CApi.set_value_name (imported.value, "wrong_symbol", 12);
		}
		if (mode == 5) {
			var wrong_type = CApi.function_type (CApi.int1_type_in_context (artifact.context), null, 0, 0);
			var builder = CApi.create_builder_in_context (artifact.context);
			var block = CApi.append_basic_block_in_context (artifact.context, functions (artifact)[0], "invalid.call");
			CApi.position_builder_at_end (builder, block);
			var wrong_call = CApi.build_call (builder, wrong_type, imported.value, null, 0, "wrong");
			CApi.build_unreachable (builder);
			CApi.dispose_builder (builder);
			imported.calls.add ((void*) wrong_call);
		}
		try {
			artifact.verify ();
			assert_not_reached ();
		} catch (LlvmError.VERIFICATION error) {
			assert (error.message.contains ("C import verification error"));
		}
	}
	var ssa = build_ssa (source);
	var other = build_ssa ("extern(C) int c_other(int x);");
	try {
		LlvmLowering.lower (ssa, NativeAbiBuilder.build (ssa), CAbiBuilder.build (other, Astra.NativeAbi.NativeAbiBuilder.build (other)));
		assert_not_reached ();
	} catch (LlvmError.INVALID_INPUT error) {
		assert (error.message.contains ("exact identity"));
	}
}

private void register_c_imports() {
	add ("/llvm/cabi/domains", c_domains);
	add ("/llvm/cabi/trap-order", c_trap_order);
	add ("/llvm/cabi/shortcircuit-paths", c_shortcircuit_paths);
	add ("/llvm/cabi/malformed", c_backend_rejections);
}

}
