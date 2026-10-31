// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.NativeModules {
private SsaProgram source() throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("module-proof.astra", "int increment(int value) { return value + 1; }\n"));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked.diagnostic == null);
	var cfg = CfgBuilder.build (CoreBuilder.build (checked.program));
	assert (CfgFlowChecker.check (cfg).diagnostic == null);
	return SsaBuilder.build (cfg);
}
private void generic_valid(LlvmModuleArtifact artifact) {
	char* message;
	int failed = CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message);
	if (message != null) {
		CApi.dispose_message (message);
	}
	assert (failed == 0);
}
private void rejected(LlvmModuleArtifact artifact) {
	bool refused = false;
	try {
		artifact.verify ();
	} catch (LlvmError error) {
		refused = true;
		Test.message ("native module authority: %s", error.message);
	}
	assert (refused);
}
private void imports() {
	try {
		var ssa = source ();
		var native = NativeAbiBuilder.build (ssa);
		var cabi = CAbiBuilder.build (ssa, native);
		var plan = new LlvmNativeModulePlan ();
		string symbol = "astra_mod_import_proof";
		plan.bind (ssa.functions[0], native.functions[0].signature, native, symbol, true);
		bool refused = false;
		try {
			LlvmLowering.lower (ssa, native, cabi);
		} catch (LlvmError error) {
			refused = true;
			Test.message ("lost native import plan: %s", error.message);
		}
		assert (refused);
		var artifact = LlvmLowering.lower (ssa, native, cabi, null, null, false, false, plan);
		string before = artifact.dump ();
		var function = CApi.named_function (artifact.module, symbol);
		assert (CApi.count_basic_blocks (function) == 0);
		CApi.set_function_call_conv (function, CApi.CallConv.C);
		generic_valid (artifact);
		rejected (artifact);
		CApi.set_function_call_conv (function, LlvmLowering.CALL_CONVENTION);
		assert (artifact.dump () == before);
		CApi.set_value_name (function, "forged", 6);
		generic_valid (artifact);
		rejected (artifact);
		CApi.set_value_name (function, symbol, symbol.length);
		assert (artifact.dump () == before);
		var block = CApi.append_basic_block_in_context (artifact.context, function, "forged.body");
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_at_end (builder, block);
		CApi.build_ret (builder, CApi.get_param (function, 0));
		CApi.dispose_builder (builder);
		generic_valid (artifact);
		rejected (artifact);
		CApi.delete_basic_block (block);
		assert (artifact.dump () == before);
		refused = false;
		try {
			ssa.functions[0].bind_module_import ("astra_mod_other");
		} catch (SsaError error) {
			refused = true;
		}
		assert (refused);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void exports() {
	try {
		var ssa = source ();
		var native = NativeAbiBuilder.build (ssa);
		var plan = new LlvmNativeModulePlan ();
		string symbol = "astra_mod_export_proof";
		plan.bind (ssa.functions[0], native.functions[0].signature, native, symbol, false);
		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native), null, null, false, false, plan);
		string before = artifact.dump ();
		var function = CApi.named_function (artifact.module, symbol);
		assert (CApi.count_basic_blocks (function) > 0);
		CApi.set_linkage (function, CApi.Linkage.INTERNAL);
		generic_valid (artifact);
		rejected (artifact);
		// Internal linkage also sets dso_local; the C API has no direct reset.
		// Rebuild from the unchanged verified graph to restore all state.
		var restored = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native), null, null, false, false, plan);
		assert (restored.dump () == before);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void record_correspondence() {
	try {
		string text;
		string path = "tests/language-generalization-10/unit-record-provider.astra";
		FileUtils.get_contents (path, out text);
		var files = new GenericArray<SourceFile> ();
		files.add (new SourceFile.from_text (path, text));
		var parsed = SyntaxProgram.parse (new SourceSet (files));
		assert (parsed.diagnostic == null);
		SemanticResult? checked = SemanticAnalyzer.analyze_program (parsed.program);
		assert (checked.diagnostic == null);
		CoreProgram? core = CoreBuilder.build (checked.program);
		checked = null;
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (CfgFlowChecker.check (cfg).diagnostic == null);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		var native = NativeAbiBuilder.build (ssa);
		SsaFunction? factory = null;
		foreach (var function in ssa.functions) {
			if (function.name == "Composite10.create") {
				factory = function;
			}
		}
		assert (factory != null);
		var signature = native.functions[factory.ordinal].signature;
		var original = signature.struct_result;
		assert (original != null && original.mode == NativeStructValueMode.MOVE_VALUE);
		LlvmNativeModulePlan? plan = new LlvmNativeModulePlan ();
		plan.bind (factory, signature, native, "astra_mod_owned_record_proof", false);
		var forged = new NativeStructValuePlan (original.struct_ordinal, original.struct_name, original.leaves, original.result_carrier, NativeStructValueMode.COPY_VALUE, original.ownership);
		forged.declaration = original.declaration;
		signature.struct_result = forged;
		bool refused = false;
		try {
			plan.validate (ssa, native);
		} catch (LlvmError error) {
			refused = error.message.contains ("typed signature");
		}
		assert (refused);
		signature.struct_result = original;
		plan.validate (ssa, native);
		NativeAbiVerifier.verify (native);
		int buffer = -1;
		for (int f = 0; f < original.ownership.length; f++) {
			if (original.ownership[f].buffer_cleanup != null) {
				buffer = f;
			}
		}
		assert (buffer >= 0);
		var owner = original.ownership[buffer];
		var ordinals = new int[owner.depth];
		for (int f = 0; f < ordinals.length; f++) {
			ordinals[f] = owner.path_ordinal (f);
		}
		var wrong_buffer = new NativeBufferValuePlan (new NativeScalarAbiType (NativeScalarType.U32));
		original.ownership[buffer] = new NativeRecordResource.projected (ordinals, owner.type_name, owner.cleanup_symbol, owner.acquisition_rank, -1, wrong_buffer);
		refused = false;
		try {
			plan.validate (ssa, native);
		} catch (LlvmError error) {
			refused = error.message.contains ("typed signature");
		}
		assert (refused);
		original.ownership[buffer] = owner;
		plan.validate (ssa, native);
		NativeAbiVerifier.verify (native);
		CAbiProgram? cabi = CAbiBuilder.build (ssa, native);
		var artifact = LlvmLowering.lower (ssa, native, cabi, null, null, false, false, plan);
		var old = WeakRef (ssa.classes[0]);
		cabi = null;
		plan = null;
		factory = null;
		ssa = null;
		assert (old.get () == null);
		NativeAbiVerifier.verify (native);
		artifact.verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void generic_correspondence() {
	try {
		var files = new GenericArray<SourceFile> ();
		foreach (string path in new string[] {"tests/language-generalization-10/unit-record-provider.astra", "tests/language-generalization-10/unit-generic-provider.astra"}) {
			string text;
			FileUtils.get_contents (path, out text);
			files.add (new SourceFile.from_text (path, text));
		}
		var parsed = SyntaxProgram.parse (new SourceSet (files));
		assert (parsed.diagnostic == null);
		SemanticResult? checked = SemanticAnalyzer.analyze_program (parsed.program);
		assert (checked.diagnostic == null);
		CoreProgram? core = CoreBuilder.build (checked.program);
		checked = null;
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (CfgFlowChecker.check (cfg).diagnostic == null);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		var native = NativeAbiBuilder.build (ssa);
		SsaFunction? inspect = null;
		foreach (var function in ssa.functions) {
			if (function.name == "Composite10.archive_count") {
				inspect = function;
			}
		}
		assert (inspect != null);
		NativeClassPlan? owner = null;
		foreach (var candidate in native.classes) {
			if (candidate.generic_instance != null) {
				owner = candidate;
			}
		}
		assert (owner != null);
		var key = owner.generic_instance;
		var record = key.record_argument;
		assert (record != null && record.mode == NativeStructValueMode.MOVE_VALUE);
		LlvmNativeModulePlan? plan = new LlvmNativeModulePlan ();
		plan.bind (inspect, native.functions[inspect.ordinal].signature, native, "astra_mod_generic_correspondence", false);
		var copied = new NativeStructValuePlan (record.struct_ordinal, record.struct_name, record.leaves, record.result_carrier, NativeStructValueMode.COPY_VALUE, record.ownership);
		copied.declaration = record.declaration;
		var members = new int[key.member_count];
		for (int m = 0; m < members.length; m++) {
			members[m] = key.member_target (m);
		}
		owner.generic_instance = new NativeExactClassInstance (key.definition, key.argument_ordinal, members, null, copied, key.generic_methods);
		bool refused = false;
		try {
			plan.validate (ssa, native);
		} catch (LlvmError error) {
			refused = error.message.contains ("typed signature");
		}
		assert (refused);
		owner.generic_instance = key;
		plan.validate (ssa, native);
		NativeAbiVerifier.verify (native);
		CAbiProgram? cabi = CAbiBuilder.build (ssa, native);
		var artifact = LlvmLowering.lower (ssa, native, cabi, null, null, false, false, plan);
		var old = WeakRef (ssa.classes[0]);
		cabi = null;
		plan = null;
		inspect = null;
		ssa = null;
		assert (old.get () == null);
		NativeAbiVerifier.verify (native);
		artifact.verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void declaration_binding() {
	try {
		var producer = source ();
		var producer_native = NativeAbiBuilder.build (producer);
		string shape = LlvmNativeModulePlan.signature_shape (producer.functions[0], producer_native.functions[0].signature, producer_native);
		string symbol = "astra_mod_declaration_proof";
		var file = new SourceFile.from_text ("<native-declaration-binding>", "int increment(int value) { return 0; }", true);
		var parsed = Parser.parse (file);
		assert (parsed.diagnostic == null);
		var units = new GenericArray<CompilationUnitSyntax> ();
		units.add (parsed.unit);
		var registry = new NativeDeclarationRegistry ();
		registry.add (file, new NativeDeclarationIdentity ("proof-origin", "F:increment", symbol, shape, "",
			producer_native.functions[0].scoped_readonly, producer_native.functions[0].readonly_inputs,
			producer_native.functions[0].callback_inputs));
		var checked = SemanticAnalyzer.analyze_program (new SyntaxProgram (units), null, null, null, null, registry);
		assert (checked.diagnostic == null);
		var ssa = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (checked.program)));
		var native = NativeAbiBuilder.build (ssa);
		var cabi = CAbiBuilder.build (ssa, native);
		bool refused = false;
		try {
			LlvmLowering.lower (ssa, native, cabi);
		} catch (LlvmError error) {
			refused = error.message.contains ("external module plan");
		}
		assert (refused);
		var plan = new LlvmNativeModulePlan ();
		refused = false;
		try {
			plan.bind (ssa.functions[0], native.functions[0].signature, native, "astra_mod_wrong", true);
		} catch (LlvmError error) {
			refused = error.message.contains ("original exact symbol");
		}
		assert (refused);
		refused = false;
		try {
			plan.bind (ssa.functions[0], native.functions[0].signature, native, symbol, false);
		} catch (LlvmError error) {
			refused = error.message.contains ("original exact symbol");
		}
		assert (refused);
		plan.bind (ssa.functions[0], native.functions[0].signature, native, symbol, true);
		var artifact = LlvmLowering.lower (ssa, native, cabi, null, null, false, false, plan);
		assert (CApi.count_basic_blocks (CApi.named_function (artifact.module, symbol)) == 0);
		artifact.verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

public int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/native-modules/closed-generic-argument-correspondence-restored", generic_correspondence);
	Test.add_func ("/native-modules/owned-record-mode-cleanup-correspondence-restored", record_correspondence);
	Test.add_func ("/native-modules/import-reject-restore", imports);
	Test.add_func ("/native-modules/export-reject-restore", exports);
	Test.add_func ("/native-modules/declaration-requires-exact-import-binding", declaration_binding);
	return Test.run ();
}
}
