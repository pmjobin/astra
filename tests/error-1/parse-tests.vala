// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;

namespace Astra.Tests.NativeExceptionParser {
private ParseResult parse(string source) {
	return Parser.parse (new SourceFile.from_text ("native-exceptions", source));
}
private void hierarchy() {
	var result = parse ("[ExceptionRoot]class Error{readonly string description;init(string text){this.description=text;}virtual property string message{get{return this.description;}}}class RuntimeError:Error{init(string text):base(text){}}class DecodeError:RuntimeError{init(string text):base(text){}override property string message{get{return \"leaf\";}}}");
	assert (result.diagnostic == null);
	assert (result.unit.classes.length == 3);
	assert (result.unit.classes[0].exception_root.spelling () == "ExceptionRoot");
	assert (result.unit.classes[1].parent_class.spelling () == "Error");
	assert (result.unit.classes[2].parent_class.spelling () == "RuntimeError");
	assert (result.unit.classes[0].fields[0].readonly_keyword.spelling () == "readonly");
	assert (((PropertyDeclarationSyntax) result.unit.classes[0].members[2]).dispatch == MemberDispatchSyntax.VIRTUAL);
	assert (((PropertyDeclarationSyntax) result.unit.classes[2].members[1]).dispatch == MemberDispatchSyntax.OVERRIDE);
	assert (((LifecycleDeclarationSyntax) result.unit.classes[1].members[0]).base_arguments.length == 1);
	assert (SyntaxDump.format (result.unit).contains ("(base-initializer (name \"text\"))"));
}
private void flow() {
	var result = parse ("void decode()throws DecodeError{throw new DecodeError(\"bad\");}void forward()throws RuntimeError{try{decode();}catch(Error e){throw;}}int main(){try{forward();return 0;}catch(DecodeError e){return 1;}catch(RuntimeError e){return 2;}catch(Error e){return 3;}}");
	assert (result.diagnostic == null);
	assert (result.unit.functions[0].throws_class.spelling () == "DecodeError");
	var thrown = (ThrowStatementSyntax) result.unit.functions[0].body.statements[0];
	assert (!thrown.is_rethrow && thrown.expression is HeapObjectConstructionSyntax);
	var guarded = (TryStatementSyntax) result.unit.functions[1].body.statements[0];
	assert (((ThrowStatementSyntax) guarded.catches[0].body.statements[0]).is_rethrow);
	assert (((TryStatementSyntax) result.unit.functions[2].body.statements[0]).catches.length == 3);
	assert (SyntaxDump.format (result.unit).contains ("(new-object DecodeError (text"));
	assert (parse ("void f(){owned Error e=new Error(\"bad\");throw move e;}").diagnostic == null);
}
private void malformed() {
	// Bounded Singleton initialization retains throws syntax; ordinary
	// constructors remain subject to their semantic effect restriction.
	assert (parse ("[Singleton]class C{init()throws E{}}").diagnostic == null);
	foreach (string source in new string[] {
			"[ExceptionRoot]int f(){return 0;}", "[ExceptionRoot()]class E{}", "[ExceptionRoot][ExceptionRoot]class E{}",
			"class A:B,C{}", "struct A:B{}", "class C{virtual int field;}", "class C{readonly property string p{get{return \"\";}}}",
			"class C{virtual init(){}}", "class C{deinit():base(){}}", "class C{init():other(){}}", "class C{init()throws{}}",
			"extern(C)void f()throws E;", "export(C)int f()throws E{return 0;}", "void f(){try{}}", "void f(){try{}catch(E){}}",
			"void f(){try{}catch(owned E e){}}", "void f(){throw;catch(E e){}}", "void f()throws{}", "void f(){throw new E(;}"
		}) {
		var result = parse (source);
		assert (result.diagnostic != null);
	}
}
private void compatibility() {
	assert (parse ("class C{int x;init(int x){this.x=x;}}void f(){owned C c=C.init(1);}").diagnostic == null);
	assert (parse ("int new(int x){return x;}void f(){owned int[] a=new int[2];int n=new(1);}").diagnostic == null);
	assert (parse ("int message(int what,int Error,int RuntimeError,int readonly,int virtual,int override,int base){return what;}").diagnostic == null);
	foreach (string name in new string[] {"throws", "throw", "try", "catch"}) {
		assert (parse ("int " + name + "(){return 1;}").diagnostic != null);
	}
	foreach (string literal in new string[] {"@\"x\"", "$\"x\"", "\"\\q\""}) {
		assert (parse ("string f(){return " + literal + ";}").diagnostic != null);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/error-1/parser/hierarchy-root-snapshot-and-override", hierarchy);
	Test.add_func ("/error-1/parser/ordinary-calls-ordered-catches-and-rethrow", flow);
	Test.add_func ("/error-1/parser/malformed-and-foreign-boundary", malformed);
	Test.add_func ("/error-1/parser/contextual-compatibility-and-frozen-text", compatibility);
	return Test.run ();
}
}
