// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.Bit {
private LlvmModuleArtifact lower(SsaProgram ssa) throws GLib.Error {
	var nabi = NativeAbiBuilder.build (ssa);
	return LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
}

private string ir(string source) throws GLib.Error {
	var artifact = lower (build (source));
	artifact.verify ();
	string text = artifact.dump ();
	assert (!Regex.match_simple ("\\b(?:shl|ashr|lshr) (?:nsw|nuw|exact)\\b|\\b(?:poison|undef)\\b", text));
	return text;
}

private void matrix() throws GLib.Error {
	var types = new BuiltinTypes ();
	int signatures = 0;
	foreach (string name in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "bool"}) {
		var element = types.resolve (name) as IntegerType;
		foreach (int lanes in new int[] {1, 2, 4, 8, 16}) {
			if (lanes != 1 && types.vector_of (types.resolve (name), lanes) == null) {
				continue;
			}
			string type = name + (lanes == 1 ? "" : "<%d>".printf (lanes));
			string physical = "i%u".printf (element == null ? 1 : element.bit_width);
			if (lanes != 1) {
				physical = "<%d x %s>".printf (lanes, physical);
			}
			string[] ops = {
				"&", "|", "^"
			};
			string[] instructions = {
				"and", "or", "xor"
			};
			for (int i = 0; i < 3; i++) {
				string text = ir ("%s f(%s a,%s b){return a%s b;}".printf (type, type, type, ops[i]));
				assert (text.contains (instructions[i] + " " + physical) && !text.contains ("br "));
				signatures++;
			}
			string not_ir = ir ("%s f(%s a){return %sa;}".printf (type, type, element == null ? "!" : "~"));
			assert (not_ir.contains ("xor " + physical));
			if (element == null) {
				continue;
			}
			foreach (string count in new string[] {"i8", "u8", "i16", "u16", "int", "u32"}) {
				var c = (IntegerType) types.resolve (count);
				foreach (string op in new string[] {"<<", ">>"}) {
					string text = ir ("%s f(%s a,%s c){return a%s c;}".printf (type, type, count, op));
					string opcode = op == "<<" ? "shl" : element.is_signed ? "ashr" : "lshr";
					assert (text.contains (opcode + " " + physical));
					assert (text.contains ((c.is_signed ? "icmp sge i" : "icmp uge i") + c.bit_width.to_string ()) && text.contains ("icmp slt") == c.is_signed);
					assert (text.index_of ("call void @llvm.trap") < text.index_of (opcode + " " + physical));
					assert (text.contains ("shufflevector") == (lanes != 1));
					assert (text.contains ("trunc") == (c.bit_width > element.bit_width) && text.contains ("zext") == (c.bit_width < element.bit_width));
					signatures++;
				}
			}
			foreach (int c in new int[] {0, (int) element.bit_width - 1}) {
				string text = ir ("%s f(%s a){return a>>%d;}".printf (type, type, c));
				assert (!text.contains ("llvm.trap") && !text.contains ("br "));
			}
		}
	}
	Test.message ("%d parameter-driven bit/shift LLVM signatures", signatures);
	string impossible = ir ("int main(){u8 a=1;int c=8;return (a<<c) as int;}");
	assert (impossible.contains ("llvm.trap") && !impossible.contains ("shl"));
}

private void lifetime() throws GLib.Error {
	SsaProgram? ssa = build (read ("values"));
	var witness = WeakRef (ssa.functions[0].entry.instructions[0]);
	var source = WeakRef (ssa.span.file);
	var type = WeakRef (ssa.functions[0].return_type);
	var artifact = lower (ssa);
	ssa = null;
	assert (witness.get () == null && source.get () == null && type.get () == null);
	artifact.verify ();
	string directory = DirUtils.make_tmp ("astra-bit-llvm-XXXXXX");
	var machine = new LlvmTargetMachineArtifact ();
	machine.configure (artifact);
	machine.emit_object (artifact, directory + "/bit.o");
	assert (FileUtils.test (directory + "/bit.o", FileTest.IS_REGULAR));
	FileUtils.unlink (directory + "/bit.o");
	DirUtils.remove (directory);
	foreach (string name in new string[] {"loop", "shift-trap", "ownership", "integration"}) {
		ir (read (name));
	}
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/bit/llvm/bit-count-normalization-and-poison-matrix", matrix);
	add ("/bit/llvm/lifetime-object-and-guarded-phis", lifetime);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
