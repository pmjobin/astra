// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.IntegerConversions {
private LlvmModuleArtifact lower(SsaProgram ssa) throws GLib.Error {
	var nabi = NativeAbiBuilder.build (ssa);
	return LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
}

private void operations() throws GLib.Error {
	string representative = lower (build (read ("values"))).dump ();
	foreach (string op in new string[] {"sext <8 x i8>", "zext <8 x i8>", "trunc <8 x i16>"}) {
		assert (representative.contains (op));
	}
	var types = new BuiltinTypes ();
	int cases = 0;
	foreach (string source in new string[] {"i8", "u8", "i16", "u16", "int", "u32"}) {
		foreach (string destination in new string[] {"i8", "u8", "i16", "u16", "int", "u32"}) {
			foreach (int lanes in new int[] {1, 2, 4, 8, 16}) {
				var from = (IntegerType) types.resolve (source);
				var to = (IntegerType) types.resolve (destination);
				if (lanes != 1 && (types.vector_of (from, lanes) == null || types.vector_of (to, lanes) == null)) {
					continue;
				}
				string s = lanes == 1 ? source : "%s<%d>".printf (source, lanes);
				string d = lanes == 1 ? destination : "%s<%d>".printf (destination, lanes);
				var ssa = build ("%s f(%s x){return x as %s;}".printf (d, s, d));
				assert (ssa.functions[0].entry.instructions.length == 1 && ssa.functions[0].entry.instructions[0] is SsaIntegerConversionInstruction);
				string llvm = lower (ssa).dump ();
				string op = from.bit_width == to.bit_width ? "" : from.bit_width > to.bit_width ? "trunc" : from.is_signed ? "sext" : "zext";
				string physical_source = lanes == 1 ? "i%u".printf (from.bit_width) : "<%d x i%u>".printf (lanes, from.bit_width);
				string physical_destination = lanes == 1 ? "i%u".printf (to.bit_width) : "<%d x i%u>".printf (lanes, to.bit_width);
				if (op != "") {
					assert (llvm.contains (op + " " + physical_source) && llvm.contains (" to " + physical_destination));
				} else {
					assert (!llvm.contains ("%v") && llvm.contains ("ret " + physical_destination + " %p0"));
				}
				foreach (string forbidden in new string[] {"bitcast", "ptrtoint", "inttoptr", "sitofp", "uitofp", "fptosi", "fptoui", "extractelement", "insertelement", "add ", "mul ", "div ", "alloca", "load ", "store ", " nsw ", " nuw "}) {
					assert (!llvm.contains (forbidden));
				}
				cases++;
			}
		}
	}
	assert (cases == 128);
}

private void lifetime() throws GLib.Error {
	SsaProgram? ssa = build ("i16<8> f(u8<8> x){return x as i16<8>;}");
	var instruction = WeakRef (ssa.functions[0].entry.instructions[0]);
	var source = WeakRef (ssa.span.file);
	var type = WeakRef (ssa.functions[0].return_type);
	var artifact = lower (ssa);
	ssa = null;
	assert (instruction.get () == null && source.get () == null && type.get () == null);
	artifact.verify ();
	assert (artifact.requires_vectors && !artifact.requires_binary32 && artifact.dump ().contains ("zext <8 x i8>"));
	var target = new LlvmTargetMachineArtifact ();
	string path = Path.build_filename (Environment.get_tmp_dir (), "astra-iconv-%u.o".printf (Random.next_int ()));
	target.configure (artifact);
	target.emit_object (artifact, path);
	assert (FileUtils.test (path, FileTest.IS_REGULAR) && FileUtils.unlink (path) == 0);
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/iconv/llvm/all-scalar-vector-pairs-exact-casts", operations);
	add ("/iconv/llvm/independent-lifetime-and-object", lifetime);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
