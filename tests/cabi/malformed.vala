// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Foreign;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.CAbi;

namespace Astra.Tests.CImports {
private const string ONE_CALL = "extern(C) int c_one(int x); extern(C) void c_void(); int main() { c_one(1); return 0; }";

private void malformed_core() throws GLib.Error {
	for (int mode = 0; mode < 8; mode++) {
		var checked_program = check (ONE_CALL);
		var program = CoreBuilder.build (checked_program);
		var span = program.span;
		var call = (CoreCCallStatement) program.functions[0].body.statements[0];
		var types = checked_program.types;
		if (mode == 0) {
			call.arguments.remove_index (0);
		} else if (mode == 1) {
			call.arguments.add (call.arguments[0]);
		} else if (mode == 2) {
			call.arguments[0] = new CoreBooleanValue (span, types.bool_type, BooleanLiteral.TRUE);
		} else if (mode == 3) {
			program.c_functions.remove_index (0);
			program.c_functions.remove_index (0);
		} else if (mode == 4) {
			var other = CoreBuilder.build (checked_program);
			program.functions[0].body.statements[0] = new CoreCCallStatement (span, other.c_functions[0], call.arguments);
			// Hold the foreign program until verification to test a live wrong owner.
			try {
				CoreVerifier.verify (program);
				assert_not_reached ();
			} catch (CoreError.INVALID_IR error) {
				assert (error.message.contains ("call target"));
			}
			continue;
		} else if (mode == 5) {
			program.functions[0].body.statements[0] = new CoreReturn (span, new CoreCCallValue (span, types.bool_type, program.c_functions[0], call.arguments));
		} else if (mode == 6) {
			program.functions[0].body.statements[0] = new CoreReturn (span, new CoreCCallValue (span, types.int_type, program.c_functions[1], new GenericArray<CoreValue> ()));
		} else {
			program.c_functions.add (program.c_functions[0]);
		}
		string? previous = null;
		for (int attempt = 0; attempt < 2; attempt++) {
			try {
				CoreDump.format (program);
				assert_not_reached ();
			} catch (CoreError.INVALID_IR error) {
				assert (previous == null || previous == error.message);
				previous = error.message;
			}
		}
	}
}

private void malformed_cfg() throws GLib.Error {
	for (int mode = 0; mode < 10; mode++) {
		var checked_program = check (ONE_CALL);
		var program = CfgBuilder.build (CoreBuilder.build (checked_program));
		var block = program.functions[0].entry;
		var call = (CfgCCallInstruction) block.instructions[0];
		var target = program.c_functions[0];
		var result = call.result;
		var types = checked_program.types;
		CfgProgram? other = null;
		if (mode == 0) {
			call.arguments.remove_index (0);
		}
		if (mode == 1) {
			call.arguments.add (call.arguments[0]);
		}
		if (mode == 2) {
			call.arguments[0] = new CfgBooleanValue (call.span, types.bool_type, BooleanLiteral.TRUE);
		}
		if (mode == 3) {
			result = null;
		}
		if (mode == 4) {
			result = new CfgCallResultValue (call.span, types.bool_type);
		}
		if (mode == 5) {
			target = program.c_functions[1];
			call.arguments.remove_index (0);
		}
		if (mode == 6) {
			other = CfgBuilder.build (CoreBuilder.build (checked_program));
			target = other.c_functions[0];
		}
		if (mode == 7) {
			program.c_functions.remove_index (1);
			program.c_functions.remove_index (0);
		}
		var changed = new CfgCCallInstruction (call.span, target, call.arguments, result);
		block.instructions[0] = changed;
		if (mode == 8) {
			block.instructions.add (changed);
		}
		if (mode == 9) {
			block.instructions.add (new CfgCCallInstruction (call.span, target, call.arguments, result));
		}
		try {
			CfgDump.format (program);
			assert_not_reached ();
		} catch (CfgError.INVALID_CFG error) {
			assert (error.message.contains ("call"));
		}
	}
}

private void malformed_ssa() throws GLib.Error {
	for (int mode = 0; mode < 10; mode++) {
		var program = build (ONE_CALL);
		var block = program.functions[0].entry;
		var call = (SsaCCallInstruction) block.instructions[0];
		var target = program.c_functions[0];
		SemanticType? result_type = call.result.semantic_type;
		var types = new BuiltinTypes ();
		SsaProgram? other = null;
		if (mode == 0) {
			call.arguments.remove_index (0);
		}
		if (mode == 1) {
			call.arguments.add (call.arguments[0]);
		}
		if (mode == 2) {
			call.arguments[0] = new SsaBooleanConstant (call.span, types.bool_type, BooleanLiteral.TRUE);
		}
		if (mode == 3) {
			result_type = null;
		}
		if (mode == 4) {
			result_type = types.bool_type;
		}
		if (mode == 5) {
			target = program.c_functions[1];
			call.arguments.remove_index (0);
		}
		if (mode == 6) {
			other = build (ONE_CALL);
			target = other.c_functions[0];
		}
		if (mode == 7) {
			program.c_functions.remove_index (1);
			program.c_functions.remove_index (0);
		}
		var changed = new SsaCCallInstruction (call.span, result_type, 0, target, call.arguments);
		block.instructions[0] = changed;
		if (mode == 8) {
			block.instructions.add (changed);
		}
		if (mode == 9) {
			call.arguments[0] = changed.result;
		}
		try {
			SsaDump.format (program);
			assert_not_reached ();
		} catch (SsaError.INVALID_SSA error) {
			assert (error.message.contains ("SSA verification error"));
		}
	}
}

private void malformed_declarations() throws GLib.Error {
	for (int mode = 0; mode < 6; mode++) {
		var checked_program = check ("extern(C) int c_one(int x);");
		var span = checked_program.span;
		var types = checked_program.types;
		var parameters = new GenericArray<SemanticType> ();
		parameters.add (mode == 0 ? types.bool_type : mode == 1 ? types.void_type : types.int_type);
		var result = mode == 2 ? types.bool_type : types.int_type;
		string symbol = mode == 3 ? "" : "c_one";
		var abi = mode == 4 ? (ForeignAbi) 99 : ForeignAbi.C;
		int ordinal = mode == 5 ? -1 : 0;
		var core = CoreBuilder.build (checked_program);
		core.c_functions[0] = new CoreCFunction (span, span, "c_one", new CForeignMetadata (symbol), abi, result, parameters, ordinal);
		try {
			CoreVerifier.verify (core);
			assert_not_reached ();
		} catch (CoreError.INVALID_IR error) {
			assert (error.message.contains ("C import"));
		}
		var cfg = CfgBuilder.build (CoreBuilder.build (checked_program));
		cfg.c_functions[0] = new CfgCFunction (span, span, "c_one", new CForeignMetadata (symbol), abi, result, parameters, ordinal);
		try {
			CfgVerifier.verify (cfg);
			assert_not_reached ();
		} catch (CfgError.INVALID_CFG error) {
			assert (error.message.contains ("C import"));
		}
		var ssa = build ("extern(C) int c_one(int x);");
		var valid_nabi = Astra.NativeAbi.NativeAbiBuilder.build (ssa);
		ssa.c_functions[0] = new SsaCFunction (span, span, "c_one", new CForeignMetadata (symbol), abi, result, parameters, ordinal);
		try {
			SsaVerifier.verify (ssa);
			assert_not_reached ();
		} catch (SsaError.INVALID_SSA error) {
			assert (error.message.contains ("C import"));
		}
		try {
			CAbiBuilder.build (ssa, valid_nabi);
			assert_not_reached ();
		} catch (CAbiError.INVALID_SSA error) {
			assert (error.message.contains ("C import"));
		}
	}
}

private void call_validation() throws GLib.Error {
	var ssa = build ();
	var cabi = CAbiBuilder.build (ssa, Astra.NativeAbi.NativeAbiBuilder.build (ssa));
	var map = new HashTable<SsaCFunction, CAbiFunction> (direct_hash, direct_equal);
	for (int i = 0; i < ssa.c_functions.length; i++) {
		map.insert (ssa.c_functions[i], cabi.functions[i]);
	}
	CAbiValidator.validate_ssa_calls (ssa, cabi, map);
	var first = (SsaCCallInstruction) ssa.functions[1].entry.instructions[0];
	assert (CAbiValidator.validate_call (first, cabi, map, "test") == cabi.functions[0]);
	map.insert (ssa.c_functions[0], cabi.functions[1]);
	map.insert (ssa.c_functions[1], cabi.functions[0]);
	try {
		CAbiValidator.validate_ssa_calls (ssa, cabi, map);
		assert_not_reached ();
	} catch (CAbiError.INCOMPATIBLE_CALL error) {
		assert (error.message.contains ("exact identity"));
	}
	map.insert (ssa.c_functions[0], cabi.functions[0]);
	map.insert (ssa.c_functions[1], cabi.functions[1]);
	for (int mode = 0; mode < 6; mode++) {
		var arguments = new GenericArray<SsaValue> ();
		arguments.add (first.arguments[0]);
		var types = new BuiltinTypes ();
		SemanticType? result = first.result.semantic_type;
		var target = first.target;
		SsaProgram? other = null;
		if (mode == 0) {
			arguments.remove_index (0);
		}
		if (mode == 1) {
			arguments.add (arguments[0]);
		}
		if (mode == 2) {
			arguments[0] = new SsaBooleanConstant (first.span, types.bool_type, BooleanLiteral.TRUE);
		}
		if (mode == 3) {
			result = null;
		}
		if (mode == 4) {
			result = types.bool_type;
		}
		if (mode == 5) {
			other = build ();
			target = other.c_functions[0];
		}
		var call = new SsaCCallInstruction (first.span, result, 0, target, arguments);
		try {
			CAbiValidator.validate_call (call, cabi, map, "test");
			assert_not_reached ();
		} catch (CAbiError error) {
			assert (error is CAbiError.INVALID_TYPE || error is CAbiError.INCOMPATIBLE_CALL);
		}
	}
}

private void register_malformed() {
	add ("/cabi/malformed/core-calls", malformed_core);
	add ("/cabi/malformed/cfg-calls", malformed_cfg);
	add ("/cabi/malformed/ssa-calls", malformed_ssa);
	add ("/cabi/malformed/declarations", malformed_declarations);
	add ("/cabi/malformed/physical-call-validation", call_validation);
}
}
