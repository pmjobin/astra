// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.Pointers {
private const string MALFORMED = "void* f(bool c, void* p) { void* x = null; if (c) { x = p; } return x; }";

private SemanticType wrong_type(RawPointerType original, int mode) {
	switch (mode) {
	case 0:
		return new IntegerType (TypeKind.INT);
	case 1:
		return new RawPointerType (original.pointee);
	case 2:
		return new RawPointerType (new SemanticType (TypeKind.INT));
	case 3:
		return new SemanticType (TypeKind.RAW_POINTER);
	default:
		return new RawPointerType (new SemanticType (TypeKind.VOID));
	}
}

private string expected_type_error(int mode) {
	return mode == 0 ? "null pointer must have type 'void*'" : mode == 1 ? "inconsistent 'void*' semantic type identity" : mode == 4 ? "inconsistent 'void' semantic type identity" : "raw pointer must point to void";
}

private void malformed_core() throws GLib.Error {
	for (int mode = 0; mode < 5; mode++) {
		var core = CoreBuilder.build (check (MALFORMED));
		var old = (CoreInitialize) core.functions[0].body.statements[0];
		core.functions[0].body.statements[0] = new CoreInitialize (old.span, old.target, new CoreNullPointerValue (old.span, wrong_type ((RawPointerType) old.target.semantic_type, mode)));
		try {
			CoreVerifier.verify (core);
			assert_not_reached ();
		} catch (CoreError.INVALID_IR error) {
			assert (error.message.has_suffix (expected_type_error (mode)));
		}
	}
}

private void malformed_cfg() throws GLib.Error {
	for (int mode = 0; mode < 5; mode++) {
		var cfg = CfgBuilder.build (CoreBuilder.build (check (MALFORMED)));
		var old = (CfgInitialize) cfg.functions[0].entry.instructions[0];
		cfg.functions[0].entry.instructions[0] = new CfgInitialize (old.span, old.target, new CfgNullPointerValue (old.span, wrong_type ((RawPointerType) old.target.semantic_type, mode)));
		try {
			CfgVerifier.verify (cfg);
			assert_not_reached ();
		} catch (CfgError.INVALID_CFG error) {
			assert (error.message.has_suffix (expected_type_error (mode)));
		}
	}
}

private void malformed_ssa() throws GLib.Error {
	for (int mode = 0; mode < 5; mode++) {
		var ssa = build (MALFORMED);
		var edge = ((SsaConditionalBranch) ssa.functions[0].blocks[0].terminator).false_edge;
		edge.arguments[0] = new SsaNullPointerConstant (ssa.span, wrong_type ((RawPointerType) ssa.functions[0].return_type, mode));
		try {
			SsaVerifier.verify (ssa);
			assert_not_reached ();
		} catch (SsaError.INVALID_SSA error) {
			assert (error.message.has_suffix (expected_type_error (mode)));
		}
	}
}

private void malformed_operators() throws GLib.Error {
	var types = new BuiltinTypes ();
	foreach (var op in new BinaryOperator[] {BinaryOperator.ADD, BinaryOperator.SUBTRACT, BinaryOperator.MULTIPLY, BinaryOperator.DIVIDE, BinaryOperator.REMAINDER, BinaryOperator.LESS, BinaryOperator.LESS_EQUAL, BinaryOperator.GREATER, BinaryOperator.GREATER_EQUAL}) {
		assert (!op.accepts (types.raw_pointer_type, types.raw_pointer_type, types.bool_type));
		assert (!op.accepts (types.raw_pointer_type, types.int_type, types.raw_pointer_type));
	}
	foreach (var op in new BinaryOperator[] {BinaryOperator.EQUAL, BinaryOperator.NOT_EQUAL}) {
		assert (op.accepts (types.raw_pointer_type, types.raw_pointer_type, types.bool_type));
		assert (!op.accepts (types.raw_pointer_type, types.int_type, types.bool_type));
		assert (!op.accepts (types.raw_pointer_type, types.bool_type, types.bool_type));
		assert (!op.accepts (types.raw_pointer_type, new RawPointerType (types.void_type), types.bool_type));
	}
	assert (!PrefixOperator.NOT.accepts (types.raw_pointer_type, types.bool_type));
}

private void register_malformed() {
	add ("/ptr/verifier/core-null-and-canonical-types", malformed_core);
	add ("/ptr/verifier/cfg-null-and-canonical-types", malformed_cfg);
	add ("/ptr/verifier/ssa-null-and-canonical-types", malformed_ssa);
	add ("/ptr/verifier/operators", malformed_operators);
}

}
