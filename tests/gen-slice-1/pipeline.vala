// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
namespace Astra.Tests.GenericSlice {
private void lifetime() throws GLib.Error {
	for (int repeat = 0; repeat < 3; repeat++) {
		ParseResult? syntax = Parser.parse (new SourceFile.from_text ("slice.astra", fixture ("basic")));
		assert (syntax.diagnostic == null);
		var ast = WeakRef (syntax.unit);
		var analyzed = SemanticAnalyzer.analyze (syntax.unit);
		syntax = null;
		assert (ast.get () == null && analyzed.diagnostic == null);
		CheckedProgram? checked = analyzed.program;
		analyzed = null;
		var definition = WeakRef (checked.generic_functions[0]);
		var universe = WeakRef (checked.types);
		CoreProgram? parameterized = CoreBuilder.build (checked);
		checked = null;
		assert (definition.get () == null && universe.get () == null);
		CoreVerifier.verify (parameterized);
		var generic_function = WeakRef (parameterized.generic_functions[0]);
		var obligation = WeakRef (parameterized.generic_functions[0].element_obligations);
		var generic_struct = WeakRef (parameterized.generic_structs[0]);
		CoreProgram? core = CoreGenericMonomorphizer.build (parameterized);
		parameterized = null;
		assert (generic_function.get () == null && obligation.get () == null && generic_struct.get () == null);
		CoreVerifier.verify_concrete (core);
		var core_graph = WeakRef (core);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (core_graph.get () == null);
		CfgVerifier.verify (cfg);
		assert (CfgFlowChecker.check (cfg).diagnostic == null);
		var cfg_graph = WeakRef (cfg);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (cfg_graph.get () == null);
		SsaVerifier.verify (ssa);
		foreach (var function in ssa.functions) {
			if (function.name.has_prefix ("astra.gen.")) {
				assert (function.storage.length == 0);
			}
			foreach (var block in function.blocks) {
				foreach (var parameter in block.parameters) {
					assert (!parameter.semantic_type.is_struct_storage () && !parameter.semantic_type.is_parameterized ());
				}
			}
		}
		var ssa_graph = WeakRef (ssa);
		var semantic_type = WeakRef (ssa.structs[0].semantic_type);
		var nabi = NativeAbiBuilder.build (ssa);
		var cabi = CAbiBuilder.build (ssa, nabi);
		ssa = null;
		assert (ssa_graph.get () == null && semantic_type.get () == null);
		NativeAbiVerifier.verify (nabi);
		CAbiVerifier.verify (cabi);
	}
}
private void correspondence() throws GLib.Error {
	var ssa = build ("struct A{int x;}struct B{int x;}void fill<T>(T[] a,T x){a[0]=x;}void fa(A[] a,A x){fill(a,x);}void fb(B[] a,B x){fill(a,x);}");
	var nabi = NativeAbiBuilder.build (ssa);
	assert (nabi.abi_version == NativeAbiVersion.STRUCT_ELEMENTS_V11 && nabi.record_elements.length == 2);
	var map = new HashTable<SsaFunction, NativeFunction> (direct_hash, direct_equal);
	for (int i = 0; i < ssa.functions.length; i++) {
		map.insert (ssa.functions[i], nabi.functions[i]);
	}
	NativeAbiValidator.validate_ssa_calls (ssa, nabi, map);
	var signature = nabi.functions[2].signature;
	var original = signature.parameters[0];
	signature.parameters[0] = new NativeParameter.typed (original.span, original.name_span, original.name, original.ordinal, new NativeRecordSliceType (nabi.record_elements[1]));
	NativeAbiVerifier.verify (nabi);
	bool rejected = false;
	try {
		NativeAbiValidator.validate_ssa_calls (ssa, nabi, map);
	} catch (NativeAbiError error) {
		rejected = true;
	}
	assert (rejected);
}
private void recovery() throws GLib.Error {
	for (int repeat = 0; repeat < 3; repeat++) {
		foreach (string bad in new string[] {"void f<T>(T[] a){a[0]=1;}", "void f<T>(T[] a){T[] b=null;}", "void f<T>(T[] a,T x){}void root(f64[] a){f(a,1.0);}"}) {
			var parsed = Parser.parse (new SourceFile.from_text ("bad.astra", bad));
			assert (parsed.diagnostic == null);
			var result = SemanticAnalyzer.analyze (parsed.unit);
			assert (result.diagnostic != null && result.program == null);
		}
		foreach (string bad in new string[] {"struct Box<T>{T value;}T grow<T>(T[] a){T saved=a[0];Box<T> box={value=saved};Box<T> grown=expand(box);return grown.value;}T expand<T>(T input){Box<T> box={value=input};Box<T> copy=expand(box);return input;}int root(int[] a){return grow(a);}", "struct Cycle<T>{Cycle<T> value;}void root(Cycle<int>* p){}"}) {
			// Exact expanding source remains negative at its earlier semantic
			// refusal; Cycle still exercises independent Core rejection.
			var parsed = Parser.parse (new SourceFile.from_text ("recovery.astra", bad));
			assert (parsed.diagnostic == null);
			var checked = SemanticAnalyzer.analyze (parsed.unit);
			if (bad.has_prefix ("struct Box<T>")) {
				assert (checked.program == null && checked.diagnostic != null);
				assert (checked.diagnostic.message.contains ("generic materialization limit exceeded: type-expression depth 128"));
				continue;
			}
			assert (checked.diagnostic == null && checked.program != null);
			CoreProgram? parameterized = CoreBuilder.build (checked.program);
			checked = null;
			parsed = null;
			var graph = WeakRef (parameterized);
			bool rejected = false;
			try {
				CoreGenericMonomorphizer.build (parameterized);
			} catch (CoreError error) {
				rejected = true;
			}
			assert (rejected);
			parameterized = null;
			assert (graph.get () == null);
		}
		SsaVerifier.verify (build (fixture ("basic")));
	}
}
int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/gen-slice/pipeline/graph-lifetimes-and-erasure", lifetime);
	add ("/gen-slice/pipeline/independent-valid-wrong-element-plan", correspondence);
	add ("/gen-slice/pipeline/failure-growth-cycle-success", recovery);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
