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
private const string EXPORTS = "int native_user(int x) { return add(x, 2); } export(C) int add(int a, int b) { return a + b; } extern(C) int c_one(int x); export(C) void record(int x) { c_one(x); return; } export(C) int recurse(int x) { if (x == 0) { return 0; } return recurse(x - 1) + x; }";

private void export_grammar() throws GLib.Error {
	var source = new SourceFile.from_text ("export.astra", "export(C) int C(int C) { return C; } export(C) void empty() {}");
	var lexer = new Lexer (source);
	assert (lexer.next_token ().kind == TokenKind.EXPORT);
	assert (lexer.next_token ().kind == TokenKind.OPEN_PAREN);
	assert (lexer.next_token ().kind == TokenKind.IDENTIFIER);
	var parsed = Parser.parse (source);
	assert (parsed.diagnostic == null && parsed.unit.functions.length == 2);
	var syntax = parsed.unit.functions[0];
	assert (syntax.export_keyword != null && syntax.extern_keyword == null && syntax.semicolon == null && syntax.body != null);
	assert (syntax.abi_identifier.spelling () == "C" && syntax.span.text () == "export(C) int C(int C) { return C; }");
	assert (SyntaxDump.format (parsed.unit).contains ("(function\n\t\t(export (abi C))"));
	var checked_result = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked_result.diagnostic == null && checked_result.program.functions[0].symbol.domain == CallableDomain.NATIVE);
	string[] sources = {
		"export(C) int f();", "export(C) extern(C) int f();", "extern(C) export(C) int f();",
		"export(C) export(C) int f() {}", "export C int f() {}", "export() int f() {}", "export(C int f() {}",
		"export(c) int f() { return 0; }", "export(Other) int f() { return 0; }",
		"export(C) bool f() { return true; }", "export(C) int f(bool x) { return 0; }", "export(C) int f(void x) { return 0; }",
		"export(C) int f() { return 0; } export(C) int f() { return 1; }", "extern(C) int f(); export(C) int f() { return 0; }",
		"export(C) int f() { return 0; } extern(C) int f();", "export(C) int f(int x) { return x; } int g() { return f(true); }"
	};
	string[] messages = {
		"export(C) requires a definition", "cannot be combined", "cannot be combined", "cannot be combined", "expected '('", "expected foreign ABI identifier", "expected ')'", "unsupported foreign ABI 'c'", "unsupported foreign ABI 'Other'", "export(C) result type must be 'int', 'void*' or 'void'; foreign bool is unsupported", "export(C) parameter type must be 'int' or 'void*'; foreign bool is unsupported", "parameter type cannot be 'void'", "duplicate function 'f'", "duplicate function 'f'", "duplicate function 'f'", "expects type 'int', provided 'bool'"
	};
	for (int i = 0; i < sources.length; i++) {
		string? previous = null;
		for (int attempt = 0; attempt < 2; attempt++) {
			var invalid = Parser.parse (new SourceFile.from_text ("invalid-export.astra", sources[i]));
			var semantic_result = invalid.diagnostic == null ? SemanticAnalyzer.analyze(invalid.unit) : null;
			var diagnostic = invalid.diagnostic ?? semantic_result.diagnostic;
			assert (diagnostic != null && diagnostic.message.contains (messages[i]));
			assert (diagnostic.span.text () != "" && (previous == null || previous == diagnostic.format ()));
			previous = diagnostic.format ();
		}
	}
}

