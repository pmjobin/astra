// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Vapi;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.Pointers {
private void syntax_and_types() throws GLib.Error {
	foreach (string spelling in new string[] {"void*", "void *", "void    *", "void/*opaque*/ *"}) {
		string text = spelling + " identity(" + spelling + " p) { " + spelling + " copy = null; copy = p; return copy; }";
		var parsed = Parser.parse (new SourceFile.from_text ("syntax.astra", text));
		assert (parsed.diagnostic == null);
		assert (parsed.unit.functions[0].return_type.stars.length == 1);
		assert (SyntaxDump.format (parsed.unit).contains ("(type \"void*\")"));
		var program = check (text);
		var ptr = program.types.raw_pointer_type;
		assert (ptr.kind == TypeKind.RAW_POINTER && ptr.pointee == program.types.void_type);
		assert (ptr != program.types.void_type && ptr != program.types.int_type && ptr != program.types.bool_type);
		assert (program.functions[0].symbol.return_type == ptr && program.functions[0].symbol.parameters[0].semantic_type == ptr);
		assert (program.functions[0].locals[0].semantic_type == ptr);
		var initialized = (CheckedLocalDeclaration) program.functions[0].body.statements[0];
		assert (initialized.initializer is CheckedNullPointerExpression && initialized.initializer.semantic_type == ptr);
		assert (initialized.initializer.span.text () == "null");
		assert (SemanticDump.format (program).contains ("(null : void*)"));
		var foreign = check ("", spelling + " identity(" + spelling + " p);");
		assert (foreign.c_functions[0].return_type == foreign.types.raw_pointer_type && foreign.c_functions[0].parameters[0].semantic_type == foreign.types.raw_pointer_type);
	}
	var program = check ("bool equal(void* a, void* b) { return a == b; } bool unequal(void* p) { return p != null; } bool equal_null() { return null == null; }");
	assert (SemanticDump.format (program).contains ("(binary == : bool"));
}

private void reject_source(string text, string message) {
	string? previous = null;
	for (int i = 0; i < 2; i++) {
		var parsed = Parser.parse (new SourceFile.from_text ("pointer-invalid.astra", text));
		Diagnostic? diagnostic = parsed.diagnostic;
		if (diagnostic == null) {
			var result = SemanticAnalyzer.analyze (parsed.unit);
			diagnostic = result.diagnostic;
		}
		if (diagnostic == null || diagnostic.message != message) {
			GLib.error ("Source: %s\nExpected: %s\nActual: %s", text, message, diagnostic == null ? "accepted" : diagnostic.message);
		}
		string formatted = diagnostic.format ();
		assert (formatted.has_prefix ("pointer-invalid.astra:1:") && (previous == null || previous == formatted));
		previous = formatted;
	}
}

