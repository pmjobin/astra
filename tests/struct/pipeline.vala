// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.Structs {
private void syntax_and_identity() throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("struct.astra", fixture ("struct-basic")));
	assert (parsed.diagnostic == null && parsed.unit.structs.length == 1);
	var declaration = parsed.unit.structs[0];
	assert (declaration.keyword.kind == TokenKind.STRUCT && declaration.fields.length == 2);
	assert (declaration.fields[0].semicolon.kind == TokenKind.SEMICOLON);
	var local = (StructLocalDeclarationSyntax) parsed.unit.functions[1].body.statements[0];
	assert (local.initializer.fields[0].name.spelling () == "y" && local.initializer.commas.length == 1);
	assert (local.initializer.span.text () == "{ y = 22, x = Pair(20) }");
	assert (SyntaxDump.format (parsed.unit).contains ("(field-access \"a\" \"x\")"));
	var result = SemanticAnalyzer.analyze (parsed.unit);
	assert (result.diagnostic == null);
	var program = result.program;
	var structure = program.structs[0];
	assert (structure.semantic_type is StructType && structure.semantic_type.display_name () == "Pair");
	assert (structure.fields[0].ordinal == 0 && structure.fields[1].ordinal == 1);
	assert (structure.fields[0].containing_struct == structure && structure.fields[0].name_span.text () == "x");
	assert (structure.span.text () == declaration.span.text ());
	assert (program.functions[0].symbol.name == structure.name);
	var function = program.functions[1];
	assert (function.locals[0].semantic_type == structure.semantic_type && function.locals[1].semantic_type == structure.semantic_type);
	var initialized = (CheckedStructLocalDeclaration) function.body.statements[0];
	assert (initialized.local == function.locals[0]);
	assert (initialized.initializers[0].field == structure.fields[1] && initialized.initializers[1].field == structure.fields[0]);
	var assignment = (CheckedFieldAssignment) function.body.statements[3];
	assert (assignment.local == function.locals[0] && assignment.field == structure.fields[0]);
	var value = (CheckedBinaryExpression) assignment.expression;
	var left = (CheckedFieldReferenceExpression) value.left;
	var right = (CheckedFieldReferenceExpression) value.right;
	assert (left.local == function.locals[0] && left.field == structure.fields[0] && left.span.text () == "a.x");
	assert (right.local == function.locals[1] && right.field == structure.fields[1]);
	assert (SemanticDump.format (program).contains ("(initialize-field #1 \"y\" (integer 22 : int))"));
	var nominal = check ("struct A { int value; } struct B { int value; } struct C { bool value; }");
	assert (nominal.structs[0].semantic_type != nominal.structs[1].semantic_type);
	assert (nominal.structs[0].fields[0] != nominal.structs[1].fields[0]);
	assert (nominal.structs[2].fields[0].semantic_type == nominal.types.bool_type);
}

private void canonical_projection() throws GLib.Error {
	var program = check ("struct Pair { int x; int y; } int f() { Pair a = { y = 2, x = 1 }; Pair b = { x = 3, y = 4 }; a.x = a.x + a.x; return a.x + b.x; }");
	var core = CoreBuilder.build (program);
	CoreVerifier.verify (core);
	var function = core.functions[0];
	assert (function.locals.length == 2 && function.field_places.length == 4);
	var ax = function.field_places[0];
	var bx = function.field_places[2];
	assert (ax != bx && ax.field == bx.field && ax.aggregate != bx.aggregate);
	assert (ax.aggregate == function.locals[0] && bx.aggregate == function.locals[1]);
	assert (ax.field == core.structs[0].fields[0]);
	assert ((Object) ax.field != (Object) program.structs[0].fields[0]);
	assert (((CoreInitialize) function.body.statements[0]).target == function.field_places[1]);
	var store = (CoreStore) function.body.statements[4];
	var sum = (CoreBinaryValue) store.value;
	assert (store.target == ax && ((CoreLoadValue) sum.left).source == ax && ((CoreLoadValue) sum.right).source == ax);
	assert (ax.span.text ().has_prefix ("Pair a") && ax.field.name_span.text () == "x");
	assert (CoreDump.format (core).contains ("(field-place (base struct-local-place #0 : Pair) (field #0 \"x\") : int)"));
	var cfg = CfgBuilder.build (core);
	CfgVerifier.verify (cfg);
	assert (CfgFlowChecker.check (cfg).diagnostic == null);
	var lowered = cfg.functions[0];
	assert (lowered.locals.length == 2 && lowered.field_places.length == 4);
	var projected = lowered.field_places[0];
	assert (projected.aggregate == lowered.locals[0] && projected.field == cfg.structs[0].fields[0]);
	assert ((Object) projected.field != (Object) ax.field && (Object) projected.aggregate != (Object) ax.aggregate);
	assert (projected != lowered.field_places[2] && projected.field == lowered.field_places[2].field);
	var cfg_store = (CfgStore) lowered.entry.instructions[4];
	var cfg_sum = (CfgBinaryValue) cfg_store.value;
	assert (cfg_store.target == projected && ((CfgLoadValue) cfg_sum.left).source == projected && ((CfgLoadValue) cfg_sum.right).source == projected);
	assert (CfgDump.format (cfg).contains ("(field-place (base struct-local-place #1 : Pair) (field #0 \"x\") : int)"));
}

