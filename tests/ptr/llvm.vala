// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Source;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.Pointers {
private LlvmModuleArtifact lower(SsaProgram ssa) throws GLib.Error {
	var nabi = NativeAbiBuilder.build (ssa);
	return LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
}

private void transport() throws GLib.Error {
	int pointer_phis = 0;
	int pointer_comparisons = 0;
	int pointer_nulls = 0;
	foreach (string name in new string[] {"ptr-native", "ptr-null", "ptr-merge", "ptr-cimport", "ptr-cexport", "ptr-roundtrip", "ptr-shortcircuit"}) {
		var artifact = lower (build (fixture (name + ".astra"), declarations (name)));
		artifact.verify ();
		string dump = artifact.dump ();
		foreach (string forbidden in new string[] {"ptrtoint", "inttoptr", "nonnull", "noalias", "dereferenceable", "align ", "nocapture", "readonly", "writeonly", "alloca", "load ", "store ", "@free", "@malloc"}) {
			assert (!dump.contains (forbidden));
		}
		assert (dump.contains ("declare ptr @astra_test_handle_a()") && !dump.contains ("@handle_a("));
		foreach (var imported in artifact.c_imports) {
			assert (CApi.get_linkage (imported.value) == CApi.Linkage.EXTERNAL && CApi.function_call_conv (imported.value) == CApi.CallConv.C);
			assert ((void*) CApi.first_block (imported.value) == null);
			foreach (var call in imported.calls) {
				assert (CApi.instruction_call_conv ((CApi.ValueRef) call) == CApi.CallConv.C && (void*) CApi.called_value ((CApi.ValueRef) call) == (void*) imported.value);
			}
		}
		foreach (var exported in artifact.c_exports) {
			assert (CApi.get_linkage (exported.value) == CApi.Linkage.EXTERNAL && CApi.function_call_conv (exported.value) == CApi.CallConv.C);
			assert (CApi.type_kind (CApi.return_type (CApi.global_value_type (exported.value))) == CApi.TypeKind.POINTER);
			assert (CApi.get_linkage (exported.native_target) == CApi.Linkage.INTERNAL && CApi.function_call_conv (exported.native_target) == CApi.CallConv.FAST);
			assert (CApi.instruction_call_conv (exported.call) == CApi.CallConv.FAST);
			assert ((void*) CApi.operand (exported.call, 0) == (void*) CApi.get_param (exported.value, 0));
		}
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			size_t length;
			if (CApi.value_name (function, out length).has_prefix ("astra.fn.")) {
				assert (CApi.get_linkage (function) == CApi.Linkage.INTERNAL && CApi.function_call_conv (function) == CApi.CallConv.FAST);
			}
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) == CApi.Opcode.PHI && CApi.type_kind (CApi.type_of (instruction)) == CApi.TypeKind.POINTER) {
						pointer_phis++;
						assert (CApi.incoming_count (instruction) == 2);
						for (uint i = 0; i < CApi.incoming_count (instruction); i++) {
							assert (CApi.type_kind (CApi.type_of (CApi.incoming_value (instruction, i))) == CApi.TypeKind.POINTER);
							var terminator = CApi.block_terminator (CApi.incoming_block (instruction, i));
							bool reaches = false;
							for (uint j = 0; j < CApi.successor_count (terminator); j++) {
								reaches = reaches || (void*) CApi.successor (terminator, j) == (void*) block;
							}
							assert (reaches);
						}
					}
					if (CApi.opcode (instruction) == CApi.Opcode.ICMP && CApi.type_kind (CApi.type_of (CApi.operand (instruction, 0))) == CApi.TypeKind.POINTER) {
						pointer_comparisons++;
						assert (CApi.predicate (instruction) == CApi.IntPredicate.EQ || CApi.predicate (instruction) == CApi.IntPredicate.NE);
					}
					for (uint o = 0; o < CApi.operand_count (instruction); o++) {
						if ((void*) CApi.is_constant_pointer_null (CApi.operand (instruction, o)) != null) {
							pointer_nulls++;
						}
					}
				}
			}
		}
	}
	assert (pointer_phis >= 3 && pointer_comparisons >= 10 && pointer_nulls >= 5);
}

private void differential() throws GLib.Error {
	string source = "void* identity(void* p) { return physical(p); }";
	string declaration = "void* physical(void* p);";
	assert (lower (build (source, declaration)).dump () == lower (build (source, declaration, true)).dump ());
	string direct = lower (build (source, declaration, true)).dump ();
	string friendly = source.replace ("physical", "friendly");
	foreach (string metadata in new string[] {"cname = \"physical\"", "cname = \"physical\", cheader_filename = \"nonexistent/pointer_api.h\""}) {
		var ssa = build (friendly, "[CCode (" + metadata + ")] void /* opaque */ * friendly(void * p);");
		assert (ssa.c_functions[0].name == "friendly" && ssa.c_functions[0].external_symbol == "physical");
		assert (lower (ssa).dump () == direct);
	}
}

