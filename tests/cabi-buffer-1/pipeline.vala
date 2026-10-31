// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.CAbiBufferPipeline {
private SsaProgram build(string declaration) throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("buffer-plan.astra", declaration));
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.format ());
	}
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	return SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (checked.program)));
}
private void correspondence() {
	try {
		string prefix = "[CCode(buffer_abi=\"u8-i32\")] extern(C) ";
		var source = build (prefix + "int sink(borrowed u8[] bytes,int tail);");
		foreach (string declaration in new string[] { prefix + "int sink(int first,borrowed u8[] bytes);", "[CCode(text_abi=\"utf8-i32\")] extern(C) int sink(borrowed string text,int tail);", "extern(C) int sink(void* bytes,int tail);" }) {
			var other = build (declaration);
			var cabi = CAbiBuilder.build (other, NativeAbiBuilder.build (other));
			var map = new HashTable<SsaCFunction, CAbiFunction> (direct_hash, direct_equal);
			map.insert (source.c_functions[0], cabi.functions[0]);
			bool rejected = false;
			try {
				CAbiValidator.validate_ssa_calls (source, cabi, map);
			} catch (CAbiError error) {
				rejected = true;
			}
			assert (rejected);
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void lifetime_and_physical_mutation() {
	try {
		SsaProgram? source = build ("[CCode(buffer_abi=\"u8-i32\")] extern(C) int sink(borrowed u8[] bytes,int tail);int forward(u8[] bytes){return sink(bytes,7);}");
		NativeAbiProgram? nabi = NativeAbiBuilder.build (source);
		CAbiProgram? cabi = CAbiBuilder.build (source, nabi);
		var artifact = LlvmLowering.lower (source, nabi, cabi);
		var old_source = WeakRef (source);
		source = null;
		assert (old_source.get () == null);
		CAbiVerifier.verify (cabi);
		NativeAbiVerifier.verify (nabi);
		cabi = null;
		nabi = null;
		assert (artifact.requires_c_buffer);
		artifact.verify ();
		var call = (CApi.ValueRef) artifact.c_imports[0].calls[0];
		for (uint index = 0; index < 2; index++) {
			var original = CApi.operand (call, index);
			var replacement = CApi.const_null (CApi.type_of (original));
			CApi.set_operand (call, index, replacement);
			bool rejected = false;
			try {
				artifact.verify ();
			} catch (LlvmError error) {
				rejected = true;
			}
			CApi.set_operand (call, index, original);
			assert (rejected);
			artifact.verify ();
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/cabi-buffer/source-plan-exact-correspondence", correspondence);
	Test.add_func ("/cabi-buffer/lifetime-and-physical-pair-mutation", lifetime_and_physical_mutation);
	return Test.run ();
}
}
