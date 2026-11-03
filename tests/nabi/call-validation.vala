// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;

namespace Astra.Tests.Native {
private void bad_call(int kind) {
	try {
		var ssa = build_ssa ("bool callee(bool p, int n) { return p; } bool caller(bool p, int n) { return callee(p, n); } void noop() { return; }");
		var program = NativeAbiBuilder.build (ssa);
		var map = correspondence (ssa, program);
		var source = first_call (ssa.functions[1]);
		var arguments = new GenericArray<SsaValue> ();
		for (int i = 0; i < source.arguments.length; i++) {
			arguments.add (source.arguments[i]);
		}
		SsaFunction target = ssa.functions[0];
		SemanticType? result_type = target.return_type;
		SsaProgram? foreign = null;
		NativeAbiProgram? foreign_native = null;
		string suffix = "";
		string message;
		switch (kind) {
		case 0:
			map.remove (target);
			message = "call target has no exact native function in the program";
			break;
		case 1:
			arguments.remove_index (1);
			message = "call argument count does not match native parameter channels";
			break;
		case 2:
			arguments.add (arguments[1]);
			message = "call argument count does not match native parameter channels";
			break;
		case 3:
			arguments[0] = arguments[1];
			suffix = "/argument #0";
			message = "call argument type does not match native parameter channel";
			break;
		case 4:
			result_type = null;
			suffix = "/result";
			message = "call result presence does not match native result channel";
			break;
		case 5:
			target = ssa.functions[2];
			arguments = new GenericArray<SsaValue> ();
			suffix = "/result";
			message = "call result presence does not match native result channel";
			break;
		case 6:
			result_type = arguments[1].semantic_type;
			suffix = "/result";
			message = "call result type does not match native result channel";
			break;
		case 7:
		case 8:
			foreign = build_ssa ("bool callee(bool p, int n) { return p; }");
			target = foreign.functions[0];
			message = "call target has no exact native function in the program";
			break;
		default:
			foreign_native = NativeAbiBuilder.build (ssa);
			map.insert (target, foreign_native.functions[0]);
			message = "call target has no exact native function in the program";
			break;
		}
		var call = new SsaCallInstruction (source.span, result_type, 2, target, arguments);
		if (kind == 8) {
			target = null;
			foreign = null;
			assert (call.target == null);
		}
		for (int i = 0; i < 2; i++) {
			try {
				NativeAbiValidator.validate_call (call, program, map, "call");
			} catch (NativeAbiError error) {
				string expected = "internal native ABI compatibility error at call" + suffix + ": " + message;
				if (!(error is NativeAbiError.INCOMPATIBLE_CALL) || error.message != expected) {
					GLib.error ("Expected: %s\nActual: %s", expected, error.message);
				}
				continue;
			}
			GLib.error ("Incompatible call passed native validation");
		}
	} catch (GLib.Error error) {
		GLib.error ("Call test setup failed: %s", error.message);
	}
}

private void bad_correspondence(int kind) {
	try {
		var ssa = build_ssa ("int f(int x) { return x; } int g(int x) { return f(x); }");
		// This case isolates the physical parameter channel. Optional effect
		// facts are tested independently by the effect-count counterpart.
		if (kind == 4) {
			foreach (var function in ssa.functions) {
				function.effect_facts = null;
			}
		}
		var program = NativeAbiBuilder.build (ssa);
		var map = correspondence (ssa, program);
		NativeAbiValidator.validate_ssa_calls (ssa, program, map);
		string path = "program";
		string message = "function correspondence must be one-to-one";
		if (kind == 0) {
			map.remove (ssa.functions[0]);
		} else if (kind == 1) {
			map.insert (ssa.functions[0], program.functions[1]);
			map.insert (ssa.functions[1], program.functions[0]);
			path = "function #0";
			message = "function correspondence must preserve exact identity and source order";
		} else if (kind == 2) {
			var foreign = build_ssa ("int f(int x) { return x; }");
			map.remove (ssa.functions[0]);
			map.insert (foreign.functions[0], program.functions[0]);
			path = "function #0";
			message = "function correspondence must preserve exact identity and source order";
		} else if (kind == 3) {
			program = NativeAbiBuilder.build (build_ssa ("int f(int x) { return x; }"));
		} else {
			string text;
			path = "function #0";
			if (kind == 4 || kind == 8) {
				text = "int f() { return 1; } int g(int x) { return x; }";
				message = kind == 8 ? "derived effects lost exact SSA/native correspondence" : "parameter channel count does not match SSA function";
			} else if (kind == 5) {
				text = "int f(bool x) { return 1; } int g(int x) { return x; }";
				path += "/parameter #0";
				message = "parameter channel type does not match SSA function";
			} else {
				text = kind == 6 ? "bool f(int x) { return true; } int g(int x) { return x; }" : "void f(int x) { return; } int g(int x) { return x; }";
				path += "/result";
				message = "result channel does not match SSA function";
			}
			var variant = build_ssa (text);
			if (kind == 4) {
				foreach (var function in variant.functions) {
					function.effect_facts = null;
				}
			}
			program = NativeAbiBuilder.build (variant);
			map = correspondence (ssa, program);
		}
		NativeAbiVerifier.verify (program);
		SsaVerifier.verify (ssa);
		try {
			NativeAbiValidator.validate_ssa_calls (ssa, program, map);
		} catch (NativeAbiError error) {
			string expected = "internal native ABI compatibility error at " + path + ": " + message;
			if (!(error is NativeAbiError.INCOMPATIBLE_CALL) || error.message != expected) {
				GLib.error ("Expected: %s\nActual: %s", expected, error.message);
			}
			return;
		}
		GLib.error ("Invalid function correspondence was accepted");
	} catch (GLib.Error error) {
		GLib.error ("Correspondence test setup failed: %s", error.message);
	}
}

private void same_spelling() {
	try {
		// Normal SSA constructors allow debug names to coincide. Both callees
		// have identical shapes: only exact identity can distinguish them.
		var types = new BuiltinTypes ();
		var file = new SourceFile.from_text ("same-spelling.astra", "same");
		var span = SourceSpan (file, 0, file.length);
		var functions = new GenericArray<SsaFunction> ();
		for (int f = 0; f < 2; f++) {
			var blocks = new GenericArray<SsaBlock> ();
			blocks.add (new SsaBlock (span, 0, 0));
			functions.add (new SsaFunction (span, span, "same", types.int_type, f, new GenericArray<SsaFunctionParameter> (), blocks, blocks[0]));
		}
		for (int f = 0; f < 2; f++) {
			var call = new SsaCallInstruction (span, types.int_type, 0, functions[1 - f], new GenericArray<SsaValue> ());
			functions[f].entry.instructions.add (call);
			functions[f].entry.complete (new SsaReturn (span, call.result));
		}
		var ssa = new SsaProgram (span, functions);
		var program = NativeAbiBuilder.build (ssa);
		assert (program.functions[0] != program.functions[1] && program.functions[0].name == program.functions[1].name);
		var map = correspondence (ssa, program);
		NativeAbiValidator.validate_ssa_calls (ssa, program, map);
		for (int f = 0; f < 2; f++) {
			assert (NativeAbiValidator.validate_call (first_call (ssa.functions[f]), program, map, "same") == program.functions[1 - f]);
		}
	} catch (GLib.Error error) {
		GLib.error ("Same-spelled exact identities failed: %s", error.message);
	}
}

private void invalid_ssa(bool void_parameter) {
	try {
		var ssa = build_ssa ("int f(int x) { return x; } int g(int x) { return f(x); }");
		string detail;
		if (void_parameter) {
			var parameter = ssa.functions[0].parameters[0];
			ssa.functions[0].parameters[0] = new SsaFunctionParameter (parameter.span, parameter.name_span, parameter.name, new SemanticType (TypeKind.VOID), 0);
			detail = "function #0/parameter #0: void is not an SSA value type";
		} else {
			var foreign = build_ssa ("int f(int x) { return x; }");
			var call = first_call (ssa.functions[1]);
			ssa.functions[1].entry.instructions[0] = new SsaCallInstruction (call.span, call.result.semantic_type, call.result.ordinal, foreign.functions[0], call.arguments);
			detail = "function #1/block #0/instruction #0: call target is not owned by the containing program";
		}
		try {
			NativeAbiBuilder.build (ssa);
		} catch (NativeAbiError error) {
			assert (error is NativeAbiError.INVALID_SSA && error.message == "internal native ABI planning error: internal SSA verification error at " + detail);
			return;
		}
		GLib.error ("Planner accepted unverified SSA");
	} catch (GLib.Error error) {
		GLib.error ("Invalid SSA test setup failed: %s", error.message);
	}
}

private void register_call_tests() {
	Test.add_func ("/nabi/calls/missing-target", () => bad_call (0));
	Test.add_func ("/nabi/calls/too-few", () => bad_call (1));
	Test.add_func ("/nabi/calls/too-many", () => bad_call (2));
	Test.add_func ("/nabi/calls/argument-type", () => bad_call (3));
	Test.add_func ("/nabi/calls/missing-result", () => bad_call (4));
	Test.add_func ("/nabi/calls/extra-result", () => bad_call (5));
	Test.add_func ("/nabi/calls/result-type", () => bad_call (6));
	Test.add_func ("/nabi/calls/foreign-target", () => bad_call (7));
	Test.add_func ("/nabi/calls/expired-target", () => bad_call (8));
	Test.add_func ("/nabi/calls/foreign-native-target", () => bad_call (9));
	Test.add_func ("/nabi/correspondence/missing", () => bad_correspondence (0));
	Test.add_func ("/nabi/correspondence/swapped", () => bad_correspondence (1));
	Test.add_func ("/nabi/correspondence/foreign-same-spelling", () => bad_correspondence (2));
	Test.add_func ("/nabi/correspondence/function-count", () => bad_correspondence (3));
	Test.add_func ("/nabi/correspondence/parameter-count", () => bad_correspondence (4));
	Test.add_func ("/nabi/correspondence/effect-parameter-count", () => bad_correspondence (8));
	Test.add_func ("/nabi/correspondence/parameter-type", () => bad_correspondence (5));
	Test.add_func ("/nabi/correspondence/result-type", () => bad_correspondence (6));
	Test.add_func ("/nabi/correspondence/result-presence", () => bad_correspondence (7));
	Test.add_func ("/nabi/same-spelling", same_spelling);
	Test.add_func ("/nabi/reject-invalid-ssa/void-parameter", () => invalid_ssa (true));
	Test.add_func ("/nabi/reject-invalid-ssa/foreign-callee", () => invalid_ssa (false));
}

}
