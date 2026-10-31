// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;

namespace Astra.Tests.Objects {
private void provenance() {
	var p = check ("class C{int x;}int main(){C a={x=1};C b=a;C nil=null;b=nil;b=a;{C inner=a;inner.x=42;}return a.x;}");
	var body = p.functions[0].body;
	var construction = (CheckedObjectConstruction) body.statements[0];
	var origin = BorrowProvenance.for_expression (construction.reference);
	assert (origin.kind == BorrowProvenanceKind.REGION && origin.origin == construction.storage && origin.region == body.region);
	var snapshot = origin.snapshot ();
	assert (snapshot.origin == DataPointerOrigin.OBJECT_STORAGE && snapshot.origin_ordinal == 0 && snapshot.region_ordinal == 0 && snapshot.is_valid ());
	var alias = (CheckedLocalDeclaration) body.statements[1];
	var copy = BorrowProvenance.for_expression (alias.initializer);
	assert (copy.origin == construction.local && copy.region == body.region);
	var nil = (CheckedLocalDeclaration) body.statements[2];
	assert (BorrowProvenance.for_expression (nil.initializer).kind == BorrowProvenanceKind.NULL);
	var nested = (CheckedBlockStatement) body.statements[5];
	assert (origin.outlives (nested.region) && !nested.region.outlives (body.region));
	assert (construction.storage.lexical_region == body.region);
}

private void escapes() {
	reject ("class C{}int main(){C outer=null;{C inner={};outer=inner;}return 0;}", "shorter lexical lifetime");
	reject ("class C{}int main(){C outer=null;while(false){C inner={};outer=inner;}return 0;}", "shorter lexical lifetime");
	reject ("class C{}int main(){C a={};C b=a;{C inner={};b=inner;}return 0;}", "shorter lexical lifetime");
	// Conservative stored-borrow discipline deliberately summarizes at locals.
	reject ("class C{}int main(){C a={};{C inner=a;a=inner;}return 0;}", "shorter lexical lifetime");
	check ("class C{}int main(){C outer={};{C inner=null;inner=outer;C alias=inner;inner=null;}return 42;}");
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/object/borrow/storage-copy-null-and-ancestor-regions", provenance);
	Test.add_func ("/object/borrow/conservative-stored-reference-escape", escapes);
	return Test.run ();
}
}
