// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.SliceBound {
private LlvmModuleArtifact lower(SsaProgram ssa) throws GLib.Error {
	var nabi = NativeAbiBuilder.build (ssa);
	return LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
}

private void shapes() throws GLib.Error {
	var types = new BuiltinTypes ();
	int shapes = 0;
	foreach (string element in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32"}) {
		foreach (int lanes in new int[] {0, 2, 4, 8, 16}) {
			if (lanes != 0 && types.vector_of (types.resolve (element), lanes) == null) {
				continue;
			}
			string type = lanes == 0 ? element : "%s<%d>".printf (element, lanes);
			var artifact = lower (build ("%s access(borrowed %s[] s,%s v,u32 i){s[i]=v;return s[i];}".printf (type, type, type)));
			string llvm = artifact.dump ();
			string physical = element == "f32" ? "float" : "i%u".printf (((IntegerType) types.resolve (element)).bit_width);
			if (lanes != 0) {
				physical = "<%d x %s>".printf (lanes, physical);
			}
			assert (llvm.contains ("@astra.fn.0(ptr %p0.base, i32 %p0.length, " + physical + " %p1, i32 %p2)"));
			assert (llvm.contains ("insertvalue { ptr, i32 }") && llvm.contains ("store " + physical) && llvm.contains ("load " + physical));
			assert (llvm.contains ("getelementptr " + physical) && llvm.contains ("extractvalue { ptr, i32 } %p0, 1") && llvm.contains ("zext i32 %p2 to i64"));
			foreach (string forbidden in new string[] {"alloca", "getelementptr inbounds", "ptrtoint", "inttoptr", "noalias", "readonly", "nonnull", "icmp eq ptr", "poison", "undef"}) {
				assert (!llvm.contains (forbidden));
			}
			shapes++;
		}
	}
	assert (shapes == 27);
	var mixed = lower (build (read ("mixed"))).dump ();
	assert (mixed.contains ("@astra.fn.0(i8 %p0, ptr %p1.base, i32 %p1.length, <4 x float> %p2, ptr %p3.base, i32 %p3.length, ptr %p4, i1 %p5)"));
	var merged = lower (build (read ("merge"))).dump ();
	assert (merged.contains ("phi { ptr, i32 }") && merged.contains ("call fastcc i32 @astra.fn.0(ptr"));
	var owned_result = lower (build (read ("owned-result"))).dump ();
	assert (owned_result.contains ("@astra.fn.0(ptr %p0.base, i32 %p0.length, ptr %p1)"));
	assert (owned_result.contains ("call fastcc ptr @astra.fn.0(ptr"));
}

private void lifetime() throws GLib.Error {
	SsaProgram? ssa = build (read ("forward"));
	var parameter = WeakRef (ssa.functions[0].parameters[0]);
	var type = WeakRef (ssa.functions[0].parameters[0].semantic_type);
	var source = WeakRef (ssa.span.file);
	var artifact = lower (ssa);
	ssa = null;
	assert (parameter.get () == null && type.get () == null && source.get () == null);
	artifact.verify ();
	string directory = DirUtils.make_tmp ("astra-slice-bound-object-XXXXXX");
	var machine = new LlvmTargetMachineArtifact ();
	machine.configure (artifact);
	machine.emit_object (artifact, directory + "/slice.o");
	assert (FileUtils.test (directory + "/slice.o", FileTest.IS_REGULAR));
	FileUtils.unlink (directory + "/slice.o");
	DirUtils.remove (directory);
	foreach (string name in new string[] {"sum", "alias", "owned", "bit", "dsp", "dot", "owned-result"}) {
		lower (build (read (name))).verify ();
	}
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/slice-bound/llvm/exact-memory-group-expansion-and-merges", shapes);
	add ("/slice-bound/llvm/lifetime-object-and-integrations", lifetime);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