private SsaEdge edge(SsaBlock target, SsaValue value) {
	var arguments = new GenericArray<SsaValue> ();
	arguments.add (value);
	return new SsaEdge (target, arguments);
}

private void parallel_edges() throws GLib.Error {
	for (int divide = 0; divide < 2; divide++) {
		var types = new BuiltinTypes ();
		var span = SourceSpan (new SourceFile.from_text ("parallel.astra", ""), 0, 0);
		var parameters = new GenericArray<SsaFunctionParameter> ();
		parameters.add (new SsaFunctionParameter (span, span, "c", types.bool_type, 0));
		parameters.add (new SsaFunctionParameter (span, span, "p", types.raw_pointer_type, 1));
		parameters.add (new SsaFunctionParameter (span, span, "n", types.int_type, 2));
		var entry = new SsaBlock (span, 0, 0);
		var join = new SsaBlock (span, 1, 1);
		join.parameters.add (new SsaBlockParameter (span, span, "p", types.raw_pointer_type, 3, 0));
		if (divide == 1) {
			entry.instructions.add (new SsaBinaryInstruction (span, types.int_type, 4, BinaryOperator.DIVIDE, parameters[2], parameters[2]));
		}
		entry.complete (new SsaConditionalBranch (span, parameters[0], edge (join, parameters[1]), edge (join, new SsaNullPointerConstant (span, types.raw_pointer_type))));
		join.complete (new SsaReturn (span, join.parameters[0]));
		var blocks = new GenericArray<SsaBlock> ();
		blocks.add (entry);
		blocks.add (join);
		var functions = new GenericArray<SsaFunction> ();
		functions.add (new SsaFunction (span, span, "f", types.raw_pointer_type, 0, parameters, blocks, entry));
		var artifact = lower (new SsaProgram (span, functions));
		var function = CApi.first_function (artifact.module);
		var physical_join = CApi.next_block (CApi.first_block (function));
		var phi = CApi.first_instruction (physical_join);
		assert (CApi.opcode (phi) == CApi.Opcode.PHI && CApi.type_kind (CApi.type_of (phi)) == CApi.TypeKind.POINTER && CApi.incoming_count (phi) == 2);
		assert ((void*) CApi.incoming_value (phi, 0) == (void*) CApi.get_param (function, 1));
		assert ((void*) CApi.is_constant_pointer_null (CApi.incoming_value (phi, 1)) != null);
		assert ((void*) CApi.incoming_block (phi, 0) != (void*) CApi.incoming_block (phi, 1));
		for (uint i = 0; i < 2; i++) {
			var incoming = CApi.incoming_block (phi, i);
			assert (CApi.block_name (incoming) == (i == 0 ? "b0.edge.true" : "b0.edge.false"));
			assert ((void*) CApi.successor (CApi.block_terminator (incoming), 0) == (void*) physical_join);
		}
		artifact.verify ();
		assert (artifact.dump ().contains ("call void @llvm.trap()") == (divide == 1));
	}
}

private void lifetime() throws GLib.Error {
	SsaProgram? ssa = build (fixture ("ptr-roundtrip.astra"), declarations ("ptr-roundtrip"));
	var ssa_ref = WeakRef (ssa);
	var pointer_ref = WeakRef (ssa.functions[0].return_type);
	var source_ref = WeakRef (ssa.c_functions[0].span.file);
	var metadata_ref = WeakRef (ssa.c_functions[0].metadata);
	NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
	CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
	var nabi_ref = WeakRef (nabi);
	var cabi_ref = WeakRef (cabi);
	var artifact = LlvmLowering.lower (ssa, nabi, cabi);
	string dump = artifact.dump ();
	ssa = null;
	nabi = null;
	cabi = null;
	assert (ssa_ref.get () == null && pointer_ref.get () == null && source_ref.get () == null && metadata_ref.get () == null && nabi_ref.get () == null && cabi_ref.get () == null);
	artifact.verify ();
	assert (artifact.dump () == dump && dump.contains ("define ptr @astra_export_echo_ptr(ptr"));
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/ptr-llvm/transport-null-icmp-phi-conventions", transport);
	add ("/ptr-llvm/source-vapi-alias-header-differential", differential);
	add ("/ptr-llvm/artifact-lifetime", lifetime);
	add ("/ptr-llvm/parallel-edges-after-trap-split", parallel_edges);
	int status = Test.run ();
	cases = null;
	return status;
}

}
