// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
namespace Astra.Source {
// The archive uses logical declaration parameters. Lower stages derive this
// layout from their own exact record and buffer groups, never caller names.
public class RuntimeLifetimeLayout : Object {
	private GenericArray<int> logical = new GenericArray<int> ();
	private GenericArray<string> paths = new GenericArray<string> ();
	private GenericArray<bool> lengths = new GenericArray<bool> ();
	private int count;
	public RuntimeLifetimeLayout (GenericArray<int> logical, GenericArray<string> paths, GenericArray<bool> lengths, int count) throws RuntimeLifetimeError {
		if (logical.length != paths.length || logical.length != lengths.length || count < 0) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("native lifetime layout lost its complete coordinate inventory");
		}
		int next = 0;
		for (int p = 0; p < logical.length; p++) {
			if (logical[p] == next) {
				next++;
			} else if (logical[p] != next - 1) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("native lifetime layout lost its ordered logical coordinates");
			}
			if (lengths[p] && (p == 0 || logical[p - 1] != logical[p] || paths[p - 1] != paths[p] || lengths[p - 1])) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("native lifetime length lost its complete original pair");
			}
			this.logical.add (logical[p]);
			this.paths.add (paths[p]);
			this.lengths.add (lengths[p]);
		}
		if (next != count) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("native lifetime layout lost its exact logical arity");
		}
		this.count = count;
	}

	private static int replace(RuntimeLifetimeEquations graph, int root, string path, int value) throws RuntimeLifetimeError {
		if (path == "") {
			return value;
		}
		// Build the projection spine once, then reconstruct from the leaf.
		// Recursive suffix strings made valid deep paths quadratic in memory.
		var edges = path.split (".");
		var parents = new GenericArray<int> ();
		int parent = root;
		for (int i = 0; i < edges.length; i++) {
			parents.add (parent);
			if (i + 1 < edges.length) {
				parent = graph.project (parent, edges[i]);
			}
		}
		for (int i = edges.length - 1; i >= 0; i--) {
			value = graph.replace (parents[i], edges[i], value);
		}
		return value;
	}

	public RuntimeLifetimeSummary to_logical(RuntimeLifetimeSummary summary, bool receiver, bool[] owners, bool[] contexts, bool[] mutable_owners) throws RuntimeLifetimeError {
		if (!summary.complete) {
			return summary;
		}
		if (owners.length != logical.length || contexts.length != logical.length || mutable_owners.length != logical.length) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("native lifetime layout differs from its physical signature");
		}
		summary.validate_formals (receiver, owners, contexts, mutable_owners);
		var graph = new RuntimeLifetimeEquations ();
		var inputs = new HashTable<int, int> (direct_hash, direct_equal);
		var anchors = new HashTable<int, RuntimeScopeOrigin> (direct_hash, direct_equal);
		if (receiver) {
			inputs.insert (-1, graph.input (-1));
		}
		for (int p = 0; p < logical.length; p++) {
			int input = lengths[p] || !owners[p] || contexts[p] ? graph.absent () : graph.input (logical[p]);
			if (!lengths[p] && owners[p] && !contexts[p] && paths[p] != "") {
				input = graph.project (input, paths[p]);
			}
			inputs.insert (p, input);
			if (contexts[p]) {
				if (paths[p] != "") {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("native scoped context needs an explicit context formal");
				}
				anchors.insert (p, new RuntimeScopeOrigin.context_input (logical[p]));
			}
		}
		int result = summary.equations.instantiate (summary.result, graph, inputs, anchors);
		int exception = summary.has_exception ? summary.equations.instantiate (summary.exception, graph, inputs, anchors) : -1;
		var updates = new HashTable<int, int> (direct_hash, direct_equal);
		var updated = summary.updated_inputs ();
		for (int u = 0; u < updated.length; u++) {
			int p = updated[u];
			int target = p == -1 ? -1 : logical[p];
			string path = p == -1 ? "" : paths[p];
			int old = updates.contains (target) ? updates.lookup (target) : graph.input (target);
			updates.insert (target, replace (graph, old, path, summary.equations.instantiate (summary.update (p), graph, inputs, anchors)));
		}
		var stores = new GenericArray<RuntimeLifetimeStore> ();
		for (uint s = 0; s < summary.store_count; s++) {
			var store = summary.store (s);
			if (store.parameter >= 0 && paths[store.parameter] != "") {
				graph.seal ();
				return new RuntimeLifetimeSummary (graph, graph.absent (), new HashTable<int, int> (direct_hash, direct_equal), new GenericArray<RuntimeLifetimeStore> (), "native mutable record-field stores need their exact target path");
			}
			stores.add (new RuntimeLifetimeStore (store.parameter == -1 ? -1 : logical[store.parameter], summary.equations.instantiate (store.value, graph, inputs, anchors)));
		}
		graph.seal ();
		return new RuntimeLifetimeSummary (graph, result, updates, stores, "", exception).logical_archive ();
	}

	public RuntimeLifetimeSummary to_physical(RuntimeLifetimeSummary summary, bool receiver, bool[] owners, bool[] contexts, bool[] mutable_owners) throws RuntimeLifetimeError {
		if (!summary.complete) {
			return summary;
		}
		if (owners.length != logical.length || contexts.length != logical.length || mutable_owners.length != logical.length) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("native lifetime layout differs from its complete physical roles");
		}
		var graph = new RuntimeLifetimeEquations ();
		var inputs = new HashTable<int, int> (direct_hash, direct_equal);
		var anchors = new HashTable<int, RuntimeScopeOrigin> (direct_hash, direct_equal);
		if (receiver) {
			inputs.insert (-1, graph.input (-1));
		}
		for (int p = 0; p < count; p++) {
			inputs.insert (p, graph.absent ());
		}
		for (int p = 0; p < logical.length; p++) {
			if (lengths[p]) {
				continue;
			}
			int input = owners[p] && !contexts[p] ? graph.input (p) : graph.absent ();
			inputs.insert (logical[p], replace (graph, inputs.lookup (logical[p]), paths[p], input));
			if (contexts[p]) {
				if (paths[p] != "") {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("native scoped context needs an explicit context formal");
				}
				anchors.insert (logical[p], new RuntimeScopeOrigin.context_input (p));
			}
		}
		int result = summary.equations.instantiate (summary.result, graph, inputs, anchors);
		int exception = summary.has_exception ? summary.equations.instantiate (summary.exception, graph, inputs, anchors) : -1;
		var updates = new HashTable<int, int> (direct_hash, direct_equal);
		var updated = summary.updated_inputs ();
		for (int u = 0; u < updated.length; u++) {
			int source = updated[u];
			int value = summary.equations.instantiate (summary.update (source), graph, inputs, anchors);
			if (source == -1) {
				updates.insert (-1, value);
				continue;
			}
			for (int p = 0; p < logical.length; p++) {
				if (logical[p] == source && mutable_owners[p]) {
					updates.insert (p, paths[p] == "" ? value : graph.project (value, paths[p]));
				}
			}
		}
		var stores = new GenericArray<RuntimeLifetimeStore> ();
		for (uint s = 0; s < summary.store_count; s++) {
			var store = summary.store (s);
			int value = summary.equations.instantiate (store.value, graph, inputs, anchors);
			if (store.parameter == -1) {
				stores.add (new RuntimeLifetimeStore (-1, value));
				continue;
			}
			for (int p = 0; p < logical.length; p++) {
				if (logical[p] == store.parameter && mutable_owners[p]) {
					stores.add (new RuntimeLifetimeStore (p, value));
				}
			}
		}
		graph.seal ();
		return new RuntimeLifetimeSummary (graph, result, updates, stores, "", exception);
	}

}
// Neutral summary storage contains no compiler nodes or callable backlinks.
// Each stage must derive its own equations and validate exact signature roles.
public class RuntimeLifetimeStore : Object {
	public int parameter { get; private set; }
	public int value { get; private set; }
	public RuntimeLifetimeStore (int parameter, int value) {
		this.parameter = parameter;
		this.value = value;
	}

}
public class RuntimeLifetimeSummary : Object {
	private const string LOGICAL_ARCHIVE = "runtime-lifetime-logical/1\n";
	public bool logical_coordinates { get; private set; }
	public RuntimeLifetimeSummary logical_archive() {
		if (!complete) {
			return this;
		}
		var result = new RuntimeLifetimeSummary (equations, this.result, updates, stores, unsupported, has_exception ? exception : -1);
		result.logical_coordinates = true;
		return result;
	}

