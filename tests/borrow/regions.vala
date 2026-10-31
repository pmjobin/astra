// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;

namespace Astra.Tests.Borrows {
private const string REGION_SOURCE = DECLARATIONS + "void f(Pair* parameter) { Pair pair = { x = 1, y = 2 }; Pair* p = &pair; if (true) { Pair* q = p; while (false) { Pair* r = parameter; } } else { Pair inner = { x = 3, y = 4 }; Pair* t = &inner; } while (false) { Pair* v = null; } } void g() {}";

private void region_tree() throws GLib.Error {
	var program = check (REGION_SOURCE);
	var function = program.functions[0];
	var root = function.body.region;
	var branch = (CheckedIf) function.body.statements[2];
	var nested = (CheckedWhile) branch.then_body.statements[1];
	var loop = (CheckedWhile) function.body.statements[3];
	LexicalRegion[] regions = {
		root, branch.then_body.region, nested.body.region, branch.else_body.region, loop.body.region
	};
	int[] parents = {
		-1, 0, 1, 0, 0
	};
	for (int i = 0; i < regions.length; i++) {
		assert (regions[i].ordinal == i);
		assert (regions[i].parent == (parents[i] < 0 ? null : regions[parents[i]]));
		for (int j = 0; j < regions.length; j++) {
			assert (regions[i].outlives (regions[j]) == (i == j || i == 0 || (i == 1 && j == 2)));
		}
	}
	int[] local_regions = {
		0, 0, 1, 2, 3, 3, 4
	};
	assert (function.locals.length == local_regions.length);
	for (int i = 0; i < local_regions.length; i++) {
		assert (function.locals[i].lexical_region == regions[local_regions[i]]);
	}
	assert (function.symbol.parameters[0].lexical_region == root);
	var other = program.functions[1].body.region;
	assert (other.ordinal == 0 && other != root && !other.outlives (root) && !root.outlives (other));
	var repeated = check (REGION_SOURCE);
	assert (!root.outlives (repeated.functions[0].body.region));
	string dump = SemanticDump.format (program, true);
	assert (dump == SemanticDump.format (repeated, true));
	assert (!SemanticDump.format (program).contains ("region"));
	assert (dump.contains ("(region #2 parent #1)") && dump.contains ("(region #3 parent #0)"));
	assert (dump.contains ("(parameter-borrow #0 region #0)"));
	assert (dump.contains ("(local-region #2 region #1 borrow-required)"));
	Test.message ("%s", dump);
}

private void expression_provenance() throws GLib.Error {
	var program = check (REGION_SOURCE);
	var function = program.functions[0];
	var root = function.body.region;
	var pointer = (CheckedLocalDeclaration) function.body.statements[1];
	var address = BorrowProvenance.for_expression (pointer.initializer);
	assert (address.kind == BorrowProvenanceKind.REGION && address.region == root && address.origin == function.locals[0]);
	var branch = (CheckedIf) function.body.statements[2];
	var copy = (CheckedLocalDeclaration) branch.then_body.statements[0];
	var local = BorrowProvenance.for_expression (copy.initializer);
	assert (local.region == pointer.local.lexical_region && local.origin == pointer.local);
	assert (local.outlives (copy.local.lexical_region));
	var read = BorrowProvenance.for_expression (new CheckedLocalReferenceExpression (copy.span, copy.local));
	assert (read.region == branch.then_body.region && !read.outlives (root));
	var nested = (CheckedWhile) branch.then_body.statements[1];
	var parameter = BorrowProvenance.for_expression (((CheckedLocalDeclaration) nested.body.statements[0]).initializer);
	assert (parameter.region == root && parameter.origin == function.symbol.parameters[0]);
	assert (parameter.outlives (nested.body.region));
	var loop = (CheckedWhile) function.body.statements[3];
	var null_value = BorrowProvenance.for_expression (((CheckedLocalDeclaration) loop.body.statements[0]).initializer);
	assert (null_value.kind == BorrowProvenanceKind.NULL && null_value.region == null && null_value.origin == null);
	assert (null_value.outlives (root) && null_value.outlives (loop.body.region) && null_value.outlives (program.functions[1].body.region));
	var null_read = BorrowProvenance.for_expression (new CheckedLocalReferenceExpression (loop.span, function.locals[6]));
	assert (null_read.kind == BorrowProvenanceKind.REGION && null_read.region == loop.body.region && !null_read.outlives (root));
}

private void register_regions() {
	add ("/borrow/regions/tree-identity-ordinals", region_tree);
	add ("/borrow/regions/expression-provenance", expression_provenance);
}
}
