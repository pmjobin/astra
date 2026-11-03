// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;

namespace Astra.Tests.ObjectResult {
private void contracts() {
	CheckedProgram? p = check ("class C{init(){}owned C copy(){return C.init();}}owned C make(){return C.init();}owned C identity(owned C c){return move c;}owned C outer(){return make();}owned C absent(){return null;}void f(){owned C c=make();}");
	var make = p.functions[0];
	assert (make.symbol.return_type == p.classes[0].semantic_type && make.symbol.return_type is ClassType);
	assert (make.symbol.result_contract == ResultOwnershipContract.OWNED_TRANSFER && make.symbol.owned_cleanup == null);
	var returned = (CheckedOwnershipReturn) make.body.statements[0];
	var fresh = (CheckedOwnedObjectResultConstruction) returned.producer;
	assert (fresh.storage == make.symbol.result_storage && fresh.constructor == p.classes[0].constructor && returned.provenance == ObjectResultProvenance.RESULT_STORAGE);
	var identity = (CheckedOwnershipReturn) p.functions[1].body.statements[0];
	assert (identity.transfer.source.incoming_parameter == p.functions[1].symbol.parameters[0] && identity.provenance == ObjectResultProvenance.OWNED_PARAMETER_STORAGE);
	var forward = (CheckedOwnershipReturn) p.functions[2].body.statements[0];
	assert (forward.provenance == ObjectResultProvenance.FORWARDED_OWNED_RESULT && ((CheckedCallExpression) forward.producer).result_storage == p.functions[2].symbol.result_storage);
	assert (((CheckedOwnershipReturn) p.functions[3].body.statements[0]).provenance == ObjectResultProvenance.NULL);
	var declaration = (CheckedOwnedLocalDeclaration) p.functions[4].body.statements[0];
	var call = (CheckedCallExpression) declaration.initializer;
	assert (call.owned_producer.object_owner == p.classes[0] && call.ownership_kind == OwnershipKind.TRANSFERABLE_OBJECT_OWNER);
	assert (call.candidate_storage.result_candidate && declaration.local.object_storage == null);
	assert (declaration.local.object_provenance == ObjectResultProvenance.CALLEE_LOCAL_STORAGE);
	assert (SemanticDump.format (p).contains ("storage-mode caller-provided"));
}

private void escapes() {
	reject ("class C{int field;}owned C f(borrowed C c){return move c.field;}", "moving ownership out of an owned field");
	string c = "class C{init(){}}";
	reject (c + "owned C f(){owned C c=C.init();return move c;}", "callee-local owned ObjectStorage cannot escape");
	reject (c + "owned C id(owned C c){return move c;}owned C f(){owned C c=C.init();return id(move c);}", "cannot escape through a forwarded");
	reject (c + "owned C f(){C c=C.init();return c;}", "fixed and borrowed references");
	reject (c + "owned C f(borrowed C c){return c;}", "fixed and borrowed references");
	reject (c + "owned C f(borrowed C c){return move c;}", "requires an owned ClassType binding");
	reject ("class C{owned C f(){return this;}}", "fixed and borrowed references");
	reject (c + "owned C make(){return C.init();}owned C f(){owned C c=make();return move c;}", "callee-local owned ObjectStorage cannot escape");
}

private void contexts() {
	string c = "class C{init(){}}owned C make(){return C.init();}";
	reject (c + "void use(borrowed C c){}void f(){use(C.init());}", "only permitted as a fresh class local initializer or direct owned object return");
	reject (c + "void f(){C c=null;c=C.init();}", "only permitted");
	reject (c + "void use(owned C c){}void f(){use(make());}", "requires explicit 'move owner' or null");
	reject (c + "void f(){make();}", "carries ownership responsibility");
	reject (c + "void f(){C c=make();}", "carries ownership responsibility");
	reject (c + "C f(){return null;}", "object-reference results are unsupported");
	reject (c + "extern(C) owned C foreign();", "object-reference results are unsupported");
	reject (c + "export(C) owned C foreign(){return null;}", "object-reference results are unsupported");
	reject (c + "class D{init(){}}owned C f(){return D.init();}", "exact result ClassName.init");
	foreach (var initializer in new string[] { "null", "move c", "c" }) {
		reject (c + "void f(){owned C c=C.init();owned C other=" + initializer + ";}", "requires fresh object construction");
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-ret/semantic/exact-contract-producer-and-storage", contracts);
	Test.add_func ("/obj-ret/semantic/local-and-borrowed-escape-firewall", escapes);
	Test.add_func ("/obj-ret/semantic/result-only-construction-and-no-temporaries", contexts);
	return Test.run ();
}

}
