// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.VectorMemory {
private LlvmModuleArtifact lower(SsaProgram ssa) throws GLib.Error {
	var nabi = NativeAbiBuilder.build (ssa);
	return LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
}

private void widths() throws GLib.Error {
	foreach (string name in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32"}) {
		var types = new BuiltinTypes ();
		for (int n = 2; n <= 16; n *= 2) {
			var vector = types.vector_of (types.resolve (name), n);
			if (vector == null) {
				continue;
			}
			string type = vector.display_name ();
			string one = name == "f32" ? "1.0" : "1";
			var artifact = lower (build ("%s f(%s* p,%s value){*p=value;return *p;} %s g(){%s x=splat(%s,%d);return f(&x,x);}".printf (type, type, type, type, type, one, n)));
			artifact.verify ();
			assert (artifact.requires_vectors && artifact.requires_binary32 == (name == "f32"));
			var machine = new LlvmTargetMachineArtifact ();
			machine.configure (artifact);
			string text = artifact.dump ();
			string physical = "<%d x %s>".printf (n, name == "f32" ? "float" : "i%u".printf (((IntegerType) types.resolve (name)).bit_width));
			assert (text.contains ("alloca " + physical) && text.contains ("store " + physical) && text.contains ("load " + physical));
			assert (text.contains ("ptr %p0") && text.contains ("icmp eq ptr %p0, null"));
			foreach (string forbidden in new string[] {"getelementptr", "ptrtoint", "inttoptr", "volatile", "atomic", "noalias", "readonly", "fast ", "fadd", "fmul", "fdiv", "fptrunc", "fpext", "sext", "zext", "trunc", "poison", "undef", "extractelement"}) {
				assert (!text.contains (forbidden));
			}
			assert (text.split (" = alloca ").length - 1 == 1);
			Test.message ("Vector object %s", type);
			audit_alignment (artifact);
		}
	}
	string plain = lower (build ("f32<4> f(bool c){f32<4> x=splat(1.0,4);if(c){x=splat(2.0,4);}return x;}")).dump ();
	assert (!plain.contains ("alloca") && !plain.contains ("load ") && !plain.contains ("store ") && plain.contains ("phi <4 x float>"));
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

private void guards_and_predecessors() throws GLib.Error {
	int guarded_inputs = 0;
	int guards = 0;
	foreach (string name in new string[] {"loop", "null", "alias"}) {
		var artifact = lower (build (read (name)));
		artifact.verify ();
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) != CApi.Opcode.PHI) {
						continue;
					}
					for (uint i = 0; i < CApi.incoming_count (instruction); i++) {
						var predecessor = CApi.incoming_block (instruction, i);
						var terminator = CApi.block_terminator (predecessor);
						bool reaches = false;
						for (uint j = 0; j < CApi.successor_count (terminator); j++) {
							reaches = reaches || (void*) CApi.successor (terminator, j) == (void*) block;
						}
						assert (reaches);
						if (CApi.block_name (predecessor).has_suffix (".nonnull")) {
							guarded_inputs++;
						}
					}
				}
				if (CApi.block_name (block).has_suffix (".nonnull")) {
					guards++;
				}
			}
		}
	}
	assert (guards > 10 && guarded_inputs >= 4);
	Test.message ("%d null guards; %d phi inputs from final guarded blocks", guards, guarded_inputs);
	foreach (string text in new string[] {"int main(){i16<8>* p=null;i16<8> v=*p;return 0;}", "int main(){f32<4>* p=null;*p=splat(1.0,4);return 0;}"}) {
		var artifact = lower (build (text));
		artifact.verify ();
		assert (artifact.dump ().contains ("br i1 true, label %memory"));
	}
}

private void lifetime() throws GLib.Error {
	SsaProgram? ssa = build (read ("basic"));
	var witness = WeakRef (ssa.functions[2].storage[0]);
	var source = WeakRef (ssa.span.file);
	var type = WeakRef (ssa.functions[0].parameters[0].semantic_type);
	var artifact = lower (ssa);
	ssa = null;
	assert (witness.get () == null && source.get () == null && type.get () == null);
	artifact.verify ();
	string directory = DirUtils.make_tmp ("astra-vecmem-llvm-XXXXXX");
	var machine = new LlvmTargetMachineArtifact ();
	machine.configure (artifact);
	machine.emit_object (artifact, directory + "/vecmem.o");
	assert (FileUtils.test (directory + "/vecmem.o", FileTest.IS_REGULAR));
	FileUtils.unlink (directory + "/vecmem.o");
	DirUtils.remove (directory);
	foreach (string name in new string[] {"widths", "f32", "dsp", "dot", "ownership"}) {
		lower (build (read (name))).verify ();
	}
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/vecmem/llvm/exact-widths-no-conversions-no-global-allocas", widths);
	add ("/vecmem/llvm/null-guards-and-physical-predecessors", guards_and_predecessors);
	add ("/vecmem/llvm/stage-lifetime-object-and-integrations", lifetime);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