private void export_identity_lifetime() throws GLib.Error {
	CheckedProgram? checked_program = check (EXPORTS);
	var checked_ref = WeakRef (checked_program);
	var export_ref = WeakRef (checked_program.c_exports[0]);
	var symbol_ref = WeakRef (checked_program.functions[1].symbol);
	var int_ref = WeakRef (checked_program.types.int_type);
	assert (checked_program.c_functions.length == 1 && checked_program.functions.length == 4 && checked_program.c_exports.length == 3);
	for (int e = 0; e < 3; e++) {
		assert (checked_program.c_exports[e].target == checked_program.functions[e + 1].symbol);
		assert (checked_program.c_exports[e].target.domain == CallableDomain.NATIVE && checked_program.c_exports[e].ordinal == e);
	}
	{
		var call = (CheckedCallExpression) ((CheckedReturnStatement) checked_program.functions[0].body.statements[0]).expression;
		assert (call.target == checked_program.c_exports[0].target && call.target.domain == CallableDomain.NATIVE);
		var recursive = (CheckedBinaryExpression) ((CheckedReturnStatement) checked_program.functions[3].body.statements[1]).expression;
		assert (((CheckedCallExpression) recursive.left).target == checked_program.functions[3].symbol);
		assert (SemanticDump.format (checked_program).contains ("(c-export #0 (abi C) (target-function \"add\") (symbol \"add\"))"));
	}
	CoreProgram? core = CoreBuilder.build (checked_program);
	checked_program = null;
	assert (checked_ref.get () == null && export_ref.get () == null && symbol_ref.get () == null);
	CoreVerifier.verify (core);
	for (int e = 0; e < 3; e++) {
		assert (core.c_exports[e].target == core.functions[e + 1]);
	}
	assert (((CoreCallValue) ((CoreReturn) core.functions[0].body.statements[0]).value).target == core.functions[1]);
	assert (((CoreCallValue) ((CoreBinaryValue) ((CoreReturn) core.functions[3].body.statements[1]).value).left).target == core.functions[3]);
	assert (CoreDump.format (core).contains ("(c-export #0"));
	var core_ref = WeakRef (core);
	var core_export_ref = WeakRef (core.c_exports[0]);
	var core_target_ref = WeakRef (core.functions[1]);
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	assert (core_ref.get () == null && core_export_ref.get () == null && core_target_ref.get () == null);
	CfgVerifier.verify (cfg);
	for (int e = 0; e < 3; e++) {
		assert (cfg.c_exports[e].target == cfg.functions[e + 1]);
	}
	assert (((CfgCallInstruction) cfg.functions[0].entry.instructions[0]).target == cfg.functions[1]);
	int cfg_recursion = 0;
	foreach (var block in cfg.functions[3].blocks) {
		foreach (var instruction in block.instructions) {
			if (instruction is CfgCallInstruction) {
				assert (((CfgCallInstruction) instruction).target == cfg.functions[3]);
				cfg_recursion++;
			}
		}
	}
	assert (cfg_recursion == 1 && CfgDump.format (cfg).contains ("(c-export #0"));
	var cfg_ref = WeakRef (cfg);
	var cfg_export_ref = WeakRef (cfg.c_exports[0]);
	var cfg_target_ref = WeakRef (cfg.functions[1]);
	SsaProgram? ssa = SsaBuilder.build (cfg);
	cfg = null;
	assert (cfg_ref.get () == null && cfg_export_ref.get () == null && cfg_target_ref.get () == null);
	SsaVerifier.verify (ssa);
	for (int e = 0; e < 3; e++) {
		assert (ssa.c_exports[e].target == ssa.functions[e + 1]);
	}
	assert (((SsaCallInstruction) ssa.functions[0].entry.instructions[0]).target == ssa.functions[1]);
	int ssa_recursion = 0;
	foreach (var block in ssa.functions[3].blocks) {
		foreach (var instruction in block.instructions) {
			if (instruction is SsaCallInstruction) {
				assert (((SsaCallInstruction) instruction).target == ssa.functions[3]);
				ssa_recursion++;
			}
		}
	}
	assert (ssa_recursion == 1 && SsaDump.format (ssa).contains ("(c-export #0"));
	NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
	assert (nabi.functions.length == 4);
	foreach (var native in nabi.functions) {
		assert (native.linkage == NativeLinkage.NATIVE_INTERNAL);
	}
	assert (NativeAbiDump.format (nabi) == NativeAbiDump.format (NativeAbiBuilder.build (build (EXPORTS.replace ("export(C) ", "")))));
	CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
	assert (cabi.functions.length == 1 && cabi.exports.length == 3);
	assert (cabi.exports[0].signature.parameters.length == 2 && cabi.exports[0].signature.result.scalar_type == CAbiScalarType.I32);
	assert (cabi.exports[1].signature.parameters.length == 1 && cabi.exports[1].signature.result == null);
	for (int e = 0; e < 3; e++) {
		assert (cabi.exports[e].native_function_ordinal == e + 1 && cabi.exports[e].ordinal == e);
	}
	string dump = CAbiDump.format (cabi);
	assert (dump.contains ("(import #0") && dump.contains ("(export #0") && dump.contains ("(native-function #1)"));
	var ssa_ref = WeakRef (ssa);
	var ssa_export_ref = WeakRef (ssa.c_exports[0]);
	var ssa_target_ref = WeakRef (ssa.functions[1]);
	var nabi_ref = WeakRef (nabi);
	var native_ref = WeakRef (nabi.functions[1]);
	ssa = null;
	nabi = null;
	assert (ssa_ref.get () == null && ssa_export_ref.get () == null && ssa_target_ref.get () == null && int_ref.get () == null);
	assert (nabi_ref.get () == null && native_ref.get () == null);
	assert (CAbiDump.format (cabi) == dump && cabi.exports[0].external_symbol == "add" && cabi.exports[0].name_span.text () == "add");
	var cabi_ref = WeakRef (cabi);
	var physical_ref = WeakRef (cabi.exports[0]);
	var source_ref = WeakRef (cabi.span.file);
	cabi = null;
	assert (cabi_ref.get () == null && physical_ref.get () == null && source_ref.get () == null);
}

