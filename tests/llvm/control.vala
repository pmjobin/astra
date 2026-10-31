// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.Llvm {
private void choose() throws GLib.Error {
	var artifact = lower (fixture ("tests/branch/fixtures/choose.astra"));
	var f = functions (artifact)[0];
	var bs = blocks (f);
	var phis = operations (f, CApi.Opcode.PHI);
	assert (bs.length == 4 && phis.length == 1 && CApi.incoming_count (phis[0]) == 2);
	var phi = phis[0];
	width (CApi.type_of (phi), 32);
	assert ((void*) CApi.first_instruction (bs[3]) == (void*) phi && (void*) returned (f) == (void*) phi);
	for (uint p = 0; p < 2; p++) {
		assert ((void*) CApi.incoming_value (phi, p) == (void*) CApi.get_param (f, p + 1));
		assert ((void*) CApi.incoming_block (phi, p) == (void*) bs[p + 1]);
		assert ((void*) CApi.successor (CApi.block_terminator (bs[p + 1]), 0) == (void*) bs[3]);
	}
}

private void multiple_and_bool() throws GLib.Error {
	var artifact = lower (fixture ("tests/ssa/fixtures/multiple.astra"));
	var f = functions (artifact)[0];
	var phis = operations (f, CApi.Opcode.PHI);
	assert (phis.length == 2 && (void*) CApi.next_instruction (phis[0]) == (void*) phis[1]);
	for (uint p = 0; p < 2; p++) {
		width (CApi.type_of (phis[p]), 32);
		assert (CApi.incoming_count (phis[p]) == 2);
		assert ((void*) CApi.incoming_value (phis[p], 0) == (void*) CApi.get_param (f, p + 1));
		assert ((void*) CApi.incoming_value (phis[p], 1) == (void*) CApi.get_param (f, 2 - p));
	}
	var boolean = lower ("bool f(bool c) { bool x = false; if (c) { x = true; } else { x = false; } return x; }");
	var phi = operations (functions (boolean)[0], CApi.Opcode.PHI)[0];
	width (CApi.type_of (phi), 1);
	assert (CApi.constant_signed (CApi.incoming_value (phi, 0)) != 0 && CApi.constant_signed (CApi.incoming_value (phi, 1)) == 0);
	var nested = lower (fixture ("tests/branch/fixtures/nested.astra"));
	assert (operations (functions (nested)[0], CApi.Opcode.PHI).length == 2);
}

private void choose_call() throws GLib.Error {
	var artifact = lower (fixture ("tests/call/fixtures/choose-call.astra"));
	var fs = functions (artifact);
	var cs = operations (fs[1], CApi.Opcode.CALL);
	var ps = operations (fs[1], CApi.Opcode.PHI);
	assert (cs.length == 2 && ps.length == 1 && CApi.incoming_count (ps[0]) == 2);
	assert ((void*) returned (fs[1]) == (void*) ps[0]);
	for (uint c = 0; c < 2; c++) {
		assert ((void*) CApi.called_value (cs[c]) == (void*) fs[0] && CApi.instruction_call_conv (cs[c]) == CApi.CallConv.FAST);
		assert ((void*) CApi.incoming_value (ps[0], c) == (void*) cs[c]);
		assert ((void*) CApi.incoming_block (ps[0], c) == (void*) CApi.instruction_parent (cs[c]));
	}
}

private SsaEdge edge(SsaBlock target, SsaValue[] values) {
	var arguments = new GenericArray<SsaValue> ();
	foreach (var value in values) {
		arguments.add (value);
	}
	return new SsaEdge (target, arguments);
}

private void parallel_edges(bool divide) throws GLib.Error {
	var types = new BuiltinTypes ();
	var file = new SourceFile.from_text ("synthetic.astra", "");
	var span = SourceSpan (file, 0, 0);
	var parameters = new GenericArray<SsaFunctionParameter> ();
	parameters.add (new SsaFunctionParameter (span, span, "c", types.bool_type, 0));
	parameters.add (new SsaFunctionParameter (span, span, "a", types.int_type, 1));
	parameters.add (new SsaFunctionParameter (span, span, "b", types.int_type, 2));
	var entry = new SsaBlock (span, 0, 0);
	var join = new SsaBlock (span, 1, 1);
	join.parameters.add (new SsaBlockParameter (span, span, "x", types.int_type, 3, 0));
	SsaValue first = parameters[1];
	if (divide) {
		var division = new SsaBinaryInstruction (span, types.int_type, 4, BinaryOperator.DIVIDE, parameters[1], parameters[2]);
		entry.instructions.add (division);
		first = division.result;
	}
	entry.complete (new SsaConditionalBranch (span, parameters[0], edge (join, {first}), edge (join, {parameters[2]})));
	join.complete (new SsaReturn (span, join.parameters[0]));
	var source_blocks = new GenericArray<SsaBlock> ();
	source_blocks.add (entry);
	source_blocks.add (join);
	var source_functions = new GenericArray<SsaFunction> ();
	source_functions.add (new SsaFunction (span, span, "f", types.int_type, 0, parameters, source_blocks, entry));
	var ssa = new SsaProgram (span, source_functions);
	SsaVerifier.verify (ssa);
	var artifact = LlvmLowering.lower (ssa, NativeAbiBuilder.build (ssa), Astra.CAbi.CAbiBuilder.build (ssa, Astra.NativeAbi.NativeAbiBuilder.build (ssa)));
	var f = functions (artifact)[0];
	var physical = blocks (f);
	assert (physical.length == (divide ? 9 : 4));
	var phi = CApi.first_instruction (physical[1]);
	assert (CApi.opcode (phi) == CApi.Opcode.PHI && CApi.incoming_count (phi) == 2);
	var true_block = CApi.incoming_block (phi, 0);
	var false_block = CApi.incoming_block (phi, 1);
	assert ((void*) true_block != (void*) false_block);
	assert (CApi.block_name (true_block) == "b0.edge.true" && CApi.block_name (false_block) == "b0.edge.false");
	assert ((void*) CApi.successor (CApi.block_terminator (true_block), 0) == (void*) physical[1]);
	assert ((void*) CApi.successor (CApi.block_terminator (false_block), 0) == (void*) physical[1]);
	var expected_first = divide ? operations (f, CApi.Opcode.PHI)[1] : CApi.get_param (f, 1);
	assert ((void*) CApi.incoming_value (phi, 0) == (void*) expected_first);
	assert ((void*) CApi.incoming_value (phi, 1) == (void*) CApi.get_param (f, 2));
	var end = divide ? CApi.instruction_parent (expected_first) : CApi.entry_block (f);
	var branch = CApi.block_terminator (end);
	assert ((void*) CApi.successor (branch, 0) == (void*) true_block && (void*) CApi.successor (branch, 1) == (void*) false_block);
	artifact.verify ();
	assert (artifact.dump () == artifact.dump ());
}