private void branch_promotion() throws GLib.Error {
	var ssa = build (fixture ("struct-branch"));
	var choose = ssa.functions[0];
	var join = choose.blocks[3];
	assert (join.parameters.length == 1 && join.parameters[0].name == "p.x");
	assert (join.parameters[0].origin_kind == SsaPromotionOrigin.FIELD && join.parameters[0].source_field_ordinal == 0);
	assert (((SsaIntegerConstant) ((SsaBranch) choose.blocks[1].terminator).edge.arguments[0]).value.to_string () == "1");
	assert (((SsaIntegerConstant) ((SsaBranch) choose.blocks[2].terminator).edge.arguments[0]).value.to_string () == "2");
	var addition = (SsaBinaryInstruction) join.instructions[0];
	assert (addition.left == join.parameters[0] && ((SsaIntegerConstant) addition.right).value.to_string () == "10");
	var multiple = ssa.functions[1].blocks[3];
	assert (multiple.parameters.length == 2 && multiple.parameters[0].name == "p.x" && multiple.parameters[1].name == "p.y");
	assert (multiple.parameters[0] != multiple.parameters[1] && multiple.parameters[1].source_field_ordinal == 1);
	assert (SsaDump.format (ssa) == SsaDump.format (build (fixture ("struct-branch"))));
}

private void promotion_order() throws GLib.Error {
	var ssa = build ("struct P { int x; bool b; } int f(bool c) { P p = { b = false, x = 0 }; int z = 0; P q = { x = 1, b = true }; if (c) { q.b = false; p.x = 2; z = 3; q.x = 4; p.b = true; } return z + p.x + q.x; }");
	var parameters = ssa.functions[0].blocks[2].parameters;
	assert (parameters.length == 5);
	string[] names = {
		"z", "p.x", "p.b", "q.x", "q.b"
	};
	for (int i = 0; i < names.length; i++) {
		assert (parameters[i].name == names[i]);
	}
	assert (parameters[0].source_local_ordinal == 1 && parameters[1].source_local_ordinal == 0 && parameters[3].source_local_ordinal == 2);
}

private void loop_pointer_scope() throws GLib.Error {
	var loop = build (fixture ("struct-loop"));
	var header = loop.functions[0].blocks[1];
	assert (header.parameters.length == 2 && header.parameters[0].name == "c.value" && header.parameters[1].name == "c.flip");
	assert (header.parameters[0].semantic_type.kind == TypeKind.INT && header.parameters[1].semantic_type.kind == TypeKind.BOOL);
	var transfer_header = loop.functions[1].blocks[1];
	assert (transfer_header.parameters.length == 3 && transfer_header.parameters[0].name == "sum");
	foreach (var parameter in transfer_header.parameters) {
		assert (!parameter.name.has_prefix ("body."));
	}
	var pointers = build (fixture ("struct-pointer"));
	var join = pointers.functions[0].blocks[3];
	assert (join.parameters.length == 2 && join.parameters[0].semantic_type.kind == TypeKind.RAW_POINTER && join.parameters[1].semantic_type.kind == TypeKind.BOOL);
	var scope = build (fixture ("struct-scope"));
	assert (scope.functions[0].blocks[3].parameters.length == 1 && scope.functions[0].blocks[3].parameters[0].name == "result");
	foreach (var program in new SsaProgram[] {loop, pointers, scope}) {
		SsaVerifier.verify (program);
		foreach (var function in program.functions) {
			assert (function.return_type.kind != TypeKind.STRUCT);
			foreach (var block in function.blocks) {
				foreach (var parameter in block.parameters) {
					assert (parameter.semantic_type.kind != TypeKind.STRUCT);
				}
				foreach (var instruction in block.instructions) {
					assert (instruction.result == null || instruction.result.semantic_type.kind != TypeKind.STRUCT);
				}
			}
		}
		string dump = SsaDump.format (program);
		assert (!dump.contains ("undef") && !dump.contains ("poison") && !dump.contains ("struct-local") && !dump.contains ("field-place"));
	}
}

