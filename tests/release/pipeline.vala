// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.Release {
private void model() throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("release.astra", BASIC));
	var syntax = (ReleaseStatementSyntax) parsed.unit.functions[0].body.statements[1];
	assert (syntax.keyword.kind == TokenKind.RELEASE && syntax.owner.spelling () == "a" && syntax.semicolon.kind == TokenKind.SEMICOLON);
	var checked = check (BASIC);
	var release = (CheckedOwnershipRelease) checked.functions[0].body.statements[1];
	assert (release.owner == checked.functions[0].locals[0] && release.cleanup == checked.c_functions[0].metadata.owned_result.cleanup);
	assert (release.span.text () == "release a;");
	var core = CoreBuilder.build (checked);
	CoreVerifier.verify (core);
	var statement = (CoreOwnershipRelease) core.functions[0].body.statements[1];
	assert (statement.owner == core.functions[0].owned_locals[0] && statement.cleanup == core.cleanups[0]);
	assert (statement.span.text () == release.span.text ());
	var control = CfgBuilder.build (core);
	CfgVerifier.verify (control);
	var function = control.functions[0];
	var event = (CfgOwnershipReleaseInstruction) function.entry.instructions[2];
	assert (event.owner == function.locals[0] && event.cleanup == control.cleanups[0] && event.span.text () == "release a;");
	assert (((CfgLoadValue) ((CfgCleanupInstruction) function.entry.instructions[4]).value).source == event.owner);
	assert (OwnershipFlow.analyze (function).diagnostic == null);
	var ssa = SsaBuilder.build (control);
	var instructions = ssa.functions[0].entry.instructions;
	assert (instructions.length == 3 && instructions[0] is SsaCCallInstruction);
	assert (((SsaCleanupInstruction) instructions[1]).value == instructions[0].result && instructions[1].span.text () == "release a;");
	assert (((SsaCleanupInstruction) instructions[2]).value is SsaNullPointerConstant);
	assert (ssa.functions[0].storage.length == 0 && ssa.functions[0].entry.parameters.length == 0);
	var baseline = build ("int f() { owned void* a = create(1); return 7; }");
	assert (NativeAbiDump.format (NativeAbiBuilder.build (ssa)) == NativeAbiDump.format (NativeAbiBuilder.build (baseline)));
	assert (CAbiDump.format (CAbiBuilder.build (ssa, NativeAbiBuilder.build (ssa))) == CAbiDump.format (CAbiBuilder.build (baseline, NativeAbiBuilder.build (baseline))));
}

private void conditional(int id) throws GLib.Error {
	var control = cfg ("void f(bool c) { owned void* a = create(%d); if (c) { release a; } }".printf (id));
	var function = control.functions[0];
	var flow = OwnershipFlow.analyze (function);
	assert (flow.diagnostic == null && flow.entry_state (function.blocks[2], function.locals[0]) == OwnershipState.join (OwnershipState.OWNED, OwnershipState.RELEASED));
	var ssa = SsaBuilder.build (control);
	var join = ssa.functions[0].blocks[2];
	assert (join.parameters.length == 1 && join.parameters[0].semantic_type.is_void_pointer ());
	assert (((SsaCleanupInstruction) join.instructions[0]).value == join.parameters[0]);
	var split = (SsaConditionalBranch) ssa.functions[0].entry.terminator;
	assert (split.false_edge.arguments[0] == ssa.functions[0].entry.instructions[0].result);
	assert (((SsaBranch) ssa.functions[0].blocks[1].terminator).edge.arguments[0] is SsaNullPointerConstant);
}

private void state_at_join(string body, int block, OwnershipState expected) throws GLib.Error {
	var control = cfg ("void f(bool c) { owned void* a = create(1); " + body + " }");
	var function = control.functions[0];
	var flow = OwnershipFlow.analyze (function);
	assert (flow.diagnostic == null && flow.entry_state (function.blocks[block], function.locals[0]) == expected);
	assert (flow.dump () == OwnershipFlow.analyze (function).dump () && flow.iterations <= 4 * function.blocks.length);
	SsaVerifier.verify (SsaBuilder.build (control));
}

