// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;

namespace Astra.Tests.Native {
private string fixture(string path) throws FileError {
	string text;
	FileUtils.get_contents (path, out text);
	return text;
}

private SsaProgram build_ssa(string text) throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("native.astra", text));
	assert (parsed.diagnostic == null);
	var checked_result = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked_result.diagnostic == null);
	var cfg = CfgBuilder.build (CoreBuilder.build (checked_result.program));
	assert (CfgFlowChecker.check (cfg).diagnostic == null);
	return SsaBuilder.build (cfg);
}

private void signature(NativeFunction function, NativeScalarType[]? parameters, NativeScalarType? result) {
	assert (function.signature.abi_version == NativeAbiVersion.SCALAR_V0 && function.linkage == NativeLinkage.NATIVE_INTERNAL);
	assert (function.signature.parameters.length == parameters.length);
	for (int i = 0; i < parameters.length; i++) {
		assert (function.signature.parameters[i].ordinal == i && function.signature.parameters[i].scalar_type == parameters[i]);
	}
	assert ((function.signature.result == null) == (result == null));
	if (result != null) {
		assert (function.signature.result.scalar_type == result);
	}
}

private HashTable<SsaFunction, NativeFunction> correspondence(SsaProgram source, NativeAbiProgram program) {
	var result = new HashTable<SsaFunction, NativeFunction> (direct_hash, direct_equal);
	assert (source.functions.length == program.functions.length);
	for (int i = 0; i < source.functions.length; i++) {
		result.insert (source.functions[i], program.functions[i]);
	}
	return result;
}

private SsaCallInstruction? first_call(SsaFunction function) {
	for (int b = 0; b < function.blocks.length; b++) {
		for (int i = 0; i < function.blocks[b].instructions.length; i++) {
			var call = function.blocks[b].instructions[i] as SsaCallInstruction;
			if (call != null) {
				return call;
			}
		}
	}
	return null;
}

private void type_mapping() {
	try {
		var types = new BuiltinTypes ();
		assert (NativeTypeMapper.map_scalar (types.int_type) == NativeScalarType.I32);
		assert (NativeTypeMapper.map_scalar (types.bool_type) == NativeScalarType.B1);
		assert (NativeTypeMapper.map_result (types.int_type).scalar_type == NativeScalarType.I32);
		assert (NativeTypeMapper.map_result (types.bool_type).scalar_type == NativeScalarType.B1);
		assert (NativeTypeMapper.map_result (types.void_type) == null);
		try {
			NativeTypeMapper.map_scalar (types.void_type);
		} catch (NativeAbiError error) {
			assert (error is NativeAbiError.INVALID_TYPE && error.message == "internal native ABI mapping error: void is not a direct scalar channel type");
			return;
		}
		GLib.error ("Void became a scalar channel");
	} catch (NativeAbiError error) {
		GLib.error ("Scalar mapping failed: %s", error.message);
	}
}

private void unsupported_mapping() {
	for (int i = 0; i < 2; i++) {
		try {
			var type = new SemanticType ((TypeKind) 99);
			if (i == 0) {
				NativeTypeMapper.map_scalar (type);
			} else {
				NativeTypeMapper.map_result (type);
			}
		} catch (NativeAbiError error) {
			assert (error is NativeAbiError.INVALID_TYPE && error.message == "internal native ABI mapping error: unsupported semantic type");
			continue;
		}
		GLib.error ("Unsupported semantic type was mapped");
	}
}

private void representative() {
	try {
		var ssa = build_ssa (fixture ("tests/nabi/fixtures/signatures.astra"));
		string before = SsaDump.format (ssa);
		var program = NativeAbiBuilder.build (ssa);
		assert (program.functions.length == 3);
		signature (program.functions[0], {NativeScalarType.I32, NativeScalarType.I32}, NativeScalarType.I32);
		signature (program.functions[1], {NativeScalarType.I32}, NativeScalarType.B1);
		signature (program.functions[2], {NativeScalarType.B1}, null);
		assert (program.functions[0].signature.parameters[0].name == "a" && program.functions[0].signature.parameters[1].name == "b");
		assert (program.functions[2].signature.parameters[0].name == "enabled");
		for (int f = 0; f < program.functions.length; f++) {
			assert (program.functions[f].ordinal == f && program.functions[f].name == ssa.functions[f].name);
			assert ((Object) program.functions[f] != (Object) ssa.functions[f] && program.functions[f].owner == program);
		}
		string dump = NativeAbiDump.format (program);
		assert (dump == fixture ("tests/nabi/fixtures/signatures.nabi") && dump == NativeAbiDump.format (NativeAbiBuilder.build (ssa)));
		assert (SsaDump.format (ssa) == before);
	} catch (GLib.Error error) {
		GLib.error ("Representative signatures failed: %s", error.message);
	}
}

