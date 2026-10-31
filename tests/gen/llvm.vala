// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Core;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;
namespace Astra.Tests.Generics {
private LlvmModuleArtifact lower(SsaProgram ssa) throws GLib.Error {
	var nabi = NativeAbiBuilder.build (ssa);
	return LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
}
private void emission() throws GLib.Error {
	var valid = build (read ("identity"));
	var nabi = NativeAbiBuilder.build (valid);
	var cabi = CAbiBuilder.build (valid, nabi);
	bool rejected = false;
	try {
		LlvmLowering.lower (unresolved_ssa (), nabi, cabi);
	} catch (LlvmError error) {
		rejected = true;
	}
	assert (rejected);
	var ssa = build (read ("dedup"));
	string ir = lower (ssa).dump ();
	int instances = 0;
	int signed_byte = 0;
	int unsigned_byte = 0;
	foreach (var f in ssa.functions) {
		if (!f.name.has_prefix ("astra.gen.")) {
			continue;
		}
		instances++;
		assert (ir.contains ("@astra.fn.%d(".printf (f.ordinal)));
		if (f.return_type.kind == Astra.Semantic.TypeKind.I8) {
			signed_byte++;
			assert (ir.contains ("define internal fastcc i8 @astra.fn.%d(i8 %%p0)".printf (f.ordinal)));
		}
		if (f.return_type.kind == Astra.Semantic.TypeKind.U8) {
			unsigned_byte++;
			assert (ir.contains ("define internal fastcc i8 @astra.fn.%d(i8 %%p0)".printf (f.ordinal)));
		}
	}
	assert (instances == 10 && signed_byte == 1 && unsigned_byte == 1);
	string unused = lower (build ("T id<T>(T x){return x;}")).dump ();
	assert (!unused.contains ("define "));
	string recursive = lower (build (read ("recursive"))).dump ();
	assert (recursive.contains ("call fastcc double") && recursive.contains ("define internal fastcc double"));
}
private void lifetime() throws GLib.Error {
	SsaProgram? ssa = build (read ("property"));
	var witness = WeakRef (ssa.functions[ssa.functions.length - 1]);
	var artifact = lower (ssa);
	ssa = null;
	assert (witness.get () == null);
	artifact.verify ();
	var directory = DirUtils.make_tmp ("astra-gen-object-XXXXXX");
	var machine = new LlvmTargetMachineArtifact ();
	machine.configure (artifact);
	machine.emit_object (artifact, directory + "/gen.o");
	assert (FileUtils.test (directory + "/gen.o", FileTest.IS_REGULAR));
	FileUtils.unlink (directory + "/gen.o");
	DirUtils.remove (directory);
}
int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/gen/llvm/concrete-only-same-representation-distinct-unused-recursion", emission);
	add ("/gen/llvm/stage-lifetime-object", lifetime);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
