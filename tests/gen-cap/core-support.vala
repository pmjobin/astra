// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Core;
namespace Astra.Tests.GenCapCore {
private SourceSpan span() {
	return SourceSpan (new SourceFile.from_text ("capability", "T"), 0, 1);
}

private CoreProgram sample(GenericOperationKind kind = GenericOperationKind.ADD, string type_name = "int", bool unused = false) {
	var s = span ();
	var types = new BuiltinTypes ();
	var concrete = types.resolve (type_name);
	var type = new TypeParameterType ("T", new GenericCapabilitySet (new GenericCapabilityIdentity[] {kind.capability ()}));
	var tp = new CoreTypeParameter (s, type, 0);
	var parameters = new GenericArray<CoreTypeParameter> ();
	parameters.add (tp);
	var requirement = new CoreGenericCapabilityRequirement (s, tp, kind.capability ());
	tp.capability_requirements.add (requirement);
	var args = new GenericArray<CoreParameter> ();
	args.add (new CoreParameter (s, s, "a", type, 0));
	if (kind != GenericOperationKind.BIT_NOT) {
		args.add (new CoreParameter (s, s, "b", kind.is_shift () ? types.int_type : (SemanticType) type, 1));
	}
	var result = kind.is_comparison () ? types.bool_type : (SemanticType) type;
	var body = new CoreBlock (s, new GenericArray<CoreStatement> ());
	body.statements.add (new CoreReturn (s, new CoreGenericCapabilityOperation (s, result, kind, tp, kind.capability (), new CoreParameterValue (s, args[0]), args.length == 1 ? null : new CoreParameterValue (s, args[1]))));
	var definition = new CoreGenericFunction (s, s, "operation", result, args, new GenericArray<CoreLocalPlace> (), body, null, parameters, 0);
	definition.capability_requirements.add (requirement);
	var roots = new GenericArray<CoreFunction> ();
	var root_body = new CoreBlock (s, new GenericArray<CoreStatement> ());
	var root_args = new GenericArray<CoreParameter> ();
	foreach (var p in args) {
		root_args.add (new CoreParameter (s, s, p.name, p.semantic_type == type ? concrete : p.semantic_type, p.ordinal));
	}
	var root = new CoreFunction (s, s, "root", kind.is_comparison () ? types.bool_type : concrete, root_args, new GenericArray<CoreLocalPlace> (), root_body);
	roots.add (root);
	var actuals = new GenericArray<SemanticType> ();
	actuals.add (concrete);
	var values = new GenericArray<CoreValue> ();
	foreach (var p in root_args) {
		values.add (new CoreParameterValue (s, p));
	}
	root_body.statements.add (new CoreReturn (s, unused ? (CoreValue) new CoreParameterValue (s, root_args[0]) : new CoreGenericCall (s, root.return_type, definition, actuals, values)));
	var program = new CoreProgram (s, roots);
	program.generic_functions.add (definition);
	return program;
}

}
