// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Vapi;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.OwnerBorrow {
private void model() throws GLib.Error {
	var checked = check (BASIC);
	var borrow = (CheckedOwnedBorrowValue) ((CheckedCallStatement) checked.functions[0].body.statements[1]).arguments[0];
	assert (borrow.source == checked.functions[0].locals[0] && borrow.parameter == checked.c_functions[1].parameters[0]);
	assert (borrow.semantic_type == checked.types.raw_pointer_type && borrow.owned_cleanup == null);
	assert (borrow.span.text () == "h" && borrow.parameter.span.text () == "borrowed void* p");
	assert (borrow.parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
	assert (checked.c_functions[3].parameters[0].pointer_contract == PointerParameterContract.UNMANAGED);
	assert (SemanticDump.format (checked).contains ("borrow-owner #0"));
	var core = CoreBuilder.build (checked);
	CoreVerifier.verify (core);
	var core_borrow = (CoreOwnedBorrowValue) ((CoreCCallStatement) core.functions[0].body.statements[1]).arguments[0];
	assert (core_borrow.source == core.functions[0].owned_locals[0] && core_borrow.parameter == core.c_functions[1].parameters[0]);
	assert (CoreDump.format (core).contains ("borrow-owner #0"));
	var control = CfgBuilder.build (core);
	assert (CfgFlowChecker.check (control).diagnostic == null);
	var instructions = control.functions[0].entry.instructions;
	var event = (CfgOwnedBorrowInstruction) instructions[2];
	assert (event.result.source == control.functions[0].locals[0] && event.result.parameter == control.c_functions[1].parameters[0]);
	assert (((CfgCCallInstruction) instructions[3]).arguments[0] == event.result);
	assert (CfgDump.format (control).contains ("borrow-owner #0"));
	var ssa = SsaBuilder.build (control);
	var physical = ssa.functions[0].entry.instructions;
	assert (physical.length == 6);
	for (int i = 1; i < 4; i++) {
		assert (((SsaCCallInstruction) physical[i]).arguments[0] == physical[0].result);
	}
	assert (((SsaCleanupInstruction) physical[4]).value == physical[0].result);
	assert (((SsaCleanupInstruction) physical[5]).value is SsaNullPointerConstant);
	assert (ssa.functions[0].storage.length == 0 && ssa.functions[0].entry.parameters.length == 0);
	assert (!SsaDump.format (ssa).contains ("borrow-owner"));
	var cabi = CAbiBuilder.build (ssa, NativeAbiBuilder.build (ssa));
	var parameter = cabi.functions[1].signature.parameters[0];
	assert (parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && parameter.scalar_type == CAbiScalarType.PTR);
	assert (parameter.span.text () == "borrowed void* p" && cabi.profile == CAbiProfile.SCALAR_PTR_V1);
	assert (cabi.cleanups[0].signature.parameters[0].pointer_contract == PointerParameterContract.UNMANAGED);
	assert (CAbiDump.format (cabi).contains ("(parameter #0 PTR (contract borrowed-noescape))"));
}

private void differential() throws GLib.Error {
	string body = "int wrapper(borrowed void* p) { return inspect(p); }";
	var source = check ("extern(C) int inspect(borrowed void* p); " + body, "");
	var vapi = check (body, "int inspect(borrowed void* p);");
	assert (SemanticDump.format (source) == SemanticDump.format (vapi));
	var core0 = CoreBuilder.build (source);
	var core1 = CoreBuilder.build (vapi);
	assert (CoreDump.format (core0) == CoreDump.format (core1));
	var cfg0 = CfgBuilder.build (core0);
	var cfg1 = CfgBuilder.build (core1);
	assert (CfgDump.format (cfg0) == CfgDump.format (cfg1));
	var ssa0 = SsaBuilder.build (cfg0);
	var ssa1 = SsaBuilder.build (cfg1);
	assert (SsaDump.format (ssa0) == SsaDump.format (ssa1));
	assert (CAbiDump.format (CAbiBuilder.build (ssa0, NativeAbiBuilder.build (ssa0))) == CAbiDump.format (CAbiBuilder.build (ssa1, NativeAbiBuilder.build (ssa1))));
	string raw = "int f(void* p) { if (p != null) { return 1; } return 0; }";
	var unmanaged = NativeAbiBuilder.build (build (raw, ""));
	var borrowed = NativeAbiBuilder.build (build (raw.replace ("void* p", "borrowed void* p"), ""));
	assert (NativeAbiDump.format (unmanaged) == NativeAbiDump.format (borrowed));
}

private void order() throws GLib.Error {
	var control = cfg ("void f() { owned void* h = create(1); observe3(record(1), h, record(2)); }");
	var instructions = control.functions[0].entry.instructions;
	assert (((CfgCCallInstruction) instructions[2]).target.name == "record");
	assert (instructions[3] is CfgOwnedBorrowInstruction);
	assert (((CfgCCallInstruction) instructions[4]).target.name == "record");
	assert (((CfgCCallInstruction) instructions[5]).target.name == "observe3");
	assert (((CfgCCallInstruction) instructions[5]).arguments[1] == ((CfgOwnedBorrowInstruction) instructions[3]).result);
	SsaBuilder.build (control);
	// A later short-circuit argument creates blocks after the borrow event.
	build ("void native(borrowed void* p, bool b) {} void f(bool c) { owned void* h = create(1); native(h, c && inspect(h) == 1); }");
}

private void lifetime() throws GLib.Error {
	VapiParseResult? syntax = VapiParser.parse (new SourceFile.from_text ("borrowed.vapi", VAPI));
	var syntax_ref = WeakRef (syntax.file.functions[1].parameters[0]);
	GenericArray<ForeignDeclarationInput>? inputs = VapiNormalizer.normalize (syntax.file);
	syntax = null;
	assert (syntax_ref.get () == null);
	var parsed = Parser.parse (new SourceFile.from_text ("borrowed.astra", BASIC));
	SemanticResult? semantic = SemanticAnalyzer.analyze (parsed.unit, inputs);
	var input_ref = WeakRef (inputs[1].parameters[0]);
	inputs = null;
	assert (input_ref.get () == null);
	var checked_ref = WeakRef (((CheckedCallStatement) semantic.program.functions[0].body.statements[1]).arguments[0]);
	var parameter_ref = WeakRef (semantic.program.c_functions[1].parameters[0]);
	CoreProgram? core = CoreBuilder.build (semantic.program);
	semantic = null;
	assert (checked_ref.get () == null && parameter_ref.get () == null);
	var core_ref = WeakRef (((CoreCCallStatement) core.functions[0].body.statements[1]).arguments[0]);
	var core_parameter = WeakRef (core.c_functions[1].parameters[0]);
	CfgProgram? control = CfgBuilder.build (core);
	core = null;
	assert (core_ref.get () == null && core_parameter.get () == null);
	OwnershipFlowResult? flow = OwnershipFlow.analyze (control.functions[0]);
	var flow_ref = WeakRef (flow);
	var event_ref = WeakRef (control.functions[0].entry.instructions[2]);
	var cfg_parameter = WeakRef (control.c_functions[1].parameters[0]);
	SsaProgram? ssa = SsaBuilder.build (control);
	flow = null;
	control = null;
	assert (flow_ref.get () == null && event_ref.get () == null && cfg_parameter.get () == null);
	var ssa_parameter = WeakRef (ssa.c_functions[1].parameters[0]);
	var cabi = CAbiBuilder.build (ssa, NativeAbiBuilder.build (ssa));
	ssa = null;
	assert (ssa_parameter.get () == null);
	CAbiVerifier.verify (cabi);
	assert (cabi.functions[1].signature.parameters[0].span.text () == "borrowed void* p");
}

private int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/oborrow/model", model);
	add ("/oborrow/source-vapi-nabi-differential", differential);
	add ("/oborrow/order", order);
	add ("/oborrow/lifetime", lifetime);
	register_diagnostics ();
	foreach (string name in new string[] {"basic", "native", "forward", "move", "destination", "repeated", "null", "loop", "body-loop", "continue", "break", "return", "order", "raw-null", "extern", "control", "conditional", "shortcircuit"}) {
		add ("/oborrow/pipeline/" + name, () => {
				var ssa = build (read ("oborrow-" + name + ".astra"), fixture_declarations ());
				CAbiVerifier.verify (CAbiBuilder.build (ssa, NativeAbiBuilder.build (ssa)));
			});
	}
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
