// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;

namespace Astra.Tests.GenInfer {
private const string IDENTITY = "T identity<T>(T x){return x;}";
private void exact_universe() {
	var types = new BuiltinTypes ();
	var universe = new GenericArray<SemanticType> ();
	foreach (string name in new string[] {"bool", "i8", "u8", "i16", "u16", "int", "u32", "f32", "f64", "void*"}) {
		universe.add (types.resolve (name));
	}
	foreach (string element in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32", "bool"}) {
		foreach (int lanes in new int[] {2, 4, 8, 16}) {
			var vector = types.vector_of (types.resolve (element), lanes);
			if (vector != null) {
				universe.add (vector);
			}
		}
	}
	assert (universe.length == 34);
	foreach (var type in universe) {
		assert (GenericArgumentTypes.supports (type));
		var name = type.display_name ();
		var program = check (IDENTITY + name + " f(" + name + " value){return identity(value);}");
		var function = program.functions[0];
		var call = (CheckedGenericCall) ((CheckedReturnStatement) function.body.statements[0]).expression;
		assert (call.type_arguments[0] == function.symbol.parameters[0].semantic_type && call.semantic_type == call.type_arguments[0]);
		assert (call.target == program.generic_functions[0].definition);
		for (int c = 0; c < GenericCapabilityIdentity.OWNABLE; c++) {
			var capability = (GenericCapabilityIdentity) c;
			var result = analyze ("T cap<T>(T x) where T : " + capability.spelling () + "{return x;}" + name + " f(" + name + " x){return cap(x);}");
			assert ((result.diagnostic == null) == GenericCapabilityAuthority.satisfies (type, capability));
			if (result.diagnostic != null) {
				assert (result.diagnostic.message.contains ("does not satisfy capability") && !result.diagnostic.message.contains ("cannot infer"));
			}
		}
	}
	var aliases = check ("T same<T>(T a,T b){return a;} int f(int a,i32 b){return same(a,b);}");
	var same = (CheckedGenericCall) ((CheckedReturnStatement) aliases.functions[0].body.statements[0]).expression;
	assert (same.type_arguments[0] == aliases.types.int_type && same.type_arguments[0] == aliases.types.i32_type);
}

private void literals() {
	var p = check (IDENTITY + "void f(){var a=identity(1);var b=identity(1.25);var c=identity(1.25f);var d=identity(1.0000000000000002d);var e=identity(null);var f=identity(1 as f64);var g=identity(true);}");
	SemanticType[] expected = {
		p.types.int_type, p.types.f32_type, p.types.f32_type, p.types.f64_type, p.types.raw_pointer_type, p.types.f64_type, p.types.bool_type
	};
	for (int i = 0; i < expected.length; i++) {
		var call = (CheckedGenericCall) ((CheckedLocalDeclaration) p.functions[0].body.statements[i]).initializer;
		assert (call.type_arguments[0] == expected[i] && p.functions[0].locals[i].semantic_type == expected[i]);
		if (i == 3) {
			assert (((CheckedFloatExpression) call.arguments[0]).value.exact_bits == 0x3ff0000000000001UL);
		}
	}
}

private void symbolic() {
	var p = check (IDENTITY + "T outer<T>(T x){return identity(x);}B pair<A,B>(A a,B b){return second(a,b);}V second<U,V>(U a,V b){return b;}");
	var inner = p.generic_functions[0].definition.type_parameters[0];
	var outer = p.generic_functions[1];
	var outer_type = outer.definition.type_parameters[0];
	var call = (CheckedGenericCall) ((CheckedReturnStatement) outer.body.statements[0]).expression;
	assert (inner != outer_type && inner.semantic_type != outer_type.semantic_type && inner.name == outer_type.name);
	assert (call.type_arguments[0] == outer_type.semantic_type && call.semantic_type == outer_type.semantic_type);
	var pair = p.generic_functions[2];
	var second = (CheckedGenericCall) ((CheckedReturnStatement) pair.body.statements[0]).expression;
	for (int i = 0; i < 2; i++) {
		assert (second.type_arguments[i] == pair.definition.type_parameters[i].semantic_type);
	}
	var inference = new GenericCallInference (p.generic_functions[0].definition);
	assert (inference.parameter_for (inner.semantic_type) == inner && inference.parameter_for (outer_type.semantic_type) == null);
	assert (inference.observe (inner, outer_type.semantic_type, 0, call.arguments[0].span));
	assert (inference.complete (call.span)[0] == outer_type.semantic_type);
	assert (inference.observations[0].parameter == inner && inference.observations[0].candidate == outer_type.semantic_type && inference.observations[0].argument_index == 0);
	for (int required = 0; required < GenericCapabilityIdentity.OWNABLE; required++) {
		for (int supplied = 0; supplied < GenericCapabilityIdentity.OWNABLE; supplied++) {
			var result = analyze ("U cap<U>(U x) where U : " + ((GenericCapabilityIdentity) required).spelling () + "{return x;}T outer<T>(T x) where T : " + ((GenericCapabilityIdentity) supplied).spelling () + "{return cap(x);}");
			assert ((result.diagnostic == null) == (required == supplied));
			if (result.diagnostic != null) {
				assert (result.diagnostic.message.contains ("does not satisfy capability"));
			}
		}
	}
}

private void ownership_proofs() {
	var p = fixture ("outer-owned");
	var span = p.generic_functions[0].symbol.span;
	var owner = new Object ();
	// Neither discarded observations nor a discarded argument proof can
	// commit a move in the enclosing definition's proof.
	var flow = new SemanticOwnershipFlow (span);
	var discarded = new SemanticOwnershipFlow (span);
	discarded.move (owner, "owner", span);
	var inference = new GenericCallInference (p.generic_functions[0].definition);
	var parameter = p.generic_functions[0].definition.type_parameters[0];
	assert (inference.observe (parameter, p.types.int_type, 0, span));
	assert (!inference.observe (parameter, p.types.f64_type, 1, span));
	flow.move (owner, "owner", span);
	assert (flow.verify ());
	var composed = new SemanticOwnershipFlow (span);
	composed.append (discarded);
	composed.move (owner, "owner", span);
	assert (!composed.verify ());
	var conditional = new SemanticOwnershipFlow (span);
	conditional.begin (GenericOwnershipEventKind.CHOICE, span, 0);
	conditional.move (owner, "owner", span);
	conditional.end ();
	var live = new SemanticOwnershipFlow (span);
	live.append (conditional);
	live.move (owner, "owner", span);
	assert (live.verify ());
	// Inferred owned forwarding checks the definition once; probing a move
	// via check_move would incorrectly produce a duplicate move here.
	check ("owned T relay<T>(owned T x) where T : Ownable{return move x;}owned T outer<T>(owned T x) where T : Ownable{return relay(move x);}");
}

private void equivalence() {
	foreach (string name in fixtures ()) {
		assert (SemanticDump.format (fixture (name)) == SemanticDump.format (fixture (name, false)));
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-infer/semantic/complete-canonical-universe", exact_universe);
	Test.add_func ("/gen-infer/semantic/standalone-literals-conversion-null-bits", literals);
	Test.add_func ("/gen-infer/semantic/exact-outer-symbols-observations", symbolic);
	Test.add_func ("/gen-infer/semantic/discarded-proof-no-owner-consumption", ownership_proofs);
	Test.add_func ("/gen-infer/semantic/explicit-inferred-equivalence", equivalence);
	return Test.run ();
}

}
