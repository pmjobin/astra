// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Core;
namespace Astra.Tests.GenOwnCore {
private CoreGenericFunction generic(SourceSpan span, string name, int ordinal, bool returned, BuiltinTypes types, GenericArray<CoreCleanupContract> contracts) {
	var type = new TypeParameterType ("T", new GenericCapabilitySet (new GenericCapabilityIdentity[] {GenericCapabilityIdentity.OWNABLE}));
	var parameter = new CoreTypeParameter (span, type, 0);
	var type_parameters = new GenericArray<CoreTypeParameter> ();
	type_parameters.add (parameter);
	var requirement = new CoreGenericCapabilityRequirement (span, parameter, GenericCapabilityIdentity.OWNABLE);
	parameter.capability_requirements.add (requirement);
	var contract = new CoreCleanupContract.for_parameter (type, span, contracts.length);
	contracts.add (contract);
	var parameters = new GenericArray<CoreParameter> ();
	var incoming = new CoreParameter (span, span, "value", type, 0, PointerParameterContract.OWNED_TRANSFER);
	parameters.add (incoming);
	var locals = new GenericArray<CoreLocalPlace> ();
	var place = new CoreLocalPlace (span, span, "value", type, 0, false, incoming);
	locals.add (place);
	var body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	var owner = new CoreOwnedLocal (span, place, contract, body);
	body.statements.add (new CoreAcquireParameter (span, owner, incoming));
	if (returned) {
		body.statements.add (new CoreOwnershipReturn (span, type, contract, owner));
	}
	var function = new CoreGenericFunction (span, span, name, returned ? (SemanticType) type : types.void_type, parameters, locals, body, returned ? contract : null, type_parameters, ordinal);
	function.capability_requirements.add (requirement);
	function.owned_locals.add (owner);
	return function;
}
private CoreProgram sample(bool resource = false, bool drop = false, bool unused = false) {
	var span = SourceSpan (new SourceFile.from_text ("ownership", "T"), 0, 1);
	var types = new BuiltinTypes ();
	var object_class = new CoreClass (span, span, "Empty", new ClassType ("Empty"));
	var handle = new HandleType ("Resource");
	SemanticType concrete = resource ? (SemanticType) handle : object_class.semantic_type;
	var cleanup = resource ? new CoreCleanupContract ("release", span, 0) : new CoreCleanupContract.for_object (object_class, 0);
	var cleanups = new GenericArray<CoreCleanupContract> ();
	cleanups.add (cleanup);
	var handles = new GenericArray<CoreHandle> ();
	if (resource) {
		handles.add (new CoreHandle (span, span, handle, cleanup, null, 0));
	}
	var dispose = generic (span, "dispose", 0, false, types, cleanups);
	var relay = generic (span, "relay", 1, true, types, cleanups);
	var forward = generic (span, "forward", 2, true, types, cleanups);
	var forwarded_arguments = new GenericArray<CoreValue> ();
	forwarded_arguments.add (new CoreOwnedArgumentValue (span, relay.parameters[0], forward.owned_cleanup, forward.owned_locals[0], forward.return_type));
	var forwarded_types = new GenericArray<SemanticType> ();
	forwarded_types.add (forward.return_type);
	forward.body.statements.remove_index (1);
	forward.body.statements.add (new CoreOwnershipReturn (span, forward.return_type, forward.owned_cleanup, null, new CoreGenericCall (span, forward.return_type, relay, forwarded_types, forwarded_arguments)));
	var definitions = new GenericArray<CoreFunction> ();
	if (!unused) {
		var parameters = new GenericArray<CoreParameter> ();
		var parameter = new CoreParameter (span, span, "owner", concrete, 0, PointerParameterContract.OWNED_TRANSFER);
		parameters.add (parameter);
		var locals = new GenericArray<CoreLocalPlace> ();
		var local = new CoreLocalPlace (span, span, "owner", concrete, 0, false, parameter);
		locals.add (local);
		var body = new CoreBlock (span, new GenericArray<CoreStatement> ());
		var owner = new CoreOwnedLocal (span, local, cleanup, body);
		var root = new CoreFunction (span, span, "root", drop ? types.void_type : concrete, parameters, locals, body, drop ? null : cleanup);
		root.owned_locals.add (owner);
		if (!drop && !resource) {
			root.result_storage = new CoreResultObjectStorage (span, object_class);
		}
		body.statements.add (new CoreAcquireParameter (span, owner, parameter));
		var arguments = new GenericArray<CoreValue> ();
		arguments.add (new CoreOwnedArgumentValue (span, drop ? dispose.parameters[0] : forward.parameters[0], cleanup, owner, concrete));
		var actuals = new GenericArray<SemanticType> ();
		actuals.add (concrete);
		if (drop) {
			body.statements.add (new CoreGenericCallStatement (span, dispose, actuals, arguments));
		} else {
			var call = new CoreGenericCall (span, concrete, forward, actuals, arguments);
			call.result_storage = root.result_storage;
			body.statements.add (new CoreOwnershipReturn (span, concrete, cleanup, null, call, resource ? ObjectResultProvenance.NONE : ObjectResultProvenance.FORWARDED_OWNED_RESULT));
		}
		definitions.add (root);
	}
	var program = new CoreProgram (span, definitions, null, null, null, cleanups, handles);
	if (!resource) {
		program.classes.add (object_class);
	}
	program.generic_functions.add (dispose);
	program.generic_functions.add (relay);
	program.generic_functions.add (forward);
	return program;
}

}
