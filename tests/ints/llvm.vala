// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.Integers {
private LlvmModuleArtifact lower(SsaProgram ssa) throws GLib.Error {
	var nabi = NativeAbiBuilder.build (ssa);
	return LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
}
private void physical() throws GLib.Error {
	string dump = lower (build (read ("physical"))).dump ();
	foreach (string width in new string[] {"i8", "i16", "i32"}) {
		foreach (string op in new string[] {"add", "sub", "mul", "sdiv", "srem", "udiv", "urem"}) {
			assert (dump.contains (op + " " + width + " "));
		}
		foreach (string predicate in new string[] {"slt", "sle", "sgt", "sge", "ult", "ule", "ugt", "uge", "eq", "ne"}) {
			assert (dump.contains ("icmp " + predicate + " " + width + " "));
		}
		assert (dump.contains ("phi " + width + " "));
	}
	foreach (string forbidden in new string[] {" nsw ", " nuw ", "sext ", "zext ", "trunc ", "poison"}) {
		assert (!dump.contains (forbidden));
	}
	assert (dump.contains ("icmp eq i8 %p0, -128") && dump.contains ("icmp eq i16 %p0, -32768"));
	assert (dump.contains ("icmp eq i8 %p1, -1") && dump.contains ("icmp eq i16 %p1, -1"));
	assert (dump.contains ("call void @llvm.trap()"));
	string unsigned_only = lower (build ("u8 f(u8 x,u8 y){return x/y+x%y;} u16 g(u16 x,u16 y){return x/y;} u32 h(u32 x,u32 y){return x%y;}")).dump ();
	assert (!unsigned_only.contains (".special") && !unsigned_only.contains (".overflow") && !unsigned_only.contains ("sdiv") && !unsigned_only.contains ("srem"));
	string constants = lower (build ("i8 a(){return -1;} u8 b(){return 255;} u32 c(){return 4294967295;} i8 d(){return -128/-1;} i16 e(){return -32768%-1;} u8 f(){return 1/0;} u16 g(){return 1%0;}")).dump ();
	assert (constants.contains ("ret i8 -1") && constants.contains ("ret i32 -1") && !constants.contains ("poison"));
}
private void joins_storage() throws GLib.Error {
	foreach (string name in new string[] {"branch", "loop", "struct", "addressable", "ownership"}) {
		var artifact = lower (build (read (name)));
		artifact.verify ();
		string dump = artifact.dump ();
		if (name == "addressable") {
			foreach (string width in new string[] {"i8", "i16", "i32"}) {
				assert (dump.contains ("load " + width + ",") && dump.contains ("store " + width + " "));
			}
			assert (dump.contains ("alloca %astra.struct."));
		} else if (name == "branch" || name == "loop") {
			assert (dump.contains ("phi i8 ") && dump.contains ("phi i16 ") && dump.contains (".continue"));
		}
	}
}
private void lifetime() throws GLib.Error {
	SsaProgram? ssa = build (read ("physical"));
	NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
	CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
	var type_ref = WeakRef (ssa.functions[0].return_type);
	var ssa_ref = WeakRef (ssa);
	var native_ref = WeakRef (nabi);
	var source_ref = WeakRef (ssa.span.file);
	var artifact = LlvmLowering.lower (ssa, nabi, cabi);
	ssa = null;
	nabi = null;
	cabi = null;
	assert (type_ref.get () == null && ssa_ref.get () == null && native_ref.get () == null && source_ref.get () == null);
	artifact.verify ();
	var target = new LlvmTargetMachineArtifact ();
	string path = Path.build_filename (Environment.get_tmp_dir (), "astra-ints-%u.o".printf (Random.next_int ()));
	target.configure (artifact);
	target.emit_object (artifact, path);
	assert (FileUtils.test (path, FileTest.IS_REGULAR) && FileUtils.unlink (path) == 0);
}
int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/ints/llvm/exact-width-sign-guards", physical);
	add ("/ints/llvm/joins-storage-ownership", joins_storage);
	add ("/ints/llvm/lifetime-object", lifetime);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
