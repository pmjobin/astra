// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Source;

private static GenericArray<SemanticType> arguments(SemanticType first, SemanticType second, SemanticType third) {
	var result = new GenericArray<SemanticType> ();
	result.add (first);
	result.add (second);
	result.add (third);
	return result;
}

private static void nominal_tuple() {
	var types = new BuiltinTypes ();
	var left = new ClassType ("SameSpelling");
	var right = new ClassType ("SameSpelling");
	var vector = new TypeArgumentVector (arguments (left, types.int_type, types.bool_type));
	assert (vector.matches (new TypeArgumentVector (arguments (left, types.int_type, types.bool_type))));
	assert (!vector.matches (new TypeArgumentVector (arguments (right, types.int_type, types.bool_type))));
	assert (!vector.matches (new TypeArgumentVector (arguments (left, types.bool_type, types.int_type))));
	assert (!vector.matches (new TypeArgumentVector.single (left)));
}

private static void immutable_tuple() {
	var types = new BuiltinTypes ();
	var source = arguments (types.int_type, types.bool_type, types.int_type);
	var vector = new TypeArgumentVector (source);
	source[1] = types.int_type;
	assert (vector.at (1) == types.bool_type);
	var copy = vector.copy_values ();
	copy[0] = types.bool_type;
	assert (vector.at (0) == types.int_type);
	assert (vector.length == 3 && vector.closed ());
}

private static void request_key_collisions() {
	var types = new BuiltinTypes ();
	var declaration = new Object ();
	var other = new Object ();
	var left = new StructType ("SameSpelling");
	var right = new StructType ("SameSpelling");
	var tuple = new TypeArgumentVector (arguments (types.int_type, left, types.bool_type));
	var key = new GenericRequestKey (declaration, tuple);
	var alias = new GenericRequestKey (declaration, new TypeArgumentVector (arguments (types.i32_type, left, types.bool_type)));
	assert (GenericRequestKey.equal (key, alias) && GenericRequestKey.hash (key) == GenericRequestKey.hash (alias));
	// Force collisions: lookup must still distinguish declaration, nominal type,
	// tuple order and heap/caller-backed storage policy.
	var cache = new HashTable<GenericRequestKey, int> ((candidate) => 0, GenericRequestKey.equal);
	cache.insert (key, 1);
	cache.insert (new GenericRequestKey (other, tuple), 2);
	cache.insert (new GenericRequestKey (declaration, new TypeArgumentVector (arguments (types.int_type, right, types.bool_type))), 3);
	cache.insert (new GenericRequestKey (declaration, new TypeArgumentVector (arguments (types.bool_type, left, types.int_type))), 4);
	cache.insert (new GenericRequestKey (declaration, tuple, 0), 5);
	assert (cache.size () == 5 && cache.lookup (alias) == 1);
	assert (cache.lookup (new GenericRequestKey (other, tuple)) == 2);
	assert (cache.lookup (new GenericRequestKey (declaration, tuple, 0)) == 5);
	cache.insert (alias, 6);
	assert (cache.size () == 5 && cache.lookup (key) == 6);
}

private static void substituted_tuple() {
	var types = new BuiltinTypes ();
	var first = new TypeParameterType ("T");
	var unrelated = new TypeParameterType ("T");
	var original = arguments (first, unrelated, types.bool_type);
	assert (!new TypeArgumentVector (original).closed ());
	var substitution = new TypeSubstitution ();
	substitution.bind (first, types.int_type);
	var result = new TypeArgumentVector (substitution.apply_arguments (original));
	assert (result.at (0) == types.int_type);
	assert (result.at (1) == unrelated);
	assert (!result.closed ());
	substitution.bind (unrelated, types.bool_type);
	assert (new TypeArgumentVector (substitution.apply_arguments (original)).closed ());
}

