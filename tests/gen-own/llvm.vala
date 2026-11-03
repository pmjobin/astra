// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;
namespace Astra.Tests.GenOwn {
private void lifetime() throws GLib.Error {
	foreach (string name in new string[] {"relay", "recursive", "null", "class-nodeinit", "multi"}) {
		SsaProgram? ssa = build (read (name));
		var weak = WeakRef (ssa.functions[0]);
		var nabi = NativeAbiBuilder.build (ssa);
		var cabi = CAbiBuilder.build (ssa, nabi);
		var artifact = LlvmLowering.lower (ssa, nabi, cabi);
		ssa = null;
		assert (weak.get () == null);
		artifact.verify ();
		string ir = artifact.dump ();
		foreach (string forbidden in new string[] {"Ownable", "type-parameter", "dictionary", "witness", "llvm.memcpy", "llvm.memmove", "@malloc", "alloca ptr", "alloca i1", "llvm.fma", "fmuladd"}) {
			assert (!ir.contains (forbidden));
		}
		if (name == "class-nodeinit") {
			assert (!ir.contains ("@astra.dtor"));
		}
	}
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/gen-own/llvm/concrete-lowering-lifetime-no-runtime-machinery", lifetime);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
