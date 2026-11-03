// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.CImports {
private const string MIXED = "int native(int x) { return x; } int main() { return native(c_one(1)) + c_two(2); } extern(C) int c_one(int x); extern(C) int c_two(int x); extern(C) void c_void();";
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
				GLib.error ("%s: %s", Test.get_path (), error.message);
			}
		});
}

private CheckedProgram check(string text = MIXED) {
	var parsed = Parser.parse (new SourceFile.from_text ("c-import.astra", text));
	assert (parsed.diagnostic == null);
	var result = SemanticAnalyzer.analyze (parsed.unit);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}

private SsaProgram build(string text = MIXED) throws GLib.Error {
	return SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (check (text))));
}

private void grammar() throws GLib.Error {
	var file = new SourceFile.from_text ("grammar.astra", "extern(C) int add(int a, int b); extern(C) void reset(); int C() { return 1; }");
	var lexer = new Lexer (file);
	assert (lexer.next_token ().kind == TokenKind.EXTERN);
	assert (lexer.next_token ().kind == TokenKind.OPEN_PAREN);
	assert (lexer.next_token ().kind == TokenKind.IDENTIFIER);
	var parsed = Parser.parse (file);
	assert (parsed.diagnostic == null && parsed.unit.functions.length == 3);
	var declaration = parsed.unit.functions[0];
	assert (declaration.extern_keyword != null && declaration.abi_identifier.spelling () == "C");
	assert (declaration.body == null && declaration.semicolon.kind == TokenKind.SEMICOLON);
	assert (declaration.parameters.length == 2 && declaration.span.text () == "extern(C) int add(int a, int b);");
	assert (parsed.unit.functions[2].extern_keyword == null && parsed.unit.functions[2].body != null);
	assert (SyntaxDump.format (parsed.unit).contains ("(extern-function"));
	assert (check ("extern(C) int main();").functions.length == 0);
}

private void diagnostics() throws GLib.Error {
	string[] sources = {
		"extern(C) int f() { return 1; }", "extern(C) int f()", "int f();", "extern C int f();", "extern() int f();", "extern(C) int f(int x,);",
		"extern(Whatever) int f();", "extern(c) int f();", "extern(C) bool f();", "extern(C) int f(bool x);", "extern(C) int f(void x);",
		"int f() { return 0; } extern(C) int f();", "extern(C) int f(); int f() { return 0; }", "extern(C) int f(); extern(C) int f(int x);",
		"extern(C) int f(int x); int main() { return f(true); }", "extern(C) void f(); int main() { return f(); }",
		"extern(C) int f(int x); int main() { return f(); }", "extern(C) int f(); int main() { return f(1); }",
		"extern(C) int f(int x, int x);", "extern(C) unknown f();", "extern(C) int f(unknown x);"
	};
	string[] messages = {
		"foreign declarations have no body", "foreign declarations have no body", "expected '{'", "expected '('", "expected foreign ABI identifier", "expected parameter type name", "unsupported foreign ABI 'Whatever'", "unsupported foreign ABI 'c'", "foreign bool is unsupported", "foreign bool is unsupported", "parameter type cannot be 'void'", "duplicate function 'f'", "duplicate function 'f'", "duplicate function 'f'", "expects type 'int', provided 'bool'", "cannot be used as a value", "expects 1 arguments, provided 0", "expects 0 arguments, provided 1", "duplicate parameter", "unknown type", "unknown type"
	};
	for (int i = 0; i < sources.length; i++) {
		string? previous = null;
		for (int attempt = 0; attempt < 2; attempt++) {
			var parsed = Parser.parse (new SourceFile.from_text ("invalid.astra", sources[i]));
			SemanticResult? semantic_result = parsed.diagnostic == null ? SemanticAnalyzer.analyze(parsed.unit) : null;
			var diagnostic = parsed.diagnostic ?? semantic_result.diagnostic;
			assert (diagnostic != null && diagnostic.message.contains (messages[i]));
			assert (previous == null || previous == diagnostic.format ());
			previous = diagnostic.format ();
		}
	}
}