private void zero_arguments() {
	try {
		var program = NativeAbiBuilder.build (build_ssa (fixture ("tests/nabi/fixtures/zero-arguments.astra")));
		signature (program.functions[0], null, null);
		signature (program.functions[1], null, NativeScalarType.I32);
		signature (program.functions[2], null, NativeScalarType.B1);
		assert (NativeAbiDump.format (NativeAbiBuilder.build (build_ssa (""))) == "(native-abi scalar-v0)\n");
	} catch (GLib.Error error) {
		GLib.error ("Zero-argument planning failed: %s", error.message);
	}
}

private void mixed() {
	try {
		var ssa = build_ssa (fixture ("tests/nabi/fixtures/mixed.astra"));
		var program = NativeAbiBuilder.build (ssa);
		signature (program.functions[0], {NativeScalarType.B1, NativeScalarType.I32, NativeScalarType.I32}, NativeScalarType.I32);
		signature (program.functions[1], null, NativeScalarType.I32);
		assert (NativeAbiValidator.validate_call (first_call (ssa.functions[1]), program, correspondence (ssa, program), "mixed") == program.functions[0]);
	} catch (GLib.Error error) {
		GLib.error ("Mixed source-order channels failed: %s", error.message);
	}
}

private void bool_transport() {
	try {
		var ssa = build_ssa (fixture ("tests/nabi/fixtures/bool-transport.astra"));
		var program = NativeAbiBuilder.build (ssa);
		signature (program.functions[0], {NativeScalarType.B1}, NativeScalarType.B1);
		signature (program.functions[1], {NativeScalarType.B1}, null);
		signature (program.functions[2], {NativeScalarType.B1}, NativeScalarType.B1);
		var calls = ssa.functions[2].entry.instructions;
		assert (calls.length == 3);
		int[] targets = {
			0, 1, 0
		};
		var map = correspondence (ssa, program);
		for (int i = 0; i < targets.length; i++) {
			assert (NativeAbiValidator.validate_call ((SsaCallInstruction) calls[i], program, map, "bool") == program.functions[targets[i]]);
		}
	} catch (GLib.Error error) {
		GLib.error ("Bool/void transport failed: %s", error.message);
	}
}

private void body_independence() {
	try {
		string[] bodies = {
			"return -2147483648;", "return 2147483647;", "return 0;", "return 1 / 0;", "return -2147483648 / -1;", "return -2147483648 % -1;", "return f();", "if (true) { return 7; } else { return 8; }"
		};
		string? expected = null;
		foreach (string body in bodies) {
			var ssa = build_ssa ("int f() { " + body + " }");
			string before = SsaDump.format (ssa);
			string dump = NativeAbiDump.format (NativeAbiBuilder.build (ssa));
			if (expected == null) {
				expected = dump;
			}
			assert (dump == expected && SsaDump.format (ssa) == before);
			assert (!dump.contains ("block") && !dump.contains ("instruction") && !dump.contains ("call") && !dump.contains ("2147483648"));
		}
	} catch (GLib.Error error) {
		GLib.error ("Body-independent signatures failed: %s", error.message);
	}
}

private void existing_fixtures() {
	try {
		string[] paths = {
			"call/forward-call", "call/recursion", "call/mutual-recursion", "call/bool-calls", "call/statements", "call/ordered-calls", "call/nested-calls", "call/choose-call", "call/places-calls", "call/branch-calls", "call/unreachable-call", "call/namespace", "scalar/boundaries", "scalar/leading", "scalar/wrapping", "scalar/division", "scalar/calls", "scalar/trap-order"
		};
		foreach (string path in paths) {
			string[] parts = path.split ("/");
			var ssa = build_ssa (fixture ("tests/" + parts[0] + "/fixtures/" + parts[1] + ".astra"));
			string before = SsaDump.format (ssa);
			var program = NativeAbiBuilder.build (ssa);
			NativeAbiVerifier.verify (program);
			NativeAbiValidator.validate_ssa_calls (ssa, program, correspondence (ssa, program));
			assert (NativeAbiDump.format (program) == NativeAbiDump.format (NativeAbiBuilder.build (ssa)) && SsaDump.format (ssa) == before);
		}
	} catch (GLib.Error error) {
		GLib.error ("Existing call/scalar fixtures failed: %s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/nabi/type-mapping", type_mapping);
	Test.add_func ("/nabi/unsupported-mapping", unsupported_mapping);
	Test.add_func ("/nabi/signatures/representative", representative);
	Test.add_func ("/nabi/signatures/zero-arguments", zero_arguments);
	Test.add_func ("/nabi/signatures/mixed", mixed);
	Test.add_func ("/nabi/signatures/bool-transport", bool_transport);
	Test.add_func ("/nabi/body-independence", body_independence);
	Test.add_func ("/nabi/existing-fixtures", existing_fixtures);
	register_lifetime_tests ();
	register_call_tests ();
	return Test.run ();
}
}
