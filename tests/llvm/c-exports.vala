// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.Llvm {
private void export_domains() throws GLib.Error {
	string source = "int native_user(int x) { return add(x, 2); } export(C) int add(int a, int b) { return a + b; } extern(C) int c_one(int x); export(C) void record(int x) { c_one(x); return; } export(C) int recurse(int x) { if (x == 0) { return 0; } return recurse(x - 1) + x; }";
	var ssa = build_ssa (source);
	var original = NativeAbiBuilder.build (ssa);
	var renamed = new GenericArray<NativeFunction> ();
	foreach (var native in original.functions) {
		var replacement = new NativeFunction (native.span, native.name_span, "same-debug-name", native.ordinal, native.signature, native.linkage);
		replacement.bind_effects (native.effect_facts);
		replacement.bind_runtime_lifetimes (native.runtime_lifetimes);
		replacement.bind_scoped_readonly (native.scoped_readonly, native.readonly_inputs, native.callback_inputs, native.callback_input_count, native.callback_contract_supported);
		renamed.add (replacement);
	}
	var nabi = new NativeAbiProgram (original.span, original.abi_version, renamed);
	var cabi = CAbiBuilder.build (ssa, nabi);
	var artifact = LlvmLowering.lower (ssa, nabi, cabi);
	var fs = functions (artifact);
	assert (fs.length == 8 && artifact.c_exports.length == 3 && artifact.c_imports.length == 1);
	for (int f = 0; f < 4; f++) {
		assert (CApi.get_linkage (fs[f]) == CApi.Linkage.INTERNAL && CApi.function_call_conv (fs[f]) == CApi.CallConv.FAST);
		foreach (var call in operations (fs[f], CApi.Opcode.CALL)) {
			foreach (var wrapper in artifact.c_exports) {
				assert ((void*) CApi.called_value (call) != (void*) wrapper.value);
			}
		}
	}
	for (int e = 0; e < 3; e++) {
		var wrapper = artifact.c_exports[e];
		assert ((void*) CApi.named_function (artifact.module, cabi.exports[e].external_symbol) == (void*) wrapper.value);
		assert (CApi.get_linkage (wrapper.value) == CApi.Linkage.EXTERNAL && CApi.function_call_conv (wrapper.value) == CApi.CallConv.C);
		assert ((void*) wrapper.native_target == (void*) fs[cabi.exports[e].native_function_ordinal]);
		assert ((void*) CApi.called_value (wrapper.call) == (void*) wrapper.native_target && CApi.instruction_call_conv (wrapper.call) == CApi.CallConv.FAST);
		var body = instructions (wrapper.value);
		assert (body.length == 2 && CApi.opcode (body[0]) == CApi.Opcode.CALL && CApi.opcode (body[1]) == CApi.Opcode.RET);
		assert (CApi.count_params (wrapper.value) == cabi.exports[e].signature.parameters.length);
		for (uint p = 0; p < CApi.count_params (wrapper.value); p++) {
			assert (CApi.int_width (CApi.type_of (CApi.get_param (wrapper.value, p))) == 32);
			assert ((void*) CApi.operand (wrapper.call, p) == (void*) CApi.get_param (wrapper.value, p));
		}
		if (e == 1) {
			assert (CApi.operand_count (body[1]) == 0);
		} else {
			assert ((void*) CApi.operand (body[1], 0) == (void*) wrapper.call);
		}
	}
	assert ((void*) CApi.called_value (operations (fs[0], CApi.Opcode.CALL)[0]) == (void*) fs[1]);
	assert ((void*) CApi.called_value (operations (fs[3], CApi.Opcode.CALL)[0]) == (void*) fs[3]);
	assert (CApi.instruction_call_conv (operations (fs[3], CApi.Opcode.CALL)[0]) == CApi.CallConv.FAST);
	artifact.verify ();
}

private void exported_mutual_calls() throws GLib.Error {
	var artifact = lower ("export(C) int a(int x) { if (x == 0) { return 0; } return b(x - 1); } export(C) int b(int x) { if (x == 0) { return 1; } return a(x - 1); } export(C) int zero() { return 0; } export(C) void empty() {}");
	var fs = functions (artifact);
	for (int f = 0; f < 2; f++) {
		var calls = operations (fs[f], CApi.Opcode.CALL);
		assert (calls.length == 1 && (void*) CApi.called_value (calls[0]) == (void*) fs[1 - f]);
		assert (CApi.instruction_call_conv (calls[0]) == CApi.CallConv.FAST);
	}
	assert (CApi.count_params (artifact.c_exports[2].value) == 0 && CApi.count_params (artifact.c_exports[3].value) == 0);
	assert (CApi.operand_count (instructions (artifact.c_exports[2].value)[1]) == 1 && CApi.operand_count (instructions (artifact.c_exports[3].value)[1]) == 0);
}