private void three_way() throws GLib.Error {
	var control = cfg (THREE_WAY);
	var flow = OwnershipFlow.analyze (control.functions[0]);
	var state = flow.entry_state (control.functions[0].blocks[3], control.functions[0].locals[0]);
	assert (flow.diagnostic == null && state == OwnershipState.join (OwnershipState.join (OwnershipState.OWNED, OwnershipState.MOVED), OwnershipState.RELEASED));
	var ssa = SsaBuilder.build (control);
	var function = ssa.functions[0];
	var join = function.blocks[3];
	assert (join.parameters.length == 1 && join.parameters[0].semantic_type.is_void_pointer ());
	assert (((SsaCleanupInstruction) join.instructions[0]).value == join.parameters[0]);
	var owning = ((SsaConditionalBranch) function.blocks[1].terminator).false_edge;
	assert (owning.target == join && owning.arguments[0] == function.entry.instructions[0].result);
	int null_inputs = 0;
	foreach (var block in function.blocks) {
		var branch = block.terminator as SsaBranch;
		if (branch != null && branch.edge.target == join) {
			assert (branch.edge.arguments.length == 1 && branch.edge.arguments[0] is SsaNullPointerConstant);
			null_inputs++;
		}
	}
	assert (null_inputs == 2 && function.storage.length == 0);
}

private void move_borrow() throws GLib.Error {
	var ssa = build ("void f() { owned void* a = create(1); inspect(a); owned void* b = move a; inspect(b); release b; }");
	var instructions = ssa.functions[0].entry.instructions;
	assert (instructions.length == 6);
	for (int i = 1; i < 3; i++) {
		assert (((SsaCCallInstruction) instructions[i]).arguments[0] == instructions[0].result);
	}
	assert (((SsaCleanupInstruction) instructions[3]).value == instructions[0].result);
	for (int i = 4; i < 6; i++) {
		assert (((SsaCleanupInstruction) instructions[i]).value is SsaNullPointerConstant);
	}
}

private void bindings() throws GLib.Error {
	var checked = check ("void f() { owned void* a = create(1); if (true) { owned void* b = create(2); release b; } else { owned void* b = create(3); release b; } inspect(a); release a; }");
	var inner = ((CheckedIf) checked.functions[0].body.statements[1]).then_body;
	assert (((CheckedOwnershipRelease) inner.statements[1]).owner == checked.functions[0].locals[1]);
	var other = ((CheckedIf) checked.functions[0].body.statements[1]).else_body;
	assert (((CheckedOwnershipRelease) other.statements[1]).owner == checked.functions[0].locals[2]);
	assert (((CheckedOwnershipRelease) checked.functions[0].body.statements[3]).owner == checked.functions[0].locals[0]);
	SsaVerifier.verify (SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (checked))));
}

private int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/release/model-identities-provenance-ssa-abi", model);
	add ("/release/conditional-pointer-phi", () => conditional (1));
	add ("/release/actual-null-conditional-pointer-phi", () => conditional (0));
	add ("/release/move-borrow-normalization", move_borrow);
	add ("/release/three-way-single-pointer-phi", three_way);
	add ("/release/exact-sibling-binding", bindings);
	add ("/release/both-arm-state", () => state_at_join ("if (c) { release a; } else { release a; }", 3, OwnershipState.RELEASED));
	add ("/release/terminating-arm", () => state_at_join ("if (c) { release a; return; } inspect(a);", 2, OwnershipState.OWNED));
	add ("/release/unreachable-predecessor", () => state_at_join ("if (c) { return; release a; } inspect(a);", 2, OwnershipState.OWNED));
	add ("/release/loop-break-state", () => state_at_join ("while (c) { release a; break; }", 3, OwnershipState.join (OwnershipState.OWNED, OwnershipState.RELEASED)));
	add ("/release/loop-return-header", () => state_at_join ("while (c) { release a; return; } inspect(a);", 1, OwnershipState.OWNED));
	add ("/release/conditional-break-header", () => state_at_join ("while (c) { if (c) { release a; break; } }", 1, OwnershipState.OWNED));
	add ("/release/all-disarmed-cleanup", () => state_at_join ("if (c) { release a; } else { owned void* b = move a; }", 3, OwnershipState.join (OwnershipState.MOVED, OwnershipState.RELEASED)));
	register_diagnostics ();
	register_lifetime ();
	foreach (string name in fixture_names ()) {
		add ("/release/pipeline/" + name, () => {
				var ssa = build (read ("release-" + name + ".astra"), fixture_declarations ());
				SsaVerifier.verify (ssa);
				CAbiVerifier.verify (CAbiBuilder.build (ssa, NativeAbiBuilder.build (ssa)));
				assert (SsaDump.format (ssa) == SsaDump.format (build (read ("release-" + name + ".astra"), fixture_declarations ())));
			});
	}
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
