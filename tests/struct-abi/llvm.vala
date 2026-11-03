// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;
namespace Astra.Tests.StructAbi {
private void physical() throws GLib.Error {
	foreach (string name in new string[] {"basic", "identity", "result", "order", "nested", "vector", "f32", "f64", "branch", "forward", "generic", "single", "cad", "method", "mixed", "pointer", "deep", "many"}) {
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
		foreach (string forbidden in new string[] {"sret", "byval", "llvm.memcpy", "llvm.memmove", "malloc", "typeinfo", "descriptor", "llvm.fma", "llvm.fmuladd", " contract ", " fast "}) {
			assert (!ir.contains (forbidden));
		}
		if (name != "method" && name != "mixed" && name != "result" && name != "order" && name != "pointer") {
			assert (!ir.contains ("alloca") && !ir.contains ("getelementptr"));
		}
		if (name == "identity") {
			assert (ir.contains ("define internal fastcc { i32, double } @astra.fn.0(i32 %p0, double %p1)") && ir.contains ("insertvalue") && ir.contains ("extractvalue"));
		}
		if (name == "single") {
			assert (ir.contains ("define internal fastcc double @astra.fn.0(double %p0)") && !ir.contains ("insertvalue") && !ir.contains ("extractvalue"));
		}
		if (name == "nested") {
			assert (ir.contains ("{ i32, double, <8 x i16> }") && ir.contains ("(i32 %p0, double %p1, <8 x i16> %p2)"));
		}
		if (name == "f64" || name == "f32") {
			assert (!ir.contains ("fadd") && !ir.contains ("fmul") && !ir.contains ("fptrunc") && !ir.contains ("fpext"));
		}
	}
}

private void firewall() throws GLib.Error {
	var ssa = build (fixture ("basic"));
	var nabi = NativeAbiBuilder.build (ssa);
	var cabi = CAbiBuilder.build (ssa, nabi);
	nabi.functions[0].signature.struct_result = null;
	bool rejected = false;
	try {
		LlvmLowering.lower (ssa, nabi, cabi);
	} catch (GLib.Error e) {
		rejected = true;
	}
	assert (rejected);
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/struct-abi/llvm/backend-only-carrier-flat-params-no-memory-lifetime", physical);
	add ("/struct-abi/llvm/missing-physical-result-plan-firewall", firewall);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
