// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.Arrays {
private LlvmModuleArtifact lower(SsaProgram ssa) throws GLib.Error {
	var nabi = NativeAbiBuilder.build (ssa);
	return LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
}

private void widths() throws GLib.Error {
	foreach (string name in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32"}) {
		var types = new BuiltinTypes ();
		foreach (int n in new int[] {0, 2, 4, 8, 16}) {
			if (n != 0 && types.vector_of (types.resolve (name), n) == null) {
				continue;
			}
			string type = n == 0 ? name : "%s<%d>".printf (name, n);
			var artifact = lower (build ("%s f(%s v,u32 i){%s[4] a={v,v,v,v};a[i]=v;return a[i];}".printf (type, type, type)));
			artifact.verify ();
			var machine = new LlvmTargetMachineArtifact ();
			machine.configure (artifact);
			string text = artifact.dump ();
			string physical = name == "f32" ? "float" : "i%u".printf (((IntegerType) types.resolve (name)).bit_width);
			if (n != 0) {
				physical = "<%d x %s>".printf (n, physical);
			}
			assert (text.contains ("alloca [4 x " + physical + "]") && text.contains ("store " + physical) && text.contains ("load " + physical));
			assert (text.contains ("getelementptr [4 x " + physical + "]") && text.contains ("icmp uge i32 %p1, 4") && text.contains ("zext i32"));
			foreach (string forbidden in new string[] {"getelementptr inbounds", "ptrtoint", "inttoptr", "volatile", "atomic", "noalias", "fast ", "poison", "undef", "extractelement"}) {
				assert (!text.contains (forbidden));
			}
			assert (text.split (" = alloca ").length - 1 == 1);
			audit_alignment (artifact);
		}
	}
	var constant = lower (build (read ("basic"))).dump ();
	assert (!constant.contains ("llvm.trap") && !constant.contains ("bounds"));
}

private void audit_alignment(LlvmModuleArtifact artifact) {
	var layout = MemoryCApi.module_data_layout (artifact.module);
	for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				CApi.TypeRef type;
				if ((void*) MemoryCApi.is_alloca (instruction) != null) {
					type = MemoryCApi.allocated_type (instruction);
				} else if ((void*) MemoryCApi.is_load (instruction) != null) {
					type = CApi.type_of (instruction);
				} else if ((void*) MemoryCApi.is_store (instruction) != null) {
					type = CApi.type_of (CApi.operand (instruction, 0));
				} else {
					continue;
				}
				uint actual = MemoryCApi.alignment (instruction);
				uint guaranteed = MemoryCApi.abi_alignment (layout, type);
				assert (actual == guaranteed);
				Test.message ("LLVM memory alignment %u equals target ABI alignment %u", actual, guaranteed);
			}
		}
	}
}

private void predecessors() throws GLib.Error {
	int inputs = 0;
	int guarded_inputs = 0;
	var artifact = lower (build (read ("loop")));
	artifact.verify ();
	for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.PHI) {
					continue;
				}
				for (uint i = 0; i < CApi.incoming_count (instruction); i++) {
					inputs++;
					var predecessor = CApi.incoming_block (instruction, i);
					var terminator = CApi.block_terminator (predecessor);
					bool reaches = false;
					for (uint j = 0; j < CApi.successor_count (terminator); j++) {
						reaches = reaches || (void*) CApi.successor (terminator, j) == (void*) block;
					}
					assert (reaches);
					if (CApi.block_name (predecessor).has_suffix (".valid")) {
						guarded_inputs++;
					}
				}
			}
		}
	}
	assert (inputs > 5 && guarded_inputs >= 3);
	Test.message ("%d phi inputs, %d from final bounds continuations", inputs, guarded_inputs);
}

private void lifetime() throws GLib.Error {
	SsaProgram? ssa = build (read ("vector"));
	var witness = WeakRef (ssa.functions[0].storage[0]);
	var type = WeakRef (ssa.functions[0].storage[0].semantic_type);
	var source = WeakRef (ssa.span.file);
	var artifact = lower (ssa);
	ssa = null;
	assert (witness.get () == null && type.get () == null && source.get () == null);
	artifact.verify ();
	string directory = DirUtils.make_tmp ("astra-array-object-XXXXXX");
	var machine = new LlvmTargetMachineArtifact ();
	machine.configure (artifact);
	machine.emit_object (artifact, directory + "/array.o");
	assert (FileUtils.test (directory + "/array.o", FileTest.IS_REGULAR));
	FileUtils.unlink (directory + "/array.o");
	DirUtils.remove (directory);
	foreach (string name in new string[] {"index", "f32", "dsp", "ownership"}) {
		lower (build (read (name))).verify ();
	}
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/array/llvm/all-shapes-plain-gep-and-target-alignment", widths);
	add ("/array/llvm/physical-phi-predecessors", predecessors);
	add ("/array/llvm/lifetime-object-and-integrations", lifetime);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
