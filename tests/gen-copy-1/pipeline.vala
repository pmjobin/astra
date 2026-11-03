// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
namespace Astra.Tests.GenericCopy {
private void lifetime() throws GLib.Error {
	for (int repeat = 0; repeat < 3; repeat++) {
		ParseResult? syntax = Parser.parse (new SourceFile.from_text ("copy.astra", fixture ("transport")));
		assert (syntax.diagnostic == null);
		var ast = WeakRef (syntax.unit);
		var analyzed = SemanticAnalyzer.analyze (syntax.unit);
		syntax = null;
		assert (ast.get () == null && analyzed.diagnostic == null);
		CheckedProgram? checked = analyzed.program;
		analyzed = null;
		var definition = WeakRef (checked.generic_functions[0]);
		var universe = WeakRef (checked.types);
		var application = WeakRef (checked.generic_functions[2].locals[0].semantic_type);
		CoreProgram? parameterized = CoreBuilder.build (checked);
		checked = null;
		assert (definition.get () == null && universe.get () == null && application.get () == null);
		CoreVerifier.verify (parameterized);
		var generic_function = WeakRef (parameterized.generic_functions[0]);
		var generic_struct = WeakRef (parameterized.generic_structs[0]);
		CoreProgram? core = CoreGenericMonomorphizer.build (parameterized);
		parameterized = null;
		assert (generic_function.get () == null && generic_struct.get () == null);
		CoreVerifier.verify_concrete (core);
		var core_graph = WeakRef (core);
		var field = WeakRef (core.structs[0].fields[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (core_graph.get () == null && field.get () == null);
		CfgVerifier.verify (cfg);
		assert (CfgFlowChecker.check (cfg).diagnostic == null);
		var cfg_graph = WeakRef (cfg);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (cfg_graph.get () == null);
		SsaVerifier.verify (ssa);
		foreach (var function in ssa.functions) {
			if (function.name.has_prefix ("astra.gen.") && !function.name.has_prefix ("astra.gen.8.")) {
				assert (function.storage.length == 0);
			}
			foreach (var block in function.blocks) {
				foreach (var parameter in block.parameters) {
					assert (!parameter.semantic_type.is_struct_storage () && !parameter.semantic_type.is_parameterized ());
				}
				foreach (var instruction in block.instructions) {
					assert (instruction.result == null || (!instruction.result.semantic_type.is_struct_storage () && !instruction.result.semantic_type.is_parameterized ()));
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
	string source = "struct A{int x;}struct B{int x;}T id<T>(T x){return x;}A fa(A a){return id(a);}B fb(B b){return id(b);}";
	var ssa = build (source);
	var nabi = NativeAbiBuilder.build (ssa);
	var map = new HashTable<SsaFunction, NativeFunction> (direct_hash, direct_equal);
	for (int i = 0; i < ssa.functions.length; i++) {
		map.insert (ssa.functions[i], nabi.functions[i]);
	}
	NativeAbiValidator.validate_ssa_calls (ssa, nabi, map);
	assert (nabi.struct_values.length == 2 && nabi.abi_version == NativeAbiVersion.AGGREGATE_V7);
	var signature = nabi.functions[2].signature;
	assert (ssa.functions[2].name.has_prefix ("astra.gen."));
	var result = signature.struct_result;
	var parameter = signature.struct_parameters[0];
	signature.struct_result = nabi.struct_values[1];
	signature.struct_parameters[0] = new NativeStructParameterPlan (0, 0, nabi.struct_values[1]);
	bool rejected = false;
	try {
		NativeAbiVerifier.verify (nabi);
	} catch (NativeAbiError error) {
		rejected = error.message.contains ("original copy/move signature declaration");
	}
	assert (rejected);
	rejected = false;
	try {
		NativeAbiValidator.validate_ssa_calls (ssa, nabi, map);
	} catch (NativeAbiError error) {
		rejected = error.message.contains ("exact source StructType declaration");
	}
	assert (rejected);
	signature.struct_result = result;
	signature.struct_parameters[0] = parameter;
	NativeAbiVerifier.verify (nabi);
	NativeAbiValidator.validate_ssa_calls (ssa, nabi, map);
}

private void forged() throws GLib.Error {
	string source = "struct S{int x;}struct Box<T>{T value;}T id<T>(T x){return x;}int main(){S s={x=42};Box<S> b={value=id(s)};return b.value.x;}";
	for (int variant = 0; variant < 5; variant++) {
		var core = CoreGenericMonomorphizer.build (CoreBuilder.build (check (source)));
		var function = core.functions[1];
		if (variant == 0) {
			function.parameters[0].struct_value_contract = null;
		}
		if (variant == 1) {
			function.body.statements.remove_index (0);
		}
		if (variant == 2) {
			var acquire = (CoreAcquireStructParameter) function.body.statements[0];
			function.body.statements.insert (1, new CoreStore (function.span, function.field_places[0], new CoreLoadValue (function.span, function.field_places[0])));
			assert (acquire.destination.incoming_parameter != null);
		}
		if (variant == 3) {
			function.generic_instance.type_arguments[0] = new StructType ("S");
		}
		if (variant == 4) {
			var initializer = (CoreStructInitialize) core.functions[0].body.statements[1];
			core.functions[0].body.statements.insert (2, initializer);
		}
		bool rejected = false;
		try {
			CoreVerifier.verify_concrete (core);
		} catch (CoreError error) {
			Test.message ("Core variant %d: %s", variant, error.message);
			rejected = true;
		}
		assert (rejected);
	}
	for (int variant = 0; variant < 3; variant++) {
		var cfg = CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (source))));
		if (variant == 0) {
			cfg.functions[1].entry.instructions.remove_index (0);
		}
		if (variant == 1) {
			cfg.functions[1].struct_parameters.remove_index (0);
		}
		if (variant == 2) {
			foreach (var instruction in cfg.functions[0].entry.instructions) {
				if (instruction is CfgStructResultConsume) {
					cfg.functions[0].entry.instructions.add (instruction);
					break;
				}
			}
		}
		bool rejected = false;
		try {
			CfgVerifier.verify (cfg);
		} catch (CfgError error) {
			Test.message ("CFG variant %d: %s", variant, error.message);
			rejected = true;
		}
		assert (rejected);
	}
	var ssa = build (source);
	ssa.functions[1].struct_parameters.remove_index (0);
	bool rejected = false;
	try {
		SsaVerifier.verify (ssa);
	} catch (SsaError error) {
		rejected = true;
	}
	assert (rejected);
}

private CoreProgram recovery_program(string source) throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("generic-copy-recovery.astra", source));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic == null) {
		return CoreBuilder.build (checked.program);
	}
	// Source declaration-demand expansion now bounds this growth before Core.
	// Retain that refusal and independently install the same concrete Core
	// demand so failure reclamation is still proved at the original stage.
	assert (checked.program == null);
	assert (checked.diagnostic.message.contains ("generic materialization limit exceeded: type-expression depth 128"));
	string dormant = source.replace ("int root(){return grow(1);}", "int root(){return 1;}");
	assert (dormant != source);
	var program = CoreBuilder.build (check (dormant));
	var root = program.functions[0];
	var returned = root.body.statements[0] as CoreReturn;
	assert (returned != null && returned.value is CoreIntegerValue);
	var arguments = new GenericArray<SemanticType> ();
	arguments.add (returned.value.semantic_type);
	var values = new GenericArray<CoreValue> ();
	values.add (returned.value);
	root.body.statements[0] = new CoreReturn (returned.span, new CoreGenericCall (returned.span, returned.value.semantic_type, program.generic_functions[0], arguments, values));
	CoreVerifier.verify (program);
	return program;
}

private void recovery() throws GLib.Error {
	foreach (string source in new string[] {"struct Box<T>{T value;}T grow<T>(T input){Box<T> box={value=input};Box<T> copy=grow(box);return input;}int root(){return grow(1);}", "struct Cycle<T>{Cycle<T> value;}void root(Cycle<int>* pointer){}"}) {
		for (int repeat = 0; repeat < 2; repeat++) {
			CoreProgram? program = recovery_program (source);
			var graph = WeakRef (program);
			var definition = WeakRef (program.generic_structs[0]);
			bool rejected = false;
			try {
				CoreGenericMonomorphizer.build (program);
			} catch (CoreError error) {
				rejected = true;
			}
			assert (rejected);
			program = null;
			assert (graph.get () == null && definition.get () == null);
			SsaVerifier.verify (build ("struct S{int x;}T id<T>(T value){return value;}S root(S value){return id(value);}"));
		}
	}
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/gen-copy/pipeline/checked-core-cfg-ssa-native-lifetimes-and-scalarization", lifetime);
	add ("/gen-copy/pipeline/exact-native-plan-correspondence", correspondence);
	add ("/gen-copy/pipeline/forged-concrete-consumers-and-storage", forged);
	add ("/gen-copy/pipeline/failed-completion-reclaims-graphs-and-recovers", recovery);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
