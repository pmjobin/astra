// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
namespace Astra.Tests.GenSemantic {
private SemanticResult check(string text) {
	var parsed = Parser.parse (new SourceFile.from_text ("generic.astra", text));
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.format ());
	}
	return SemanticAnalyzer.analyze (parsed.unit);
}

private void reject(string text, string diagnostic) {
	var result = check (text);
	if (result.diagnostic == null || !result.diagnostic.message.contains (diagnostic)) {
		GLib.error ("expected %s: %s", diagnostic, result.diagnostic == null ? "accepted invalid generic" : result.diagnostic.format ());
	}
}

private void identity() {
	var result = check ("T id<T>(T x){T y=x;y=x;return y;}T other<T>(T x){return id<T>(x);}int main(){return id<int>(id<i32>(42));}");
	assert (result.diagnostic == null && result.program.generic_functions.length == 2 && result.program.functions.length == 1);
	var a = result.program.generic_functions[0];
	var b = result.program.generic_functions[1];
	assert (a.definition != b.definition && a.definition.type_parameters[0] != b.definition.type_parameters[0]);
	assert (a.definition.return_type == a.definition.type_parameters[0].semantic_type && a.locals[0].semantic_type == a.definition.return_type);
	assert (a.definition.return_type != b.definition.return_type && ((TypeParameterType) a.definition.return_type).capability == GenericCapability.GEN1_PLAIN_COPY);
	var call = ((CheckedReturnStatement) b.body.statements[0]).expression as CheckedGenericCall;
	assert (call.target == a.definition && call.type_arguments[0] == b.definition.return_type && call.semantic_type == b.definition.return_type);
	var root = ((CheckedReturnStatement) result.program.functions[0].body.statements[0]).expression as CheckedGenericCall;
	assert (root.type_arguments[0] == ((CheckedGenericCall) root.arguments[0]).type_arguments[0]);
	assert (SemanticDump.format (result.program).contains ("checked-once GEN1_PLAIN_COPY"));
}

private void scope() {
	reject ("T f<T,T>(T a){return a;}", "duplicate type parameter");
	reject ("int f<int>(){return 1;}", "builtin type name");
	reject ("struct T{int v;}T f<T>(T a){return a;}", "cannot shadow");
	reject ("T f<T>(T a){return a;}T g(T x){return x;}", "unknown type 'T'");
	reject ("int main<T>(){return 1;}", "main cannot be a generic");
	foreach (string prefix in new string[] {"int f(int x){return x;}", "T f<T>(T x){return x;}", "U f<T,U>(T x,U y){return y;}"}) {
		reject (prefix + "T f<T>(T x){return x;}", "duplicate function");
	}
}

private void arguments() {
	assert (check ("T id<T>(T x){return x;}int main(){return id(42);}").diagnostic == null);
	reject ("T id<T,U>(T x,U y){return x;}int main(){return id<int>(42,1);}", "expects 2 type arguments, provided 1");
	reject ("T id<T>(T x){return x;}int main(){return id<int,bool>(42);}", "expects 1 type arguments, provided 2");
	reject ("int id(int x){return x;}int main(){return id<int>(42);}", "non-generic function");
	foreach (string type in new string[] {"void", "int*", "int[]", "int[4]", "C"}) {
		reject ("struct S{int x;}class C{}int tag<T>(){return 1;}int main(){return tag<" + type + ">();}", "GEN-1 type argument");
	}
	assert (check ("struct S{int x;}class C{}int tag<T>(){return 1;}int main(){return tag<S>();}").diagnostic == null);
	reject ("T id<T>(T x){T[] y=x;return x;}", "signature-derived");
	foreach (string type in new string[] {"T*", "T[4]", "T<4>"}) {
		reject ("T id<T>(T x){" + type + " y=x;return x;}", "type constructors");
	}
	reject ("owned T id<T>(T x){return x;}", "owned T requires explicit capability Ownable");
	reject ("T id<T>(owned T x){return x;}", "owned T requires explicit capability Ownable");
	reject ("T id<T>(borrowed T x){return x;}", "borrowed T requires explicit capability Ownable");
}

private void capability() {
	reject ("T mix<T,U>(T a,U b){T c=b;return c;}int main(){return mix<int,int>(1,2);}", "type");
	reject ("T mix<T,U>(T a,U b){return b;}", "type");
	foreach (string op in new string[] {"+", "-", "*", "/", "%", "==", "!=", "<", ">", "&", "|", "^", "<<", ">>"}) {
		var result = check ("T bad<T>(T a,T b){return a " + op + " b;}int main(){return 42;}");
		assert (result.diagnostic != null);
	}
	reject ("T bad<T>(T a,T b){return a+b;}int main(){return bad<int>(1,2);}", "operator");
	foreach (string body in new string[] {"return -x;", "return !x;", "return ~x;", "if(x){return x;}return x;", "return x.field;", "return x.method();", "return x[0];", "return *x;"}) {
		assert (check ("T bad<T>(T x){" + body + "}").diagnostic != null);
	}
	reject ("T bad<T>(T x){int y=x as int;return x;}", "casts to or from");
	reject ("T bad<T>(T x){T y=1 as T;return y;}", "casts to or from");
	reject ("T bad<T>(T x){T y=null;return y;}", "null cannot be contextualized");
	reject ("T bad<T>(T x){T y=x;void* p=&y;return y;}", "address-of");
}

private void matrix() {
	var types = new BuiltinTypes ();
	foreach (string name in new string[] {"bool", "i8", "u8", "i16", "u16", "int", "i32", "u32", "f32", "f64", "void*"}) {
		assert (GenericArgumentTypes.supports (types.resolve (name)));
	}
	foreach (string name in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32", "bool"}) {
		foreach (int lanes in new int[] {2, 4, 8, 16}) {
			var type = types.vector_of (types.resolve (name), lanes);
			if (type != null) {
				assert (GenericArgumentTypes.supports (type));
			}
		}
	}
	var result = check ("T first<T,U>(T a,U b){return a;}U reorder<T,U>(T a,U b){return first<U,T>(b,a);}int tag<T>(){return 1;}f64 run(){return reorder<int,f64>(tag<void*>(),1.25);}");
	assert (result.diagnostic == null && result.program.generic_functions.length == 3);
	assert (((CheckedReturnStatement) result.program.functions[0].body.statements[0]).expression.semantic_type is F64Type);
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen/semantic/exact-identity-substitution", identity);
	Test.add_func ("/gen/semantic/scope-namespace", scope);
	Test.add_func ("/gen/semantic/explicit-arguments-deferred", arguments);
	Test.add_func ("/gen/semantic/definition-capability-unused-invalid", capability);
	Test.add_func ("/gen/semantic/matrix-reordering", matrix);
	return Test.run ();
}

}
