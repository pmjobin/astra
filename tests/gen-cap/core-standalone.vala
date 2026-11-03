// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Core;
namespace Astra.Tests.GenCapCore {
private bool rejects(CoreProgram program) {
	try {
		CoreVerifier.verify (program);
	} catch (CoreError error) {
		return true;
	}
	return false;
}

private void requirements() {
	try {
		CoreVerifier.verify (sample ());
	} catch (CoreError error) {
		GLib.error ("%s", error.message);
	}
	var missing = sample ();
	missing.generic_functions[0].capability_requirements.remove_index (0);
	assert (rejects (missing));
	var duplicate = sample ();
	var d = duplicate.generic_functions[0];
	d.capability_requirements.add (d.capability_requirements[0]);
	assert (rejects (duplicate));
	var foreign = sample ();
	var g = foreign.generic_functions[0];
	var p = new CoreTypeParameter (g.span, g.type_parameters[0].semantic_type, 0);
	g.capability_requirements.remove_index (0);
	g.capability_requirements.add (new CoreGenericCapabilityRequirement (g.span, p, GenericCapabilityIdentity.NUMERIC));
	assert (rejects (foreign));
	assert (rejects (sample (GenericOperationKind.ADD, "bool")));
	var invalid_identity = sample ();
	var tp = invalid_identity.generic_functions[0].type_parameters[0];
	tp.capability_requirements.remove_index (0);
	tp.capability_requirements.add (new CoreGenericCapabilityRequirement (tp.span, tp, (GenericCapabilityIdentity) 99));
	assert (rejects (invalid_identity));
}

private void forwarding() {
	try {
		var program = sample (GenericOperationKind.EQ);
		CoreVerifier.verify (program);
		var inner = program.generic_functions[0];
		var other = sample ();
		var template = other.generic_functions[0];
		var body = new CoreBlock (template.span, new GenericArray<CoreStatement> ());
		var outer = new CoreGenericFunction (template.span, template.span, "outer", inner.return_type, template.parameters, template.locals, body, null, template.type_parameters, 1);
		foreach (var requirement in template.capability_requirements) {
			outer.capability_requirements.add (requirement);
		}
		var types = new GenericArray<SemanticType> ();
		types.add (outer.type_parameters[0].semantic_type);
		var values = new GenericArray<CoreValue> ();
		foreach (var parameter in outer.parameters) {
			values.add (new CoreParameterValue (inner.span, parameter));
		}
		body.statements.add (new CoreReturn (inner.span, new CoreGenericCall (inner.span, inner.return_type, inner, types, values)));
		program.generic_functions.add (outer);
		bool rejected = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			rejected = error.message.contains ("unsatisfied exact generic capability");
		}
		assert (rejected);
		var lost = sample ();
		var call = (CoreGenericCall) ((CoreReturn) lost.functions[0].body.statements[0]).value;
		call.target_requirements.remove_index (0);
		rejected = false;
		try {
			CoreVerifier.verify (lost);
		} catch (CoreError error) {
			rejected = error.message.contains ("lost target capability requirements");
		}
		assert (rejected);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void operations() {
	for (int scenario = 0; scenario < 6; scenario++) {
		var program = sample ();
		var generic = program.generic_functions[0];
		var types = new BuiltinTypes ();
		var original = (CoreGenericCapabilityOperation) ((CoreReturn) generic.body.statements[0]).value;
		var other = new CoreTypeParameter (generic.span, new TypeParameterType ("U"), 1);
		CoreValue rhs = scenario == 2 ? (CoreValue) new CoreBooleanValue (generic.span, types.bool_type, BooleanLiteral.TRUE) : original.right;
		var operation = new CoreGenericCapabilityOperation (generic.span, scenario == 1 ? types.bool_type : original.semantic_type, scenario == 4 ? (GenericOperationKind) 99 : scenario == 5 ? GenericOperationKind.EQ : original.operator_kind, scenario == 3 ? other : original.type_parameter, scenario == 0 ? GenericCapabilityIdentity.EQ : original.capability, original.left, rhs);
		generic.body.statements.remove_index (0);
		generic.body.statements.add (new CoreReturn (generic.span, operation));
		assert (rejects (program));
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-cap/core/requirements-identity-duplicates-concrete-call", requirements);
	Test.add_func ("/gen-cap/core/parametric-forwarding-retained-evidence", forwarding);
	Test.add_func ("/gen-cap/core/forged-operator-authority-identity-shapes", operations);
	return Test.run ();
}

}