private static void storage_vectors() {
	bool[] inputs = {
		false, true, false, true
	};
	var storage = new GenericStorageVector (inputs);
	inputs[1] = false;
	assert (storage.count == 2 && storage.parameter (0) == 1 && storage.parameter (1) == 3);
	assert (storage.is_heap (1) && storage.is_heap (3) && !storage.is_heap (0));
	assert (storage.valid (4) && !storage.valid (3));
	assert (!new GenericStorageVector.single (-2).valid (4));
	var types = new BuiltinTypes ();
	var definition = new Object ();
	var tuple = new TypeArgumentVector.single (types.int_type);
	var caller = new GenericRequestKey (definition, tuple);
	var first = new GenericRequestKey (definition, tuple, 1);
	var padded = new GenericRequestKey (definition, tuple, -1, new GenericStorageVector (new bool[] { false, true, false, false }));
	assert (GenericRequestKey.equal (first, padded));
	assert (GenericRequestKey.hash (first) == GenericRequestKey.hash (padded));
	assert (GenericRequestKey.equal (caller, new GenericRequestKey (definition, tuple, -1, new GenericStorageVector (new bool[4]))));
	var multiple = new GenericRequestKey (definition, tuple, -1, storage);
	var other = new GenericRequestKey (definition, tuple, 3);
	var cache = new HashTable<GenericRequestKey, int> ((key) => 0, GenericRequestKey.equal);
	cache.insert (caller, 10);
	cache.insert (first, 11);
	cache.insert (other, 13);
	cache.insert (multiple, 14);
	assert (cache.size () == 4);
	assert (cache.lookup (padded) == 11 && cache.lookup (multiple) == 14);
	assert (cache.lookup (caller) == 10 && cache.lookup (other) == 13);
}

private static void storage_requirements() {
	var input = new Object ();
	var alternate = new Object ();
	var helper = new Object ();
	var terminal = new Object ();
	var neighbor = new Object ();
	var caller = new Object ();
	var graph = new GenericStorageRequirements ();
	graph.link (input, helper);
	graph.link (helper, input);
	graph.link (input, alternate);
	graph.link (alternate, terminal);
	graph.constrain (terminal, GenericStorageRequirements.HEAP);
	graph.constrain (caller, GenericStorageRequirements.CALLER);
	graph.solve ();
	assert (graph.permits (input, true) && !graph.permits (input, false));
	assert (graph.allowed (helper) == GenericStorageRequirements.HEAP);
	assert (graph.allowed (alternate) == GenericStorageRequirements.HEAP);
	assert (graph.reason (input, false) == terminal && graph.reason (helper, false) == terminal);
	assert (graph.allowed (neighbor) == GenericStorageRequirements.EITHER);
	assert (graph.permits (caller, false) && !graph.permits (caller, true));
	graph.link (input, caller);
	graph.solve ();
	assert (graph.allowed (input) == 0 && graph.allowed (helper) == 0);
	assert (graph.allowed (terminal) == GenericStorageRequirements.HEAP);
	assert (graph.allowed (neighbor) == GenericStorageRequirements.EITHER);
}

private static void reachable_owner_transfers() {
	var span = SourceSpan (new SourceFile.from_text ("owner-edges.astra", "x"), 0, 1);
	var owner = new Object ();
	var neighbor = new Object ();
	var first = new Object ();
	var second = new Object ();
	var forbidden = new Object ();
	var flow = new GenericOwnershipFlow (span);
	flow.begin (GenericOwnershipEventKind.CHOICE, span);
	flow.move (owner, "owner", span, first, 0);
	flow.arm (1);
	flow.move (owner, "owner", span, second, 1);
	flow.end ();
	flow.begin (GenericOwnershipEventKind.CHOICE, span, 0);
	flow.move (neighbor, "neighbor", span, forbidden, 2);
	flow.arm (1);
	flow.owner_event (GenericOwnershipEventKind.READ, neighbor, "neighbor", span);
	flow.end ();
	flow.jump (GenericOwnershipEventKind.RETURN, span);
	flow.move (neighbor, "neighbor", span, forbidden, 3);
	assert (flow.verify ());
	assert (!flow.transfer_scopes.lookup (owner).valid);
	var transfers = flow.transfers_for (owner);
	assert (transfers.length == 2);
	assert (transfers[0].target == first && transfers[0].parameter == 0);
	assert (transfers[1].target == second && transfers[1].parameter == 1);
	assert (flow.transfers_for (neighbor).length == 0);
	transfers.remove_index (0);
	assert (flow.transfers_for (owner).length == 2);
	var loop = new Object ();
	var repeated = new GenericOwnershipFlow (span);
	repeated.begin (GenericOwnershipEventKind.LOOP, span, 1, loop);
	repeated.arm (1);
	repeated.move (owner, "owner", span, first, 0);
	repeated.jump (GenericOwnershipEventKind.BREAK, span, loop);
	repeated.arm (2);
	repeated.end ();
	assert (repeated.verify ());
	assert (!repeated.transfer_scopes.lookup (owner).valid);
	assert (repeated.transfers_for (owner).length == 1);
	var temporary = new Object ();
	var local = new GenericOwnershipFlow (span);
	local.move (owner, "owner", span, temporary, -1, false, true);
	local.move (temporary, "temporary", span, second, 1);
	assert (local.verify ());
	var incoming = local.transfers_for (owner);
	var outgoing = local.transfers_for (temporary);
	assert (incoming.length == 1 && incoming[0].local && incoming[0].target == temporary);
	assert (outgoing.length == 1 && !outgoing[0].local && outgoing[0].target == second);
}

