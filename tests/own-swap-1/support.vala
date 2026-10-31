// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.OwnSwapPipeline {
private void recovery() {
	try {
		for (int repeat = 0; repeat < 3; repeat++) {
			foreach (var bad in new string[] { "void f<T>(owned T[] a,owned T[] b){release a;swap(a,b);}", "void f<T,U>(owned T[] a,owned U[] b){swap(a,b);}", "void f<T>(owned T[] a,owned T[] b,bool flag){if(flag){release b;}swap(a,b);}" }) {
				var parsed = Parser.parse (new SourceFile.from_text ("bad-exchange.astra", bad));
				assert (parsed.diagnostic == null);
				var checked = SemanticAnalyzer.analyze (parsed.unit);
				assert (checked.diagnostic != null && checked.program == null);
			}
			foreach (var bad in new string[] { "struct Box<T>{T value;}T expand<T>(T input){Box<T> box={value=input};Box<T> copy=expand(box);return input;}void f<T>(owned T[] a,owned T[] b,T x){swap(a,b);T y=expand(x);}void root(){var a=new int[2];var b=new int[3];f(move a,move b,1);}", "struct Cycle<T>{Cycle<T> value;}void f<T>(owned T[] a,owned T[] b){swap(a,b);}void root(Cycle<int>* p){}" }) {
				Astra.Syntax.ParseResult? parsed = Parser.parse (new SourceFile.from_text ("growth-exchange.astra", bad));
				assert (parsed.diagnostic == null);
				SemanticResult? checked = SemanticAnalyzer.analyze (parsed.unit);
				parsed = null;
				if (bad.has_prefix ("struct Box<T>")) {
					assert (checked.program == null && checked.diagnostic != null);
					assert (checked.diagnostic.message.contains ("generic materialization limit exceeded: type-expression depth 128"));
					continue;
				}
				assert (checked.diagnostic == null);
				CoreProgram? core = CoreBuilder.build (checked.program);
				checked = null;
				CoreVerifier.verify (core);
				var graph = WeakRef (core);
				var definition = WeakRef (core.generic_functions[0]);
				bool rejected = false;
				try {
					CoreGenericMonomorphizer.build (core);
				} catch (CoreError error) {
					Test.message ("expected bounded failure: %s", error.message);
					rejected = true;
				}
				assert (rejected);
				core = null;
				assert (graph.get () == null && definition.get () == null);
			}
			SsaVerifier.verify (build ());
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private SsaProgram build() throws GLib.Error {
	string source;
	FileUtils.get_contents ("tests/own-swap-1/fixtures/slots.astra", out source);
	ParseResult? parsed = Parser.parse (new SourceFile.from_text ("own-swap/slots.astra", source));
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.format ());
	}
	var syntax = WeakRef (parsed.unit);
	SemanticResult? result = SemanticAnalyzer.analyze (parsed.unit);
	parsed = null;
	assert (syntax.get () == null);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	CheckedProgram? checked = result.program;
	result = null;
	var checked_function = WeakRef (checked.functions[0]);
	var universe = WeakRef (checked.types);
	CoreProgram? core = CoreBuilder.build (checked);
	checked = null;
	assert (checked_function.get () == null && universe.get () == null);
	CoreVerifier.verify (core);
	var old_core = WeakRef (core);
	var old_function = WeakRef (core.generic_functions[0]);
	core = CoreGenericMonomorphizer.build (core);
	assert (old_core.get () == null && old_function.get () == null);
	CoreVerifier.verify (core);
	var core_function = WeakRef (core.functions[0]);
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	assert (core_function.get () == null);
	CfgVerifier.verify (cfg);
	var flow = CfgFlowChecker.check (cfg);
	if (flow.diagnostic != null) {
		GLib.error ("%s", flow.diagnostic.format ());
	}
	var cfg_function = WeakRef (cfg.functions[0]);
	var ssa = SsaBuilder.build (cfg);
	cfg = null;
	assert (cfg_function.get () == null);
	SsaVerifier.verify (ssa);
	return ssa;
}
}
