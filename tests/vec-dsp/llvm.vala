// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.VectorDsp {
private LlvmModuleArtifact lower(SsaProgram ssa) throws GLib.Error {
	var nabi = NativeAbiBuilder.build (ssa);
	return LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
}

private string operation(string source) throws GLib.Error {
	var ssa = build (source);
	assert (ssa.functions[0].storage.length == 0 && ssa.functions[0].entry.instructions.length == 1 && ssa.functions[0].entry.instructions[0] is SsaDspInstruction);
	string llvm = lower (ssa).dump ();
	foreach (string forbidden in new string[] {"extractelement", "insertelement", "alloca", "load ", "store ", " nsw ", " nuw ", " fast ", " nnan ", " ninf ", " nsz ", " reassoc ", " contract ", " afn ", " arcp "}) {
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
	foreach (string category in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32", "bool"}) {
		var element = types.resolve (category);
		foreach (int lanes in new int[] {1, 2, 4, 8, 16}) {
			var vector = lanes == 1 ? null : types.vector_of (element, lanes);
			if (lanes != 1 && vector == null) {
				continue;
			}
			string source = lanes == 1 ? category : vector.display_name ();
			if (element is IntegerType) {
				foreach (string op in new string[] {"add", "sub"}) {
					string llvm = operation ("%s f(%s a,%s b){return sat_%s(a,b);}".printf (source, source, source, op));
					assert (llvm.contains ("@llvm." + (((IntegerType) element).is_signed ? "s" : "u") + op + ".sat."));
					count++;
				}
			}
			if (vector == null) {
				continue;
			}
			foreach (bool high in new bool[] {false, true}) {
				string llvm = operation ("%s f(%s a,%s b){return interleave_%s(a,b);}".printf (source, source, source, high ? "high" : "low"));
				var mask = new StringBuilder ("<");
				for (int i = 0; i < lanes; i++) {
					if (i > 0) {
						mask.append (", ");
					}
					mask.append_printf ("i32 %d", (high ? lanes / 2 : 0) + i / 2 + (i % 2) * lanes);
				}
				mask.append (">");
				assert (llvm.contains ("shufflevector") && llvm.contains (mask.str));
				foreach (string numeric in new string[] {"fadd", "fsub", "fmul", "fdiv", "fcmp"}) {
					assert (!llvm.contains (numeric));
				}
				count++;
			}
			if (!(element is IntegerType)) {
				continue;
			}
			foreach (string destination in new string[] {"i8", "u8", "i16", "u16", "int", "u32"}) {
				var d = (IntegerType) types.resolve (destination);
				var s = (IntegerType) element;
				bool widen = d.bit_width > s.bit_width;
				if (d.bit_width == s.bit_width) {
					continue;
				}
				var output = types.vector_of (d, widen ? lanes / 2 : lanes * 2);
				if (output == null) {
					continue;
				}
				foreach (string op in widen ? new string[] {"widen_low", "widen_high"} : new string[] {"pack_wrap", "pack_sat"}) {
					string llvm = operation ("%s f(%s a,%s b){return %s(a,%s%s);}".printf (output.display_name (), source, source, op, widen ? "" : "b,", destination));
					assert (llvm.contains ("shufflevector"));
					if (widen) {
						assert (llvm.contains ((s.is_signed ? "sext" : "zext") + " <%d x i%u>".printf (lanes / 2, s.bit_width)));
						var mask = new StringBuilder ("<");
						for (int i = 0; i < lanes / 2; i++) {
							if (i > 0) {
								mask.append (", ");
							}
							mask.append_printf ("i32 %d", (op == "widen_high" ? lanes / 2 : 0) + i);
						}
						mask.append (">");
						assert (llvm.contains (mask.str));
					} else {
						assert (llvm.contains ("trunc <%d x i%u>".printf (lanes, s.bit_width)));
						if (op == "pack_sat") {
							assert (llvm.contains (s.is_signed ? "icmp sgt" : "icmp ugt") && llvm.contains ("select <"));
							if (s.minimum < d.minimum) {
								assert (llvm.contains ("icmp slt"));
							}
						} else {
							assert (!llvm.contains ("icmp") && !llvm.contains ("select "));
						}
					}
					count++;
				}
			}
		}
	}
	Test.message ("%d parameter-driven LLVM DSP operations", count);
}

private void lifetime() throws GLib.Error {
	SsaProgram? ssa = build (read ("values"));
	var instruction = WeakRef (ssa.functions[0].entry.instructions[0]);
	var source = WeakRef (ssa.span.file);
	var type = WeakRef (ssa.functions[6].return_type);
	var artifact = lower (ssa);
	ssa = null;
	assert (instruction.get () == null && source.get () == null && type.get () == null);
	artifact.verify ();
	assert (artifact.requires_vectors && artifact.requires_binary32);
	var target = new LlvmTargetMachineArtifact ();
	string path = Path.build_filename (Environment.get_tmp_dir (), "astra-dsp-%u.o".printf (Random.next_int ()));
	target.configure (artifact);
	target.emit_object (artifact, path);
	assert (FileUtils.test (path, FileTest.IS_REGULAR) && FileUtils.unlink (path) == 0);
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/dsp/llvm/all-primitives-shapes-and-exact-masks", operations);
	add ("/dsp/llvm/independent-lifetime-and-object", lifetime);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
