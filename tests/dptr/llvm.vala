// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.DataPointers {
private LlvmModuleArtifact lower(SsaProgram ssa) throws GLib.Error {
	var nabi = NativeAbiBuilder.build (ssa);
	return LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
}

private void widths() throws GLib.Error {
	var types = new BuiltinTypes ();
	foreach (string name in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32"}) {
		string one = name == "f32" ? "1.0" : "1";
		string source = "%s f(%s* p,%s value){*p=value;return *p;} %s g(){%s x=%s;return f(&x,x);}".printf (name, name, name, name, name, one);
		var ssa = build (source);
		var artifact = lower (ssa);
		artifact.verify ();
		string text = artifact.dump ();
		string physical = name == "f32" ? "float" : "i%u".printf (((IntegerType) types.resolve (name)).bit_width);
		assert (text.contains ("alloca " + physical) && text.contains ("store " + physical) && text.contains ("load " + physical));
		assert (text.contains ("ptr %p0") && text.contains ("icmp eq ptr %p0, null"));
		assert (text.contains ("call void @llvm.trap()") && text.contains ("unreachable"));
		foreach (string forbidden in new string[] {"getelementptr", "ptrtoint", "inttoptr", "volatile", "atomic", "noalias", "readonly", "nonnull", "fast ", "fadd", "fmul", "fdiv", "fptrunc", "fpext", "sext", "zext", "trunc", "poison", "undef"}) {
			// The continuation block name documents the guard; it is not a
			// nonnull parameter attribute or an optimizer assumption.
			if (forbidden == "nonnull") {
				assert (!text.contains ("ptr nonnull"));
			} else {
				assert (!text.contains (forbidden));
			}
		}
		assert (text.split (" = alloca ").length - 1 == 1);
	}
	string plain = lower (build ("int f(bool c){int x=1;if(c){x=2;}return x;}")).dump ();
	assert (!plain.contains ("alloca") && !plain.contains ("load ") && !plain.contains ("store ") && plain.contains ("phi i32"));
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
	assert (guards > 20 && guarded_inputs >= 4);
	Test.message ("%d null guards; %d phi inputs from final guarded blocks", guards, guarded_inputs);
	foreach (string text in new string[] {"int main(){int* p=null;return *p;}", "int main(){int* p=null;*p=1;return 0;}"}) {
		var artifact = lower (build (text));
		artifact.verify ();
		assert (artifact.dump ().contains ("br i1 true, label %memory"));
	}
}

private void lifetime() throws GLib.Error {
	SsaProgram? ssa = build (read ("basic"));
	var witness = WeakRef (ssa.functions[3].storage[0]);
	var source = WeakRef (ssa.span.file);
	var type = WeakRef (ssa.functions[0].parameters[0].semantic_type);
	var artifact = lower (ssa);
	ssa = null;
	assert (witness.get () == null && source.get () == null && type.get () == null);
	artifact.verify ();
	string directory = DirUtils.make_tmp ("astra-dptr-llvm-XXXXXX");
	var machine = new LlvmTargetMachineArtifact ();
	machine.configure (artifact);
	machine.emit_object (artifact, directory + "/dptr.o");
	assert (FileUtils.test (directory + "/dptr.o", FileTest.IS_REGULAR));
	FileUtils.unlink (directory + "/dptr.o");
	DirUtils.remove (directory);
	foreach (string name in new string[] {"widths", "f32", "integration", "ownership"}) {
		lower (build (read (name))).verify ();
	}
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/dptr/llvm/exact-widths-no-conversions-no-global-allocas", widths);
	add ("/dptr/llvm/null-guards-and-physical-predecessors", guards_and_predecessors);
	add ("/dptr/llvm/stage-lifetime-object-and-integrations", lifetime);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
