// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.Llvm {
private delegate void TestBody() throws GLib.Error;

private class Case : Object {
	internal TestBody body;

	internal Case (owned TestBody body) {
		this.body = (owned) body;
	}
}

private HashTable<string, Case> cases;

private void add(string path, owned TestBody body) {
	cases.insert (path, new Case ((owned) body));
	Test.add_func (path, () => {
			try {
				cases.lookup (Test.get_path ()).body ();
			} catch (GLib.Error error) {
				GLib.error ("%s failed: %s", Test.get_path (), error.message);
			}
		});
}

private string fixture(string path) throws FileError {
	string text;
	FileUtils.get_contents (path, out text);
	return text;
}

private SsaProgram build_ssa(string text, string path = "llvm-test.astra") throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text (path, text));
	assert (parsed.diagnostic == null);
	var checked_result = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked_result.diagnostic == null);
	var cfg = CfgBuilder.build (CoreBuilder.build (checked_result.program));
	assert (CfgFlowChecker.check (cfg).diagnostic == null);
	return SsaBuilder.build (cfg);
}

private LlvmModuleArtifact lower(string text, string path = "llvm-test.astra") throws GLib.Error {
	var ssa = build_ssa (text, path);
	var nabi = NativeAbiBuilder.build (ssa);
	string before_ssa = SsaDump.format (ssa);
	string before_nabi = NativeAbiDump.format (nabi);
	var artifact = LlvmLowering.lower (ssa, nabi, Astra.CAbi.CAbiBuilder.build (ssa, Astra.NativeAbi.NativeAbiBuilder.build (ssa)));
	assert (SsaDump.format (ssa) == before_ssa && NativeAbiDump.format (nabi) == before_nabi);
	artifact.verify ();
	assert (artifact.dump () == artifact.dump ());
	return artifact;
}

private CApi.ValueRef[] functions(LlvmModuleArtifact artifact) {
	CApi.ValueRef[] result = null;
	for (var f = CApi.first_function (artifact.module); (void*) f != null; f = CApi.next_function (f)) {
		if (CApi.intrinsic_id (f) == 0) {
			result += f;
		}
	}
	return result;
}

private CApi.BasicBlockRef[] blocks(CApi.ValueRef function) {
	CApi.BasicBlockRef[] result = null;
	for (var b = CApi.first_block (function); (void*) b != null; b = CApi.next_block (b)) {
		result += b;
	}
	return result;
}

private CApi.ValueRef[] instructions(CApi.ValueRef function) {
	CApi.ValueRef[] result = null;
	foreach (var b in blocks (function)) {
		for (var i = CApi.first_instruction (b); (void*) i != null; i = CApi.next_instruction (i)) {
			result += i;
		}
	}
	return result;
}

private CApi.ValueRef[] operations(CApi.ValueRef function, CApi.Opcode opcode) {
	CApi.ValueRef[] result = null;
	foreach (var i in instructions (function)) {
		if (CApi.opcode (i) == opcode) {
			result += i;
		}
	}
	return result;
}

private void width(CApi.TypeRef type, uint bits) {
	assert (CApi.type_kind (type) == CApi.TypeKind.INTEGER && CApi.int_width (type) == bits);
}

private CApi.ValueRef returned(CApi.ValueRef function) {
	var returns = operations (function, CApi.Opcode.RET);
	assert (returns.length == 1);
	return CApi.operand (returns[0], 0);
}

