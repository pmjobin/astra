// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
namespace Astra.Tests.GenericBuffer {
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
				assert (function.object_storage.length == 0);
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
	for (int variant = 0; variant < 3; variant++) {
		ssa = build ("struct A{int x;}struct B{int x;}owned T[] relay<T>(owned T[] a){return move a;}owned A[] fa(owned A[] a){return relay(move a);}owned B[] fb(owned B[] b){return relay(move b);}");
		nabi = NativeAbiBuilder.build (ssa);
		map.remove_all ();
		for (int i = 0; i < ssa.functions.length; i++) {
			map.insert (ssa.functions[i], nabi.functions[i]);
		}
		var original_function = nabi.functions[0];
		var original_signature = original_function.signature;
		// Construct an independent, self-consistent physical declaration. The
		// upstream signature remains sealed, so mutating it would correctly fail
		// the native verifier before reaching the intended SSA correspondence check.
		var owner_signature = new NativeSignature (original_signature.abi_version, original_signature.parameters, original_signature.result);
		owner_signature.buffer_result = original_signature.buffer_result;
		foreach (var parameter in original_signature.buffer_parameters) {
			owner_signature.buffer_parameters.add (parameter);
		}
		if (variant == 0) {
			owner_signature.buffer_result = new NativeBufferValuePlan.for_record (nabi.record_elements[1]);
		}
		if (variant == 1) {
			owner_signature.buffer_parameters.remove_index (0);
		}
		if (variant == 2) {
			owner_signature.buffer_result = null;
		}
		owner_signature.bind_buffer_transport ();
		var replacement = new NativeFunction (original_function.span, original_function.name_span, original_function.name,
			original_function.ordinal, owner_signature, original_function.linkage);
		replacement.bind_effects (original_function.effect_facts);
		replacement.bind_scoped_readonly (original_function.scoped_readonly, original_function.readonly_inputs,
			original_function.callback_inputs, original_function.callback_input_count, original_function.callback_contract_supported);
		replacement.claim_owner (nabi);
		nabi.functions[0] = replacement;
		map.insert (ssa.functions[0], replacement);
		NativeAbiVerifier.verify (nabi);
		rejected = false;
		try {
			NativeAbiValidator.validate_ssa_calls (ssa, nabi, map);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
	}
}

private void recovery() throws GLib.Error {
	for (int repeat = 0; repeat < 3; repeat++) {
		foreach (string bad in new string[] {"void f<T>(owned T[] a){release a;var n=len(a);}", "void drop<T>(owned T[] a){}void f<T>(owned T[] a){drop(move a);drop(move a);}", "void f<T>(T[] a,T x){}void root(f64[] a){f(a,1.0);}", "void f<T>(owned T[] a,T x){}void root(){var a=new f64[1];f(move a,1.0);}"}) {
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

private void cleanup_rank() throws GLib.Error {
	var checked = check ("struct S{int x;f64 y;}class Token{init(){}deinit(){}}V finish<V,U>(V snapshot,owned U companion) where U : Ownable{Token token=Token.init();return snapshot;}void root(S value){var token=Token.init();var saved=finish(value,move token);}");
	var core = CoreGenericMonomorphizer.build (CoreBuilder.build (checked));
	bool found = false;
	foreach (var function in core.functions) {
		if (function.generic_instance != null) {
			assert (function.object_storage.length == 1 && function.object_storage[0].cleanup_rank == 2 && function.locals[2].semantic_type is ClassType);
			found = true;
		}
	}
	assert (found);
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/gen-buffer/pipeline/graph-lifetimes-and-erasure", lifetime);
	add ("/gen-buffer/pipeline/independent-valid-wrong-element-plan", correspondence);
	add ("/gen-buffer/pipeline/failure-growth-cycle-success", recovery);
	add ("/gen-buffer/pipeline/record-parameter-object-cleanup-rank-remapping", cleanup_rank);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
