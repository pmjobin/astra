// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.VectorDot {
private LlvmModuleArtifact lower(SsaProgram ssa) throws GLib.Error {
	var nabi = NativeAbiBuilder.build (ssa);
	return LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
}

private string operation(string source) throws GLib.Error {
	var ssa = build (source);
	assert (ssa.functions[0].storage.length == 0 && ssa.functions[0].entry.instructions.length == 1 && ssa.functions[0].entry.instructions[0] is SsaVectorDotInstruction);
	string llvm = lower (ssa).dump ();
	foreach (string forbidden in new string[] {"insertelement", "llvm.fma", "llvm.fmuladd", "vector.reduce.fadd", "alloca", "load ", "store ", " nsw ", " nuw ", " fast ", " nnan ", " ninf ", " nsz ", " reassoc ", " contract ", " afn ", " arcp "}) {
		if (llvm.contains (forbidden)) {
			GLib.error ("Forbidden %s in %s: %s", forbidden, source, llvm);
		}
	}
	// LLVM's nocreateundeforpoison attribute is a guarantee, not a lane.
	assert (!Regex.match_simple ("\\b(?:undef|poison)\\b", llvm));
	return llvm;
}

private void operations() throws GLib.Error {
	var types = new BuiltinTypes ();
	int count = 0;
	foreach (string category in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32"}) {
		var element = types.resolve (category);
		foreach (int lanes in new int[] {2, 4, 8, 16}) {
			var vector = types.vector_of (element, lanes);
			if (vector == null) {
				continue;
			}
			string source = vector.display_name ();
			foreach (string destination in category == "f32" ? new string[] {"f32"} : new string[] {"i8", "u8", "i16", "u16", "int", "u32"}) {
				var d = types.resolve (destination) as IntegerType;
				var s = element as IntegerType;
				if (s != null && d.bit_width < s.bit_width) {
					continue;
				}
				foreach (bool mac in new bool[] {false, true}) {
					string op = (mac ? "mac" : "dot") + (s == null ? "" : "_wrap");
					string llvm = operation ("%s f(%s%s a,%s b){return %s(%sa,b%s);}".printf (destination, mac ? destination + " c," : "", source, source, op, mac ? "c," : "", s != null && !mac ? "," + destination : ""));
					if (s != null) {
						assert (llvm.contains ("mul <%d x i%u>".printf (lanes, d.bit_width)));
						if (d.bit_width > s.bit_width) {
							assert (llvm.contains ((s.is_signed ? "sext" : "zext") + " <%d x i%u>".printf (lanes, s.bit_width)));
						} else {
							assert (!llvm.contains ("sext ") && !llvm.contains ("zext "));
						}
					} else {
						assert (llvm.contains ("fmul <%d x float>".printf (lanes)));
						assert (llvm.contains (mac ? "fadd float %p0," : "fadd float 0.000000e+00,"));
						int extracts = 0;
						int adds = 0;
						string previous = mac ? "%p0" : "0.000000e+00";
						foreach (string line in llvm.split ("\n")) {
							if (line.contains ("extractelement")) {
								assert (line.has_suffix (", i32 %d".printf (extracts)));
								extracts++;
							}
							if (line.contains ("fadd float")) {
								assert (line.contains ("fadd float " + previous + ","));
								previous = line.strip ().split (" = ")[0];
								adds++;
							}
						}
						assert (extracts == lanes && adds == lanes);
					}
					count++;
				}
			}
		}
	}
	assert (count == 164);
	Test.message ("%d exact parameter-driven LLVM dot/MAC realizations", count);
}

private void lifetime() throws GLib.Error {
	SsaProgram? ssa = build (read ("values"));
	var instruction = WeakRef (ssa.functions[0].entry.instructions[0]);
	var source = WeakRef (ssa.span.file);
	var type = WeakRef (ssa.functions[0].return_type);
	var artifact = lower (ssa);
	ssa = null;
	assert (instruction.get () == null && source.get () == null && type.get () == null);
	artifact.verify ();
	assert (artifact.requires_vectors && artifact.requires_binary32);
	var target = new LlvmTargetMachineArtifact ();
	string path = Path.build_filename (Environment.get_tmp_dir (), "astra-dot-%u.o".printf (Random.next_int ()));
	target.configure (artifact);
	target.emit_object (artifact, path);
	assert (FileUtils.test (path, FileTest.IS_REGULAR) && FileUtils.unlink (path) == 0);
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/dot/llvm/all-modes-shapes-extension-and-ordered-adds", operations);
	add ("/dot/llvm/independent-lifetime-and-object", lifetime);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