private void identity_and_lifetime() throws GLib.Error {
	CheckedProgram? checked_program = check ();
	var checked_ref = WeakRef (checked_program);
	var symbol_ref = WeakRef (checked_program.c_functions[0]);
	var native_symbol_ref = WeakRef (checked_program.functions[0].symbol);
	var types_ref = WeakRef (checked_program.types);
	var int_ref = WeakRef (checked_program.types.int_type);
	{
		var expression = (CheckedBinaryExpression) ((CheckedReturnStatement) checked_program.functions[1].body.statements[0]).expression;
		var native_call = (CheckedCallExpression) expression.left;
		var c_call = (CheckedCallExpression) native_call.arguments[0];
		assert (native_call.target == checked_program.functions[0].symbol && native_call.target.domain == CallableDomain.NATIVE);
		assert (c_call.target == checked_program.c_functions[0] && c_call.target.domain == CallableDomain.C);
		assert (((CheckedCallExpression) expression.right).target == checked_program.c_functions[1]);
		assert (checked_program.c_functions[0].abi == ForeignAbi.C && checked_program.c_functions[0].external_symbol == "c_one");
		assert (SemanticDump.format (checked_program).contains ("(c-call \"c_one\""));
	}
	CoreProgram? core = CoreBuilder.build (checked_program);
	checked_program = null;
	assert (checked_ref.get () == null && symbol_ref.get () == null && native_symbol_ref.get () == null && types_ref.get () == null);
	CoreVerifier.verify (core);
	assert (CoreDump.format (core).contains ("(c-call \"c_one\""));
	{
		var expression = (CoreBinaryValue) ((CoreReturn) core.functions[1].body.statements[0]).value;
		var native_call = (CoreCallValue) expression.left;
		assert (native_call.target == core.functions[0]);
		assert (((CoreCCallValue) native_call.arguments[0]).target == core.c_functions[0]);
		assert (((CoreCCallValue) expression.right).target == core.c_functions[1]);
	}
	var core_ref = WeakRef (core);
	var core_c_ref = WeakRef (core.c_functions[0]);
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	assert (core_ref.get () == null && core_c_ref.get () == null);
	CfgVerifier.verify (cfg);
	assert (CfgDump.format (cfg).contains ("(c-call #0 \"c_one\""));
	{
		var block = cfg.functions[1].entry;
		assert (block.instructions.length == 3 && block.terminator.successors ().length == 0);
		assert (((CfgCCallInstruction) block.instructions[0]).target == cfg.c_functions[0]);
		assert (((CfgCallInstruction) block.instructions[1]).target == cfg.functions[0]);
		assert (((CfgCCallInstruction) block.instructions[2]).target == cfg.c_functions[1]);
	}
	var cfg_ref = WeakRef (cfg);
	var cfg_c_ref = WeakRef (cfg.c_functions[0]);
	SsaProgram? ssa = SsaBuilder.build (cfg);
	cfg = null;
	assert (cfg_ref.get () == null && cfg_c_ref.get () == null);
	SsaVerifier.verify (ssa);
	assert (SsaDump.format (ssa).contains ("c-call #0 \"c_one\""));
	{
		var block = ssa.functions[1].entry;
		assert (block.instructions.length == 4 && block.terminator.successors ().length == 0);
		assert (((SsaCCallInstruction) block.instructions[0]).target == ssa.c_functions[0]);
		assert (((SsaCallInstruction) block.instructions[1]).target == ssa.functions[0]);
		assert (((SsaCCallInstruction) block.instructions[2]).target == ssa.c_functions[1]);
	}
	NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
	CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
	assert (nabi.functions.length == 2 && cabi.functions.length == 3);
	assert (!NativeAbiDump.format (nabi).contains ("c_one") && !CAbiDump.format (cabi).contains ("native"));
	assert (cabi.functions[0].ordinal == 0 && nabi.functions[0].ordinal == 0);
	assert (cabi.functions[0].signature.parameters[0].scalar_type == CAbiScalarType.I32);
	assert (nabi.functions[0].signature.parameters[0].scalar_type == NativeScalarType.I32);
	var ssa_ref = WeakRef (ssa);
	var ssa_c_ref = WeakRef (ssa.c_functions[0]);
	var ssa_call_ref = WeakRef (ssa.functions[1].entry.instructions[0]);
	string dump = CAbiDump.format (cabi);
	ssa = null;
	assert (ssa_ref.get () == null && ssa_c_ref.get () == null && ssa_call_ref.get () == null && int_ref.get () == null);
	CAbiVerifier.verify (cabi);
	assert (CAbiDump.format (cabi) == dump && cabi.functions[0].external_symbol == "c_one");
	assert (cabi.functions[2].signature.result == null);
	var cabi_ref = WeakRef (cabi);
	var physical_ref = WeakRef (cabi.functions[0]);
	var source_ref = WeakRef (cabi.span.file);
	cabi = null;
	nabi = null;
	assert (cabi_ref.get () == null && physical_ref.get () == null && source_ref.get () == null);
}

private void expired_checked_call() throws GLib.Error {
	CheckedProgram? program = check ("extern(C) void c_void(); void native() { c_void(); }");
	var statement = (CheckedCallStatement) program.functions[0].body.statements[0];
	var target_ref = WeakRef (statement.target);
	program = null;
	assert (target_ref.get () == null && statement.target == null);
	var replacement = check ("void native() {}");
	replacement.functions[0].body.statements.add (statement);
	try {
		CoreBuilder.build (replacement);
		assert_not_reached ();
	} catch (CoreError.INVALID_CHECKED_MODEL error) {
		assert (error.message.contains ("call target is not owned"));
	}
}

private void fixtures() throws GLib.Error {
	foreach (string name in new string[] {"c-basic", "c-void", "c-order", "c-shortcircuit", "c-loop", "c-recursive-native", "c-missing-symbol", "c-trap-order"}) {
		string text;
		FileUtils.get_contents ("tests/cabi/fixtures/" + name + ".astra", out text);
		var ssa = build (text);
		var cabi = CAbiBuilder.build (ssa, Astra.NativeAbi.NativeAbiBuilder.build (ssa));
		var nabi = NativeAbiBuilder.build (ssa);
		assert (cabi.functions.length == ssa.c_functions.length && nabi.functions.length == ssa.functions.length);
		var rebuilt = build (text);
		assert (CAbiDump.format (cabi) == CAbiDump.format (CAbiBuilder.build (rebuilt, NativeAbiBuilder.build (rebuilt))));
	}
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/cabi/parser/grammar", grammar);
	add ("/cabi/frontend/diagnostics", diagnostics);
	add ("/cabi/identity-forward-lifetime", identity_and_lifetime);
	add ("/cabi/expired-checked-call", expired_checked_call);
	add ("/cabi/fixtures", fixtures);
	register_malformed ();
	register_exports ();
	int status = Test.run ();
	cases = null;
	return status;
}

}