private static void aggregate_initialization() {
	var types = new BuiltinTypes ();
	var record = new StructType ("Pair");
	CopyabilityFields fields = (type) => {
		if (type != record) {
			return null;
		}
		var result = new GenericArray<SemanticType> ();
		result.add (types.int_type);
		result.add (types.bool_type);
		return result;
	};
	try {
		var names = StructLeafOrder.path_names (record, fields);
		var empty = new FieldInitializationState (1);
		var left = empty.copy ();
		assert (left.initialize_record_part (0, "0", names));
		assert (!left.is_definite (0) && left.is_part_possible (0, "0"));
		assert (!left.is_part_possible (0, "1"));
		var right = empty.copy ();
		assert (right.initialize_record_part (0, "1", names));
		var partial = FieldInitializationState.join (left, right);
		assert (!partial.is_definite (0));
		assert (partial.is_part_possible (0, "0") && partial.is_part_possible (0, "1"));
		assert (left.initialize_record_part (0, "1", names));
		assert (left.is_definite (0));
		assert (!FieldInitializationState.join (left, right).is_definite (0));
		assert (right.initialize_record_part (0, "0", names));
		assert (FieldInitializationState.join (left, right).is_definite (0));
		assert (!empty.initialize_record_part (0, "2", names));
		assert (empty.same_as (new FieldInitializationState (1)));
	} catch (StructLeafError error) {
		assert_not_reached ();
	}
}

private void closure_substitution() {
	var types = new BuiltinTypes ();
	var input = new TypeParameterType ("T");
	var output = new TypeParameterType ("T");
	var environment = new ClassType ("Environment");
	var error = new ClassType ("Error");
	var resource = new HandleType ("Resource");
	var parameters = new GenericArray<SemanticType> ();
	parameters.add (input);
	var contracts = new GenericArray<PointerParameterContract> ();
	contracts.add (PointerParameterContract.UNMANAGED);
	var original = new ClosureHandleType (environment, output, parameters, error, false, false, contracts, ResultOwnershipContract.OWNED_TRANSFER);
	assert (original.is_parameterized () && !new TypeArgumentVector.single (original).closed ());
	var substitution = new TypeSubstitution ();
	substitution.bind (input, types.int_type);
	var partial = (ClosureHandleType) substitution.apply (original);
	assert (partial.parameter_types[0] == types.int_type && partial.result_type == output && partial.is_parameterized ());
	substitution.bind (output, resource);
	var complete = (ClosureHandleType) substitution.apply (original);
	assert (complete == substitution.apply (original) && !complete.is_parameterized ());
	assert (complete.environment_type == environment && complete.throws_type == error && complete.result_type == resource && complete.result_contract == ResultOwnershipContract.OWNED_TRANSFER);
	assert (substitution.matches (original, complete));
	assert (!substitution.matches (original, new ClosureHandleType (new ClassType ("Environment"), resource, complete.parameter_types, error, false, false, contracts, ResultOwnershipContract.OWNED_TRANSFER)));
	assert (!substitution.matches (original, new ClosureHandleType (environment, resource, complete.parameter_types, new ClassType ("Error"), false, false, contracts, ResultOwnershipContract.OWNED_TRANSFER)));
	assert (!substitution.matches (original, new ClosureHandleType (environment, resource, complete.parameter_types, error, false, false, contracts)));
	assert (original.parameter_types[0] == input && original.result_type == output);
}

