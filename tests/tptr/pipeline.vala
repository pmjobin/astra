// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.TypedPointers {

private void syntax_identity() throws GLib.Error {
	var lexer = new Lexer (new SourceFile.from_text ("tokens", "& && -> -"));
	foreach (var kind in new TokenKind[] {TokenKind.AMPERSAND, TokenKind.AMPERSAND_AMPERSAND, TokenKind.ARROW, TokenKind.MINUS, TokenKind.EOF}) {
		assert (lexer.next_token ().kind == kind);
	}
	var parsed = Parser.parse (new SourceFile.from_text ("tptr", SIMPLE));
	assert (parsed.diagnostic == null);
	assert (parsed.unit.functions[0].parameters[0].type_name.spelling () == "Pair*");
	var assignment = (FieldAssignmentStatementSyntax) parsed.unit.functions[0].body.statements[0];
	assert (assignment.target.indirect && assignment.target.dot.kind == TokenKind.ARROW);
	var call = ((CallStatementSyntax) parsed.unit.functions[1].body.statements[2]).call;
	assert (call.arguments[0] is AddressOfExpressionSyntax);
	assert (((AddressOfExpressionSyntax) call.arguments[0]).identifier.spelling () == "p");
	assert (SyntaxDump.format (parsed.unit).contains ("(address-of \"p\")"));
	var program = check (SIMPLE);
	var pointer = (TypedPointerType) program.functions[0].symbol.parameters[0].semantic_type;
	assert (pointer.pointee == program.structs[0].semantic_type);
	assert (program.types.pointer_to (pointer.pointee) == pointer);
	assert ((SemanticType) pointer != program.types.raw_pointer_type && pointer.display_name () == "Pair*");
	var local = program.functions[1].locals[0];
	assert (local.address_taken);
	var borrow = (CheckedAddressOfExpression) ((CheckedCallStatement) program.functions[1].body.statements[2]).arguments[0];
	assert (borrow.local == local && borrow.semantic_type == pointer && borrow.span.text () == "&p");
	var indirect = (CheckedIndirectFieldAssignment) program.functions[0].body.statements[0];
	assert (((CheckedParameterReferenceExpression) indirect.pointer).parameter == program.functions[0].symbol.parameters[0]);
	assert (indirect.field == program.structs[0].fields[0]);
	var nominal = check ("void f(A* a, A /* lexical */ * other, B* b) {} struct A { int x; } struct B { int x; }");
	var parameters = nominal.functions[0].symbol.parameters;
	assert (parameters[0].semantic_type == parameters[1].semantic_type && parameters[0].semantic_type != parameters[2].semantic_type);
	assert (program.types.pointer_to (pointer.pointee) != nominal.types.pointer_to (nominal.structs[0].semantic_type));
}

private void contextual_null() throws GLib.Error {
	var program = check ("struct P { int x; } void take(P* p) {} bool f(P* p) { P* q = null; q = (null); take(null); return p == null && null != q; } bool defaults() { return null == null; } void* opaque() { return null; }");
	var function = program.functions[1];
	var type = function.symbol.parameters[0].semantic_type;
	assert (((CheckedLocalDeclaration) function.body.statements[0]).initializer.semantic_type == type);
	assert (((CheckedAssignment) function.body.statements[1]).expression.semantic_type == type);
	assert (((CheckedCallStatement) function.body.statements[2]).arguments[0].semantic_type == type);
	var equality = (CheckedShortCircuitExpression) ((CheckedReturnStatement) function.body.statements[3]).expression;
	assert (((CheckedBinaryExpression) equality.left).right.semantic_type == type);
	assert (((CheckedBinaryExpression) equality.right).left.semantic_type == type);
	var defaults = (CheckedBinaryExpression) ((CheckedReturnStatement) program.functions[2].body.statements[0]).expression;
	assert (defaults.left.semantic_type == program.types.raw_pointer_type && defaults.right.semantic_type == program.types.raw_pointer_type);
	assert (program.functions[3].symbol.return_type == program.types.raw_pointer_type);
	SsaVerifier.verify (SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (program))));
}

