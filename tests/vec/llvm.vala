// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.Vectors {
private LlvmModuleArtifact lower(SsaProgram ssa) throws GLib.Error {
	var nabi = NativeAbiBuilder.build (ssa);
	return LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
}

private void physical() throws GLib.Error {
	string arithmetic = lower (build (read ("f32"))).dump ();
	foreach (string op in new string[] {"fadd", "fsub", "fmul", "fdiv", "fneg"}) {
		assert (arithmetic.contains (op + " <4 x float> "));
	}
	foreach (string predicate in new string[] {"oeq", "une", "olt", "ole", "ogt", "oge"}) {
		assert (arithmetic.contains ("fcmp " + predicate + " <4 x float> "));
	}
	string integer = lower (build (read ("integers"))).dump ();
	assert (integer.contains ("icmp sgt <4 x i8>") && integer.contains ("icmp ugt <4 x i8>") && integer.contains ("add <8 x i16>") && integer.contains ("add <16 x i8>"));
	string masks = lower (build (read ("masks"))).dump ();
	assert (masks.contains ("xor <4 x i1>") && masks.contains ("icmp eq <4 x i1>") && masks.contains ("icmp ne <4 x i1>"));
	assert (masks.contains ("extractelement <4 x i1>") && masks.contains ("and i1") && masks.contains ("or i1"));
	foreach (string name in new string[] {"basic", "integers", "f32", "masks", "branch", "loop", "native-call", "order", "ownership", "physical"}) {
		string dump = lower (build (read (name))).dump ();
		foreach (string flag in new string[] {"reassoc", "nnan", "ninf", "nsz", "arcp", "contract", "afn", "fast", "poison", "undef", "llvm.fma", "llvm.fmuladd"}) {
			assert (!dump.contains (" " + flag + " ") && !dump.contains ("@" + flag));
		}
		foreach (string line in dump.split ("\n")) {
			if (line.contains (" = add ") || line.contains (" = sub ") || line.contains (" = mul ")) {
				assert (!line.contains (" nsw ") && !line.contains (" nuw "));
			}
		}
		assert (!dump.contains ("alloca <") && !dump.contains ("load <") && !dump.contains ("store <"));
		if (name == "branch") {
			assert (dump.contains ("phi <4 x i16>") && dump.contains ("phi <4 x i1>"));
		}
		if (name == "loop") {
			assert (dump.contains ("phi <4 x i8>") && dump.contains ("phi <4 x float>") && dump.contains ("phi <4 x i1>"));
		}
		if (name == "basic") {
			assert (dump.contains ("insertelement <4 x i32> zeroinitializer"));
		}
	}
}

private void lifetime() throws GLib.Error {
	SsaProgram? ssa = build (read ("f32"));
	NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
	CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
	var type_ref = WeakRef (ssa.functions[0].return_type);
	var element_ref = WeakRef (((VectorType) ssa.functions[0].return_type).element_type);
	var ssa_ref = WeakRef (ssa);
	var native_ref = WeakRef (nabi);
	var source_ref = WeakRef (ssa.span.file);
	var artifact = LlvmLowering.lower (ssa, nabi, cabi);
	ssa = null;
	nabi = null;
	cabi = null;
	assert (type_ref.get () == null && element_ref.get () == null && ssa_ref.get () == null && native_ref.get () == null && source_ref.get () == null);
	artifact.verify ();
	assert (artifact.requires_vectors && artifact.requires_binary32);
	string dump = artifact.dump ();
	assert (dump.contains ("fdiv <4 x float>") && dump.contains ("fmul <4 x float>"));
	var target = new LlvmTargetMachineArtifact ();
	string path = Path.build_filename (Environment.get_tmp_dir (), "astra-vec-%u.o".printf (Random.next_int ()));
	target.configure (artifact);
	target.emit_object (artifact, path);
	assert (FileUtils.test (path, FileTest.IS_REGULAR) && FileUtils.unlink (path) == 0);
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/vec/llvm/operations-construction-masks-phis-no-memory", physical);
	add ("/vec/llvm/lifetime-object", lifetime);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
