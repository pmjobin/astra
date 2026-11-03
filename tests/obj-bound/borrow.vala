// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;

namespace Astra.Tests.ObjectBound {
private void authority() {
	var p = check ("class C{}void helper(borrowed C c){}void outer(borrowed C c){C local=c;helper(local);helper(c);helper(null);{C inner=c;helper(inner);}}");
	var body = p.functions[1].body;
	var parameter = p.functions[1].symbol.parameters[0];
	var copy = (CheckedLocalDeclaration) body.statements[0];
	var proof = BorrowProvenance.for_expression (copy.initializer);
	assert (proof.kind == BorrowProvenanceKind.REGION && proof.origin == parameter && proof.region == body.region && proof.region.parent == null);
	assert (parameter.lexical_region == body.region && proof.outlives (copy.local.lexical_region));
	var snapshot = proof.snapshot ();
	assert (snapshot.origin == DataPointerOrigin.PARAMETER && snapshot.origin_ordinal == 0 && snapshot.region_ordinal == 0 && snapshot.is_valid ());
	var local_call = (CheckedCallStatement) body.statements[1];
	var local_proof = BorrowProvenance.for_expression (local_call.arguments[0]);
	assert (local_proof.origin == copy.local && local_proof.region == body.region && copy.local.cleanup == null);
	var nil = BorrowProvenance.for_expression (((CheckedCallStatement) body.statements[3]).arguments[0]);
	assert (nil.kind == BorrowProvenanceKind.NULL && nil.region == null && nil.origin == null && nil.outlives (body.region));
	var inner = (CheckedBlockStatement) body.statements[4];
	assert (proof.outlives (inner.region) && !inner.region.outlives (body.region));
}

private void caller() {
	var p = check ("class C{int x;deinit(){}}void f(borrowed C c){c.x=42;}int main(){C c={x=1};C alias=c;f(c);c=null;return alias.x;}");
	var body = p.functions[1].body;
	var construction = (CheckedObjectConstruction) body.statements[0];
	assert (construction.storage.object_class.destructor == p.classes[0].destructor && construction.storage.cleanup_rank == 0);
	assert (construction.local.cleanup == null && p.functions[0].locals.length == 0);
	var argument = ((CheckedCallStatement) body.statements[2]).arguments[0];
	assert (BorrowProvenance.for_expression (argument).region == construction.storage.lexical_region);
	check ("class C{}void f(borrowed C c,int n){C local=c;if(n>0){f(local,n-1);}}void g(){{C c={};f(c,3);}}");
}

private void escape() {
	reject ("class C{}void f(borrowed C c){C outer=c;{C inner=c;outer=inner;}}", "shorter lexical lifetime");
	reject ("class C{}void f(borrowed C c){C outer=c;{C inner={};outer=inner;}}", "shorter lexical lifetime");
	reject ("class C{}C f(borrowed C c){C local=c;return local;}", "object-reference results are unsupported");
	check ("class C{}void f(borrowed C c){C outer=null;outer=c;{C inner=outer;inner=null;}}");
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-bound/borrow/function-region-copy-forward-and-null-authority", authority);
	Test.add_func ("/obj-bound/borrow/caller-keeps-storage-and-cleanup-rank", caller);
	Test.add_func ("/obj-bound/borrow/conservative-copy-and-result-escape-rejection", escape);
	return Test.run ();
}

}