private void mapping() throws GLib.Error {
	var artifact = new LlvmModuleArtifact ();
	var mapper = new LlvmTypeMapper (artifact.context);
	width (mapper.scalar (NativeScalarType.I32), 32);
	width (mapper.scalar (NativeScalarType.B1), 1);
	assert (CApi.type_kind (mapper.result_type (null)) == CApi.TypeKind.VOID);
	var types = new BuiltinTypes ();
	width (mapper.value_type (types.int_type), 32);
	width (mapper.value_type (types.bool_type), 1);
	var module = lower (fixture ("tests/nabi/fixtures/signatures.astra"));
	var fs = functions (module);
	assert (fs.length == 3);
	uint[] counts = {
		2, 1, 1
	};
	for (int f = 0; f < fs.length; f++) {
		assert (CApi.get_linkage (fs[f]) == CApi.Linkage.INTERNAL);
		assert (CApi.function_call_conv (fs[f]) == CApi.CallConv.FAST);
		assert (CApi.count_params (fs[f]) == counts[f]);
		for (uint p = 0; p < counts[f]; p++) {
			width (CApi.type_of (CApi.get_param (fs[f], p)), f == 2 ? 1 : 32);
		}
	}
	width (CApi.return_type (CApi.global_value_type (fs[0])), 32);
	width (CApi.return_type (CApi.global_value_type (fs[1])), 1);
	assert (CApi.type_kind (CApi.return_type (CApi.global_value_type (fs[2]))) == CApi.TypeKind.VOID);
}

private void constants() throws GLib.Error {
	var artifact = lower (fixture ("tests/llvm/fixtures/constants.astra"));
	var fs = functions (artifact);
	int64[] expected = {
		0, 2147483647L, -1, -2147483648L, -1, 0
	};
	assert (fs.length == 8);
	for (int f = 0; f < fs.length; f++) {
		assert (CApi.count_params (fs[f]) == 0);
		if (f < expected.length) {
			var result = returned (fs[f]);
			width (CApi.type_of (result), f < 4 ? 32 : 1);
			assert (CApi.constant_signed (result) == expected[f]);
		} else {
			assert (CApi.type_kind (CApi.return_type (CApi.global_value_type (fs[f]))) == CApi.TypeKind.VOID);
			assert (operations (fs[f], CApi.Opcode.RET).length == 1);
		}
	}
	assert (functions (lower ("")).length == 0);
}

private void wrapping() throws GLib.Error {
	var artifact = lower (fixture ("tests/llvm/fixtures/wrapping.astra"));
	var fs = functions (artifact);
	CApi.Opcode[] expected = {
		CApi.Opcode.ADD, CApi.Opcode.SUB, CApi.Opcode.MUL, CApi.Opcode.SUB
	};
	for (int f = 0; f < expected.length; f++) {
		var ops = operations (fs[f], expected[f]);
		assert (ops.length == 1 && CApi.get_nsw (ops[0]) == 0 && CApi.get_nuw (ops[0]) == 0);
		assert ((void*) returned (fs[f]) == (void*) ops[0]);
	}
	var negate = operations (fs[3], CApi.Opcode.SUB)[0];
	assert (CApi.constant_signed (CApi.operand (negate, 0)) == 0);
	assert ((void*) CApi.operand (negate, 1) == (void*) CApi.get_param (fs[3], 0));
	assert (instructions (fs[4]).length == 1 && (void*) returned (fs[4]) == (void*) CApi.get_param (fs[4], 0));
	int64[] folded = {
		-2147483648L, 2147483647L, -2, -2147483648L
	};
	for (int f = 0; f < folded.length; f++) {
		assert (CApi.constant_signed (returned (fs[f + 5])) == folded[f]);
	}
	assert (!artifact.dump ().contains ("nsw") && !artifact.dump ().contains ("nuw"));
}

