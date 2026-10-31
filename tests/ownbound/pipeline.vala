// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.Ownbound {
private void contracts() throws GLib.Error {
	var checked = check (BASIC);
	var function = checked.functions[0];
	assert (function.symbol.result_contract == ResultOwnershipContract.OWNED_TRANSFER);
	assert (function.symbol.parameters[0].pointer_contract == PointerParameterContract.OWNED_TRANSFER);
	assert (function.symbol.return_type == function.symbol.parameters[0].semantic_type);
	assert (function.locals[0].incoming_parameter == function.symbol.parameters[0]);
	assert (function.locals[0].lexical_region == function.body.region);
	assert (function.locals[0].cleanup == checked.handles[0].cleanup);
	var returned = (CheckedOwnershipReturn) function.body.statements[0];
	assert (returned.transfer.source == function.locals[0] && returned.cleanup == function.symbol.owned_cleanup);
	var fresh = (CheckedOwnedLocalDeclaration) checked.functions[1].body.statements[1];
	var call = (CheckedCallExpression) fresh.initializer;
	assert (call.owned_producer.kind == OwnedProducerKind.NATIVE_OWNED_CALL && call.owned_cleanup == fresh.local.cleanup);
	var argument = (CheckedOwnedArgument) call.arguments[0];
	assert (argument.parameter == function.symbol.parameters[0] && argument.transfer.source == checked.functions[1].locals[0]);
	var core = CoreBuilder.build (checked);
	CoreVerifier.verify (core);
	assert (core.functions[0].body.statements[0] is CoreAcquireParameter);
	assert (core.functions[0].body.statements[1] is CoreOwnershipReturn);
	assert (core.functions[0].owned_locals[0].place.incoming_parameter == core.functions[0].parameters[0]);
	assert (core.functions[0].owned_cleanup == core.handles[0].cleanup);
}
private void ordering() throws GLib.Error {
	var control = cfg ("void consume(int n, owned Resource r, int m) { } void f() { owned Resource r = create(1); consume(inspect(r), move r, inspect(null)); }", TYPES + API);
	CfgVerifier.verify (control);
	assert (CfgFlowChecker.check (control).diagnostic == null);
	var instructions = control.functions[1].entry.instructions;
	int capture = -1;
	int later = -1;
	int commit = -1;
	int invoke = -1;
	for (int i = 0; i < instructions.length; i++) {
		if (instructions[i] is CfgOwnedArgumentCapture) {
			capture = i;
		}
		if (instructions[i] is CfgCCallInstruction && capture >= 0) {
			later = i;
		}
		if (instructions[i] is CfgOwnedCallTransferCommit) {
			commit = i;
		}
		if (instructions[i] is CfgCallInstruction) {
			invoke = i;
		}
	}
	assert (capture > 0 && capture < later && later < commit && invoke == commit + 1);
	var pending = ((CfgOwnedArgumentCapture) instructions[capture]).transfer;
	assert (((CfgOwnedCallTransferCommit) instructions[commit]).transfers[0] == pending);
	var ssa = SsaBuilder.build (control);
	SsaCallInstruction? native = null;
	foreach (var instruction in ssa.functions[1].entry.instructions) {
		if (instruction is SsaCallInstruction) {
			native = (SsaCallInstruction) instruction;
		}
	}
	assert (native != null && native.owned_arguments.length == 1);
	assert (native.owned_arguments[0].value == native.arguments[1]);
	assert (native.owned_arguments[0].source_after_commit is SsaNullPointerConstant);
	var last = (SsaCleanupInstruction) ssa.functions[1].entry.instructions[ssa.functions[1].entry.instructions.length - 1];
	assert (last.value is SsaNullPointerConstant);
}
private void returned_pointer() throws GLib.Error {
	var ssa = build (BASIC);
	var pass = ssa.functions[0];
	assert (pass.storage.length == 0);
	assert (((SsaReturn) pass.entry.terminator).value == pass.parameters[0]);
	assert (pass.entry.terminator is SsaOwnershipReturn);
	assert (((SsaCleanupInstruction) pass.entry.instructions[0]).value is SsaNullPointerConstant);
	int acquire = 0;
	int rearm = 0;
	foreach (var instruction in ssa.functions[1].entry.instructions) {
		var call = instruction as SsaCallInstruction;
		if (call == null) {
			continue;
		}
		if (call.owned_result_use == SsaOwnedResultUse.ACQUIRE) {
			acquire++;
		}
		if (call.owned_result_use == SsaOwnedResultUse.REARM) {
			rearm++;
		}
	}
	assert (acquire == 1 && rearm == 1);
}
private void physical() throws GLib.Error {
	string? reference = null;
	foreach (string qualifier in new string[] {"", "borrowed ", "owned "}) {
		var ssa = build ("void consume(" + qualifier + "Resource r) { }", TYPES);
		var dump = NativeAbiDump.format (NativeAbiBuilder.build (ssa));
		if (reference == null) {
			reference = dump;
		} else {
			assert (reference == dump);
		}
		assert (dump.contains ("scalar-ptr-v1") && dump.contains ("ptr"));
	}
	var owned_result = build ("owned Resource make() { return null; }", TYPES);
	var unmanaged_result = build ("Resource make() { return null; }", TYPES);
	assert (NativeAbiDump.format (NativeAbiBuilder.build (owned_result)) == NativeAbiDump.format (NativeAbiBuilder.build (unmanaged_result)));
	var nabi = NativeAbiBuilder.build (build (BASIC));
	NativeAbiVerifier.verify (nabi);
	var ssa = build (BASIC);
	CAbiVerifier.verify (CAbiBuilder.build (ssa, NativeAbiBuilder.build (ssa)));
}
private int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/ownbound/contracts/checked-core", contracts);
	add ("/ownbound/order/capture-evaluate-commit-call", ordering);
	add ("/ownbound/ssa/return-capture-and-disarm", returned_pointer);
	add ("/ownbound/nabi/physical-erasure", physical);
	add ("/ownbound/order/null-test-before-move", () => build ("void consume(bool c, owned Resource r) { } void f(owned Resource r) { consume(r == null, move r); }"));
	add ("/ownbound/order/nested-move-after-read", () => build ("bool consume(owned Resource r) { return true; } void use(bool a, bool b) { } void f(owned Resource r) { use(r == null, consume(move r)); }"));
	add ("/ownbound/order/binary-read-before-move", () => build ("bool consume(owned Resource r) { return true; } bool f(owned Resource r) { return (r == null) == consume(move r); }"));
	add ("/ownbound/rearm/parameter-from-own-call", () => build ("owned Resource pass(owned Resource r) { return move r; } void f(owned Resource r) { r = pass(move r); }"));
	add ("/ownbound/order/trap-before-commit", () => {
			var program = cfg ("void consume(owned Resource r, int n) { } void f(owned Resource r, int n) { consume(move r, 1 / n); }");
			var instructions = program.functions[1].entry.instructions;
			int division = -1;
			for (int i = 0; i < instructions.length; i++) {
				var evaluation = instructions[i] as CfgEvaluateInstruction;
				if (evaluation != null && evaluation.value is CfgBinaryValue) {
					division = i;
				}
				if (instructions[i] is CfgOwnedCallTransferCommit) {
					assert (division > 0 && division < i && instructions[i + 1] is CfgCallInstruction);
				}
			}
		});
	register_diagnostics ();
	register_lifetime ();
	foreach (string name in fixture_names ()) {
		add ("/ownbound/fixture/" + name, () => SsaVerifier.verify (build (read (name + ".astra"), fixture_declarations (name))));
	}
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
