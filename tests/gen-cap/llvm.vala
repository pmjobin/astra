// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Core;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;
namespace Astra.Tests.Generics {
private void concrete() throws GLib.Error {
	assert (build (read ("numeric")).functions.length > 0);
	bool rejected = false;
	try {
		SsaVerifier.verify (unresolved_ssa ());
	} catch (SsaError error) {
		rejected = true;
	}
	assert (rejected);
	SsaProgram? ssa = build ("T divide<T>(T a,T b) where T : Numeric {return a/b;}int integer(int a,int b){return divide<int>(a,b);}f64 floating(f64 a,f64 b){return divide<f64>(a,b);}");
	var weak_function = WeakRef (ssa.functions[0]);
	var nabi = NativeAbiBuilder.build (ssa);
	var cabi = CAbiBuilder.build (ssa, nabi);
	var artifact = LlvmLowering.lower (ssa, nabi, cabi);
	ssa = null;
	assert (weak_function.get () == null);
	artifact.verify ();
	string ir = artifact.dump ();
	assert (ir.contains ("sdiv i32") && ir.contains ("fdiv double") && ir.contains ("llvm.trap"));
	foreach (string forbidden in new string[] {"dictionary", "witness", "capability", "generic-op", "nsw", "nuw", "fdiv fast", "contract", "fmuladd", "llvm.fma"}) {
		assert (!ir.contains (forbidden));
	}
	var directory = DirUtils.make_tmp ("astra-gen-cap-object-XXXXXX");
	var machine = new LlvmTargetMachineArtifact ();
	machine.configure (artifact);
	machine.emit_object (artifact, directory + "/cap.o");
	assert (FileUtils.test (directory + "/cap.o", FileTest.IS_REGULAR));
	FileUtils.unlink (directory + "/cap.o");
	DirUtils.remove (directory);
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/gen-cap/llvm/division-semantics-lifetime-firewall-object", concrete);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