private void export_backend_rejections() throws GLib.Error {
	for (int mode = 0; mode < 9; mode++) {
		var artifact = lower ("export(C) int add(int a, int b) { return a + b; } int other(int a, int b) { return a - b; }");
		var binding = artifact.c_exports[0];
		if (mode == 0) {
			CApi.set_function_call_conv (binding.value, CApi.CallConv.FAST);
		}
		if (mode == 1) {
			CApi.set_linkage (binding.value, CApi.Linkage.INTERNAL);
		}
		if (mode == 2) {
			CApi.set_function_call_conv (binding.native_target, CApi.CallConv.C);
		}
		if (mode == 3) {
			CApi.set_linkage (binding.native_target, CApi.Linkage.EXTERNAL);
		}
		if (mode == 4) {
			CApi.set_instruction_call_conv (binding.call, CApi.CallConv.C);
		}
		if (mode == 5) {
			CApi.set_value_name (binding.value, "wrong", 5);
		}
		if (mode == 6) {
			CApi.set_operand (binding.call, 0, CApi.get_param (binding.value, 1));
		}
		if (mode == 7) {
			CApi.set_operand (instructions (binding.value)[1], 0, CApi.get_param (binding.value, 0));
		}
		if (mode == 8) {
			CApi.set_operand (binding.call, 2, functions (artifact)[1]);
		}
		try {
			artifact.verify ();
			assert_not_reached ();
		} catch (LlvmError.VERIFICATION error) {
			assert (error.message.contains ("C export verification error"));
		}
	}
	for (int mode = 0; mode < 4; mode++) {
		var ssa = build_ssa ("export(C) int f(int x) { return x; } int g(int x) { return x; }");
		var nabi = NativeAbiBuilder.build (ssa);
		var cabi = CAbiBuilder.build (ssa, nabi);
		var original = cabi.exports[0];
		var exports = new GenericArray<CAbiExport> ();
		exports.add (new CAbiExport (original.span, original.name_span, mode == 1 ? "wrong" : "f", 0, original.signature, mode == 0 ? 1 : 0));
		if (mode == 2) {
			exports.remove_index (0);
		}
		if (mode == 3) {
			exports.add (new CAbiExport (original.span, original.name_span, "f", 1, original.signature, 1));
		}
		cabi = new CAbiProgram (cabi.span, cabi.profile, new GenericArray<CAbiFunction> (), exports);
		if (mode == 3) {
			string expected = new Astra.Source.Diagnostic (original.name_span, "C external symbol 'f' is declared more than once").format ();
			try {
				CAbiVerifier.verify (cabi);
				assert_not_reached ();
			} catch (CAbiError.DUPLICATE_SYMBOL error) {
				assert (error.message == expected);
			}
			try {
				LlvmLowering.lower (ssa, nabi, cabi);
				assert_not_reached ();
			} catch (LlvmError.INVALID_INPUT error) {
				assert (error.message == "internal LLVM input error: " + expected);
			}
		} else {
			try {
				LlvmLowering.lower (ssa, nabi, cabi);
				assert_not_reached ();
			} catch (LlvmError.INVALID_INPUT error) {
				assert (error.message.contains ("export"));
			}
		}
	}
	var ssa = build_ssa ("export(C) int f() { return 0; }");
	ssa.c_exports[0] = new SsaCExport (ssa.span, ssa.span, ssa.functions[0], "astra.fn.0", Astra.Semantic.ForeignAbi.C, 0);
	var nabi = NativeAbiBuilder.build (ssa);
	try {
		LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
		assert_not_reached ();
	} catch (LlvmError.INVALID_INPUT error) {
		assert (error.message.contains ("conflicts with a native implementation"));
	}
}

private void export_llvm_lifetime() throws GLib.Error {
	SsaProgram? ssa = build_ssa ("export(C) int recurse(int x) { if (x == 0) { return 0; } return recurse(x - 1); } extern(C) int c_one(int x); export(C) void record(int x) { c_one(x); }");
	NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
	CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
	var ssa_ref = WeakRef (ssa);
	var ssa_export_ref = WeakRef (ssa.c_exports[0]);
	var nabi_ref = WeakRef (nabi);
	var cabi_ref = WeakRef (cabi);
	var export_ref = WeakRef (cabi.exports[0]);
	var signature_ref = WeakRef (cabi.exports[0].signature);
	var source_ref = WeakRef (ssa.span.file);
	var artifact = LlvmLowering.lower (ssa, nabi, cabi);
	string dump = artifact.dump ();
	ssa = null;
	nabi = null;
	cabi = null;
	assert (ssa_ref.get () == null && ssa_export_ref.get () == null && nabi_ref.get () == null && cabi_ref.get () == null);
	assert (export_ref.get () == null && signature_ref.get () == null && source_ref.get () == null);
	assert (artifact.dump () == dump && artifact.c_exports.length == 2);
}

private void register_c_exports() {
	add ("/llvm/cexport/domains-forwarding-native-recursion", export_domains);
	add ("/llvm/cexport/mutual-calls-and-zero-arguments", exported_mutual_calls);
	add ("/llvm/cexport/malformed", export_backend_rejections);
	add ("/llvm/cexport/lifetime", export_llvm_lifetime);
}
}