	public RuntimeLifetimeEquations equations { get; private set; }
	public int result { get; private set; }
	public bool has_exception { get; private set; }
	public int exception { get; private set; }
	public bool complete { get; private set; }
	private string unsupported;
	public string limitation { get { return unsupported; } }
	private HashTable<int, int> updates = new HashTable<int, int> (direct_hash, direct_equal);
	private GenericArray<RuntimeLifetimeStore> stores = new GenericArray<RuntimeLifetimeStore> ();
	public GenericArray<int> updated_inputs() {
		var result = new GenericArray<int> ();
		foreach (int key in updates.get_keys ()) {
			result.add (key);
		}
		return result;
	}

	public int update(int parameter) {
		return updates.lookup (parameter);
	}

	public uint store_count { get { return stores.length; } }
	public RuntimeLifetimeStore store(uint index) {
		return stores[index];
	}

	public RuntimeLifetimeSummary (RuntimeLifetimeEquations equations, int result, HashTable<int, int> updates, GenericArray<RuntimeLifetimeStore> stores, string unsupported, int exception = -1) {
		this.equations = equations;
		this.result = result;
		this.unsupported = unsupported;
		this.complete = unsupported == "";
		this.has_exception = exception >= 0;
		this.exception = exception < 0 ? equations.absent () : exception;
		foreach (int key in updates.get_keys ()) {
			this.updates.insert (key, updates.lookup (key));
		}
		foreach (var store in stores) {
			this.stores.add (store);
		}
	}

