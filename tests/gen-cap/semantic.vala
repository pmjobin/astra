// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
namespace Astra.Tests.GenCapSemantic {
private SemanticResult check(string source) {
	var parsed = Parser.parse (new SourceFile.from_text ("capability.astra", source));
	assert (parsed.diagnostic == null);
	return SemanticAnalyzer.analyze (parsed.unit);
}
private void reject(string source, string message) {
	var result = check (source);
	if (result.diagnostic == null || !result.diagnostic.message.contains (message)) {
		GLib.error ("expected %s, got %s", message, result.diagnostic == null ? "success" : result.diagnostic.message);
	}
	assert (result.program == null);
}
private void identities() {
	var result = check ("bool same<T>(T a,T b) where T : Eq {return a==b;} bool outer<T,U>(T a,T b,U c) where U : Numeric where T : Ordered, Eq {return same<T>(a,b);}");
	assert (result.diagnostic == null);
	var inner = result.program.generic_functions[0];
	var outer = result.program.generic_functions[1];
	var requirement = inner.capability_requirements[0];
	var parameter = inner.definition.type_parameters[0];
	assert (requirement.type_parameter == parameter && requirement.capability.name == "Eq" && requirement.span.text () == "Eq");
	assert (parameter.semantic_type.capability == GenericCapability.GEN1_PLAIN_COPY);
	assert (outer.capability_requirements[0].type_parameter == outer.definition.type_parameters[1]);
	assert (outer.capability_requirements[2].capability == requirement.capability);
	assert (outer.definition.type_parameters[0].semantic_type != parameter.semantic_type);
	var operation = ((CheckedReturnStatement) inner.body.statements[0]).expression as CheckedGenericCapabilityOperation;
	assert (operation != null && operation.capability == requirement.capability && operation.type_parameter == parameter.semantic_type && operation.operator_kind == GenericOperationKind.EQ && operation.semantic_type.kind == TypeKind.BOOL);
	var call = ((CheckedReturnStatement) outer.body.statements[0]).expression as CheckedGenericCall;
	assert (call.target_requirements[0] == requirement);
	assert (SemanticDump.format (result.program).contains ("generic-op eq (capability Eq)"));
	assert (check ("struct Eq{int n;} int Eq(){return 1;} bool f<Eq>(Eq a,Eq b) where Eq : Eq {return a==b;}").diagnostic != null); // GEN-1 forbids type shadowing.
	assert (check ("int Eq(){return 1;} bool f<Eq>(Eq a,Eq b) where Eq : Eq {return a==b;}").diagnostic == null);
	reject ("T f<T>(T a) where U : Eq {return a;}", "unknown type parameter 'U'");
	foreach (string name in new string[] {"Magic", "eq", "Copy", "Move", "int"}) {
		reject ("T f<T>(T a) where T : " + name + " {return a;}", "unknown generic capability");
	}
}
private void operators() {
	for (int i = 0; i <= (int) GenericOperationKind.SHIFT_RIGHT; i++) {
		var kind = (GenericOperationKind) i;
		string expression = kind == GenericOperationKind.BIT_NOT ? "~a" : kind.is_shift () ? "a" + kind.spelling () + "count" : "a" + kind.spelling () + "b";
		string source = (kind.is_comparison () ? "bool" : "T") + " f<T>(T a,T b,int count) where T : " + kind.capability ().spelling () + " {return " + expression + ";}";
		assert (check (source).diagnostic == null);
		string other = kind.capability () == GenericCapabilityIdentity.EQ ? "Ordered" : "Eq";
		reject (source.replace ("where T : " + kind.capability ().spelling (), "where T : " + other), "requires explicit capability");
	}
	foreach (string expression in new string[] {"-a", "+a", "!a", "a%b", "a&&b", "a||b", "a as int", "a.member", "a[0]", "*a"}) {
		assert (check ("T f<T>(T a,T b) where T : Eq, Ordered, Numeric, Bitwise, Shift {return " + expression + ";}").diagnostic != null);
	}
	reject ("T f<T>(T a) where T : Numeric {return a+1;}", "generic literals cannot");
	reject ("T f<T>(T a) where T : Numeric {return 1.0+a;}", "generic literals cannot");
	reject ("bool f<T,U>(T a,U b) where T : Eq where U : Eq {return a==b;}bool root(){return f<int,int>(1,1);}", "exact same type parameter");
	reject ("T f<T,U>(T a,U b) where T : Shift where U : Shift {return a>>b;}", "concrete scalar IntegerType count");
	reject ("bool f<T>(T a,T b) where T : Ordered {return a==b;}", "requires explicit capability 'Eq'");
	reject ("bool f<T>(T a,T b) where T : Numeric {return a<b;}", "requires explicit capability 'Ordered'");
	reject ("bool f<T>(T a,T b) where T : Numeric {return a==b;}", "requires explicit capability 'Eq'");
}
private void forwarding() {
	string inner = "bool inner<T>(T a,T b) where T : Eq {return a==b;}";
	foreach (string constraint in new string[] {"", "where T : Ordered", "where T : Numeric"}) {
		reject (inner + "bool outer<T>(T a,T b) " + constraint + " {return inner<T>(a,b);} bool root(){return outer<int>(1,1);}", "type argument 'T' does not satisfy capability 'Eq'");
	}
	assert (check (inner + "bool outer<T>(T a,T b) where T : Ordered, Eq {return inner<T>(a,b);}").diagnostic == null);
	reject ("int tag<T>() where T : Eq {return 1;}int root(){return tag<i16<8>>();}", "type argument 'i16<8>' does not satisfy capability 'Eq'");
	reject ("int tag<T,U>() where U : Shift, Bitwise where T : Numeric {return 1;}int root(){return tag<bool,f64>();}", "type argument 'f64' does not satisfy capability 'Shift'");
	assert (check ("T a<T>(int n,T x,T y) where T : Ordered {if(n==0){return x;}return b<T>(n-1,x,y);}T b<T>(int n,T x,T y) where T : Ordered {if(x<y){return y;}return a<T>(n,x,y);}").diagnostic == null);
	reject ("T a<T>(T x) where T : Eq {return b<T>(x);}T b<T>(T x) where T : Ordered {return a<T>(x);}", "does not satisfy capability");
}
private void contextual_results() {
	assert (check ("T id<T>(T x){return x;}bool root(){return id<u32>(4294967295)==4294967295 && 1.0==id<f64>(1.0);}").diagnostic == null);
	for (int outer = 0; outer < 5; outer++) {
		for (int inner = 0; inner < 5; inner++) {
			string source = "int inner<T>() where T : " + ((GenericCapabilityIdentity) inner).spelling () + " {return 1;}int outer<T>() where T : " + ((GenericCapabilityIdentity) outer).spelling () + " {return inner<T>();}";
			assert ((check (source).diagnostic == null) == (outer == inner));
		}
	}
}
private void matrices() {
	var types = new BuiltinTypes ();
	foreach (string name in new string[] {"i8", "u8", "i16", "u16", "int", "i32", "u32", "f32", "f64", "bool", "void*"}) {
		var type = types.resolve (name);
		for (int c = 0; c < 5; c++) {
			var capability = (GenericCapabilityIdentity) c;
			bool expected = type is IntegerType || (type is FloatingType && c <= (int) GenericCapabilityIdentity.NUMERIC) || c == (int) GenericCapabilityIdentity.EQ;
			var result = check ("int tag<T>() where T : " + capability.spelling () + " {return 1;}int root(){return tag<" + name + ">();}");
			assert ((result.diagnostic == null) == expected);
			assert (GenericCapabilityAuthority.satisfies (type, capability) == expected);
		}
	}
	foreach (string element in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32", "bool"}) {
		foreach (int lanes in new int[] {2, 4, 8, 16}) {
			var vector = types.vector_of (types.resolve (element), lanes);
			if (vector == null) {
				continue;
			}
			assert (GenericArgumentTypes.supports (vector));
			assert (check ("int tag<T>(){return 1;}int root(){return tag<" + vector.display_name () + ">();}").diagnostic == null);
			for (int c = 0; c < 5; c++) {
				reject ("int tag<T>() where T : " + ((GenericCapabilityIdentity) c).spelling () + " {return 1;}int root(){return tag<" + vector.display_name () + ">();}", "does not satisfy capability");
			}
		}
	}
	foreach (string constraint in new string[] {"Eq, Ordered", "Numeric, Bitwise", "Ordered, Bitwise", "Numeric, Shift"}) {
		assert (check ("int tag<T>() where T : " + constraint + " {return 1;}int root(){return tag<u32>();}").diagnostic == null);
		if (constraint != "Eq, Ordered") {
			reject ("int tag<T>() where T : " + constraint + " {return 1;}int root(){return tag<f64>();}", "does not satisfy capability");
		}
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-cap/semantic/identities-namespace-provenance", identities);
	Test.add_func ("/gen-cap/semantic/operator-authority-no-implication", operators);
	Test.add_func ("/gen-cap/semantic/parametric-phantom-source-order-recursion", forwarding);
	Test.add_func ("/gen-cap/semantic/concrete-result-context-explicit-forwarding-matrix", contextual_results);
	Test.add_func ("/gen-cap/semantic/complete-matrix-intersections-vectors", matrices);
	return Test.run ();
}
}
