// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;

namespace Astra.Tests.RuntimeLifetimes {
private delegate void Check() throws GLib.Error;
private void refused(owned Check action) {
	bool rejected = false;
	try {
		action ();
	} catch (GLib.Error failure) {
		rejected = true;
		Test.message ("%s", failure.message);
	}
	assert (rejected);
}
private int allocation(RuntimeLifetimeEquations graph, int context = -1, int region = -1, string? field = null, int child = 0) throws GLib.Error {
	var roots = new GenericArray<RuntimeScopeOrigin> ();
	if (context >= 0) {
		roots.add (new RuntimeScopeOrigin.local (context, region));
	}
	var fields = new HashTable<string, int> (str_hash, str_equal);
	if (field != null) {
		fields.insert (field, child);
	}
	return graph.product (roots, fields);
}
private bool contains(GenericArray<RuntimeScopeOrigin> origins, int context) {
	foreach (var origin in origins) {
		if (origin.kind == RuntimeScopeOriginKind.LOCAL_CONTEXT && origin.ordinal == context) {
			return true;
		}
	}
	return false;
}
private void independent_origins() {
	try {
		var graph = new RuntimeLifetimeEquations ();
		int heap = allocation (graph);
		int scoped_child = allocation (graph, 11, 2);
		int container = allocation (graph, 7, 1, "e", heap);
		int scoped_container = allocation (graph, 7, 1, "e", scoped_child);
		int heap_element = graph.project (container, "e");
		int scoped_element = graph.project (scoped_container, "e");
		int replaced = graph.replace (scoped_container, "e", heap);
		graph.seal ();
		assert (graph.requirements (heap_element).length == 0);
		var roots = graph.requirements (container);
		assert (roots.length == 1 && contains (roots, 7));
		roots = graph.requirements (scoped_container);
		assert (roots.length == 2 && contains (roots, 7) && contains (roots, 11));
		roots = graph.requirements (scoped_element);
		assert (roots.length == 1 && contains (roots, 11));
		roots = graph.requirements (replaced);
		assert (roots.length == 1 && contains (roots, 7));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void nested_products() {
	try {
		var graph = new RuntimeLifetimeEquations ();
		int child = allocation (graph, 13, 4);
		int record = allocation (graph, -1, -1, "f0", child);
		int holder = allocation (graph, 8, 2, "f1", record);
		int extracted = graph.project (holder, "f1.f0");
		int replacement = graph.replace (holder, "f1", allocation (graph, -1, -1, "f0", graph.absent ()));
		graph.seal ();
		var roots = graph.requirements (holder, "", false);
		assert (roots.length == 1 && contains (roots, 8));
		roots = graph.requirements (extracted);
		assert (roots.length == 1 && contains (roots, 13));
		roots = graph.requirements (replacement);
		assert (roots.length == 1 && contains (roots, 8));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void opaque_substitution() {
	try {
		var producer = new RuntimeLifetimeEquations ();
		int input = producer.input (0);
		var roots = new GenericArray<RuntimeScopeOrigin> ();
		roots.add (new RuntimeScopeOrigin.context_input (1));
		var fields = new HashTable<string, int> (str_hash, str_equal);
		fields.insert ("c", input);
		int result = producer.product (roots, fields);
		producer.seal ();
		var caller = new RuntimeLifetimeEquations ();
		int actual = allocation (caller, 5, 2);
		var inputs = new HashTable<int, int> (direct_hash, direct_equal);
		inputs.insert (0, actual);
		var contexts = new HashTable<int, RuntimeScopeOrigin> (direct_hash, direct_equal);
		contexts.insert (1, new RuntimeScopeOrigin.local (9, 3));
		int bound = producer.instantiate (result, caller, inputs, contexts);
		int captured = caller.project (bound, "c");
		caller.seal ();
		var requirements = caller.requirements (bound);
		assert (requirements.length == 2 && contains (requirements, 5) && contains (requirements, 9));
		requirements = caller.requirements (captured);
		assert (requirements.length == 1 && contains (requirements, 5));
		var missing = new RuntimeLifetimeEquations ();
		inputs.remove (0);
		refused (() => producer.instantiate (result, missing, inputs, contexts));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void replacement_summary() {
	try {
		var producer = new RuntimeLifetimeEquations ();
		int old = producer.input (-1);
		int incoming = producer.input (0);
		int updated = producer.replace (old, "f0", incoming);
		producer.seal ();
		var requirements = producer.requirements (updated);
		bool excluded = false;
		foreach (var origin in requirements) {
			assert (origin.valid ());
			if (origin.ordinal == -1) {
				assert (origin.descendants && origin.exclusion_count == 1 && origin.exclusion (0) == "f0");
				excluded = true;
			}
		}
		assert (excluded);
		var caller = new RuntimeLifetimeEquations ();
		int stale = allocation (caller, 4, 1);
		int live = allocation (caller, 9, 3);
		int receiver = allocation (caller, 2, 0, "f0", stale);
		var inputs = new HashTable<int, int> (direct_hash, direct_equal);
		inputs.insert (-1, receiver);
		inputs.insert (0, live);
		var contexts = new HashTable<int, RuntimeScopeOrigin> (direct_hash, direct_equal);
		int bound = producer.instantiate (updated, caller, inputs, contexts);
		caller.seal ();
		requirements = caller.requirements (bound);
		assert (requirements.length == 2 && contains (requirements, 2) && contains (requirements, 9) && !contains (requirements, 4));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void recursive_backedges() {
	try {
		RuntimeLifetimeEquations? graph = new RuntimeLifetimeEquations ();
		var reference = WeakRef (graph);
		int loop = graph.join ();
		int seed = allocation (graph, 3, 1);
		int next = allocation (graph, 8, 2, "f0", loop);
		graph.alternative (loop, seed);
		graph.alternative (loop, next);
		int child = graph.project (next, "f0");
		graph.seal ();
		var requirements = graph.requirements (child);
		assert (requirements.length == 2 && contains (requirements, 3) && contains (requirements, 8));
		graph = null;
		assert (reference.get () == null);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void original_allocation_root() {
	try {
		var producer = new RuntimeLifetimeEquations ();
		int environment = producer.input (0);
		var roots = new GenericArray<RuntimeScopeOrigin> ();
		var fields = new HashTable<string, int> (str_hash, str_equal);
		fields.insert ("c", environment);
		var sources = new GenericArray<int> ();
		sources.add (environment);
		int carrier = producer.product (roots, fields, sources);
		producer.seal ();
		var caller = new RuntimeLifetimeEquations ();
		int child = allocation (caller, 11, 3);
		int actual = allocation (caller, 7, 1, "f0", child);
		var inputs = new HashTable<int, int> (direct_hash, direct_equal);
		inputs.insert (0, actual);
		var contexts = new HashTable<int, RuntimeScopeOrigin> (direct_hash, direct_equal);
		int closure = producer.instantiate (carrier, caller, inputs, contexts);
		int extracted = caller.project (closure, "c.f0");
		caller.seal ();
		var requirements = caller.requirements (closure, "", false);
		assert (requirements.length == 1 && contains (requirements, 7));
		requirements = caller.requirements (closure);
		assert (requirements.length == 2 && contains (requirements, 7) && contains (requirements, 11));
		requirements = caller.requirements (extracted);
		assert (requirements.length == 1 && contains (requirements, 11));
		var ungrounded = new RuntimeLifetimeEquations ();
		int loop = ungrounded.join ();
		var recursive_sources = new GenericArray<int> ();
		recursive_sources.add (loop);
		int recursive = ungrounded.product (roots, new HashTable<string, int> (str_hash, str_equal), recursive_sources);
		ungrounded.alternative (loop, recursive);
		ungrounded.seal ();
		refused (() => ungrounded.requirements (recursive));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void recursive_projection() {
	try {
		var producer = new RuntimeLifetimeEquations ();
		int loop = producer.join ();
		int input = producer.input (0);
		int step = producer.project (loop, "f0");
		producer.alternative (loop, input);
		producer.alternative (loop, step);
		producer.seal ();
		var symbolic = producer.requirements (loop, "", false);
		bool widened = false;
		foreach (var origin in symbolic) {
			if (origin.descendants && origin.path == "") {
				widened = true;
			}
		}
		assert (widened);
		var caller = new RuntimeLifetimeEquations ();
		int tail = allocation (caller, 11, 4, "f0", caller.absent ());
		int head = allocation (caller, 7, 2, "f0", tail);
		var inputs = new HashTable<int, int> (direct_hash, direct_equal);
		inputs.insert (0, head);
		var contexts = new HashTable<int, RuntimeScopeOrigin> (direct_hash, direct_equal);
		int bound = producer.instantiate (loop, caller, inputs, contexts);
		caller.seal ();
		var requirements = caller.requirements (bound);
		assert (requirements.length == 2 && contains (requirements, 7) && contains (requirements, 11));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void escape_and_grounding() {
	try {
		var producer = new RuntimeLifetimeEquations ();
		int local = allocation (producer, 3, 1);
		producer.seal ();
		var caller = new RuntimeLifetimeEquations ();
		var inputs = new HashTable<int, int> (direct_hash, direct_equal);
		var contexts = new HashTable<int, RuntimeScopeOrigin> (direct_hash, direct_equal);
		refused (() => producer.instantiate (local, caller, inputs, contexts));
		var graph = new RuntimeLifetimeEquations ();
		int loop = graph.join ();
		graph.alternative (loop, loop);
		int holder = allocation (graph, 2, 0, "f0", loop);
		graph.seal ();
		refused (() => graph.requirements (loop));
		refused (() => graph.requirements (holder));
		assert (graph.requirements (holder, "", false).length == 1);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void malformed_and_sealed() {
	try {
		var graph = new RuntimeLifetimeEquations ();
		int value = allocation (graph);
		refused (() => graph.requirements (value));
		refused (() => graph.project (value, "f01"));
		refused (() => graph.project (value, "f2147483648"));
		refused (() => graph.project (value, ".f0"));
		refused (() => graph.replace (value, "f0.f1", value));
		var roots = new GenericArray<RuntimeScopeOrigin> ();
		roots.add (new RuntimeScopeOrigin.local (0, -1));
		var fields = new HashTable<string, int> (str_hash, str_equal);
		refused (() => graph.product (roots, fields));
		int loop = graph.join ();
		graph.alternative (loop, value);
		graph.seal ();
		assert (graph.requirements (loop).length == 0);
		refused (() => graph.alternative (loop, value));
		refused (() => graph.project (value, "f0"));
		refused (() => graph.requirements (value, "f0"));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void actual_storage_extent() {
	try {
		var graph = new RuntimeLifetimeEquations ();
		int heap = allocation (graph);
		int outer = allocation (graph, 10, 1, "e", heap);
		int inner = allocation (graph, 20, 2);
		int nested = allocation (graph, 10, 1, "f0", inner);
		int extracted = graph.project (outer, "e");
		int forged = allocation (graph, 10, 0);
		int owner_input = graph.input (0);
		var roots = new GenericArray<RuntimeScopeOrigin> ();
		roots.add (new RuntimeScopeOrigin.context_input (1));
		int context_input = graph.product (roots, new HashTable<string, int> (str_hash, str_equal));
		graph.seal ();
		var regions = new RuntimeLifetimeRegions ();
		assert (regions.add_region (-1) == 0);
		assert (regions.add_region (0) == 1);
		assert (regions.add_region (1) == 2);
		assert (regions.add_region (0) == 3);
		regions.context (10, 1);
		regions.context (20, 2);
		regions.owner (5, 0);
		regions.owner (15, 1);
		regions.owner (25, 2);
		regions.owner (30, 3);
		regions.owner (9, 1);
		regions.input (0);
		regions.input (1, true);
		refused (() => regions.input (0, true));
		refused (() => regions.input (1));
		regions.seal ();
		regions.validate (graph, outer, 15);
		regions.validate (graph, outer, 25);
		regions.validate (graph, nested, 25);
		regions.validate (graph, extracted, 5);
		regions.validate (graph, owner_input, 5);
		regions.validate (graph, context_input, 5);
		refused (() => regions.validate (graph, outer, 5));
		refused (() => regions.validate (graph, outer, 30));
		refused (() => regions.validate (graph, outer, 9));
		refused (() => regions.validate (graph, nested, 15));
		refused (() => regions.validate (graph, forged, 15));
		refused (() => regions.owner (40, 1));
		var unbound = new RuntimeLifetimeRegions ();
		unbound.add_region (-1);
		unbound.owner (5, 0);
		unbound.seal ();
		refused (() => unbound.validate (graph, owner_input, 5));
		refused (() => unbound.validate (graph, context_input, 5));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void structured_flow_versions() {
	try {
		var flow = new RuntimeLifetimeFlow ();
		int first = allocation (flow.equations, 3, 1);
		int second = allocation (flow.equations, 7, 2);
		int third = allocation (flow.equations, 11, 3);
		flow.declare (0, first);
		int captured = flow.read (0);
		var scope = flow.state.snapshot ();
		flow.write (0, second);
		flow.declare (1, third);
		var left = flow.state.snapshot ();
		flow.state = scope.snapshot ();
		flow.write (0, third);
		var right = flow.state.snapshot ();
		flow.merge (scope, left, right);
		int joined = flow.read (0);
		refused (() => flow.read (1));
		flow.begin_loop ();
		int header = flow.read (0);
		var body = flow.state.snapshot ();
		flow.write (0, first);
		flow.jump (false);
		flow.state = body.snapshot ();
		flow.write (0, second);
		flow.jump (true);
		flow.end_loop ();
		int result = flow.read (0);
		flow.equations.seal ();
		var requirements = flow.equations.requirements (captured);
		assert (requirements.length == 1 && contains (requirements, 3));
		requirements = flow.equations.requirements (joined);
		assert (requirements.length == 2 && contains (requirements, 7) && contains (requirements, 11));
		requirements = flow.equations.requirements (header);
		assert (requirements.length == 3 && contains (requirements, 3) && contains (requirements, 7) && contains (requirements, 11));
		requirements = flow.equations.requirements (result);
		assert (requirements.length == 3);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void exception_state_versions() {
	try {
		RuntimeLifetimeFlow? flow = new RuntimeLifetimeFlow ();
		var reference = WeakRef (flow);
		int before = allocation (flow.equations, 5, 1);
		int after = allocation (flow.equations, 9, 2);
		flow.declare (0, before);
		flow.begin_try ();
		flow.exception (before, 17);
		flow.write (0, after);
		flow.begin_try ();
		flow.exception (after, 23);
		var nested = flow.end_try ();
		assert (nested.length == 1 && nested[0].site == 23 && nested[0].value == after);
		var handler = nested[0].state.snapshot ();
		flow.state = handler;
		flow.exception (after, 29);
		var outer = flow.end_try ();
		assert (outer.length == 2 && outer[0].site == 17 && outer[1].site == 29);
		flow.state = outer[0].state.snapshot ();
		assert (flow.read (0) == before);
		flow.state = outer[1].state.snapshot ();
		assert (flow.read (0) == after);
		flow.equations.seal ();
		flow = null;
		assert (reference.get () == null);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void frozen_summary_inventory() {
	try {
		var graph = new RuntimeLifetimeEquations ();
		int value = graph.input (0);
		var updates = new HashTable<int, int> (direct_hash, direct_equal);
		updates.insert (-1, value);
		var stores = new GenericArray<RuntimeLifetimeStore> ();
		stores.add (new RuntimeLifetimeStore (-1, value));
		var summary = new RuntimeLifetimeSummary (graph, value, updates, stores, "");
		assert (!summary.valid ());
		graph.seal ();
		assert (summary.valid ());
		updates.insert (-1, graph.absent ());
		stores.remove_index (0);
		var exposed = summary.updated_inputs ();
		exposed.remove_index (0);
		assert (summary.updated_inputs ().length == 1 && summary.update (-1) == value && summary.store_count == 1 && summary.store (0).value == value);
		assert (graph.requirements (summary.result).length == 1);
		assert (!new RuntimeLifetimeSummary (graph, 99999, updates, stores, "").valid ());
		updates.insert (-3, value);
		assert (!new RuntimeLifetimeSummary (graph, value, updates, stores, "").valid ());
		updates.remove (-3);
		stores.add (new RuntimeLifetimeStore (-2, value));
		assert (!new RuntimeLifetimeSummary (graph, value, updates, stores, "").valid ());
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void archived_summary() {
	try {
		RuntimeLifetimeEquations? graph = new RuntimeLifetimeEquations ();
		var weak = WeakRef (graph);
		int incoming = graph.input (0);
		int receiver = graph.input (-1);
		var roots = new GenericArray<RuntimeScopeOrigin> ();
		roots.add (new RuntimeScopeOrigin.context_input (2));
		var fields = new HashTable<string, int> (str_hash, str_equal);
		fields.insert ("f1", graph.absent ());
		fields.insert ("f0", incoming);
		int child = graph.product (roots, fields);
		int updated = graph.replace (receiver, "f0", child);
		int result = graph.project (updated, "f0");
		var updates = new HashTable<int, int> (direct_hash, direct_equal);
		updates.insert (-1, updated);
		var stores = new GenericArray<RuntimeLifetimeStore> ();
		stores.add (new RuntimeLifetimeStore (-1, child));
		graph.seal ();
		RuntimeLifetimeSummary? summary = new RuntimeLifetimeSummary (graph, result, updates, stores, "");
		string encoded = summary.encode ();
		var decoded = RuntimeLifetimeSummary.decode (encoded);
		summary = null;
		graph = null;
		assert (weak.get () == null);
		assert (decoded.valid () && decoded.complete && decoded.encode () == encoded && decoded.updated_inputs ().length == 1 && decoded.store_count == 1);
		assert (decoded.equations.requirements (decoded.result).length == 2);
		var caller = new RuntimeLifetimeEquations ();
		int actual = allocation (caller, 7, 1);
		int host = allocation (caller);
		var inputs = new HashTable<int, int> (direct_hash, direct_equal);
		inputs.insert (0, actual);
		inputs.insert (-1, host);
		var contexts = new HashTable<int, RuntimeScopeOrigin> (direct_hash, direct_equal);
		contexts.insert (2, new RuntimeScopeOrigin.local (11, 2));
		int rebound = decoded.equations.instantiate (decoded.result, caller, inputs, contexts);
		caller.seal ();
		var requirements = caller.requirements (rebound);
		assert (requirements.length == 2 && contains (requirements, 7) && contains (requirements, 11));
		var unavailable = RuntimeLifetimeSummary.decode ("runtime-lifetime-summary/1:incomplete");
		assert (unavailable.valid () && !unavailable.complete && unavailable.encode () == "runtime-lifetime-summary/1:incomplete");
		decoded.validate_formals (true, new bool[] { true, false, false }, new bool[] { false, false, true }, new bool[] { false, false, false });
		refused (() => decoded.validate_formals (false, new bool[] { true, false, false }, new bool[] { false, false, true }, new bool[] { false, false, false }));
		refused (() => decoded.validate_formals (true, new bool[] { false, false, false }, new bool[] { false, false, true }, new bool[] { false, false, false }));
		refused (() => decoded.validate_formals (true, new bool[] { true, false, false }, new bool[] { false, false, false }, new bool[] { false, false, false }));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void archived_mutants() {
	try {
		string valid = "runtime-lifetime-summary/1\nr|1\n--\nruntime-lifetime-equations/1\na\ni|0\n";
		assert (RuntimeLifetimeSummary.decode (valid).encode () == valid);
		foreach (var text in new string[] {
				valid.replace ("summary/1", "summary/2"), valid.replace ("equations/1", "equations/9"), valid.replace ("r|1", "r|2"), valid.replace ("i|0", "i|00"), valid.replace ("i|0", "j|1"), valid.replace ("i|0", "q|0|f01"), valid.replace ("i|0", "p|-1||"), valid.replace ("i|0", "p||f0=0,f0=1|"), valid.replace ("i|0", "p|||9"), valid.replace ("i|0", "unknown|0"), valid + "i|1\n", valid.replace ("\n--\n", "\nu|0|1\nu|0|1\n--\n"), valid.replace ("i|0", "i|0|extra"), valid.replace ("i|0", "p|0,0||")
			}) {
			refused (() => RuntimeLifetimeSummary.decode (text));
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void retired_local_summary() {
	try {
		var producer = new RuntimeLifetimeEquations ();
		int heap = allocation (producer);
		int local = allocation (producer, 5, 1);
		int host = allocation (producer, -1, -1, "f0", local);
		int replaced = producer.replace (host, "f0", heap);
		int scoped_host = allocation (producer, 9, 2, "f0", heap);
		int extracted = producer.project (scoped_host, "f0");
		producer.seal ();
		assert (producer.requirements (replaced).length == 0 && producer.requirements (extracted).length == 0);
		var caller = new RuntimeLifetimeEquations ();
		var inputs = new HashTable<int, int> (direct_hash, direct_equal);
		var contexts = new HashTable<int, RuntimeScopeOrigin> (direct_hash, direct_equal);
		int rebound = producer.instantiate (replaced, caller, inputs, contexts);
		int child = producer.instantiate (extracted, caller, inputs, contexts);
		caller.seal ();
		assert (caller.requirements (rebound).length == 0 && caller.requirements (child).length == 0);
		var summary = new RuntimeLifetimeSummary (producer, replaced, new HashTable<int, int> (direct_hash, direct_equal), new GenericArray<RuntimeLifetimeStore> (), "");
		var decoded = RuntimeLifetimeSummary.decode (summary.encode ());
		assert (decoded.equations.requirements (decoded.result).length == 0 && !decoded.equations.has_scope_roots);
		var escape = new RuntimeLifetimeSummary (producer, host, new HashTable<int, int> (direct_hash, direct_equal), new GenericArray<RuntimeLifetimeStore> (), "");
		refused (() => escape.encode ());
		var fresh_caller = new RuntimeLifetimeEquations ();
		refused (() => producer.instantiate (host, fresh_caller, inputs, contexts));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void exceptional_summary() {
	try {
		RuntimeLifetimeEquations? graph = new RuntimeLifetimeEquations ();
		var weak = WeakRef (graph);
		int success = graph.input (0);
		var roots = new GenericArray<RuntimeScopeOrigin> ();
		roots.add (new RuntimeScopeOrigin.context_input (1));
		int failure = graph.product (roots, new HashTable<string, int> (str_hash, str_equal));
		graph.seal ();
		RuntimeLifetimeSummary? summary = new RuntimeLifetimeSummary (graph, success, new HashTable<int, int> (direct_hash, direct_equal), new GenericArray<RuntimeLifetimeStore> (), "", failure);
		assert (summary.valid () && summary.complete && summary.has_exception);
		assert (summary.matches_exception (true) && !summary.matches_exception (false));
		string encoded = summary.encode ();
		assert (encoded.has_prefix ("runtime-lifetime-summary/2\n"));
		var decoded = RuntimeLifetimeSummary.decode (encoded);
		summary = null;
		graph = null;
		assert (weak.get () == null);
		assert (decoded.has_exception && decoded.encode () == encoded);
		decoded.validate_formals (false, new bool[] { true, false }, new bool[] { false, true }, new bool[] { false, false });
		var caller = new RuntimeLifetimeEquations ();
		int input = allocation (caller, 7, 1);
		var inputs = new HashTable<int, int> (direct_hash, direct_equal);
		inputs.insert (0, input);
		var contexts = new HashTable<int, RuntimeScopeOrigin> (direct_hash, direct_equal);
		contexts.insert (1, new RuntimeScopeOrigin.local (11, 2));
		int normal = decoded.equations.instantiate (decoded.result, caller, inputs, contexts);
		int error = decoded.equations.instantiate (decoded.exception, caller, inputs, contexts);
		caller.seal ();
		assert (contains (caller.requirements (normal), 7) && !contains (caller.requirements (normal), 11));
		assert (contains (caller.requirements (error), 11) && !contains (caller.requirements (error), 7));
		refused (() => decoded.validate_formals (false, new bool[] { true, false }, new bool[] { false, false }, new bool[] { false, false }));
		foreach (string mutant in new string[] { encoded.replace ("summary/2", "summary/3"), encoded.replace ("summary/2", "summary/1"), encoded.replace ("e|", "r|"), encoded.replace ("\ne|", "\ne|99999\ne|"), encoded.replace ("\n--\n", "\ne|0\n--\n") }) {
			refused (() => RuntimeLifetimeSummary.decode (mutant));
		}
		var normal_summary = new RuntimeLifetimeSummary (caller, normal, new HashTable<int, int> (direct_hash, direct_equal), new GenericArray<RuntimeLifetimeStore> (), "");
		assert (normal_summary.matches_exception (false) && !normal_summary.matches_exception (true));
		var escaped = new RuntimeLifetimeEquations ();
		int local = allocation (escaped, 5, 1);
		escaped.seal ();
		var invalid = new RuntimeLifetimeSummary (escaped, escaped.absent (), new HashTable<int, int> (direct_hash, direct_equal), new GenericArray<RuntimeLifetimeStore> (), "", local);
		refused (() => invalid.encode ());
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void coordinate_origin(RuntimeLifetimeSummary summary, string field, RuntimeScopeOriginKind kind, int ordinal, string path = "") throws GLib.Error {
	var roots = summary.equations.requirements (summary.result, field);
	assert (roots.length == 1 && roots[0].kind == kind && roots[0].ordinal == ordinal && roots[0].path == path);
}
private void native_coordinates() {
	try {
		var indices = new GenericArray<int> ();
		var paths = new GenericArray<string> ();
		var lengths = new GenericArray<bool> ();
		foreach (int index in new int[] { 0, 0, 0, 0, 1, 2 }) {
			indices.add (index);
		}
		foreach (string path in new string[] { "f0.f0", "f0.f1", "f0.f1", "f1", "", "" }) {
			paths.add (path);
		}
		foreach (bool length in new bool[] { false, false, true, false, false, false }) {
			lengths.add (length);
		}
		var layout = new RuntimeLifetimeLayout (indices, paths, lengths, 3);
		var graph = new RuntimeLifetimeEquations ();
		var fields = new HashTable<string, int> (str_hash, str_equal);
		fields.insert ("f0", graph.input (0));
		fields.insert ("f1", graph.input (1));
		fields.insert ("f2", graph.input (4));
		var roots = new GenericArray<RuntimeScopeOrigin> ();
		roots.add (new RuntimeScopeOrigin.context_input (5));
		fields.insert ("f3", graph.product (roots, new HashTable<string, int> (str_hash, str_equal)));
		int result = graph.product (new GenericArray<RuntimeScopeOrigin> (), fields);
		var updates = new HashTable<int, int> (direct_hash, direct_equal);
		updates.insert (4, graph.replace (graph.input (4), "f0", graph.input (0)));
		var stores = new GenericArray<RuntimeLifetimeStore> ();
		stores.add (new RuntimeLifetimeStore (-1, graph.input (0)));
		graph.seal ();
		var original = new RuntimeLifetimeSummary (graph, result, updates, stores, "");
		bool[] contexts = {
			false, false, false, false, false, true
		};
		var logical = layout.to_logical (original, true, new bool[] { true, true, false, false, true, false }, contexts, new bool[] { false, false, false, false, true, false });
		logical.validate_formals (true, new bool[] { true, true, false }, new bool[] { false, false, true }, new bool[] { false, true, false });
		assert (logical.logical_coordinates && logical.encode ().has_prefix ("runtime-lifetime-logical/1\n"));
		refused (() => { RuntimeLifetimeSummary.decode ("runtime-lifetime-logical/1\n" + logical.encode ());
		});
		refused (() => { RuntimeLifetimeSummary.decode ("runtime-lifetime-logical/1\nruntime-lifetime-summary/1:incomplete");
		});
		coordinate_origin (logical, "f0", RuntimeScopeOriginKind.OWNER_PARAMETER, 0, "f0.f0");
		coordinate_origin (logical, "f1", RuntimeScopeOriginKind.OWNER_PARAMETER, 0, "f0.f1");
		coordinate_origin (logical, "f2", RuntimeScopeOriginKind.OWNER_PARAMETER, 1);
		coordinate_origin (logical, "f3", RuntimeScopeOriginKind.CONTEXT_PARAMETER, 2);
		assert (logical.updated_inputs ().length == 1 && logical.store (0).parameter == -1);
		var restored = layout.to_physical (RuntimeLifetimeSummary.decode (logical.encode ()), true, new bool[] { true, true, false, false, true, false }, contexts, new bool[] { false, false, false, false, true, false });
		assert (!restored.logical_coordinates);
		restored.validate_formals (true, new bool[] { true, true, false, false, true, false }, contexts, new bool[] { false, false, false, false, true, false });
		coordinate_origin (restored, "f0", RuntimeScopeOriginKind.OWNER_PARAMETER, 0);
		coordinate_origin (restored, "f1", RuntimeScopeOriginKind.OWNER_PARAMETER, 1);
		coordinate_origin (restored, "f2", RuntimeScopeOriginKind.OWNER_PARAMETER, 4);
		coordinate_origin (restored, "f3", RuntimeScopeOriginKind.CONTEXT_PARAMETER, 5);
		assert (restored.updated_inputs ().length == 1 && restored.store (0).parameter == -1);
		roots = restored.equations.requirements (restored.update (4), "f0");
		assert (roots.length == 1 && roots[0].ordinal == 0 && roots[0].path == "");
		// The layout owns copies; a later producer edit cannot retarget it.
		indices[4] = 9;
		var copied = layout.to_logical (original, true, new bool[] { true, true, false, false, true, false }, contexts, new bool[] { false, false, false, false, true, false });
		coordinate_origin (copied, "f2", RuntimeScopeOriginKind.OWNER_PARAMETER, 1);
		refused (() => { new RuntimeLifetimeLayout (indices, paths, lengths, 3);
		});
		indices[4] = 1;
		lengths[0] = true;
		refused (() => { new RuntimeLifetimeLayout (indices, paths, lengths, 3);
		});
		lengths[0] = false;
		paths[2] = "f9";
		refused (() => { new RuntimeLifetimeLayout (indices, paths, lengths, 3);
		});
		paths[2] = "f0.f1";
		refused (() => { new RuntimeLifetimeLayout (indices, paths, lengths, 4);
		});
		refused (() => { layout.to_physical (logical, true, new bool[] { true }, contexts, new bool[] { false });
		});
		bool[] wrong = contexts.copy ();
		wrong[1] = true;
		refused (() => { layout.to_logical (original, true, new bool[] { true, true, false, false, true, false }, wrong, new bool[] { false, false, false, false, true, false });
		});
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void empty_query_identity() {
	try {
		RuntimeLifetimeEquations? graph = new RuntimeLifetimeEquations ();
		var weak = WeakRef (graph);
		int heap = allocation (graph);
		int scoped = allocation (graph, 7, 1);
		var fields = new HashTable<string, int> (str_hash, str_equal);
		fields.insert ("f0", heap);
		fields.insert ("f1", scoped);
		int record = graph.product (new GenericArray<RuntimeScopeOrigin> (), fields);
		int input = graph.input (0);
		int replaced = graph.replace (record, "f1", heap);
		int loop = graph.join ();
		graph.alternative (loop, loop);
		int broken = allocation (graph, -1, -1, "f0", loop);
		int grounded = graph.join ();
		graph.alternative (grounded, heap);
		graph.alternative (grounded, grounded);
		graph.seal ();
		var excluded = new GenericArray<string> ();
		excluded.add ("f1");
		assert (graph.requirements (record, "", true, excluded).length == 0);
		excluded[0] = "f0";
		assert (contains (graph.requirements (record, "", true, excluded), 7));
		assert (graph.requirements (record, "", false).length == 0);
		assert (contains (graph.requirements (record), 7));
		assert (graph.requirements (record, "f0").length == 0);
		assert (contains (graph.requirements (record, "f1"), 7));
		assert (graph.requirements (replaced).length == 0);
		assert (contains (graph.requirements (record), 7));
		assert (graph.requirements (input).length == 1);
		var exposed = graph.requirements (heap);
		exposed.add (new RuntimeScopeOrigin.local (99, 2));
		assert (graph.requirements (heap).length == 0);
		assert (graph.requirements (grounded).length == 0);
		assert (graph.requirements (grounded).length == 0);
		// Warm empty queries cannot admit an invalid projection or cycle, and
		// a failed larger query cannot cache its partially traversed children.
		for (int i = 0; i < 2; i++) {
			refused (() => graph.requirements (heap, "f0"));
			refused (() => graph.requirements (record, "f0.f0"));
			refused (() => graph.requirements (broken));
			refused (() => graph.requirements (loop));
			refused (() => graph.requirements (heap, "f01"));
			refused (() => graph.requirements (99999));
			refused (() => graph.requirements (record, "", false, excluded));
		}
		excluded[0] = "invalid";
		refused (() => graph.requirements (record, "", true, excluded));
		graph = null;
		assert (weak.get () == null);
		var other = new RuntimeLifetimeEquations ();
		int same_ordinal = allocation (other, 11, 3);
		other.seal ();
		assert (same_ordinal == heap && contains (other.requirements (same_ordinal), 11));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void repeated_empty_products() {
	try {
		var graph = new RuntimeLifetimeEquations ();
		var products = new GenericArray<int> ();
		int value = allocation (graph);
		products.add (value);
		for (int i = 0; i < 512; i++) {
			value = allocation (graph, -1, -1, "f0", value);
			products.add (value);
		}
		graph.seal ();
		for (int round = 0; round < 3; round++) {
			for (int i = (int) products.length - 1; i >= 0; i--) {
				assert (graph.requirements (products[i]).length == 0);
			}
		}
		var outputs = new GenericArray<int> ();
		outputs.add (value);
		GenericArray<int> rewritten;
		string encoded = graph.encode_outputs (outputs, out rewritten);
		var decoded = RuntimeLifetimeEquations.decode (encoded);
		assert (decoded.requirements (rewritten[0]).length == 0);
		GenericArray<int> decoded_outputs;
		assert (decoded.encode_outputs (rewritten, out decoded_outputs) == encoded);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
public int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/runtime-lifetimes/empty-query-exact-identity-guards", empty_query_identity);
	Test.add_func ("/runtime-lifetimes/repeated-empty-products", repeated_empty_products);
	Test.add_func ("/runtime-lifetimes/native-logical-physical-coordinates", native_coordinates);
	Test.add_func ("/runtime-lifetimes/exception-result-archive-substitution", exceptional_summary);
	Test.add_func ("/runtime-lifetimes/independent-container-element-origins", independent_origins);
	Test.add_func ("/runtime-lifetimes/nested-record-field-projection", nested_products);
	Test.add_func ("/runtime-lifetimes/opaque-input-context-substitution", opaque_substitution);
	Test.add_func ("/runtime-lifetimes/receiver-replacement-excludes-retired-field", replacement_summary);
	Test.add_func ("/runtime-lifetimes/recursive-owning-backedges-no-cycles", recursive_backedges);
	Test.add_func ("/runtime-lifetimes/carrier-inherits-original-allocation-root", original_allocation_root);
	Test.add_func ("/runtime-lifetimes/recursive-projection-converges", recursive_projection);
	Test.add_func ("/runtime-lifetimes/local-escape-ungrounded-cycle", escape_and_grounding);
	Test.add_func ("/runtime-lifetimes/malformed-sealed-contracts", malformed_and_sealed);
	Test.add_func ("/runtime-lifetimes/actual-destination-cleanup-extent", actual_storage_extent);
	Test.add_func ("/runtime-lifetimes/structured-branch-loop-write-versions", structured_flow_versions);
	Test.add_func ("/runtime-lifetimes/exception-point-state-versions", exception_state_versions);
	Test.add_func ("/runtime-lifetimes/frozen-neutral-summary-inventory", frozen_summary_inventory);
	Test.add_func ("/runtime-lifetimes/versioned-summary-roundtrip-substitution", archived_summary);
	Test.add_func ("/runtime-lifetimes/versioned-summary-negative-controls", archived_mutants);
	Test.add_func ("/runtime-lifetimes/retired-local-hidden-by-replacement-projection", retired_local_summary);
	return Test.run ();
}
}
