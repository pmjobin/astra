// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;
namespace Astra.Tests.StructAgg {
private void physical() throws GLib.Error {
	foreach (string name in new string[] {"basic", "deep", "siblings", "vector", "f64", "pointer", "scalarize", "addressed", "method", "order", "generic"}) {
		SsaProgram? ssa = build (fixture (name));
		NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
		CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
		var ssa_ref = WeakRef (ssa);
		var source_ref = WeakRef (ssa.span.file);
		var artifact = LlvmLowering.lower (ssa, nabi, cabi);
		ssa = null;
		nabi = null;
		cabi = null;
		assert (ssa_ref.get () == null && source_ref.get () == null);
		artifact.verify ();
		string ir = artifact.dump ();
		foreach (string forbidden in new string[] {"llvm.memcpy", "malloc", "typeinfo", "descriptor", " fast ", " contract ", "llvm.fma", "llvm.fmuladd"}) {
			assert (!ir.contains (forbidden));
		}
		if (name == "basic" || name == "deep" || name == "siblings" || name == "scalarize") {
			assert (!ir.contains ("alloca") && !ir.contains ("getelementptr"));
		}
		if (name == "vector") {
			assert (ir.contains ("load <8 x i16>") && ir.contains ("store <8 x i16>") && ir.contains ("<4 x float>"));
		}
		if (name == "f64") {
			assert (ir.contains ("load double") && ir.contains ("store double") && ir.contains ("fmul double") && ir.contains ("fadd double"));
		}
		if (name == "pointer" || name == "addressed") {
			assert (ir.contains ("getelementptr") && ir.contains ("alloca %astra.struct."));
		}
	}
}
int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/struct-agg/llvm/physical-types-addresses-ssa-lifetime", physical);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