private void storage_authority() throws GLib.Error {
	var core = CoreBuilder.build (check (SIMPLE));
	CoreVerifier.verify (core);
	var main = core.functions[1];
	var local = main.locals[0];
	assert (local.address_taken && !local.is_promotable () && main.locals[1].is_promotable ());
	foreach (var place in main.field_places) {
		assert (!place.is_promotable () && place.aggregate == local);
	}
	var address = (CoreAddressOfValue) ((CoreCallStatement) main.body.statements[3]).arguments[0];
	assert (address.target == local && ((TypedPointerType) address.semantic_type).pointee == local.semantic_type);
	var indirect = (CoreIndirectFieldPlace) ((CoreStore) core.functions[0].body.statements[0]).target;
	assert (!indirect.is_promotable () && indirect.field == main.field_places[0].field);
	assert (((CoreParameterValue) indirect.pointer).parameter == core.functions[0].parameters[0]);
	assert (CoreDump.format (core).contains ("address-taken"));
	var cfg = CfgBuilder.build (core);
	CfgVerifier.verify (cfg);
	var cfg_main = cfg.functions[1];
	assert (cfg_main.locals[0].address_taken && !cfg_main.field_places[0].is_promotable ());
	var cfg_indirect = (CfgIndirectFieldPlace) ((CfgStore) cfg.functions[0].entry.instructions[0]).target;
	assert (cfg_indirect.field == cfg.structs[0].fields[0]);
	assert ((Object) cfg_indirect.field != (Object) indirect.field);
	assert (CfgDump.format (cfg).contains ("address-of") && CfgDump.format (cfg).contains ("address-taken"));
	var ssa = SsaBuilder.build (cfg);
	var body = ssa.functions[1].entry.instructions;
	assert (body[0] is SsaInitializeInstruction && body[1] is SsaInitializeInstruction);
	assert (((SsaFieldPlace) ((SsaInitializeInstruction) body[0]).target).field.ordinal == 1);
	assert (((SsaFieldPlace) ((SsaInitializeInstruction) body[1]).target).field.ordinal == 0);
	assert (body[2] is SsaLoadInstruction && body[3] is SsaAddressOfInstruction && body[4] is SsaCallInstruction && body[5] is SsaLoadInstruction);
	var before = (SsaLoadInstruction) body[2];
	var after = (SsaLoadInstruction) body[5];
	assert (before.source == after.source && before.result != after.result);
	assert (((SsaDirectFieldPlace) before.source).storage == ssa.functions[1].storage[0]);
	assert (((SsaAddressOfInstruction) body[3]).target == ssa.functions[1].storage[0]);
	assert (((SsaCallInstruction) body[4]).arguments[0] == body[3].result);
	assert (((SsaIndirectFieldPlace) ((SsaStoreInstruction) ssa.functions[0].entry.instructions[0]).target).pointer == ssa.functions[0].parameters[0]);
	assert ((Object) ssa.structs[0].fields[0] != (Object) cfg.structs[0].fields[0]);
}

