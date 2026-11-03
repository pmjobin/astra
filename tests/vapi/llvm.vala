// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.Vapi {
private void differential() throws GLib.Error {
	foreach (string name in new string[] {"basic", "order", "shortcircuit", "loop", "recursive-native", "roundtrip", "mixed"}) {
		string source = fixture ("vapi-" + name + ".astra");
		string[] declarations = {
			fixture ("basic.vapi"), fixture ("state.vapi")
		};
		if (name == "roundtrip") {
			declarations += fixture ("roundtrip.vapi");
		}
		var a = build (source, declarations, false);
		var b = build (source, declarations);
		var a_nabi = NativeAbiBuilder.build (a);
		var b_nabi = NativeAbiBuilder.build (b);
		var source_artifact = LlvmLowering.lower (a, a_nabi, CAbiBuilder.build (a, a_nabi));
		var vapi_artifact = LlvmLowering.lower (b, b_nabi, CAbiBuilder.build (b, b_nabi));
		source_artifact.verify ();
		vapi_artifact.verify ();
		// Both tests use program.astra as the module name; no debug spans are
		// emitted. Full IR equality is stronger than foreign-shape equality.
		assert (source_artifact.dump () == vapi_artifact.dump ());
		int calls = 0;
		foreach (var imported in vapi_artifact.c_imports) {
			assert (CApi.get_linkage (imported.value) == CApi.Linkage.EXTERNAL);
			assert (CApi.function_call_conv (imported.value) == CApi.CallConv.C);
			assert ((void*) CApi.first_block (imported.value) == null);
			foreach (var call in imported.calls) {
				assert (CApi.instruction_call_conv ((CApi.ValueRef) call) == CApi.CallConv.C);
				assert ((void*) CApi.called_value ((CApi.ValueRef) call) == (void*) imported.value);
				calls++;
			}
		}
		assert (calls > 0);
		if (name == "recursive-native") {
			assert (vapi_artifact.dump ().contains ("call fastcc i32 @astra.fn.0"));
		}
		if (name == "mixed") {
			assert (vapi_artifact.c_exports.length == 1 && vapi_artifact.c_imports.length == 6);
			assert (vapi_artifact.dump ().contains ("define i32 @mixed(i32"));
		}
	}
}

private void lifetime() throws GLib.Error {
	SsaProgram? ssa = build (alias_source (fixture ("vapi-roundtrip.astra")), {fixture ("aliases.vapi"), fixture ("state-aliases.vapi"), fixture ("roundtrip-aliases.vapi")});
	var metadata_ref = WeakRef (ssa.c_functions[2].metadata);
	var source_ref = WeakRef (ssa.c_functions[0].span.file);
	var ssa_ref = WeakRef (ssa);
	var imported_ref = WeakRef (ssa.c_functions[0]);
	NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
	CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
	var nabi_ref = WeakRef (nabi);
	var cabi_ref = WeakRef (cabi);
	var signature_ref = WeakRef (cabi.functions[0].signature);
	var artifact = LlvmLowering.lower (ssa, nabi, cabi);
	ssa = null;
	nabi = null;
	cabi = null;
	assert (ssa_ref.get () == null && imported_ref.get () == null && nabi_ref.get () == null && cabi_ref.get () == null && signature_ref.get () == null && source_ref.get () == null && metadata_ref.get () == null);
	artifact.verify ();
	assert (artifact.dump ().contains ("declare i32 @astra_test_add_impl(i32, i32)"));
	assert (artifact.dump ().contains ("define i32 @astra_export_roundtrip()"));
}

