// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;
namespace Astra.Tests.StructCopy {
private void physical() throws GLib.Error {
	foreach (string name in new string[] {"basic", "assign", "nested", "deep", "vector", "f64", "pointer", "alias", "generic", "scalarize", "mixed", "method", "null-source", "null-destination"}) {
		SsaProgram? ssa = build (fixture (name));
		NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
		CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
		var source = WeakRef (ssa.span.file);
		var graph = WeakRef (ssa);
		var artifact = LlvmLowering.lower (ssa, nabi, cabi);
		ssa = null;
		nabi = null;
		cabi = null;
		assert (source.get () == null && graph.get () == null);
		artifact.verify ();
		string ir = artifact.dump ();
		foreach (string forbidden in new string[] {"llvm.memcpy", "llvm.memmove", "malloc", "typeinfo", "descriptor", "llvm.fma", "llvm.fmuladd", " contract ", " fast "}) {
			assert (!ir.contains (forbidden));
		}
		if (name == "basic" || name == "assign" || name == "nested" || name == "deep" || name == "scalarize") {
			assert (!ir.contains ("alloca"));
		}
		if (name == "vector") {
			assert (ir.contains ("load <8 x i16>") && ir.contains ("store <8 x i16>"));
		}
		if (name == "f64") {
			assert (!ir.contains ("fadd") && !ir.contains ("fmul") && !ir.contains ("fptrunc") && !ir.contains ("fpext"));
		}
	}
}
int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/struct-copy/llvm/lifetime-ordinary-memory-no-aggregate-runtime", physical);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
