// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.Backend.LLVM;
using Astra.Driver;

namespace Astra.Tests.Exec {
private SsaProgram build_ssa(string text) throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("entry.astra", text));
	assert (parsed.diagnostic == null);
	var checked_result = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked_result.diagnostic == null);
	var cfg = CfgBuilder.build (CoreBuilder.build (checked_result.program));
	assert (CfgFlowChecker.check (cfg).diagnostic == null);
	return SsaBuilder.build (cfg);
}

private LlvmModuleArtifact lower_entry(string text = "int helper() { return 0; } int main() { if (false) { return main(); } return helper(); }") throws GLib.Error {
	var ssa = build_ssa (text);
	return LlvmLowering.lower (ssa, NativeAbiBuilder.build (ssa), Astra.CAbi.CAbiBuilder.build (ssa, Astra.NativeAbi.NativeAbiBuilder.build (ssa)), ProgramEntry.resolve (ssa));
}

private void wrapper() throws GLib.Error {
	var ssa = build_ssa ("int helper() { return 7; } int main() { if (false) { return main(); } return helper(); }");
	var entry = ProgramEntry.resolve (ssa);
	assert (entry == ssa.functions[1]);
	var native = NativeAbiBuilder.build (ssa);
	var renamed = new GenericArray<NativeFunction> ();
	for (int f = 0; f < native.functions.length; f++) {
		var old = native.functions[f];
		assert (old.linkage == NativeLinkage.NATIVE_INTERNAL);
		var replacement = new NativeFunction (old.span, old.name_span, "same-debug-name", f, old.signature, old.linkage);
		replacement.bind_effects (old.effect_facts);
		replacement.bind_runtime_lifetimes (old.runtime_lifetimes);
		replacement.bind_scoped_readonly (old.scoped_readonly, old.readonly_inputs, old.callback_inputs, old.callback_input_count, old.callback_contract_supported);
		renamed.add (replacement);
	}
	var nabi = new NativeAbiProgram (native.span, native.abi_version, renamed);
	var artifact = LlvmLowering.lower (ssa, nabi, Astra.CAbi.CAbiBuilder.build (ssa, nabi), entry);
	string independent = artifact.dump ();
	assert (!independent.contains ("target triple") && !independent.contains ("target datalayout") && !independent.contains ("@main("));
	var target = new LlvmTargetMachineArtifact ();
	artifact.configure_executable (target);
	assert (CApi.get_target (artifact.module) == target.triple);
	assert (CApi.get_data_layout (artifact.module) == target.data_layout);
	var helper = CApi.first_function (artifact.module);
	var internal_main = CApi.next_function (helper);
	var launch = CApi.next_function (internal_main);
	assert ((void*) CApi.next_function (launch) == null);
	assert (CApi.get_linkage (internal_main) == CApi.Linkage.INTERNAL);
	assert (CApi.function_call_conv (internal_main) == CApi.CallConv.FAST);
	assert (CApi.get_linkage (launch) == CApi.Linkage.EXTERNAL);
	assert (CApi.function_call_conv (launch) == CApi.CallConv.C);
	assert (CApi.count_params (launch) == 0);
	assert (CApi.int_width (CApi.return_type (CApi.global_value_type (launch))) == 32);
	var block = CApi.entry_block (launch);
	assert ((void*) CApi.next_block (block) == null);
	var call = CApi.first_instruction (block);
	var ret = CApi.next_instruction (call);
	assert (CApi.opcode (call) == CApi.Opcode.CALL && (void*) CApi.called_value (call) == (void*) internal_main);
	assert (CApi.instruction_call_conv (call) == CApi.CallConv.FAST);
	assert (CApi.opcode (ret) == CApi.Opcode.RET && (void*) CApi.operand (ret, 0) == (void*) call);
	assert ((void*) CApi.next_instruction (ret) == null);
	bool recursive = false;
	for (var b = CApi.first_block (internal_main); (void*) b != null; b = CApi.next_block (b)) {
		for (var i = CApi.first_instruction (b); (void*) i != null; i = CApi.next_instruction (i)) {
			if (CApi.opcode (i) == CApi.Opcode.CALL) {
				assert ((void*) CApi.called_value (i) != (void*) launch && CApi.instruction_call_conv (i) == CApi.CallConv.FAST);
				recursive = recursive || (void*) CApi.called_value (i) == (void*) internal_main;
			}
		}
	}
	assert (recursive);
	assert (artifact.dump ().contains ("define i32 @main()"));
	Test.message ("triple: %s; CPU: target default (empty); features: empty; PIC; default code model; codegen None", target.triple);
	Test.message ("data layout: %s", target.data_layout);
	Test.message ("host linker argv: %s", string.joinv (" | ", Config.host_linker_argv ()));
	Test.message ("configured LLVM before emission:\n%s", artifact.dump ());
	try {
		artifact.configure_executable (target);
		assert_not_reached ();
	} catch (LlvmError.INVALID_INPUT error) {
		assert (error.message.contains ("no launch wrapper"));
	}
}

