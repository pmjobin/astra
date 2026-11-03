// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
namespace Astra.Tests.AllocationFailure {
private CheckedProgram check(string text) {
	var syntax = Parser.parse (new SourceFile.from_text ("allocation-action.astra", text));
	if (syntax.diagnostic != null) {
		GLib.error ("%s", syntax.diagnostic.format ());
	}
	var result = SemanticAnalyzer.analyze (syntax.unit);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}

private SsaProgram build(string text) throws GLib.Error {
	var cfg = CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text))));
	var flow = CfgFlowChecker.check (cfg);
	if (flow.diagnostic != null) {
		GLib.error ("%s", flow.diagnostic.format ());
	}
	return SsaBuilder.build (cfg);
}

private const string SOURCE = "struct Box<T>{T value;}extern(C) void output(int code,int n);void report(int code,int n,[CallerFilePath] string file,[CallerLineNumber] int line,[CallerArgumentExpression(\"n\")] string text){output(code,n);}owned T[] make<T>(int n,int code){return new T[n] else report(code,n);}void root(){var a=make<Box<int>>(0,17);var b=make<Box<int>>(2,19);}";
}
