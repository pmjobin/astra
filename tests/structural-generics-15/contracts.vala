// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.Vapi;

private CheckedProgram check(string fixture) throws GLib.Error {
	string text;
	string path = "tests/structural-generics-15/" + fixture + ".astra";
	FileUtils.get_contents (path, out text);
	if (fixture == "owned-closure-async" || fixture == "generic-record-async" || fixture == "generic-storage-requirements" || fixture == "open-class-method-resource-results" || fixture == "open-class-method-owners" || fixture == "open-class-owning-members" || fixture == "open-class-lazy" || fixture == "generic-class-result-origins" || fixture == "symbolic-owned-callable-results" || fixture == "symbolic-consuming-callables" || fixture == "borrowed-callable-records" || fixture == "copied-callable-record-results" || fixture == "owning-callable-record-results" || fixture == "owned-callable-class-results" || fixture == "owned-callable-results" || fixture == "owning-record-callables" || fixture == "owned-callable-classes" || fixture == "copied-callable-fields" || fixture == "owned-callable-resources" || fixture == "closed-record-callables" || fixture == "copied-record-closure" || fixture == "borrowed-closure-channel" || fixture == "nested-buffer-producer" || fixture == "closed-closure-environment" || fixture == "owned-generic-async") {
		string errors;
		FileUtils.get_contents ("lib/astra/base/errors.astra", out errors);
		text += "\n" + errors;
	}
	if (fixture == "owned-closure-async" || fixture == "borrowed-callable-records" || fixture == "borrowed-closure-channel" || fixture == "borrowed-function-channel" || fixture == "readonly-buffer-view" || fixture == "borrowed-buffer-parameter" || fixture == "borrowed-record-getter" || fixture == "readonly-record-parameter") {
		string box;
		FileUtils.get_contents ("lib/astra/collections/box.astra", out box);
		text += "\n" + box;
	}
	if (fixture == "owned-closure-async" || fixture == "owned-generic-async" || fixture == "generic-record-async") {
		string runtime;
		FileUtils.get_contents ("lib/astra/async/virtual.astra", out runtime);
		text += "\n" + runtime;
	}
	var parsed = Parser.parse (new SourceFile.from_text (path, text));
	assert (parsed.diagnostic == null);
	SemanticResult result;
	if (fixture == "owned-closure-async" || fixture == "generic-owner-fresh-results" || fixture == "generic-owner-local-chains" || fixture == "dependent-fixed-Class-results" || fixture == "member-fixed-Class-factories" || fixture == "member-wrapper-result-origins" || fixture == "class-signature-origins" || fixture == "generic-storage-requirements" || fixture == "open-class-owned-formals" || fixture == "record-method-result-origins" || fixture == "method-result-origins" || fixture == "open-class-method-resource-results" || fixture == "open-class-method-owners" || fixture == "open-class-owning-members" || fixture == "open-class-lazy" || fixture == "generic-class-result-origins" || fixture == "symbolic-owned-callable-results" || fixture == "symbolic-consuming-callables" || fixture == "borrowed-callable-records" || fixture == "copied-callable-record-results" || fixture == "owning-callable-record-results" || fixture == "owned-callable-class-results" || fixture == "owned-callable-results" || fixture == "owning-record-callables" || fixture == "owned-callable-classes" || fixture == "copied-callable-fields" || fixture == "owned-callable-resources" || fixture == "closed-record-type-only" || fixture == "closed-record-callables" || fixture == "copied-record-closure" || fixture == "borrowed-closure-channel" || fixture == "borrowed-function-channel" || fixture == "borrowed-record-leaves" || fixture == "borrowed-record-getter" || fixture == "readonly-record-parameter" || fixture == "borrowed-buffer-parameter" || fixture == "borrowed-record-parameter" || fixture == "lexical-construction" || fixture == "owning-record-payload" || fixture == "owning-buffer-record" || fixture == "nested-buffer-producer" || fixture == "deferred-lifetimes" || fixture == "nested-field-observation" || fixture == "multiple-slot-fields" || fixture == "closed-closure-environment" || fixture == "closed-generic-dispatch" || fixture == "owned-generic-async" || fixture == "closed-class-owner-transport" || fixture == "owning-record-view" || fixture == "owning-buffer-view" || fixture == "readonly-buffer-view") {
		string api;
		FileUtils.get_contents ("tests/own-field/fixtures/resources.vapi", out api);
		var imported = VapiParser.parse (new SourceFile.from_text ("resources.vapi", api));
		assert (imported.diagnostic == null);
		result = SemanticAnalyzer.analyze (parsed.unit, VapiNormalizer.normalize (imported.file), VapiNormalizer.normalize_handles (imported.file));
	} else {
		result = SemanticAnalyzer.analyze (parsed.unit);
	}
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}

private CoreProgram core(string fixture) throws GLib.Error {
	return CoreGenericMonomorphizer.build (CoreBuilder.build (check (fixture)));
}

private void materialization_budget_independent() {
	try {
		string text = "class Marker<T>{init(){}} void choose<A,B,C,D,E,F,G,H,I,J,K,L,M,N,O>(){} int main(){var marker=new Marker<int>();choose<int,bool,int,int,int,int,int,int,int,int,int,int,int,int,int>();return 0;}";
		var parsed = Parser.parse (new SourceFile.from_text ("budget.astra", text));
		assert (parsed.diagnostic == null);
		var result = SemanticAnalyzer.analyze (parsed.unit);
		assert (result.diagnostic == null);
		CheckedProgram? checked = result.program;
		var predecessor = WeakRef (checked.generic_functions[0].definition);
		CoreProgram program = CoreBuilder.build (checked);
		checked = null;
		result = null;
		assert (predecessor.get () == null);
		CoreVerifier.verify (program);
		var origin = program.generic_functions[0];
		CoreFunction? root = null;
		foreach (var candidate in program.functions) {
			if (candidate.name == "main") {
				root = candidate;
			}
		}
		assert (root != null);
		CoreGenericCallStatement? first = null;
		foreach (var statement in root.body.statements) {
			if (statement is CoreGenericCallStatement) {
				first = (CoreGenericCallStatement) statement;
			}
		}
		assert (first != null && first.type_arguments.length == 15);
		var integer = first.type_arguments[0];
		var boolean = first.type_arguments[1];
		var pass = new CoreGenericMonomorphizer (program);
		CoreFunction? saved = null;
		for (int index = 0; index < 16383; index++) {
			var arguments = new GenericArray<SemanticType> ();
			for (int bit = 0; bit < 15; bit++) {
				arguments.add ((index & (1 << bit)) == 0 ? integer : boolean);
			}
			var instance = pass.request (origin, arguments, root);
			if (index == 0) {
				saved = instance;
			}
		}
		var repeated = new GenericArray<SemanticType> ();
		for (int bit = 0; bit < 15; bit++) {
			repeated.add (integer);
		}
		assert (pass.request (origin, repeated, root) == saved);
		var overflow = new GenericArray<SemanticType> ();
		for (int bit = 0; bit < 15; bit++) {
			overflow.add ((16383 & (1 << bit)) == 0 ? integer : boolean);
		}
		bool refused = false;
		try {
			pass.request (origin, overflow, root);
		} catch (CoreError error) {
			refused = error.message.contains ("at most 16384 closed instances; requesting choose<") && error.message.contains ("from main");
		}
		assert (refused && pass.request (origin, repeated, root) == saved);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private CheckedProgram callback_summary_checked() throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("callback-summary.astra",
		"class Sample{int value;init(int value){this.value=value;}} " +
		"int read_sample(borrowed Sample value){return value.value;} " +
		"int change_sample(borrowed Sample value){value.value=99;return value.value;} " +
		"int invoke_sample(borrowed Sample value,Fn<int,borrowed Sample> callback){return callback(value);} " +
		"int forward_sample(Fn<int,borrowed Sample> callback,borrowed Sample value){return invoke_sample(value,callback);} " +
		"int recursive_sample(bool stop,borrowed Sample value,Fn<int,borrowed Sample> callback){if(stop){return callback(value);}return recursive_sample(true,value,callback);} " +
		"int pure_sample(borrowed Sample value){return forward_sample(read_sample,value);} " +
		"int impure_sample(borrowed Sample value){return forward_sample(change_sample,value);} " +
		"int main(){var value=new Sample(42);return forward_sample(read_sample,value);} "));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	return checked.program;
}

private CoreProgram callback_summary_core_program() throws GLib.Error {
	return CoreGenericMonomorphizer.build (CoreBuilder.build (callback_summary_checked ()));
}

private SsaProgram callback_summary_program() throws GLib.Error {
	return SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (callback_summary_checked ()))));
}

private void callback_summary_source() {
	try {
		var program = callback_summary_checked ();
		var effects = ReadonlyInspection.infer_effects (program, (type) => null);
		int selected = 0;
		foreach (var definition in program.all_definitions ()) {
			var function = definition.symbol;
			var facts = effects.readonly_summary (function);
			assert (facts != null);
			if (function.name == "invoke_sample") {
				assert (facts.eligible && !facts.requires_input (0) && facts.requires_input (1));
				selected++;
			} else if (function.name == "forward_sample") {
				assert (facts.eligible && facts.requires_input (0) && !facts.requires_input (1));
				selected++;
			} else if (function.name == "recursive_sample") {
				assert (facts.eligible && !facts.requires_input (0) && !facts.requires_input (1) && facts.requires_input (2));
				selected++;
			} else if (function.name == "pure_sample" || function.name == "read_sample") {
				assert (facts.eligible && !facts.requires_input (0));
				selected++;
			} else if (function.name == "impure_sample" || function.name == "change_sample") {
				assert (!facts.eligible);
				selected++;
			}
		}
		assert (selected == 7);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void callback_summary_core() {
	try {
		CheckedProgram? previous = callback_summary_checked ();
		var predecessor = WeakRef (previous);
		var program = CoreGenericMonomorphizer.build (CoreBuilder.build (previous));
		previous = null;
		assert (predecessor.get () == null);
		var effects = CoreVerifier.infer_effects (program);
		int selected = 0;
		foreach (var function in program.functions) {
			var facts = effects.readonly_summary (function);
			assert (facts != null);
			if (function.name == "invoke_sample") {
				assert (facts.eligible && !facts.requires_input (0) && facts.requires_input (1));
				selected++;
			} else if (function.name == "forward_sample") {
				assert (facts.eligible && facts.requires_input (0) && !facts.requires_input (1));
				selected++;
			} else if (function.name == "recursive_sample") {
				assert (facts.eligible && !facts.requires_input (0) && !facts.requires_input (1) && facts.requires_input (2));
				selected++;
			} else if (function.name == "pure_sample" || function.name == "read_sample") {
				assert (facts.eligible && !facts.requires_input (0));
				selected++;
			} else if (function.name == "impure_sample" || function.name == "change_sample") {
				assert (!facts.eligible);
				selected++;
			}
		}
		assert (selected == 7);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void callback_summary_cfg() {
	try {
		CoreProgram? previous = callback_summary_core_program ();
		var predecessor = WeakRef (previous);
		var program = CfgBuilder.build (previous);
		previous = null;
		assert (predecessor.get () == null);
		var effects = CfgVerifier.infer_effects (program);
		int selected = 0;
		foreach (var function in program.functions) {
			var facts = effects.readonly_summary (function);
			assert (facts != null);
			if (function.name == "invoke_sample") {
				assert (facts.eligible && !facts.requires_input (0) && facts.requires_input (1));
				selected++;
			} else if (function.name == "forward_sample") {
				assert (facts.eligible && facts.requires_input (0) && !facts.requires_input (1));
				selected++;
			} else if (function.name == "recursive_sample") {
				assert (facts.eligible && !facts.requires_input (0) && !facts.requires_input (1) && facts.requires_input (2));
				selected++;
			} else if (function.name == "pure_sample" || function.name == "read_sample") {
				assert (facts.eligible && !facts.requires_input (0));
				selected++;
			} else if (function.name == "impure_sample" || function.name == "change_sample") {
				assert (!facts.eligible);
				selected++;
			}
		}
		assert (selected == 7);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void callback_summary_formals() {
	try {
		var program = callback_summary_program ();
		var inference = new SsaReadonlyInference (program);
		int selected = 0;
		foreach (var function in program.functions) {
			var facts = inference.summary (function);
			assert (facts != null);
			if (function.name == "invoke_sample") {
				assert (facts.eligible && !facts.requires_input (0) && facts.requires_input (1));
				selected++;
			} else if (function.name == "forward_sample") {
				assert (facts.eligible && facts.requires_input (0) && !facts.requires_input (1));
				selected++;
			} else if (function.name == "recursive_sample") {
				assert (facts.eligible && !facts.requires_input (0) && !facts.requires_input (1) && facts.requires_input (2));
				selected++;
			} else if (function.name == "pure_sample" || function.name == "read_sample") {
				assert (facts.eligible && !facts.requires_input (0));
				selected++;
			} else if (function.name == "impure_sample" || function.name == "change_sample") {
				assert (!facts.eligible);
				selected++;
			}
		}
		assert (selected == 7);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void callback_summary_observed_callers() {
	try {
		var program = callback_summary_program ();
		SsaFunction? forwarding = null;
		SsaFunction? mutating = null;
		SsaCallInstruction? call = null;
		foreach (var function in program.functions) {
			if (function.name == "forward_sample") {
				forwarding = function;
			}
			if (function.name == "change_sample") {
				mutating = function;
			}
			if (function.name != "main") {
				continue;
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var invoked = instruction as SsaCallInstruction;
					if (invoked != null && invoked.target.name == "forward_sample") {
						call = invoked;
					}
				}
			}
		}
		assert (forwarding != null && mutating != null && call != null);
		var before = new SsaReadonlyInference (program).summary (forwarding);
		assert (before.eligible && before.requires_input (0));
		var original = call.arguments[0];
		call.arguments[0] = new SsaFunctionAddress (original.span, (FunctionValueType) original.semantic_type, mutating);
		SsaVerifier.verify (program);
		var after = new SsaReadonlyInference (program).summary (forwarding);
		assert (after.eligible && after.requires_input (0));
		call.arguments[0] = original;
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void callback_mandatory_preconditions() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("callback-preconditions.astra",
			"class Sample{int value;init(int value){this.value=value;}} int read_sample(borrowed Sample value){return value.value;} " +
			"class SlotReader{private owned Sample[slots] values;init(){this.values=new Sample[slots];} " +
			"int inspect(borrowed Sample value,Fn<int,borrowed Sample> callback){return callback(value);} " +
			"int query(Fn<int,borrowed Sample> callback){return this.inspect(this.values[0],callback);}} " +
			"class Bookkeeper{private owned SlotReader values;private int count;init(){var values=new SlotReader();this.values=move values;this.count=0;} " +
			"int query(Fn<int,borrowed Sample> callback){this.count=this.count+1;return this.values.query(callback);}} " +
			"int main(){var reader=new Bookkeeper();return reader.query(read_sample);} "));
		assert (parsed.diagnostic == null);
		var checked = SemanticAnalyzer.analyze (parsed.unit);
		if (checked.diagnostic != null) {
			GLib.error ("%s", checked.diagnostic.format ());
		}
		var program = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (checked.program))));
		var readonly_facts = new SsaReadonlyInference (program);
		var preconditions = new SsaCallbackPreconditions (program, readonly_facts);
		int selected = 0;
		foreach (var function in program.functions) {
			var facts = preconditions.summary (function);
			assert (facts != null && facts.eligible);
			var method = function as SsaMethod;
			string owner = method == null ? "" : method.declaring_type.name;
			if (owner == "SlotReader" && function.name.has_suffix ("inspect")) {
				assert (!facts.requires_input (0) && !facts.requires_input (1));
				assert (readonly_facts.summary (function).requires_input (1));
				selected++;
			} else if (owner == "SlotReader" && function.name.has_suffix ("query")) {
				assert (facts.requires_input (0) && readonly_facts.summary (function).eligible);
				selected++;
			} else if (owner == "Bookkeeper" && function.name.has_suffix ("query")) {
				assert (facts.requires_input (0) && !readonly_facts.summary (function).eligible);
				selected++;
			}
		}
		assert (selected == 3);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private CheckedProgram callback_library_checked() throws GLib.Error {
	string text = "class SummarySample{int value;init(int value){this.value=value;}} " +
	    "bool same_summary_key(int a,int b){return a==b;} int inspect_summary(borrowed SummarySample value){return value.value;} " +
	    "int main(){var map=new Map<int,SummarySample>(same_summary_key);var a=new SummarySample(41);if(!map.put(1,move a)){return 1;} " +
	    "int first=map.lookup<int>(1,inspect_summary,0);var cache=new Cache<int,SummarySample>(same_summary_key);var b=new SummarySample(42); " +
	    "if(!cache.put(2,move b)){return 2;}return first+cache.lookup<int>(2,inspect_summary,0)-83;} ";
	foreach (string path in new string[] { "lib/astra/collections/map.astra", "lib/astra/collections/cache.astra" }) {
		string library;
		FileUtils.get_contents (path, out library);
		text += "\n" + library;
	}
	var parsed = Parser.parse (new SourceFile.from_text ("callback-map-cache.astra", text));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	return checked.program;
}

private void callback_map_cache_preconditions() {
	try {
		var checked = callback_library_checked ();
		var program = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (checked))));
		var readonly_facts = new SsaReadonlyInference (program);
		var preconditions = new SsaCallbackPreconditions (program, readonly_facts);
		int selected = 0;
		foreach (var function in program.functions) {
			var method = function as SsaMethod;
			if (method == null || method.generic_method_instance == null) {
				continue;
			}
			string owner = method.declaring_type.semantic_type.display_name ();
			var instance = method.generic_method_instance;
			string name = instance.class_instance.definition.generic_method_name (instance.member);
			var facts = preconditions.summary (function);
			var readonly_summary = readonly_facts.summary (function);
			if (owner == "Map<int,SummarySample>" && name == "inspect") {
				assert (readonly_summary.eligible && readonly_summary.requires_input (1));
				assert (facts.eligible && !facts.requires_input (1));
				selected++;
			} else if (owner == "Map<int,SummarySample>" && name == "lookup") {
				assert (readonly_summary.eligible && readonly_summary.requires_input (1));
				assert (facts.eligible && facts.requires_input (1));
				selected++;
			} else if (owner == "Cache<int,SummarySample>" && name == "lookup") {
				assert (!readonly_summary.eligible && facts.eligible && facts.requires_input (1));
				selected++;
			}
		}
		assert (selected == 3);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void callback_library_source() {
	try {
		var program = callback_library_checked ();
		var effects = ReadonlyInspection.infer_effects (program, (type) => null);
		int selected = 0;
		foreach (var definition in program.all_definitions ()) {
			var method = definition.symbol as MethodSymbol;
			if (method == null || method.generic_method_instance == null) {
				continue;
			}
			string owner = method.declaring_type.semantic_type.display_name ();
			var instance = method.generic_method_instance;
			string name = instance.class_instance.definition.generic_method_name (instance.member);
			var facts = effects.required_summary (method);
			var readonly_summary = effects.readonly_summary (method);
			Test.message ("%s::%s readonly=%s input1=%s required1=%s valid=%s", owner, name, readonly_summary.eligible.to_string (), readonly_summary.requires_input (1).to_string (), facts.requires_input (1).to_string (), facts.eligible.to_string ());
			if (owner == "Map<int,SummarySample>" && name == "inspect") {
				assert (readonly_summary.eligible && readonly_summary.requires_input (1));
				assert (facts.eligible && !facts.requires_input (1));
				selected++;
			} else if (owner == "Map<int,SummarySample>" && name == "lookup") {
				assert (readonly_summary.eligible && readonly_summary.requires_input (1));
				assert (facts.eligible && facts.requires_input (1));
				selected++;
			} else if (owner == "Cache<int,SummarySample>" && name == "lookup") {
				assert (!readonly_summary.eligible && facts.eligible && facts.requires_input (1));
				selected++;
			}
		}
		assert (selected == 3);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void callback_library_core() {
	try {
		var program = CoreGenericMonomorphizer.build (CoreBuilder.build (callback_library_checked ()));
		var effects = CoreVerifier.infer_effects (program);
		int selected = 0;
		foreach (var definition in program.functions) {
			var method = definition as CoreMethod;
			if (method == null || method.generic_method_instance == null) {
				continue;
			}
			string owner = method.declaring_type.semantic_type.display_name ();
			var instance = method.generic_method_instance;
			string name = instance.class_instance.definition.generic_method_name (instance.member);
			var facts = effects.required_summary (method);
			var readonly_summary = effects.readonly_summary (method);
			Test.message ("%s::%s readonly=%s input1=%s required1=%s valid=%s", owner, name, readonly_summary.eligible.to_string (), readonly_summary.requires_input (1).to_string (), facts.requires_input (1).to_string (), facts.eligible.to_string ());
			if (owner == "Map<int,SummarySample>" && name == "inspect") {
				assert (readonly_summary.eligible && readonly_summary.requires_input (1));
				assert (facts.eligible && !facts.requires_input (1));
				selected++;
			} else if (owner == "Map<int,SummarySample>" && name == "lookup") {
				assert (readonly_summary.eligible && readonly_summary.requires_input (1));
				assert (facts.eligible && facts.requires_input (1));
				selected++;
			} else if (owner == "Cache<int,SummarySample>" && name == "lookup") {
				assert (!readonly_summary.eligible && facts.eligible && facts.requires_input (1));
				selected++;
			}
		}
		assert (selected == 3);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}


private void callback_library_cfg() {
	try {
		var program = CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (callback_library_checked ())));
		var effects = CfgVerifier.infer_effects (program);
		int selected = 0;
		foreach (var definition in program.functions) {
			var method = definition as CfgMethod;
			if (method == null || method.generic_method_instance == null) {
				continue;
			}
			string owner = method.declaring_type.semantic_type.display_name ();
			var instance = method.generic_method_instance;
			string name = instance.class_instance.definition.generic_method_name (instance.member);
			var facts = effects.required_summary (method);
			var readonly_summary = effects.readonly_summary (method);
			Test.message ("%s::%s readonly=%s input1=%s required1=%s valid=%s", owner, name, readonly_summary.eligible.to_string (), readonly_summary.requires_input (1).to_string (), facts.requires_input (1).to_string (), facts.eligible.to_string ());
			if (owner == "Map<int,SummarySample>" && name == "inspect") {
				assert (readonly_summary.eligible && readonly_summary.requires_input (1));
				assert (facts.eligible && !facts.requires_input (1));
				selected++;
			} else if (owner == "Map<int,SummarySample>" && name == "lookup") {
				assert (readonly_summary.eligible && readonly_summary.requires_input (1));
				assert (facts.eligible && facts.requires_input (1));
				selected++;
			} else if (owner == "Cache<int,SummarySample>" && name == "lookup") {
				assert (!readonly_summary.eligible && facts.eligible && facts.requires_input (1));
				selected++;
			}
		}
		assert (selected == 3);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}


private void released_source_callback_analysis(ref WeakRef previous) throws GLib.Error {
	var program = callback_summary_checked ();
	previous.set (program.functions[0].symbol);
	var effects = ReadonlyInspection.infer_effects (program, (type) => null);
	assert (effects.readonly_summary (program.functions[0].symbol) != null);
}
private void released_core_callback_analysis(ref WeakRef previous) throws GLib.Error {
	var program = callback_summary_core_program ();
	previous.set (program.functions[0]);
	var effects = CoreVerifier.infer_effects (program);
	assert (effects.readonly_summary (program.functions[0]) != null);
}
private void released_cfg_callback_analysis(ref WeakRef previous) throws GLib.Error {
	var program = CfgBuilder.build (callback_summary_core_program ());
	previous.set (program.functions[0]);
	var effects = CfgVerifier.infer_effects (program);
	assert (effects.readonly_summary (program.functions[0]) != null);
}
private void released_ssa_callback_analysis(ref WeakRef previous) throws GLib.Error {
	var program = callback_summary_program ();
	previous.set (program.functions[0]);
	var effects = new SsaReadonlyInference (program);
	assert (effects.summary (program.functions[0]) != null);
}
private void callback_analysis_release() {
	try {
		WeakRef previous = WeakRef (null);
		released_source_callback_analysis (ref previous);
		assert (previous.get () == null);
		released_core_callback_analysis (ref previous);
		assert (previous.get () == null);
		released_cfg_callback_analysis (ref previous);
		assert (previous.get () == null);
		released_ssa_callback_analysis (ref previous);
		assert (previous.get () == null);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private SsaProgram callback_iteration_program() throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("callback-iteration.astra",
		"class Item{int value;init(int value){this.value=value;}} " +
		"int observe(borrowed Item value){return value.value;} " +
		"int apply(borrowed Item value,Fn<int,borrowed Item> callback){return callback(value);} " +
		"class Bag<T> where T:ExactHeapClass{owned T[slots] entries;init(){this.entries=new T[slots];}} " +
		"int scan(borrowed Bag<Item> values,Fn<int,borrowed Item> callback){int total=0;foreach(var value in values){total=total+apply(value,callback);}return total;} " +
		"int main(){var values=new Bag<Item>();return scan(values,observe);}"));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	return SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (checked.program))));
}
private void callback_iteration_context() {
	try {
		var program = callback_iteration_program ();
		var effects = new SsaReadonlyInference (program);
		var required = new SsaCallbackPreconditions (program, effects);
		SsaSlotsValueInstruction? selected = null;
		int scans = 0;
		foreach (var function in program.functions) {
			if (function.name.has_suffix ("scan")) {
				assert (required.summary (function).eligible && required.summary (function).requires_input (1));
				scans++;
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var loan = instruction as SsaSlotsValueInstruction;
					if (loan != null && loan.readonly_required) {
						selected = loan;
					}
				}
			}
		}
		assert (scans == 1 && selected != null);
		selected.readonly_required = false;
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			refused = error.message.contains ("original readonly iteration context");
		}
		assert (refused);
		selected.readonly_required = true;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private SemanticResult native_callback_semantics(bool mutating) throws GLib.Error {
	var file = new SourceFile.from_text ("native-callback.declarations.astra",
		"namespace CallbackProof; class Item{int value;init(int value){}} int lookup(Fn<int,borrowed Item> callback){}", true);
	var header = Parser.parse (file);
	var consumer = Parser.parse (new SourceFile.from_text ("native-callback-consumer.astra",
		"int observe(borrowed CallbackProof.Item value){return value.value;} " +
		"int mutate(borrowed CallbackProof.Item value){value.value=99;return value.value;} " +
		"int main(){return CallbackProof.lookup(" + (mutating ? "mutate" : "observe") + ");}"));
	assert (header.diagnostic == null && consumer.diagnostic == null);
	var registry = new NativeDeclarationRegistry ();
	var types = new GenericArray<string> ();
	types.add ("CallbackProof.Item");
	registry.add_types (file, types);
	foreach (string key in new string[] { "C:CallbackProof.Item::init", "C:CallbackProof.Item::deinit" }) {
		registry.add (file, new NativeDeclarationIdentity ("callback-proof", key, "callback_proof_symbol", "declaration-proof"));
	}
	registry.add (file, new NativeDeclarationIdentity ("callback-proof", "F:CallbackProof.lookup", "callback_lookup", "declaration-proof", "", false, "", "0"));
	var units = new GenericArray<CompilationUnitSyntax> ();
	units.add (header.unit);
	units.add (consumer.unit);
	return SemanticAnalyzer.analyze_program (new SyntaxProgram (units), null, null, null, null, registry);
}

private CfgProgram native_buffer_parameter_cfg() throws GLib.Error {
	var file = new SourceFile.from_text ("native-buffer-parameter.declarations.astra",
		"namespace BufferParameter; class Consumer{init(){} void accept(owned u8[] bytes){}}", true);
	var header = Parser.parse (file);
	var consumer = Parser.parse (new SourceFile.from_text ("native-buffer-parameter.astra",
		"int main(){var receiver=new BufferParameter.Consumer();var bytes=new u8[3];bytes[0]=42;receiver.accept(move bytes);return 0;}"));
	assert (header.diagnostic == null && consumer.diagnostic == null);
	var registry = new NativeDeclarationRegistry ();
	var types = new GenericArray<string> ();
	types.add ("BufferParameter.Consumer");
	registry.add_types (file, types);
	foreach (string key in new string[] { "C:BufferParameter.Consumer::init", "C:BufferParameter.Consumer::deinit", "C:BufferParameter.Consumer::accept" }) {
		registry.add (file, new NativeDeclarationIdentity ("buffer-parameter", key, "buffer_parameter_symbol", "declaration-proof"));
	}
	var units = new GenericArray<CompilationUnitSyntax> ();
	units.add (header.unit);
	units.add (consumer.unit);
	var checked = SemanticAnalyzer.analyze_program (new SyntaxProgram (units), null, null, null, null, registry);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	return CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (checked.program)));
}
private void native_buffer_parameter_ssa() {
	try {
		CfgProgram? previous = native_buffer_parameter_cfg ();
		var prior = WeakRef (previous);
		var program = SsaBuilder.build (previous);
		previous = null;
		assert (prior.get () == null);
		SsaFunction? selected = null;
		foreach (var function in program.functions) {
			if (function.name.has_suffix ("accept")) {
				selected = function;
			}
		}
		assert (selected != null && selected.buffer_parameters.length == 1);
		var original = selected.buffer_parameters[0];
		selected.buffer_parameters.remove_index (0);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			refused = error.message.contains ("original owned buffer contract");
		}
		assert (refused);
		selected.buffer_parameters.add (original);
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void native_buffer_parameter_detached() {
	try {
		SsaProgram? previous = SsaBuilder.build (native_buffer_parameter_cfg ());
		var prior = WeakRef (previous);
		var program = NativeAbiBuilder.build (previous);
		previous = null;
		assert (prior.get () == null);
		NativeSignature? selected = null;
		foreach (var function in program.functions) {
			if (function.name.has_suffix ("accept")) {
				selected = function.signature;
			}
		}
		assert (selected != null && selected.buffer_parameters.length == 1);
		var original = selected.buffer_parameters[0];
		selected.buffer_parameters.remove_index (0);
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			refused = error.message.contains ("original ownership declaration");
		}
		assert (refused);
		selected.buffer_parameters.add (original);
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private SemanticResult runtime_composition_semantics(bool different_provider = false, bool different_error = false) throws GLib.Error {
	var units = new GenericArray<CompilationUnitSyntax> ();
	foreach (string path in new string[] { "lib/astra/base/errors.astra", "lib/astra/async/virtual.astra",
	                                       "tests/structural-generics-15/runtime-composition-provider.astra", "tests/structural-generics-15/runtime-composition.astra" }) {
		string text;
		FileUtils.get_contents (path, out text);
		if (path.has_suffix ("-provider.astra")) {
			if (different_provider) {
				text = text.replace ("returns ProducerStatus;", "returns ProducerStatus provider \"linux-io-uring\";");
			}
			if (different_error) {
				text = text.replace ("throws AsyncError", "throws OtherAsyncError");
				text += "\nclass OtherAsyncError : Error { init(string message) : base(message) {} }\n";
			}
		}
		var parsed = Parser.parse (new SourceFile.from_text (path, text));
		assert (parsed.diagnostic == null);
		units.add (parsed.unit);
	}
	return SemanticAnalyzer.analyze_program (new SyntaxProgram (units));
}
private void runtime_composition_conflicts() {
	try {
		var provider = runtime_composition_semantics (true);
		assert (provider.program == null && provider.diagnostic.message.contains ("same provider and nominal error"));
		var error = runtime_composition_semantics (false, true);
		assert (error.program == null && error.diagnostic.message.contains ("same provider and nominal error"));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void runtime_composition_detached() {
	try {
		var checked = runtime_composition_semantics ();
		assert (checked.diagnostic == null);
		CheckedProgram? source = checked.program;
		var source_ref = WeakRef (source);
		CoreProgram? core_program = CoreGenericMonomorphizer.build (CoreBuilder.build (source));
		source = null;
		checked = null;
		assert (source_ref.get () == null);
		CoreVerifier.verify_concrete (core_program);
		var core_ref = WeakRef (core_program);
		CfgProgram? cfg_program = CfgBuilder.build (core_program);
		core_program = null;
		assert (core_ref.get () == null);
		assert (CfgFlowChecker.check (cfg_program).diagnostic == null);
		var cfg_ref = WeakRef (cfg_program);
		SsaProgram? ssa_program = SsaBuilder.build (cfg_program);
		cfg_program = null;
		assert (cfg_ref.get () == null);
		SsaVerifier.verify (ssa_program);
		var ssa_ref = WeakRef (ssa_program);
		var native_program = NativeAbiBuilder.build (ssa_program);
		ssa_program = null;
		assert (ssa_ref.get () == null);
		NativeAbiVerifier.verify (native_program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void async_closure_core_proof() {
	try {
		CheckedProgram? previous = check ("owned-closure-async");
		var prior = WeakRef (previous);
		var program = CoreGenericMonomorphizer.build (CoreBuilder.build (previous));
		previous = null;
		assert (prior.get () == null);
		CoreFunction? selected = null;
		foreach (var function in program.functions) {
			if (function.name == "run_capture") {
				selected = function;
			}
		}
		assert (selected != null);
		var original = selected.parameters[0];
		selected.parameters[0] = new CoreParameter (original.span, original.name_span, original.name,
			original.semantic_type, original.ordinal, PointerParameterContract.BORROWED_NOESCAPE);
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			refused = error.message.contains ("Closure capture");
		}
		assert (refused);
		selected.parameters[0] = original;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void async_closure_cfg_proof() {
	try {
		CoreProgram? previous = core ("owned-closure-async");
		var prior = WeakRef (previous);
		var program = CfgBuilder.build (previous);
		previous = null;
		assert (prior.get () == null);
		CfgFunction? selected = null;
		foreach (var function in program.functions) {
			if (function.name == "run_capture") {
				selected = function;
			}
		}
		assert (selected != null);
		var original = selected.parameters[0];
		selected.parameters[0] = new CfgParameter (original.span, original.name_span, original.name,
			original.semantic_type, original.ordinal, PointerParameterContract.BORROWED_NOESCAPE);
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			refused = error.message.contains ("Closure capture");
		}
		assert (refused);
		selected.parameters[0] = original;
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void async_closure_ssa_proof() {
	try {
		CfgProgram? previous = CfgBuilder.build (core ("owned-closure-async"));
		var prior = WeakRef (previous);
		var program = SsaBuilder.build (previous);
		previous = null;
		assert (prior.get () == null);
		SsaFunction? selected = null;
		foreach (var function in program.functions) {
			if (function.name == "run_capture") {
				selected = function;
			}
		}
		assert (selected != null);
		var original = selected.parameters[0];
		selected.parameters[0] = new SsaFunctionParameter (original.span, original.name_span, original.name,
			original.semantic_type, original.ordinal, PointerParameterContract.BORROWED_NOESCAPE);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			refused = error.message.contains ("Closure capture");
		}
		assert (refused);
		selected.parameters[0] = original;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void async_closure_native_proof() {
	try {
		SsaProgram? previous = SsaBuilder.build (CfgBuilder.build (core ("owned-closure-async")));
		var prior = WeakRef (previous);
		var program = NativeAbiBuilder.build (previous);
		previous = null;
		assert (prior.get () == null);
		NativeAsyncOwner? selected = null;
		foreach (var frame in program.async_frames) {
			for (uint o = 0; o < frame.owner_count; o++) {
				if (frame.owner (o).closure != null) {
					selected = frame.owner (o);
				}
			}
		}
		assert (selected != null);
		var original = selected.closure;
		selected.closure = null;
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			refused = error.message.contains ("original callable cleanup contract");
		}
		assert (refused);
		selected.closure = original;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private SemanticResult native_callback_with_semantics(bool mutating, bool scoped = true) throws GLib.Error {
	var file = new SourceFile.from_text ("native-callback-with.declarations.astra",
		"namespace CallbackWith; class Item{int value;init(int value){}} int apply(borrowed Item value,Fn<int,borrowed Item> callback){}", true);
	var header = Parser.parse (file);
	string invoked = "return CallbackWith.apply(value," + (mutating ? "mutate" : "observe") + ");";
	var consumer = Parser.parse (new SourceFile.from_text ("native-callback-with.astra",
		"int observe(borrowed CallbackWith.Item value){return value.value;} " +
		"int mutate(borrowed CallbackWith.Item value){value.value=99;return value.value;} " +
		"int main(){var value=new CallbackWith.Item(1);" + (scoped ? "with(value){" + invoked + "}" : invoked) + "}"));
	assert (header.diagnostic == null && consumer.diagnostic == null);
	var registry = new NativeDeclarationRegistry ();
	var types = new GenericArray<string> ();
	types.add ("CallbackWith.Item");
	registry.add_types (file, types);
	foreach (string key in new string[] { "C:CallbackWith.Item::init", "C:CallbackWith.Item::deinit" }) {
		registry.add (file, new NativeDeclarationIdentity ("callback-with", key, "callback_with_symbol", "declaration-proof"));
	}
	registry.add (file, new NativeDeclarationIdentity ("callback-with", "F:CallbackWith.apply", "callback_apply", "declaration-proof", "", true, "0", ""));
	var units = new GenericArray<CompilationUnitSyntax> ();
	units.add (header.unit);
	units.add (consumer.unit);
	return SemanticAnalyzer.analyze_program (new SyntaxProgram (units), null, null, null, null, registry);
}
private CoreProgram native_callback_with_core() throws GLib.Error {
	var checked = native_callback_with_semantics (false);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	return CoreGenericMonomorphizer.build (CoreBuilder.build (checked.program));
}
private void native_callback_with_source() {
	try {
		assert (native_callback_with_semantics (false).diagnostic == null);
		assert (native_callback_with_semantics (true, false).diagnostic == null);
		var invalid = native_callback_with_semantics (true);
		assert (invalid.diagnostic != null && invalid.diagnostic.message.contains ("native callback inputs"));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private CoreCallValue? callback_with_core_call(CoreBlock body) {
	foreach (var statement in body.statements) {
		var returned = statement as CoreReturn;
		if (returned != null && returned.value is CoreCallValue) {
			return (CoreCallValue) returned.value;
		}
		if (statement is CoreScope) {
			var nested = callback_with_core_call (((CoreScope) statement).body);
			if (nested != null) {
				return nested;
			}
		}
	}
	return null;
}
private void native_callback_with_core_proof() {
	try {
		var program = native_callback_with_core ();
		CoreFunction? mutator = null;
		CoreCallValue? call = null;
		foreach (var function in program.functions) {
			if (function.name == "mutate") {
				mutator = function;
			}
			if (function.name == "main") {
				call = callback_with_core_call (function.body);
			}
		}
		assert (call != null && mutator != null);
		var original = call.arguments[1];
		call.arguments[1] = new CoreFunctionAddress (original.span, (FunctionValueType) original.semantic_type, mutator);
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			refused = error.message.contains ("native callback inputs");
		}
		assert (refused);
		call.arguments[1] = original;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void native_callback_with_cfg_proof() {
	try {
		CoreProgram? previous = native_callback_with_core ();
		var prior = WeakRef (previous);
		var program = CfgBuilder.build (previous);
		previous = null;
		assert (prior.get () == null);
		CfgFunction? mutator = null;
		CfgCallInstruction? call = null;
		foreach (var function in program.functions) {
			if (function.name == "mutate") {
				mutator = function;
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var candidate = instruction as CfgCallInstruction;
					if (candidate != null && candidate.target.name == "CallbackWith.apply") {
						call = candidate;
					}
				}
			}
		}
		assert (call != null && mutator != null && call.readonly_required);
		call.readonly_required = false;
		bool erased = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			erased = error.message.contains ("original readonly scope context");
		}
		assert (erased);
		call.readonly_required = true;
		var original = call.arguments[1];
		call.arguments[1] = new CfgFunctionAddress (original.span, (FunctionValueType) original.semantic_type, mutator);
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			refused = error.message.contains ("native callback inputs");
		}
		assert (refused);
		call.arguments[1] = original;
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void native_callback_with_ssa_proof() {
	try {
		CfgProgram? previous = CfgBuilder.build (native_callback_with_core ());
		var prior = WeakRef (previous);
		var program = SsaBuilder.build (previous);
		previous = null;
		assert (prior.get () == null);
		SsaFunction? mutator = null;
		SsaCallInstruction? call = null;
		foreach (var function in program.functions) {
			if (function.name == "mutate") {
				mutator = function;
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var candidate = instruction as SsaCallInstruction;
					if (candidate != null && candidate.target.name == "CallbackWith.apply") {
						call = candidate;
					}
				}
			}
		}
		assert (call != null && mutator != null && call.readonly_required);
		call.readonly_required = false;
		bool erased = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			erased = error.message.contains ("original readonly scope context");
		}
		assert (erased);
		call.readonly_required = true;
		var original = call.arguments[1];
		call.arguments[1] = new SsaFunctionAddress (original.span, (FunctionValueType) original.semantic_type, mutator);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			refused = error.message.contains ("native callback inputs");
		}
		assert (refused);
		call.arguments[1] = original;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private CheckedProgram native_callback_checked() throws GLib.Error {
	var result = native_callback_semantics (false);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}
private CoreProgram native_callback_core() throws GLib.Error {
	return CoreGenericMonomorphizer.build (CoreBuilder.build (native_callback_checked ()));
}
private CfgProgram native_callback_cfg() throws GLib.Error {
	return CfgBuilder.build (native_callback_core ());
}
private SsaProgram native_callback_ssa() throws GLib.Error {
	return SsaBuilder.build (native_callback_cfg ());
}
private void native_callback_source() {
	try {
		var result = native_callback_semantics (true);
		assert (result.diagnostic != null && result.diagnostic.message.contains ("native callback inputs"));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void native_callback_core_proof() {
	try {
		CheckedProgram? previous = native_callback_checked ();
		var prior = WeakRef (previous);
		var program = CoreGenericMonomorphizer.build (CoreBuilder.build (previous));
		previous = null;
		assert (prior.get () == null);
		CoreFunction? mutator = null;
		CoreCallValue? call = null;
		foreach (var function in program.functions) {
			if (function.name == "mutate") {
				mutator = function;
			}
			if (function.name != "main") {
				continue;
			}
			foreach (var statement in function.body.statements) {
				var returned = statement as CoreReturn;
				if (returned != null) {
					call = returned.value as CoreCallValue;
				}
			}
		}
		assert (mutator != null && call != null);
		var original = call.arguments[0];
		call.arguments[0] = new CoreFunctionAddress (original.span, (FunctionValueType) original.semantic_type, mutator);
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			refused = error.message.contains ("native callback inputs");
			Test.message ("%s", error.message);
		}
		assert (refused);
		call.arguments[0] = original;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void native_callback_cfg_proof() {
	try {
		CoreProgram? previous = native_callback_core ();
		var prior = WeakRef (previous);
		var program = CfgBuilder.build (previous);
		previous = null;
		assert (prior.get () == null);
		CfgFunction? mutator = null;
		CfgCallInstruction? call = null;
		foreach (var function in program.functions) {
			if (function.name == "mutate") {
				mutator = function;
			}
			if (function.name != "main") {
				continue;
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var invoked = instruction as CfgCallInstruction;
					if (invoked != null && invoked.target.name == "CallbackProof.lookup") {
						call = invoked;
					}
				}
			}
		}
		assert (mutator != null && call != null);
		var original = call.arguments[0];
		call.arguments[0] = new CfgFunctionAddress (original.span, (FunctionValueType) original.semantic_type, mutator);
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			refused = error.message.contains ("native callback inputs");
			Test.message ("%s", error.message);
		}
		assert (refused);
		call.arguments[0] = original;
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void native_callback_ssa_proof() {
	try {
		CfgProgram? previous = native_callback_cfg ();
		var prior = WeakRef (previous);
		var program = SsaBuilder.build (previous);
		previous = null;
		assert (prior.get () == null);
		SsaFunction? mutator = null;
		SsaCallInstruction? call = null;
		foreach (var function in program.functions) {
			if (function.name == "mutate") {
				mutator = function;
			}
			if (function.name != "main") {
				continue;
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var invoked = instruction as SsaCallInstruction;
					if (invoked != null && invoked.target.name == "CallbackProof.lookup") {
						call = invoked;
					}
				}
			}
		}
		assert (mutator != null && call != null);
		var original = call.arguments[0];
		call.arguments[0] = new SsaFunctionAddress (original.span, (FunctionValueType) original.semantic_type, mutator);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			refused = error.message.contains ("native callback inputs");
			Test.message ("%s", error.message);
		}
		assert (refused);
		call.arguments[0] = original;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void native_callback_detached_proof() {
	try {
		SsaProgram? previous = native_callback_ssa ();
		var prior = WeakRef (previous);
		var program = NativeAbiBuilder.build (previous);
		previous = null;
		assert (prior.get () == null);
		NativeFunction? selected = null;
		foreach (var function in program.functions) {
			if (function.name == "CallbackProof.lookup") {
				selected = function;
			}
		}
		assert (selected != null && selected.callback_inputs == "0" && selected.callback_input_count == 1);
		selected.callback_inputs = "";
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			refused = error.message.contains ("original checked definition contract");
		}
		assert (refused);
		selected.callback_inputs = "0";
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private CheckedProgram native_readonly_declarations() throws GLib.Error {
	var file = new SourceFile.from_text ("native-readonly.declarations.astra",
		"namespace ReadProof; class Item{int value;init(int value){}} int inspect(borrowed Item value){} int mutate(borrowed Item value){}", true);
	var header = Parser.parse (file);
	var consumer = Parser.parse (new SourceFile.from_text ("native-readonly-consumer.astra",
		"class Store{private owned ReadProof.Item[slots] values;init(){this.values=new ReadProof.Item[slots];} " +
		"int inspect(borrowed ReadProof.Item item,Fn<int,borrowed ReadProof.Item> callback){return callback(item);} " +
		"int read(Fn<int,borrowed ReadProof.Item> callback){return this.inspect(this.values[0],callback);}} " +
		"int main(){var store=new Store();return store.read(ReadProof.inspect);} "));
	assert (header.diagnostic == null && consumer.diagnostic == null);
	var registry = new NativeDeclarationRegistry ();
	var types = new GenericArray<string> ();
	types.add ("ReadProof.Item");
	registry.add_types (file, types);
	foreach (string key in new string[] { "C:ReadProof.Item::init", "C:ReadProof.Item::deinit", "F:ReadProof.inspect", "F:ReadProof.mutate" }) {
		registry.add (file, new NativeDeclarationIdentity ("readonly-proof", key, "readonly_proof_symbol", "declaration-proof", "", key == "F:ReadProof.inspect"));
	}
	var units = new GenericArray<CompilationUnitSyntax> ();
	units.add (header.unit);
	units.add (consumer.unit);
	var result = SemanticAnalyzer.analyze_program (new SyntaxProgram (units), null, null, null, null, registry);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}

private CoreProgram native_readonly_core() throws GLib.Error {
	return CoreGenericMonomorphizer.build (CoreBuilder.build (native_readonly_declarations ()));
}

private CfgProgram native_readonly_cfg() throws GLib.Error {
	return CfgBuilder.build (native_readonly_core ());
}

private SsaProgram native_readonly_ssa() throws GLib.Error {
	return SsaBuilder.build (native_readonly_cfg ());
}

private void native_readonly_contract_core() {
	try {
		CheckedProgram? source = native_readonly_declarations ();
		var predecessor = WeakRef (source.classes[0]);
		var program = CoreGenericMonomorphizer.build (CoreBuilder.build (source));
		source = null;
		assert (predecessor.get () == null);
		CoreVerifier.verify_concrete (program);
		CoreFunction? mutating = null;
		CoreCallValue? call = null;
		foreach (var function in program.functions) {
			if (function.name == "ReadProof.mutate") {
				mutating = function;
			}
			if (function.name != "main") {
				continue;
			}
			foreach (var statement in function.body.statements) {
				var returned = statement as CoreReturn;
				if (returned != null) {
					call = returned.value as CoreCallValue;
				}
			}
		}
		assert (mutating != null && call != null && call.arguments.length == 1);
		var original = call.arguments[0];
		call.arguments[0] = new CoreFunctionAddress (original.span, (FunctionValueType) original.semantic_type, mutating);
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			refused = error.message.contains ("readonly scoped inspector");
			Test.message ("%s", error.message);
		}
		assert (refused);
		call.arguments[0] = original;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_readonly_contract_cfg() {
	try {
		CoreProgram? source = native_readonly_core ();
		var predecessor = WeakRef (source);
		var program = CfgBuilder.build (source);
		source = null;
		assert (predecessor.get () == null);
		assert (CfgFlowChecker.check (program).diagnostic == null);
		CfgFunction? mutating = null;
		CfgCallInstruction? call = null;
		foreach (var function in program.functions) {
			if (function.name == "ReadProof.mutate") {
				mutating = function;
			}
			if (function.name != "main") {
				continue;
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var invoked = instruction as CfgCallInstruction;
					if (invoked != null && invoked.target.name.has_suffix ("read")) {
						call = invoked;
					}
				}
			}
		}
		assert (mutating != null && call != null && call.arguments.length == 1);
		var original = call.arguments[0];
		call.arguments[0] = new CfgFunctionAddress (original.span, (FunctionValueType) original.semantic_type, mutating);
		bool refused = false;
		try {
			refused = CfgFlowChecker.check (program).diagnostic != null;
		} catch (CfgError error) {
			refused = error.message.contains ("readonly scoped inspector");
			Test.message ("%s", error.message);
		}
		assert (refused);
		call.arguments[0] = original;
		assert (CfgFlowChecker.check (program).diagnostic == null);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_readonly_contract_ssa() {
	try {
		CfgProgram? source = native_readonly_cfg ();
		var predecessor = WeakRef (source);
		var program = SsaBuilder.build (source);
		source = null;
		assert (predecessor.get () == null);
		SsaVerifier.verify (program);
		SsaFunction? mutating = null;
		SsaCallInstruction? call = null;
		foreach (var function in program.functions) {
			if (function.name == "ReadProof.mutate") {
				mutating = function;
			}
			if (function.name != "main") {
				continue;
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var invoked = instruction as SsaCallInstruction;
					if (invoked != null && invoked.target.name.has_suffix ("read")) {
						call = invoked;
					}
				}
			}
		}
		assert (mutating != null && call != null && call.arguments.length == 1);
		var original = call.arguments[0];
		call.arguments[0] = new SsaFunctionAddress (original.span, (FunctionValueType) original.semantic_type, mutating);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			refused = error.message.contains ("readonly scoped inspector");
			Test.message ("%s", error.message);
		}
		assert (refused);
		call.arguments[0] = original;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_readonly_detached() {
	try {
		SsaProgram? source = native_readonly_ssa ();
		var predecessor = WeakRef (source);
		var program = NativeAbiBuilder.build (source);
		source = null;
		assert (predecessor.get () == null);
		NativeAbiVerifier.verify (program);
		NativeFunction? selected = null;
		foreach (var function in program.functions) {
			if (function.name == "ReadProof.inspect") {
				selected = function;
			}
		}
		assert (selected != null && selected.scoped_readonly);
		selected.scoped_readonly = false;
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			refused = error.message.contains ("original checked definition contract");
		}
		assert (refused);
		selected.scoped_readonly = true;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private CheckedProgram native_task_declarations() throws GLib.Error {
	var file = new SourceFile.from_text ("native-task.declarations.astra",
		"namespace TaskProof; [ExceptionRoot] class Root{readonly string text;init(string message){} virtual property string message{get{}}} " +
		"class RuntimeFailure:Root{init(string message){}} struct Reply<T>{T value;} " +
		"async Reply<int> compute(int input) throws Root{}", true);
	var header = Parser.parse (file);
	var consumer = Parser.parse (new SourceFile.from_text ("native-task-consumer.astra",
		"enum RunStatus{Completed,Cancelled} async runtime VirtualExecutor throws TaskProof.RuntimeFailure returns RunStatus; " +
		"async void parent() throws TaskProof.Root{var result=await TaskProof.compute(40);} int main(){return 0;}"));
	assert (header.diagnostic == null && consumer.diagnostic == null);
	var registry = new NativeDeclarationRegistry ();
	var names = new GenericArray<string> ();
	foreach (string name in new string[] { "TaskProof.Root", "TaskProof.RuntimeFailure", "TaskProof.Reply<int>" }) {
		names.add (name);
	}
	registry.add_types (file, names);
	foreach (string name in new string[] { "TaskProof.Root", "TaskProof.RuntimeFailure" }) {
		foreach (string member in new string[] { "init", "deinit" }) {
			registry.add (file,
				new NativeDeclarationIdentity ("task-proof", "C:" + name + "::" + member, "task_proof_symbol", "declaration-proof"));
		}
	}
	registry.add (file, new NativeDeclarationIdentity ("task-proof", "C:TaskProof.Root::get:message", "task_proof_message", "declaration-proof"));
	registry.add (file, new NativeDeclarationIdentity ("task-proof", "F:TaskProof.compute", "task_proof_compute", "declaration-proof"));
	var boundaries = new GenericArray<FunctionDeclarationSyntax> ();
	foreach (var function in header.unit.functions) {
		boundaries.add (function);
	}
	foreach (var owner in header.unit.classes) {
		foreach (var member in owner.methods) {
			boundaries.add (member);
		}
	}
	var units = new GenericArray<CompilationUnitSyntax> ();
	units.add (header.unit);
	units.add (consumer.unit);
	var result = SemanticAnalyzer.analyze_program (new SyntaxProgram (units), null, null, null, boundaries, registry);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}

private CoreProgram native_task_core() throws GLib.Error {
	return CoreGenericMonomorphizer.build (CoreBuilder.build (native_task_declarations ()));
}

private CfgProgram native_task_cfg() throws GLib.Error {
	return CfgBuilder.build (native_task_core ());
}

private SsaProgram native_task_ssa() throws GLib.Error {
	return SsaBuilder.build (native_task_cfg ());
}

private void native_task_contract_core() {
	try {
		CheckedProgram? source = native_task_declarations ();
		var predecessor = WeakRef (source.classes[0]);
		var program = CoreGenericMonomorphizer.build (CoreBuilder.build (source));
		source = null;
		assert (predecessor.get () == null);
		CoreVerifier.verify_concrete (program);
		CoreFunction? selected = null;
		foreach (var function in program.functions) {
			if (function.name == "TaskProof.compute") {
				selected = function;
			}
		}
		assert (selected != null && selected.async_body != null && selected.native_declaration != null);
		var original = selected.async_body;
		var runtime = original.runtime;
		var changed = new AsyncRuntimeIdentity (runtime.nomination, runtime.executor_name, runtime.error_type, runtime.status_type, AsyncProviderKind.LINUX_IO_URING);
		selected.async_body = new AsyncBodyContract (original.declaration, original.success_type, original.success_mode, original.exception_bound, changed);
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			refused = error.message.contains ("native declaration differs from its original async result/runtime contract");
			Test.message ("%s", error.message);
		}
		assert (refused);
		selected.async_body = original;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_task_contract_cfg() {
	try {
		CoreProgram? source = native_task_core ();
		var predecessor = WeakRef (source);
		var program = CfgBuilder.build (source);
		source = null;
		assert (predecessor.get () == null);
		assert (CfgFlowChecker.check (program).diagnostic == null);
		CfgFunction? selected = null;
		foreach (var function in program.functions) {
			if (function.name == "TaskProof.compute") {
				selected = function;
			}
		}
		assert (selected != null && selected.async_body != null && selected.native_declaration != null);
		var original = selected.async_body;
		var runtime = original.runtime;
		var changed = new AsyncRuntimeIdentity (runtime.nomination, runtime.executor_name, runtime.error_type, runtime.status_type, AsyncProviderKind.LINUX_IO_URING);
		selected.async_body = new AsyncBodyContract (original.declaration, original.success_type, original.success_mode, original.exception_bound, changed);
		bool refused = false;
		try {
			refused = CfgFlowChecker.check (program).diagnostic != null;
		} catch (CfgError error) {
			refused = error.message.contains ("native declaration differs from its original async result/runtime contract");
			Test.message ("%s", error.message);
		}
		assert (refused);
		selected.async_body = original;
		assert (CfgFlowChecker.check (program).diagnostic == null);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_task_contract_ssa() {
	try {
		CfgProgram? source = native_task_cfg ();
		var predecessor = WeakRef (source);
		var program = SsaBuilder.build (source);
		source = null;
		assert (predecessor.get () == null);
		SsaVerifier.verify (program);
		SsaFunction? selected = null;
		foreach (var function in program.functions) {
			if (function.name == "TaskProof.compute") {
				selected = function;
			}
		}
		assert (selected != null && selected.async_body != null && selected.native_declaration != null);
		var original = selected.async_body;
		var runtime = original.runtime;
		var changed = new AsyncRuntimeIdentity (runtime.nomination, runtime.executor_name, runtime.error_type, runtime.status_type, AsyncProviderKind.LINUX_IO_URING);
		selected.async_body = new AsyncBodyContract (original.declaration, original.success_type, original.success_mode, original.exception_bound, changed);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			refused = error.message.contains ("native declaration differs from its original async result/runtime contract");
			Test.message ("%s", error.message);
		}
		assert (refused);
		selected.async_body = original;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_task_detached_contract() {
	try {
		SsaProgram? source = native_task_ssa ();
		var predecessor = WeakRef (source);
		var program = NativeAbiBuilder.build (source);
		source = null;
		assert (predecessor.get () == null);
		NativeAbiVerifier.verify (program);
		NativeFunction? selected = null;
		foreach (var function in program.functions) {
			if (function.name == "TaskProof.compute") {
				selected = function;
			}
		}
		assert (selected != null && selected.async_callable != null && selected.async_callable.imported && program.async_frames.length == 1);
		var original = selected.async_callable;
		selected.async_callable = null;
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			refused = true;
		}
		assert (refused);
		selected.async_callable = original;
		NativeAbiVerifier.verify (program);
		var frame = program.async_frames[0];
		program.async_frames.remove_index (0);
		refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			refused = error.message.contains ("local tasks require one frame");
		}
		assert (refused);
		program.async_frames.add (frame);
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private SsaProgram generic_record_async_ssa() throws GLib.Error {
	CfgProgram? source = CfgBuilder.build (core ("generic-record-async"));
	var predecessor = WeakRef (source);
	var program = SsaBuilder.build (source);
	source = null;
	assert (predecessor.get () == null);
	return program;
}

private void async_record_nominal_frame() {
	try {
		var program = generic_record_async_ssa ();
		SsaVerifier.verify (program);
		SsaFunction? selected = null;
		foreach (var function in program.functions) {
			if (function.name == "produce_record") {
				selected = function;
			}
		}
		assert (selected != null && selected.async_body != null && selected.struct_result != null);
		assert (selected.async_body.success_type != selected.return_type);
		assert (selected.async_body.success_type.logical_identity == selected.return_type.logical_identity);
		var plan = NativeAsyncFrameBuilder.build (selected, program);
		NativeAsyncFrameBuilder.validate (plan, selected, program);
		var original = selected.async_body;
		// Identical spelling and unchanged physical leaf group do not grant
		// the original declared record result identity to a forged type.
		selected.async_body = new AsyncBodyContract (original.declaration, new StructType (selected.return_type.display_name ()), original.success_mode, original.exception_bound, original.runtime);
		bool refused = false;
		try {
			NativeAsyncFrameBuilder.build (selected, program);
		} catch (NativeAbiError error) {
			refused = error.message.contains ("async frame lost exact native body/result/effect contract");
		}
		assert (refused);
		selected.async_body = original;
		NativeAsyncFrameBuilder.validate (plan, selected, program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private CheckedProgram native_interface_declarations() throws GLib.Error {
	var file = new SourceFile.from_text ("native-protocol.declarations.astra",
		"namespace ProtocolProof; interface Score{int apply(int input);} " +
		"class First:Score{int bias;init(){} override int apply(int input){}} " +
		"int dispatch(borrowed Score value,int input){}", true);
	var header = Parser.parse (file);
	var consumer = Parser.parse (new SourceFile.from_text ("native-protocol-consumer.astra",
		"int main(){var value=new ProtocolProof.First();return ProtocolProof.dispatch(value,2);}"));
	assert (header.diagnostic == null && consumer.diagnostic == null);
	var registry = new NativeDeclarationRegistry ();
	var names = new GenericArray<string> ();
	foreach (string name in new string[] { "ProtocolProof.Score", "ProtocolProof.First" }) {
		names.add (name);
		foreach (string member in new string[] { "init", "deinit", "apply" }) {
			registry.add (file, new NativeDeclarationIdentity ("protocol-proof", "C:" + name + "::" + member,
				"protocol_proof_symbol", "declaration-proof"));
		}
	}
	registry.add_types (file, names);
	registry.add (file, new NativeDeclarationIdentity ("protocol-proof", "F:ProtocolProof.dispatch",
		"protocol_proof_dispatch", "declaration-proof"));
	var boundaries = new GenericArray<FunctionDeclarationSyntax> ();
	foreach (var function in header.unit.functions) {
		boundaries.add (function);
	}
	foreach (var owner in header.unit.classes) {
		foreach (var member in owner.methods) {
			boundaries.add (member);
		}
	}
	var units = new GenericArray<CompilationUnitSyntax> ();
	units.add (header.unit);
	units.add (consumer.unit);
	var result = SemanticAnalyzer.analyze_program (new SyntaxProgram (units), null, null, null, boundaries, registry);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}

private CoreProgram native_interface_core() throws GLib.Error {
	return CoreGenericMonomorphizer.build (CoreBuilder.build (native_interface_declarations ()));
}

private CfgProgram native_interface_cfg() throws GLib.Error {
	return CfgBuilder.build (native_interface_core ());
}

private void native_interface_signature_core() {
	try {
		CheckedProgram? source = native_interface_declarations ();
		var predecessor = WeakRef (source.classes[0]);
		var program = CoreGenericMonomorphizer.build (CoreBuilder.build (source));
		source = null;
		assert (predecessor.get () == null);
		CoreVerifier.verify_concrete (program);
		CoreFunction? selected = null;
		foreach (var function in program.functions) {
			if (function is CoreMethod && ((CoreMethod) function).declaring_type.name == "ProtocolProof.First") {
				selected = function;
			}
		}
		assert (selected != null && selected.native_declaration != null && selected.parameters.length == 1);
		var original = selected.parameters[0];
		selected.parameters[0] = new CoreParameter (original.span, original.name_span, original.name, original.semantic_type, original.ordinal, PointerParameterContract.OWNED_TRANSFER);
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			refused = error.message.contains ("native declaration differs from its original exact signature");
			Test.message ("%s", error.message);
		}
		assert (refused);
		selected.parameters[0] = original;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_interface_signature_cfg() {
	try {
		CoreProgram? source = native_interface_core ();
		var predecessor = WeakRef (source);
		var program = CfgBuilder.build (source);
		source = null;
		assert (predecessor.get () == null);
		assert (CfgFlowChecker.check (program).diagnostic == null);
		CfgFunction? selected = null;
		foreach (var function in program.functions) {
			if (function is CfgMethod && ((CfgMethod) function).declaring_type.name == "ProtocolProof.First") {
				selected = function;
			}
		}
		assert (selected != null && selected.native_declaration != null && selected.parameters.length == 1);
		var original = selected.parameters[0];
		selected.parameters[0] = new CfgParameter (original.span, original.name_span, original.name, original.semantic_type, original.ordinal, PointerParameterContract.OWNED_TRANSFER);
		bool refused = false;
		try {
			refused = CfgFlowChecker.check (program).diagnostic != null;
		} catch (CfgError error) {
			refused = error.message.contains ("native declaration differs from its original exact signature");
			Test.message ("%s", error.message);
		}
		assert (refused);
		selected.parameters[0] = original;
		assert (CfgFlowChecker.check (program).diagnostic == null);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_interface_signature_ssa() {
	try {
		CfgProgram? source = native_interface_cfg ();
		var predecessor = WeakRef (source);
		var program = SsaBuilder.build (source);
		source = null;
		assert (predecessor.get () == null);
		SsaVerifier.verify (program);
		SsaFunction? selected = null;
		foreach (var function in program.functions) {
			if (function is SsaMethod && ((SsaMethod) function).declaring_type.name == "ProtocolProof.First") {
				selected = function;
			}
		}
		assert (selected != null && selected.native_declaration != null && selected.parameters.length == 1);
		var original = selected.parameters[0];
		selected.parameters[0] = new SsaFunctionParameter (original.span, original.name_span, original.name, original.semantic_type, original.ordinal, PointerParameterContract.OWNED_TRANSFER);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			refused = error.message.contains ("native declaration differs from its original exact signature");
			Test.message ("%s", error.message);
		}
		assert (refused);
		selected.parameters[0] = original;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private CheckedProgram native_exception_declarations() throws GLib.Error {
	var file = new SourceFile.from_text ("native-exceptions.declarations.astra",
		"namespace ExceptionProof; [ExceptionRoot] class Root{init(){} virtual property string message{get{}}} " +
		"class Narrow:Root{init(){}} struct Reply{int value;} Reply choose(bool fail) throws Root{}", true);
	var header = Parser.parse (file);
	var consumer = Parser.parse (new SourceFile.from_text ("native-exception-consumer.astra",
		"int main(){try{var reply=ExceptionProof.choose(false);return reply.value;}catch(ExceptionProof.Root error){return 0;}}"));
	assert (header.diagnostic == null && consumer.diagnostic == null);
	var registry = new NativeDeclarationRegistry ();
	var names = new GenericArray<string> ();
	foreach (string name in new string[] { "ExceptionProof.Root", "ExceptionProof.Narrow", "ExceptionProof.Reply" }) {
		names.add (name);
	}
	registry.add_types (file, names);
	foreach (string name in new string[] { "ExceptionProof.Root", "ExceptionProof.Narrow" }) {
		foreach (string member in new string[] { "init", "deinit" }) {
			registry.add (file, new NativeDeclarationIdentity ("exception-proof", "C:" + name + "::" + member,
				"exception_proof_symbol", "declaration-proof"));
		}
	}
	registry.add (file, new NativeDeclarationIdentity ("exception-proof", "C:ExceptionProof.Root::get:message",
		"exception_proof_message", "declaration-proof"));
	registry.add (file, new NativeDeclarationIdentity ("exception-proof", "F:ExceptionProof.choose",
		"exception_proof_choose", "declaration-proof"));
	var boundaries = new GenericArray<FunctionDeclarationSyntax> ();
	foreach (var function in header.unit.functions) {
		boundaries.add (function);
	}
	foreach (var owner in header.unit.classes) {
		foreach (var member in owner.methods) {
			boundaries.add (member);
		}
	}
	var units = new GenericArray<CompilationUnitSyntax> ();
	units.add (header.unit);
	units.add (consumer.unit);
	var result = SemanticAnalyzer.analyze_program (new SyntaxProgram (units), null, null, null, boundaries, registry);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}

private CoreProgram native_exception_core() throws GLib.Error {
	return CoreGenericMonomorphizer.build (CoreBuilder.build (native_exception_declarations ()));
}

private CfgProgram native_exception_cfg() throws GLib.Error {
	return CfgBuilder.build (native_exception_core ());
}

private void native_exception_bound_core() {
	try {
		CheckedProgram? source = native_exception_declarations ();
		var predecessor = WeakRef (source.classes[0]);
		var program = CoreGenericMonomorphizer.build (CoreBuilder.build (source));
		source = null;
		assert (predecessor.get () == null);
		CoreVerifier.verify_concrete (program);
		CoreFunction? selected = null;
		ClassType? narrow = null;
		foreach (var owner in program.classes) {
			if (owner.name == "ExceptionProof.Narrow") {
				narrow = (ClassType) owner.semantic_type;
			}
		}
		foreach (var function in program.functions) {
			if (function.name == "ExceptionProof.choose") {
				selected = function;
			}
		}
		assert (selected != null && narrow != null);
		var original = selected.throws_type;
		selected.throws_type = narrow;
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			refused = error.message.contains ("native declaration differs from its original exact signature");
			Test.message ("%s", error.message);
		}
		assert (refused);
		selected.throws_type = original;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_exception_bound_cfg() {
	try {
		CoreProgram? source = native_exception_core ();
		var predecessor = WeakRef (source);
		var program = CfgBuilder.build (source);
		source = null;
		assert (predecessor.get () == null);
		assert (CfgFlowChecker.check (program).diagnostic == null);
		CfgFunction? selected = null;
		ClassType? narrow = null;
		foreach (var owner in program.classes) {
			if (owner.name == "ExceptionProof.Narrow") {
				narrow = (ClassType) owner.semantic_type;
			}
		}
		foreach (var function in program.functions) {
			if (function.name == "ExceptionProof.choose") {
				selected = function;
			}
		}
		assert (selected != null && narrow != null);
		var original = selected.throws_type;
		selected.throws_type = narrow;
		bool refused = false;
		try {
			refused = CfgFlowChecker.check (program).diagnostic != null;
		} catch (CfgError error) {
			refused = error.message.contains ("native declaration differs from its original exact signature");
			Test.message ("%s", error.message);
		}
		assert (refused);
		selected.throws_type = original;
		assert (CfgFlowChecker.check (program).diagnostic == null);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_exception_bound_ssa() {
	try {
		CfgProgram? source = native_exception_cfg ();
		var predecessor = WeakRef (source);
		var program = SsaBuilder.build (source);
		source = null;
		assert (predecessor.get () == null);
		SsaVerifier.verify (program);
		SsaFunction? selected = null;
		ClassType? narrow = null;
		foreach (var owner in program.classes) {
			if (owner.name == "ExceptionProof.Narrow") {
				narrow = (ClassType) owner.semantic_type;
			}
		}
		foreach (var function in program.functions) {
			if (function.name == "ExceptionProof.choose") {
				selected = function;
			}
		}
		assert (selected != null && narrow != null);
		var original = selected.throws_type;
		selected.throws_type = narrow;
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			refused = error.message.contains ("native declaration differs from its original exact signature");
			Test.message ("%s", error.message);
		}
		assert (refused);
		selected.throws_type = original;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private CheckedProgram native_method_declarations() throws GLib.Error {
	var file = new SourceFile.from_text ("native-methods.declarations.astra",
		"namespace MethodProof; class Marker{init(){}} class Other{init(){}} " +
		"class Counter<T>{init(){} int constant<R>() where R:Ownable {}} " +
		"internal struct Request{owned Counter<int> value;}", true);
	var header = Parser.parse (file);
	var consumer = Parser.parse (new SourceFile.from_text ("native-method-consumer.astra",
		"int main(){var value=new MethodProof.Counter<int>();return value.constant<MethodProof.Marker>()-7;}"));
	assert (header.diagnostic == null && consumer.diagnostic == null);
	var registry = new NativeDeclarationRegistry ();
	var names = new GenericArray<string> ();
	foreach (string name in new string[] { "MethodProof.Marker", "MethodProof.Other", "MethodProof.Counter<int>" }) {
		names.add (name);
		foreach (string member in new string[] { "init", "deinit" }) {
			registry.add (file, new NativeDeclarationIdentity ("method-proof", "C:" + name + "::" + member,
				"method_proof_symbol", "declaration-proof"));
		}
	}
	registry.add_types (file, names);
	registry.add (file, new NativeDeclarationIdentity ("method-proof",
		"C:MethodProof.Counter<int>::constant<MethodProof.Marker>", "method_proof_constant", "declaration-proof"));
	var boundaries = new GenericArray<FunctionDeclarationSyntax> ();
	foreach (var owner in header.unit.classes) {
		foreach (var member in owner.methods) {
			boundaries.add (member);
		}
	}
	var units = new GenericArray<CompilationUnitSyntax> ();
	units.add (header.unit);
	units.add (consumer.unit);
	var result = SemanticAnalyzer.analyze_program (new SyntaxProgram (units), null, null, null, boundaries, registry);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}

private CoreProgram native_method_core() throws GLib.Error {
	return CoreGenericMonomorphizer.build (CoreBuilder.build (native_method_declarations ()));
}

private CfgProgram native_method_cfg() throws GLib.Error {
	return CfgBuilder.build (native_method_core ());
}

private void native_method_key_core() {
	try {
		CheckedProgram? source = native_method_declarations ();
		var predecessor = WeakRef (source.classes[0]);
		var program = CoreGenericMonomorphizer.build (CoreBuilder.build (source));
		source = null;
		assert (predecessor.get () == null);
		CoreVerifier.verify_concrete (program);
		CoreMethod? selected = null;
		SemanticType? other = null;
		foreach (var owner in program.classes) {
			if (owner.name == "MethodProof.Other") {
				other = owner.semantic_type;
			}
		}
		foreach (var function in program.functions) {
			var method = function as CoreMethod;
			if (method != null && method.generic_method_instance != null) {
				selected = method;
			}
		}
		assert (selected != null && other != null);
		var original = selected.generic_method_instance;
		selected.generic_method_instance = original.copy (new TypeArgumentVector.single (other));
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			refused = error.message.contains ("native declaration differs from its original exact signature");
			Test.message ("%s", error.message);
		}
		assert (refused);
		selected.generic_method_instance = original;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_method_key_cfg() {
	try {
		CoreProgram? source = native_method_core ();
		var predecessor = WeakRef (source);
		var program = CfgBuilder.build (source);
		source = null;
		assert (predecessor.get () == null);
		assert (CfgFlowChecker.check (program).diagnostic == null);
		CfgMethod? selected = null;
		SemanticType? other = null;
		foreach (var owner in program.classes) {
			if (owner.name == "MethodProof.Other") {
				other = owner.semantic_type;
			}
		}
		foreach (var function in program.functions) {
			var method = function as CfgMethod;
			if (method != null && method.generic_method_instance != null) {
				selected = method;
			}
		}
		assert (selected != null && other != null);
		var original = selected.generic_method_instance;
		selected.generic_method_instance = original.copy (new TypeArgumentVector.single (other));
		bool refused = false;
		try {
			refused = CfgFlowChecker.check (program).diagnostic != null;
		} catch (CfgError error) {
			refused = error.message.contains ("native declaration differs from its original exact signature");
			Test.message ("%s", error.message);
		}
		assert (refused);
		selected.generic_method_instance = original;
		assert (CfgFlowChecker.check (program).diagnostic == null);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_method_key_ssa() {
	try {
		CfgProgram? source = native_method_cfg ();
		var predecessor = WeakRef (source);
		var program = SsaBuilder.build (source);
		source = null;
		assert (predecessor.get () == null);
		SsaVerifier.verify (program);
		SsaMethod? selected = null;
		SemanticType? other = null;
		foreach (var owner in program.classes) {
			if (owner.name == "MethodProof.Other") {
				other = owner.semantic_type;
			}
		}
		foreach (var function in program.functions) {
			var method = function as SsaMethod;
			if (method != null && method.generic_method_instance != null) {
				selected = method;
			}
		}
		assert (selected != null && other != null);
		var original = selected.generic_method_instance;
		selected.generic_method_instance = original.copy (new TypeArgumentVector.single (other));
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			refused = error.message.contains ("native declaration differs from its original exact signature");
			Test.message ("%s", error.message);
		}
		assert (refused);
		selected.generic_method_instance = original;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void code_input_core() {
	try {
		CheckedProgram? source = check ("scoped-code-inspection");
		var predecessor = WeakRef (source.functions[0].symbol);
		var program = CoreGenericMonomorphizer.build (CoreBuilder.build (source));
		source = null;
		assert (predecessor.get () == null);
		CoreVerifier.verify_concrete (program);
		CoreFunction? mutating = null;
		CoreCallValue? installed = null;
		foreach (var function in program.functions) {
			if (function.name == "change_unobserved_code") {
				mutating = function;
			}
			if (function.name != "main") {
				continue;
			}
			foreach (var statement in function.body.statements) {
				var initialized = statement as CoreInitialize;
				var converted = initialized == null ? null : initialized.value as CoreIntegerConversionValue;
				if (converted != null) {
					installed = converted.operand as CoreCallValue;
				}
			}
		}
		assert (mutating != null && installed != null && installed.arguments.length == 1);
		var original = installed.arguments[0];
		installed.arguments[0] = new CoreFunctionAddress (original.span, (FunctionValueType) original.semantic_type, mutating);
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			refused = error.message.contains ("readonly scoped inspector");
			Test.message ("%s", error.message);
		}
		assert (refused);
		installed.arguments[0] = original;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void code_input_cfg() {
	try {
		CoreProgram? source = core ("scoped-code-inspection");
		var predecessor = WeakRef (source);
		var program = CfgBuilder.build (source);
		source = null;
		assert (predecessor.get () == null);
		assert (CfgFlowChecker.check (program).diagnostic == null);
		CfgFunction? mutating = null;
		CfgCallInstruction? installed = null;
		foreach (var function in program.functions) {
			if (function.name == "change_unobserved_code") {
				mutating = function;
			}
			if (function.name != "main") {
				continue;
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var invoked = instruction as CfgCallInstruction;
					if (invoked != null && invoked.target.name == "replace_callback") {
						installed = invoked;
					}
				}
			}
		}
		assert (mutating != null && installed != null && installed.arguments.length == 1);
		var original = installed.arguments[0];
		installed.arguments[0] = new CfgFunctionAddress (original.span, (FunctionValueType) original.semantic_type, mutating);
		bool refused = false;
		try {
			refused = CfgFlowChecker.check (program).diagnostic != null;
		} catch (CfgError error) {
			refused = error.message.contains ("readonly scoped inspector");
			Test.message ("%s", error.message);
		}
		assert (refused);
		installed.arguments[0] = original;
		assert (CfgFlowChecker.check (program).diagnostic == null);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void code_input_ssa() {
	try {
		CfgProgram? source = CfgBuilder.build (core ("scoped-code-inspection"));
		var predecessor = WeakRef (source);
		var program = SsaBuilder.build (source);
		source = null;
		assert (predecessor.get () == null);
		SsaVerifier.verify (program);
		SsaFunction? mutating = null;
		SsaCallInstruction? installed = null;
		foreach (var function in program.functions) {
			if (function.name == "change_unobserved_code") {
				mutating = function;
			}
			if (function.name != "main") {
				continue;
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var invoked = instruction as SsaCallInstruction;
					if (invoked != null && invoked.target.name == "replace_callback") {
						installed = invoked;
					}
				}
			}
		}
		assert (mutating != null && installed != null && installed.arguments.length == 1);
		var original = installed.arguments[0];
		installed.arguments[0] = new SsaFunctionAddress (original.span, (FunctionValueType) original.semantic_type, mutating);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			refused = error.message.contains ("readonly scoped inspector");
			Test.message ("%s", error.message);
		}
		assert (refused);
		installed.arguments[0] = original;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void code_inspection_core() {
	try {
		CheckedProgram? source = check ("scoped-code-inspection");
		var predecessor = WeakRef (source.functions[0].symbol);
		var program = CoreGenericMonomorphizer.build (CoreBuilder.build (source));
		source = null;
		assert (predecessor.get () == null);
		CoreVerifier.verify_concrete (program);
		CoreFunction? target = null;
		CoreInitialize? read = null;
		foreach (var function in program.functions) {
			if (function.name != "inspect_code") {
				continue;
			}
			target = function;
			foreach (var statement in function.body.statements) {
				var initialized = statement as CoreInitialize;
				var load = initialized == null ? null : initialized.value as CoreLoadValue;
				if (load != null && load.source is CoreIndirectFieldPlace) {
					read = initialized;
				}
			}
		}
		assert (target != null && read != null);
		var observed = (CoreLoadValue) read.value;
		int position = (int) target.body.statements.length - 1;
		target.body.statements.insert (position, new CoreStore (read.span, observed.source, observed));
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			refused = error.message.contains ("readonly scoped inspector");
			Test.message ("%s", error.message);
		}
		assert (refused);
		target.body.statements.remove_index (position);
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void code_inspection_cfg() {
	try {
		CoreProgram? source = core ("scoped-code-inspection");
		var predecessor = WeakRef (source);
		var program = CfgBuilder.build (source);
		source = null;
		assert (predecessor.get () == null);
		assert (CfgFlowChecker.check (program).diagnostic == null);
		CfgBlock? body = null;
		CfgEvaluateInstruction? read = null;
		foreach (var function in program.functions) {
			if (function.name != "inspect_code") {
				continue;
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var evaluated = instruction as CfgEvaluateInstruction;
					var load = evaluated == null ? null : evaluated.value as CfgLoadValue;
					if (load != null && load.source is CfgIndirectFieldPlace) {
						body = block;
						read = evaluated;
					}
				}
			}
		}
		assert (body != null && read != null);
		body.instructions.add (new CfgStore (read.span, ((CfgLoadValue) read.value).source, read.result));
		bool refused = false;
		try {
			refused = CfgFlowChecker.check (program).diagnostic != null;
		} catch (CfgError error) {
			refused = error.message.contains ("readonly scoped inspector");
			Test.message ("%s", error.message);
		}
		assert (refused);
		body.instructions.remove_index (body.instructions.length - 1);
		assert (CfgFlowChecker.check (program).diagnostic == null);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void code_inspection_ssa() {
	try {
		CfgProgram? source = CfgBuilder.build (core ("scoped-code-inspection"));
		var predecessor = WeakRef (source);
		var program = SsaBuilder.build (source);
		source = null;
		assert (predecessor.get () == null);
		SsaVerifier.verify (program);
		SsaBlock? body = null;
		SsaLoadInstruction? read = null;
		foreach (var function in program.functions) {
			if (function.name != "inspect_code") {
				continue;
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var load = instruction as SsaLoadInstruction;
					if (load != null && load.source is SsaIndirectFieldPlace) {
						body = block;
						read = load;
					}
				}
			}
		}
		assert (body != null && read != null);
		body.instructions.add (new SsaStoreInstruction (read.span, read.source, read.result));
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			refused = error.message.contains ("readonly scoped inspector");
			Test.message ("%s", error.message);
		}
		assert (refused);
		body.instructions.remove_index (body.instructions.length - 1);
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void copied_inspection_core() {
	try {
		CheckedProgram? source = check ("copied-record-slot-inspection");
		var predecessor = WeakRef (source.functions[0].symbol);
		var program = CoreGenericMonomorphizer.build (CoreBuilder.build (source));
		source = null;
		assert (predecessor.get () == null);
		CoreVerifier.verify_concrete (program);
		CoreFunction? inspector = null;
		CoreInitialize? read = null;
		int position = -1;
		foreach (var function in program.functions) {
			if (function.implicit_receiver == null || !function.return_type.is_struct_storage () || function.parameters.length != 1) {
				continue;
			}
			for (int i = 0; i < function.body.statements.length; i++) {
				var initialized = function.body.statements[i] as CoreInitialize;
				var value = initialized == null ? null : initialized.value as CoreLoadValue;
				var field = value == null ? null : value.source as CoreIndirectFieldPlace;
				if (field != null && field.field.containing_type.semantic_type == function.parameters[0].semantic_type) {
					inspector = function;
					read = initialized;
					position = i + 1;
				}
			}
		}
		assert (inspector != null && read != null);
		var loaded = (CoreLoadValue) read.value;
		inspector.body.statements.insert (position, new CoreStore (read.span, loaded.source, loaded));
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			refused = error.message.contains ("readonly scoped inspector");
			Test.message ("%s", error.message);
		}
		assert (refused);
		inspector.body.statements.remove_index (position);
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void copied_inspection_cfg() {
	try {
		CoreProgram? previous = core ("copied-record-slot-inspection");
		var predecessor = WeakRef (previous);
		var program = CfgBuilder.build (previous);
		previous = null;
		assert (predecessor.get () == null);
		assert (CfgFlowChecker.check (program).diagnostic == null);
		CfgBlock? body = null;
		CfgEvaluateInstruction? read = null;
		int position = -1;
		foreach (var function in program.functions) {
			if (function.implicit_receiver == null || !function.return_type.is_struct_storage () || function.parameters.length != 1) {
				continue;
			}
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var evaluation = block.instructions[i] as CfgEvaluateInstruction;
					var value = evaluation == null ? null : evaluation.value as CfgLoadValue;
					var field = value == null ? null : value.source as CfgIndirectFieldPlace;
					if (field != null && field.field.containing_type.semantic_type == function.parameters[0].semantic_type) {
						body = block;
						read = evaluation;
						position = block.instructions.length;
					}
				}
			}
		}
		assert (body != null && read != null);
		body.instructions.insert (position, new CfgStore (read.span, ((CfgLoadValue) read.value).source, read.result));
		bool refused = false;
		try {
			refused = CfgFlowChecker.check (program).diagnostic != null;
		} catch (CfgError error) {
			refused = error.message.contains ("readonly scoped inspector");
			Test.message ("%s", error.message);
		}
		assert (refused);
		body.instructions.remove_index (position);
		assert (CfgFlowChecker.check (program).diagnostic == null);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void copied_inspection_ssa() {
	try {
		CfgProgram? previous = CfgBuilder.build (core ("copied-record-slot-inspection"));
		var predecessor = WeakRef (previous);
		var program = SsaBuilder.build (previous);
		previous = null;
		assert (predecessor.get () == null);
		SsaVerifier.verify (program);
		SsaBlock? body = null;
		SsaLoadInstruction? read = null;
		int position = -1;
		foreach (var function in program.functions) {
			if (function.implicit_receiver == null || !function.return_type.is_struct_storage () || function.parameters.length != 1) {
				continue;
			}
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var load = block.instructions[i] as SsaLoadInstruction;
					var field = load == null ? null : load.source as SsaIndirectFieldPlace;
					if (field != null && field.field.containing_type.semantic_type == function.parameters[0].semantic_type) {
						body = block;
						read = load;
						position = block.instructions.length;
					}
				}
			}
		}
		assert (body != null && read != null);
		body.instructions.insert (position, new SsaStoreInstruction (read.span, read.source, read.result));
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			refused = error.message.contains ("readonly scoped inspector");
			Test.message ("%s", error.message);
		}
		assert (refused);
		body.instructions.remove_index (position);
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void historical_owner_call_producer() {
	try {
		string text = "class C{init(){}}class D{init(){}}void loan<T>(borrowed T v) where T:Ownable{}void sink<T>(owned T v) where T:Ownable{}void stage<T>(owned T input,bool send) where T:Ownable{owned T current=move input;loan<T>(current);if(send){sink<T>(move current);}}int main(){owned C l=C.init();var h=new C();stage<C>(move l,false);stage<C>(move h,true);return 42;}owned T echo<T>(owned T v) where T:Ownable{return move v;}";
		var parsed = Parser.parse (new SourceFile.from_text ("historical-owner-producer", text));
		assert (parsed.diagnostic == null);
		SemanticResult? source = SemanticAnalyzer.analyze (parsed.unit);
		assert (source.diagnostic == null);
		var predecessor = WeakRef (source.program.generic_functions[0].definition);
		var program = CoreBuilder.build (source.program);
		source = null;
		assert (predecessor.get () == null);
		CoreVerifier.verify (program);
		CoreGenericFunction? producer = null;
		CoreGenericFunction? function = null;
		foreach (var candidate in program.generic_functions) {
			if (candidate.name == "echo") {
				producer = candidate;
			}
			if (candidate.name == "stage") {
				function = candidate;
			}
		}
		assert (producer != null && function != null);
		var original = (CoreOwnershipTransfer) function.body.statements[1];
		var types = new GenericArray<SemanticType> ();
		types.add (original.source.place.semantic_type);
		var arguments = new GenericArray<CoreValue> ();
		arguments.add (new CoreOwnedArgumentValue (original.span, producer.parameters[0], original.cleanup, original.source, original.source.place.semantic_type));
		function.body.statements[1] = new CoreInitialize (original.span, original.destination.place, new CoreGenericCall (original.span, original.source.place.semantic_type, producer, types, arguments), original.destination);
		CoreVerifier.verify (program);
		function.body.statements[1] = original;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void fresh_result_cfg_extent() {
	try {
		CoreProgram? previous = core ("generic-owner-fresh-results");
		var predecessor = WeakRef (previous);
		var program = CfgBuilder.build (previous);
		previous = null;
		assert (predecessor.get () == null);
		assert (CfgFlowChecker.check (program).diagnostic == null);
		var origins = new CfgCallerResultOrigins (program);
		CfgOwnershipTransferInstruction? transfer = null;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var candidate = instruction as CfgOwnershipTransferInstruction;
					if (candidate == null || !candidate.cleanup.is_object || candidate.cleanup.is_heap_object) {
						continue;
					}
					var roots = origins.inputs (function, candidate.source);
					if ((roots.domains & GenericResultOrigins.CALLER) != 0) {
						transfer = candidate;
					}
				}
			}
		}
		assert (transfer != null && transfer.destination.text_extent != null);
		var extent = transfer.destination.text_extent;
		transfer.destination.text_extent = new Astra.Text.TextLoanExtent (null, extent.ordinal + 1);
		bool refused = false;
		try {
			refused = CfgFlowChecker.check (program).diagnostic != null;
		} catch (CfgError error) {
			refused = error.message.contains ("ownership transfer");
			Test.message ("%s", error.message);
		}
		assert (refused);
		transfer.destination.text_extent = extent;
		assert (CfgFlowChecker.check (program).diagnostic == null);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void fresh_result_core_roots() {
	try {
		CheckedProgram? checked = check ("generic-caller-result-roots");
		var source = WeakRef (checked.generic_functions[0].definition);
		var program = CoreGenericMonomorphizer.build (CoreBuilder.build (checked));
		checked = null;
		assert (source.get () == null);
		CoreVerifier.verify (program);
		CoreFunction? identity = null;
		foreach (var function in program.functions) {
			if (function.generic_instance != null && function.generic_instance.origin.name == "identity" && function.result_storage != null) {
				identity = function;
			}
		}
		assert (identity != null);
		CoreOwnershipReturn? original = null;
		int position = -1;
		for (int i = 0; i < identity.body.statements.length; i++) {
			if (identity.body.statements[i] is CoreOwnershipReturn) {
				original = (CoreOwnershipReturn) identity.body.statements[i];
				position = i;
			}
		}
		assert (original != null && original.source != null);
		var storage = identity.result_storage;
		var constructed = new CoreOwnedObjectResultConstruction (original.span, storage, storage.object_class.constructor, new GenericArray<CoreValue> ());
		identity.body.statements[position] = new CoreOwnershipReturn (original.span, original.semantic_type, original.cleanup, null, constructed, ObjectResultProvenance.RESULT_STORAGE);
		bool refused = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			refused = error.message.contains ("callee-local storage cannot escape");
			Test.message ("%s", error.message);
		}
		assert (refused);
		identity.body.statements[position] = original;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void fresh_result_cfg_roots() {
	try {
		CoreProgram? previous = core ("generic-caller-result-roots");
		var predecessor = WeakRef (previous);
		var program = CfgBuilder.build (previous);
		previous = null;
		assert (predecessor.get () == null);
		assert (CfgFlowChecker.check (program).diagnostic == null);
		CfgFunction? owner = null;
		CfgCallInstruction? producer = null;
		CfgLocalPlace? returned = null;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var call = instruction as CfgCallInstruction;
					if (call != null && call.target.implicit_receiver == null && call.target.owned_cleanup != null && function.result_storage != null) {
						owner = function;
						producer = call;
					}
					var capture = instruction as CfgOwnershipReturnInstruction;
					if (capture != null && capture.result.source != null && capture.result.provenance == ObjectResultProvenance.OWNED_PARAMETER_STORAGE && function.parameters.length == 1) {
						returned = capture.result.source;
					}
				}
			}
		}
		assert (owner != null && producer != null);
		// Select the actual return owner in this call's function.
		returned = null;
		foreach (var block in owner.blocks) {
			foreach (var instruction in block.instructions) {
				var capture = instruction as CfgOwnershipReturnInstruction;
				if (capture != null) {
					returned = capture.result.source;
				}
			}
		}
		assert (returned != null);
		var roots = new CfgCallerResultOrigins (program).inputs (owner, returned);
		assert (roots.domains == 0 && roots.input_count == 1 && roots.input (0) == 0);
		var argument = producer.arguments[0];
		producer.arguments[0] = owner.result_storage;
		roots = new CfgCallerResultOrigins (program).inputs (owner, returned);
		assert ((roots.domains & GenericResultOrigins.CALLER) != 0);
		bool refused = false;
		try {
			refused = CfgFlowChecker.check (program).diagnostic != null;
		} catch (CfgError error) {
			refused = true;
			Test.message ("%s", error.message);
		}
		assert (refused);
		producer.arguments[0] = argument;
		assert (CfgFlowChecker.check (program).diagnostic == null);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void fresh_result_ssa_roots() {
	try {
		CfgProgram? previous = CfgBuilder.build (core ("generic-caller-result-roots"));
		var predecessor = WeakRef (previous);
		var program = SsaBuilder.build (previous);
		previous = null;
		assert (predecessor.get () == null);
		SsaVerifier.verify (program);
		SsaFunction? owner = null;
		SsaCallInstruction? producer = null;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var call = instruction as SsaCallInstruction;
					if (call != null && call.target != null && call.target.implicit_receiver == null && call.target.owned_cleanup != null && function.result_storage != null) {
						owner = function;
						producer = call;
					}
				}
			}
		}
		assert (owner != null && producer != null);
		SsaValue? returned = null;
		foreach (var block in owner.blocks) {
			var capture = block.terminator as SsaOwnershipReturn;
			if (capture != null) {
				returned = capture.value;
			}
		}
		assert (returned != null && new SsaCallerResultOrigins (program).incoming (owner, returned));
		var argument = producer.arguments[0];
		producer.arguments[0] = owner.result_storage;
		assert (!new SsaCallerResultOrigins (program).incoming (owner, returned));
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			refused = true;
			Test.message ("%s", error.message);
		}
		assert (refused);
		producer.arguments[0] = argument;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void owner_local_chains_core() {
	try {
		CheckedProgram? checked = check ("generic-owner-local-chains");
		var predecessor = WeakRef (checked.generic_functions[0].definition);
		var program = CoreBuilder.build (checked);
		checked = null;
		assert (predecessor.get () == null);
		CoreVerifier.verify (program);
		CoreGenericFunction? chain = null;
		foreach (var function in program.generic_functions) {
			if (function.name == "chain") {
				chain = function;
			}
		}
		assert (chain != null && chain.owned_locals.length == 3);
		CoreOwnershipTransfer? first = null;
		CoreOwnershipTransfer? second = null;
		int index = -1;
		for (int i = 0; i < chain.body.statements.length; i++) {
			var transfer = chain.body.statements[i] as CoreOwnershipTransfer;
			if (transfer == null) {
				continue;
			}
			if (first == null) {
				first = transfer;
			} else {
				second = transfer;
				index = i;
			}
		}
		assert (first != null && second != null && first.destination == second.source);
		chain.body.statements[index] = new CoreOwnershipTransfer (second.span, first.source, second.destination, second.cleanup);
		bool refused = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			refused = error.message.contains ("live incoming owner and an empty fresh destination");
			Test.message ("%s", error.message);
		}
		assert (refused);
		chain.body.statements[index] = second;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void owner_local_chains_cfg() {
	try {
		CoreProgram? predecessor = core ("generic-owner-local-chains");
		var graph = WeakRef (predecessor);
		var program = CfgBuilder.build (predecessor);
		predecessor = null;
		assert (graph.get () == null);
		assert (CfgFlowChecker.check (program).diagnostic == null);
		CfgFunction? caller = null;
		foreach (var function in program.functions) {
			if (function.return_type is ClassType && function.owned_cleanup != null && !function.heap_result) {
				caller = function;
			}
		}
		assert (caller != null);
		CfgAcquireParameter? acquisition = null;
		int index = -1;
		for (int i = 0; i < caller.entry.instructions.length; i++) {
			if (caller.entry.instructions[i] is CfgAcquireParameter) {
				acquisition = (CfgAcquireParameter) caller.entry.instructions[i];
				index = i;
				break;
			}
		}
		assert (acquisition != null);
		caller.entry.instructions.remove_index (index);
		bool refused = false;
		try {
			refused = CfgFlowChecker.check (program).diagnostic != null;
		} catch (CfgError error) {
			refused = true;
			Test.message ("%s", error.message);
		}
		assert (refused);
		caller.entry.instructions.insert (index, acquisition);
		assert (CfgFlowChecker.check (program).diagnostic == null);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void owner_local_chains_ssa() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("generic-owner-local-chains"));
		var graph = WeakRef (predecessor);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (graph.get () == null);
		SsaVerifier.verify (program);
		SsaFunction? owner = null;
		SsaOwnershipReturn? original = null;
		foreach (var function in program.functions) {
			foreach (var candidate in function.blocks) {
				var returned = candidate.terminator as SsaOwnershipReturn;
				if (returned != null && returned.provenance == ObjectResultProvenance.OWNED_PARAMETER_STORAGE) {
					owner = function;
					original = returned;
				}
			}
		}
		assert (owner != null && original != null && original.source_parameter != null && original.value == original.source_parameter);
		var parameter = original.source_parameter;
		int index = parameter.ordinal;
		owner.parameters[index] = new SsaFunctionParameter (parameter.span, parameter.name_span, parameter.name, parameter.semantic_type, parameter.ordinal, parameter.pointer_contract);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			refused = error.message.contains ("parameter");
			Test.message ("%s", error.message);
		}
		assert (refused);
		owner.parameters[index] = parameter;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void dependent_fixed_result_contracts() {
	try {
		CheckedProgram? checked = check ("dependent-fixed-Class-results");
		var source = WeakRef (checked.generic_functions[0].definition);
		foreach (var function in checked.generic_functions) {
			function.definition.result_origins = new GenericResultOrigins (GenericResultOrigins.UNKNOWN);
		}
		CoreProgram? symbolic = CoreBuilder.build (checked);
		checked = null;
		assert (source.get () == null);
		CoreVerifier.verify (symbolic);
		var equations = CoreGenericResultOrigins.derive (symbolic);
		var projection = new CoreResultOriginProjection (symbolic);
		uint projected_domains = 0;
		int projected = 0;
		foreach (var function in symbolic.generic_functions) {
			assert (function.return_type is ClassType && !function.return_type.is_parameterized ());
			if (function.name == "allocate_marker") {
				assert (equations.lookup (function).domains == GenericResultOrigins.HEAP);
				continue;
			}
			assert ((equations.lookup (function).domains & GenericResultOrigins.UNKNOWN) != 0);
			foreach (var owner in symbolic.classes) {
				var key = owner.generic_instance;
				if (key == null || key.definition.name != "ProductionHost") {
					continue;
				}
				var equation = projection.project (function, key.arguments.copy_values ());
				bool caller = key.arguments.at (0).display_name () == "CallerProducer";
				uint expected = caller ? GenericResultOrigins.CALLER : GenericResultOrigins.HEAP;
				if (caller && function.name.has_prefix ("alternative")) {
					expected |= GenericResultOrigins.HEAP;
				}
				assert (equation.domains == expected);
				projected_domains |= equation.domains;
				projected++;
			}
		}
		assert (projected == 10 && projected_domains == 3);
		equations = null;
		projection = null;
		var predecessor = WeakRef (symbolic.generic_functions[0]);
		var program = CoreGenericMonomorphizer.build (symbolic);
		symbolic = null;
		assert (predecessor.get () == null);
		CoreVerifier.verify_concrete (program);
		CoreFunction? heap = null;
		uint actual_domains = 0;
		foreach (var function in program.functions) {
			if (function.generic_instance == null) {
				continue;
			}
			assert (function.generic_instance.has_storage_domain (function));
			actual_domains |= function.heap_result ? 2 : 1;
			if (function.heap_result) {
				heap = function;
			}
		}
		assert (heap != null && actual_domains == 3);
		heap.heap_result = false;
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			refused = true;
			Test.message ("%s", error.message);
		}
		assert (refused);
		heap.heap_result = true;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void member_fixed_result_contracts() {
	try {
		CheckedProgram? checked = check ("member-fixed-Class-factories");
		var source = WeakRef (checked.generic_functions[0].definition);
		foreach (var function in checked.generic_functions) {
			function.definition.result_origins = new GenericResultOrigins (GenericResultOrigins.UNKNOWN);
		}
		CoreProgram? symbolic = CoreBuilder.build (checked);
		checked = null;
		assert (source.get () == null);
		foreach (var function in symbolic.all_definitions ()) {
			Test.message ("projection input %s heap=%s storage=%s", function.name, function.heap_result.to_string (), (function.result_storage != null).to_string ());
		}
		CoreVerifier.verify (symbolic);
		SemanticType? integer = null;
		SemanticType? boolean = null;
		foreach (var owner in symbolic.classes) {
			var key = owner.generic_instance;
			if (key == null) {
				continue;
			}
			if (key.definition.name == "Maker") {
				boolean = key.arguments.at (0);
			}
			if (key.definition.name == "MadeCrate" && key.arguments.at (0).display_name () == "int") {
				integer = key.arguments.at (0);
			}
		}
		assert (integer != null && boolean != null);
		HashTable<CoreGenericFunction, GenericResultOrigins>? equations = CoreGenericResultOrigins.derive (symbolic);
		CoreResultOriginProjection? projection = new CoreResultOriginProjection (symbolic);
		int applications = 0;
		foreach (var function in symbolic.generic_functions) {
			var arguments = new GenericArray<SemanticType> ();
			if (function.type_parameters.length == 2) {
				assert ((equations.lookup (function).domains & GenericResultOrigins.UNKNOWN) != 0);
				arguments.add (integer);
				applications++;
			}
			arguments.add (boolean);
			var equation = projection.project (function, arguments);
			assert (equation.domains == (function.name == "make_caller" ? GenericResultOrigins.CALLER : GenericResultOrigins.HEAP));
			assert (projection.project (function, arguments) == equation);
		}
		assert (applications == 2);
		equations = null;
		projection = null;
		var predecessor = WeakRef (symbolic.generic_functions[0]);
		var program = CoreGenericMonomorphizer.build (symbolic);
		symbolic = null;
		assert (predecessor.get () == null);
		CoreVerifier.verify_concrete (program);
		int closed_applications = 0;
		uint domains = 0;
		foreach (var function in program.functions) {
			var key = function.generic_instance;
			if (key == null) {
				continue;
			}
			assert (key.has_storage_domain (function));
			if (key.origin.name == "nested_application") {
				assert (function.heap_result && !function.return_type.is_parameterized ());
				closed_applications++;
			}
			domains |= function.heap_result ? 2 : 1;
		}
		assert (closed_applications == 2 && domains == 3);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void member_wrapper_result_contracts() {
	try {
		CheckedProgram? checked = check ("member-wrapper-result-origins");
		var source = WeakRef (checked.generic_functions[0].definition);
		foreach (var function in checked.generic_functions) {
			function.definition.result_origins = new GenericResultOrigins (GenericResultOrigins.UNKNOWN);
		}
		CoreProgram? symbolic = CoreBuilder.build (checked);
		checked = null;
		assert (source.get () == null);
		CoreVerifier.verify (symbolic);
		CoreClass? factory = null;
		CoreMethod? identity = null;
		int identity_index = -1;
		foreach (var owner in symbolic.classes) {
			if (owner.generic_instance == null || owner.generic_instance.definition.name != "WrappedFactory") {
				continue;
			}
			factory = owner;
			for (int m = 0; m < owner.methods.length; m++) {
				var binding = owner.methods[m].generic_method_instance;
				if (binding != null && owner.generic_instance.definition.generic_method_name (binding.member) == "identity") {
					identity = owner.methods[m];
					identity_index = m;
				}
			}
		}
		assert (factory != null && identity != null && identity_index >= 0);
		var arguments = factory.generic_instance.arguments.copy_values ();
		arguments.add (identity.return_type);
		CoreGenericFunction? recursive = null;
		var projection = new CoreResultOriginProjection (symbolic);
		int results = 0;
		foreach (var function in symbolic.generic_functions) {
			if (function.name == "recursive_identity") {
				recursive = function;
			}
			var equation = projection.project (function, arguments);
			assert (equation.domains == (function.name == "relay_caller" ? GenericResultOrigins.CALLER : GenericResultOrigins.HEAP));
			results++;
		}
		assert (results == 5 && recursive != null);
		factory.methods.remove_index (identity_index);
		var missing = new CoreResultOriginProjection (symbolic);
		assert ((missing.project (recursive, arguments).domains & GenericResultOrigins.UNKNOWN) != 0);
		factory.methods.insert (identity_index, identity);
		projection = new CoreResultOriginProjection (symbolic);
		assert (projection.project (recursive, arguments).domains == GenericResultOrigins.HEAP);
		CoreVerifier.verify (symbolic);
		var predecessor = WeakRef (symbolic.generic_functions[0]);
		var program = CoreGenericMonomorphizer.build (symbolic);
		symbolic = null;
		// Drop analysis caches before proving the predecessor was destroyed.
		projection = null;
		missing = null;
		factory = null;
		identity = null;
		recursive = null;
		assert (predecessor.get () == null);
		CoreVerifier.verify_concrete (program);
		uint domains = 0;
		foreach (var function in program.functions) {
			var key = function.generic_instance;
			if (key == null) {
				continue;
			}
			assert (key.has_storage_domain (function));
			if (key.origin.name == "relay_caller") {
				assert (!function.heap_result && function.result_storage != null);
				domains |= 1;
			}
			if (key.origin.name == "relay_heap") {
				assert (function.heap_result && function.result_storage == null);
				domains |= 2;
			}
		}
		assert (domains == 3);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void class_signature_origins_contracts() {
	try {
		CheckedProgram? checked = check ("class-signature-origins");
		var source = WeakRef (checked.generic_functions[0].definition);
		foreach (var function in checked.generic_functions) {
			function.definition.result_origins = new GenericResultOrigins (GenericResultOrigins.UNKNOWN);
		}
		CoreProgram? symbolic = CoreBuilder.build (checked);
		checked = null;
		assert (source.get () == null);
		CoreVerifier.verify (symbolic);
		HashTable<CoreGenericFunction, GenericResultOrigins>? equations = CoreGenericResultOrigins.derive (symbolic);
		int producers = 0;
		foreach (var function in symbolic.generic_functions) {
			if (function.owned_cleanup == null) {
				continue;
			}
			var equation = equations.lookup (function);
			assert (equation != null);
			if (function.name == "build_caller") {
				assert (equation.domains == GenericResultOrigins.CALLER && equation.input_count == 0);
			} else if (function.name == "build_heap") {
				assert (equation.domains == GenericResultOrigins.HEAP && equation.input_count == 0);
			} else {
				assert (equation.domains == 0 && equation.input_count == 1 && equation.input (0) == 0);
			}
			producers++;
		}
		assert (producers == 6);
		equations = null;
		var predecessor = WeakRef (symbolic.generic_functions[0]);
		var program = CoreGenericMonomorphizer.build (symbolic);
		symbolic = null;
		assert (predecessor.get () == null);
		CoreVerifier.verify_concrete (program);
		uint fixed_domains = 0;
		uint constructed_domains = 0;
		CoreFunction? heap = null;
		foreach (var function in program.functions) {
			var identity = function.generic_instance;
			if (identity == null) {
				continue;
			}
			assert (identity.has_storage_domain (function));
			if (identity.origin.name == "return_fixed") {
				fixed_domains |= function.heap_result ? 2 : 1;
			}
			if (identity.origin.name == "return_crate") {
				constructed_domains |= function.heap_result ? 2 : 1;
			}
			if (identity.origin.name == "build_heap") {
				heap = function;
			}
		}
		assert (fixed_domains == 3 && constructed_domains == 3 && heap != null);
		var missing_cleanup = new CoreFunction (heap.span, heap.name_span, heap.name,
			heap.return_type, heap.parameters, heap.locals, heap.body);
		missing_cleanup.generic_instance = heap.generic_instance;
		missing_cleanup.heap_result = heap.heap_result;
		assert (!heap.generic_instance.has_storage_domain (missing_cleanup));
		bool refused = false;
		heap.heap_result = false;
		refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("canonical consuming storage domain");
		}
		assert (refused);
		heap.heap_result = true;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void storage_requirements_contracts() {
	try {
		CheckedProgram? checked = check ("generic-storage-requirements");
		var source = WeakRef (checked.generic_functions[0].definition);
		CoreProgram? symbolic = CoreBuilder.build (checked);
		checked = null;
		assert (source.get () == null);
		CoreVerifier.verify (symbolic);
		{
			CoreGenericFunction? pair = null;
			foreach (var candidate in symbolic.generic_functions) {
				if (candidate.name == "retire_pair") {
					pair = candidate;
				}
			}
			assert (pair != null);
			CoreOwnedLocal? second = null;
			foreach (var owner in pair.owned_locals) {
				if (owner.place.incoming_parameter == pair.parameters[1]) {
					second = owner;
				}
			}
			CoreCallStatement? call = null;
			foreach (var statement in pair.body.statements) {
				var branch = statement as CoreIf;
				if (branch != null) {
					call = branch.then_block.statements[0] as CoreCallStatement;
				}
			}
			assert (call != null && second != null);
			var saved = call.arguments[0] as CoreOwnedArgumentValue;
			assert (saved != null && saved.source != second);
			call.arguments[0] = new CoreOwnedArgumentValue (saved.span, saved.parameter, saved.cleanup, second, saved.semantic_type);
			bool refused = false;
			try {
				CoreVerifier.verify (symbolic);
			} catch (CoreError error) {
				Test.message ("%s", error.message);
				refused = error.message.contains ("moved");
			}
			assert (refused);
			call.arguments[0] = saved;
			CoreVerifier.verify (symbolic);
		}
		var program = CoreGenericMonomorphizer.build (symbolic);
		symbolic = null;
		CoreVerifier.verify_concrete (program);
		uint masks = 0;
		int witnessed = 0;
		foreach (var function in program.functions) {
			var instance = function.generic_instance;
			if (instance == null || instance.origin.name != "retire_pair") {
				continue;
			}
			assert (instance.has_storage_domain (function));
			uint mask = (instance.storage.is_heap (0) ? 1 : 0) | (instance.storage.is_heap (1) ? 2 : 0);
			masks |= 1U << (int) mask;
			witnessed++;
		}
		assert (witnessed == 4 && masks == 15);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void owned_class_formal_contracts() {
	try {
		CheckedProgram? checked = check ("open-class-owned-formals");
		var source = WeakRef (checked.generic_functions[0].definition);
		CoreProgram? symbolic = CoreBuilder.build (checked);
		checked = null;
		assert (source.get () == null);
		CoreVerifier.verify (symbolic);
		CoreProperty? property = null;
		SemanticType? other = null;
		foreach (var application in symbolic.class_applications) {
			foreach (var candidate in application.properties) {
				if (candidate.is_borrowed) {
					property = candidate;
				} else {
					other = candidate.semantic_type;
				}
			}
		}
		assert (property != null && other != null && property.semantic_type != other);
		var original = property.semantic_type;
		property.semantic_type = other;
		bool refused = false;
		try {
			CoreVerifier.verify (symbolic);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("exact declared type and getter result");
		}
		assert (refused);
		property.semantic_type = original;
		CoreVerifier.verify (symbolic);
		var definition = WeakRef (symbolic.generic_functions[0]);
		var program = CoreGenericMonomorphizer.build (symbolic);
		symbolic = null;
		assert (definition.get () == null);
		CoreVerifier.verify_concrete (program);
		int witnessed = 0;
		foreach (var function in program.functions) {
			var instance = function.generic_instance;
			if (instance == null || (instance.origin.name != "retire_copied_formal" && instance.origin.name != "retire_owner_formal")) {
				continue;
			}
			assert (instance.owns_parameter (0) && instance.has_storage_domain (function));
			assert (!function.parameters[0].heap_object);
			function.parameters[0].heap_object = true;
			assert (!instance.has_storage_domain (function));
			refused = false;
			try {
				CoreVerifier.verify_concrete (program);
			} catch (CoreError error) {
				Test.message ("%s", error.message);
				refused = error.message.contains ("canonical consuming storage domain");
			}
			assert (refused);
			function.parameters[0].heap_object = false;
			CoreVerifier.verify_concrete (program);
			witnessed++;
		}
		assert (witnessed == 5);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void storage_vector_headers() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("storage-headers.astra", "class Child{init(){}}int drain<T>(owned T left,owned T right) where T:Ownable{return 42;}int main(){return 42;}"));
		assert (parsed.diagnostic == null);
		SemanticResult? analyzed = SemanticAnalyzer.analyze (parsed.unit);
		assert (analyzed.diagnostic == null);
		CheckedProgram? checked = analyzed.program;
		analyzed = null;
		var predecessor = WeakRef (checked.generic_functions[0].definition);
		var program = CoreBuilder.build (checked);
		checked = null;
		assert (predecessor.get () == null);
		CoreVerifier.verify (program);
		var pass = new CoreGenericMonomorphizer (program);
		var arguments = new GenericArray<SemanticType> ();
		arguments.add (program.classes[0].semantic_type);
		var headers = new GenericArray<CoreFunction> ();
		for (int mask = 0; mask < 4; mask++) {
			var storage = new GenericStorageVector (new bool[] { (mask & 1) != 0, (mask & 2) != 0 });
			var header = pass.request (program.generic_functions[0], arguments, program.functions[0], -1, storage);
			assert (header.generic_instance.has_storage_domain (header));
			assert (header.parameters[0].heap_object == ((mask & 1) != 0));
			assert (header.parameters[1].heap_object == ((mask & 2) != 0));
			foreach (var previous in headers) {
				assert (previous != header);
			}
			assert (pass.request (program.generic_functions[0], arguments, program.functions[0], -1, storage) == header);
			header.parameters[1].heap_object = !header.parameters[1].heap_object;
			assert (!header.generic_instance.has_storage_domain (header));
			header.parameters[1].heap_object = !header.parameters[1].heap_object;
			headers.add (header);
		}
		assert (pass.request (program.generic_functions[0], arguments, program.functions[0]) == headers[0]);
		assert (pass.request (program.generic_functions[0], arguments, program.functions[0], 0) == headers[1]);
		bool refused = false;
		try {
			pass.request (program.generic_functions[0], arguments, program.functions[0], -1, new GenericStorageVector.single (2));
		} catch (CoreError error) {
			refused = error.message.contains ("exact parameter positions");
		}
		assert (refused);
		assert (pass.request (program.generic_functions[0], arguments, program.functions[0], -1, new GenericStorageVector (new bool[] { true, true })) == headers[3]);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void expanding_materialization_independent() {
	try {
		ParseResult? parsed = Parser.parse (new SourceFile.from_text ("expanding-core.astra", "struct Wrapper<T>{int tag;}void expand<T>(){expand<T>();}void root(){expand<int>();}"));
		assert (parsed.diagnostic == null);
		SemanticResult? result = SemanticAnalyzer.analyze (parsed.unit);
		assert (result.diagnostic == null);
		var predecessor = WeakRef (result.program.generic_functions[0].definition);
		var program = CoreBuilder.build (result.program);
		result = null;
		parsed = null;
		assert (predecessor.get () == null);
		CoreVerifier.verify (program);
		var definition = program.generic_functions[0];
		var call = definition.body.statements[0] as CoreGenericCallStatement;
		assert (call != null && call.type_arguments.length == 1);
		var original = call.type_arguments[0];
		var root = program.functions[0];
		var original_entry = root.body.statements[0];
		var arguments = new GenericArray<SemanticType> ();
		arguments.add (original);
		call.type_arguments[0] = program.generic_structs[0].application (arguments);
		CoreVerifier.verify (program);
		bool refused = false;
		try {
			CoreGenericMonomorphizer.build (program);
		} catch (CoreError error) {
			refused = error.message.contains ("type-expression depth 128 while requesting Wrapper");
		}
		assert (refused);
		call.type_arguments[0] = original;
		// The monomorphizer consumes ordinary bodies in place. Restore the
		// entry call as well as the independent mutation before recovery.
		root.body.statements[0] = original_entry;
		CoreVerifier.verify_concrete (CoreGenericMonomorphizer.build (program));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void exchange_expansion_independent() {
	try {
		ParseResult? parsed = Parser.parse (new SourceFile.from_text ("exchange-expansion-core.astra", "struct Wrapper<T>{int tag;}void expand<T>(){expand<T>();}void exchange<T>(owned T[] a,owned T[] b){swap(a,b);expand<T>();}void root(){var a=new int[2];var b=new int[3];exchange(move a,move b);}"));
		assert (parsed.diagnostic == null);
		SemanticResult? result = SemanticAnalyzer.analyze (parsed.unit);
		assert (result.diagnostic == null);
		var predecessor = WeakRef (result.program.generic_functions[0].definition);
		var program = CoreBuilder.build (result.program);
		result = null;
		parsed = null;
		assert (predecessor.get () == null);
		CoreVerifier.verify (program);
		var definition = program.generic_functions[0];
		var call = definition.body.statements[0] as CoreGenericCallStatement;
		assert (call != null && call.type_arguments.length == 1);
		var original = call.type_arguments[0];
		var root = program.functions[0];
		var original_statements = new GenericArray<CoreStatement> ();
		foreach (var statement in root.body.statements) {
			original_statements.add (statement);
		}
		var arguments = new GenericArray<SemanticType> ();
		arguments.add (original);
		call.type_arguments[0] = program.generic_structs[0].application (arguments);
		CoreVerifier.verify (program);
		bool refused = false;
		try {
			CoreGenericMonomorphizer.build (program);
		} catch (CoreError error) {
			refused = error.message.contains ("type-expression depth 128 while requesting Wrapper");
		}
		assert (refused);
		call.type_arguments[0] = original;
		root.body.statements.remove_range (0, root.body.statements.length);
		foreach (var statement in original_statements) {
			root.body.statements.add (statement);
		}
		// Concrete cleanup filtering also densifies these consuming inputs.
		for (int index = 0; index < program.cleanups.length; index++) {
			program.cleanups[index].ordinal = index;
		}
		CoreVerifier.verify_concrete (CoreGenericMonomorphizer.build (program));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void materialization_depth_independent() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("depth.astra", "struct Wrapper<T>{int tag;}void choose<T>(){}int main(){choose<int>();return 0;}"));
		assert (parsed.diagnostic == null);
		var result = SemanticAnalyzer.analyze (parsed.unit);
		assert (result.diagnostic == null);
		CheckedProgram? checked = result.program;
		var predecessor = WeakRef (checked.generic_structs[0].definition);
		CoreProgram program = CoreBuilder.build (checked);
		checked = null;
		result = null;
		assert (predecessor.get () == null);
		CoreVerifier.verify (program);
		var root = program.functions[0];
		var initial = root.body.statements[0] as CoreGenericCallStatement;
		assert (initial != null);
		SemanticType nested = initial.type_arguments[0];
		for (int depth = 0; depth < 128; depth++) {
			var arguments = new GenericArray<SemanticType> ();
			arguments.add (nested);
			nested = program.generic_structs[0].application (arguments);
		}
		var pass = new CoreGenericMonomorphizer (program);
		var valid = new GenericArray<SemanticType> ();
		valid.add (nested);
		var saved = pass.request (program.generic_functions[0], valid, root);
		assert (pass.struct_instances.length == 128);
		var invalid = new GenericArray<SemanticType> ();
		invalid.add (program.generic_structs[0].application (valid));
		bool refused = false;
		try {
			pass.request (program.generic_functions[0], invalid, root);
		} catch (CoreError error) {
			refused = error.message.contains ("type-expression depth 128 while requesting choose");
		}
		assert (refused && pass.request (program.generic_functions[0], valid, root) == saved && pass.struct_instances.length == 128);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void independent() {
	try {
		CheckedProgram? checked = check ("copied-record");
		var prior = WeakRef (checked.classes[0]);
		CoreProgram? c = CoreBuilder.build (checked);
		checked = null;
		assert (prior.get () == null);
		CoreVerifier.verify (c);
		CoreProgram? concrete = CoreGenericMonomorphizer.build (c);
		c = null;
		prior = WeakRef (concrete.classes[0]);
		CfgProgram? g = CfgBuilder.build (concrete);
		concrete = null;
		assert (prior.get () == null);
		CfgVerifier.verify (g);
		prior = WeakRef (g.classes[0]);
		SsaProgram? s = SsaBuilder.build (g);
		g = null;
		assert (prior.get () == null);
		SsaVerifier.verify (s);
		prior = WeakRef (s.classes[0]);
		var native = NativeAbiBuilder.build (s);
		s = null;
		assert (prior.get () == null);
		NativeAbiVerifier.verify (native);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void core_substitution() {
	try {
		var program = core ("three-parameters");
		var owner = program.classes[0];
		var saved = owner.fields[2].semantic_type;
		owner.fields[2].semantic_type = owner.fields[1].semantic_type;
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			refused = error.message.contains ("substituted");
		}
		assert (refused);
		owner.fields[2].semantic_type = saved;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void cfg_initialization() {
	try {
		CoreProgram? predecessor = core ("copied-record");
		var prior = WeakRef (predecessor.classes[0]);
		var program = CfgBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		var block = program.classes[0].constructor.entry;
		int index = -1;
		for (int i = 0; i < block.instructions.length; i++) {
			var initialize = block.instructions[i] as CfgInitialize;
			if (initialize == null || !(initialize.target is CfgFieldPlace)) {
				continue;
			}
			CfgPlace root = initialize.target;
			while (root is CfgFieldPlace) {
				root = ((CfgFieldPlace) root).aggregate;
			}
			if (root is CfgIndirectFieldPlace) {
				index = i;
				break;
			}
		}
		assert (index >= 0);
		var saved = block.instructions[index];
		block.instructions.remove_index (index);
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("not initialized");
		}
		assert (refused);
		block.instructions.insert (index, saved);
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void ssa_initialization() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("copied-record"));
		var prior = WeakRef (predecessor.classes[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		var block = program.classes[0].constructor.entry;
		int index = -1;
		for (int i = 0; i < block.instructions.length; i++) {
			var initialize = block.instructions[i] as SsaInitializeInstruction;
			if (initialize == null || !(initialize.target is SsaFieldPlace)) {
				continue;
			}
			SsaMemoryPlace root = initialize.target;
			while (root is SsaFieldPlace && ((SsaFieldPlace) root).aggregate != null) {
				root = ((SsaFieldPlace) root).aggregate;
			}
			if (root is SsaIndirectFieldPlace) {
				index = i;
				break;
			}
		}
		assert (index >= 0);
		var saved = block.instructions[index];
		block.instructions.remove_index (index);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("not initialized");
		}
		assert (refused);
		block.instructions.insert (index, saved);
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_member() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("three-parameters")));
		var prior = WeakRef (predecessor.classes[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		NativeFunction? constructor = null;
		foreach (var function in program.functions) {
			if (function.kind == NativeCallableKind.CONSTRUCTOR && function.declaring_type_is_class && function.declaring_type_ordinal == 0) {
				constructor = function;
			}
		}
		assert (constructor != null);
		var saved = constructor.signature.parameters[2];
		constructor.signature.parameters[2] = new NativeParameter.typed (saved.span, saved.name_span, saved.name,
			saved.ordinal, new NativeScalarAbiType (NativeScalarType.I32));
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			refused = error.message.contains ("parameter physical type");
		}
		assert (refused);
		constructor.signature.parameters[2] = saved;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void inline_record_ssa() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("owning-record-payload"));
		var prior = WeakRef (predecessor.classes[1]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaRecordFieldCommit? commit = null;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					if (instruction is SsaRecordFieldCommit) {
						commit = (SsaRecordFieldCommit) instruction;
					}
				}
			}
		}
		assert (commit != null && commit.leaves.length >= 2);
		var first = commit.leaves[0];
		commit.leaves[0] = commit.leaves[1];
		commit.leaves[1] = first;
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			refused = error.message.contains ("record field move changed");
		}
		assert (refused);
		commit.leaves[1] = commit.leaves[0];
		commit.leaves[0] = first;
		SsaVerifier.verify (program);
		var descriptor = commit.destination.field;
		var record = descriptor.record_owner;
		descriptor.record_owner = null;
		refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			refused = true;
		}
		assert (refused);
		descriptor.record_owner = record;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void inline_record_native() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("owning-buffer-record")));
		var prior = WeakRef (predecessor.classes[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		var owner = program.classes[0];
		var original = owner.fields[0];
		assert (original.owns_record);
		owner.fields[0] = new NativeClassField (original.span, original.name, original.type_name,
			original.ordinal, original.text_snapshot, original.storage_type, original.record_ordinal,
			original.is_private, original.owned_class_ordinal, original.owns_buffer, original.resource_owner, false);
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			refused = true;
		}
		assert (refused);
		owner.fields[0] = original;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void projected_record_cfg() {
	try {
		CoreProgram? predecessor = core ("nested-record-producer");
		var prior = WeakRef (predecessor.structs[0]);
		var program = CfgBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		bool tested = false;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var acquire = block.instructions[i] as CfgStructBoundaryAcquire;
					if (acquire == null || acquire.projection == null) {
						continue;
					}
					assert (acquire.record_move != null);
					block.instructions.remove_index (i);
					bool refused = false;
					try {
						CfgVerifier.verify (program);
					} catch (CfgError error) {
						Test.message ("%s", error.message);
						refused = error.message.contains ("subobject move");
					}
					assert (refused);
					block.instructions.insert (i, acquire);
					CfgVerifier.verify (program);
					tested = true;
				}
			}
		}
		assert (tested);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void projected_record_ssa() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("nested-record-producer"));
		var prior = WeakRef (predecessor.structs[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaStructBoundaryAcquire? acquire = null;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var candidate = instruction as SsaStructBoundaryAcquire;
					if (candidate != null && candidate.projection != null) {
						acquire = candidate;
					}
				}
			}
		}
		assert (acquire != null && acquire.leaves.length == 2 && acquire.record_move != null);
		var first = acquire.leaves[0];
		acquire.leaves[0] = acquire.leaves[1];
		acquire.leaves[1] = first;
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("subobject move changed");
		}
		assert (refused);
		acquire.leaves[1] = acquire.leaves[0];
		acquire.leaves[0] = first;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void projected_buffer_ssa() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("nested-buffer-producer"));
		var prior = WeakRef (predecessor.structs[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		bool tested = false;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var write = block.instructions[i] as SsaBufferWriteInstruction;
					var acquire = write == null ? null : write.record_boundary as SsaStructBoundaryAcquire;
					if (acquire == null || acquire.projection == null || acquire.record_move == null) {
						continue;
					}
					block.instructions.insert (i + 1, write);
					bool refused = false;
					try {
						SsaVerifier.verify (program);
					} catch (SsaError error) {
						Test.message ("%s", error.message);
						refused = true;
					}
					assert (refused);
					block.instructions.remove_index (i + 1);
					SsaVerifier.verify (program);
					write.record_boundary = null;
					refused = false;
					try {
						SsaVerifier.verify (program);
					} catch (SsaError error) {
						Test.message ("%s", error.message);
						refused = error.message.contains ("acquisition/disarm");
					}
					assert (refused);
					write.record_boundary = acquire;
					SsaVerifier.verify (program);
					tested = true;
				}
			}
		}
		assert (tested);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void method_tuple_core() {
	try {
		CheckedProgram? predecessor = check ("method-tuples");
		var prior = WeakRef (predecessor.classes[0]);
		var program = CoreGenericMonomorphizer.build (CoreBuilder.build (predecessor));
		predecessor = null;
		assert (prior.get () == null);
		CoreMethod? chosen = null;
		CoreMethod? alternate = null;
		foreach (var method in program.classes[0].methods) {
			if (method.name == "phantom<int,Pair>") {
				chosen = method;
			}
			if (method.name == "phantom<int,bool>") {
				alternate = method;
			}
		}
		assert (chosen != null && alternate != null);
		var original = chosen.generic_method_instance;
		assert (original.arguments.length == 2 && original.arguments.at (0) == alternate.generic_method_instance.arguments.at (0));
		chosen.generic_method_instance = original.copy (alternate.generic_method_instance.arguments);
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			refused = error.message.contains ("declared generic Class");
		}
		assert (refused);
		chosen.generic_method_instance = original;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void method_tuple_native() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("method-tuples")));
		var prior = WeakRef (predecessor.classes[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		NativeFunction? chosen = null;
		NativeFunction? alternate = null;
		foreach (var function in program.functions) {
			if (function.name == "phantom<int,Pair>") {
				chosen = function;
			}
			if (function.name == "phantom<int,bool>") {
				alternate = function;
			}
		}
		assert (chosen != null && alternate != null);
		var original = chosen.generic_method_instance;
		assert (original.argument_count == 2 && original.argument_type (1).record != null);
		chosen.generic_method_instance = new NativeGenericMethodInstance.declared (original.definition,
			original.class_ordinal, original.member, original.target_ordinal,
			new NativeDeclaredType[] { original.argument_type (0), alternate.generic_method_instance.argument_type (1) });
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("native origin/key mismatch");
		}
		assert (refused);
		chosen.generic_method_instance = original;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void substituted_constraint_native() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("substituted-constraints")));
		var prior = WeakRef (predecessor.classes[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		NativeClassPlan? owner = null;
		foreach (var candidate in program.classes) {
			if (candidate.name == "Gate<int>") {
				owner = candidate;
			}
		}
		assert (owner != null);
		var original = owner.generic_instance;
		var declaration = original.declared_structure;
		assert (declaration.argument_count == 1 && declaration.field_count == 0);
		NativeDeclaredMember[] members = {};
		for (int m = 0; m < declaration.member_count; m++) {
			members += declaration.member (m);
		}
		var forged = new NativeDeclaredClass (original.definition,
			new NativeDeclaredType[] { new NativeDeclaredType ("bool", new NativeScalarAbiType (NativeScalarType.B1)) },
			{}, members);
		var targets = new int[original.member_count];
		for (int m = 0; m < targets.length; m++) {
			targets[m] = original.member_target (m);
		}
		int[] no_properties = null;
		owner.generic_instance = new NativeExactClassInstance.declared (original.definition, forged, targets, no_properties);
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("Class substituted capability constraint");
		}
		assert (refused);
		owner.generic_instance = original;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void phantom_class_native() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("substituted-constraints")));
		var prior = WeakRef (predecessor.classes[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		NativeClassPlan? owner = null;
		foreach (var candidate in program.classes) {
			if (candidate.name == "Empty<int>") {
				owner = candidate;
			}
		}
		assert (owner != null);
		var original = owner.generic_instance;
		var declaration = original.declared_structure;
		assert (declaration.argument_count == 1 && declaration.field_count == 0 && declaration.member_count == 0);
		var forged = new NativeDeclaredClass (original.definition,
			new NativeDeclaredType[] { new NativeDeclaredType ("bool", new NativeScalarAbiType (NativeScalarType.B1)) }, {}, {});
		int[] no_targets = null;
		owner.generic_instance = new NativeExactClassInstance.declared (original.definition, forged, no_targets, no_targets);
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		if (!refused) {
			Test.message ("native Class accepted a changed phantom type argument with the original nominal plan");
			Test.fail ();
		}
		owner.generic_instance = original;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void deferred_native_origin() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("deferred-lifetimes")));
		var prior = WeakRef (predecessor.classes[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		NativeFunction? discard = null;
		foreach (var function in program.functions) {
			if (function.name == "discard<DeferredOwner>") {
				discard = function;
			}
		}
		assert (discard != null);
		var parameter = discard.signature.parameters[0];
		var saved = parameter.object_origin;
		assert (saved != null && !saved.heap);
		parameter.object_origin = new NativeObjectOriginPlan (saved.class_ordinal, saved.class_name, true);
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			refused = error.message.contains ("parameter owner provenance");
		}
		assert (refused);
		parameter.object_origin = saved;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void nested_receiver_core() {
	try {
		CheckedProgram? predecessor = check ("nested-field-observation");
		var prior = WeakRef (predecessor.classes[0]);
		var initial = CoreBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		var program = CoreGenericMonomorphizer.build (initial);
		CoreFunction? exercise = null;
		CoreFunction? consumer = null;
		foreach (var function in program.functions) {
			if (function.name == "exercise") {
				exercise = function;
			}
			if (function.name == "consume_projection") {
				consumer = function;
			}
		}
		assert (exercise != null && consumer != null);
		CoreOwnedLocal? root = null;
		foreach (var owner in exercise.owned_locals) {
			if (owner.place.name == "outer") {
				root = owner;
			}
		}
		CoreCallValue? observed = null;
		foreach (var statement in exercise.body.statements) {
			var conditional = statement as CoreIf;
			var comparison = conditional == null ? null : conditional.condition as CoreBinaryValue;
			var call = comparison == null ? null : comparison.left as CoreCallValue;
			if (call != null && call.target.name == "inspect") {
				observed = call;
			}
		}
		assert (root != null && observed != null);
		var saved = observed.arguments[0];
		var arguments = new GenericArray<CoreValue> ();
		arguments.add (new CoreOwnedArgumentValue (saved.span, consumer.parameters[0], root.cleanup, root));
		observed.arguments[0] = new CoreCallValue (saved.span, consumer.return_type, consumer, arguments);
		bool refused = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			refused = error.message.contains ("borrow overlaps");
		}
		assert (refused);
		observed.arguments[0] = saved;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void nested_receiver_cfg() {
	try {
		CoreProgram? predecessor = core ("nested-field-observation");
		var prior = WeakRef (predecessor.classes[0]);
		var program = CfgBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CfgFunction? probe = null;
		foreach (var function in program.functions) {
			if (function.name == "projected_probe") {
				probe = function;
			}
		}
		assert (probe != null);
		CfgBlock? block = null;
		int call_index = -1;
		int cleanup_index = -1;
		foreach (var candidate in probe.blocks) {
			for (int i = 0; i < candidate.instructions.length; i++) {
				var call = candidate.instructions[i] as CfgCallInstruction;
				if (call != null && call.target.name == "inspect") {
					block = candidate;
					call_index = i;
				}
			}
		}
		assert (block != null);
		for (int i = call_index + 1; i < block.instructions.length; i++) {
			if (block.instructions[i] is CfgCleanupInstruction) {
				cleanup_index = i;
				break;
			}
		}
		assert (cleanup_index > call_index);
		var saved = block.instructions[cleanup_index];
		block.instructions.remove_index (cleanup_index);
		block.instructions.insert (call_index, saved);
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("loan overlaps");
		}
		if (!refused) {
			Test.message ("CFG accepted ancestor destruction after capturing the child receiver and before its call");
			Test.fail ();
		}
		block.instructions.remove_index (call_index);
		block.instructions.insert (cleanup_index, saved);
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void nested_receiver_ssa() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("nested-field-observation"));
		var prior = WeakRef (predecessor.classes[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaFunction? probe = null;
		foreach (var function in program.functions) {
			if (function.name == "projected_probe") {
				probe = function;
			}
		}
		assert (probe != null);
		SsaBlock? block = null;
		int call_index = -1;
		int cleanup_index = -1;
		foreach (var candidate in probe.blocks) {
			for (int i = 0; i < candidate.instructions.length; i++) {
				var call = candidate.instructions[i] as SsaCallInstruction;
				if (call != null && call.target.name == "inspect") {
					block = candidate;
					call_index = i;
				}
			}
		}
		assert (block != null);
		for (int i = call_index + 1; i < block.instructions.length; i++) {
			if (block.instructions[i] is SsaCleanupInstruction) {
				cleanup_index = i;
				break;
			}
		}
		assert (cleanup_index > call_index);
		var saved = block.instructions[cleanup_index];
		block.instructions.remove_index (cleanup_index);
		block.instructions.insert (call_index, saved);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("loan overlaps") || error.message.contains ("required cleanup lost its exact original disposal position");
		}
		if (!refused) {
			Test.message ("SSA accepted ancestor destruction after capturing the child receiver and before its call");
			Test.fail ();
		}
		block.instructions.remove_index (call_index);
		block.instructions.insert (cleanup_index, saved);
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void exact_bound_native() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("constrained-declarations")));
		var prior = WeakRef (predecessor.classes[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		NativeClassPlan? owner = null;
		foreach (var candidate in program.classes) {
			if (candidate.name == "EmptyWitness<FirstValue>") {
				owner = candidate;
			}
		}
		assert (owner != null);
		var original = owner.generic_instance;
		assert (original.definition.structure.constraint_count == 1 && original.definition.structure.constraint (0).exact_heap_class);
		assert (original.declared_structure.field_count == 0);
		NativeDeclaredMember[] members = {};
		for (int m = 0; m < original.declared_structure.member_count; m++) {
			members += original.declared_structure.member (m);
		}
		var forged = new NativeDeclaredClass (original.definition,
			new NativeDeclaredType[] { new NativeDeclaredType ("bool", new NativeScalarAbiType (NativeScalarType.B1)) }, {}, members);
		var targets = new int[original.member_count];
		for (int m = 0; m < targets.length; m++) {
			targets[m] = original.member_target (m);
		}
		int[] no_targets = null;
		owner.generic_instance = new NativeExactClassInstance.declared (original.definition, forged, targets, no_targets);
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("Class substituted capability constraint");
		}
		assert (refused);
		owner.generic_instance = original;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void multiple_slots_core() {
	try {
		var program = core ("multiple-slot-fields");
		CoreClass? owner = null;
		CoreClass? other = null;
		foreach (var candidate in program.classes) {
			if (candidate.name == "Buckets<SlotChild,bool>") {
				owner = candidate;
			}
			if (candidate.name == "Buckets<SlotHolder,bool>") {
				other = candidate;
			}
		}
		assert (owner != null && other != null && owner.fields[0].semantic_type is OwnerSlotsType && owner.fields[1].semantic_type is OwnerSlotsType);
		var saved = owner.fields[1].slots_cleanup;
		owner.fields[1].slots_cleanup = other.fields[1].slots_cleanup;
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		owner.fields[1].slots_cleanup = saved;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void multiple_slots_cfg() {
	try {
		CoreProgram? predecessor = core ("multiple-slot-fields");
		var prior = WeakRef (predecessor.classes[0]);
		var program = CfgBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CfgClass? owner = null;
		foreach (var candidate in program.classes) {
			if (candidate.name == "Buckets<SlotChild,bool>") {
				owner = candidate;
			}
		}
		assert (owner != null);
		CfgBlock? block = null;
		int index = -1;
		int drops = 0;
		foreach (var candidate in owner.destructor.blocks) {
			for (int i = 0; i < candidate.instructions.length; i++) {
				var drop = candidate.instructions[i] as CfgSlotsDrop;
				if (drop == null) {
					continue;
				}
				drops++;
				if (drop.store.field.ordinal == 1) {
					block = candidate;
					index = i;
				}
			}
		}
		assert (block != null && index >= 0 && drops == 2);
		var saved = block.instructions[index];
		block.instructions.remove_index (index);
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("slot cleanup");
		}
		assert (refused);
		block.instructions.insert (index, saved);
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void multiple_slots_ssa() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("multiple-slot-fields"));
		var prior = WeakRef (predecessor.classes[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaClass? owner = null;
		foreach (var candidate in program.classes) {
			if (candidate.name == "Buckets<SlotChild,bool>") {
				owner = candidate;
			}
		}
		assert (owner != null);
		SsaBlock? block = null;
		int index = -1;
		int drops = 0;
		foreach (var candidate in owner.destructor.blocks) {
			for (int i = 0; i < candidate.instructions.length; i++) {
				var drop = candidate.instructions[i] as SsaSlotsEffect;
				if (drop == null || drop.action != SsaSlotsAction.DROP) {
					continue;
				}
				drops++;
				if (drop.store.field.ordinal == 1) {
					block = candidate;
					index = i;
				}
			}
		}
		assert (block != null && index >= 0 && drops == 2);
		var saved = block.instructions[index];
		block.instructions.remove_index (index);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("slot");
		}
		assert (refused);
		block.instructions.insert (index, saved);
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void closed_environment_native() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("closed-closure-environment")));
		var prior = WeakRef (predecessor.classes[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		int chosen = -1;
		NativeClosurePlan? other = null;
		for (int i = 0; i < program.closures.length; i++) {
			var candidate = program.closures[i];
			if (!candidate.binding) {
				continue;
			}
			if (candidate.handle.checked_error != null) {
				chosen = i;
			} else {
				other = candidate;
			}
		}
		assert (chosen >= 0 && other != null);
		var saved = program.closures[chosen];
		assert (saved.destructor >= 0 && other.destructor >= 0 && saved.destructor != other.destructor);
		program.closures[chosen] = new NativeClosurePlan (saved.caller, saved.block, saved.instruction,
			true, saved.handle, saved.target, other.destructor);
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("environment destruction channel");
		}
		assert (refused);
		program.closures[chosen] = saved;
		NativeAbiVerifier.verify (program);
		program.closures[chosen] = new NativeClosurePlan (saved.caller, saved.block, saved.instruction,
			true, saved.handle, other.target, saved.destructor);
		refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("bound code requires exact borrowed environment");
		}
		assert (refused);
		program.closures[chosen] = saved;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void closed_dispatch_native() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("closed-generic-dispatch")));
		var prior = WeakRef (predecessor.classes[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		NativeClassPlan? chosen = null;
		NativeClassPlan? other = null;
		foreach (var candidate in program.classes) {
			if (candidate.name == "Scorer<int,bool>") {
				chosen = candidate;
			}
			if (candidate.name == "Scorer<ScoreNote,int>") {
				other = candidate;
			}
		}
		assert (chosen != null && other != null && chosen.generic_instance != null && other.generic_instance != null);
		assert (chosen.virtual_targets.length == 1 && other.virtual_targets.length == 1);
		int saved = chosen.virtual_targets[0];
		chosen.virtual_targets[0] = other.virtual_targets[0];
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		chosen.virtual_targets[0] = saved;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void async_capture_core() {
	try {
		var program = core ("owned-generic-async");
		CoreFunction? body = null;
		foreach (var function in program.functions) {
			if (function.async_body != null) {
				body = function;
			}
		}
		assert (body != null && body.parameters[0].heap_object);
		body.parameters[0].heap_object = false;
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		body.parameters[0].heap_object = true;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void async_capture_cfg() {
	try {
		CoreProgram? predecessor = core ("owned-generic-async");
		var prior = WeakRef (predecessor.classes[0]);
		var program = CfgBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CfgFunction? body = null;
		foreach (var function in program.functions) {
			if (function.async_body != null) {
				body = function;
			}
		}
		assert (body != null && body.parameters[0].heap_object);
		body.parameters[0].heap_object = false;
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		body.parameters[0].heap_object = true;
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void async_capture_ssa() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("owned-generic-async"));
		var prior = WeakRef (predecessor.classes[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaFunction? body = null;
		foreach (var function in program.functions) {
			if (function.async_body != null) {
				body = function;
			}
		}
		assert (body != null && body.parameters[0].heap_object);
		body.parameters[0].heap_object = false;
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		body.parameters[0].heap_object = true;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private NativeAsyncFramePlan frame_with_owners(NativeAsyncFramePlan original, GenericArray<NativeAsyncOwner> owners) {
	var fields = new GenericArray<NativeAsyncField> ();
	for (uint i = 0; i < original.field_count; i++) {
		fields.add (original.field (i));
	}
	var states = new GenericArray<NativeAsyncState> ();
	for (uint i = 0; i < original.state_count; i++) {
		states.add (original.state (i));
	}
	var buffers = new GenericArray<NativeAsyncBuffer> ();
	for (uint i = 0; i < original.buffer_count; i++) {
		buffers.add (original.buffer (i));
	}
	var storage = new GenericArray<NativeAsyncStorage> ();
	for (uint i = 0; i < original.storage_count; i++) {
		storage.add (original.storage_slot (i));
	}
	var enums = new GenericArray<NativeAsyncEnumStorage> ();
	for (uint i = 0; i < original.enum_count; i++) {
		enums.add (original.enum_slot (i));
	}
	var loans = new GenericArray<NativeAsyncLoan> ();
	for (uint i = 0; i < original.loan_count; i++) {
		loans.add (original.loan (i));
	}
	var waits = new GenericArray<NativeAsyncWait> ();
	for (uint i = 0; i < original.wait_count; i++) {
		waits.add (original.wait (i));
	}
	return new NativeAsyncFramePlan (original.function_ordinal, original.declaration, original.result,
		fields, states, original.object_count, original.owner_count, buffers, owners, storage,
		enums, original.record_result, loans, waits, original.provider);
}

private void async_capture_native() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("owned-generic-async")));
		var prior = WeakRef (predecessor.classes[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null && program.async_frames.length == 1);
		var saved = program.async_frames[0];
		var owners = new GenericArray<NativeAsyncOwner> ();
		int wrong_class = -1;
		foreach (var owner in program.classes) {
			if (owner.exception_root) {
				wrong_class = owner.ordinal;
			}
		}
		assert (wrong_class >= 0);
		bool mutated = false;
		for (uint i = 0; i < saved.owner_count; i++) {
			var owner = saved.owner (i);
			if (owner.capture_first_leaf >= 0 && owner.class_ordinal >= 0) {
				assert (!mutated && owner.class_ordinal != wrong_class && program.classes[owner.class_ordinal].generic_instance != null);
				owners.add (new NativeAsyncOwner (owner.ordinal, owner.source_ordinal, wrong_class,
					owner.catch_owner, owner.cleanup_symbol, owner.capture_first_leaf, owner.cleanup_position));
				mutated = true;
			} else {
				owners.add (owner);
			}
		}
		assert (mutated);
		program.async_frames[0] = frame_with_owners (saved, owners);
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		if (!refused) {
			Test.message ("native frame accepted a captured generic input with a different Class destruction identity after SSA destruction");
			Test.fail ();
		}
		program.async_frames[0] = saved;
		NativeAbiVerifier.verify (program);
		var relabeled = new GenericArray<NativeAsyncOwner> ();
		for (uint i = 0; i < saved.owner_count; i++) {
			var owner = saved.owner (i);
			if (owner.capture_first_leaf >= 0 && owner.class_ordinal >= 0) {
				relabeled.add (new NativeAsyncOwner (owner.ordinal, owner.source_ordinal, -1,
					owner.catch_owner, "wrong_resource_cleanup", owner.capture_first_leaf, owner.cleanup_position));
			} else {
				relabeled.add (owner);
			}
		}
		program.async_frames[0] = frame_with_owners (saved, relabeled);
		refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("Class cleanup differs");
		}
		assert (refused);
		program.async_frames[0] = saved;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_boundary_origins() {
	try {
		const string text = "class Surface<T>{owned T value;init(owned T value){this.value=move value;}}owned Surface<int> forward(owned Surface<int> value){return move value;}owned Surface<int> lexical(){return Surface<int>.init(42);}int main(){return 0;}";
		for (int scenario = 0; scenario < 3; scenario++) {
			var parsed = Parser.parse (new SourceFile.from_text ("native-boundary-origins.astra", text));
			assert (parsed.diagnostic == null);
			var units = new GenericArray<CompilationUnitSyntax> ();
			units.add (parsed.unit);
			var boundaries = new GenericArray<FunctionDeclarationSyntax> ();
			// The same spelling and token offsets in another source cannot bind
			// this declaration. A selected lexical producer must still fail.
			var other = Parser.parse (new SourceFile.from_text ("other-boundary.astra", text));
			assert (other.diagnostic == null);
			var selected = scenario == 2 ? other.unit : parsed.unit;
			foreach (var declaration in selected.functions) {
				if (declaration.name.spelling () == (scenario == 1 ? "lexical" : "forward")) {
					boundaries.add (declaration);
				}
			}
			assert (boundaries.length == 1);
			var checked = SemanticAnalyzer.analyze_program (new SyntaxProgram (units), null, null, null, boundaries);
			if (scenario == 1) {
				assert (checked.diagnostic != null && checked.diagnostic.message.contains ("incompatible heap and caller-backed"));
				continue;
			}
			if (checked.diagnostic != null) {
				GLib.error ("%s", checked.diagnostic.format ());
			}
			var program = NativeAbiBuilder.build (SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (checked.program)))));
			bool found_forward = false;
			bool found_lexical = false;
			foreach (var function in program.functions) {
				if (function.name == "forward") {
					found_forward = true;
					assert (function.signature.generic_owner_result_heap == (scenario == 0));
					assert (function.signature.parameters[0].generic_owner_heap == (scenario == 0));
				}
				if (function.name == "lexical") {
					found_lexical = true;
					assert (!function.signature.generic_owner_result_heap && function.signature.object_result != null);
				}
			}
			assert (found_forward && found_lexical);
			NativeAbiVerifier.verify (program);
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void closed_class_storage() {
	try {
		CheckedProgram? predecessor = check ("closed-class-owner-transport");
		var prior = WeakRef (predecessor.classes[0]);
		var program = CoreGenericMonomorphizer.build (CoreBuilder.build (predecessor));
		predecessor = null;
		assert (prior.get () == null);
		CoreFunction? heap = null;
		CoreFunction? lexical = null;
		foreach (var function in program.functions) {
			if (function.generic_instance == null || function.generic_instance.origin.name != "retire_transport") {
				continue;
			}
			if (function.parameters[0].heap_object) {
				heap = function;
			} else {
				lexical = function;
			}
		}
		assert (heap != null && lexical != null);
		foreach (var function in program.functions) {
			if (function.generic_instance != null && function.generic_instance.origin == lexical.generic_instance.origin && function.parameters[0].semantic_type == lexical.parameters[0].semantic_type && function.parameters[0].heap_object) {
				heap = function;
			}
		}
		assert (heap != lexical && heap.parameters[0].semantic_type == lexical.parameters[0].semantic_type);
		assert (heap.generic_instance.heap_owned_parameter == 0 && lexical.generic_instance.heap_owned_parameter == -1);
		var saved = heap.parameters[0].heap_object;
		heap.parameters[0].heap_object = false;
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		heap.parameters[0].heap_object = saved;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void closed_class_nominal_calls() {
	try {
		const string source = "class Cell<T>{init(){}}void observe<T>(borrowed T value) where T:Ownable{}int main(){var first=new Cell<int>();var second=new Cell<bool>();observe(first);observe(second);return 0;}";
		var parsed = Parser.parse (new SourceFile.from_text ("closed-class-loans.astra", source));
		assert (parsed.diagnostic == null);
		var checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.diagnostic == null);
		CfgProgram? predecessor = CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (checked.program)));
		var prior = WeakRef (predecessor.classes[0]);
		SsaProgram? ssa = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		var native = NativeAbiBuilder.build (ssa);
		{
			var correspondence = new HashTable<SsaFunction, NativeFunction> (direct_hash, direct_equal);
			for (int i = 0; i < ssa.functions.length; i++) {
				correspondence.insert (ssa.functions[i], native.functions[i]);
			}
			SsaCallInstruction? first = null;
			SsaCallInstruction? second = null;
			foreach (var function in ssa.functions) {
				foreach (var block in function.blocks) {
					foreach (var instruction in block.instructions) {
						var call = instruction as SsaCallInstruction;
						if (call == null || !call.target.name.has_prefix ("astra.gen.0.")) {
							continue;
						}
						if (first == null) {
							first = call;
						} else {
							second = call;
						}
					}
				}
			}
			assert (first != null && second != null && first.arguments[0].semantic_type != second.arguments[0].semantic_type);
			var saved = first.arguments[0];
			first.arguments[0] = second.arguments[0];
			bool refused = false;
			try {
				SsaVerifier.verify (ssa);
			} catch (SsaError error) {
				refused = true;
			}
			assert (refused);
			refused = false;
			try {
				NativeAbiValidator.validate_ssa_calls (ssa, native, correspondence);
			} catch (NativeAbiError error) {
				Test.message ("%s", error.message);
				refused = true;
			}
			assert (refused);
			first.arguments[0] = saved;
			SsaVerifier.verify (ssa);
			NativeAbiValidator.validate_ssa_calls (ssa, native, correspondence);
			correspondence.remove_all ();
			first = null;
			second = null;
		}
		prior = WeakRef (ssa.classes[0]);
		ssa = null;
		assert (prior.get () == null);
		NativeAbiVerifier.verify (native);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void open_record_contracts() {
	try {
		CheckedProgram? predecessor = check ("open-record-formals");
		var prior = WeakRef (predecessor.generic_functions[0]);
		var program = CoreBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CoreGenericFunction? target = null;
		CoreGenericFunction? other = null;
		foreach (var function in program.generic_functions) {
			if (function.name == "relay_payload") {
				target = function;
			}
			if (function.name == "forward_payload") {
				other = function;
			}
		}
		assert (target != null && other != null && target.return_type != other.return_type);
		var result = target.struct_result_contract;
		var formal = target.parameters[0];
		var formal_type = formal.semantic_type;
		var contract = formal.struct_value_contract;
		for (int variant = 0; variant < 4; variant++) {
			if (variant == 0) {
				target.struct_result_contract = null;
			}
			if (variant == 1) {
				target.struct_result_contract = new StructValueContract (target.return_type, StructValueMode.MOVE_VALUE);
			}
			if (variant == 2) {
				target.struct_result_contract = new StructValueContract (other.return_type);
			}
			if (variant == 3) {
				// Matching display names cannot import another function's T premise.
				formal.semantic_type = other.parameters[0].semantic_type;
				formal.struct_value_contract = new StructValueContract (formal.semantic_type);
			}
			bool refused = false;
			try {
				CoreVerifier.verify (program);
			} catch (CoreError error) {
				Test.message ("variant %d: %s", variant, error.message);
				refused = true;
			}
			assert (refused);
			target.struct_result_contract = result;
			formal.semantic_type = formal_type;
			formal.struct_value_contract = contract;
			CoreVerifier.verify (program);
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void open_record_lifetimes() {
	try {
		CoreProgram? parameterized = CoreBuilder.build (check ("open-record-formals"));
		var definition = WeakRef (parameterized.generic_functions[0]);
		var formal = WeakRef (parameterized.generic_functions[0].parameters[0].semantic_type);
		CoreProgram? concrete = CoreGenericMonomorphizer.build (parameterized);
		parameterized = null;
		assert (definition.get () == null && formal.get () == null);
		CoreVerifier.verify_concrete (concrete);
		var graph = WeakRef (concrete);
		CfgProgram? cfg = CfgBuilder.build (concrete);
		concrete = null;
		assert (graph.get () == null);
		CfgVerifier.verify (cfg);
		assert (CfgFlowChecker.check (cfg).diagnostic == null);
		graph = WeakRef (cfg);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (graph.get () == null);
		SsaVerifier.verify (ssa);
		foreach (var function in ssa.functions) {
			assert (!function.return_type.is_parameterized ());
			assert (function.return_type.is_struct_storage () == (function.struct_result != null));
			foreach (var parameter in function.parameters) {
				assert (!parameter.semantic_type.is_struct_storage () && !parameter.semantic_type.is_parameterized ());
			}
		}
		graph = WeakRef (ssa);
		var native = NativeAbiBuilder.build (ssa);
		ssa = null;
		assert (graph.get () == null);
		NativeAbiVerifier.verify (native);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void record_projection_core() {
	try {
		CheckedProgram? predecessor = check ("record-projections");
		var prior = WeakRef (predecessor.structs[0]);
		var program = CoreGenericMonomorphizer.build (CoreBuilder.build (predecessor));
		predecessor = null;
		assert (prior.get () == null);
		CoreFunction? target = null;
		foreach (var f in program.functions) {
			if (f.name == "copy_part") {
				target = f;
			}
		}
		assert (target != null && target.body.statements.length == 1);
		var saved = target.body.statements[0];
		var returned = saved as CoreStructReturn;
		var projection = returned == null ? null : returned.producer as CoreStructProjectionProducer;
		assert (projection != null);
		var wrong = new CoreStructProjectionProducer (projection.span, projection.source,
			new StructLeafPath (new int[] { 999 }, projection.semantic_type));
		target.body.statements[0] = new CoreStructReturn (saved.span, wrong);
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("projection");
		}
		assert (refused);
		target.body.statements[0] = saved;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void record_projection_cfg() {
	try {
		CoreProgram? predecessor = core ("record-projections");
		var prior = WeakRef (predecessor.structs[0]);
		var program = CfgBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CfgBlock? selected = null;
		int position = -1;
		foreach (var f in program.functions) {
			if (f.name != "copy_part") {
				continue;
			}
			foreach (var block in f.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var consume = block.instructions[i] as CfgStructResultConsume;
					var local = consume == null ? null : consume.destination as CfgLocalPlace;
					if (local != null && local.name == "$record-projection") {
						selected = block;
						position = i + (int) consume.results.shape.leaves.length;
					}
				}
			}
		}
		assert (selected != null && position >= 0 && selected.instructions[position] is CfgInitialize);
		var saved = selected.instructions[position];
		selected.instructions.remove_index (position);
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("complete exact ordered leaf");
		}
		assert (refused);
		selected.instructions.insert (position, saved);
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void record_projection_ssa() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("record-projections"));
		var prior = WeakRef (predecessor.structs[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaBlock? selected = null;
		int position = -1;
		foreach (var f in program.functions) {
			if (f.name != "copy_part") {
				continue;
			}
			foreach (var block in f.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					if (block.instructions[i] is SsaStructResultConsume) {
						selected = block;
						position = i;
					}
				}
			}
		}
		assert (selected != null && position >= 0);
		var saved = selected.instructions[position];
		selected.instructions.remove_index (position);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("no bounded complete consumer");
		}
		assert (refused);
		selected.instructions.insert (position, saved);
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void record_projection_native() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("record-projections")));
		var prior = WeakRef (predecessor.structs[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		NativeSignature? selected = null;
		foreach (var f in program.functions) {
			if (f.kind == NativeCallableKind.PROPERTY_GETTER && f.signature.struct_result != null && f.signature.struct_result.struct_name == "ProjectionStats") {
				selected = f.signature;
			}
		}
		NativeStructValuePlan? other = null;
		foreach (var plan in program.struct_values) {
			if (plan.struct_name == "OtherProjectionStats") {
				other = plan;
			}
		}
		assert (selected != null && other != null && selected.struct_result.leaf_count == other.leaf_count);
		var saved = selected.struct_result;
		selected.struct_result = other;
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		selected.struct_result = saved;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void lexical_origin_core() {
	try {
		CheckedProgram? predecessor = check ("lexical-construction");
		var prior = WeakRef (predecessor.classes[0]);
		var program = CoreGenericMonomorphizer.build (CoreBuilder.build (predecessor));
		predecessor = null;
		assert (prior.get () == null);
		CoreFunction? target = null;
		foreach (var f in program.functions) {
			if (f.name == "consume_number") {
				target = f;
			}
		}
		assert (target != null && !target.parameters[0].heap_object);
		target.parameters[0].heap_object = true;
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		target.parameters[0].heap_object = false;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void lexical_origin_cfg() {
	try {
		CoreProgram? predecessor = core ("lexical-construction");
		var prior = WeakRef (predecessor.classes[0]);
		var program = CfgBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CfgFunction? target = null;
		foreach (var f in program.functions) {
			if (f.name == "consume_number") {
				target = f;
			}
		}
		assert (target != null && !target.parameters[0].heap_object);
		target.parameters[0].heap_object = true;
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		target.parameters[0].heap_object = false;
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void lexical_origin_ssa() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("lexical-construction"));
		var prior = WeakRef (predecessor.classes[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaFunction? target = null;
		foreach (var f in program.functions) {
			if (f.name == "consume_number") {
				target = f;
			}
		}
		assert (target != null && !target.parameters[0].heap_object);
		target.parameters[0].heap_object = true;
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		target.parameters[0].heap_object = false;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void lexical_origin_native() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("lexical-construction")));
		var prior = WeakRef (predecessor.classes[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		NativeFunction? consumer = null;
		NativeFunction? producer = null;
		foreach (var f in program.functions) {
			if (f.name == "consume_number") {
				consumer = f;
			}
			if (f.name == "construct_number") {
				producer = f;
			}
		}
		assert (consumer != null && producer != null);
		var parameter = consumer.signature.parameters[0];
		var saved = parameter.object_origin;
		assert (saved != null && !saved.heap && !parameter.generic_owner_heap);
		parameter.object_origin = new NativeObjectOriginPlan (saved.class_ordinal, saved.class_name, true);
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		parameter.object_origin = saved;
		NativeAbiVerifier.verify (program);
		var original = producer.signature;
		var origin = original.object_result.object_origin;
		assert (origin != null && !origin.heap && !original.generic_owner_result_heap);
		var wrong = new NativeOwnedObjectResultPlan.typed (new NativeObjectOriginPlan (origin.class_ordinal, origin.class_name, true));
		var changed = new NativeSignature (original.abi_version, original.parameters, original.result, original.receiver, wrong);
		changed.bind_generic_owner_result (original.generic_owner_result_class, original.generic_owner_result_origin, false);
		refused = false;
		try {
			NativeAbiVerifier.verify_detached_signature (changed, "lexical result relabeled as heap");
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		NativeAbiVerifier.verify_detached_signature (original, "restored lexical result");
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void indexed_inspector_core() {
	try {
		CheckedProgram? predecessor = check ("indexed-method-inspection");
		var prior = WeakRef (predecessor.classes[0]);
		var program = CoreGenericMonomorphizer.build (CoreBuilder.build (predecessor));
		predecessor = null;
		assert (prior.get () == null);
		CoreClass? owner = null;
		foreach (var c in program.classes) {
			if (c.name == "InspectionStore") {
				owner = c;
			}
		}
		assert (owner != null);
		var inspector = owner.methods[0];
		var field = owner.fields[0];
		var store = new CoreIndirectFieldPlace (field.span, new CoreReceiverValue (field.span, inspector.receiver), field);
		var count = new CoreIntegerValue.typed (field.span, owner.fields[1].semantic_type, AstraIntegerValue.from_int64 ((IntegerType) owner.fields[1].semantic_type, 4));
		var reserve = new CoreSlotsValue (field.span, inspector.return_type, store, OwnerSlotsAction.RESERVE, count);
		inspector.body.statements.insert (0, new CoreIf (field.span, reserve, new CoreBlock (field.span, new GenericArray<CoreStatement> ()), null));
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("readonly scoped inspector");
		}
		assert (refused);
		inspector.body.statements.remove_index (0);
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void indexed_inspector_cfg() {
	try {
		CoreProgram? predecessor = core ("indexed-method-inspection");
		var prior = WeakRef (predecessor.classes[0]);
		var program = CfgBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CfgClass? owner = null;
		foreach (var c in program.classes) {
			if (c.name == "InspectionStore") {
				owner = c;
			}
		}
		assert (owner != null);
		var inspector = owner.methods[0];
		var field = owner.fields[0];
		var store = new CfgIndirectFieldPlace (field.span, new CfgReceiverValue (field.span, inspector.receiver), field);
		var count = new CfgIntegerValue.typed (field.span, owner.fields[1].semantic_type, AstraIntegerValue.from_int64 ((IntegerType) owner.fields[1].semantic_type, 4));
		var reserve = new CfgSlotsValue (field.span, inspector.return_type, store, OwnerSlotsAction.RESERVE, count);
		inspector.entry.instructions.insert (0, new CfgEvaluateInstruction (field.span, reserve, new CfgEvaluatedValue (field.span, inspector.return_type)));
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("readonly scoped inspector");
		}
		assert (refused);
		inspector.entry.instructions.remove_index (0);
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void indexed_inspector_ssa() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("indexed-method-inspection"));
		var prior = WeakRef (predecessor.classes[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaClass? owner = null;
		foreach (var c in program.classes) {
			if (c.name == "InspectionStore") {
				owner = c;
			}
		}
		assert (owner != null);
		var inspector = owner.methods[0];
		var field = owner.fields[0];
		int ordinal = 0;
		foreach (var b in inspector.blocks) {
			foreach (var p in b.parameters) {
				ordinal = int.max (ordinal, p.ordinal + 1);
			}
			foreach (var i in b.instructions) {
				if (i.result != null) {
					ordinal = int.max (ordinal, i.result.ordinal + 1);
				}
			}
		}
		var store = new SsaIndirectFieldPlace (field.span, inspector.implicit_receiver, field);
		var count = new SsaIntegerConstant.typed (field.span, owner.fields[1].semantic_type, AstraIntegerValue.from_int64 ((IntegerType) owner.fields[1].semantic_type, 4));
		inspector.entry.instructions.insert (0, new SsaSlotsValueInstruction (field.span, inspector.return_type, ordinal, store, OwnerSlotsAction.RESERVE, count));
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("readonly scoped inspector");
		}
		assert (refused);
		inspector.entry.instructions.remove_index (0);
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void generic_callable_field_core() {
	try {
		var program = core ("generic-comparator-field");
		assert (program.classes.length == 2);
		var saved = program.classes[0].fields[0].semantic_type;
		program.classes[0].fields[0].semantic_type = program.classes[1].fields[0].semantic_type;
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			refused = true;
		}
		assert (refused);
		program.classes[0].fields[0].semantic_type = saved;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void generic_callable_field_native() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("generic-comparator-field")));
		var prior = WeakRef (predecessor.classes[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		assert (program.classes.length == 2);
		var saved = program.classes[0].fields[0];
		var other = program.classes[1].fields[0];
		assert (!saved.storage_type.same_type (other.storage_type));
		program.classes[0].fields[0] = new NativeClassField (saved.span, saved.name, saved.type_name,
			saved.ordinal, saved.text_snapshot, other.storage_type, saved.record_ordinal, saved.is_private);
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		program.classes[0].fields[0] = saved;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void record_callable_core() {
	try {
		CheckedProgram? predecessor = check ("copied-record-comparator");
		var prior = WeakRef (predecessor.structs[0]);
		var program = CoreGenericMonomorphizer.build (CoreBuilder.build (predecessor));
		predecessor = null;
		assert (prior.get () == null);
		FunctionValueType? signature = null;
		foreach (var f in program.functions) {
			if (f.name == "use_comparator") {
				signature = (FunctionValueType) f.parameters[0].semantic_type;
			}
		}
		assert (signature != null && signature.record_parameters.length == 2);
		var saved = signature.record_parameters[1];
		signature.record_parameters[1] = new StructBoundaryGroup (saved.source_ordinal, saved.first_leaf + 1, saved.shape);
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			refused = error.message.contains ("record parameter");
		}
		assert (refused);
		signature.record_parameters[1] = saved;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void record_callable_cfg() {
	try {
		CoreProgram? predecessor = core ("copied-record-comparator");
		var prior = WeakRef (predecessor.structs[0]);
		var program = CfgBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CfgFunctionValueCall? call = null;
		foreach (var f in program.functions) {
			if (f.name != "use_comparator") {
				continue;
			}
			foreach (var b in f.blocks) {
				foreach (var i in b.instructions) {
					var evaluated = i as CfgEvaluateInstruction;
					if (evaluated != null && evaluated.value is CfgFunctionValueCall) {
						call = (CfgFunctionValueCall) evaluated.value;
					}
				}
			}
		}
		assert (call != null && call.struct_arguments.length == 2);
		var saved = call.struct_arguments[0];
		call.struct_arguments[0] = new StructBoundaryGroup (saved.source_ordinal + 1, saved.first_leaf, saved.shape);
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			refused = error.message.contains ("record parameter");
		}
		assert (refused);
		call.struct_arguments[0] = saved;
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void record_callable_ssa() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("copied-record-comparator"));
		var prior = WeakRef (predecessor.structs[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaFunctionValueCall? call = null;
		foreach (var f in program.functions) {
			if (f.name != "use_comparator") {
				continue;
			}
			foreach (var b in f.blocks) {
				foreach (var i in b.instructions) {
					if (i is SsaFunctionValueCall) {
						call = (SsaFunctionValueCall) i;
					}
				}
			}
		}
		assert (call != null && call.struct_arguments.length == 2);
		var saved = call.struct_arguments[0];
		call.struct_arguments.remove_index (0);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			refused = error.message.contains ("record parameter");
		}
		assert (refused);
		call.struct_arguments.insert (0, saved);
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void record_callable_native() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("copied-record-comparator")));
		var prior = WeakRef (predecessor.structs[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		assert (program.function_values.length > 0);
		var call = program.function_values[0];
		var saved = call.record_arguments[0];
		call.record_arguments[0] = new NativeCallableRecordParameter (saved.source_ordinal, saved.first_leaf, "SameLayout", saved.leaves);
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			refused = error.message.contains ("nominal identity");
		}
		assert (refused);
		call.record_arguments[0] = saved;
		NativeAbiVerifier.verify (program);
		var signature = call.signature.record_parameters[0];
		var leaf = signature.leaves[0];
		signature.leaves[0] = new NativeStructLeafChannel (leaf.field_path, new NativeScalarAbiType (NativeScalarType.I32));
		refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			refused = true;
		}
		assert (refused);
		signature.leaves[0] = leaf;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void record_observation_core() {
	try {
		var program = core ("owning-record-view");
		CorePropertyGetter? getter = null;
		foreach (var function in program.functions) {
			if (function is CorePropertyGetter && function.struct_result_contract != null && function.struct_result_contract.mode == StructValueMode.BORROW_VALUE) {
				getter = (CorePropertyGetter) function;
			}
		}
		assert (getter != null && getter.body.statements.length == 1);
		var saved = getter.body.statements[0];
		var returned = saved as CoreStructReturn;
		var borrowed = returned == null ? null : returned.producer as CoreStructBorrowSnapshot;
		assert (borrowed != null);
		getter.body.statements[0] = new CoreStructReturn (saved.span, new CoreStructSnapshot (saved.span, borrowed.source));
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			refused = true;
		}
		assert (refused);
		getter.body.statements[0] = saved;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void record_observation_cfg() {
	try {
		var program = CfgBuilder.build (core ("owning-record-view"));
		CfgPropertyGetter? getter = null;
		foreach (var function in program.functions) {
			if (function is CfgPropertyGetter && function.struct_result != null && function.struct_result.mode == StructValueMode.BORROW_VALUE) {
				getter = (CfgPropertyGetter) function;
			}
		}
		assert (getter != null);
		var returned = (CfgStructReturn) getter.entry.terminator;
		assert (returned.leaves.length >= 2 && returned.leaves[0].semantic_type == returned.leaves[1].semantic_type);
		var first = returned.leaves[0];
		returned.leaves[0] = returned.leaves[1];
		returned.leaves[1] = first;
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			refused = error.message.contains ("borrowed record getter");
		}
		assert (refused);
		returned.leaves[1] = returned.leaves[0];
		returned.leaves[0] = first;
		CfgVerifier.verify (program);
		CfgCallInstruction? call = null;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var candidate = instruction as CfgCallInstruction;
					if (candidate != null && candidate.target == getter) {
						call = candidate;
					}
				}
			}
		}
		assert (call != null);
		var original = call.struct_result;
		call.struct_result = new CfgStructCallResults (call.span, new StructValueShape (original.shape.semantic_type, original.shape.leaves, StructValueMode.MOVE_VALUE));
		refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			refused = error.message.contains ("declared copy, move or bounded borrow");
		}
		assert (refused);
		call.struct_result = original;
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void record_observation_ssa() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("owning-record-view"));
		var prior = WeakRef (predecessor.classes[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaPropertyGetter? getter = null;
		foreach (var function in program.functions) {
			if (function is SsaPropertyGetter && function.struct_result != null && function.struct_result.mode == StructValueMode.BORROW_VALUE) {
				getter = (SsaPropertyGetter) function;
			}
		}
		assert (getter != null);
		var returned = (SsaStructReturn) getter.entry.terminator;
		var first = returned.leaves[0];
		returned.leaves[0] = returned.leaves[1];
		returned.leaves[1] = first;
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			refused = error.message.contains ("borrowed record getter");
		}
		assert (refused);
		returned.leaves[1] = returned.leaves[0];
		returned.leaves[0] = first;
		SsaVerifier.verify (program);
		SsaCallInstruction? call = null;
		SsaBlock? captured_block = null;
		int marker = -1;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var candidate = instruction as SsaCallInstruction;
					if (candidate != null && candidate.target == getter) {
						call = candidate;
						captured_block = block;
					}
				}
			}
		}
		assert (call != null);
		var original = call.struct_result;
		for (int i = 0; i < captured_block.instructions.length; i++) {
			var consumption = captured_block.instructions[i] as SsaStructResultConsume;
			if (consumption != null && consumption.results == original) {
				marker = i;
			}
		}
		assert (marker >= 0);
		var saved_marker = captured_block.instructions[marker];
		call.struct_result = new SsaStructCallResults (call.span, new StructValueShape (original.shape.semantic_type, original.shape.leaves, StructValueMode.MOVE_VALUE), original.leaves);
		captured_block.instructions[marker] = new SsaStructResultConsume (call.span, call.struct_result, StructResultUseKind.OBSERVE);
		refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			refused = error.message.contains ("declared copy, move or bounded borrow");
		}
		assert (refused);
		call.struct_result = original;
		captured_block.instructions[marker] = saved_marker;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void record_observation_native() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("owning-record-view")));
		var prior = WeakRef (predecessor.classes[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		NativeFunction? getter = null;
		foreach (var function in program.functions) {
			if (function.record_observation != null) {
				getter = function;
			}
		}
		assert (getter != null && getter.signature.struct_result.mode == NativeStructValueMode.MOVE_VALUE && getter.signature.struct_result_mode == NativeStructValueMode.BORROW_VALUE);
		getter.signature.struct_result_mode = NativeStructValueMode.MOVE_VALUE;
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			refused = true;
		}
		assert (refused);
		getter.signature.struct_result_mode = NativeStructValueMode.BORROW_VALUE;
		NativeAbiVerifier.verify (program);
		var saved = getter.record_observation;
		getter.record_observation = new NativeRecordObservation (saved.class_ordinal, saved.field_ordinal + 1, saved.value_plan);
		refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			refused = true;
		}
		assert (refused);
		getter.record_observation = saved;
		NativeAbiVerifier.verify (program);
		getter.record_observation = null;
		refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			refused = true;
		}
		assert (refused);
		getter.record_observation = saved;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void buffer_view_core() {
	try {
		var program = core ("owning-buffer-view");
		CoreFunction? exercise = null;
		foreach (var function in program.functions) {
			if (function.name == "exercise_buffer_views") {
				exercise = function;
			}
		}
		assert (exercise != null);
		int location = -1;
		CoreIf? branch = null;
		CoreCallValue? retirement = null;
		for (int i = 0; i < exercise.body.statements.length; i++) {
			if (location < 0 && exercise.body.statements[i] is CoreIf) {
				location = i;
				branch = (CoreIf) exercise.body.statements[i];
			}
			var returned = exercise.body.statements[i] as CoreReturn;
			var difference = returned == null ? null : returned.value as CoreBinaryValue;
			if (difference != null && difference.left is CoreCallValue) {
				retirement = (CoreCallValue) difference.left;
			}
		}
		assert (location >= 0 && branch != null && retirement != null);
		var alternatives = (CoreShortCircuitValue) branch.condition;
		var comparison = (CoreBinaryValue) alternatives.right;
		var read = (CoreLoadValue) comparison.left;
		var original = (CoreSliceElementPlace) read.source;
		var invalid = new CoreSliceElementPlace (original.span, original.slice, original.slice_type, retirement, original.provenance);
		exercise.body.statements.insert (location, new CoreReturn (original.span, new CoreLoadValue (original.span, invalid)));
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("temporary field borrow overlaps");
		}
		assert (refused);
		exercise.body.statements.remove_index (location);
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void buffer_view_cfg() {
	try {
		var program = CfgBuilder.build (core ("owning-buffer-view"));
		CfgBlock? block = null;
		int position = -1;
		CfgEvaluateInstruction? captured = null;
		CfgRecordBufferView? observed = null;
		CfgRecordBufferView? other = null;
		foreach (var function in program.functions) {
			foreach (var candidate in function.blocks) {
				for (int i = 0; i < candidate.instructions.length; i++) {
					var evaluation = candidate.instructions[i] as CfgEvaluateInstruction;
					var view = evaluation == null ? null : evaluation.value as CfgRecordBufferView;
					if (view == null) {
						continue;
					}
					if (observed == null) {
						block = candidate;
						position = i;
						captured = evaluation;
						observed = view;
					} else if (view.group != observed.group) {
						other = view;
					}
				}
			}
		}
		assert (observed != null && other != null);
		block.instructions[position] = new CfgEvaluateInstruction (captured.span, new CfgRecordBufferView (captured.span, other.group, observed.source), captured.result);
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("record buffer view requires");
		}
		assert (refused);
		block.instructions[position] = captured;
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void buffer_view_ssa() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("owning-buffer-view"));
		var prior = WeakRef (predecessor.classes[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaPropertyGetter? getter = null;
		foreach (var function in program.functions) {
			if (function is SsaPropertyGetter && function.struct_result != null && function.struct_result.mode == StructValueMode.BORROW_VALUE) {
				getter = (SsaPropertyGetter) function;
			}
		}
		assert (getter != null);
		var returned = (SsaStructReturn) getter.entry.terminator;
		int first = -1;
		int second = -1;
		for (int i = 0; i < returned.shape.leaves.length; i++) {
			var component = returned.shape.leaves[i] as StructBufferLeafPath;
			if (component != null && component.component == 1) {
				if (first < 0) {
					first = i;
				} else {
					second = i;
				}
			}
		}
		assert (first >= 0 && second >= 0);
		var saved = returned.leaves[first];
		returned.leaves[first] = returned.leaves[second];
		returned.leaves[second] = saved;
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("borrowed record getter");
		}
		assert (refused);
		returned.leaves[second] = returned.leaves[first];
		returned.leaves[first] = saved;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void buffer_view_native() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("owning-buffer-view")));
		var prior = WeakRef (predecessor.classes[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		NativeStructValuePlan? plan = null;
		foreach (var function in program.functions) {
			if (function.record_observation != null) {
				plan = function.record_observation.value_plan;
			}
		}
		assert (plan != null);
		int first = -1;
		int second = -1;
		for (int i = 0; i < plan.leaves.length; i++) {
			if (plan.leaves[i].buffer_component == 1) {
				if (first < 0) {
					first = i;
				} else {
					second = i;
				}
			}
		}
		assert (first >= 0 && second >= 0);
		var saved = plan.leaves[first];
		plan.leaves[first] = plan.leaves[second];
		plan.leaves[second] = saved;
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		plan.leaves[second] = plan.leaves[first];
		plan.leaves[first] = saved;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void readonly_buffer_core() {
	try {
		var program = core ("readonly-buffer-view");
		CoreFunction? inspector = null;
		foreach (var function in program.functions) {
			if (function.name == "inspect") {
				inspector = function;
			}
		}
		assert (inspector != null);
		var returned = inspector.body.statements[0] as CoreReturn;
		var sum = returned == null ? null : returned.value as CoreBinaryValue;
		var read = sum == null ? null : sum.right as CoreLoadValue;
		assert (read != null && read.source is CoreSliceElementPlace);
		var type = (IntegerType) read.semantic_type;
		var saved = inspector.body.statements[0];
		inspector.body.statements[0] = new CoreStore (read.span, read.source, new CoreIntegerValue.typed (read.span, type, AstraIntegerValue.from_int64 (type, 99)));
		inspector.body.statements.add (new CoreReturn (read.span, new CoreIntegerValue.typed (read.span, type, AstraIntegerValue.from_int64 (type, 0))));
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("readonly scoped inspector");
		}
		assert (refused);
		inspector.body.statements.remove_index (1);
		inspector.body.statements[0] = saved;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void readonly_buffer_cfg() {
	try {
		var program = CfgBuilder.build (core ("readonly-buffer-view"));
		CfgBlock? block = null;
		CfgLoadValue? read = null;
		int position = -1;
		foreach (var function in program.functions) {
			if (function.name != "inspect") {
				continue;
			}
			foreach (var candidate in function.blocks) {
				for (int i = 0; i < candidate.instructions.length; i++) {
					var evaluation = candidate.instructions[i] as CfgEvaluateInstruction;
					var load = evaluation == null ? null : evaluation.value as CfgLoadValue;
					if (load != null && load.source is CfgSliceElementPlace) {
						block = candidate;
						position = i + 1;
						read = load;
					}
				}
			}
		}
		assert (read != null && position >= 0);
		var type = (IntegerType) read.semantic_type;
		block.instructions.insert (position, new CfgStore (read.span, read.source, new CfgIntegerValue.typed (read.span, type, AstraIntegerValue.from_int64 (type, 99))));
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("readonly scoped inspector");
		}
		assert (refused);
		block.instructions.remove_index (position);
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void readonly_buffer_ssa() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("readonly-buffer-view"));
		var prior = WeakRef (predecessor.classes[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaBlock? block = null;
		SsaLoadInstruction? read = null;
		int position = -1;
		foreach (var function in program.functions) {
			if (function.name != "inspect") {
				continue;
			}
			foreach (var candidate in function.blocks) {
				for (int i = 0; i < candidate.instructions.length; i++) {
					var load = candidate.instructions[i] as SsaLoadInstruction;
					if (load != null && load.source is SsaSliceElementPlace) {
						block = candidate;
						position = i + 1;
						read = load;
					}
				}
			}
		}
		assert (read != null && position >= 0);
		var type = (IntegerType) read.source.semantic_type;
		block.instructions.insert (position, new SsaStoreInstruction (read.span, read.source, new SsaIntegerConstant.typed (read.span, type, AstraIntegerValue.from_int64 (type, 99))));
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("readonly scoped inspector");
		}
		assert (refused);
		block.instructions.remove_index (position);
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void borrowed_record_core() {
	try {
		var program = core ("borrowed-record-parameter");
		CoreFunction? target = null;
		foreach (var function in program.functions) {
			if (function.name == "read_parameter") {
				target = function;
			}
		}
		assert (target != null);
		var parameter = target.parameters[0];
		var saved = parameter.struct_value_contract;
		parameter.struct_value_contract = new StructValueContract (parameter.semantic_type, StructValueMode.MOVE_VALUE);
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		parameter.struct_value_contract = saved;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void borrowed_record_core_overlap() {
	try {
		var program = core ("borrowed-record-parameter");
		CoreFunction? main = null;
		CoreFunction? consume = null;
		foreach (var function in program.functions) {
			if (function.name == "main") {
				main = function;
			}
			if (function.name == "consume_parameter") {
				consume = function;
			}
		}
		assert (main != null && consume != null);
		CoreOwnedLocal? root = null;
		CoreCallValue? call = null;
		foreach (var owner in main.owned_locals) {
			if (owner.place.name == "pack") {
				root = owner;
			}
		}
		foreach (var statement in main.body.statements) {
			var condition = statement as CoreIf;
			var comparison = condition == null ? null : condition.condition as CoreBinaryValue;
			var candidate = comparison == null ? null : comparison.left as CoreCallValue;
			if (candidate != null && candidate.target.name == "tagged_parameter") {
				call = candidate;
			}
		}
		assert (root != null && call != null);
		var saved = call.arguments[1];
		var arguments = new GenericArray<CoreValue> ();
		arguments.add (new CoreStructArgument (saved.span, consume.parameters[0], new CoreStructMoveProducer (saved.span, root)));
		call.arguments[1] = new CoreCallValue (saved.span, consume.return_type, consume, arguments);
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("active borrowed record argument");
		}
		assert (refused);
		call.arguments[1] = saved;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void borrowed_record_cfg() {
	try {
		CoreProgram? predecessor = core ("borrowed-record-parameter");
		var prior = WeakRef (predecessor.classes[0]);
		var program = CfgBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CfgFunction? target = null;
		CfgCallInstruction? call = null;
		foreach (var function in program.functions) {
			if (function.name == "read_parameter") {
				target = function;
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var candidate = instruction as CfgCallInstruction;
					if (candidate != null && candidate.target.name == "tagged_parameter") {
						call = candidate;
					}
				}
			}
		}
		assert (target != null && call != null);
		var binding = target.entry.instructions[0];
		assert (binding is CfgStructParameterBorrow);
		target.entry.instructions.remove_index (0);
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("entry binding");
		}
		assert (refused);
		target.entry.instructions.insert (0, binding);
		CfgVerifier.verify (program);
		var saved = call.struct_arguments[0];
		assert (saved is CfgStructBorrowArgument);
		call.struct_arguments[0] = new StructBoundaryGroup (saved.source_ordinal, saved.first_leaf, saved.shape);
		refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("record argument loan");
		}
		assert (refused);
		call.struct_arguments[0] = saved;
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void borrowed_record_ssa() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("borrowed-record-parameter"));
		var prior = WeakRef (predecessor.classes[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaFunction? target = null;
		SsaCallInstruction? call = null;
		SsaBlock? block = null;
		int position = -1;
		foreach (var function in program.functions) {
			if (function.name == "read_parameter") {
				target = function;
			}
			foreach (var candidate in function.blocks) {
				for (int i = 0; i < candidate.instructions.length; i++) {
					var invoked = candidate.instructions[i] as SsaCallInstruction;
					if (invoked != null && invoked.target.name == "tagged_parameter") {
						call = invoked;
						block = candidate;
						position = i;
					}
				}
			}
		}
		assert (target != null && call != null && position > 0);
		var binding = target.entry.instructions[0];
		assert (binding is SsaStructParameterBorrow);
		target.entry.instructions.remove_index (0);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("entry binding");
		}
		assert (refused);
		target.entry.instructions.insert (0, binding);
		SsaVerifier.verify (program);
		var read = block.instructions[position - 1];
		assert (read is SsaHeapOwnerEvent);
		block.instructions.remove_index (position - 1);
		refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("live owner READ");
		}
		assert (refused);
		block.instructions.insert (position - 1, read);
		SsaVerifier.verify (program);
		var saved = call.struct_arguments[0];
		call.struct_arguments[0] = new StructBoundaryGroup (saved.source_ordinal, saved.first_leaf, saved.shape);
		refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("record argument loan");
		}
		assert (refused);
		call.struct_arguments[0] = saved;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void borrowed_record_native() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("borrowed-record-parameter")));
		var prior = WeakRef (predecessor.classes[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		NativeSignature? signature = null;
		foreach (var function in program.functions) {
			if (function.name == "read_parameter") {
				signature = function.signature;
			}
		}
		assert (signature != null && signature.struct_parameters.length == 1);
		var saved = signature.struct_parameters[0];
		assert (saved.mode == NativeStructValueMode.BORROW_VALUE);
		signature.struct_parameters[0] = new NativeStructParameterPlan (saved.source_ordinal, saved.first_leaf, saved.value_plan, NativeStructValueMode.MOVE_VALUE);
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		signature.struct_parameters[0] = saved;
		NativeAbiVerifier.verify (program);
		var leaf = signature.parameters[saved.first_leaf];
		assert (leaf.borrowed_class_ordinal >= 0 && leaf.object_origin == null);
		leaf.object_origin = new NativeObjectOriginPlan (leaf.borrowed_class_ordinal, "ParameterChild", true);
		refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		leaf.object_origin = null;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void borrowed_record_cfg_overlap() {
	try {
		CoreProgram? predecessor = core ("borrowed-record-parameter");
		var prior = WeakRef (predecessor.classes[0]);
		var program = CfgBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CfgCallInstruction? call = null;
		CfgBlock? consumer = null;
		int position = -1;
		CfgFunction? main = null;
		foreach (var function in program.functions) {
			if (function.name != "main") {
				continue;
			}
			main = function;
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var invoked = block.instructions[i] as CfgCallInstruction;
					if (invoked != null && invoked.target.name == "tagged_parameter") {
						call = invoked;
						consumer = block;
						position = i;
					}
				}
			}
		}
		assert (main != null && call != null);
		var loan = call.struct_arguments[0] as CfgStructBorrowArgument;
		assert (loan != null);
		CfgBlock? original = null;
		CfgOwnershipTransferInstruction? move = null;
		int old_position = -1;
		foreach (var block in main.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var transfer = block.instructions[i] as CfgOwnershipTransferInstruction;
				if (transfer != null && transfer.source == loan.source) {
					original = block;
					move = transfer;
					old_position = i;
				}
			}
		}
		assert (move != null && original != consumer);
		original.instructions.remove_index (old_position);
		consumer.instructions.insert (position, move);
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("record argument loan overlaps");
		}
		assert (refused);
		consumer.instructions.remove_index (position);
		original.instructions.insert (old_position, move);
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void borrowed_buffer_ssa() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("borrowed-buffer-parameter"));
		var prior = WeakRef (predecessor.structs[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaStructParameterBorrow? binding = null;
		SsaStructBorrowArgument? loan = null;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var entry = instruction as SsaStructParameterBorrow;
					if (entry != null && entry.buffers.length == 2) {
						binding = entry;
					}
					var call = instruction as SsaCallInstruction;
					if (call == null) {
						continue;
					}
					foreach (var group in call.struct_arguments) {
						var candidate = group as SsaStructBorrowArgument;
						if (candidate != null && candidate.incoming == null && candidate.buffers.length == 2) {
							loan = candidate;
						}
					}
				}
			}
		}
		assert (binding != null && loan != null);
		var saved = binding.buffers[0];
		binding.buffers[0] = binding.buffers[1];
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("record buffer");
		}
		assert (refused);
		binding.buffers[0] = saved;
		SsaVerifier.verify (program);
		var view = loan.buffers[0];
		loan.buffers[0] = loan.buffers[1];
		refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("record argument loan changed its original buffer");
		}
		assert (refused);
		loan.buffers[0] = view;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void borrowed_buffer_native() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("borrowed-buffer-parameter")));
		var prior = WeakRef (predecessor.structs[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		NativeSignature? signature = null;
		foreach (var function in program.functions) {
			if (function.name == "observe_buffered_parameter") {
				signature = function.signature;
			}
		}
		assert (signature != null && signature.struct_parameters[0].mode == NativeStructValueMode.BORROW_VALUE);
		var leaf = signature.parameters[0];
		assert (leaf.resource != null && !leaf.owns_resource);
		signature.parameters[0] = new NativeParameter.typed (leaf.span, leaf.name_span, leaf.name, leaf.ordinal, leaf.abi_type);
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("borrowed record Resource leaf");
		}
		assert (refused);
		signature.parameters[0] = leaf;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void borrowed_getter_core_overlap() {
	try {
		var program = core ("borrowed-record-getter");
		CoreFunction? exercise = null;
		CoreFunction? consume = null;
		foreach (var function in program.functions) {
			if (function.name == "exercise_parameter_leaves") {
				exercise = function;
			}
			if (function.name == "finish_parameter_getter") {
				consume = function;
			}
		}
		assert (exercise != null && consume != null);
		CoreOwnedLocal? owner = null;
		CoreCallValue? call = null;
		foreach (var candidate in exercise.owned_locals) {
			if (candidate.place.name == "box") {
				owner = candidate;
			}
		}
		foreach (var statement in exercise.body.statements) {
			var branch = statement as CoreIf;
			var comparison = branch == null ? null : branch.condition as CoreBinaryValue;
			var invoked = comparison == null ? null : comparison.left as CoreCallValue;
			if (invoked != null && invoked.target.name == "tagged_parameter_leaves") {
				call = invoked;
			}
		}
		assert (owner != null && call != null);
		var saved = call.arguments[1];
		var type = (IntegerType) saved.semantic_type;
		var arguments = new GenericArray<CoreValue> ();
		arguments.add (new CoreIntegerValue.typed (saved.span, type, AstraIntegerValue.from_int64 (type, 0)));
		arguments.add (new CoreOwnedArgumentValue (saved.span, consume.parameters[1], owner.cleanup, owner));
		call.arguments[1] = new CoreCallValue (saved.span, consume.return_type, consume, arguments);
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("borrow overlaps");
		}
		assert (refused);
		call.arguments[1] = saved;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void borrowed_getter_cfg() {
	try {
		CoreProgram? predecessor = core ("borrowed-record-getter");
		var prior = WeakRef (predecessor.classes[0]);
		var program = CfgBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CfgCallInstruction? call = null;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var candidate = instruction as CfgCallInstruction;
					if (candidate != null && candidate.target.name == "tagged_parameter_leaves") {
						call = candidate;
					}
				}
			}
		}
		assert (call != null);
		var group = call.struct_arguments[0];
		assert (group is CfgStructBorrowResultArgument);
		int second = -1;
		for (int i = 1; i < group.shape.leaves.length; i++) {
			if (group.shape.leaves[i].semantic_type == group.shape.leaves[0].semantic_type) {
				second = i;
				break;
			}
		}
		assert (second > 0);
		var first = call.arguments[group.first_leaf];
		var other = call.arguments[group.first_leaf + second];
		call.arguments[group.first_leaf] = other;
		call.arguments[group.first_leaf + second] = first;
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("original ordered result leaf");
		}
		assert (refused);
		call.arguments[group.first_leaf] = first;
		call.arguments[group.first_leaf + second] = other;
		CfgVerifier.verify (program);
		call.struct_arguments[0] = new StructBoundaryGroup (group.source_ordinal, group.first_leaf, group.shape);
		refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("record argument loan");
		}
		assert (refused);
		call.struct_arguments[0] = group;
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void borrowed_getter_ssa() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("borrowed-record-getter"));
		var prior = WeakRef (predecessor.classes[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaCallInstruction? call = null;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var candidate = instruction as SsaCallInstruction;
					if (candidate != null && candidate.target.name == "tagged_parameter_leaves") {
						call = candidate;
					}
				}
			}
		}
		assert (call != null);
		var group = call.struct_arguments[0];
		assert (group is SsaStructBorrowResultArgument);
		int second = -1;
		for (int i = 1; i < group.shape.leaves.length; i++) {
			if (group.shape.leaves[i].semantic_type == group.shape.leaves[0].semantic_type) {
				second = i;
				break;
			}
		}
		assert (second > 0);
		var first = call.arguments[group.first_leaf];
		var other = call.arguments[group.first_leaf + second];
		call.arguments[group.first_leaf] = other;
		call.arguments[group.first_leaf + second] = first;
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("original ordered result leaf");
		}
		assert (refused);
		call.arguments[group.first_leaf] = first;
		call.arguments[group.first_leaf + second] = other;
		SsaVerifier.verify (program);
		call.struct_arguments[0] = new StructBoundaryGroup (group.source_ordinal, group.first_leaf, group.shape);
		refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("record argument loan");
		}
		assert (refused);
		call.struct_arguments[0] = group;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void parameter_buffer_path_ssa() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("readonly-record-parameter"));
		var prior = WeakRef (predecessor.classes[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaStructParameterBorrow? binding = null;
		SsaBufferBorrowInstruction? view = null;
		SsaBlock? selected = null;
		int position = -1;
		foreach (var function in program.functions) {
			if (function.name != "inspect_borrowed_payload") {
				continue;
			}
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var entry = block.instructions[i] as SsaStructParameterBorrow;
					if (entry != null) {
						binding = entry;
					}
					var candidate = block.instructions[i] as SsaBufferBorrowInstruction;
					if (view == null && candidate != null && candidate.record_parameter != null) {
						view = candidate;
						selected = block;
						position = i;
					}
				}
			}
		}
		assert (binding != null && binding.buffers.length == 2 && view != null && view.record_path != null);
		var other = binding.buffers[0] == view.pair ? binding.buffers[1] : binding.buffers[0];
		assert (other.shape == view.pair.shape);
		selected.instructions[position] = new SsaBufferBorrowInstruction.for_parameter (view.span, other, view.record_parameter, view.record_path, view.result.ordinal);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("original declared field path or pair");
		}
		assert (refused);
		selected.instructions[position] = view;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void readonly_parameter_core() {
	try {
		var program = core ("readonly-record-parameter");
		CoreFunction? helper = null;
		foreach (var function in program.functions) {
			if (function.name == "inspect_borrowed_payload") {
				helper = function;
			}
		}
		assert (helper != null && helper.body.statements.length == 2);
		var saved = helper.body.statements[1];
		var returned = saved as CoreReturn;
		var sum = returned == null ? null : returned.value as CoreBinaryValue;
		var read = sum == null ? null : sum.right as CoreLoadValue;
		assert (read != null && read.source is CoreSliceElementPlace);
		var type = (IntegerType) read.semantic_type;
		helper.body.statements[1] = new CoreStore (read.span, read.source, new CoreIntegerValue.typed (read.span, type, AstraIntegerValue.from_int64 (type, 99)));
		helper.body.statements.add (new CoreReturn (read.span, new CoreIntegerValue.typed (read.span, type, AstraIntegerValue.from_int64 (type, 0))));
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("readonly scoped inspector");
		}
		assert (refused);
		helper.body.statements.remove_index (2);
		helper.body.statements[1] = saved;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void readonly_parameter_cfg() {
	try {
		var program = CfgBuilder.build (core ("readonly-record-parameter"));
		CfgBlock? block = null;
		CfgLoadValue? read = null;
		int position = -1;
		foreach (var function in program.functions) {
			if (function.name != "inspect_borrowed_payload") {
				continue;
			}
			foreach (var candidate in function.blocks) {
				for (int i = 0; i < candidate.instructions.length; i++) {
					var evaluation = candidate.instructions[i] as CfgEvaluateInstruction;
					var load = evaluation == null ? null : evaluation.value as CfgLoadValue;
					if (load != null && load.source is CfgSliceElementPlace) {
						block = candidate;
						position = i + 1;
						read = load;
					}
				}
			}
		}
		assert (read != null && position > 0);
		var type = (IntegerType) read.semantic_type;
		block.instructions.insert (position, new CfgStore (read.span, read.source, new CfgIntegerValue.typed (read.span, type, AstraIntegerValue.from_int64 (type, 99))));
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("readonly scoped inspector");
		}
		assert (refused);
		block.instructions.remove_index (position);
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void readonly_parameter_ssa() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("readonly-record-parameter"));
		var prior = WeakRef (predecessor.classes[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaBlock? block = null;
		SsaLoadInstruction? read = null;
		int position = -1;
		foreach (var function in program.functions) {
			if (function.name != "inspect_borrowed_payload") {
				continue;
			}
			foreach (var candidate in function.blocks) {
				for (int i = 0; i < candidate.instructions.length; i++) {
					var load = candidate.instructions[i] as SsaLoadInstruction;
					if (load != null && load.source is SsaSliceElementPlace) {
						block = candidate;
						position = i + 1;
						read = load;
					}
				}
			}
		}
		assert (read != null && position > 0);
		var type = (IntegerType) read.source.semantic_type;
		block.instructions.insert (position, new SsaStoreInstruction (read.span, read.source, new SsaIntegerConstant.typed (read.span, type, AstraIntegerValue.from_int64 (type, 99))));
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("readonly scoped inspector");
		}
		assert (refused);
		block.instructions.remove_index (position);
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void callable_channel_core() {
	try {
		var program = core ("borrowed-function-channel");
		CoreFunctionValueCall? invocation = null;
		foreach (var function in program.functions) {
			if (function.name == "forward_callable_child") {
				invocation = ((CoreReturn) function.body.statements[0]).value as CoreFunctionValueCall;
			}
		}
		assert (invocation != null && invocation.channel_parameters.length == 2);
		var channel = invocation.channel_parameters[0];
		invocation.channel_parameters[0] = new CoreParameter (channel.span, channel.name_span, channel.name, channel.semantic_type, channel.ordinal);
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("channel declaration");
		}
		assert (refused);
		invocation.channel_parameters[0] = channel;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void callable_channel_cfg() {
	try {
		CoreProgram? predecessor = core ("borrowed-function-channel");
		var prior = WeakRef (predecessor.classes[0]);
		var program = CfgBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CfgFunctionValueCall? invocation = null;
		foreach (var function in program.functions) {
			if (function.name != "forward_callable_child") {
				continue;
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var evaluation = instruction as CfgEvaluateInstruction;
					var call = evaluation == null ? null : evaluation.value as CfgFunctionValueCall;
					if (call != null) {
						invocation = call;
					}
				}
			}
		}
		assert (invocation != null && invocation.channel_parameters.length == 2);
		var channel = invocation.channel_parameters[0];
		invocation.channel_parameters.remove_index (0);
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("channel declarations");
		}
		assert (refused);
		invocation.channel_parameters.insert (0, channel);
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void callable_channel_ssa_operand() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("borrowed-function-channel"));
		var prior = WeakRef (predecessor.classes[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaFunctionValueCall? invocation = null;
		SsaValue? other = null;
		foreach (var function in program.functions) {
			if (function.name != "exercise_callable_loans") {
				continue;
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var call = instruction as SsaFunctionValueCall;
					if (call == null || call.borrowed_arguments.length == 0 || call.borrowed_arguments[0].source_owner == null || !(call.arguments[0].semantic_type is ClassType)) {
						continue;
					}
					if (invocation == null) {
						invocation = call;
					} else if (call.arguments[0] != invocation.arguments[0] && call.arguments[0].semantic_type == invocation.arguments[0].semantic_type) {
						other = call.arguments[0];
					}
				}
			}
		}
		assert (invocation != null && other != null);
		var original = invocation.arguments[0];
		invocation.arguments[0] = other;
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("original physical argument");
		}
		assert (refused);
		invocation.arguments[0] = original;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void callable_channel_ssa_owner() {
	try {
		var program = SsaBuilder.build (CfgBuilder.build (core ("borrowed-function-channel")));
		SsaFunctionValueCall? invocation = null;
		SsaHeapOwner? other = null;
		SsaBlock? block = null;
		int read_position = -1;
		foreach (var function in program.functions) {
			if (function.name != "exercise_callable_loans") {
				continue;
			}
			foreach (var candidate in function.blocks) {
				foreach (var instruction in candidate.instructions) {
					var call = instruction as SsaFunctionValueCall;
					if (call == null || call.borrowed_arguments.length == 0 || call.borrowed_arguments[0].source_owner == null || !(call.arguments[0].semantic_type is ClassType)) {
						continue;
					}
					if (invocation == null) {
						invocation = call;
						block = candidate;
					} else if (call.borrowed_arguments[0].source_owner != invocation.borrowed_arguments[0].source_owner && call.arguments[0].semantic_type == invocation.arguments[0].semantic_type) {
						other = call.borrowed_arguments[0].source_owner;
					}
				}
			}
		}
		assert (invocation != null && other != null);
		for (int p = 0; p < block.instructions.length; p++) {
			var event = block.instructions[p] as SsaHeapOwnerEvent;
			if (event != null && event.effect == invocation) {
				read_position = p;
			}
		}
		assert (read_position >= 0);
		var loan = invocation.borrowed_arguments[0];
		var read = (SsaHeapOwnerEvent) block.instructions[read_position];
		invocation.borrowed_arguments[0] = new SsaCallableBorrowArgument (loan.ordinal, loan.value, other);
		block.instructions[read_position] = new SsaHeapOwnerEvent (read.span, other, SsaHeapOwnerAction.READ, loan.value, invocation);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		invocation.borrowed_arguments[0] = loan;
		block.instructions[read_position] = read;
		SsaVerifier.verify (program);
		invocation.borrowed_arguments[0] = new SsaCallableBorrowArgument (loan.ordinal, loan.value, null);
		block.instructions.remove_index (read_position);
		refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("non-acquiring origin");
		}
		assert (refused);
		invocation.borrowed_arguments[0] = loan;
		block.instructions.insert (read_position, read);
		SsaVerifier.verify (program);
		block.instructions.remove_index (read_position);
		refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("live backing owner");
		}
		assert (refused);
		block.instructions.insert (read_position, read);
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void callable_channel_native() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("borrowed-function-channel")));
		var prior = WeakRef (predecessor.classes[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		NativeFunctionValuePlan? invocation = null;
		foreach (var candidate in program.function_values) {
			if (candidate.signature.borrowed_parameters.length != 0 && candidate.signature.borrowed_parameters[0].is_class) {
				invocation = candidate;
				break;
			}
		}
		assert (invocation != null);
		var signature = invocation.signature;
		var channel = signature.borrowed_parameters[0];
		signature.borrowed_parameters.remove_index (0);
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		signature.borrowed_parameters.insert (0, channel);
		NativeAbiVerifier.verify (program);
		signature.borrowed_parameters[0] = new NativeCallableBorrowChannel (channel.ordinal, "Other", false);
		refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("borrowed argument");
		}
		assert (refused);
		signature.borrowed_parameters[0] = channel;
		NativeAbiVerifier.verify (program);

		NativeFunctionPointerType? field_signature = null;
		foreach (var owner in program.classes) {
			foreach (var field in owner.fields) {
				var candidate = field.storage_type as NativeFunctionPointerType;
				if (candidate != null && candidate.borrowed_parameters.length != 0) {
					field_signature = candidate;
				}
			}
		}
		assert (field_signature != null);
		var field_channel = field_signature.borrowed_parameters[0];
		field_signature.borrowed_parameters.remove_index (0);
		refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		field_signature.borrowed_parameters.insert (0, field_channel);
		NativeAbiVerifier.verify (program);

		assert (program.callable_resources.length != 0);
		var resource = program.callable_resources[0];
		program.callable_resources[0] = new NativeScalarOwner (resource.type_name, "wrong_cleanup");
		refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("cleanup declaration inventory");
		}
		assert (refused);
		program.callable_resources[0] = resource;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void closure_channel_core() {
	try {
		var program = core ("borrowed-closure-channel");
		CoreClosureCall? invocation = null;
		foreach (var function in program.functions) {
			if (function.name == "forward_closure_loan") {
				invocation = ((CoreReturn) function.body.statements[0]).value as CoreClosureCall;
			}
		}
		assert (invocation != null && invocation.channel_parameters.length == 3);
		var channel = invocation.channel_parameters[0];
		invocation.channel_parameters[0] = new CoreParameter (channel.span, channel.name_span, channel.name, channel.semantic_type, channel.ordinal);
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("closure channel");
		}
		assert (refused);
		invocation.channel_parameters[0] = channel;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void closure_channel_cfg() {
	try {
		CoreProgram? predecessor = core ("borrowed-closure-channel");
		var prior = WeakRef (predecessor.classes[0]);
		var program = CfgBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CfgClosureCall? invocation = null;
		foreach (var function in program.functions) {
			if (function.name != "forward_checked_closure_loan") {
				continue;
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var call = instruction as CfgCheckedClosureInvoke;
					if (call != null) {
						invocation = call.call;
					}
				}
			}
		}
		assert (invocation != null && invocation.channel_parameters.length == 4);
		var channel = invocation.channel_parameters[0];
		invocation.channel_parameters.remove_index (0);
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("channel declarations");
		}
		assert (refused);
		invocation.channel_parameters.insert (0, channel);
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void closure_channel_ssa() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("borrowed-closure-channel"));
		var prior = WeakRef (predecessor.classes[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaClosureCall? invocation = null;
		SsaBlock? block = null;
		foreach (var function in program.functions) {
			if (function.name != "exercise_closure_loans") {
				continue;
			}
			foreach (var candidate in function.blocks) {
				foreach (var instruction in candidate.instructions) {
					var call = instruction as SsaClosureCall;
					if (call != null && call.source_owner != null && call.borrowed_arguments.length == 2 && call.borrowed_arguments[0].source_owner != null) {
						invocation = call;
						block = candidate;
						break;
					}
				}
				if (invocation != null) {
					break;
				}
			}
		}
		assert (invocation != null && block != null);
		var loan = invocation.borrowed_arguments[0];
		int position = -1;
		for (int i = 0; i < block.instructions.length; i++) {
			var read = block.instructions[i] as SsaHeapOwnerEvent;
			if (read != null && read.effect == invocation && read.owner == loan.source_owner && read.value == loan.value) {
				position = i;
			}
		}
		assert (position >= 0);
		var original = (SsaHeapOwnerEvent) block.instructions[position];
		block.instructions.remove_index (position);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("live backing owner");
		}
		assert (refused);
		block.instructions.insert (position, original);
		SsaVerifier.verify (program);
		block.instructions.insert (position, new SsaHeapOwnerEvent (original.span, original.owner, SsaHeapOwnerAction.READ, original.value, invocation));
		refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("duplicates or invents");
		}
		assert (refused);
		block.instructions.remove_index (position);
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void repeated_callable_reads_ssa() {
	try {
		var program = SsaBuilder.build (CfgBuilder.build (core ("borrowed-closure-channel")));
		SsaFunctionValueCall? invocation = null;
		SsaBlock? block = null;
		foreach (var function in program.functions) {
			if (function.name != "exercise_closure_loans") {
				continue;
			}
			foreach (var candidate in function.blocks) {
				foreach (var instruction in candidate.instructions) {
					var call = instruction as SsaFunctionValueCall;
					if (call != null && call.borrowed_arguments.length == 2 && call.borrowed_arguments[0].source_owner != null && call.borrowed_arguments[0].source_owner == call.borrowed_arguments[1].source_owner && call.arguments[0] == call.arguments[1]) {
						invocation = call;
						block = candidate;
					}
				}
			}
		}
		assert (invocation != null && block != null);
		int position = -1;
		for (int i = 0; i < block.instructions.length; i++) {
			var read = block.instructions[i] as SsaHeapOwnerEvent;
			if (read != null && read.effect == invocation) {
				position = i;
				break;
			}
		}
		assert (position >= 0);
		var original = block.instructions[position];
		block.instructions.remove_index (position);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("complete original owner read group");
		}
		assert (refused);
		block.instructions.insert (position, original);
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void closure_channel_native() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("borrowed-closure-channel")));
		var prior = WeakRef (predecessor.classes[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		NativeClosurePlan? invocation = null;
		NativeClosurePlan? binding = null;
		foreach (var plan in program.closures) {
			if (plan.handle.checked_error != null && plan.handle.signature.borrowed_parameters.length == 2) {
				if (plan.binding) {
					binding = plan;
				} else {
					invocation = plan;
				}
			}
		}
		assert (invocation != null && binding != null);
		var channel = invocation.handle.signature.borrowed_parameters[0];
		invocation.handle.signature.borrowed_parameters[0] = new NativeCallableBorrowChannel (channel.ordinal, "R", false);
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("borrowed argument nominal identity");
		}
		assert (refused);
		invocation.handle.signature.borrowed_parameters[0] = channel;
		NativeAbiVerifier.verify (program);
		var target = program.functions[binding.target];
		var original = target.signature.parameters[1];
		target.signature.parameters[1] = new NativeParameter.typed (original.span, original.name_span, original.name, original.ordinal, original.abi_type, target.signature.parameters[0].borrowed_class_ordinal);
		refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("bound borrowed parameter");
		}
		assert (refused);
		target.signature.parameters[1] = original;
		NativeAbiVerifier.verify (program);
		original = target.signature.parameters[2];
		var resource = original.resource;
		var forged = new NativeParameter.typed (original.span, original.name_span, original.name, original.ordinal, original.abi_type);
		forged.bind_resource (new NativeScalarOwner (resource.type_name, "wrong_cleanup"), false);
		target.signature.parameters[2] = forged;
		refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("borrowed Resource cleanup");
		}
		assert (refused);
		target.signature.parameters[2] = original;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void closure_record_core() {
	try {
		var program = core ("copied-record-closure");
		CoreClosureCall? invocation = null;
		foreach (var function in program.functions) {
			if (function.name == "forward_closure_record") {
				invocation = ((CoreReturn) function.body.statements[function.body.statements.length - 1]).value as CoreClosureCall;
			}
		}
		assert (invocation != null);
		var original = invocation.arguments[0];
		invocation.arguments[0] = invocation.arguments[2];
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		invocation.arguments[0] = original;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void closure_record_cfg() {
	try {
		CoreProgram? predecessor = core ("copied-record-closure");
		var prior = WeakRef (predecessor.classes[0]);
		var program = CfgBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CfgClosureCall? invocation = null;
		CfgClosureBind? binding = null;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var evaluation = instruction as CfgEvaluateInstruction;
					if (evaluation == null || instruction is CfgClosureCallSuccess) {
						continue;
					}
					var call = evaluation.value as CfgClosureCall;
					if (call != null && instruction is CfgCheckedClosureInvoke) {
						invocation = call;
					}
					if (evaluation.value is CfgClosureBind) {
						binding = (CfgClosureBind) evaluation.value;
					}
				}
			}
		}
		assert (invocation != null && binding != null && invocation.struct_arguments.length == 2);
		var original = invocation.struct_arguments[0];
		invocation.struct_arguments.remove_index (0);
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("record parameter");
		}
		assert (refused);
		invocation.struct_arguments.insert (0, original);
		CfgVerifier.verify (program);
		original = binding.target.struct_parameters[0];
		binding.target.struct_parameters[0] = new StructBoundaryGroup (original.source_ordinal - 1, original.first_leaf, original.shape);
		refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		binding.target.struct_parameters[0] = original;
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void closure_record_ssa() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("copied-record-closure"));
		var prior = WeakRef (predecessor.classes[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaClosureCall? invocation = null;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var call = instruction as SsaClosureCall;
					if (call != null && ((ClosureHandleType) call.callee.semantic_type).throws_type != null) {
						invocation = call;
					}
				}
			}
		}
		assert (invocation != null && invocation.struct_arguments.length == 2 && invocation.borrowed_arguments.length == 1);
		var original = invocation.struct_arguments[0];
		invocation.struct_arguments[0] = new StructBoundaryGroup (original.source_ordinal, original.first_leaf + 1, original.shape);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("record parameter");
		}
		assert (refused);
		invocation.struct_arguments[0] = original;
		SsaVerifier.verify (program);
		var loan = invocation.borrowed_arguments[0];
		invocation.borrowed_arguments[0] = new SsaCallableBorrowArgument (loan.ordinal - 1, loan.value, loan.source_owner);
		refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		invocation.borrowed_arguments[0] = loan;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void closure_record_native() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("copied-record-closure")));
		var prior = WeakRef (predecessor.classes[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		NativeClosurePlan? invocation = null;
		NativeClosurePlan? binding = null;
		foreach (var plan in program.closures) {
			if (plan.handle.checked_error == null) {
				continue;
			}
			if (plan.binding) {
				binding = plan;
			} else {
				invocation = plan;
			}
		}
		assert (invocation != null && binding != null && invocation.record_arguments.length == 2);
		var original = invocation.record_arguments[0];
		invocation.record_arguments[0] = new NativeCallableRecordParameter (original.source_ordinal, original.first_leaf, invocation.record_arguments[1].record_name, original.leaves);
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("record argument nominal identity");
		}
		assert (refused);
		invocation.record_arguments[0] = original;
		NativeAbiVerifier.verify (program);
		var target = program.functions[binding.target];
		var parameter = target.signature.struct_parameters[0];
		target.signature.struct_parameters[0] = new NativeStructParameterPlan (parameter.source_ordinal, parameter.first_leaf - 1, parameter.value_plan, parameter.mode);
		refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		target.signature.struct_parameters[0] = parameter;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void callable_signature_inventory_core() {
	try {
		var program = core ("borrowed-function-channel");
		FunctionValueType? signature = null;
		foreach (var function in program.functions) {
			foreach (var parameter in function.parameters) {
				if (parameter.semantic_type is FunctionValueType) {
					signature = (FunctionValueType) parameter.semantic_type;
				}
			}
		}
		assert (signature != null);
		int original_count = (int) signature.parameter_types.length;
		signature.parameter_types.add (signature.result_type);
		bool refused = false;
		try {
			signature.verify_records (signature.record_parameters, (record) => null);
		} catch (StructLeafError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("complete parameter channel");
		}
		assert (refused);
		refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		signature.parameter_types.remove_index (original_count);
		CoreVerifier.verify_concrete (program);

		program = core ("copied-record-closure");
		ClosureHandleType? closure = null;
		foreach (var function in program.functions) {
			foreach (var parameter in function.parameters) {
				if (parameter.semantic_type is ClosureHandleType) {
					closure = (ClosureHandleType) parameter.semantic_type;
				}
			}
		}
		assert (closure != null);
		original_count = (int) closure.parameter_types.length;
		closure.parameter_types.add (closure.result_type);
		refused = false;
		try {
			closure.verify_records (closure.record_parameters, (record) => null);
		} catch (StructLeafError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("complete parameter channel");
		}
		assert (refused);
		refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		closure.parameter_types.remove_index (original_count);
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void generic_record_callable_graphs() {
	try {
		CheckedProgram? checked = check ("closed-record-callables");
		var checked_definition = WeakRef (checked.generic_structs[0].definition);
		CoreProgram? symbolic = CoreBuilder.build (checked);
		checked = null;
		assert (checked_definition.get () == null);
		CoreVerifier.verify (symbolic);
		var definition = WeakRef (symbolic.generic_structs[0]);
		CoreProgram? concrete = CoreGenericMonomorphizer.build (symbolic);
		symbolic = null;
		assert (definition.get () == null);
		CoreVerifier.verify_concrete (concrete);
		CoreClosureCall? invocation = null;
		foreach (var function in concrete.functions) {
			if (function.name == "forward_application") {
				invocation = ((CoreReturn) function.body.statements[function.body.statements.length - 1]).value as CoreClosureCall;
			}
		}
		assert (invocation != null && invocation.arguments[0] is CoreStructArgument);
		assert (((CoreStructArgument) invocation.arguments[0]).parameter == null);
		assert (invocation.arguments[0].semantic_type is StructType);
		var core_owner = WeakRef (concrete.classes[0]);
		CfgProgram? cfg = CfgBuilder.build (concrete);
		invocation = null;
		concrete = null;
		assert (core_owner.get () == null);
		CfgVerifier.verify (cfg);
		var cfg_owner = WeakRef (cfg.classes[0]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (cfg_owner.get () == null);
		SsaVerifier.verify (ssa);
		var ssa_owner = WeakRef (ssa.classes[0]);
		var native = NativeAbiBuilder.build (ssa);
		ssa = null;
		assert (ssa_owner.get () == null);
		assert (native.record_applications.length == 2);
		NativeAbiVerifier.verify (native);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void generic_record_callable_nominal_core() {
	try {
		var program = CoreBuilder.build (check ("closed-record-callables"));
		CoreGenericStructApplicationType? pair = null;
		foreach (var function in program.functions) {
			if (function.name != "application_code") {
				continue;
			}
			var signature = (FunctionValueType) function.return_type;
			var input = (CoreGenericStructApplicationType) signature.parameter_types[0];
			pair = input.type_arguments[0] as CoreGenericStructApplicationType;
		}
		assert (pair != null && pair.type_arguments.length == 2);
		var first = pair.type_arguments[0];
		var second = pair.type_arguments[1];
		pair.type_arguments[0] = second;
		pair.type_arguments[1] = first;
		bool refused = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		pair.type_arguments[0] = first;
		pair.type_arguments[1] = second;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void generic_record_callable_boundary_core() {
	try {
		var program = core ("closed-record-callables");
		CoreClosureCall? invocation = null;
		foreach (var function in program.functions) {
			if (function.name == "forward_application") {
				invocation = ((CoreReturn) function.body.statements[function.body.statements.length - 1]).value as CoreClosureCall;
			}
		}
		assert (invocation != null && invocation.channel_parameters.length == 4);
		var original = (CoreStructArgument) invocation.arguments[0];
		invocation.arguments[0] = new CoreStructArgument (original.span, invocation.channel_parameters[0], original.producer);
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("indirect record argument");
		}
		assert (refused);
		invocation.arguments[0] = original;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void generic_record_callable_native() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("closed-record-callables")));
		var prior = WeakRef (predecessor.classes[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null && program.record_applications.length == 2);
		var application = program.record_applications[0];
		program.record_applications.remove_index (0);
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("original nominal application");
		}
		assert (refused);
		program.record_applications.insert (0, application);
		NativeAbiVerifier.verify (program);
		var arguments = new NativeDeclaredType[application.argument_count];
		for (int a = 0; a < arguments.length; a++) {
			arguments[a] = application.argument (a);
		}
		program.record_applications[0] = new NativeRecordApplicationPlan ("SameLayoutOtherDefinition", arguments, application.record);
		refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("original nominal application");
		}
		assert (refused);
		program.record_applications[0] = application;
		NativeAbiVerifier.verify (program);
		NativeFunctionPointerType? callback = null;
		foreach (var owner in program.classes) {
			foreach (var field in owner.fields) {
				if (field.storage_type is NativeFunctionPointerType && ((NativeFunctionPointerType) field.storage_type).record_parameters.length == 2) {
					callback = (NativeFunctionPointerType) field.storage_type;
				}
			}
		}
		assert (callback != null);
		var group = callback.record_parameters[0];
		callback.record_parameters[0] = new NativeCallableRecordParameter (group.source_ordinal, group.first_leaf, callback.record_parameters[1].record_name, group.leaves);
		refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		callback.record_parameters[0] = group;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void class_type_argument_core() {
	try {
		var program = core ("closed-record-type-only");
		assert (program.class_type_arguments.length == 2);
		foreach (var function in program.functions) {
			if (function.name != "main") {
				continue;
			}
			foreach (var local in function.locals) {
				assert (!(local.semantic_type is StructType) && local.semantic_type.get_type () != typeof (HandleType));
			}
		}
		var original = program.class_type_arguments[0];
		assert (original.semantic_type is StructType);
		program.class_type_arguments.remove_index (0);
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("nominal argument");
		}
		assert (refused);
		program.class_type_arguments.insert (0, original);
		CoreVerifier.verify_concrete (program);
		program.class_type_arguments[0] = new ClassTypeArgument (original.owner_type, original.ordinal, program.class_type_arguments[1].semantic_type);
		refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("nominal argument");
		}
		assert (refused);
		program.class_type_arguments[0] = original;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void class_type_argument_cfg() {
	try {
		CoreProgram? predecessor = core ("closed-record-type-only");
		var prior = WeakRef (predecessor.classes[0]);
		var program = CfgBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null && program.class_type_arguments.length == 2);
		var original = program.class_type_arguments[0];
		program.class_type_arguments.remove_index (0);
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("nominal argument");
		}
		assert (refused);
		program.class_type_arguments.insert (0, original);
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void class_type_argument_ssa() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("closed-record-type-only"));
		var prior = WeakRef (predecessor.classes[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null && program.class_type_arguments.length == 2 && program.structs.length == 1);
		var original = program.class_type_arguments[0];
		program.class_type_arguments[0] = new ClassTypeArgument (original.owner_type, original.ordinal, program.class_type_arguments[1].semantic_type);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("nominal argument");
		}
		assert (refused);
		program.class_type_arguments[0] = original;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private CoreProgram native_declaration_program(out WeakRef prior_function, out WeakRef prior_class) throws GLib.Error {
	var source = new SourceFile.from_text ("<native-declaration-proof>",
		"namespace NativeFacts; class Item { int code; init(int code) { this.code=code; } deinit() {} } struct Input { int first; bool ready; } int inspect(Input input,borrowed Item value) { if(input.ready){return input.first+value.code;}return value.code; }", true);
	var parsed = Parser.parse (source);
	assert (parsed.diagnostic == null);
	var units = new GenericArray<CompilationUnitSyntax> ();
	units.add (parsed.unit);
	var declarations = new NativeDeclarationRegistry ();
	foreach (string key in new string[] { "F:NativeFacts.inspect", "C:NativeFacts.Item::init", "C:NativeFacts.Item::deinit" }) {
		declarations.add (source, new NativeDeclarationIdentity ("proof-origin", key, "astra_mod_proof_" + key, "not-an-emission-contract"));
	}
	var checked = SemanticAnalyzer.analyze_program (new SyntaxProgram (units), null, null, null, null, declarations);
	assert (checked.diagnostic == null);
	prior_function = WeakRef (checked.program.functions[0].symbol);
	prior_class = WeakRef (checked.program.classes[0]);
	return CoreBuilder.build (checked.program);
}

private void native_declaration_core() {
	try {
		WeakRef prior_function;
		WeakRef prior_class;
		var program = native_declaration_program (out prior_function, out prior_class);
		assert (prior_function.get () == null && prior_class.get () == null);
		CoreVerifier.verify (program);
		CoreFunction? function = null;
		foreach (var candidate in program.functions) {
			if (candidate.name == "NativeFacts.inspect") {
				function = candidate;
			}
		}
		assert (function != null && function.native_declaration != null);
		var original = function.native_declaration;
		function.native_declaration = null;
		bool refused = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			refused = error.message.contains ("native declaration lost");
		}
		assert (refused);
		function.native_declaration = original;
		var parameter = function.parameters[function.parameters.length - 1];
		var type = parameter.semantic_type;
		parameter.semantic_type = new ClassType (type.display_name ());
		refused = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			refused = error.message.contains ("native declaration differs");
		}
		assert (refused);
		parameter.semantic_type = type;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_declaration_cfg() {
	try {
		WeakRef prior_function;
		WeakRef prior_class;
		CoreProgram? symbolic = native_declaration_program (out prior_function, out prior_class);
		CoreProgram? predecessor = CoreGenericMonomorphizer.build (symbolic);
		symbolic = null;
		assert (prior_function.get () == null && prior_class.get () == null);
		prior_class = WeakRef (predecessor.classes[0]);
		var program = CfgBuilder.build (predecessor);
		predecessor = null;
		assert (prior_class.get () == null);
		CfgVerifier.verify (program);
		CfgFunction? function = null;
		foreach (var candidate in program.functions) {
			if (candidate.name == "NativeFacts.inspect") {
				function = candidate;
			}
		}
		assert (function != null && function.native_declaration != null && function.struct_parameters.length == 1);
		var original = function.native_declaration;
		function.native_declaration = null;
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			refused = error.message.contains ("native declaration lost");
		}
		assert (refused);
		function.native_declaration = original;
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_declaration_ssa() {
	try {
		WeakRef prior_function;
		WeakRef prior_class;
		CoreProgram? symbolic = native_declaration_program (out prior_function, out prior_class);
		CoreProgram? concrete = CoreGenericMonomorphizer.build (symbolic);
		symbolic = null;
		CfgProgram? predecessor = CfgBuilder.build (concrete);
		concrete = null;
		assert (prior_function.get () == null && prior_class.get () == null);
		prior_class = WeakRef (predecessor.classes[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior_class.get () == null);
		SsaVerifier.verify (program);
		SsaFunction? function = null;
		foreach (var candidate in program.functions) {
			if (candidate.name == "NativeFacts.inspect") {
				function = candidate;
			}
		}
		assert (function != null && function.native_declaration != null && function.struct_parameters.length == 1);
		var original = function.native_declaration;
		function.native_declaration = null;
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			refused = error.message.contains ("native declaration lost");
		}
		assert (refused);
		function.native_declaration = original;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_declaration_core_body() {
	try {
		WeakRef prior_function;
		WeakRef prior_class;
		var program = native_declaration_program (out prior_function, out prior_class);
		assert (prior_function.get () == null && prior_class.get () == null);
		CoreFunction? function = null;
		foreach (var candidate in program.functions) {
			if (candidate.name == "NativeFacts.inspect") {
				function = candidate;
			}
		}
		assert (function != null && function.body.statements.length == 0 && function.locals.length == 0);
		function.body.statements.add (new CoreScope (function.span, new CoreBlock (function.span, new GenericArray<CoreStatement> ())));
		bool refused = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			refused = error.message.contains ("executable statements or local storage");
		}
		assert (refused);
		function.body.statements.remove_index (0);
		function.locals.add (new CoreLocalPlace (function.span, function.name_span, "injected", function.return_type, 0));
		refused = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			refused = error.message.contains ("executable statements or local storage");
		}
		assert (refused);
		function.locals.remove_index (0);
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_declaration_cfg_body() {
	try {
		WeakRef prior_function;
		WeakRef prior_class;
		CoreProgram? symbolic = native_declaration_program (out prior_function, out prior_class);
		CoreProgram? predecessor = CoreGenericMonomorphizer.build (symbolic);
		symbolic = null;
		prior_class = WeakRef (predecessor.classes[0]);
		var program = CfgBuilder.build (predecessor);
		predecessor = null;
		assert (prior_function.get () == null && prior_class.get () == null);
		CfgFunction? function = null;
		foreach (var candidate in program.functions) {
			if (candidate.name == "NativeFacts.inspect") {
				function = candidate;
			}
		}
		assert (function != null && function.declaration_only ());
		function.blocks.add (new CfgBlock (function.span, 1, new GenericArray<CfgInstruction> (), new CfgFunctionEnd (function.span)));
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			refused = error.message.contains ("one empty declaration block");
		}
		assert (refused);
		function.blocks.remove_index (1);
		function.locals.add (new CfgLocalPlace (function.span, function.name_span, "injected", function.return_type, 0));
		refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			refused = error.message.contains ("one empty declaration block");
		}
		assert (refused);
		function.locals.remove_index (0);
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_declaration_ssa_body() {
	try {
		WeakRef prior_function;
		WeakRef prior_class;
		CoreProgram? symbolic = native_declaration_program (out prior_function, out prior_class);
		CoreProgram? concrete = CoreGenericMonomorphizer.build (symbolic);
		symbolic = null;
		CfgProgram? predecessor = CfgBuilder.build (concrete);
		concrete = null;
		prior_class = WeakRef (predecessor.classes[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior_function.get () == null && prior_class.get () == null);
		SsaFunction? function = null;
		foreach (var candidate in program.functions) {
			if (candidate.name == "NativeFacts.inspect") {
				function = candidate;
			}
		}
		assert (function != null && function.declaration_only ());
		var extra = new SsaBlock (function.span, 1, 1);
		extra.complete (new SsaFunctionEnd (function.span));
		function.blocks.add (extra);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			refused = error.message.contains ("one empty declaration block");
		}
		assert (refused);
		function.blocks.remove_index (1);
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private CoreProgram native_property_program(out WeakRef prior_function, out WeakRef prior_class) throws GLib.Error {
	var source = new SourceFile.from_text ("<native-property-proof>",
		"namespace NativeViews; class Item { int code; init(int code) {} } class Holder { owned Item child; init(owned Item child) {} property borrowed Item view { get {} } property int first { get {} } property int second { get {} } }", true);
	var parsed = Parser.parse (source);
	assert (parsed.diagnostic == null);
	var units = new GenericArray<CompilationUnitSyntax> ();
	units.add (parsed.unit);
	var declarations = new NativeDeclarationRegistry ();
	foreach (string key in new string[] { "C:NativeViews.Item::init", "C:NativeViews.Holder::init", "C:NativeViews.Holder::deinit", "C:NativeViews.Holder::get:view", "C:NativeViews.Holder::get:first", "C:NativeViews.Holder::get:second" }) {
		declarations.add (source, new NativeDeclarationIdentity ("property-proof-origin", key, "astra_mod_property_proof_" + key, "not-an-emission-contract"));
	}
	var checked = SemanticAnalyzer.analyze_program (new SyntaxProgram (units), null, null, null, null, declarations);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	prior_function = WeakRef (checked.program.properties[0].getter);
	prior_class = WeakRef (checked.program.classes[1]);
	return CoreBuilder.build (checked.program);
}

private void native_property_contracts() {
	try {
		WeakRef prior_function;
		WeakRef prior_class;
		CoreProgram? symbolic = native_property_program (out prior_function, out prior_class);
		assert (prior_function.get () == null && prior_class.get () == null);
		CoreVerifier.verify (symbolic);
		assert (symbolic.classes[1].properties[0].is_borrowed);
		symbolic.classes[1].properties[0].is_borrowed = false;
		bool refused = false;
		try {
			CoreVerifier.verify (symbolic);
		} catch (CoreError error) {
			refused = error.message.contains ("native declaration differs");
		}
		assert (refused);
		symbolic.classes[1].properties[0].is_borrowed = true;
		CoreProgram? concrete = CoreGenericMonomorphizer.build (symbolic);
		symbolic = null;
		prior_class = WeakRef (concrete.classes[1]);
		CfgProgram? cfg = CfgBuilder.build (concrete);
		concrete = null;
		assert (prior_class.get () == null);
		CfgVerifier.verify (cfg);
		cfg.classes[1].properties[0].is_borrowed = false;
		refused = false;
		try {
			CfgVerifier.verify (cfg);
		} catch (CfgError error) {
			refused = error.message.contains ("native declaration differs");
		}
		assert (refused);
		cfg.classes[1].properties[0].is_borrowed = true;
		prior_class = WeakRef (cfg.classes[1]);
		var ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (prior_class.get () == null);
		SsaVerifier.verify (ssa);
		ssa.classes[1].properties[0].is_borrowed = false;
		refused = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			refused = error.message.contains ("native declaration differs");
		}
		assert (refused);
		ssa.classes[1].properties[0].is_borrowed = true;
		SsaVerifier.verify (ssa);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private CoreProgram native_record_property_program(out WeakRef prior) throws GLib.Error {
	var source = new SourceFile.from_text ("<native-record-property-proof>",
		"namespace NativeRecordViews; class Child { int code; init(int code) {} deinit() {} } struct Payload { owned Child child; int stamp; } class Holder { private Payload payload; init(Payload payload) {} property borrowed Payload view { get {} } }", true);
	var parsed = Parser.parse (source);
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.format ());
	}
	var units = new GenericArray<CompilationUnitSyntax> ();
	units.add (parsed.unit);
	var declarations = new NativeDeclarationRegistry ();
	foreach (string key in new string[] { "C:NativeRecordViews.Child::init", "C:NativeRecordViews.Child::deinit", "C:NativeRecordViews.Holder::init", "C:NativeRecordViews.Holder::deinit", "C:NativeRecordViews.Holder::get:view" }) {
		declarations.add (source, new NativeDeclarationIdentity ("record-property-proof-origin", key,
			"astra_mod_record_property_proof_" + key, "not-an-emission-contract", key.has_suffix ("::get:view") ? "payload" : ""));
	}
	var checked = SemanticAnalyzer.analyze_program (new SyntaxProgram (units), null, null, null, null, declarations);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	prior = WeakRef (checked.program.classes[1]);
	return CoreBuilder.build (checked.program);
}

private void native_record_property_binding() {
	try {
		WeakRef prior;
		CoreProgram? symbolic = native_record_property_program (out prior);
		assert (prior.get () == null);
		CoreProgram? concrete = CoreGenericMonomorphizer.build (symbolic);
		symbolic = null;
		CfgProgram? cfg = CfgBuilder.build (concrete);
		concrete = null;
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		var native = NativeAbiBuilder.build (ssa);
		NativeFunction? getter = null;
		foreach (var candidate in native.functions) {
			if (candidate.record_observation != null) {
				getter = candidate;
			}
		}
		assert (getter != null && getter.record_observation.field_ordinal == 0);
		prior = WeakRef (ssa.classes[1]);
		ssa = null;
		assert (prior.get () == null);
		NativeAbiVerifier.verify (native);
		var original = getter.record_observation;
		getter.record_observation = new NativeRecordObservation (original.class_ordinal, original.field_ordinal + 1, original.value_plan);
		bool refused = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			refused = error.message.contains ("record observation lost its original exact receiver-field binding");
		}
		assert (refused);
		getter.record_observation = original;
		NativeAbiVerifier.verify (native);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private CoreProgram native_closed_record_program(string argument, out WeakRef prior) throws GLib.Error {
	var source = new SourceFile.from_text ("<native-record-inventory-proof>",
		"namespace RecordInventory; struct Pair<A,B> { A first; B second; }", true);
	var parsed = Parser.parse (source);
	assert (parsed.diagnostic == null);
	var client = Parser.parse (new SourceFile.from_text ("<native-record-inventory-client>",
		"int probe<T>(T item){RecordInventory.Pair<T,bool> value={first=item,second=true};return 0;}int main(){return probe<" + argument + ">(" + (argument == "int" ? "42" : "true") + ");}"));
	assert (client.diagnostic == null);
	var units = new GenericArray<CompilationUnitSyntax> ();
	units.add (parsed.unit);
	units.add (client.unit);
	var declarations = new NativeDeclarationRegistry ();
	var inventory = new GenericArray<string> ();
	inventory.add ("RecordInventory.Pair<int,bool>");
	declarations.add_types (source, inventory);
	inventory.remove_index (0);
	var checked = SemanticAnalyzer.analyze_program (new SyntaxProgram (units), null, null, null, null, declarations);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	prior = WeakRef (checked.program.generic_structs[0].definition);
	return CoreBuilder.build (checked.program);
}

private void native_closed_record_inventory() {
	try {
		WeakRef prior;
		CoreProgram? program = native_closed_record_program ("int", out prior);
		assert (prior.get () == null);
		CoreVerifier.verify (program);
		var concrete = CoreGenericMonomorphizer.build (program);
		program = null;
		CoreVerifier.verify_concrete (concrete);
		program = native_closed_record_program ("bool", out prior);
		assert (prior.get () == null);
		CoreVerifier.verify (program);
		bool refused = false;
		try {
			CoreGenericMonomorphizer.build (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("closed record application is not exported: RecordInventory.Pair<bool,bool>");
		}
		assert (refused);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_published_record_metadata() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("<published-record-proof>",
			"namespace PublishedRecords;struct Pair<A,B>{A first;B second;}internal struct Published{Pair<i64,bool> value;}"));
		assert (parsed.diagnostic == null);
		var checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.diagnostic == null);
		CoreProgram? symbolic = CoreBuilder.build (checked.program);
		CoreProgram? concrete = CoreGenericMonomorphizer.build (symbolic);
		symbolic = null;
		CfgProgram? cfg = CfgBuilder.build (concrete);
		concrete = null;
		SsaProgram? ssa = SsaBuilder.build (cfg, new string[] { "PublishedRecords.Pair<i64,bool>" });
		cfg = null;
		assert (ssa.functions.length == 0 && ssa.structs.length == 1);
		var prior = WeakRef (ssa.structs[0]);
		var native = NativeAbiBuilder.build (ssa);
		ssa = null;
		assert (prior.get () == null && native.record_applications.length == 1);
		NativeAbiVerifier.verify (native);
		var application = native.record_applications[0];
		assert (application.nominal_name == "PublishedRecords.Pair<i64,bool>");
		native.record_applications.remove_index (0);
		bool refused = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("original nominal application");
		}
		assert (refused);
		native.record_applications.add (application);
		NativeAbiVerifier.verify (native);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_resource_transport() {
	try {
		string text;
		FileUtils.get_contents ("tests/structural-generics-15/unit-resource-provider.astra", out text);
		var parsed = Parser.parse (new SourceFile.from_text ("<native-resource-proof>", text));
		assert (parsed.diagnostic == null);
		string api;
		FileUtils.get_contents ("tests/own-field/fixtures/resources.vapi", out api);
		var imported = VapiParser.parse (new SourceFile.from_text ("resources.vapi", api));
		assert (imported.diagnostic == null);
		var checked = SemanticAnalyzer.analyze (parsed.unit, VapiNormalizer.normalize (imported.file), VapiNormalizer.normalize_handles (imported.file));
		if (checked.diagnostic != null) {
			GLib.error ("%s", checked.diagnostic.format ());
		}
		CoreProgram? symbolic = CoreBuilder.build (checked.program);
		CoreProgram? concrete = CoreGenericMonomorphizer.build (symbolic);
		symbolic = null;
		CfgProgram? cfg = CfgBuilder.build (concrete);
		concrete = null;
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		var prior = WeakRef (ssa.functions[0]);
		var native = NativeAbiBuilder.build (ssa);
		ssa = null;
		assert (prior.get () == null);
		NativeAbiVerifier.verify (native);
		int tested = 0;
		foreach (var function in native.functions) {
			if (function.name != "NativeResources.consume" && function.name != "NativeResources.inspect" && function.name != "NativeResources.consume_other") {
				continue;
			}
			var signature = function.signature;
			var original = signature.parameters[0];
			assert (original.resource != null);
			var forged = new NativeParameter.typed (original.span, original.name_span, original.name, original.ordinal, original.abi_type);
			forged.bind_resource (original.resource, !original.owns_resource);
			signature.parameters[0] = forged;
			bool refused = false;
			try {
				NativeAbiVerifier.verify (native);
			} catch (NativeAbiError error) {
				Test.message ("%s", error.message);
				refused = error.message.contains ("Resource cleanup/transfer differs from its original signature");
			}
			assert (refused);
			signature.parameters[0] = original;
			NativeAbiVerifier.verify (native);
			forged = new NativeParameter.typed (original.span, original.name_span, original.name, original.ordinal, original.abi_type);
			forged.bind_resource (new NativeScalarOwner (original.resource.type_name, "incorrect_destructor"), original.owns_resource);
			signature.parameters[0] = forged;
			refused = false;
			try {
				NativeAbiVerifier.verify (native);
			} catch (NativeAbiError error) {
				Test.message ("%s", error.message);
				refused = error.message.contains ("Resource cleanup/transfer differs from its original signature");
			}
			assert (refused);
			signature.parameters[0] = original;
			NativeAbiVerifier.verify (native);
			tested++;
		}
		assert (tested == 3);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void owned_callable_core() {
	try {
		CheckedProgram? checked = check ("owned-callable-resources");
		var prior = WeakRef (checked.classes[0]);
		var program = CoreBuilder.build (checked);
		checked = null;
		assert (prior.get () == null);
		CoreVerifier.verify (program);
		CoreFunctionValueCall? invocation = null;
		CoreFunction? caller = null;
		foreach (var function in program.functions) {
			if (function.name != "forward_transfer") {
				continue;
			}
			caller = function;
			foreach (var statement in function.body.statements) {
				var returned = statement as CoreReturn;
				if (returned != null) {
					invocation = returned.value as CoreFunctionValueCall;
				}
			}
		}
		assert (invocation != null && caller != null && invocation.channel_parameters.length == 1);
		var original = invocation.arguments[0] as CoreOwnedArgumentValue;
		assert (original != null);
		invocation.arguments[0] = new CoreOwnedArgumentValue (original.span, caller.parameters[1], original.cleanup, original.source);
		bool refused = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("indirect owned argument requires its exact channel");
		}
		assert (refused);
		invocation.arguments[0] = original;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void owned_callable_cfg() {
	try {
		CoreProgram? predecessor = core ("owned-callable-resources");
		var prior = WeakRef (predecessor.functions[0]);
		var program = CfgBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CfgVerifier.verify (program);
		CfgBlock? block = null;
		CfgOwnedCallTransferCommit? commit = null;
		int position = -1;
		foreach (var function in program.functions) {
			if (function.name != "forward_transfer") {
				continue;
			}
			foreach (var candidate in function.blocks) {
				for (int p = 0; p < candidate.instructions.length; p++) {
					var transfer = candidate.instructions[p] as CfgOwnedCallTransferCommit;
					if (transfer != null) {
						block = candidate;
						commit = transfer;
						position = p;
					}
				}
			}
		}
		assert (commit != null && block != null && commit.transfers.length == 1);
		block.instructions.remove_index (position);
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("indirect owned argument requires one exact committed capture");
		}
		assert (refused);
		block.instructions.insert (position, commit);
		CfgVerifier.verify (program);
		var original = commit.transfers[0].consumer;
		commit.transfers[0].consumer = null;
		refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		commit.transfers[0].consumer = original;
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void owned_callable_ssa() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("owned-callable-resources"));
		var prior = WeakRef (predecessor.functions[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaVerifier.verify (program);
		SsaFunctionValueCall? invocation = null;
		foreach (var function in program.functions) {
			if (function.name == "forward_transfer") {
				foreach (var block in function.blocks) {
					foreach (var instruction in block.instructions) {
						invocation = instruction as SsaFunctionValueCall ?? invocation;
					}
				}
			}
		}
		assert (invocation != null && invocation.owned_arguments.length == 1);
		var original = invocation.owned_arguments[0];
		invocation.owned_arguments.remove_index (0);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		invocation.owned_arguments.add (original);
		SsaVerifier.verify (program);
		invocation.owned_arguments[0] = new SsaCallableOwnedArgument (original.span, original.ordinal, original.value, original.cleanup, original.source_ordinal, null);
		refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		invocation.owned_arguments[0] = original;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void owned_callable_native() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("owned-callable-resources")));
		var prior = WeakRef (predecessor.functions[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		NativeAbiVerifier.verify (program);
		NativeFunctionValuePlan? invocation = null;
		foreach (var plan in program.function_values) {
			if (plan.owned_arguments.length != 0 && plan.signature.record_parameters.length != 0) {
				invocation = plan;
			}
		}
		assert (invocation != null);
		var original = invocation.owned_arguments[0];
		invocation.owned_arguments[0] = new NativeCallableOwnedArgument (original.ordinal, new NativeScalarOwner (original.resource.type_name, "incorrect_callback_destructor"), original.source_ordinal, original.null_argument, original.committed_null);
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("original ownership transfer facts");
		}
		assert (refused);
		invocation.owned_arguments[0] = original;
		NativeAbiVerifier.verify (program);
		var channel = invocation.signature.owned_parameters[0];
		invocation.signature.owned_parameters[0] = new NativeCallableOwnedChannel (channel.ordinal, "Other");
		refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("original owned channel declarations");
		}
		assert (refused);
		invocation.signature.owned_parameters[0] = channel;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}


private void copied_callable_fields_native() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("copied-callable-fields")));
		var prior = WeakRef (predecessor.functions[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		NativeAbiVerifier.verify (program);
		NativeFunctionPointerType? signature = null;
		foreach (var plan in program.function_values) {
			if (plan.signature.record_parameters.length == 1 && plan.signature.parameter_types.length == 6) {
				signature = plan.signature;
			}
		}
		assert (signature != null);
		var group = signature.record_parameters[0];
		int pointer = -1;
		int code = -1;
		int vector = -1;
		for (int p = 0; p < signature.parameter_types.length; p++) {
			if (signature.parameter_types[p] is NativeFunctionPointerType) {
				code = p;
			} else if (signature.parameter_types[p] is NativeVectorType) {
				vector = p;
			} else if (((NativeScalarAbiType) signature.parameter_types[p]).scalar_type == NativeScalarType.PTR) {
				pointer = p;
			}
		}
		assert (pointer >= 0 && code >= 0 && vector >= 0);
		signature.borrowed_parameters.add (new NativeCallableBorrowChannel (pointer, "R", false));
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			refused = error.message.contains ("without borrow or transfer authority");
		}
		assert (refused);
		signature.borrowed_parameters.remove_index (0);
		NativeAbiVerifier.verify (program);
		foreach (int ordinal in new int[] { code, vector }) {
			var original_type = signature.parameter_types[ordinal];
			var original_leaf = group.leaves[ordinal];
			NativeAbiType forged;
			if (ordinal == code) {
				forged = new NativeScalarAbiType (NativeScalarType.PTR);
			} else {
				forged = new NativeVectorType (NativeScalarType.I32, 4);
			}
			signature.parameter_types[ordinal] = forged;
			group.leaves[ordinal] = new NativeStructLeafChannel (original_leaf.field_path, forged);
			refused = false;
			try {
				NativeAbiVerifier.verify (program);
			} catch (NativeAbiError error) {
				Test.message ("%s", error.message);
				refused = error.message.contains ("differs from its declared storage");
			}
			assert (refused);
			signature.parameter_types[ordinal] = original_type;
			group.leaves[ordinal] = original_leaf;
			NativeAbiVerifier.verify (program);
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void owned_class_callable_core() {
	try {
		CheckedProgram? predecessor = check ("owned-callable-classes");
		var prior = WeakRef (predecessor.classes[0]);
		var program = CoreBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CoreVerifier.verify (program);
		CoreFunctionValueCall? invocation = null;
		foreach (var function in program.functions) {
			if (function.name != "forward_class") {
				continue;
			}
			foreach (var statement in function.body.statements) {
				var returned = statement as CoreReturn;
				if (returned != null) {
					invocation = returned.value as CoreFunctionValueCall;
				}
			}
		}
		assert (invocation != null && invocation.channel_parameters[0].heap_object);
		invocation.channel_parameters[0].heap_object = false;
		bool refused = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			refused = error.message.contains ("channel declaration differs from carried signature");
		}
		assert (refused);
		invocation.channel_parameters[0].heap_object = true;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void owned_class_callable_cfg() {
	try {
		CoreProgram? predecessor = core ("owned-callable-classes");
		var prior = WeakRef (predecessor.functions[0]);
		var program = CfgBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CfgVerifier.verify (program);
		CfgFunctionValueCall? invocation = null;
		foreach (var function in program.functions) {
			if (function.name != "forward_class") {
				continue;
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var evaluation = instruction as CfgEvaluateInstruction;
					if (evaluation != null && evaluation.value is CfgFunctionValueCall) {
						invocation = (CfgFunctionValueCall) evaluation.value;
					}
				}
			}
		}
		assert (invocation != null && invocation.channel_parameters[0].heap_object);
		invocation.channel_parameters[0].heap_object = false;
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			refused = error.message.contains ("channel differs from its signature");
		}
		assert (refused);
		invocation.channel_parameters[0].heap_object = true;
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void owned_class_callable_ssa() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("owned-callable-classes"));
		var prior = WeakRef (predecessor.functions[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaVerifier.verify (program);
		SsaFunctionValueCall? invocation = null;
		foreach (var function in program.functions) {
			if (function.name == "forward_class") {
				foreach (var block in function.blocks) {
					foreach (var instruction in block.instructions) {
						invocation = instruction as SsaFunctionValueCall ?? invocation;
					}
				}
			}
		}
		assert (invocation != null && invocation.owned_arguments.length == 1);
		var original = invocation.owned_arguments[0];
		assert (original.cleanup.is_heap_object);
		SsaCleanupContract? lexical = null;
		foreach (var cleanup in program.cleanups) {
			if (cleanup.is_object && !cleanup.is_heap_object && cleanup.object_class == original.cleanup.object_class) {
				lexical = cleanup;
			}
		}
		assert (lexical != null);
		invocation.owned_arguments[0] = new SsaCallableOwnedArgument (original.span, original.ordinal, original.value, lexical, original.source_ordinal, original.source_after_commit, original.source_storage);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("indirect owned argument lost exact ordinal, value or cleanup");
		}
		assert (refused);
		invocation.owned_arguments[0] = original;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void owned_class_callable_native() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("owned-callable-classes")));
		var prior = WeakRef (predecessor.functions[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		NativeAbiVerifier.verify (program);
		NativeFunctionValuePlan? invocation = null;
		foreach (var plan in program.function_values) {
			if (plan.owned_arguments.length != 0 && plan.signature.owned_parameters[0].is_class) {
				invocation = plan;
			}
		}
		assert (invocation != null);
		var original = invocation.owned_arguments[0];
		assert (original.resource.class_ordinal >= 0);
		invocation.owned_arguments[0] = new NativeCallableOwnedArgument (original.ordinal, new NativeScalarOwner (original.resource.type_name, ""), original.source_ordinal, original.null_argument, original.committed_null);
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			refused = error.message.contains ("original ownership transfer facts");
		}
		assert (refused);
		invocation.owned_arguments[0] = original;
		var channel = invocation.signature.owned_parameters[0];
		invocation.signature.owned_parameters[0] = new NativeCallableOwnedChannel (channel.ordinal, channel.type_name);
		refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			refused = error.message.contains ("original owned channel declarations");
		}
		assert (refused);
		invocation.signature.owned_parameters[0] = channel;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void owning_record_callable_core() {
	try {
		CheckedProgram? predecessor = check ("owning-record-callables");
		var prior = WeakRef (predecessor.structs[0]);
		var program = CoreBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CoreVerifier.verify (program);
		CoreFunctionValueCall? invocation = null;
		foreach (var function in program.functions) {
			if (function.name != "forward_record_packet") {
				continue;
			}
			foreach (var statement in function.body.statements) {
				var returned = statement as CoreReturn;
				if (returned != null) {
					invocation = returned.value as CoreFunctionValueCall;
				}
			}
		}
		assert (invocation != null);
		var original = (CoreStructArgument) invocation.arguments[0];
		var moved = original.producer as CoreStructMoveProducer;
		assert (moved != null);
		invocation.arguments[0] = new CoreStructArgument (original.span, null, new CoreStructSnapshot (original.span, moved.source.place));
		bool refused = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			refused = error.message.contains ("exact copy/move signature boundary");
		}
		assert (refused);
		invocation.arguments[0] = original;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void owning_record_callable_cfg() {
	try {
		CoreProgram? predecessor = core ("owning-record-callables");
		var prior = WeakRef (predecessor.functions[0]);
		var program = CfgBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CfgVerifier.verify (program);
		CfgBlock? site = null;
		CfgStructBoundaryMove? move = null;
		int position = -1;
		foreach (var function in program.functions) {
			if (function.name != "forward_record_packet") {
				continue;
			}
			foreach (var block in function.blocks) {
				for (int p = 0; p < block.instructions.length; p++) {
					if (block.instructions[p] is CfgStructBoundaryMove) {
						site = block;
						position = p;
						move = (CfgStructBoundaryMove) block.instructions[p];
					}
				}
			}
		}
		assert (site != null && move != null);
		site.instructions.remove_index (position);
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("indirect MOVE_VALUE argument requires one exact complete field commit");
		}
		assert (refused);
		site.instructions.insert (position, move);
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void owning_record_callable_ssa() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("owning-record-callables"));
		var prior = WeakRef (predecessor.functions[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaVerifier.verify (program);
		SsaFunctionValueCall? invocation = null;
		foreach (var function in program.functions) {
			if (function.name == "forward_record_packet") {
				foreach (var block in function.blocks) {
					foreach (var instruction in block.instructions) {
						invocation = instruction as SsaFunctionValueCall ?? invocation;
					}
				}
			}
		}
		assert (invocation != null && invocation.record_moves.length == 1);
		var signature = (FunctionValueType) invocation.callee.semantic_type;
		assert (!signature.record_parameters[0].shape.physical_buffers && invocation.struct_arguments[0].shape.physical_buffers);
		assert (invocation.struct_arguments[0].shape.leaves.length == signature.record_parameters[0].shape.leaves.length + 1);
		var original_move = invocation.record_moves[0];
		invocation.record_moves.remove_index (0);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("MOVE_VALUE argument lost its exact call commit");
		}
		assert (refused);
		invocation.record_moves.add (original_move);
		SsaVerifier.verify (program);
		int length = -1;
		for (int p = 0; p < invocation.struct_arguments[0].shape.leaves.length; p++) {
			var buffer = invocation.struct_arguments[0].shape.leaves[p] as StructBufferLeafPath;
			if (buffer != null && buffer.component == 1) {
				length = p;
			}
		}
		assert (length >= 0);
		var original_length = invocation.arguments[length];
		invocation.arguments[length] = invocation.arguments[invocation.arguments.length - 1];
		refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("indirect MOVE_VALUE argument requires one exact complete prior field commit");
		}
		assert (refused);
		invocation.arguments[length] = original_length;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void owning_record_callable_native() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("owning-record-callables")));
		var prior = WeakRef (predecessor.functions[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		NativeAbiVerifier.verify (program);
		NativeFunctionValuePlan? invocation = null;
		foreach (var plan in program.function_values) {
			if (plan.signature.record_parameters.length == 1 && plan.signature.record_parameters[0].mode == NativeStructValueMode.MOVE_VALUE) {
				invocation = plan;
			}
		}
		assert (invocation != null);
		var original_group = invocation.signature.record_parameters[0];
		invocation.signature.record_parameters[0] = new NativeCallableRecordParameter (original_group.source_ordinal, original_group.first_leaf, original_group.record_name, original_group.leaves);
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("exact complete copied declaration");
		}
		assert (refused);
		invocation.signature.record_parameters[0] = original_group;
		NativeAbiVerifier.verify (program);
		int base_index = -1;
		for (int p = 0; p < original_group.leaves.length; p++) {
			if (original_group.leaves[p].buffer_component == 0) {
				base_index = p;
			}
		}
		assert (base_index >= 0);
		var original_leaf = original_group.leaves[base_index];
		original_group.leaves[base_index] = new NativeStructLeafChannel (original_leaf.field_path, original_leaf.abi_type, original_leaf.storage_path, 1);
		refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("differs from its declared storage");
		}
		assert (refused);
		original_group.leaves[base_index] = original_leaf;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void owning_record_callable_type_roots() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("historical-owning-record-callable"));
		var prior = WeakRef (predecessor.structs[0]);
		SsaProgram? ssa = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null && ssa.structs.length == 1);
		SsaVerifier.verify (ssa);
		var declaration = ssa.structs[0];
		ssa.structs.remove_index (0);
		bool refused = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("exact struct field graph");
		}
		assert (refused);
		ssa.structs.add (declaration);
		SsaVerifier.verify (ssa);
		prior = WeakRef (ssa.functions[0]);
		var native = NativeAbiBuilder.build (ssa);
		ssa = null;
		assert (prior.get () == null && native.struct_values.length == 1);
		NativeAbiVerifier.verify (native);
		var plan = native.struct_values[0];
		native.struct_values.remove_index (0);
		refused = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("exact complete copied declaration");
		}
		assert (refused);
		native.struct_values.add (plan);
		NativeAbiVerifier.verify (native);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void owned_callable_result_core() {
	try {
		CheckedProgram? predecessor = check ("owned-callable-results");
		var prior = WeakRef (predecessor.functions[0]);
		var program = CoreBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CoreVerifier.verify (program);
		CoreFunction? caller = null;
		CoreInitialize? original = null;
		int position = -1;
		foreach (var function in program.functions) {
			if (function.name != "exercise_result_functions") {
				continue;
			}
			for (int i = 0; i < function.body.statements.length; i++) {
				var initialization = function.body.statements[i] as CoreInitialize;
				if (initialization != null && initialization.acquisition != null && initialization.value is CoreFunctionValueCall) {
					caller = function;
					original = initialization;
					position = i;
					break;
				}
			}
		}
		assert (caller != null && original != null && position >= 0);
		var call = (CoreFunctionValueCall) original.value;
		CoreCleanupContract? wrong = null;
		foreach (var handle in program.handles) {
			if (handle.name == "Other") {
				wrong = handle.cleanup;
			}
		}
		assert (wrong != null && wrong != call.owned_cleanup);
		var forged = new CoreFunctionValueCall (call.span, (FunctionValueType) call.callee.semantic_type, call.callee, call.arguments, wrong);
		caller.body.statements[position] = new CoreInitialize (original.span, original.target, forged, original.acquisition);
		bool refused = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("exact acquisition and declared cleanup");
		}
		assert (refused);
		caller.body.statements[position] = original;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void owned_callable_result_cfg() {
	try {
		CoreProgram? predecessor = core ("owned-callable-results");
		var prior = WeakRef (predecessor.functions[0]);
		var program = CfgBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CfgVerifier.verify (program);
		CfgBlock? site = null;
		CfgInitialize? original = null;
		int position = -1;
		foreach (var function in program.functions) {
			if (function.name != "exercise_result_functions") {
				continue;
			}
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var initialization = block.instructions[i] as CfgInitialize;
					if (initialization != null && initialization.acquisition != null && initialization.value is CfgEvaluatedValue) {
						site = block;
						original = initialization;
						position = i;
						break;
					}
				}
			}
		}
		assert (site != null && original != null && position >= 0);
		site.instructions.remove_index (position);
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		site.instructions.insert (position, original);
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void owned_callable_result_ssa() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("owned-callable-results"));
		var prior = WeakRef (predecessor.functions[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaVerifier.verify (program);
		SsaBlock? site = null;
		SsaHeapOwnerEvent? original = null;
		int position = -1;
		foreach (var function in program.functions) {
			if (function.name != "exercise_result_functions") {
				continue;
			}
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var event = block.instructions[i] as SsaHeapOwnerEvent;
					if (event != null && event.action == SsaHeapOwnerAction.ACQUIRE) {
						site = block;
						original = event;
						position = i;
						break;
					}
				}
			}
		}
		assert (site != null && original != null && position >= 0);
		site.instructions.remove_index (position);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("exactly one guarded producer acquisition");
		}
		assert (refused);
		site.instructions.insert (position, original);
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void checked_callable_result_ssa() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("owned-callable-results"));
		var prior = WeakRef (predecessor.functions[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaVerifier.verify (program);
		SsaClosureCallSuccess? original = null;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var success = instruction as SsaClosureCallSuccess;
					if (success != null && success.call.owned_cleanup != null) {
						original = success;
					}
				}
			}
		}
		assert (original != null && original.call.owned_success == original);
		// A new result with no guarded acquisition cannot replace the publication.
		var forged = new SsaClosureCallSuccess (original.span, original.call, original.result.ordinal);
		assert (original.call.owned_success == forged);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("exactly one guarded producer acquisition");
		}
		assert (refused);
		original.call.owned_success = original;
		forged = null;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void owned_callable_result_native() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("owned-callable-results")));
		var prior = WeakRef (predecessor.functions[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		NativeAbiVerifier.verify (program);
		int position = -1;
		for (int i = 0; i < program.function_values.length; i++) {
			if (program.function_values[i].result_owner != null) {
				position = i;
				break;
			}
		}
		assert (position >= 0);
		var original = program.function_values[position];
		var resource = original.result_owner;
		assert (resource != null && original.signature.owned_result != null);
		program.function_values[position] = new NativeFunctionValuePlan (original.caller, original.block, original.instruction, original.signature,
			original.record_arguments, original.borrowed_arguments, original.owned_arguments,
			new NativeScalarOwner (resource.type_name, "incorrect_result_destructor"));
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("result cleanup differs");
		}
		assert (refused);
		program.function_values[position] = original;
		NativeAbiVerifier.verify (program);
		program.function_values[position] = new NativeFunctionValuePlan (original.caller, original.block, original.instruction, original.signature,
			original.record_arguments, original.borrowed_arguments, original.owned_arguments);
		refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("owned Resource acquisition");
		}
		assert (refused);
		program.function_values[position] = original;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private CoreProgram class_result_domain_core(out WeakRef source_function) throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("class-result-domain.astra",
		"class HeapProduced{init(){}}"
		+ "owned HeapProduced heap_result(){var value=new HeapProduced();return move value;}"
		+ "owned HeapProduced lexical_result(){return HeapProduced.init();}"
		+ "int main(){Fn<owned HeapProduced> code=heap_result;var value=code();return 0;}"));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	source_function = WeakRef (checked.program.functions[0]);
	return CoreGenericMonomorphizer.build (CoreBuilder.build (checked.program));
}

private void class_result_domain_core_proof() {
	try {
		WeakRef prior;
		var program = class_result_domain_core (out prior);
		assert (prior.get () == null);
		CoreVerifier.verify (program);
		CoreFunction? lexical = null;
		CoreFunction? caller = null;
		CoreInitialize? original = null;
		int position = -1;
		foreach (var function in program.functions) {
			if (function.name == "lexical_result") {
				lexical = function;
			}
			if (function.name != "main") {
				continue;
			}
			for (int i = 0; i < function.body.statements.length; i++) {
				var initialization = function.body.statements[i] as CoreInitialize;
				if (initialization != null && initialization.value is CoreFunctionAddress) {
					caller = function;
					original = initialization;
					position = i;
				}
			}
		}
		assert (lexical != null && !lexical.heap_result && caller != null && original != null && position >= 0);
		var forged = new CoreFunctionAddress (original.value.span, (FunctionValueType) original.value.semantic_type, lexical);
		caller.body.statements[position] = new CoreInitialize (original.span, original.target, forged, original.acquisition);
		bool refused = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("function address requires exact");
		}
		assert (refused);
		caller.body.statements[position] = original;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void class_result_domain_cfg_proof() {
	try {
		WeakRef source;
		CoreProgram? predecessor = class_result_domain_core (out source);
		var prior = WeakRef (predecessor.functions[0]);
		var program = CfgBuilder.build (predecessor);
		predecessor = null;
		assert (source.get () == null && prior.get () == null);
		CfgVerifier.verify (program);
		CfgFunction? lexical = null;
		CfgBlock? site = null;
		CfgInitialize? original = null;
		int position = -1;
		foreach (var function in program.functions) {
			if (function.name == "lexical_result") {
				lexical = function;
			}
			if (function.name != "main") {
				continue;
			}
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var candidate = block.instructions[i] as CfgInitialize;
					if (candidate != null && candidate.value is CfgFunctionAddress) {
						site = block;
						original = candidate;
						position = i;
					}
				}
			}
		}
		assert (lexical != null && !lexical.heap_result && site != null && original != null && position >= 0);
		var forged = new CfgFunctionAddress (original.value.span, (FunctionValueType) original.value.semantic_type, lexical);
		site.instructions[position] = new CfgInitialize (original.span, original.target, forged, original.acquisition);
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("function address requires exact");
		}
		assert (refused);
		site.instructions[position] = original;
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void class_result_domain_ssa_proof() {
	try {
		WeakRef source;
		CfgProgram? predecessor = CfgBuilder.build (class_result_domain_core (out source));
		var prior = WeakRef (predecessor.functions[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (source.get () == null && prior.get () == null);
		SsaVerifier.verify (program);
		SsaFunction? target = null;
		foreach (var function in program.functions) {
			if (function.name == "heap_result") {
				target = function;
			}
		}
		assert (target != null && target.heap_result && target.result_storage == null && target.owned_cleanup.is_heap_object);
		target.heap_result = false;
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		target.heap_result = true;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void class_result_native_proof() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("owned-callable-class-results")));
		var prior = WeakRef (predecessor.functions[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		NativeAbiVerifier.verify (program);
		int position = -1;
		for (int i = 0; i < program.function_values.length; i++) {
			var candidate = program.function_values[i];
			if (candidate.result_owner != null && candidate.signature.owned_result != null && candidate.signature.owned_result.is_class) {
				position = i;
				break;
			}
		}
		assert (position >= 0);
		var original = program.function_values[position];
		var resource = original.result_owner;
		program.function_values[position] = new NativeFunctionValuePlan (original.caller, original.block, original.instruction, original.signature,
			original.record_arguments, original.borrowed_arguments, original.owned_arguments,
			new NativeScalarOwner (resource.type_name, resource.cleanup_symbol, (int) program.classes.length));
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("Class result requires its exact nominal heap cleanup");
		}
		assert (refused);
		program.function_values[position] = original;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void class_result_buffer_native_proof() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("owned-callable-class-results")));
		var prior = WeakRef (predecessor.functions[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		NativeAbiVerifier.verify (program);
		NativeClassPlan? owner = null;
		int position = -1;
		foreach (var candidate in program.classes) {
			if (candidate.generic_instance == null || candidate.generic_instance.declared_structure == null) {
				continue;
			}
			for (int f = 0; f < candidate.fields.length; f++) {
				if (candidate.fields[f].owns_buffer) {
					owner = candidate;
					position = f;
					break;
				}
			}
		}
		assert (owner != null && position >= 0);
		var original = owner.fields[position];
		owner.fields[position] = new NativeClassField (original.span, original.name, original.type_name, original.ordinal, original.text_snapshot,
			original.storage_type, original.record_ordinal, original.is_private, original.owned_class_ordinal, false, original.resource_owner, original.owns_record);
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		owner.fields[position] = original;
		NativeAbiVerifier.verify (program);
		owner.fields[position] = new NativeClassField (original.span, original.name, original.type_name, original.ordinal, original.text_snapshot,
			new NativeSliceType (NativeScalarType.PTR, NativeScalarType.I64), original.record_ordinal, original.is_private,
			original.owned_class_ordinal, true, original.resource_owner, original.owns_record);
		refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		owner.fields[position] = original;
		NativeAbiVerifier.verify (program);
		// Validate a newly reconstructed declaration as well as the completed
		// program's immutable field inventory. The physical pair is unchanged;
		// its nominal element now disagrees with the declared int[] identity.
		var declared = owner.generic_instance.declared_structure;
		var field_type = declared.field_type (position);
		assert (field_type.valid (program));
		var malformed = new NativeDeclaredType (field_type.name, new NativeSliceType (), -1, null, null,
			"@slice", new NativeDeclaredType[] { new NativeDeclaredType ("bool", new NativeScalarAbiType (NativeScalarType.B1)) }, field_type.nominal_name);
		assert (!malformed.valid (program));
		NativeDeclaredType[] arguments = {};
		NativeDeclaredType[] fields = {};
		NativeDeclaredMember[] members = {};
		for (int i = 0; i < declared.argument_count; i++) {
			arguments += declared.argument (i);
		}
		for (int i = 0; i < declared.field_count; i++) {
			fields += i == position ? malformed : declared.field_type (i);
		}
		for (int i = 0; i < declared.member_count; i++) {
			members += declared.member (i);
		}
		var forged = new NativeDeclaredClass (declared.definition, arguments, fields, members);
		refused = false;
		try {
			forged.verify (owner, program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("field type/visibility substitution");
		}
		assert (refused);
		declared.verify (owner, program);
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void callable_record_result_core() {
	try {
		CheckedProgram? predecessor = check ("owning-callable-record-results");
		var prior = WeakRef (predecessor.functions[0]);
		var program = CoreGenericMonomorphizer.build (CoreBuilder.build (predecessor));
		predecessor = null;
		assert (prior.get () == null);
		CoreVerifier.verify_concrete (program);
		CoreFunction? site = null;
		CoreStructResultStore? original = null;
		int position = -1;
		foreach (var function in program.functions) {
			for (int i = 0; i < function.body.statements.length; i++) {
				var store = function.body.statements[i] as CoreStructResultStore;
				if (store != null && store.producer is CoreStructInvocationResult) {
					site = function;
					original = store;
					position = i;
				}
			}
		}
		assert (original != null && original.producer.contract.mode == StructValueMode.MOVE_VALUE);
		var producer = new CoreStructInvocationResult (((CoreStructInvocationResult) original.producer).invocation, StructValueMode.COPY_VALUE);
		site.body.statements[position] = new CoreStructResultStore (original.span, original.destination, producer, original.initializes_destination);
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("derived copy/move mode");
		}
		assert (refused);
		site.body.statements[position] = original;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void callable_record_result_cfg() {
	try {
		CoreProgram? predecessor = core ("owning-callable-record-results");
		var prior = WeakRef (predecessor.functions[0]);
		var program = CfgBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CfgVerifier.verify (program);
		CfgStructInvoke? invocation = null;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					if (instruction is CfgStructInvoke) {
						invocation = (CfgStructInvoke) instruction;
					}
				}
			}
		}
		assert (invocation != null && invocation.results.leaves.length > 1);
		var original = invocation.results.leaves[0];
		invocation.results.leaves[0] = invocation.results.leaves[invocation.results.leaves.length - 1];
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("unique ordered leaf definitions");
		}
		assert (refused);
		invocation.results.leaves[0] = original;
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void callable_record_result_ssa() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("owning-callable-record-results"));
		var prior = WeakRef (predecessor.functions[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaVerifier.verify (program);
		SsaStructCallResults? group = null;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var call = instruction as SsaFunctionValueCall;
					if (call != null && call.struct_result != null && call.struct_result.buffers.length > 0) {
						group = call.struct_result;
					}
				}
			}
		}
		assert (group != null && group.buffers.length == 1);
		var original = group.buffers[0];
		group.buffers.remove_index (0);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("one original complete physical field pair");
		}
		assert (refused);
		group.buffers.add (original);
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void checked_callable_record_result_ssa() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("owning-callable-record-results"));
		var prior = WeakRef (predecessor.functions[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaVerifier.verify (program);
		SsaClosureCallSuccess? original = null;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var success = instruction as SsaClosureCallSuccess;
					if (success != null && success.struct_result != null) {
						original = success;
					}
				}
			}
		}
		assert (original != null && original.result == null && original.call.owned_success == original);
		var forged = new SsaClosureCallSuccess (original.span, original.call, -1);
		forged.struct_result = original.struct_result;
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("exact dominating null-error successor");
		}
		assert (refused);
		original.call.owned_success = original;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void callable_record_result_native() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("owning-callable-record-results")));
		var prior = WeakRef (predecessor.functions[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		NativeAbiVerifier.verify (program);
		NativeFunctionValuePlan? invocation = null;
		foreach (var plan in program.function_values) {
			if (plan.signature.record_result != null) {
				invocation = plan;
			}
		}
		assert (invocation != null && invocation.signature.result_scalar () == null);
		var group = invocation.signature.record_result;
		var original = group.leaves[0];
		group.leaves[0] = new NativeStructLeafChannel (original.field_path, original.abi_type, original.storage_path, 1);
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("original native value declaration");
		}
		assert (refused);
		group.leaves[0] = original;
		NativeAbiVerifier.verify (program);
		// Reconstructing a whole signature cannot bypass nominal field verification.
		var wrong = new GenericArray<NativeStructLeafChannel> ();
		foreach (var leaf in group.leaves) {
			wrong.add (leaf);
		}
		wrong[0] = new NativeStructLeafChannel ("unrelated", original.abi_type);
		var signature = new NativeFunctionPointerType (null, invocation.signature.parameter_types, invocation.signature.record_parameters,
			invocation.signature.borrowed_parameters, invocation.signature.owned_parameters, null, new NativeCallableRecordResult (group.record_name, wrong, group.mode));
		int position = 0;
		while (program.function_values[position] != invocation) {
			position++;
		}
		program.function_values[position] = new NativeFunctionValuePlan (invocation.caller, invocation.block, invocation.instruction, signature,
			invocation.record_arguments, invocation.borrowed_arguments, invocation.owned_arguments, null, invocation.record_result);
		refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("original native value declaration");
		}
		assert (refused);
		program.function_values[position] = invocation;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void callable_record_result_native_acquisition() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("owning-callable-record-results")));
		var prior = WeakRef (predecessor.functions[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		NativeAbiVerifier.verify (program);
		int position = -1;
		for (int i = 0; i < program.function_values.length; i++) {
			if (program.function_values[i].record_result != null) {
				position = i;
				break;
			}
		}
		assert (position >= 0);
		var original = program.function_values[position];
		program.function_values[position] = new NativeFunctionValuePlan (original.caller, original.block, original.instruction, original.signature,
			original.record_arguments, original.borrowed_arguments, original.owned_arguments);
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("original native value declaration");
		}
		assert (refused);
		program.function_values[position] = original;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void callable_record_result_native_field() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("copied-callable-record-results")));
		var prior = WeakRef (predecessor.functions[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		NativeAbiVerifier.verify (program);
		NativeClassPlan? owner = null;
		int position = -1;
		foreach (var candidate in program.classes) {
			if (candidate.generic_instance == null || candidate.generic_instance.declared_structure == null) {
				continue;
			}
			for (int f = 0; f < candidate.fields.length; f++) {
				var signature = candidate.fields[f].storage_type as NativeFunctionPointerType;
				if (signature != null && signature.record_result != null) {
					owner = candidate;
					position = f;
				}
			}
		}
		assert (owner != null && position >= 0);
		var declared = owner.generic_instance.declared_structure;
		var original = declared.field_type (position);
		assert (original.valid (program));
		var integer = new NativeDeclaredType ("int", new NativeScalarAbiType (NativeScalarType.I32));
		var malformed = new NativeDeclaredType (original.name, original.storage, -1, null, null,
			"Fn", new NativeDeclaredType[] { integer, integer }, original.nominal_name);
		assert (!malformed.valid (program));
		NativeDeclaredType[] arguments = {};
		NativeDeclaredType[] fields = {};
		NativeDeclaredMember[] members = {};
		for (int i = 0; i < declared.argument_count; i++) {
			arguments += declared.argument (i);
		}
		for (int i = 0; i < declared.field_count; i++) {
			fields += i == position ? malformed : declared.field_type (i);
		}
		for (int i = 0; i < declared.member_count; i++) {
			members += declared.member (i);
		}
		var forged = new NativeDeclaredClass (declared.definition, arguments, fields, members);
		bool refused = false;
		try {
			forged.verify (owner, program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("field type/visibility substitution");
		}
		assert (refused);
		declared.verify (owner, program);
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}


private void borrowed_record_callable_core() {
	try {
		CheckedProgram? predecessor = check ("borrowed-callable-records");
		var prior = WeakRef (predecessor.functions[0]);
		var program = CoreGenericMonomorphizer.build (CoreBuilder.build (predecessor));
		predecessor = null;
		assert (prior.get () == null);
		CoreVerifier.verify_concrete (program);
		CoreFunctionValueCall? invocation = null;
		foreach (var function in program.functions) {
			if (function.name != "forward_borrowed_record") {
				continue;
			}
			foreach (var statement in function.body.statements) {
				var returned = statement as CoreReturn;
				if (returned != null) {
					invocation = returned.value as CoreFunctionValueCall;
				}
			}
		}
		assert (invocation != null && invocation.channel_parameters[0].struct_value_contract != null);
		var channel = invocation.channel_parameters[0];
		var original = channel.struct_value_contract;
		channel.struct_value_contract = null;
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("valid ownership or borrowed-noescape contract");
		}
		assert (refused);
		channel.struct_value_contract = original;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void borrowed_record_callable_cfg() {
	try {
		CoreProgram? predecessor = core ("borrowed-callable-records");
		var prior = WeakRef (predecessor.functions[0]);
		var program = CfgBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CfgVerifier.verify (program);
		CfgFunctionValueCall? invocation = null;
		int position = -1;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var evaluation = instruction as CfgEvaluateInstruction;
					var call = evaluation == null ? null : evaluation.value as CfgFunctionValueCall;
					if (call == null) {
						continue;
					}
					for (int g = 0; g < call.struct_arguments.length; g++) {
						if (call.struct_arguments[g] is CfgStructBorrowArgument) {
							invocation = call;
							position = g;
						}
					}
				}
			}
		}
		assert (invocation != null && position >= 0);
		var original = invocation.struct_arguments[position];
		invocation.struct_arguments[position] = new StructBoundaryGroup (original.source_ordinal, original.first_leaf, original.shape);
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("record argument loan");
		}
		assert (refused);
		invocation.struct_arguments[position] = original;
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void borrowed_record_callable_ssa_buffers() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("borrowed-callable-records"));
		var prior = WeakRef (predecessor.functions[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaVerifier.verify (program);
		SsaStructBorrowArgument? loan = null;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var call = instruction as SsaFunctionValueCall;
					if (call == null) {
						continue;
					}
					foreach (var group in call.struct_arguments) {
						var candidate = group as SsaStructBorrowArgument;
						if (candidate != null && candidate.buffers.length > 0) {
							loan = candidate;
						}
					}
				}
			}
		}
		assert (loan != null);
		var original = loan.buffers[0];
		loan.buffers.remove_index (0);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("record argument");
		}
		assert (refused);
		loan.buffers.insert (0, original);
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void borrowed_record_callable_ssa_owner() {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("borrowed-callable-records"));
		var prior = WeakRef (predecessor.functions[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaVerifier.verify (program);
		SsaBlock? site = null;
		SsaHeapOwnerEvent? original = null;
		int position = -1;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var call = block.instructions[i] as SsaFunctionValueCall;
					if (call == null) {
						continue;
					}
					foreach (var group in call.struct_arguments) {
						var loan = group as SsaStructBorrowArgument;
						if (loan == null || loan.owners.length == 0) {
							continue;
						}
						for (int j = i - 1; j >= 0; j--) {
							var read = block.instructions[j] as SsaHeapOwnerEvent;
							if (read == null || read.action != SsaHeapOwnerAction.READ) {
								break;
							}
							if (read.owner == loan.owners[0] && read.effect == null) {
								site = block;
								position = j;
								original = read;
							}
						}
					}
				}
			}
		}
		assert (site != null && position >= 0 && original != null);
		site.instructions.remove_index (position);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("exact live owner READ");
		}
		assert (refused);
		site.instructions.insert (position, original);
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void borrowed_record_callable_native_mode() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("borrowed-callable-records")));
		var prior = WeakRef (predecessor.functions[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		NativeAbiVerifier.verify (program);
		NativeFunctionValuePlan? invocation = null;
		int position = -1;
		foreach (var call in program.function_values) {
			for (int g = 0; g < call.signature.record_parameters.length; g++) {
				if (call.signature.record_parameters[g].mode == NativeStructValueMode.BORROW_VALUE) {
					invocation = call;
					position = g;
				}
			}
		}
		assert (invocation != null && position >= 0);
		var signature = invocation.signature.record_parameters[position];
		var actual = invocation.record_arguments[position];
		invocation.signature.record_parameters[position] = new NativeCallableRecordParameter (signature.source_ordinal, signature.first_leaf, signature.record_name, signature.leaves, NativeStructValueMode.MOVE_VALUE);
		invocation.record_arguments[position] = new NativeCallableRecordParameter (actual.source_ordinal, actual.first_leaf, actual.record_name, actual.leaves, NativeStructValueMode.MOVE_VALUE);
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		invocation.signature.record_parameters[position] = signature;
		invocation.record_arguments[position] = actual;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void symbolic_callable_lexical_result() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("symbolic-lexical.astra",
			"T apply<T>(Fn<T,T> code,T value){return code(value);}int main(){return 0;}"));
		assert (parsed.diagnostic == null);
		var checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.diagnostic == null);
		CheckedProgram? predecessor = checked.program;
		checked = null;
		var prior = WeakRef (predecessor.functions[0]);
		var program = CoreBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CoreVerifier.verify (program);
		CoreParameter? channel = null;
		foreach (var function in program.generic_functions) {
			if (function.name == "apply") {
				channel = function.parameters[0];
			}
		}
		assert (channel != null);
		var original = (FunctionValueType) channel.semantic_type;
		channel.semantic_type = new FunctionValueType (new TypeParameterType ("Output"), original.parameter_types);
		bool refused = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("unresolved or nonlexical type parameter");
		}
		assert (refused);
		channel.semantic_type = original;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void symbolic_consuming_channel_core() {
	try {
		CheckedProgram? predecessor = check ("symbolic-consuming-callables");
		var prior = WeakRef (predecessor.functions[0]);
		var program = CoreBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CoreVerifier.verify (program);
		CoreFunctionValueCall? invocation = null;
		foreach (var function in program.generic_functions) {
			if (function.name != "apply_consuming") {
				continue;
			}
			foreach (var statement in function.body.statements) {
				var returned = statement as CoreReturn;
				if (returned != null) {
					invocation = returned.value as CoreFunctionValueCall;
				}
			}
		}
		assert (invocation != null && invocation.channel_parameters[0].pointer_contract == PointerParameterContract.OWNED_TRANSFER);
		var original = invocation.channel_parameters[0];
		invocation.channel_parameters[0] = new CoreParameter (original.span, original.name_span, original.name, original.semantic_type, original.ordinal);
		bool refused = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("channel declaration differs from carried signature");
		}
		assert (refused);
		invocation.channel_parameters[0] = original;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void symbolic_consuming_heap_core() {
	try {
		CheckedProgram? predecessor = check ("symbolic-consuming-callables");
		var prior = WeakRef (predecessor.functions[0]);
		var program = CoreGenericMonomorphizer.build (CoreBuilder.build (predecessor));
		predecessor = null;
		assert (prior.get () == null);
		CoreVerifier.verify_concrete (program);
		CoreFunctionValueCall? invocation = null;
		foreach (var function in program.functions) {
			if (function.generic_instance == null || function.generic_instance.origin.name != "apply_consuming" || !(function.parameters[1].semantic_type is ClassType)) {
				continue;
			}
			foreach (var statement in function.body.statements) {
				var returned = statement as CoreReturn;
				if (returned != null) {
					invocation = returned.value as CoreFunctionValueCall;
				}
			}
		}
		assert (invocation != null && invocation.channel_parameters[0].heap_object);
		invocation.channel_parameters[0].heap_object = false;
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("channel declaration differs from carried signature");
		}
		assert (refused);
		invocation.channel_parameters[0].heap_object = true;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void symbolic_owned_result_core() {
	try {
		CheckedProgram? predecessor = check ("symbolic-owned-callable-results");
		var prior = WeakRef (predecessor.functions[0]);
		var program = CoreBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CoreVerifier.verify (program);
		CoreCleanupContract? foreign = null;
		foreach (var handle in program.handles) {
			if (handle.name == "Other") {
				foreign = handle.cleanup;
			}
		}
		assert (foreign != null);
		int tested = 0;
		foreach (var function in program.generic_functions) {
			if (function.name != "invoke_factory" && function.name != "invoke_closure_factory" && function.name != "invoke_checked_factory") {
				continue;
			}
			var original = function.body.statements[0] as CoreOwnershipReturn;
			assert (original != null && original.producer is CoreInvocation && original.semantic_type is TypeParameterType);
			for (int mutant = 0; mutant < 2; mutant++) {
				CoreCleanupContract? cleanup = mutant == 0 ? null : foreign;
				CoreValue forged;
				var code = original.producer as CoreFunctionValueCall;
				if (code != null) {
					forged = new CoreFunctionValueCall (code.span, (FunctionValueType) code.callee.semantic_type, code.callee, code.arguments, cleanup);
				} else {
					var closure = (CoreClosureCall) original.producer;
					forged = new CoreClosureCall (closure.span, (ClosureHandleType) closure.callee.semantic_type, closure.callee, closure.arguments, cleanup);
				}
				function.body.statements[0] = new CoreOwnershipReturn (original.span, original.semantic_type, original.cleanup, null, forged);
				bool refused = false;
				try {
					CoreVerifier.verify (program);
				} catch (CoreError error) {
					Test.message ("%s", error.message);
					refused = error.message.contains ("exact acquisition and declared cleanup");
				}
				assert (refused);
				function.body.statements[0] = original;
				CoreVerifier.verify (program);
			}
			tested++;
		}
		assert (tested == 3);
		var concrete = CoreGenericMonomorphizer.build (program);
		CoreVerifier.verify_concrete (concrete);
		int closed = 0;
		foreach (var function in concrete.functions) {
			if (function.generic_instance == null || function.generic_instance.origin.name != "invoke_factory") {
				continue;
			}
			var original = function.body.statements[0] as CoreOwnershipReturn;
			var call = original == null ? null : original.producer as CoreFunctionValueCall;
			assert (call != null && call.owned_cleanup == function.owned_cleanup && !(call.semantic_type is TypeParameterType));
			var forged = new CoreFunctionValueCall (call.span, (FunctionValueType) call.callee.semantic_type, call.callee, call.arguments, null);
			function.body.statements[0] = new CoreOwnershipReturn (original.span, original.semantic_type, original.cleanup, null, forged);
			bool refused = false;
			try {
				CoreVerifier.verify_concrete (concrete);
			} catch (CoreError error) {
				Test.message ("%s", error.message);
				refused = error.message.contains ("exact acquisition and declared cleanup");
			}
			assert (refused);
			function.body.statements[0] = original;
			CoreVerifier.verify_concrete (concrete);
			closed++;
		}
		assert (closed == 2);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void symbolic_owned_result_cfg() {
	try {
		CoreProgram? predecessor = core ("symbolic-owned-callable-results");
		var prior = WeakRef (predecessor.functions[0]);
		var program = CfgBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CfgVerifier.verify (program);
		CfgBlock? site = null;
		CfgOwnershipReturnInstruction? original = null;
		int position = -1;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var capture = block.instructions[i] as CfgOwnershipReturnInstruction;
					if (capture != null && capture.result.source == null && capture.result.producer is CfgEvaluatedValue && capture.result.semantic_type.get_type () == typeof (HandleType)) {
						site = block;
						original = capture;
						position = i;
						break;
					}
				}
			}
		}
		assert (site != null && original != null && position >= 0);
		site.instructions.remove_index (position);
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		site.instructions.insert (position, original);
		CfgVerifier.verify (program);
		site.instructions.insert (position, original);
		refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		site.instructions.remove_index (position);
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void symbolic_owned_result_ssa(bool checked_closure) {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("symbolic-owned-callable-results"));
		var prior = WeakRef (predecessor.functions[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaVerifier.verify (program);
		SsaBlock? site = null;
		SsaHeapOwnerEvent? original = null;
		int position = -1;
		foreach (var function in program.functions) {
			SsaValue? producer = null;
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					if (checked_closure) {
						var call = instruction as SsaClosureCall;
						if (call != null && call.owned_cleanup != null && ((ClosureHandleType) call.callee.semantic_type).throws_type != null) {
							producer = call.owned_result_value ();
						}
					} else {
						var call = instruction as SsaFunctionValueCall;
						if (call != null && call.owned_cleanup != null) {
							producer = call.owned_result_value ();
						}
					}
				}
			}
			if (producer == null) {
				continue;
			}
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var event = block.instructions[i] as SsaHeapOwnerEvent;
					if (event != null && event.owner == null && event.action == SsaHeapOwnerAction.RETURN && event.value == producer) {
						site = block;
						original = event;
						position = i;
						break;
					}
				}
			}
		}
		assert (site != null && original != null && position >= 0);
		site.instructions.remove_index (position);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("exactly one guarded producer acquisition");
		}
		assert (refused);
		site.instructions.insert (position, original);
		SsaVerifier.verify (program);
		site.instructions.insert (position, new SsaHeapOwnerEvent (original.span, null, SsaHeapOwnerAction.RETURN, original.value, original.effect));
		refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("exactly one guarded producer acquisition");
		}
		assert (refused);
		site.instructions.remove_index (position);
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void symbolic_closed_owner_native() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("symbolic-owned-callable-results")));
		var prior = WeakRef (predecessor.classes[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		NativeAbiVerifier.verify (program);
		NativeClassPlan? owner = null;
		foreach (var candidate in program.classes) {
			var key = candidate.generic_instance;
			if (key == null || key.declared_structure.argument_count != 2 || key.definition.structure.constraint_count != 1) {
				continue;
			}
			var argument = key.declared_structure.argument (0);
			if (argument.class_ordinal >= 0 && program.classes[argument.class_ordinal].generic_instance != null) {
				owner = candidate;
			}
		}
		assert (owner != null);
		var original = owner.generic_instance;
		var declaration = original.declared_structure;
		var argument = declaration.argument (0);
		assert (argument.valid (program) && argument.satisfies (Astra.GenericCapabilityIdentity.OWNABLE, program));
		assert (!argument.satisfies (Astra.GenericCapabilityIdentity.EQ, program) && !argument.satisfies (Astra.GenericCapabilityIdentity.NUMERIC, program));
		NativeDeclaredType[] fields = {};
		for (int f = 0; f < declaration.field_count; f++) {
			fields += declaration.field_type (f);
		}
		NativeDeclaredMember[] members = {};
		for (int m = 0; m < declaration.member_count; m++) {
			members += declaration.member (m);
		}
		var forged = new NativeDeclaredClass (original.definition,
			new NativeDeclaredType[] { new NativeDeclaredType ("bool", new NativeScalarAbiType (NativeScalarType.B1)), declaration.argument (1) }, fields, members);
		var targets = new int[original.member_count];
		for (int m = 0; m < targets.length; m++) {
			targets[m] = original.member_target (m);
		}
		var properties = new int[original.property_count];
		for (int p = 0; p < properties.length; p++) {
			properties[p] = original.property_target (p);
		}
		owner.generic_instance = new NativeExactClassInstance.declared (original.definition, forged, targets, properties);
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("Class substituted capability constraint");
		}
		assert (refused);
		owner.generic_instance = original;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void generic_class_result_core() {
	try {
		CheckedProgram? checked = check ("generic-class-result-origins");
		var source = WeakRef (checked.generic_functions[0].definition);
		// Deliberately poison the disposable Source summary. Core must derive
		// its equation from its own producer/transfer graph, independently.
		foreach (var function in checked.generic_functions) {
			function.definition.result_origins = new GenericResultOrigins (GenericResultOrigins.CALLER);
		}
		CoreProgram? symbolic = CoreBuilder.build (checked);
		checked = null;
		assert (source.get () == null);
		CoreVerifier.verify (symbolic);
		HashTable<CoreGenericFunction, GenericResultOrigins>? equations = CoreGenericResultOrigins.derive (symbolic);
		int independent = 0;
		foreach (var function in symbolic.generic_functions) {
			var equation = equations.lookup (function);
			if (function.return_type is ClassType) {
				assert (function.heap_result);
				continue;
			}
			if (function.name == "preserve_result") {
				assert (equation.domains == 0 && equation.input_count == 1 && equation.input (0) == 0);
			} else {
				assert (equation.domains == GenericResultOrigins.HEAP && equation.input_count == 0);
				independent++;
			}
		}
		assert (independent == 5);
		equations = null;
		var predecessor = WeakRef (symbolic.generic_functions[0]);
		var program = CoreGenericMonomorphizer.build (symbolic);
		symbolic = null;
		assert (predecessor.get () == null);
		CoreVerifier.verify_concrete (program);
		CoreFunction? producer = null;
		int input_domains = 0;
		foreach (var function in program.functions) {
			var key = function.generic_instance;
			if (key == null) {
				continue;
			}
			if (key.origin.name == "preserve_result") {
				assert (key.has_storage_domain (function));
				input_domains |= function.heap_result ? 2 : 1;
			}
			if (key.origin.name == "originate_result") {
				producer = function;
			}
		}
		assert (input_domains == 3 && producer != null && producer.heap_result && producer.generic_instance.heap_result && producer.generic_instance.heap_owned_parameter == -1);
		producer.heap_result = false;
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("canonical consuming storage domain");
		}
		assert (refused);
		producer.heap_result = true;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void generic_class_result_cleanup_core() {
	try {
		CoreProgram? symbolic = CoreBuilder.build (check ("generic-class-result-origins"));
		var predecessor = WeakRef (symbolic.generic_functions[0]);
		var program = CoreGenericMonomorphizer.build (symbolic);
		symbolic = null;
		assert (predecessor.get () == null);
		CoreVerifier.verify_concrete (program);
		CoreFunction? producer = null;
		CoreCleanupContract? wrong = null;
		foreach (var function in program.functions) {
			if (function.generic_instance == null || function.generic_instance.origin.name != "originate_result") {
				continue;
			}
			foreach (var cleanup in program.cleanups) {
				if (cleanup.is_object && !cleanup.is_heap_object && cleanup.object_class.semantic_type == function.return_type) {
					producer = function;
					wrong = cleanup;
				}
			}
		}
		assert (producer != null && wrong != null);
		var original = producer.body.statements[0] as CoreOwnershipReturn;
		var call = original == null ? null : original.producer as CoreFunctionValueCall;
		assert (call != null && call.owned_cleanup.is_heap_object && wrong != call.owned_cleanup);
		var forged = new CoreFunctionValueCall (call.span, (FunctionValueType) call.callee.semantic_type, call.callee, call.arguments, wrong);
		producer.body.statements[0] = new CoreOwnershipReturn (original.span, original.semantic_type, original.cleanup, null, forged, original.provenance);
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("indirect Class forwarding requires the exact heap result");
		}
		assert (refused);
		producer.body.statements[0] = original;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void generic_class_result_cfg() {
	try {
		CoreProgram? predecessor = core ("generic-class-result-origins");
		var prior = WeakRef (predecessor.functions[0]);
		var program = CfgBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CfgVerifier.verify (program);
		CfgBlock? site = null;
		CfgOwnershipReturnInstruction? original = null;
		int position = -1;
		foreach (var function in program.functions) {
			if (!function.heap_result) {
				continue;
			}
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var capture = block.instructions[i] as CfgOwnershipReturnInstruction;
					if (capture != null && capture.result.source == null && capture.result.producer is CfgEvaluatedValue) {
						site = block;
						original = capture;
						position = i;
					}
				}
			}
		}
		assert (site != null && original != null && position >= 0);
		site.instructions.remove_index (position);
		bool refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		site.instructions.insert (position, original);
		CfgVerifier.verify (program);
		site.instructions.insert (position, original);
		refused = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		site.instructions.remove_index (position);
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void generic_class_result_ssa(bool checked_closure) {
	try {
		CfgProgram? predecessor = CfgBuilder.build (core ("generic-class-result-origins"));
		var prior = WeakRef (predecessor.functions[0]);
		var program = SsaBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		SsaVerifier.verify (program);
		SsaBlock? site = null;
		SsaHeapOwnerEvent? original = null;
		int position = -1;
		foreach (var function in program.functions) {
			SsaValue? produced = null;
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					if (checked_closure) {
						var invocation = instruction as SsaClosureCall;
						if (invocation != null && invocation.owned_cleanup != null && ((ClosureHandleType) invocation.callee.semantic_type).throws_type != null) {
							produced = invocation.owned_result_value ();
						}
					} else {
						var invocation = instruction as SsaFunctionValueCall;
						if (invocation != null && invocation.owned_cleanup != null) {
							produced = invocation.owned_result_value ();
						}
					}
				}
			}
			if (produced == null || !(produced.semantic_type is ClassType)) {
				continue;
			}
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var event = block.instructions[i] as SsaHeapOwnerEvent;
					if (event != null && event.owner == null && event.action == SsaHeapOwnerAction.RETURN && event.value == produced) {
						site = block;
						original = event;
						position = i;
					}
				}
			}
		}
		assert (site != null && original != null && position >= 0);
		site.instructions.remove_index (position);
		bool refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		site.instructions.insert (position, original);
		SsaVerifier.verify (program);
		site.instructions.insert (position, new SsaHeapOwnerEvent (original.span, null, SsaHeapOwnerAction.RETURN, original.value, original.effect));
		refused = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		site.instructions.remove_index (position);
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void generic_class_result_native() {
	try {
		SsaProgram? predecessor = SsaBuilder.build (CfgBuilder.build (core ("generic-class-result-origins")));
		var prior = WeakRef (predecessor.functions[0]);
		var program = NativeAbiBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		NativeAbiVerifier.verify (program);
		NativeSignature? signature = null;
		foreach (var function in program.functions) {
			if (function.name.has_prefix ("astra.gen.") && function.signature.heap_result != null) {
				signature = function.signature;
			}
		}
		assert (signature != null);
		var original = signature.heap_result;
		signature.heap_result = new NativeObjectOriginPlan (original.class_ordinal, original.class_name, false);
		bool refused = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("storage origin");
		}
		assert (refused);
		signature.heap_result = original;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void open_class_header_result() {
	try {
		CheckedProgram? predecessor = check ("open-class-members");
		assert (predecessor.class_applications.length > 0);
		var prior = WeakRef (predecessor.class_applications[0]);
		var program = CoreBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CoreVerifier.verify (program);
		var header = program.class_applications[0].methods[0];
		var original = header.return_type;
		header.return_type = new TypeParameterType (((TypeParameterType) original).name);
		bool refused = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("immutable declared type patterns");
		}
		assert (refused);
		header.return_type = original;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void open_class_header_receiver() {
	try {
		CheckedProgram? predecessor = check ("open-class-members");
		var prior = WeakRef (predecessor.class_applications[0]);
		var program = CoreBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CoreVerifier.verify (program);
		var owner = program.class_applications[0];
		var original = owner.application_receiver;
		owner.application_receiver = new ReceiverType (owner.semantic_type, ReceiverMode.INITIALIZING);
		bool refused = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("exact symbolic declaration and live receiver");
		}
		assert (refused);
		owner.application_receiver = original;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void open_class_lazy_contract() {
	try {
		CheckedProgram? predecessor = check ("open-class-lazy");
		var prior = WeakRef (predecessor.class_applications[0]);
		var program = CoreBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CoreVerifier.verify (program);
		var property = program.class_applications[0].properties[0];
		assert (property.is_lazy);
		property.is_lazy = false;
		bool refused = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("exact declared accessor signatures");
		}
		assert (refused);
		property.is_lazy = true;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void open_class_owned_field() {
	try {
		CheckedProgram? predecessor = check ("open-class-owning-members");
		var prior = WeakRef (predecessor.class_applications[0]);
		var program = CoreBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CoreVerifier.verify (program);
		CoreStructField? field = null;
		foreach (var owner in program.class_applications) {
			foreach (var candidate in owner.fields) {
				if (candidate.owned_cleanup != null && candidate.owned_cleanup.type_parameter != null) {
					field = candidate;
				}
			}
		}
		assert (field != null);
		var original = field.owned_cleanup;
		field.owned_cleanup = null;
		bool refused = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("exact declared ownership responsibility");
		}
		assert (refused);
		field.owned_cleanup = original;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void open_class_foreign_field_cleanup() {
	try {
		CheckedProgram? predecessor = check ("open-class-owning-members");
		var prior = WeakRef (predecessor.class_applications[0]);
		var program = CoreBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CoreVerifier.verify (program);
		CoreStructField? field = null;
		CoreCleanupContract? foreign = null;
		foreach (var owner in program.class_applications) {
			foreach (var candidate in owner.fields) {
				if (candidate.owned_cleanup == null || candidate.owned_cleanup.type_parameter == null) {
					continue;
				}
				if (field == null) {
					field = candidate;
				} else if (field.semantic_type != candidate.semantic_type) {
					foreign = candidate.owned_cleanup;
				}
			}
		}
		assert (field != null && foreign != null);
		var original = field.owned_cleanup;
		field.owned_cleanup = foreign;
		bool refused = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("exact declared ownership responsibility");
		}
		assert (refused);
		field.owned_cleanup = original;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void open_class_callback_mode() {
	try {
		CheckedProgram? predecessor = check ("open-class-owning-members");
		var prior = WeakRef (predecessor.class_applications[0]);
		var program = CoreBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CoreVerifier.verify (program);
		var header = program.class_applications[0].methods[0];
		var parameter = header.parameters[0];
		var original = parameter.semantic_type as FunctionValueType;
		assert (original != null && original.parameter_contract (0) == PointerParameterContract.BORROWED_NOESCAPE);
		var modes = new GenericArray<PointerParameterContract> ();
		modes.add (PointerParameterContract.OWNED_TRANSFER);
		parameter.semantic_type = new FunctionValueType (original.result_type, original.parameter_types, modes);
		bool refused = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("immutable declared type patterns");
		}
		assert (refused);
		parameter.semantic_type = original;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void open_method_foreign_scope() {
	try {
		CheckedProgram? predecessor = check ("open-class-generic-methods");
		assert (predecessor.method_applications.length > 0);
		var prior = WeakRef (predecessor.method_applications[0]);
		var program = CoreBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CoreVerifier.verify (program);
		var header = program.method_applications[0];
		var original = header.application_scope;
		foreach (var function in program.generic_functions) {
			if (function.identity != original) {
				header.application_scope = function.identity;
				break;
			}
		}
		assert (header.application_scope != original);
		bool refused = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("nonlexical type parameter");
		}
		assert (refused);
		header.application_scope = original;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void open_method_ordered_arguments() {
	try {
		CheckedProgram? predecessor = check ("open-class-generic-methods");
		var prior = WeakRef (predecessor.method_applications[0]);
		var program = CoreBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CoreVerifier.verify (program);
		CoreMethod? header = null;
		foreach (var application in program.method_applications) {
			if (application.generic_method_instance.arguments.length == 2) {
				header = application;
				break;
			}
		}
		assert (header != null);
		var original = header.generic_method_instance;
		var reversed = new GenericArray<SemanticType> ();
		reversed.add (original.arguments.at (1));
		reversed.add (original.arguments.at (0));
		header.generic_method_instance = new ClassMethodInstance.application (original.class_instance, original.member, new TypeArgumentVector (reversed));
		bool refused = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("exact bodyless declared signature");
		}
		assert (refused);
		header.generic_method_instance = original;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void open_method_owned_input_origin() {
	try {
		var program = core ("open-class-method-owners");
		CoreVerifier.verify_concrete (program);
		CoreParameter? input = null;
		foreach (var owner in program.classes) {
			foreach (var method in owner.methods) {
				if (method.generic_method_instance == null || method.parameters.length == 0) {
					continue;
				}
				var parameter = method.parameters[0];
				if (parameter.semantic_type is ClassType && parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER && parameter.heap_object) {
					input = parameter;
				}
			}
		}
		assert (input != null);
		input.heap_object = false;
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		input.heap_object = true;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private CoreMethod copy_method_header(CoreMethod original, CoreCleanupContract? cleanup) {
	var copy = new CoreMethod (original.span, original.name_span, original.name, original.declaring_type, original.receiver,
		original.method_ordinal, original.member_ordinal, original.return_type, original.parameters, original.locals, original.body, cleanup);
	copy.generic_method_instance = original.generic_method_instance;
	copy.application_scope = original.application_scope;
	copy.throws_type = original.throws_type;
	copy.dispatch_kind = original.dispatch_kind;
	copy.virtual_slot = original.virtual_slot;
	copy.heap_result = original.heap_result;
	return copy;
}

private void open_method_result_cleanup() {
	try {
		CheckedProgram? predecessor = check ("open-class-method-resource-results");
		var prior = WeakRef (predecessor.method_applications[0]);
		var program = CoreBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CoreVerifier.verify (program);
		var header = program.method_applications[0];
		assert (header.owned_cleanup != null);
		program.method_applications[0] = copy_method_header (header, null);
		bool refused = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("exact declared responsibility");
		}
		assert (refused);
		program.method_applications[0] = header;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void open_method_foreign_result_cleanup() {
	try {
		CheckedProgram? predecessor = check ("open-class-method-resource-results");
		var prior = WeakRef (predecessor.method_applications[0]);
		var program = CoreBuilder.build (predecessor);
		predecessor = null;
		assert (prior.get () == null);
		CoreVerifier.verify (program);
		var header = program.method_applications[0];
		assert (header.owned_cleanup != null);
		CoreCleanupContract? foreign = null;
		foreach (var other in program.method_applications) {
			if (other.owned_cleanup != null && other.return_type != header.return_type) {
				foreign = other.owned_cleanup;
				break;
			}
		}
		assert (foreign != null && foreign.type_parameter != null);
		program.method_applications[0] = copy_method_header (header, foreign);
		bool refused = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = error.message.contains ("exact declared responsibility");
		}
		assert (refused);
		program.method_applications[0] = header;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void record_method_heap_result() {
	try {
		var program = core ("record-method-result-origins");
		CoreVerifier.verify_concrete (program);
		CoreMethod? factory = null;
		foreach (var owner in program.classes) {
			foreach (var method in owner.methods) {
				if (method.generic_method_instance != null && method.heap_result) {
					factory = method;
				}
			}
		}
		assert (factory != null);
		factory.heap_result = false;
		bool refused = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			refused = true;
		}
		assert (refused);
		factory.heap_result = true;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/declared-generics/core-record-producer-heap-result-after-specialization", record_method_heap_result);
	Test.add_func ("/declared-generics/core-open-method-result-cleanup-after-destroyed-source", open_method_result_cleanup);
	Test.add_func ("/declared-generics/core-open-method-foreign-result-cleanup-after-destroyed-source", open_method_foreign_result_cleanup);
	Test.add_func ("/declared-generics/core-open-method-owned-input-origin-after-specialization", open_method_owned_input_origin);
	Test.add_func ("/declared-generics/core-open-method-foreign-scope-after-destroyed-source", open_method_foreign_scope);
	Test.add_func ("/declared-generics/core-open-method-ordered-arguments-after-destroyed-source", open_method_ordered_arguments);
	Test.add_func ("/declared-generics/core-open-Class-callback-mode-after-destroyed-source", open_class_callback_mode);
	Test.add_func ("/declared-generics/core-open-Class-owned-field-after-destroyed-source", open_class_owned_field);
	Test.add_func ("/declared-generics/core-open-Class-foreign-field-cleanup-after-destroyed-source", open_class_foreign_field_cleanup);
	Test.add_func ("/declared-generics/destroyed-predecessor-graphs", independent);
	Test.add_func ("/declared-generics/core-field-substitution", core_substitution);
	Test.add_func ("/declared-generics/cfg-incomplete-record-field", cfg_initialization);
	Test.add_func ("/declared-generics/ssa-incomplete-record-field", ssa_initialization);
	Test.add_func ("/declared-generics/native-member-channel", native_member);
	Test.add_func ("/declared-generics/inline-record-ssa-leaf-order-and-owner", inline_record_ssa);
	Test.add_func ("/declared-generics/inline-record-native-responsibility", inline_record_native);
	Test.add_func ("/declared-generics/projected-record-cfg-complete-transfer", projected_record_cfg);
	Test.add_func ("/declared-generics/projected-record-ssa-original-leaves", projected_record_ssa);
	Test.add_func ("/declared-generics/projected-buffer-ssa-once-only-transfer", projected_buffer_ssa);
	Test.add_func ("/declared-generics/method-tuple-core-later-argument", method_tuple_core);
	Test.add_func ("/declared-generics/method-tuple-native-phantom-argument", method_tuple_native);
	Test.add_func ("/declared-generics/native-substituted-constraint", substituted_constraint_native);
	Test.add_func ("/declared-generics/native-phantom-class-argument", phantom_class_native);
	Test.add_func ("/declared-generics/native-deferred-parameter-origin", deferred_native_origin);
	Test.add_func ("/declared-generics/core-nested-receiver-ancestor-loan", nested_receiver_core);
	Test.add_func ("/declared-generics/cfg-nested-receiver-ancestor-loan", nested_receiver_cfg);
	Test.add_func ("/declared-generics/ssa-nested-receiver-ancestor-loan", nested_receiver_ssa);
	Test.add_func ("/declared-generics/native-exact-phantom-constraint", exact_bound_native);
	Test.add_func ("/declared-generics/core-multiple-slot-cleanup", multiple_slots_core);
	Test.add_func ("/declared-generics/cfg-multiple-slot-retirement", multiple_slots_cfg);
	Test.add_func ("/declared-generics/ssa-multiple-slot-retirement", multiple_slots_ssa);
	Test.add_func ("/declared-generics/native-closed-closure-environment", closed_environment_native);
	Test.add_func ("/declared-generics/native-closed-generic-interface-target", closed_dispatch_native);
	Test.add_func ("/declared-generics/core-owned-generic-async-capture", async_capture_core);
	Test.add_func ("/declared-generics/cfg-owned-generic-async-capture", async_capture_cfg);
	Test.add_func ("/declared-generics/ssa-owned-generic-async-capture", async_capture_ssa);
	Test.add_func ("/declared-generics/native-owned-generic-async-capture", async_capture_native);
	Test.add_func ("/declared-generics/core-copied-record-callable", record_callable_core);
	Test.add_func ("/declared-generics/cfg-copied-record-callable", record_callable_cfg);
	Test.add_func ("/declared-generics/ssa-copied-record-callable", record_callable_ssa);
	Test.add_func ("/declared-generics/native-copied-record-callable", record_callable_native);
	Test.add_func ("/declared-generics/core-generic-callable-field", generic_callable_field_core);
	Test.add_func ("/declared-generics/native-generic-callable-field", generic_callable_field_native);
	Test.add_func ("/declared-generics/core-indexed-method-inspection", indexed_inspector_core);
	Test.add_func ("/declared-generics/cfg-indexed-method-inspection", indexed_inspector_cfg);
	Test.add_func ("/declared-generics/ssa-indexed-method-inspection", indexed_inspector_ssa);
	Test.add_func ("/declared-generics/core-lexical-generic-origin", lexical_origin_core);
	Test.add_func ("/declared-generics/cfg-lexical-generic-origin", lexical_origin_cfg);
	Test.add_func ("/declared-generics/ssa-lexical-generic-origin", lexical_origin_ssa);
	Test.add_func ("/declared-generics/native-lexical-generic-origin", lexical_origin_native);
	Test.add_func ("/declared-generics/core-record-projection-path", record_projection_core);
	Test.add_func ("/declared-generics/cfg-record-projection-complete-capture", record_projection_cfg);
	Test.add_func ("/declared-generics/ssa-record-projection-bounded-consumer", record_projection_ssa);
	Test.add_func ("/declared-generics/native-record-projection-nominal-result", record_projection_native);
	Test.add_func ("/declared-generics/native-boundary-origin-scope", native_boundary_origins);
	Test.add_func ("/declared-generics/core-open-record-scoped-contract", open_record_contracts);
	Test.add_func ("/declared-generics/open-record-destroyed-predecessors", open_record_lifetimes);
	Test.add_func ("/declared-generics/core-closed-class-owner-origin", closed_class_storage);
	Test.add_func ("/declared-generics/ssa-native-closed-class-nominal-loan", closed_class_nominal_calls);
	Test.add_func ("/declared-generics/core-owning-record-observation", record_observation_core);
	Test.add_func ("/declared-generics/cfg-owning-record-observation", record_observation_cfg);
	Test.add_func ("/declared-generics/ssa-owning-record-observation", record_observation_ssa);
	Test.add_func ("/declared-generics/native-owning-record-observation", record_observation_native);
	Test.add_func ("/declared-generics/core-buffer-view-index-loan", buffer_view_core);
	Test.add_func ("/declared-generics/cfg-buffer-view-result-origin", buffer_view_cfg);
	Test.add_func ("/declared-generics/ssa-buffer-view-complete-pair", buffer_view_ssa);
	Test.add_func ("/declared-generics/native-buffer-view-complete-pair", buffer_view_native);
	Test.add_func ("/declared-generics/core-readonly-buffer-store", readonly_buffer_core);
	Test.add_func ("/declared-generics/cfg-readonly-buffer-store", readonly_buffer_cfg);
	Test.add_func ("/declared-generics/ssa-readonly-buffer-store", readonly_buffer_ssa);
	Test.add_func ("/declared-generics/core-borrowed-record-parameter-mode", borrowed_record_core);
	Test.add_func ("/declared-generics/core-borrowed-record-argument-overlap", borrowed_record_core_overlap);
	Test.add_func ("/declared-generics/cfg-borrowed-record-entry-and-argument", borrowed_record_cfg);
	Test.add_func ("/declared-generics/ssa-borrowed-record-entry-and-live-owner", borrowed_record_ssa);
	Test.add_func ("/declared-generics/native-borrowed-record-mode-and-cleanup", borrowed_record_native);
	Test.add_func ("/declared-generics/cfg-borrowed-record-argument-overlap", borrowed_record_cfg_overlap);
	Test.add_func ("/declared-generics/ssa-borrowed-record-buffer-pairs", borrowed_buffer_ssa);
	Test.add_func ("/declared-generics/native-borrowed-record-resource-identity", borrowed_buffer_native);
	Test.add_func ("/declared-generics/core-borrowed-getter-argument-overlap", borrowed_getter_core_overlap);
	Test.add_func ("/declared-generics/cfg-borrowed-getter-original-group", borrowed_getter_cfg);
	Test.add_func ("/declared-generics/ssa-borrowed-getter-original-group", borrowed_getter_ssa);
	Test.add_func ("/declared-generics/ssa-parameter-buffer-declared-path", parameter_buffer_path_ssa);
	Test.add_func ("/declared-generics/core-readonly-record-parameter-store", readonly_parameter_core);
	Test.add_func ("/declared-generics/cfg-readonly-record-parameter-store", readonly_parameter_cfg);
	Test.add_func ("/declared-generics/ssa-readonly-record-parameter-store", readonly_parameter_ssa);
	Test.add_func ("/declared-generics/core-callable-channel-mode", callable_channel_core);
	Test.add_func ("/declared-generics/cfg-callable-channel-declarations", callable_channel_cfg);
	Test.add_func ("/declared-generics/ssa-callable-original-operand", callable_channel_ssa_operand);
	Test.add_func ("/declared-generics/ssa-callable-original-live-owner", callable_channel_ssa_owner);
	Test.add_func ("/declared-generics/native-callable-nominal-borrowed-argument", callable_channel_native);
	Test.add_func ("/declared-generics/core-closure-channel-mode", closure_channel_core);
	Test.add_func ("/declared-generics/cfg-checked-closure-channel-declarations", closure_channel_cfg);
	Test.add_func ("/declared-generics/ssa-closure-complete-read-group", closure_channel_ssa);
	Test.add_func ("/declared-generics/ssa-callable-repeated-owner-read-count", repeated_callable_reads_ssa);
	Test.add_func ("/declared-generics/native-closure-borrowed-nominal-and-cleanup", closure_channel_native);
	Test.add_func ("/declared-generics/core-closure-copied-record-identity", closure_record_core);
	Test.add_func ("/declared-generics/cfg-closure-copied-record-groups", closure_record_cfg);
	Test.add_func ("/declared-generics/ssa-closure-copied-record-and-borrow-offset", closure_record_ssa);
	Test.add_func ("/declared-generics/native-closure-copied-record-nominal-and-bound-offset", closure_record_native);
	Test.add_func ("/declared-generics/core-callable-complete-parameter-inventory", callable_signature_inventory_core);
	Test.add_func ("/declared-generics/generic-record-callable-destroyed-stage-graphs", generic_record_callable_graphs);
	Test.add_func ("/declared-generics/core-generic-record-callable-nominal-arguments", generic_record_callable_nominal_core);
	Test.add_func ("/declared-generics/core-generic-record-indirect-argument-boundary", generic_record_callable_boundary_core);
	Test.add_func ("/declared-generics/native-generic-record-application-inventory-and-field", generic_record_callable_native);
	Test.add_func ("/declared-generics/core-class-type-only-argument-inventory", class_type_argument_core);
	Test.add_func ("/declared-generics/cfg-class-type-only-argument-inventory", class_type_argument_cfg);
	Test.add_func ("/declared-generics/ssa-class-type-only-argument-inventory", class_type_argument_ssa);
	Test.add_func ("/declared-generics/core-native-declaration-original-signature", native_declaration_core);
	Test.add_func ("/declared-generics/cfg-native-declaration-original-signature", native_declaration_cfg);
	Test.add_func ("/declared-generics/ssa-native-declaration-original-signature", native_declaration_ssa);
	Test.add_func ("/declared-generics/core-native-declaration-body-refusal", native_declaration_core_body);
	Test.add_func ("/declared-generics/cfg-native-declaration-body-refusal", native_declaration_cfg_body);
	Test.add_func ("/declared-generics/ssa-native-declaration-body-refusal", native_declaration_ssa_body);
	Test.add_func ("/declared-generics/native-property-result-contract-after-destroyed-stages", native_property_contracts);
	Test.add_func ("/declared-generics/native-imported-record-property-after-destroyed-ssa", native_record_property_binding);
	Test.add_func ("/declared-generics/core-imported-record-closed-inventory-after-destroyed-source", native_closed_record_inventory);
	Test.add_func ("/declared-generics/native-published-record-metadata-after-destroyed-ssa", native_published_record_metadata);
	Test.add_func ("/declared-generics/native-resource-cleanup-and-transfer-after-destroyed-ssa", native_resource_transport);
	Test.add_func ("/declared-generics/core-owned-callable-exact-channel-after-destroyed-source", owned_callable_core);
	Test.add_func ("/declared-generics/cfg-owned-callable-commit-after-destroyed-core", owned_callable_cfg);
	Test.add_func ("/declared-generics/ssa-owned-callable-transfer-after-destroyed-cfg", owned_callable_ssa);
	Test.add_func ("/declared-generics/native-owned-callable-cleanup-after-destroyed-ssa", owned_callable_native);
	Test.add_func ("/declared-generics/native-copied-callable-field-identity-after-destroyed-ssa", copied_callable_fields_native);
	Test.add_func ("/declared-generics/core-owned-Class-callable-heap-channel", owned_class_callable_core);
	Test.add_func ("/declared-generics/cfg-owned-Class-callable-heap-channel", owned_class_callable_cfg);
	Test.add_func ("/declared-generics/ssa-owned-Class-callable-heap-cleanup", owned_class_callable_ssa);
	Test.add_func ("/declared-generics/native-owned-Class-callable-heap-cleanup", owned_class_callable_native);
	Test.add_func ("/declared-generics/core-owning-record-callable-move-mode", owning_record_callable_core);
	Test.add_func ("/declared-generics/cfg-owning-record-callable-complete-commit", owning_record_callable_cfg);
	Test.add_func ("/declared-generics/ssa-owning-record-callable-complete-buffer-pair", owning_record_callable_ssa);
	Test.add_func ("/declared-generics/native-owning-record-callable-mode-and-buffer-role", owning_record_callable_native);
	Test.add_func ("/declared-generics/unused-owning-record-callable-type-roots", owning_record_callable_type_roots);
	Test.add_func ("/declared-generics/core-callable-owned-result-cleanup-after-destroyed-source", owned_callable_result_core);
	Test.add_func ("/declared-generics/cfg-callable-owned-result-acquisition-after-destroyed-core", owned_callable_result_cfg);
	Test.add_func ("/declared-generics/ssa-callable-owned-result-acquisition-after-destroyed-cfg", owned_callable_result_ssa);
	Test.add_func ("/declared-generics/ssa-checked-callable-owned-result-publication-after-destroyed-cfg", checked_callable_result_ssa);
	Test.add_func ("/declared-generics/native-callable-owned-result-cleanup-after-destroyed-ssa", owned_callable_result_native);
	Test.add_func ("/declared-generics/core-Class-result-code-allocation-origin", class_result_domain_core_proof);
	Test.add_func ("/declared-generics/cfg-Class-result-code-allocation-origin", class_result_domain_cfg_proof);
	Test.add_func ("/declared-generics/ssa-Class-result-code-allocation-origin", class_result_domain_ssa_proof);
	Test.add_func ("/declared-generics/native-Class-result-nominal-heap-cleanup", class_result_native_proof);
	Test.add_func ("/declared-generics/native-generic-Class-buffer-declaration-and-pair", class_result_buffer_native_proof);
	Test.add_func ("/declared-generics/core-callable-record-result-derived-mode", callable_record_result_core);
	Test.add_func ("/declared-generics/cfg-callable-record-result-complete-group", callable_record_result_cfg);
	Test.add_func ("/declared-generics/ssa-callable-record-result-complete-buffer-pair", callable_record_result_ssa);
	Test.add_func ("/declared-generics/ssa-checked-callable-record-result-guarded-publication", checked_callable_record_result_ssa);
	Test.add_func ("/declared-generics/native-callable-record-result-original-nominal-fields", callable_record_result_native);
	Test.add_func ("/declared-generics/native-callable-record-result-complete-acquisition", callable_record_result_native_acquisition);
	Test.add_func ("/declared-generics/native-callable-record-result-Class-field-declaration", callable_record_result_native_field);
	Test.add_func ("/declared-generics/core-borrowed-record-callable-exact-channel", borrowed_record_callable_core);
	Test.add_func ("/declared-generics/cfg-borrowed-record-callable-original-capture", borrowed_record_callable_cfg);
	Test.add_func ("/declared-generics/ssa-borrowed-record-callable-complete-buffer-views", borrowed_record_callable_ssa_buffers);
	Test.add_func ("/declared-generics/ssa-borrowed-record-callable-live-owner-READ", borrowed_record_callable_ssa_owner);
	Test.add_func ("/declared-generics/native-borrowed-record-callable-preserved-mode", borrowed_record_callable_native_mode);
	Test.add_func ("/declared-generics/core-symbolic-callable-result-lexical-authority", symbolic_callable_lexical_result);
	Test.add_func ("/declared-generics/core-symbolic-consuming-channel-after-destroyed-source", symbolic_consuming_channel_core);
	Test.add_func ("/declared-generics/core-symbolic-consuming-heap-after-specialization", symbolic_consuming_heap_core);
	Test.add_func ("/declared-generics/core-open-Class-header-result-after-destroyed-source", open_class_header_result);
	Test.add_func ("/declared-generics/core-open-Class-header-receiver-after-destroyed-source", open_class_header_receiver);
	Test.add_func ("/declared-generics/core-open-Class-lazy-contract-after-destroyed-source", open_class_lazy_contract);
	Test.add_func ("/declared-generics/core-symbolic-owned-callable-result-cleanup", symbolic_owned_result_core);
	Test.add_func ("/declared-generics/cfg-symbolic-owned-callable-result-capture", symbolic_owned_result_cfg);
	Test.add_func ("/declared-generics/ssa-symbolic-owned-callable-result-forward", () => { symbolic_owned_result_ssa (false);
	});
	Test.add_func ("/declared-generics/ssa-symbolic-owned-checked-result-forward", () => { symbolic_owned_result_ssa (true);
	});
	Test.add_func ("/declared-generics/native-closed-Class-Ownable-capability", symbolic_closed_owner_native);
	Test.add_func ("/declared-generics/core-Class-result-equation-without-Source-summary", generic_class_result_core);
	Test.add_func ("/declared-generics/core-Class-result-exact-heap-cleanup", generic_class_result_cleanup_core);
	Test.add_func ("/declared-generics/cfg-Class-result-unique-return-capture", generic_class_result_cfg);
	Test.add_func ("/declared-generics/ssa-Class-result-exact-forward", () => { generic_class_result_ssa (false);
	});
	Test.add_func ("/declared-generics/ssa-checked-Class-result-exact-forward", () => { generic_class_result_ssa (true);
	});
	Test.add_func ("/declared-generics/native-Class-result-allocation-origin", generic_class_result_native);
	Test.add_func ("/declared-generics/core-closed-instance-budget-after-destroyed-source", materialization_budget_independent);
	Test.add_func ("/declared-generics/core-type-depth-budget-after-destroyed-source", materialization_depth_independent);
	Test.add_func ("/declared-generics/core-expanding-call-after-destroyed-source-and-recovery", expanding_materialization_independent);
	Test.add_func ("/declared-generics/core-owned-exchange-expansion-after-destroyed-source-and-recovery", exchange_expansion_independent);
	Test.add_func ("/declared-generics/core-storage-vector-headers-after-destroyed-source", storage_vector_headers);
	Test.add_func ("/declared-generics/core-owned-Class-formal-and-borrowed-header-contracts", owned_class_formal_contracts);
	Test.add_func ("/declared-generics/core-reachable-storage-requirements-after-destroyed-source", storage_requirements_contracts);
	Test.add_func ("/declared-generics/core-Class-signature-result-origins-without-source", class_signature_origins_contracts);
	Test.add_func ("/declared-generics/core-member-result-projection-without-source-or-guessed-producer", member_wrapper_result_contracts);
	Test.add_func ("/declared-generics/core-fixed-and-constructed-member-result-projection", member_fixed_result_contracts);
	Test.add_func ("/declared-generics/core-dependent-fixed-Class-result-origins", dependent_fixed_result_contracts);
	Test.add_func ("/declared-generics/core-owner-local-chains-after-destroyed-source", owner_local_chains_core);
	Test.add_func ("/declared-generics/cfg-owner-local-incoming-root-after-destroyed-core", owner_local_chains_cfg);
	Test.add_func ("/declared-generics/ssa-owner-local-return-pointer-after-destroyed-cfg", owner_local_chains_ssa);
	Test.add_func ("/declared-generics/core-fresh-result-callee-roots-after-destroyed-source", fresh_result_core_roots);
	Test.add_func ("/declared-generics/cfg-fresh-result-operand-roots-after-destroyed-core", fresh_result_cfg_roots);
	Test.add_func ("/declared-generics/ssa-fresh-result-operand-roots-after-destroyed-cfg", fresh_result_ssa_roots);
	Test.add_func ("/declared-generics/core-historical-owner-local-producer-after-destroyed-source", historical_owner_call_producer);
	Test.add_func ("/declared-generics/cfg-fresh-result-transfer-backing-extent-after-destroyed-core", fresh_result_cfg_extent);
	Test.add_func ("/declared-generics/core-copied-inspection-rejects-observed-write-after-destroyed-source", copied_inspection_core);
	Test.add_func ("/declared-generics/cfg-copied-inspection-rejects-observed-write-after-destroyed-core", copied_inspection_cfg);
	Test.add_func ("/declared-generics/ssa-copied-inspection-rejects-observed-write-after-destroyed-cfg", copied_inspection_ssa);
	Test.add_func ("/declared-generics/core-callback-code-effects-after-destroyed-source", code_inspection_core);
	Test.add_func ("/declared-generics/cfg-callback-code-effects-after-destroyed-core", code_inspection_cfg);
	Test.add_func ("/declared-generics/ssa-callback-code-effects-after-destroyed-cfg", code_inspection_ssa);
	Test.add_func ("/declared-generics/core-callback-input-through-conversion-after-destroyed-source", code_input_core);
	Test.add_func ("/declared-generics/cfg-callback-input-after-destroyed-core", code_input_cfg);
	Test.add_func ("/declared-generics/ssa-callback-input-after-destroyed-cfg", code_input_ssa);
	Test.add_func ("/declared-generics/core-native-method-erased-argument-after-destroyed-source", native_method_key_core);
	Test.add_func ("/declared-generics/cfg-native-method-erased-argument-after-destroyed-core", native_method_key_cfg);
	Test.add_func ("/declared-generics/ssa-native-method-erased-argument-after-destroyed-cfg", native_method_key_ssa);
	Test.add_func ("/declared-generics/source-native-callback-required-input", native_callback_source);
	Test.add_func ("/declared-generics/core-native-callback-required-input-after-destroyed-source", native_callback_core_proof);
	Test.add_func ("/declared-generics/cfg-native-callback-required-input-after-destroyed-core", native_callback_cfg_proof);
	Test.add_func ("/declared-generics/ssa-native-callback-required-input-after-destroyed-cfg", native_callback_ssa_proof);
	Test.add_func ("/declared-generics/native-callback-input-immutable-after-destroyed-ssa", native_callback_detached_proof);

	Test.add_func ("/declared-generics/callback-analysis-releases-every-phase", callback_analysis_release);
	Test.add_func ("/declared-generics/ssa-native-owned-buffer-parameter-after-destroyed-cfg", native_buffer_parameter_ssa);
	Test.add_func ("/declared-generics/native-owned-buffer-parameter-after-destroyed-ssa", native_buffer_parameter_detached);
	Test.add_func ("/declared-generics/runtime-composition-provider-error-conflicts", runtime_composition_conflicts);
	Test.add_func ("/declared-generics/runtime-composition-after-destroyed-predecessors", runtime_composition_detached);
	Test.add_func ("/declared-generics/core-async-closure-owner-after-destroyed-source", async_closure_core_proof);
	Test.add_func ("/declared-generics/cfg-async-closure-owner-after-destroyed-core", async_closure_cfg_proof);
	Test.add_func ("/declared-generics/ssa-async-closure-owner-after-destroyed-cfg", async_closure_ssa_proof);
	Test.add_func ("/declared-generics/native-async-closure-owner-after-destroyed-ssa", async_closure_native_proof);
	Test.add_func ("/declared-generics/callback-iteration-preserves-readonly-context", callback_iteration_context);
	Test.add_func ("/declared-generics/source-native-callback-with-scope", native_callback_with_source);
	Test.add_func ("/declared-generics/core-native-callback-with-scope", native_callback_with_core_proof);
	Test.add_func ("/declared-generics/cfg-native-callback-with-scope-after-destroyed-core", native_callback_with_cfg_proof);
	Test.add_func ("/declared-generics/ssa-native-callback-with-scope-after-destroyed-cfg", native_callback_with_ssa_proof);

	Test.add_func ("/declared-generics/core-callback-library-map-cache-preconditions", callback_library_core);
	Test.add_func ("/declared-generics/cfg-callback-library-map-cache-preconditions", callback_library_cfg);

	Test.add_func ("/declared-generics/source-callback-library-map-cache-preconditions", callback_library_source);

	Test.add_func ("/declared-generics/core-callback-summary-after-destroyed-source", callback_summary_core);
	Test.add_func ("/declared-generics/cfg-callback-summary-after-destroyed-core", callback_summary_cfg);

	Test.add_func ("/declared-generics/source-callback-summary-independent-formals-and-recursion", callback_summary_source);

	Test.add_func ("/declared-generics/ssa-callback-library-map-cache-preconditions", callback_map_cache_preconditions);

	Test.add_func ("/declared-generics/ssa-callback-mandatory-preconditions-through-mutating-bookkeeping", callback_mandatory_preconditions);

	Test.add_func ("/declared-generics/ssa-callback-summary-independent-formals-and-recursion", callback_summary_formals);
	Test.add_func ("/declared-generics/ssa-callback-summary-independent-of-observed-callers", callback_summary_observed_callers);

	Test.add_func ("/declared-generics/core-native-readonly-after-destroyed-predecessor", native_readonly_contract_core);
	Test.add_func ("/declared-generics/cfg-native-readonly-after-destroyed-predecessor", native_readonly_contract_cfg);
	Test.add_func ("/declared-generics/ssa-native-readonly-after-destroyed-predecessor", native_readonly_contract_ssa);
	Test.add_func ("/declared-generics/native-readonly-detached-original-contract", native_readonly_detached);

	Test.add_func ("/declared-generics/core-native-task-runtime-after-destroyed-predecessor", native_task_contract_core);
	Test.add_func ("/declared-generics/cfg-native-task-runtime-after-destroyed-predecessor", native_task_contract_cfg);
	Test.add_func ("/declared-generics/ssa-native-task-runtime-after-destroyed-predecessor", native_task_contract_ssa);
	Test.add_func ("/declared-generics/native-task-detached-factory-and-frame-inventory", native_task_detached_contract);
	Test.add_func ("/declared-generics/async-generic-record-frame-nominal-identity", async_record_nominal_frame);
	Test.add_func ("/declared-generics/core-native-interface-imported-implementation-signature", native_interface_signature_core);
	Test.add_func ("/declared-generics/cfg-native-interface-imported-implementation-signature", native_interface_signature_cfg);
	Test.add_func ("/declared-generics/ssa-native-interface-imported-implementation-signature", native_interface_signature_ssa);
	Test.add_func ("/declared-generics/core-native-exception-bound-after-destroyed-source", native_exception_bound_core);
	Test.add_func ("/declared-generics/cfg-native-exception-bound-after-destroyed-core", native_exception_bound_cfg);
	Test.add_func ("/declared-generics/ssa-native-exception-bound-after-destroyed-cfg", native_exception_bound_ssa);
	return Test.run ();
}
