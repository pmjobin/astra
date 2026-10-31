// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.VectorLanes {
private LlvmModuleArtifact lower(SsaProgram ssa) throws GLib.Error {
	var nabi = NativeAbiBuilder.build (ssa);
	return LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
}

private void operations() throws GLib.Error {
	foreach (string element in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32", "bool"}) {
		string type = element + "<4>";
		string source = type + " f(" + type + " v," + element + " x,bool<4> m){" + type + " b=splat(x,4);" + type + " c=insert(v,1,b[2]);return select(m,shuffle(c,3,2,1,0),b);}";
		string llvm = lower (build (source)).dump ();
		foreach (string op in new string[] {"insertelement", "extractelement", "shufflevector", "select <4 x i1>"}) {
			assert (llvm.contains (op));
		}
		assert (llvm.contains ("zeroinitializer") && !llvm.contains ("br ") && !llvm.contains ("phi "));
		foreach (string flag in new string[] {"undef", "poison", "fast", "reassoc", "nnan", "ninf", "nsz", "arcp", "contract", "afn"}) {
			assert (!llvm.contains (" " + flag + " "));
		}
		assert (!llvm.contains ("fadd") && !llvm.contains ("fmul") && !llvm.contains ("alloca") && !llvm.contains ("load ") && !llvm.contains ("store "));
	}
	string floats = lower (build (read ("lane-f32"))).dump ();
	assert (floats.contains ("fmul <4 x float>") && floats.contains ("fadd <4 x float>") && floats.contains ("select <4 x i1>"));
	assert (!floats.contains (" contract ") && !floats.contains ("@llvm.fma") && !floats.contains ("@llvm.fmuladd"));
}

private void lifetime() throws GLib.Error {
	SsaProgram? ssa = build ("f32<4> f(f32<4> a,bool<4> m){return select(m,shuffle(a,3,2,1,0),insert(a,1,a[2]));}");
	var shuffle = (SsaVectorShuffleInstruction) ssa.functions[0].entry.instructions[0];
	var selectors = WeakRef (shuffle.selectors);
	shuffle = null;
	var source_ref = WeakRef (ssa.span.file);
	var type_ref = WeakRef (ssa.functions[0].return_type);
	var artifact = lower (ssa);
	ssa = null;
	assert (selectors.get () == null && source_ref.get () == null && type_ref.get () == null);
	artifact.verify ();
	assert (artifact.requires_vectors && artifact.requires_binary32 && artifact.dump ().contains ("shufflevector <4 x float>"));
	var target = new LlvmTargetMachineArtifact ();
	string path = Path.build_filename (Environment.get_tmp_dir (), "astra-vec-lane-%u.o".printf (Random.next_int ()));
	target.configure (artifact);
	target.emit_object (artifact, path);
	assert (FileUtils.test (path, FileTest.IS_REGULAR) && FileUtils.unlink (path) == 0);
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/vec-lane/llvm/exact-operations-no-branches-memory-fast-math", operations);
	add ("/vec-lane/llvm/independent-lifetime-and-object", lifetime);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