private void comparisons() throws GLib.Error {
	var artifact = lower (fixture ("tests/llvm/fixtures/comparisons.astra"));
	var fs = functions (artifact);
	CApi.IntPredicate[] expected = {
		CApi.IntPredicate.SLT, CApi.IntPredicate.SLE, CApi.IntPredicate.SGT, CApi.IntPredicate.SGE, CApi.IntPredicate.EQ, CApi.IntPredicate.NE, CApi.IntPredicate.EQ, CApi.IntPredicate.NE
	};
	for (int f = 0; f < expected.length; f++) {
		var comparison = operations (fs[f], CApi.Opcode.ICMP)[0];
		assert (CApi.predicate (comparison) == expected[f]);
		width (CApi.type_of (comparison), 1);
		width (CApi.type_of (CApi.operand (comparison, 0)), f < 6 ? 32 : 1);
		assert ((void*) CApi.operand (comparison, 0) == (void*) CApi.get_param (fs[f], 0));
		assert ((void*) CApi.operand (comparison, 1) == (void*) CApi.get_param (fs[f], 1));
	}
	var negate = operations (fs[8], CApi.Opcode.XOR)[0];
	width (CApi.type_of (negate), 1);
	assert (CApi.constant_signed (CApi.operand (negate, 1)) != 0);
}

private void calls(string path, int[] callers, int[] targets) throws GLib.Error {
	var artifact = lower (fixture (path));
	var fs = functions (artifact);
	int n = 0;
	for (int f = 0; f < fs.length; f++) {
		foreach (var call in operations (fs[f], CApi.Opcode.CALL)) {
			assert (n < callers.length && f == callers[n]);
			assert ((void*) CApi.called_value (call) == (void*) fs[targets[n]]);
			assert (CApi.instruction_call_conv (call) == CApi.function_call_conv (fs[targets[n]]) && CApi.instruction_call_conv (call) == CApi.CallConv.FAST);
			n++;
		}
	}
	assert (n == callers.length);
}

private void ordered_calls() throws GLib.Error {
	var artifact = lower (fixture ("tests/call/fixtures/ordered-calls.astra"));
	var fs = functions (artifact);
	var ordered = instructions (fs[2]);
	assert (ordered.length == 4);
	assert (CApi.opcode (ordered[0]) == CApi.Opcode.CALL && CApi.opcode (ordered[1]) == CApi.Opcode.CALL && CApi.opcode (ordered[2]) == CApi.Opcode.ADD && CApi.opcode (ordered[3]) == CApi.Opcode.RET);
	assert ((void*) CApi.called_value (ordered[0]) == (void*) fs[0] && (void*) CApi.called_value (ordered[1]) == (void*) fs[1]);
	assert ((void*) CApi.operand (ordered[2], 0) == (void*) ordered[0] && (void*) CApi.operand (ordered[2], 1) == (void*) ordered[1]);
	var nested = lower (fixture ("tests/call/fixtures/nested-calls.astra"));
	var nf = functions (nested);
	var nc = operations (nf[2], CApi.Opcode.CALL);
	assert (nc.length == 3);
	assert (CApi.constant_signed (CApi.operand (nc[0], 0)) == 1 && CApi.constant_signed (CApi.operand (nc[1], 0)) == 2);
	assert ((void*) CApi.operand (nc[2], 0) == (void*) nc[0] && (void*) CApi.operand (nc[2], 1) == (void*) nc[1]);
}

private void rejection() throws GLib.Error {
	string[] mismatches = {
		"", "bool f(int a) { return true; }", "int f(bool a) { return 1; }", "int f() { return 1; }"
	};
	var ssa = build_ssa ("int f(int a) { return a; }");
	foreach (string mismatch in mismatches) {
		var nabi = NativeAbiBuilder.build (build_ssa (mismatch));
		string? previous = null;
		for (int i = 0; i < 2; i++) {
			try {
				LlvmLowering.lower (ssa, nabi, Astra.CAbi.CAbiBuilder.build (ssa, Astra.NativeAbi.NativeAbiBuilder.build (ssa)));
			} catch (LlvmError error) {
				assert (error is LlvmError.INVALID_INPUT && error.message.has_prefix ("internal LLVM input error:"));
				assert (previous == null || previous == error.message);
				previous = error.message;
				continue;
			}
			GLib.error ("Mismatched SSA/NABI was accepted");
		}
	}
	var valid_nabi = NativeAbiBuilder.build (ssa);
	var valid_cabi = Astra.CAbi.CAbiBuilder.build (ssa, Astra.NativeAbi.NativeAbiBuilder.build (ssa));
	ssa.functions[0].entry.instructions.add (new SsaPrefixInstruction (ssa.span, ssa.functions[0].return_type, 0, PrefixOperator.POSITIVE, ssa.functions[0].parameters[0]));
	try {
		LlvmLowering.lower (ssa, valid_nabi, valid_cabi);
	} catch (LlvmError error) {
		assert (error is LlvmError.INVALID_INPUT && error.message.contains ("SSA verification error"));
		return;
	}
	GLib.error ("Invalid SSA was accepted");
}

