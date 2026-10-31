// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;

namespace Astra.Tests.LifecycleParser {
private void grammar() {
	var result = Parser.parse (new SourceFile.from_text ("lifecycle", "class C{init(int n){this.x=n;}int x;deinit(){}void f(){}}int main(){C c=C.init(42);return c.x;}"));
	assert (result.diagnostic == null);
	var c = result.unit.classes[0];
	assert (c.members.length == 4 && c.methods.length == 1 && c.fields.length == 1);
	var ctor = (LifecycleDeclarationSyntax) c.members[0];
	var dtor = (LifecycleDeclarationSyntax) c.members[2];
	assert (ctor.is_constructor && ctor.return_type == null && ctor.parameters.length == 1);
	assert (!dtor.is_constructor && dtor.return_type == null && dtor.parameters.length == 0);
	assert (((LocalDeclarationSyntax) result.unit.functions[0].body.statements[0]).initializer is ConstructorInitializerSyntax);
	var dump = SyntaxDump.format (result.unit);
	assert (dump.contains ("constructor-initializer") && dump.contains ("(constructor") && dump.contains ("(destructor"));
}
private void restricted() {
	foreach (var body in new string[] { "C c=C.init()+1;", "delete c;" }) {
		assert (Parser.parse (new SourceFile.from_text ("invalid", "int main(){" + body + "}")).diagnostic != null);
	}
	// ERROR-1 heap construction now parses; its owning class premises remain semantic.
	var heap = Parser.parse (new SourceFile.from_text ("error-1", "int main(){C c=new C();}"));
	assert (heap.diagnostic == null && ((LocalDeclarationSyntax) heap.unit.functions[0].body.statements[0]).initializer is HeapObjectConstructionSyntax);
	foreach (var declaration in new string[] { "struct C{init(){}}", "struct C{deinit(){}}", "class C{deinit(int n){}}", "class C{init;}", "class C{init() ;}", "class C{init(int){}}", "class C{init() int{}}" }) {
		assert (Parser.parse (new SourceFile.from_text ("invalid", declaration)).diagnostic != null);
	}
	// These spellings remain unresolved calls in syntax because existing
	// struct methods may use these names. Class resolution rejects them.
	foreach (var body in new string[] { "c=C.init();", "return C.init();", "use(C.init());", "C c=(C.init());" }) {
		var parsed = Parser.parse (new SourceFile.from_text ("invalid-construction", "int main(){" + body + "}"));
		assert (parsed.diagnostic == null && !SyntaxDump.format (parsed.unit).contains ("constructor-initializer"));
	}
	// Lifecycle names and new are contextual, not new global keywords.
	assert (Parser.parse (new SourceFile.from_text ("free", "int init(){return 1;}int deinit(){return 2;}int new(){return 3;}")).diagnostic == null);
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-life/parser/lifecycle-and-dedicated-construction", grammar);
	Test.add_func ("/obj-life/parser/restricted-construction-and-malformed-members", restricted);
	return Test.run ();
}
}
