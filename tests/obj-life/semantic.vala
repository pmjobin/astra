// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;

namespace Astra.Tests.LifecycleSemantic {
private CheckedProgram check(string source) {
	var parsed = Parser.parse (new SourceFile.from_text ("lifecycle", source));
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.format ());
	}
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	return checked.program;
}
private void reject(string source, string fragment) {
	var parsed = Parser.parse (new SourceFile.from_text ("invalid", source));
	var diagnostic = parsed.diagnostic;
	if (diagnostic == null) {
		diagnostic = SemanticAnalyzer.analyze (parsed.unit).diagnostic;
	}
	if (diagnostic == null || !diagnostic.message.contains (fragment)) {
		GLib.error ("expected %s; found %s", fragment, diagnostic == null ? "success" : diagnostic.message);
	}
}
private void identities() {
	CheckedProgram? p = check ("class C{int x;init(int n){this.x=n;}deinit(){this.x=this.x+1;this.log();}void log(){}}int main(){C c=C.init(42);C a=c;c=null;a.x=43;return 42;}");
	var c = p.classes[0];
	assert (c.constructor.domain == CallableDomain.CONSTRUCTOR && c.destructor.domain == CallableDomain.DESTRUCTOR);
	assert (!((Object) c.constructor is MethodSymbol) && !((Object) c.destructor is MethodSymbol));
	assert (c.methods.length == 1 && c.constructor.declaring_class == c && c.destructor.declaring_class == c);
	assert (c.constructor.receiver.semantic_type.mode == ReceiverMode.INITIALIZING && c.destructor.receiver.semantic_type.mode == ReceiverMode.LIVE);
	assert (c.constructor.receiver.semantic_type != c.receiver_type && c.destructor.receiver.semantic_type == c.receiver_type);
	var construction = (CheckedConstructorObjectInitialization) p.functions[0].body.statements[0];
	assert (construction.storage.destructor == c.destructor && construction.constructor == c.constructor && construction.arguments.length == 1);
	assert (p.functions[0].body.statements[1] is CheckedLocalDeclaration);
	assert (p.functions[2] is CheckedConstructor && p.functions[3] is CheckedDestructor);
	assert (p.functions[2].body.statements[0] is CheckedFieldInitialize);
	assert (((CheckedConstructor) p.functions[2]).initialization.is_definite (0));
	assert (SemanticDump.format (p).contains ("cleanup destructor"));
	var witness = WeakRef (p.functions[2]);
	p = null;
	assert (witness.get () == null);
}
private void declarations() {
	reject ("class C{init(){}init(int n){}}", "duplicate lifecycle");
	reject ("class C{deinit(){}deinit(){}}", "duplicate lifecycle");
	foreach (var declaration in new string[] { "int init;", "int deinit;", "void init(){}", "C init(){return null;}", "void deinit(){}" }) {
		reject ("class C{" + declaration + "}", "lifecycle name");
	}
	assert (check ("class C{init(C other){}}").classes[0].constructor.parameters[0].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
	reject ("class C{init(){}}int main(){C c={};return 0;}", "cannot bypass");
	reject ("class C{}int main(){C c=C.init();return 0;}", "no explicit init");
	reject ("class C{init(int n){}}int main(){C c=C.init();return 0;}", "expects 1 arguments");
	reject ("class C{int x;init(int n){this.x=n;}}int main(){C c=C.init(c.x);return 0;}", "unknown name");
	reject ("class C{deinit(){this.deinit();}}", "cannot be invoked explicitly");
	reject ("class C{deinit(){}}int main(){C c={};c.deinit();return 0;}", "cannot be invoked explicitly");
	reject ("class C{deinit(){}}int main(){C.deinit();return 0;}", "cannot be invoked explicitly");
	reject ("class C{init(){}}int main(){C c=C.init();int x=c.init;return 0;}", "unknown field");
	reject ("class C{deinit(){}}int main(){C c={};int x=c.deinit;return 0;}", "unknown field");
	check ("class C{int x;deinit(){this.x=1;}}int main(){C c={x=42};return c.x;}");
	check ("class C{init(){}}int main(){C c=C.init();return 42;}");
	foreach (var body in new string[] { "C c=null;c=C.init();return 0;", "return C.init();", "use(C.init());return 0;", "C c=(C.init());return 0;" }) {
		reject ("class C{init(){}}void use(int n){}int main(){" + body + "}", "fresh class local initializer");
	}
	check ("struct S{int x;int init(){return this.x;}void deinit(){this.x=42;}}int main(){S s={x=1};s.deinit();int x=s.init();return x;}");
	check ("int new(){return 42;}int main(){return new();}");
}
private void definite_initialization() {
	string head = "class C{int x;int y;init(bool b){";
	reject (head + "this.x=1;}}", "field 'y' is not definitely initialized");
	reject (head + "int z=this.x;this.x=1;this.y=2;}}", "field 'x' read before");
	reject (head + "this.x=this.x+1;this.y=2;}}", "field 'x' read before");
	reject (head + "this.x=1;this.x=2;this.y=3;}}", "field 'x' is possibly initialized twice");
	reject (head + "if(b){this.x=1;}this.x=2;this.y=3;}}", "field 'x' is possibly initialized twice");
	reject (head + "if(b){this.x=1;}this.y=this.x;}}", "field 'x' read before");
	reject (head + "if(b){this.x=1;}this.y=2;}}", "field 'x' is not definitely initialized");
	reject (head + "while(b){this.x=1;}this.y=2;}}", "inside a loop");
	reject (head + "return;}}", "explicit return");
	reject (head + "return this;}}", "explicit return");
	reject (head + "C alias=this;this.x=1;this.y=2;}}", "receiver");
	reject (head + "this.x=1;this.y=2;this.f();}void f(){}}", "this.method");
	check (head + "if(b){this.x=1;}else{this.x=2;}this.y=this.x;}}");
	check (head + "this.x=1;int sum=0;while(b){sum=sum+this.x;break;}this.y=sum;}}");
	check (head + "if(b){this.x=1;this.y=2;}else{while(true){}}}}");
	check (head + "if(false){this.x=1;}this.x=2;this.y=3;}}");
	check (head + "while(true){}this.x=1;this.x=2;}}");
	check (head + "bool unused=false && this.x==0;this.x=1;this.y=2;}}");
}
private void lifetime() {
	reject ("class C{init(){}deinit(){}}int main(){C outer=null;{C inner=C.init();outer=inner;}return 42;}", "shorter lexical lifetime");
	check ("class C{init(){}deinit(){}}int main(){C outer=C.init();{C inner=outer;outer=null;}return 42;}");
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-life/semantic/symbols-receivers-storage-and-lifetime", identities);
	Test.add_func ("/obj-life/semantic/declaration-and-construction-contracts", declarations);
	Test.add_func ("/obj-life/semantic/exact-definite-field-initialization", definite_initialization);
	Test.add_func ("/obj-life/semantic/reference-provenance-regression", lifetime);
	return Test.run ();
}
}
