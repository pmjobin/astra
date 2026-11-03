// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.Structs {
private LlvmModuleArtifact lower(SsaProgram ssa) throws GLib.Error {
	var nabi = NativeAbiBuilder.build (ssa);
	return LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
}

private void scalarized_modules() throws GLib.Error {
	int integer_phis = 0;
	int boolean_phis = 0;
	int pointer_phis = 0;
	foreach (string name in new string[] {"struct-basic", "struct-order", "struct-branch", "struct-loop", "struct-pointer", "struct-scope", "struct-trap"}) {
		var artifact = lower (build (fixture (name)));
		artifact.verify ();
		string dump = artifact.dump ();
		foreach (string forbidden in new string[] {" = type ", "extractvalue", "insertvalue", "alloca", "getelementptr", "load ", "store ", "undef", "poison", "ptrtoint", "inttoptr"}) {
			assert (!dump.contains (forbidden));
		}
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					var type = CApi.type_of (instruction);
					var kind = CApi.type_kind (type);
					assert (kind == CApi.TypeKind.INTEGER || kind == CApi.TypeKind.POINTER || kind == CApi.TypeKind.VOID);
					if (CApi.opcode (instruction) != CApi.Opcode.PHI) {
						continue;
					}
					if (kind == CApi.TypeKind.POINTER) {
						pointer_phis++;
					} else if (CApi.int_width (type) == 1) {
						boolean_phis++;
					} else {
						assert (CApi.int_width (type) == 32);
						integer_phis++;
					}
					assert (CApi.incoming_count (instruction) >= 2);
					for (uint i = 0; i < CApi.incoming_count (instruction); i++) {
						assert ((void*) CApi.type_of (CApi.incoming_value (instruction, i)) == (void*) type);
						var terminator = CApi.block_terminator (CApi.incoming_block (instruction, i));
						bool reaches = false;
						for (uint j = 0; j < CApi.successor_count (terminator); j++) {
							reaches = reaches || (void*) CApi.successor (terminator, j) == (void*) block;
						}
						assert (reaches);
					}
				}
			}
		}
	}
	assert (integer_phis > 0 && boolean_phis > 0 && pointer_phis > 0);
	Test.message ("ordinary field/workload phis: i32=%d i1=%d ptr=%d", integer_phis, boolean_phis, pointer_phis);
}

private void differential() throws GLib.Error {
	string struct_text = "struct P { int x; int y; } int sum(int a, int b) { P p = { x = a, y = b }; return p.x + p.y; }";
	string scalar_text = "int sum(int a, int b) { int x = a; int y = b; return x + y; }";
	assert (lower (build (struct_text)).dump () == lower (build (scalar_text)).dump ());
	string branch_struct = "struct P { int x; int y; } int f(bool c) { P p = { y = 10, x = 0 }; if (c) { p.x = 1; } else { p.x = 2; } return p.x + p.y; }";
	string branch_scalar = "int f(bool c) { int y = 10; int x = 0; if (c) { x = 1; } else { x = 2; } return x + y; }";
	assert (lower (build (branch_struct)).dump () == lower (build (branch_scalar)).dump ());
}

private void trap_order() throws GLib.Error {
	var artifact = lower (build (fixture ("struct-trap")));
	string dump = artifact.dump ();
	int first = dump.index_of ("call i32 @astra_test_record(i32 2)");
	int divide = dump.index_of ("sdiv i32");
	int later = dump.index_of ("call i32 @astra_test_record(i32 1)");
	assert (first >= 0 && divide > first && later > divide);
	assert (dump.contains ("call void @llvm.trap()") && dump.contains ("unreachable"));
	artifact.verify ();
}

private void llvm_lifetime() throws GLib.Error {
	SsaProgram? ssa = build (fixture ("struct-pointer"));
	var ssa_ref = WeakRef (ssa);
	var pointer_ref = WeakRef (ssa.c_functions[0].return_type);
	var source_ref = WeakRef (ssa.span.file);
	NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
	CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
	var artifact = LlvmLowering.lower (ssa, nabi, cabi);
	ssa = null;
	nabi = null;
	cabi = null;
	assert (ssa_ref.get () == null && pointer_ref.get () == null && source_ref.get () == null);
	artifact.verify ();
	assert (artifact.dump ().contains ("phi ptr"));
}

private int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/struct/llvm/scalarized-modules", scalarized_modules);
	add ("/struct/llvm/differential", differential);
	add ("/struct/llvm/trap-order", trap_order);
	add ("/struct/llvm/lifetime", llvm_lifetime);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
