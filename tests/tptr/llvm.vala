// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.TypedPointers {
private LlvmModuleArtifact lower(SsaProgram ssa) throws GLib.Error {
	var nabi = NativeAbiBuilder.build (ssa);
	return LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
}

private void materialization() throws GLib.Error {
	foreach (string name in new string[] {"tptr-basic", "tptr-alias", "tptr-null", "tptr-recursive", "tptr-loop", "tptr-mixed-storage", "tptr-order"}) {
		var ssa = build (fixture (name));
		var artifact = lower (ssa);
		artifact.verify ();
		string dump = artifact.dump ();
		assert (dump.contains ("%astra.struct.0 = type {"));
		assert (dump.contains ("getelementptr") && dump.contains ("alloca %astra.struct.0"));
		assert (dump.contains ("load i32") && dump.contains ("store i32"));
		int storage = 0;
		foreach (var function in ssa.functions) {
			storage += (int) function.storage.length;
		}
		assert (dump.split (" = alloca ").length - 1 == storage);
		foreach (string forbidden in new string[] {"ptrtoint", "inttoptr", "memcpy", "memmove", "extractvalue", "insertvalue", "load %astra.struct", "store %astra.struct", "undef", "poison"}) {
			assert (!dump.contains (forbidden));
		}
		foreach (string line in dump.split ("\n")) {
			if (!line.has_prefix ("define ")) {
				continue;
			}
			foreach (string attribute in new string[] {"nonnull", "noalias", "nocapture", "readonly", "writeonly", "dereferenceable", "align "}) {
				assert (!line.contains (attribute));
			}
		}
	}
	string mixed = lower (build (fixture ("tptr-null"))).dump ();
	assert (mixed.contains ("type { i32, i1, ptr }"));
	assert (mixed.contains ("load i1") && mixed.contains ("store i1") && mixed.contains ("load ptr") && mixed.contains ("store ptr"));
	assert (mixed.contains ("i32 0, i32 2"));
}

private void guards_and_predecessors() throws GLib.Error {
	int split_incoming = 0;
	int guards = 0;
	foreach (string name in new string[] {"tptr-loop", "tptr-null"}) {
		var artifact = lower (build (fixture (name)));
		string dump = artifact.dump ();
		assert (dump.contains ("call void @llvm.trap()") && dump.contains ("unreachable"));
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) == CApi.Opcode.PHI) {
						for (uint i = 0; i < CApi.incoming_count (instruction); i++) {
							var predecessor = CApi.incoming_block (instruction, i);
							var terminator = CApi.block_terminator (predecessor);
							bool reaches = false;
							for (uint j = 0; j < CApi.successor_count (terminator); j++) {
								reaches = reaches || (void*) CApi.successor (terminator, j) == (void*) block;
							}
							assert (reaches);
							if (CApi.block_name (predecessor).has_suffix (".nonnull")) {
								split_incoming++;
							}
						}
					}
				}
				if (CApi.block_name (block).has_suffix (".nonnull")) {
					guards++;
					assert (CApi.opcode (CApi.first_instruction (block)) == CApi.Opcode.GEP);
				}
			}
		}
	}
	assert (guards > 10 && split_incoming >= 4);
	Test.message ("null guards=%d; phi inputs from actual post-null-check blocks=%d", guards, split_incoming);
}

private void null_store_order() throws GLib.Error {
	var artifact = lower (build ("struct P { int x; } int effect() { return 42; } void write(P* p) { p->x = effect(); } int main() { write(null); return 0; }"));
	string dump = artifact.dump ();
	int call = dump.index_of ("call fastcc i32 @astra.fn.0()");
	int guard = dump.index_of ("icmp eq ptr %p0, null");
	int trap = dump.index_of ("call void @llvm.trap()");
	int gep = dump.index_of ("getelementptr");
	int store = dump.index_of ("store i32");
	assert (call >= 0 && guard > call && trap > guard && gep > trap && store > gep);
	assert (dump.contains ("call fastcc void @astra.fn.1(ptr null)"));
	artifact.verify ();
}

private void no_materialization() throws GLib.Error {
	string[] programs = {
		"struct P { int x; } int f(bool c) { P p = { x = 1 }; if (c) { p.x = 2; } return p.x; }",
		"struct P { int x; } bool f(P* p, P* q) { P* local = null; local = p; return local == q; }"
	};
	foreach (string source in programs) {
		string dump = lower (build (source)).dump ();
		foreach (string forbidden in new string[] {" = type ", "alloca", "getelementptr", "load ", "store "}) {
			assert (!dump.contains (forbidden));
		}
	}
	string plain = "int f(bool c) { int x = 1; if (c) { x = 2; } return x; }";
	assert (lower (build (programs[0])).dump () == lower (build (plain)).dump ());
}

private void llvm_lifetime() throws GLib.Error {
	SsaProgram? ssa = build (fixture ("tptr-alias"));
	var program_ref = WeakRef (ssa);
	var structure_ref = WeakRef (ssa.structs[0]);
	var storage_ref = WeakRef (ssa.functions[3].storage[0]);
	var pointer_ref = WeakRef (ssa.functions[0].parameters[0].semantic_type);
	var source_ref = WeakRef (ssa.span.file);
	var artifact = lower (ssa);
	ssa = null;
	assert (program_ref.get () == null && structure_ref.get () == null && storage_ref.get () == null);
	assert (pointer_ref.get () == null && source_ref.get () == null);
	artifact.verify ();
	assert (artifact.dump ().contains ("alloca %astra.struct.0"));
}

private int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/tptr/llvm/materialization", materialization);
	add ("/tptr/llvm/guards-predecessors", guards_and_predecessors);
	add ("/tptr/llvm/null-store-order", null_store_order);
	add ("/tptr/llvm/no-materialization", no_materialization);
	add ("/tptr/llvm/lifetime", llvm_lifetime);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