private void backend_errors() throws GLib.Error {
	var target = new LlvmTargetMachineArtifact ();
	try {
		LlvmTargetMachineArtifact.lookup_target ("astra-invalid-target");
		assert_not_reached ();
	} catch (LlvmError.TARGET error) {
		assert (error.message.contains ("lookup failed") && error.message.contains ("astra-invalid-target"));
	}
	var ssa = build_ssa ("int main() { return 0; }");
	var other = build_ssa ("int main() { return 0; }");
	try {
		LlvmLowering.lower (ssa, NativeAbiBuilder.build (ssa), Astra.CAbi.CAbiBuilder.build (ssa, Astra.NativeAbi.NativeAbiBuilder.build (ssa)), other.functions[0]);
		assert_not_reached ();
	} catch (LlvmError.INVALID_INPUT error) {
		assert (error.message.contains ("selected identity"));
	}
	var artifact = lower_entry ();
	var workspace = new Workspace ();
	try {
		target.emit_object (artifact, workspace.executable);
		assert_not_reached ();
	} catch (LlvmError.INVALID_INPUT error) {
		assert (error.message.contains ("not configured"));
	}
	artifact.configure_executable (target);
	// Force LLVM's real file-open error after a transaction already exists.
	try {
		var output = new ExecutableOutput (workspace.executable);
		target.emit_object (artifact, Path.build_filename (output.object_path, "missing-parent.o"));
		assert_not_reached ();
	} catch (LlvmError.EMISSION error) {
		assert (error.message.contains ("LLVM object emission failed:") && error.message.length > 40);
	}
	assert (!FileUtils.test (workspace.executable, FileTest.EXISTS));
	workspace.clean_temporaries ();
}

private void lifetime(string text = "int helper(int a, int b) { return a / b; } int main() { if (false) { return main(); } return helper(-2147483648, -1) + -2147483648; }") throws GLib.Error {
	ParseResult? parsed = Parser.parse (new SourceFile.from_text ("lifetime.astra", text));
	SemanticResult? checked_result = SemanticAnalyzer.analyze (parsed.unit);
	CoreProgram? core = CoreBuilder.build (checked_result.program);
	CfgProgram? cfg = CfgBuilder.build (core);
	assert (CfgFlowChecker.check (cfg).diagnostic == null);
	SsaProgram? ssa = SsaBuilder.build (cfg);
	NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
	// GWeakRef has address-sensitive registration; never move initialized
	// weak refs through a by-value Vala array initializer.
	var source_ref = WeakRef (parsed.unit.span.file);
	var syntax_ref = WeakRef (parsed.unit);
	var syntax_function_ref = WeakRef (parsed.unit.functions[1]);
	var checked_ref = WeakRef (checked_result.program);
	var type_ref = WeakRef (checked_result.program.types.int_type);
	var symbol_ref = WeakRef (checked_result.program.functions[1].symbol);
	var core_ref = WeakRef (core);
	var cfg_ref = WeakRef (cfg);
	var ssa_ref = WeakRef (ssa);
	var ssa_function_ref = WeakRef (ssa.functions[1]);
	var nabi_ref = WeakRef (nabi);
	var native_ref = WeakRef (nabi.functions[1]);
	var signature_ref = WeakRef (nabi.functions[1].signature);
	SsaFunction? selected_entry = ProgramEntry.resolve (ssa);
	Astra.CAbi.CAbiProgram? cabi = Astra.CAbi.CAbiBuilder.build (ssa, nabi);
	LlvmModuleArtifact? artifact = LlvmLowering.lower (ssa, nabi, cabi, selected_entry);
	cabi = null;
	LlvmTargetMachineArtifact? target = new LlvmTargetMachineArtifact ();
	artifact.configure_executable (target);
	selected_entry = null;
	parsed = null;
	checked_result = null;
	core = null;
	cfg = null;
	ssa = null;
	nabi = null;
	assert (source_ref.get () == null && syntax_ref.get () == null && syntax_function_ref.get () == null);
	assert (checked_ref.get () == null && type_ref.get () == null && symbol_ref.get () == null);
	assert (core_ref.get () == null && cfg_ref.get () == null);
	assert (ssa_ref.get () == null && ssa_function_ref.get () == null);
	assert (nabi_ref.get () == null && native_ref.get () == null && signature_ref.get () == null);
	var workspace = new Workspace ();
	ExecutableOutput? output = new ExecutableOutput (workspace.executable);
	target.emit_object (artifact, output.object_path);
	var artifact_ref = WeakRef (artifact);
	var target_ref = WeakRef (target);
	artifact = null;
	target = null;
	assert (artifact_ref.get () == null && target_ref.get () == null);
	assert (FileUtils.test (output.object_path, FileTest.IS_REGULAR));
	output.link_and_commit ();
	output = null;
	workspace.clean_temporaries ();
	var run = new Run ({workspace.executable});
	run.exits (0);
	run.silent ();
}

private void register_backend() {
	add ("/exec/backend/wrapper-and-main-recursion", wrapper);
	add ("/exec/backend/errors", backend_errors);
	add ("/exec/backend/lifetime", () => lifetime ());
}

}
