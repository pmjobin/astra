// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.Rearm {
private void model() throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("rearm.astra", BASIC));
	assert (parsed.unit.functions[0].body.statements[2] is AssignmentStatementSyntax);
	var checked = check (BASIC);
	var rearm = (CheckedOwnershipRearmAssignment) checked.functions[0].body.statements[2];
	assert (rearm.owner == checked.functions[0].locals[0] && rearm.producer.target == checked.c_functions[0]);
	assert (rearm.cleanup == rearm.producer.owned_cleanup && rearm.span.text () == "a = create(2);");
	var core = CoreBuilder.build (checked);
	var statement = (CoreOwnershipRearm) core.functions[0].body.statements[2];
	assert (core.functions[0].owned_locals.length == 1 && statement.owner == core.functions[0].owned_locals[0]);
	assert (statement.cleanup == core.cleanups[0] && ((CoreCCallValue) statement.producer).target == core.c_functions[0]);
	var control = CfgBuilder.build (core);
	var function = control.functions[0];
	var event = (CfgOwnershipRearmInstruction) function.entry.instructions[4];
	var producer = (CfgCCallInstruction) function.entry.instructions[3];
	assert (event.owner == function.locals[0] && event.value == producer.result && event.cleanup == control.cleanups[0]);
	assert (event.span.text () == rearm.span.text ());
	int cleanups = 0;
	foreach (var instruction in function.entry.instructions) {
		if (instruction is CfgCleanupInstruction) {
			cleanups++;
		}
	}
	assert (cleanups == 1 && function.locals.length == 1);
	assert (OwnershipFlow.analyze (function).diagnostic == null);
	var ssa = SsaBuilder.build (control);
	var instructions = ssa.functions[0].entry.instructions;
	assert (instructions.length == 4 && instructions[0] is SsaCCallInstruction && instructions[2] is SsaCCallInstruction);
	assert (((SsaCleanupInstruction) instructions[1]).value == instructions[0].result);
	assert (((SsaCleanupInstruction) instructions[3]).value == instructions[2].result);
	assert (ssa.functions[0].storage.length == 0 && ssa.functions[0].entry.parameters.length == 0);
	assert (!SsaDump.format (ssa).contains ("ownership-rearm"));
	var baseline = build ("int f() { owned void* a = create(1); return 7; }");
	assert (NativeAbiDump.format (NativeAbiBuilder.build (ssa)) == NativeAbiDump.format (NativeAbiBuilder.build (baseline)));
	assert (CAbiDump.format (CAbiBuilder.build (ssa, NativeAbiBuilder.build (ssa))) == CAbiDump.format (CAbiBuilder.build (baseline, NativeAbiBuilder.build (baseline))));
}

private void branch(bool both) throws GLib.Error {
	var control = cfg ("void f(bool c) { owned void* a = create(1); release a; if (c) { a = create(2); } " + (both ? "else { a = variant(3); } inspect(a);" : "") + " }");
	var function = control.functions[0];
	var flow = OwnershipFlow.analyze (function);
	var join = function.blocks[both ? 3 : 2];
	assert (flow.diagnostic == null && flow.entry_state (join, function.locals[0]) == (both ? OwnershipState.OWNED : OwnershipState.join (OwnershipState.OWNED, OwnershipState.RELEASED)));
	var ssa = SsaBuilder.build (control);
	var merged = ssa.functions[0].blocks[join.ordinal];
	assert (merged.parameters.length == 1 && merged.parameters[0].semantic_type.is_void_pointer ());
	var incoming = ((SsaBranch) ssa.functions[0].blocks[1].terminator).edge.arguments[0];
	assert (incoming == ssa.functions[0].blocks[1].instructions[0].result);
	if (both) {
		assert (((SsaBranch) ssa.functions[0].blocks[2].terminator).edge.arguments[0] == ssa.functions[0].blocks[2].instructions[0].result);
	} else {
		assert (((SsaConditionalBranch) ssa.functions[0].entry.terminator).false_edge.arguments[0] is SsaNullPointerConstant);
	}
	var cleanup = (SsaCleanupInstruction) merged.instructions[merged.instructions.length - 1];
	assert (cleanup.value == merged.parameters[0]);
}

private void mixed() throws GLib.Error {
	var control = cfg ("void f(bool c) { owned void* a = create(1); if (c) { release a; } else { owned void* b = move a; } a = create(2); inspect(a); }");
	var function = control.functions[0];
	var flow = OwnershipFlow.analyze (function);
	assert (flow.diagnostic == null && flow.entry_state (function.blocks[3], function.locals[0]) == OwnershipState.join (OwnershipState.MOVED, OwnershipState.RELEASED));
	var ssa = SsaBuilder.build (control);
	foreach (int i in new int[] {1, 2}) {
		var edge = ((SsaBranch) ssa.functions[0].blocks[i].terminator).edge;
		assert (edge.arguments.length == 1 && edge.arguments[0] is SsaNullPointerConstant);
	}
	var join = ssa.functions[0].blocks[3];
	assert (((SsaCCallInstruction) join.instructions[1]).arguments[0] == join.instructions[0].result);
}

private void terminating(string body) throws GLib.Error {
	var control = cfg ("void f(bool c) { owned void* a = create(1); " + body + " a = create(2); inspect(a); }");
	assert (OwnershipFlow.analyze (control.functions[0]).diagnostic == null);
	SsaVerifier.verify (SsaBuilder.build (control));
}

private int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/rearm/model-identities-contract-slot-ssa-abi", model);
	add ("/rearm/mixed-disarmed-null-inputs", mixed);
	add ("/rearm/conditional-pointer-phi", () => branch (false));
	add ("/rearm/both-arm-pointer-phi", () => branch (true));
	add ("/rearm/terminating-owned", () => terminating ("if (c) { return; } release a;"));
	add ("/rearm/terminating-disarmed", () => terminating ("if (c) { release a; return; } release a;"));
	add ("/rearm/unreachable-owned-predecessor", () => terminating ("release a; if (c) { return; a = create(3); }"));
	register_diagnostics ();
	register_lifetime ();
	foreach (string name in fixture_names ()) {
		add ("/rearm/pipeline/" + name, () => {
				var ssa = build (read ("rearm-" + name + ".astra"), fixture_declarations ());
				SsaVerifier.verify (ssa);
				CAbiVerifier.verify (CAbiBuilder.build (ssa, NativeAbiBuilder.build (ssa)));
				assert (SsaDump.format (ssa) == SsaDump.format (build (read ("rearm-" + name + ".astra"), fixture_declarations ())));
			});
	}
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
