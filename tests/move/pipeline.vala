// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.Moves {
private void model() throws GLib.Error {
	var checked = check (BASIC);
	var declaration = (CheckedOwnedLocalDeclaration) checked.functions[0].body.statements[1];
	var move = (CheckedOwnershipMove) declaration.initializer;
	assert (move.source == checked.functions[0].locals[0] && move.cleanup == declaration.cleanup);
	assert (move.semantic_type == checked.types.raw_pointer_type && move.span.text () == "move a");
	var core = CoreBuilder.build (checked);
	CoreVerifier.verify (core);
	var transfer = (CoreOwnershipTransfer) core.functions[0].body.statements[1];
	assert (transfer.source == core.functions[0].owned_locals[0] && transfer.destination == core.functions[0].owned_locals[1]);
	assert (transfer.source.cleanup == core.cleanups[0] && transfer.destination.cleanup == core.cleanups[0] && transfer.cleanup == core.cleanups[0]);
	assert (transfer.source.scope == transfer.destination.scope && transfer.span.text () == "move a");
	var control = CfgBuilder.build (core);
	CfgVerifier.verify (control);
	var function = control.functions[0];
	var operation = (CfgOwnershipTransferInstruction) function.entry.instructions[2];
	assert (operation.source == function.locals[0] && operation.destination == function.locals[1]);
	assert (operation.cleanup == control.cleanups[0] && operation.span.text () == "move a");
	assert (((CfgInitialize) function.entry.instructions[1]).acquisition == function.locals[0]);
	var cleanups = new GenericArray<CfgCleanupInstruction> ();
	foreach (var instruction in function.entry.instructions) {
		if (instruction is CfgCleanupInstruction) {
			cleanups.add ((CfgCleanupInstruction) instruction);
		}
	}
	assert (cleanups.length == 2 && ((CfgLoadValue) cleanups[0].value).source == operation.destination && ((CfgLoadValue) cleanups[1].value).source == operation.source);
	assert (OwnershipFlow.analyze (function).diagnostic == null);
	var ssa = SsaBuilder.build (control);
	SsaVerifier.verify (ssa);
	var instructions = ssa.functions[0].entry.instructions;
	assert (instructions.length == 3 && instructions[0] is SsaCCallInstruction);
	assert (((SsaCleanupInstruction) instructions[1]).value == instructions[0].result);
	assert (((SsaCleanupInstruction) instructions[2]).value is SsaNullPointerConstant);
	assert (ssa.functions[0].entry.parameters.length == 0 && ssa.functions[0].storage.length == 0);
	var baseline = build ("int f() { owned void* a = create(1); return 7; }");
	assert (NativeAbiDump.format (NativeAbiBuilder.build (ssa)) == NativeAbiDump.format (NativeAbiBuilder.build (baseline)));
	assert (CAbiDump.format (CAbiBuilder.build (ssa, NativeAbiBuilder.build (ssa))) == CAbiDump.format (CAbiBuilder.build (baseline, NativeAbiBuilder.build (baseline))));
}
private void conditional() throws GLib.Error {
	var control = cfg ("void f(bool condition) { owned void* a = create(1); if (condition) { owned void* b = move a; } }");
	CfgVerifier.verify (control);
	var function = control.functions[0];
	var flow = OwnershipFlow.analyze (function);
	assert (flow.diagnostic == null && flow.entry_state (function.blocks[2], function.locals[0]) == OwnershipState.join (OwnershipState.OWNED, OwnershipState.MOVED));
	assert (flow.entry_state (function.blocks[2], function.locals[1]) == null);
	assert (flow.dump () == read ("move-conditional.flow"));
	var ssa = SsaBuilder.build (control);
	var join = ssa.functions[0].blocks[2];
	assert (join.parameters.length == 1 && join.parameters[0].semantic_type.is_void_pointer ());
	assert (((SsaCleanupInstruction) join.instructions[0]).value == join.parameters[0]);
	var split = (SsaConditionalBranch) ssa.functions[0].entry.terminator;
	assert (split.false_edge.arguments[0] == ssa.functions[0].entry.instructions[0].result);
	assert (((SsaBranch) ssa.functions[0].blocks[1].terminator).edge.arguments[0] is SsaNullPointerConstant);
}
private void state_at_join(string body, int block, OwnershipState expected) throws GLib.Error {
	var control = cfg ("void f(bool condition) { owned void* a = create(1); " + body + " }");
	CfgVerifier.verify (control);
	var function = control.functions[0];
	var result = OwnershipFlow.analyze (function);
	assert (result.diagnostic == null && result.entry_state (function.blocks[block], function.locals[0]) == expected);
	SsaVerifier.verify (SsaBuilder.build (control));
}
private void chain() throws GLib.Error {
	var ssa = build ("void f() { owned void* a = create(1); owned void* b = move a; owned void* c = move b; owned void* d = move c; }");
	var instructions = ssa.functions[0].entry.instructions;
	assert (instructions.length == 5 && ((SsaCleanupInstruction) instructions[1]).value == instructions[0].result);
	for (int i = 2; i < 5; i++) {
		assert (((SsaCleanupInstruction) instructions[i]).value is SsaNullPointerConstant);
	}
}
private int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/move/model-identities-contracts-ssa-abi", model);
	add ("/move/conditional-state-pointer-phi", conditional);
	add ("/move/chain-normalization", chain);
	add ("/move/both-arm-state", () => state_at_join ("if (condition) { owned void* b = move a; } else { owned void* c = move a; }", 3, OwnershipState.MOVED));
	add ("/move/terminating-arm-state", () => state_at_join ("if (condition) { owned void* b = move a; return; } if (a == null) { return; }", 2, OwnershipState.OWNED));
	add ("/move/unreachable-predecessor-state", () => state_at_join ("if (condition) { return; owned void* b = move a; } if (a == null) { return; }", 2, OwnershipState.OWNED));
	add ("/move/loop-break-state", () => state_at_join ("while (condition) { owned void* b = move a; break; }", 3, OwnershipState.join (OwnershipState.OWNED, OwnershipState.MOVED)));
	add ("/move/loop-return-header-state", () => state_at_join ("while (condition) { owned void* b = move a; return; } if (a == null) { return; }", 1, OwnershipState.OWNED));
	add ("/move/conditional-break-header-state", () => state_at_join ("while (condition) { if (condition) { owned void* b = move a; break; } }", 1, OwnershipState.OWNED));
	register_diagnostics ();
	register_lifetime ();
	foreach (string name in new string[] {"basic", "chain", "chain-lifo", "null", "conditional", "both-arms", "return", "break", "continue", "loop", "lifo", "contracts", "terminating-arm", "loop-break", "loop-return", "conditional-break", "mixed", "unreachable", "trap"}) {
		add ("/move/pipeline/" + name, () => {
				var ssa = build (read ("move-" + name + ".astra"), fixture_declarations ());
				SsaVerifier.verify (ssa);
				CAbiVerifier.verify (CAbiBuilder.build (ssa, NativeAbiBuilder.build (ssa)));
				assert (SsaDump.format (ssa) == SsaDump.format (build (read ("move-" + name + ".astra"), fixture_declarations ())));
			});
	}
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
