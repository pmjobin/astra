// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;
namespace Astra.Tests.GenericCopy {
private void physical() throws GLib.Error {
	SsaProgram? ssa = build (fixture ("transport"));
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
	foreach (string forbidden in new string[] {"sret", "byval", "llvm.memcpy", "llvm.memmove", "@malloc", "@calloc", "@free", "typeinfo", "descriptor", "phi {", "phi %astra.struct", " contract ", " fast "}) {
		assert (!text.contains (forbidden));
	}
	assert (text.contains ("phi i32") && text.contains ("phi double") && text.contains ("insertvalue") && text.contains ("extractvalue"));
	SsaProgram? plain = build ("struct S{int x;f64 y;}T id<T>(T x){T local=x;return local;}S f(S x){return id(x);}");
	var native = NativeAbiBuilder.build (plain);
	var compiled = LlvmLowering.lower (plain, native, CAbiBuilder.build (plain, native));
	plain = null;
	compiled.verify ();
	assert (!compiled.dump ().contains ("alloca") && native.abi_version == NativeAbiVersion.AGGREGATE_V7);
}
int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/gen-copy/llvm/actual-carriers-phis-lifetime-and-no-runtime", physical);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