private void result_origin_equations() {
	int[] inputs = {
		1
	};
	var original = new GenericResultOrigins (0, inputs);
	inputs[0] = 0;
	assert (original.input (0) == 1);
	var arguments = new GenericArray<GenericResultOrigins> ();
	arguments.add (new GenericResultOrigins (GenericResultOrigins.CALLER));
	arguments.add (new GenericResultOrigins (0, new int[] {2}));
	var composed = original.compose (arguments);
	assert (composed.input_count == 1 && composed.input (0) == 2 && composed.domains == 0);
	assert (composed.evaluate (new bool[] {false, true, false}) == GenericResultOrigins.CALLER);
	assert (composed.evaluate (new bool[] {false, false, true}) == GenericResultOrigins.HEAP);
	var produced = new GenericResultOrigins (GenericResultOrigins.HEAP);
	assert (produced.compose (arguments).same (produced) && produced.input_count == 0);
	var joined = original.union (composed).union (original);
	assert (joined.input_count == 2 && joined.same (composed.union (original)));
	assert (joined.evaluate (new bool[] {false, false, true}) == (GenericResultOrigins.CALLER | GenericResultOrigins.HEAP));
	assert (new GenericResultOrigins (GenericResultOrigins.UNKNOWN).evaluate (new bool[0]) == GenericResultOrigins.UNKNOWN);
	assert (composed.evaluate (new bool[0]) == GenericResultOrigins.UNKNOWN);
}

private void callable_substitution() {
	var types = new BuiltinTypes ();
	var first = new TypeParameterType ("T");
	var unrelated = new TypeParameterType ("T");
	var inputs = new GenericArray<SemanticType> ();
	inputs.add (first);
	var original = types.function_value (unrelated, inputs);
	assert (original.is_parameterized ());
	var substitution = new TypeSubstitution (null, types.substitute_function);
	substitution.bind (first, types.int_type);
	var partial = (FunctionValueType) substitution.apply (original);
	assert (partial.parameter_types[0] == types.int_type && partial.result_type == unrelated);
	substitution.bind (unrelated, types.bool_type);
	var complete = (FunctionValueType) substitution.apply (original);
	assert (!complete.is_parameterized ());
	var expected_inputs = new GenericArray<SemanticType> ();
	expected_inputs.add (types.int_type);
	assert (complete == types.function_value (types.bool_type, expected_inputs));
	assert (substitution.matches (original, complete));
	var other_nominal = new ClassType ("SameSpelling");
	var nominal = new ClassType ("SameSpelling");
	var borrowed = new GenericArray<PointerParameterContract> ();
	borrowed.add (PointerParameterContract.BORROWED_NOESCAPE);
	var left_inputs = new GenericArray<SemanticType> ();
	left_inputs.add (nominal);
	var right_inputs = new GenericArray<SemanticType> ();
	right_inputs.add (other_nominal);
	var left = types.function_value (types.int_type, left_inputs, borrowed);
	var right = types.function_value (types.int_type, right_inputs, borrowed);
	assert (!substitution.matches (left, right));
	var consumed = new GenericArray<PointerParameterContract> ();
	consumed.add (PointerParameterContract.OWNED_TRANSFER);
	assert (!substitution.matches (left, types.function_value (types.int_type, left_inputs, consumed)));
}