private void diagnostics() throws GLib.Error {
	foreach (string type in new string[] {"int*", "bool*", "void**", "int**", "void***"}) {
		string message = type.contains ("**") ? "pointer depth greater than one is unsupported" : "typed pointer pointee must be an integer, f32, numeric vector, or native struct; bool and resource storage are unsupported";
		if (type == "int*") {
			reject_source (type + " f() { return null; }", "typed-pointer function results are unsupported; escaping pointers require return-lifetime contracts");
			check ("void f(int* p) {} void g(){int* p=null;}");
		} else {
			reject_source (type + " f() { return null; }", message);
			reject_source ("void f(" + type + " p) {}", message);
			reject_source ("void f() { " + type + " p = null; }", message);
		}
		foreach (string declaration in new string[] {type + " f();", "void f(" + type + " p);"}) {
			for (int attempt = 0; attempt < 2; attempt++) {
				var vapi = VapiParser.parse (new SourceFile.from_text ("pointer-invalid.vapi", "// provenance\n" + declaration));
				assert (vapi.diagnostic == null);
				var empty = Parser.parse (new SourceFile.from_text ("empty.astra", ""));
				var result = SemanticAnalyzer.analyze (empty.unit, VapiNormalizer.normalize (vapi.file));
				int column = declaration.has_prefix ("void f(") ? 8 : 1;
				assert (result.program == null && result.diagnostic.format () == "pointer-invalid.vapi:2:%d: error: %s".printf (column, "unsupported foreign pointer type; C/VAPI supports only 'void*'"));
			}
		}
	}
	foreach (string op in new string[] {"+", "-", "*", "/", "%", "<", "<=", ">", ">="}) {
		reject_source ("void f(void* p, void* q) { bool b = p " + op + " q; }", "operator '" + op + "' requires an 'int' operand, found 'void*'");
		reject_source ("void f(void* p) { void* x = p " + op + " 1; }", "operator '" + op + "' requires an 'int' operand, found 'void*'");
	}
	reject_source ("void f(void* p) { if (p) {} }", "if condition must have type 'bool', found 'void*'");
	reject_source ("void f(void* p) { while (p) {} }", "while condition must have type 'bool', found 'void*'");
	reject_source ("void f() { int x = null; }", "expected initializer of type 'int', found 'void*'");
	reject_source ("void f() { bool x = null; }", "expected initializer of type 'bool', found 'void*'");
	reject_source ("void f() { void* x = 0; }", "expected initializer of type 'void*', found 'int'");
	reject_source ("void f() { void* x = true; }", "expected initializer of type 'void*', found 'bool'");
	reject_source ("void f() { void* x = null; x = true; }", "expected assignment value of type 'void*', found 'bool'");
	reject_source ("bool f(void* p) { return !p; }", "operator '!' requires a 'bool' operand, found 'void*'");
	reject_source ("void f() { void* x = null; x = 1; }", "expected assignment value of type 'void*', found 'int'");
	reject_source ("void* f() { return 0; }", "expected return value of type 'void*', found 'int'");
	reject_source ("int add(int a, int b) { return a + b; } int f() { return add(null, 1); }", "argument 1 of function 'add' expects type 'int', provided 'void*'");
	foreach (string value in new string[] {"1", "true"}) {
		reject_source ("bool f(void* p) { return p == " + value + "; }", "operator '==' requires matching non-void operands, found 'void*' and '" + (value == "1" ? "int" : "bool") + "'");
	}
	reject_source ("extern(C) bool f(void* p);", "extern(C) result type must be 'int', 'void*' or 'void'; foreign bool is unsupported");
	reject_source ("export(C) void* f(bool p) { return null; }", "export(C) parameter type must be 'int' or 'void*'; foreign bool is unsupported");
	foreach (string text in new string[] {"void* f(void* p) { return *p; }", "void* f(int x) { return &x; }", "int f(void* p) { return (int)p; }", "void* f(int x) { return (void*)x; }", "void* f() { void* p; return null; }", "void (*callback)();"}) {
		var parsed = Parser.parse (new SourceFile.from_text ("unsupported.astra", text));
		if (text.contains ("*p;")) {
			assert (parsed.diagnostic == null);
			assert (SemanticAnalyzer.analyze (parsed.unit).diagnostic.message.contains ("dereference requires a typed pointer"));
		} else if (text.contains ("&x")) {
			assert (parsed.diagnostic == null);
			assert (SemanticAnalyzer.analyze (parsed.unit).diagnostic.message == "address borrow requires a direct local integer, f32, numeric vector, or native struct variable");
		} else {
			assert (parsed.diagnostic != null);
		}
	}
	var cfg = CfgBuilder.build (CoreBuilder.build (check ("void* partial(bool c) { if (c) { return null; } }")));
	assert (CfgFlowChecker.check (cfg).diagnostic != null);
}

private void promotion() throws GLib.Error {
	var core = CoreBuilder.build (check (fixture ("ptr-merge.astra"), declarations ("ptr-merge")));
	assert (core.functions[0].locals[0] is CoreLocalPlace && core.functions[0].locals[0].semantic_type.kind == TypeKind.RAW_POINTER);
	var initialized = (CoreInitialize) core.functions[0].body.statements[0];
	assert (initialized.value is CoreNullPointerValue && initialized.target == core.functions[0].locals[0]);
	var cfg = CfgBuilder.build (core);
	assert (cfg.functions[0].locals[0] is CfgLocalPlace);
	assert (((CfgInitialize) cfg.functions[0].blocks[0].instructions[0]).value is CfgNullPointerValue);
	var ssa = SsaBuilder.build (cfg);
	var choose = ssa.functions[0];
	assert (choose.blocks[3].parameters.length == 1 && choose.blocks[3].parameters[0].semantic_type.kind == TypeKind.RAW_POINTER);
	assert (((SsaBranch) choose.blocks[1].terminator).edge.arguments[0] == choose.parameters[1]);
	assert (((SsaBranch) choose.blocks[2].terminator).edge.arguments[0] == choose.parameters[2]);
	assert (((SsaReturn) choose.blocks[3].terminator).value == choose.blocks[3].parameters[0]);
	var maybe = ssa.functions[1];
	assert (((SsaConditionalBranch) maybe.blocks[0].terminator).false_edge.arguments[0] is SsaNullPointerConstant);
	assert (maybe.blocks[2].parameters[0].semantic_type.kind == TypeKind.RAW_POINTER);
	var loop = ssa.functions[2];
	assert (loop.blocks[1].parameters.length == 2 && loop.blocks[1].parameters[1].semantic_type.kind == TypeKind.RAW_POINTER);
	assert (((SsaBranch) loop.blocks[0].terminator).edge.arguments[1] == loop.parameters[1]);
	assert (((SsaBranch) loop.blocks[2].terminator).edge.arguments[1] == loop.parameters[2]);
	string dump = SsaDump.format (ssa);
	assert (dump == fixture ("ptr-merge.ssa"));
	foreach (string storage in new string[] {"(local", "(load", "(store", "(initialize", "(place"}) {
		assert (!dump.contains (storage));
	}
	var straight = build ("void* identity(void* p) { void* copy = null; copy = p; return copy; }");
	assert (straight.functions[0].blocks[0].instructions.length == 0);
	assert (((SsaReturn) straight.functions[0].blocks[0].terminator).value == straight.functions[0].parameters[0]);
}