private void verifier_rejection() throws GLib.Error {
	var artifact = new LlvmModuleArtifact ();
	var signature = CApi.function_type (CApi.int32_type_in_context (artifact.context), null, 0, 0);
	var function = CApi.add_function (artifact.module, "invalid", signature);
	CApi.append_basic_block_in_context (artifact.context, function, "unterminated");
	string? previous = null;
	for (int i = 0; i < 3; i++) {
		try {
			if (i == 1) {
				artifact.dump ();
			} else {
				artifact.verify ();
			}
		} catch (LlvmError error) {
			assert (error is LlvmError.VERIFICATION && error.message.has_prefix ("internal LLVM verification error:") && error.message.contains ("terminator"));
			assert (previous == null || previous == error.message);
			previous = error.message;
			continue;
		}
		GLib.error ("Invalid LLVM was accepted");
	}
}

private void existing_fixture(string path) {
	add ("/llvm/existing/" + path, () => {
			string[] parts = path.split ("/");
			string source = fixture ("tests/" + parts[0] + "/fixtures/" + parts[1] + ".astra");
			var first = lower (source, "/one/input.astra");
			var second = lower (source, "/another/input.astra");
			assert (first.dump () == second.dump ());
			assert (!first.dump ().contains ("nsw") && !first.dump ().contains ("nuw") && !first.dump ().contains ("poison"));
			audit_division (first);
		});
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/llvm/types-and-signatures", mapping);
	add ("/llvm/constants-and-void", constants);
	add ("/llvm/wrapping", wrapping);
	add ("/llvm/comparisons", comparisons);
	add ("/llvm/calls/forward", () => calls ("tests/call/fixtures/forward-call.astra", {0}, {1}));
	add ("/llvm/calls/self", () => calls ("tests/call/fixtures/recursion.astra", {0}, {0}));
	add ("/llvm/calls/mutual", () => calls ("tests/call/fixtures/mutual-recursion.astra", {0, 1}, {1, 0}));
	add ("/llvm/calls/nested", () => calls ("tests/call/fixtures/nested-calls.astra", {2, 2, 2}, {0, 0, 1}));
	add ("/llvm/calls/order", ordered_calls);
	add ("/llvm/invalid-input", rejection);
	add ("/llvm/verifier-rejection", verifier_rejection);
	register_control_tests ();
	register_loop_tests ();
	register_loop_control_tests ();
	register_shortcircuit_tests ();
	register_division_tests ();
	register_lifetime_tests ();
	register_c_imports ();
	register_c_exports ();
	string[] paths = {
		"call/forward-call", "call/recursion", "call/mutual-recursion", "call/bool-calls", "call/statements", "call/ordered-calls", "call/nested-calls", "call/choose-call", "call/places-calls", "call/branch-calls", "call/unreachable-call", "call/namespace", "scalar/boundaries", "scalar/leading", "scalar/wrapping", "scalar/division", "scalar/calls", "scalar/trap-order", "branch/nested", "branch/siblings", "branch/boolean-place", "branch/operators", "ssa/multiple", "ssa/scoped", "ssa/dead-merge", "nabi/bool-transport"
	};
	foreach (string path in paths) {
		existing_fixture (path);
	}
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
