// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;
namespace Astra.Tests.GenericSlice {
private void physical() throws GLib.Error {
	SsaProgram? ssa = build (fixture ("basic"));
	NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
	CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
	var source = WeakRef (ssa.span.file);
	var graph = WeakRef (ssa);
	var plans = WeakRef (nabi);
	var artifact = LlvmLowering.lower (ssa, nabi, cabi);
	ssa = null;
	nabi = null;
	cabi = null;
	assert (source.get () == null && graph.get () == null && plans.get () == null);
	artifact.verify ();
	var target = new LlvmTargetMachineArtifact ();
	target.configure (artifact);
	artifact.verify ();
	string text = artifact.dump ();
	foreach (string forbidden in new string[] {"sret", "byval", "llvm.memcpy", "llvm.memmove", "@malloc", "@calloc", "@free", "noalias", "typeinfo", "phi %astra.struct", " contract ", " fast "}) {
		assert (!text.contains (forbidden));
	}
	assert (text.contains ("phi i32") && text.contains ("llvm.trap") && text.contains ("insertvalue") && text.contains ("extractvalue"));
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/gen-slice/llvm/erased-borrow-record-leaves-bounds-and-lifetimes", physical);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