private void non_array_order() throws GLib.Error {
	var types = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("synthetic.astra", ""), 0, 0);
	var parameters = new GenericArray<SsaFunctionParameter> ();
	parameters.add (new SsaFunctionParameter (span, span, "a", types.int_type, 0));
	var bs = new GenericArray<SsaBlock> ();
	for (int b = 0; b < 3; b++) {
		bs.add (new SsaBlock (span, b, b));
	}
	var computation = new SsaPrefixInstruction (span, types.int_type, 1, PrefixOperator.NEGATIVE, parameters[0]);
	bs[1].instructions.add (computation);
	bs[0].complete (new SsaReturn (span, computation.result));
	bs[1].complete (new SsaBranch (span, edge (bs[0], {})));
	bs[2].complete (new SsaBranch (span, edge (bs[1], {})));
	var fs = new GenericArray<SsaFunction> ();
	fs.add (new SsaFunction (span, span, "f", types.int_type, 0, parameters, bs, bs[2]));
	var ssa = new SsaProgram (span, fs);
	var artifact = LlvmLowering.lower (ssa, NativeAbiBuilder.build (ssa), Astra.CAbi.CAbiBuilder.build (ssa, Astra.NativeAbi.NativeAbiBuilder.build (ssa)));
	var function = functions (artifact)[0];
	assert (CApi.block_name (CApi.entry_block (function)) == "b2");
	assert ((void*) returned (function) == (void*) operations (function, CApi.Opcode.SUB)[0]);
}

private void debug_names() throws GLib.Error {
	var ssa = build_ssa ("int first(int second) { return second(second); } int second(int first) { return first; }");
	var original = NativeAbiBuilder.build (ssa);
	var renamed = new GenericArray<NativeFunction> ();
	for (int f = 0; f < original.functions.length; f++) {
		var old = original.functions[f];
		var replacement = new NativeFunction (old.span, old.name_span, "same-debug-name", f, old.signature, old.linkage);
		replacement.bind_effects (old.effect_facts);
		replacement.bind_runtime_lifetimes (old.runtime_lifetimes);
		replacement.bind_scoped_readonly (old.scoped_readonly, old.readonly_inputs, old.callback_inputs, old.callback_input_count, old.callback_contract_supported);
		renamed.add (replacement);
	}
	var nabi = new NativeAbiProgram (original.span, original.abi_version, renamed);
	var artifact = LlvmLowering.lower (ssa, nabi, Astra.CAbi.CAbiBuilder.build (ssa, Astra.NativeAbi.NativeAbiBuilder.build (ssa)));
	var fs = functions (artifact);
	assert ((void*) CApi.called_value (operations (fs[0], CApi.Opcode.CALL)[0]) == (void*) fs[1]);
	assert (artifact.dump () == LlvmLowering.lower (ssa, original, Astra.CAbi.CAbiBuilder.build (ssa, Astra.NativeAbi.NativeAbiBuilder.build (ssa))).dump ());
}

private void call_forms() throws GLib.Error {
	var artifact = lower ("int value() { return 1; } void sink(bool b) {} bool condition(bool b) { return b; } void f(bool b) { value(); sink(b); if (condition(b)) { return; } }");
	var fs = functions (artifact);
	var cs = operations (fs[3], CApi.Opcode.CALL);
	assert (cs.length == 3);
	for (int c = 0; c < cs.length; c++) {
		assert ((void*) CApi.called_value (cs[c]) == (void*) fs[c] && CApi.instruction_call_conv (cs[c]) == CApi.CallConv.FAST);
	}
	width (CApi.type_of (cs[0]), 32);
	assert (CApi.type_kind (CApi.type_of (cs[1])) == CApi.TypeKind.VOID);
	width (CApi.type_of (cs[2]), 1);
	var terminator = CApi.block_terminator (CApi.entry_block (fs[3]));
	assert ((void*) CApi.condition (terminator) == (void*) cs[2]);
}

private void register_control_tests() {
	add ("/llvm/control/choose", choose);
	add ("/llvm/control/multiple-bool-nested", multiple_and_bool);
	add ("/llvm/control/choose-call", choose_call);
	add ("/llvm/control/parallel", () => parallel_edges (false));
	add ("/llvm/control/parallel-after-division", () => parallel_edges (true));
	add ("/llvm/control/non-array-order", non_array_order);
	add ("/llvm/calls/debug-names", debug_names);
	add ("/llvm/calls/void-discarded-condition", call_forms);
}
}