private void mixed_promotion() throws GLib.Error {
	var ssa = build (fixture ("tptr-mixed-storage"));
	var mixed = ssa.functions[1];
	assert (mixed.storage.length == 1 && mixed.storage[0].name == "b");
	int fields = 0;
	foreach (var block in mixed.blocks) {
		foreach (var parameter in block.parameters) {
			if (parameter.origin_kind == SsaPromotionOrigin.FIELD) {
				assert (parameter.name == "a.x");
				fields++;
			}
		}
	}
	assert (fields == 1);
	assert (ssa.functions[2].storage.length == 1 && ssa.functions[2].storage[0].name == "p");
	assert (ssa.functions[2].entry.instructions[2] is SsaStoreInstruction);
	assert (ssa.functions[3].storage.length == 1);
	var untouched = build ("struct P { int x; } int f(bool c) { P p = { x = 1 }; if (c) { p.x = 2; } return p.x; }");
	assert (untouched.structs.length == 0 && untouched.functions[0].storage.length == 0);
	foreach (var block in untouched.functions[0].blocks) {
		foreach (var instruction in block.instructions) {
			assert (!(instruction is SsaLoadInstruction || instruction is SsaStoreInstruction || instruction is SsaInitializeInstruction || instruction is SsaAddressOfInstruction));
		}
	}
	var promoted = build ("struct P { int x; } int f(P* p) { P* q = p; return q->x; }");
	assert (promoted.functions[0].storage.length == 0 && promoted.functions[0].entry.instructions.length == 1);
	var load = (SsaLoadInstruction) promoted.functions[0].entry.instructions[0];
	assert (((SsaIndirectFieldPlace) load.source).pointer == promoted.functions[0].parameters[0]);
	var merge = build ("struct P { int x; } int f(P* p, P* q, bool c) { P* r = p; if (c) { r = q; } return r->x; }");
	var join = merge.functions[0].blocks[2];
	assert (join.parameters.length == 1 && join.parameters[0].semantic_type.is_struct_pointer ());
	assert (((SsaIndirectFieldPlace) ((SsaLoadInstruction) join.instructions[0]).source).pointer == join.parameters[0]);
}

private void order_and_abi() throws GLib.Error {
	var ssa = build ("struct P { int x; } int effect() { return 42; } void write(P* p) { p->x = effect(); } int ordered(P* p, int n) { return 1 / n + p->x; }");
	var body = ssa.functions[1].entry.instructions;
	assert (body.length == 2 && body[0] is SsaCallInstruction && body[1] is SsaStoreInstruction);
	assert (((SsaStoreInstruction) body[1]).value == body[0].result);
	var ordered = ssa.functions[2].entry.instructions;
	assert (ordered[0] is SsaBinaryInstruction && ((SsaBinaryInstruction) ordered[0]).operator_kind == BinaryOperator.DIVIDE);
	assert (ordered[1] is SsaLoadInstruction);
	var nabi = NativeAbiBuilder.build (ssa);
	assert (nabi.abi_version == NativeAbiVersion.SCALAR_PTR_V1);
	assert (NativeAbiBuilder.build (build ("int f() { return 1; }")).abi_version == NativeAbiVersion.SCALAR_V0);
	assert (nabi.functions[0].signature.abi_version == NativeAbiVersion.SCALAR_PTR_V1);
	assert (nabi.functions[1].signature.parameters[0].scalar_type == NativeScalarType.PTR);
	assert (NativeTypeMapper.map_scalar (ssa.functions[1].parameters[0].semantic_type) == NativeScalarType.PTR);
	assert (CAbiBuilder.build (ssa, nabi).functions.length == 0);
	try {
		CAbiTypeMapper.map_scalar (ssa.functions[1].parameters[0].semantic_type);
		assert_not_reached ();
	} catch (CAbiError.INVALID_TYPE error) {
		assert (error.message.contains ("typed native struct pointers"));
	}
	assert (CAbiTypeMapper.map_scalar (new BuiltinTypes ().raw_pointer_type) == CAbiScalarType.PTR);
}

private int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/tptr/syntax-identity", syntax_identity);
	add ("/tptr/contextual-null", contextual_null);
	add ("/tptr/storage-authority", storage_authority);
	add ("/tptr/mixed-promotion", mixed_promotion);
	add ("/tptr/order-abi", order_and_abi);
	foreach (string fixture in new string[] {"tptr-basic", "tptr-alias", "tptr-null", "tptr-recursive", "tptr-loop", "tptr-mixed-storage", "tptr-order"}) {
		string name = fixture;
		add ("/tptr/pipeline/" + name, () => {
				var first = build (TypedPointers.fixture (name));
				assert (SsaDump.format (first) == SsaDump.format (build (TypedPointers.fixture (name))));
				var nabi = NativeAbiBuilder.build (first);
				NativeAbiVerifier.verify (nabi);
				CAbiVerifier.verify (CAbiBuilder.build (first, nabi));
			});
	}
	register_diagnostics ();
	register_lifetime ();
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