private void profiles() throws GLib.Error {
	string[] programs = {
		"int f(int x) { return x; } bool b(bool x) { return x; }", "int f() { void* p = null; if (p == null) { return 0; } return 1; }", "void* f() { return null; }", "void f(void* p) {}", "export(C) int e(int x) { return x; } export(C) void* ep(void* p) { return p; } bool b(bool x) { return x; }"
	};
	for (int i = 0; i < programs.length; i++) {
		var ssa = build (programs[i], i == 4 ? "int scalar(int x); void* pointer(void* p);" : "");
		var nabi = NativeAbiBuilder.build (ssa);
		assert (nabi.abi_version == (i < 2 ? NativeAbiVersion.SCALAR_V0 : NativeAbiVersion.SCALAR_PTR_V1));
		foreach (var function in nabi.functions) {
			assert (function.signature.abi_version == nabi.abi_version);
		}
		var cabi = CAbiBuilder.build (ssa, nabi);
		assert (cabi.profile == (i == 4 ? CAbiProfile.SCALAR_PTR_V1 : CAbiProfile.SCALAR_V0));
		if (i == 4) {
			assert (nabi.functions[0].signature.result.scalar_type == NativeScalarType.I32 && nabi.functions[1].signature.result.scalar_type == NativeScalarType.PTR && nabi.functions[2].signature.result.scalar_type == NativeScalarType.B1);
			assert (cabi.functions.length == 2 && cabi.exports.length == 2);
			assert (cabi.functions[0].signature.result.scalar_type == CAbiScalarType.I32 && cabi.functions[1].signature.result.scalar_type == CAbiScalarType.PTR);
			assert (cabi.exports[0].signature.result.scalar_type == CAbiScalarType.I32 && cabi.exports[1].signature.result.scalar_type == CAbiScalarType.PTR);
			assert (CAbiDump.format (cabi).has_prefix ("(c-abi scalar-ptr-v1"));
		}
	}
	foreach (string declaration in new string[] {"void* imported();", "void imported(void* p);"}) {
		var ssa = build ("int main() { return 0; }", declaration);
		var nabi = NativeAbiBuilder.build (ssa);
		assert (nabi.abi_version == NativeAbiVersion.SCALAR_V0);
		assert (CAbiBuilder.build (ssa, nabi).profile == CAbiProfile.SCALAR_PTR_V1);
	}
}

private void differential() throws GLib.Error {
	foreach (string name in new string[] {"ptr-native", "ptr-null", "ptr-cimport", "ptr-merge", "ptr-shortcircuit"}) {
		string text = fixture (name + ".astra");
		string vapi = fixture ("pointer-basic.vapi");
		var source = check (text, vapi, true);
		var foreign = check (text, vapi);
		assert (SemanticDump.format (source) == SemanticDump.format (foreign));
		var a_core = CoreBuilder.build (source);
		var b_core = CoreBuilder.build (foreign);
		assert (CoreDump.format (a_core) == CoreDump.format (b_core));
		var a_cfg = CfgBuilder.build (a_core);
		var b_cfg = CfgBuilder.build (b_core);
		assert (CfgDump.format (a_cfg) == CfgDump.format (b_cfg));
		var a = SsaBuilder.build (a_cfg);
		var b = SsaBuilder.build (b_cfg);
		assert (SsaDump.format (a) == SsaDump.format (b));
		var a_nabi = NativeAbiBuilder.build (a);
		var b_nabi = NativeAbiBuilder.build (b);
		assert (NativeAbiDump.format (a_nabi) == NativeAbiDump.format (b_nabi));
		assert (CAbiDump.format (CAbiBuilder.build (a, a_nabi)) == CAbiDump.format (CAbiBuilder.build (b, b_nabi)));
	}
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/ptr/syntax-canonical-type-null", syntax_and_types);
	add ("/ptr/source-vapi-diagnostics", diagnostics);
	add ("/ptr/place-ssa-branch-null-loop", promotion);
	add ("/ptr/independent-abi-profiles", profiles);
	add ("/ptr/source-vapi-differential", differential);
	register_lifetime ();
	register_malformed ();
	int status = Test.run ();
	cases = null;
	return status;
}

}
