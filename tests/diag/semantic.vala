// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Text;

namespace Astra.Tests.DiagSemantic {
private const string CHECK = "void check(int value, [CallerFilePath] string file, [CallerLineNumber] int line, [CallerArgumentExpression(\"value\")] string expression){}\n";
private CheckedProgram analyze(string text, string path = "diag.astra") {
	var parsed = Parser.parse (new SourceFile.from_text (path, text));
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.format ());
	}
	var result = SemanticAnalyzer.analyze (parsed.unit);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}
private void text_is(CheckedExpression expression, string expected) {
	assert (expression is CheckedTextExpression);
	assert (((CheckedTextExpression) expression).payload.equal_content (new TextBytes (expected.data)));
}
private void capture() {
	var p = analyze (CHECK + "void test(){\r\n\t/* français 😀 */ check( /* outside */ (1 /* inside */ +\r\n\t2) /* outside */ );\r\n}", "./sub//file.astra");
	var call = (CheckedCallStatement) p.functions[1].body.statements[0];
	assert (call.arguments.length == 4 && call.target == p.functions[0].symbol);
	text_is (call.arguments[1], "sub/file.astra");
	assert (((CheckedIntegerExpression) call.arguments[2]).value.mathematical_value == 3);
	text_is (call.arguments[3], "(1 /* inside */ +\r\n\t2)");
	var parameter = p.functions[0].symbol.parameters[3];
	assert (parameter.caller_information.kind == CallerInformationKind.ARGUMENT_EXPRESSION && parameter.caller_information.target_ordinal == 0 && parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
	p = analyze ("void show(string value,[CallerArgumentExpression(\"value\")] string expression){} void f(){show(\"a\\0b\");}");
	call = (CheckedCallStatement) p.functions[1].body.statements[0];
	assert (((CheckedTextExpression) call.arguments[0]).payload.hex () == "610062");
	text_is (call.arguments[1], "\"a\\0b\"");
}
private void explicit_prefixes() {
	var p = analyze (CHECK + "void f(string file,int line,string expression){check(1);check(2,file);check(3,file,line);check(4,file,line,expression);}");
	for (int i = 0; i < 4; i++) {
		var call = (CheckedCallStatement) p.functions[1].body.statements[i];
		assert (call.arguments.length == 4);
		for (int j = 1; j <= i; j++) {
			assert (((CheckedParameterReferenceExpression) call.arguments[j]).parameter == p.functions[1].symbol.parameters[j - 1]);
		}
		if (i < 3) {
			text_is (call.arguments[3], (i + 1).to_string ());
		}
	}
	string[] annotations = {
		"[CallerFilePath] borrowed string file", "[CallerLineNumber] i32 line", "[CallerArgumentExpression(\"value\")] string expression"
	};
	for (int a = 0; a < 3; a++) {
		for (int b = 0; b < 3; b++) {
			for (int c = 0; c < 3; c++) {
				if (a == b || a == c || b == c) {
					continue;
				}
				p = analyze ("void check(int value," + annotations[a] + "," + annotations[b] + "," + annotations[c] + "){} void f(){check(7);}");
				assert (CallerInformation.minimum_arguments (p.functions[0].symbol) == 1);
			}
		}
	}
}
private void generics() {
	var p = analyze ("T id<T>(T x,[CallerArgumentExpression(\"x\")] string expression,[CallerLineNumber] int line){return x;}\nT outer<T>(T x){return id(x);}\nint a(){return id(1);}\nint b(){return id<int>(2);}\nf64 c(){return id(2.0d);}");
	var outer = p.generic_functions[1];
	var call = (CheckedGenericCall) ((CheckedReturnStatement) outer.body.statements[0]).expression;
	assert (call.type_arguments[0] == outer.definition.type_parameters[0].semantic_type && call.type_arguments[0] != p.generic_functions[0].definition.type_parameters[0].semantic_type);
	text_is (call.arguments[1], "x");
	assert (((CheckedIntegerExpression) call.arguments[2]).value.mathematical_value == 2);
	foreach (var function in p.functions) {
		call = (CheckedGenericCall) ((CheckedReturnStatement) function.body.statements[0]).expression;
		assert (call.arguments.length == 3);
	}
	p = analyze ("owned T take<T>(owned T x,[CallerArgumentExpression(\"x\")] string expression) where T:Ownable{return move x;} owned T outer<T>(owned T x) where T:Ownable{return take(move x);}");
	var flow = new SemanticOwnershipFlow (p.span);
	var owner = new Object ();
	var discarded = new SemanticOwnershipFlow (p.span);
	discarded.move (owner, "x", p.span);
	flow.move (owner, "x", p.span);
	assert (flow.verify ());
	var duplicate = new SemanticOwnershipFlow (p.span);
	duplicate.append (discarded);
	duplicate.move (owner, "x", p.span);
	assert (!duplicate.verify ());
}
private void forged_contracts() {
	var source = new SourceFile.from_text ("forged.astra", "function parameter annotation target");
	var types = new BuiltinTypes ();
	var other_types = new BuiltinTypes ();
	var all = SourceSpan (source, 0, source.length);
	var name = SourceSpan (source, 0, 8);
	var annotation = SourceSpan (source, 9, 18);
	var parameter_name = SourceSpan (source, 19, 29);
	for (int defect = 0; defect < 11; defect++) {
		var parameters = new GenericArray<ParameterSymbol> ();
		var first = new ParameterSymbol (all, name, types.bool_type, 0);
		parameters.add (first);
		var type = defect == 2 ? types.int_type : defect == 3 ? other_types.string_type : types.string_type;
		var parameter = new ParameterSymbol (all, parameter_name, type, defect == 6 ? 12 : 1, defect == 4 ? PointerParameterContract.OWNED_TRANSFER : PointerParameterContract.BORROWED_NOESCAPE);
		var kind = defect == 0 ? (CallerInformationKind) 99 : defect == 5 ? CallerInformationKind.FILE_PATH : CallerInformationKind.ARGUMENT_EXPRESSION;
		parameter.caller_information = new CallerInformationContract (kind, defect == 7 ? SourceSpan (source, 0, 0) : annotation, defect == 1 ? 1 : 0);
		parameters.add (parameter);
		if (defect == 8) {
			parameters.add (new ParameterSymbol (all, name, types.int_type, 2));
		}
		DirectCallableSymbol symbol = defect == 9 ? (DirectCallableSymbol) new CFunctionSymbol (all, name, types.void_type, parameters) : new FunctionSymbol (all, name, types.void_type, parameters);
		assert (CallerInformation.validate (symbol, types, defect == 10) != null);
	}
}
private void missing_ranges() {
	var p = analyze (CHECK);
	var target = p.functions[0].symbol;
	var file = new SourceFile.from_text ("call.astra", "check(1)");
	var id = new Token (TokenKind.IDENTIFIER, SourceSpan (file, 0, 5));
	var open = new Token (TokenKind.OPEN_PAREN, SourceSpan (file, 5, 6));
	var close = new Token (TokenKind.CLOSE_PAREN, SourceSpan (file, 7, 8));
	var args = new GenericArray<ExpressionSyntax> ();
	args.add (new IntegerLiteralExpressionSyntax (new Token (TokenKind.INTEGER, SourceSpan (file, 6, 6))));
	var call = new CallExpressionSyntax (id, open, args, new GenericArray<Token> (), close);
	Diagnostic? error;
	assert (CallerInformation.complete (call, target, p.types, out error) == null && error.message.contains ("written-argument source range"));
	args[0] = new IntegerLiteralExpressionSyntax (new Token (TokenKind.INTEGER, SourceSpan (file, 6, 7)));
	call = new CallExpressionSyntax (new Token (TokenKind.IDENTIFIER, SourceSpan (file, 0, 0)), open, args, new GenericArray<Token> (), close);
	assert (CallerInformation.complete (call, target, p.types, out error) == null && error.message.contains ("call-name source range"));
	while (args.length < 4) {
		args.add (args[0]);
	}
	assert (CallerInformation.complete (call, target, p.types, out error).length == 0 && error == null);
	file = new SourceFile.from_text ("bad\xff.astra", "void f(){check(1);}");
	var parsed = Parser.parse (file);
	assert (parsed.diagnostic == null);
	var invalid = ((CallStatementSyntax) parsed.unit.functions[0].body.statements[0]).call;
	assert (CallerInformation.complete (invalid, target, p.types, out error) == null && error.message.contains ("not representable"));
}
private void detached_source() {
	try {
		string directory = Environment.get_variable ("DIAG_OUTPUT");
		assert (directory != null);
		DirUtils.create_with_parents (directory, 0700);
		string path = Path.build_filename (directory, "removed.astra");
		FileUtils.set_contents (path, CHECK + "void f(){check((123));}");
		string bytes;
		FileUtils.get_contents (path, out bytes);
		var parsed = Parser.parse (new SourceFile.from_text ("relative/removed.astra", bytes));
		assert (parsed.diagnostic == null);
		FileUtils.set_contents (path, "deleted after parsing");
		assert (FileUtils.unlink (path) == 0);
		var checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.diagnostic == null);
		var call = (CheckedCallStatement) checked.program.functions[1].body.statements[0];
		text_is (call.arguments[1], "relative/removed.astra");
		text_is (call.arguments[3], "(123)");
	} catch (FileError error) {
		GLib.error ("%s", error.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/diag/semantic/exact-owned-source-bytes-crlf", capture);
	Test.add_func ("/diag/semantic/positional-prefixes-and-orders", explicit_prefixes);
	Test.add_func ("/diag/semantic/generic-exact-outer-and-proofs", generics);
	Test.add_func ("/diag/semantic/independent-forged-contracts", forged_contracts);
	Test.add_func ("/diag/semantic/missing-ranges-and-explicit-calls", missing_ranges);
	Test.add_func ("/diag/semantic/source-changed-and-deleted", detached_source);
	return Test.run ();
}
}