	public bool matches_exception(bool throwing) {
		return !complete || has_exception == throwing;
	}

	public bool valid() {
		if (!equations.is_sealed || !equations.contains (result) || !equations.contains (exception)) {
			return false;
		}
		foreach (int key in updates.get_keys ()) {
			if (key < -1 || !equations.contains (updates.lookup (key))) {
				return false;
			}
		}
		foreach (var store in stores) {
			if (store.parameter < -1 || !equations.contains (store.value)) {
				return false;
			}
		}
		return true;
	}

	private GenericArray<string> ordered_updates() {
		var result = new GenericArray<string> ();
		foreach (int key in updates.get_keys ()) {
			result.add (key.to_string ());
		}
		RuntimeLifetimeEquations.sort_edges (result);
		return result;
	}

	public string encode() throws RuntimeLifetimeError {
		if (!valid ()) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("lifetime archive requires a valid sealed summary");
		}
		if (!complete) {
			return "runtime-lifetime-summary/1:incomplete";
		}
		var outputs = new GenericArray<int> ();
		outputs.add (result);
		if (has_exception) {
			outputs.add (exception);
		}
		var keys = ordered_updates ();
		foreach (var key in keys) {
			outputs.add (updates.lookup (int.parse (key)));
		}
		foreach (var store in stores) {
			outputs.add (store.value);
		}
		GenericArray<int> rewritten;
		string graph = equations.encode_outputs (outputs, out rewritten);
		var text = new StringBuilder (has_exception ? "runtime-lifetime-summary/2\n" : "runtime-lifetime-summary/1\n");
		text.append_printf ("r|%d\n", rewritten[0]);
		int next = 1;
		if (has_exception) {
			text.append_printf ("e|%d\n", rewritten[next++]);
		}
		foreach (var key in keys) {
			text.append_printf ("u|%s|%d\n", key, rewritten[next++]);
		}
		foreach (var store in stores) {
			text.append_printf ("s|%d|%d\n", store.parameter, rewritten[next++]);
		}
		text.append ("--\n");
		text.append (graph);
		return logical_coordinates ? LOGICAL_ARCHIVE + text.str : text.str;
	}

	public static RuntimeLifetimeSummary decode(string text) throws RuntimeLifetimeError {
		if (text.length > 8 * 1024 * 1024) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("lifetime archive exceeds its bounded inventory");
		}
		if (!text.has_prefix (LOGICAL_ARCHIVE)) {
			return decode_physical (text);
		}
		// One coordinate wrapper is permitted. Never recursively decode suffixes:
		// repeated framing used to allocate one suffix per prefix before refusal.
		string payload = text.substring (LOGICAL_ARCHIVE.length);
		if (payload.has_prefix (LOGICAL_ARCHIVE)) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("logical lifetime archive requires one complete unambiguous coordinate version");
		}
		var summary = decode_physical (payload);
		if (!summary.complete) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("logical lifetime archive requires one complete unambiguous coordinate version");
		}
		return summary.logical_archive ();
	}

	private static RuntimeLifetimeSummary decode_physical(string text) throws RuntimeLifetimeError {
		if (text == "runtime-lifetime-summary/1:incomplete") {
			var graph = new RuntimeLifetimeEquations ();
			graph.seal ();
			return new RuntimeLifetimeSummary (graph, 0, new HashTable<int, int> (direct_hash, direct_equal), new GenericArray<RuntimeLifetimeStore> (), "native lifetime contract is incomplete");
		}
		bool exceptional = text.has_prefix ("runtime-lifetime-summary/2\n");
		if (!exceptional && !text.has_prefix ("runtime-lifetime-summary/1\n")) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("unsupported lifetime summary archive");
		}
		int separator = text.index_of ("\n--\n");
		if (separator < 0) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("lifetime summary lost its equation payload");
		}
		var header = text.substring (0, separator).split ("\n");
		var graph = RuntimeLifetimeEquations.decode (text.substring (separator + 4));
		if (header.length < (exceptional ? 3 : 2)) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("lifetime summary lost its result channel");
		}
		int result = -1;
		int exception = -1;
		var updates = new HashTable<int, int> (direct_hash, direct_equal);
		var stores = new GenericArray<RuntimeLifetimeStore> ();
		for (int i = 1; i < header.length; i++) {
			var entry = header[i].split ("|");
			if (i == 1 && entry.length == 2 && entry[0] == "r") {
				result = RuntimeLifetimeEquations.archive_integer (entry[1], 0, (int) graph.count - 1);
			} else if (exceptional && i == 2 && entry.length == 2 && entry[0] == "e") {
				exception = RuntimeLifetimeEquations.archive_integer (entry[1], 0, (int) graph.count - 1);
			} else if (i > (exceptional ? 2 : 1) && entry.length == 3 && (entry[0] == "u" || entry[0] == "s")) {
				int parameter = RuntimeLifetimeEquations.archive_integer (entry[1], -1);
				int value = RuntimeLifetimeEquations.archive_integer (entry[2], 0, (int) graph.count - 1);
				if (entry[0] == "u") {
					if (updates.contains (parameter)) {
						throw new RuntimeLifetimeError.INVALID_GRAPH ("duplicate lifetime input update");
					}
					updates.insert (parameter, value);
				} else {
					stores.add (new RuntimeLifetimeStore (parameter, value));
				}
			} else {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("malformed lifetime summary channel");
			}
		}
		var summary = new RuntimeLifetimeSummary (graph, result, updates, stores, "", exception);
		if (!summary.valid () || summary.encode () != text) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("lifetime summary archive is not canonical");
		}
		return summary;
	}

	public void validate_formals(bool receiver, bool[] owners, bool[] contexts, bool[] mutable_owners) throws RuntimeLifetimeError {
		if (!valid () || owners.length != mutable_owners.length || owners.length != contexts.length) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("lifetime contract lost its exact signature inventory");
		}
		if (!complete) {
			return;
		}
		equations.validate_formals (receiver, owners, contexts);
		foreach (int key in updates.get_keys ()) {
			if (!(key == -1 ? receiver : key >= 0 && key < mutable_owners.length && mutable_owners[key])) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("lifetime update requires its declared mutable borrowed input");
			}
		}
		foreach (var store in stores) {
			int key = store.parameter;
			if (!(key == -1 ? receiver : key >= 0 && key < mutable_owners.length && mutable_owners[key])) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("lifetime store requires its declared mutable borrowed input");
			}
		}
	}

}
}