private void code_parameter_obligations() {
	var graph = new Astra.Code.CodeOrigins ();
	var formal = new Object ();
	var local = new Object ();
	var address = new Object ();
	var target = new Object ();
	graph.parameter (formal);
	graph.copy (local, formal);
	graph.address (address, target);
	graph.copy (formal, address);
	var parameters = new GenericArray<Object> ();
	parameters.add (formal);
	var obligation = graph.frontier (local, parameters);
	assert (obligation != null && obligation.parameters.length == 1 && obligation.parameters[0] == formal);
	assert (obligation.targets.length == 0);
	// Concrete call-site checking remains separate from the generic promise.
	var concrete = graph.targets (local);
	assert (concrete != null && concrete.length == 1 && concrete[0] == target);
	graph.unknown (formal);
	assert (graph.frontier (local, parameters) == null);
}

private void code_mixed_obligations() {
	var graph = new Astra.Code.CodeOrigins ();
	var first = new Object ();
	var second = new Object ();
	var joined = new Object ();
	var address = new Object ();
	var target = new Object ();
	graph.parameter (first);
	graph.parameter (second);
	graph.copy (joined, first);
	graph.copy (joined, second);
	graph.address (address, target);
	graph.copy (joined, address);
	var parameters = new GenericArray<Object> ();
	parameters.add (first);
	parameters.add (second);
	var obligation = graph.frontier (joined, parameters);
	assert (obligation != null && obligation.parameters.length == 2 && obligation.targets.length == 1);
	assert (obligation.parameters.find (first) && obligation.parameters.find (second) && obligation.targets[0] == target);
	// An unrelated declaration's formal must not be specialized to its
	// currently observed callers while deriving this declaration's promise.
	var unrelated = new Object ();
	graph.parameter (unrelated);
	graph.copy (unrelated, address);
	graph.copy (joined, unrelated);
	assert (graph.frontier (joined, parameters) == null);
	var opaque = new Object ();
	graph.copy (joined, opaque);
	assert (graph.frontier (joined, parameters) == null);
}

private void code_cyclic_obligations() {
	var graph = new Astra.Code.CodeOrigins ();
	var first = new Object ();
	var second = new Object ();
	graph.copy (first, second);
	graph.copy (second, first);
	var parameters = new GenericArray<Object> ();
	assert (graph.frontier (first, parameters) == null);
	var formal = new Object ();
	graph.parameter (formal);
	parameters.add (formal);
	graph.copy (second, formal);
	var obligation = graph.frontier (first, parameters);
	assert (obligation != null && obligation.parameters.length == 1 && obligation.parameters[0] == formal);
	var storage = new Object ();
	graph.storage (storage);
	graph.copy (storage, formal);
	assert (graph.frontier (storage, parameters) == null);
	graph.escape_storage ();
	assert (graph.frontier (storage, parameters) == null);
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/generic-arguments/nominal-order-and-arity", nominal_tuple);
	Test.add_func ("/generic-arguments/immutable-caller-worklists", immutable_tuple);
	Test.add_func ("/generic-arguments/lexical-substitution", substituted_tuple);
	Test.add_func ("/generic-arguments/request-cache-collisions-retain-exact-identities", request_key_collisions);
	Test.add_func ("/generic-arguments/storage-vectors-preserve-independent-parameters", storage_vectors);
	Test.add_func ("/generic-arguments/ownership-edges-retain-reachable-branches-loops-and-locals", reachable_owner_transfers);
	Test.add_func ("/generic-arguments/storage-requirements-compose-per-input-through-cycles-and-branches", storage_requirements);
	Test.add_func ("/generic-fields/aggregate-definite-and-possible-prefixes", aggregate_initialization);
	Test.add_func ("/generic-arguments/callable-substitution-retains-nominal-and-channel-identity", callable_substitution);
	Test.add_func ("/generic-arguments/closure-substitution-retains-environment-error-and-ownership", closure_substitution);
	Test.add_func ("/generic-arguments/result-origin-equations-preserve-independent-inputs", result_origin_equations);
	Test.add_func ("/code-obligations/formal-boundaries-preserve-call-site-proof", code_parameter_obligations);
	Test.add_func ("/code-obligations/mixed-addresses-and-independent-inputs", code_mixed_obligations);
	Test.add_func ("/code-obligations/cycles-and-opaque-storage", code_cyclic_obligations);
	return Test.run ();
}