private void metadata_differential() throws GLib.Error {
	string source = "int main() { reset(); return friendly(42); }";
	string[] declarations = {
		"[CCode (cname = \"physical\")] int friendly(int x); [CCode (cname = \"physical_reset\")] void reset();"
	};
	var plain = build (source, declarations);
	var plain_nabi = NativeAbiBuilder.build (plain);
	var plain_cabi = CAbiBuilder.build (plain, plain_nabi);
	var plain_llvm = LlvmLowering.lower (plain, plain_nabi, plain_cabi);
	var direct = build ("int main() { physical_reset(); return physical(42); }", {"int physical(int x); void physical_reset();"}, false);
	var direct_nabi = NativeAbiBuilder.build (direct);
	var direct_cabi = CAbiBuilder.build (direct, direct_nabi);
	assert (plain_cabi.functions[0].name == "friendly" && direct_cabi.functions[0].name == "physical");
	assert (plain_cabi.functions[0].external_symbol == direct_cabi.functions[0].external_symbol);
	assert (plain_llvm.dump () == LlvmLowering.lower (direct, direct_nabi, direct_cabi).dump ());
	string headers = declarations[0].replace (")]", ", cheader_filename = \"this/header/does/not/exist.h\")]");
	var with_header = build (source, {headers});
	var header_nabi = NativeAbiBuilder.build (with_header);
	var header_cabi = CAbiBuilder.build (with_header, header_nabi);
	assert (NativeAbiDump.format (plain_nabi) == NativeAbiDump.format (header_nabi));
	assert (plain_nabi.functions.length == 1);
	for (int i = 0; i < 2; i++) {
		var a = plain_cabi.functions[i];
		var b = header_cabi.functions[i];
		assert (a.metadata.header_count == 0 && b.metadata.header_count == 1);
		assert (a.signature.profile == b.signature.profile && a.signature.parameters.length == b.signature.parameters.length);
		assert ((a.signature.result == null) == (b.signature.result == null));
		if (a.signature.result != null) {
			assert (a.signature.result.scalar_type == b.signature.result.scalar_type);
		}
		for (int p = 0; p < a.signature.parameters.length; p++) {
			assert (a.signature.parameters[p].scalar_type == b.signature.parameters[p].scalar_type);
		}
	}
	assert (CAbiDump.format (header_cabi).contains ("(headers") && !CAbiDump.format (plain_cabi).contains ("(headers"));
	var header_llvm = LlvmLowering.lower (with_header, header_nabi, header_cabi);
	header_llvm.verify ();
	assert (plain_llvm.dump () == header_llvm.dump ());
	assert (!header_llvm.dump ().contains ("friendly") && !header_llvm.dump ().contains ("does/not/exist"));
	assert (header_llvm.dump ().contains ("declare i32 @physical(i32)") && header_llvm.dump ().contains ("call i32 @physical(i32 42)"));
	assert (header_llvm.dump ().contains ("call void @physical_reset()") && header_llvm.dump ().contains ("define internal fastcc i32 @astra.fn.0()"));
}

private void aliases() throws GLib.Error {
	foreach (string name in new string[] {"basic", "order", "shortcircuit", "loop", "recursive-native", "roundtrip"}) {
		string[] declarations = {
			fixture ("aliases.vapi"), fixture ("state-aliases.vapi")
		};
		if (name == "roundtrip") {
			declarations += fixture ("roundtrip-aliases.vapi");
		}
		var ssa = build (alias_source (fixture ("vapi-" + name + ".astra")), declarations);
		var nabi = NativeAbiBuilder.build (ssa);
		var cabi = CAbiBuilder.build (ssa, nabi);
		var artifact = LlvmLowering.lower (ssa, nabi, cabi);
		artifact.verify ();
		for (int f = 0; f < artifact.c_imports.length; f++) {
			var imported = artifact.c_imports[f];
			size_t length;
			assert (CApi.value_name (imported.value, out length) == cabi.functions[f].external_symbol);
			assert (CApi.function_call_conv (imported.value) == CApi.CallConv.C && (void*) CApi.first_block (imported.value) == null);
			foreach (var call in imported.calls) {
				assert ((void*) CApi.called_value ((CApi.ValueRef) call) == (void*) imported.value);
				assert (CApi.instruction_call_conv ((CApi.ValueRef) call) == CApi.CallConv.C);
			}
		}
		assert (artifact.dump ().contains ("declare i32 @astra_test_add_impl(i32, i32)") && !artifact.dump ().contains ("@add("));
	}
	// Opaque symbol spelling reaches LLVM unchanged, without an identifier rule.
	foreach (string symbol in new string[] {"physical.$name", "space name", "é", "quote\"back\\line\n"}) {
		string encoded = symbol.replace ("\\", "\\\\").replace ("\"", "\\\"").replace ("\n", "\\n");
		var ssa = build ("int main() { return local(); }", {"[CCode (cname = \"" + encoded + "\")] int local();"});
		var nabi = NativeAbiBuilder.build (ssa);
		var artifact = LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
		artifact.verify ();
		size_t length;
		assert (CApi.value_name (artifact.c_imports[0].value, out length) == symbol && length == symbol.length);
	}
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/vapi-llvm/metadata-physical-and-header-differential", metadata_differential);
	add ("/vapi-llvm/aliases-exact-c-targets", aliases);
	add ("/vapi-llvm/source-extern-differential-ccc", differential);
	add ("/vapi-llvm/frontend-through-artifact-lifetime", lifetime);
	int status = Test.run ();
	cases = null;
	return status;
}

}
