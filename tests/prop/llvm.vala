// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.Properties {
private LlvmModuleArtifact lower(SsaProgram ssa) throws GLib.Error {
	var nabi = NativeAbiBuilder.build (ssa);
	return LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
}
private void calls() throws GLib.Error {
	string basic = lower (build (read ("basic"))).dump ();
	assert (basic.contains ("define internal fastcc i32 @astra.propget.class.0.0(ptr %this)"));
	assert (basic.contains ("define internal fastcc void @astra.propset.class.0.0(ptr %this, i32 %p0)"));
	assert (basic.contains ("call fastcc void @astra.propset.class.0.0") && basic.contains ("call fastcc i32 @astra.propget.class.0.0"));
	assert (!basic.contains ("icmp eq ptr %this, null"));
	string f64 = lower (build (read ("f64"))).dump ();
	assert (f64.contains ("double @astra.propget.class.0.0") && f64.contains ("@astra.propset.class.0.0(ptr %this, double %p0)"));
	assert (f64.contains ("fmul double") && f64.contains ("fadd double") && !f64.contains ("fmuladd") && !f64.contains (" fast "));
	string nullable = lower (build (read ("null-set"))).dump ();
	assert (nullable.index_of ("br i1 true, label %object.guard") < nullable.index_of ("call i32 @life_record") && nullable.index_of ("call i32 @life_record") < nullable.index_of ("call fastcc void @astra.propset"));
}
private void lifetime() throws GLib.Error {
	SsaProgram? ssa = build (read ("recursive"));
	var property = WeakRef (ssa.classes[0].properties[0]);
	var accessor = WeakRef (ssa.classes[0].properties[0].getter);
	var artifact = lower (ssa);
	ssa = null;
	assert (property.get () == null && accessor.get () == null);
	artifact.verify ();
	var directory = DirUtils.make_tmp ("astra-prop-object-XXXXXX");
	var machine = new LlvmTargetMachineArtifact ();
	machine.configure (artifact);
	machine.emit_object (artifact, directory + "/prop.o");
	assert (FileUtils.test (directory + "/prop.o", FileTest.IS_REGULAR));
	FileUtils.unlink (directory + "/prop.o");
	DirUtils.remove (directory);
}
int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/prop/llvm/direct-calls-f64-and-null-order", calls);
	add ("/prop/llvm/stage-lifetime-and-object", lifetime);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