private void checked_export_rejection() throws GLib.Error {
	for (int expired = 0; expired < 2; expired++) {
		CheckedProgram? other = check ("export(C) int f() { return 0; }");
		var metadata = other.c_exports[0];
		var program = check ("int f() { return 0; }");
		program.c_exports.add (metadata);
		if (expired == 1) {
			other = null;
			assert (metadata.target == null);
		}
		try {
			CoreBuilder.build (program);
			assert_not_reached ();
		} catch (CoreError.INVALID_CHECKED_MODEL error) {
			assert (error.message.contains ("no exact native mapping"));
		}
	}
}

private void export_compatibility() throws GLib.Error {
	for (int mode = 0; mode < 10; mode++) {
		var ssa = build ("export(C) int f(int x) { return x; } int g(int x) { return x; }");
		var nabi = NativeAbiBuilder.build (ssa);
		var cabi = CAbiBuilder.build (ssa, nabi);
		var map = new HashTable<SsaFunction, NativeFunction> (direct_hash, direct_equal);
		for (int f = 0; f < ssa.functions.length; f++) {
			map.insert (ssa.functions[f], nabi.functions[f]);
		}
		var original = cabi.exports[0];
		var parameters = new GenericArray<CAbiParameter> ();
		parameters.add (original.signature.parameters[0]);
		var result = original.signature.result;
		int ordinal = mode == 0 ? 1 : mode == 1 ? 42 : 0;
		if (mode == 2) {
			parameters.remove_index (0);
		}
		if (mode == 3) {
			result = null;
		}
		if (mode == 4) {
			map.insert (ssa.functions[0], nabi.functions[1]);
		}
		if (mode == 5) {
			map.remove (ssa.functions[0]);
		}
		if (mode == 6) {
			parameters[0] = new CAbiParameter (ssa.span, ssa.span, "", 0, (CAbiScalarType) 99);
		}
		var exports = new GenericArray<CAbiExport> ();
		exports.add (new CAbiExport (ssa.span, ssa.span, mode == 7 ? "wrong" : "f", 0, new CAbiSignature (cabi.profile, parameters, result), ordinal));
		cabi = new CAbiProgram (ssa.span, cabi.profile, new GenericArray<CAbiFunction> (), exports);
		if (mode == 8) {
			exports.remove_index (0);
		}
		if (mode == 9) {
			var physical = nabi.functions[0];
			physical.signature.parameters[0] = new NativeParameter (ssa.span, ssa.span, "", 0, NativeScalarType.B1);
		}
		try {
			CAbiValidator.validate_exports (ssa, nabi, cabi, map);
			assert_not_reached ();
		} catch (CAbiError.INCOMPATIBLE_CALL error) {
			assert (error.message.contains ("export"));
		}
	}
	var ssa = build ("export(C) int f(int x) { return x; }");
	foreach (string text in new string[] {"", "bool f(int x) { return true; }", "int f(bool x) { return 0; }", "int f() { return 0; }"}) {
		try {
			CAbiBuilder.build (ssa, NativeAbiBuilder.build (build (text)));
			assert_not_reached ();
		} catch (CAbiError.INVALID_NATIVE_ABI error) {
			assert (error.message.contains ("C ABI planning error"));
		}
	}
}

private void register_exports() {
	add ("/cexport/grammar-and-diagnostics", export_grammar);
	add ("/cexport/identity-native-calls-recursion-lifetime", export_identity_lifetime);
	add ("/cexport/checked-invalid-target", checked_export_rejection);
	add ("/cexport/physical-compatibility", export_compatibility);
	register_export_malformed ();
}
}