private void ordered_initialization() throws GLib.Error {
	var core = CoreBuilder.build (check (fixture ("struct-trap")));
	var body = core.functions[0].body;
	assert (((CoreFieldPlace) ((CoreInitialize) body.statements[0]).target).field.ordinal == 1);
	assert (((CoreFieldPlace) ((CoreInitialize) body.statements[1]).target).field.ordinal == 0);
	var cfg = CfgBuilder.build (core);
	var instructions = cfg.functions[0].entry.instructions;
	assert (instructions[0] is CfgCCallInstruction && instructions[1] is CfgInitialize);
	assert (instructions[2] is CfgEvaluateInstruction && instructions[3] is CfgCCallInstruction && instructions[4] is CfgInitialize);
	assert (((CfgBinaryValue) ((CfgEvaluateInstruction) instructions[2]).value).operator_kind == BinaryOperator.DIVIDE);
	var short_cfg = CfgBuilder.build (CoreBuilder.build (check ("extern(C) int record(int n); struct S { bool b; int x; } int f(bool c) { S s = { b = c && record(1) != 0, x = record(2) }; return s.x; }")));
	var function = short_cfg.functions[0];
	int initialization_block = -1;
	foreach (var block in function.blocks) {
		for (int i = 0; i < block.instructions.length; i++) {
			var initialization = block.instructions[i] as CfgInitialize;
			if (initialization != null && initialization.target == function.field_places[0]) {
				initialization_block = block.ordinal;
				assert (block.instructions[i + 1] is CfgCCallInstruction && block.instructions[i + 2] is CfgInitialize);
			}
		}
	}
	assert (initialization_block > 0 && function.blocks[initialization_block].instructions[0] is CfgInitialize);
	SsaVerifier.verify (SsaBuilder.build (short_cfg));
}

private void abi_unchanged() throws GLib.Error {
	var aggregate = build ("struct P { int x; bool b; void* p; } int f(int x, bool c) { P a = { p = null, b = c, x = x }; if (a.b) { return a.x; } return 0; }");
	var scalar = build ("int f(int x, bool c) { void* p = null; bool b = c; int a = x; if (b) { return a; } return 0; }");
	var aggregate_nabi = NativeAbiBuilder.build (aggregate);
	var scalar_nabi = NativeAbiBuilder.build (scalar);
	assert (NativeAbiDump.format (aggregate_nabi) == NativeAbiDump.format (scalar_nabi));
	assert (CAbiDump.format (CAbiBuilder.build (aggregate, aggregate_nabi)) == CAbiDump.format (CAbiBuilder.build (scalar, scalar_nabi)));
	foreach (string name in new string[] {"struct-basic", "struct-order", "struct-branch", "struct-loop", "struct-pointer", "struct-scope", "struct-trap"}) {
		var ssa = build (fixture (name));
		var nabi = NativeAbiBuilder.build (ssa);
		NativeAbiVerifier.verify (nabi);
		CAbiVerifier.verify (CAbiBuilder.build (ssa, nabi));
	}
}

private int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/struct/syntax-semantic-identity", syntax_and_identity);
	add ("/struct/canonical-core-cfg-projection", canonical_projection);
	add ("/struct/branch-independent-promotion", branch_promotion);
	add ("/struct/promotion-order", promotion_order);
	add ("/struct/loop-pointer-scope", loop_pointer_scope);
	add ("/struct/ordered-initialization", ordered_initialization);
	add ("/struct/abi-unchanged", abi_unchanged);
	register_diagnostics ();
	register_lifetime ();
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
