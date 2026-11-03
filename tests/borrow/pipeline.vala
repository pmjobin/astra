// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.Borrows {
private void storage_and_promotion() throws GLib.Error {
	var core = CoreBuilder.build (check (fixture ("borrow-reassign")));
	CoreVerifier.verify (core);
	var function = core.functions[0];
	assert (function.locals.length == 3 && function.locals[2].is_promotable ());
	assert (function.locals[0].address_taken && function.locals[1].address_taken);
	foreach (var field in function.field_places) {
		assert (!field.is_promotable ());
	}
	var initialize = (CoreInitialize) function.body.statements[4];
	assert (initialize.target == function.locals[2] && ((CoreAddressOfValue) initialize.value).target == function.locals[0]);
	var reassign = (CoreStore) function.body.statements[6];
	assert (reassign.target == function.locals[2] && ((CoreAddressOfValue) reassign.value).target == function.locals[1]);
	assert (!CoreDump.format (core).contains ("region"));
	var cfg = CfgBuilder.build (core);
	CfgVerifier.verify (cfg);
	assert (cfg.functions[0].locals[2].is_promotable ());
	var cfg_instructions = cfg.functions[0].entry.instructions;
	var first_address = (CfgEvaluateInstruction) cfg_instructions[4];
	var second_address = (CfgEvaluateInstruction) cfg_instructions[7];
	assert (((CfgAddressOfValue) first_address.value).target == cfg.functions[0].locals[0]);
	assert (((CfgAddressOfValue) second_address.value).target == cfg.functions[0].locals[1]);
	assert (((CfgInitialize) cfg_instructions[5]).value == first_address.result);
	assert (((CfgStore) cfg_instructions[8]).value == second_address.result);
	assert (!CfgDump.format (cfg).contains ("region"));
	var ssa = SsaBuilder.build (cfg);
	var instructions = ssa.functions[0].entry.instructions;
	assert (ssa.functions[0].storage.length == 2);
	assert (instructions[4] is SsaAddressOfInstruction && instructions[6] is SsaAddressOfInstruction);
	assert (((SsaIndirectFieldPlace) ((SsaStoreInstruction) instructions[5]).target).pointer == instructions[4].result);
	assert (((SsaIndirectFieldPlace) ((SsaStoreInstruction) instructions[7]).target).pointer == instructions[6].result);
	assert (!SsaDump.format (ssa).contains ("region"));
	var mixed = build (fixture ("borrow-mixed")).functions[0];
	assert (mixed.storage.length == 1 && mixed.storage[0].name == "referent");
	int fields = 0;
	foreach (var block in mixed.blocks) {
		foreach (var parameter in block.parameters) {
			if (parameter.origin_kind == SsaPromotionOrigin.FIELD) {
				assert (parameter.name == "untouched.x");
				fields++;
			}
		}
	}
	assert (fields == 1);
}

private void branch_merge() throws GLib.Error {
	var function = build (fixture ("borrow-branch")).functions[0];
	var left = function.blocks[1];
	var right = function.blocks[2];
	var join = function.blocks[3];
	assert (join.parameters.length == 1 && join.parameters[0].name == "p" && join.parameters[0].semantic_type.is_struct_pointer ());
	assert (((SsaAddressOfInstruction) left.instructions[0]).target == function.storage[0]);
	assert (((SsaAddressOfInstruction) right.instructions[0]).target == function.storage[1]);
	assert (((SsaBranch) left.terminator).edge.target == join && ((SsaBranch) right.terminator).edge.target == join);
	assert (((SsaBranch) left.terminator).edge.arguments[0] == left.instructions[0].result);
	assert (((SsaBranch) right.terminator).edge.arguments[0] == right.instructions[0].result);
	assert (((SsaIndirectFieldPlace) ((SsaStoreInstruction) join.instructions[0]).target).pointer == join.parameters[0]);
}

private void null_merge() throws GLib.Error {
	var function = build (DECLARATIONS + "bool f(bool c) { Pair pair = { x = 1, y = 2 }; Pair* p = null; if (c) { p = &pair; } return p == null; }").functions[0];
	var split = (SsaConditionalBranch) function.entry.terminator;
	var join = function.blocks[2];
	assert (join.parameters.length == 1 && join.parameters[0].semantic_type.is_struct_pointer ());
	assert (split.false_edge.target == join && split.false_edge.arguments[0] is SsaNullPointerConstant);
	assert (((SsaBranch) function.blocks[1].terminator).edge.arguments[0] == function.blocks[1].instructions[0].result);
	assert (((SsaBinaryInstruction) join.instructions[0]).left == join.parameters[0]);
}

private void loop_flow() throws GLib.Error {
	var function = build (fixture ("borrow-loop")).functions[0];
	var header = function.blocks[1];
	assert (header.parameters[0].name == "p" && header.parameters[0].semantic_type.is_struct_pointer ());
	int addresses = 0;
	int retained = 0;
	foreach (var block in function.blocks) {
		var branch = block.terminator as SsaBranch;
		if (branch == null || branch.edge.target != header) {
			continue;
		}
		var value = branch.edge.arguments[0];
		if (value == header.parameters[0]) {
			retained++;
		} else {
			bool found = false;
			foreach (var instruction in block.instructions) {
				if (instruction is SsaAddressOfInstruction && instruction.result == value) {
					found = true;
				}
			}
			assert (found);
			addresses++;
		}
	}
	assert (addresses == 2 && retained == 1);
}

private void abi() throws GLib.Error {
	var ssa = build (fixture ("borrow-transitive"));
	var nabi = NativeAbiBuilder.build (ssa);
	assert (nabi.abi_version == NativeAbiVersion.SCALAR_PTR_V1);
	assert (nabi.functions[0].signature.parameters[0].scalar_type == NativeScalarType.PTR);
	assert (nabi.functions[1].signature.parameters[0].scalar_type == NativeScalarType.PTR);
	NativeAbiVerifier.verify (nabi);
	var cabi = CAbiBuilder.build (ssa, nabi);
	CAbiVerifier.verify (cabi);
	assert (cabi.functions.length == 0);
	try {
		CAbiTypeMapper.map_scalar (ssa.functions[0].parameters[0].semantic_type);
		assert_not_reached ();
	} catch (CAbiError.INVALID_TYPE error) {
		assert (error.message.contains ("typed native struct pointers"));
	}
}

private int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	register_regions ();
	register_diagnostics ();
	register_lifetime ();
	add ("/borrow/storage-promotion", storage_and_promotion);
	add ("/borrow/branch-merge", branch_merge);
	add ("/borrow/null-merge", null_merge);
	add ("/borrow/loop-flow", loop_flow);
	add ("/borrow/abi", abi);
	foreach (string fixture in new string[] {"basic", "copy", "reassign", "late", "branch", "null", "loop", "scopes", "recursive", "transitive", "alias", "mixed"}) {
		string name = "borrow-" + fixture;
		add ("/borrow/pipeline/" + name, () => {
				var ssa = build (Borrows.fixture (name));
				SsaVerifier.verify (ssa);
				assert (SsaDump.format (ssa) == SsaDump.format (build (Borrows.fixture (name))));
				var nabi = NativeAbiBuilder.build (ssa);
				NativeAbiVerifier.verify (nabi);
				CAbiVerifier.verify (CAbiBuilder.build (ssa, nabi));
			});
	}
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
