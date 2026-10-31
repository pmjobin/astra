// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;
namespace Astra.Tests.GenStruct {
private void physical() throws GLib.Error {
	foreach (string name in new string[] {"basic", "nested", "generic-fn", "cap", "pointer", "f64", "vector", "box-matrix", "members"}) {
		SsaProgram? ssa = build (fixture (name));
		NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
		CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
		var witness = WeakRef (ssa);
		var source = WeakRef (ssa.span.file);
		var artifact = LlvmLowering.lower (ssa, nabi, cabi);
		ssa = null;
		nabi = null;
		cabi = null;
		assert (witness.get () == null && source.get () == null);
		artifact.verify ();
		string ir = artifact.dump ();
		foreach (string forbidden in new string[] {"llvm.memcpy", "llvm.memmove", "malloc", "typeinfo", "descriptor", "witness", "dictionary", " fast ", " contract ", "llvm.fma", "llvm.fmuladd", "Pair<", "Bundle<", "Box<"}) {
			assert (!ir.contains (forbidden));
		}
		if (name == "basic" || name == "nested" || name == "generic-fn" || name == "cap") {
			assert (!ir.contains ("alloca") && !ir.contains ("getelementptr"));
		}
		if (name == "vector" || name == "box-matrix") {
			assert (ir.contains ("load <8 x i16>") && ir.contains ("store <8 x i16>"));
		}
		if (name == "f64") {
			assert (ir.contains ("load double") && ir.contains ("store double"));
		}
		if (name == "pointer") {
			assert (ir.contains ("getelementptr") && ir.contains ("alloca %astra.struct."));
		}
	}
}
int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/gen-struct/llvm/ordinary-concrete-layout-promotion-memory-stage-lifetime", physical);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
